## 安全屋阅读与确认；主状态只读 GameState，所有本页播放经过同一入口。
extends Control
signal session_entered(session: int)
signal exit_line_finished(session: int, completed: bool)
const Interaction = preload("res://scripts/interactable.gd")
const SEQUENCES: Dictionary = {&"sofa": ["T176", "T177"], &"exit": ["T193"],
	&"trust": ["T178", "T179", "T180", "T181", "T182", "T183", "T184", "T185", "T186", "T187", "T188", "T189"]}
const TRUST_IDS: Array[String] = ["T178", "T179", "T180", "T181", "T182", "T183", "T184", "T185", "T186", "T187", "T188", "T189"]
const ALLOWED_IDS: Array[String] = ["T176", "T177", "T190", "T193", "T178", "T179", "T180", "T181", "T182", "T183", "T184", "T185", "T186", "T187", "T188", "T189"]
const OBJECT_IDS: Array[String] = ["Sofa", "Speaker", "Door"]
var flow: Node
var player: Control
var exit_service: Node
var captured_run: int = -1
var busy: bool = false
var _kind: StringName = &""
var _sequence_run: int = -1
var _seen: Array[String] = []
var _expected: Array = []
var _focus_target: String = "Sofa"
var _entered_state: int = -1
var _reading_focus: bool = false
@onready var grid: Control = $Grid
@onready var visual: Control = $Illustration/DressingVisual
@onready var medical: Control = $MedicalIllustration

func configure(director: Node, service: Node) -> void:
	if flow != null:
		return
	flow = director
	player = flow.dialogue
	exit_service = service
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/safe_room_grid.json"))
	grid.configure(flow.map.get_grid_size(), data)
	grid.resized.connect(_layout_targets)
	for id: String in OBJECT_IDS:
		var slot: Control = $Objects.get_node(id)
		var item := Interaction.new()
		item.name = "Interaction"
		item.progression = id in ["Sofa", "Speaker"]
		slot.add_child(item)
		item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.object_confirmed.connect(request_object)
	grid.cell_selected.connect(_cell_selected)
	medical.closed.connect(_on_medical_closed)
	player.line_started.connect(_on_line)
	player.sequence_finished.connect(_on_sequence_finished)
	exit_service.status_changed.connect(_refresh_status)
	exit_service.exit_saved.connect(_on_exit_saved)
	visibility_changed.connect(_restore_focus)
	_layout_targets()

func enter_session() -> void:
	var fresh: bool = captured_run != GameState.run_id
	if fresh:
		captured_run = GameState.run_id
		busy = false
		_kind = &""
		_seen.clear()
		_reading_focus = false
		for id: String in OBJECT_IDS:
			interaction(id).set_read(false)
		grid.select_cell(grid.initial_cell)
		_entered_state = -1
	if _entered_state != GameState.state:
		if GameState.state == GameState.State.S6:
			exit_service.reset_session(captured_run)
			grid.select_object("Door")
			session_entered.emit(captured_run)
		_entered_state = GameState.state
		_reading_focus = false
		$Status/ProgressNotice.text = ""
	if fresh:
		visual.show()
		medical.dismiss()
		$Objects.show()
		grid.show()
	_refresh_status()
	_restore_focus.call_deferred()

func interaction(id: String) -> Control:
	return $Objects.get_node(id).get_node("Interaction")

func _owns_session() -> bool:
	return is_instance_valid(flow) and GameState.presenter == flow._present and captured_run == GameState.run_id

func _can_request() -> bool:
	return _owns_session() and GameState.state in [GameState.State.S0, GameState.State.S1, GameState.State.S6] and grid.valid and is_visible_in_tree() and not busy and not player.is_playing() and not exit_service.pending and not exit_service.committed

func request_object(id: String) -> bool:
	if id not in OBJECT_IDS or not _owns_session() or not grid.valid or not is_visible_in_tree():
		return false
	if id == "Door" and GameState.state == GameState.State.S0 and not GameState.event_done(&"E4"):
		$Status/ProgressNotice.text = Interaction.text_for("safe_room_speaker_pending")
		return false
	if not _can_request():
		return false
	_focus_target = id
	var item: Control = interaction(id)
	match id:
		"Speaker":
			if GameState.state != GameState.State.S0:
				return false
			var accepted: bool = flow.request_opening(captured_run)
			if accepted:
				_reading_focus = true
				grid.release_focus()
			return accepted
		"Sofa":
			if GameState.state != GameState.State.S6:
				return false
			if not GameState.event_done(&"E13"):
				return request_room_sequence(&"trust", TRUST_IDS)
			if not item.read:
				return request_room_sequence(&"sofa", ["T176", "T177"])
			if GameState.event_done(&"E12"):
				return false
			if not flow.finish_safehouse(&"E12", captured_run):
				return false
			return item.activate()
		"Door":
			if GameState.state == GameState.State.S1:
				return flow.request_departure(captured_run)
			if GameState.state == GameState.State.S6:
				return exit_service.request_exit(captured_run)
	return false

## 整段及物件专属序列均须精确匹配；拒绝时不接触播放器。
func request_room_sequence(kind: StringName, ids: Array) -> bool:
	if not SEQUENCES.has(kind) or ids != SEQUENCES[kind]:
		return false
	for id: Variant in ids:
		if id not in ALLOWED_IDS or not player.get_lines().has(id):
			return false
	if kind == &"exit":
		if not _can_read_exit():
			return false
	elif GameState.state != GameState.State.S6 or not _can_request():
		return false
	_kind = kind
	_sequence_run = captured_run
	_expected = ids.duplicate()
	_seen.clear()
	busy = true
	player.skip_allowed = false
	if not player.play_seq(ids):
		_clear_reading()
		return false
	if kind == &"sofa":
		player.hide()
		medical.open()
	elif kind == &"trust" and not GameState.event_started(&"E13"):
		GameState.record_event(&"E13", false, captured_run)
	$Status/ProgressNotice.text = ""
	return true

func _on_line(id: String) -> void:
	if busy:
		_seen.append(id)

func _on_sequence_finished(skipped: bool) -> void:
	if not busy:
		return
	var complete: bool = not skipped and _owns_session() and _sequence_run == captured_run
	complete = complete and not player.is_playing() and _seen == _expected and player._keys == _expected
	var exit_read: bool = _kind == &"exit"
	var session: int = _sequence_run
	if complete and _kind == &"trust":
		complete = GameState.state == GameState.State.S6
		if complete:
			if not GameState.event_done(&"E13"):
				flow.finish_safehouse(&"E13", captured_run)
			flow.main.show_page(&"ScenePage")
	elif complete and not exit_read:
		interaction("Sofa").complete_reading()
	_clear_reading()
	if exit_read:
		exit_line_finished.emit(session, complete)

func _clear_reading() -> void:
	_reading_focus = false
	medical.dismiss()
	busy = false
	_kind = &""
	_expected.clear()
	_seen.clear()
	_restore_focus.call_deferred()

## flow先路由网格，避免同一鼠标点击既选格又推进正文。
func blocks_object_input(event: InputEvent) -> bool:
	if medical.is_visible_in_tree():
		if event is InputEventMouse and flow.main._page_switch_bar.get_global_rect().has_point(event.position):
			return false
		if medical.route_input(event):
			return true
	if is_visible_in_tree() and event is InputEventMouseButton and (busy or exit_service.pending):
		for id: String in OBJECT_IDS:
			if $Objects.get_node(id).get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				return true
	if not is_visible_in_tree() or not grid.is_visible_in_tree():
		return false
	if event is InputEventMouseButton:
		if not grid.get_global_rect().has_point(event.position):
			if event.pressed:
				_reading_focus = true
				grid.release_focus()
			return false
		if busy or exit_service.pending or exit_service.committed:
			get_viewport().set_input_as_handled()
			return true
		var local_event: InputEventMouseButton = event.duplicate()
		local_event.position = grid.get_global_transform_with_canvas().affine_inverse() * event.position
		var consumed: bool = grid.handle_input(local_event)
		if consumed:
			get_viewport().set_input_as_handled()
		return consumed
	if event is InputEventKey:
		if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
			return false
		if busy or exit_service.pending or exit_service.committed:
			return false
		if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] or not _reading_focus:
			var consumed: bool = grid.handle_input(event)
			if consumed:
				get_viewport().set_input_as_handled()
			return consumed
	return false

func _cell_selected(cell: Vector2i) -> void:
	_reading_focus = false
	var id: String = grid.object_at(cell)
	if not id.is_empty():
		_focus_target = id
	for target: String in OBJECT_IDS:
		interaction(target).active = target == id

func _on_medical_closed() -> void:
	if busy and _kind == &"sofa" and player.is_playing():
		player.show()

func _restore_focus() -> void:
	if not is_visible_in_tree():
		medical.dismiss()
	if _can_request() and not _reading_focus:
		grid.grab_focus()

func _on_exit_saved(_session: int, _receipt: Dictionary) -> void:
	interaction("Door").complete_reading()
	_refresh_status()

func _refresh_status() -> void:
	if not grid.valid:
		$Status/ProgressNotice.text = grid.last_error
	$Status/SaveStatus.text = "自动保存失败，正在重试。" if exit_service.pending and exit_service.last_error != OK else ""
	$Status/SaveStatus.visible = not $Status/SaveStatus.text.is_empty()
	grid.input_enabled = not exit_service.committed and not exit_service.pending and not busy

func _layout_targets() -> void:
	if not is_node_ready() or not grid.valid:
		return
	for id: String in OBJECT_IDS:
		var slot: Control = $Objects.get_node(id)
		slot.position = grid.position + grid.center(grid.objects[id].cell) - Vector2(14, 14)
		slot.size = Vector2(28, 28)

func _can_read_exit() -> bool:
	return _owns_session() and not busy and not player.is_playing() and exit_service.is_waiting_before_save(captured_run) and flow.epilogue.can_read(captured_run)




## 安全屋阅读与确认；主状态只读 GameState，所有本页播放经过同一入口。
extends Control
const Interaction = preload("res://scripts/interactable.gd")
const SEQUENCES: Dictionary = {&"sofa": ["T176", "T177"], &"detail": ["T190"]}
const ALLOWED_IDS: Array[String] = ["T176", "T177", "T190"]
const TARGET_RECTS: Dictionary = {
	"Sofa": Rect2(0.12, 0.66, 0.15, 0.18), "Scar": Rect2(0.38, 0.33, 0.10, 0.17),
	"Door": Rect2(0.84, 0.20, 0.10, 0.55)}
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
@onready var visual: Control = $Illustration/DressingVisual

func configure(director: Node, service: Node) -> void:
	if flow != null:
		return
	flow = director
	player = flow.dialogue
	exit_service = service
	visual.resized.connect(_layout_targets)
	resized.connect(_layout_targets)
	for id: String in TARGET_RECTS:
		var button: Button = $Objects.get_node(id)
		var item := Interaction.new()
		item.name = "Interaction"
		item.progression = id == "Sofa"
		button.add_child(item)
		item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.pressed.connect(request_object.bind(id))
		button.focus_entered.connect(_focus_changed.bind(id, true))
		button.focus_exited.connect(_focus_changed.bind(id, false))
		if id == "Scar":
			item.repeated.connect(func(): request_room_sequence(&"detail", ["T190"]))
	player.line_started.connect(_on_line)
	player.sequence_finished.connect(_on_sequence_finished)
	exit_service.status_changed.connect(_refresh_status)
	exit_service.exit_saved.connect(_on_exit_saved)
	visibility_changed.connect(_restore_focus)
	_layout_targets()

func enter_session() -> void:
	if captured_run == GameState.run_id:
		return
	captured_run = GameState.run_id
	exit_service.reset_session(captured_run)
	busy = false
	_kind = &""
	_seen.clear()
	for id: String in TARGET_RECTS:
		interaction(id).set_read(false)
	$Status/ProgressNotice.text = ""
	visual.reset_dressing()
	_refresh_status()
	_restore_focus.call_deferred()

func interaction(id: String) -> Control:
	return $Objects.get_node(id).get_node("Interaction")

func _owns_session() -> bool:
	return is_instance_valid(flow) and GameState.presenter == flow._present and captured_run == GameState.run_id

func _can_request() -> bool:
	return _owns_session() and GameState.state == GameState.State.S6 and is_visible_in_tree() and not busy and not player.is_playing() and not exit_service.pending and not exit_service.committed

func request_object(id: String) -> bool:
	if not TARGET_RECTS.has(id) or not _can_request():
		return false
	_focus_target = id
	var item: Control = interaction(id)
	match id:
		"Sofa":
			if not item.read:
				return request_room_sequence(&"sofa", ["T176", "T177"])
			if GameState.event_done(&"E12"):
				return false
			if not flow.finish_safehouse(&"E12", captured_run):
				return false
			return item.activate()
		"Scar":
			if item.read:
				item.activate()
				return busy
			return request_room_sequence(&"detail", ["T190"])
		"Door":
			if not GameState.event_done(&"E12"):
				$Status/ProgressNotice.text = Interaction.text_for("progress_pending")
				return false
			return exit_service.request_exit(captured_run)
	return false

## 整段及物件专属序列均须精确匹配；拒绝时不接触播放器。
func request_room_sequence(kind: StringName, ids: Array) -> bool:
	if not SEQUENCES.has(kind) or ids != SEQUENCES[kind]:
		return false
	for id: Variant in ids:
		if id not in ALLOWED_IDS or not player.get_lines().has(id):
			return false
	if not _can_request():
		return false
	_kind = kind
	_sequence_run = captured_run
	_expected = ids.duplicate()
	_seen.clear()
	busy = true
	player.skip_allowed = false
	if kind == &"sofa":
		visual.show_dressing()
	if not player.play_seq(ids):
		_clear_reading()
		return false
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
	if complete:
		interaction("Sofa" if _kind == &"sofa" else "Scar").complete_reading()
	_clear_reading()

func _clear_reading() -> void:
	busy = false
	_kind = &""
	_expected.clear()
	_seen.clear()
	_restore_focus.call_deferred()

## 阅读中的热区点击不替换序列，也不充当正文继续。
func blocks_object_input(event: InputEvent) -> bool:
	if not busy or not is_visible_in_tree() or not event is InputEventMouseButton:
		return false
	for id: String in TARGET_RECTS:
		if $Objects.get_node(id).get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			return true
	return false

func _focus_changed(id: String, active: bool) -> void:
	interaction(id).active = active
	if active:
		_focus_target = id

func _restore_focus() -> void:
	if _can_request():
		$Objects.get_node(_focus_target).grab_focus()

func _on_exit_saved(_session: int, _receipt: Dictionary) -> void:
	interaction("Door").complete_reading()
	_refresh_status()

func _refresh_status() -> void:
	$Status/SaveStatus.text = "自动保存失败，正在重试。" if exit_service.pending and exit_service.last_error != OK else ""
	$Status/SaveStatus.visible = not $Status/SaveStatus.text.is_empty()
	for id: String in TARGET_RECTS:
		$Objects.get_node(id).disabled = exit_service.committed or exit_service.pending

func _layout_targets() -> void:
	if not is_instance_valid(visual) or not is_node_ready():
		return
	var canvas := Rect2(visual.global_position - global_position, visual.size)
	for id: String in TARGET_RECTS:
		var fraction: Rect2 = TARGET_RECTS[id]
		var button: Button = $Objects.get_node(id)
		button.position = canvas.position + fraction.position * canvas.size
		button.size = fraction.size * canvas.size

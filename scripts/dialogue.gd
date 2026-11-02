## 台词数据验证与逐句播放；S0 接线独立放在下方小型流程对象中。
extends Control

signal line_started(key: String)
signal sequence_finished(skipped: bool)
signal stage_started(stage: StringName, session: int)
signal stage_finished(stage: StringName, session: int)

const LINES_PATH: String = "res://data/lines.json"
const MODES: Array[String] = ["read", "auto", "caption"]
const AUTO_SECONDS: float = 3.0
const CAPTION_SECONDS: float = 3.0
const FADE_SECONDS: float = 0.25
var caption_hold_seconds: float = CAPTION_SECONDS
@export var characters_per_second: float = 30.0
@onready var _panel: PanelContainer = %Panel
@onready var _speaker: Label = %Speaker
@onready var _body: RichTextLabel = %Body
var _lines: Dictionary = {}
var _keys: Array[String] = []
var _index: int = 0
var _active: bool = false
var _typing: bool = false
var _typed: float = 0.0
var _elapsed: float = 0.0
var _s0: RefCounted
var skip_allowed: bool = true
var last_error: String = ""
var _caption_only: bool = false
var data_valid: bool = false
var source_data: Variant = null
var last_resume_accepted: bool = false

func _ready() -> void:
	load_lines()
	_set_active(false)

func load_lines() -> bool:
	if source_data != null:
		return load_lines_data(source_data)
	var file: FileAccess = FileAccess.open(LINES_PATH, FileAccess.READ)
	if file == null:
		return _reject_data("无法读取台词文件：%s" % LINES_PATH)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _reject_data("台词 JSON 解析失败：%s" % json.get_error_message())
	return load_lines_data(json.data)

func load_lines_data(data: Variant) -> bool:
	var reason: String = validate_lines(data)
	if reason.is_empty():
		reason = validate_required_ids(data)
	if not reason.is_empty():
		return _reject_data(reason)
	var next_lines: Dictionary = {}
	for entry: Dictionary in data:
		next_lines[str(entry["id"])] = entry.duplicate(true)
	_lines = next_lines
	data_valid = true
	last_error = ""
	last_resume_accepted = _s0.retry_pending_stage() if _s0 != null else false
	return true

static func validate_required_ids(data: Array) -> String:
	var ids: Dictionary = {}
	for entry: Dictionary in data:
		ids[str(entry["id"])] = true
	var missing: Array[String] = []
	for number: int in range(101, 196):
		var id: String = "T%d" % number
		if not ids.has(id):
			missing.append(id)
	return "" if missing.is_empty() else "序章缺少必需台词：" + ", ".join(missing)

static func validate_lines(data: Variant) -> String:
	if not data is Array or (data as Array).is_empty():
		return "台词根必须是非空数组"
	var seen: Dictionary = {}
	for value: Variant in data:
		if not value is Dictionary:
			return "台词条目必须是对象"
		var entry: Dictionary = value
		for field: String in ["id", "speaker", "text", "mode"]:
			if not entry.get(field) is String or str(entry[field]).is_empty():
				return "台词缺少非空字符串字段：%s" % field
		var key: String = entry["id"]
		if seen.has(key):
			return "台词 id 重复：%s" % key
		if not MODES.has(entry["mode"]):
			return "台词 mode 无效：%s" % key
		seen[key] = true
	return ""

func _reject_data(reason: String) -> bool:
	data_valid = false
	_set_active(false)
	_lines.clear()
	return _reject(reason)

func _reject(reason: String) -> bool:
	last_error = reason
	push_error("[Dialogue] %s" % reason)
	return false

func get_lines() -> Dictionary:
	return _lines.duplicate(true)

func play(key: String) -> bool:
	return play_seq([key])

## 先校验整段再替换当前播放，缺 key 不会吞掉已有内容。
func validate_sequence(keys: Array) -> String:
	if not data_valid:
		return "台词数据未成功加载"
	if keys.is_empty():
		return "台词序列不能为空"
	for key: Variant in keys:
		if not key is String or not _lines.has(key):
			return "台词 key 不存在：%s" % str(key)
		if _caption_only and _lines[key]["mode"] != "caption":
			return "字幕实例拒绝非caption台词"
	return ""

func play_seq(keys: Array) -> bool:
	var reason: String = validate_sequence(keys)
	if not reason.is_empty():
		return _reject(reason)
	_keys.assign(keys)
	_index = 0
	last_error = ""
	_set_active(true)
	_show_current()
	return true

func skip() -> bool:
	if not _active or not skip_allowed:
		return false
	_finish(true)
	return true

func get_current_key() -> String:
	return _keys[_index] if _active else ""

func get_current_mode() -> String:
	return str(_lines[get_current_key()]["mode"]) if _active else ""

func is_playing() -> bool:
	return _active

func is_typing() -> bool:
	return _typing

func get_visible_text() -> String:
	return _body.get_parsed_text()

func get_caption_alpha() -> float:
	return _panel.modulate.a

func _show_current() -> void:
	var entry: Dictionary = _lines[_keys[_index]]
	_speaker.text = entry["speaker"]
	_body.text = entry["text"]
	_body.scroll_to_line(0)
	_typed = 0.0
	_elapsed = 0.0
	_panel.modulate.a = 1.0
	_typing = characters_per_second > 0.0 and entry["mode"] != "caption"
	_body.visible_characters = 0 if _typing else -1
	line_started.emit(_keys[_index])

func finish_text() -> void:
	_typing = false
	_body.visible_characters = -1

func advance() -> void:
	if not _active:
		return
	if _typing:
		finish_text()
	elif get_current_mode() == "read":
		_next_line()

func _next_line() -> void:
	if _index + 1 >= _keys.size():
		_finish(false)
		return
	_index += 1
	_show_current()

func _finish(skipped: bool) -> void:
	_set_active(false)
	sequence_finished.emit(skipped)

func _set_active(value: bool) -> void:
	_active = value
	visible = value
	set_process(value)
	set_process_input(value)
	if not value:
		_typing = false

func _process(delta: float) -> void:
	advance_time(delta)

## 与运行时共用的时钟入口；自检注入 delta，无协程或定时器。
func advance_time(delta: float) -> void:
	if not _active or delta <= 0.0:
		return
	if _typing:
		_typed += characters_per_second * delta
		_body.visible_characters = mini(int(_typed), _body.get_total_character_count())
		if _body.visible_characters >= _body.get_total_character_count():
			finish_text()
		return
	_elapsed += delta
	match get_current_mode():
		"auto":
			if _elapsed >= AUTO_SECONDS:
				_next_line()
		"caption":
			_panel.modulate.a = 1.0 - clampf((_elapsed - caption_hold_seconds) / FADE_SECONDS, 0.0, 1.0)
			if _elapsed >= caption_hold_seconds + FADE_SECONDS:
				_next_line()
		"read":
			pass

func _input(event: InputEvent) -> void:
	if not _active or get_current_mode() == "caption":
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			if event.is_action_pressed(&"ui_cancel"):
				if skip_allowed:
					skip()
				else:
					finish_text()
			elif event.is_action_pressed(&"ui_accept"):
				advance()
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			advance()
	get_viewport().set_input_as_handled()


## 专用字幕实例只改自己的覆盖样式，不影响剧情/调查播放器。
func configure_caption_view(rect: Rect2, hold_seconds: float = CAPTION_SECONDS) -> void:
	if not is_finite(hold_seconds) or hold_seconds <= 0.0:
		_reject("caption hold must be positive")
		return
	caption_hold_seconds = hold_seconds
	_caption_only = true
	skip_allowed = false
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_speaker.hide()
	var margin: MarginContainer = _panel.get_node("Margin")
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 0)
	_body.custom_minimum_size = Vector2.ZERO
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_OFF
	for node: Control in find_children("*", "Control", true, false):
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	set_caption_rect(rect)

func set_caption_rect(rect: Rect2) -> void:
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.position = rect.position
	_panel.size = rect.size

func bind_s0(room: Control, switch_page: Callable) -> void:
	if _s0 != null:
		_s0.dispose()
	var page: Control = room.flow.main.get_node("Pages/ScenePage")
	var nav: Control = page.get_node("PageNav")
	for row: Array in [[nav.reading_requested, Callable(page, "_begin_reading")], [nav.confirmed, Callable(page, "_on_confirmed")]]:
		if row[0].is_connected(row[1]):
			row[0].disconnect(row[1])
	_s0 = S0Sequence.new(self, room, switch_page)

func start_s0_from_speaker(session: int) -> bool:
	return _s0 != null and _s0.start_from_speaker(session)

func get_story_phase() -> StringName:
	return _s0.phase if _s0 != null else &""

func _exit_tree() -> void:
	if _s0 != null:
		_s0.dispose()

## 三段过场只保留阶段与编号，不解释脚本表达式，也不保存台词正文。
class S0Sequence extends RefCounted:
	const SEQUENCES: Dictionary = {
		&"READING": ["T112", "T113", "T114"],
		&"R2": ["T116"], &"R3": ["T117", "T118"], &"R4": ["T121"]}
	var phase: StringName = &""
	var last_completed_stage: StringName = &""
	var pending_stage: StringName = &""
	var _player: Control
	var _page: Control
	var _item: Control
	var _switch_page: Callable
	var _resume_vital: bool = false
	var _resume_focus: bool = false
	var _disposed: bool = false
	var _running: bool = false
	var _run_id: int = GameState.run_id
	var _seen: Array[String] = []

	func _init(player: Control, room: Control, switch_page: Callable) -> void:
		_player = player
		_page = room
		_item = room.interaction("Speaker")
		_switch_page = switch_page
		_player.sequence_finished.connect(_on_finished)
		_player.line_started.connect(_on_line)

	func binding_valid(session: int) -> bool:
		return not _disposed and session == _run_id and session == GameState.run_id and is_instance_valid(_page) and _page.is_inside_tree() and is_instance_valid(_item) and _page.has_node("Objects/Speaker/Interaction") and _page.captured_run == session and _page._owns_session() and _page.player == _player and _item == _page.interaction("Speaker")

	func start_from_speaker(session: int) -> bool:
		if not binding_valid(session) or GameState.state != GameState.State.S0 or not GameState.event_done(&"E1") or GameState.event_done(&"E4") or _player.is_playing() or _running or phase != &"" or pending_stage != &"":
			return false
		_resume_vital = GameState.is_processing()
		_resume_focus = _page._reading_focus
		_running = true
		GameState.set_process(false)
		return _start(&"READING")

	func _on_line(id: String) -> void:
		if _running:
			_seen.append(id)

	func _start(next: StringName) -> bool:
		_seen.clear()
		var previous_skip: bool = _player.skip_allowed
		var reason: String = _player.validate_sequence(SEQUENCES[next])
		_player.skip_allowed = next == &"R2"
		if not reason.is_empty() or not _player.play_seq(SEQUENCES[next]):
			pending_stage = next
			_player.skip_allowed = previous_skip
			if not reason.is_empty():
				_player.last_error = reason
			_restore()
			return false
		phase = next
		pending_stage = &""
		_player.stage_started.emit(phase, _run_id)
		return true

	func retry_pending_stage() -> bool:
		if not binding_valid(_run_id) or GameState.state != GameState.State.S0 or pending_stage == &"" or _player.is_playing():
			return false
		_resume_vital = GameState.is_processing()
		_resume_focus = _page._reading_focus
		_running = true
		GameState.set_process(false)
		return _start(pending_stage)

	func _on_finished(skipped: bool) -> void:
		if _run_id != GameState.run_id or not _running or phase == &"" or phase == last_completed_stage:
			return
		if skipped and phase != &"R2":
			_restore()
			pending_stage = phase
			return
		if not skipped and (_player.is_playing() or _seen != SEQUENCES[phase] or _player._keys != SEQUENCES[phase]):
			return
		last_completed_stage = phase
		_player.stage_finished.emit(phase, _run_id)
		match phase:
			&"READING":
				_item.complete_reading()
				_item.activate()
				_start(&"R2")
			&"R2":
				_start(&"R3")
			&"R3":
				_start(&"R4")
			&"R4":
				phase = &"DONE"
				_restore()
				_switch_page.call(&"r4_finished", _run_id)

	func _restore() -> void:
		if not _running:
			return
		_running = false
		if _run_id == GameState.run_id:
			GameState.set_process(_resume_vital)
			if is_instance_valid(_page):
				_page._reading_focus = _resume_focus

	func dispose() -> void:
		_disposed = true
		_restore()
		if is_instance_valid(_player):
			if _player.sequence_finished.is_connected(_on_finished):
				_player.sequence_finished.disconnect(_on_finished)
			if _player.line_started.is_connected(_on_line):
				_player.line_started.disconnect(_on_line)



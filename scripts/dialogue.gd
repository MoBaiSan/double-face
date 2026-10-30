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

func _ready() -> void:
	load_lines()
	_set_active(false)

func load_lines() -> bool:
	var file: FileAccess = FileAccess.open(LINES_PATH, FileAccess.READ)
	if file == null:
		return _reject("无法读取台词文件：%s" % LINES_PATH)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _reject("台词 JSON 解析失败：%s" % json.get_error_message())
	var reason: String = validate_lines(json.data)
	if not reason.is_empty():
		return _reject(reason)
	_lines.clear()
	for entry: Dictionary in json.data:
		_lines[str(entry["id"])] = entry.duplicate(true)
	return true

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

func _reject(reason: String) -> bool:
	last_error = reason
	push_error("[Dialogue] %s" % reason)
	return false

func get_lines() -> Dictionary:
	return _lines.duplicate(true)

func play(key: String) -> bool:
	return play_seq([key])

## 先校验整段再替换当前播放，缺 key 不会吞掉已有内容。
func play_seq(keys: Array) -> bool:
	if keys.is_empty():
		return _reject("台词序列不能为空")
	for key: Variant in keys:
		if not key is String or not _lines.has(key):
			return _reject("台词 key 不存在：%s" % str(key))
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
			_panel.modulate.a = 1.0 - clampf((_elapsed - CAPTION_SECONDS) / FADE_SECONDS, 0.0, 1.0)
			if _elapsed >= CAPTION_SECONDS + FADE_SECONDS:
				_next_line()
		"read":
			pass

func _input(event: InputEvent) -> void:
	if not _active or get_current_mode() == "caption":
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			if event.is_action_pressed(&"ui_cancel") and skip_allowed:
				skip()
			elif event.is_action_pressed(&"ui_accept"):
				advance()
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			advance()
	get_viewport().set_input_as_handled()

func bind_s0(page: Control, switch_page: Callable) -> void:
	if _s0 == null:
		_s0 = S0Sequence.new(self, page, switch_page)

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
	var _player: Control
	var _page: Control
	var _nav: Control
	var _item: Control
	var _switch_page: Callable
	var _placeholder: Callable
	var _resume_vital: bool = false
	var _resume_nav: bool = false
	var _running: bool = false
	var _run_id: int = GameState.run_id

	func _init(player: Control, page: Control, switch_page: Callable) -> void:
		_player = player
		_page = page
		_nav = page.get_node("PageNav")
		_switch_page = switch_page
		_placeholder = Callable(page, "_begin_reading")
		if _nav.reading_requested.is_connected(_placeholder):
			_nav.reading_requested.disconnect(_placeholder)
		if not _nav.reading_requested.is_connected(_on_read_requested):
			_nav.reading_requested.connect(_on_read_requested)
		if not _player.sequence_finished.is_connected(_on_finished):
			_player.sequence_finished.connect(_on_finished)

	func _on_read_requested(node: Control) -> void:
		if GameState.state != GameState.State.S0 or _player.is_playing():
			return
		if str(node.get_meta("interaction_id", "")) != "s0_old_speaker":
			_placeholder.call(node)
			return
		if phase != &"":
			return
		_item = _nav.get_interactable(node)
		_resume_vital = GameState.is_processing()
		_resume_nav = _nav.is_processing_input()
		_running = true
		GameState.set_process(false)
		_nav.set_process_input(false)
		_start(&"READING")

	func _start(next: StringName) -> void:
		phase = next
		_player.stage_started.emit(phase, _run_id)
		_player.skip_allowed = phase == &"R2"
		_player.play_seq(SEQUENCES[phase])

	func _on_finished(_skipped: bool) -> void:
		if _run_id != GameState.run_id:
			return
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
		GameState.set_process(_resume_vital)
		if is_instance_valid(_nav):
			_nav.set_process_input(_resume_nav)

	func dispose() -> void:
		_restore()
		if is_instance_valid(_nav):
			if _nav.reading_requested.is_connected(_on_read_requested):
				_nav.reading_requested.disconnect(_on_read_requested)
			if is_instance_valid(_page) and not _nav.reading_requested.is_connected(_placeholder):
				_nav.reading_requested.connect(_placeholder)
		if is_instance_valid(_player) and _player.sequence_finished.is_connected(_on_finished):
			_player.sequence_finished.disconnect(_on_finished)

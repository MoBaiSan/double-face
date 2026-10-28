## 显式参数运行；用真实输入与固定 delta 检查旧音响到里侧的完整播放链。
extends RefCounted

const EXPECTED_T116: String = "出发了，琥珀君。"
const T118_PARTS: Array[String] = [
	"白濑葵", "四十余小时前出现失声症状", "疑为狂想症初期", "坐标D-7区，废弃旧排练厅",
]
const PLAYER_SCRIPT = preload("res://scripts/dialogue.gd")
var _main: Control
var _player: Control
var _failures: int = 0
var _input_count: int = 0
var _started: Array[String] = []

func run(main: Control, player: Control) -> int:
	_main = main
	_player = player
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	GameState.set_process(false)
	GameState.set_frozen(false)
	GameState.vital_now = GameState.vital_max
	_player.line_started.connect(_on_line_started)
	_check_data()
	_check_typewriter()
	_check_s0()
	_check_caption()
	_player.line_started.disconnect(_on_line_started)
	print("[SP-11] failures=%d" % _failures)
	return _failures

func _check_data() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))
	var continuous: bool = raw is Array and raw.size() == 94
	var ids: Dictionary = {}
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				ids[str(entry.get("id", ""))] = true
	for number: int in range(101, 195):
		continuous = continuous and ids.has("T%d" % number)
	_check(continuous and ids.size() == 94, "lines_count expected=94 contiguous=T101-T194 actual=%d" % ids.size())
	var lines: Dictionary = _player.get_lines()
	var t116: String = str(lines.get("T116", {}).get("text", ""))
	_check(t116 == EXPECTED_T116, "t116_exact expected_chars=8 actual_chars=%d" % t116.length())
	var t118: String = str(lines.get("T118", {}).get("text", ""))
	var contains_all: bool = true
	for part: String in T118_PARTS:
		contains_all = contains_all and t118.contains(part)
	_check(contains_all, "t118_full expected_fragments=4 actual_chars=%d" % t118.length())
	_check_schema(lines)
	_check(_source_matches(lines), "lines_source_exact expected=94 matching_fields=id,speaker,text,mode")

func _check_schema(lines: Dictionary) -> void:
	_check(not PLAYER_SCRIPT.validate_lines({}).is_empty(), "schema_root_array expected=reject_object")
	var first: Dictionary = lines.get("T101", {}).duplicate(true)
	_check(not PLAYER_SCRIPT.validate_lines([first, first]).is_empty(), "schema_duplicate_id expected=reject")
	var invalid: Dictionary = first.duplicate(true)
	invalid["mode"] = "invalid"
	_check(not PLAYER_SCRIPT.validate_lines([invalid]).is_empty(), "schema_mode expected=reject_unknown")
	invalid = first.duplicate(true)
	invalid.erase("text")
	_check(not PLAYER_SCRIPT.validate_lines([invalid]).is_empty(), "schema_required_text expected=reject_missing")

func _source_matches(lines: Dictionary) -> bool:
	var path: String = "res://design/gdd/序章_剧情与台词（重写版v2）.md"
	var pattern := RegEx.new()
	if pattern.compile("^\\| (T\\d{3}) \\| ([^|]+) \\| (read|auto|caption) \\| (.*) \\|$") != OK:
		return false
	var matched: int = 0
	for row: String in FileAccess.get_file_as_string(path).split("\n"):
		var found: RegExMatch = pattern.search(row.trim_suffix("\r"))
		if found == null:
			continue
		var entry: Dictionary = lines.get(found.get_string(1), {})
		if entry.get("speaker", "") != found.get_string(2) or entry.get("mode", "") != found.get_string(3):
			return false
		if entry.get("text", "") != found.get_string(4):
			return false
		matched += 1
	return matched == 94 and lines.size() == 94

func _check_typewriter() -> void:
	_player.characters_per_second = 30.0
	var accepted: bool = _player.play_seq(["T101", "T102"])
	var body: RichTextLabel = _player.get_node("Panel/Margin/TextLayout/Body")
	var began_partial: bool = _player.is_typing() and body.visible_characters == 0
	_key(KEY_ENTER)
	var whole: String = str(_player.get_lines().get("T101", {}).get("text", ""))
	var first_completed: bool = not _player.is_typing() and body.visible_characters == -1
	first_completed = first_completed and body.get_parsed_text() == whole and _player.get_current_key() == "T101"
	_key(KEY_ENTER)
	_check(accepted and began_partial and first_completed and _player.get_current_key() == "T102",
		"typewriter_skip expected=complete_then_next actual=%s" % _player.get_current_key())
	_player.skip()

func _check_s0() -> void:
	_main.show_page(&"ScenePage")
	_started.clear()
	var option: Control = _main.get_node("Pages/ScenePage/TestOptions/OptionTwo")
	_click(option.get_global_rect().get_center())
	_check(_player.get_story_phase() == &"READING" and _player.get_current_key() == "T112",
		"old_speaker_starts_reading expected=T112 actual=%s" % _player.get_current_key())
	for index: int in range(3):
		_player.advance_time(100.0)
		_key(KEY_ENTER)
	_check(_player.get_story_phase() == &"R2" and _player.get_current_key() == "T116",
		"old_speaker_auto_r2 expected=T116 actual=%s" % _player.get_current_key())
	var r2_active: bool = _player.get_current_key() == "T116"
	var skipped: bool = _player.skip()
	_check(r2_active and skipped and _player.get_story_phase() == &"R3" and _player.get_current_key() == "T117",
		"r2_skip_to_r3 expected=T117 actual=%s" % _player.get_current_key())
	_check_r3()
	_check_r4()
	_main.show_page(&"ScenePage")
	_click(option.get_global_rect().get_center())
	_check(not _player.is_playing() and _player.get_story_phase() == &"DONE",
		"old_speaker_no_replay expected=stopped actual_playing=%s" % _player.is_playing())

func _check_r3() -> void:
	_player.advance_time(100.0)
	_player.advance_time(100.0)
	_check(_player.get_current_key() == "T117", "r3_waits_without_input expected=T117 actual=%s" % _player.get_current_key())
	var before: int = _input_count
	_key(KEY_ENTER)
	_check(_input_count == before + 1 and _player.get_current_key() == "T118",
		"r3_needs_one_press expected=T118 actual=%s" % _player.get_current_key())
	_player.advance_time(100.0)
	_key(KEY_ESCAPE)
	_check(_player.get_current_key() == "T118", "r3_no_skip expected=T118 actual=%s" % _player.get_current_key())
	_key(KEY_ENTER)

func _check_r4() -> void:
	var entered: bool = _player.get_story_phase() == &"R4" and _player.get_current_key() == "T121"
	var before: int = _input_count
	for tick: int in range(120):
		_player.advance_time(0.1)
	var passed: bool = entered and _input_count == before and _started.has("T121")
	passed = passed and _player.get_story_phase() == &"DONE" and _main._current_page == &"MapPage"
	passed = passed and not _player.is_playing() and not _has_instruction(_main)
	_check(passed, "r4_zero_input expected=MapPage T121_played=true input_delta=0 actual=%s input_delta=%d" %
		[_main._current_page, _input_count - before])

func _check_caption() -> void:
	var caption_key: String = ""
	for entry: Dictionary in _player.get_lines().values():
		if entry.get("mode") == "caption":
			caption_key = str(entry["id"])
			break
	_main.show_page(&"ScenePage")
	GameState.set_process(true)
	var started: bool = _player.play(caption_key)
	var before: float = GameState.vital_now
	GameState.drain_time(1.0)
	_check(started and not _main.get_tree().paused and GameState.is_processing() and GameState.vital_now < before,
		"caption_keeps_time_running expected=unpaused draining=true")
	_key(KEY_PAGEDOWN)
	_check(_main._current_page == &"MapPage" and _player.is_playing(),
		"caption_passes_input expected=MapPage actual=%s" % _main._current_page)
	_player.advance_time(2.99)
	_check(_player.is_playing() and is_equal_approx(_player.get_caption_alpha(), 1.0),
		"caption_holds_three_seconds expected=visible alpha=1")
	_player.advance_time(0.02)
	var fading: bool = _player.is_playing() and _player.get_caption_alpha() < 1.0 and _player.get_caption_alpha() > 0.0
	_player.advance_time(0.3)
	_check(fading and not _player.is_playing(), "caption_fades_then_finishes expected=fade_then_stopped")
	GameState.set_process(false)

func _has_instruction(node: Node) -> bool:
	if node is Control and node.is_visible_in_tree():
		if node is Label and node.text.contains("按"):
			return true
		if node is RichTextLabel and node.get_parsed_text().contains("按"):
			return true
	for child: Node in node.get_children():
		if _has_instruction(child):
			return true
	return false

func _key(code: Key) -> void:
	_input_count += 1
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		_main.get_viewport().push_input(event)

func _click(position: Vector2) -> void:
	_input_count += 1
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		_main.get_viewport().push_input(event, true)

func _on_line_started(key: String) -> void:
	_started.append(key)

func _check(passed: bool, label: String) -> void:
	print("[SP-11] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1

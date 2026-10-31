## 显式参数运行；用真实输入与固定 delta 检查旧音响到里侧的完整播放链。
extends RefCounted

const EXPECTED_T116: String = "出发了，琥珀君。"
const T118_PARTS: Array[String] = [
	"白濑葵", "四十余小时前出现失声症状", "疑为狂想症初期", "坐标D-7区，废弃旧排练厅",
]
const PLAYER_SCRIPT = preload("res://scripts/dialogue.gd")
const CR_CONTEXT = preload("res://scripts/prologue_test_context.gd")
var _main: Control
var _player: Control
var _failures: int = 0
var _input_count: int = 0
var _started: Array[String] = []
var _cr_check: Callable
var _cr_index: int = 78

func run(main: Control, player: Control) -> int:
	_main = main
	_player = player
	var scope = preload("res://scripts/prologue_test_context.gd").new()
	scope.remember(main)
	scope.enter_domain(main, GameState.State.S0)
	GameState.record_event(&"E1", true)
	main._flow.content.present(GameState.state)
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
	scope.restore()
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
	_player.skip_allowed = true
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
	var sequence: Array[String] = _player._keys.duplicate()
	var started_before: int = _started.size()
	_click(option.get_global_rect().get_center())
	_main.get_node("Pages/ScenePage/PageNav").reading_requested.emit(option)
	var expected: Array[String] = ["T122", "T123", "T124", "T125", "T126", "T127", "T128", "T129"]
	var no_replay: bool = _started.slice(started_before).all(func(key): return key not in ["T112", "T116"])
	_check(_player._keys == sequence and sequence == expected and _player.get_story_phase() == &"DONE"
		and GameState.state == GameState.State.S1 and _player.get_current_key() in expected and no_replay,
		"old_speaker_no_replay expected=S0_DONE S1_sequence_unchanged")

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
	passed = passed and _player.get_story_phase() == &"DONE" and GameState.state == GameState.State.S1
	passed = passed and _main.get_node("Pages/ScenePage/FlowContent/Departure").is_visible_in_tree() and not _has_instruction(_main)
	_check(passed, "r4_zero_input expected=S1 Departure T121_played=true input_delta=0 actual=%s input_delta=%d" %
		[_main._current_page, _input_count - before])

func _check_caption() -> void:
	preload("res://scripts/prologue_test_context.gd").enter_domain(_main)
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


## CR-FIX：独立域夹具覆盖五条修复；不改共享夹具或生产自检分支。
func run_cr_cases(host: Control, check: Callable) -> void:
	_main = host
	_cr_check = check
	await _check_cr_cases()

func _check_cr_cases() -> void:
	for spec: Array in [[_check_opening_cancel, GameState.State.S0], [_check_entry_intro, GameState.State.S1],
			[_check_checkpoint_retry, GameState.State.S4], [_check_victory_focus, GameState.State.S2]]:
		var c = CR_CONTEXT.new()
		await c.create(_main, spec[1])
		var path: String = "user://cr_fix_%d.json" % c.main.get_instance_id()
		c.flow.checkpoint.path = path
		await spec[0].call(c)
		await c.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check_opening_cancel(c: RefCounted) -> void:
	var player: Control = c.main._dialogue
	c.key(KEY_ESCAPE)
	c.key(KEY_ESCAPE, false)
	_check(player.is_playing() and player.get_current_key() == "T101" and not player.is_typing()
		and not GameState.event_done(&"E1") and GameState.state == GameState.State.S0, "cancel_does_not_skip_opening")
	c.finish_sequence(player)
	c.click(c.main.get_node("Pages/ScenePage/TestOptions/OptionTwo"))
	c.finish_sequence(player)
	c.key(KEY_ESCAPE)
	c.key(KEY_ESCAPE, false)
	_check(GameState.event_done(&"E1") and GameState.event_done(&"E2")
		and player.get_story_phase() == &"R3" and player.get_current_key() == "T117", "opening_cancel_still_allows_r2_skip")

func _check_entry_intro(c: RefCounted) -> void:
	var player: Control = c.main._dialogue
	c.flow._play_event(&"E5", range(122, 130))
	var eight: bool = player._keys == ["T122", "T123", "T124", "T125", "T126", "T127", "T128", "T129"]
	c.finish_sequence(player)
	c.key(KEY_DOWN)
	_check(eight and GameState.event_done(&"E5") and player._keys == ["T130", "T131"]
		and player.get_current_key() == "T130" and GameState.state == GameState.State.S1
		and c.map.get_step_count() == 0 and GameState.vital_now == 100.0, "t130_plays_before_first_step")
	c.key(KEY_ESCAPE)
	c.key(KEY_ENTER)
	c.key(KEY_DOWN)
	var second: bool = player.get_current_key() == "T131" and c.map.get_step_count() == 0
	c.finish_sequence(player)
	var hidden: bool = true
	for page: StringName in [&"ScenePage", &"BattlePage"]:
		c.flow.request_page(page)
		c.key(KEY_DOWN)
		hidden = hidden and c.main._current_page == page and GameState.state == GameState.State.S1
		hidden = hidden and c.map.get_current_node_id() == &"entry_exit" and c.map.get_step_count() == 0 and GameState.vital_now == 100.0
	_check(hidden, "hidden_map_step_ignored")
	c.flow.request_page(&"MapPage")
	c.key(KEY_DOWN)
	_check(second and not player.is_playing() and GameState.state == GameState.State.S2
		and c.map.get_current_node_id() == &"c1" and c.map.get_step_count() == 1 and GameState.vital_now == 99.0, "t131_read_then_first_step")

func _check_checkpoint_retry(c: RefCounted) -> void:
	var writer = c.flow.checkpoint
	writer.write_once(GameState.run_id - 1, &"task_complete", {"safehouse_reached": false})
	var old: String = FileAccess.get_file_as_string(writer.path)
	writer.replace_file = func(_a: String, _b: String): return ERR_BUSY
	c.flow._play_event(&"E9", range(161, 171))
	c.finish_sequence(c.main._dialogue)
	c.flow._process(0.5)
	_check(GameState.state == GameState.State.S4 and c.flow._pending_checkpoint_run == GameState.run_id
		and writer.last_error == ERR_BUSY and writer.attempts == 2 and writer.writes == 1
		and FileAccess.get_file_as_string(writer.path) == old, "checkpoint_failure_keeps_pending")
	writer.replace_file = Callable()
	c.flow._process(0.5)
	c.flow._process(2.0)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(writer.path))
	_check(GameState.state == GameState.State.S6 and c.flow._pending_checkpoint_run == -1
		and writer.attempts == 3 and writer.writes == 2 and saved is Dictionary
		and saved.get("progress", {}).get("safehouse_reached") == true, "checkpoint_retry_saves_once_then_s6")

func _check_victory_focus(c: RefCounted) -> void:
	c.walk(CR_CONTEXT.ROUTE)
	c.read_point()
	c.win()
	c.battle.set_process(true)
	c.battle._return.grab_focus()
	var kept: bool = true
	for frame: int in range(3):
		await c.main.get_tree().process_frame
		kept = kept and c.main.get_viewport().gui_get_focus_owner() == c.battle._return
	_check(kept and c.battle._return.is_visible_in_tree() and not c.battle._return.disabled
		and c.battle._buttons.all(func(button: Button): return button.disabled), "victory_return_focus_kept")
	c.key(KEY_ENTER)
	c.key(KEY_ENTER, false)
	await c.main.get_tree().process_frame
	var returned_by_key: bool = c.battle._returned and c.main._current_page == &"MapPage" and c.event_count(&"E17") == 1
	c.battle._on_return_pressed()
	_check(returned_by_key and c.battle._returned and c.main._current_page == &"MapPage" and GameState.state == GameState.State.S2
		and not GameState.is_frozen() and c.map.get_current_node_id() == &"point5"
		and c.event_count(&"E17") == 1, "victory_keyboard_return_once")

## 原 SP-14 61–67 的真实输入驱动；保留全部断言，补读独立入图段。
static func run_story_input_test(c: RefCounted, check: Callable) -> void:
	var bar: Control = c.main.get_node("Overlay/PageSwitchBar")
	var page: Control = c.main.get_node("Pages/ScenePage")
	bar._finish_user_text(c.main._dialogue)
	var speaker: Control = page.get_node("TestOptions/OptionTwo")
	print("[U-03b] speaker text=%s visible=%s rect=%s" % [speaker.get_node("Text").text, speaker.is_visible_in_tree(), speaker.get_global_rect()])
	check.call(61, speaker.is_visible_in_tree() and speaker.get_node("Text").text == "旧音响", "旧音响入口有真实名称")
	bar._click_at(speaker.get_global_rect().get_center())
	check.call(62, c.main._dialogue.get_current_key() == "T112", "旧音响中心点击触发旁白T112")
	for index: int in range(4):
		bar._finish_user_text(c.main._dialogue)
	check.call(63, c.main._dialogue.get_story_phase() == &"DONE" and GameState.state == GameState.State.S1 and c.main._dialogue.get_current_key() == "T122", "真实阅读串完R2_R3_R4进入S1")
	bar._finish_user_text(c.main._dialogue)
	bar._finish_user_text(c.main._dialogue)
	bar._log_map_input(c, "departure_finished")
	bar._click_map_point(c.map, &"c1")
	var entered: bool = GameState.state == GameState.State.S2 and c.map.get_current_node_id() == &"c1"
	check.call(64, entered and c.map.get_step_count() == 1 and GameState.vital_now == 99.0, "出发文字结束后真实鼠标首步到c1")
	if not entered:
		bar._push_key(KEY_DOWN)
	bar._log_map_input(c, "first_step")
	bar._test_map_continuation(c, check)

func _check(passed: bool, label: String) -> void:
	if _cr_check.is_valid():
		_cr_index += 1
		_cr_check.call(_cr_index, passed, label)
		return
	print("[SP-11] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1

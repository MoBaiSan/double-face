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
	main._flow.content.present(GameState.state)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	GameState.set_process(false)
	GameState.set_frozen(false)
	GameState.vital_now = GameState.vital_max
	_player.line_started.connect(_on_line_started)
	_check_data()
	_check_typewriter()
	await _check_s0()
	_check_caption()
	_player.line_started.disconnect(_on_line_started)
	await _fix_dialogue_cases()
	print("[SP-11] failures=%d" % _failures)
	scope.restore()
	return _failures

func _check_data() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))
	var continuous: bool = raw is Array and raw.size() == 95
	var ids: Dictionary = {}
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				ids[str(entry.get("id", ""))] = true
	for number: int in range(101, 196):
		continuous = continuous and ids.has("T%d" % number)
	_check(continuous and ids.size() == 95, "lines_count expected=95 contiguous=T101-T195 actual=%d" % ids.size())
	var lines: Dictionary = _player.get_lines()
	var t116: String = str(lines.get("T116", {}).get("text", ""))
	_check(t116 == EXPECTED_T116, "t116_exact expected_chars=8 actual_chars=%d" % t116.length())
	var t118: String = str(lines.get("T118", {}).get("text", ""))
	var contains_all: bool = true
	for part: String in T118_PARTS:
		contains_all = contains_all and t118.contains(part)
	_check(contains_all, "t118_full expected_fragments=4 actual_chars=%d" % t118.length())
	_check_schema(lines)
	_check(_source_matches(lines), "lines_source_exact expected=95 matching_fields=id,speaker,text,mode")

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
	return matched == 94 and lines.size() == 95 and lines["T195"] == {"id": "T195", "speaker": "旁白", "mode": "read", "text": "——霍尔姆是位于涅斯公国西部边境地区的一座城镇。"}

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
	var c = CR_CONTEXT.new()
	c.attach(_main)
	var option: Control = _main.get_node("Pages/ScenePage/TestOptions/OptionTwo")
	c.room_action("Speaker")
	c.read_sequence_input()
	await _main.get_tree().process_frame
	await _main.get_tree().process_frame
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
	c.room_action("Speaker")
	_main.get_node("Pages/ScenePage/PageNav").reading_requested.emit(option)
	var expected: Array[String] = ["T121"]
	var no_replay: bool = _started.slice(started_before).all(func(key): return key not in ["T112", "T116"])
	_check(_player._keys == sequence and sequence == expected and _player.get_story_phase() == &"DONE"
		and GameState.state == GameState.State.S1 and not _player.is_playing() and no_replay,
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
	passed = passed and _main.get_node("Pages/ScenePage/FlowContent/Safehouse").is_visible_in_tree() and not _has_instruction(_main)
	_check(passed, "r4_zero_input expected=S1 Safehouse T121_played=true input_delta=0 actual=%s input_delta=%d" %
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
	c.room_action("Speaker")
	c.key(KEY_ESCAPE)
	c.key(KEY_ESCAPE, false)
	_check(player.is_playing() and player.get_current_key() == "T101" and not player.is_typing()
		and not GameState.event_done(&"E1") and GameState.state == GameState.State.S0, "cancel_does_not_skip_opening")
	c.finish_sequence(player)
	await c.main.get_tree().process_frame
	await c.main.get_tree().process_frame
	c.finish_sequence(player)
	c.key(KEY_ESCAPE)
	c.key(KEY_ESCAPE, false)
	_check(GameState.event_done(&"E1") and GameState.event_done(&"E2")
		and player.get_story_phase() == &"R3" and player.get_current_key() == "T117", "opening_cancel_still_allows_r2_skip")

func _check_entry_intro(c: RefCounted) -> void:
	CR_CONTEXT.enter_domain(c.main, GameState.State.S0)
	await c.opening_to_s1()
	var player: Control = c.main._dialogue
	c.room_action("Door")
	c.read_sequence_input()
	var eight: bool = player._keys == ["T122", "T123", "T124", "T125", "T126", "T127", "T128", "T129"]
	c.read_sequence_input()
	c.key(KEY_DOWN)
	_check(eight and GameState.event_done(&"E5") and player._keys == ["T130", "T131"]
		and player.get_current_key() == "T130" and GameState.state == GameState.State.S1
		and c.map.get_step_count() == 0 and GameState.vital_now == 100.0, "t130_plays_before_first_step")
	c.key(KEY_ESCAPE)
	c.key(KEY_ENTER)
	var second: bool = player.get_current_key() == "T131" and c.map.get_step_count() == 0
	var hidden: bool = true
	for page: StringName in [&"ScenePage", &"BattlePage"]:
		c.flow.request_page(page)
		c.key(KEY_DOWN)
		hidden = hidden and c.main._current_page == page and GameState.state == GameState.State.S1
		hidden = hidden and c.map.get_current_node_id() == &"entry_exit" and c.map.get_step_count() == 0 and GameState.vital_now == 100.0
	_check(hidden, "hidden_map_step_ignored")
	c.flow.request_page(&"MapPage")
	c.read_sequence_input()
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
	var room: Control = c.flow.safe_room
	check.call(61, room.grid.is_visible_in_tree() and room.grid.objects.Speaker.display_name == "旧音响", "旧音响入口有真实名称")
	c.room_action("Speaker")
	c.read_sequence_input()
	await c.main.get_tree().process_frame
	await c.main.get_tree().process_frame
	check.call(62, c.main._dialogue.get_current_key() == "T112" and not room.interaction("Speaker").read, "真实E1完成后桥接T112")
	for index: int in range(4):
		c.read_sequence_input()
	check.call(63, c.main._dialogue.get_story_phase() == &"DONE" and GameState.state == GameState.State.S1 and not GameState.event_started(&"E5"), "真实阅读串完R2_R3_R4进入S1")
	var entered: bool = c.departure_to_s2()
	check.call(64, entered and c.map.get_step_count() == 1 and GameState.vital_now == 99.0, "出发文字结束自动首步到c1")
	bar._test_map_continuation(c, check)

func _check(passed: bool, label: String) -> void:
	if _cr_check.is_valid():
		_cr_index += 1
		_cr_check.call(_cr_index, passed, label)
		return
	print("[SP-11] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1


## FIX-02：均用完整原表的内存副本，不改数据文件。
class RejectingPlayer extends "res://scripts/dialogue.gd":
	var reject_requests: bool = true
	var play_calls: int = 0
	func play_seq(keys: Array) -> bool:
		play_calls += 1
		if reject_requests:
			last_error = "selftest actual play rejected"
			return false
		return super.play_seq(keys)

func _original_lines() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json")) as Array

func _without_line(data: Array, id: String) -> Array:
	return data.filter(func(entry: Dictionary): return entry.id != id)

func _fix_dialogue_cases() -> void:
	var raw: Array = _original_lines()
	var required_ok: bool = PLAYER_SCRIPT.validate_required_ids(raw).is_empty()
	var checked: int = 0
	for id: String in ["T101", "T157", "T193", "T195"]:
		var missing: Array = _without_line(raw, id)
		var reason: String = PLAYER_SCRIPT.validate_required_ids(missing)
		var extra: Dictionary = raw[0].duplicate(true)
		extra.id = "T999"
		missing.append(extra)
		required_ok = required_ok and reason.contains(id) and PLAYER_SCRIPT.validate_lines(missing).is_empty()
		required_ok = required_ok and missing.size() == raw.size() and PLAYER_SCRIPT.validate_required_ids(missing).contains(id)
		checked += 1
	_check(required_ok and checked == 4, "prologue_required_line_ids")
	_check(await _missing_assembly(raw), "missing_lines_block_assembly")
	var event_results: Array[bool] = []
	for actual_reject: bool in [false, true]:
		event_results.append(await _event_retry_case(actual_reject))
	_check(event_results.size() == 2 and not event_results.has(false), "failed_event_play_is_retryable")
	_check(await _map_line_binding(raw), "map_bind_requires_t157")
	var stage_results: Array[bool] = []
	for stage: StringName in [&"READING", &"R2", &"R3"]:
		stage_results.append(await _s0_pending_case(stage, "", raw))
	for guard: String in ["stale_run", "busy_player"]:
		stage_results.append(await _s0_pending_case(&"R2", guard, raw))
	_check(stage_results.size() == 5 and not stage_results.has(false), "s0_stage_failure_releases_locks")

func _missing_assembly(raw: Array) -> bool:
	var scope = CR_CONTEXT.new()
	scope.remember(_main)
	_main.hide()
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	GameState.begin_session(GameState.State.S0)
	GameState.set_process(false)
	var checked: int = 0
	var passed: bool = true
	for id: String in ["T101", "T157", "T193", "T195"]:
		var before: Dictionary = GameState.capture_session()
		var connections: Array = GameState.get_signal_connection_list(&"event_changed")
		var missing: Array = _without_line(raw, id)
		var candidate: Control = load("res://scenes/Main.tscn").instantiate()
		candidate.dialogue_factory = func():
			var player: Control = load("res://scenes/ui/DialogueBox.tscn").instantiate()
			player.source_data = missing
			return player
		_main.get_tree().root.add_child(candidate)
		var grid: Control = candidate.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
		var battle: Control = candidate.get_node("Pages/BattlePage")
		var battle_state: int = battle.turn_phase
		battle.submit_command(0)
		var rejected: bool = candidate.startup_blocked and not candidate._flow.assembly_ready
		rejected = rejected and candidate._flow.last_error.contains(id) and candidate._dialogue == null
		rejected = rejected and not candidate._flow.configure(candidate)
		rejected = rejected and not GameState.event_started(&"E1") and not GameState.event_done(&"E1")
		rejected = rejected and not candidate.show_page(&"MapPage") and not grid.try_move_to(&"c1")
		rejected = rejected and battle.turn_phase == battle_state and candidate.get_node("Pages").process_mode == Node.PROCESS_MODE_DISABLED
		candidate.free()
		rejected = rejected and GameState.capture_session() == before
		rejected = rejected and GameState.get_signal_connection_list(&"event_changed") == connections
		passed = passed and rejected
		checked += 1
	var restored: bool = scope.restore()
	var healthy = CR_CONTEXT.new()
	await healthy.create(_main)
	var accepted: bool = healthy.flow.assembly_ready and not healthy.main.startup_blocked and not GameState.event_started(&"E1") and healthy.flow.safe_room.grid.valid
	var healthy_restored: bool = await healthy.close()
	return passed and checked == 4 and restored and accepted and healthy_restored

func _event_retry_case(actual_reject: bool) -> bool:
	var c = CR_CONTEXT.new()
	await c.create(_main)
	var player: Control = c.main._dialogue
	if actual_reject:
		player._set_active(false)
		player = load("res://scenes/ui/DialogueBox.tscn").instantiate()
		player.set_script(RejectingPlayer)
		c.main.get_node("Overlay").add_child(player)
		c.main._dialogue = player
		c.flow.dialogue = player
		player.sequence_finished.connect(c.flow._on_sequence_finished)
		player.line_started.connect(c.flow._on_story_line)
		c.flow.safe_room.player = player
	# 不经过 run 开头的 E1 完成初始化；新会话必须独立证明未开始。
	CR_CONTEXT.enter_domain(c.main, GameState.State.S0)
	c.flow._sequence_run = -1
	var run_before: int = GameState.run_id
	var skip_before: bool = player.skip_allowed
	var sequence_before: int = c.flow._sequence_run
	var checkpoint_before: Array = [c.flow.checkpoint.writes, c.flow.checkpoint.attempts]
	var finished: Array = []
	c.watch(player.sequence_finished, func(skipped: bool): finished.append(skipped))
	var precondition: bool = not GameState.event_started(&"E1") and not GameState.event_done(&"E1")
	precondition = precondition and not player.is_playing() and c.flow._sequence_event == &""
	var saved_line: Dictionary = player._lines["T101"].duplicate(true)
	if not actual_reject:
		player._lines.erase("T101")
	var preflight: String = player.validate_sequence(["T101", "T102", "T103", "T104", "T105", "T106"])
	var rejected: bool = not c.flow._play_event(&"E1", range(101, 107))
	var rolled_back: bool = not GameState.event_started(&"E1") and not GameState.event_done(&"E1")
	rolled_back = rolled_back and GameState.run_id == run_before and finished.is_empty() and c.event_count(&"E1") == 0
	rolled_back = rolled_back and c.flow._sequence_event == &"" and c.flow._sequence_run == sequence_before
	rolled_back = rolled_back and player.skip_allowed == skip_before and not player.is_playing()
	if actual_reject:
		rejected = rejected and preflight.is_empty() and player.play_calls == 1
		player.reject_requests = false
	else:
		rejected = rejected and preflight.contains("T101") and player.last_error.contains("T101")
		player._lines["T101"] = saved_line
	var start_before: int = c.event_count(&"E1", false)
	var accepted: bool = c.flow._play_event(&"E1", range(101, 107))
	accepted = accepted and GameState.event_started(&"E1") and not GameState.event_done(&"E1")
	var duplicate: bool = c.flow._play_event(&"E1", range(101, 107))
	accepted = accepted and not duplicate and c.event_count(&"E1", false) == start_before + 1 and finished.is_empty()
	c.finish_sequence(player)
	var completed: bool = GameState.event_done(&"E1") and c.event_count(&"E1") == 1 and finished == [false]
	completed = completed and GameState.run_id == run_before and [c.flow.checkpoint.writes, c.flow.checkpoint.attempts] == checkpoint_before
	var restored: bool = await c.close()
	var passed: bool = precondition and rejected and rolled_back and accepted and completed and restored
	if not passed:
		print("[SP-11] retry case actual=%s pre=%s rejected=%s rollback=%s accepted=%s completed=%s restored=%s" %
			[actual_reject, precondition, rejected, rolled_back, accepted, completed, restored])
	return passed

func _map_line_binding(raw: Array) -> bool:
	var c = CR_CONTEXT.new()
	await c.create(_main)
	var player: Control = c.points.get_dialogue()
	var before: Dictionary = GameState.capture_session()
	var signals_before: Array = c.map._interactions.investigated.get_connections()
	var progress_before: Array = GameState.get_signal_connection_list(&"progress_changed")
	var arrival: String = c.map._arrival_text
	player._lines.erase("T157")
	var rejected: bool = not c.map.bind_progress(c.points)
	rejected = rejected and GameState.capture_session() == before and c.map._arrival_text == arrival
	rejected = rejected and c.map._interactions.investigated.get_connections() == signals_before
	rejected = rejected and GameState.get_signal_connection_list(&"progress_changed") == progress_before
	var loaded: bool = player.load_lines_data(raw)
	var accepted: bool = c.map.bind_progress(c.points)
	accepted = accepted and c.map._arrival_text == str(player.get_lines()["T157"]["text"]) and c.map._arrival_text == arrival
	var restored: bool = await c.close()
	return rejected and loaded and accepted and restored

func _s0_pending_case(stage: StringName, guard: String, raw: Array) -> bool:
	var c = CR_CONTEXT.new()
	await c.create(_main)
	var player: Control = c.main._dialogue
	var room: Control = c.flow.safe_room
	var item: Control = room.interaction("Speaker")
	var ids_seen: Array = []
	c.watch(player.line_started, func(id: String): ids_seen.append(id))
	var starts: Array = []
	var finishes: Array = []
	var reads: Array = []
	var activations: Array = []
	c.watch(player.stage_started, func(id: StringName, _run: int): starts.append(id))
	c.watch(player.stage_finished, func(id: StringName, _run: int): finishes.append(id))
	c.watch(item.state_changed, func(): reads.append(item.read))
	c.watch(item.activated, func(): activations.append(true))
	GameState.set_process(true)
	var precondition: bool = not GameState.event_started(&"E1") and not item.read and not item._progress_confirmed
	var missing_id: String = {&"READING": "T112", &"R2": "T116", &"R3": "T117"}[stage]
	c.room_action("Speaker")
	# E1已经获准播放，才令下一段缺键；仍真实读完E1。
	if stage == &"READING":
		player._lines.erase(missing_id)
	c.read_sequence_input()
	await c.main.get_tree().process_frame
	await c.main.get_tree().process_frame
	if stage != &"READING":
		precondition = precondition and player.get_current_key() == "T112" and player._s0.phase == &"READING" and not item.read and not GameState.event_started(&"E2")
	if stage == &"R2":
		player._lines.erase(missing_id)
		c.read_sequence_input()
	elif stage == &"R3":
		c.read_sequence_input()
		player._lines.erase(missing_id)
		c.read_sequence_input()
	var previous: StringName = {&"READING": &"", &"R2": &"READING", &"R3": &"R2"}[stage]
	var expected_prefix: Array = [] if stage == &"READING" else ([&"READING"] if stage == &"R2" else [&"READING", &"R2"])
	var failed: bool = player._s0.pending_stage == stage and player._s0.phase == previous and player._s0.last_completed_stage == previous
	failed = failed and not player._s0._running and not player.is_playing() and GameState.is_processing() and room.grid.input_enabled
	failed = failed and starts == expected_prefix and finishes == expected_prefix
	failed = failed and item.read == (stage != &"READING") and item._progress_confirmed == (stage != &"READING")
	failed = failed and reads.size() == (0 if stage == &"READING" else 1) and activations.size() == reads.size()
	var resumed: bool = false
	if guard != "":
		var old_run: int = player._s0._run_id
		var active_key: String = ""
		if guard == "stale_run":
			GameState.begin_session(GameState.State.S0)
			precondition = precondition and old_run != GameState.run_id
		else:
			precondition = precondition and player.play_seq(["T101"])
			active_key = player.get_current_key()
		var loaded: bool = player.load_lines_data(raw)
		resumed = loaded and not player.last_resume_accepted and player._s0.pending_stage == stage
		resumed = resumed and starts == expected_prefix and finishes == expected_prefix and not player._s0._running
		resumed = resumed and (not player.is_playing() if guard == "stale_run" else player.is_playing() and player.get_current_key() == active_key)
	else:
		# 只走生产加载提交后的自动续播，不调用 _start，不清 phase、不重发阅读。
		var loaded: bool = player.load_lines_data(raw)
		resumed = loaded and player.last_resume_accepted and player._s0.pending_stage == &"" and player._s0.phase == stage
		resumed = resumed and starts.size() == expected_prefix.size() + 1 and starts.back() == stage
		for attempt: int in range(6):
			if GameState.state != GameState.State.S0 or not player.is_playing():
				break
			c.finish_sequence(player)
		resumed = resumed and starts == [&"READING", &"R2", &"R3", &"R4"] and finishes == starts
		resumed = resumed and reads == [true] and activations == [true] and item.read and item._progress_confirmed
		resumed = resumed and GameState.state == GameState.State.S1 and player._s0.last_completed_stage == &"R4"
		for id: StringName in [&"E2", &"E3", &"E4"]:
			resumed = resumed and GameState.event_done(id) and c.event_count(id) == 1 and c.event_count(id, false) == 1
	if guard == "":
		resumed = resumed and ids_seen == ["T101","T102","T103","T104","T105","T106","T112","T113","T114","T116","T117","T118","T121"]
		resumed = resumed and c.event_count(&"E1") == 1 and c.event_count(&"E1", false) == 1
	var restored: bool = await c.close()
	var passed: bool = precondition and failed and resumed and restored
	if not passed:
		print("[SP-11] stage case %s/%s pre=%s failed_state=%s resumed=%s restored=%s starts=%s finishes=%s" %
			[stage, guard, precondition, failed, resumed, restored, starts, finishes])
	return passed



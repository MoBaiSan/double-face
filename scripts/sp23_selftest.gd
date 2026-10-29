## SP-23 完整生产接线自检；固定期望与逐例清理，不替代独立复审及人工试玩。
extends RefCounted
const B = preload("res://scripts/battle.gd")
const ROUTE: Array[StringName] = [&"c1", &"point1", &"point2", &"point3", &"point4", &"point5"]
const OLD: Dictionary = {"vital_max": 100.0, "time_drain_per_second": 0.08, "step_cost": 1.0,
	"required_point_cost": 6.0, "optional_point_cost": 4.0, "battle_win_recovery": 10.0,
	"threshold_full": 61.0, "threshold_low": 31.0, "threshold_critical": 1.0, "drain_flush_threshold": 0.01}
const KEYS: Array[String] = ["player_hp_max", "enemy_hp_max", "player_attack", "enemy_attack",
	"damage_random_min", "damage_random_max", "charge_attack_multiplier", "charge_received_multiplier",
	"guard_received_multiplier", "item_heal", "item_uses", "action_seconds", "attack_shift_px",
	"hit_shift_px", "feedback_seconds", "pose_scale_delta"]
var tree: SceneTree
var main: Control
var b: Control
var map: Control
var points: Node
var sample: float = 1.0
var failures: int = 0
var results: Dictionary = {}
var snapshot: Array = []
var events: Array[int] = [0, 0, 0, 0, 0]
var clean: bool = true
static func start_once(root: Control) -> void:
	if root.get_tree().has_meta("sp23_runner") or DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--sp23-self-test"):
		return
	var runner: RefCounted = load("res://scripts/sp23_selftest.gd").new()
	root.get_tree().set_meta("sp23_runner", runner)
	runner.call_deferred("run", root)
func run(root: Control) -> void:
	tree = root.get_tree()
	var focus: Control = root.get_viewport().gui_get_focus_owner()
	var original_focus: WeakRef = weakref(focus) if focus != null else null
	root.hide()
	root.set_process_unhandled_key_input(false)
	await _case(_configuration, false)
	await _case(_invalid, false)
	await _case(_driven, true, {"player_hp_max": 150, "enemy_hp_max": 130, "player_attack": 31,
		"enemy_attack": 12, "charge_attack_multiplier": 3, "charge_received_multiplier": 1.5,
		"guard_received_multiplier": 0.25, "item_heal": 17, "item_uses": 2, "action_seconds": 0.6,
		"attack_shift_px": 8, "hit_shift_px": 5, "feedback_seconds": 0.2, "pose_scale_delta": 0.05})
	for method: Callable in [_layout, _input_timing, _motion, _defeat, _zero_reward, _replace]:
		await _case(method)
	for batch: Array in [[_formula, [0.9, 1.0, 1.1], true], [_charge, range(5), true], [_item, [30, 90, 100], true],
		[_entry, ["finish", "skip", "hide", "unpaid", "zero"], false],
		[_other, [&"point1", &"point2", &"point3", &"point4", &"point6", &"point7"], false], [_win, [70.0, 95.0], true]]:
		for value: Variant in batch[1]:
			await _case(batch[0].bind(value), batch[2])
	await _case(_preview, false)
	root.show()
	root.set_process_unhandled_key_input(true)
	_restore_focus(original_focus)
	_check(clean, "fixture_cleanup_restores_state")
	for label: String in results:
		print("[SP-23] %s %s" % ["PASS" if results[label] else "FAIL", label])
	print("[SP-23] failures=%d" % failures)
	tree.quit(0 if failures == 0 else 1)
func _case(method: Callable, enter: bool = true, edits: Dictionary = {}) -> void:
	var focus: Control = tree.current_scene.get_viewport().gui_get_focus_owner()
	snapshot = [GameState.vital_now, GameState.is_frozen(), GameState.is_processing(), weakref(focus) if focus != null else null, GameState.get_signal_connection_list("vital_changed")]
	GameState.set_process(false)
	GameState.set_frozen(true)
	GameState.vital_now = 100.0
	GameState.set_frozen(false)
	main = load("res://scenes/Main.tscn").instantiate()
	tree.root.add_child(main)
	b = main.get_node("Pages/BattlePage")
	map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	points = main.get_node("Overlay/Points")
	clean = clean and b.player_hp == 100 and b.enemy_hp == 100 and b.item_uses == 1 and b.start_count == 0
	snapshot.append([b.is_processing(), b.random_sample, b._rng.state])
	b.set_process(false)
	sample = 1.0
	b.random_sample = func() -> float: return sample
	var data: Dictionary = _data()
	for key: String in edits:
		data["battle_" + key] = edits[key]
	b.load_configuration(data)
	events = [0, 0, 0, 0, 0]
	GameState.vital_changed.connect(_vital)
	b.battle_lost.connect(func() -> void: events[1] += 1)
	main._dialogue.line_started.connect(func(_key: String) -> void: events[2] += 1)
	points.get_dialogue().line_started.connect(func(_key: String) -> void: events[2] += 1)
	b.visibility_changed.connect(func() -> void: events[3] += 1)
	for anchor: Node2D in [b._player, b._enemy]:
		b._animator(anchor).animation_started.connect(func(key: StringName) -> void: events[4] += int(key == &"feedback"))
	main.show_page(&"MapPage")
	if enter:
		_walk(ROUTE)
		_read()
	await main._wait_for_layout()
	await method.call()
	await _cleanup()
func _cleanup() -> void:
	var interactions: RefCounted = map._interactions
	b.random_sample = snapshot[5][1]
	b._rng.state = snapshot[5][2]
	b._reset_feedback()
	b.elapsed = 0.0
	b.set_process(snapshot[5][0])
	clean = clean and not b.random_sample.is_valid() and not b._feedback_active and b.elapsed == 0.0
	GameState.vital_changed.disconnect(_vital)
	main.queue_free()
	await tree.process_frame
	clean = clean and not is_instance_valid(main) and interactions.get_signal_connection_list("investigated").is_empty()
	GameState.set_frozen(true)
	GameState.vital_now = snapshot[0]
	GameState.set_frozen(snapshot[1])
	GameState.set_process(snapshot[2])
	_restore_focus(snapshot[3])
	clean = clean and GameState.vital_now == snapshot[0] and GameState.is_frozen() == snapshot[1]
	clean = clean and GameState.is_processing() == snapshot[2] and GameState.get_drain_accum() == 0.0
	clean = clean and GameState.get_signal_connection_list("vital_changed") == snapshot[4]
	clean = clean and tree.current_scene.get_viewport().gui_get_focus_owner() == (snapshot[3].get_ref() if snapshot[3] != null else null)
func _restore_focus(reference: WeakRef) -> void:
	var focus: Control = reference.get_ref() if reference != null else null
	tree.current_scene.get_viewport().gui_release_focus()
	if is_instance_valid(focus) and focus.is_visible_in_tree() and focus.focus_mode != Control.FOCUS_NONE and (not focus is Button or not focus.disabled):
		focus.grab_focus()
func _check(ok: bool, label: String) -> void:
	results[label] = bool(results.get(label, true)) and ok
	failures += int(not ok)
func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/knobs.json"))
func _vital(_value: float, _maximum: float, reason: StringName) -> void:
	if reason == &"battle_win":
		events[0] += 1
func _walk(route: Array) -> void:
	_check(route.all(map.try_move_to), "fixture_real_map_movement")
func _read() -> void:
	map.confirm_selection()
	points.get_dialogue().finish_text()
	points.get_dialogue().advance()
func _turn(command: int) -> void:
	b.submit_command(command)
	b.advance_time(b._k("action_seconds"))
	b.advance_time(b._k("action_seconds"))
func _input(value: Variant) -> void:
	main.get_node("Overlay/PageSwitchBar").call("_push_key" if value is int else "_click_button", value)
func _locked() -> bool:
	var ok: bool = true
	for target: Variant in [KEY_PAGEUP, KEY_PAGEDOWN] + main.get_node("Overlay/PageSwitchBar").get_children():
		_input(target)
		ok = ok and main._current_page == &"BattlePage"
	for page: StringName in [&"ScenePage", &"MapPage"]:
		ok = not main.show_page(page) and ok
	return ok and GameState.is_frozen()
func _configuration() -> void:
	var data: Dictionary = _data()
	_check(data.size() == 26 and B.validate_configuration(data).is_empty() and KEYS.all(func(key: String) -> bool: return data.has("battle_" + key)), "battle_knobs_complete")
	_check(OLD.keys().all(func(key: String) -> bool: return data.get(key) == OLD[key]), "existing_knobs_unchanged")
func _invalid() -> void:
	_walk(ROUTE)
	var cases: Array = KEYS.map(func(key: String) -> Array: return [key, null])
	cases.append_array([["player_hp_max", true], ["enemy_hp_max", "1"], ["player_attack", INF],
		["enemy_attack", -1], ["action_seconds", 0], ["feedback_seconds", 2],
		["damage_random_min", 2], ["player_hp_max", 2.5], ["item_uses", 0.5]])
	for change: Array in cases:
		var data: Dictionary = _data()
		if change[1] == null:
			data.erase("battle_" + change[0])
		else:
			data["battle_" + change[0]] = change[1]
		var rejected: bool = not b.load_configuration(data) and not b.last_error.is_empty()
		_read()
		map._interactions.investigated.emit(&"point5")
		b.submit_command(0)
		_check(rejected and b.start_count == 0 and b.turn_count == 0 and b._buttons.all(func(button: Button) -> bool: return button.disabled), "battle_knobs_reject_invalid")
	for root: Variant in [null, [], 1]:
		_check(not b.load_configuration(root) and b._buttons[0].disabled, "battle_knobs_reject_invalid")
func _driven() -> void:
	b.submit_command(0)
	var ok: bool = b.player_hp == 150 and b.enemy_hp == 99 and b._enemy_bar.max_value == 130
	ok = ok and b._enemy.position - b._origins[b._enemy].origin == Vector2(8, 5)
	b.advance_time(0.1)
	ok = ok and b._enemy.get_node("Visual/EdgeNear").scale.is_equal_approx(Vector2(1.05, 1.05))
	b.advance_time(0.49)
	ok = ok and b.state == B.State.PLAYER_ACTION
	b.advance_time(0.01)
	ok = ok and b.player_hp == 138
	b.advance_time(0.6)
	for row: Array in [[1, 99, 120], [0, 6, 108], [2, 6, 105]]:
		_turn(row[0])
		ok = ok and b.enemy_hp == row[1] and b.player_hp == row[2]
	for hp: int in [100, 80]:
		b.player_hp = hp
		b.submit_command(3)
		ok = ok and b.player_hp == hp + 17
		b.advance_time(0.6)
		b.advance_time(0.6)
	_check(ok and b.item_uses == 0, "battle_knobs_drive_results")
func _layout() -> void:
	var ok: bool = true
	for i: int in range(4):
		var button: Button = b._buttons[i]
		ok = ok and button.is_visible_in_tree() and button.text == ["攻击", "蓄力", "防御", "道具"][i]
		ok = ok and b.get_node("CommandWindow").get_global_rect().encloses(button.get_global_rect())
		for j: int in range(i):
			ok = ok and not button.get_global_rect().intersects(b._buttons[j].get_global_rect())
	_check(ok, "commands_four_visible")
	_check(b._buttons[0].has_focus() and b._buttons[0].get_theme_stylebox("focus").border_width_left > 0, "default_attack_cursor")
	_check(b._status.text == "琥珀　H 100/100" and b.get_node("StatusWindow").get_child_count() == 1, "status_one_hp_line")
	var name: Label = b.get_node("ViewArea/EnemyName")
	_check(name.text == "迷境" and name.get_theme_font_size("font_size") == b._status.get_theme_font_size("font_size")
		and name.get_theme_color("font_color").v > b._status.get_theme_color("font_color").v and name.position.y >= b._enemy.position.y and name.get_rect().end.y <= b._enemy_bar.position.y, "enemy_name_only")
	_check(not b._enemy_bar.show_percentage and b.get_node("ViewArea").find_children("*", "Label", true, false) == [name], "enemy_bar_no_digits")
	for region: String in ["ViewArea", "CommandWindow", "StatusWindow", "ReturnButton"]:
		for path: String in ["Overlay/ThroatPlaceholder", "Overlay/ThroatPlaceholder/ValueText", "Overlay/PageSwitchBar"]:
			_check(not b.get_node(region).get_global_rect().intersects(main.get_node(path).get_global_rect()), "page_layout_clearance")
	var before: int = events[2]
	_turn(0)
	_check(events[2] == before and not main._dialogue.is_playing() and not points.get_dialogue().is_playing()
		and b.find_children("*", "AudioStreamPlayer", true, false).is_empty() and b.find_children("*", "RichTextLabel", true, false).is_empty(), "no_battle_dialogue_or_audio")
func _formula(value: float) -> void:
	sample = value
	b.submit_command(0)
	var expected: int = {0.9: 82, 1.0: 80, 1.1: 78}[value]
	_check(b.enemy_hp == expected and b.player_hp == 100, "atk_formula")
	_check(b.player_hp == 100 and b.state == B.State.PLAYER_ACTION, "player_before_enemy")
	b.advance_time(0.4)
	_check(b.player_hp == expected and b.enemy_hp == expected, "enemy_atk_formula")
	if value == 1.0:
		_check(b._status.text == "琥珀　H 80/100", "status_text_after_damage")
func _charge(gap: int) -> void:
	sample = 0.93 if gap == 3 else 1.0
	b.submit_command(2 if gap == 4 else 1)
	_check(b.enemy_hp == 100 and b._player.scale != Vector2.ONE, "charge_guard_item_visible_feedback")
	b.advance_time(0.4)
	if gap != 3:
		_check(b.player_hp == (90 if gap == 4 else 75) and b.enemy_hp == 100, "guard_formula" if gap == 4 else "charge_waits_this_turn")
		_check(b._status.text == ("琥珀　H 90/100" if gap == 4 else "琥珀　H 75/100"), "status_text_after_damage")
	b.advance_time(0.4)
	if gap in [1, 2]:
		_turn(gap)
	b.submit_command(0)
	var labels: Array = ["charge_next_attack", "charge_expires_and_no_stack",
		"charge_expires_and_no_stack", "charge_rounding_once", "guard_formula"]
	_check(b.enemy_hp == [50, 50, 80, 53, 80][gap], labels[gap])
	if gap == 0:
		b.advance_time(0.4)
		b.advance_time(0.4)
		b.submit_command(0)
		_check(b.enemy_hp == 30, "charge_next_attack")
	if gap == 4:
		b.advance_time(0.4)
		_check(b.player_hp == 70, "guard_formula")
func _item(hp: int) -> void:
	b.player_hp = hp
	b.submit_command(3)
	_check(b.player_hp == (70 if hp == 30 else 100) and b.item_uses == 0, "item_heals_40" if hp == 30 else "item_caps_hp")
	_check(b._status.text == ("琥珀　H 70/100" if hp == 30 else "琥珀　H 100/100"), "status_text_after_item")
	_check(b._player.scale != Vector2.ONE and b._buttons[3].disabled, "charge_guard_item_visible_feedback")
	b.advance_time(0.4)
	if hp == 30:
		_check(b._status.text == "琥珀　H 50/100", "status_text_after_item")
	b.advance_time(0.4)
	var before: int = b.player_hp
	_input(b._buttons[3])
	_check(b.player_hp == before and b.turn_count == 1 and b._buttons[3].is_visible_in_tree()
		and b._buttons[3].get_theme_color("font_disabled_color").s < b._buttons[3].get_theme_color("font_color").s, "item_once_disabled_gray")
func _input_timing() -> void:
	var ok: bool = true
	for entry: Array in [[KEY_RIGHT, 1], [KEY_DOWN, 3], [KEY_LEFT, 2], [KEY_UP, 0]]:
		_input(entry[0])
		ok = ok and b._buttons[entry[1]].has_focus()
	_input(KEY_ENTER)
	_check(ok and b.turn_count == 1 and b.enemy_hp == 80, "commands_keyboard_and_mouse")
	b.advance_time(0.1)
	for i: int in range(4):
		_input(b._buttons[i])
		_input(KEY_ENTER)
	_check(b.elapsed == 0.1 and b.turn_count == 1 and b.player_hp == 100, "input_cannot_accelerate")
	for boundary: Array in [[0.29, B.State.PLAYER_ACTION], [0.01, B.State.ENEMY_ACTION],
			[0.39, B.State.ENEMY_ACTION], [0.01, B.State.COMMAND]]:
		b.advance_time(boundary[0])
		_check(b.state == boundary[1] and b.turn_count == 1, "two_fixed_action_times")
	_input(b._buttons[0])
	_check(b.turn_count == 2 and b.enemy_hp == 60, "commands_keyboard_and_mouse")
	_check(_locked(), "battle_navigation_locked")
func _motion() -> void:
	var frame: int = Engine.get_process_frames()
	b.submit_command(0)
	var ok: bool = b._enemy.position - b._origins[b._enemy].origin == Vector2(6, 3)
	ok = ok and b._enemy_bar.value == 80 and Engine.get_process_frames() == frame
	await tree.process_frame
	_check(ok and b._enemy.position != b._origins[b._enemy].origin and b._enemy_bar.value == 80, "hp_and_motion_same_frame")
	for enemy_turn: bool in [false, true]:
		b.advance_time(0.08)
		_check(b._enemy.get_node("Visual/EdgeNear").scale.is_equal_approx(Vector2(1.03, 1.03)) and is_equal_approx(b._enemy.get_node("Visual").modulate.a, 0.97), "enemy_spread_then_contract")
		b.advance_time(0.08)
		_check(b._enemy.get_node("Visual/EdgeFar").scale == Vector2.ONE
			and b._player.transform == b._origins[b._player] and b._enemy.transform == b._origins[b._enemy] and b.state != B.State.COMMAND, "feedback_returns_to_origin")
		if not enemy_turn:
			b.advance_time(0.24)
	var vital: float = GameState.vital_now
	GameState.drain_time(10)
	GameState.pay_step()
	GameState.pay_point(&"required")
	_check(GameState.vital_now == vital and main.get_node("Overlay/ThroatPlaceholder").is_visible_in_tree() and main.get_node("Overlay/ThroatPlaceholder").get_value() == vital, "battle_freezes_vital")
func _entry(mode: String) -> void:
	_walk(ROUTE)
	GameState.vital_now = 6 if mode == "zero" else (5 if mode == "unpaid" else 70)
	map.confirm_selection()
	var waiting: bool = main._current_page == &"MapPage" and not map.get_interactable(&"point5").read
	points.get_dialogue().finish_text()
	waiting = waiting and main._current_page == &"MapPage"
	if mode == "hide":
		main.get_node("Pages/MapPage").hide()
		main.get_node("Pages/MapPage").show()
	elif mode == "skip":
		points.get_dialogue().skip()
	else:
		points.get_dialogue().advance()
	var expected: Array = {"finish": [64, true, 1, "point5_finish_enters_page"],
		"zero": [0, true, 0, "zero_vital_before_battle"], "unpaid": [5, false, 0, "point5_interrupt_or_unpaid_no_battle"],
		"skip": [70, false, 0, "point5_interrupt_or_unpaid_no_battle"], "hide": [70, false, 0, "point5_interrupt_or_unpaid_no_battle"]}[mode]
	_check(waiting and GameState.vital_now == expected[0] and map.get_interactable(&"point5").read == expected[1]
		and b.start_count == expected[2] and GameState.is_frozen() == (mode == "finish") and main._current_page == (&"BattlePage" if mode == "finish" else &"MapPage"), expected[3])
	if mode == "zero":
		_check(b._buttons[0].disabled and events[0] == 0, "zero_vital_before_battle")
		_zero_reward()
func _other(target: StringName) -> void:
	var junction: int = ROUTE.find(target) if target in ROUTE else (2 if target == &"point6" else 4)
	_walk(ROUTE.slice(0, junction + 1) + ([] if target in ROUTE else [target]))
	_read()
	_check(map.get_interactable(target).read and b.start_count == 0 and main._current_page == &"MapPage", "other_points_no_battle")
func _no_spread() -> bool:
	return [b._enemy, b._player].all(func(anchor: Node2D) -> bool: return not b._animator(anchor).is_playing() \
		and anchor.get_node("Visual/EdgeNear").scale == Vector2.ONE and anchor.get_node("Visual/EdgeFar").scale == Vector2.ONE and anchor.get_node("Visual").modulate.a == 1.0)
func _win(vital: float) -> void:
	GameState.vital_now = vital
	var place: Array = [map.get_step_count(), map.get_revealed_ids()]
	for command: int in ([0, 0, 0, 0] if vital == 70 else [1, 0, 1]):
		_turn(command)
	var before: Array[int] = [Engine.get_process_frames(), events[4]]
	b.submit_command(0)
	_check(b.enemy_hp == 0 and b._enemy_bar.value == 0 and b._enemy.is_visible_in_tree() and b._enemy.position - b._origins[b._enemy].origin == Vector2(6, 3) and Engine.get_process_frames() == before[0], "lethal_frame_motion_shown actual_px=%s" % [b._enemy.position - b._origins[b._enemy].origin])
	_check(events[4] == before[1] and _no_spread(), "lethal_no_spread_no_flash spread=%d flash=%d" % [events[4] - before[1], events[4] - before[1]])
	_check(b.turn_count == (5 if vital == 70 else 4) and b.player_hp == (20 if vital == 70 else 30), "baseline_turn_counts")
	_check(GameState.vital_now == (80 if vital == 70 else 100) and events[0] == 1, "win_recovers_and_caps_once")
	_check(_no_spread(), "no_spread_on_zero")
	_input(b._return)
	var locked: bool = _locked()
	b.advance_time(0.4)
	b.advance_time(1.0)
	_check(b.player_hp == (20 if vital == 70 else 30) and b.enemy_hp == 0 and not b._enemy.visible, "lethal_no_counterattack")
	locked = _locked() and locked
	var changes: int = events[3]
	_input(b._return)
	_check(main._current_page == &"MapPage" and not GameState.is_frozen() and map.get_current_node_id() == &"point5" and [map.get_step_count(), map.get_revealed_ids()] == place, "win_returns_same_point5")
	b._on_return_pressed()
	_input(b._return)
	_check(locked and events[3] == changes + 1 and events[0] == 1, "victory_return_once")
	map.confirm_selection()
	map._interactions.investigated.emit(&"point5")
	for page: StringName in [&"BattlePage", &"MapPage"]:
		main.show_page(page)
	b._settle_victory()
	_check(b.start_count == 1 and b.enemy_hp == 0 and b.item_uses == 1 and events[0] == 1, "one_battle_only")
	_check(map.try_move_to(&"point4"), "win_returns_same_point5")
func _defeat() -> void:
	b.player_hp = 10
	b.submit_command(0)
	var frame: int = Engine.get_process_frames()
	b.advance_time(0.4)
	_check(b.player_hp == 0 and b._player.is_visible_in_tree() and b._player.position - b._origins[b._player].origin == Vector2(-6, 3) and Engine.get_process_frames() == frame, "player_lethal_frame_motion actual_px=%s" % [b._player.position - b._origins[b._player].origin])
	_check(b._status.text == "琥珀　H 0/100", "status_text_after_zero")
	_check(_no_spread(), "no_spread_on_zero")
	var turns: int = b.turn_count
	b.submit_command(0)
	b.advance_time(4)
	b._on_return_pressed()
	b._on_return_pressed()
	_check(b.state == B.State.DEFEATED and b.player_hp == 0 and events[1] == 1 and events[0] == 0 and b.turn_count == turns, "defeat_stops_without_reward")
	_check(_locked() and b._return.disabled and b.player_hp == 0 and events[0] == 0, "defeat_navigation_locked")
func _zero_reward() -> void:
	GameState.vital_now = 0
	b.enemy_hp = 0
	for i: int in range(2):
		b._on_investigated(&"point5")
		b._settle_victory()
		b.submit_command(0)
		b.advance_time(1)
		_input(KEY_PAGEUP)
	_check(GameState.vital_now == 0 and events[0] == 0, "zero_vital_no_win_recovery")
func _replace() -> void:
	for anchor: Node2D in [b._player, b._enemy]:
		anchor.get_node("Visual").free()
		var replacement := Sprite2D.new()
		replacement.name = &"Visual"
		anchor.add_child(replacement)
	b.submit_command(0)
	var shifted: bool = b._enemy.transform != b._origins[b._enemy]
	b.advance_time(0.4)
	_check(shifted and b.enemy_hp == 80 and b.player_hp == 80 and b._enemy_bar.value == 80, "silhouettes_replaceable")
func _preview() -> void:
	_input(main.get_node("Overlay/PageSwitchBar/BattleButton"))
	_input(KEY_ENTER)
	_check(main._current_page == &"BattlePage" and GameState.is_frozen() and b.start_count == 0 and b._buttons[0].disabled and b.turn_count == 0, "preview_does_not_start")
	_input(KEY_PAGEUP)
	_check(main._current_page == &"MapPage" and not GameState.is_frozen(), "battle_navigation_locked")

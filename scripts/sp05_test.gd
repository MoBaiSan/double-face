## SP-05 独立开发测试页；不被 Main.tscn 引用，也不注册全局输入。
extends Control

var _failures: int = 0
var _frame_delta_sum: float = 0.0


func _process(delta: float) -> void:
	_frame_delta_sum += delta


func _ready() -> void:
	$Set84.pressed.connect(_set_84)
	$Set96.pressed.connect(_set_96)
	$ToggleFreeze.pressed.connect(_toggle_freeze)
	GameState.vital_changed.connect(_on_vital_changed)
	GameState.frozen_changed.connect(_on_frozen_changed)
	_on_vital_changed(GameState.vital_now, GameState.vital_max, &"initial")
	_on_frozen_changed(GameState.is_frozen())
	if OS.get_cmdline_user_args().has("--sp05-self-test"):
		call_deferred("_run_self_test")


func _set_84() -> void:
	GameState.vital_now = 84.0


func _set_96() -> void:
	GameState.vital_now = 96.0


func _toggle_freeze() -> void:
	GameState.set_frozen(not GameState.is_frozen())


func _on_vital_changed(value: float, maximum: float, reason: StringName) -> void:
	$Value.text = "vital_now=%d / %.0f  reason=%s" % [floori(value), maximum, reason]


func _on_frozen_changed(frozen: bool) -> void:
	$Frozen.text = "冻结：" + ("是" if frozen else "否")


func _run_self_test() -> void:
	var saved: Dictionary = GameState.capture_session()
	GameState.begin_session(GameState.State.S2)
	var maximum: float = GameState.vital_max
	var rate: float = GameState.get_knob("time_drain_per_second")
	GameState.set_process(true)
	GameState.set_frozen(false)
	GameState.vital_now = maximum
	await _test_auto_drain(maximum, rate)
	GameState.set_process(false)
	GameState.set_frozen(true)
	var reset_accum: float = GameState.get_drain_accum()
	print("[SP-05] selftest_accum_reset actual=%.6f" % reset_accum)
	if absf(reset_accum) > 0.000001:
		_failures += 1
	GameState.set_frozen(false)
	GameState.vital_now = maximum
	for _second: int in range(125):
		GameState.drain_time(1.0)
	_assert_close("time_125s", maximum - rate * 125.0, GameState.vital_now)
	_test_independent_costs(maximum)
	_test_freeze(maximum, rate)
	_test_battle_win(maximum)
	_test_display_floor(maximum)
	await _base_configuration_cases()
	GameState.begin_session(GameState.State.S0, saved)
	print("[SP-05] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## 等待真实帧并验证 GameState._process 的自动接线；容差取未 flush 的旋钮阈值。
func _test_auto_drain(maximum: float, rate: float) -> void:
	_frame_delta_sum = 0.0
	while _frame_delta_sum < 1.0:
		await get_tree().process_frame
	var expected_drop: float = rate * _frame_delta_sum
	var actual_drop: float = maximum - GameState.vital_now
	var tolerance: float = GameState.get_knob("drain_flush_threshold")
	var passed: bool = actual_drop > 0.0 and absf(actual_drop - expected_drop) <= tolerance
	print("[SP-05] auto_drain_via_process elapsed=%.6f expected_drop=%.6f actual_drop=%.6f tolerance=%.6f %s" % [
		_frame_delta_sum, expected_drop, actual_drop, tolerance, "PASS" if passed else "FAIL"])
	if not passed:
		_failures += 1


func _test_independent_costs(maximum: float) -> void:
	GameState.vital_now = maximum
	GameState.pay_step()
	_assert_close("step_cost", maximum - GameState.get_knob("step_cost"), GameState.vital_now)
	GameState.vital_now = maximum
	GameState.pay_point(&"required")
	_assert_close("required_point", maximum - GameState.get_knob("required_point_cost"), GameState.vital_now)
	GameState.vital_now = maximum
	GameState.pay_point(&"optional")
	_assert_close("optional_point", maximum - GameState.get_knob("optional_point_cost"), GameState.vital_now)


func _test_freeze(maximum: float, rate: float) -> void:
	GameState.set_frozen(false)
	GameState.vital_now = maximum
	GameState.drain_time(0.1)
	var accumulated: float = GameState.get_drain_accum()
	GameState.set_frozen(true)
	_assert_close("freeze_clears_accum", 0.0, GameState.get_drain_accum())
	var frozen_value: float = GameState.vital_now
	GameState.drain_time(1000.0)
	_assert_close("frozen_no_drain", frozen_value, GameState.vital_now)
	var before_costs: float = GameState.vital_now
	var step_allowed: bool = GameState.pay_step()
	var point_allowed: bool = GameState.pay_point(&"required")
	var costs_unchanged: bool = is_equal_approx(before_costs, GameState.vital_now)
	print("[SP-05] frozen_pay_step expected=false actual=%s %s" % [
		step_allowed, "PASS" if not step_allowed and costs_unchanged else "FAIL"])
	print("[SP-05] frozen_pay_point expected=false actual=%s %s" % [
		point_allowed, "PASS" if not point_allowed and costs_unchanged else "FAIL"])
	if step_allowed or point_allowed or not costs_unchanged:
		_failures += 2
	GameState.set_frozen(false)
	GameState.drain_time(1.0)
	_assert_close("unfreeze_no_catchup", maximum - rate, GameState.vital_now)
	print("[SP-05] freeze_accum_before=%.6f" % accumulated)


func _test_battle_win(maximum: float) -> void:
	GameState.vital_now = 84.0
	GameState.on_battle_win()
	_assert_close("battle_win_84_to_92", 92.0, GameState.vital_now)
	GameState.vital_now = 96.0
	GameState.on_battle_win()
	_assert_close("battle_win_96_to_100", maximum, GameState.vital_now)


func _test_display_floor(maximum: float) -> void:
	GameState.vital_now = maximum
	_assert_text("display_100", "100")
	GameState.vital_now = 99.9
	_assert_text("display_99_9", "99")
	GameState.vital_now = 0.4
	_assert_text("display_0_4", "0")


func _assert_close(name: String, expected: float, actual: float) -> void:
	var passed: bool = absf(actual - expected) <= 0.000001
	print("[SP-05] %s expected=%.6f actual=%.6f %s" % [
		name, expected, actual, "PASS" if passed else "FAIL"])
	if not passed:
		_failures += 1


func _assert_text(name: String, expected: String) -> void:
	var actual: String = $Value.text.split(" ")[0].trim_prefix("vital_now=")
	var passed: bool = actual == expected
	print("[SP-05] %s expected=%s actual=%s %s" % [
		name, expected, actual, "PASS" if passed else "FAIL"])
	if not passed:
		_failures += 1


func _fix_assert(ok: bool, name: String) -> void:
	_failures += int(not ok)
	print("[SP-05] %s %s" % [name, "PASS" if ok else "FAIL"])

func _base_configuration_cases() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/knobs.json"))
	var isolated = preload("res://scripts/gamestate.gd").new()
	var missing: Array[bool] = []
	for key: String in isolated.BASE_KNOBS:
		var sample: Dictionary = source.duplicate(true)
		sample.erase(key)
		missing.append(not isolated.load_base_configuration(sample) and isolated.configuration_error.contains(key) and not isolated.configuration_valid and not isolated.is_processing())
	_fix_assert(missing.size() == 10 and missing.all(func(ok: bool): return ok), "base_knobs_required_keys_rejected")
	var invalid: Array[bool] = []
	for key: String in isolated.BASE_KNOBS:
		for value: Variant in ["bad", false, null, NAN, INF, -INF, -1.0]:
			var sample: Dictionary = source.duplicate(true)
			sample[key] = value
			invalid.append(not isolated.load_base_configuration(sample))
		if key not in ["time_drain_per_second", "battle_win_recovery"]:
			var sample: Dictionary = source.duplicate(true)
			sample[key] = 0
			invalid.append(not isolated.load_base_configuration(sample))
	for pair: Array in [["threshold_low", 1.0], ["threshold_critical", 40.0], ["threshold_full", 101.0], ["drain_flush_threshold", 0.0000001]]:
		var sample: Dictionary = source.duplicate(true)
		sample[pair[0]] = pair[1]
		invalid.append(not isolated.load_base_configuration(sample))
	_fix_assert(invalid.size() == 82 and invalid.all(func(ok: bool): return ok), "base_knobs_type_and_range_rejected")
	var zero: Dictionary = source.duplicate(true)
	zero.time_drain_per_second = 0.0
	zero.battle_win_recovery = 0.0
	var allowed: bool = isolated.load_base_configuration(zero)
	isolated.begin_session(isolated.State.S2)
	isolated.vital_now = 50.0
	isolated.drain_time(100.0)
	isolated.on_battle_win()
	allowed = allowed and isolated.vital_now == 50.0 and isolated.pay_step() and isolated.vital_now == 49.0
	_fix_assert(allowed, "base_knobs_explicit_zero_allowed")
	isolated.free()
	var saved: Dictionary = GameState.capture_session()
	var knobs: Dictionary = GameState._knobs.duplicate(true)
	var maximum: float = GameState.vital_max
	var valid_before: bool = GameState.configuration_valid
	var error_before: String = GameState.configuration_error
	var processing: bool = GameState.is_processing()
	var blocked: Array[bool] = []
	var rejected_mains: Array[Control] = []
	for key: String in ["vital_max", "time_drain_per_second"]:
		var sample: Dictionary = source.duplicate(true)
		sample.erase(key)
		var rejected: bool = not GameState.load_base_configuration(sample)
		var run: int = GameState.run_id
		var events: Dictionary = GameState._events.duplicate(true)
		var main: Control = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(main)
		var grid: Control = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
		blocked.append(rejected and main.startup_blocked and not GameState.is_processing() and GameState.run_id == run and GameState._events == events and not main.show_page(&"MapPage") and not grid.try_move_to(&"c1") and not GameState.pay_step())
		rejected_mains.append(main)
	var loaded: bool = GameState.load_base_configuration(source)
	var loader_still_stopped: bool = not GameState.is_processing()
	# 合法配置本身不能启用半装配；失败的新装配同样不得开启处理。
	var missing_lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))
	missing_lines = missing_lines.filter(func(entry: Dictionary): return entry.id != "T101")
	var failed: Control = load("res://scenes/Main.tscn").instantiate()
	failed.dialogue_factory = func():
		var player: Control = load("res://scenes/ui/DialogueBox.tscn").instantiate()
		player.source_data = missing_lines
		return player
	var before_failed: Dictionary = GameState.capture_session()
	get_tree().root.add_child(failed)
	var failed_still_stopped: bool = failed.startup_blocked and not failed._flow.assembly_ready and not GameState.is_processing() and GameState.capture_session() == before_failed
	rejected_mains.append(failed)
	var healthy: Control = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(healthy)
	var recovered: bool = loaded and loader_still_stopped and failed_still_stopped and not healthy.startup_blocked and healthy._flow.assembly_ready and GameState.event_started(&"E1") and GameState.is_processing()
	var auto_drain: bool = await _recovered_session_auto_drain(healthy)
	var old_flows_blocked: bool = true
	for rejected_main: Control in rejected_mains:
		old_flows_blocked = old_flows_blocked and rejected_main.startup_blocked and rejected_main.get_node("Pages").process_mode == Node.PROCESS_MODE_DISABLED and not rejected_main.show_page(&"MapPage")
		rejected_main.free()
	recovered = recovered and auto_drain and old_flows_blocked
	healthy.free()
	GameState._knobs = knobs
	GameState.vital_max = maximum
	GameState.configuration_valid = valid_before
	GameState.configuration_error = error_before
	GameState.begin_session(GameState.State.S0, saved)
	GameState.set_process(processing)
	_fix_assert(blocked.size() == 2 and blocked.all(func(ok: bool): return ok) and recovered, "invalid_base_config_blocks_start")

## 恢复路径只靠生产装配开启处理；不手工set_process(true)或调用drain_time。
func _recovered_session_auto_drain(main: Control) -> bool:
	var context = preload("res://scripts/prologue_test_context.gd").new()
	context.attach(main) # 只挂接实例，不使用会关闭处理/重置会话的create或enter_domain。
	var player: Control = main._dialogue
	var committed: bool = GameState.is_processing() and GameState.state == GameState.State.S0
	await main._wait_for_layout()
	context.finish_sequence(player) # E1真实完成。
	context.click(main.get_node("Pages/ScenePage/TestOptions/OptionTwo"))
	for stage: int in range(4): # READING、R2、R3、R4各由真实完成推进。
		context.finish_sequence(player)
	context.finish_sequence(player) # E5完成，真实呈现地图。
	context.finish_sequence(player) # T130/T131结束，让首步输入进入原流程。
	await main._wait_for_layout()
	var target: Vector2 = context.map.get_global_transform_with_canvas() * context.map._point_position(&"c1")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		main.get_viewport().push_input(event, true)
	var entered: bool = GameState.state == GameState.State.S2 and main._current_page == &"MapPage" and context.map.get_current_node_id() == &"c1" and context.map.get_step_count() == 1
	entered = entered and GameState.event_done(&"E1") and GameState.event_done(&"E4") and GameState.event_done(&"E5")
	var running: bool = GameState.is_processing() and not GameState.is_frozen()
	var start_value: float = GameState.vital_now
	var rate: float = GameState.get_knob("time_drain_per_second")
	var tolerance: float = GameState.get_knob("drain_flush_threshold")
	var accumulated_before: float = GameState.get_drain_accum()
	var wait_seconds: float = 2.0 * tolerance / rate if rate > 0.0 else 0.25
	_frame_delta_sum = 0.0
	for frame: int in range(120):
		await get_tree().process_frame
		if _frame_delta_sum >= wait_seconds:
			break
	var expected_drop: float = rate * _frame_delta_sum + accumulated_before
	var actual_drop: float = start_value - GameState.vital_now
	var within_expected: bool = rate > 0.0 and _frame_delta_sum >= wait_seconds and actual_drop > 0.0 and absf(actual_drop - expected_drop) <= tolerance
	print("[SP-05] recovered_auto_drain committed=%s entered_s2=%s processing=%s elapsed=%.6f start=%.6f expected=%.6f actual=%.6f tolerance=%.6f" %
		[committed, entered, running, _frame_delta_sum, start_value, start_value - expected_drop, GameState.vital_now, tolerance])
	return committed and entered and running and GameState.is_processing() and within_expected

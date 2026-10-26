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
	_assert_close("battle_win_84_to_94", 94.0, GameState.vital_now)
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

## 序章嗓子条与必查进度；离场权限集中检查，地图与战斗实例各自管理表现。
extends Node

signal progress_changed(done: int, open: bool)
signal exit_confirmed
const REQUIRED_COUNT: int = 5
const NORMAL_RETURN_STEPS: int = 6
var _required_ids: Dictionary = {}
var _completed_ids: Dictionary = {}
var _progress_valid: bool = false
var _p5_read: bool = false
var _p5_won: bool = false
var _exit_consumed: bool = false
var must_done: int:
	get:
		return _completed_ids.size()
var exit_open: bool:
	get:
		return _progress_valid and must_done == REQUIRED_COUNT

signal vital_changed(vital_now: float, vital_max: float, reason: StringName)
signal frozen_changed(frozen: bool)

const KNOBS_PATH: String = "res://data/knobs.json"
const VITAL_EPSILON: float = 1e-6
const REQUIRED_KIND: StringName = &"required"
const OPTIONAL_KIND: StringName = &"optional"

var vital_max: float = 0.0
var _vital_now: float = 0.0
var _frozen: bool = false
var _drain_accum: float = 0.0
var _point_pay_calls: int = 0
var _knobs: Dictionary = {}

var vital_now: float:
	get:
		return _vital_now
	set(value):
		_set_vital(value, &"external")


func _ready() -> void:
	_load_knobs()
	vital_max = _knob("vital_max")
	_vital_now = vital_max
	set_process(true)
	if "--sp10-self-test" in OS.get_cmdline_user_args():
		_run_sp10_self_test.call_deferred()


func _process(delta: float) -> void:
	drain_time(delta)


## 按经过时间累积嗓子消耗；由自动处理或测试入口在非冻结期间调用。
func drain_time(delta: float) -> void:
	if _frozen or delta <= 0.0:
		return
	_drain_accum += delta * _knob("time_drain_per_second")
	if _drain_accum < _knob("drain_flush_threshold"):
		return
	var amount: float = _drain_accum
	_drain_accum = 0.0
	_set_vital(_vital_now - amount, &"time")


## 扣除一次移动费用；地图光标确认走格时调用，冻结期间拒绝扣除。
func pay_step() -> bool:
	if _frozen:
		return false
	return _spend(_knob("step_cost"), &"step")


## 扣除一次必查或可选调查费用；调查确认时传入对应类型调用。
func pay_point(kind: StringName) -> bool:
	_point_pay_calls += 1
	if _frozen:
		return false
	var knob_name: String = ""
	if kind == REQUIRED_KIND:
		knob_name = "required_point_cost"
	elif kind == OPTIONAL_KIND:
		knob_name = "optional_point_cost"
	else:
		return false
	return _spend(_knob(knob_name), &"point_" + kind)


## 切换战斗冻结状态；进入冻结时清掉未结算时间累积并通知界面。
func set_frozen(value: bool) -> void:
	if value:
		_drain_accum = 0.0
	if _frozen == value:
		return
	_frozen = value
	frozen_changed.emit(_frozen)


## 进入战斗冻结并清除进入前的时间累积；战斗边界跨入时调用。
func enter_battle() -> void:
	if _frozen:
		return
	set_frozen(true)


## 离开战斗解除冻结；战斗边界跨出时调用。
func exit_battle() -> void:
	if not _frozen:
		return
	set_frozen(false)


## 返回当前是否冻结；测试页和页面切换逻辑用它读取状态。
func is_frozen() -> bool:
	return _frozen


## 结算战斗胜利回 10 点；战斗胜利事件发生时调用且自动截断上限。
func on_battle_win() -> void:
	var alive_before: bool = _vital_now > 0.0
	_set_vital(_vital_now + _knob("battle_win_recovery"), &"battle_win")
	if alive_before and _progress_valid and _p5_read:
		_p5_won = true
		_complete_required(&"point5")


## 读取尚未结算的时间扣除累积；冻结自检用它确认清零。
func get_drain_accum() -> float:
	return _drain_accum


## 返回调查扣点入口调用次数；点阵死胡同自检用它确认没有伪调查。
func get_point_pay_call_count() -> int:
	return _point_pay_calls


## 返回向下取整的显示值；UI 更新数字标签时调用。
func get_display_value() -> int:
	return floori(_vital_now)


## 根据旋钮阈值计算状态档位；VitalBar 收到数值信号时调用。
func get_band_for_value(value: float) -> StringName:
	if value >= _knob("threshold_full"):
		return &"full"
	if value >= _knob("threshold_low"):
		return &"low"
	if value >= _knob("threshold_critical"):
		return &"critical"
	return &"broken"


## 读取指定旋钮数值；自检和扣点入口用它避免散落常量。
func get_knob(name: String) -> float:
	return _knob(name)


func _spend(amount: float, reason: StringName) -> bool:
	if amount <= 0.0 or _vital_now < amount:
		return false
	_set_vital(_vital_now - amount, reason)
	return true


func _set_vital(value: float, reason: StringName) -> void:
	if vital_max <= 0.0:
		return
	var next_value: float = clampf(value, 0.0, vital_max)
	if absf(next_value - _vital_now) < VITAL_EPSILON:
		return
	_vital_now = next_value
	vital_changed.emit(_vital_now, vital_max, reason)


func _load_knobs() -> void:
	var text: String = FileAccess.get_file_as_string(KNOBS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SP-05 knobs 无法解析：%s" % KNOBS_PATH)
		return
	_knobs = parsed as Dictionary


func _knob(name: String) -> float:
	return float(_knobs.get(name, 0.0))

## 只绑定已验证的五个必查点；配置缺失或不完整时出口保持关闭。
func configure_progress(definitions: Dictionary, map_ids: Dictionary) -> void:
	_required_ids.clear()
	for map_id: Variant in map_ids:
		var definition: Dictionary = definitions.get(map_ids[map_id], {})
		if definition.get("progress", false):
			_required_ids[StringName(map_id)] = true
	_progress_valid = _required_ids.size() == REQUIRED_COUNT and _required_ids.has(&"point5")
	reset_progress()

## 只清本局数据；完整第二局由调用者销毁并重建含BattlePage的Main。
func reset_progress() -> void:
	_completed_ids.clear()
	_p5_read = false
	_p5_won = false
	_exit_consumed = false
	progress_changed.emit(must_done, exit_open)

func record_investigated(map_id: StringName) -> void:
	if not _progress_valid or not _required_ids.has(map_id):
		return
	if map_id == &"point5":
		_p5_read = true
		if not _p5_won:
			return
	_complete_required(map_id)

func _complete_required(map_id: StringName) -> void:
	if _completed_ids.has(map_id):
		return
	_completed_ids[map_id] = true
	progress_changed.emit(must_done, exit_open)

func can_confirm_exit(at_entry: bool, map_active: bool) -> bool:
	return exit_open and at_entry and map_active and not _frozen and _vital_now > 0.0 and not _exit_consumed

func try_confirm_exit(at_entry: bool, map_active: bool) -> bool:
	if not can_confirm_exit(at_entry, map_active):
		return false
	_exit_consumed = true
	exit_confirmed.emit()
	return true

func _run_sp10_self_test() -> void:
	await get_tree().process_frame
	await load("res://scripts/sp10_selftest.gd").new().run(self)

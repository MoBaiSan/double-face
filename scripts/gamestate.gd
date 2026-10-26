## 序章的嗓子条数值来源；只读取旋钮，不承载地图、战斗或剧情。
extends Node

signal vital_changed(vital_now: float, vital_max: float, reason: StringName)
signal frozen_changed(frozen: bool)

const KNOBS_PATH: String = "res://data/knobs.json"
const REQUIRED_KIND: StringName = &"required"
const OPTIONAL_KIND: StringName = &"optional"

var vital_max: float = 0.0
var _vital_now: float = 0.0
var _frozen: bool = false
var _drain_accum: float = 0.0
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


## 返回当前是否冻结；测试页和页面切换逻辑用它读取状态。
func is_frozen() -> bool:
	return _frozen


## 结算战斗胜利回 10 点；战斗胜利事件发生时调用且自动截断上限。
func on_battle_win() -> void:
	_set_vital(_vital_now + _knob("battle_win_recovery"), &"battle_win")


## 读取尚未结算的时间扣除累积；冻结自检用它确认清零。
func get_drain_accum() -> float:
	return _drain_accum


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
	if amount <= 0.0:
		return false
	_set_vital(_vital_now - amount, reason)
	return true


func _set_vital(value: float, reason: StringName) -> void:
	if vital_max <= 0.0:
		return
	var next_value: float = clampf(value, 0.0, vital_max)
	if is_equal_approx(next_value, _vital_now):
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

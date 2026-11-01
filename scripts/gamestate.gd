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
const BASE_KNOBS: Array[String] = ["vital_max", "time_drain_per_second", "step_cost", "required_point_cost", "optional_point_cost", "battle_win_recovery", "threshold_full", "threshold_low", "threshold_critical", "drain_flush_threshold"]
var _knobs: Dictionary = {}
var configuration_valid: bool = false
var configuration_error: String = ""

var vital_now: float:
	get:
		return _vital_now
	set(value):
		_set_vital(value, &"external")


func _ready() -> void:
	if not _load_knobs():
		return
	vital_max = _knob("vital_max")
	_vital_now = vital_max
	set_process(true)
	if "--sp10-self-test" in OS.get_cmdline_user_args():
		_run_sp10_self_test.call_deferred()


func _process(delta: float) -> void:
	drain_time(delta)


## 按经过时间累积嗓子消耗；由自动处理或测试入口在非冻结期间调用。
func drain_time(delta: float) -> void:
	if not configuration_valid or _state not in [State.S2, State.S3] or _frozen or delta <= 0.0:
		return
	_drain_accum += delta * _knob("time_drain_per_second")
	if _drain_accum < _knob("drain_flush_threshold"):
		return
	var amount: float = _drain_accum
	_drain_accum = 0.0
	_set_vital(_vital_now - amount, &"time")


## 扣除一次移动费用；地图光标确认走格时调用，冻结期间拒绝扣除。
func pay_step() -> bool:
	if not configuration_valid or _frozen:
		return false
	return _spend(_knob("step_cost"), &"step")


## 扣除一次必查或可选调查费用；调查确认时传入对应类型调用。
func pay_point(kind: StringName) -> bool:
	_point_pay_calls += 1
	if not configuration_valid or _frozen:
		return false
	var cost: float = get_point_cost(kind)
	return cost >= 0.0 and _spend(cost, &"point_" + kind)

## 调查校验与支付共用当前旋钮；未知类型返回负值，不能作为免费调查。
func get_point_cost(kind: StringName) -> float:
	if kind == REQUIRED_KIND:
		return _knob("required_point_cost")
	if kind == OPTIONAL_KIND:
		return _knob("optional_point_cost")
	return -1.0


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


## 按 battle_win_recovery 结算战斗胜利恢复；胜利事件发生时调用且自动截断上限。
func on_battle_win() -> void:
	var alive_before: bool = _vital_now > 0.0
	if not alive_before:
		return
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
	if _vital_now <= 0.0:
		request_transition(&"failure")


func _load_knobs() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KNOBS_PATH))
	if not load_base_configuration(parsed):
		push_error("SP-05 knobs 无法加载：%s" % configuration_error)
		return false
	return true

static func validate_base_configuration(data: Variant) -> String:
	if not data is Dictionary:
		return "基础配置根必须是对象"
	for key: String in BASE_KNOBS:
		if not data.has(key):
			return "基础配置缺少键：%s" % key
		var value: Variant = data[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return "基础配置必须为有限数值：%s" % key
		if key in ["time_drain_per_second", "battle_win_recovery"]:
			if float(value) < 0.0:
				return "基础配置不得为负：%s" % key
		elif float(value) <= 0.0:
			return "基础配置必须大于零：%s" % key
	if float(data["drain_flush_threshold"]) <= VITAL_EPSILON:
		return "基础配置必须大于数值精度：drain_flush_threshold"
	if not (data["threshold_critical"] < data["threshold_low"] and data["threshold_low"] < data["threshold_full"] and data["threshold_full"] <= data["vital_max"]):
		return "基础阈值顺序错误：threshold_critical < threshold_low < threshold_full <= vital_max"
	return ""

func load_base_configuration(data: Variant) -> bool:
	configuration_error = validate_base_configuration(data)
	configuration_valid = configuration_error.is_empty()
	if not configuration_valid:
		_knobs.clear()
		vital_max = 0.0
		_vital_now = 0.0
		_drain_accum = 0.0
		set_process(false)
		return false
	_knobs = data.duplicate(true)
	vital_max = float(_knobs["vital_max"])
	_vital_now = vital_max
	_drain_accum = 0.0
	return true

func _knob(name: String) -> float:
	if not configuration_valid:
		return 0.0 # 无效状态仅供静止UI安全查询；所有行动入口均拒绝。
	if not _knobs.has(name):
		configuration_error = "基础配置缺少键：%s" % name
		configuration_valid = false
		set_process(false)
		push_error(configuration_error)
		return 0.0
	return float(_knobs[name])

## 只绑定已验证的五个必查点；配置缺失或不完整时出口保持关闭。
func configure_progress(definitions: Dictionary, map_ids: Dictionary) -> void:
	_required_ids.clear()
	for map_id: Variant in map_ids:
		var definition: Dictionary = definitions.get(map_ids[map_id], {})
		if definition.get("progress", false):
			_required_ids[StringName(map_id)] = true
	_progress_valid = _required_ids.size() == REQUIRED_COUNT and _required_ids.has(&"point5")
	reset_progress()

## 只清本局数据；完整第二局须重建BattlePage并复位地图，不能只调用本函数。
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
	return _state == State.S3 and exit_open and at_entry and map_active and not _frozen and _vital_now > 0.0 and not _exit_consumed

func try_confirm_exit(at_entry: bool, map_active: bool) -> bool:
	if not can_confirm_exit(at_entry, map_active):
		return false
	_exit_consumed = true
	exit_confirmed.emit()
	return true

func _run_sp10_self_test() -> void:
	await get_tree().process_frame
	await load("res://scripts/sp10_selftest.gd").new().run(self)

enum State { S0, S1, S2, S2B, S3, S4, S5, S6 }
signal state_changed(from: int, to: int, reason: StringName, session: int)
signal event_changed(id: StringName, completed: bool, session: int)
var _state: State = State.S0
var state: State:
	get:
		return _state
var run_id: int = 0
var eaten_used: bool = false
var presenter: Callable
var battle_actor: WeakRef
var _events: Dictionary = {}
var _investigations: Dictionary = {}
var tutorial_seen: Dictionary = {"investigation": false, "vital": false, "battle": false}
var tutorial_loaded: bool = false
var inside_caption_state: Dictionary = {}


## 教学旗独立于任务进度，重来不清；显式域快照仍精确恢复。
func claim_tutorial(key: String, session: int) -> bool:
	if session != run_id or not tutorial_seen.has(key) or tutorial_seen[key]:
		return false
	tutorial_seen[key] = true
	return true

func import_tutorial(data: Variant) -> void:
	var source: Dictionary = data if data is Dictionary else {}
	for key: String in tutorial_seen:
		var value: Variant = source.get(key, false)
		if value is bool and value:
			tutorial_seen[key] = true
	tutorial_loaded = true

func begin_session(initial: State = State.S0, saved: Dictionary = {}) -> void:
	if not saved.is_empty():
		for key: String in saved:
			set(key, saved[key])
		return
	if not configuration_valid:
		return
	run_id += 1
	eaten_used = false
	_state = initial
	_events.clear()
	_investigations.clear()
	reset_progress()
	_vital_now = vital_max
	inside_caption_state = {"session": run_id, "requested": {}, "played": {}, "closed": false,
		"t141_after_step": -1, "previous_done": 0, "last_vital": vital_max,
		"last_band": get_band_for_value(vital_max)}
	_drain_accum = 0.0
	set_frozen(initial in [State.S2B, State.S4, State.S5])

func capture_session() -> Dictionary:
	var saved: Dictionary = {}
	for key: String in ["_state", "run_id", "_events", "_investigations",
		"_required_ids", "_completed_ids", "_progress_valid", "_p5_read", "_p5_won",
		"_exit_consumed", "_vital_now", "_frozen", "_drain_accum", "presenter", "battle_actor", "eaten_used",
		"tutorial_seen", "tutorial_loaded", "inside_caption_state"]:
		var value: Variant = get(key)
		saved[key] = value.duplicate(true) if value is Dictionary else value
	return saved

func can_map_action() -> bool:
	return configuration_valid and _state in [State.S2, State.S3] and not _frozen and _vital_now > 0.0

func can_investigate() -> bool:
	return can_map_action()

func event_done(id: StringName) -> bool:
	return int(_events.get(id, 0)) == 2

func event_started(id: StringName) -> bool:
	return _events.has(id)

func record_event(id: StringName, completed: bool = false, session: int = -1) -> bool:
	if session != -1 and session != run_id:
		return false
	if not _event_allowed(id):
		return false
	var value: int = 2 if completed else 1
	if int(_events.get(id, 0)) >= value:
		return false
	_events[id] = value
	event_changed.emit(id, completed, run_id)
	return true

func cancel_started_event(id: StringName, session: int) -> bool:
	if session != run_id or int(_events.get(id, 0)) != 1:
		return false
	_events.erase(id)
	return true

func _event_allowed(id: StringName) -> bool:
	match id:
		&"E1": return _state == State.S0
		&"E2": return _state == State.S0 and event_done(&"E1")
		&"E3": return _state == State.S0 and event_done(&"E2")
		&"E4": return _state == State.S0 and event_done(&"E3")
		&"E5": return _state == State.S1
		&"E6": return can_investigate()
		&"E7": return _state == State.S3 and exit_open
		&"E8": return _state == State.S3 and _exit_consumed
		&"E9": return _state == State.S4
		&"E10": return _state == State.S5
		&"E11": return _state == State.S2
		&"E12", &"E13": return _state == State.S6
		&"E14": return _state == State.S6 and event_done(&"E12")
		&"E15", &"E16", &"E17": return _state == State.S2B
	return false

func record_investigation(id: StringName, session: int) -> bool:
	if session != run_id or not can_investigate() or _investigations.has(id):
		return false
	_investigations[id] = true
	_events[&"E6"] = 2
	event_changed.emit(&"E6", true, run_id)
	return true

func request_transition(reason: StringName, session: int = -1) -> bool:
	if (session != -1 and session != run_id) or not presenter.is_valid():
		return false
	var target: int = _transition_target(reason)
	if target < 0:
		return false
	var previous: State = _state
	var frozen_before: bool = _frozen
	var accumulated: float = _drain_accum
	_state = target as State
	if not _state in [State.S2, State.S3]:
		set_frozen(true)
	set_frozen(_state in [State.S2B, State.S4, State.S5])
	if not presenter.call(_state):
		_state = previous
		set_frozen(frozen_before)
		_drain_accum = accumulated
		return false
	state_changed.emit(previous, _state, reason, run_id)
	return true

func _transition_target(reason: StringName) -> int:
	if reason == &"failure" and _state in [State.S2, State.S2B, State.S3]:
		var actor: Node = battle_actor.get_ref() if battle_actor != null else null
		if _vital_now <= 0.0 or (_state == State.S2B and actor != null and actor.player_hp <= 0):
			return State.S5
	if _vital_now <= 0.0:
		return -1
	match reason:
		&"r4_finished":
			if _state == State.S0 and event_done(&"E4"): return State.S1
		&"first_step":
			if _state == State.S1 and event_done(&"E5"): return State.S2
		&"battle_started":
			if _state == State.S2 and _p5_read: return State.S2B
		&"battle_return":
			if _state == State.S2B and event_done(&"E17"): return State.S2
		&"investigation_complete":
			if _state == State.S2 and exit_open: return State.S3
		&"exit":
			if _state == State.S3 and event_done(&"E8"): return State.S4
		&"r10_finished":
			if _state == State.S4 and event_done(&"E9"): return State.S6
	return -1

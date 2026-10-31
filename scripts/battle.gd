## SP-23：唯一一场战斗；剧情调查成功信号是唯一开战入口。
extends Control

signal battle_started
signal battle_lost
signal incoming_damage(product: float, hp: int, maximum: int)

enum State { INACTIVE, COMMAND, PLAYER_ACTION, ENEMY_ACTION, VICTORY, DEFEATED }
const KNOBS_PATH: String = "res://data/knobs.json"
const KNOB_NAMES: Array[String] = [
	"player_hp_max", "enemy_hp_max", "player_attack", "enemy_attack",
	"damage_random_min", "damage_random_max", "charge_attack_multiplier",
	"charge_received_multiplier", "guard_received_multiplier", "item_heal",
	"item_uses", "action_seconds", "attack_shift_px", "hit_shift_px",
	"feedback_seconds", "pose_scale_delta"]
const COMPONENT_TESTS: Array[String] = [
	"--sp09-self-test", "--sp11-self-test", "--sp07-self-test",
	"--sp06-self-test", "--sp03-self-test", "--sp04-self-test"]
const EPSILON: float = 1e-6

@onready var _player: Node2D = $ViewArea/PlayerAnchor
@onready var _enemy: Node2D = $ViewArea/EnemyAnchor
@onready var _status: Label = $StatusWindow/StatusText
@onready var _enemy_bar: ProgressBar = $ViewArea/EnemyHP
@onready var _return: Button = $ReturnButton
@onready var _buttons: Array[Button] = [
	$CommandWindow/MarginContainer/GridContainer/Attack,
	$CommandWindow/MarginContainer/GridContainer/Charge,
	$CommandWindow/MarginContainer/GridContainer/Guard,
	$CommandWindow/MarginContainer/GridContainer/Item]
var turn_phase: State = State.INACTIVE
var player_hp: int = 0
var enemy_hp: int = 0
var item_uses: int = 0
var turn_count: int = 0
var start_count: int = 0
var _run_id: int = -1
var elapsed: float = 0.0
var random_sample: Callable
var last_error: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _knobs: Dictionary = {}
var _valid: bool = false
var _main: Control
var _map: Control
var _points: Node
var _interactions: RefCounted
var _started: bool = false
var _settled: bool = false
var _returned: bool = false
var _return_permit: bool = false
var _charged: bool = false
var _received_multiplier: float = 1.0
var _selected: int = 0
var _status_template: String
var _origins: Dictionary = {}
var _feedback_time: float = 0.0
var _feedback_active: bool = false

func _ready() -> void:
	_status_template = _status.text
	for anchor: Node2D in [_player, _enemy]:
		_origins[anchor] = anchor.transform
	for index: int in range(_buttons.size()):
		_buttons[index].pressed.connect(submit_command.bind(index))
	_return.pressed.connect(_on_return_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_rng.randomize()
	load_configuration(JSON.parse_string(FileAccess.get_file_as_string(KNOBS_PATH)))

## 内存副本也走同一校验；正式单场一旦开始，不允许重配来重置血量。
func load_configuration(data: Variant) -> bool:
	if _started:
		return false
	last_error = validate_configuration(data)
	_valid = last_error.is_empty()
	if not _valid:
		push_error("[SP-23] %s，%s" % [last_error, KNOBS_PATH])
		_sync_controls()
		return false
	_knobs = data.duplicate(true)
	player_hp = int(_k("player_hp_max"))
	enemy_hp = int(_k("enemy_hp_max"))
	item_uses = int(_k("item_uses"))
	_prepare_animations()
	_refresh_display()
	return true

static func validate_configuration(data: Variant) -> String:
	if not data is Dictionary:
		return "战斗配置根必须是对象"
	for suffix: String in KNOB_NAMES:
		var key: String = "battle_" + suffix
		if not data.has(key):
			return "战斗配置缺少键：%s" % key
		var value: Variant = data[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return "战斗配置必须为有限数值：%s" % key
		if float(value) < 0.0:
			return "战斗配置不得为负：%s" % key
		if suffix in ["player_hp_max", "enemy_hp_max", "item_uses"] and float(value) != floorf(float(value)):
			return "战斗配置必须为整数：%s" % key
		if suffix.ends_with("hp_max") or suffix.ends_with("multiplier") or suffix.ends_with("seconds") or suffix.begins_with("damage_random"):
			if float(value) <= 0.0:
				return "战斗配置必须大于零：%s" % key
	if data["battle_damage_random_min"] > data["battle_damage_random_max"]:
		return "战斗配置随机范围倒置：battle_damage_random_min"
	if data["battle_feedback_seconds"] > data["battle_action_seconds"]:
		return "战斗反馈时长超过动作：battle_feedback_seconds"
	return ""

func _k(suffix: String) -> float:
	return float(_knobs["battle_" + suffix])

func configure(main: Control) -> void:
	if OS.get_cmdline_user_args().has("--sp23-self-test"):
		load("res://scripts/sp23_selftest.gd").start_once(main)
	_main = main
	_run_id = GameState.run_id
	_map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	_points = main.get_node_or_null("Overlay/Points")
	_interactions = _map._interactions
	if not _interactions.investigated.is_connected(_on_investigated):
		_interactions.investigated.connect(_on_investigated)

func _on_investigated(point_id: StringName) -> void:
	if _run_id != GameState.run_id or not GameState.can_investigate():
		return
	if point_id != &"point5" or _started or not _valid or GameState.vital_now <= 0.0:
		return
	if _main == null or _main._current_page != &"MapPage" or _points == null:
		return
	if _map.get_current_node_id() != &"point5" or not _map.get_interactable(point_id).read:
		return
	if _points.get_dialogue().is_playing():
		return
	_started = true
	start_count += 1
	turn_phase = State.COMMAND
	if not GameState.request_transition(&"battle_started", _run_id):
		_started = false
		start_count -= 1
		turn_phase = State.INACTIVE
		return
	_sync_controls(true)
	battle_started.emit()

## Main 的所有翻页入口共同经过此守卫；返回令牌在消费前就锁存。
func can_show_page(page_name: StringName) -> bool:
	if _main == null or turn_phase == State.INACTIVE:
		return true
	if page_name == &"BattlePage":
		return true
	if turn_phase == State.VICTORY and _return_permit and page_name == &"MapPage":
		_return_permit = false
		return true
	return false

func submit_command(index: int) -> void:
	if turn_phase != State.COMMAND or not _valid or not is_visible_in_tree():
		return
	if GameState.vital_now <= 0.0:
		_defeat()
		return
	if index < 0 or index >= _buttons.size() or (index == 3 and item_uses <= 0):
		return
	_selected = index
	turn_count += 1
	turn_phase = State.PLAYER_ACTION
	elapsed = 0.0
	_received_multiplier = 1.0
	var attack_multiplier: float = _k("charge_attack_multiplier") if _charged else 1.0
	_charged = index == 1
	match index:
		0:
			enemy_hp = maxi(0, enemy_hp - roundi(_k("player_attack") * _roll() * attack_multiplier))
		1:
			_received_multiplier = _k("charge_received_multiplier")
		2:
			_received_multiplier = _k("guard_received_multiplier")
		3:
			item_uses -= 1
			player_hp = mini(int(_k("player_hp_max")), player_hp + int(_k("item_heal")))
	if enemy_hp == 0:
		_settle_victory()
	else:
		_start_feedback(index, false)
	_refresh_display()

func _roll() -> float:
	if random_sample.is_valid():
		return float(random_sample.call())
	return _rng.randf_range(_k("damage_random_min"), _k("damage_random_max"))

func _process(delta: float) -> void:
	advance_time(delta)

## 可注入 delta 的唯一时钟；超长帧也只跨一个动作边界，不缓存指令。
func advance_time(delta: float) -> void:
	if not _valid or delta <= 0.0 or not is_finite(delta):
		return
	if turn_phase == State.DEFEATED:
		_advance_feedback(delta)
		return
	if turn_phase not in [State.PLAYER_ACTION, State.ENEMY_ACTION, State.VICTORY]:
		return
	if GameState.vital_now <= 0.0:
		_defeat()
		return
	elapsed += delta
	_advance_feedback(delta)
	if elapsed + EPSILON < _k("action_seconds"):
		return
	match turn_phase:
		State.PLAYER_ACTION:
			_enemy_action()
		State.ENEMY_ACTION:
			turn_phase = State.COMMAND
			elapsed = 0.0
			_sync_controls(true)
		State.VICTORY:
			elapsed = _k("action_seconds")
			_enemy.hide()
			_sync_controls()

func _enemy_action() -> void:
	turn_phase = State.ENEMY_ACTION
	elapsed = 0.0
	var product: float = _k("enemy_attack") * _roll() * _received_multiplier
	incoming_damage.emit(product, player_hp, int(_k("player_hp_max")))
	player_hp = maxi(0, player_hp - roundi(product))
	if player_hp == 0:
		_defeat()
	else:
		_start_feedback(0, true)
	_refresh_display()

func _settle_victory() -> void:
	if _settled or not _started or enemy_hp != 0 or player_hp <= 0:
		return
	_settled = true
	turn_phase = State.VICTORY
	_start_feedback(0, false)
	if GameState.vital_now > 0.0:
		GameState.on_battle_win()
		GameState.record_event(&"E17", false, _run_id)

func _defeat() -> void:
	if turn_phase == State.DEFEATED or _returned:
		return
	turn_phase = State.DEFEATED
	_settled = true
	if player_hp <= 0:
		_start_feedback(0, true)
	else:
		_reset_feedback()
	_refresh_display()
	battle_lost.emit()

func _on_return_pressed() -> void:
	if turn_phase != State.VICTORY or _returned or GameState.vital_now <= 0.0:
		return
	if elapsed + EPSILON < _k("action_seconds"):
		return
	_returned = true
	_return_permit = true
	if _main._flow.return_from_battle():
		turn_phase = State.INACTIVE
		_main._flow._on_progress(GameState.must_done, GameState.exit_open)
	_return_permit = false
	_sync_controls()

func _refresh_display() -> void:
	if _valid:
		_status.text = _status_template % [player_hp, int(_k("player_hp_max"))]
		_enemy_bar.max_value = _k("enemy_hp_max")
		_enemy_bar.value = enemy_hp
	_sync_controls()

func _sync_controls(focus_command: bool = false) -> void:
	var available: bool = _valid and turn_phase == State.COMMAND and is_visible_in_tree() and GameState.vital_now > 0.0
	for index: int in range(_buttons.size()):
		_buttons[index].disabled = not available or (index == 3 and item_uses <= 0)
	_return.visible = _valid and turn_phase == State.VICTORY and elapsed + EPSILON >= _k("action_seconds")
	_return.disabled = not _return.visible or _returned or GameState.vital_now <= 0.0
	var focused: Control = get_viewport().gui_get_focus_owner()
	var return_available: bool = not _return.disabled and _return.is_visible_in_tree()
	if focused != null and is_ancestor_of(focused) and not (return_available if focused == _return else available):
		focused.release_focus()
	if return_available and (focused == null or is_ancestor_of(focused)):
		_return.grab_focus()
	if available and focus_command:
		_buttons[0 if _buttons[_selected].disabled else _selected].grab_focus()

func _on_visibility_changed() -> void:
	_sync_controls()

## 造型与归一化轨道留在场景；仅把轨道幅度映射到配置，不依赖多边形名。
func _prepare_animations() -> void:
	for anchor: Node2D in [_player, _enemy]:
		var animator: AnimationPlayer = _animator(anchor)
		if animator == null:
			continue
		if not animator.has_meta("feedback_source"):
			animator.set_meta("feedback_source", animator.get_animation(&"feedback").duplicate(true))
		var animation: Animation = animator.get_meta("feedback_source").duplicate(true)
		for track: int in range(animation.get_track_count()):
			for key: int in range(animation.track_get_key_count(track)):
				var value: Variant = animation.track_get_key_value(track, key)
				if value is Vector2:
					value = Vector2.ONE + (value - Vector2.ONE) * _k("pose_scale_delta")
				elif value is Color:
					value.a = 1.0 - (1.0 - value.a) * _k("pose_scale_delta")
				animation.track_set_key_value(track, key, value)
		var library := AnimationLibrary.new()
		library.add_animation(&"feedback", animation)
		animator.remove_animation_library(&"")
		animator.add_animation_library(&"", library)
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func _animator(anchor: Node2D) -> AnimationPlayer:
	var animator := anchor.get_node_or_null("Visual/AnimationPlayer") as AnimationPlayer
	return animator if animator != null and animator.has_animation(&"feedback") else null

func _start_feedback(command: int, enemy_turn: bool) -> void:
	_reset_feedback()
	_feedback_active = true
	var shift := Vector2(_k("attack_shift_px"), _k("hit_shift_px"))
	var pose: float = _k("pose_scale_delta")
	if enemy_turn:
		_enemy.position.x -= shift.x
		_player.position += Vector2(-shift.x, shift.y)
	elif command == 0:
		_player.position.x += shift.x
		_enemy.position += shift
	else:
		match command:
			1: _player.scale = Vector2(1.0 + pose, 1.0 - pose)
			2: _player.scale = Vector2(1.0 - pose, 1.0 + pose)
			3: _player.scale = Vector2.ONE * (1.0 + pose)
	# 归零仍后仰；只停止外沿散收和透明闪动。
	if player_hp <= 0 or enemy_hp <= 0:
		return
	for anchor: Node2D in [_player, _enemy] if enemy_turn or command == 0 else [_player]:
		var animator: AnimationPlayer = _animator(anchor)
		if animator != null:
			animator.play(&"feedback")
			animator.advance(0.0)

func _advance_feedback(delta: float) -> void:
	if not _feedback_active:
		return
	_feedback_time += delta
	for anchor: Node2D in [_player, _enemy]:
		var animator: AnimationPlayer = _animator(anchor)
		if animator != null and animator.is_playing():
			animator.advance(delta / _k("feedback_seconds"))
	if _feedback_time + EPSILON >= _k("feedback_seconds"):
		_reset_feedback()

func _reset_feedback() -> void:
	_feedback_active = false
	_feedback_time = 0.0
	for anchor: Node2D in [_player, _enemy]:
		anchor.transform = _origins[anchor]
		var animator: AnimationPlayer = _animator(anchor)
		if animator != null and animator.assigned_animation == &"feedback":
			animator.seek(1.0, true)
			animator.stop(true)

func _exit_tree() -> void:
	if _interactions != null and _interactions.investigated.is_connected(_on_investigated):
		_interactions.investigated.disconnect(_on_investigated)
	for index: int in range(_buttons.size()):
		var callback: Callable = submit_command.bind(index)
		if _buttons[index].pressed.is_connected(callback):
			_buttons[index].pressed.disconnect(callback)
	if _return.pressed.is_connected(_on_return_pressed):
		_return.pressed.disconnect(_on_return_pressed)
	if visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.disconnect(_on_visibility_changed)
	random_sample = Callable()
	_reset_feedback()

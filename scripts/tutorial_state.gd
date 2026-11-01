## 四类教学的只读呈现；三面永久旗只由GameState保存。
extends Node
signal hint_shown(kind: StringName, text: String)
## 时间与样式集中定义，不改变玩法旋钮。
const FOCUS_DWELL_SECONDS: float = 0.5
const HINT_SECONDS: float = 3.0
const HINT_FONT_SIZE: int = 20
const HINT_MAX_HEIGHT: float = 32.0
const INVESTIGATION: String = "停在这里，按一下确认"
const VITAL: String = "调查会消耗嗓子条"
const HELP: Dictionary = {1: "下次攻击更强，受伤更多", 2: "本轮受到的伤害减半", 3: "用一份药恢复生命"}
static var _test_started: bool = false
var main: Control
var map: Control
var points: Node
var map_page: Control
var actor: Control
var map_slot: Label
var battle_slot: Label
var map_pending: Dictionary = {}
var battle_pending: Dictionary = {}
var map_elapsed: float = 0.0
var map_epoch: int = 0
var _map_kind: StringName = &""
var _map_point: StringName = &""
var _last_vital: float = 0.0
var _run: int = -1
var _window_run: int = -1
var _seen: Dictionary = {}
var _hover: int = -1
var _buttons: Array[Button] = []
var _connections: Array = []

func configure(host: Control) -> void:
	name = &"TutorialHints"
	main = host
	map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	map_page = main.get_node("Pages/MapPage")
	points = main.get_node("Overlay/Points")
	map_slot = _label(&"MapHintSlot")
	battle_slot = _label(&"BattleHintSlot")
	if not GameState.tutorial_loaded:
		GameState.import_tutorial(main._flow.checkpoint.read_saved().get("tutorial", {}))
	_last_vital = GameState.vital_now
	map.moved.connect(_on_moved)
	map_page.visibility_changed.connect(_map_visibility)
	GameState.vital_changed.connect(_vital_changed)
	GameState.state_changed.connect(_state_changed)
	_sync_session()
	_bind_actor()
	if OS.get_cmdline_user_args().has("--sp16-self-test") and not _test_started:
		_test_started = true
		call_deferred("_run_test")

func _label(id: StringName) -> Label:
	var label := Label.new()
	label.name = id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.add_theme_font_override("font", preload("res://assets/fonts/simkai.ttf"))
	label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	label.add_theme_color_override("font_color", Color("443b2c"))
	label.z_index = 20
	add_child(label)
	label.hide()
	return label

func _owned() -> bool:
	return is_instance_valid(main) and main.is_inside_tree() and main.can_process() \
		and is_instance_valid(main._flow) and main._flow.has_method("_present") \
		and GameState.presenter == Callable(main._flow, "_present")

func _process(delta: float) -> void:
	advance_time(delta)

func advance_time(delta: float) -> void:
	if not _owned():
		return
	_sync_session()
	_bind_actor()
	_layout()
	_refresh_map()
	if map_slot.visible:
		map_elapsed += maxf(0.0, delta)
		if map_elapsed + 0.000001 >= HINT_SECONDS:
			_clear_map()
	_tick_battle(maxf(0.0, delta))

func _layout() -> void:
	var area: Vector2 = main.size
	map_slot.position = area * Vector2(0.05, 0.43)
	battle_slot.position = area * Vector2(0.05, 0.51)
	for label: Label in [map_slot, battle_slot]:
		label.size = Vector2(area.x * 0.65, HINT_MAX_HEIGHT)

func _sync_session() -> void:
	if _run == GameState.run_id:
		return
	_run = GameState.run_id
	_last_vital = GameState.vital_now
	_window_run = -1
	_seen.clear()
	_clear_map()
	_clear_battle()

func _map_active() -> bool:
	if not _owned() or GameState.state != GameState.State.S2 or not GameState.can_investigate():
		return false
	return map_page.is_visible_in_tree() and not points.get_dialogue().is_playing() \
		and not (main._dialogue.is_playing() and main._dialogue.get_current_mode() != "caption")

func _refresh_map() -> void:
	if not _map_active():
		if not map_pending.is_empty() and GameState.state == GameState.State.S2:
			return
		_clear_map()
		return
	var id: StringName = map.get_current_node_id()
	if _map_kind == &"investigation" and id != _map_point:
		_clear_map()
	if GameState.tutorial_seen["investigation"] or not map_pending.is_empty():
		return
	var item: Control = map.get_interactable(id)
	if item != null and not item.read and map.get_revealed_ids().has(id):
		_show_map(&"investigation", INVESTIGATION)

func _show_map(kind: StringName, text: String) -> void:
	if not _map_active() or not GameState.claim_tutorial(str(kind), _run):
		return
	_layout()
	map_pending.clear()
	_map_kind = kind
	_map_point = map.get_current_node_id()
	map_elapsed = 0.0
	map_slot.text = text
	map_slot.show()
	hint_shown.emit(kind, text)

func _on_moved(_from: StringName, _to: StringName, _steps: int) -> void:
	if _owned():
		call_deferred("_refresh_map")

func _vital_changed(value: float, _maximum: float, reason: StringName) -> void:
	var before: float = _last_vital
	_last_vital = value
	if not _owned() or GameState.state != GameState.State.S2 or GameState.tutorial_seen["vital"]:
		return
	if reason not in [&"point_required", &"point_optional"] or value <= 0.0 or value >= before:
		return
	var item: Control = map.get_interactable(map.get_current_node_id())
	if item == null or not map_page.is_visible_in_tree():
		return
	map_pending = {"item": weakref(item), "run": GameState.run_id, "epoch": map_epoch}
	call_deferred("_flush_vital", map_epoch, GameState.run_id)

func _flush_vital(epoch: int, session: int) -> void:
	if epoch != map_epoch or session != GameState.run_id or map_pending.is_empty():
		return
	var item: Control = map_pending.item.get_ref()
	map_pending.clear()
	if is_instance_valid(item) and item.read and _map_active():
		_show_map(&"vital", VITAL)

func _map_visibility() -> void:
	if not map_page.is_visible_in_tree():
		_clear_map()

func _state_changed(_from: int, target: int, _reason: StringName, _session: int) -> void:
	if not _owned():
		return
	_sync_session()
	if target != GameState.State.S2:
		_clear_map()
	if target != GameState.State.S2B:
		_clear_battle()
	_bind_actor()

func _clear_map() -> void:
	map_epoch += 1
	map_pending.clear()
	map_elapsed = 0.0
	_map_kind = &""
	if is_instance_valid(map_slot):
		map_slot.text = ""
		map_slot.hide()

func _bind_actor() -> void:
	var next: Control = main.get_node_or_null("Pages/BattlePage")
	if actor == next and is_instance_valid(actor):
		return
	_disconnect_actor()
	actor = next
	_window_run = -1
	_hover = -1
	_clear_battle()
	_seen.clear()
	if actor == null:
		return
	_buttons.assign(actor._buttons)
	_link(actor.battle_started, _battle_started)
	_link(actor.visibility_changed, _battle_visibility)
	for index: int in range(_buttons.size()):
		_link(_buttons[index].focus_entered, _focused.bind(index))
		_link(_buttons[index].focus_exited, _focus_left.bind(index))
		_link(_buttons[index].mouse_entered, _mouse_entered.bind(index))
		_link(_buttons[index].mouse_exited, _mouse_left.bind(index))
	if actor.start_count > 0:
		_battle_started()

func _link(event: Signal, callback: Callable) -> void:
	event.connect(callback)
	_connections.append([event, callback])

func _disconnect_actor() -> void:
	for pair: Array in _connections:
		var event: Signal = pair[0]
		if is_instance_valid(event.get_object()) and event.is_connected(pair[1]):
			event.disconnect(pair[1])
	_connections.clear()
	_buttons.clear()

func _battle_started() -> void:
	if not _owned() or not is_instance_valid(actor) or not actor.is_visible_in_tree():
		return
	_sync_session()
	if GameState.state == GameState.State.S2B and actor.turn_phase == actor.State.COMMAND:
		if GameState.claim_tutorial("battle", _run):
			_window_run = _run

func _command_active(index: int) -> bool:
	return _owned() and is_instance_valid(actor) and _window_run == GameState.run_id \
		and GameState.state == GameState.State.S2B and actor.is_visible_in_tree() \
		and actor.turn_phase == actor.State.COMMAND and index >= 1 and index <= 3 \
		and not _buttons[index].disabled

func _focused(index: int) -> void:
	if _hover == index:
		return
	_hover = -1
	_clear_battle()
	if _command_active(index) and not _seen.has(index):
		battle_pending = {"index": index, "mouse": false, "dwell": 0.0, "shown": 0.0}

func _focus_left(index: int) -> void:
	if battle_pending.get("index", -1) == index and not battle_pending.get("mouse", false):
		_clear_battle()

func _mouse_entered(index: int) -> void:
	_hover = index
	_clear_battle()
	if _command_active(index) and not _seen.has(index):
		battle_pending = {"index": index, "mouse": true, "dwell": 0.0, "shown": 0.0}
		_show_battle(index)

func _mouse_left(index: int) -> void:
	if _hover == index:
		_hover = -1
	if battle_pending.get("index", -1) == index:
		_clear_battle()

func _tick_battle(delta: float) -> void:
	if battle_pending.is_empty():
		return
	var index: int = battle_pending.index
	if not _command_active(index):
		_clear_battle()
		return
	if battle_slot.visible:
		battle_pending.shown += delta
		if battle_pending.shown + 0.000001 >= HINT_SECONDS:
			_clear_battle()
	elif not battle_pending.mouse:
		if main.get_viewport().gui_get_focus_owner() != _buttons[index]:
			_clear_battle()
			return
		battle_pending.dwell += delta
		if battle_pending.dwell + 0.000001 >= FOCUS_DWELL_SECONDS:
			_show_battle(index)

func _show_battle(index: int) -> void:
	_layout()
	_seen[index] = true
	battle_slot.text = HELP[index]
	battle_slot.show()
	battle_pending.shown = 0.0
	hint_shown.emit(&"battle", battle_slot.text)

func _battle_visibility() -> void:
	if not actor.is_visible_in_tree():
		_hover = -1
		_clear_battle()

func _clear_battle() -> void:
	battle_pending.clear()
	if is_instance_valid(battle_slot):
		battle_slot.text = ""
		battle_slot.hide()

func _exit_tree() -> void:
	_disconnect_actor()
	for pair: Array in [[GameState.vital_changed, _vital_changed], [GameState.state_changed, _state_changed],
		[map.moved, _on_moved], [map_page.visibility_changed, _map_visibility]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func _run_test() -> void:
	var failures: int = await load("res://scripts/sp16_selftest.gd").new().run(main)
	get_tree().quit(0 if failures == 0 else 1)

## 显式域夹具；不在生产分支中按自检参数放宽守卫。
extends RefCounted
const S = preload("res://scripts/gamestate.gd").State
const ROUTE: Array[StringName] = [&"c1", &"point1", &"point2", &"point3", &"point4", &"point5"]
var main: Control
var map: Control
var battle: Control
var points: Node
var flow: Node
var saved: Dictionary
var root: Control
var original_mode: int
var original_visible: bool
var process_before: bool
var focus: WeakRef
var connections: Dictionary = {}
var watched: Array = []
var events: Array = []
var transitions: Array = []
var restored: bool = false
var _component_connections: Array = []
var _component_interactions: RefCounted
var _investigation_before: Callable

func remember(host: Control) -> void:
	root = host
	saved = GameState.capture_session()
	process_before = GameState.is_processing()
	original_visible = root.visible
	original_mode = root.process_mode
	var owner: Control = root.get_viewport().gui_get_focus_owner()
	focus = weakref(owner) if owner != null else null
	for id: StringName in [&"vital_changed", &"progress_changed", &"state_changed", &"event_changed"]:
		connections[id] = GameState.get_signal_connection_list(id)

func create(host: Control, initial: int = S.S0) -> void:
	remember(host)
	root.hide()
	root.process_mode = Node.PROCESS_MODE_DISABLED
	main = load("res://scenes/Main.tscn").instantiate()
	root.get_tree().root.add_child(main)
	attach(main)
	GameState.set_process(false)
	battle.set_process(false)
	main._dialogue.set_process(false)
	if initial != S.S0:
		enter_domain(main, initial)
	watch(GameState.event_changed, _event)
	watch(GameState.state_changed, _transition)
	await main._wait_for_layout()

func attach(host: Control) -> void:
	main = host
	flow = main._flow
	map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	battle = main.get_node("Pages/BattlePage")
	points = main.get_node("Overlay/Points")

static func enter_domain(host: Control, initial: int = S.S2) -> void:
	var director: Node = host.get_meta("production_flow", host._flow)
	director._sequence_event = &""
	host._dialogue._set_active(false)
	GameState.begin_session(initial)
	GameState.presenter = director._present
	if host._dialogue._s0 != null:
		host._dialogue._s0._run_id = GameState.run_id
	host.get_node("Pages/BattlePage")._run_id = GameState.run_id
	GameState.battle_actor = weakref(host.get_node("Pages/BattlePage"))
	director._present(initial)
	GameState.set_process(false)

func watch(event: Signal, callback: Callable) -> void:
	event.connect(callback)
	watched.append([event, callback])

func _event(id: StringName, complete: bool, session: int) -> void:
	events.append([id, complete, session])

func _transition(from: int, to: int, reason: StringName, session: int) -> void:
	transitions.append([from, to, reason, session, main._current_page,
		GameState.is_frozen(), map.get_current_node_id(), main._dialogue.get_current_key()])

func event_count(id: StringName, complete: bool = true) -> int:
	return events.filter(func(row: Array): return row[0] == id and row[1] == complete).size()

func finish_sequence(player: Control) -> void:
	var keys: Array = player._keys.duplicate()
	for index: int in range(keys.size() + 1):
		if not player.is_playing() or player._keys != keys:
			break
		player.finish_text()
		if player.get_current_mode() == "read":
			player.advance()
		else:
			player.advance_time(100.0)

func read_point() -> bool:
	var ok: bool = map.confirm_selection()
	finish_sequence(points.get_dialogue())
	return ok

func walk(route: Array) -> bool:
	for id: StringName in route:
		if not map.try_move_to(id):
			return false
	return true

func walk_to(target: StringName) -> bool:
	var start: StringName = map.get_current_node_id()
	var queue: Array[StringName] = [start]
	var previous: Dictionary = {start: &""}
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		if current == target:
			break
		for value: Variant in map._points[current]["edges"]:
			var next: StringName = StringName(value)
			if not previous.has(next):
				previous[next] = current
				queue.append(next)
	if not previous.has(target):
		return false
	var route: Array = []
	while target != start:
		route.push_front(target)
		target = previous[target]
	return walk(route)

func read_first(count: int = 5) -> void:
	map.try_move_to(&"c1")
	for number: int in range(1, count + 1):
		map.try_move_to(StringName("point%d" % number))
		read_point()

func win() -> void:
	battle.random_sample = func(): return 1.0
	for turn: int in range(5):
		battle.submit_command(0)
		battle.advance_time(0.4)
		battle.advance_time(0.4)

func return_battle() -> void:
	battle._on_return_pressed()

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	main.get_viewport().push_input(event)

func click(control: Control) -> void:
	main.get_viewport().gui_release_focus()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		main.get_viewport().push_input(event, true)

func replace_battle() -> Control:
	var old: Control = battle
	main.get_node("Pages").remove_child(old)
	battle = load("res://scenes/ui/BattlePage.tscn").instantiate()
	main.get_node("Pages").add_child(battle)
	main._pages[&"BattlePage"] = battle
	battle.configure(main)
	battle.set_process(false)
	old.free()
	map.reset_map()
	GameState.vital_now = 100.0
	return battle

func close() -> bool:
	for pair: Array in watched:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	watched.clear()
	main.queue_free()
	await root.get_tree().process_frame
	return restore()

func restore() -> bool:
	var components_restored: bool = _restore_component_callbacks()
	if root.has_meta("production_flow"):
		root._flow.queue_free()
		root._flow = root.get_meta("production_flow")
		root.remove_meta("production_flow")
	GameState.begin_session(S.S0, saved)
	GameState.set_process(process_before)
	root.process_mode = original_mode
	root.visible = original_visible
	root.get_viewport().gui_release_focus()
	var owner: Control = focus.get_ref() if focus != null else null
	if is_instance_valid(owner) and owner.is_visible_in_tree() and owner.focus_mode != Control.FOCUS_NONE:
		owner.grab_focus()
	restored = components_restored and GameState.capture_session() == saved and GameState.is_processing() == process_before
	for id: StringName in connections:
		restored = restored and connections[id] == GameState.get_signal_connection_list(id)
	return restored and root.get_viewport().gui_get_focus_owner() == owner

## 只由组件夹具记录它即将替换的接线；普通新实例夹具没有这些恢复项。
func _remember_component_callbacks(nav: Control) -> void:
	_component_interactions = map._interactions
	_investigation_before = _component_interactions.request_investigation
	for event: Signal in [nav.reading_requested, _component_interactions.investigated]:
		_component_connections.append([event, event.get_connections()])

func _restore_component_callbacks() -> bool:
	if _component_connections.is_empty():
		return true
	if not is_instance_valid(_component_interactions):
		return false
	_component_interactions.request_investigation = _investigation_before
	var matched: bool = _component_interactions.request_investigation == _investigation_before
	for binding: Array in _component_connections:
		var event: Signal = binding[0]
		if not is_instance_valid(event.get_object()):
			return false
		for connection: Dictionary in event.get_connections():
			event.disconnect(connection.callable)
		for connection: Dictionary in binding[1]:
			event.connect(connection.callable, connection.flags)
		matched = matched and event.get_connections() == binding[1]
	return matched

static func component_scope(host: Control, initial: int = S.S2, renderer: bool = false, legacy_map: bool = true):
	var scope = load("res://scripts/prologue_test_context.gd").new()
	scope.remember(host)
	scope.attach(host)
	enter_domain(host, initial)
	var nav: Control = host.get_node("Pages/ScenePage/PageNav")
	scope._remember_component_callbacks(nav)
	nav.reading_requested.disconnect(host._dialogue._s0._on_read_requested)
	nav.reading_requested.connect(host._dialogue._s0._placeholder)
	if initial == S.S0:
		GameState.record_event(&"E1", true)
		host._flow.content.present(initial)
	if legacy_map:
		scope.map._interactions.request_investigation = Callable()
	var callback := Callable(scope.battle, "_on_investigated")
	if scope.map._interactions.investigated.is_connected(callback):
		scope.map._interactions.investigated.disconnect(callback)
	if renderer:
		host.set_meta("production_flow", host._flow)
		var adapter := RenderOnly.new()
		adapter.host = host
		host.add_child(adapter)
		host._flow = adapter
	return scope

class RenderOnly extends Node:
	var host: Control
	var presenting: bool = true
	func request_page(page: StringName) -> bool:
		return host.show_page(page)

## P2 对应自检辅助，固定期望与真实事件；不在生产路径加入测试分支。
extends RefCounted
const CONTEXT = preload("res://scripts/prologue_test_context.gd")
const DATA = preload("res://scripts/map_data.gd")
const POINTS = preload("res://scripts/points.gd")

class InputWitness extends Node:
	var seen: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			seen += 1

static func component_callbacks(host: Control, check: Callable) -> void:
	var nav: Control = host.get_node("Pages/ScenePage/PageNav")
	var map: Control = host.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	var battle: Control = host.get_node("Pages/BattlePage")
	var before: Array = [nav.reading_requested.get_connections(), map._interactions.request_investigation, map._interactions.investigated.get_connections()]
	var production: bool = nav.reading_requested.is_connected(host._dialogue._s0._on_read_requested) and before[1].is_valid() and map._interactions.investigated.is_connected(battle._on_investigated)
	var scope = CONTEXT.component_scope(host)
	var replaced: bool = nav.reading_requested.is_connected(host._dialogue._s0._placeholder) and not map._interactions.request_investigation.is_valid() and not map._interactions.investigated.is_connected(battle._on_investigated)
	var restored: bool = scope.restore()
	var after: Array = [nav.reading_requested.get_connections(), map._interactions.request_investigation, map._interactions.investigated.get_connections()]
	check.call(production and replaced and restored and before == after, "restore_restores_component_callbacks production=%s replaced=%s restore=%s equal=%s" % [production, replaced, restored, before == after])

static func hidden_map_ignores_keys(map: Control) -> bool:
	var host: Control = map.get_tree().current_scene
	var witness := InputWitness.new()
	host.add_child(witness)
	var modes: Array = _isolate_input(host, map, witness)
	var owner: Control = host.get_viewport().gui_get_focus_owner()
	host.get_viewport().gui_release_focus()
	var before: Array = [map.get_current_node_id(), map.get_step_count(), GameState.vital_now, map.get_pending_node_id()]
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_DOWN
		event.pressed = pressed
		map.get_viewport().push_input(event)
	var unchanged: bool = before == [map.get_current_node_id(), map.get_step_count(), GameState.vital_now, map.get_pending_node_id()]
	var passed: bool = not map.is_visible_in_tree() and unchanged and witness.seen == 2
	for entry: Array in modes:
		entry[0].set_process_input(entry[1])
		entry[0].set_process_unhandled_key_input(entry[2])
		entry[0].set_process_unhandled_input(entry[3])
		entry[0].set_process_shortcut_input(entry[4])
	if is_instance_valid(owner) and owner.is_visible_in_tree():
		owner.grab_focus()
	witness.free()
	return passed

static func _isolate_input(host: Control, map: Control, witness: Node) -> Array:
	var nodes: Array[Node] = [host]
	nodes.append_array(host.find_children("*", "", true, false))
	var modes: Array = []
	for node: Node in nodes:
		if node == map or node == witness:
			continue
		modes.append([node, node.is_processing_input(), node.is_processing_unhandled_key_input(), node.is_processing_unhandled_input(), node.is_processing_shortcut_input()])
		node.set_process_input(false)
		node.set_process_unhandled_key_input(false)
		node.set_process_unhandled_input(false)
		node.set_process_shortcut_input(false)
	return modes

static func re_register_callbacks(host: Control, check: Callable) -> void:
	var nav: Control = host.get_node("Pages/ScenePage/PageNav")
	var previous: StringName = host._current_page
	var reading: bool = nav.reading
	host.show_page(&"ScenePage")
	nav.reading = false
	var first := Control.new()
	var second := Control.new()
	nav._scope.add_child(first)
	nav._scope.add_child(second)
	nav.register_selectable(first)
	nav.register_selectable(second)
	nav.unregister_selectable(first)
	var released: bool = not nav._outlines.has(first.get_instance_id())
	nav.register_selectable(first)
	var calls: Array = []
	var callback := func(node: Control): calls.append(node)
	var confirmed_before: Array = nav.confirmed.get_connections()
	for connection: Dictionary in confirmed_before:
		nav.confirmed.disconnect(connection.callable)
	nav.confirmed.connect(callback)
	nav._select(second)
	first.mouse_entered.emit()
	var hovered: bool = nav.get_selected() == first
	nav._select(second)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	first.gui_input.emit(click)
	var rewired: bool = released and hovered and nav.get_selected() == first and calls == [first] and first.resized.is_connected(nav._on_layout_changed) and first.visibility_changed.is_connected(nav._on_candidate_visibility_changed.bind(first))
	nav.confirmed.disconnect(callback)
	for connection: Dictionary in confirmed_before:
		nav.confirmed.connect(connection.callable, connection.flags)
	first.free()
	second.free()
	nav.refresh_candidates()
	nav.reading = reading
	host.show_page(previous)
	check.call(rewired, "re_register_rewires_callbacks released=%s hover=%s clicks=%d" % [released, hovered, calls.size()])

static func point_costs(host: Control, check: Callable) -> void:
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/points.json"))
	var lines: Dictionary = host._dialogue.get_lines()
	var knobs: Dictionary = GameState._knobs.duplicate(true)
	var vital: float = GameState.vital_now
	var frozen: bool = GameState.is_frozen()
	var calls: int = GameState.get_point_pay_call_count()
	var changed: Array = raw.duplicate(true)
	GameState._knobs["required_point_cost"] = 5.0
	GameState._knobs["optional_point_cost"] = 5.0
	for entry: Dictionary in changed:
		entry["cost"] = 5.0
	var validation: bool = POINTS.validate_data(changed, lines).is_empty() and not POINTS.validate_data(raw, lines).is_empty()
	GameState.set_frozen(false)
	GameState.vital_now = 100.0
	var paid: bool = GameState.pay_point(&"required") and GameState.vital_now == 95.0
	paid = GameState.pay_point(&"optional") and GameState.vital_now == 90.0 and paid
	GameState._knobs = knobs
	GameState.vital_now = vital
	GameState.set_frozen(frozen)
	GameState._point_pay_calls = calls
	check.call(validation and paid and POINTS.validate_data(raw, lines).is_empty(), "point_cost_matches_knobs cost=5 required=95 optional=90 original_restored=true")

static func map_validation(map: Control, check: Callable) -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map.json"))
	_bad_containers(source, map, check)
	_bad_coordinates(source, map, check)
	var integral: Dictionary = source.duplicate(true)
	integral["grid_size"] = [5.0, 5.0]
	integral["points"][0]["grid"] = [0.0, 0.0]
	var normalized = DATA.from_dictionary(integral)
	var loaded: bool = map.load_map_for_test(integral)
	var used: Array = map._points[&"entry_exit"]["grid"]
	var center: Vector2 = map.get_point_position_for_test(&"entry_exit")
	var pitch: float = minf(map.size.x / 5.0, map.size.y / 5.0)
	var expected: Vector2 = map.size * 0.5 - Vector2.ONE * (pitch * 2.0)
	check.call(loaded and normalized != null and used == normalized.points[&"entry_exit"]["grid"] and used[0] is int and used[1] is int and center.is_equal_approx(expected) and integral["points"][0]["grid"][0] is float, "map_normalized_coordinates_used_for_draw integers=true raw_unchanged=true")
	map.load_map_for_test(source)

static func _bad_containers(source: Dictionary, map: Control, check: Callable) -> void:
	var rejected: bool = true
	for root: Variant in [null, [], "map"]:
		rejected = not DATA.validate_dictionary(root) and rejected
	var count: int = 3
	for field: String in ["points", "grid_size", "visual"]:
		for value: Variant in [null, "invalid", 5]:
			var raw: Dictionary = source.duplicate(true)
			raw[field] = value
			rejected = not DATA.validate_dictionary(raw) and not map.load_map_for_test(raw) and rejected
			count += 1
	var raw: Dictionary = source.duplicate(true)
	raw["points"] = [null]
	rejected = not DATA.validate_dictionary(raw) and not map.load_map_for_test(raw) and rejected
	check.call(rejected, "map_rejects_invalid_containers cases=%d null_points_safe=true" % (count + 1))

static func _bad_coordinates(source: Dictionary, map: Control, check: Callable) -> void:
	var failures: Array[String] = []
	for pair: Array in [["grid_size", [0, 5]], ["grid_size", [2.5, 5]], ["grid_size", [2147483648, 5]], ["grid_size", [true, 5]], ["grid_size", ["5", 5]], ["grid_size", [INF, 5]], ["grid_size", [NAN, 5]], ["grid", [-0.5, 0]], ["grid", [0.5, 0]], ["grid", [5, 0]], ["grid", [-1, 0]], ["grid", [true, 0]], ["grid", ["0", 0]], ["grid", [INF, 0]], ["grid", [NAN, 0]], ["grid", null], ["grid", [0]], ["grid", [0, 0, 0]]]:
		var raw: Dictionary = source.duplicate(true)
		if pair[0] == "grid":
			raw["points"][0]["grid"] = pair[1]
		else:
			raw["grid_size"] = pair[1]
		var rejected: bool = not DATA.validate_dictionary(raw)
		rejected = not map.load_map_for_test(raw) and rejected
		if not rejected:
			failures.append(str(pair))
	check.call(failures.is_empty(), "map_rejects_bad_coordinates cases=18 accepted=%s" % [failures])

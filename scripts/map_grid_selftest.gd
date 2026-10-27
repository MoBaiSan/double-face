extends RefCounted

var _map: Node
var _failures: int = 0
var _vital_signal_count: int = 0
const MAP_DATA_SCRIPT = preload("res://scripts/map_data.gd")


## 在显式自测参数下加载拆分后的断言模块，并把失败数映射为进程退出码。
func run(map: Node) -> int:
	_map = map
	if not GameState.vital_changed.is_connected(_on_test_vital_changed):
		GameState.vital_changed.connect(_on_test_vital_changed)
	_prepare_map_state()
	_test_task_guards()
	_test_initial_layout_and_input()
	_test_hover_and_invalid_clicks()
	_test_dead_end()
	_test_round_trip()
	_test_balance_guards()
	_test_epsilon_boundaries()
	_test_corner_labels()
	print("[SP-06] failures=%d" % _failures)
	return _failures


func _prepare_map_state() -> void:
	GameState.set_process(false)
	GameState.set_frozen(true)
	GameState.set_frozen(false)
	GameState.vital_now = GameState.vital_max
	_map.reset_map()


func _test_task_guards() -> void:
	_check(_map.is_playable_for_test() and _map.get_start_id_for_test() == &"entry_exit",
		"C1 start_id_loaded playable=true")
	var base: Dictionary = {"grid_size": [2, 2], "start_id": "a", "points": [{"id": "a", "display_name": "a", "grid": [0, 0], "color": "plain", "surveyable": false, "survey_kind": "none", "edges": []}]}
	var missing: Dictionary = base.duplicate(true)
	missing.erase("start_id")
	_check(not MAP_DATA_SCRIPT.validate_dictionary(missing), "C2 missing_required rejected=true")
	var duplicate: Dictionary = base.duplicate(true)
	duplicate["points"].append((base["points"] as Array)[0].duplicate(true))
	_check(not MAP_DATA_SCRIPT.validate_dictionary(duplicate), "C2 duplicate_id rejected=true")
	var out_of_bounds: Dictionary = base.duplicate(true)
	(out_of_bounds["points"] as Array)[0]["grid"] = [2, 0]
	_check(not MAP_DATA_SCRIPT.validate_dictionary(out_of_bounds), "C2 grid_bounds rejected=true")
	var map_page: Control = _map.get_parent().get_parent().get_parent() as Control
	var was_visible: bool = map_page.visible
	map_page.visible = true
	_check(_map.is_processing() and _map.is_processing_unhandled_input(), "C3 visible_processing enabled=true")
	map_page.visible = false
	_check(not _map.is_processing() and not _map.is_processing_unhandled_input(), "C3 hidden_processing disabled=true")
	map_page.visible = was_visible
	var scene_page: Control = map_page.get_parent().get_node("ScenePage") as Control
	var nav: Control = scene_page.get_node("PageNav") as Control
	var before: int = nav.get_candidates().size()
	var temp := Control.new()
	temp.add_to_group("selectable")
	scene_page.add_child(temp)
	nav.refresh_candidates()
	var added: int = nav.get_candidates().size()
	temp.visible = false
	nav.refresh_candidates()
	var hidden: int = nav.get_candidates().size()
	temp.free()
	nav.refresh_candidates()
	_check(added == before + 1 and hidden == before,
		"C4 on_demand_refresh node_visibility=true before=%d added=%d hidden=%d processing=%s" % [before, added, hidden, nav.is_processing()])
	_map.reset_map()
	var blank: Vector2 = Vector2.ZERO
	var target: Vector2 = _map.get_point_position_for_test(&"c1")
	_check(not _map.is_map_click_target_for_test(blank) and _map.is_map_click_target_for_test(target),
		"C5 click_hit_only revealed_adjacent=true")


func _test_initial_layout_and_input() -> void:
	var revealed: Array[StringName] = _map.get_revealed_ids()
	_check(_same_ids(revealed, [&"c1", &"entry_exit"]),
		"initial_visible expected=2 actual=%d" % revealed.size())
	_check(_map.should_draw_outline_for_test(&"point5"),
		"white_point_outline expected=true actual=%s" % _map.should_draw_outline_for_test(&"point5"))
	var map_area: Control = _map.get_parent().get_parent() as Control
	var viewport_height: float = _map.get_viewport_rect().size.y
	var map_area_below: bool = map_area != null \
		and map_area.get_global_rect().position.y >= viewport_height * 0.48 \
		and _map.visible_points_inside_map_area()
	_check(map_area_below, "map_area_below_narration expected=true actual=%s" % map_area_below)
	var horizontal_pitch: float = abs(_map.get_point_position_for_test(&"point3").x - _map.get_point_position_for_test(&"point2").x)
	var vertical_pitch: float = abs(_map.get_point_position_for_test(&"point6").y - _map.get_point_position_for_test(&"point2").y)
	_check(abs(horizontal_pitch - vertical_pitch) <= 0.5,
		"grid_square_pitch expected<=0.5 actual=%.3f" % abs(horizontal_pitch - vertical_pitch))
	var centered: bool = _is_grid_centered()
	_check(centered, "grid_centered expected<=1 actual=(%.3f, %.3f)" % _grid_center_delta())
	_check(not _map.is_visible_in_tree(), "hidden_map_input blocked=true")
	_test_keyboard_event_path()
	var after_c1: Array[StringName] = _map.get_revealed_ids()
	_check(_same_ids(after_c1, [&"c1", &"entry_exit", &"point1"]),
		"revealed_after_c1 exact=true actual=%s" % [after_c1])


func _is_grid_centered() -> bool:
	var ids: Array[StringName] = _map.get_point_ids()
	var min_point: Vector2 = _map.get_point_position_for_test(ids[0])
	var max_point: Vector2 = min_point
	for point_id: StringName in ids:
		var point_position: Vector2 = _map.get_point_position_for_test(point_id)
		min_point.x = min(min_point.x, point_position.x)
		min_point.y = min(min_point.y, point_position.y)
		max_point.x = max(max_point.x, point_position.x)
		max_point.y = max(max_point.y, point_position.y)
	var center_delta: Vector2 = (min_point + max_point) * 0.5 - _map.size * 0.5
	return abs(center_delta.x) <= 1.0 and abs(center_delta.y) <= 1.0


func _grid_center_delta() -> Array[float]:
	var ids: Array[StringName] = _map.get_point_ids()
	var min_point: Vector2 = _map.get_point_position_for_test(ids[0])
	var max_point: Vector2 = min_point
	for point_id: StringName in ids:
		var point_position: Vector2 = _map.get_point_position_for_test(point_id)
		min_point = min_point.min(point_position)
		max_point = max_point.max(point_position)
	var delta: Vector2 = (min_point + max_point) * 0.5 - _map.size * 0.5
	return [abs(delta.x), abs(delta.y)]


## 自检真实 unhandled_key_input 链；headless 实测 ui_accept 映射 KEY_ENTER。
func _test_keyboard_event_path() -> void:
	var map_area: Control = _map.get_parent().get_parent() as Control
	var map_page: Control = map_area.get_parent() as Control
	var scene_page: Control = map_page.get_parent().get_node("ScenePage") as Control
	var previous_map_visible: bool = map_page.visible
	var previous_scene_visible: bool = scene_page.visible
	map_page.visible = true
	scene_page.visible = false
	GameState.set_frozen(false)
	GameState.vital_now = GameState.vital_max
	_map.reset_map()
	_push_key_event(KEY_DOWN, true)
	var pending_ok: bool = _map.get_pending_node_id() == &"c1" and _map.get_current_node_id() == &"entry_exit"
	_push_key_event(KEY_DOWN, false)
	_check(pending_ok, "keyboard_event_pending target=c1")
	_push_key_event(KEY_ENTER, true)
	var moved_ok: bool = _map.get_current_node_id() == &"c1" and _map.get_step_count() == 1
	_push_key_event(KEY_ENTER, false)
	_check(moved_ok, "keyboard_event_confirm_move current=c1 steps=1")
	map_page.visible = previous_map_visible
	scene_page.visible = previous_scene_visible


func _push_key_event(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	_map.get_viewport().push_input(event)


func _test_hover_and_invalid_clicks() -> void:
	GameState.vital_now = GameState.vital_max
	_map.reset_map()
	for target: StringName in [&"c1", &"point1", &"point2", &"point6", &"d1", &"point6", &"point2", &"point1"]:
		_map.try_move_to(target)
	_map.set_hover_for_test(_map.get_point_position_for_test(&"point2"))
	_check(_map.get_hovered_node_id() == &"point2", "hover_adjacent id=point2")
	_map.set_hover_for_test(_map.get_point_position_for_test(&"point1"))
	_check(_map.get_hovered_node_id() == &"", "hover_current empty=true")
	_map.set_hover_for_test(_map.get_point_position_for_test(&"point6"))
	_check(_map.get_hovered_node_id() == &"", "hover_non_adjacent empty=true")
	_map.set_hover_for_test(_map.get_point_position_for_test(&"point5"))
	_check(_map.get_hovered_node_id() == &"", "hover_unrevealed empty=true")
	var before: float = GameState.vital_now
	var current_before: StringName = _map.get_current_node_id()
	_check(not _map.try_move_to(&"point5") and GameState.vital_now == before and _map.get_current_node_id() == current_before, "click_unrevealed no_op=true")
	_check(not _map.try_move_to(current_before) and GameState.vital_now == before, "click_current no_op=true")


func _test_dead_end() -> void:
	_map.reset_map()
	for target: StringName in [&"c1", &"point1", &"point2", &"point6"]:
		_map.try_move_to(target)
	GameState.vital_now = 99.0
	var point_calls: int = GameState.get_point_pay_call_count()
	_check(_map.try_move_to(&"d1") and is_equal_approx(GameState.vital_now, 98.0),
		"d1_step_cost expected=98.000000 actual=%.6f" % GameState.vital_now)
	var before: float = GameState.vital_now
	var confirmed: bool = _map.confirm_selection()
	var drawn_labels: Array[Dictionary] = _map.get_drawn_labels()
	var deadend_labels_ok: bool = drawn_labels.is_empty()
	for label_entry: Dictionary in drawn_labels:
		var label_text: String = str(label_entry.get("text", ""))
		deadend_labels_ok = deadend_labels_ok and not label_text.contains("没有东西")
		deadend_labels_ok = deadend_labels_ok and not label_text.contains("没有东西")
	_check(not confirmed and is_equal_approx(GameState.vital_now, before) and GameState.get_point_pay_call_count() == point_calls,
		"d1_confirm silent=true value_unchanged=true pay_point_calls=0")
	_check(deadend_labels_ok, "deadend_draws_no_text labels=%d" % drawn_labels.size())


func _test_round_trip() -> void:
	GameState.vital_now = GameState.vital_max
	_map.reset_map()
	var route: Array[StringName] = [&"c1", &"point1", &"point2", &"point3", &"point4", &"point5", &"point4", &"point3", &"point2", &"point1", &"c1", &"entry_exit"]
	for index: int in range(6):
		_map.try_move_to(route[index])
	_check(_map.get_current_node_id() == &"point5" and _map.get_step_count() == 6, "shortest_main_route steps=6")
	for index: int in range(6, route.size()):
		_map.try_move_to(route[index])
	_check(_map.get_step_count() == 12, "shortest_round_trip steps=12")
	_check(is_equal_approx(GameState.vital_now, 88.0),
		"shortest_round_trip_vital expected=88.000000 actual=%.6f" % GameState.vital_now)


func _test_balance_guards() -> void:
	GameState.set_frozen(false)
	_map.reset_map()
	GameState.vital_now = GameState.vital_max
	_map.try_move_to(&"c1")
	var current_before: StringName = _map.get_current_node_id()
	var steps_before: int = _map.get_step_count()
	GameState.vital_now = 0.0
	var no_step: bool = not _map.try_move_to(&"point1") and _map.get_current_node_id() == current_before
	no_step = no_step and _map.get_step_count() == steps_before and is_zero_approx(GameState.vital_now)
	_check(no_step, "no_step_at_zero moved=false value=0")
	var calls_before: int = GameState.get_point_pay_call_count()
	var point_allowed: bool = GameState.pay_point(&"required")
	var no_point: bool = not point_allowed and is_zero_approx(GameState.vital_now)
	no_point = no_point and GameState.get_point_pay_call_count() == calls_before + 1
	_check(no_point, "no_point_at_zero allowed=false value=0 calls+1")
	var step_cost: float = GameState.get_knob("step_cost")
	_map.reset_map()
	GameState.vital_now = step_cost - 0.5
	var before_insufficient: float = GameState.vital_now
	var insufficient: bool = not _map.try_move_to(&"c1") and _map.get_step_count() == 0
	insufficient = insufficient and is_equal_approx(GameState.vital_now, before_insufficient)
	_check(insufficient, "no_step_when_insufficient value=%.6f" % GameState.vital_now)
	_map.reset_map()
	GameState.vital_now = step_cost
	var exact: bool = _map.try_move_to(&"c1") and _map.get_current_node_id() == &"c1"
	exact = exact and is_zero_approx(GameState.vital_now)
	_check(exact, "step_at_exact_balance moved=true value=0")


func _test_epsilon_boundaries() -> void:
	var maximum: float = GameState.vital_max
	var rate: float = GameState.get_knob("time_drain_per_second")
	var threshold: float = GameState.get_knob("drain_flush_threshold")
	GameState.set_frozen(true)
	GameState.set_frozen(false)
	GameState.vital_now = maximum
	var flush_input: float = threshold / rate + GameState.VITAL_EPSILON
	var flushes: int = 10
	for _index: int in range(flushes):
		GameState.drain_time(flush_input)
	var expected_drop: float = rate * flush_input * flushes
	var actual_drop: float = maximum - GameState.vital_now
	var flush_ok: bool = actual_drop > 0.0 and absf(actual_drop - expected_drop) <= GameState.VITAL_EPSILON
	_check(flush_ok, "epsilon_flush_not_swallowed flushes=%d drop=%.6f expected=%.6f" % [flushes, actual_drop, expected_drop])
	GameState.vital_now = maximum
	var signal_before: int = _vital_signal_count
	GameState.vital_now = maximum - GameState.VITAL_EPSILON * 0.5
	var tiny_ignored: bool = is_equal_approx(GameState.vital_now, maximum)
	tiny_ignored = tiny_ignored and _vital_signal_count == signal_before
	_check(tiny_ignored, "epsilon_ignores_tiny_change signal_delta=0 value=%.6f" % GameState.vital_now)


func _test_corner_labels() -> void:
	_map.reset_map()
	_map.try_move_to(&"c1")
	_map.try_move_to(&"point1")
	var corner_label: Label = _map.get_node("../../CurrentPointLabel") as Label
	var corner_text: String = corner_label.text
	_check(corner_text == "当前位置：点1", "corner_label_text expected=当前位置：点1 actual=%s" % corner_text)
	var map_area: Control = _map.get_parent().get_parent() as Control
	var corner_inside: bool = map_area.get_global_rect().encloses(corner_label.get_global_rect())
	_check(corner_inside, "corner_label_inside_map_area expected=true actual=%s" % corner_inside)
	_map.try_move_to(&"point2")
	_check(corner_label.text == "当前位置：点2", "corner_label_updates_on_move expected=当前位置：点2 actual=%s" % corner_label.text)


func _same_ids(actual: Array[StringName], expected: Array[StringName]) -> bool:
	if actual.size() != expected.size():
		return false
	for point_id: StringName in expected:
		if not actual.has(point_id):
			return false
	return true


func _check(passed: bool, label: String) -> void:
	print("[SP-06] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1


func _on_test_vital_changed(_value: float, _maximum: float, _reason: StringName) -> void:
	_vital_signal_count += 1

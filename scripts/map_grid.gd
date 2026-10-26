## 里侧点阵的显示与移动；调查业务由后续卡接入。
extends Control

signal moved(from_id: StringName, to_id: StringName, step_count: int)

const MAP_PATH: String = "res://data/map.json"
const START_ID: StringName = &"entry_exit"

var _points: Dictionary = {}
var _revealed: Dictionary = {}
var _current_id: StringName = START_ID
var _pending_id: StringName = &""
var _hovered_id: StringName = &""
var _step_count: int = 0
var _grid_size: Vector2 = Vector2.ONE
var _visual: Dictionary = {}
var _pulse_time: float = 0.0
var _failures: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	_load_map()
	reset_map()
	if OS.get_cmdline_user_args().has("--sp06-self-test"):
		call_deferred("_run_self_test")


func _process(delta: float) -> void:
	_pulse_time = fmod(_pulse_time + delta, _float_visual("blue_pulse_period"))
	queue_redraw()


## 将光标恢复到入口并建立初始两点揭开集合；进入里侧时调用。
func reset_map() -> void:
	_current_id = StringName(_points.get(START_ID, {}).get("id", START_ID))
	_pending_id = &""
	_hovered_id = &""
	_step_count = 0
	_revealed.clear()
	_revealed[START_ID] = true
	_reveal_neighbors(START_ID)
	queue_redraw()


## 尝试移动到指定相邻点；鼠标点击和确认键都只通过此入口。
func try_move_to(node_id: StringName) -> bool:
	if not _points.has(node_id) or not _revealed.has(node_id):
		return false
	if not _is_adjacent(_current_id, node_id):
		return false
	if not GameState.pay_step():
		return false
	var from_id: StringName = _current_id
	_current_id = node_id
	_step_count += 1
	_pending_id = &""
	_hovered_id = &""
	_reveal_neighbors(_current_id)
	moved.emit(from_id, _current_id, _step_count)
	queue_redraw()
	return true


## 读取当前光标点；地图页和无头自检只读此值。
func get_current_node_id() -> StringName:
	return _current_id


## 读取成功移动次数；回程移动同样计入。
func get_step_count() -> int:
	return _step_count


## 返回排序后的揭开集合副本，避免调用方改写内部状态。
func get_revealed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in _revealed.keys():
		ids.append(value as StringName)
	ids.sort()
	return ids


## 返回当前可走悬停点；当前点、隐藏点和非邻点都返回空。
func get_hovered_node_id() -> StringName:
	return _hovered_id


## 返回当前确认候选；没有候选时确认静默失败。
func confirm_selection() -> bool:
	if _pending_id == &"":
		return false
	return try_move_to(_pending_id)


## 根据屏幕方向选择一个相邻候选，不在此处扣步费。
func select_direction(direction: Vector2) -> bool:
	var target: StringName = _find_direction_target(direction)
	if target == &"":
		return false
	_pending_id = target
	_hovered_id = target
	queue_redraw()
	return true


func _gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_hovered_id = _hover_candidate_at(motion.position)
		queue_redraw()
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var clicked_id: StringName = _hover_candidate_at(button.position)
	if clicked_id != &"":
		try_move_to(clicked_id)
	accept_event()


func _on_mouse_exited() -> void:
	_hovered_id = &""
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var direction: Vector2 = Vector2.ZERO
	if event.is_action_pressed(&"ui_left"):
			direction = Vector2.LEFT
	elif event.is_action_pressed(&"ui_right"):
			direction = Vector2.RIGHT
	elif event.is_action_pressed(&"ui_up"):
			direction = Vector2.UP
	elif event.is_action_pressed(&"ui_down"):
			direction = Vector2.DOWN
	elif event.is_action_pressed(&"ui_accept"):
		if confirm_selection():
			get_viewport().set_input_as_handled()
		return
	else:
		return
	if select_direction(direction):
		get_viewport().set_input_as_handled()


func _load_map() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not parsed is Dictionary:
		push_error("SP-06 地图数据无法解析：%s" % MAP_PATH)
		return
	_grid_size = Vector2(parsed.get("grid_size", [1, 1])[0], parsed.get("grid_size", [1, 1])[1])
	_visual = parsed.get("visual", {}) as Dictionary
	_points.clear()
	for point_variant: Variant in parsed.get("points", []):
		var point: Dictionary = point_variant as Dictionary
		var point_id: StringName = StringName(str(point.get("id", "")))
		_points[point_id] = point


func _reveal_neighbors(node_id: StringName) -> void:
	_revealed[node_id] = true
	var point: Dictionary = _points.get(node_id, {}) as Dictionary
	for neighbor: Variant in point.get("edges", []):
		_revealed[StringName(str(neighbor))] = true


func _is_adjacent(from_id: StringName, to_id: StringName) -> bool:
	var point: Dictionary = _points.get(from_id, {}) as Dictionary
	for neighbor: Variant in point.get("edges", []):
		if StringName(str(neighbor)) == to_id:
			return true
	return false


func _find_direction_target(direction: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_score: float = -INF
	var from_position: Vector2 = _point_position(_current_id)
	var point: Dictionary = _points.get(_current_id, {}) as Dictionary
	for neighbor: Variant in point.get("edges", []):
		var candidate: StringName = StringName(str(neighbor))
		if not _revealed.has(candidate):
			continue
		var delta: Vector2 = _point_position(candidate) - from_position
		var distance: float = delta.length()
		if distance <= 0.0:
			continue
		var score: float = direction.dot(delta.normalized())
		if score > best_score and score > 0.5:
			best_score = score
			best_id = candidate
	return best_id


func _hover_candidate_at(position: Vector2) -> StringName:
	for point_id: StringName in _points.keys():
		if not _revealed.has(point_id) or not _is_adjacent(_current_id, point_id):
			continue
		if _point_position(point_id).distance_to(position) <= _float_visual("point_radius") * 1.6:
			return point_id
	return &""


func _point_position(point_id: StringName) -> Vector2:
	var point: Dictionary = _points.get(point_id, {}) as Dictionary
	var grid: Array = point.get("grid", [0, 0]) as Array
	var pitch: float = min(size.x / _grid_size.x, size.y / _grid_size.y)
	return Vector2(
		size.x * 0.5 + (float(grid[0]) - (_grid_size.x - 1.0) * 0.5) * pitch,
		size.y * 0.5 + (float(grid[1]) - (_grid_size.y - 1.0) * 0.5) * pitch)

func _float_visual(name: String) -> float:
	return float(_visual.get(name, 1.0))


func _visible_points_inside_map_area() -> bool:
	var map_area: Control = get_parent().get_parent() as Control
	if map_area == null:
		return false
	var area_rect: Rect2 = map_area.get_global_rect()
	var margin: float = _float_visual("point_radius") + _float_visual("hover_outline_px")
	for point_id: StringName in _revealed.keys():
		var center: Vector2 = get_global_transform() * _point_position(point_id)
		if center.x - margin < area_rect.position.x or center.x + margin > area_rect.end.x:
			return false
		if center.y - margin < area_rect.position.y or center.y + margin > area_rect.end.y:
			return false
	return true


func _draw() -> void:
	for point_id: StringName in _points.keys():
		var point: Dictionary = _points[point_id] as Dictionary
		if not _revealed.has(point_id):
			continue
		for neighbor_variant: Variant in point.get("edges", []):
			var neighbor_id: StringName = StringName(str(neighbor_variant))
			if not _revealed.has(neighbor_id) or str(point_id) > str(neighbor_id):
				continue
			draw_line(_point_position(point_id), _point_position(neighbor_id),
				Color(str(_visual.get("edge_color", "#8f8066"))), _float_visual("line_width"))
	for point_id: StringName in _points.keys():
		if not _revealed.has(point_id):
			continue
		_draw_point(point_id, _points[point_id] as Dictionary)


func _draw_point(point_id: StringName, point: Dictionary) -> void:
	var point_color: String = str(point.get("color", "plain"))
	var color: Color = Color(str(_visual.get("plain_color", "#9b8f78")))
	match point_color:
		"black":
			color = Color(str(_visual.get("black_color", "#443b2c")))
		"blue":
			color = Color(str(_visual.get("blue_color", "#356aa8")))
		"white":
			color = Color(str(_visual.get("white_color", "#f2ebd6")))
	var pulse: float = 0.0
	if point_id == START_ID:
		pulse = (sin(_pulse_time / _float_visual("blue_pulse_period") * TAU) + 1.0) * 0.5
		color.a = lerpf(1.0 - _float_visual("blue_pulse_amplitude"), 1.0, pulse)
	if point_id == _hovered_id:
		color = color.lightened(_float_visual("hover_brightness"))
	draw_circle(_point_position(point_id), _float_visual("point_radius"), color)
	if _should_draw_outline(point_id, point):
		var outline: Color = Color(str(_visual.get("label_color", "#443b2c")))
		var width: float = _float_visual("hover_outline_px") if point_id == _hovered_id else 1.0
		draw_arc(_point_position(point_id), _float_visual("point_radius") + width,
			0.0, TAU, 24, outline, width)
	if point_color != "plain":
		var font: Font = get_theme_font("font")
		draw_string(font, _point_position(point_id) + Vector2(16.0, 6.0),
			str(point.get("display_name", point_id)), HORIZONTAL_ALIGNMENT_LEFT, -1,
			16, Color(str(_visual.get("label_color", "#443b2c"))))


func _should_draw_outline(point_id: StringName, point: Dictionary) -> bool:
	return point_id == _current_id or point_id == _hovered_id or str(point.get("color", "plain")) == "white"


func _same_ids(actual: Array[StringName], expected: Array[StringName]) -> bool:
	if actual.size() != expected.size():
		return false
	for point_id: StringName in expected:
		if not actual.has(point_id):
			return false
	return true


func _run_self_test() -> void:
	GameState.set_process(false)
	GameState.set_frozen(true)
	GameState.set_frozen(false)
	GameState.vital_now = GameState.vital_max
	reset_map()
	_check(_same_ids(get_revealed_ids(), [&"c1", &"entry_exit"]),
		"initial_visible expected=2 actual=%d" % get_revealed_ids().size())
	var white_point: Dictionary = _points.get(&"point5", {}) as Dictionary
	_check(_should_draw_outline(&"point5", white_point),
		"white_point_outline expected=true actual=%s" % _should_draw_outline(&"point5", white_point))
	var map_area: Control = get_parent().get_parent() as Control
	var viewport_height: float = get_viewport_rect().size.y
	var map_area_below: bool = map_area != null \
		and map_area.get_global_rect().position.y >= viewport_height * 0.48 \
		and _visible_points_inside_map_area()
	_check(map_area_below, "map_area_below_narration expected=true actual=%s" % map_area_below)
	var horizontal_pitch: float = abs(_point_position(&"point3").x - _point_position(&"point2").x)
	var vertical_pitch: float = abs(_point_position(&"point6").y - _point_position(&"point2").y)
	var pitch_delta: float = abs(horizontal_pitch - vertical_pitch)
	_check(pitch_delta <= 0.5, "grid_square_pitch expected<=0.5 actual=%.3f" % pitch_delta)
	var min_point: Vector2 = _point_position(&"entry_exit")
	var max_point: Vector2 = min_point
	for point_id: StringName in _points.keys():
		var point_position: Vector2 = _point_position(point_id)
		min_point.x = min(min_point.x, point_position.x)
		min_point.y = min(min_point.y, point_position.y)
		max_point.x = max(max_point.x, point_position.x)
		max_point.y = max(max_point.y, point_position.y)
	var bounds_center: Vector2 = (min_point + max_point) * 0.5
	var map_center: Vector2 = size * 0.5
	var center_delta: Vector2 = bounds_center - map_center
	var centered: bool = abs(center_delta.x) <= 1.0 and abs(center_delta.y) <= 1.0
	_check(centered, "grid_centered expected<=1 actual=(%.3f, %.3f)" % [abs(center_delta.x), abs(center_delta.y)])
	_check(not is_visible_in_tree(), "hidden_map_input blocked=true")
	_check(select_direction(Vector2.DOWN) and confirm_selection(), "keyboard_move_to_c1")
	_check(is_equal_approx(GameState.vital_now, 99.0),
		"keyboard_step_cost expected=99.000000 actual=%.6f" % GameState.vital_now)
	var after_c1: Array[StringName] = get_revealed_ids()
	_check(_same_ids(after_c1, [&"c1", &"entry_exit", &"point1"]),
		"revealed_after_c1 exact=true actual=%s" % [after_c1])
	_test_hover_and_invalid_clicks()
	_test_dead_end()
	_test_round_trip()
	print("[SP-06] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _test_hover_and_invalid_clicks() -> void:
	GameState.vital_now = GameState.vital_max
	reset_map()
	for target: StringName in [&"c1", &"point1", &"point2", &"point6", &"d1", &"point6", &"point2", &"point1"]:
		try_move_to(target)
	_update_hover_for_test(_point_position(&"point2"))
	_check(get_hovered_node_id() == &"point2", "hover_adjacent id=point2")
	_update_hover_for_test(_point_position(&"point1"))
	_check(get_hovered_node_id() == &"", "hover_current empty=true")
	_update_hover_for_test(_point_position(&"point6"))
	_check(get_hovered_node_id() == &"", "hover_non_adjacent empty=true")
	_update_hover_for_test(_point_position(&"point5"))
	_check(get_hovered_node_id() == &"", "hover_unrevealed empty=true")
	var before: float = GameState.vital_now
	var current_before: StringName = _current_id
	_check(not try_move_to(&"point5") and GameState.vital_now == before
		and _current_id == current_before, "click_unrevealed no_op=true")
	_check(not try_move_to(current_before) and GameState.vital_now == before,
		"click_current no_op=true")


func _update_hover_for_test(position: Vector2) -> void:
	_hovered_id = _hover_candidate_at(position)


func _test_dead_end() -> void:
	reset_map()
	for target: StringName in [&"c1", &"point1", &"point2", &"point6"]:
		try_move_to(target)
	GameState.vital_now = 99.0
	var point_calls: int = GameState.get_point_pay_call_count()
	_check(try_move_to(&"d1") and is_equal_approx(GameState.vital_now, 98.0),
		"d1_step_cost expected=98.000000 actual=%.6f" % GameState.vital_now)
	var before: float = GameState.vital_now
	var confirmed: bool = confirm_selection()
	var no_text_nodes: bool = find_children("*", "Label", true, false).is_empty()
	_check(not confirmed and is_equal_approx(GameState.vital_now, before)
		and GameState.get_point_pay_call_count() == point_calls,
		"d1_confirm silent=true value_unchanged=true pay_point_calls=0")
	_check(no_text_nodes, "d1_text_nodes expected=0 actual=0")


func _test_round_trip() -> void:
	GameState.vital_now = GameState.vital_max
	reset_map()
	var route: Array[StringName] = [
		&"c1", &"point1", &"point2", &"point3", &"point4", &"point5",
		&"point4", &"point3", &"point2", &"point1", &"c1", &"entry_exit"]
	for index: int in range(6):
		try_move_to(route[index])
	_check(_current_id == &"point5" and _step_count == 6, "shortest_main_route steps=6")
	for index: int in range(6, route.size()):
		try_move_to(route[index])
	_check(_step_count == 12, "shortest_round_trip steps=12")
	_check(is_equal_approx(GameState.vital_now, 88.0),
		"shortest_round_trip_vital expected=88.000000 actual=%.6f" % GameState.vital_now)


func _check(passed: bool, label: String) -> void:
	print("[SP-06] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1

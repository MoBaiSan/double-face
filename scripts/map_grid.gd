## 里侧点阵的显示与移动；调查业务由后续卡接入。
extends Control
signal moved(from_id: StringName, to_id: StringName, step_count: int)
const MAP_PATH: String = "res://data/map.json"
const MAP_DATA_SCRIPT = preload("res://scripts/map_data.gd")
@onready var _current_point_label: Label = get_node("../../CurrentPointLabel")
var _points: Dictionary = {}
var _start_id: StringName = &""
var _playable: bool = false
var _revealed: Dictionary = {}
var _current_id: StringName = &""
var _pending_id: StringName = &""
var _hovered_id: StringName = &""
var _step_count: int = 0
var _grid_size: Vector2 = Vector2.ONE
var _visual: Dictionary = {}
var _pulse_time: float = 0.0
var _last_gui_input_consumed: bool = false
var _start_fallback_warning: bool = false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(_on_mouse_exited)
	visibility_changed.connect(_on_visibility_changed)
	_sync_visibility_processing()
	_load_map()
	reset_map()
	if OS.get_cmdline_user_args().has("--sp06-self-test"):
		call_deferred("_run_self_test")
func _process(delta: float) -> void:
	_pulse_time = fmod(_pulse_time + delta, _float_visual("blue_pulse_period"))
	queue_redraw()
func _on_visibility_changed() -> void:
	_sync_visibility_processing()
func _sync_visibility_processing() -> void:
	var active: bool = is_visible_in_tree()
	set_process(active)
	set_process_unhandled_input(active)
## 将光标恢复到入口并建立初始两点揭开集合；进入里侧时调用。
func reset_map() -> void:
	if not _playable:
		_current_id = &""
		_pending_id = &""
		_hovered_id = &""
		_revealed.clear()
		_refresh_current_point_label()
		queue_redraw()
		return
	_current_id = _start_id
	_pending_id = &""
	_hovered_id = &""
	_step_count = 0
	_revealed.clear()
	_revealed[_start_id] = true
	_reveal_neighbors(_start_id)
	_refresh_current_point_label()
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
	_refresh_current_point_label()
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
	_last_gui_input_consumed = false
	var clicked_id: StringName = _hover_candidate_at(button.position)
	if clicked_id == &"":
		return
	_hovered_id = clicked_id
	try_move_to(clicked_id)
	_last_gui_input_consumed = true
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
		push_error("SP-06 map data parse failed: %s" % MAP_PATH)
		_playable = false
		return
	var raw_map: Dictionary = parsed as Dictionary
	var data = MAP_DATA_SCRIPT.from_dictionary(raw_map, _resolve_start_id(raw_map))
	if data == null:
		_playable = false
		_points.clear()
		return
	_grid_size = Vector2(data.grid_size)
	_start_id = data.start_id
	_visual = data.visual
	_points = data.points.duplicate(true)
	_playable = _points.has(_start_id)
	if not _playable:
		push_error("SP-06 map is unplayable: start_id=%s" % _start_id)
func _resolve_start_id(raw_map: Dictionary) -> StringName:
	var requested: StringName = StringName(str(raw_map.get("start_id", "")))
	var found: Dictionary = {}
	for point_variant: Variant in raw_map.get("points", []):
		if point_variant is Dictionary:
			found[StringName(str((point_variant as Dictionary).get("id", "")))] = true
	if requested != &"" and found.has(requested):
		return requested
	_start_fallback_warning = true
	push_warning("MapData start_id 缺失或不存在，回落 entry_exit")
	return &"entry_exit"
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
func _display_name(point_id: StringName) -> String:
	var point: Dictionary = _points.get(point_id, {}) as Dictionary
	var display_name: String = str(point.get("display_name", "")).strip_edges()
	return display_name if not display_name.is_empty() else str(point_id)
func _refresh_current_point_label() -> void:
	_current_point_label.text = "当前位置：" + _display_name(_current_id)
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
## 返回当前待选点，供自测验证方向键只改变候选而不移动。
func get_pending_node_id() -> StringName:
	return _pending_id
## 返回地图点 id，供自测计算布局边界而不暴露内部字典。
func get_point_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in _points.keys():
		ids.append(value as StringName)
	ids.sort()
	return ids
## 返回指定点在当前地图矩形内的局部坐标。
func get_point_position_for_test(point_id: StringName) -> Vector2:
	return _point_position(point_id)
## 返回指定点是否应绘制描边，供自测覆盖白点恒显规则。
func should_draw_outline_for_test(point_id: StringName) -> bool:
	return _should_draw_outline(point_id, _points.get(point_id, {}) as Dictionary)
## 设置自测用悬停位置，只改变高亮状态，不触发移动或扣点。
func set_hover_for_test(position: Vector2) -> void:
	_hovered_id = _hover_candidate_at(position)
func is_map_click_target_for_test(position: Vector2) -> bool:
	return _hover_candidate_at(position) != &""
## 判断当前可见点的包围圆是否完整落在地图区内。
func visible_points_inside_map_area() -> bool:
	return _visible_points_inside_map_area()
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
	var labels: Array[Dictionary] = get_drawn_labels()
	var font: Font = get_theme_font("font")
	for label_entry: Dictionary in labels:
		draw_string(font, label_entry.get("position", Vector2.ZERO), str(label_entry.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(str(_visual.get("label_color", "#443b2c"))))
## 返回地图绘制路径会画的点旁文字；当前名字由 CurrentPointLabel 角标负责。
func get_drawn_labels() -> Array[Dictionary]:
	var labels: Array[Dictionary] = []
	return labels
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
	if point_id == _start_id:
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
func _should_draw_outline(point_id: StringName, point: Dictionary) -> bool:
	return point_id == _current_id or point_id == _hovered_id or str(point.get("color", "plain")) == "white"
func get_last_gui_input_consumed_for_test() -> bool:
	return _last_gui_input_consumed
func load_map_for_test(raw_map: Dictionary) -> bool:
	_start_fallback_warning = false
	var data = MAP_DATA_SCRIPT.from_dictionary(raw_map, _resolve_start_id(raw_map))
	if data == null:
		return false
	_grid_size = Vector2(data.grid_size)
	_start_id = data.start_id
	_visual = data.visual
	_points = data.points.duplicate(true)
	_playable = _points.has(_start_id)
	reset_map()
	return _playable
func did_start_fallback_for_test() -> bool:
	return _start_fallback_warning
func resolve_start_id_for_test(raw_map: Dictionary) -> StringName:
	return _resolve_start_id(raw_map)
func get_start_id_for_test() -> StringName:
	return _start_id
func is_playable_for_test() -> bool:
	return _playable
func _same_ids(actual: Array[StringName], expected: Array[StringName]) -> bool:
	if actual.size() != expected.size():
		return false
	for point_id: StringName in expected:
		if not actual.has(point_id):
			return false
	return true
## 在显式自测参数下加载拆分后的断言模块，并把失败数映射为进程退出码。
func _run_self_test() -> void:
	var failures: int = preload("res://scripts/map_grid_selftest.gd").new().run(self)
	get_tree().quit(0 if failures == 0 else 1)

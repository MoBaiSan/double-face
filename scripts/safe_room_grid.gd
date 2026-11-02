## 安全屋完整点阵；只发选择/确认意图，不认识故事阶段或费用。
extends "res://scripts/dot_grid_surface.gd"
signal cell_selected(cell: Vector2i)
signal object_confirmed(id: String)
var dimensions: Vector2i
var current_cell: Vector2i
var initial_cell: Vector2i
var return_target: String
var objects: Dictionary = {}
var valid: bool = false
var last_error: String = ""
var input_enabled: bool = true
var _last_event: InputEvent
var _font: Font = preload("res://assets/fonts/simkai.ttf")

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func configure(grid_size: Vector2, data: Variant) -> bool:
	valid = false
	objects.clear()
	if not _integer(grid_size.x) or not _integer(grid_size.y) or grid_size.x <= 0 or grid_size.y <= 0:
		return _invalid("安全屋网格尺寸无效")
	dimensions = Vector2i(grid_size)
	if not data is Dictionary or not data.get("objects") is Array or data.objects.size() != 3:
		return _invalid("安全屋必须有三个物件")
	var cells: Array[Vector2i] = []
	for row: Variant in data.objects:
		if not row is Dictionary or row.get("id") not in ["Sofa", "Speaker", "Door"] or objects.has(row.id):
			return _invalid("安全屋物件ID无效")
		if not _valid_cell(row.get("cell")) or not row.get("display_name") is String or row.display_name.strip_edges().is_empty():
			return _invalid("安全屋物件坐标或名称无效")
		var cell := Vector2i(row.cell[0], row.cell[1])
		if cell in cells:
			return _invalid("安全屋物件重叠")
		cells.append(cell)
		objects[row.id] = {"cell": cell, "display_name": row.display_name}
	if not _valid_cell(data.get("initial_cell")) or data.get("return_target") != "Door":
		return _invalid("安全屋初始格或返回点无效")
	initial_cell = Vector2i(data.initial_cell[0], data.initial_cell[1])
	if initial_cell in cells:
		return _invalid("安全屋初始格必须是普通格")
	return_target = data.return_target
	current_cell = initial_cell
	valid = true
	last_error = ""
	queue_redraw()
	return true

func _integer(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == floor(float(value))

func _valid_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1]) and value[0] >= 0 and value[1] >= 0 and value[0] < dimensions.x and value[1] < dimensions.y

func _invalid(reason: String) -> bool:
	last_error = reason
	queue_redraw()
	return false

func center(cell: Vector2i) -> Vector2:
	return cell_center(Vector2(cell), Vector2(dimensions))

func cell_at(point: Vector2) -> Vector2i:
	if not valid:
		return Vector2i(-1, -1)
	var pitch: float = grid_pitch(Vector2(dimensions))
	var origin: Vector2 = size * 0.5 - Vector2(dimensions) * pitch * 0.5
	var relative: Vector2 = point - origin
	if pitch <= 0 or relative.x < 0 or relative.y < 0 or relative.x >= dimensions.x * pitch or relative.y >= dimensions.y * pitch:
		return Vector2i(-1, -1)
	return Vector2i(floori(relative.x / pitch), floori(relative.y / pitch))

func object_at(cell: Vector2i) -> String:
	for id: String in objects:
		if objects[id].cell == cell:
			return id
	return ""

func select_cell(cell: Vector2i) -> bool:
	if not valid or cell.x < 0 or cell.y < 0 or cell.x >= dimensions.x or cell.y >= dimensions.y:
		return false
	current_cell = cell
	cell_selected.emit(cell)
	queue_redraw()
	return true

func select_object(id: String) -> bool:
	return select_cell(objects[id].cell) if objects.has(id) else false

func confirm_current() -> void:
	var id: String = object_at(current_cell)
	if not id.is_empty():
		object_confirmed.emit(id)

func handle_input(event: InputEvent) -> bool:
	if event == _last_event:
		return _last_gui_input_consumed
	_last_event = event
	_last_gui_input_consumed = false
	if not input_enabled or not valid or not is_visible_in_tree():
		return false
	if is_left_press(event):
		var cell: Vector2i = cell_at(event.position)
		if cell == Vector2i(-1, -1):
			return false
		var previous: Vector2i = current_cell
		select_cell(cell)
		grab_focus()
		var id: String = object_at(cell)
		if id == "Door" or cell == previous:
			confirm_current()
		consume_grid_input()
	elif event is InputEventKey and event.pressed and not event.echo:
		var direction: Vector2i = {KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT, KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN}.get(event.keycode, Vector2i.ZERO)
		if direction != Vector2i.ZERO:
			select_cell(current_cell + direction)
			grab_focus()
			consume_grid_input()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			confirm_current()
			consume_grid_input()
	return _last_gui_input_consumed

func _gui_input(event: InputEvent) -> void:
	handle_input(event)

func _draw() -> void:
	if not valid:
		return
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			var cell := Vector2i(x, y)
			var point: Vector2 = center(cell)
			draw_circle(point, 5.0, Color("#84765b"))
			if cell == current_cell:
				draw_arc(point, 12.0, 0.0, TAU, 32, Color("#443b2c"), 3.0)
			var id: String = object_at(cell)
			if not id.is_empty():
				draw_string(_font, point + Vector2(15, 5), objects[id].display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#443b2c"))

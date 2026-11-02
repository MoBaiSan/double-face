## 纯点阵几何与鼠标消费；不依赖游戏状态或收费系统。
extends Control
var _last_gui_input_consumed: bool = false

func grid_pitch(dimensions: Vector2) -> float:
	return min(size.x / dimensions.x, size.y / dimensions.y)

func cell_center(cell: Vector2, dimensions: Vector2) -> Vector2:
	return size * 0.5 + (cell - (dimensions - Vector2.ONE) * 0.5) * grid_pitch(dimensions)

func is_left_press(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT

func consume_grid_input() -> void:
	_last_gui_input_consumed = true
	accept_event()

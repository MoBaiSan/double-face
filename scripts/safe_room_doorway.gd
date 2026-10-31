## 静态门口构图；正式素材只替换 _build_visual()。
extends Control
const REFERENCE: Vector2 = Vector2(960, 480)
const PADDING: float = 24.0
var canvas: Node2D
var figure: Node2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_visual()
	get_parent().resized.connect(_fit)
	_fit()
	reset_visual()

func _fit() -> void:
	var available: Vector2 = get_parent().size - Vector2.ONE * PADDING * 2.0
	var factor: float = maxf(0.0, minf(available.x / REFERENCE.x, available.y / REFERENCE.y))
	size = REFERENCE * factor
	position = (get_parent().size - size) * 0.5
	canvas.scale = Vector2.ONE * factor

func _build_visual() -> void:
	canvas = Node2D.new()
	canvas.name = "Canvas"
	add_child(canvas)
	_rect("Background", Rect2(0, 0, 1, 1), Color("#F2EBDD"))
	_rect("RoomInterior", Rect2(0, 0, 0.82, 1), Color("#D9CEB8"))
	_rect("DoorOpening", Rect2(0.83, 0.16, 0.13, 0.75), Color("#443B2C"))
	_rect("Threshold", Rect2(0.825, 0.16, 0.005, 0.75), Color("#9F8D6B"))
	figure = Node2D.new()
	figure.name = "AoiFigure"
	canvas.add_child(figure)
	var head: Array[Vector2] = []
	for i: int in range(16):
		var angle: float = TAU * i / 16.0
		head.append(Vector2(0.895, 0.28) + Vector2(cos(angle) * 0.035, sin(angle) * 0.07))
	_polygon("Head", head)
	_polygon("Torso", [Vector2(.85,.40), Vector2(.94,.40), Vector2(.94,.86), Vector2(.85,.86)])

func _rect(id: String, area: Rect2, color: Color) -> void:
	var item := ColorRect.new()
	item.name = id
	item.position = area.position * REFERENCE
	item.size = area.size * REFERENCE
	item.color = color
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(item)

func _polygon(id: String, points: Array[Vector2]) -> void:
	var item := Polygon2D.new()
	item.name = id
	item.polygon = PackedVector2Array(points.map(func(point: Vector2): return point * REFERENCE))
	item.color = Color("#D7B690")
	figure.add_child(item)

func show_entry() -> void:
	show()
	figure.show()

func leave() -> void:
	figure.hide()

func reset_visual() -> void:
	hide()
	figure.hide()

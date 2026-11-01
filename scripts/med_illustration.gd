## 有边框的上药小图；关闭事件先消费，不能穿透为下一句或物件点击。
extends Control
signal closed
const REFERENCE: Vector2 = Vector2(960, 480)
const MAX_WIDTH: float = 560.0
const FRAME_PADDING: float = 8.0
const PAPER: Color = Color("#F2EBDD")
const INK: Color = Color("#443B2C")
const COAT: Color = Color("#7C5A43")
const SKIN: Color = Color("#D7B690")
const CLOTH: Color = Color("#FFF9E5")
var frame: Panel
var picture: Control
var _root: Node2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	frame = Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = INK
	style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	picture = Control.new()
	picture.name = "Picture"
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	_build_visual()
	resized.connect(_fit)
	_fit()
	hide()

func _fit() -> void:
	if frame == null:
		return
	var width: float = minf(MAX_WIDTH, size.x * 0.5)
	picture.position = Vector2.ONE * FRAME_PADDING
	picture.size = Vector2(width, width * 0.5)
	frame.size = picture.size + Vector2.ONE * FRAME_PADDING * 2.0
	frame.position = (size - frame.size) * 0.5
	_root.scale = picture.size / REFERENCE

func open() -> void:
	_fit()
	show()

func dismiss() -> void:
	if not visible:
		return
	hide()
	closed.emit()

func route_input(event: InputEvent) -> bool:
	if not is_visible_in_tree():
		return false
	if event is InputEventKey and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		return false
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and frame.get_global_rect().has_point(event.position):
			dismiss()
	elif event is InputEventKey:
		if event.pressed and not event.echo and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel")):
			dismiss()
	else:
		return false
	get_viewport().set_input_as_handled()
	return true

func _build_visual() -> void:
	_root = Node2D.new()
	_root.name = "VisualRoot"
	picture.add_child(_root)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = PAPER
	background.size = REFERENCE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	_polygon("SofaShape", COAT, [Vector2(.09,.61),Vector2(.49,.61),Vector2(.49,.91),Vector2(.09,.91)])
	_polygon("DoorShape", INK, [Vector2(.83,.16),Vector2(.96,.16),Vector2(.96,.91),Vector2(.83,.91)])
	_polygon("BanTorso", INK, [Vector2(.25,.32),Vector2(.40,.32),Vector2(.48,.52),Vector2(.44,.82),Vector2(.24,.82),Vector2(.24,.43)])
	_polygon("KohakuTorso", COAT, [Vector2(.62,.29),Vector2(.73,.29),Vector2(.77,.48),Vector2(.76,.86),Vector2(.60,.86),Vector2(.59,.45)])
	_head("BanHead", Vector2(.31,.23), Vector2(.055,.095))
	_head("KohakuHead", Vector2(.67,.19), Vector2(.055,.10))
	_polygon("ShoulderPatch", INK, [Vector2(.39,.35),Vector2(.47,.35),Vector2(.47,.48),Vector2(.39,.48)])
	_polygon("UpperArm", COAT, [Vector2(.635,.36),Vector2(.665,.40),Vector2(.55,.53),Vector2(.515,.48)])
	_polygon("Forearm", SKIN, [Vector2(.54,.46),Vector2(.56,.51),Vector2(.46,.455),Vector2(.445,.42)])
	_polygon("Hand", SKIN, [Vector2(.435,.405),Vector2(.480,.405),Vector2(.480,.465),Vector2(.435,.465)])
	_polygon("Bandage", CLOTH, [Vector2(.405,.38),Vector2(.452,.38),Vector2(.452,.445),Vector2(.405,.445)])

func _head(id: String, center: Vector2, radius: Vector2) -> void:
	var vertices: Array[Vector2] = []
	for index: int in range(8):
		var angle: float = TAU * float(index) / 8.0
		vertices.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_polygon(id, SKIN, vertices)

func _polygon(id: String, color: Color, vertices: Array[Vector2]) -> void:
	var shape := Polygon2D.new()
	shape.name = id
	shape.color = color
	var points := PackedVector2Array()
	for point: Vector2 in vertices:
		points.append(point * REFERENCE)
	shape.polygon = points
	_root.add_child(shape)


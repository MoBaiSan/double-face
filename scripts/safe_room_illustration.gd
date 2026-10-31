## 静态占位插画；布局与业务独立，正式图仅替换 _build_visual()。
extends Control
const REFERENCE: Vector2 = Vector2(960, 480)
const PADDING: float = 24.0
const PAPER: Color = Color("#F2EBDD")
const INK: Color = Color("#443B2C")
const COAT: Color = Color("#7C5A43")
const SKIN: Color = Color("#D7B690")
const CLOTH: Color = Color("#FFF9E5")
var _root: Node2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_visual()
	get_parent().resized.connect(_fit)
	_fit()
	reset_dressing()

func _fit() -> void:
	var available: Vector2 = get_parent().size - Vector2.ONE * PADDING * 2.0
	var factor: float = maxf(0.0, minf(available.x / REFERENCE.x, available.y / REFERENCE.y))
	size = REFERENCE * factor
	position = (get_parent().size - size) * 0.5
	_root.scale = Vector2.ONE * factor

func _build_visual() -> void:
	_root = Node2D.new()
	_root.name = "VisualRoot"
	add_child(_root)
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

func show_dressing() -> void:
	for id: String in ["UpperArm", "Forearm", "Hand", "Bandage"]:
		_root.get_node(id).show()

func reset_dressing() -> void:
	for id: String in ["UpperArm", "Forearm", "Hand", "Bandage"]:
		_root.get_node(id).hide()

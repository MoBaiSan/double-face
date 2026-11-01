## 整页插画层；美术到位只需给本节点的 artwork 属性指定一张图片。
extends Control
## 比例热区与占位形状共同使用整页坐标，绘制节点全部不拦输入。
const REFERENCE: Vector2 = Vector2(1280, 720)
const PAPER: Color = Color("#F2EBDD")
const INK: Color = Color("#443B2C")
const COAT: Color = Color("#7C5A43")
const SKIN: Color = Color("#D7B690")
const CLOTH: Color = Color("#FFF9E5")
@export var artwork: Texture2D
var _root: Node2D
var _image: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_visual()
	_image = TextureRect.new()
	_image.name = "Artwork"
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_artwork(artwork)
	get_parent().resized.connect(_fit)
	_fit()

func set_artwork(value: Texture2D) -> void:
	artwork = value
	if not is_instance_valid(_image):
		return
	_image.texture = artwork
	_image.visible = artwork != null
	_root.visible = artwork == null

func _fit() -> void:
	position = Vector2.ZERO
	size = get_parent().size
	_root.scale = size / REFERENCE

func _build_visual() -> void:
	_root = Node2D.new()
	_root.name = "VisualRoot"
	add_child(_root)
	_rect("Wall", PAPER, Rect2(0, 0, 1, 1))
	_rect("Floor", Color("#BCA588"), Rect2(0, .60, 1, .40))
	_rect("Skirting", COAT, Rect2(0, .59, 1, .015))
	_rect("WindowFrame", COAT, Rect2(.055, .08, .15, .34))
	_rect("Window", Color("#B4C2BA"), Rect2(.065, .095, .13, .31))
	_rect("WindowBar", COAT, Rect2(.125, .095, .008, .31))
	_rect("SofaBack", COAT, Rect2(.08, .50, .44, .27))
	_rect("SofaSeat", Color("#9B785D"), Rect2(.09, .62, .42, .16))
	_rect("SofaLeg", INK, Rect2(.11, .79, .38, .025))
	_polygon("BanTorso", INK, [Vector2(.25,.32),Vector2(.40,.32),Vector2(.48,.52),Vector2(.44,.82),Vector2(.24,.82),Vector2(.24,.43)])
	_head("BanHead", Vector2(.31,.23), Vector2(.055,.095))
	_rect("Scar", Color("#BC7B64"), Rect2(.39, .35, .08, .13))
	_rect("ScarLine", CLOTH, Rect2(.405, .375, .05, .015))
	_rect("DoorFrame", INK, Rect2(.765, .16, .11, .65))
	_rect("Door", COAT, Rect2(.78, .20, .08, .55))
	_rect("DoorHandle", CLOTH, Rect2(.84, .46, .012, .035))
	_rect("DoorStep", Color("#635849"), Rect2(.75, .81, .14, .025))

func _rect(id: String, color: Color, fraction: Rect2) -> void:
	var item := ColorRect.new()
	item.name = id
	item.color = color
	item.position = fraction.position * REFERENCE
	item.size = fraction.size * REFERENCE
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(item)

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


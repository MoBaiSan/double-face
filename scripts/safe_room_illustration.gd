## 可配置文字占位与贴图共用槽位；不承载剧情入口。
extends Control
@export var artwork: Texture2D:
	set(value):
		artwork = value
		_sync()
@export var placeholder_text: String = "安全屋":
	set(value):
		placeholder_text = value
		_sync()
var _image: TextureRect
var _placeholder: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new()
	_image.name = "Artwork"
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder = Label.new()
	_placeholder.name = "Placeholder"
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.add_theme_font_override("font", preload("res://assets/fonts/simkai.ttf"))
	_placeholder.add_theme_font_size_override("font_size", 32)
	add_child(_placeholder)
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_parent().resized.connect(_fit)
	_fit()
	_sync()

func set_artwork(value: Texture2D) -> void:
	artwork = value

func _fit() -> void:
	position = Vector2.ZERO
	size = get_parent().size

func _sync() -> void:
	if not is_instance_valid(_image) or not is_instance_valid(_placeholder):
		return
	_image.texture = artwork
	_image.visible = artwork != null
	_placeholder.text = placeholder_text
	_placeholder.visible = artwork == null

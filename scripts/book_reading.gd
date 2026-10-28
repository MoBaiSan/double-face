## 占位书页的阅读生命周期；只显示既有选项文本，不编写剧情。
extends Control

@export var reading_frame: NodePath = ^"NarrationFrame"
@export var reading_text: NodePath = ^"NarrationFrame/Margin/TestText"
@onready var _nav: Control = $PageNav
@onready var _frame: Control = get_node(reading_frame)
@onready var _text: Label = get_node(reading_text)
var _reading_node: Control
var _original_text: String
var _frame_was_visible: bool = true
var _frame_mouse_filter: int

func _ready() -> void:
	_nav.reading_requested.connect(_begin_reading)
	_nav.confirmed.connect(_on_confirmed)
	_frame.gui_input.connect(_on_frame_input)
	visibility_changed.connect(_on_visibility_changed)

## 未读推进点可以进入阅读，但不能发推进确认；收起文字后才变成已读。
func _begin_reading(node: Control) -> void:
	if _nav.reading or not is_visible_in_tree():
		return
	_reading_node = node
	_original_text = _text.text
	_frame_was_visible = _frame.visible
	_text.text = (node.get_node("Text") as Label).text
	_frame_mouse_filter = _frame.mouse_filter
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.show()
	_nav.reading = true

func _on_confirmed(node: Control) -> void:
	var item = _nav.get_interactable(node)
	if item != null and not item.progression:
		_begin_reading(node)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _nav.reading or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		_finish_reading()
		get_viewport().set_input_as_handled()

func _on_frame_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if _nav.reading and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_finish_reading()
		_frame.accept_event()

func _finish_reading() -> void:
	var item = _nav.get_interactable(_reading_node)
	if item != null:
		item.complete_reading()
	_close_reading()

func _close_reading() -> void:
	_nav.reading = false
	_reading_node = null
	_text.text = _original_text
	_frame.visible = _frame_was_visible
	_frame.mouse_filter = _frame_mouse_filter

func _on_visibility_changed() -> void:
	if is_node_ready() and not is_visible_in_tree() and _nav.reading:
		_close_reading()

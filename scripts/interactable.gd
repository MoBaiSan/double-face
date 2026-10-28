## 两种书页共用的可点状态、扣点守卫与已读绘制。
extends Control

signal activated
signal repeated
signal state_changed

const DARK: Color = Color("443b2c")
const BRIGHT: Color = Color("fff9e5")
const READ_SHADE: Color = Color(0.55, 0.55, 0.55, 0.72)
const OUTLINE_PX: int = 1
const TEXT_PATH: String = "res://data/interaction_text.json"
static var _texts: Dictionary = {}

var hint_key: StringName = &""
var cost_kind: StringName = &""
var progression: bool = false
var _progress_confirmed: bool = false
var read: bool = false
var candidate: WeakRef
var active: bool = false:
	set(value):
		active = value
		queue_redraw()
var used: bool:
	get:
		return read
	set(value):
		set_read(value)
var _border := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.bg_color = Color.TRANSPARENT
	_border.anti_aliasing = false
	resized.connect(queue_redraw)

static func text_for(key: String) -> String:
	if _texts.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEXT_PATH))
		if parsed is Dictionary:
			_texts = parsed
	return str(_texts.get(key, ""))

func set_read(value: bool) -> void:
	if read == value:
		return
	read = value
	if not read:
		_progress_confirmed = false
	queue_redraw()
	state_changed.emit()

## 由真实书页阅读结束事件调用；推进资格只由自身已读状态导出。
func complete_reading() -> void:
	set_read(true)

func can_confirm() -> bool:
	return not progression or (read and not _progress_confirmed)

func has_outline() -> bool:
	return not progression or read

func get_outline_color() -> Color:
	return BRIGHT if active else DARK

func get_hint_text() -> String:
	if hint_key == &"" or not can_confirm():
		return ""
	return text_for("already_read" if read else str(hint_key))

func get_read_shade() -> Color:
	return READ_SHADE if read else Color.TRANSPARENT

func has_checkmark() -> bool:
	return read

## 成功才设置已读；重复确认只发提示信号，不调用扣点或业务。
func activate() -> bool:
	if progression:
		if _progress_confirmed:
			repeated.emit()
			return false
		if not can_confirm():
			return false
		_progress_confirmed = true
		activated.emit()
		return true
	if read:
		repeated.emit()
		return false
	if cost_kind != &"" and not GameState.pay_point(cost_kind):
		return false
	set_read(true)
	activated.emit()
	return true

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	if read:
		draw_rect(bounds, get_read_shade())
	if has_outline():
		_border.border_color = get_outline_color()
		_border.set_border_width_all(OUTLINE_PX)
		draw_style_box(_border, bounds)
	if has_checkmark():
		var start := Vector2(size.x - 15.0, 9.0)
		draw_line(start, start + Vector2(4.0, 4.0), DARK, 2.0)
		draw_line(start + Vector2(4.0, 4.0), start + Vector2(11.0, -4.0), DARK, 2.0)

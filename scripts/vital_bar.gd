## 常驻嗓子条的外观控件；只负责显示与下降反馈，不保存游戏状态。
extends Control
class_name VitalBar

signal value_changed(value: float, band: StringName)
signal drop_flashed

const MAX_VALUE: float = 100.0
const BAR_OFFSET_X: float = 32.0
const BAR_WIDTH: float = 24.0
const FLASH_DURATION: float = 0.15
## GDD §3.2「充足」：条是满色。
const FULL_COLOR: Color = Color("#217a8a")
## GDD §3.2「偏低」：条变色；没有十六进制指定，采用方案色。
const LOW_COLOR: Color = Color("#ad6b24")
## GDD §3.2「告急」：条色偏红；持续闪动留待后续数值卡。
const CRITICAL_COLOR: Color = Color("#b33b3b")
## GDD §3.2「断」：0 点歌声停；本卡让空槽体/边框保持可见。
const BROKEN_COLOR: Color = Color("#4c526b")
const THROAT_TEXT: String = "斑さん还能唱"

var _value: float = MAX_VALUE
var _flash_remaining: float = 0.0
var _flash_count: int = 0

## 调试与外部驱动入口：赋值即走 set_value()，保证重绘与闪光一致。
var value: float:
	get:
		return _value
	set(input):
		set_value(input)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_flash_remaining = maxf(_flash_remaining - delta, 0.0)
	if _flash_remaining <= 0.0:
		set_process(false)
	queue_redraw()


## 外部只需设置数值；本控件不创建或持有 GameState。
func set_value(value: float) -> void:
	var next_value: float = clampf(value, 0.0, MAX_VALUE)
	var previous_value: float = _value
	_value = next_value
	if next_value < previous_value:
		_flash_remaining = FLASH_DURATION
		_flash_count += 1
		drop_flashed.emit()
		set_process(true)
	value_changed.emit(_value, get_band())
	queue_redraw()


func get_value() -> float:
	return _value


func get_band() -> StringName:
	if is_zero_approx(_value):
		return &"broken"
	if _value <= 30.0:
		return &"critical"
	if _value <= 60.0:
		return &"low"
	return &"full"


func get_state_color() -> Color:
	match get_band():
		&"broken":
			return BROKEN_COLOR
		&"critical":
			return CRITICAL_COLOR
		&"low":
			return LOW_COLOR
		_:
			return FULL_COLOR


func get_fill_height() -> float:
	return size.y * _value / MAX_VALUE


func get_fill_top() -> float:
	return size.y - get_fill_height()


func get_flash_count() -> int:
	return _flash_count


func is_flash_active() -> bool:
	return _flash_remaining > 0.0


func get_bar_rect() -> Rect2:
	return Rect2(BAR_OFFSET_X, 0.0, BAR_WIDTH, size.y)


func get_text_content() -> String:
	return THROAT_TEXT


func _draw() -> void:
	var bar_rect: Rect2 = get_bar_rect()
	var state_color: Color = get_state_color()
	var draw_color: Color = state_color.lightened(0.22) if is_flash_active() else state_color
	draw_rect(bar_rect, Color("#d3c7ae"))
	if is_zero_approx(_value):
		draw_rect(bar_rect.grow(-1.0), Color(draw_color, 0.28))
		draw_rect(bar_rect, draw_color, false, 1.0)
	else:
		var fill_rect: Rect2 = Rect2(
			bar_rect.position.x, get_fill_top(), bar_rect.size.x, get_fill_height())
		draw_rect(fill_rect, draw_color)
		draw_rect(bar_rect, state_color, false, 1.0)

## 常驻嗓子条的外观控件；只负责显示与下降反馈，不保存游戏状态。
extends Control
class_name VitalBar

signal value_changed(value: float, band: StringName)
signal drop_flashed

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

var _value: float = 0.0
var _max_value: float = 0.0
var _band: StringName = &"broken"
var _flash_remaining: float = 0.0
var _flash_count: int = 0
var _bound_state: Node = null

## 调试与外部驱动入口：赋值即走 set_value()，保证重绘与闪光一致。
var value: float:
	get:
		return _value
	# Godot 4.6 属性 setter 参数不能单独标注类型，属性本身已声明 float。
	set(input):
		set_value(input)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var throat_label: Label = get_node_or_null("ThroatText") as Label
	if throat_label != null:
		throat_label.text = THROAT_TEXT
	_bind_state()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_flash_remaining = maxf(_flash_remaining - delta, 0.0)
	if _flash_remaining <= 0.0:
		set_process(false)
	queue_redraw()


## 外部只需设置数值；本控件不创建或持有 GameState。
func set_value(value: float) -> void:
	var state: Node = _bound_state
	var band: StringName = _band
	if state != null and state.has_method("get_band_for_value"):
		band = state.call("get_band_for_value", value) as StringName
	_set_display_value(value, band)


func _set_display_value(value: float, band: StringName) -> void:
	var next_value: float = clampf(value, 0.0, _max_value)
	var previous_value: float = _value
	_value = next_value
	_band = band
	var value_label: Label = get_node_or_null("ValueText") as Label
	if value_label != null:
		value_label.text = get_display_text()
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
	return _band


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


func get_draw_color() -> Color:
	return get_state_color().lightened(0.22) if is_flash_active() else get_state_color()


func get_fill_height() -> float:
	if _max_value <= 0.0:
		return 0.0
	return size.y * _value / _max_value


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


func get_display_text() -> String:
	return str(floori(_value))


func _bind_state() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or not state.has_signal("vital_changed"):
		return
	_bound_state = state
	_max_value = float(state.get("vital_max"))
	state.connect("vital_changed", _on_state_vital_changed)
	_on_state_vital_changed(state.get("vital_now"), state.get("vital_max"), &"initial")


func _on_state_vital_changed(value: float, _maximum: float, _reason: StringName) -> void:
	var band: StringName = _band
	if _bound_state != null and _bound_state.has_method("get_band_for_value"):
		band = _bound_state.call("get_band_for_value", value) as StringName
	_set_display_value(value, band)


func _draw() -> void:
	var bar_rect: Rect2 = get_bar_rect()
	var state_color: Color = get_state_color()
	var draw_color: Color = get_draw_color()
	draw_rect(bar_rect, Color("#d3c7ae"))
	if is_zero_approx(_value):
		draw_rect(bar_rect.grow(-1.0), Color(draw_color, 0.28))
		draw_rect(bar_rect, draw_color, false, 1.0)
	else:
		var fill_rect: Rect2 = Rect2(
			bar_rect.position.x, get_fill_top(), bar_rect.size.x, get_fill_height())
		draw_rect(fill_rect, draw_color)
		draw_rect(bar_rect, state_color, false, 1.0)

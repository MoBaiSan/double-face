## 纸面右下角的三页直达入口；按钮不参与键盘焦点。
extends HBoxContainer

const PAGE_NAMES: Array[StringName] = [&"ScenePage", &"MapPage", &"BattlePage"]
@onready var _buttons: Array[Button] = [$BookButton, $MapButton, $BattleButton]
var _show_page: Callable


func _ready() -> void:
	for index: int in range(_buttons.size()):
		_buttons[index].pressed.connect(_on_page_pressed.bind(index))


func configure(show_page: Callable) -> void:
	_show_page = show_page


func refresh(current_page: StringName) -> void:
	for index: int in range(_buttons.size()):
		_buttons[index].disabled = PAGE_NAMES[index] == current_page


func _on_page_pressed(index: int) -> void:
	if _buttons[index].disabled or not _show_page.is_valid():
		return
	_show_page.call(PAGE_NAMES[index])


## 由 SP-03 调用；真实鼠标事件覆盖切页，并复用主自检的失败计数。
func run_self_test(main: Control, check: Callable) -> void:
	var previous_page: StringName = main.get("_current_page")
	var expected_texts: Array[String] = ["书页", "地图", "战斗"]
	var present: bool = _buttons.size() == 3
	var no_focus: bool = true
	for index: int in range(_buttons.size()):
		present = present and _buttons[index].is_inside_tree() and _buttons[index].text == expected_texts[index]
		no_focus = no_focus and _buttons[index].focus_mode == Control.FOCUS_NONE
	check.call(present, "switch_buttons_present texts=书页/地图/战斗")
	check.call(no_focus, "switch_buttons_focus_none")
	_test_click_switches(main, check)
	_test_destinations_and_keys(main, check)
	_test_bounds(main, check)
	main.show_page(previous_page)


func _test_click_switches(main: Control, check: Callable) -> void:
	main.show_page(&"ScenePage")
	var press_count: Array[int] = [0]
	var count_press: Callable = func() -> void: press_count[0] += 1
	$MapButton.pressed.connect(count_press)
	_click_button($MapButton)
	var on_map: bool = main.get("_current_page") == &"MapPage"
	check.call(on_map and press_count[0] == 1 and _disabled_matches(&"MapPage"),
		"switch_map_click current=MapPage disabled=false/true/false")
	var before: StringName = main.get("_current_page")
	_click_button($MapButton)
	check.call(main.get("_current_page") == before and press_count[0] == 1,
		"switch_current_disabled_noop")
	$MapButton.pressed.disconnect(count_press)


func _test_destinations_and_keys(main: Control, check: Callable) -> void:
	var destinations_ok: bool = true
	for index: int in range(_buttons.size()):
		_click_button(_buttons[index])
		destinations_ok = destinations_ok and main.get("_current_page") == PAGE_NAMES[index]
		destinations_ok = destinations_ok and _disabled_matches(PAGE_NAMES[index])
	check.call(destinations_ok, "switch_all_destinations")
	main.show_page(&"ScenePage")
	_push_key(KEY_PAGEDOWN)
	var down_ok: bool = main.get("_current_page") == &"MapPage" and _disabled_matches(&"MapPage")
	_push_key(KEY_PAGEUP)
	check.call(down_ok and main.get("_current_page") == &"ScenePage" and _disabled_matches(&"ScenePage"),
		"switch_pageup_pagedown_sync")


func _disabled_matches(page: StringName) -> bool:
	for index: int in range(_buttons.size()):
		if _buttons[index].disabled != (PAGE_NAMES[index] == page):
			return false
	return true


func _test_bounds(main: Control, check: Callable) -> void:
	var map_rect: Rect2 = (main.get_node("Pages/MapPage/MapArea") as Control).get_global_rect()
	var throat_rect: Rect2 = (main.get_node("Overlay/ThroatPlaceholder") as Control).get_global_rect()
	var value_rect: Rect2 = (main.get_node("Overlay/ThroatPlaceholder/ValueText") as Control).get_global_rect()
	var clear: bool = true
	var limits: bool = true
	for button: Button in _buttons:
		var rect: Rect2 = button.get_global_rect()
		clear = clear and not rect.intersects(map_rect) and not rect.intersects(throat_rect) and not rect.intersects(value_rect)
		limits = limits and rect.end.x <= 1180.0 and rect.end.y >= 680.0 and rect.end.y <= 720.0
	check.call(clear, "switch_rects_clear_map_and_throat")
	check.call(limits, "switch_rects_right_bottom_limits")
	var bounds: Rect2 = get_global_rect()
	print("[SP-03] switch_bounds x=%.1f y=%.1f w=%.1f h=%.1f throat_dx=%.1f throat_dy=%.1f value_dy=%.1f map_dy=%.1f" % [
		bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y,
		throat_rect.position.x - bounds.end.x, bounds.position.y - throat_rect.end.y,
		bounds.position.y - value_rect.end.y, bounds.position.y - map_rect.end.y])


func _click_button(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
		get_viewport().push_input(event, true)


func _push_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event)

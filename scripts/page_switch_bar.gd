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
	_test_production_pages(main, check)
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



## U-03b：从正式开场出发，真实输入覆盖玩家报告的入口与停滞。
func run_story_input_test(c: RefCounted, check: Callable) -> void:
	var page: Control = c.main.get_node("Pages/ScenePage")
	_finish_user_text(c.main._dialogue)
	var speaker: Control = page.get_node("TestOptions/OptionTwo")
	print("[U-03b] speaker text=%s visible=%s rect=%s" % [speaker.get_node("Text").text, speaker.is_visible_in_tree(), speaker.get_global_rect()])
	check.call(61, speaker.is_visible_in_tree() and speaker.get_node("Text").text == "旧音响", "旧音响入口有真实名称")
	_click_at(speaker.get_global_rect().get_center())
	check.call(62, c.main._dialogue.get_current_key() == "T112", "旧音响中心点击触发旁白T112")
	for index: int in range(4):
		_finish_user_text(c.main._dialogue)
	check.call(63, c.main._dialogue.get_story_phase() == &"DONE" and GameState.state == GameState.State.S1 and c.main._dialogue.get_current_key() == "T122", "真实阅读串完R2_R3_R4进入S1")
	_finish_user_text(c.main._dialogue)
	_log_map_input(c, "departure_finished")
	_click_map_point(c.map, &"c1")
	var entered: bool = GameState.state == GameState.State.S2 and c.map.get_current_node_id() == &"c1"
	check.call(64, entered and c.map.get_step_count() == 1 and GameState.vital_now == 99.0, "出发文字结束后真实鼠标首步到c1")
	if not entered:
		_push_key(KEY_DOWN)
	_log_map_input(c, "first_step")
	_test_map_continuation(c, check)

func _test_map_continuation(c: RefCounted, check: Callable) -> void:
	_click_map_point(c.map, &"point1")
	_click_map_point(c.map, &"point1")
	var first: bool = c.points.get_dialogue().is_playing() and c.points.get_dialogue().get_current_key() == "T134"
	print("[U-03b] point1 current=%s playing=%s key=%s" % [c.map.get_current_node_id(), c.points.get_dialogue().is_playing(), c.points.get_dialogue().get_current_key()])
	check.call(65, first and c.map.get_revealed_ids().has(&"point1"), "S2已揭示点真实点击播放调查")
	_finish_user_text(c.points.get_dialogue())
	_click_map_point(c.map, &"point2")
	_click_map_point(c.map, &"point2")
	check.call(66, c.map.get_interactable(&"point1").read and c.points.get_dialogue().is_playing() and c.points.get_dialogue().get_current_key() == "T136", "关闭调查后能继续调查下一点")
	_finish_user_text(c.points.get_dialogue())
	var pages: bool = _real_page_cycle(c.main)
	check.call(67, pages and GameState.state == GameState.State.S2 and c.map.get_interactable(&"point2").read, "S2调查后翻三页与键盘均可用")

func _finish_user_text(player: Control) -> void:
	var keys: Array = player._keys.duplicate()
	for index: int in range(keys.size() + 1):
		if not player.is_playing() or player._keys != keys:
			break
		player.finish_text()
		if player.get_current_mode() == "read":
			_push_key(KEY_ENTER)
		else:
			player.advance_time(100.0)

func _click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _click_map_point(map: Control, id: StringName) -> void:
	_click_at(map.get_global_transform_with_canvas() * map._point_position(id))

func _log_map_input(c: RefCounted, label: String) -> void:
	print("[U-03b] %s state=%d page=%s map_visible=%s mode=%d input=%s unhandled=%s mouse_filter=%d dialogue_visible=%s playing=%s frozen=%s" % [
		label, GameState.state, c.main._current_page, c.map.is_visible_in_tree(), c.map.process_mode,
		c.map.is_processing_input(), c.map.is_processing_unhandled_key_input(), c.map.mouse_filter,
		c.main._dialogue.visible, c.main._dialogue.is_playing(), GameState.is_frozen()])

func _test_production_pages(main: Control, check: Callable) -> void:
	var router: Node = main._flow
	main._flow = main.get_meta("production_flow", router)
	var before: int = GameState.state
	var ok: bool = _real_page_cycle(main)
	main._flow = router
	check.call(ok and GameState.state == before, "production_buttons_real_centers_and_page_keys")

func _real_page_cycle(main: Control) -> bool:
	var ok: bool = true
	for index: int in [1, 2, 0, 1, 2]:
		_click_at(_buttons[index].get_global_rect().get_center())
		ok = main._current_page == PAGE_NAMES[index] and _disabled_matches(PAGE_NAMES[index]) and ok
	_push_key(KEY_PAGEDOWN)
	ok = main._current_page == &"ScenePage" and _disabled_matches(&"ScenePage") and ok
	_push_key(KEY_PAGEUP)
	return main._current_page == &"BattlePage" and _disabled_matches(&"BattlePage") and ok

func _push_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		get_viewport().push_input(event)

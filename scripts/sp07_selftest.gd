## 显式参数才运行；通过真实书页组件与地图事件链检查反馈及扣点。
extends RefCounted

var _main: Control
var _map: Control
var _nav: Control
var _failures: int = 0
var _confirmed: int = 0
var _investigated: int = 0
var _repeated: int = 0

func run(main: Control) -> int:
	_main = main
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	GameState.set_process(false)
	GameState.set_frozen(false)
	GameState.vital_now = GameState.vital_max
	_nav = main.get_node("Pages/ScenePage/PageNav")
	_map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	_nav.confirmed.connect(_on_book_confirmed)
	_map._interactions.investigated.connect(_on_investigated)
	_map._interactions.repeated.connect(_on_repeated)
	_test_shared_implementation()
	_test_book_feedback()
	await _test_progress_gate()
	_test_map_investigation()
	_test_all_points()
	print("[SP-07] failures=%d" % _failures)
	return _failures

func _test_shared_implementation() -> void:
	_main.show_page(&"ScenePage")
	var node: Control = _main.get_node("Pages/ScenePage/TestOptions/OptionOne")
	var book_item = _nav.get_interactable(node)
	var map_item = _map.get_interactable(&"point1")
	var book_scene: Control = load("res://scenes/ui/BookPage.tscn").instantiate()
	_main.add_child(book_scene)
	var standalone = book_scene.get_node("PageNav").get_interactable(book_scene.get_node("TestOptions/OptionOne"))
	_check(book_item != null and map_item != null and standalone != null
		and book_item.get_script() == map_item.get_script()
		and standalone.get_script() == map_item.get_script(), "shared_component_scene_book_map")
	book_scene.free()

func _test_book_feedback() -> void:
	var second: Control = _main.get_node("Pages/ScenePage/TestOptions/OptionOne")
	_nav.move_selection(Vector2.DOWN)
	var item = _nav.get_interactable(second)
	_check(not item.read and item.has_outline() and item.OUTLINE_PX == 1
		and item.get_outline_color() == Color("443b2c"), "unread_inner_outline_1px_dark")
	_check(not item.has_checkmark() and item.get_read_shade() == Color.TRANSPARENT, "unread_no_gray_no_check")
	_hover(second.get_global_rect().get_center())
	_check(item.active and item.get_outline_color() == Color("fff9e5"), "hover_outline_exact_bright")
	var before: float = GameState.vital_now
	_click(second.get_global_rect().get_center())
	_check(item.read and item.get_read_shade().a > 0.0
		and item.get_read_shade().r == item.get_read_shade().g
		and item.get_read_shade().g == item.get_read_shade().b, "read_is_gray")
	_check(item.read and item.has_checkmark(), "read_has_top_right_check")
	_check(item.get_hint_text().is_empty(), "book_no_hint_text")
	var confirmations: int = _confirmed
	_key(KEY_ENTER)
	_click(second.get_global_rect().get_center())
	_check(GameState.vital_now == before and _confirmed == confirmations, "book_repeat_no_cost_or_replay")

func _test_progress_gate() -> void:
	var node: Control = _main.get_node("Pages/ScenePage/TestOptions/OptionTwo")
	var item = _nav.get_interactable(node)
	var before: int = _confirmed
	_hover(node.get_global_rect().get_center())
	_click(node.get_global_rect().get_center())
	var notice: Label = _nav._progress_notice
	_check(item.progression and not item.read and not item.has_outline() and not item.can_confirm()
		and item.get_hint_text().is_empty() and notice.visible and notice.text == "还有没看过的地方。"
		and notice.get_theme_color("font_color") == Color("777777") and _confirmed == before,
		"progress_pending_no_outline_no_confirm_gray_notice")
	_check(_nav.reading and _main.get_node("Pages/ScenePage/Illustration/Label").text == node.get_node("Text").text,
		"progress_real_reading_started")
	_key(KEY_ENTER)
	_check(item.read and item.can_confirm() and item.has_outline() and not notice.visible and not _nav.reading,
		"progress_complete_notice_gone_can_confirm")
	_key(KEY_ENTER)
	_check(_confirmed == before + 1 and item.read, "progress_confirm_after_ready")
	_key(KEY_ENTER)
	_check(_confirmed == before + 1 and not _nav.reading, "progress_reconfirm_no_replay")
	_main.get_node("Pages").hide()
	await _test_book_optional_independence(false)
	await _test_book_optional_independence(true)
	await _test_s6_progression()
	_main.get_node("Pages").show()

func _test_book_optional_independence(read_optional: bool) -> void:
	var page: Control = await _mount_book("res://scenes/ui/BookPage.tscn")
	var nav: Control = page.get_node("PageNav")
	var optional: Control = page.get_node("TestOptions/OptionOne")
	var progress: Control = page.get_node("TestOptions/OptionTwo")
	var item = nav.get_interactable(progress)
	var other = nav.get_interactable(optional)
	if read_optional:
		_click(optional.get_global_rect().get_center())
		_key(KEY_ENTER)
	_check(other.read == read_optional and not other.progression and item.progression
		and not item.read and not item.can_confirm() and not item.has_outline(),
		"optional_read_%s_does_not_unlock_progress" % read_optional)
	_click(progress.get_global_rect().get_center())
	_key(KEY_ENTER)
	_check(item.read and item.can_confirm() and not nav._progress_notice.visible
		and other.read == read_optional, "self_read_unlocks_with_optional_%s" % read_optional)
	if not read_optional:
		_click(optional.get_global_rect().get_center())
		_key(KEY_ENTER)
		_check(item.can_confirm() and other.read and not nav._progress_notice.visible,
			"optional_read_after_unlock_does_not_relock")
	page.free()

func _test_s6_progression() -> void:
	var page: Control = await _mount_book("res://scenes/ui/S6Page.tscn")
	var nav: Control = page.get_node("PageNav")
	var sofa: Control = page.get_node("TestOptions/OptionOne")
	var door: Control = page.get_node("TestOptions/OptionTwo")
	var sofa_item = nav.get_interactable(sofa)
	var door_item = nav.get_interactable(door)
	_check(sofa_item.progression and door_item.progression and not sofa_item.can_confirm()
		and not door_item.can_confirm() and not sofa_item.has_outline() and not door_item.has_outline(),
		"s6_sofa_door_initially_locked")
	_click(sofa.get_global_rect().get_center())
	_key(KEY_ENTER)
	_check(sofa_item.read and sofa_item.can_confirm() and not door_item.read
		and not door_item.can_confirm() and not nav._progress_notice.visible,
		"s6_sofa_self_read_independent_unlock")
	_click(door.get_global_rect().get_center())
	_check(not door_item.can_confirm() and nav._progress_notice.visible, "s6_door_stays_locked_until_own_read")
	_click(page.get_node("Illustration").get_global_rect().get_center())
	_check(door_item.read and door_item.can_confirm() and sofa_item.can_confirm()
		and not nav._progress_notice.visible, "s6_door_mouse_read_completion_unlocks")
	_check(sofa.get_node("Text").text == "选项一" and door.get_node("Text").text == "选项二",
		"s6_keeps_existing_placeholder_text")
	page.free()

func _mount_book(path: String) -> Control:
	var page: Control = load(path).instantiate()
	_main.add_child(page)
	await _main.get_tree().process_frame
	await _main.get_tree().process_frame
	return page
func _test_map_investigation() -> void:
	_main.show_page(&"MapPage")
	GameState.set_frozen(false)
	_map.reset_map()
	_map.try_move_to(&"c1")
	_map.try_move_to(&"point1")
	var item = _map.get_interactable(&"point1")
	var point: Vector2 = _map.get_global_transform_with_canvas() * _map.get_point_position_for_test(&"point1")
	_hover(point)
	_check(item.get_hint_text() == "调查" and item.get_outline_color() == Color("fff9e5"),
		"map_hint_and_hover_shared")
	var before: float = GameState.vital_now
	var steps: int = _map.get_step_count()
	_click(point)
	_check(absf(before - GameState.vital_now - 6.0) <= 1e-6, "required_cost_6")
	var frame: Control = _main.get_node("Pages/MapPage/InvestigationText")
	_check(item.read and frame.visible and not frame.get_node("Margin/Text").text.is_empty()
		and _investigated == 1, "first_investigation_text_and_cost_together")
	_check(item.has_checkmark() and item.get_read_shade().a > 0.0, "map_read_gray_and_check")
	before = GameState.vital_now
	var calls: int = GameState.get_point_pay_call_count()
	var investigations: int = _investigated
	_click(point)
	_check(absf(GameState.vital_now - before) <= 1e-6
		and GameState.get_point_pay_call_count() == calls, "read_repeat_vital_unchanged")
	_check(_investigated == investigations and _repeated == 1
		and _map.get_current_node_id() == &"point1" and _map.get_step_count() == steps
		and not frame.visible and item.get_hint_text() == "已经看过了", "read_repeat_only_hint_no_progress_no_replay")
	_map.try_move_to(&"point2")
	_map.try_move_to(&"point6")
	before = GameState.vital_now
	_key(KEY_ENTER)
	_check(absf(before - GameState.vital_now - 4.0) <= 1e-6
		and _map.get_interactable(&"point6").read, "optional_cost_4_keyboard")

func _test_all_points() -> void:
	for target: StringName in [&"point2", &"point3", &"point4", &"point5", &"point4", &"point7"]:
		_map.try_move_to(target)
		_map.confirm_selection()
	var all_read: bool = true
	for id: StringName in [&"point1", &"point2", &"point3", &"point4", &"point5", &"point6", &"point7"]:
		all_read = all_read and _map.get_interactable(id).read
	_check(all_read and _investigated == 7, "all_seven_points_once")
	_map.get_interactable(&"point7").set_read(false)
	GameState.vital_now = 0.0
	var before: int = _investigated
	_map.confirm_selection()
	_check(not _map.get_interactable(&"point7").read and _investigated == before, "failed_payment_stays_unread")

func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		_main.get_viewport().push_input(event, true)

func _hover(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	_main.get_viewport().push_input(event, true)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		_main.get_viewport().push_input(event)

func _on_book_confirmed(_node: Control) -> void:
	_confirmed += 1

func _on_investigated(_point_id: StringName) -> void:
	_investigated += 1

func _on_repeated(_point_id: StringName) -> void:
	_repeated += 1

func _check(passed: bool, label: String) -> void:
	print("[SP-07] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1

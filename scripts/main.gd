## 常驻书页的组装与翻页入口；由 Main 持有，复用既有 PageNav。
## 不创建剧情、地图或战斗数据，自查仅在无头且显式传参时执行。
extends Control

const PAGE_NAMES: Array[StringName] = [&"ScenePage", &"MapPage", &"BattlePage"]
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const SELF_TEST_ARGUMENT: String = "--sp03-self-test"
const SELF_TEST_ROUNDS: int = 3
const LAYOUT_WAIT_FRAMES: int = 2

@onready var _pages_root: Control = $Pages
@onready var _book_page: Control = $BookPage
@onready var _throat_placeholder: Control = $Overlay/ThroatPlaceholder
@onready var _scene_nav: Control = $Pages/ScenePage/PageNav

var _pages: Dictionary = {}
var _page_data: Dictionary = {}
var _current_page: StringName = &""
var _current_data: Dictionary = {}
var _failures: int = 0
var _original_scene: Node = null
var _main_scene_unchanged: bool = true


func _ready() -> void:
	for page_name: StringName in PAGE_NAMES:
		var page: Control = _pages_root.get_node_or_null(NodePath(page_name)) as Control
		if page == null:
			push_error("书页节点缺失：%s" % page_name)
			return
		_pages[page_name] = page
		_page_data[page_name] = {}
	show_page(PAGE_NAMES[0])
	print("[godot-project] ready")
	if DisplayServer.get_name() == "headless":
		if OS.get_cmdline_user_args().has(SELF_TEST_ARGUMENT):
			call_deferred("_run_self_test")


## 显示指定常驻页并切换空数据引用；未知页返回 false 且不改变当前页。
func show_page(name: StringName) -> bool:
	if not _pages.has(name):
		return false
	if name != _current_page:
		for page_name: StringName in PAGE_NAMES:
			_set_page_active(_pages[page_name] as Control, page_name == name)
	_current_page = name
	_current_data = _page_data[name]
	return true


func _set_page_active(page: Control, active: bool) -> void:
	var nav: Control = page.get_node_or_null("PageNav") as Control
	# 必须先暂停再隐藏，否则既有导航的逐帧同步会丢掉当前候选。
	if nav != null and not active:
		nav.set_process(false)
		nav.set_process_input(false)
	page.visible = active
	if nav != null and active:
		nav.set_process(true)
		nav.set_process_input(true)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var direction: int = 0
	match key.keycode:
		KEY_PAGEDOWN:
			direction = 1
		KEY_PAGEUP:
			direction = -1
		_:
			return
	_turn_page(direction)
	get_viewport().set_input_as_handled()


func _turn_page(direction: int) -> void:
	var current_index: int = PAGE_NAMES.find(_current_page)
	if current_index < 0:
		return
	var next_index: int = posmod(current_index + direction, PAGE_NAMES.size())
	show_page(PAGE_NAMES[next_index])


func _run_self_test() -> void:
	if not await _wait_for_layout():
		return
	_original_scene = get_tree().current_scene
	_observe_main_scene()
	var option_label: Label = $Pages/ScenePage/TestOptions/OptionOne/Text
	print("[SP-03] font_size default=%d option=%d" % [
		get_theme_font_size(&"font_size", &"Label"), option_label.get_theme_font_size(&"font_size")])
	_test_visible_pages()
	await _test_fixed_paper_and_throat()
	await _test_navigation_retention()
	_test_unknown_page()
	_observe_main_scene()
	var current: Node = get_tree().current_scene
	var path: String = current.scene_file_path if current != null else "<null>"
	print("[SP-03] current_scene=%s" % path)
	_check(_main_scene_unchanged, "5 main_scene unchanged: %s" % path)
	print("[SP-03] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _wait_for_layout() -> bool:
	for _frame: int in range(LAYOUT_WAIT_FRAMES):
		if not is_inside_tree():
			return false
		var tree: SceneTree = get_tree()
		await tree.process_frame
	return is_inside_tree()


func _test_visible_pages() -> void:
	for page_name: StringName in PAGE_NAMES:
		var accepted: bool = show_page(page_name)
		_observe_main_scene()
		_check(accepted and _only_page_visible(page_name), "1 visible: %s" % page_name)
		var expected_nav_count: int = 1 if page_name == PAGE_NAMES[0] else 0
		_check(_active_navigation_count() == expected_nav_count,
			"1 working navigation: %s" % page_name)


func _active_navigation_count() -> int:
	var count: int = 0
	var background_nav: Control = $BookPage/PageNav
	for nav: Control in [background_nav, _scene_nav]:
		if nav.can_process() and nav.is_processing_input():
			count += 1
	return count


func _test_fixed_paper_and_throat() -> void:
	show_page(PAGE_NAMES[0])
	_observe_main_scene()
	if not await _wait_for_layout():
		return
	var book_bounds: Rect2 = Rect2(_book_page.global_position, _book_page.size)
	var throat_bounds: Rect2 = Rect2(
		_throat_placeholder.global_position, _throat_placeholder.size)
	var book_id: int = _book_page.get_instance_id()
	var throat_id: int = _throat_placeholder.get_instance_id()
	for round_index: int in range(SELF_TEST_ROUNDS):
		var stable: bool = true
		for page_name: StringName in [PAGE_NAMES[1], PAGE_NAMES[2], PAGE_NAMES[0]]:
			show_page(page_name)
			_observe_main_scene()
			if not await _wait_for_layout():
				return
			stable = stable and _book_page.global_position == book_bounds.position
			stable = stable and _book_page.size == book_bounds.size
			stable = stable and _throat_placeholder.global_position == throat_bounds.position
			stable = stable and _throat_placeholder.size == throat_bounds.size
			stable = stable and _book_page.get_instance_id() == book_id
			stable = stable and _throat_placeholder.get_instance_id() == throat_id
		_check(stable, "2 paper/throat fixed, round %d" % (round_index + 1))


func _test_navigation_retention() -> void:
	show_page(PAGE_NAMES[0])
	_observe_main_scene()
	if not await _wait_for_layout():
		return
	var first: Control = $Pages/ScenePage/TestOptions/OptionOne
	var second: Control = $Pages/ScenePage/TestOptions/OptionTwo
	var selected: Control = _scene_nav.call("get_selected") as Control
	var starts_first: bool = selected == first
	_scene_nav.call("confirm_selection")
	var used_before: bool = _has_used_state(first)
	var outline_before: int = _outline_id(first)
	_scene_nav.call("move_selection", Vector2.DOWN)
	selected = _scene_nav.call("get_selected") as Control
	var moved: bool = selected == second
	_scene_nav.call("move_selection", Vector2.UP)
	selected = _scene_nav.call("get_selected") as Control
	_check(starts_first and moved and selected == first, "3 selected: one -> two -> one")
	await _test_state_after_page_turn(first, used_before, outline_before)


func _test_state_after_page_turn(first: Control, used_before: bool, outline_id: int) -> void:
	for page_name: StringName in [PAGE_NAMES[1], PAGE_NAMES[2], PAGE_NAMES[0]]:
		show_page(page_name)
		_observe_main_scene()
		if not await _wait_for_layout():
			return
	var selected: Control = _scene_nav.call("get_selected") as Control
	var retained: bool = selected == first and used_before and _has_used_state(first)
	retained = retained and _outline_id(first) == outline_id
	_check(retained, "3 selection/gray-check retained after return")


func _has_used_state(node: Control) -> bool:
	var used_ids: Dictionary = _scene_nav.get("_used_ids")
	var outlines: Dictionary = _scene_nav.get("_outlines")
	var outline: Control = outlines.get(node.get_instance_id()) as Control
	return bool(used_ids.get(node.get_instance_id(), false)) \
		and outline != null and bool(outline.get("used"))


func _outline_id(node: Control) -> int:
	var outlines: Dictionary = _scene_nav.get("_outlines")
	var outline: Control = outlines.get(node.get_instance_id()) as Control
	return outline.get_instance_id() if outline != null else 0


func _test_unknown_page() -> void:
	var before: StringName = _current_page
	var accepted: bool = show_page(&"Nope")
	_observe_main_scene()
	_check(not accepted and _current_page == before and _only_page_visible(before),
		"4 unknown page returns false without changing visible page")


func _only_page_visible(name: StringName) -> bool:
	var count: int = 0
	for page_name: StringName in PAGE_NAMES:
		var page: Control = _pages[page_name] as Control
		if page.visible:
			count += 1
	var target: Control = _pages[name] as Control
	return count == 1 and target.visible


func _observe_main_scene() -> void:
	var current: Node = get_tree().current_scene
	_main_scene_unchanged = _main_scene_unchanged and current == _original_scene
	_main_scene_unchanged = _main_scene_unchanged and current != null
	if current != null:
		_main_scene_unchanged = _main_scene_unchanged and current.scene_file_path == MAIN_SCENE_PATH


func _check(passed: bool, label: String) -> void:
	print("[SP-03] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1
		push_error("SP-03 自查失败：%s" % label)

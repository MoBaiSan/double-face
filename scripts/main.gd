## 常驻书页的组装与翻页入口；由 Main 持有，复用既有 PageNav。
## 不创建剧情、地图或战斗数据，自查仅在无头且显式传参时执行。
extends Control
const PAGE_NAMES: Array[StringName] = [&"ScenePage", &"MapPage", &"BattlePage"]
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const SELF_TEST_ARGUMENT: String = "--sp03-self-test"
const FORCE_LAYOUT_FAIL_ARGUMENT: String = "--sp03-force-layout-fail"
const SP04_SELF_TEST_ARGUMENT: String = "--sp04-self-test"
const SP04_DEMO_PREFIX: String = "--sp04-demo="
const SELF_TEST_ROUNDS: int = 3
const LAYOUT_WAIT_FRAMES: int = 2
const SP04_VALUES: Array[float] = [100.0, 60.0, 30.0, 0.0]
const SP04_BANDS: Array[StringName] = [&"full", &"low", &"critical", &"broken"]
const SP04_EXPECTED_COLORS: Array[Color] = [
	Color("#217a8a"), Color("#ad6b24"), Color("#b33b3b"), Color("#4c526b")]
@onready var _pages_root: Control = $Pages
@onready var _book_page: Control = $BookPage
@onready var _throat_placeholder: VitalBar = $Overlay/ThroatPlaceholder
@onready var _scene_nav: Control = $Pages/ScenePage/PageNav
@onready var _page_switch_bar = $Overlay/PageSwitchBar
var _pages: Dictionary = {}
var _page_data: Dictionary = {}
var _current_page: StringName = &""
var _current_data: Dictionary = {}
var _failures: int = 0
var _original_scene: Node = null
var _main_scene_unchanged: bool = true
var _sp04_failures: int = 0
var _force_layout_fail: bool = false
var _dialogue: Control
func _ready() -> void:
	for page_name: StringName in PAGE_NAMES:
		var page: Control = _pages_root.get_node_or_null(NodePath(page_name)) as Control
		if page == null:
			push_error("书页节点缺失：%s" % page_name)
			return
		_pages[page_name] = page
		_page_data[page_name] = {}
	_connect_page_nav(_book_page)
	for page_name: StringName in PAGE_NAMES:
		_connect_page_nav(_pages[page_name] as Control)
	_page_switch_bar.configure(show_page)
	show_page(PAGE_NAMES[0])
	_setup_dialogue()
	print("[godot-project] ready")
	if DisplayServer.get_name() == "headless":
		var user_args: PackedStringArray = OS.get_cmdline_user_args()
		_force_layout_fail = user_args.has(FORCE_LAYOUT_FAIL_ARGUMENT)
		_handle_sp04_demo(user_args)
		if user_args.has(SELF_TEST_ARGUMENT):
			call_deferred("_run_self_test")
		if user_args.has(SP04_SELF_TEST_ARGUMENT):
			GameState.set_process(false)
			call_deferred("_run_sp04_self_test")
		if user_args.has("--sp07-self-test"):
			call_deferred("_run_sp07_self_test")
func _connect_page_nav(page: Control) -> void:
	var nav: Control = page.get_node_or_null("PageNav") as Control
	if nav != null and nav.has_signal("confirmed"):
		nav.confirmed.connect(_on_page_nav_confirmed.bind(nav))
func _on_page_nav_confirmed(node: Control, nav: Control) -> void:
	if nav.has_method("mark_used"):
		nav.mark_used(node)
func _handle_sp04_demo(user_args: PackedStringArray) -> void:
	for argument: String in user_args:
		if not argument.begins_with(SP04_DEMO_PREFIX):
			continue
		var value_text: String = argument.trim_prefix(SP04_DEMO_PREFIX)
		if not value_text.is_valid_float():
			print("[SP-04] DEMO FAIL invalid value=%s" % value_text)
			return
		_throat_placeholder.set_value(value_text.to_float())
		_print_sp04_demo("DEMO", _throat_placeholder)
		return
func _print_sp04_demo(prefix: String, bar: VitalBar) -> void:
	var color_text: String = bar.get_state_color().to_html(false)
	print("[SP-04] %s value=%d band=%s fill_height=%.2f color=#%s " % [
		prefix, roundi(bar.get_value()), bar.get_band(), bar.get_fill_height(), color_text])
	print("[SP-04] %s flash_count=%d top=%.2f vertical=%s" % [
		prefix, bar.get_flash_count(), bar.get_fill_top(), str(bar.size.y > bar.size.x)])
## 显示指定常驻页并切换空数据引用；未知页返回 false 且不改变当前页。
func show_page(name: StringName) -> bool:
	if not _pages.has(name):
		return false
	var was_battle: bool = _current_page == &"BattlePage"
	if name != _current_page:
		for page_name: StringName in PAGE_NAMES:
			_set_page_active(_pages[page_name] as Control, page_name == name)
	_current_page = name
	_current_data = _page_data[name]
	_page_switch_bar.refresh(name)
	if name == &"BattlePage" and not was_battle:
		GameState.enter_battle()
	elif was_battle and name != &"BattlePage":
		GameState.exit_battle()
	return true
## 必须先暂停再隐藏，否则既有导航的逐帧同步会丢掉当前候选。
func _set_page_active(page: Control, active: bool) -> void:
	var nav: Control = page.get_node_or_null("PageNav") as Control
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
func _run_sp04_self_test() -> void:
	if not await _wait_for_layout():
		var failures_before_wait: int = _sp04_failures
		_sp04_check(false, "wait_for_layout")
		_sp04_check(_sp04_failures > failures_before_wait, "layout_wait_failure_recorded")
		print("[SP-04] failures=%d" % _sp04_failures)
		get_tree().quit(1)
		return
	var bar: VitalBar = _throat_placeholder
	var initial_flash_count: int = bar.get_flash_count()
	for index: int in range(SP04_VALUES.size()):
		bar.set_value(SP04_VALUES[index])
		var passed: bool = _sp04_state_matches(bar, index)
		_print_sp04_result(passed, SP04_VALUES[index], bar)
	var before_rise: int = bar.get_flash_count()
	bar.set_value(10.0)
	_sp04_check(bar.get_flash_count() == before_rise, "rise_no_flash")
	var throat_label: Label = $Overlay/ThroatPlaceholder/ThroatText
	var actual_text: String = throat_label.text.replace("\n", "")
	print("[SP-04] text_read=%s" % actual_text)
	var expected_text: String = "斑さん还能唱"
	_sp04_check(actual_text == expected_text, "text_exact")
	_sp04_check(bar.get_text_content() == expected_text, "text_single_source")
	_sp04_check(throat_label.text == bar.get_vertical_text(), "text_vertical_layout")
	_sp04_check(throat_label.text.count("\n") == 5, "text_vertical_layout")
	_sp04_check(bar.get_bar_rect().size == Vector2(24.0, bar.size.y), "vertical_bar_geometry")
	_sp04_check(bar.global_position.x >= 1180.0, "left_boundary")
	_sp04_check(initial_flash_count == 0, "normal_start_no_flash")
	print("[SP-04] failures=%d" % _sp04_failures)
	get_tree().quit(0 if _sp04_failures == 0 else 1)
func _sp04_state_matches(bar: VitalBar, index: int) -> bool:
	var expected_value: float = SP04_VALUES[index]
	var expected_height: float = bar.size.y * expected_value / 100.0
	var expected_top: float = bar.size.y - expected_height
	var expected_flash_count: int = index
	var expected_color: Color = SP04_EXPECTED_COLORS[index]
	var actual_color: Color = bar.get_state_color()
	var geometry_ok: bool = is_equal_approx(bar.get_fill_height(), expected_height)
	geometry_ok = geometry_ok and is_equal_approx(bar.get_fill_top(), expected_top)
	var flash_ok: bool = bar.get_flash_count() == expected_flash_count
	var color_ok: bool = expected_color.is_equal_approx(actual_color)
	var expected_draw_color: Color = expected_color.lightened(0.22) if expected_flash_count > 0 else expected_color
	var draw_color_ok: bool = expected_draw_color.is_equal_approx(bar.get_draw_color())
	print("[SP-04] color value=%d expected=#%s actual=#%s" % [
		roundi(expected_value), expected_color.to_html(false), actual_color.to_html(false)])
	return geometry_ok and flash_ok and color_ok and draw_color_ok and bar.get_band() == SP04_BANDS[index]
func _print_sp04_result(passed: bool, expected_value: float, bar: VitalBar) -> void:
	var status: String = "PASS" if passed else "FAIL"
	print("[SP-04] %s value=%d band=%s fill_height=%.2f color=#%s flash_count=%d " % [
		status, roundi(expected_value), bar.get_band(), bar.get_fill_height(),
		bar.get_state_color().to_html(false), bar.get_flash_count()])
	print("[SP-04] %s top=%.2f vertical=%s" % [
		status, bar.get_fill_top(), str(bar.size.y > bar.size.x)])
	if not passed:
		_sp04_failures += 1
func _sp04_check(passed: bool, label: String) -> void:
	print("[SP-04] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_sp04_failures += 1
func _run_self_test() -> void:
	if not await _wait_for_layout():
		_failures += 1
		print("[SP-03] FAIL wait_for_layout")
		print("[SP-03] failures=%d" % _failures)
		get_tree().quit(1)
		return
	_original_scene = get_tree().current_scene
	_observe_main_scene()
	var option_label: Label = $Pages/ScenePage/TestOptions/OptionOne/Text
	print("[SP-03] font_size default=%d option=%d" % [
		get_theme_font_size(&"font_size", &"Label"), option_label.get_theme_font_size(&"font_size")])
	_test_visible_pages()
	_test_battle_freeze_boundaries()
	await _test_fixed_paper_and_throat()
	await _test_navigation_retention()
	_test_hidden_nav_does_not_consume()
	_test_unknown_page()
	_page_switch_bar.run_self_test(self, _check)
	_observe_main_scene()
	var current: Node = get_tree().current_scene
	var path: String = current.scene_file_path if current != null else "<null>"
	print("[SP-03] current_scene=%s" % path)
	_check(_main_scene_unchanged, "5 main_scene unchanged: %s" % path)
	print("[SP-03] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
func _wait_for_layout() -> bool:
	if _force_layout_fail:
		return false
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
		var manual_nav_count: int = 0
		for candidate: Node in $Pages.find_children("*", "Control", true, false):
			var nav: Control = candidate as Control
			if nav != null and nav.has_method("get_candidates") and nav.is_visible_in_tree() and nav.is_processing_input():
				manual_nav_count += 1
		_check(_active_navigation_count() == manual_nav_count, "nav_count_dynamic: %s" % page_name)
		if page_name != PAGE_NAMES[0]:
			_check(manual_nav_count == 0, "hidden_nav_not_counted: %s" % page_name)
func _active_navigation_count() -> int:
	var count: int = 0
	for candidate: Node in find_children("*", "Control", true, false):
		var nav: Control = candidate as Control
		if nav == null or not nav.has_method("get_candidates"):
			continue
		if nav.is_visible_in_tree() and nav.is_processing_input():
			count += 1
	return count
func _test_battle_freeze_boundaries() -> void:
	show_page(&"ScenePage")
	GameState.set_process(false)
	GameState.exit_battle()
	GameState.vital_now = GameState.vital_max
	GameState.drain_time(0.25)
	GameState.enter_battle()
	var entered: bool = GameState.is_frozen() and is_zero_approx(GameState.get_drain_accum())
	_check(entered, "freeze_on_enter_battle frozen=true accum=0")
	show_page(&"MapPage")
	var survived_map_switch: bool = GameState.is_frozen()
	show_page(&"BattlePage")
	var survived_battle_return: bool = GameState.is_frozen()
	_check(survived_map_switch and survived_battle_return,
		"freeze_survives_page_switch map=true battle=true")
	GameState.exit_battle()
	var drain_probe: float = GameState.get_knob("drain_flush_threshold") / GameState.get_knob("time_drain_per_second") * 0.5
	GameState.drain_time(drain_probe)
	var unfrozen_drains: bool = not GameState.is_frozen() and GameState.get_drain_accum() > 0.0
	_check(unfrozen_drains, "unfreeze_on_exit_battle frozen=false drains=true")
	show_page(&"ScenePage")
func _test_hidden_nav_does_not_consume() -> void:
	show_page(&"BattlePage")
	_scene_nav.set_process_input(true)
	var hidden_event: InputEventKey = InputEventKey.new()
	hidden_event.keycode = KEY_DOWN
	hidden_event.pressed = true
	get_viewport().push_input(hidden_event)
	var hidden_handled: bool = get_viewport().is_input_handled()
	hidden_event.pressed = false
	get_viewport().push_input(hidden_event)
	show_page(&"ScenePage")
	var before: Control = _scene_nav.get_selected() as Control
	var visible_event: InputEventKey = InputEventKey.new()
	visible_event.keycode = KEY_DOWN
	visible_event.pressed = true
	get_viewport().push_input(visible_event)
	var visible_handled: bool = get_viewport().is_input_handled()
	var moved: bool = _scene_nav.get_selected() != before
	visible_event.pressed = false
	get_viewport().push_input(visible_event)
	_check(not hidden_handled and visible_handled and moved,
		"hidden_nav_does_not_consume hidden=false visible=true moved=true")
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
	var interaction = _scene_nav.get_interactable(node)
	return interaction != null and interaction.read
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

func _run_sp07_self_test() -> void:
	var failures: int = await preload("res://scripts/sp07_selftest.gd").new().run(self)
	get_tree().quit(0 if failures == 0 else 1)

func _setup_dialogue() -> void:
	_dialogue = preload("res://scenes/ui/DialogueBox.tscn").instantiate()
	$Overlay.add_child(_dialogue)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var component_test: bool = false
	for argument: String in args:
		if argument in ["--sp03-self-test", "--sp04-self-test", "--sp05-self-test", "--sp06-self-test", "--sp07-self-test"]:
			component_test = true
	if not component_test:
		_dialogue.bind_s0(_pages[&"ScenePage"], show_page)
		var points: Node = preload("res://scripts/points.gd").new()
		$Overlay.add_child(points)
		points.configure(self, _dialogue)
	if DisplayServer.get_name() == "headless" and args.has("--sp11-self-test"):
		call_deferred("_run_sp11_self_test")

func _run_sp11_self_test() -> void:
	var failures: int = await preload("res://scripts/sp11_selftest.gd").new().run(self, _dialogue)
	get_tree().quit(0 if failures == 0 else 1)

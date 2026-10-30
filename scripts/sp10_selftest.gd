## SP-10：真实事件与实际状态断言；复用SP-23夹具，不修改旧自检。
extends RefCounted
const FIXTURE = preload("res://scripts/sp23_selftest.gd")
var h: RefCounted = FIXTURE.new()
var failures: int = 0
var results: Dictionary = {}
var clean: bool = true
var exits: int = 0
var opens: int = 0
var step_charges: int = 0
var shown: Array[String] = []
var old_battle_id: int = 0
const PROGRESS_FIELDS = ["_required_ids", "_completed_ids", "_progress_valid", "_p5_read", "_p5_won", "_exit_consumed"]

func run(state: Node) -> void:
	h.tree = state.get_tree()
	var root: Control = h.tree.current_scene
	var saved: Dictionary = {}
	for key: String in PROGRESS_FIELDS:
		var value: Variant = state.get(key)
		saved[key] = value.duplicate(true) if value is Dictionary else value
	var visible_before: bool = root.visible
	var input_before: bool = root.is_processing_unhandled_key_input()
	root.hide()
	root.set_process_unhandled_key_input(false)
	state.progress_changed.connect(_progress)
	state.exit_confirmed.connect(_exit)
	state.vital_changed.connect(_vital)
	for method: Callable in [_basic, _full_win, _early_win, _injured, _defeat_reset, _zero, _movement, _detour, _second, _book, _click_exit]:
		await _case(method)
	for key: String in PROGRESS_FIELDS:
		state.set(key, saved[key])
	state.progress_changed.disconnect(_progress)
	state.exit_confirmed.disconnect(_exit)
	state.vital_changed.disconnect(_vital)
	root.visible = visible_before
	root.set_process_unhandled_key_input(input_before)
	_check(34, clean and h.clean, "夹具释放、信号/进度/嗓子/冻结/处理/焦点恢复")
	_check(33, _safe_text("\n".join(shown)), "S2/S3实际文字无封路、未完成数或回程倒数")
	print("[SP10] assertions=%d failures=%d" % [results.size(), failures])
	h.tree.quit(0 if failures == 0 and results.size() == 48 else 1)

func _case(method: Callable) -> void:
	var before: int = GameState.get_signal_connection_list("progress_changed").size()
	await h._case(func() -> void:
		clean = clean and GameState.must_done == 0 and h.map._visited == {&"entry_exit": true}
		h.points.get_dialogue().line_started.connect(_capture_line)
		await method.call(), false)
	clean = clean and GameState.get_signal_connection_list("progress_changed").size() == before
	clean = clean and not is_instance_valid(h.main)

func _capture_line(key: String) -> void:
	shown.append(str(h.points.get_dialogue().get_lines()[key]["text"]))
func _progress(_done: int, open: bool) -> void:
	if open:
		opens += 1
func _exit() -> void:
	exits += 1
func _vital(_now: float, _max: float, reason: StringName) -> void:
	if reason == &"step":
		step_charges += 1
func _check(id: int, ok: bool, message: String) -> void:
	ok = ok and not results.has(id)
	results[id] = ok
	if not ok:
		failures += 1
	print("[SP10] %s %02d %s" % ["PASS" if ok else "FAIL", id, message])
func _key(code: int, pressed: bool = true, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	h.main.get_viewport().push_input(event)
func _press(code: int) -> void:
	_key(code)
	_key(code, false)
func _walk(route: Array) -> void:
	for id: StringName in route:
		clean = h.map.try_move_to(id) and clean
func _read_first(count: int) -> void:
	_walk([&"c1"])
	for i: int in range(1, count + 1):
		_walk([StringName("point%d" % i)])
		h._read()
func _win() -> void:
	for command: int in [1, 0, 1]:
		h._turn(command)
	h.b.submit_command(0)
func _return() -> void:
	h.b.advance_time(0.4)
	h.b._return.pressed.emit()
func _hint() -> String:
	var hint: Label = h.main.get_node("Pages/MapPage/ReturnHint")
	if hint.is_visible_in_tree():
		shown.append(hint.text)
		return hint.text
	return ""
func _button() -> Button:
	return h.main.get_node("Pages/MapPage/ExitConfirm")
func _safe_text(value: String) -> bool:
	var pattern: RegEx = RegEx.new()
	pattern.compile("门合上|通道关闭|回不去了|还差|[0-9零一二三四五六七八九十]+步")
	return pattern.search(value) == null

func _basic() -> void:
	_check(1, GameState.must_done == 0 and not GameState.exit_open and not _button().visible, "初始出口关闭")
	var counts: Array = []
	_walk([&"c1"])
	for id: StringName in [&"point1", &"point2", &"point3"]:
		_walk([id])
		h._read()
		counts.append([GameState.must_done, GameState.exit_open])
	_check(2, counts == [[1, false], [2, false], [3, false]], "前三点逐一计数")
	var notifications: int = opens
	h._read()
	_check(6, GameState.must_done == 3 and opens == notifications, "重复调查不增加进度")
	_walk([&"point2", &"point6"])
	h._read()
	_walk([&"point2", &"point3", &"point4", &"point7"])
	h._read()
	_check(7, GameState.must_done == 3 and not GameState.exit_open, "两个可选点不计必查")
	_walk([&"point4", &"point3", &"point2", &"point1", &"c1", &"entry_exit"])
	var before: Array = [exits, GameState.vital_now, h.main._current_page]
	_check(3, not h.map.confirm_selection() and [exits, GameState.vital_now, h.main._current_page] == before, "A8三点出口确认静默无效")
	_check(4, _hint() == "" and not _button().visible and _safe_text("\n".join(shown)), "A8无还差几个提示")
	_button().pressed.emit()
	_check(5, [exits, GameState.vital_now, h.main._current_page] == before, "直接触发出口按钮仍无效")

func _full_win() -> void:
	_read_first(5)
	_check(8, h.points.get_progress_count() == 5 and GameState.must_done == 4 and not GameState.exit_open, "点5已读未胜不完成")
	GameState.vital_now = 100.0
	var frame: int = Engine.get_process_frames()
	var notifications: int = opens
	_win()
	old_battle_id = h.b.get_instance_id()
	_check(11, GameState.must_done == 5 and GameState.exit_open and GameState.vital_now == 100.0 and Engine.get_process_frames() == frame, "满嗓子胜利同帧计第五点")
	h.b._settle_victory()
	h.b.submit_command(0)
	_check(16, GameState.must_done == 5 and opens == notifications + 1, "重复胜利不重复开放")
	h.b._return.pressed.emit()
	h.main.show_page(&"MapPage")
	_check(17, h.main._current_page == &"BattlePage" and not h.map.is_visible_in_tree() and h.b.elapsed < 0.4, "胜态锁期间不能抢先返回")
	var steps: int = h.map.get_step_count()
	_return()
	_check(18, h.map.get_current_node_id() == &"point5" and h.map.get_step_count() == steps and _hint() == "该回去了", "手动返回原点5并提示")
	await _normal_return()
	var before: Array = [exits, GameState.vital_now]
	_check(28, h.map.confirm_selection() and exits == before[0] + 1, "入口首次确认恰好一次")
	var consumed: Array = [exits, GameState.vital_now]
	var denied: bool = not h.map.confirm_selection()
	_button().pressed.emit()
	_check(29, denied and [exits, GameState.vital_now] == consumed, "重复确认与点击不重复离场")
	var visited: Dictionary = h.map._visited.duplicate()
	h.main.show_page(&"ScenePage")
	h.main.show_page(&"MapPage")
	_walk([&"c1", &"point1"])
	h._read()
	_walk([&"c1", &"entry_exit"])
	_check(31, GameState.must_done == 5 and h.map._visited == visited and not h.map.confirm_selection() and exits == consumed[0], "翻页回访调查保留进度与出口消费")

func _normal_return() -> void:
	var start_steps: int = h.map.get_step_count()
	var start_vital: float = GameState.vital_now
	var route: Array = [&"point4", &"point3", &"point2", &"point1", &"c1", &"entry_exit"]
	for i: int in range(GameState.NORMAL_RETURN_STEPS):
		_press(KEY_LEFT if i < 4 else KEY_UP)
		var expected: String = "该回去了" if i < 5 else "斑さん，我这边看完了。"
		_check(21 + i, h.map.get_current_node_id() == route[i] and GameState.vital_now == start_vital and _hint() == expected and _safe_text(_hint()) and _button().visible == (i == 5), "回程第%d次方向：位置/免费/无数字/出口权限" % (i + 1))
	var total: int = h.map.get_step_count()
	await h.tree.process_frame
	_check(27, total - start_steps == GameState.NORMAL_RETURN_STEPS and h.map.get_step_count() == total and GameState.vital_now == start_vital, "六次手动移动、零步费、空帧不代走")
	var page: Control = h.main.get_node("Pages/MapPage")
	page.hide()
	var denied: bool = not h.map.confirm_selection()
	page.show()
	GameState.set_frozen(true)
	denied = not h.map.confirm_selection() and denied
	GameState.set_frozen(false)
	GameState.vital_now = 0.0
	denied = not h.map.confirm_selection() and denied and _hint() == ""
	GameState.vital_now = start_vital
	_check(30, denied, "隐藏/冻结/归零均拒绝出口")

func _early_win() -> void:
	_walk(FIXTURE.ROUTE)
	h._read()
	_win()
	_check(9, GameState.must_done == 1 and not GameState.exit_open, "提前赢点5仅计一点")
	_return()
	for id: StringName in [&"point4", &"point3", &"point2", &"point1"]:
		_walk([id])
		h._read()
	_check(10, GameState.must_done == 5 and GameState.exit_open and h.map.get_current_node_id() == &"point1", "补齐末点原地开放")
	var steps: int = h.map.get_step_count()
	_press(KEY_UP)
	_press(KEY_UP)
	_check(39, h.map.get_step_count() - steps == 2 and _safe_text(_hint()) and h.map.confirm_selection(), "非点5补齐后两步可出口")
func _injured() -> void:
	_read_first(5)
	GameState.vital_now = 70.0
	var frame: int = Engine.get_process_frames()
	_win()
	h.b._settle_victory()
	_check(12, GameState.must_done == 5 and GameState.vital_now == 80.0 and h.events[0] == 1 and Engine.get_process_frames() == frame, "未满嗓子胜利同帧只回10")
func _defeat_reset() -> void:
	_walk(FIXTURE.ROUTE)
	h._read()
	h.b.player_hp = 10
	h._turn(0)
	_check(13, h.b.state == h.B.State.DEFEATED and GameState.must_done == 0 and not GameState.exit_open and _hint() == "", "败态不完成、不提示成功")
	var started: int = h.b.start_count
	h.map.reset_map()
	h.main.show_page(&"MapPage")
	_check(32, GameState.must_done == 0 and not GameState.exit_open and h.map._visited == {&"entry_exit": true} and h.b.start_count == started and h.b.state == h.B.State.DEFEATED and h.main._current_page == &"BattlePage", "reset只清数据、不解败态或战斗单场标记")
func _zero() -> void:
	_walk(FIXTURE.ROUTE)
	GameState.vital_now = GameState.get_knob("required_point_cost")
	h._read()
	_check(14, GameState.vital_now == 0.0 and h.b.start_count == 0 and GameState.must_done == 0 and not GameState.exit_open, "点5读完归零拒战")
	GameState.on_battle_win()
	_check(15, GameState.must_done == 0 and not GameState.exit_open, "归零胜利入口不能按回补后的值记进度")

func _movement() -> void:
	var moved: Array = [0]
	h.map.moved.connect(func(_a: StringName, _b: StringName, _c: int) -> void: moved[0] += 1)
	_key(KEY_DOWN, false)
	_key(KEY_DOWN, true, true)
	var ignored: bool = moved[0] == 0 and h.map.get_current_node_id() == &"entry_exit"
	_press(KEY_DOWN)
	var immediate: bool = h.map.get_current_node_id() == &"c1" and h.map.get_step_count() == 1 and h.map.get_pending_node_id() == &"" and moved[0] == 1
	_press(KEY_ENTER)
	_check(19, immediate and h.map.get_current_node_id() == &"c1" and h.map.get_step_count() == 1 and moved[0] == 1, "真实方向即移动、确认不补走")
	_check(40, ignored and moved[0] == 1, "释放与echo不走、一按只走一边")
	var charges: int = step_charges
	_press(KEY_UP)
	_check(35, GameState.vital_now == 99.0 and step_charges == charges and h.map.get_current_node_id() == &"entry_exit", "首次99、回访仍99且无步费事件")
	_walk([&"c1"])
	var before: float = GameState.vital_now
	var revealed: bool = h.map.get_revealed_ids().has(&"point1")
	_walk([&"point1"])
	_check(36, revealed and GameState.vital_now == before - 1.0, "显露不等于到达、首次仍收费")
	before = GameState.vital_now
	_walk([&"c1", &"point1"])
	var unread_free: bool = GameState.vital_now == before
	h._read()
	var cost: float = before - GameState.vital_now
	before = GameState.vital_now
	_walk([&"c1", &"point1"])
	_check(37, unread_free and cost == GameState.get_knob("required_point_cost") and GameState.vital_now == before, "未读/已读回访免费、首次调查照扣")
	_move_guards()
func _move_guards() -> void:
	var before: Array = [h.map.get_current_node_id(), h.map.get_step_count(), GameState.vital_now]
	var visited: Dictionary = h.map._visited.duplicate()
	var denied: bool = not h.map.try_move_to(&"absent") and not h.map.try_move_to(&"point5")
	_check(20, denied and [h.map.get_current_node_id(), h.map.get_step_count(), GameState.vital_now] == before, "非法/不相邻/未显露移动无效")
	_check(43, h.map._visited == visited and not h.map._visited.has(&"point5"), "无效移动不提前登记到达")
	GameState.set_frozen(true)
	denied = not h.map.try_move_to(&"c1")
	GameState.set_frozen(false)
	GameState.vital_now = 0.0
	denied = not h.map.try_move_to(&"c1") and denied
	_check(41, denied and h.map.get_current_node_id() == before[0], "免费回访仍拒绝冻结/归零")
	h.map.reset_map()
	GameState.vital_now = 0.5
	denied = not h.map.try_move_to(&"c1") and not h.map._visited.has(&"c1")
	GameState.vital_now = 100.0
	var paid: bool = h.map.try_move_to(&"c1")
	_check(42, denied and paid and GameState.vital_now == 99.0, "支付失败不登记、恢复后首次照扣")
	var data: Dictionary = h._data()
	var same: bool = data.size() == 26 and not data.has("exit_return_steps") and GameState.NORMAL_RETURN_STEPS == 6
	for key: String in FIXTURE.OLD:
		same = same and data[key] == FIXTURE.OLD[key]
	var battle_values: Array = [100, 100, 20, 20, 0.9, 1.1, 2.5, 1.25, 0.5, 40, 1, 0.4, 6.0, 3.0, 0.16, 0.03]
	for i: int in range(FIXTURE.KEYS.size()):
		same = same and data["battle_" + FIXTURE.KEYS[i]] == battle_values[i]
	_check(44, same, "原26旋钮值不变、六步使用常量")

func _detour() -> void:
	_read_first(5)
	_win()
	_return()
	var steps: int = h.map.get_step_count()
	for i: int in range(6):
		_press(KEY_LEFT if i % 2 == 0 else KEY_RIGHT)
	var off_exit: bool = h.map.get_current_node_id() == &"point5" and h.map.get_step_count() - steps == 6
	_press(KEY_LEFT)
	var continued: bool = h.map.get_current_node_id() == &"point4" and h.map.get_step_count() - steps == 7
	_walk([&"point3", &"point2", &"point1", &"c1", &"entry_exit"])
	_check(38, off_exit and continued and _safe_text(_hint()) and h.map.confirm_selection(), "六步未到继续第七步、更长回程仍可确认")
func _second() -> void:
	var fresh: bool = h.b.get_instance_id() != old_battle_id and h.b.start_count == 0 and GameState.must_done == 0
	_read_first(5)
	_win()
	_check(45, fresh and GameState.must_done == 5 and h.b.start_count == 1, "销毁旧Main并重建BattlePage后第二局真实完成")
func _book() -> void:
	_walk(FIXTURE.ROUTE)
	h._read()
	var before: Array = [h.map.get_current_node_id(), h.map.get_step_count(), h.b.turn_count]
	h.b._buttons[0].grab_focus()
	_press(KEY_RIGHT)
	var selected_only: bool = h.main.get_viewport().gui_get_focus_owner() == h.b._buttons[1] and h.b.turn_count == before[2]
	_press(KEY_ENTER)
	_check(46, selected_only and h.b.turn_count == before[2] + 1 and [h.map.get_current_node_id(), h.map.get_step_count()] == before.slice(0, 2), "书页方向只选、确认一次执行、地图不动")

func _click_exit() -> void:
	_read_first(5)
	_win()
	_return()
	for i: int in range(GameState.NORMAL_RETURN_STEPS):
		_press(KEY_LEFT if i < 4 else KEY_UP)
	await h.main._wait_for_layout()
	var button: Button = _button()
	_check(47, _exit_rects_clear(button), "exit_button_not_covered")
	var before: int = exits
	var page_before: StringName = h.main._current_page
	var center: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = center
		event.global_position = center
		h.main.get_viewport().push_input(event, true)
	_check(48, exits == before + 1 and page_before == &"MapPage" and h.main._current_page == page_before and h.map.is_visible_in_tree(), "exit_button_real_click_confirms")

func _exit_rects_clear(button: Button) -> bool:
	var exit_rect: Rect2 = button.get_global_rect()
	var viewport_rect: Rect2 = h.main.get_viewport().get_visible_rect()
	var bar: Control = h.main.get_node("Overlay/PageSwitchBar")
	var hint: Control = h.main.get_node("Pages/MapPage/ReturnHint")
	var vital: Control = h.main.get_node("Overlay/ThroatPlaceholder")
	var clear: bool = button.is_visible_in_tree() and exit_rect.has_area() and viewport_rect.encloses(exit_rect)
	print("[SP10] RECT ExitConfirm=%s center=%s" % [exit_rect, exit_rect.get_center()])
	print("[SP10] RECT PageSwitchBar=%s" % bar.get_global_rect())
	for control: Control in [bar.get_node("BookButton"), bar.get_node("MapButton"), bar.get_node("BattleButton"), hint, vital]:
		var other_rect: Rect2 = control.get_global_rect()
		print("[SP10] RECT %s=%s" % [control.name, other_rect])
		clear = not exit_rect.intersects(other_rect) and clear
	return clear and hint.is_visible_in_tree() and viewport_rect.encloses(hint.get_global_rect())

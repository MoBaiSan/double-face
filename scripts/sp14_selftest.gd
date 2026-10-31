## 方案 §7 的60项；真实流程、输入、持久文件与显式域夹具。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const S = C.S
var c: RefCounted
var root: Control
var results: Dictionary = {}
var failures: int = 0
var clean: bool = true
var synchronized: bool = true
var observed: Dictionary = {}
var first_step_count: int = 0
var exit_count: int = 0
var route_finished: bool = false

func run(host: Control) -> void:
	root = host
	for test: Callable in [_opening, _exploration, _zero_entry, _combat,
		_death, _victory, _partial_win, _early_win, _interfaces, _guards, _user_play, _free_pages]:
		await test.call()
	await _drop()
	await preload("res://scripts/sp11_selftest.gd").new().run_cr_cases(root, ck)
	await preload("res://scripts/u05_selftest.gd").new().run(root, ck)
	ck(55, synchronized and observed.size() >= 7, "state_changed_画面冻结同步")
	ck(58, first_step_count == 1 and exit_count == 1, "物理输入只消费一次")
	ck(59, clean, "夹具恢复状态会话进度焦点连接")
	ck(60, _source_contract() and route_finished, "show_page唯一换页_26键_A1")
	print("[SP-14] assertions=%d failures=%d" % [results.size(), failures])
	root.get_tree().quit(0 if failures == 0 and results.size() == 95 else 1)

func _fresh(initial: int = S.S2) -> void:
	await _drop()
	c = C.new()
	await c.create(root, initial)
	c.flow.checkpoint.path = "user://sp14_probe_%d.json" % c.main.get_instance_id()

func _drop() -> void:
	if c == null:
		return
	for row: Array in c.transitions:
		observed[row[1]] = true
		var page: StringName = &"BattlePage" if row[1] == S.S2B else &"ScenePage"
		if row[1] in [S.S2, S.S3]: page = &"MapPage"
		synchronized = synchronized and (row[1] == S.S5 or row[4] == page)
		synchronized = synchronized and row[5] == (row[1] in [S.S2B, S.S4, S.S5])
	var path: String = c.flow.checkpoint.path
	clean = await c.close() and clean
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	c = null

func ck(id: int, ok: bool, label: String) -> void:
	if results.has(id):
		ok = false
	results[id] = ok
	failures += int(not ok)
	print("[SP-14] %s %02d %s" % ["PASS" if ok else "FAIL", id, label])

func _opening() -> void:
	await _fresh(S.S0)
	var gs_text: String = FileAccess.get_file_as_string("res://scripts/gamestate.gd")
	var regex := RegEx.new()
	regex.compile("(?m)^var (_state|state)[: ]")
	var unique: bool = regex.search_all(gs_text).size() == 2
	for file: String in ["main", "map_grid", "points", "dialogue", "battle", "prologue_flow", "prologue_scene"]:
		unique = unique and regex.search(FileAccess.get_file_as_string("res://scripts/%s.gd" % file)) == null
	ck(1, unique, "主状态仅GameState存储")
	ck(2, GameState.state == S.S0 and c.main._current_page == &"ScenePage" and not c.map.is_visible_in_tree(), "开局S0书页")
	var vital: float = GameState.vital_now
	GameState.drain_time(60.0)
	ck(3, GameState.vital_now == vital, "S0_60秒不扣")
	var started: Array = []
	c.watch(c.main._dialogue.line_started, func(id: String): started.append(id))
	c.flow.configure(c.main)
	ck(4, started.is_empty() and c.main._dialogue.get_current_key() == "T101", "重复装配不重播E1")
	c.finish_sequence(c.main._dialogue)
	var page: Control = c.main.get_node("Pages/ScenePage")
	c.click(page.get_node("TestOptions/OptionOne"))
	page._finish_reading()
	ck(5, not GameState.event_started(&"E2") and GameState.state == S.S0, "可选阅读不推进旧曲")
	c.click(page.get_node("TestOptions/OptionTwo"))
	c.main._dialogue.finish_text()
	c.main._dialogue.advance()
	var still_reading: bool = not GameState.event_started(&"E2")
	c.finish_sequence(c.main._dialogue)
	ck(6, still_reading and GameState.event_started(&"E2") and c.main._dialogue.get_current_key() == "T116", "旧音响读完才E2")
	c.finish_sequence(c.main._dialogue)
	var e3: bool = GameState.event_done(&"E2") and c.event_count(&"E3", false) == 1
	c.finish_sequence(c.main._dialogue)
	ck(7, e3 and GameState.event_done(&"E3") and c.event_count(&"E4", false) == 1, "E2_E3_E4按完成串接")
	c.click(c.main.get_node("Overlay/PageSwitchBar/MapButton"))
	c.key(KEY_PAGEDOWN)
	ck(8, GameState.state == S.S0 and c.main._current_page == &"BattlePage" and c.main._dialogue.get_current_key() == "T121", "R4可翻页但状态与当前台词不变")
	c.finish_sequence(c.main._dialogue)
	ck(9, GameState.state == S.S1 and c.flow.content.get_node("Departure").is_visible_in_tree() and c.main._dialogue.get_current_key() == "T122", "S1独立出发内容")
	_departure()

func _departure() -> void:
	var before: float = GameState.vital_now
	GameState.drain_time(60.0)
	ck(10, GameState.vital_now == before, "S1_60秒不扣")
	c.key(KEY_DOWN)
	ck(11, c.map.get_current_node_id() == &"entry_exit" and c.map.get_step_count() == 0 and GameState.vital_now == before, "S1未完方向无效")
	c.finish_sequence(c.main._dialogue)
	c.finish_sequence(c.main._dialogue)
	c.key(KEY_DOWN, false)
	c.key(KEY_DOWN, true, true)
	ck(13, GameState.state == S.S1 and c.map.get_step_count() == 0, "释放与echo不出发")
	c.key(KEY_DOWN)
	first_step_count = c.map.get_step_count()
	ck(12, GameState.state == S.S2 and c.map.get_current_node_id() == &"c1" and first_step_count == 1 and GameState.vital_now == before - 1.0, "首个方向一次到c1扣1")

func _exploration() -> void:
	await _fresh()
	GameState.drain_time(60.0)
	ck(14, is_equal_approx(GameState.vital_now, 95.2), "S2_60秒扣4.8")
	c.walk([&"c1", &"point1"])
	c.map.confirm_selection()
	var before: float = GameState.vital_now
	GameState.drain_time(1.0)
	ck(15, c.points.get_dialogue().is_playing() and is_equal_approx(before - GameState.vital_now, 0.08), "调查阅读继续耗时")
	c.finish_sequence(c.points.get_dialogue())
	before = GameState.vital_now
	var steps: int = c.map.get_step_count()
	c.walk([&"c1", &"point1", &"point2"])
	var invalid: bool = c.map.try_move_to(&"point5")
	ck(16, not invalid and GameState.vital_now == before - 1 and c.map.get_step_count() == steps + 3 and not c.map._visited.has(&"point5"), "首访1回访0非法0")
	c.read_point()
	c.map.try_move_to(&"point3")
	c.read_point()
	c.walk([&"point2", &"point1", &"c1", &"entry_exit"])
	c.key(KEY_ENTER)
	c.main.get_node("Pages/MapPage/ExitConfirm").pressed.emit()
	ck(17, GameState.must_done == 3 and GameState.state == S.S2 and not GameState._exit_consumed, "三查点出口键盘按钮均无效")
	c.walk_to(&"point6")
	c.read_point()
	var count: int = c.event_count(&"E6")
	c.read_point()
	ck(18, GameState.must_done == 3 and c.map.get_interactable(&"point6").read and c.event_count(&"E6") == count, "可选与重复不增必查或E6")

func _zero_entry() -> void:
	await _fresh()
	c.walk(C.ROUTE)
	c.map.confirm_selection()
	ck(19, GameState.state == S.S2 and c.battle.start_count == 0 and not GameState._p5_read, "p5未读完不开战")
	GameState.vital_now = 6.0
	c.finish_sequence(c.points.get_dialogue())
	ck(20, GameState.state == S.S5 and GameState.vital_now == 0.0 and c.battle.start_count == 0, "p5扣至0拒战")

func _combat() -> void:
	await _fresh()
	c.walk(C.ROUTE)
	c.read_point()
	ck(21, GameState.state == S.S2B and c.main._current_page == &"BattlePage" and not c.map.is_visible_in_tree(), "S2b独立战斗页")
	var vital: float = GameState.vital_now
	GameState.drain_time(60.0)
	c.battle.advance_time(1.0)
	ck(22, GameState.vital_now == vital and GameState.is_frozen(), "S2b等待动作都冻条")
	c.map._interactions.investigated.emit(&"point5")
	ck(23, c.battle.start_count == 1 and c.event_count(&"E15") == 1, "E15重入只开战一次")
	var samples: Array = [0]
	c.battle.random_sample = func(): samples[0] += 1; return 1.0
	_turn(0)
	var early: bool = not GameState.event_started(&"E16")
	c.battle.player_hp = 65
	var seen: Array = []
	c.watch(c.battle.incoming_damage, func(_product: float, hp: int, _max: int): seen.append(hp))
	_turn(0)
	_turn(2)
	ck(24, early and c.event_count(&"E16") == 1 and seen[0] == 65, "E16预测半血前一次通知")
	ck(25, samples[0] == 5 and c.battle.player_hp == 35 and c.battle.enemy_hp == 60, "E16不改伤害或随机次数")

func _turn(command: int) -> void:
	c.battle.submit_command(command)
	c.battle.advance_time(0.4)
	c.battle.advance_time(0.4)

func _death() -> void:
	await _fresh()
	c.walk(C.ROUTE)
	c.read_point()
	var vital: float = GameState.vital_now
	c.battle.player_hp = 0
	c.battle.enemy_hp = 0
	c.battle._settle_victory()
	c.battle._defeat()
	ck(26, GameState.state == S.S5 and GameState.vital_now == vital and GameState.must_done == 0, "同帧双零败优先")
	GameState.vital_now = 0.0
	c.battle.battle_lost.emit()
	ck(27, c.event_count(&"E10") == 1, "嗓子与战斗同帧失败合并")

func _victory() -> void:
	await _fresh()
	c.read_first()
	GameState.vital_now = 100.0
	c.battle.random_sample = func(): return 1.0
	for index: int in range(4): _turn(0)
	c.battle.submit_command(0)
	ck(28, GameState.must_done == 5 and c.event_count(&"E17", false) == 1 and GameState.vital_now == 100.0, "满嗓胜利同帧p5与E17")
	ck(33, GameState.state == S.S2B and not c.map.is_visible_in_tree(), "战斗内满五不抢页")
	c.return_battle()
	var locked: bool = GameState.state == S.S2B and c.main._current_page == &"BattlePage"
	c.battle.advance_time(0.4)
	GameState.drain_time(60.0)
	ck(30, locked and GameState.state == S.S2B and GameState.vital_now == 100.0, "胜利锁与等待仍冻S2b")
	c.return_battle()
	c.return_battle()
	ck(31, GameState.state == S.S3 and c.map.get_current_node_id() == &"point5" and c.map.is_visible_in_tree() and c.event_count(&"E17") == 1, "一次返回原点并同步S3")
	await _return_route()

func _return_route() -> void:
	var hint: Label = c.main.get_node("Pages/MapPage/ReturnHint")
	ck(34, hint.is_visible_in_tree() and hint.text == "该回去了" and c.map.get_step_count() == 6, "S3只提示不代走无数字")
	var steps: int = c.map.get_step_count()
	for index: int in range(6): c.key(KEY_LEFT if index % 2 == 0 else KEY_RIGHT)
	var off_exit: bool = c.map.get_current_node_id() == &"point5"
	c.key(KEY_LEFT)
	ck(36, off_exit and c.map.get_current_node_id() == &"point4" and c.map.get_step_count() == steps + 7, "第六步未到可走第七步")
	c.key(KEY_RIGHT)
	var vital: float = GameState.vital_now
	GameState.drain_time(60.0)
	steps = c.map.get_step_count()
	for index: int in range(6): c.key(KEY_LEFT if index < 4 else KEY_UP)
	ck(35, is_equal_approx(vital - GameState.vital_now, 4.8) and c.map.get_step_count() == steps + 6 and c.map.get_current_node_id() == &"entry_exit", "S3耗时4.8且六次回访免费")
	await c.main._wait_for_layout()
	var presses: Array = [0, 0]
	c.watch(GameState.exit_confirmed, func(): presses[0] += 1)
	for button: Button in c.main.get_node("Overlay/PageSwitchBar")._buttons:
		c.watch(button.pressed, func(): presses[1] += 1)
	c.click(c.main.get_node("Pages/MapPage/ExitConfirm"))
	exit_count = presses[0]
	ck(37, exit_count == 1 and presses[1] == 0 and GameState.state == S.S4 and c.main._dialogue.get_current_key() == "T161", "出口真实点击进S4未碰翻页栏")
	c.map.confirm_selection()
	c.main.get_node("Pages/MapPage/ExitConfirm").pressed.emit()
	ck(38, presses[0] == 1 and c.event_count(&"E9", false) == 1 and c.flow.checkpoint.attempts == 0, "重复出口不重播不重存")
	_ending()

func _ending() -> void:
	var vital: float = GameState.vital_now
	GameState.drain_time(60.0)
	ck(39, GameState.vital_now == vital and not c.map.try_move_to(&"c1"), "S4停止耗时与移动")
	ck(40, GameState.state == S.S4 and c.main._dialogue.get_current_key() == "T161" and not c.map.is_visible_in_tree(), "T161只在离开地图后")
	c.finish_sequence(c.main._dialogue)
	route_finished = GameState.state == S.S6
	ck(41, route_finished and c.main._current_page == &"ScenePage" and not c.main._dialogue.is_playing(), "R10结束自动S6无章节")
	c.flow._on_sequence_finished(false)
	ck(42, c.flow.checkpoint.attempts == 1 and c.flow.checkpoint.writes == 1, "任务完成只自动存一次")
	var text: String = FileAccess.get_file_as_string(c.flow.checkpoint.path)
	var doc: Variant = JSON.parse_string(text)
	ck(43, doc is Dictionary and doc.get("checkpoint") == "task_complete" and doc.get("progress", {}).get("safehouse_reached") == true, "真实检查点读回进度")
	var failed = load("res://scripts/prologue_checkpoint.gd").new()
	failed.path = c.flow.checkpoint.path
	failed.replace_file = func(_a: String, _b: String): return ERR_BUSY
	var ok: bool = failed.write_once(999, &"task_complete", {"safehouse_reached": false})
	ck(44, not ok and failed.last_error == ERR_BUSY and failed.writes == 0 and failed.attempts == 1 and FileAccess.get_file_as_string(failed.path) == text, "保存失败保留旧文件不伪成功")
	GameState.drain_time(60.0)
	ck(45, GameState.vital_now == vital and not c.main.get_node("Pages/ScenePage/TestOptions").visible and c.flow.content.get_node("Safehouse").is_visible_in_tree(), "S6不扣且隐藏S0选项")
	var finished: Array = []
	c.watch(c.flow.prologue_finished, func(): finished.append(true))
	ck(46, not GameState.event_done(&"E12") and not c.flow.finish_safehouse(&"E14", GameState.run_id) and finished.is_empty(), "后续内容未装不完成序章")
	c.click(c.flow.safe_room.get_node("Objects/Sofa"))
	c.finish_sequence(c.main._dialogue)
	c.click(c.flow.safe_room.get_node("Objects/Sofa"))
	var door: bool = c.flow.content.request_door()
	c.flow.finish_safehouse(&"E14", GameState.run_id)
	ck(47, door and finished.size() == 1 and not GameState.event_done(&"E13"), "上药完成即可收尾信赖可选")

func _partial_win() -> void:
	await _fresh()
	c.walk(C.ROUTE)
	c.read_point()
	GameState.vital_now = 85.0
	c.win()
	c.battle._settle_victory()
	ck(29, GameState.vital_now == 95.0 and c.event_count(&"E17", false) == 1, "胜利仅一次加10")

func _early_win() -> void:
	await _fresh()
	c.walk(C.ROUTE)
	c.read_point()
	c.win()
	c.return_battle()
	var early: bool = GameState.state == S.S2 and GameState.must_done == 1
	for point: StringName in [&"point4", &"point3", &"point2", &"point1"]:
		c.map.try_move_to(point)
		c.read_point()
	ck(32, early and GameState.state == S.S3 and GameState.must_done == 5 and c.map.get_current_node_id() == &"point1", "p5先完成末点原地转S3")

func _interfaces() -> void:
	await _fresh()
	preload("res://scripts/sp15_test_context.gd").legacy_interfaces(c, ck, _retry_starts_battle)

func _retry_starts_battle() -> bool:
	if not c.walk(C.ROUTE):
		return false
	var position: Vector2 = c.map.get_global_transform_with_canvas() * c.map.get_point_position_for_test(&"point5")
	var motion := InputEventMouseMotion.new()
	motion.position = position
	c.main.get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		c.main.get_viewport().push_input(event, true)
	var reading: bool = c.points.get_dialogue().is_playing()
	c.points.get_dialogue().finish_text()
	c.key(KEY_ENTER)
	var links: int = 0
	for connection: Dictionary in c.map._interactions.get_signal_connection_list("investigated"):
		links += int(connection["callable"] == Callable(c.battle, "_on_investigated"))
	return reading and c.map.get_interactable(&"point5").read and c.battle.start_count == 1 and links == 1 \
		and GameState.state == S.S2B and c.main._current_page == &"BattlePage" \
		and c.battle.is_visible_in_tree() and not c.map.is_visible_in_tree()

func _guards() -> void:
	await _fresh()
	var before: Array = [GameState.state, c.main._current_page, GameState.is_frozen()]
	var rejected: bool = not GameState.request_transition(&"r4_finished")
	ck(54, rejected and before == [GameState.state, c.main._current_page, GameState.is_frozen()], "非法边拒绝且无部分写入")
	var old_run: int = GameState.run_id
	C.enter_domain(c.main, S.S0)
	for id: StringName in [&"E1", &"E2", &"E3", &"E4"]: GameState.record_event(id, true)
	ck(56, not c.flow.finish_s0(&"r4_finished", old_run) and GameState.state == S.S0, "旧会话完成回调不推进")
	C.enter_domain(c.main, S.S2)
	GameState.drain_time(0.1)
	var accumulated: bool = GameState.get_drain_accum() > 0.0
	c.walk(C.ROUTE)
	c.read_point()
	var cleared: bool = GameState.get_drain_accum() == 0.0
	c.win()
	c.return_battle()
	var vital: float = GameState.vital_now
	GameState.drain_time(0.02)
	ck(57, accumulated and cleared and GameState.vital_now == vital, "离开窗口清零头返回不补扣")

func _user_play() -> void:
	await _fresh(S.S0)
	preload("res://scripts/sp11_selftest.gd").run_story_input_test(c, ck)

func _free_pages() -> void:
	for state: int in S.values():
		await _fresh(state)
		if state == S.S5:
			ck(68 + state, preload("res://scripts/sp15_test_context.gd").legacy_s5(c), "失败模态真实键鼠不翻页_保持S5冻结")
			continue
		var before: Array = [GameState.state, GameState.run_id, GameState.is_frozen(), c.main._dialogue.get_current_key()]
		var ok: bool = c.main.get_node("Overlay/PageSwitchBar")._real_page_cycle(c.main)
		ck(68 + state, ok and before == [GameState.state, GameState.run_id, GameState.is_frozen(), c.main._dialogue.get_current_key()], "无战败实例各状态真实翻页_保持状态与剧情_%d" % state)
	await _fresh()
	c.walk(C.ROUTE)
	c.read_point()
	var bar: Control = c.main.get_node("Overlay/PageSwitchBar")
	var before: Array = [c.battle.turn_count, c.battle.enemy_hp, c.battle.player_hp, GameState.vital_now]
	var free: bool = bar._real_page_cycle(c.main)
	ck(76, free and GameState.state == S.S2B and GameState.is_frozen() and before == [c.battle.turn_count, c.battle.enemy_hp, c.battle.player_hp, GameState.vital_now], "真实战斗中翻页不结算不解冻")
	c.win()
	free = bar._real_page_cycle(c.main)
	ck(77, free and GameState.state == S.S2B and not c.battle._returned and GameState.is_frozen(), "胜态翻页不冒充返回")
	await _fresh()
	c.walk(C.ROUTE)
	c.read_point()
	c.battle.player_hp = 10
	c.battle.submit_command(0)
	c.main._flow.request_page(&"ScenePage")
	c.battle.advance_time(0.4)
	var locked: bool = c.main._current_page == &"BattlePage"
	for key: Key in [KEY_PAGEDOWN, KEY_PAGEUP]:
		c.key(key)
		locked = locked and c.main._current_page == &"BattlePage"
	for button: Button in c.main.get_node("Overlay/PageSwitchBar")._buttons:
		c.click(button)
		locked = locked and c.main._current_page == &"BattlePage"
	ck(78, locked and GameState.state == S.S5 and c.battle.player_hp == 0 and c.battle._return.disabled and GameState.is_frozen(), "翻走后战败自动回战斗且真实键鼠锁页")

func _source_contract() -> bool:
	for file: String in ["main", "prologue_flow", "prologue_scene", "battle", "dialogue", "gamestate"]:
		var text: String = FileAccess.get_file_as_string("res://scripts/%s.gd" % file)
		if text.contains("change_scene_to_file") or text.contains("reload_current_scene"):
			return false
	var knobs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/knobs.json"))
	return knobs is Dictionary and knobs.size() == 26


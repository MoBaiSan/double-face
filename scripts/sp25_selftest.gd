## SP-25：32个固定汇总；CASE不计PASS。真实输入、回执和独立固定期望。
extends SceneTree
var C: Script
var H: Script
const S: Dictionary = {"S0":0,"S1":1,"S2":2,"S2B":3,"S3":4,"S4":5,"S5":6,"S6":7}
var refusing_main: GDScript
var rejecting_main: GDScript
const FULL_OPENING: Array = ["T101","T102","T103","T104","T105","T106","T112","T113","T114","T116","T117","T118","T121"]
const DEPARTURE: Array = ["T195","T122","T123","T124","T125","T126","T127","T128","T129","T130","T131"]
var host: Control
var state: Node
var h: RefCounted
var results: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# --script入口编译早于Autoload注册；仅测试替身在注册后编译，源码固定且不落文件。
	C = load("res://scripts/prologue_test_context.gd")
	H = load("res://scripts/sp19_test_context.gd")
	refusing_main = GDScript.new()
	refusing_main.source_code = 'extends "res://scripts/main.gd"\nvar refuse_map: bool = false\nfunc show_page(page: StringName) -> bool:\n\tif refuse_map and page == &"MapPage":\n\t\treturn false\n\treturn super.show_page(page)\n'
	var refusing_ok: bool = refusing_main.reload() == OK
	rejecting_main = GDScript.new()
	rejecting_main.source_code = 'extends "res://scripts/main.gd"\nfunc _ready() -> void:\n\tdialogue_factory = func():\n\t\tvar player: Control = load("res://scenes/ui/DialogueBox.tscn").instantiate()\n\t\tplayer.set_script(load("res://scripts/sp11_selftest.gd").RejectingPlayer)\n\t\treturn player\n\tsuper._ready()\n'
	if rejecting_main.reload() != OK or not refusing_ok:
		quit(1)
		return
	host = load("res://scenes/Main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	state = root.get_node("GameState")
	h = H.new()
	await process_frame
	for test: Callable in [_geometry, _sofa, _return_and_free, _background, _departure, _exit, _domains, _opening, _retry]:
		await test.call()
	await h.close()
	if not h.clean or results.size() != 32:
		failures += 1
	print("[SP-25] assertions=%d failures=%d" % [results.size(), failures])
	quit(0 if failures == 0 else 1)

func ck(id: int, ok: bool, label: String) -> void:
	ok = ok and not results.has(id)
	results[id] = ok
	failures += int(not ok)
	print("[SP-25] %s %02d %s" % ["PASS" if ok else "FAIL", id, label])

func case_result(id: String, ok: bool) -> bool:
	print("[SP-25 CASE] %s %s" % [id, "OK" if ok else "BAD"])
	return ok

func fresh(initial: int = S.S6) -> void:
	await h.fresh(host, initial)
	# 使用只属于本进程的临时档；不覆盖玩家存档。
	h.c.flow.checkpoint.path = "user://sp25_%d_%d.json" % [OS.get_process_id(), h.serial]
	h.paths.append(h.c.flow.checkpoint.path)

func snapshot() -> Array:
	return [state.capture_session(), h.c.map.get_current_node_id(), h.c.map.get_step_count(), h.c.map.get_revealed_ids(), h.c.map._visited.duplicate(), h.c.flow.checkpoint.writes, h.c.flow.checkpoint.attempts]

func player_snapshot() -> Array:
	return [h.player._keys.duplicate(), h.player._index, h.player._typed, h.player._elapsed, h.player.skip_allowed, h.player.is_playing()]

func raw_lines() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))

func finish_opening() -> void:
	for i: int in range(4):
		h.c.read_sequence_input()

func _geometry() -> void:
	await fresh(S.S0)
	var grid: Control = h.room.grid
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/safe_room_grid.json"))
	var ok: bool = grid.valid and grid.dimensions == Vector2i(5,5) and Vector2(grid.dimensions) == h.c.map.get_grid_size()
	ok = ok and grid.objects.keys() == ["Sofa","Speaker","Door"] and grid.objects.Sofa.cell == Vector2i(1,3) and grid.objects.Speaker.cell == Vector2i(1,1) and grid.objects.Door.cell == Vector2i(4,2) and grid.initial_cell == Vector2i(2,2) and grid.return_target == "Door"
	var bad: Array = []
	var missing: Dictionary = layout.duplicate(true)
	missing.objects.remove_at(1)
	bad.append(missing)
	var overlap: Dictionary = layout.duplicate(true)
	overlap.objects[1].cell = [1,3]
	bad.append(overlap)
	var bounds: Dictionary = layout.duplicate(true)
	bounds.objects[1].cell = [5,0]
	bad.append(bounds)
	var fraction: Dictionary = layout.duplicate(true)
	fraction.objects[1].cell = [1.5,1]
	bad.append(fraction)
	var no_initial: Dictionary = layout.duplicate(true)
	no_initial.erase("initial_cell")
	bad.append(no_initial)
	for invalid: Dictionary in bad:
		var probe = load("res://scripts/safe_room_grid.gd").new()
		ok = not probe.configure(Vector2(5,5), invalid) and not probe.valid and not probe.last_error.is_empty() and ok
		probe.free()
	ck(1, ok, "同源尺寸三目标及坏布局拒绝")
	var probe = load("res://scripts/safe_room_grid.gd").new()
	root.add_child(probe)
	h.c.flow.set_process_input(false)
	probe.configure(Vector2(5,5), layout)
	var geometric: bool = true
	for box: Vector2 in [Vector2(500,500), Vector2(800,400)]:
		probe.size = box
		var pitch: float = 100.0 if box.x == 500 else 80.0
		var origin: Vector2 = Vector2(50,50) if box.x == 500 else Vector2(240,40)
		for y: int in range(5):
			for x: int in range(5):
				geometric = probe.center(Vector2i(x,y)).is_equal_approx(origin + Vector2(x,y) * pitch) and geometric
	ck(2, geometric and probe.objects.size() == 3 and probe.get("revealed") == null, "两尺寸25中心固定期望全貌")
	probe.size = Vector2(500,500)
	probe.position = Vector2(600,0)
	probe.z_index = 100
	var selections: Array = []
	var confirmations: Array = []
	probe.cell_selected.connect(func(cell: Vector2i): selections.append(cell))
	probe.object_confirmed.connect(func(id: String): confirmations.append(id))
	var clicks: bool = true
	probe.select_cell(Vector2i(4,4))
	selections.clear()
	for y: int in range(5):
		for x: int in range(5):
			var before: int = selections.size()
			_click_position(probe.global_position + probe.center(Vector2i(x,y)))
			clicks = clicks and probe.current_cell == Vector2i(x,y) and selections.size() == before + 1
	ck(3, clicks and confirmations == ["Door"] and selections.size() == 25, "真实Viewport25格各一次Door单确认")
	var edges: bool = probe.cell_at(Vector2(0,0)) == Vector2i(0,0) and probe.cell_at(Vector2(99.99,99.99)) == Vector2i(0,0) and probe.cell_at(Vector2(100,100)) == Vector2i(1,1)
	edges = edges and probe.cell_at(Vector2(499.99,499.99)) == Vector2i(4,4)
	for point: Vector2 in [Vector2(-0.01,0),Vector2(500,0),Vector2(0,500),Vector2(500,500)]:
		edges = probe.cell_at(point) == Vector2i(-1,-1) and edges
	ck(4, edges, "共边四角半开边界外侧拒绝")
	probe.queue_free()
	h.c.flow.set_process_input(true)
	await process_frame
	var before_map: Array = snapshot()
	grid.select_cell(Vector2i(0,0))
	h.key(KEY_LEFT)
	h.key(KEY_UP)
	var keyboard: bool = grid.current_cell == Vector2i(0,0)
	for code: Key in [KEY_RIGHT,KEY_DOWN,KEY_LEFT,KEY_UP]:
		h.key(code)
	keyboard = keyboard and grid.current_cell == Vector2i(0,0)
	h.c.key(KEY_RIGHT,false)
	h.c.key(KEY_RIGHT,true,true)
	_click_position(grid.global_position + grid.center(Vector2i(4,4)), MOUSE_BUTTON_RIGHT)
	ck(5, keyboard and grid.current_cell == Vector2i(0,0) and snapshot() == before_map, "方向边界释放echo右键不改地图")
	var ordinary: bool = true
	var count: int = 0
	for y: int in range(5):
		for x: int in range(5):
			var cell := Vector2i(x,y)
			if grid.object_at(cell) != "":
				continue
			h.c.click_cell(cell)
			h.key(KEY_ENTER)
			count += 1
			ordinary = grid.current_cell == cell and ordinary
	ck(6, ordinary and count == 22 and snapshot() == before_map and h.lines.is_empty() and h.room.get_node("Status/ProgressNotice").text.is_empty(), "22普通格仅移动")

func _click_position(position: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = button
		event.pressed = pressed
		root.push_input(event,true)

func _sofa() -> void:
	await fresh()
	h.c.click_cell(Vector2i(1,3))
	var select_only: bool = not h.player.is_playing() and h.lines.is_empty()
	h.key(KEY_ENTER)
	h.finish_reading()
	ck(7, select_only and h.ids() == h.room.TRUST_IDS and state.event_done(&"E13") and not state.event_done(&"E12") and not h.room.interaction("Sofa").read, "归来沙发首遍12句")
	h.lines.clear()
	h.click("Sofa")
	var medical: bool = h.room.medical.visible and h.player.get_current_key() == "T176"
	h.c.click(h.room.medical.frame)
	medical = medical and not h.room.medical.visible and h.player.get_current_key() == "T176"
	h.player.finish_text()
	medical = medical and h.player.get_visible_text() == H.T176 and h.player._speaker.text == "琥珀"
	h.key(KEY_ENTER)
	h.player.finish_text()
	medical = medical and h.player.get_visible_text() == H.T177 and h.player._speaker.text == "斑"
	h.key(KEY_ENTER)
	ck(8, medical and h.ids() == ["T176","T177"] and h.room.interaction("Sofa").read and not state.event_done(&"E12"), "第二遍原医疗原文不提前确认")
	h.click("Sofa")
	h.click("Sofa")
	h.click("Sofa")
	ck(9, h.c.event_count(&"E12") == 1 and h.c.event_count(&"E13") == 1 and h.c.event_count(&"E13",false) == 1 and h.ids() == ["T176","T177"], "第三确认一次后续不重复")
	await fresh()
	h.click("Sofa")
	var start: Array = player_snapshot()
	for id: String in ["Sofa","Speaker","Door"]:
		h.click(id)
	var busy: bool = player_snapshot() == start and h.exit_service.accepted == 0
	busy = h.page_inputs() and busy
	h.finish_reading()
	await process_frame
	ck(10, busy and h.room.grid.current_cell == Vector2i(1,3) and root.gui_get_focus_owner() == h.room.grid and not state.event_done(&"E12"), "忙态不换序翻页结束回沙发")

func full_return() -> bool:
	var ok: bool = await h.c.opening_to_s1()
	ok = h.c.departure_to_s2() and ok
	for number: int in range(1,6):
		ok = h.c.walk_to(StringName("point%d" % number)) and ok
		ok = h.c.read_point() and ok
	h.c.win()
	h.c.return_battle()
	ok = state.state == S.S3 and ok
	ok = h.c.walk_to(&"entry_exit") and ok
	await h.c.main._wait_for_layout()
	h.c.click(h.c.main.get_node("Pages/MapPage/ExitConfirm"))
	h.c.read_sequence_input()
	return ok and state.state == S.S6 and h.c.flow.checkpoint.writes == 1

func _return_and_free() -> void:
	await fresh(S.S0)
	var returned: bool = await full_return()
	var entering: Array = [h.player._keys.duplicate(), h.c.flow.checkpoint.writes, h.exit_service.accepted]
	await process_frame
	await process_frame
	ck(11, returned and h.room.grid.current_cell == Vector2i(4,2) and not h.player.is_playing() and not h.room.interaction("Door").read and entering == [h.player._keys.duplicate(),h.c.flow.checkpoint.writes,h.exit_service.accepted], "真实回程落门两帧不自动确认")
	h.c.click_cell(Vector2i(0,0))
	var same: bool = h.page_inputs() and h.room.grid.current_cell == Vector2i(0,0)
	h.read_trust()
	h.c.flow.content.present(S.S6)
	same = same and state.event_done(&"E13") and h.room.grid.current_cell == Vector2i(1,3)
	C.enter_domain(h.c.main,S.S0)
	same = same and h.room.grid.current_cell == Vector2i(2,2) and not h.room.interaction("Sofa").read and not state.event_started(&"E13")
	await h.c.opening_to_s1()
	ck(12, same and h.room.grid.current_cell == Vector2i(1,1) and state.state == S.S1, "翻页保格S1不重置新run清空")
	var free: bool = true
	for phase: int in [S.S0,S.S1,S.S6]:
		await fresh(phase)
		state.vital_now = 73.0
		state.set_process(true)
		var before: Array = snapshot()
		var pays: int = state._point_pay_calls
		for pass_number: int in range(2):
			h.room.grid.select_cell(Vector2i(0,0))
			for y: int in range(5):
				for x: int in range(5):
					if h.room.grid.object_at(Vector2i(x,y)) == "":
						h.c.click_cell(Vector2i(x,y))
					if x < 4: h.key(KEY_RIGHT)
				if y < 4: h.key(KEY_DOWN)
		await process_frame
		await process_frame
		free = free and state.is_processing() and state.vital_now == 73.0 and state._point_pay_calls == pays and snapshot() == before
	ck(13, free, "三阶段真实帧两轮纯移动不收费")

func _background() -> void:
	await fresh(S.S0)
	var art: Control = h.room.visual
	ck(14, art.artwork == null and art.placeholder_text == "安全屋" and art.get_node("Placeholder").text == "安全屋" and art.get_node("Placeholder").visible and not art.get_node("Artwork").visible and art.mouse_filter == Control.MOUSE_FILTER_IGNORE and h.room.grid.valid, "可配置文字占位首帧全貌")
	var before: Vector2 = h.room.grid.size
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color("#86724f"))
	var texture := ImageTexture.create_from_image(image)
	art.artwork = texture
	var swap: bool = art.get_node("Artwork").visible and not art.get_node("Placeholder").visible
	h.c.click_cell(Vector2i(0,0))
	swap = swap and h.room.grid.current_cell == Vector2i(0,0)
	art.artwork = null
	ck(15, swap and not art.get_node("Artwork").visible and art.get_node("Placeholder").visible and h.room.grid.size == before, "一属性换图清空恢复输入不变")
	var denied: bool = not h.room.request_object("Scar") and not h.room.request_object("Ban") and not h.room.request_room_sequence(&"detail",["T190"])
	ck(16, denied and not h.room.has_node("Objects/Scar") and not h.room.has_node("Objects/Ban") and not h.room.grid.objects.has("Scar") and h.player.get_lines().has("T190") and h.lines.is_empty(), "撤入口不删原文")

func _departure() -> void:
	await fresh(S.S0)
	var opening_ok: bool = await h.c.opening_to_s1()
	h.lines.clear()
	h.click("Door")
	var immediate: bool = h.c.main._current_page == &"MapPage" and h.player.get_current_key() == "T195" and state.state == S.S1 and h.c.map.get_step_count() == 0
	for i: int in range(3):
		h.c.read_sequence_input()
	var auto_step: bool = state.state == S.S2 and h.c.map.get_current_node_id() == &"c1" and h.c.map.get_step_count() == 1 and state.vital_now == 99.0
	ck(17, opening_ok and immediate and auto_step and h.ids() == DEPARTURE and h.c.flow.checkpoint.writes == 0 and h.c.event_count(&"E5") == 1, "门对白真实完成自动首步精确99")
	var raw: Array = raw_lines()
	var player_script = load("res://scripts/dialogue.gd")
	var missing: Array = raw.filter(func(row: Dictionary): return row.id != "T195")
	var rejects: bool = player_script.validate_required_ids(missing).contains("T195")
	await fresh(S.S0)
	await h.c.opening_to_s1()
	var entry: Dictionary = h.player._lines.T195
	h.player._lines.erase("T195")
	var before: Array = snapshot()
	var page: StringName = h.c.main._current_page
	rejects = not h.room.request_object("Door") and snapshot() == before and h.c.main._current_page == page and not state.event_started(&"E5") and rejects
	h.player._lines.T195 = entry
	rejects = h.c.departure_to_s2() and rejects
	ck(19, rejects and state.vital_now == 99.0 and h.c.event_count(&"E5") == 1, "T195必需运行缺失拒绝恢复一次")
	await fresh(S.S0)
	await h.c.opening_to_s1()
	h.click("Door")
	h.c.read_sequence_input()
	h.c.read_sequence_input()
	var entry_text: bool = h.player.get_current_key() == "T130"
	h.c.flow.request_page(&"ScenePage")
	h.key(KEY_DOWN)
	var delayed: bool = state.state == S.S1 and h.c.map.get_step_count() == 0 and state.vital_now == 100.0
	h.c.flow.request_page(&"BattlePage")
	h.c.read_sequence_input()
	var once: bool = state.state == S.S2 and h.c.map.get_step_count() == 1 and state.vital_now == 99.0
	var after: Array = snapshot()
	h.c.flow._finish_departure_intro(false)
	h.c.flow.request_departure(state.run_id)
	once = once and snapshot() == after
	# 旧局与取消均是真实播放后发生，不伪造完成阶段。
	await fresh(S.S0)
	await h.c.opening_to_s1()
	h.click("Door")
	h.player._finish(true)
	var cancelled: bool = state.state == S.S1 and h.c.map.get_step_count() == 0 and not state.event_started(&"E5")
	C.enter_domain(h.c.main,S.S0)
	h.c.flow._finish_departure_intro(false)
	ck(24, entry_text and delayed and once and cancelled and state.state == S.S0 and not state.event_started(&"E5"), "翻页不提前首步旧局取消重复拒绝")
	var failures_ok: bool = true
	for missing_id: String in ["T122","T130","target","present"]:
		h.main_script = refusing_main if missing_id == "present" else null
		await fresh(S.S0)
		h.main_script = null
		await h.c.opening_to_s1()
		var saved_lines: Dictionary = h.player._lines.duplicate(true)
		var revealed: Dictionary = h.c.map._revealed.duplicate()
		if missing_id == "target":
			h.c.map._revealed.erase(&"c1")
		elif missing_id == "present":
			h.c.main.refuse_map = true
		else:
			h.player._lines.erase(missing_id)
		var failed_before: Array = snapshot()
		var rejected: bool = not h.room.request_object("Door") and state.state == S.S1 and snapshot() == failed_before and not state.event_started(&"E5")
		h.player._lines = saved_lines
		h.c.map._revealed = revealed
		if missing_id == "present":
			h.c.main.refuse_map = false
		var retried: bool = h.c.departure_to_s2() and state.vital_now == 99.0 and h.c.event_count(&"E5") == 1
		failures_ok = case_result("31."+missing_id,rejected and retried) and failures_ok
	h.main_script = refusing_main
	await fresh(S.S0)
	h.main_script = null
	await h.c.opening_to_s1()
	h.click("Door")
	h.c.read_sequence_input()
	h.c.read_sequence_input()
	h.c.main.refuse_map = true
	h.c.read_sequence_input()
	var ready: bool = state.state == S.S1 and h.c.flow._departure_phase == &"READY" and h.c.map.get_step_count() == 0 and state.vital_now == 100.0
	var ids_before: Array = h.ids()
	h.c.main.refuse_map = false
	h.c.flow.request_page(&"ScenePage")
	h.click("Door")
	var retried_ready: bool = state.state == S.S2 and state.vital_now == 99.0 and h.c.map.get_step_count() == 1 and h.ids() == ids_before and h.c.event_count(&"E5") == 1
	failures_ok = case_result("31.READY_RETRY",ready and retried_ready) and failures_ok
	ck(31, failures_ok, "出发预检及呈现失败同请求恢复")

func _exit() -> void:
	await fresh()
	h.c.flow.checkpoint.replace_file = func(_a: String,_b: String): return ERR_BUSY
	h.click("Door")
	var start: bool = h.player.get_current_key() == "T193" and h.arrival_ok and h.c.flow.checkpoint.writes == 0
	h.finish_reading()
	var failed: bool = h.exit_service.pending and not state.event_done(&"E14") and h.finished.is_empty()
	var fake: bool = not state.record_event(&"E14",true,state.run_id) and not h.c.flow.finish_safehouse(&"E14",state.run_id)
	h.ep._saved(state.run_id,{"run_id":state.run_id,"checkpoint":&"safehouse_exit"})
	fake = fake and not state.event_done(&"E14")
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	h.exit_service.advance_time(2.0)
	ck(18, start and failed and fake and h.finished_once() and h.ids() == ["T193"] and h.c.event_count(&"E14") == 1 and not h.exit_service.request_exit(state.run_id), "真实回执一次收尾保存失败拒E14")
	var retry_ok: bool = true
	for at_line: int in [1,11]:
		await fresh()
		h.click("Sofa")
		for n: int in range(at_line - 1):
			h.player.finish_text()
			h.key(KEY_ENTER)
		h.player._finish(true)
		var interrupted: bool = not state.event_done(&"E13") and not h.room.busy
		h.lines.clear()
		h.click("Sofa")
		h.finish_reading()
		retry_ok = case_result("20.partial%d" % at_line,interrupted and h.ids() == h.room.TRUST_IDS and state.event_done(&"E13")) and retry_ok
	for invalid: String in ["old_run","wrong_keys"]:
		await fresh()
		h.click("Sofa")
		if invalid == "old_run":
			h.room._sequence_run -= 1
		else:
			h.player._keys.assign(["T101"])
		h.finish_reading()
		retry_ok = not state.event_done(&"E13") and retry_ok
	ck(20, retry_ok, "信赖中断错误旧run不伪完成")
	await fresh(S.S0)
	var denied: bool = not h.room.request_object("Sofa")
	await h.c.opening_to_s1()
	denied = not h.room.request_object("Sofa") and denied and not state.event_done(&"E13")
	# 真回程继续当前开局，不能begin_session(S6)冒充。
	h.c.departure_to_s2()
	for n: int in range(1,6):
		h.c.walk_to(StringName("point%d" % n))
		h.c.read_point()
	h.c.win()
	h.c.return_battle()
	h.c.walk_to(&"entry_exit")
	await h.c.main._wait_for_layout()
	h.c.click(h.c.main.get_node("Pages/MapPage/ExitConfirm"))
	h.c.read_sequence_input()
	h.complete_sofa()
	var completed: bool = state.state == S.S6 and state.event_done(&"E12") and state.event_done(&"E13") and h.page_inputs()
	C.enter_domain(h.c.main,S.S0)
	ck(21, denied and completed and not state.event_started(&"E12") and not state.event_started(&"E13") and not h.room.interaction("Sofa").read, "只归来才沙发完成同局保持新局清空")
	await fresh(S.S0)
	var travelled: bool = await full_return()
	h.click("Door")
	h.finish_reading()
	ck(23, travelled and h.exit_service.committed and not state.event_done(&"E12") and not state.event_done(&"E13") and h.c.flow.checkpoint.read_safehouse_branch() == {"r13_done":false,"trust_read":false}, "全程不碰沙发可收尾且真实false")
	await fresh(S.S0)
	travelled = await full_return()
	h.c.flow.checkpoint.replace_file = func(_a: String,_b: String): return ERR_BUSY
	h.click("Door")
	h.finish_reading()
	var waiting: bool = h.exit_service.pending and h.c.flow.checkpoint.writes == 1 and not state.event_done(&"E14")
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	h.exit_service.advance_time(1.0)
	ck(25, travelled and waiting and h.exit_service.committed and h.c.flow.checkpoint.writes == 2 and h.ids().count("T193") == 1 and not state.event_done(&"E12") and not state.event_done(&"E13"), "未上药完整往返失败恢复不重播")
	await _branch_readback()

func _branch_readback() -> void:
	var all_ok: bool = true
	for branch: String in ["false_false","false_true","true_true"]:
		await fresh(S.S0)
		var travelled: bool = await full_return()
		if branch == "false_true":
			h.read_trust()
		elif branch == "true_true":
			h.complete_sofa()
		h.click("Door")
		h.finish_reading()
		var expected: Dictionary = {"r13_done":branch == "true_true","trust_read":branch != "false_false"}
		var actual: Dictionary = h.c.flow.checkpoint.read_safehouse_branch()
		print("[SP-25 CASE] 26.%s expected_r13=%s/actual_r13=%s expected_trust=%s/actual_trust=%s" % [branch.to_upper(), expected.r13_done, actual.get("r13_done", "missing"), expected.trust_read, actual.get("trust_read", "missing")])
		var path: String = h.c.flow.checkpoint.path
		var restored: bool = await h.c.close()
		h.c = null
		var reader = load("res://scripts/prologue_checkpoint.gd").new()
		reader.path = path
		var output: Array = []
		var code: int = OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://scripts/sp19_readback_selftest.gd","--",ProjectSettings.globalize_path(path),branch],output,true)
		var logs: String = "\n".join(output)
		all_ok = case_result("26."+branch.to_upper(),travelled and restored and actual == expected and reader.read_safehouse_branch() == expected and code == 0 and logs.contains("SP19_READBACK_OK") and not logs.contains("SCRIPT ERROR")) and all_ok
		var document: Dictionary = reader.read_saved()
		var text: String = FileAccess.get_file_as_string(path)
		var bad: Array = ["not json","{}",JSON.stringify({"version":1,"checkpoint":"task_complete","progress":document.progress})]
		var missing: Dictionary = document.duplicate(true)
		missing.progress.erase("r13_done")
		bad.append(JSON.stringify(missing))
		var wrong: Dictionary = document.duplicate(true)
		wrong.progress.trust_read = "false"
		bad.append(JSON.stringify(wrong))
		for data: String in bad:
			var f: FileAccess = FileAccess.open(path,FileAccess.WRITE)
			f.store_string(data)
			f.close()
			all_ok = reader.read_safehouse_branch().is_empty() and all_ok
		var f: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		f.store_string(text)
		f.close()
		# 旧档true/false仍可读，但当前剧情不能伪造为该组合。
		document.progress.r13_done = true
		document.progress.trust_read = false
		f = FileAccess.open(path,FileAccess.WRITE)
		f.store_string(JSON.stringify(document))
		f.close()
		all_ok = reader.read_safehouse_branch() == {"r13_done":true,"trust_read":false} and all_ok
	ck(26, all_ok, "真实分支新上下文独立进程读回坏档未知")

func _domains() -> void:
	var a_ok: bool = true
	var executed_a: int = 0
	await fresh()
	h.complete_sofa()
	a_ok = state.event_done(&"E12") and state.event_done(&"E13") and h.c.event_count(&"E12") == 1 and h.c.event_count(&"E13") == 1
	executed_a += 1
	for phase: int in [S.S0,S.S1,S.S2,S.S2B,S.S3,S.S4,S.S5]:
		await fresh(phase)
		# 页面可见且会话归属正确，让阶段守卫真正承受负例。
		h.c.flow.request_page(&"ScenePage")
		h.room.show()
		h.room.enter_session()
		var before: Array = snapshot()
		var lines: Array = h.ids()
		var pre: bool = h.room.is_visible_in_tree() and h.room._owns_session() and state.state == phase
		var rejected: bool = not h.room.request_object("Sofa") and not h.room.request_room_sequence(&"trust",h.room.TRUST_IDS) and not h.room.request_room_sequence(&"sofa",["T176","T177"])
		a_ok = case_result("22A.state%d" % phase,pre and rejected and snapshot() == before and h.ids() == lines and not h.player.is_playing()) and a_ok
		executed_a += 1
	for guard: String in ["hidden","busy","old_run"]:
		await fresh()
		if guard == "hidden":
			h.c.flow.request_page(&"MapPage")
		elif guard == "busy":
			h.click("Sofa")
		else:
			state.begin_session(S.S6)
		var before: Array = snapshot()
		var playing: Array = player_snapshot()
		var lines: Array = h.ids()
		a_ok = not h.room.request_object("Sofa") and snapshot() == before and player_snapshot() == playing and h.ids() == lines and a_ok
		executed_a += 1
	await fresh()
	var b_ok: bool = true
	var executed_b: int = 0
	for phase: int in [S.S0,S.S1,S.S2,S.S2B,S.S3,S.S4,S.S5,S.S6]:
		for event_id: StringName in [&"E12",&"E13"]:
			for done: bool in [false,true]:
				b_ok = _direct_event_case(phase,event_id,done,false) and b_ok
				executed_b += 1
	for event_id: StringName in [&"E12",&"E13"]:
		for done: bool in [false,true]:
			b_ok = _direct_event_case(S.S6,event_id,done,true) and b_ok
			executed_b += 1
	print("[SP-25 CASE] 22A executed=%d ok=%s 22B executed=%d ok=%s" % [executed_a,a_ok,executed_b,b_ok])
	ck(22, executed_a == 11 and executed_b == 36 and a_ok and b_ok, "页面及直接事件域独立仅S6合法")

func _direct_event_case(phase: int, event_id: StringName, done: bool, stale: bool) -> bool:
	var saved: Dictionary = state.capture_session()
	var processing: bool = state.is_processing()
	var before_connections: Array = state.event_changed.get_connections()
	state.begin_session(phase)
	var run: int = state.run_id
	var passed_run: int = run - 1 if stale else run
	var before: Dictionary = state.capture_session()
	var events: Array = []
	var collect: Callable = func(id: StringName, completed: bool, session: int): events.append([id,completed,session])
	state.event_changed.connect(collect)
	var result: bool = state.record_event(event_id,done,passed_run)
	var legal: bool = phase == S.S6 and not stale
	var ok: bool = passed_run != -1 and state.run_id == run and state.state == phase
	if legal:
		ok = ok and result and state.event_started(event_id) and state.event_done(event_id) == done and state._events == {event_id:2 if done else 1} and events == [[event_id,done,run]]
		var after: Dictionary = state.capture_session()
		after["_events"] = before["_events"].duplicate()
		ok = after == before and ok
	else:
		ok = ok and not result and not state.event_started(&"E12") and not state.event_started(&"E13") and not state.event_done(&"E12") and not state.event_done(&"E13") and events.is_empty() and state.capture_session() == before
	state.event_changed.disconnect(collect)
	state.begin_session(S.S0,saved)
	state.set_process(processing)
	return ok and state.capture_session() == saved and state.is_processing() == processing and state.event_changed.get_connections() == before_connections

func _opening() -> void:
	await fresh(S.S0)
	var room: Control = h.room
	var nav: Control = h.c.main.get_node("Pages/ScenePage/PageNav")
	var old: Control = h.c.main.get_node("Pages/ScenePage/TestOptions/OptionTwo")
	h.c.flow.configure(h.c.main)
	h.c.flow.content.present(S.S0)
	h.c.click_cell(Vector2i(0,0))
	nav.reading_requested.emit(old)
	nav.confirmed.emit(old)
	await process_frame
	await process_frame
	var silent: bool = h.room == room and room.grid.valid and room.is_visible_in_tree() and not h.player.is_playing() and h.ids().is_empty()
	for id: StringName in [&"E1",&"E2",&"E3",&"E4"]:
		silent = silent and not state.event_started(id)
	ck(27, silent and not h.c.main.get_node("Pages/ScenePage/TestOptions").visible and not h.c.flow.content.has_node("Departure"), "真实冷开局等待旧入口都不自播")
	await fresh(S.S0)
	var starts: Array = []
	var finishes: Array = []
	var reads: Array = []
	var activations: Array = []
	h.c.watch(h.player.stage_started,func(id: StringName,_run: int): starts.append(id))
	h.c.watch(h.player.stage_finished,func(id: StringName,_run: int): finishes.append(id))
	h.c.watch(h.room.interaction("Speaker").state_changed,func(): reads.append(h.room.interaction("Speaker").read))
	h.c.watch(h.room.interaction("Speaker").activated,func(): activations.append(true))
	h.click("Speaker")
	h.c.read_sequence_input()
	var sync_boundary: bool = state.event_done(&"E1") and not h.player._s0._running and h.player._s0.phase == &"" and not h.room.interaction("Speaker").read and not state.event_started(&"E2") and starts.is_empty() and finishes.is_empty()
	await process_frame
	await process_frame
	var handoff: bool = _reading_boundary(starts,finishes,reads,activations)
	var read_each: bool = true
	for id: String in ["T112","T113","T114"]:
		read_each = read_each and h.player.get_current_key() == id and not h.room.interaction("Speaker").read and not state.event_started(&"E2")
		h.player.finish_text()
		h.key(KEY_ENTER)
	read_each = read_each and reads == [true] and activations == [true] and h.player.get_current_key() == "T116" and state.event_started(&"E2") and starts == [&"READING",&"R2"] and finishes == [&"READING"]
	for i: int in range(3):
		h.c.read_sequence_input()
	var exact: bool = h.ids() == FULL_OPENING and starts == [&"READING",&"R2",&"R3",&"R4"] and finishes == starts and reads == [true] and activations == [true]
	for id: StringName in [&"E1",&"E2",&"E3",&"E4"]:
		exact = exact and h.c.event_count(id,false) == 1 and h.c.event_count(id) == 1
	var before: Array = snapshot()
	var ids_before: Array = h.ids()
	h.click("Speaker")
	var repeated: bool = snapshot() == before and h.ids() == ids_before and h.room.get_node("Status/ProgressNotice").text.is_empty()
	await fresh(S.S0)
	h.click("Speaker")
	var e1_skip: bool = not h.player.skip()
	h.c.read_sequence_input()
	await process_frame
	await process_frame
	h.c.read_sequence_input()
	var r2_skip: bool = h.player.skip() and h.player.get_current_key() == "T117"
	var r3_no_skip: bool = not h.player.skip()
	h.c.read_sequence_input()
	var r4_auto: bool = h.player.get_current_key() == "T121"
	h.player.advance_time(100.0)
	h.player.advance_time(100.0)
	r4_auto = r4_auto and state.state == S.S1 and h.player.get_story_phase() == &"DONE"
	await fresh(S.S6)
	var s6_repeat: bool = not h.room.request_object("Speaker") and h.lines.is_empty() and h.room.get_node("Status/ProgressNotice").text.is_empty()
	ck(28, sync_boundary and handoff and read_each and exact and repeated and e1_skip and r2_skip and r3_no_skip and r4_auto and s6_repeat, "HANDOFF真实三句及完整轨迹各一次")
	var reminder: bool = true
	for phase: String in ["IDLE","E1","READING","R2","R3","R4"]:
		await fresh(S.S0)
		if phase != "IDLE":
			h.click("Speaker")
		if phase not in ["IDLE","E1"]:
			h.c.read_sequence_input()
			await process_frame
			await process_frame
			while h.player.get_story_phase() != StringName(phase) and state.state == S.S0:
				h.c.read_sequence_input()
		var prior: Array = snapshot()
		var playback: Array = player_snapshot()
		h.click("Door")
		var ok: bool = h.room.grid.current_cell == Vector2i(4,2) and h.room.get_node("Status/ProgressNotice").text == "还有没听完的内容。" and state.state == S.S0 and snapshot() == prior and player_snapshot() == playback
		reminder = case_result("29."+phase,ok) and reminder
		# 回正文取得阅读焦点后继续；不让提醒确认冒充正文输入。
		if phase == "R4":
			h.player.advance_time(100.0)
			h.player.advance_time(100.0)
			reminder = h.room.get_node("Status/ProgressNotice").text.is_empty() and reminder
	ck(29, reminder, "六个未听完阶段门只一句提醒不动播放")
	var sofa: bool = true
	for phase: int in [S.S0,S.S1]:
		await fresh(phase)
		var before_sofa: Array = snapshot()
		h.click("Sofa")
		h.click("Sofa")
		h.key(KEY_ENTER)
		sofa = not h.room.request_room_sequence(&"trust",h.room.TRUST_IDS) and not h.room.request_room_sequence(&"sofa",["T176","T177"]) and sofa
		sofa = sofa and snapshot() == before_sofa and h.lines.is_empty() and not h.room.medical.visible and h.room.get_node("Status/ProgressNotice").text.is_empty()
	await fresh()
	h.click("Sofa")
	ck(30, sofa and h.player.get_current_key() == "T178", "出发前沙发所有入口无反应归来可用")

func _reading_boundary(starts: Array, finishes: Array, reads: Array, activations: Array) -> bool:
	return case_result("HANDOFF",h.player._s0._running and h.player._s0.phase == &"READING" and h.player.is_playing() and h.player.get_current_key() == "T112" and state.event_done(&"E1") and h.c.event_count(&"E1") == 1 and not state.event_started(&"E2") and not h.room.interaction("Speaker").read and activations.is_empty() and reads.is_empty() and h.player._s0.last_completed_stage != &"READING" and starts == [&"READING"] and finishes.is_empty())

func _retry() -> void:
	var ok: bool = true
	for reject: bool in [false,true]:
		h.main_script = rejecting_main if reject else null
		await fresh(S.S0)
		h.main_script = null
		var line: Dictionary = h.player._lines.T101
		if not reject:
			h.player._lines.erase("T101")
		h.click("Speaker")
		var refused: bool = not state.event_started(&"E1") and not state.event_done(&"E1") and not h.player.is_playing() and h.c.flow._opening_token == -1
		if reject:
			h.player.reject_requests = false
		else:
			h.player._lines.T101 = line
		var starts: Array = []
		var finishes: Array = []
		var reads: Array = []
		var activations: Array = []
		h.c.watch(h.player.stage_started,func(id: StringName,_run: int): starts.append(id))
		h.c.watch(h.player.stage_finished,func(id: StringName,_run: int): finishes.append(id))
		h.c.watch(h.room.interaction("Speaker").state_changed,func(): reads.append(h.room.interaction("Speaker").read))
		h.c.watch(h.room.interaction("Speaker").activated,func(): activations.append(true))
		h.click("Speaker")
		h.c.read_sequence_input()
		await process_frame
		await process_frame
		var boundary: bool = _reading_boundary(starts,finishes,reads,activations)
		finish_opening()
		ok = case_result("32.RETRY_HANDOFF."+str(reject),refused and boundary and h.ids() == FULL_OPENING and starts == [&"READING",&"R2",&"R3",&"R4"] and finishes == starts and reads == [true] and activations == [true]) and ok
	# 沿用SP11的生产加载续播样本，非直接_start；每例独立执行，不短路。
	await h.close()
	var runner = load("res://scripts/sp11_selftest.gd").new()
	runner._main = host
	var raw: Array = raw_lines()
	for stage: StringName in [&"R2",&"R3"]:
		var restored: bool = await runner._s0_pending_case(stage,"",raw)
		ok = case_result("32.PENDING_"+str(stage),restored) and ok
	for guard: String in ["stale_run","busy_player"]:
		var rejected: bool = await runner._s0_pending_case(&"R2",guard,raw)
		ok = case_result("32."+guard,rejected) and ok
	await fresh(S.S0)
	h.click("Speaker")
	h.c.read_sequence_input()
	var new_starts: Array = []
	var new_finishes: Array = []
	var new_reads: Array = []
	var new_activations: Array = []
	h.c.watch(h.player.stage_started,func(id: StringName,_run: int): new_starts.append(id))
	h.c.watch(h.player.stage_finished,func(id: StringName,_run: int): new_finishes.append(id))
	h.c.watch(h.room.interaction("Speaker").state_changed,func(): new_reads.append(h.room.interaction("Speaker").read))
	h.c.watch(h.room.interaction("Speaker").activated,func(): new_activations.append(true))
	var old_run: int = state.run_id
	var old_token: int = h.c.flow._opening_token
	var queued: bool = h.c.flow._opening_pending and h.c.flow._opening_queued
	C.enter_domain(h.c.main,S.S0)
	h.click("Speaker")
	var new_token: int = h.c.flow._opening_token
	await process_frame
	await process_frame
	var ignored: bool = state.run_id != old_run and new_token != old_token and h.c.flow._opening_token == new_token and h.player.get_current_key() == "T101" and h.player.get_story_phase() == &"" and not state.event_started(&"E2")
	h.lines.clear()
	h.c.read_sequence_input()
	var pending: Array = [h.c.flow._opening_token,h.c.flow._opening_pending,h.c.flow._opening_queued]
	h.c.flow._start_reading_after_e1(state.run_id,old_token)
	var old_ignored: bool = pending == [h.c.flow._opening_token,h.c.flow._opening_pending,h.c.flow._opening_queued]
	await process_frame
	await process_frame
	var next_ok: bool = h.player.get_current_key() == "T112" and h.player.get_story_phase() == &"READING" and not h.room.interaction("Speaker").read and not state.event_started(&"E2")
	finish_opening()
	var tail: Array = ["T102","T103","T104","T105","T106","T112","T113","T114","T116","T117","T118","T121"]
	ok = case_result("32.STALE_RUN_BRIDGE",queued and ignored and next_ok and h.ids() == tail and state.state == S.S1 and new_starts == [&"READING",&"R2",&"R3",&"R4"] and new_finishes == new_starts and new_reads == [true] and new_activations == [true]) and ok
	ok = case_result("32.STALE_TOKEN",old_ignored and next_ok) and ok
	ck(32, ok, "失败重试生产续播及旧run旧token不清新请求")


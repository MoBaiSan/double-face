## SP-26：固定28个顶层断言；CASE不计PASS，全部走生产输入/读档/保存链。
extends SceneTree
const IDS: Array[String] = ["T178", "T179", "T180", "T181", "T182", "T183", "T184", "T185", "T186", "T187", "T188", "T189"]
const LINES: Array = [
	["T178", "琥珀", "斑さん。"],
	["T179", "琥珀", "刚才那句。「站在前面是我的工作」——那个，是工作吗。"],
	["T180", "斑", "怎么，突然问这个。"],
	["T181", "斑", "工作啊。不然呢。报告是我写的，路线是我定的，门是我开的。你在里头多待两分钟，我这边就有一堆数字要盯着。"],
	["T182", "斑", "再说，站在前面这件事我很擅长。擅长的事不拿来当工作，难道拿去当爱好吗。"],
	["T183", "琥珀", "我问的是——"],
	["T184", "斑", "哎，等一下，你那个绷带别绕那么紧，绕太紧肩膀会麻。……对，就这样。你手比我有数，你自己来。"],
	["T185", "斑", "咖啡还剩半罐。你喝完再过去，别剩。"],
	["T186", "旁白", "琥珀没有再说下去。他把手收回来，看了斑一会儿。"],
	["T187", "斑", "……看什么。我脸上有东西？"],
	["T188", "琥珀", "没有。"],
	["T189", "琥珀", "晚安，斑さん。"],
]

const S: Dictionary = {"S0":0,"S1":1,"S2":2,"S2B":3,"S3":4,"S4":5,"S5":6,"S6":7}
var C: Script
var H: Script
var h: RefCounted
var state: Node
var host: Control
var results: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	C = load("res://scripts/prologue_test_context.gd")
	H = load("res://scripts/sp19_test_context.gd")
	host = load("res://scenes/Main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	state = root.get_node("GameState")
	h = H.new()
	await process_frame
	for test: Callable in [_trust, _options_input, _medical_detail, _lifecycle, _content_guards, _save_matrix, _restore, _cleanup]:
		await test.call()
	await h.close()
	if not h.clean or results.size() != 28:
		failures += 1
	print("[SP-26] assertions=%d failures=%d" % [results.size(), failures])
	quit(0 if failures == 0 and results.size() == 28 else 1)

func ck(id: int, ok: bool, label: String) -> void:
	ok = ok and not results.has(id)
	results[id] = ok
	failures += int(not ok)
	print("[SP-26] %s %02d %s" % ["PASS" if ok else "FAIL", id, label])

func case_result(name: String, ok: bool) -> bool:
	print("[SP-26 CASE] %s %s" % [name, "OK" if ok else "BAD"])
	return ok

func fresh(phase: int = S.S6) -> void:
	await h.fresh(host, phase)
	h.c.flow.checkpoint.path = "user://sp26_%d_%d.json" % [OS.get_process_id(), h.serial]
	h.paths.append(h.c.flow.checkpoint.path)

func ready_options() -> void:
	h.read_trust()
	h.lines.clear()
	h.click("Sofa")

func option(id: String) -> Control:
	return h.room.get_node("SofaOptions/Choices/" + id)

func snapshot() -> Array:
	return [state.capture_session(), h.c.map.get_current_node_id(), h.c.map.get_step_count(), h.c.map.get_revealed_ids(), h.c.flow.checkpoint.attempts, h.c.flow.checkpoint.writes]

func playback() -> Array:
	return [h.player.is_playing(), h.player.get_current_key(), h.player._keys.duplicate(), h.player.get_visible_text(), h.room.busy, h.room._kind]

func record_signals() -> Array:
	var signals: Array = []
	h.c.watch(h.room.grid.cell_selected, func(cell: Vector2i): signals.append(["cell",cell]))
	h.c.watch(h.room.grid.object_confirmed, func(id: String): signals.append(["object",id]))
	return signals

func _trust() -> void:
	var gate: bool = true
	for phase: int in [S.S0,S.S1,S.S2,S.S2B,S.S3,S.S4,S.S5]:
		await fresh(phase)
		h.c.flow.request_page(&"ScenePage")
		h.room.show()
		h.room.enter_session()
		var before: Array = snapshot()
		h.click("Sofa")
		h.key(KEY_ENTER)
		gate = case_result("01.phase%d" % phase, not h.room.request_object("Sofa") and not h.room.options_open and h.lines.is_empty() and not h.player.is_playing() and snapshot() == before) and gate
	ck(1, gate, "sofa_phase_gate")
	await fresh()
	h.click("Sofa")
	var exact: bool = not h.room.options_open and h.player.get_current_key() == "T178"
	for row: Array in LINES:
		exact = h.player.get_current_key() == row[0] and h.player.get_current_mode() == "read" and not h.room.options_open and exact
		h.key(KEY_ENTER)
		exact = h.player.get_visible_text() == row[2] and h.player._speaker.text == row[1] and not state.event_done(&"E13") and exact
		h.key(KEY_ENTER)
	ck(2, exact and h.ids() == IDS and not h.player.is_playing(), "first_trust_exact")
	await process_frame
	ck(3, state.event_done(&"E13") and h.c.event_count(&"E13") == 1 and h.c.event_count(&"E13",false) == 1 and not h.room.options_open and not h.room.interaction("Sofa").read and not state.event_done(&"E12") and root.gui_get_focus_owner() == h.room.grid, "trust_completion_once")
	var retries: bool = true
	for mode: String in ["first","eleventh","old_run","wrong_keys"]:
		await fresh()
		h.click("Sofa")
		if mode == "eleventh":
			for n: int in range(10):
				h.player.finish_text()
				h.key(KEY_ENTER)
		if mode in ["first","eleventh"]:
			h.player._finish(true)
		else:
			if mode == "old_run": h.room._sequence_run -= 1
			else: h.player._keys.assign(["T101"])
			h.finish_reading()
		var rejected: bool = not state.event_done(&"E13") and not h.room.options_open and not h.room.busy
		h.lines.clear()
		h.click("Sofa")
		h.finish_reading()
		retries = case_result("04."+mode,rejected and h.ids() == IDS and state.event_done(&"E13") and h.c.event_count(&"E13") == 1 and not h.room.options_open) and retries
	ck(4, retries, "partial_trust_retry")

func _options_input() -> void:
	await fresh()
	h.read_trust()
	h.lines.clear()
	h.focus_object("Sofa")
	var confirmations: Array = []
	h.c.watch(h.room.options_nav.confirmed, func(node: Control): confirmations.append(String(node.name)))
	h.key(KEY_ENTER)
	var candidates: Array = h.room.options_nav.get_candidates()
	var ancestor: Array = h.c.main.get_node("Pages/ScenePage/PageNav").get_candidates()
	ck(5, h.room.options_open and candidates == [option("Medical"),option("ScarDetail")] and option("Medical").get_node("Text").text == "上药" and option("ScarDetail").get_node("Text").text == "看斑的旧伤" and h.room.options_nav.get_selected() == option("Medical") and not ancestor.has(option("Medical")) and not ancestor.has(option("ScarDetail")) and h.lines.is_empty(), "exact_two_scoped_choices")
	ck(6, confirmations.is_empty() and not h.player.is_playing() and not state.event_done(&"E12") and not h.room.medical.visible, "opening_key_not_choice")
	var openings: Array = []
	h.c.watch(h.room.medical.visibility_changed, func():
		if h.room.medical.visible: openings.append(true))
	h.choose_option("Medical")
	ck(7, confirmations == ["Medical"] and openings.size() == 1 and h.ids() == ["T176"] and h.room.medical.visible and not h.room.options_open and not state.event_done(&"E12"), "mouse_medical_single")
	await fresh()
	ready_options()
	var clicks: Array = []
	h.c.watch(h.room.options_nav.confirmed, func(node: Control): clicks.append(String(node.name)))
	var grid_events: Array = record_signals()
	var cell: Vector2i = h.room.grid.current_cell
	h.choose_option("ScarDetail")
	ck(8, clicks == ["ScarDetail"] and h.ids() == ["T190"] and h.player.is_typing() and not h.room.medical.visible and grid_events.is_empty() and h.room.grid.current_cell == cell, "mouse_detail_single")
	await fresh()
	ready_options()
	grid_events = record_signals()
	cell = h.room.grid.current_cell
	var pays: int = state._point_pay_calls
	var steps: int = h.c.map.get_step_count()
	var navigation: bool = true
	for key: Key in [KEY_DOWN,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:
		h.key(key)
		navigation = h.room.options_nav.get_selected() == option("ScarDetail") and navigation
	h.c.key(KEY_UP,true,true)
	navigation = h.room.options_nav.get_selected() == option("ScarDetail") and navigation
	h.key(KEY_UP)
	h.key(KEY_UP)
	navigation = h.room.options_nav.get_selected() == option("Medical") and navigation
	ck(9, navigation and h.room.grid.current_cell == cell and grid_events.is_empty() and state._point_pay_calls == pays and h.c.map.get_step_count() == steps and h.lines.is_empty(), "arrows_not_grid")
	h.key(KEY_DOWN)
	var run: int = h.room.menu_run
	var token: int = h.room.menu_token
	h.key(KEY_ENTER)
	var one: bool = h.ids() == ["T190"] and h.player.is_typing() and not h.room.options_open
	var before: Array = snapshot()
	var playing: Array = playback()
	var duplicate: bool = h.room.choose_sofa_option(&"ScarDetail",run,token)
	ck(10, one and not duplicate and h.ids() == ["T190"] and h.player.is_typing() and snapshot() == before and playback() == playing, "confirm_not_advance")

func _medical_detail() -> void:
	await fresh()
	ready_options()
	var activations: Array = []
	h.c.watch(h.room.interaction("Sofa").activated, func(): activations.append(true))
	h.choose_option("Medical")
	h.finish_reading()
	var first: bool = h.ids() == ["T176","T177"] and h.room.interaction("Sofa").read and not state.event_done(&"E12") and not h.room.options_open and not h.room.busy
	h.click("Sofa")
	var separate: bool = h.room.options_open and not state.event_done(&"E12") and not h.player.is_playing()
	h.choose_option("Medical")
	ck(11, first and separate and state.event_done(&"E12") and h.c.event_count(&"E12") == 1 and activations.size() == 1 and h.ids() == ["T176","T177"], "two_medical_actions")
	var inert: bool = true
	for n: int in range(2):
		h.click("Sofa")
		inert = h.room.options_nav.get_candidates().size() == 2 and h.room.options_nav.get_interactable(option("Medical")).read and inert
		h.choose_option("Medical")
		inert = h.room.options_open and not h.player.is_playing() and h.c.event_count(&"E12") == 1 and inert
		h.key(KEY_ESCAPE)
	h.click("Sofa")
	h.choose_option("ScarDetail")
	inert = h.player.get_current_key() == "T190" and inert
	ck(12, inert and activations.size() == 1 and h.ids() == ["T176","T177","T190"], "completed_medical_inert")
	await fresh()
	ready_options()
	var ends: Array = []
	h.c.watch(h.player.sequence_finished, func(skipped: bool): ends.append(skipped))
	h.choose_option("ScarDetail")
	h.player.finish_text()
	ck(13, h.ids() == ["T190"] and h.player.get_visible_text() == "斑的左肩有一道旧疤。" and h.player._speaker.text == "旁白" and h.player.get_current_mode() == "read", "detail_literal_only")
	h.finish_reading()
	var repeatable: bool = not h.room.options_open
	for n: int in range(2):
		h.click("Sofa")
		repeatable = not h.room.options_nav.get_interactable(option("ScarDetail")).read and repeatable
		h.choose_option("ScarDetail")
		h.finish_reading()
		repeatable = not h.room.options_open and not h.player.is_playing() and repeatable
	ck(14, repeatable and ends == [false,false,false] and h.ids() == ["T190","T190","T190"], "detail_repeat_three")
	await fresh()
	ready_options()
	var medical_before: Array = [h.room.interaction("Sofa").read,h.room.interaction("Sofa")._progress_confirmed,state.event_done(&"E12"),state.vital_now]
	h.choose_option("ScarDetail")
	h.finish_reading()
	var kept: bool = medical_before == [h.room.interaction("Sofa").read,h.room.interaction("Sofa")._progress_confirmed,state.event_done(&"E12"),state.vital_now]
	h.click("Sofa")
	h.choose_option("Medical")
	h.finish_reading()
	ck(15, kept and h.ids() == ["T190","T176","T177"] and h.room.interaction("Sofa").read and not state.event_done(&"E12"), "detail_not_medical")
	h.lines.clear()
	var mixed: bool = true
	for n: int in range(2):
		h.click("Sofa")
		h.choose_option("ScarDetail")
		h.finish_reading()
		mixed = h.room.interaction("Sofa").read and not state.event_done(&"E12") and mixed
	h.click("Sofa")
	h.choose_option("Medical")
	ck(16, mixed and h.ids() == ["T190","T190"] and state.event_done(&"E12") and h.c.event_count(&"E12") == 1, "mixed_actions_keep_step")

func _lifecycle() -> void:
	await fresh()
	ready_options()
	var cell: Vector2i = h.room.grid.current_cell
	var before: Array = snapshot()
	h.key(KEY_ESCAPE)
	var canceled: bool = not h.room.options_open and not h.player.is_playing() and h.room.grid.current_cell == cell and snapshot() == before
	h.click("Sofa")
	var events: Array = record_signals()
	h.c.click_cell(Vector2i(0,0))
	canceled = canceled and not h.room.options_open and h.room.grid.current_cell == cell and events.is_empty() and snapshot() == before
	h.click("Sofa")
	ck(17, canceled and h.room.options_open and h.room.options_nav.get_candidates().size() == 2 and h.lines.is_empty(), "cancel_no_clickthrough")
	var pages: bool = h.c.flow.request_page(&"MapPage") and not h.room.options_open
	pages = h.c.flow.request_page(&"ScenePage") and pages
	await process_frame
	pages = not h.room.options_open and root.gui_get_focus_owner() == h.room.grid and pages
	h.click("Sofa")
	h.key(KEY_PAGEUP)
	pages = not h.room.options_open and h.c.main._current_page == &"BattlePage" and pages
	h.c.flow.request_page(&"ScenePage")
	await process_frame
	h.click("Sofa")
	h.key(KEY_PAGEDOWN)
	pages = not h.room.options_open and h.c.main._current_page == &"MapPage" and pages
	h.c.flow.request_page(&"ScenePage")
	await process_frame
	h.click("Sofa")
	await process_frame
	var hover_token: int = h.room.menu_token
	var hover_cell: Vector2i = h.room.grid.current_cell
	var hover_selected: Control = h.room.options_nav.get_selected()
	var hover_before: Array = snapshot()
	var motion := InputEventMouseMotion.new()
	motion.position = h.c.main._page_switch_bar.get_node("MapButton").get_global_rect().get_center()
	motion.relative = Vector2(1, 0)
	h.c.main.get_viewport().push_input(motion, true)
	await process_frame
	var hover_kept: bool = h.room.options_open and h.room.get_node("SofaOptions").is_visible_in_tree() and h.room.menu_token == hover_token and h.c.main._current_page == &"ScenePage" and h.room.grid.current_cell == hover_cell and h.room.options_nav.get_selected() == hover_selected and snapshot() == hover_before and h.lines.is_empty()
	pages = case_result("18.page_bar_hover_keeps_menu", hover_kept) and pages
	var click_from_open: bool = h.room.options_open
	h.c.click(h.c.main._page_switch_bar.get_node("MapButton"))
	pages = case_result("18.page_button_click_closes_menu", click_from_open and not h.room.options_open and h.c.main._current_page == &"MapPage") and pages
	h.c.flow.request_page(&"ScenePage")
	await process_frame
	h.c.main.size = Vector2(1120,720)
	await h.c.main._wait_for_layout()
	h.click("Sofa")
	await process_frame
	var paper: Rect2 = h.room.get_node("PaperFrame").get_global_rect()
	for node: Control in [option("Medical"),option("ScarDetail")]:
		var rect: Rect2 = node.get_global_rect()
		pages = rect.size.x > 0 and rect.size.y >= 56 and paper.encloses(rect) and not rect.intersects(h.c.main._page_switch_bar.get_global_rect()) and not rect.intersects(h.c.main._throat_placeholder.get_global_rect()) and pages
	h.key(KEY_ESCAPE)
	ck(18, pages and state.event_done(&"E13") and not state.event_done(&"E12") and not h.room.options_open, "page_layout_lifecycle")
	var guards: bool = true
	for mode: String in ["hidden","busy","pending","committed","state","old_run","old_token"]:
		await fresh()
		ready_options()
		var run: int = h.room.menu_run
		var token: int = h.room.menu_token
		if mode == "hidden": h.c.flow.request_page(&"MapPage")
		elif mode == "busy": h.player.play_seq(["T190"])
		elif mode == "pending": h.exit_service.pending = true
		elif mode == "committed": h.exit_service.committed = true
		elif mode == "state": C.enter_domain(h.c.main,S.S1)
		elif mode == "old_run": state.begin_session(S.S6)
		else:
			h.key(KEY_ESCAPE)
			h.click("Sofa")
		var guard_snapshot: Array = snapshot()
		var playing: Array = playback()
		var ids: Array = h.ids()
		var current_token: int = h.room.menu_token
		var rejected: bool = not h.room.choose_sofa_option(&"ScarDetail",run,token) and not h.room.choose_sofa_option(&"Medical",run,token)
		var stable: bool = snapshot() == guard_snapshot and playback() == playing and h.ids() == ids and h.room.menu_token == current_token
		if mode == "old_token":
			stable = stable and h.room.options_open and h.room.menu_token != token
		guards = case_result("19."+mode,rejected and stable) and guards
	ck(19, guards, "request_guards")

func _content_guards() -> void:
	await fresh()
	h.read_trust()
	h.lines.clear()
	var good: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))
	var bad: Array = good.filter(func(row: Dictionary): return row.id != "T190")
	print("[SP-26 CASE] 20.EXPECTED_DATA_REJECTION missing T190")
	var rejected: bool = not h.player.load_lines_data(bad)
	h.click("Sofa")
	h.choose_option("ScarDetail")
	rejected = rejected and h.lines.is_empty() and not h.room.busy and not h.player.is_playing() and not h.room.interaction("Sofa").read and not state.event_done(&"E12")
	var loaded: bool = h.player.load_lines_data(good)
	h.click("Sofa")
	h.choose_option("ScarDetail")
	h.finish_reading()
	ck(20, rejected and loaded and h.ids() == ["T190"] and h.c.event_count(&"E13") == 1 and state.event_done(&"E13"), "missing_detail_retry")
	await fresh()
	h.read_trust()
	h.lines.clear()
	var before: Array = snapshot()
	var exact: bool = true
	for ids: Array in [[],["T190","T190"],["T190","T191"],["T176"]]:
		exact = not h.room.request_room_sequence(&"detail",ids) and exact
	exact = not h.room.request_room_sequence(&"unknown",["T190"]) and exact
	exact = not h.room.request_room_sequence(&"sofa",["T190","T190"]) and exact
	exact = snapshot() == before and h.lines.is_empty() and not h.room.busy and exact
	var legal: bool = h.room.request_room_sequence(&"detail",["T190"])
	h.finish_reading()
	ck(21, exact and legal and h.ids() == ["T190"] and snapshot() == before, "exact_sequence_guard")
	var three: bool = true
	for n: int in range(3):
		h.click("Sofa")
		three = h.room.grid.objects.keys() == ["Sofa","Speaker","Door"] and h.room.grid.dimensions == Vector2i(5,5) and h.room.grid.objects.Sofa.cell == Vector2i(1,3) and h.room.grid.objects.Speaker.cell == Vector2i(1,1) and h.room.grid.objects.Door.cell == Vector2i(4,2) and h.room.get_node("Objects").get_child_count() == 3 and not h.room.has_node("Objects/Scar") and not h.room.has_node("Objects/Ban") and three
		h.choose_option("ScarDetail")
		h.finish_reading()
	ck(22, three and h.room.grid.valid, "still_three_targets")
	await fresh()
	state.vital_now = 73.0
	state.set_process(true)
	var frames: Array = []
	h.c.watch(process_frame, func(): frames.append(true))
	var pays: int = state._point_pay_calls
	var steps: int = h.c.map.get_step_count()
	h.c.click_cell(Vector2i(0,0))
	h.key(KEY_RIGHT)
	h.key(KEY_DOWN)
	h.read_trust()
	h.click("Sofa")
	h.key(KEY_DOWN)
	h.key(KEY_UP)
	h.choose_option("ScarDetail")
	h.finish_reading()
	h.complete_sofa()
	await process_frame
	await process_frame
	ck(23, state.is_processing() and frames.size() >= 2 and state.vital_now == 73.0 and state._point_pay_calls == pays and h.c.map.get_step_count() == steps and state.event_done(&"E12"), "free_room_actions")

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

func _save_matrix() -> void:
	var matrix: bool = true
	for branch: String in ["UNTOUCHED","TRUST","DETAIL","FIRST_MEDICAL","COMPLETE"]:
		await fresh(S.S0 if branch == "UNTOUCHED" else S.S6)
		var travelled: bool = true
		if branch == "UNTOUCHED":
			travelled = await full_return()
		else:
			h.read_trust()
		if branch == "DETAIL":
			h.click("Sofa")
			h.choose_option("ScarDetail")
			h.finish_reading()
		elif branch == "FIRST_MEDICAL":
			h.begin_medical()
			h.finish_reading()
		elif branch == "COMPLETE":
			h.complete_sofa()
		var expected_r13: bool = branch == "COMPLETE"
		var expected_trust: bool = branch != "UNTOUCHED"
		var writes: int = h.c.flow.checkpoint.writes
		h.click("Door")
		h.finish_reading()
		var actual: Dictionary = h.c.flow.checkpoint.read_safehouse_branch()
		print("[SP-26 CASE] 24.%s expected_r13=%s actual_r13=%s expected_trust=%s actual_trust=%s" % [branch,expected_r13,actual.get("r13_done","missing"),expected_trust,actual.get("trust_read","missing")])
		var saved: bool = actual == {"r13_done":expected_r13,"trust_read":expected_trust}
		saved = saved and h.exit_service.committed and h.c.flow.checkpoint.writes == writes+1 and h.receipts.size() == 1 and h.finished.size() == 1 and h.c.event_count(&"E14") == 1
		saved = saved and state.event_done(&"E12") == expected_r13 and state.event_done(&"E13") == expected_trust
		h.exit_service.advance_time(3.0)
		saved = not h.exit_service.request_exit(state.run_id) and h.c.flow.checkpoint.writes == writes+1 and saved
		matrix = case_result("24."+branch, travelled and saved) and matrix
	await fresh()
	h.c.flow.checkpoint.replace_file = func(_a: String,_b: String): return ERR_BUSY
	h.click("Door")
	h.finish_reading()
	var held: bool = h.exit_service.pending and not h.exit_service.committed and not state.event_done(&"E14") and h.receipts.is_empty() and h.finished.is_empty()
	var fake: bool = not state.record_event(&"E14",true,state.run_id) and not h.c.flow.finish_safehouse(&"E14",state.run_id)
	h.ep._saved(state.run_id,{"run_id":state.run_id,"checkpoint":&"safehouse_exit"})
	fake = not state.event_done(&"E14") and fake
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	h.exit_service.advance_time(2.0)
	matrix = case_result("24.RETRY",held and fake and h.exit_service.committed and h.c.flow.checkpoint.writes == 1 and h.receipts.size() == 1 and h.finished.size() == 1 and h.c.event_count(&"E14") == 1 and h.c.flow.checkpoint.read_safehouse_branch() == {"r13_done":false,"trust_read":false}) and matrix
	ck(24, matrix, "truthful_exit_matrix")

func write_old(r13: bool, trust: bool) -> void:
	write_fixture(JSON.stringify({"version":1,"checkpoint":"safehouse_exit","progress":{"safehouse_reached":true,"safehouse_exit":true,"r13_done":r13,"trust_read":trust}}))

func write_fixture(text: String) -> void:
	var file: FileAccess = FileAccess.open(h.c.flow.checkpoint.path,FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _restore() -> void:
	var no_replay: bool = true
	for r13: bool in [false,true]:
		await fresh()
		write_old(r13,true)
		var restored: bool = h.c.flow.restore_safehouse_branch(state.run_id)
		h.click("Sofa")
		var valid: bool = restored and state.event_done(&"E13") and state.event_done(&"E12") == r13 and h.room.interaction("Sofa").read == r13 and h.room.options_open and h.room.options_nav.get_candidates().size() == 2 and h.lines.is_empty() and not state.event_started(&"E14")
		no_replay = case_result("25.r13_%s" % r13, valid) and no_replay
	ck(25, no_replay, "loaded_true_no_replay")
	var truthful: bool = true
	for r13: bool in [false,true]:
		await fresh()
		write_old(r13,false)
		var restored: bool = h.c.flow.restore_safehouse_branch(state.run_id)
		var initially_unread: bool = not state.event_started(&"E13") and state.event_done(&"E12") == r13
		h.click("Sofa")
		var starts_trust: bool = h.player.get_current_key() == "T178" and not h.room.options_open
		h.finish_reading()
		var correct: bool = h.ids() == IDS and state.event_done(&"E13") and h.c.event_count(&"E13") == 1 and state.event_done(&"E12") == r13 and h.room.interaction("Sofa").read == r13
		h.click("Door")
		h.finish_reading()
		correct = correct and h.c.flow.checkpoint.read_safehouse_branch() == {"r13_done":r13,"trust_read":true}
		truthful = case_result("26.r13_%s" % r13, restored and initially_unread and starts_trust and correct) and truthful
	ck(26, truthful, "loaded_false_keeps_truth")
	var refused: bool = true
	for invalid: String in ["missing","type","json","checkpoint","old_run","state","progress","repeat"]:
		await fresh()
		write_old(false,true)
		var document: Dictionary = h.c.flow.checkpoint.read_saved()
		var run: int = state.run_id
		if invalid == "missing":
			document.progress.erase("trust_read")
			write_fixture(JSON.stringify(document))
		elif invalid == "type":
			document.progress.trust_read = "false"
			write_fixture(JSON.stringify(document))
		elif invalid == "json":
			write_fixture("not JSON")
		elif invalid == "checkpoint":
			document.checkpoint = "task_complete"
			write_fixture(JSON.stringify(document))
		elif invalid == "old_run":
			run -= 1
		elif invalid == "state":
			C.enter_domain(h.c.main,S.S1)
			run = state.run_id
		elif invalid == "progress":
			h.click("Sofa")
		else:
			refused = h.c.flow.restore_safehouse_branch(run) and refused
		var before: Array = snapshot()
		var playing: Array = playback()
		var ids: Array = h.ids()
		var rejected: bool = not h.c.flow.restore_safehouse_branch(run)
		refused = case_result("27."+invalid,rejected and snapshot() == before and playback() == playing and h.ids() == ids) and refused
	await fresh(S.S0)
	write_old(true,true)
	h.c.flow.configure(h.c.main)
	refused = case_result("27.NEW_GAME",state.state == S.S0 and not state.event_started(&"E13") and not state.event_done(&"E12") and not h.room.options_open and h.lines.is_empty()) and refused
	ck(27, refused, "restore_rejects_invalid")

func _cleanup() -> void:
	var clean: bool = true
	for n: int in range(2):
		await fresh()
		ready_options()
		var old_run: int = h.room.menu_run
		var old_token: int = h.room.menu_token
		C.enter_domain(h.c.main,S.S6)
		h.read_trust()
		h.lines.clear()
		h.click("Sofa")
		var token: int = h.room.menu_token
		clean = not h.room.choose_sofa_option(&"ScarDetail",old_run,old_token) and h.room.options_open and h.room.menu_token == token and clean
		h.room.configure(h.c.flow,h.exit_service)
		h.c.flow.configure(h.c.main)
		var chosen: Array = []
		h.c.watch(h.room.options_nav.confirmed,func(node: Control): chosen.append(String(node.name)))
		h.choose_option("ScarDetail")
		clean = h.ids() == ["T190"] and chosen == ["ScarDetail"] and clean
		h.finish_reading()
		await h.close()
		clean = h.clean and clean
	for path: String in h.paths:
		clean = not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".tmp") and clean
	ck(28, clean, "cleanup_and_rebind")

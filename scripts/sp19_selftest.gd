## SP-19：40 条真实输入、呈现和持久化检查。
extends RefCounted
const H = preload("res://scripts/sp19_test_context.gd")
const S = H.S
var h = H.new()
var host: Control
var results: Dictionary = {}
var failures: int = 0

func run(root: Control) -> void:
	host = root
	for test: Callable in [_entry, _reading, _keyboard, _layout, _permissions, _cancel, _guards, _save, _failures, _stale, _pages, _durable, _texts, _ending, _configure]:
		await test.call()
	await h.close()
	ck(39, h.clean and h.paths.all(func(path: String): return not FileAccess.file_exists(path)), "fixture_restores_all_session_data")
	if results.size() != 40:
		failures += 1
	print("[SP-19] assertions=%d failures=%d" % [results.size(), failures])
	root.get_tree().quit(0 if failures == 0 else 1)

func ck(id: int, ok: bool, label: String) -> void:
	if results.has(id):
		ok = false
	results[id] = ok
	if not ok:
		failures += 1
	print("[SP-19] %s %02d %s" % ["PASS" if ok else "FAIL", id, label])

func _entry() -> void:
	await h.fresh(host)
	h.click("Door")
	ck(1, h.ids().is_empty() and h.c.flow.checkpoint.attempts == 0 and not h.art.visible and not GameState.event_done(&"E14"), "r13_required_before_exit")
	await h.ready_door(host)
	h.click("Door")
	h.finish_reading()
	ck(2, h.finished_once() and not GameState.event_done(&"E13"), "r14_unread_still_finishes")
	await h.ready_door(host, true)
	h.click("Door")
	h.finish_reading()
	ck(3, h.finished_once(true) and GameState.event_done(&"E13"), "r14_read_same_single_exit")

func _reading() -> void:
	await h.ready_door(host)
	h.click("Door")
	var before: bool = h.c.flow.checkpoint.attempts == 0 and h.c.flow.checkpoint.writes == 0
	ck(4, h.player.get_current_key() == "T193" and h.exit_service.pending and before, "real_mouse_door_starts_t193")
	ck(6, h.arrival_ok, "figure_visible_before_line")
	ck(8, h.phase_contract() and h.ep.phase == h.ep.Phase.READING, "standing_outside_not_inside")
	var typing: bool = h.player._typing and h.c.flow.checkpoint.attempts == 0
	h.key(KEY_ESCAPE)
	var full: bool = h.player.get_visible_text() == H.THANKS and h.player.is_playing()
	var row: Dictionary = h.player.get_lines()["T193"]
	ck(10, full and row.text == H.THANKS and row.speaker == "白濑葵" and row.mode == "read" and h.player._speaker.text == "白濑葵" and h.player.get_current_mode() == "read", "thanks_exact_text")
	ck(15, typing and full and not h.player._typing and h.c.flow.checkpoint.writes == 0 and not GameState.event_done(&"E14"), "esc_completes_sentence_not_exit")
	ck(19, before and typing and full and h.c.flow.checkpoint.attempts == 0 and h.c.flow.checkpoint.writes == 0, "checkpoint_after_line")
	h.key(KEY_ENTER)
	ck(11, h.exit_ids() == ["T193"] and h.finished.size() == 1, "thanks_shown_once")

func _keyboard() -> void:
	await h.ready_door(host)
	h.button("Door").grab_focus()
	h.key(KEY_ENTER)
	ck(5, h.player.get_current_key() == "T193" and h.exit_service.pending and h.c.flow.checkpoint.writes == 0, "keyboard_door_starts_t193")

func _layout() -> void:
	await h.ready_door(host)
	h.click("Door")
	ck(7, h.no_extra_nodes() and h.room.get_parent() == h.c.flow.content, "no_extra_target_or_map")
	var ok: bool = await h.resize_matrix()
	h.player.advance_time(0.02)
	ok = await h.resize_matrix() and ok
	h.player.finish_text()
	ok = await h.resize_matrix() and ok
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.finish_reading()
	ok = h.ep.phase == h.ep.Phase.WAIT_SAVE and await h.resize_matrix() and ok
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	ok = h.ep.phase == h.ep.Phase.FINISHED and await h.resize_matrix() and ok
	ck(9, ok, "doorway_layout_survives_resize")

func _permissions() -> void:
	await h.ready_door(host)
	var ok: bool = not h.room.request_room_sequence(&"exit", ["T193"])
	var initial: Array = h.ids()
	for id: String in h.player.get_lines():
		if id != "T193":
			ok = not h.room.request_room_sequence(&"exit", [id]) and ok
	for ids: Array in [[], ["missing"], ["T193","T194"], ["T192","T193"], ["T193","T193"], ["T176","T193"]]:
		ok = not h.room.request_room_sequence(&"exit", ids) and ok
	ck(12, ok and h.ids() == initial and not h.player.is_playing(), "invalid_exit_sequence_rejects_whole")
	ok = not h.room.request_room_sequence(&"sofa", ["T193"]) and not h.room.request_room_sequence(&"detail", ["T193"])
	h.click("Scar")
	h.finish_reading()
	ck(13, ok and h.ids() == ["T176","T177","T190"], "t193_not_available_to_sofa_or_scar")
	h.click("Door")
	initial = h.ids()
	for id: String in ["Sofa","Scar","Door"]:
		h.click(id)
	ck(14, h.ids() == initial and h.player._keys == ["T193"] and h.player.is_playing() and h.exit_service.accepted == 1, "busy_exit_cannot_be_replaced")

func _cancel() -> void:
	await h.ready_door(host)
	h.click("Door")
	h.player._finish(true)
	var ok: bool = not h.exit_service.pending and h.c.flow.checkpoint.writes == 0 and not GameState.event_done(&"E14") and not h.art.visible
	h.click("Door")
	ck(16, ok and h.player.get_current_key() == "T193" and h.player.is_playing(), "cancelled_read_does_not_save")
	await h.ready_door(host)
	var saved: Dictionary = h.player._lines["T193"].duplicate(true)
	h.player._lines.erase("T193")
	h.click("Door")
	ok = h.c.flow.checkpoint.writes == 0 and not h.exit_service.pending and h.ep.last_error != OK and not h.room.get_node("Status/ProgressNotice").text.is_empty() and not GameState.event_done(&"E14")
	h.player._lines["T193"] = saved
	h.click("Door")
	h.finish_reading()
	ck(17, ok and h.finished_once(), "missing_t193_recovers_without_progress")

func _guards() -> void:
	await h.ready_door(host)
	var ok: bool = not h.c.flow.finish_safehouse(&"E14", GameState.run_id)
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.click("Door")
	ok = not h.c.flow.finish_safehouse(&"E14", GameState.run_id) and ok
	h.finish_reading()
	ok = not h.c.flow.finish_safehouse(&"E14", GameState.run_id) and ok
	ck(18, ok and h.finished.is_empty() and h.c.flow.checkpoint.writes == 0, "direct_finish_requires_saved_receipt")
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	for i: int in range(3):
		h.click("Door")
		h.exit_service.complete_before_save(GameState.run_id, true)
		h.ep._line_finished(GameState.run_id, true)
		h.ep._saved(GameState.run_id, h.exit_service.receipt)
	ck(22, h.finished_once(), "duplicate_callbacks_do_not_repeat")

func _save() -> void:
	await h.ready_door(host)
	var seam: Array = []
	h.c.flow.checkpoint.replace_file = h.replace_and_observe.bind(seam)
	h.click("Door")
	h.finish_reading()
	ck(20, seam == [true] and h.phase_contract() and not h.art.figure.visible, "hidden_after_leaving")
	ck(21, h.finished_once() and h.c.flow.checkpoint.attempts == 1, "checkpoint_written_once")
	await h.fresh(host, S.S4)
	h.c.flow._on_state_changed(S.S3, S.S4, &"exit", GameState.run_id)
	h.finish_reading()
	var first: bool = GameState.state == S.S6 and h.c.flow.checkpoint.writes == 1 and h.document().checkpoint == "task_complete"
	h.complete_sofa()
	h.click("Door")
	h.finish_reading()
	ck(23, first and h.c.flow.checkpoint.writes == 2 and h.c.flow.checkpoint.attempts == 2 and h.receipts.size() == 1 and h.finished.size() == 1, "task_and_exit_checkpoints_separate")

func _failures() -> void:
	var ok: bool = true
	for mode: String in ["open","rename"]:
		await h.ready_door(host)
		var path: String = h.c.flow.checkpoint.path
		h.c.flow.checkpoint.write_once(GameState.run_id, &"task_complete", {"safehouse_reached":true})
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if mode == "open":
			h.c.flow.checkpoint.path += "/missing/save.json"
		else:
			h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
		h.click("Door")
		h.finish_reading()
		var notice: Label = h.room.get_node("Status/SaveStatus")
		ok = h.exit_service.pending and not h.exit_service.committed and h.c.flow.checkpoint.writes == 1 and bytes == FileAccess.get_file_as_bytes(path) and ok
		ok = notice.is_visible_in_tree() and notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE and not GameState.event_done(&"E14") and h.phase_contract() and ok
	ck(24, ok, "failed_write_keeps_old_and_pending")
	var attempts: int = h.c.flow.checkpoint.attempts
	for delta: float in [NAN, INF, -1.0, 0.0]:
		h.exit_service.advance_time(delta)
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(0.99)
	var held: bool = h.c.flow.checkpoint.attempts == attempts and h.c.flow.checkpoint.writes == 1
	h.exit_service.advance_time(0.01)
	ck(25, held and h.c.flow.checkpoint.attempts == attempts + 1 and h.c.flow.checkpoint.writes == 2 and h.exit_ids() == ["T193"] and h.finished.size() == 1, "retry_after_one_second_no_replay")
	await _hidden_retry()

func _hidden_retry() -> void:
	await h.ready_door(host)
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.click("Door")
	h.finish_reading()
	h.c.main.show_page(&"MapPage")
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	var kept: bool = h.c.main._current_page == &"MapPage"
	h.c.main.show_page(&"ScenePage")
	ck(26, kept and h.finished_once() and h.phase_contract() and not h.room.get_node("Status/SaveStatus").visible, "hidden_page_retry_still_finishes")

func _stale() -> void:
	var ok: bool = true
	for waiting: bool in [true,false]:
		await h.ready_door(host)
		h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
		h.click("Door")
		if not waiting:
			h.finish_reading()
		var run: int = GameState.run_id
		var attempts: int = h.c.flow.checkpoint.attempts
		H.C.enter_domain(h.c.main, S.S6)
		h.ep._line_finished(run, true)
		h.exit_service.complete_before_save(run, true)
		h.exit_service.advance_time(3.0)
		h.ep._saved(run, {"run_id":run,"checkpoint":&"safehouse_exit"})
		ok = h.c.flow.checkpoint.attempts == attempts and h.c.flow.checkpoint.writes == 0 and not GameState.event_done(&"E14") and h.ep.phase == h.ep.Phase.IDLE and ok
	ck(27, ok, "old_run_callbacks_cannot_commit")
	await h.ready_door(host)
	h.click("Door")
	h.finish_reading()
	var first: bool = h.finished_once()
	var run: int = GameState.run_id
	H.C.enter_domain(h.c.main, S.S6)
	h.complete_sofa()
	h.click("Door")
	ok = h.phase_contract() and h.player.get_current_key() == "T193"
	h.finish_reading()
	ck(28, first and ok and GameState.run_id != run and h.receipts.size() == 2 and h.receipts[1][0] == GameState.run_id and h.c.flow.checkpoint.writes == 2 and h.finished.size() == 2, "fresh_run_rebinds_epilogue")

func _pages() -> void:
	await h.ready_door(host)
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.click("Door")
	var ok: bool = h.page_inputs()
	h.finish_reading()
	ok = h.page_inputs() and h.phase_contract() and ok
	for i: int in range(3):
		h.exit_service.advance_time(1.0)
		h.exit_service.complete_before_save(GameState.run_id, true)
		ok = h.page_inputs() and h.phase_contract() and ok
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	ok = h.page_inputs() and h.phase_contract() and ok
	ck(29, ok and h.finished_once(), "page_buttons_and_keys_remain_free")
	ck(40, h.c.flow.checkpoint.attempts == 5 and h.finished_once() and h.ep.line_completed, "retry_path_has_no_second_read")

func _durable() -> void:
	await h.ready_door(host)
	h.click("Door")
	h.finish_reading()
	var path: String = h.c.flow.checkpoint.path
	var restored: bool = await h.c.close()
	h.c = null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var doc: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if file != null:
		file.close()
	ck(30, restored and doc is Dictionary and H.valid_document(doc), "saved_file_reopens_with_expected_document")
	ck(31, h.read_in_new_process(path), "new_process_reads_durable_exit")
	h.clean = restored and h.clean

func _texts() -> void:
	await h.ready_door(host)
	h.click("Door")
	h.player.finish_text()
	var words: Array[String] = h.text_fields(h.room)
	words.append(h.player.get_visible_text())
	words.append(h.player._speaker.text)
	h.finish_reading()
	words.append_array(h.text_fields(h.room))
	ck(32, h.clean_words(words), "no_forbidden_terms")
	ck(33, h.exit_ids() == ["T193"] and h.player.get_lines()["T193"].text == H.THANKS and h.permitted_ui(), "no_extra_exposition_or_voice_text")
	ck(34, h.clean_words(h.global_texts(), true), "a15_global_terms_absent")

func _ending() -> void:
	await h.ready_door(host)
	var main_id: int = h.c.main.get_instance_id()
	GameState.vital_now = 73.0
	h.click("Door")
	GameState.drain_time(30.0)
	h.finish_reading()
	GameState.drain_time(30.0)
	var stable: bool = not h.room.request_object("Sofa") and not h.room.request_object("Scar") and not h.room.request_object("Door")
	ck(35, stable and h.c.main.get_instance_id() == main_id and h.c.main._current_page == &"ScenePage" and GameState.state == S.S6 and h.phase_contract() and not h.room.get_node("Objects").visible, "finish_stays_s6_without_title_scene")
	ck(36, GameState.vital_now == 73.0 and h.finished_once(), "s6_reading_and_ending_do_not_drain")
	ck(37, not h.room.interaction("Scar").read and not GameState.event_started(&"E13") and not GameState.event_done(&"E13") and h.exit_ids() == ["T193"], "exit_does_not_mark_scar_or_r14")

func _configure() -> void:
	await h.ready_door(host)
	h.ep.configure(h.c.flow)
	h.ep.configure(h.c.flow)
	h.click("Door")
	h.finish_reading()
	ck(38, h.finished_once() and h.room.exit_line_finished.get_connections().size() == 1, "configure_twice_one_connection")

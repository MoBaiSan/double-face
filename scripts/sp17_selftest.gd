## SP-17固定40条；独立固定期望、真实输入和真实隔离存档。
extends RefCounted
const H = preload("res://scripts/sp17_test_context.gd")
const S = H.S
var h = H.new()
var host: Control
var results: Dictionary = {}
var failures: int = 0

func run(root: Control) -> void:
	host = root
	for test: Callable in [_layout, _keyboard, _dialogue, _cancel, _detail, _allowlist, _door, _save_failure, _retry, _stale, _hook, _persistence, _busy, _recovery, _cleanup]:
		await test.call()
	await h.close()
	if not h.clean:
		failures += 1
	print("[SP-17] assertions=%d failures=%d" % [results.size(), failures])
	host.get_tree().quit(0 if results.size() == 40 and failures == 0 else 1)

func ck(id: int, ok: bool, name: String) -> void:
	if results.has(id):
		ok = false
	results[id] = ok
	failures += int(not ok)
	print("[SP-17] %s %02d %s" % ["PASS" if ok else "FAIL", id, name])

func _layout() -> void:
	await h.fresh(host, S.S4)
	h.c.flow._on_state_changed(S.S3, S.S4, &"exit", GameState.run_id)
	h.finish_reading()
	await host.get_tree().process_frame
	ck(1, GameState.state == S.S6 and h.c.main._current_page == &"ScenePage" and h.room == h.c.main.get_node("Pages/ScenePage/FlowContent/Safehouse") and h.room.scene_file_path == "res://scenes/ui/SafeRoomPage.tscn" and h.c.main.get_node("Pages").get_child_count() == 3, "s6_uses_scene_page")
	var step: int = h.c.map.get_step_count()
	var absent: bool = h.descendants(h.room).all(func(node: Node): return not node is CharacterBody2D and not node is CharacterBody3D and node.name not in [&"MapGrid", &"Cursor", &"CursorContainer"] and (node.get_script() == null or not "map_grid" in node.get_script().resource_path))
	h.key(KEY_RIGHT)
	ck(2, absent and h.c.map.get_step_count() == step, "safe_room_has_no_map_or_movable_actor")
	var targets: Array = h.descendants(h.room).filter(func(node: Node): return node is Control and node.focus_mode != Control.FOCUS_NONE)
	ck(3, targets.size() == 3 and targets.map(func(node: Node): return String(node.name)) == ["Sofa", "Scar", "Door"] and h.room.interaction("Sofa").progression and not h.room.interaction("Scar").progression and not h.room.interaction("Door").progression, "exactly_three_room_targets")
	ck(5, h.targets_clear(), "hit_rects_clear_and_visible")
	await h.fresh(host)
	var silent: bool = h.page_inputs()
	ck(8, silent and h.lines.is_empty() and not h.player.is_playing() and not GameState.event_done(&"E12"), "entrance_stays_silent_per_run")
	h.click("Sofa")
	ck(6, h.player.get_current_key() == "T176" and h.room.visual.get_node("VisualRoot/Hand").is_visible_in_tree(), "sofa_real_mouse_starts_dressing")
	await host.get_tree().process_frame
	ck(4, h.art_contract(), "chosen_illustration_contract")

func _keyboard() -> void:
	await h.fresh(host)
	var position: StringName = h.c.map.get_current_node_id()
	var step: int = h.c.map.get_step_count()
	h.button("Sofa").grab_focus()
	h.key(KEY_RIGHT)
	ck(34, host.get_viewport().gui_get_focus_owner() == h.button("Scar") and h.c.map.get_current_node_id() == position and h.c.map.get_step_count() == step, "arrow_keys_only_focus_objects")
	h.key(KEY_LEFT)
	h.key(KEY_ENTER)
	var reading: bool = h.player.get_current_key() == "T176"
	for i: int in range(4):
		h.key(KEY_ENTER)
	var before: bool = not GameState.event_done(&"E12") and h.room.interaction("Sofa").read
	await host.get_tree().process_frame
	h.key(KEY_ENTER)
	ck(7, reading and before and GameState.event_done(&"E12") and h.c.event_count(&"E12") == 1, "keyboard_keeps_read_then_confirm")

func _dialogue() -> void:
	await h.fresh(host)
	h.click("Sofa")
	h.player.finish_text()
	var data: Dictionary = h.player.get_lines()
	ck(10, h.player._speaker.text == "琥珀" and h.player.get_visible_text() == H.T176 and data.T176.text == H.T176 and h.player._body.visible_characters == -1, "t176_literal_visible")
	h.player.advance()
	h.player.finish_text()
	ck(11, h.player._speaker.text == "斑" and h.player.get_visible_text() == H.T177 and data.T177.text == H.T177 and h.player._body.visible_characters == -1, "t177_literal_visible")
	h.finish_reading()
	ck(9, h.ids() == ["T176", "T177"] and h.room.interaction("Sofa").read and not GameState.event_done(&"E12"), "dressing_sequence_exact_order")
	h.click("Sofa")
	h.click("Sofa")
	h.click("Sofa")
	ck(14, h.c.event_count(&"E12") == 1 and h.ids() == ["T176", "T177"], "sofa_completion_only_once")

func _cancel() -> void:
	await h.fresh(host)
	h.click("Sofa")
	h.key(KEY_ESCAPE)
	ck(12, h.player.get_current_key() == "T176" and not h.player.is_typing() and h.player.get_visible_text() == H.T176 and h.ids() == ["T176"] and not GameState.event_done(&"E12"), "dressing_cancel_only_finishes_line")
	h.player._finish(true)
	var skipped: bool = not h.room.interaction("Sofa").read and not h.room.busy
	h.click("Sofa")
	h.room._sequence_run -= 1
	h.finish_reading()
	ck(13, skipped and not h.room.interaction("Sofa").read and not GameState.event_done(&"E12") and h.c.flow.checkpoint.writes == 0, "unfinished_read_cannot_unlock_door")

func _detail() -> void:
	await h.fresh(host)
	GameState.vital_now = 73.0
	var progress: Dictionary = GameState.capture_session()
	for i: int in range(2):
		h.click("Scar")
		h.finish_reading()
	ck(15, h.lines == [["T190", "旁白", H.T190], ["T190", "旁白", H.T190]], "scar_repeat_replays_approved_ids")
	var item: Control = h.room.interaction("Scar")
	ck(18, item.get_script() == preload("res://scripts/interactable.gd") and item.read and item.has_checkmark() and item.get_read_shade().a > 0.0 and not h.button("Scar").disabled, "shared_read_feedback_preserved")
	h.click("Scar")
	h.finish_reading()
	ck(16, h.ids() == ["T190", "T190", "T190"] and GameState.vital_now == 73.0 and GameState.capture_session() == progress and not GameState.event_done(&"E12"), "scar_never_pays_or_progresses")

func _allowlist() -> void:
	await h.fresh(host)
	var rejected: bool = true
	var ids: Array = h.player.get_lines().keys()
	ids.append("unknown_sp17")
	for id: String in ids:
		if id in ["T176", "T177", "T190"]:
			continue
		rejected = not h.room.request_room_sequence(&"detail", [id]) and rejected
		rejected = not h.room.request_room_sequence(&"sofa", ["T176", id, "T177"]) and rejected
	for sample: Array in [["T176"], ["T177", "T176"], ["T190", "T190"], ["T176", "T177", "T191"]]:
		rejected = not h.room.request_room_sequence(&"sofa", sample) and rejected
	rejected = not h.room.request_room_sequence(&"detail", ["T176"]) and rejected
	rejected = not h.room.request_room_sequence(&"unknown", ["T190"]) and rejected
	await host.get_tree().process_frame
	rejected = rejected and h.lines.is_empty() and not h.player.is_playing() and not h.room.busy
	h.click("Scar")
	var unchanged: bool = not h.room.request_room_sequence(&"detail", ["T191"]) and h.player.get_current_key() == "T190"
	h.finish_reading()
	var allowed_text: bool = h.ids() == ["T190"] and h.lines[0][2] == H.T190
	for node: Node in h.descendants(h.room):
		if node is Label or node is Button:
			allowed_text = allowed_text and node.text in ["", "沙发", "斑的旧伤", "门"]
	ck(17, rejected and unchanged and allowed_text and h.player.get_lines().has("T191"), "narration_matches_allowlist")

func _door() -> void:
	await h.fresh(host)
	h.click("Door")
	h.click("Sofa")
	h.finish_reading()
	h.click("Door")
	ck(19, h.c.flow.checkpoint.attempts == 0 and h.exit_service.accepted == 0 and h.receipts.is_empty(), "door_before_sofa_does_nothing")
	h.click("Sofa")
	h.click("Door")
	h.finish_reading()
	ck(20, h.exit_service.accepted == 1 and h.exit_service.committed and h.c.flow.checkpoint.attempts == 1 and h.receipts.size() == 1, "door_mouse_starts_one_exit")
	var doc: Dictionary = h.document()
	ck(21, doc.get("version") == 1 and doc.get("checkpoint") == "safehouse_exit" and doc.get("progress") == {"safehouse_reached": true, "safehouse_exit": true, "r13_done": true, "trust_read": false}, "exit_checkpoint_round_trip")
	for i: int in range(3):
		h.click("Door")
		h.key(KEY_ENTER)
	ck(22, h.c.flow.checkpoint.writes == 1 and h.c.flow.checkpoint.attempts == 1 and h.exit_service.accepted == 1 and h.receipts.size() == 1, "repeated_door_one_success")
	ck(30, h.receipts.size() == 1 and GameState.event_done(&"E14") and h.finished.size() == 1 and h.ids() == ["T176", "T177", "T193"], "r15_finishes_after_saved")
	ck(37, not h.room.interaction("Scar").read and not GameState.event_started(&"E13") and not GameState.event_done(&"E13") and h.ids() == ["T176", "T177", "T193"], "trust_is_not_required_or_started")

func _save_failure() -> void:
	await h.fresh(host, S.S4)
	h.c.flow._on_state_changed(S.S3, S.S4, &"exit", GameState.run_id)
	h.finish_reading()
	h.complete_sofa()
	h.click("Door")
	h.finish_reading()
	h.c.flow.checkpoint.write_once(GameState.run_id, &"task_complete", {})
	h.c.flow.checkpoint.write_once(GameState.run_id, &"safehouse_exit", {})
	ck(23, h.c.flow.checkpoint.writes == 2 and h.c.flow.checkpoint.attempts == 2 and h.receipts.size() == 1, "two_checkpoint_keys_independent")
	await h.fresh(host)
	h.complete_sofa()
	h.c.flow.checkpoint.path += "/missing/save.json"
	h.click("Door")
	h.finish_reading()
	var status: Label = h.room.get_node("Status/SaveStatus")
	ck(24, h.exit_service.pending and not h.exit_service.committed and h.exit_service.last_error != OK and status.is_visible_in_tree() and status.text == "自动保存失败，正在重试。" and status.mouse_filter == Control.MOUSE_FILTER_IGNORE and status.focus_mode == Control.FOCUS_NONE and h.receipts.is_empty(), "open_failure_visible_pending")
	await h.fresh(host)
	h.c.flow.checkpoint.write_once(GameState.run_id, &"task_complete", {"safehouse_reached": true})
	var old: String = h.file_text()
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.complete_sofa()
	h.click("Door")
	h.finish_reading()
	ck(25, h.exit_service.pending and not h.exit_service.committed and h.c.flow.checkpoint.writes == 1 and h.file_text() == old and h.receipts.is_empty(), "replace_failure_preserves_previous")

func _retry() -> void:
	var payload: Dictionary = h.exit_service._payload.duplicate(true)
	var attempts: int = h.c.flow.checkpoint.attempts
	for i: int in range(3):
		h.click("Door")
		h.exit_service.request_exit(GameState.run_id)
	ck(27, h.exit_service.accepted == 1 and h.exit_service._payload == payload and h.c.flow.checkpoint.attempts == attempts and h.receipts.is_empty() and not GameState.event_done(&"E14"), "pending_rejects_duplicate_exit")
	h.exit_service.advance_time(-1.0)
	h.exit_service.advance_time(NAN)
	var held: bool = h.c.flow.checkpoint.attempts == attempts
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(0.99)
	var before: bool = h.c.flow.checkpoint.writes == 1
	h.exit_service.advance_time(0.01)
	h.exit_service.advance_time(3.0)
	ck(26, held and before and h.c.flow.checkpoint.writes == 2 and not h.exit_service.pending and h.exit_service.committed and not h.room.get_node("Status/SaveStatus").visible and h.receipts.size() == 1, "automatic_retry_completes")

func _stale() -> void:
	await h.fresh(host)
	h.complete_sofa()
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.click("Door")
	h.finish_reading()
	var attempts: int = h.c.flow.checkpoint.attempts
	var old_run: int = GameState.run_id
	GameState.begin_session(S.S6)
	h.exit_service.advance_time(1.0)
	h.exit_service.complete_before_save(old_run, true)
	var guarded: bool = h.c.flow.checkpoint.attempts == attempts and h.c.flow.checkpoint.writes == 0 and not h.exit_service.pending and not GameState.event_done(&"E12") and not GameState.event_done(&"E14")
	var reused: bool = await _reused_room()
	ck(28, guarded and reused, "old_run_cannot_save_or_finish")
	await h.fresh(host)
	h.complete_sofa()
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.click("Door")
	h.finish_reading()
	h.c.main.show_page(&"MapPage")
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service._process(1.0)
	h.c.main.show_page(&"ScenePage")
	ck(29, h.c.flow.checkpoint.writes == 1 and h.receipts.size() == 1 and h.exit_service.committed and h.room.interaction("Door").read and not h.room.get_node("Status/SaveStatus").visible, "hiding_page_does_not_drop_retry")

func _reused_room() -> bool:
	await h.fresh(host)
	h.complete_sofa()
	h.click("Door")
	h.finish_reading()
	var first: bool = h.c.flow.checkpoint.writes == 1 and h.exit_service.committed
	var previous: int = GameState.run_id
	H.C.enter_domain(h.c.main, S.S6)
	h.exit_service.complete_before_save(previous, true)
	h.complete_sofa()
	h.click("Door")
	h.finish_reading()
	return first and GameState.run_id != previous and h.c.flow.checkpoint.writes == 2 and h.receipts.size() == 2 and h.receipts[1][0] == GameState.run_id

func _hook() -> void:
	var all_ok: bool = true
	for mode: String in ["normal", "cancel", "old"]:
		await h.fresh(host)
		h.complete_sofa()
		var callback: Array = []
		h.exit_service.before_save = func(run: int, done: Callable): callback.append([run, done])
		h.click("Door")
		h.exit_service.advance_time(2.0)
		all_ok = all_ok and callback.size() == 1 and h.c.flow.checkpoint.writes == 0
		if mode == "old":
			GameState.begin_session(S.S6)
		callback[0][1].call(callback[0][0], mode != "cancel")
		callback[0][1].call(callback[0][0], true)
		all_ok = all_ok and h.c.flow.checkpoint.writes == (1 if mode == "normal" else 0) and h.receipts.size() == (1 if mode == "normal" else 0)
	ck(31, all_ok, "before_save_hook_orders_exit")

func _persistence() -> void:
	await h.fresh(host)
	h.complete_sofa()
	h.click("Scar")
	h.finish_reading()
	var room_id: int = h.room.get_instance_id()
	var pages: bool = h.page_inputs()
	ck(32, pages and h.c.flow.safe_room.get_instance_id() == room_id and h.room.interaction("Sofa").read and h.room.interaction("Scar").read and GameState.event_done(&"E12") and h.ids() == ["T176", "T177", "T190"], "page_return_preserves_room")
	GameState.vital_now = 73.0
	GameState.drain_time(30.0)
	h.click("Scar")
	GameState.drain_time(30.0)
	ck(33, GameState.vital_now == 73.0 and h.player.get_current_key() == "T190", "s6_sixty_seconds_no_drain")
	pages = h.page_inputs() and pages
	h.finish_reading()
	h.c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	h.click("Door")
	pages = h.page_inputs() and pages
	h.finish_reading()
	h.c.flow.checkpoint.replace_file = Callable()
	h.exit_service.advance_time(1.0)
	pages = h.page_inputs() and pages
	ck(35, pages and h.exit_service.committed and GameState.state == S.S6, "page_buttons_and_keys_still_work")

func _busy() -> void:
	await h.fresh(host)
	h.click("Scar")
	for id: String in ["Sofa", "Scar", "Door"]:
		h.click(id)
	var held: bool = h.player.get_current_key() == "T190" and h.ids() == ["T190"] and h.exit_service.accepted == 0
	h.finish_reading()
	h.click("Scar")
	ck(36, held and h.player.get_current_key() == "T190" and h.ids() == ["T190", "T190"], "busy_reader_blocks_room_reentry")

func _recovery() -> void:
	var recovered: bool = true
	for key: String in ["T176", "T177"]:
		await h.fresh(host)
		var data: Dictionary = h.player._lines[key].duplicate(true)
		h.player._lines.erase(key)
		h.click("Sofa")
		recovered = recovered and not h.room.busy and not h.player.is_playing() and not h.room.interaction("Sofa").read and not GameState.event_done(&"E12")
		h.player._lines[key] = data
		h.click("Sofa")
		h.finish_reading()
		recovered = recovered and h.ids() == ["T176", "T177"] and h.room.interaction("Sofa").read
	ck(38, recovered, "playback_failure_is_recoverable")
	var rejected: bool = true
	for mode: String in ["hidden", "state", "run"]:
		await h.fresh(host)
		if mode == "hidden":
			h.c.main.show_page(&"MapPage")
		elif mode == "state":
			H.C.enter_domain(h.c.main, S.S2)
		else:
			GameState.begin_session(S.S6)
		var snapshot: Dictionary = GameState.capture_session()
		for id: String in ["Sofa", "Scar", "Door"]:
			rejected = not h.room.request_object(id) and rejected
		rejected = rejected and h.lines.is_empty() and h.c.flow.checkpoint.attempts == 0 and GameState.capture_session() == snapshot
	ck(39, rejected, "wrong_state_or_hidden_target_rejected")

func _cleanup() -> void:
	var ok: bool = true
	for i: int in range(2):
		await h.fresh(host)
		h.room.configure(h.c.flow, h.exit_service)
		h.click("Scar")
		h.finish_reading()
		ok = ok and h.ids() == ["T190"] and h.room.interaction("Scar").read
	await h.close()
	ck(40, ok and h.clean, "context_cleanup_no_stale_connections")

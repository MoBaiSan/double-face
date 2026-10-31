## SP-15固定40条；每条只计一次，使用真实生产入口与Viewport事件。
extends RefCounted
const H = preload("res://scripts/sp15_test_context.gd")
const S = H.S
var h = H.new()
var root: Control
var failures: int = 0
var results: Dictionary = {}

func run(host: Control) -> void:
	root = host
	for test: Callable in [_entries, _clock, _input, _screen, _reset, _battle, _story, _repeat, _failures]:
		await test.call()
	await h.close()
	if not h.clean:
		failures += 1
	print("[SP-15] assertions=%d failures=%d" % [results.size(), failures])
	root.get_tree().quit(0 if failures == 0 and results.size() == 40 else 1)

func ck(id: int, ok: bool, label: String) -> void:
	if results.has(id):
		ok = false
	results[id] = ok
	failures += int(not ok)
	print("[SP-15] %s %02d %s" % ["PASS" if ok else "FAIL", id, label])

func _entries() -> void:
	await h.fresh(root)
	GameState.vital_now = 1.0
	GameState.pay_step()
	h.panel.set_process(false)
	ck(1, GameState.state == S.S5 and GameState.is_frozen() and h.panel.active, "vital_zero_enters_s5")
	h.panel.advance_time(0.5)
	h.c.flow._on_battle_lost()
	h.service.enter_failure(&"failure", GameState.run_id)
	ck(4, h.c.event_count(&"E10") == 1 and h.panel.start_count == 1 and h.panel.elapsed == 0.5, "e10_and_panel_start_once")
	await h.fresh(root, S.S3)
	h.fail_vital()
	ck(2, GameState.state == S.S5 and h.panel.scene_file_path == "res://scenes/ui/FailPanel.tscn" and h.panel.active, "return_zero_uses_same_failure")
	await h.fresh(root)
	h.defeat()
	ck(3, h.c.battle.player_hp == 0 and GameState.state == S.S5 and h.panel.active and h.panel.scene_file_path == "res://scenes/ui/FailPanel.tscn" and not GameState.event_started(&"E17"), "hp_zero_uses_shared_failure")
	ck(18, h.navigate() and h.c.main._current_page == &"BattlePage" and not h.c.main.show_page(&"MapPage") and h.c.battle.turn_phase == h.c.battle.State.DEFEATED and h.c.battle._return.disabled, "defeated_battle_lock_survives_modal")

func _clock() -> void:
	await h.fresh(root)
	h.fail_vital()
	h.panel.advance_time(-1)
	h.panel.advance_time(NAN)
	h.panel.advance_time(INF)
	ck(7, h.panel.elapsed == 0.0 and not h.panel.ready_for_retry, "failure_clock_rejects_invalid_delta")
	h.panel.advance_time(1.99)
	var hidden: bool = not h.panel.actions.visible and h.panel.retry.disabled
	h.panel.advance_time(0.01)
	ck(5, h.panel.retry.is_visible_in_tree() and not h.panel.retry.disabled and h.panel.elapsed <= 3.0, "retry_visible_within_three_seconds")
	ck(8, root.get_viewport().gui_get_focus_owner() == h.panel.retry, "retry_has_default_focus")
	h.panel.advance_time(100.0)
	ck(6, hidden and h.panel.ready_for_retry and h.panel.elapsed == 2.0, "failure_clock_boundary")

func _input() -> void:
	await h.fresh(root)
	var run: int = GameState.run_id
	h.fail_vital()
	h.ready_panel()
	await h.retry_mouse()
	ck(9, GameState.state == S.S2 and GameState.run_id == run + 1 and h.c.event_count(&"E11") == 1, "retry_mouse_center_works")
	await h.fresh(root)
	run = GameState.run_id
	h.fail_vital()
	h.ready_panel()
	await h.retry_key()
	ck(10, GameState.state == S.S2 and GameState.run_id == run + 1, "retry_keyboard_accept_works")
	await h.fresh(root)
	h.c.key(KEY_ENTER)
	h.fail_vital()
	h.ready_panel()
	h.c.key(KEY_ENTER, true, true)
	await root.get_tree().process_frame
	var held: bool = GameState.state == S.S5 and not h.service.busy
	h.c.key(KEY_ENTER, false)
	await h.retry_key()
	ck(11, held and GameState.state == S.S2, "held_confirm_cannot_auto_retry")

func _screen() -> void:
	await h.fresh(root)
	h.c.walk([&"c1", &"point1"])
	h.click_point(&"point1")
	var started: bool = h.c.points.get_dialogue().is_playing()
	h.fail_vital()
	var snapshot: Array = []
	for delta: float in [0.0, 0.2, 0.8, 1.0]:
		h.panel.advance_time(delta)
		snapshot.append(h.frame_signature())
	ck(14, started and not h.c.main._dialogue.is_playing() and not h.c.points.get_dialogue().is_playing() and not h.c.map.get_interactable(&"point1").read and GameState.must_done == 0 and h.c.battle.start_count == 0, "both_dialogues_cancel_without_commit")
	ck(13, h.panel.screen.get_global_rect().encloses(root.get_viewport_rect()) and h.panel.get_node("Screen/Backdrop").get_global_rect().encloses(root.get_viewport_rect()) and h.panel.get_node("Screen/Backdrop").color.a == 1.0 and h.panel.layer > 0, "fail_panel_covers_viewport")
	var buttons: Array = h.panel.find_children("*", "Button", true, false)
	ck(12, buttons.size() == 1 and buttons[0] == h.panel.retry and not h.panel.retry.disabled and root.get_viewport().gui_get_focus_owner() == h.panel.retry, "only_retry_is_interactive")
	var text_nodes: Array = h.panel.find_children("*", "Label", true, false) + h.panel.find_children("*", "RichTextLabel", true, false)
	ck(15, text_nodes.is_empty() and h.panel.retry.text == "立刻重来" and h.panel.get_node("Screen").get_child_count() == 4, "failure_has_no_caption_or_actor")
	var step: int = h.c.map.get_step_count()
	var still: bool = h.navigate()
	h.click_point(&"point1")
	ck(17, still and h.c.map.get_step_count() == step and not h.c.points.get_dialogue().is_playing() and GameState.state == S.S5, "failure_consumes_page_and_map_input")
	await h.fresh(root)
	h.defeat()
	var same: bool = true
	var index: int = 0
	for delta: float in [0.0, 0.2, 0.8, 1.0]:
		h.panel.advance_time(delta)
		same = same and h.frame_signature() == snapshot[index]
		index += 1
	ck(16, same, "same_two_visual_stages_for_both_causes")

func _reset() -> void:
	await h.fresh(root)
	var host_id: int = h.c.main.get_instance_id()
	var grid_id: int = h.c.map.get_instance_id()
	var points_id: int = h.c.points.get_instance_id()
	for i: int in range(1, 8):
		h.c.map.get_interactable(StringName("point%d" % i)).read = true
		GameState.record_investigated(StringName("point%d" % i))
	GameState._p5_won = true
	GameState._exit_consumed = true
	GameState._drain_accum = 0.009
	GameState.eaten_used = true
	h.c.map._pending_id = &"point7"
	h.c.map._hovered_id = &"point7"
	h.fail_vital()
	h.ready_panel()
	await h.retry_mouse()
	ck(19, GameState.state == S.S2 and h.c.map.get_current_node_id() == &"entry_exit" and h.c.map.get_step_count() == 0, "retry_starts_at_entry_without_step")
	var full: bool = GameState.vital_now == 100.0 and h.c.main._throat_placeholder.get_value() == 100.0 and GameState.get_drain_accum() == 0.0
	GameState.drain_time(1.0)
	ck(20, full and is_equal_approx(GameState.vital_now, 99.92) and not GameState.is_frozen(), "retry_restores_full_vital_and_clock")
	ck(21, h.all_unread(), "all_seven_points_unread_again")
	ck(22, GameState.must_done == 0 and not GameState.exit_open and not GameState._p5_read and not GameState._p5_won and not GameState._exit_consumed and not h.c.main.get_node("Pages/MapPage/ReturnHint").visible, "progress_and_exit_flags_reset")
	ck(23, h.c.map._visited == {&"entry_exit": true} and h.c.map._pending_id == &"" and h.c.map._hovered_id == &"" and h.c.map._revealed == {&"entry_exit": true, &"c1": true}, "map_cursor_reveal_and_visited_reset actual=%s" % [[h.c.map._visited, h.c.map._pending_id, h.c.map._hovered_id, h.c.map.get_revealed_ids()]])
	ck(28, not GameState.eaten_used, "eaten_used_resets_without_sp24")
	ck(39, h.c.main.get_instance_id() == host_id and h.c.map.get_instance_id() == grid_id and h.c.points.get_instance_id() == points_id and not h.panel.active and not h.panel.visible, "retry_clears_overlay_and_preserves_host")

func _battle() -> void:
	await h.fresh(root)
	h.c.walk(H.C.ROUTE)
	h.c.read_point()
	h.c.battle.submit_command(3)
	h.c.battle.advance_time(0.4)
	h.c.battle.advance_time(0.4)
	h.c.battle.submit_command(1)
	var old_id: int = h.c.battle.get_instance_id()
	var run: int = GameState.run_id
	var old: WeakRef = weakref(h.c.battle)
	h.c.battle.player_hp = 0
	h.c.battle._defeat()
	h.panel.set_process(false)
	h.ready_panel()
	await h.retry_mouse()
	ck(24, h.battle_full(), "both_fighters_full_after_retry")
	ck(26, old.get_ref() == null and h.c.battle.get_instance_id() != old_id and GameState.run_id == run + 1 and h.c.battle._run_id == run + 1, "battle_identity_matches_new_run")
	var b = h.c.battle
	ck(27, b.turn_phase == b.State.INACTIVE and b.turn_count == 0 and b.start_count == 0 and b.elapsed == 0 and not b._started and not b._settled and not b._returned and not b.has_method("can_show_page") and not b.get_property_list().any(func(p: Dictionary): return p.name == "_return_permit") and not b._charged and b._received_multiplier == 1.0, "battle_latches_are_fresh")
	var before: Array = [GameState.vital_now, GameState.must_done, GameState.state]
	var refused: bool = not GameState.request_transition(&"failure", run) and not GameState.record_investigation(&"point1", run)
	h.service.enter_failure(&"failure", run)
	ck(29, refused and before == [GameState.vital_now, GameState.must_done, GameState.state] and not h.panel.active, "stale_callbacks_cannot_mutate_new_run")
	h.c.walk(H.C.ROUTE)
	var reading: bool = h.click_point(&"point5")
	h.c.points.get_dialogue().finish_text()
	h.c.key(KEY_ENTER)
	h.c.key(KEY_ENTER, false)
	ck(32, reading and GameState.state == S.S2B and b.start_count == 1 and b._run_id == GameState.run_id, "second_point5_real_click_starts_battle")
	b.submit_command(3)
	ck(25, b.player_hp == 100 and b.item_uses == 0, "emergency_item_refills_to_one")

func _story() -> void:
	await h.fresh(root, S.S0)
	h.opening()
	var finished: bool = GameState.state == S.S2 and h.c.main._dialogue.get_story_phase() == &"DONE"
	var seen: Array = []
	h.c.main._dialogue.line_started.connect(func(key: String): seen.append(key))
	h.fail_vital()
	h.ready_panel()
	await h.retry_mouse()
	h.c.flow.request_page(&"ScenePage")
	h.c.main.get_node("Pages/ScenePage/PageNav").reading_requested.emit(h.c.main.get_node("Pages/ScenePage/TestOptions/OptionTwo"))
	ck(30, finished and h.c.main._dialogue.get_story_phase() == &"DONE" and seen.is_empty() and not GameState.event_started(&"E1"), "retry_does_not_replay_r1_r4")
	h.c.flow.request_page(&"MapPage")
	h.c.key(KEY_DOWN)
	h.c.key(KEY_DOWN, false)
	ck(31, seen.is_empty() and not GameState.event_started(&"E5") and GameState.state == S.S2 and h.c.map.get_current_node_id() == &"c1", "retry_skips_departure_and_entry_read")
	var moved: bool = h.c.map.get_step_count() == 1 and GameState.vital_now == 99.0
	h.c.key(KEY_DOWN)
	h.c.key(KEY_DOWN, false)
	var reading: bool = h.click_point(&"point1")
	h.c.points.get_dialogue().finish_text()
	h.c.key(KEY_ENTER)
	h.c.key(KEY_ENTER, false)
	ck(33, moved and reading and not h.c.points.get_dialogue().is_playing(), "recovered_map_real_inputs_work")
	ck(40, h.c.main._page_switch_bar._real_page_cycle(h.c.main) and GameState.state == S.S2 and h.clean, "normal_page_switching_restored")

func _repeat() -> void:
	await h.fresh(root)
	var run: int = GameState.run_id
	var grid_connections: int = h.c.map.moved.get_connections().size()
	var old: Array[WeakRef] = []
	var all_reset: bool = true
	for i: int in range(4):
		old.append(weakref(h.c.battle))
		if i == 1: h.defeat()
		else: h.fail_vital()
		h.ready_panel()
		if i == 0:
			h.panel.retry.pressed.emit()
			h.panel.retry.pressed.emit()
		await h.retry_mouse()
		all_reset = all_reset and GameState.state == S.S2 and h.battle_full() and h.all_unread() and GameState.must_done == 0 and GameState.vital_now == 100
		if i == 0:
			ck(34, GameState.run_id == run + 1 and h.c.event_count(&"E11") == 1, "double_retry_changes_run_once")
		if i == 2:
			ck(35, all_reset and GameState.run_id == run + 3 and h.panel.start_count == 3, "fail_retry_fail_three_same")
	ck(36, all_reset and GameState.run_id == run + 4 and h.panel.start_count == 4, "retry_not_capped_at_three")
	var links: int = 0
	for connection: Dictionary in h.c.map._interactions.investigated.get_connections():
		links += int(connection["callable"] == Callable(h.c.battle, "_on_investigated"))
	ck(37, old.all(func(ref: WeakRef): return ref.get_ref() == null) and links == 1 and h.c.map.moved.get_connections().size() == grid_connections, "retry_does_not_accumulate_connections")

func _failures() -> void:
	var both: bool = true
	for after_commit: bool in [false, true]:
		await h.fresh(root)
		h.fail_vital()
		h.ready_panel()
		both = await h.failed_rebuild(after_commit) and both
	ck(38, both, "failed_rebuild_is_retryable")

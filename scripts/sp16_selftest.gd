## SP-16：真实输入、固定期望与独立临时档。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const EMPTY: Dictionary = {"investigation": false, "vital": false, "battle": false}
const NAMES: Array[String] = [
	"s0_teaches_with_zero_text", "s0_first_option_selected",
	"s0_real_direction_and_confirm", "investigation_first_eligible_exact_text",
	"investigation_ineligible_never_claims", "investigation_hint_never_repeats",
	"investigation_hint_does_not_block", "vital_hint_on_real_point_debit",
	"vital_hint_ignores_other_changes", "vital_hint_second_third_absent",
	"vital_hint_within_ten_seconds", "no_hint_on_cancel_failed_or_zero_payment",
	"point5_handoff_preserves_tutorial_flags", "battle_first_attack_immediate",
	"battle_never_opens_tutorial_dialog", "battle_keyboard_half_second_boundary",
	"battle_keyboard_dwell_resets", "battle_three_mouse_explanations",
	"battle_help_clears_on_action_or_leave", "battle_each_help_once_in_first_encounter",
	"battle_rebind_ignores_old_actor", "hint_copy_whitelist_and_length",
	"hint_mouse_passthrough", "hint_rects_do_not_overlap_controls",
	"tutorial_flags_survive_retry", "tutorial_flags_roundtrip",
	"tutorial_old_save_defaults_false", "tutorial_does_not_add_save",
	"tutorial_save_failure_keeps_old_and_memory", "tutorial_fixture_restore_exact",
	"four_teaching_categories_only", "tutorial_keeps_gameplay_state",
	"hint_slots_are_independent", "battle_hint_not_delayed_by_map_hint",
	"entering_battle_clears_map_hint"
]
var host: Control
var c: RefCounted
var t: Node
var shown: Array = []
var failures: int = 0
var assertions: int = 0
var ids: Dictionary = {}
var cleanup_ok: bool = true
var path: String = ""

func run(root: Control) -> int:
	host = root
	await _map_cases()
	await _vital_cases()
	await _battle_cases()
	await _battle_more()
	await _save_cases()
	await _contracts()
	await _independent()
	await _close()
	if assertions != 35 or not cleanup_ok:
		failures += 1
		print("[SP-16] FAIL count_or_fixture_restore")
	print("[SP-16] assertions=%d failures=%d" % [assertions, failures])
	return failures

func _fresh(initial: int = GameState.State.S2) -> void:
	await _close()
	c = C.new()
	await c.create(host, initial)
	t = c.main.get_node("Overlay/TutorialHints")
	t.set_process(false)
	GameState.tutorial_seen = EMPTY.duplicate(true)
	GameState.tutorial_loaded = true
	shown.clear()
	t.hint_shown.connect(func(kind: StringName, copy: String): shown.append([kind, copy]))
	path = "user://sp16_%d.json" % c.main.get_instance_id()
	c.flow.checkpoint.path = path
	t.advance_time(0.0)
	_mouse(Vector2(2, 2))
	await _frame()

func _close() -> void:
	if c != null:
		cleanup_ok = await c.close() and cleanup_ok
		c = null
	for candidate: String in [path, path + ".tmp"]:
		if not path.is_empty() and FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	path = ""

func _frame() -> void:
	await host.get_tree().process_frame

func _key(code: Key) -> void:
	c.key(code)
	c.key(code, false)

func _mouse(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	c.main.get_viewport().push_input(event, true)

func _go(id: StringName) -> void:
	c.walk_to(id)
	t.advance_time(0.0)
	await _frame()

func _read() -> void:
	c.read_point()
	await _frame()

func _start_battle() -> void:
	await _fresh()
	await _go(&"point5")
	await _read()
	t.advance_time(0.0)
	_mouse(Vector2(2, 2))

func _count(kind: StringName) -> int:
	return shown.filter(func(row: Array): return row[0] == kind).size()

func ck(id: int, passed: bool) -> void:
	assertions += 1
	if ids.has(id):
		passed = false
	ids[id] = true
	if not passed:
		failures += 1
	print("[SP-16] %s %02d %s" % ["PASS" if passed else "FAIL", id, NAMES[id - 1]])

func _map_cases() -> void:
	await _fresh(GameState.State.S0)
	ck(1, not t.map_slot.visible and not t.battle_slot.visible and t.map_slot.text == "" and t.battle_slot.text == "")
	var nav: Control = c.main._scene_nav
	var first: Control = nav.get_candidates()[0]
	ck(2, nav.get_selected() == first and nav._outlines[first.get_instance_id()].active)
	c.finish_sequence(c.main._dialogue)
	_key(KEY_DOWN)
	var moved: bool = nav.get_selected() != first
	_key(KEY_ENTER)
	ck(3, moved and c.main._dialogue.is_playing())
	await _fresh()
	var ineligible: bool = await _ineligible_cases()
	await _go(&"point1")
	ck(4, t.map_slot.visible and t.map_slot.text == "停在这里，按一下确认" and GameState.tutorial_seen.investigation)
	ck(5, ineligible)
	await _go(&"c1")
	await _go(&"point1")
	c.main.show_page(&"ScenePage")
	c.main.show_page(&"MapPage")
	t.advance_time(0.0)
	ck(6, _count(&"investigation") == 1 and not t.map_slot.visible)
	await _fresh()
	await _go(&"point1")
	_key(KEY_ENTER)
	t.advance_time(0.0)
	ck(7, c.points.get_dialogue().is_playing() and not t.map_slot.visible)

func _ineligible_cases() -> bool:
	var ok: bool = not t.map_slot.visible and not GameState.tutorial_seen.investigation
	_mouse(c.map.get_global_transform() * c.map.get_point_position_for_test(&"point1"))
	t.advance_time(0.0)
	ok = ok and not t.map_slot.visible and not c.map.try_move_to(&"point5")
	var item: Control = c.map.get_interactable(&"point1")
	item.set_read(true)
	await _go(&"point1")
	ok = ok and not t.map_slot.visible and not GameState.tutorial_seen.investigation
	item.set_read(false)
	c.main.show_page(&"ScenePage")
	t.advance_time(0.0)
	ok = ok and not GameState.tutorial_seen.investigation
	c.main.show_page(&"MapPage")
	c.map.confirm_selection()
	t.advance_time(0.0)
	ok = ok and c.points.get_dialogue().is_playing() and not t.map_slot.visible
	c.points.get_dialogue()._finish(true)
	C.enter_domain(c.main, GameState.State.S3)
	t.advance_time(0.0)
	ok = ok and not GameState.tutorial_seen.investigation
	C.enter_domain(c.main, GameState.State.S2)
	return ok

func _vital_cases() -> void:
	await _fresh()
	await _go(&"point1")
	var before: float = GameState.vital_now
	_key(KEY_ENTER)
	t.advance_time(0.0)
	var late: bool = _count(&"vital") == 0
	c.finish_sequence(c.points.get_dialogue())
	await _frame()
	ck(8, late and GameState.vital_now < before and t.map_slot.text == "调查会消耗嗓子条" and _count(&"vital") == 1)
	t.advance_time(2.99)
	var still_visible: bool = t.map_slot.visible
	t.advance_time(0.01)
	var timed_out: bool = not t.map_slot.visible
	await _go(&"point2")
	await _read()
	await _go(&"point3")
	await _read()
	ck(10, _count(&"vital") == 1)
	ck(11, still_visible and timed_out)
	await _fresh()
	GameState._set_vital(90.0, &"time")
	GameState._set_vital(89.0, &"step")
	GameState._set_vital(99.0, &"win")
	t.advance_time(1.0)
	ck(9, _count(&"vital") == 0 and not GameState.tutorial_seen.vital)
	await _go(&"point1")
	_key(KEY_ENTER)
	c.points.get_dialogue()._finish(true)
	GameState.set_frozen(true)
	c.read_point()
	GameState.set_frozen(false)
	GameState.vital_now = 0.0
	t.advance_time(0.0)
	ck(12, _count(&"vital") == 0 and not GameState.tutorial_seen.vital and not t.map_slot.visible and not t.battle_slot.visible)

func _battle_cases() -> void:
	await _start_battle()
	var buttons: Array = c.battle._buttons
	ck(13, GameState.state == GameState.State.S2B and GameState.tutorial_seen.battle and not GameState.tutorial_seen.vital and t.map_pending.is_empty() and not buttons[0].disabled)
	var default_attack: bool = c.main.get_viewport().gui_get_focus_owner() == buttons[0]
	ck(15, t.find_children("*", "Button", true, false).is_empty() and t.find_children("*", "Popup", true, false).is_empty() and not c.main._dialogue.is_playing())
	_key(KEY_RIGHT)
	t.advance_time(0.49)
	var hidden: bool = not t.battle_slot.visible
	t.advance_time(0.01)
	ck(16, hidden and t.battle_slot.visible and t.battle_slot.text == "下次攻击更强，受伤更多")
	_key(KEY_DOWN)
	t.advance_time(0.3)
	_key(KEY_LEFT)
	t.advance_time(0.3)
	ck(17, not t.battle_slot.visible)
	var originals: Array = ["下次攻击更强，受伤更多", "本轮受到的伤害减半", "用一份药恢复生命"]
	var all_hover: bool = true
	for index: int in range(1, 4):
		await _start_battle()
		_mouse(c.battle._buttons[index].get_global_rect().get_center())
		await _frame()
		all_hover = all_hover and t.battle_slot.visible and t.battle_slot.text == originals[index - 1]
	ck(18, all_hover)
	await _start_battle()
	var all_visible: bool = c.battle._buttons.all(func(b: Button): return b.is_visible_in_tree() and not b.disabled)
	_key(KEY_ENTER)
	ck(14, default_attack and all_visible and c.battle.turn_count == 1 and c.battle.enemy_hp < 100)

func _battle_more() -> void:
	await _start_battle()
	_key(KEY_RIGHT)
	t.advance_time(0.5)
	_key(KEY_ENTER)
	t.advance_time(0.0)
	var action_clears: bool = not t.battle_slot.visible
	await _start_battle()
	_mouse(c.battle._buttons[1].get_global_rect().get_center())
	await _frame()
	t.advance_time(3.0)
	ck(19, action_clears and not t.battle_slot.visible)
	_mouse(Vector2(2, 2))
	_mouse(c.battle._buttons[1].get_global_rect().get_center())
	await _frame()
	var no_repeat: bool = not t.battle_slot.visible
	_mouse(c.battle._buttons[2].get_global_rect().get_center())
	await _frame()
	ck(20, no_repeat and t.battle_slot.text == "本轮受到的伤害减半" and _count(&"battle") == 2)
	c.main.show_page(&"MapPage")
	c.main.show_page(&"BattlePage")
	var retained: bool = not t.battle_slot.visible and GameState.tutorial_seen.battle and t._seen.has(1) and t._seen.has(2)
	ck(21, await _rebuilt_battle_keeps_memory() and retained)
	var texts: Array = [t.INVESTIGATION, t.VITAL, t.HELP[1], t.HELP[2], t.HELP[3]]
	ck(22, texts == ["停在这里，按一下确认", "调查会消耗嗓子条", "下次攻击更强，受伤更多", "本轮受到的伤害减半", "用一份药恢复生命"] and texts.slice(1).all(func(s: String): return s.length() <= 14 and not s.contains("！")))
	await _start_battle()
	_mouse(c.battle._buttons[1].get_global_rect().get_center())
	await _frame()
	c.click(c.battle._buttons[1])
	ck(23, c.battle.turn_count == 1 and c.battle._charged and t.battle_slot.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	ck(24, _rects_safe())

func _rebuilt_battle_keeps_memory() -> bool:
	var old_id: int = c.battle.get_instance_id()
	c.replace_battle()
	C.enter_domain(c.main, GameState.State.S2)
	await _go(&"point5")
	await _read()
	t.advance_time(0.0)
	var focused: bool = c.main.get_viewport().gui_get_focus_owner() == c.battle._buttons[0]
	_mouse(c.battle._buttons[1].get_global_rect().get_center())
	await _frame()
	return c.battle.get_instance_id() != old_id and focused and GameState.tutorial_seen.battle and not t.battle_slot.visible

func _rects_safe() -> bool:
	t.advance_time(0.0)
	var battle_rect: Rect2 = t.battle_slot.get_global_rect()
	var map_rect: Rect2 = t.map_slot.get_global_rect()
	for node: Control in [c.battle.get_node("CommandWindow"), c.battle.get_node("StatusWindow"), c.battle.get_node("ReturnButton"), c.main.get_node("Overlay/PageSwitchBar"), c.main.get_node("Overlay/ThroatPlaceholder")]:
		if battle_rect.intersects(node.get_global_rect()):
			return false
	for panel: Control in [c.main._dialogue.get_node("Panel"), c.points.get_dialogue().get_node("Panel")]:
		if map_rect.intersects(panel.get_global_rect()):
			return false
	print("[SP-16] RECT map=%s battle=%s" % [map_rect, battle_rect])
	return not map_rect.intersects(c.main.get_node("Pages/MapPage/MapArea").get_global_rect()) and not map_rect.intersects(battle_rect)

func _save_cases() -> void:
	await _start_battle()
	GameState.tutorial_seen = {"investigation": true, "vital": true, "battle": true}
	var previous_actor: int = c.battle.get_instance_id()
	GameState.vital_now = 0.0
	c.flow.recovery.panel.advance_time(3.0)
	c.flow.request_retry()
	await _frame()
	await _frame()
	t.advance_time(0.0)
	ck(25, GameState.state == GameState.State.S2 and c.main.get_node("Pages/BattlePage").get_instance_id() != previous_actor and GameState.tutorial_seen == {"investigation": true, "vital": true, "battle": true})
	var cp: RefCounted = c.flow.checkpoint
	GameState.tutorial_seen = {"investigation": true, "vital": false, "battle": true}
	var saved: bool = cp.write_once(GameState.run_id, &"task_complete", {"safehouse_reached": true})
	GameState.tutorial_seen = EMPTY.duplicate(true)
	GameState.tutorial_loaded = false
	GameState.import_tutorial(cp.read_saved().get("tutorial", {}))
	ck(26, saved and cp.read_saved().get("version") == 1 and GameState.tutorial_seen == {"investigation": true, "vital": false, "battle": true})
	GameState.tutorial_seen = EMPTY.duplicate(true)
	GameState.import_tutorial({"investigation": "true", "vital": 1, "unknown": true})
	var invalid_false: bool = GameState.tutorial_seen == EMPTY
	GameState.import_tutorial({})
	GameState.import_tutorial(null)
	ck(27, invalid_false and GameState.tutorial_seen == EMPTY)
	t.advance_time(4.0)
	var duplicate: bool = cp.write_once(GameState.run_id, &"task_complete", {})
	ck(28, duplicate and cp.writes == 1 and cp.attempts == 1 and cp.read_saved().progress.safehouse_reached)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(cp.path)
	GameState.tutorial_seen = {"investigation": true, "vital": true, "battle": true}
	cp.replace_file = func(_a: String, _b: String): return ERR_FILE_CANT_WRITE
	var refused: bool = not cp.write_once(GameState.run_id, &"safehouse_exit", {"done": true})
	var preserved: bool = FileAccess.get_file_as_bytes(cp.path) == bytes and GameState.tutorial_seen.vital
	cp.replace_file = Callable()
	var recovered: bool = cp.write_once(GameState.run_id, &"safehouse_exit", {"done": true})
	ck(29, refused and preserved and recovered and cp.read_saved().get("tutorial", {}).get("vital", false) == true)

func _contracts() -> void:
	await _close()
	ck(30, cleanup_ok)
	await _fresh(GameState.State.S0)
	var zero: bool = t.map_slot.text.is_empty() and t.battle_slot.text.is_empty()
	await _fresh()
	await _go(&"point1")
	var investigated: bool = t.map_slot.text == "停在这里，按一下确认"
	await _read()
	var vital: bool = t.map_slot.text == "调查会消耗嗓子条"
	await _start_battle()
	_mouse(c.battle._buttons[1].get_global_rect().get_center())
	await _frame()
	ck(31, zero and investigated and vital and t.battle_slot.text == "下次攻击更强，受伤更多" and t.get_child_count() == 2)
	var values: Array = [GameState.state, GameState.is_frozen(), GameState.vital_now, c.battle.player_hp, c.battle.enemy_hp, c.battle.item_uses, c.battle.turn_count]
	t.advance_time(0.5)
	t.advance_time(3.0)
	ck(32, values == [GameState.state, GameState.is_frozen(), GameState.vital_now, c.battle.player_hp, c.battle.enemy_hp, c.battle.item_uses, c.battle.turn_count])

func _independent() -> void:
	await _start_battle()
	_key(KEY_RIGHT)
	t.advance_time(0.3)
	t.map_pending = {"run": GameState.run_id, "epoch": t.map_epoch}
	t._clear_map()
	t.advance_time(0.2)
	ck(33, t.map_slot != t.battle_slot and t.battle_slot.text == "下次攻击更强，受伤更多" and t.battle_pending.dwell >= 0.5)
	await _fresh()
	await _go(&"point5")
	var map_was_present: bool = t.map_slot.visible and t.map_elapsed < 3.0
	c.read_point()
	var cleared_same_frame: bool = not t.map_slot.visible and t.map_slot.text.is_empty() and t.map_pending.is_empty() and t.map_elapsed == 0.0
	_key(KEY_RIGHT)
	t.advance_time(0.49)
	var early_hidden: bool = not t.battle_slot.visible
	t.advance_time(0.01)
	var on_time: bool = t.battle_slot.text == "下次攻击更强，受伤更多"
	_mouse(c.battle._buttons[3].get_global_rect().get_center())
	await _frame()
	ck(34, map_was_present and early_hidden and on_time and t.battle_slot.text == "用一份药恢复生命" and GameState.tutorial_seen.battle)
	await _frame()
	ck(35, cleared_same_frame and not t.map_slot.visible and t.map_slot.text.is_empty() and GameState.tutorial_seen.investigation and not GameState.tutorial_seen.vital)

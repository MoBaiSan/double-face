## SP-12：真实域/输入、固定台词与时钟边界；不改旧组判据。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const IDS: Array[String] = ["T132", "T141", "T146"]
const TEXTS: Array[String] = ["我这儿信号挺好——你那边呢？", "三个了。你果然一样一样地看。", "琥珀君。我快唱不动了，剩下的别管了。"]
const NAMES: Array[String] = [
	"caption_texts_exact", "t132_requested_on_third_successful_move",
	"failed_moves_do_not_count", "free_revisit_is_still_a_move",
	"t132_fourth_move_does_not_repeat", "t141_ignores_optional_points",
	"t141_arms_without_playing", "t141_requested_on_next_successful_move",
	"fourth_required_does_not_repeat_t141", "point5_counts_only_after_win",
	"t146_on_downward_critical_edge", "t146_band_boundaries",
	"t146_once_per_run", "t146_ignores_rise_and_non_inside",
	"retry_rearms_t132", "retry_rearms_t141",
	"retry_t146_waits_for_new_drop", "critical_snapshot_is_not_a_new_edge",
	"caption_queue_plays_when_busy", "caption_holds_then_fades",
	"caption_real_direction_keeps_working", "caption_natural_drain_unchanged",
	"caption_does_not_block_investigation", "caption_has_no_portraits_or_mask",
	"caption_and_tutorial_slots_independent", "caption_rect_avoids_controls",
	"hidden_caption_resumes_remaining_time", "battle_suspends_and_preserves_alarm",
	"caption_queue_dropped_on_failure", "caption_memory_snapshot_no_extra_save",
	"caption_view_does_not_change_read_auto", "caption_rejects_non_whitelist_and_stale_host"]
var host: Control
var c: RefCounted
var t: Node
var shown: Array = []
var failures: int = 0
var checked: Dictionary = {}
var cleanup_ok: bool = true
var path: String = ""

func run(root: Control) -> int:
	host = root
	await _text_and_moves()
	await _required_points()
	await _bands()
	await _retry_and_snapshot()
	await _queue_and_time()
	await _interaction()
	await _teaching()
	await _battle_and_failure()
	await _contracts()
	await _close()
	if checked.size() != 32 or not cleanup_ok:
		failures += 1
		print("[SP-12] FAIL count_or_fixture_restore")
	print("[SP-12] assertions=%d failures=%d" % [checked.size(), failures])
	return failures

func _fresh(initial: int = GameState.State.S2) -> void:
	await _close()
	c = C.new()
	await c.create(host, initial)
	t = c.main.get_node("Overlay/InsideCaptions")
	t.set_process(false)
	var tutorial: Node = c.main.get_node("Overlay/TutorialHints")
	tutorial.set_process(false)
	GameState.tutorial_seen = {"investigation": true, "vital": true, "battle": true}
	tutorial.advance_time(0.0)
	shown.clear()
	t.caption_started.connect(func(key: String, step: int): shown.append([key, step]))
	path = "user://sp12_%d.json" % c.main.get_instance_id()
	c.flow.checkpoint.path = path
	t.advance_time(0.0)

func _close() -> void:
	if c != null:
		cleanup_ok = await c.close() and cleanup_ok
		c = null
	for candidate: String in [path, path + ".tmp"]:
		if not path.is_empty() and FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	path = ""

func _key(code: Key) -> void:
	c.key(code)
	c.key(code, false)

func _go(id: StringName) -> void:
	c.walk_to(id)
	await host.get_tree().process_frame

func _read() -> void:
	c.read_point()
	await host.get_tree().process_frame

func _flush() -> void:
	for turn: int in range(3):
		t.advance_time(3.25)

func _count(key: String) -> int:
	return shown.filter(func(row: Array): return row[0] == key).size()

func ck(id: int, passed: bool) -> void:
	if checked.has(id):
		passed = false
	checked[id] = passed
	if not passed:
		failures += 1
	print("[SP-12] %s %02d %s" % ["PASS" if passed else "FAIL", id, NAMES[id - 1]])

func _text_and_moves() -> void:
	await _fresh()
	t.request_captions(IDS)
	var exact: bool = true
	for index: int in range(3):
		var entry: Dictionary = t.player.get_lines()[IDS[index]]
		exact = exact and entry.text == TEXTS[index] and entry.speaker == "斑" and entry.mode == "caption"
		exact = exact and t.player.get_current_key() == IDS[index] and t.player.get_visible_text() == TEXTS[index] and not t.player.is_typing()
		exact = exact and not t.player.get_node("Panel/Margin/TextLayout/Speaker").visible
		t.advance_time(3.25)
	ck(1, exact)
	await _fresh()
	_key(KEY_LEFT)
	GameState.vital_now = 0.5
	_key(KEY_DOWN)
	ck(3, c.map.get_step_count() == 0 and c.map.get_current_node_id() == &"entry_exit" and shown.is_empty())
	GameState.vital_now = 100.0
	_key(KEY_DOWN)
	_key(KEY_UP)
	var early: bool = shown.is_empty() and c.map.get_step_count() == 2
	_key(KEY_DOWN)
	ck(2, early and shown == [["T132", 3]] and c.map.get_step_count() == 3)
	ck(4, GameState.vital_now == 99.0 and c.map.get_current_node_id() == &"c1")
	_key(KEY_UP)
	_flush()
	ck(5, _count("T132") == 1 and c.map.get_step_count() == 4)

func _required_points() -> void:
	await _fresh()
	for id: StringName in [&"point6", &"point7"]:
		await _go(id)
		await _read()
	ck(6, GameState.must_done == 0 and GameState.inside_caption_state.t141_after_step == -1 and _count("T141") == 0)
	await _fresh()
	c.read_first(3)
	_flush()
	var armed: int = GameState.inside_caption_state.t141_after_step
	ck(7, GameState.must_done == 3 and armed == c.map.get_step_count() and _count("T141") == 0)
	var denied: bool = not c.map.try_move_to(&"entry_exit")
	c.map.try_move_to(&"point4")
	ck(8, denied and shown.back() == ["T141", armed + 1])
	await _read()
	c.map.try_move_to(&"point3")
	_flush()
	ck(9, GameState.must_done == 4 and _count("T141") == 1)
	await _fresh()
	c.read_first(2)
	await _go(&"point5")
	_flush()
	await _read()
	var before_win: bool = GameState.must_done == 2 and GameState.inside_caption_state.t141_after_step == -1
	c.win()
	armed = GameState.inside_caption_state.t141_after_step
	c.return_battle()
	var no_return_move: bool = _count("T141") == 0 and c.map.get_step_count() == armed
	c.map.try_move_to(&"point4")
	_flush()
	ck(10, before_win and no_return_move and GameState.must_done == 3 and _count("T141") == 1)

func _bands() -> void:
	await _fresh()
	GameState.vital_now = 31.0
	var early: bool = shown.is_empty()
	GameState.vital_now = 30.0
	ck(11, early and _count("T146") == 1)
	GameState.vital_now = 35.0
	GameState.vital_now = 29.0
	GameState.vital_now = 28.0
	_flush()
	ck(13, _count("T146") == 1)
	var boundaries: bool = true
	var values: Array[float] = [31.0, 30.99, 30.0, 1.0, 0.99, 0.0]
	var bands: Array[StringName] = [&"low", &"critical", &"critical", &"critical", &"broken", &"broken"]
	for index: int in range(values.size()):
		await _fresh()
		GameState.vital_now = 31.0
		GameState.vital_now = values[index]
		boundaries = boundaries and GameState.get_band_for_value(values[index]) == bands[index] and _count("T146") == (1 if index in [1, 2, 3] else 0)
		print("[SP-12] BAND value=%s band=%s starts=%d" % [values[index], GameState.get_band_for_value(values[index]), _count("T146")])
	ck(12, boundaries)
	await _fresh()
	GameState.vital_now = 0.5
	GameState.vital_now = 2.0
	var rising_ignored: bool = shown.is_empty()
	for state: int in [GameState.State.S0, GameState.State.S1, GameState.State.S6]:
		await _fresh(state)
		GameState.vital_now = 29.0
		rising_ignored = rising_ignored and shown.is_empty()
	ck(14, rising_ignored)

func _retry_and_snapshot() -> void:
	await _fresh()
	t.request_captions(IDS)
	GameState.vital_now = 0.0
	c.flow.recovery.panel.advance_time(3.0)
	c.flow.request_retry()
	await host.get_tree().process_frame
	c.attach(c.main)
	t.advance_time(0.0)
	shown.clear()
	var no_replay: bool = t.pending.is_empty() and not t.player.is_playing() and GameState.vital_now == 100.0
	_key(KEY_DOWN)
	_key(KEY_UP)
	_key(KEY_DOWN)
	ck(15, no_replay and shown == [["T132", 3]])
	c.read_first(3)
	_flush()
	var before: bool = _count("T141") == 0
	c.map.try_move_to(&"point4")
	_flush()
	ck(16, before and _count("T141") == 1)
	before = _count("T146") == 0
	GameState.vital_now = 31.0
	GameState.vital_now = 30.0
	ck(17, before and _count("T146") == 1)
	await _fresh()
	var snapshot: Dictionary = GameState.capture_session()
	snapshot._vital_now = 30.0
	snapshot.inside_caption_state.last_vital = 30.0
	snapshot.inside_caption_state.last_band = &"critical"
	GameState.begin_session(GameState.State.S2, snapshot)
	t.advance_time(0.0)
	GameState.vital_now = 29.0
	ck(18, shown.is_empty() and GameState.inside_caption_state.requested.is_empty())

func _queue_and_time() -> void:
	await _fresh()
	await _go(&"point1")
	GameState.vital_now = 31.0
	_key(KEY_RIGHT)
	var first: bool = t.player.get_current_key() == "T146" and t.pending == ["T132"]
	_key(KEY_RIGHT)
	t.advance_time(1.0)
	t.request_captions(["T141"])
	t.request_captions(IDS)
	var kept: bool = t.player.get_current_key() == "T146" and t.pending == ["T132", "T141"]
	t.advance_time(2.25)
	kept = kept and t.player.get_current_key() == "T132"
	_flush()
	ck(19, first and kept and shown == [["T146", 2], ["T132", 4], ["T141", 4]] and t.pending.is_empty())
	await _fresh()
	t.request_captions(["T132"])
	t.advance_time(2.99)
	var hold: bool = t.player.is_playing() and is_equal_approx(t.player.get_caption_alpha(), 1.0)
	t.advance_time(0.01)
	hold = hold and is_equal_approx(t.player.get_caption_alpha(), 1.0)
	t.advance_time(0.125)
	var fade: bool = t.player.get_caption_alpha() > 0.0 and t.player.get_caption_alpha() < 1.0
	t.advance_time(0.125)
	ck(20, hold and fade and not t.player.is_playing())

func _interaction() -> void:
	await _fresh()
	t.request_captions(["T132"])
	_key(KEY_DOWN)
	_key(KEY_ENTER)
	_key(KEY_ESCAPE)
	ck(21, c.map.get_current_node_id() == &"c1" and c.map.get_step_count() == 1 and t.player.is_playing())
	var before: float = GameState.vital_now
	var freezes: Array = []
	c.watch(GameState.frozen_changed, func(value: bool): freezes.append(value))
	GameState.drain_time(1.0)
	t.advance_time(1.0)
	ck(22, is_equal_approx(before - GameState.vital_now, 0.08) and freezes.is_empty() and not GameState.is_frozen() and not host.get_tree().paused)
	await _go(&"point1")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = c.map.get_global_transform() * c.map.get_point_position_for_test(&"point1")
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		c.main.get_viewport().push_input(event, true)
	ck(23, c.points.get_dialogue().is_playing() and t.player.get_current_key() == "T132")
	c.finish_sequence(c.points.get_dialogue())
	var no_art: bool = ["TextureRect", "Sprite2D", "AnimatedSprite2D", "Polygon2D", "CanvasModulate"].all(func(kind: String): return t.player.find_children("*", kind, true, false).is_empty())
	ck(24, no_art and c.main.find_children("*", "CanvasModulate", true, false).is_empty() and t.player.get_node("Panel").get_theme_stylebox("panel") is StyleBoxEmpty and not c.main.get_node("Pages/ScenePage").visible and not c.main.get_node("Pages/BattlePage").visible and c.main.modulate == Color.WHITE)
	c.main.show_page(&"ScenePage")
	t.advance_time(2.0)
	var hidden: bool = not t.player.visible
	c.main.show_page(&"MapPage")
	t.advance_time(1.99)
	var remaining: bool = t.player.visible and is_equal_approx(t.player.get_caption_alpha(), 1.0)
	t.advance_time(0.26)
	ck(27, hidden and remaining and not t.player.is_playing() and _count("T132") == 1)

func _teaching() -> void:
	await _fresh()
	var tutorial: Node = c.main.get_node("Overlay/TutorialHints")
	GameState.tutorial_seen = {"investigation": false, "vital": false, "battle": false}
	await _go(&"point1")
	tutorial.advance_time(0.0)
	t.request_captions(["T132"])
	var simultaneous: bool = t.player.visible and tutorial.map_slot.visible and tutorial.map_slot.text == "停在这里，按一下确认"
	await host.get_tree().process_frame
	ck(26, _rects(tutorial))
	await _go(&"point5")
	await _read()
	_key(KEY_RIGHT)
	tutorial.advance_time(0.49)
	var early: bool = not tutorial.battle_slot.visible
	tutorial.advance_time(0.01)
	ck(25, simultaneous and early and tutorial.battle_slot.text == "下次攻击更强，受伤更多" and not tutorial.map_slot.visible and not t.player.visible)

func _rects(tutorial: Node) -> bool:
	var rect: Rect2 = t.player.get_node("Panel").get_global_rect()
	print("[SP-12] RECT caption=%s map_hint=%s battle_hint=%s" % [rect, tutorial.map_slot.get_global_rect(), tutorial.battle_slot.get_global_rect()])
	for node: Control in [tutorial.map_slot, tutorial.battle_slot, c.points.get_dialogue().get_node("Panel"), c.main.get_node("Pages/MapPage/MapArea"), c.main.get_node("Pages/MapPage/ExitConfirm"), c.main.get_node("Overlay/PageSwitchBar"), c.main.get_node("Overlay/ThroatPlaceholder")]:
		if rect.intersects(node.get_global_rect()):
			return false
	return rect.position.is_equal_approx(Vector2(512, 180)) and rect.size.is_equal_approx(Vector2(614.4, 40)) and t.player.get_node("Panel/Margin/TextLayout/Body").get_line_count() == 1

func _battle_and_failure() -> void:
	await _fresh()
	await _go(&"point5")
	GameState.vital_now = 31.0
	GameState.vital_now = 30.0
	await _read()
	t.advance_time(9.0)
	var hidden: bool = not t.player.visible and t.pending.has("T146")
	c.win()
	c.return_battle()
	t.advance_time(3.25)
	ck(28, hidden and GameState.vital_now >= 31.0 and t.player.get_current_key() == "T146" and t.player.visible)
	await _fresh()
	t.request_captions(IDS)
	GameState.vital_now = 0.0
	t.advance_time(20.0)
	var cleared: bool = GameState.state == GameState.State.S5 and t.pending.is_empty() and not t.player.is_playing() and not t.player.visible and not t.request_captions(["T132"])
	ck(29, cleared and await _exit_clears())

func _exit_clears() -> bool:
	await _fresh()
	c.read_first(5)
	c.win()
	c.return_battle()
	c.walk_to(&"entry_exit")
	t.request_captions(IDS)
	var queued: bool = not t.pending.is_empty()
	c.map.confirm_selection()
	t.advance_time(10.0)
	return queued and GameState.state == GameState.State.S4 and t.pending.is_empty() and not t.player.is_playing() and not t.player.visible

func _contracts() -> void:
	await _fresh()
	t.request_captions(["T132"])
	var saved: Dictionary = GameState.capture_session()
	GameState.begin_session()
	GameState.begin_session(GameState.State.S2, saved)
	ck(30, GameState.inside_caption_state.requested == {"T132": true} and GameState.inside_caption_state.played == {"T132": true} and GameState.tutorial_seen == {"investigation": true, "vital": true, "battle": true} and c.flow.checkpoint.writes == 0 and not FileAccess.file_exists(path))
	await _fresh()
	c.main._dialogue.play("T133")
	var read_ok: bool = c.main._dialogue.get_current_mode() == "read" and c.main._dialogue.get_node("Panel").get_theme_stylebox("panel") is StyleBoxFlat
	c.main._dialogue.play("T122")
	var auto_ok: bool = c.main._dialogue.get_current_mode() == "auto" and c.main._dialogue.get_node("Panel").get_theme_stylebox("panel") is StyleBoxFlat
	var rejected: bool = not t.player.play_seq(["T132", "T133"])
	ck(31, read_ok and auto_ok and rejected and not t.player.is_playing() and c.main.get_node("Overlay").find_children("InsideCaptions", "", false, false).size() == 1)
	var illegal: bool = not t.request_captions(["T132", "T151"]) and GameState.inside_caption_state.requested.is_empty()
	var presenter: Callable = GameState.presenter
	GameState.presenter = Callable()
	var stale: bool = not t.request_captions(["T132"])
	GameState.presenter = presenter
	ck(32, illegal and stale and shown.is_empty())

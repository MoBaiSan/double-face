## SP-24 固定样本与独立会话自检；不替代像素试玩与独立复审。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const B = preload("res://scripts/battle.gd")
const NAMES: Array[String] = [
	"prediction_before_hp_write", "exact_half_does_not_trigger", "first_crossing_from_half_triggers",
	"already_below_is_not_retroactive", "mitigation_multiplies_before_rounding", "once_per_battle",
	"second_third_crossings_do_not_repeat", "battle_entry_is_not_the_trigger",
	"four_effects_start_same_frame", "shadow_and_dim_last_one_draw", "caption_exact_t151",
	"caption_holds_1_5_then_fades", "caption_input_does_not_wait_or_skip", "sp12_queue_is_untouched",
	"sp12_default_duration_stays_three", "caption_rects_do_not_overlap",
	"free_page_turn_does_not_replay_or_cut", "no_explanatory_text", "no_portrait_or_camera_switch",
	"retry_resets_eaten_used", "failed_retry_keeps_used", "old_actor_cannot_present",
	"failure_clears_effects", "non_damage_does_not_consume", "all_thresholds_use_maximum_hp",
	"rounding_boundary_predicts_candidate", "dim_is_transient_not_black", "fresh_host_has_no_stale_visuals"]
var host: Control
var c: RefCounted
var t: Node
var b: Control
var failures: int = 0
var checked: Dictionary = {}
var clean: bool = true
var roll: float = 1.0
var samples: int = 0
var path: String = ""

func run(root: Control) -> int:
	host = root
	await _thresholds()
	await _scales()
	await _repeat()
	await _visuals()
	await _timing()
	await _queue()
	await _pages()
	await _retry()
	await _guards()
	await _close()
	if checked.size() != 28 or not clean:
		failures += 1
		print("[SP-24] FAIL count_or_fixture_restore")
	print("[SP-24] assertions=%d failures=%d" % [checked.size(), failures])
	return failures

func ck(id: int, ok: bool) -> void:
	if checked.has(id):
		ok = false
	checked[id] = ok
	if not ok:
		failures += 1
	print("[SP-24] %s %02d %s" % ["PASS" if ok else "FAIL", id, NAMES[id - 1]])

func _fresh(start: bool = true) -> void:
	await _close()
	c = C.new()
	await c.create(host, GameState.State.S2)
	t = c.main.get_node("Overlay/InsideCaptions")
	t.set_process(false)
	c.main.get_node("Overlay/TutorialHints").set_process(false)
	GameState.tutorial_seen = {"investigation": true, "vital": true, "battle": true}
	c.main.get_node("Overlay/TutorialHints").advance_time(0.0)
	path = "user://sp24_%d.json" % c.main.get_instance_id()
	c.flow.checkpoint.path = path
	t.advance_time(0.0)
	b = c.battle
	if start:
		clean = c.walk(C.ROUTE) and c.read_point() and clean
		t._stop()
		await c.main._wait_for_layout()
	samples = 0
	b.random_sample = func(): samples += 1; return roll

func _close() -> void:
	if c != null:
		clean = await c.close() and clean
		c = null
	for file: String in [path, path + ".tmp"]:
		if not path.is_empty() and FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	path = ""

func _hit(hp: int, command: int = 0, sample: float = 1.0) -> void:
	if b.turn_phase == B.State.ENEMY_ACTION:
		b.advance_time(0.4)
	roll = sample
	b.player_hp = hp
	b.submit_command(command)
	b.advance_time(0.4)

func _key(key: Key) -> void:
	c.key(key)
	c.key(key, false)

func _thresholds() -> void:
	await _fresh()
	var seen: Array = []
	c.watch(b.incoming_damage, func(p: float, hp: int, _maximum: int): seen.append([p, hp, GameState.eaten_used]))
	_hit(60)
	ck(1, seen == [[20.0, 60, true]] and b.player_hp == 50 and samples == 2 and c.event_count(&"E16") == 1)
	for row: Array in [[2, 70, 50, false], [3, 50, 40, true], [4, 49, 29, false]]:
		await _fresh()
		_hit(row[1])
		ck(row[0], b.player_hp == row[2] and GameState.eaten_used == row[3] and t.eaten_starts == (1 if row[3] else 0))
	var bounds: bool = true
	for row: Array in [[10.49, false, 50], [10.5, true, 55]]:
		await _fresh()
		_hit(60, 0, row[0] / 20.0)
		bounds = bounds and GameState.eaten_used == row[1] and b.player_hp == row[2] and samples == 2
	ck(26, bounds)

func _scales() -> void:
	var exact: bool = true
	for row: Array in [[60, 0, 1.0, 50], [55, 2, 1.0, 50], [60, 1, 0.9, 49]]:
		await _fresh()
		_hit(row[0], row[1], row[2])
		exact = exact and b.player_hp == row[3] and t.eaten_starts == 1
	ck(5, exact)
	var maxima: bool = true
	for row: Array in [[150, 85, true, 75], [150, 95, false, 75], [101, 71, false, 51], [101, 70, true, 60]]:
		await _fresh()
		b._knobs["battle_player_hp_max"] = row[0]
		_hit(row[1])
		maxima = maxima and GameState.eaten_used == row[2] and b.player_hp == row[3]
	ck(25, maxima)

func _repeat() -> void:
	await _fresh()
	ck(8, not GameState.eaten_used and t.eaten_starts == 0 and not is_instance_valid(t.eaten_view))
	b.enemy_hp = 1000
	_hit(60)
	_hit(70)
	ck(6, b.player_hp == 50 and t.eaten_starts == 1 and c.event_count(&"E16") == 1 and b._received_multiplier == 1.0)
	var once: bool = true
	for hp: int in [69, 69, 40]:
		_hit(hp)
		once = once and b.player_hp == hp - 20 and t.eaten_starts == 1
	ck(7, once and GameState.eaten_used and c.event_count(&"E16") == 1)

func _visuals() -> void:
	await _fresh()
	var page: StringName = c.main._current_page
	var camera: Camera2D = c.main.get_viewport().get_camera_2d()
	var frame: int = Engine.get_process_frames()
	_hit(60)
	var dim: ColorRect = t.eaten_view.get_node("PaperDim")
	var smear: Node2D = t.eaten_view.get_node("LeftSmear")
	var record: Dictionary = t.eaten_receipt
	t.advance_time(2.0)
	ck(9, dim.is_visible_in_tree() and smear.is_visible_in_tree() and t.eaten_player.is_visible_in_tree() and t.eaten_player.get_caption_alpha() == 1.0 and b.player_hp == 50 and [record.shadow_frame, record.dim_frame, record.caption_frame, record.damage_frame] == [frame, frame, frame, frame])
	ck(11, t.eaten_player.get_current_key() == "T151" and t.eaten_player.get_visible_text() == "歌声卡了一下。" and t.eaten_player.get_current_mode() == "caption" and not t.eaten_player._speaker.visible and t.eaten_player._body.visible_characters == -1)
	var text: Array[String] = []
	for node: Node in t.eaten_view.find_children("*", "", true, false):
		if node is Label and node.is_visible_in_tree() and not node.text.is_empty(): text.append(node.text)
		if node is RichTextLabel and node.is_visible_in_tree() and not node.text.is_empty(): text.append(node.text)
	ck(18, text == ["歌声卡了一下。"])
	var shapes: bool = smear.get_child_count() == 3 and smear.get_children().all(func(node: Node): return node is Polygon2D)
	for kind: String in ["Sprite2D", "TextureRect", "Camera2D", "AudioStreamPlayer"]:
		shapes = shapes and t.eaten_view.find_children("*", kind, true, false).is_empty()
	ck(19, shapes and page == c.main._current_page and camera == c.main.get_viewport().get_camera_2d())
	var modulate_before: Color = c.main.modulate
	var transient: bool = is_equal_approx(dim.color.a, 0.12) and dim.mouse_filter == Control.MOUSE_FILTER_IGNORE
	var connected: bool = RenderingServer.frame_post_draw.is_connected(t._eaten_draw_completed)
	t._eaten_draw_completed()
	for i: int in range(3): t._eaten_draw_completed()
	ck(10, connected and not dim.visible and not smear.visible and record.draws == 1)
	ck(27, transient and not dim.visible and c.main.modulate == modulate_before)
	print("[SP-24] FRAME receipt=%s shadow_visible=%s dim_visible=%s" % [record, smear.visible, dim.visible])

func _timing() -> void:
	await _fresh()
	_hit(60)
	t._eaten_draw_completed()
	t.advance_time(1.49)
	var times: Array = [t.eaten_player.get_caption_alpha()]
	t.advance_time(0.01)
	times.append(t.eaten_player.get_caption_alpha())
	t.advance_time(0.125)
	times.append(t.eaten_player.get_caption_alpha())
	t.advance_time(0.125)
	ck(12, is_equal_approx(times[0], 1) and is_equal_approx(times[1], 1) and is_equal_approx(times[2], 0.5) and not t.eaten_player.is_playing() and not t.eaten_view.visible)
	await _fresh()
	_hit(60)
	_key(KEY_ENTER)
	_key(KEY_ESCAPE)
	c.click(t.eaten_player.get_node("Panel"))
	var still: bool = t.eaten_player.is_playing() and t.eaten_player._elapsed == 0.0 and b.turn_count == 1
	b.advance_time(0.4)
	var prior: int = b.enemy_hp
	c.click(b._buttons[0])
	print("[SP-24] INPUT still=%s turns=%d enemy=%d prior=%d paused=%s page=%s focus=%s" % [still, b.turn_count, b.enemy_hp, prior, c.main.get_tree().paused, c.main._current_page, c.main.get_viewport().gui_get_focus_owner()])
	ck(13, still and b.turn_count == 2 and b.enemy_hp < prior and not c.main.get_tree().paused)
	print("[SP-24] TIME alpha_1.49/1.50/1.625=%s end_1.75=true" % [times])

func _queue() -> void:
	await _fresh(false)
	var started: Array[String] = []
	c.watch(t.player.line_started, func(key: String): started.append(key))
	t.request_captions(["T132", "T141", "T146"])
	t.advance_time(1.0)
	clean = c.walk(C.ROUTE) and c.read_point() and clean
	var waiting: Array = t.pending.duplicate()
	var clock: float = t.player._elapsed
	_hit(60)
	t.advance_time(1.75)
	var untouched: bool = t.pending == waiting and t.player._elapsed == clock and started == ["T132"]
	b.enemy_hp = 20
	b.advance_time(0.4)
	b.submit_command(0)
	b.advance_time(0.4)
	c.return_battle()
	t.advance_time(2.25)
	t.advance_time(3.25)
	t.advance_time(3.25)
	ck(14, untouched and started == ["T132", "T141", "T146"] and t.pending.is_empty())
	await _fresh(false)
	t.request_captions(["T132"])
	t.advance_time(2.99)
	var held: bool = t.player.get_caption_alpha() == 1.0 and t.player.is_playing()
	t.advance_time(0.26)
	ck(15, held and not t.player.is_playing() and t.player.caption_hold_seconds == 3.0)

func _pages() -> void:
	await _fresh()
	b.submit_command(0)
	clean = c.main._flow.request_page(&"MapPage") and clean
	b.player_hp = 60
	b.advance_time(0.4)
	var free: bool = c.main._current_page == &"MapPage" and t.eaten_view.is_visible_in_tree() and b.player_hp == 50
	_key(KEY_PAGEUP)
	_key(KEY_PAGEDOWN)
	c.main._flow.request_page(&"BattlePage")
	ck(17, free and t.eaten_starts == 1 and GameState.eaten_used and b.player_hp == 50)
	await host.get_tree().process_frame
	var rect: Rect2 = t.eaten_player.get_node("Panel").get_global_rect()
	var tutorial: Node = c.main.get_node("Overlay/TutorialHints")
	tutorial._layout()
	var clear: bool = rect.position.is_equal_approx(Vector2(64, 50.4)) and rect.size.is_equal_approx(Vector2(819.2, 40))
	for node: Control in [t.player.get_node("Panel"), tutorial.map_slot, tutorial.battle_slot]:
		clear = clear and not rect.intersects(node.get_global_rect())
	ck(16, clear and t.eaten_player._body.get_line_count() == 1)
	print("[SP-24] RECT hit=%s inside=%s map_hint=%s battle_hint=%s" % [rect, t.player.get_node("Panel").get_global_rect(), tutorial.map_slot.get_global_rect(), tutorial.battle_slot.get_global_rect()])

func _retry() -> void:
	await _fresh()
	_hit(60)
	var old_run: int = GameState.run_id
	var old_id: int = b.get_instance_id()
	var recovery: Node = c.flow.recovery
	GameState.vital_now = 0.0
	recovery.panel.set_process(false)
	recovery.panel.advance_time(2.0)
	recovery.battle_factory = func(): return null
	var accepted: bool = c.flow.request_retry()
	await host.get_tree().process_frame
	ck(21, accepted and GameState.state == GameState.State.S5 and GameState.run_id == old_run and GameState.eaten_used and b.get_instance_id() == old_id and not recovery.busy)
	recovery.battle_factory = Callable()
	c.click(recovery.panel.retry)
	await host.get_tree().process_frame
	c.attach(c.main)
	b = c.battle
	b.set_process(false)
	b.random_sample = func(): samples += 1; return roll
	var reset: bool = GameState.state == GameState.State.S2 and GameState.run_id == old_run + 1 and not GameState.eaten_used and b.get_instance_id() != old_id and b.player_hp == 100 and b.item_uses == 1
	clean = c.walk(C.ROUTE) and c.read_point() and clean
	_hit(60)
	ck(20, reset and GameState.eaten_used and b.player_hp == 50 and t.eaten_starts == 1 and t.eaten_receipt.run == GameState.run_id)
	ck(22, not t.present_eaten(b, old_run) and not t.can_present_eaten(host.get_node("Pages/BattlePage"), GameState.run_id) and t.eaten_starts == 1)

func _guards() -> void:
	await _fresh()
	_hit(60, 3)
	var none: bool = not GameState.eaten_used and t.eaten_starts == 0 and b.player_hp == 80
	_hit(60, 0, 0.0)
	ck(24, none and not GameState.eaten_used and b.player_hp == 60 and t.eaten_starts == 0)
	var cleared: bool = true
	for target: int in [GameState.State.S4, GameState.State.S6]:
		await _fresh()
		_hit(60)
		t._state_changed(GameState.State.S2B, target, &"test", GameState.run_id)
		cleared = cleared and not t.eaten_view.visible and not t.eaten_player.is_playing() and not t._eaten_flash
	await _fresh()
	_hit(50, 2, 20.0)
	t.advance_time(3.0)
	ck(23, cleared and GameState.state == GameState.State.S5 and b.player_hp == 0 and not t.eaten_view.visible and not t.eaten_player.is_playing())
	await _rebuild_caption_host()

func _rebuild_caption_host() -> void:
	await _fresh()
	_hit(60)
	var run: int = GameState.run_id
	c.main.get_node("Overlay").remove_child(t)
	t.free()
	t = load("res://scripts/inside_captions.gd").new()
	c.main.get_node("Overlay").add_child(t)
	t.configure(c.main)
	t.set_process(false)
	t.advance_time(0.0)
	_hit(70)
	var links: int = 0
	for row: Dictionary in RenderingServer.frame_post_draw.get_connections():
		if row.callable.get_object() == t and row.callable.get_method() == &"_eaten_draw_completed":
			links += 1
	ck(28, GameState.run_id == run and GameState.eaten_used and b.player_hp == 50 and t.eaten_starts == 0 and not is_instance_valid(t.eaten_view) and links == 1)

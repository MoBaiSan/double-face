## SP-15与SP-14迁移的显式夹具；所有故障只注入测试对象。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const S = C.S
var c: RefCounted
var root: Control
var clean: bool = true
var panel: CanvasLayer
var service: Node
var candidate_run: int = -1

func fresh(host: Control, initial: int = S.S2) -> void:
	if c != null:
		clean = await c.close() and clean
	root = host
	c = C.new()
	await c.create(host, initial)
	service = c.flow.recovery
	panel = service.panel

func close() -> void:
	if c != null:
		clean = await c.close() and clean
		c = null

func fail_vital() -> void:
	GameState.vital_now = 0.0
	panel.set_process(false)

func ready_panel() -> void:
	panel.advance_time(2.0)

func defeat() -> void:
	c.walk(C.ROUTE)
	c.read_point()
	c.battle.player_hp = 10
	c.battle.random_sample = func(): return 1.0
	c.battle.submit_command(0)
	c.battle.advance_time(0.4)
	panel.set_process(false)

func retry_mouse() -> void:
	c.click(panel.retry)
	await root.get_tree().process_frame
	c.attach(c.main)
	c.battle.set_process(false)

func retry_key() -> void:
	c.key(KEY_ENTER)
	c.key(KEY_ENTER, false)
	await root.get_tree().process_frame
	c.attach(c.main)
	c.battle.set_process(false)

func click_point(id: StringName) -> bool:
	var pos: Vector2 = c.map.get_global_transform_with_canvas() * c.map.get_point_position_for_test(id)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		c.main.get_viewport().push_input(event, true)
	return c.points.get_dialogue().is_playing()

func navigate() -> bool:
	var before: StringName = c.main._current_page
	for key: Key in [KEY_PAGEUP, KEY_PAGEDOWN]:
		c.key(key)
		c.key(key, false)
	for button: Button in c.main._page_switch_bar._buttons:
		c.click(button)
	return before == c.main._current_page

func all_unread() -> bool:
	for i: int in range(1, 8):
		var item: Control = c.map.get_interactable(StringName("point%d" % i))
		if item == null or item.read:
			return false
	return true

func battle_full() -> bool:
	return c.battle.player_hp == 100 and c.battle.enemy_hp == 100 and c.battle.item_uses == 1

func frame_signature() -> Array:
	return [panel.elapsed, panel.actions.visible,
		panel.get_node("Screen/CutMarker").points,
		panel.get_node("Screen/ChannelMask/LeftEdge").offset_right,
		panel.get_node("Screen/ChannelMask/RightEdge").offset_left]

func opening() -> void:
	c.finish_sequence(c.main._dialogue)
	var nav: Control = c.main.get_node("Pages/ScenePage/PageNav")
	nav.reading_requested.emit(c.main.get_node("Pages/ScenePage/TestOptions/OptionTwo"))
	for i: int in range(6):
		c.finish_sequence(c.main._dialogue)
	c.key(KEY_DOWN)
	c.key(KEY_DOWN, false)

func _make_tracked() -> Control:
	var actor: Control = load("res://scenes/ui/BattlePage.tscn").instantiate()
	actor.tree_exiting.connect(func(): candidate_run = actor._run_id)
	return actor

func failed_rebuild(after_commit: bool) -> bool:
	var run: int = GameState.run_id
	var old: Control = c.battle
	var map_page: Control = c.main._pages[&"MapPage"]
	var completed: int = service.completed_count
	candidate_run = -1
	service.battle_factory = _make_tracked if after_commit else func(): return null
	if after_commit:
		c.main._pages.erase(&"MapPage")
	c.click(panel.retry)
	var accepted: bool = service.busy and GameState.run_id == run
	await root.get_tree().process_frame
	var failed: bool = accepted and GameState.state == S.S5 and GameState.is_frozen() and GameState.run_id == run
	failed = failed and c.main.get_node("Pages/BattlePage") == old and c.main._pages[&"BattlePage"] == old
	failed = failed and GameState.battle_actor.get_ref() == old and not GameState.event_started(&"E11")
	failed = failed and service.completed_count == completed and service.last_receipt.is_empty()
	failed = failed and not service.busy and not panel.retry.disabled and panel.active
	failed = failed and candidate_run == (run + 1 if after_commit else -1)
	c.main._pages[&"MapPage"] = map_page
	service.battle_factory = Callable()
	await retry_mouse()
	return failed and GameState.state == S.S2 and GameState.run_id == run + 1 and c.event_count(&"E11") == 1 and service.last_receipt.get("run_id") == run + 1 and c.battle._run_id == run + 1

static func legacy_interfaces(c, check: Callable, start: Callable) -> void:
	GameState.vital_now = 0.0
	c.flow.recovery.panel.set_process(false)
	check.call(48, GameState.state == S.S5 and GameState.is_frozen() and not c.map.try_move_to(&"c1") and not c.main._dialogue.is_playing(), "S5立即锁定无失败台词")
	c.key(KEY_PAGEUP)
	c.key(KEY_PAGEDOWN)
	for button: Button in c.main.get_node("Overlay/PageSwitchBar")._buttons: c.click(button)
	c.return_battle()
	check.call(49, GameState.state == S.S5 and c.main._current_page == &"MapPage" and c.flow.recovery.panel.visible and GameState.is_frozen() and GameState.vital_now == 0, "探索归零模态锁页且返回不解除失败")
	var saved: Callable = c.flow.retry_service
	c.flow.retry_service = Callable()
	check.call(50, not c.flow.request_retry() and not c.flow.request_title() and GameState.state == S.S5, "服务未装不假重来或标题")
	c.flow.retry_service = saved
	var calls: Array = [0]
	c.flow.title_service = func(): calls[0] += 1; return true
	var title: bool = c.flow.request_title()
	check.call(53, title and calls[0] == 1 and not GameState.event_started(&"E11") and GameState.state == S.S5, "标题仅交宿主不串重来")
	var session: int = GameState.run_id
	var rejected: bool = not c.flow.retry_ready({"battle": c.battle, "map": c.map}, session)
	c.replace_battle()
	var accepted: bool = c.flow.retry_ready({"battle": c.battle, "map": c.map}, session)
	var reset: bool = rejected and accepted and c.battle.start_count == 0 and c.battle.item_uses == 1 and c.battle.enemy_hp == 100
	var initial: bool = GameState.state == S.S2 and GameState.vital_now == 100.0 and c.map.get_current_node_id() == &"entry_exit" and not GameState.event_started(&"E1") and GameState.event_done(&"E11")
	var started: bool = start.call()
	check.call(51, reset and started, "重来必须新战斗实例和全复位，真实点5调查可开战")
	check.call(52, initial and GameState.run_id == session + 1 and c.battle._run_id == GameState.run_id, "新局直接S2不重播开场，后继战斗绑定新局代号")

static func legacy_s5(c) -> bool:
	C.enter_domain(c.main, S.S2)
	GameState.vital_now = 0.0
	for key: Key in [KEY_PAGEDOWN, KEY_PAGEUP]: c.key(key)
	for button: Button in c.main._page_switch_bar._buttons: c.click(button)
	return c.main._current_page == &"MapPage" and GameState.state == S.S5 and GameState.is_frozen() and c.flow.recovery.panel.visible and GameState.vital_now == 0.0

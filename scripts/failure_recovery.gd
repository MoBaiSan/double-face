## S5共用失败服务。重来保留Main/地图，事务性更换战斗实例。
extends Node
const PANEL = preload("res://scenes/ui/FailPanel.tscn")
const BATTLE = preload("res://scenes/ui/BattlePage.tscn")
var flow: Node
var main: Control
var panel: CanvasLayer
var failed_run: int = -1
var busy: bool = false
var battle_factory: Callable
var last_receipt: Dictionary = {}
var completed_count: int = 0

func configure(director: Node) -> void:
	flow = director
	main = flow.main
	panel = PANEL.instantiate()
	main.add_child(panel)
	panel.retry_pressed.connect(_request_retry)
	flow.failure_entered.connect(enter_failure)
	flow.retry_service = reset_after_fail
	main.visibility_changed.connect(_sync_visibility)

func owns_session() -> bool:
	return is_instance_valid(flow) and GameState.presenter == Callable(flow, "_present")

func enter_failure(_reason: StringName, session: int) -> void:
	if not owns_session() or GameState.state != GameState.State.S5:
		return
	if session != GameState.run_id or session == failed_run:
		return
	failed_run = session
	last_receipt.clear()
	busy = false
	panel.start()
	_sync_visibility()

func _sync_visibility() -> void:
	if not is_instance_valid(panel) or not panel.active:
		return
	panel.visible = owns_session() and main.is_visible_in_tree()

func route_input(event: InputEvent) -> bool:
	if not owns_session():
		return false
	return panel.route_input(event)

func _request_retry() -> void:
	flow.request_retry()

## true只是收件成功；完成必须等待retry_ready、E11及收据。
func reset_after_fail(session: int) -> bool:
	if not owns_session() or GameState.state != GameState.State.S5:
		return false
	if session != GameState.run_id or session != failed_run or busy or not panel.ready_for_retry:
		return false
	busy = true
	panel.set_busy(true)
	_rebuild.call_deferred(session)
	return true

func _make_battle() -> Control:
	return battle_factory.call() if battle_factory.is_valid() else BATTLE.instantiate()

func _rebuild(session: int) -> void:
	if not owns_session() or session != GameState.run_id or GameState.state != GameState.State.S5:
		_attempt_failed()
		return
	var candidate: Control = _make_battle()
	if not is_instance_valid(candidate):
		_attempt_failed()
		return
	var old: Control = main.get_node("Pages/BattlePage")
	var modes: Dictionary = _detach(old)
	candidate.name = &"BattlePage"
	candidate.visible = false
	main.get_node("Pages").add_child(candidate)
	main._pages[&"BattlePage"] = candidate
	if not candidate.is_fresh_for_retry():
		_restore_actor(old, candidate, modes)
		_attempt_failed()
		return
	main._connect_page_nav(candidate)
	main.get_node("Overlay/Points").cancel_pending_for_failure()
	flow.map.reset_map()
	GameState.vital_now = GameState.vital_max
	if not flow.retry_ready({"battle": candidate, "map": flow.map}, session):
		_restore_actor(old, candidate, modes)
		_attempt_failed()
		return
	old.free()
	busy = false

func _detach(actor: Control) -> Dictionary:
	var modes: Dictionary = {"visible": actor.visible, "process": actor.is_processing(),
		"input": actor.is_processing_input(), "unhandled": actor.is_processing_unhandled_input()}
	actor.set_process(false)
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	main.get_node("Pages").remove_child(actor)
	return modes

func _restore_actor(old: Control, candidate: Control, modes: Dictionary) -> void:
	main.get_node("Pages").remove_child(candidate)
	candidate.free()
	main.get_node("Pages").add_child(old)
	main._pages[&"BattlePage"] = old
	old.visible = modes["visible"]
	old.set_process(modes["process"])
	old.set_process_input(modes["input"])
	old.set_process_unhandled_input(modes["unhandled"])
	flow._bind_battle()
	flow._present(GameState.state)

func _attempt_failed() -> void:
	busy = false
	if is_instance_valid(panel):
		panel.set_busy(false)
		_sync_visibility()

func complete_retry(session: int, actor: Control) -> void:
	if not owns_session() or session != failed_run or GameState.state != GameState.State.S2:
		return
	if not GameState.event_done(&"E11") or actor._run_id != GameState.run_id:
		return
	last_receipt = {"failed_run": session, "run_id": GameState.run_id,
		"battle": actor.get_instance_id(), "map": flow.map.get_instance_id()}
	completed_count += 1
	busy = false
	panel.dismiss()

func _exit_tree() -> void:
	if is_instance_valid(main) and main.visibility_changed.is_connected(_sync_visibility):
		main.visibility_changed.disconnect(_sync_visibility)
	if is_instance_valid(flow) and flow.retry_service == reset_after_fail:
		flow.retry_service = Callable()
	if is_instance_valid(panel):
		panel.queue_free()

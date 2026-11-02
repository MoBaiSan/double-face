## 状态只由 GameState 持有；此节点装配事件和同步呈现。
extends Node
signal failure_entered(reason: StringName, session: int)
signal retry_requested(session: int)
signal title_requested(session: int)
signal first_map_move
signal investigation_completed(point: StringName)
signal battle_entered
signal s1_finished
signal safehouse_entered
signal prologue_finished
var recovery: Node
var main: Control
var dialogue: Control
var map: Control
var content: Control
var safe_room: Control
var room_exit: Node
var epilogue: Node
var checkpoint = preload("res://scripts/prologue_checkpoint.gd").new()
var retry_service: Callable
var title_service: Callable
var presenting: bool = false
var _sequence_event: StringName = &""
var _sequence_run: int = -1
var _pending_checkpoint_run: int = -1
var _checkpoint_retry_elapsed: float = 0.0
const CHECKPOINT_RETRY_SECONDS: float = 1.0
var _battle_id: int = 0
var _dialogue_inputs: Array[Control] = []
var dialogue_factory: Callable
var assembly_ready: bool = false
var _restored_branch_run: int = -1
var last_error: String = ""
var _opening_serial: int = 0
var _opening_token: int = -1
var _opening_run: int = -1
var _opening_pending: bool = false
var _opening_queued: bool = false
var _opening_handed: bool = false
var _event_seen: Array[String] = []
var _departure_phase: StringName = &"NONE"
var _departure_run: int = -1
var _departure_seen: Array[String] = []
var _departure_keys: Array = []

func configure(host: Control) -> bool:
	if main != null:
		return assembly_ready
	if not GameState.configuration_valid:
		last_error = GameState.configuration_error
		return false
	main = host
	map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	content = main.get_node("Pages/ScenePage/FlowContent")
	content.configure()
	var saved: Dictionary = GameState.capture_session()
	dialogue = dialogue_factory.call() if dialogue_factory.is_valid() else preload("res://scenes/ui/DialogueBox.tscn").instantiate()
	main.get_node("Overlay").add_child(dialogue)
	main._dialogue = dialogue
	if not dialogue.data_valid:
		last_error = dialogue.last_error
		return _abort_configuration(saved)
	var points := preload("res://scripts/points.gd").new()
	main.get_node("Overlay").add_child(points)
	points.configure(main, dialogue)
	if not points._valid or not points.get_dialogue().data_valid or not points.get_dialogue().get_lines().has("T157"):
		last_error = "序章调查或T157台词数据无效"
		return _abort_configuration(saved, points)
	GameState.begin_session()
	GameState.presenter = _present
	dialogue.sequence_finished.connect(_on_sequence_finished)
	dialogue.stage_started.connect(_on_stage_started)
	dialogue.stage_finished.connect(_on_stage_finished)
	dialogue.line_started.connect(_on_story_line)
	if not map.bind_progress(points):
		last_error = "序章地图缺少T157"
		return _abort_configuration(saved, points)
	_bind_dialogue_input(dialogue)
	_bind_dialogue_input(points.get_dialogue())
	map._interactions.investigated.connect(_on_investigated)
	GameState.state_changed.connect(_on_state_changed)
	GameState.progress_changed.connect(_on_progress)
	GameState.exit_confirmed.connect(_on_exit)
	main.get_node("Pages/BattlePage").configure(main)
	_bind_battle()
	recovery = preload("res://scripts/failure_recovery.gd").new()
	add_child(recovery)
	recovery.configure(self)
	_setup_safehouse()
	dialogue.bind_s0(safe_room, finish_s0)
	assembly_ready = true
	_present(GameState.state)
	# 仅新流程成功提交后恢复；正常启动已开启处理，不重复切换。
	if not GameState.is_processing():
		GameState.set_process(true)
	_start_requested_test.call_deferred()
	return true

func _abort_configuration(saved: Dictionary, points: Node = null) -> bool:
	if is_instance_valid(points):
		points.free()
	if is_instance_valid(dialogue):
		dialogue.free()
	main._dialogue = null
	dialogue = null
	main = null
	GameState.begin_session(GameState.State.S0, saved)
	assembly_ready = false
	return false

func _setup_safehouse() -> void:
	safe_room = content.get_node("Safehouse")
	room_exit = preload("res://scripts/safe_room_exit.gd").new()
	add_child(room_exit)
	room_exit.configure(self, safe_room)
	safe_room.configure(self, room_exit)
	content.sofa_requested.connect(func(): safe_room.request_object("Sofa"))
	content.door_requested.connect(func(): safe_room.request_object("Door"))
	epilogue = preload("res://scripts/safe_room_epilogue.gd").new()
	add_child(epilogue)
	epilogue.configure(self)

func _bind_battle() -> void:
	var actor: Control = main.get_node("Pages/BattlePage")
	_battle_id = actor.get_instance_id()
	GameState.battle_actor = weakref(actor)
	if not actor.battle_lost.is_connected(_on_battle_lost):
		actor.battle_lost.connect(_on_battle_lost)

func _start_requested_test() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and args.has("--sp19-self-test") and not get_tree().has_meta("sp19_runner"):
		get_tree().set_meta("sp19_runner", true)
		await load("res://scripts/sp19_selftest.gd").new().run(main)
	elif DisplayServer.get_name() == "headless" and args.has("--sp17-self-test") and not get_tree().has_meta("sp17_runner"):
		get_tree().set_meta("sp17_runner", true)
		await load("res://scripts/sp17_selftest.gd").new().run(main)
	elif DisplayServer.get_name() == "headless" and args.has("--sp15-self-test") and not get_tree().has_meta("sp15_runner"):
		get_tree().set_meta("sp15_runner", true)
		await load("res://scripts/sp15_selftest.gd").new().run(main)
	elif args.has("--sp14-self-test") and not get_tree().has_meta("sp14_runner"):
		get_tree().set_meta("sp14_runner", true)
		await load("res://scripts/sp14_selftest.gd").new().run(main)
	elif args.has("--sp11-self-test") and not get_tree().has_meta("sp11_runner"):
		get_tree().set_meta("sp11_runner", true)
		main._run_sp11_self_test()

func _present(target: int) -> bool:
	var page: StringName = &"ScenePage"
	if target in [GameState.State.S2, GameState.State.S3]:
		page = &"MapPage"
	elif target == GameState.State.S2B:
		page = &"BattlePage"
	elif target == GameState.State.S5:
		var battle: Control = main.get_node("Pages/BattlePage")
		page = &"BattlePage" if battle.turn_phase == battle.State.DEFEATED else main._current_page
	presenting = true
	var shown: bool = main.show_page(page)
	presenting = false
	if not shown:
		return false
	content.present(target)
	map._refresh_progress_ui()
	return true

func request_page(page: StringName) -> bool:
	return assembly_ready and GameState.configuration_valid and main.show_page(page)

func _play_event(id: StringName, numbers: Array) -> bool:
	var keys: Array = []
	for number: int in numbers:
		keys.append("T%d" % number)
	var reason: String = dialogue.validate_sequence(keys)
	if not reason.is_empty():
		dialogue.last_error = reason
		return false
	var previous_event: StringName = _sequence_event
	var previous_run: int = _sequence_run
	var previous_skip: bool = dialogue.skip_allowed
	if not GameState.record_event(id):
		return false
	_event_seen.clear()
	_sequence_event = id
	_sequence_run = GameState.run_id
	if id == &"E1":
		dialogue.skip_allowed = false
	if not dialogue.play_seq(keys):
		GameState.cancel_started_event(id, _sequence_run)
		_sequence_event = previous_event
		_sequence_run = previous_run
		dialogue.skip_allowed = previous_skip
		return false
	return true

func _on_story_line(id: String) -> void:
	if is_instance_valid(safe_room):
		safe_room._reading_focus = true
		safe_room.grid.release_focus()
	if _sequence_event != &"":
		_event_seen.append(id)
	if _departure_phase in [&"INTRO", &"ENTRY_TEXT"]:
		_departure_seen.append(id)

func _on_sequence_finished(skipped: bool) -> void:
	var id: StringName = _sequence_event
	_sequence_event = &""
	if id == &"":
		_finish_departure_intro(skipped)
		return
	if skipped or dialogue.is_playing() or _event_seen != dialogue._keys or not GameState.record_event(id, true, _sequence_run):
		return
	match id:
		&"E1":
			# 本轮分发只登记；旧结束通知不能结算尚未启动的READING。
			if _opening_run == _sequence_run and _opening_token >= 0:
				_opening_pending = true
				_queue_reading_bridge()
		&"E5":
			s1_finished.emit()
			if _departure_run == GameState.run_id and _departure_phase == &"E5":
				_departure_phase = &"ENTRY_TEXT"
				_departure_keys = ["T130", "T131"]
				_departure_seen.clear()
				request_page(&"MapPage")
				dialogue.skip_allowed = false
				if not dialogue.play_seq(_departure_keys):
					last_error = dialogue.last_error
		&"E9":
			_pending_checkpoint_run = _sequence_run
			_retry_checkpoint()

func request_opening(session: int) -> bool:
	if session != GameState.run_id or GameState.presenter != _present or GameState.state != GameState.State.S0 or GameState.event_done(&"E4") or not safe_room._owns_session() or not safe_room.is_visible_in_tree() or safe_room.busy or room_exit.pending or dialogue.is_playing():
		return false
	if _opening_run != session:
		_opening_token = -1
		_opening_run = session
		_opening_pending = false
		_opening_queued = false
		_opening_handed = false
	if _opening_handed:
		return false
	if GameState.event_done(&"E1"):
		if not _opening_pending:
			return false
		_queue_reading_bridge()
		return true
	if _opening_token >= 0 or GameState.event_started(&"E1"):
		return false
	var ids: Array = ["T101", "T102", "T103", "T104", "T105", "T106", "T112", "T113", "T114", "T116", "T117", "T118", "T121"]
	var reason: String = dialogue.validate_sequence(ids)
	if not reason.is_empty():
		dialogue.last_error = reason
		return false
	_opening_serial += 1
	_opening_token = _opening_serial
	if not _play_event(&"E1", range(101, 107)):
		_opening_token = -1
		return false
	return true

func _queue_reading_bridge() -> void:
	if _opening_queued or not _opening_pending:
		return
	_opening_queued = true
	_start_reading_after_e1.call_deferred(_opening_run, _opening_token)

func _start_reading_after_e1(session: int, token: int) -> void:
	# 旧回调必须在写任何请求标志之前返回，不能清掉新会话的token。
	if session != GameState.run_id or session != _opening_run or token != _opening_token or not _opening_pending or _opening_handed or GameState.presenter != _present:
		return
	_opening_queued = false
	if GameState.state != GameState.State.S0 or not GameState.event_done(&"E1") or GameState.event_done(&"E4") or not is_instance_valid(dialogue) or dialogue.is_playing() or not is_instance_valid(safe_room):
		return
	if safe_room.flow != self or safe_room.player != dialogue or safe_room.captured_run != session or dialogue._s0 == null or not dialogue._s0.binding_valid(session):
		return
	_opening_pending = false
	_opening_handed = true
	dialogue.start_s0_from_speaker(session)

func _departure_target() -> StringName:
	if not map._playable or map.get_current_node_id() != map._start_id or map.get_step_count() != 0 or GameState.vital_now < GameState.get_knob("step_cost") or GameState.vital_now <= 0:
		return &""
	var target: StringName = map._find_direction_target(Vector2.DOWN)
	if target == &"" or not map._points.has(target) or not map._revealed.has(target) or map._visited.has(target) or not map._is_adjacent(map._start_id, target):
		return &""
	return target

func request_departure(session: int) -> bool:
	if session != GameState.run_id or GameState.presenter != _present or GameState.state != GameState.State.S1 or not GameState.event_done(&"E4") or not safe_room.is_visible_in_tree() or not safe_room._owns_session() or dialogue.is_playing():
		return false
	if _departure_run != session:
		_departure_run = session
		_departure_phase = &"NONE"
	if _departure_phase == &"READY":
		return _commit_departure_step(session)
	if _departure_phase != &"NONE":
		return false
	var keys: Array = ["T195", "T122", "T123", "T124", "T125", "T126", "T127", "T128", "T129", "T130", "T131"]
	var reason: String = dialogue.validate_sequence(keys)
	if not reason.is_empty() or _departure_target() == &"":
		last_error = reason if not reason.is_empty() else "出发目标不可用"
		return false
	if not request_page(&"MapPage"):
		return false
	_departure_phase = &"INTRO"
	_departure_keys = ["T195"]
	_departure_seen.clear()
	dialogue.skip_allowed = false
	if not dialogue.play_seq(_departure_keys):
		_departure_phase = &"NONE"
		request_page(&"ScenePage")
		return false
	return true

func _finish_departure_intro(skipped: bool) -> void:
	if _departure_run != GameState.run_id or GameState.presenter != _present or GameState.state != GameState.State.S1 or _departure_phase not in [&"INTRO", &"ENTRY_TEXT"]:
		return
	if skipped or dialogue.is_playing() or _departure_seen != _departure_keys or dialogue._keys != _departure_keys:
		return
	if _departure_phase == &"INTRO":
		_departure_phase = &"E5"
		_play_event(&"E5", range(122, 130))
	else:
		_departure_phase = &"READY"
		_commit_departure_step(_departure_run)

func _commit_departure_step(session: int) -> bool:
	if session != GameState.run_id or GameState.presenter != _present or _departure_phase != &"READY" or GameState.state != GameState.State.S1 or not GameState.event_done(&"E5"):
		return false
	var target: StringName = _departure_target()
	if target == &"" or not request_page(&"MapPage") or not GameState.request_transition(&"first_step", session):
		return false
	if not map.try_move_to(target):
		last_error = "首步提交失败"
		return false
	_departure_phase = &"COMMITTED"
	first_map_move.emit()
	return true

## 保存失败留在 S4；每秒重试同一任务，成功后才进入 S6。
func _process(delta: float) -> void:
	if _pending_checkpoint_run < 0 or GameState.presenter != _present:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_checkpoint_retry_elapsed += delta
	if _checkpoint_retry_elapsed >= CHECKPOINT_RETRY_SECONDS:
		_retry_checkpoint()

func _retry_checkpoint() -> void:
	var session: int = _pending_checkpoint_run
	_checkpoint_retry_elapsed = 0.0
	if session != GameState.run_id or GameState.state != GameState.State.S4:
		_pending_checkpoint_run = -1
		return
	content.set_checkpoint_status()
	if not checkpoint.write_once(session, &"task_complete", {"safehouse_reached": true}):
		content.set_checkpoint_status(checkpoint.last_error)
		return
	_pending_checkpoint_run = -1
	GameState.request_transition(&"r10_finished", session)

func _on_stage_started(stage: StringName, session: int) -> void:
	var id: StringName = {&"R2": &"E2", &"R3": &"E3", &"R4": &"E4"}.get(stage, &"")
	if id != &"":
		GameState.record_event(id, false, session)

func _on_stage_finished(stage: StringName, session: int) -> void:
	var id: StringName = {&"R2": &"E2", &"R3": &"E3", &"R4": &"E4"}.get(stage, &"")
	if id != &"":
		GameState.record_event(id, true, session)

func finish_s0(reason: StringName, session: int) -> bool:
	return GameState.request_transition(reason, session)

func _on_state_changed(_from: int, target: int, reason: StringName, session: int) -> void:
	if GameState.presenter != _present:
		return
	match target:
		GameState.State.S2B:
			GameState.record_event(&"E15", true, session)
			battle_entered.emit()
		GameState.State.S3: GameState.record_event(&"E7", true, session)
		GameState.State.S4: _play_event(&"E9", range(161, 171))
		GameState.State.S5:
			_sequence_event = &""
			dialogue._finish(true)
			main.get_node("Overlay/Points").cancel_pending_for_failure()
			if GameState.record_event(&"E10", true, session):
				failure_entered.emit(reason, session)
		GameState.State.S6:
			GameState.record_event(&"E12", false, session)
			safehouse_entered.emit()

func _input(event: InputEvent) -> void:
	if recovery != null and recovery.route_input(event):
		return
	if GameState.presenter != _present or _route_dialogue_input(event):
		return
## 文字仍走既有播放器；翻页事件留给按钮 GUI 与 Main 的同一入口。
func _bind_dialogue_input(player: Control) -> void:
	_dialogue_inputs.push_front(player)
	player.line_started.connect(func(_key: String): player.set_process_input(false))
	player.set_process_input(false)

func _route_dialogue_input(event: InputEvent) -> bool:
	if safe_room != null and safe_room.blocks_object_input(event):
		return true
	if event is InputEventKey and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		return false
	if event is InputEventMouse and main._page_switch_bar.get_global_rect().has_point(event.position):
		return false
	for player: Control in _dialogue_inputs:
		if player.is_playing() and player.get_current_mode() != "caption":
			player._input(event)
			return true
	return false

func _on_investigated(point: StringName) -> void:
	if GameState.record_investigation(point, GameState.run_id):
		investigation_completed.emit(point)

func _on_progress(_done: int, open: bool) -> void:
	if GameState.presenter != _present:
		return
	if open:
		GameState.request_transition(&"investigation_complete")

func _on_exit() -> void:
	if GameState.presenter != _present:
		return
	if GameState.record_event(&"E8", true):
		GameState.request_transition(&"exit")

func _on_battle_lost() -> void:
	GameState.request_transition(&"failure")

func return_from_battle() -> bool:
	if not GameState.record_event(&"E17", true):
		return false
	if not GameState.request_transition(&"battle_return"):
		return false
	return true

func request_retry() -> bool:
	if GameState.state != GameState.State.S5:
		return false
	retry_requested.emit(GameState.run_id)
	return bool(retry_service.call(GameState.run_id)) if retry_service.is_valid() else false

func retry_ready(receipt: Dictionary, session: int) -> bool:
	if GameState.state != GameState.State.S5 or session != GameState.run_id:
		return false
	var actor: Control = receipt.get("battle")
	var grid: Control = receipt.get("map")
	if not _fresh_session(actor, grid):
		return false
	var saved: Dictionary = GameState.capture_session()
	var previous_id: int = _battle_id
	GameState.begin_session(GameState.State.S2)
	actor.configure(main)
	map = grid
	_bind_battle()
	if not _present(GameState.state):
		GameState.begin_session(GameState.State.S0, saved)
		_battle_id = previous_id
		return false
	GameState.record_event(&"E11", true)
	recovery.complete_retry(session, actor)
	return true

func _fresh_session(actor: Control, grid: Control) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(grid):
		return false
	if actor.get_instance_id() == _battle_id or actor != main.get_node("Pages/BattlePage"):
		return false
	if grid != main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid"):
		return false
	if not actor.is_fresh_for_retry() or grid.get_step_count() != 0:
		return false
	for id: StringName in grid._points:
		var item: Control = grid.get_interactable(id)
		if item != null and item.read:
			return false
	return grid.get_current_node_id() == grid._start_id and GameState.configuration_valid and GameState.vital_max > 0.0 and is_equal_approx(GameState.vital_now, GameState.vital_max)

func request_title() -> bool:
	if GameState.state != GameState.State.S5:
		return false
	title_requested.emit(GameState.run_id)
	return bool(title_service.call()) if title_service.is_valid() else false

func finish_safehouse(id: StringName, session: int) -> bool:
	if id == &"E14" and (epilogue == null or not epilogue.can_finish(session)):
		return false
	if id not in [&"E12", &"E13", &"E14"] or not GameState.record_event(id, true, session):
		return false
	if id == &"E14":
		prologue_finished.emit()
	return true


func can_finish_safehouse(session: int) -> bool:
	return epilogue != null and epilogue.can_finish(session)


## 只导入已经装配的干净 S6 的两项旧档事实；不是整章继续游戏入口。
func restore_safehouse_branch(session: int) -> bool:
	if not _can_restore_safehouse_branch(session):
		return false
	var branch: Dictionary = checkpoint.read_safehouse_branch()
	if branch.is_empty() or not _can_restore_safehouse_branch(session):
		return false
	if branch.trust_read and not GameState.record_event(&"E13", true, session):
		return false
	if session != GameState.run_id or GameState.presenter != _present:
		return false
	if branch.r13_done and not GameState.record_event(&"E12", true, session):
		return false
	if not safe_room.sync_restored_sofa_progress(session):
		return false
	_restored_branch_run = session
	return true

func _can_restore_safehouse_branch(session: int) -> bool:
	if not assembly_ready or session != GameState.run_id or session == _restored_branch_run or GameState.presenter != _present:
		return false
	if GameState.state != GameState.State.S6 or not is_instance_valid(safe_room) or safe_room.flow != self or safe_room.captured_run != session:
		return false
	if not safe_room.is_visible_in_tree() or not safe_room._can_request() or safe_room.options_open or safe_room.medical.is_visible_in_tree():
		return false
	return not GameState.event_started(&"E13") and not GameState.event_done(&"E12") and not GameState.event_done(&"E14") and not safe_room.interaction("Sofa").read

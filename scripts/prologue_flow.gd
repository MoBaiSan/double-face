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
var main: Control
var dialogue: Control
var map: Control
var content: Control
var checkpoint = preload("res://scripts/prologue_checkpoint.gd").new()
var retry_service: Callable
var title_service: Callable
var presenting: bool = false
var _sequence_event: StringName = &""
var _sequence_run: int = -1
var _battle_id: int = 0
var _dialogue_inputs: Array[Control] = []

func configure(host: Control) -> void:
	if main != null:
		return
	main = host
	map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	content = main.get_node("Pages/ScenePage/FlowContent")
	content.configure()
	GameState.begin_session()
	GameState.presenter = _present
	dialogue = preload("res://scenes/ui/DialogueBox.tscn").instantiate()
	main.get_node("Overlay").add_child(dialogue)
	main._dialogue = dialogue
	dialogue.sequence_finished.connect(_on_sequence_finished)
	dialogue.stage_started.connect(_on_stage_started)
	dialogue.stage_finished.connect(_on_stage_finished)
	dialogue.bind_s0(main.get_node("Pages/ScenePage"), finish_s0)
	var points := preload("res://scripts/points.gd").new()
	main.get_node("Overlay").add_child(points)
	points.configure(main, dialogue)
	_bind_dialogue_input(dialogue)
	_bind_dialogue_input(points.get_dialogue())
	map.bind_progress(points)
	map._interactions.investigated.connect(_on_investigated)
	GameState.state_changed.connect(_on_state_changed)
	GameState.progress_changed.connect(_on_progress)
	GameState.exit_confirmed.connect(_on_exit)
	main.get_node("Pages/BattlePage").configure(main)
	_bind_battle()
	_present(GameState.state)
	_play_event(&"E1", range(101, 107))
	_start_requested_test.call_deferred()

func _bind_battle() -> void:
	var actor: Control = main.get_node("Pages/BattlePage")
	_battle_id = actor.get_instance_id()
	GameState.battle_actor = weakref(actor)
	if not actor.battle_lost.is_connected(_on_battle_lost):
		actor.battle_lost.connect(_on_battle_lost)
		actor.incoming_damage.connect(_on_incoming_damage)

func _start_requested_test() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--sp14-self-test") and not get_tree().has_meta("sp14_runner"):
		get_tree().set_meta("sp14_runner", true)
		await load("res://scripts/sp14_selftest.gd").new().run(main)
	elif args.has("--sp11-self-test"):
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
	return main.show_page(page)

func _play_event(id: StringName, numbers: Array) -> void:
	if not GameState.record_event(id):
		return
	_sequence_event = id
	_sequence_run = GameState.run_id
	var keys: Array = []
	for number: int in numbers:
		keys.append("T%d" % number)
	dialogue.play_seq(keys)

func _on_sequence_finished(skipped: bool) -> void:
	var id: StringName = _sequence_event
	_sequence_event = &""
	if id == &"" or skipped or not GameState.record_event(id, true, _sequence_run):
		return
	match id:
		&"E1": content.present(GameState.state)
		&"E5":
			s1_finished.emit()
			request_page(&"MapPage")
		&"E9":
			checkpoint.write_once(GameState.run_id, &"task_complete", {"safehouse_reached": true})
			GameState.request_transition(&"r10_finished", _sequence_run)

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
		GameState.State.S1: _play_event(&"E5", range(122, 130))
		GameState.State.S2B:
			GameState.record_event(&"E15", true, session)
			battle_entered.emit()
		GameState.State.S3: GameState.record_event(&"E7", true, session)
		GameState.State.S4: _play_event(&"E9", range(161, 171))
		GameState.State.S5:
			_sequence_event = &""
			dialogue._finish(true)
			if GameState.record_event(&"E10", true, session):
				failure_entered.emit(reason, session)
		GameState.State.S6:
			GameState.record_event(&"E12", false, session)
			safehouse_entered.emit()

func _input(event: InputEvent) -> void:
	if GameState.presenter != _present or _route_dialogue_input(event):
		return
	if GameState.state != GameState.State.S1 or not GameState.event_done(&"E5"):
		return
	var target: StringName = &""
	if event is InputEventKey and event.pressed and not event.echo:
		var direction: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT,
			KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}.get(event.keycode, Vector2.ZERO)
		if direction == Vector2.ZERO or not map.select_direction(direction):
			return
		target = map._pending_id
		map._pending_id = &""
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and map.is_visible_in_tree():
		target = map._hover_candidate_at(map.get_global_transform_with_canvas().affine_inverse() * event.position)
	if target == &"":
		return
	get_viewport().set_input_as_handled()
	if GameState.request_transition(&"first_step") and map.try_move_to(target):
		first_map_move.emit()

## 文字仍走既有播放器；翻页事件留给按钮 GUI 与 Main 的同一入口。
func _bind_dialogue_input(player: Control) -> void:
	_dialogue_inputs.push_front(player)
	player.line_started.connect(func(_key: String): player.set_process_input(false))
	player.set_process_input(false)

func _route_dialogue_input(event: InputEvent) -> bool:
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

func _on_incoming_damage(product: float, hp: int, maximum: int) -> void:
	if hp - roundi(product) <= maximum / 2.0:
		GameState.record_event(&"E16", true)

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
	if retry_service.is_valid():
		retry_service.call(GameState.run_id)
	return false

func retry_ready(receipt: Dictionary, session: int) -> bool:
	if GameState.state != GameState.State.S5 or session != GameState.run_id:
		return false
	var actor: Control = receipt.get("battle")
	var grid: Control = receipt.get("map")
	if not _fresh_session(actor, grid):
		return false
	GameState.begin_session(GameState.State.S2)
	actor.configure(main)
	map = grid
	_bind_battle()
	if not _present(GameState.state):
		return false
	GameState.record_event(&"E11", true)
	return true

func _fresh_session(actor: Control, grid: Control) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(grid):
		return false
	if actor.get_instance_id() == _battle_id or actor != main.get_node("Pages/BattlePage"):
		return false
	if grid != main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid"):
		return false
	if actor._started or actor.item_uses != 1 or actor.enemy_hp != int(actor._k("enemy_hp_max")):
		return false
	if actor.player_hp != int(actor._k("player_hp_max")) or grid.get_step_count() != 0:
		return false
	for id: StringName in grid._points:
		var item: Control = grid.get_interactable(id)
		if item != null and item.read:
			return false
	return grid.get_current_node_id() == grid._start_id and GameState.vital_now == 100.0

func request_title() -> bool:
	if GameState.state != GameState.State.S5:
		return false
	title_requested.emit(GameState.run_id)
	return bool(title_service.call()) if title_service.is_valid() else false

func finish_safehouse(id: StringName, session: int) -> bool:
	if id not in [&"E12", &"E13", &"E14"] or not GameState.record_event(id, true, session):
		return false
	if id == &"E14":
		prologue_finished.emit()
	return true


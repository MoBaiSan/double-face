## 门口收尾仅管理呈现事务；写入仍由原离开服务完成。
extends Node
enum Phase { IDLE, READING, LEFT, WAIT_SAVE, FINISHED }
var phase: Phase = Phase.IDLE
var flow: Node
var room: Control
var service: Node
var doorway: Control
var run: int = -1
var line_completed: bool = false
var last_error: Error = OK
var _done: Callable

func configure(director: Node) -> void:
	if flow != null:
		return
	flow = director
	room = flow.safe_room
	service = flow.room_exit
	doorway = room.get_node("Illustration/DoorwayVisual")
	service.before_save = begin_exit
	room.session_entered.connect(reset_session)
	room.exit_line_finished.connect(_line_finished)
	service.exit_saved.connect(_saved)
	service.status_changed.connect(_status_changed)
	reset_session(GameState.run_id)

func _valid(session: int) -> bool:
	return session == run and session == GameState.run_id and GameState.presenter == flow._present and GameState.state == GameState.State.S6

func reset_session(session: int) -> void:
	if session == run:
		return
	run = session
	phase = Phase.IDLE
	line_completed = false
	last_error = OK
	_done = Callable()
	doorway.reset_visual()
	room.visual.show()
	room.get_node("Objects").show()

func begin_exit(session: int, done: Callable) -> void:
	if not _valid(session) or phase != Phase.IDLE or not service.is_waiting_before_save(session):
		done.call(session, false)
		return
	_done = done
	phase = Phase.READING
	last_error = OK
	room.visual.hide()
	doorway.show_entry()
	flow.request_page(&"ScenePage")
	if not room.request_room_sequence(&"exit", ["T193"]):
		_cancel(session)

func can_read(session: int) -> bool:
	return _valid(session) and phase == Phase.READING and doorway.is_visible_in_tree() and doorway.figure.visible and not room.visual.visible and GameState.event_done(&"E12")

func _line_finished(session: int, completed: bool) -> void:
	if not _valid(session) or phase != Phase.READING:
		return
	if not completed:
		_cancel(session)
		return
	line_completed = true
	phase = Phase.LEFT
	doorway.leave()
	var done: Callable = _done
	_done = Callable()
	done.call(session, true)
	if phase == Phase.LEFT and service.pending:
		phase = Phase.WAIT_SAVE

func _cancel(session: int) -> void:
	last_error = ERR_CANT_OPEN
	phase = Phase.IDLE
	line_completed = false
	doorway.reset_visual()
	room.visual.show()
	var done: Callable = _done
	_done = Callable()
	if done.is_valid():
		done.call(session, false)
	room.get_node("Status/ProgressNotice").text = "内容加载失败，请重试。"
	room._restore_focus.call_deferred()

func _status_changed() -> void:
	if _valid(run) and line_completed and service.pending and service.last_error != OK:
		phase = Phase.WAIT_SAVE

func _receipt_matches(session: int, receipt: Dictionary) -> bool:
	return _valid(session) and line_completed and not doorway.figure.visible and service.committed and receipt == service.receipt and receipt.get("run_id") == run and receipt.get("checkpoint") == &"safehouse_exit"

func _saved(session: int, receipt: Dictionary) -> void:
	if phase not in [Phase.LEFT, Phase.WAIT_SAVE] or not _receipt_matches(session, receipt):
		return
	phase = Phase.FINISHED
	room.get_node("Objects").hide()
	flow.finish_safehouse(&"E14", session)

func can_finish(session: int) -> bool:
	return phase == Phase.FINISHED and _receipt_matches(session, service.receipt)

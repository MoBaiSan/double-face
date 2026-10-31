## 安全屋离开事务；写入失败保留请求，隐藏页面不停止重试。
extends Node
signal status_changed
signal exit_saved(session: int, receipt: Dictionary)
var flow: Node
var room: Control
var pending: bool = false
var committed: bool = false
var last_error: Error = OK
var before_save: Callable
var accepted: int = 0
var receipt: Dictionary = {}
var _run: int = -1
var _elapsed: float = 0.0
var _waiting: bool = false
var _payload: Dictionary = {}

func configure(director: Node, content: Control) -> void:
	flow = director
	room = content

func reset_session(session: int) -> void:
	if not _valid_session(session) or session == _run:
		return
	_run = session
	pending = false
	committed = false
	_waiting = false
	_elapsed = 0.0
	last_error = OK
	accepted = 0
	receipt.clear()
	_payload.clear()
	status_changed.emit()

func _valid_session(session: int) -> bool:
	return is_instance_valid(flow) and GameState.presenter == flow._present and session == GameState.run_id and GameState.state == GameState.State.S6

func request_exit(session: int) -> bool:
	if pending or committed or not _valid_session(session) or not GameState.event_done(&"E12"):
		return false
	if not room.is_visible_in_tree() or room.busy or flow.dialogue.is_playing():
		return false
	_run = session
	_payload = {"safehouse_reached": true, "safehouse_exit": true,
		"r13_done": true, "trust_read": GameState.event_done(&"E13")}
	pending = true
	accepted += 1
	_elapsed = 0.0
	status_changed.emit()
	if before_save.is_valid():
		_waiting = true
		before_save.call(session, complete_before_save)
	else:
		_attempt()
	return true

## 后续服务显式交还相同局号；取消不落盘，重复通知不会重新提交。
func complete_before_save(session: int, completed: bool) -> void:
	if not pending or not _waiting or session != _run:
		return
	if not _valid_session(session):
		_cancel_pending()
		return
	_waiting = false
	if not completed:
		_cancel_pending()
		return
	_attempt()

func _attempt() -> void:
	if not pending or not _valid_session(_run):
		_cancel_pending()
		return
	_elapsed = 0.0
	if not flow.checkpoint.write_once(_run, &"safehouse_exit", _payload):
		last_error = flow.checkpoint.last_error
		status_changed.emit()
		return
	last_error = OK
	pending = false
	committed = true
	receipt = {"run_id": _run, "checkpoint": &"safehouse_exit", "progress": _payload.duplicate(true)}
	status_changed.emit()
	exit_saved.emit(_run, receipt.duplicate(true))

func _cancel_pending() -> void:
	pending = false
	_waiting = false
	_elapsed = 0.0
	last_error = OK
	status_changed.emit()

func _process(delta: float) -> void:
	advance_time(delta)

func advance_time(delta: float) -> void:
	if not pending:
		return
	if not _valid_session(_run):
		_cancel_pending()
		return
	if _waiting or not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= flow.CHECKPOINT_RETRY_SECONDS:
		_attempt()

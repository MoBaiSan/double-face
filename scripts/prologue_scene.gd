## 书页内容实例；剧情主状态始终从 GameState 读取。
extends Control
signal sofa_requested
signal trust_requested
signal door_requested
var _checkpoint_status: Label
var _checkpoint_run: int = -1

func configure() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: String in ["TaskComplete"]:
		var slot := Control.new()
		slot.name = id
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(slot)
	var room: Control = preload("res://scenes/ui/SafeRoomPage.tscn").instantiate()
	add_child(room)
	_create_checkpoint_status()

func present(target: int) -> void:
	var page: Control = get_parent()
	page.get_node("Illustration").visible = target == GameState.State.S0
	page.get_node("TestOptions").visible = target == GameState.State.S0
	$Departure.visible = target == GameState.State.S1
	$TaskComplete.visible = target == GameState.State.S4
	_sync_checkpoint_status(target)
	$Safehouse.visible = target == GameState.State.S6
	if target == GameState.State.S6:
		$Safehouse.enter_session()
	var enabled: bool = target == GameState.State.S0 and GameState.event_done(&"E1")
	page.get_node("PageNav").set_process(enabled)
	page.get_node("PageNav").set_process_input(enabled)

func request_sofa() -> bool:
	if GameState.state != GameState.State.S6:
		return false
	sofa_requested.emit()
	return true

func request_trust() -> bool:
	if GameState.state != GameState.State.S6 or GameState.event_done(&"E13"):
		return false
	trust_requested.emit()
	return true

func request_door() -> bool:
	if GameState.state != GameState.State.S6 or not GameState.event_done(&"E12"):
		return false
	door_requested.emit()
	return true


func _create_checkpoint_status() -> void:
	_checkpoint_status = Label.new()
	_checkpoint_status.name = "CheckpointStatus"
	$TaskComplete.add_child(_checkpoint_status)
	_checkpoint_status.anchor_left = 0.05
	_checkpoint_status.anchor_top = 0.56
	_checkpoint_status.anchor_right = 0.89
	_checkpoint_status.anchor_bottom = 0.76
	_checkpoint_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checkpoint_status.focus_mode = Control.FOCUS_NONE
	_checkpoint_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkpoint_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_checkpoint_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checkpoint_status.add_theme_font_override("font", preload("res://assets/fonts/simkai.ttf"))
	_checkpoint_status.add_theme_font_size_override("font_size", 24)
	_checkpoint_status.add_theme_color_override("font_color", Color(0.266667, 0.231373, 0.172549, 1.0))
	_checkpoint_status.hide()

func set_checkpoint_status(error: Error = OK) -> void:
	if GameState.state != GameState.State.S4:
		return
	_checkpoint_run = GameState.run_id
	_checkpoint_status.text = "正在保存……" if error == OK else "自动保存失败，正在重试（错误码 %d）" % int(error)
	_checkpoint_status.show()

func _sync_checkpoint_status(target: int) -> void:
	if target == GameState.State.S4:
		if _checkpoint_run != GameState.run_id:
			set_checkpoint_status()
		return
	_checkpoint_run = -1
	_checkpoint_status.text = ""
	_checkpoint_status.hide()

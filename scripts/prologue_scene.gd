## 书页内容实例；剧情主状态始终从 GameState 读取。
extends Control
signal sofa_requested
signal trust_requested
signal door_requested

func configure() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: String in ["TaskComplete", "Safehouse"]:
		var slot := Control.new()
		slot.name = id
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(slot)

func present(target: int) -> void:
	var page: Control = get_parent()
	page.get_node("Illustration").visible = target == GameState.State.S0
	page.get_node("TestOptions").visible = target == GameState.State.S0
	$Departure.visible = target == GameState.State.S1
	$TaskComplete.visible = target == GameState.State.S4
	$Safehouse.visible = target == GameState.State.S6
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


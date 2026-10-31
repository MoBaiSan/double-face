## 唯一失败屏：两秒无字演出，完成后只允许立刻重来。
extends CanvasLayer
signal retry_pressed
const CUT_SECONDS: float = 0.20
const CLOSE_SECONDS: float = 1.80
const FAIL_SECONDS: float = CUT_SECONDS + CLOSE_SECONDS
@onready var screen: Control = $Screen
@onready var actions: Control = $Screen/Actions
@onready var retry: Button = $Screen/Actions/Buttons/RetryButton
var elapsed: float = 0.0
var active: bool = false
var ready_for_retry: bool = false
var busy: bool = false
var start_count: int = 0
var accept_down: bool = false
var _accept_press: bool = false

func _ready() -> void:
	retry.pressed.connect(_on_retry)
	screen.resized.connect(_draw_frame)
	dismiss()

func start() -> void:
	active = true
	busy = false
	ready_for_retry = false
	elapsed = 0.0
	_accept_press = false
	start_count += 1
	actions.hide()
	retry.disabled = true
	show()
	get_viewport().gui_release_focus()
	set_process(true)
	_draw_frame()

func _process(delta: float) -> void:
	advance_time(delta)

func advance_time(delta: float) -> void:
	if not active or not visible or busy or not is_finite(delta) or delta <= 0.0:
		return
	elapsed = minf(FAIL_SECONDS, elapsed + delta)
	_draw_frame()
	if elapsed + 0.000001 >= FAIL_SECONDS and not ready_for_retry:
		ready_for_retry = true
		actions.show()
		retry.disabled = false
		retry.grab_focus()

func _draw_frame() -> void:
	if not is_node_ready():
		return
	var cut: float = clampf(elapsed / CUT_SECONDS, 0.0, 1.0)
	var center: Vector2 = screen.size * Vector2(0.5, 0.28)
	var wave: PackedVector2Array = []
	for i: int in range(9):
		wave.append(center + Vector2((i - 4) * 14.0, sin(i * PI / 2.0) * 10.0 * (1.0 - cut)))
	$Screen/CutMarker.points = wave
	var progress: float = clampf((elapsed - CUT_SECONDS) / CLOSE_SECONDS, 0.0, 1.0)
	var width: float = $Screen/ChannelMask.size.x
	$Screen/ChannelMask/LeftEdge.offset_right = width * 0.5 * progress
	$Screen/ChannelMask/RightEdge.offset_left = -width * 0.5 * progress

func route_input(event: InputEvent) -> bool:
	var accept: bool = event.is_action("ui_accept") and event is InputEventKey
	var was_down: bool = accept_down
	if accept:
		accept_down = event.pressed
	if not active or not visible:
		return false
	var allow: bool = false
	if accept and ready_for_retry and not busy and not event.echo:
		if event.pressed:
			_accept_press = not was_down
			allow = _accept_press
		else:
			allow = _accept_press
			_accept_press = false
	elif event is InputEventMouse and ready_for_retry and not busy:
		allow = retry.get_global_rect().has_point(event.position)
	if not allow:
		get_viewport().set_input_as_handled()
	return true

func _on_retry() -> void:
	if not active or not visible or not ready_for_retry or busy:
		return
	retry_pressed.emit()

func set_busy(value: bool) -> void:
	busy = value
	retry.disabled = value or not ready_for_retry
	if not value and active and visible and ready_for_retry:
		retry.grab_focus()

func dismiss() -> void:
	active = false
	ready_for_retry = false
	busy = false
	_accept_press = false
	hide()
	set_process(false)
	if is_node_ready():
		retry.disabled = true
		actions.hide()

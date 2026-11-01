## 三句里侧字幕的触发与FIFO；只有显示时钟暂停，不改变游戏时钟或输入。
extends Node
signal caption_started(key: String, step: int)
const IDS: Array[String] = ["T132", "T141", "T146"]
const QUEUE_LIMIT: int = 3
const CAPTION_HEIGHT: float = 40.0
var main: Control
var map: Control
var player: Control
var pending: Array[String] = []
var last_error: String = ""
var _run: int = -1
var _stopping: bool = false
var _links: Array = []
static var _test_started: bool = false
static var _sp24_started: bool = false
const EATEN_HOLD_SECONDS: float = 1.5
var eaten_view: Control
var eaten_player: Control
var eaten_actor: WeakRef
var eaten_starts: int = 0
var eaten_receipt: Dictionary = {}
var _eaten_flash: bool = false

func configure(host: Control) -> void:
	if main != null:
		return
	name = &"InsideCaptions"
	main = host
	map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	player = preload("res://scenes/ui/DialogueBox.tscn").instantiate()
	player.name = &"InsideCaption"
	add_child(player)
	player.configure_caption_view(_caption_rect())
	_link(map.moved, _moved)
	_link(map.visibility_changed, _visibility_changed)
	_link(GameState.progress_changed, _progress)
	_link(GameState.vital_changed, _vital)
	_link(GameState.state_changed, _state_changed)
	_link(player.line_started, _started)
	_link(player.sequence_finished, _finished)
	_link(RenderingServer.frame_post_draw, _eaten_draw_completed)
	_sync_run()
	if OS.get_cmdline_user_args().has("--sp24-self-test") and not _sp24_started:
		_sp24_started = true
		call_deferred("_run_sp24_test")
	if OS.get_cmdline_user_args().has("--sp12-self-test") and not _test_started:
		_test_started = true
		call_deferred("_run_test")

func _owns() -> bool:
	return is_instance_valid(main) and main.is_inside_tree() and main.can_process() \
		and is_instance_valid(main._flow) and main._flow.has_method("_present") \
		and GameState.presenter == Callable(main._flow, "_present")

func _caption_rect() -> Rect2:
	return Rect2(main.size * Vector2(0.4, 0.25), Vector2(main.size.x * 0.48, CAPTION_HEIGHT))

func _process(delta: float) -> void:
	advance_time(delta)

func advance_time(delta: float) -> void:
	if not _owns():
		player.hide()
		_clear_eaten()
		return
	_sync_run()
	_advance_eaten(delta)
	player.set_caption_rect(_caption_rect())
	if not _can_show():
		player.hide()
		return
	_pump()
	player.visible = player.is_playing()
	if player.is_playing() and delta > 0.0:
		player.advance_time(delta)

func _sync_run() -> void:
	if _run == GameState.run_id:
		return
	_stop()
	_clear_eaten(true)
	eaten_starts = 0
	eaten_receipt.clear()
	_run = GameState.run_id

func _can_show() -> bool:
	return _owns() and GameState.state in [GameState.State.S2, GameState.State.S3] \
		and not GameState.inside_caption_state.get("closed", false) \
		and map.is_visible_in_tree() and not main._dialogue.is_playing()

func request_captions(keys: Array) -> bool:
	if not _owns():
		return false
	_sync_run()
	if GameState.state not in [GameState.State.S2, GameState.State.S3] \
			or GameState.inside_caption_state.get("closed", false):
		return false
	for key: Variant in keys:
		if not key is String or key not in IDS:
			last_error = "字幕请求不在白名单"
			return false
	var additions: Array[String] = []
	var data: Dictionary = GameState.inside_caption_state
	for key: String in keys:
		if not data.requested.has(key) and key not in additions:
			additions.append(key)
	if pending.size() + additions.size() > QUEUE_LIMIT:
		last_error = "字幕队列已满"
		return false
	for key: String in additions:
		data.requested[key] = true
		pending.append(key)
	last_error = ""
	_pump()
	return true

func _pump() -> void:
	if _stopping or not _can_show() or player.is_playing() or pending.is_empty():
		return
	if not player.play(pending[0]):
		last_error = player.last_error
		return
	pending.pop_front()
	player.set_process(false)

func _started(key: String) -> void:
	if _owns() and _run == GameState.run_id:
		GameState.inside_caption_state.played[key] = true
		caption_started.emit(key, map.get_step_count())

func _finished(_skipped: bool) -> void:
	if not _stopping and _owns():
		_pump()

func _moved(_from: StringName, _to: StringName, steps: int) -> void:
	if not _owns():
		return
	_sync_run()
	var data: Dictionary = GameState.inside_caption_state
	if steps == 3:
		request_captions(["T132"])
	if int(data.t141_after_step) >= 0 and steps > int(data.t141_after_step):
		data.t141_after_step = -1
		request_captions(["T141"])

func _progress(done: int, _open: bool) -> void:
	if not _owns():
		return
	_sync_run()
	var data: Dictionary = GameState.inside_caption_state
	var before: int = int(data.previous_done)
	data.previous_done = done
	if before < 3 and done == 3 and not data.requested.has("T141") \
			and not data.closed and GameState.state in [GameState.State.S2, GameState.State.S2B, GameState.State.S3]:
		data.t141_after_step = map.get_step_count()

func _vital(value: float, _maximum: float, _reason: StringName) -> void:
	if not _owns():
		return
	_sync_run()
	var data: Dictionary = GameState.inside_caption_state
	var old_value: float = float(data.last_vital)
	var old_band: StringName = StringName(data.last_band)
	var band: StringName = GameState.get_band_for_value(value)
	data.last_vital = value
	data.last_band = band
	if value < old_value and old_band != &"critical" and band == &"critical":
		request_captions(["T146"])

func _state_changed(_from: int, target: int, _reason: StringName, session: int) -> void:
	if not _owns() or session != GameState.run_id:
		return
	_sync_run()
	if target in [GameState.State.S4, GameState.State.S5, GameState.State.S6]:
		GameState.inside_caption_state.closed = true
		_stop()
		_clear_eaten()
	else:
		advance_time(0.0)

func _visibility_changed() -> void:
	if _owns():
		advance_time(0.0)

func _stop() -> void:
	_stopping = true
	pending.clear()
	if is_instance_valid(player):
		if player.is_playing():
			player._finish(true)
		player.hide()
	_stopping = false

func _link(event: Signal, callback: Callable) -> void:
	event.connect(callback)
	_links.append([event, callback])

func _exit_tree() -> void:
	_stop()
	_clear_eaten(true)
	for pair: Array in _links:
		var event: Signal = pair[0]
		if is_instance_valid(event.get_object()) and event.is_connected(pair[1]):
			event.disconnect(pair[1])
	_links.clear()

func _run_test() -> void:
	var failures: int = await load("res://scripts/sp12_selftest.gd").new().run(main)
	get_tree().quit(0 if failures == 0 else 1)

## 独立的本击呈现；不进入三句字幕的队列，不改变游戏时钟。
func _eaten_owner(actor: Control, session: int) -> bool:
	return _owns() and session == GameState.run_id and is_instance_valid(actor) \
		and actor == main.get_node_or_null("Pages/BattlePage") \
		and GameState.state == GameState.State.S2B

func _eaten_rect() -> Rect2:
	return Rect2(main.size * Vector2(0.05, 0.07), Vector2(main.size.x * 0.64, CAPTION_HEIGHT))

func can_present_eaten(actor: Control, session: int) -> bool:
	if not _eaten_owner(actor, session):
		return false
	_sync_run()
	if not _prepare_eaten(actor):
		return false
	var entry: Dictionary = eaten_player.get_lines().get("T151", {})
	if entry.get("mode") != "caption" or entry.get("text", "").is_empty():
		last_error = "T151 caption is unavailable"
		push_error(last_error)
		return false
	return true

func _prepare_eaten(actor: Control) -> bool:
	if is_instance_valid(eaten_view) and eaten_actor != null and eaten_actor.get_ref() == actor:
		return true
	_clear_eaten(true)
	var source: Control = actor.get_node_or_null("EatenMomentTemplate")
	if source == null:
		last_error = "EatenMomentTemplate is unavailable"
		push_error(last_error)
		return false
	eaten_view = source.duplicate()
	eaten_view.name = &"EatenMoment"
	add_child(eaten_view)
	eaten_actor = weakref(actor)
	eaten_player = preload("res://scenes/ui/DialogueBox.tscn").instantiate()
	eaten_view.get_node("EatenCaption").add_child(eaten_player)
	eaten_player.configure_caption_view(_eaten_rect(), EATEN_HOLD_SECONDS)
	eaten_player.set_process(false)
	eaten_view.position = Vector2.ZERO
	eaten_view.size = main.size
	eaten_view.get_node("LeftSmear").scale = main.size / Vector2(1280.0, 720.0)
	return true

func present_eaten(actor: Control, session: int) -> bool:
	if not can_present_eaten(actor, session) or not eaten_player.play("T151"):
		return false
	eaten_player.set_process(false)
	eaten_starts += 1
	eaten_receipt = {"run": session, "actor": actor.get_instance_id(),
		"shadow_frame": -1, "dim_frame": -1, "caption_frame": Engine.get_process_frames(),
		"damage_frame": -1, "draws": 0}
	eaten_view.show()
	eaten_view.get_node("LeftSmear").show()
	eaten_receipt.shadow_frame = Engine.get_process_frames()
	eaten_view.get_node("PaperDim").show()
	eaten_receipt.dim_frame = Engine.get_process_frames()
	_eaten_flash = true
	return true

## 生产由绘制完成信号调用；无渲染自检注入同一帧边界入口。
func _eaten_draw_completed() -> void:
	if not _eaten_flash or not is_instance_valid(eaten_view):
		return
	eaten_receipt.draws += 1
	eaten_view.get_node("LeftSmear").hide()
	eaten_view.get_node("PaperDim").hide()
	_eaten_flash = false

func _advance_eaten(delta: float) -> void:
	if not is_instance_valid(eaten_view):
		return
	var actor: Control = eaten_actor.get_ref() if eaten_actor != null else null
	if not is_instance_valid(actor) or actor != main.get_node_or_null("Pages/BattlePage") \
			or GameState.state in [GameState.State.S4, GameState.State.S5, GameState.State.S6]:
		_clear_eaten()
		return
	eaten_view.size = main.size
	eaten_player.set_caption_rect(_eaten_rect())
	eaten_view.get_node("LeftSmear").scale = main.size / Vector2(1280.0, 720.0)
	if eaten_player.is_playing() and not _eaten_flash and delta > 0.0 and is_finite(delta):
		eaten_player.advance_time(delta)
	if not eaten_player.is_playing() and not _eaten_flash:
		eaten_view.hide()

func _clear_eaten(release: bool = false) -> void:
	_eaten_flash = false
	if is_instance_valid(eaten_view):
		eaten_view.get_node("LeftSmear").hide()
		eaten_view.get_node("PaperDim").hide()
		if eaten_player.is_playing():
			eaten_player._finish(true)
		eaten_view.hide()
		if release:
			eaten_view.free()
			eaten_view = null
			eaten_player = null
			eaten_actor = null

func _run_sp24_test() -> void:
	var failures: int = await load("res://scripts/sp24_selftest.gd").new().run(main)
	get_tree().quit(0 if failures == 0 else 1)

## U-05b：S4保存反馈与实际原子写入失败；沿用SP-14编号88–91。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const S = C.S
var c: RefCounted
var host: Control
var check: Callable
var clean: bool = true

func run(root: Control, assertion: Callable) -> void:
	host = root
	check = assertion
	await _progress()
	await _failure()
	await _retry()
	await _persistent_failure()

func _fresh() -> void:
	c = C.new()
	await c.create(host, S.S4)
	c.flow.set_process(false)
	c.flow.checkpoint.path = "user://u05b_%d_%d.json" % [OS.get_process_id(), c.main.get_instance_id()]
	c.flow._on_state_changed(S.S3, S.S4, &"exit", GameState.run_id)

func _notice() -> Label:
	return c.flow.content.get_node_or_null("TaskComplete/CheckpointStatus") as Label

func _noninteractive_notice() -> bool:
	var notice: Label = _notice()
	return notice != null and notice.is_visible_in_tree() and notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE

func _drop() -> void:
	var path: String = c.flow.checkpoint.path
	clean = await c.close() and clean
	for file: String in [path, path + ".tmp"]:
		var absolute: String = ProjectSettings.globalize_path(file)
		if FileAccess.file_exists(file):
			clean = DirAccess.remove_absolute(absolute) == OK and clean
	c = null

func _progress() -> void:
	await _fresh()
	await host.get_tree().process_frame
	var notice: Label = _notice()
	var ok: bool = _noninteractive_notice()
	if notice != null:
		var rect: Rect2 = notice.get_global_rect()
		ok = ok and notice.text == "正在保存……" and rect.size.x > 400.0 and rect.size.y > 24.0
		ok = ok and c.main.get_viewport_rect().encloses(rect) and not rect.intersects(c.main._dialogue._panel.get_global_rect())
	ok = ok and GameState.state == S.S4 and c.flow.checkpoint.writes == 0
	await _drop()
	check.call(88, ok and clean, "task_checkpoint_progress_is_visible")

func _failure() -> void:
	var ok: bool = true
	for sample: Array in [[ERR_BUSY, 44], [ERR_FILE_CANT_WRITE, 13]]:
		await _fresh()
		c.flow.checkpoint.replace_file = func(_a: String, _b: String): return sample[0]
		c.finish_sequence(c.main._dialogue)
		var notice: Label = _notice()
		ok = ok and _noninteractive_notice() and GameState.state == S.S4
		ok = ok and c.flow.checkpoint.last_error == sample[0] and c.flow.checkpoint.writes == 0
		ok = ok and notice != null and notice.text == "自动保存失败，正在重试（错误码 %d）" % sample[1]
		print("[U-05b] error_notice=%s" % (notice.text if notice != null else "<missing>"))
		await _drop()
	check.call(89, ok and clean, "task_checkpoint_failure_shows_error_code")

func _retry() -> void:
	await _fresh()
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	c.finish_sequence(c.main._dialogue)
	var notice: Label = _notice()
	var before: bool = _noninteractive_notice() and c.flow.checkpoint.attempts == 1
	c.flow.checkpoint.replace_file = Callable()
	c.flow._process(0.99)
	var held: bool = GameState.state == S.S4 and c.flow.checkpoint.writes == 0 and c.flow.checkpoint.attempts == 1
	c.flow._process(0.01)
	c.flow._process(3.0)
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(c.flow.checkpoint.path))
	var ok: bool = before and held and GameState.state == S.S6 and c.flow.checkpoint.writes == 1 and c.flow.checkpoint.attempts == 2
	ok = ok and notice != null and not notice.visible and notice.text.is_empty()
	ok = ok and c.flow.safe_room.is_visible_in_tree() and c.event_count(&"E9") == 1
	ok = ok and document is Dictionary and document.get("checkpoint") == "task_complete"
	await _drop()
	check.call(90, ok and clean, "task_checkpoint_retry_recovers_once")

func _persistent_failure() -> void:
	await _fresh()
	var previous = preload("res://scripts/prologue_checkpoint.gd").new()
	previous.path = c.flow.checkpoint.path
	var seeded: bool = previous.write_once(-1, &"task_complete", {"safehouse_reached": false})
	var original: PackedByteArray = FileAccess.get_file_as_bytes(previous.path)
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	c.finish_sequence(c.main._dialogue)
	for second: int in range(3):
		c.flow._process(1.0)
	var ok: bool = seeded and GameState.state == S.S4 and c.flow.checkpoint.writes == 0 and c.flow.checkpoint.attempts == 4
	ok = ok and c.flow._pending_checkpoint_run == GameState.run_id and not c.flow.safe_room.is_visible_in_tree()
	ok = ok and original == FileAccess.get_file_as_bytes(previous.path) and not FileAccess.file_exists(previous.path + ".tmp")
	await _drop()
	check.call(91, ok and clean, "task_checkpoint_no_fake_success")

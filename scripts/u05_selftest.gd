## U-05b/c：S4保存反馈与首次失败探针；沿用SP-14编号88–95。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const S = C.S
var c: RefCounted
var host: Control
var check: Callable
var clean: bool = true
var _probe_ops: Array[String] = []
var _probe_files: Dictionary = {}
var _probe_errors: Dictionary = {}

func run(root: Control, assertion: Callable) -> void:
	host = root
	check = assertion
	await _progress()
	await _failure()
	await _retry()
	await _persistent_failure()
	await _probe_once()
	await _probe_visible()
	await _probe_untouched()
	await _probe_codes()

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

func _setup_probe(errors: Dictionary = {}) -> void:
	_probe_ops.clear()
	_probe_errors = errors.duplicate()
	_probe_files = {"user://prologue_checkpoint.json": "old-checkpoint-bytes"}
	c.flow.checkpoint.write_probe.io = _probe_io

func _probe_io(kind: StringName, path: String) -> Variant:
	_probe_ops.append("%s:%s" % [kind, path])
	match kind:
		&"globalize": return ProjectSettings.globalize_path(path)
		&"exists": return true
		&"user_dir": return OS.get_user_data_dir()
		&"mkdir": return _probe_errors.get("mkdir", OK)
		&"write":
			var error: int = int(_probe_errors.get(path, OK))
			var opened: bool = error != ERR_FILE_CANT_OPEN
			if opened:
				_probe_files[path] = "probe"
			return {"opened": opened, "error": error}
		&"remove":
			var error: int = int(_probe_errors.get("remove:" + path, OK))
			if error == OK:
				_probe_files.erase(path)
			return error
	return ERR_INVALID_PARAMETER

func _probe_label() -> Label:
	return c.flow.content.get_node_or_null("TaskComplete/CheckpointProbe") as Label

func _probe_once() -> void:
	await _fresh()
	_setup_probe()
	var successful = preload("res://scripts/prologue_checkpoint.gd").new()
	successful.path = c.flow.checkpoint.path
	successful.write_probe.io = _probe_io
	var ok: bool = successful.write_once(-1, &"task_complete", {})
	ok = ok and successful.write_probe.runs == 0 and _probe_ops.is_empty()
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	c.finish_sequence(c.main._dialogue)
	var first_ops: Array[String] = _probe_ops.duplicate()
	for second: int in range(3):
		c.flow._process(1.0)
	ok = ok and not first_ops.is_empty() and _probe_ops == first_ops
	ok = ok and c.flow.checkpoint.write_probe.runs == 1 and c.flow.checkpoint.last_error == ERR_BUSY
	c.flow.checkpoint.replace_file = Callable()
	c.flow._process(1.0)
	ok = ok and GameState.state == S.S6 and c.flow.checkpoint.writes == 1
	ok = ok and _probe_ops == first_ops and not _probe_label().visible and _probe_label().text.is_empty()
	await _drop()
	check.call(92, ok and clean, "write_probe_runs_once")

func _probe_visible() -> void:
	await _fresh()
	_setup_probe({"user://prologue_checkpoint.json.tmp": ERR_FILE_CANT_OPEN})
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_FILE_CANT_OPEN
	c.finish_sequence(c.main._dialogue)
	await host.get_tree().process_frame
	var label: Label = _probe_label()
	var ok: bool = c.flow.checkpoint.last_error == ERR_FILE_CANT_OPEN
	ok = ok and _notice().text == "自动保存失败，正在重试（错误码 12）"
	ok = ok and label != null and label.is_visible_in_tree()
	if label != null:
		var lines: PackedStringArray = label.text.split("\n")
		var expected: PackedStringArray = ["a 用户目录：" + ProjectSettings.globalize_path("user://"),
			"b 目录存在：true", "c probe.txt：成功", "d prologue_checkpoint.json.tmp：错误码 12",
			"e saves/probe.txt：建目录成功；成功", "f OS用户目录：" + OS.get_user_data_dir()]
		ok = ok and lines == expected and label.get_theme_font_size("font_size") >= 24
		ok = ok and label.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.focus_mode == Control.FOCUS_NONE
		ok = ok and c.main.get_viewport_rect().encloses(label.get_global_rect())
		ok = ok and not label.get_global_rect().intersects(_notice().get_global_rect())
		ok = ok and label.get_line_count() >= 6 and label.get_visible_line_count() == label.get_line_count()
		print("[U-05c] layout=%s" % JSON.stringify({"rect": str(label.get_global_rect()), "title": str(_notice().get_global_rect()), "view": str(c.main.get_viewport_rect()), "line_count": label.get_line_count(), "visible_lines": label.get_visible_line_count(), "font": label.get_theme_font_size("font_size"), "text_matches": lines == expected, "injected": true, "error": c.flow.checkpoint.last_error, "title_text": _notice().text}))
		for line: String in lines:
			print("[U-05c] %s" % line)
	await _drop()
	check.call(93, ok and clean, "write_probe_lines_visible")

func _probe_untouched() -> void:
	await _fresh()
	_setup_probe()
	var previous = preload("res://scripts/prologue_checkpoint.gd").new()
	previous.path = c.flow.checkpoint.path
	var ok: bool = previous.write_once(-1, &"task_complete", {"safehouse_reached": false})
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(previous.path)
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	c.finish_sequence(c.main._dialogue)
	ok = ok and bytes == FileAccess.get_file_as_bytes(previous.path) and c.flow.checkpoint.writes == 0
	ok = ok and _probe_files == {"user://prologue_checkpoint.json": "old-checkpoint-bytes"}
	ok = ok and not _probe_ops.has("write:user://prologue_checkpoint.json")
	ok = ok and not _probe_ops.has("remove:user://prologue_checkpoint.json")
	for path: String in ["user://probe.txt", "user://prologue_checkpoint.json.tmp", "user://saves/probe.txt"]:
		var index: int = _probe_ops.find("write:" + path)
		ok = ok and index >= 0 and index + 1 < _probe_ops.size()
		if index >= 0 and index + 1 < _probe_ops.size():
			ok = ok and _probe_ops[index + 1] == "remove:" + path
	await _drop()
	check.call(94, ok and clean, "write_probe_does_not_touch_checkpoint")

func _probe_codes() -> void:
	var ok: bool = true
	var samples: Array[Dictionary] = [
		{"user://probe.txt": ERR_FILE_CANT_OPEN, "user://prologue_checkpoint.json.tmp": ERR_FILE_CANT_WRITE},
		{"mkdir": ERR_CANT_CREATE, "remove:user://probe.txt": ERR_FILE_NO_PERMISSION}]
	for index: int in range(samples.size()):
		await _fresh()
		_setup_probe(samples[index])
		c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_FILE_CANT_OPEN
		c.finish_sequence(c.main._dialogue)
		var text: String = c.flow.checkpoint.get_probe_text()
		if index == 0:
			ok = ok and text.contains("c probe.txt：错误码 12")
			ok = ok and text.contains("d prologue_checkpoint.json.tmp：错误码 13")
			ok = ok and not _probe_ops.has("remove:user://probe.txt")
			ok = ok and _probe_ops.has("remove:user://prologue_checkpoint.json.tmp")
		else:
			ok = ok and text.contains("e saves/probe.txt：建目录错误码 20；未写入")
			ok = ok and text.contains("c probe.txt：成功；清理失败（错误码 10）")
			ok = ok and not _probe_ops.has("write:user://saves/probe.txt")
		ok = ok and c.flow.checkpoint.last_error == ERR_FILE_CANT_OPEN and c.flow.checkpoint.writes == 0
		await _drop()
	check.call(95, ok and clean, "write_probe_reports_error_codes")

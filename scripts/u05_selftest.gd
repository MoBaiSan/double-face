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
var _probe_dirs: Dictionary = {}
var _race_mode: String = ""
var _race_trace: Array[String] = []
var _foreign: Dictionary = {}

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
	await _probe_collision()

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
	var ok: bool = notice != null and not notice.is_visible_in_tree()
	ok = ok and notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.focus_mode == Control.FOCUS_NONE
	if notice != null:
		var rect: Rect2 = notice.get_global_rect()
		ok = ok and notice.text.is_empty() and rect.size.x > 400.0 and rect.size.y > 24.0
		ok = ok and c.main.get_viewport_rect().encloses(rect) and not rect.intersects(c.main._dialogue._panel.get_global_rect())
	ok = ok and GameState.state == S.S4 and c.flow.checkpoint.writes == 0
	await _drop()
	check.call(88, ok and clean, "task_checkpoint_pending_has_no_result")

func _failure() -> void:
	var ok: bool = true
	for sample: Array in [[ERR_BUSY, 44], [ERR_FILE_CANT_WRITE, 13]]:
		await _fresh()
		c.flow.checkpoint.replace_file = func(_a: String, _b: String): return sample[0]
		c.finish_sequence(c.main._dialogue)
		var notice: Label = _notice()
		ok = ok and _noninteractive_notice() and GameState.state == S.S4
		ok = ok and c.flow.checkpoint.last_error == sample[0] and c.flow.checkpoint.writes == 0
		ok = ok and notice != null and notice.text == "自动存档失败，正在重试（错误码 %d）" % sample[1]
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
	ok = ok and notice != null and notice.is_visible_in_tree() and notice.text == "自动存档完成"
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
	_probe_files = {"user://prologue_checkpoint.json": "old-checkpoint-bytes",
		"user://probe.txt": "原文本\n甲", "user://prologue_checkpoint.json.tmp": "原临时\n乙",
		"user://saves/probe.txt": "原子目录\n丙"}
	_probe_dirs = {"user://saves": "shared"}
	_race_mode = ""
	_race_trace.clear()
	_foreign.clear()
	c.flow.checkpoint.write_probe.io = _probe_io
	c.flow.checkpoint.write_probe.token_source = func(): return "u05"

func _probe_kind(path: String) -> String:
	for kind: String in ["direct", "temporary", "nested"]:
		if path.contains("_" + kind + "_"):
			return kind
	return ""

func _probe_io(kind: StringName, path: String) -> Variant:
	# path_exists 已真实返回 false 后，在 B 的原子预留动作前调度 A。
	if kind == &"reserve_dir" and _race_trace.has("B:exists:false:" + path) and not _foreign.has(path):
		if not _probe_dirs.has(path) and not _probe_files.has(path):
			_probe_dirs[path] = "A"
			_probe_files[path.path_join("foreign.bin")] = "A原字节-" + path
			_foreign[path] = _probe_files[path.path_join("foreign.bin")]
			_race_trace.append("A:reserve:OK:" + path)
			_race_trace.append("A:write:" + path)
	_probe_ops.append("%s:%s" % [kind, path])
	match kind:
		&"globalize": return ProjectSettings.globalize_path(path)
		&"dir_exists": return true
		&"path_exists":
			var occupied: bool = _probe_files.has(path) or _probe_dirs.has(path)
			if not occupied and path.contains(".df_diag_") and not path.contains("/probe") and _race_mode in ["race", "all"]:
				if _race_mode == "all" or path.ends_with("_0"):
					_race_trace.append("B:exists:false:" + path)
			return occupied
		&"user_dir": return OS.get_user_data_dir()
		&"mkdir":
			var error: int = int(_probe_errors.get("mkdir", OK))
			if error == OK:
				_probe_dirs[path] = "shared"
			return error
		&"reserve_dir":
			if _probe_files.has(path) or _probe_dirs.has(path):
				_race_trace.append("B:reserve:ERR_ALREADY_EXISTS:" + path)
				return ERR_ALREADY_EXISTS
			_probe_dirs[path] = "B"
			_race_trace.append("B:reserve:OK:" + path)
			if _race_mode == "inner":
				_probe_files[path.path_join("probe.tmp" if _probe_kind(path) == "temporary" else "probe.txt")] = "外来文件"
			return OK
		&"write":
			var error: int = int(_probe_errors.get(_probe_kind(path), OK))
			var created: bool = error != ERR_FILE_CANT_OPEN and not _probe_files.has(path)
			if error != ERR_FILE_CANT_OPEN:
				_probe_files[path] = "probe"
			return {"created": created, "error": error}
		&"remove":
			var error: int = int(_probe_errors.get("remove:" + _probe_kind(path), OK)) if path.contains("/probe.") else OK
			if error != OK:
				return error
			if _probe_dirs.has(path):
				for file_path: String in _probe_files:
					if file_path.begins_with(path + "/"):
						return ERR_BUSY
				_probe_dirs.erase(path)
			else:
				_probe_files.erase(path)
			return OK
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
	_setup_probe({"temporary": ERR_FILE_CANT_OPEN})
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_FILE_CANT_OPEN
	c.finish_sequence(c.main._dialogue)
	await host.get_tree().process_frame
	var label: Label = _probe_label()
	var ok: bool = c.flow.checkpoint.last_error == ERR_FILE_CANT_OPEN
	ok = ok and _notice().text == "自动存档失败，正在重试（错误码 12）"
	ok = ok and label != null and not label.is_visible_in_tree() and label.text.is_empty()
	if label != null:
		var lines: PackedStringArray = c.flow.checkpoint.get_probe_text().split("\n")
		var expected: PackedStringArray = ["a 用户目录：" + ProjectSettings.globalize_path("user://"),
			"b 目录存在：true", "c 独立文本探针：成功", "d 独立临时探针：错误码 12",
			"e saves独立探针：建目录成功；成功", "f OS用户目录：" + OS.get_user_data_dir()]
		ok = ok and lines == expected and _notice().get_theme_font_size("font_size") >= 24
		ok = ok and label.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.focus_mode == Control.FOCUS_NONE
		ok = ok and c.main.get_viewport_rect().encloses(_notice().get_global_rect())
		ok = ok and not _notice().get_global_rect().intersects(c.main._dialogue._panel.get_global_rect())
		ok = ok and lines.size() == 6 and _noninteractive_notice()
	await _drop()
	check.call(93, ok and clean, "write_probe_details_not_rendered")

func _probe_untouched() -> void:
	await _fresh()
	_setup_probe()
	var original: Dictionary = _probe_files.duplicate(true)
	var previous = preload("res://scripts/prologue_checkpoint.gd").new()
	previous.path = c.flow.checkpoint.path
	var ok: bool = previous.write_once(-1, &"task_complete", {})
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(previous.path)
	c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
	c.finish_sequence(c.main._dialogue)
	ok = ok and bytes == FileAccess.get_file_as_bytes(previous.path) and c.flow.checkpoint.writes == 0
	ok = ok and _probe_files == original
	for path: String in original:
		ok = ok and not _probe_ops.has("write:" + path) and not _probe_ops.has("remove:" + path)
	var probe = c.flow.checkpoint.write_probe
	var owned: bool = probe.created_files.size() == 3 and probe.owned_dirs.size() == 3
	for path: String in probe.created_files:
		owned = owned and _probe_ops.has("write:" + path) and _probe_ops.has("remove:" + path) and not _probe_files.has(path)
	for operation: String in _probe_ops:
		if operation.begins_with("remove:"):
			var path: String = operation.trim_prefix("remove:")
			owned = owned and (probe.created_files.has(path) or probe.owned_dirs.has(path))
	owned = owned and _probe_dirs == {"user://saves": "shared"}
	await _drop()
	check.call(94, ok and clean, "write_probe_does_not_touch_checkpoint")
	check.call(96, owned and clean, "probe_cleans_only_owned_files")

func _probe_codes() -> void:
	var ok: bool = true
	var samples: Array[Dictionary] = [
		{"direct": ERR_FILE_CANT_OPEN, "temporary": ERR_FILE_CANT_WRITE},
		{"mkdir": ERR_CANT_CREATE, "remove:direct": ERR_FILE_NO_PERMISSION}]
	for index: int in range(samples.size()):
		await _fresh()
		_setup_probe(samples[index])
		c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_FILE_CANT_OPEN
		c.finish_sequence(c.main._dialogue)
		var text: String = c.flow.checkpoint.get_probe_text()
		var probe = c.flow.checkpoint.write_probe
		if index == 0:
			ok = ok and text.contains("c 独立文本探针：错误码 12") and text.contains("d 独立临时探针：错误码 13")
			ok = ok and probe.created_files.size() == 2
			for path: String in probe.created_files:
				ok = ok and not _probe_files.has(path) and _probe_ops.has("remove:" + path)
		else:
			ok = ok and text.contains("e saves独立探针：建目录错误码 20；未写入")
			ok = ok and text.contains("c 独立文本探针：成功；清理失败（错误码 10）")
			ok = ok and _probe_files.has("user://.df_diag_u05_direct_0/probe.txt")
		ok = ok and c.flow.checkpoint.last_error == ERR_FILE_CANT_OPEN and c.flow.checkpoint.writes == 0
		await _drop()
	var unsupported = preload("res://scripts/write_probe.gd").new()
	var unsupported_ops: Array[StringName] = []
	unsupported.io = func(kind: StringName, _path: String):
		unsupported_ops.append(kind)
		return OK if kind == &"mkdir" else null
	var unsupported_text: String = unsupported.run_once()
	ok = ok and unsupported_text.contains("路径检测不可用；未试写") and unsupported_text.contains("未知（诊断接口不支持）")
	ok = ok and unsupported.created_files.is_empty() and unsupported.owned_dirs.is_empty()
	ok = ok and not unsupported_ops.has(&"write") and not unsupported_ops.has(&"remove")
	check.call(95, ok and clean, "write_probe_reports_error_codes")

func _probe_collision() -> void:
	var results: Array[bool] = []
	for mode: String in ["file", "directory", "inner", "race", "all"]:
		await _fresh()
		_setup_probe()
		_race_mode = mode
		var d0: String = "user://.df_diag_u05_direct_0"
		if mode == "file":
			_probe_files[d0] = "外来候选字节"
		if mode == "directory":
			_probe_dirs[d0] = "A"
			_probe_files[d0 + "/foreign.bin"] = "外来候选字节"
		var before: Dictionary = _probe_files.duplicate(true)
		c.flow.checkpoint.replace_file = func(_a: String, _b: String): return ERR_BUSY
		c.finish_sequence(c.main._dialogue)
		var probe = c.flow.checkpoint.write_probe
		var ok: bool = probe.runs == 1
		for path: String in before:
			ok = ok and _probe_files.get(path) == before[path] and not _probe_ops.has("write:" + path) and not _probe_ops.has("remove:" + path)
		if mode in ["file", "directory"]:
			ok = ok and not probe.owned_dirs.has(d0) and probe.owned_dirs.has("user://.df_diag_u05_direct_1")
		if mode == "directory":
			ok = ok and _probe_dirs.get(d0) == "A" and not _probe_ops.has("remove:" + d0)
		if mode == "inner":
			ok = ok and probe.created_files.is_empty()
			for directory: String in probe.owned_dirs:
				var file: String = directory + ("/probe.tmp" if _probe_kind(directory) == "temporary" else "/probe.txt")
				ok = ok and _probe_files.get(file) == "外来文件" and not _probe_ops.has("write:" + file) and not _probe_ops.has("remove:" + file)
		if mode in ["race", "all"]:
			ok = ok and _foreign.size() == (3 if mode == "race" else 24)
			for directory: String in _foreign:
				ok = ok and _probe_dirs.get(directory) == "A" and _probe_files.get(directory + "/foreign.bin") == _foreign[directory] and not probe.owned_dirs.has(directory)
				var index: int = _race_trace.find("B:exists:false:" + directory)
				ok = ok and index >= 0
				if index >= 0:
					ok = ok and _race_trace.slice(index, index + 4) == ["B:exists:false:" + directory, "A:reserve:OK:" + directory, "A:write:" + directory, "B:reserve:ERR_ALREADY_EXISTS:" + directory]
				for operation: String in _probe_ops:
					ok = ok and not operation.begins_with("write:" + directory + "/") and not operation.begins_with("remove:" + directory)
					ok = ok and not operation.begins_with("path_exists:" + directory + "/")
			if mode == "race":
				ok = ok and probe.created_files.size() == 3 and _probe_ops.has("reserve_dir:user://.df_diag_u05_direct_1")
				for path: String in probe.created_files:
					ok = ok and _probe_ops.has("write:" + path) and _probe_ops.has("remove:" + path)
			else:
				ok = ok and probe.owned_dirs.is_empty() and probe.created_files.is_empty()
				ok = ok and _probe_ops.filter(func(op: String): return op.begins_with("write:") or op.begins_with("remove:")).is_empty()
		results.append(ok)
		await _drop()
	check.call(97, results.size() == 5 and results.all(func(ok: bool): return ok) and clean, "probe_collision_preserves_bytes")

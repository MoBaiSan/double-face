## U-06 独立无窗口自检；不改变 SP-14 的 95 条既有断言或入口。
extends SceneTree
const L = preload("res://scripts/save_location.gd")
const W = preload("res://scripts/prologue_checkpoint.gd")
var C: Script
var host: Control
var paths: PackedStringArray
var directory: String
var failures: int = 0
var assertions: int = 0
var ops: Array[String] = []
var files: Dictionary = {}
var existing: Array[String] = []
var errors: PackedInt32Array = [0, 0, 0]
var mkdir_errors: PackedInt32Array = [0, 0, 0]
var cleanup_error: Error = OK

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	directory = OS.get_temp_dir().path_join("DoubleFace-U06-%d" % OS.get_process_id())
	for index in 3:
		var folder: String = directory.path_join(str(index))
		DirAccess.make_dir_recursive_absolute(folder)
		paths.append(folder.path_join(L.FILE_NAME))
	print("[U-06] actual_paths=%s" % JSON.stringify(_actual_paths()))
	host = load("res://scenes/Main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	await process_frame
	C = load("res://scripts/prologue_test_context.gd")
	_primary()
	_beside()
	_temp()
	_read_order()
	_stable()
	_no_formal_probe()
	_write_error_cleanup()
	_existing_pin()
	_all_fail()
	_malformed()
	_real_cleanup()
	await _notices()
	_remove_owned()
	host.queue_free()
	await process_frame
	print("[U-06] assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 and assertions == 12 else 1)

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
	print("[U-06] %s %s" % ["PASS" if ok else "FAIL", label])

func _actual_paths() -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in L.default_paths():
		result.append(ProjectSettings.globalize_path(path))
	return result

func _mock(samples: PackedInt32Array = [0, 0, 0]) -> RefCounted:
	ops.clear()
	files.clear()
	existing.clear()
	errors = samples
	mkdir_errors = [0, 0, 0]
	cleanup_error = OK
	return L.new(paths, _io)

func _io(operation: StringName, target: String) -> Variant:
	ops.append("%s:%s" % [operation, target])
	var parent: String = target if operation == &"mkdir" else target.get_base_dir()
	var index: int = paths.find(parent.path_join(L.FILE_NAME))
	match operation:
		&"exists": return target in existing or files.has(target)
		&"mkdir": return mkdir_errors[index]
		&"write":
			var opened: bool = errors[index] not in [ERR_FILE_CANT_OPEN, ERR_FILE_NO_PERMISSION]
			if opened:
				files[target] = "probe"
			return {"opened": opened, "error": errors[index]}
		&"remove":
			if cleanup_error == OK:
				files.erase(target)
			return cleanup_error
	return ERR_INVALID_PARAMETER

func _primary() -> void:
	var location = _mock()
	var ok: bool = location.select() == paths[0] and location.probe_paths.size() == 1
	ok = ok and location.notice().is_empty() and files.is_empty()
	_check(ok, "save_primary_used_when_writable")

func _beside() -> void:
	var ok: bool = true
	for error: int in [ERR_FILE_CANT_OPEN, ERR_FILE_CANT_WRITE, ERR_FILE_NO_PERMISSION]:
		var location = _mock(PackedInt32Array([error, OK, OK]))
		ok = location.select() == paths[1] and location.probe_paths.size() == 2 and ok
		ok = files.is_empty() and ok
	var blocked_parent = _mock()
	mkdir_errors[0] = ERR_FILE_NO_PERMISSION
	ok = blocked_parent.select() == paths[1] and blocked_parent.probe_paths.size() == 1 and ok
	_check(ok, "save_falls_back_beside_exe")

func _temp() -> void:
	var location = _mock([ERR_FILE_CANT_OPEN, ERR_FILE_CANT_WRITE, OK])
	var ok: bool = location.select() == paths[2] and location.probe_paths.size() == 3
	_check(ok and files.is_empty(), "save_falls_back_to_temp")

func _read_order() -> void:
	_erase_files()
	for index in 3:
		_seed(paths[index], JSON.stringify({"progress": {"slot": 11 * (index + 1)}}))
	var ok: bool = true
	for index in 3:
		var location = L.new(paths)
		var writer = W.new(location)
		var saved: Dictionary = writer.read_saved()
		ok = writer.path == paths[index] and saved.get("progress", {}).get("slot") == 11 * (index + 1) and ok
		ok = location.probe_paths.is_empty() and ok
		ok = writer.write_once(index, &"task_complete", {"slot": 100 + index}) and ok
		ok = writer.write_once(index, &"task_complete", {}) and writer.writes == 1 and ok
		ok = writer.read_saved().get("progress", {}).get("slot") == 100 + index and ok
		for untouched in range(index + 1, 3):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(paths[untouched]))
			ok = data.get("progress", {}).get("slot") == 11 * (untouched + 1) and ok
		DirAccess.remove_absolute(paths[index])
	_check(ok, "save_reads_first_existing")

func _stable() -> void:
	var location = _mock([ERR_FILE_CANT_OPEN, OK, OK])
	var writer = W.new(location)
	var first_ops: Array[String] = ops.duplicate()
	existing.append(paths[0])
	errors = [0, 0, 0]
	var ok: bool = writer.path == paths[1]
	for index in 8:
		ok = location.select() == paths[1] and writer.path == paths[1] and ok
		location.notice()
	_check(ok and ops == first_ops, "save_path_stable_within_run")

func _no_formal_probe() -> void:
	var location = _mock([ERR_FILE_CANT_WRITE, ERR_FILE_CANT_OPEN, OK])
	location.select()
	var ok: bool = location.probe_paths.size() == 3 and files.is_empty()
	for operation: String in ops:
		for path: String in paths:
			ok = operation not in ["write:" + path, "remove:" + path] and ok
	for probe: String in location.probe_paths:
		ok = probe.get_file().begins_with(".df_write_probe_") and probe not in paths and ok
	print("[U-06] probe_operations=%s" % JSON.stringify(ops))
	_check(ok, "save_probe_never_uses_checkpoint")

func _write_error_cleanup() -> void:
	var location = _mock([ERR_FILE_CANT_WRITE, OK, OK])
	var ok: bool = location.select() == paths[1] and files.is_empty()
	for probe: String in location.probe_paths:
		var written: int = ops.find("write:" + probe)
		ok = written >= 0 and ops[written + 1] == "remove:" + probe and ok
	location = _mock()
	cleanup_error = ERR_FILE_NO_PERMISSION
	location.select()
	ok = location.last_error == ERR_FILE_NO_PERMISSION and location.probe_paths.size() == 3 and ok
	_check(ok, "save_probe_write_error_cleans_and_cleanup_error_rejected")

func _existing_pin() -> void:
	var location = _mock([ERR_FILE_CANT_OPEN, ERR_FILE_CANT_OPEN, OK])
	existing.append(paths[1])
	var writer = W.new(location)
	var ok: bool = writer.path == paths[1] and location.probe_paths.is_empty()
	existing.append(paths[0])
	ok = location.select() == paths[1] and ok
	_check(ok, "save_existing_unwritable_stays_selected")

func _legacy_probe(operation: StringName, target: String) -> Variant:
	match operation:
		&"globalize": return ProjectSettings.globalize_path(target)
		&"user_dir": return OS.get_user_data_dir()
		&"exists": return true
		&"mkdir", &"remove": return OK
		&"write": return {"opened": false, "error": ERR_FILE_CANT_OPEN}
	return null

func _all_fail() -> void:
	_erase_files()
	var location = _mock([ERR_FILE_CANT_OPEN, ERR_FILE_CANT_OPEN, ERR_FILE_CANT_OPEN])
	var writer = W.new(location)
	_seed(paths[0], "old bytes")
	writer.replace_file = func(_a: String, _b: String): return ERR_FILE_NO_PERMISSION
	writer.write_probe.io = _legacy_probe
	var ok: bool = not writer.write_once(1, &"task_complete", {})
	ok = writer.writes == 0 and writer._written.is_empty() and writer.path == paths[0] and ok
	ok = writer.last_error == ERR_FILE_NO_PERMISSION and FileAccess.get_file_as_string(paths[0]) == "old bytes" and ok
	ok = not FileAccess.file_exists(paths[0] + ".tmp") and ok
	_check(ok, "save_all_locations_fail_no_fake_commit")
	_erase_files()

func _malformed() -> void:
	_seed(paths[0], "{broken")
	_seed(paths[1], '{"progress":{"slot":22}}')
	var writer = W.new(L.new(paths))
	var ok: bool = writer.read_saved().is_empty() and writer.last_error != OK
	ok = writer.path == paths[0] and FileAccess.get_file_as_string(paths[0]) == "{broken" and ok
	_check(ok, "save_unreadable_first_does_not_silently_switch")
	_erase_files()

func _real_cleanup() -> void:
	var location = L.new(paths)
	var ok: bool = location.select() == paths[0] and location.probe_paths.size() == 1
	for probe: String in location.probe_paths:
		ok = not FileAccess.file_exists(probe) and ok
	for path: String in paths:
		ok = not FileAccess.file_exists(path) and ok
	print("[U-06] real_probe_clean=%s paths=%s" % [ok, JSON.stringify(location.probe_paths)])
	_check(ok, "save_real_probe_removed_without_creating_checkpoint")

func _notices() -> void:
	var ok: bool = true
	for index in 3:
		ok = await _notice_sample(index) and ok
	_check(ok, "save_notice_only_on_fallback")

func _notice_sample(index: int) -> bool:
	var context = C.new()
	await context.create(host, C.S.S4)
	context.flow.set_process(false)
	var samples: PackedInt32Array = [0, 0, 0]
	for previous in index:
		samples[previous] = ERR_FILE_CANT_OPEN
	context.flow.checkpoint = W.new(_mock(samples))
	context.flow.content.present(C.S.S4)
	await process_frame
	var label: Label = context.flow.content.get_node("TaskComplete/SaveLocationNotice")
	var expected: String = ["", "存档已改存到游戏旁边的 saves 文件夹", "存档已改存到系统临时目录"][index]
	var ok: bool = label.text == expected and label.is_visible_in_tree() == (index > 0)
	ok = label.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.focus_mode == Control.FOCUS_NONE and ok
	ok = label.get_theme_font_size("font_size") >= 24 and ok
	context.flow._on_state_changed(C.S.S3, C.S.S4, &"exit", root.get_node("GameState").run_id)
	context.finish_sequence(context.main._dialogue)
	await process_frame
	ok = root.get_node("GameState").state == C.S.S6 and context.flow.checkpoint.writes == 1 and ok
	ok = label.text == expected and label.is_visible_in_tree() == (index > 0) and ok
	ok = context.main.get_viewport_rect().encloses(label.get_global_rect()) and ok
	print("[U-06] notice=%s visible=%s state=%s" % [label.text, label.is_visible_in_tree(), root.get_node("GameState").state])
	ok = await context.close() and ok
	_erase_files()
	return ok

func _seed(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _erase_files() -> void:
	for path: String in paths:
		for target: String in [path, path + ".tmp"]:
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(target)

func _remove_owned() -> void:
	_erase_files()
	for path: String in paths:
		DirAccess.remove_absolute(path.get_base_dir())
	DirAccess.remove_absolute(directory)
	print("[U-06] test_directory_removed=%s" % not DirAccess.dir_exists_absolute(directory))

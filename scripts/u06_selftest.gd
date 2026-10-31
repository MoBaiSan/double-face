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
	await _success_text()
	await _success_timing()
	await _failure_text()
	_location_text_removed()
	_remove_owned()
	host.queue_free()
	await process_frame
	print("[U-06] assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 and assertions == 15 else 1)

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
	ok = ok and location.selected_index == 0 and files.is_empty()
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
		ok = location.selected_index == 1 and ok
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

func _fresh_result(index: int = 0) -> RefCounted:
	var context = C.new()
	await context.create(host, C.S.S4)
	context.flow.set_process(false)
	context.flow.content.set_process(false)
	var samples: PackedInt32Array = [0, 0, 0]
	for previous in index:
		samples[previous] = ERR_FILE_CANT_OPEN
	context.flow.checkpoint = W.new(_mock(samples))
	context.flow.checkpoint.write_probe.io = _legacy_probe
	context.flow.content.present(C.S.S4)
	context.flow._on_state_changed(C.S.S3, C.S.S4, &"exit", root.get_node("GameState").run_id)
	return context

func _result(context: RefCounted) -> Label:
	return context.flow.content.get_node("TaskComplete/CheckpointStatus")

func _close_result(context: RefCounted) -> bool:
	var clean: bool = await context.close()
	_erase_files()
	return clean

func _success_text() -> void:
	var ok: bool = true
	for index in 3:
		var context = await _fresh_result(index)
		var label: Label = _result(context)
		ok = not label.is_visible_in_tree() and label.text.is_empty() and ok
		context.finish_sequence(context.main._dialogue)
		await process_frame
		ok = root.get_node("GameState").state == C.S.S6 and context.flow.checkpoint.writes == 1 and ok
		ok = label.is_visible_in_tree() and label.text == "自动存档完成" and ok
		ok = _valid_rect(context, label) and ok
		ok = await _close_result(context) and ok
	_check(ok, "save_success_text_shown")

func _success_timing() -> void:
	var context = await _fresh_result()
	context.finish_sequence(context.main._dialogue)
	var label: Label = _result(context)
	print("[U-06b] timing=%s" % JSON.stringify({"seconds": 0.0, "visible": label.is_visible_in_tree(), "text": label.text}))
	for delta: float in [NAN, INF, -1.0, 0.0]:
		context.flow.content._process(delta)
	context.flow.content._process(1.99)
	var ok: bool = label.is_visible_in_tree() and label.text == "自动存档完成"
	print("[U-06b] timing=%s" % JSON.stringify({"seconds": 1.99, "visible": label.is_visible_in_tree(), "text": label.text}))
	context.flow.content._process(0.01)
	print("[U-06b] timing=%s" % JSON.stringify({"seconds": 2.0, "visible": label.is_visible_in_tree(), "text": label.text}))
	ok = not label.visible and label.text.is_empty() and ok
	context.flow.content.present(C.S.S6)
	context.flow.content._process(10.0)
	ok = not label.visible and label.text.is_empty() and ok
	ok = context.flow.checkpoint.writes == 1 and ok
	ok = await _close_result(context) and ok
	_check(ok, "save_success_text_hides_after_two_seconds")

func _failure_text() -> void:
	var ok: bool = true
	for error: int in [12, 13, 44]:
		ok = await _failure_sample(error) and ok
	_check(ok, "save_failure_text_keeps_error_code")

func _failure_sample(error: int) -> bool:
	var context = await _fresh_result()
	context.flow.checkpoint.replace_file = func(_a: String, _b: String): return error
	context.finish_sequence(context.main._dialogue)
	await process_frame
	var label: Label = _result(context)
	var expected: String = "自动存档失败，正在重试（错误码 %d）" % error
	var ok: bool = label.is_visible_in_tree() and label.text == expected
	ok = root.get_node("GameState").state == C.S.S4 and context.flow.checkpoint.writes == 0 and ok
	ok = _valid_rect(context, label) and ok
	context.flow.content._process(3.0)
	context.flow.content.set_checkpoint_status()
	ok = label.is_visible_in_tree() and label.text == expected and ok
	context.flow.checkpoint.replace_file = Callable()
	context.flow._process(1.0)
	ok = label.text == "自动存档完成" and context.flow.checkpoint.writes == 1 and ok
	C.enter_domain(context.main, C.S.S2)
	context.flow.content.present(C.S.S2)
	ok = not label.visible and label.text.is_empty() and ok
	ok = await _close_result(context) and ok
	return ok

func _valid_rect(context: RefCounted, label: Label) -> bool:
	var rect: Rect2 = label.get_global_rect()
	var ok: bool = context.main.get_viewport_rect().encloses(rect) and rect.size.y >= 24.0
	ok = label.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.focus_mode == Control.FOCUS_NONE and ok
	var observed: Dictionary = {"notice": str(rect), "text": label.text, "buttons": {}}
	var panels: Array[Control] = [context.main._dialogue._panel, context.flow.safe_room.player._panel]
	observed["dialogue"] = []
	for panel: Control in panels:
		ok = not rect.intersects(panel.get_global_rect()) and ok
		observed["dialogue"].append(str(panel.get_global_rect()))
	for button: Node in context.main.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			ok = not rect.intersects(button.get_global_rect()) and ok
			observed.buttons[str(context.main.get_path_to(button))] = str(button.get_global_rect())
	print("[U-06b] rects=%s" % JSON.stringify(observed))
	return ok

func _location_text_removed() -> void:
	var banned: PackedStringArray = [String.chr(0x6539) + String.chr(0x5b58),
		"saves " + String.chr(0x6587) + String.chr(0x4ef6) + String.chr(0x5939),
		String.chr(0x4e34) + String.chr(0x65f6) + String.chr(0x76ee) + String.chr(0x5f55)]
	_check(_source_clean("res://", banned), "save_location_text_removed")

func _source_clean(folder: String, banned: PackedStringArray) -> bool:
	var ok: bool = true
	for sub: String in DirAccess.get_directories_at(folder):
		if not sub.begins_with("."):
			ok = _source_clean(folder.path_join(sub), banned) and ok
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() in ["gd", "tscn", "tres", "json", "md", "cfg", "godot"]:
			var text: String = FileAccess.get_file_as_string(folder.path_join(file))
			for phrase: String in banned:
				ok = not text.contains(phrase) and ok
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

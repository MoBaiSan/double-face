## 两个检查点共用的原子写入器；成功才登记去重，失败保留旧文件。
extends RefCounted
var path: String
var location: RefCounted
var last_error: Error = OK
var writes: int = 0
var attempts: int = 0
var _written: Dictionary = {}
var replace_file: Callable
var write_probe = preload("res://scripts/write_probe.gd").new()

func _init(save_location: RefCounted = null) -> void:
	location = save_location if save_location != null else preload("res://scripts/save_location.gd").new()
	path = location.select()

func write_once(run_id: int, checkpoint_id: StringName, payload: Dictionary) -> bool:
	var key: String = "%d:%s" % [run_id, checkpoint_id]
	if _written.has(key):
		return true
	attempts += 1
	var document: Dictionary = {"version": 1, "checkpoint": checkpoint_id, "progress": payload}
	var state: Node = (Engine.get_main_loop() as SceneTree).root.get_node("GameState")
	document["tutorial"] = state.tutorial_seen.duplicate(true)
	if not _write_atomic(JSON.stringify(document)):
		write_probe.run_once()
		return false
	_written[key] = true
	writes += 1
	return true

func _write_atomic(text: String) -> bool:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return false
	file.store_string(text)
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error == OK:
		last_error = _replace(temporary, path)
	if last_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return last_error == OK

func _replace(temporary: String, target: String) -> Error:
	if replace_file.is_valid():
		return replace_file.call(temporary, target)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(target))


func get_probe_text() -> String:
	return write_probe.text


func get_location_notice() -> String:
	return location.notice() if path == location.selected else ""

func read_saved() -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = FileAccess.get_open_error()
		return {}
	var text: String = file.get_as_text()
	last_error = file.get_error()
	file.close()
	if last_error != OK:
		return {}
	var document := JSON.new()
	last_error = document.parse(text)
	if last_error != OK:
		return {}
	if not document.data is Dictionary:
		last_error = ERR_INVALID_DATA
		return {}
	return document.data

## 缺失/坏档返回未知，不把未知伪装成未上药分支。
func read_safehouse_branch() -> Dictionary:
	var document: Dictionary = read_saved()
	if document.get("version") != 1 or document.get("checkpoint") != "safehouse_exit":
		return {}
	var progress: Variant = document.get("progress")
	if not progress is Dictionary or progress.get("safehouse_reached") != true or progress.get("safehouse_exit") != true:
		return {}
	if not progress.get("r13_done") is bool or not progress.get("trust_read") is bool:
		return {}
	return {"r13_done": progress.r13_done, "trust_read": progress.trust_read}

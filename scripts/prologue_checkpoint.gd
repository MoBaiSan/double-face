## 两个检查点共用的原子写入器；成功才登记去重，失败保留旧文件。
extends RefCounted
var path: String = "user://prologue_checkpoint.json"
var last_error: Error = OK
var writes: int = 0
var attempts: int = 0
var _written: Dictionary = {}
var replace_file: Callable

func write_once(run_id: int, checkpoint_id: StringName, payload: Dictionary) -> bool:
	var key: String = "%d:%s" % [run_id, checkpoint_id]
	if _written.has(key):
		return true
	attempts += 1
	var document: Dictionary = {"version": 1, "checkpoint": checkpoint_id, "progress": payload}
	if not _write_atomic(JSON.stringify(document)):
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


## 每个保存器启动时固定位置；先沿用旧档，否则依次探测三个候选目录。
extends RefCounted
const FILE_NAME: String = "prologue_checkpoint.json"
const NOTICE_EXE: String = "存档已改存到游戏旁边的 saves 文件夹"
const NOTICE_TEMP: String = "存档已改存到系统临时目录"
var candidates: PackedStringArray
var io: Callable
var selected: String = ""
var selected_index: int = -1
var last_error: Error = OK
var probe_paths: Array[String] = []
var _decided: bool = false

func _init(paths: PackedStringArray = [], operations: Callable = Callable()) -> void:
	candidates = default_paths() if paths.is_empty() else paths.duplicate()
	io = operations

static func default_paths() -> PackedStringArray:
	return PackedStringArray(["user://" + FILE_NAME,
		OS.get_executable_path().get_base_dir().path_join("saves").path_join(FILE_NAME),
		OS.get_temp_dir().path_join("Double Face").path_join(FILE_NAME)])

func select() -> String:
	if _decided:
		return selected
	_decided = true
	var existing: int = _find_existing()
	if existing >= 0:
		return _pin(existing)
	for index in candidates.size():
		last_error = _probe(candidates[index])
		if last_error == OK:
			return _pin(index)
	# 三处都失败仍固定首选，保存器继续如实报错/重试，绝不登记成功。
	return _pin(0)

func _find_existing() -> int:
	for index in candidates.size():
		if bool(_op(&"exists", candidates[index])):
			return index
	return -1

func _pin(index: int) -> String:
	selected_index = index
	selected = candidates[index]
	return selected

func notice() -> String:
	select()
	if selected_index == 1:
		return NOTICE_EXE
	return NOTICE_TEMP if selected_index == 2 else ""

func _probe(target: String) -> Error:
	var directory: String = target.get_base_dir()
	var error: Error = int(_op(&"mkdir", directory)) as Error
	if error != OK:
		return error
	var probe: String = directory.path_join(".df_write_probe_%d_%d_%d.tmp" %
		[OS.get_process_id(), get_instance_id(), Time.get_ticks_usec()])
	if bool(_op(&"exists", probe)):
		return ERR_ALREADY_EXISTS
	probe_paths.append(probe)
	var result: Dictionary = _op(&"write", probe)
	error = int(result.error) as Error
	if bool(result.opened):
		var cleanup: Error = int(_op(&"remove", probe)) as Error
		if cleanup != OK:
			return cleanup
	return error

func _op(operation: StringName, target: String) -> Variant:
	if io.is_valid():
		return io.call(operation, target)
	match operation:
		&"exists": return FileAccess.file_exists(target)
		&"mkdir": return DirAccess.make_dir_recursive_absolute(target)
		&"write": return _write_probe(target)
		&"remove": return DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	return ERR_INVALID_PARAMETER

func _write_probe(target: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return {"opened": false, "error": FileAccess.get_open_error()}
	var stored: bool = file.store_string("Double Face save-location probe\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if not stored and error == OK:
		error = ERR_FILE_CANT_WRITE
	return {"opened": true, "error": error}

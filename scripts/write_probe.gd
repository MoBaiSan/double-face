## 首次保存失败的诊断；独占新目录，只清理本次创建的文件。
extends RefCounted
const MAX_CANDIDATES: int = 8
var text: String = ""
var runs: int = 0
var io: Callable
var token_source: Callable
var owned_dirs: Array[String] = []
var created_files: Array[String] = []
var _token: String = ""

func run_once() -> String:
	if runs > 0:
		return text
	runs += 1
	_token = str(token_source.call()) if token_source.is_valid() else "%d_%d_%d" % [OS.get_process_id(), get_instance_id(), Time.get_ticks_usec()]
	var absolute: String = str(_op(&"globalize", "user://"))
	var exists: Variant = _op(&"dir_exists", absolute)
	var exists_text: String = str(exists).to_lower() if exists is bool else "未知（诊断接口不支持）"
	var direct: String = _probe("user://", "direct", ".txt")
	var temporary: String = _probe("user://", "temporary", ".tmp")
	var mkdir_error: int = int(_op(&"mkdir", "user://saves"))
	var nested: String = "建目录错误码 %d；未写入" % mkdir_error
	if mkdir_error == OK:
		nested = "建目录成功；" + _probe("user://saves", "nested", ".txt")
	text = "\n".join([
		"a 用户目录：" + absolute,
		"b 目录存在：" + exists_text,
		"c 独立文本探针：" + direct,
		"d 独立临时探针：" + temporary,
		"e saves独立探针：" + nested,
		"f OS用户目录：" + str(_op(&"user_dir"))])
	return text

func _probe(parent: String, kind: String, suffix: String) -> String:
	for index: int in range(MAX_CANDIDATES):
		var directory: String = parent.path_join(".df_diag_%s_%s_%d" % [_token, kind, index])
		var occupied: Variant = _op(&"path_exists", directory)
		if not occupied is bool:
			return "路径检测不可用；未试写"
		if occupied:
			continue
		var reserved: int = int(_op(&"reserve_dir", directory))
		if reserved == ERR_ALREADY_EXISTS:
			continue
		if reserved != OK:
			return "创建诊断目录错误码 %d；未试写" % reserved
		owned_dirs.append(directory)
		var path: String = directory.path_join("probe" + suffix)
		var message: String = _write_and_remove(path)
		# 非递归删除：非本轮文件出现时保留，不扫描清理。
		var cleanup: int = int(_op(&"remove", directory))
		if cleanup != OK:
			message += "；目录清理失败（错误码 %d）" % cleanup
		return message
	return "候选目录均不可用；未试写"

func _write_and_remove(path: String) -> String:
	if not owned_dirs.has(path.get_base_dir()):
		return "未取得目录所有权；未写入"
	var occupied: Variant = _op(&"path_exists", path)
	if not occupied is bool:
		return "路径检测不可用；未试写"
	if occupied:
		return "候选文件已占用；未写入"
	var result: Dictionary = _op(&"write", path)
	var error: int = int(result.get("error", ERR_CANT_OPEN))
	var message: String = "成功" if error == OK else "错误码 %d" % error
	if bool(result.get("created", false)):
		created_files.append(path)
		var cleanup: int = int(_op(&"remove", path))
		if cleanup != OK:
			message += "；清理失败（错误码 %d）" % cleanup
	return message

func _op(kind: StringName, path: String = "") -> Variant:
	if io.is_valid():
		return io.call(kind, path)
	match kind:
		&"globalize": return ProjectSettings.globalize_path(path)
		&"dir_exists": return DirAccess.dir_exists_absolute(path)
		&"path_exists": return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
		&"user_dir": return OS.get_user_data_dir()
		&"mkdir": return DirAccess.make_dir_recursive_absolute(path)
		&"reserve_dir": return DirAccess.make_dir_absolute(path)
		&"write": return _write_file(path)
		&"remove": return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return ERR_INVALID_PARAMETER

func _write_file(path: String) -> Dictionary:
	if not owned_dirs.has(path.get_base_dir()) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return {"created": false, "error": ERR_ALREADY_EXISTS}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"created": false, "error": FileAccess.get_open_error()}
	var stored: bool = file.store_string("write-probe\n")
	file.flush()
	var error: Error = file.get_error()
	if not stored and error == OK:
		error = ERR_FILE_CANT_WRITE
	file.close()
	return {"created": true, "error": error}

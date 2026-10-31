## 首次保存失败的一次性诊断；不写正式检查点，也不决定保存是否成功。
extends RefCounted
const PROBE_PATHS: Array[String] = [
	"user://probe.txt", "user://prologue_checkpoint.json.tmp", "user://saves/probe.txt"]
var text: String = ""
var runs: int = 0
var io: Callable

func run_once() -> String:
	if runs > 0:
		return text
	runs += 1
	var absolute: String = str(_op(&"globalize", "user://"))
	var exists: bool = bool(_op(&"exists", absolute))
	var direct: String = _write_and_remove(PROBE_PATHS[0])
	var temporary: String = _write_and_remove(PROBE_PATHS[1])
	var mkdir_error: int = int(_op(&"mkdir", "user://saves"))
	var nested: String = "建目录错误码 %d；未写入" % mkdir_error
	if mkdir_error == OK:
		nested = "建目录成功；" + _write_and_remove(PROBE_PATHS[2])
	text = "\n".join([
		"a 用户目录：" + absolute,
		"b 目录存在：" + ("true" if exists else "false"),
		"c probe.txt：" + direct,
		"d prologue_checkpoint.json.tmp：" + temporary,
		"e saves/probe.txt：" + nested,
		"f OS用户目录：" + str(_op(&"user_dir"))])
	return text

func _write_and_remove(path: String) -> String:
	var result: Dictionary = _op(&"write", path)
	var error: int = int(result.get("error", ERR_CANT_OPEN))
	var message: String = "成功" if error == OK else "错误码 %d" % error
	if bool(result.get("opened", false)):
		var cleanup: int = int(_op(&"remove", path))
		if cleanup != OK:
			message += "；清理失败（错误码 %d）" % cleanup
	return message

func _op(kind: StringName, path: String = "") -> Variant:
	if io.is_valid():
		return io.call(kind, path)
	match kind:
		&"globalize": return ProjectSettings.globalize_path(path)
		&"exists": return DirAccess.dir_exists_absolute(path)
		&"user_dir": return OS.get_user_data_dir()
		&"mkdir": return DirAccess.make_dir_recursive_absolute(path)
		&"write": return _write_file(path)
		&"remove": return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return ERR_INVALID_PARAMETER

func _write_file(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"opened": false, "error": FileAccess.get_open_error()}
	file.store_string("write-probe\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return {"opened": true, "error": error}

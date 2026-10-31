## 独立进程只读父测试拥有的临时文件。
extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path():
		quit(1)
		return
	var basename: String = args[0].get_file()
	if not basename.begins_with("sp19_") or not basename.ends_with(".json"):
		quit(2)
		return
	var file: FileAccess = FileAccess.open(args[0], FileAccess.READ)
	if file == null:
		quit(3)
		return
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var valid: bool = document is Dictionary and document.get("version") == 1 and document.get("checkpoint") == "safehouse_exit"
	valid = valid and document.get("progress") == {"safehouse_reached": true, "safehouse_exit": true, "r13_done": true, "trust_read": false}
	if valid:
		print("SP19_READBACK_OK")
	else:
		print("SP19_READBACK_BAD_DOCUMENT")
	quit(0 if valid else 4)

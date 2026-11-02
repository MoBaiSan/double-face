## 独立进程只读父测试拥有的临时文件。
extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path():
		quit(1)
		return
	var basename: String = args[0].get_file()
	if not (basename.begins_with("sp19_") or basename.begins_with("sp25_")) or not basename.ends_with(".json"):
		quit(2)
		return
	var expected: Dictionary = {"false_false": {"r13_done": false, "trust_read": false}, "false_true": {"r13_done": false, "trust_read": true}, "true_true": {"r13_done": true, "trust_read": true}, "true_false": {"r13_done": true, "trust_read": false}}
	if not expected.has(args[1]):
		quit(3)
		return
	var reader = load("res://scripts/prologue_checkpoint.gd").new()
	reader.path = args[0]
	var valid: bool = reader.read_safehouse_branch() == expected[args[1]]
	if valid:
		print("SP19_READBACK_OK")
	else:
		print("SP19_READBACK_BAD_DOCUMENT")
	quit(0 if valid else 4)

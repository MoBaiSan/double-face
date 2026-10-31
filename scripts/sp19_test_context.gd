## SP-19 的显式域夹具；只拥有独立临时档。
extends "res://scripts/sp17_test_context.gd"
const THANKS: String = "……谢谢你们。这一趟，辛苦你们了。"
var ep: Node
var art: Control
var arrival_ok: bool = false

func fresh(host: Control, initial: int = S.S6) -> void:
	await super.fresh(host, initial)
	var path: String = "user://sp19_%d_%d.json" % [OS.get_process_id(), serial]
	paths.append(path)
	c.flow.checkpoint.path = path
	c.flow.checkpoint.write_probe.io = _probe_io
	ep = c.flow.epilogue
	art = ep.doorway
	arrival_ok = false
	c.watch(player.line_started, _arrival)

func _probe_io(kind: StringName, path: String) -> Variant:
	match kind:
		&"globalize": return ProjectSettings.globalize_path(path)
		&"exists": return true
		&"file_exists": return false
		&"write": return {"opened": true, "error": OK}
		&"user_dir": return OS.get_user_data_dir()
	return OK

func _arrival(id: String) -> void:
	if id == "T193":
		arrival_ok = phase_contract() and not room.visual.visible

func ready_door(host: Control, trust: bool = false) -> void:
	await fresh(host)
	complete_sofa()
	if trust:
		GameState.record_event(&"E13", true)

func exit_ids() -> Array:
	return ids().filter(func(id: String): return id != "T176" and id != "T177")

func finished_once(trust: bool = false) -> bool:
	return exit_ids() == ["T193"] and c.flow.checkpoint.writes == 1 and receipts.size() == 1 and finished.size() == 1 and c.event_count(&"E14") == 1 and valid_document(document(), trust)

static func valid_document(doc: Dictionary, trust: bool = false) -> bool:
	return doc.get("version") == 1 and doc.get("checkpoint") == "safehouse_exit" and doc.get("progress") == {"safehouse_reached": true, "safehouse_exit": true, "r13_done": true, "trust_read": trust}

func phase_contract() -> bool:
	if ep.phase == ep.Phase.READING:
		if not room.is_visible_in_tree():
			return true
		return _outside()
	if ep.phase in [ep.Phase.LEFT, ep.Phase.WAIT_SAVE, ep.Phase.FINISHED]:
		return not art.figure.visible and not room.visual.visible and art.visible
	return not art.visible and not art.figure.visible

func _outside() -> bool:
	if not art.is_visible_in_tree() or not art.figure.is_visible_in_tree() or room.visual.visible:
		return false
	var opening: ColorRect = art.canvas.get_node("DoorOpening")
	var interior: ColorRect = art.canvas.get_node("RoomInterior")
	var frame: Rect2 = art.get_global_rect()
	var threshold: float = art.canvas.get_node("Threshold").get_global_rect().end.x
	var area: float = 0.0
	for id: String in ["Head", "Torso"]:
		var item: Polygon2D = art.figure.get_node(id)
		var poly: PackedVector2Array = _polygon(item)
		if not _fully_shown(item, frame) or _area(poly) <= 0.0 or _color(item).a < 0.95:
			return false
		for point: Vector2 in poly:
			if point.x < threshold or not opening.get_global_rect().has_point(point) or not c.main.get_viewport_rect().has_point(point):
				return false
		if _overlap(poly, _polygon(interior)) > 0.01:
			return false
		area += _overlap(poly, _polygon(opening))
	return area >= frame.get_area() * 0.01 and _distance(art.figure.get_node("Head").color, opening.color) > 0.2

func resize_matrix() -> bool:
	var previous: Vector2 = c.main.size
	var window: Window = c.main.get_window()
	var window_size: Vector2i = window.size
	var scaling: Vector2i = window.content_scale_size
	window.content_scale_size = Vector2i.ZERO
	var ok: bool = true
	for size: Vector2 in [Vector2(1280,720), Vector2(1600,900)]:
		window.size = Vector2i(size)
		c.main.size = size
		await c.main.get_tree().process_frame
		art._fit()
		ok = c.main.size.is_equal_approx(size) and c.main.get_viewport_rect().size.is_equal_approx(size) and phase_contract() and ok
		print("[SP-19] layout=%s" % JSON.stringify({"phase": ep.phase, "window": str(window.size), "viewport": str(c.main.get_viewport_rect()), "figure_visible": art.figure.visible}))
		c.main.show_page(&"MapPage")
		ok = phase_contract() and ok
		c.main.show_page(&"ScenePage")
		ok = phase_contract() and ok
	window.size = window_size
	window.content_scale_size = scaling
	c.main.size = previous
	await c.main.get_tree().process_frame
	art._fit()
	return ok

func text_fields(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node: Node in [root] + descendants(root):
		if node is Label or node is Button or node is RichTextLabel:
			out.append(node.text)
		if node is Control:
			out.append(node.tooltip_text)
			out.append(node.accessibility_name)
			out.append(node.accessibility_description)
	return out

static func banned(global_only: bool = false) -> Array[String]:
	var codes: Array = [[0x51c0,0x5316],[0x5929,0x7136,0x5171,0x9e23]]
	if not global_only:
		codes += [[0x72c2,0x60f3,0x75c7],[0x5931,0x58f0],[0x4fb5,0x8680],[0x8840,0x8109]]
	var out: Array[String] = []
	for row: Array in codes:
		var word: String = ""
		for code: int in row:
			word += String.chr(code)
		out.append(word)
	return out

func clean_words(texts: Array, global_only: bool = false) -> bool:
	for text: String in texts:
		for word: String in banned(global_only):
			if text.contains(word):
				return false
	return true

func permitted_ui() -> bool:
	var allowed: Array[String] = ["", "沙发", "斑的旧伤", "门", "还有没看过的地方。", "自动保存失败，正在重试。", "内容加载失败，请重试。"]
	for text: String in text_fields(room):
		if text not in allowed:
			print("[SP-19] unexpected_ui=%s" % text)
			return false
	return true

func no_extra_nodes() -> bool:
	if room.get_node("Objects").get_child_count() != 3 or room.find_children("*", "Button", true, false).size() != 3:
		return false
	for item: Node in [art] + descendants(art):
		if item is Button or item is CharacterBody2D or item is TileMapLayer:
			return false
		if item is Control and (item.focus_mode != Control.FOCUS_NONE or item.mouse_filter != Control.MOUSE_FILTER_IGNORE):
			return false
	for node: Node in descendants(room):
		var script: Script = node.get_script() as Script
		if script != null and script.resource_path == "res://scripts/map_grid.gd":
			return false
	return room.find_children("*", "CharacterBody2D", true, false).is_empty() and room.find_children("*", "TileMapLayer", true, false).is_empty()

func replace_and_observe(from: String, to: String, observations: Array) -> Error:
	observations.append(ep.phase == ep.Phase.LEFT and phase_contract() and not GameState.event_done(&"E14"))
	return DirAccess.rename_absolute(from, to)

func global_texts() -> Array[String]:
	var texts: Array[String] = []
	for entry: Dictionary in player.get_lines().values():
		texts.append(entry.text)
	for file: String in DirAccess.get_files_at("res://scenes/ui"):
		if file.ends_with(".tscn"):
			for line: String in FileAccess.get_file_as_string("res://scenes/ui/" + file).split("\n"):
				if line.begins_with("text = ") or line.begins_with("tooltip_text = ") or line.begins_with("accessibility_"):
					texts.append(line)
	return texts

func read_in_new_process(path: String) -> bool:
	var output: Array = []
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/sp19_readback_selftest.gd", "--", ProjectSettings.globalize_path(path)]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(output)
	return code == 0 and text.contains("SP19_READBACK_OK") and not text.contains("SCRIPT ERROR")

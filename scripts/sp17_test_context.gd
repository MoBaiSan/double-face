## SP-17隔离夹具与实际几何取数；不取屏幕像素，不改生产许可。
extends RefCounted
const C = preload("res://scripts/prologue_test_context.gd")
const S = C.S
const T176: String = "斑さん，下次不用挡得那么靠前。我可以自己判断。"
const T177: String = "那可不行。站在前面是我的工作。你要是受伤了，谁来对付那些麻烦的迷境？"
const T190: String = "斑的左肩有一道旧疤。"
var c: RefCounted
var room: Control
var exit_service: Node
var player: Control
var lines: Array = []
var receipts: Array = []
var finished: Array = []
var paths: Array[String] = []
var clean: bool = true
var serial: int = 0

func fresh(host: Control, initial: int = S.S6) -> void:
	if c != null:
		clean = await c.close() and clean
	c = C.new()
	await c.create(host, initial)
	room = c.flow.safe_room
	exit_service = c.flow.room_exit
	player = c.main._dialogue
	exit_service.set_process(false)
	serial += 1
	var path: String = "user://sp17_%d_%d.json" % [OS.get_process_id(), serial]
	paths.append(path)
	c.flow.checkpoint.path = path
	lines.clear()
	receipts.clear()
	finished.clear()
	c.watch(player.line_started, _line)
	c.watch(exit_service.exit_saved, func(run: int, receipt: Dictionary): receipts.append([run, receipt]))
	c.watch(c.flow.prologue_finished, func(): finished.append(true))

func _line(id: String) -> void:
	lines.append([id, player._speaker.text, player.get_visible_text()])

func ids() -> Array:
	return lines.map(func(row: Array): return row[0])

func button(id: String) -> Button:
	return room.get_node("Objects/" + id)

func click(id: String) -> void:
	c.click(button(id))

func key(code: Key) -> void:
	c.key(code, true)
	c.key(code, false)

func finish_reading() -> void:
	c.finish_sequence(player)

func complete_sofa() -> void:
	click("Sofa")
	finish_reading()
	click("Sofa")

func file_text() -> String:
	return FileAccess.get_file_as_string(c.flow.checkpoint.path)

func document() -> Dictionary:
	var data: Variant = JSON.parse_string(file_text())
	return data if data is Dictionary else {}

func close() -> void:
	if c != null:
		clean = await c.close() and clean
		c = null
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))

func descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(descendants(child))
	return found

func targets_clear() -> bool:
	var rects: Array[Rect2] = []
	var paper: Rect2 = room.get_node("PaperFrame").get_global_rect()
	for id: String in ["Sofa", "Scar", "Door"]:
		var rect: Rect2 = button(id).get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0 or not paper.encloses(rect):
			return false
		for other: Rect2 in rects:
			if rect.intersects(other):
				return false
		for bar: Control in [c.main._page_switch_bar, c.main._throat_placeholder]:
			if rect.intersects(bar.get_global_rect()):
				return false
		rects.append(rect)
	return true

func _area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(polygon.size()):
		total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(total) * 0.5

func _polygon(item: CanvasItem) -> PackedVector2Array:
	var raw: PackedVector2Array
	if item is Polygon2D:
		raw = item.polygon
	else:
		var box: Vector2 = item.size
		raw = PackedVector2Array([Vector2.ZERO, Vector2(box.x, 0), box, Vector2(0, box.y)])
	return item.get_global_transform() * raw

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for vertex: Vector2 in polygon:
		rect = rect.expand(vertex)
	return rect

func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var total: float = 0.0
	for part: PackedVector2Array in Geometry2D.intersect_polygons(a, b):
		total += _area(part)
	return total

func _color(item: CanvasItem) -> Color:
	var value: Color = item.color * item.self_modulate
	var current: Node = item
	while current is CanvasItem:
		value *= current.modulate
		current = current.get_parent()
	return value

func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

## 带符号片段保留布尔差集的孔洞；随后遮挡仍按同一真实多边形扣除。
func _visible_area(item: CanvasItem, later: Array) -> float:
	var pieces: Array = [{"p": _polygon(item), "sign": 1.0}]
	for blocker: CanvasItem in later:
		if not blocker.is_visible_in_tree() or _color(blocker).a < 0.95:
			continue
		var next: Array = []
		for piece: Dictionary in pieces:
			for part: PackedVector2Array in Geometry2D.clip_polygons(piece.p, _polygon(blocker)):
				var sign_value: float = -1.0 if Geometry2D.is_polygon_clockwise(part) else 1.0
				next.append({"p": part, "sign": piece.sign * sign_value})
		pieces = next
	var total: float = 0.0
	for piece: Dictionary in pieces:
		total += piece.sign * _area(piece.p)
	return absf(total)

func _fully_shown(item: CanvasItem, frame: Rect2) -> bool:
	if not item.is_visible_in_tree() or _color(item).a < 0.95 or item.material != null:
		return false
	if item is Polygon2D and item.texture != null:
		return false
	for point: Vector2 in _polygon(item):
		if not frame.grow(0.01).has_point(point):
			return false
		var parent: Node = item.get_parent()
		while parent is CanvasItem:
			if parent is Control and parent.clip_contents and not parent.get_global_rect().grow(0.01).has_point(point):
				return false
			if parent.material != null:
				return false
			parent = parent.get_parent()
	return true

func art_contract() -> bool:
	var art: Control = room.visual
	var frame: Rect2 = art.get_global_rect()
	var w: float = frame.size.x
	var height: float = frame.size.y
	if w < 900.0 or height < 450.0 or absf(w / height - 2.0) > 0.01:
		return false
	var root: Node = art.get_node("VisualRoot")
	if not root.get_node("Background") is ColorRect:
		return false
	var shapes: Dictionary = {}
	for id: String in ["BanHead", "BanTorso", "KohakuHead", "KohakuTorso", "ShoulderPatch", "UpperArm", "Forearm", "Hand", "Bandage"]:
		var node: Node = root.get_node_or_null(id)
		if not node is Polygon2D or node.polygon.size() < (6 if id.ends_with("Head") else 4):
			return false
		if not _fully_shown(node, frame):
			return false
		shapes[id] = _polygon(node)
	if not _figures(shapes, w, height) or not _contacts(shapes, w * height):
		return false
	return _art_visibility(root, shapes, w * height)

func _figures(shapes: Dictionary, w: float, height: float) -> bool:
	var a: Rect2 = _bounds(shapes.BanHead)
	var b: Rect2 = _bounds(shapes.KohakuHead)
	if absf(a.get_center().x - b.get_center().x) < 0.20 * w:
		return false
	for prefix: String in ["Ban", "Kohaku"]:
		var head: Rect2 = _bounds(shapes[prefix + "Head"])
		var body: Rect2 = _bounds(shapes[prefix + "Torso"])
		if head.size.x < 0.05*w or head.size.y < 0.07*height or _area(shapes[prefix+"Head"]) < 0.002*w*height:
			return false
		if body.size.x < 0.12*w or body.size.y < 0.20*height or _area(shapes[prefix+"Torso"]) < 0.025*w*height:
			return false
		if body.position.y - head.end.y > 0.04 * height:
			return false
	return true

func _contacts(p: Dictionary, area: float) -> bool:
	if _area(p.Hand) < 0.001*area or _area(p.Bandage) < 0.0005*area:
		return false
	for row: Array in [["ShoulderPatch", "BanTorso", 0.50], ["Hand", "ShoulderPatch", 0.15], ["Bandage", "ShoulderPatch", 0.50]]:
		if _overlap(p[row[0]], p[row[1]]) < row[2] * _area(p[row[0]]):
			return false
	return _overlap(p.UpperArm, p.KohakuTorso) > 0.0 and _overlap(p.Forearm, p.UpperArm) > 0.0 and _overlap(p.Forearm, p.Hand) > 0.0

func _art_visibility(root: Node, polygons: Dictionary, area: float) -> bool:
	var nodes: Array = root.get_children()
	var palette: Array = []
	for i: int in range(1, nodes.size()):
		var item: CanvasItem = nodes[i]
		var visible_area: float = _visible_area(item, nodes.slice(i + 1))
		var color: Color = _color(item)
		var group: int = -1
		for index: int in range(palette.size()):
			if _distance(palette[index].color, color) < 0.20:
				group = index
		if group < 0:
			palette.append({"color": color, "area": visible_area})
		else:
			palette[group].area += visible_area
		if String(item.name) in ["BanHead", "BanTorso", "KohakuHead", "KohakuTorso", "Hand", "Bandage"]:
			var minimum: float = 0.30 if item.name in [&"Hand", &"Bandage"] else 0.60
			if visible_area < minimum * _area(polygons[String(item.name)]):
				return false
	var colors: int = palette.filter(func(group: Dictionary): return group.area >= 0.001 * area).size()
	var shoulder: Color = _color(root.get_node("ShoulderPatch"))
	return colors >= 3 and _distance(shoulder, _color(root.get_node("Background"))) >= 0.25 and _distance(shoulder, _color(root.get_node("Hand"))) >= 0.20 and _distance(shoulder, _color(root.get_node("Bandage"))) >= 0.35

func page_inputs() -> bool:
	for index: int in [1, 2, 0]:
		c.click(c.main._page_switch_bar._buttons[index])
		if c.main._current_page != [&"ScenePage", &"MapPage", &"BattlePage"][index]:
			return false
	key(KEY_PAGEDOWN)
	var moved: bool = c.main._current_page == &"MapPage"
	key(KEY_PAGEUP)
	return moved and c.main._current_page == &"ScenePage" and GameState.state == S.S6

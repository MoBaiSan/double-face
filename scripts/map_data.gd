extends RefCounted

class_name MapData
const POINT_FIELDS: Array[StringName] = [
	&"id", &"display_name", &"grid", &"color", &"surveyable", &"survey_kind", &"edges"]
## Vector2i 的边界先在原数值上验证，禁止截断小数后再判合法。
const MAX_GRID_SIZE: int = 2147483647
var grid_size: Vector2i = Vector2i.ZERO
var start_id: StringName = &""
var used_fallback: bool = false
var visual: Dictionary = {}
var points: Dictionary = {}

static func from_dictionary(raw: Variant, fallback_start_id: StringName = &""):
	if not raw is Dictionary:
		push_error("地图根必须是字典")
		return null
	var result = new()
	if not result._load(raw, fallback_start_id):
		return null
	return result

static func validate_dictionary(raw: Variant) -> bool:
	return from_dictionary(raw) != null

func _load(raw: Dictionary, fallback_start_id: StringName = &"") -> bool:
	if not _read_header(raw):
		return false
	for point: Variant in raw["points"]:
		if not _read_point(point):
			return false
	if not _validate_edges():
		return false
	start_id = StringName(str(raw.get("start_id", "")))
	if not points.has(start_id):
		var fallback: StringName = fallback_start_id if fallback_start_id != &"" else &"entry_exit"
		if not points.has(fallback):
			push_error("地图起点不存在：%s" % start_id)
			return false
		used_fallback = true
		if fallback_start_id == &"":
			push_warning("MapData start_id 缺失或不存在，回落 entry_exit")
		start_id = fallback
	return true

func _read_header(raw: Dictionary) -> bool:
	if not raw.has("grid_size") or not raw.has("points"):
		push_error("地图数据缺少必填字段")
		return false
	if not raw["points"] is Array or not raw.get("visual", {}) is Dictionary:
		push_error("地图点列表必须是数组，视觉参数必须是字典")
		return false
	var grid: Variant = raw["grid_size"]
	if not grid is Array or grid.size() != 2:
		push_error("地图网格尺寸必须包含两个值")
		return false
	if not _integer_in_range(grid[0], 1, MAX_GRID_SIZE) or not _integer_in_range(grid[1], 1, MAX_GRID_SIZE):
		push_error("地图网格尺寸必须是范围内的正整数")
		return false
	grid_size = Vector2i(int(grid[0]), int(grid[1]))
	visual = raw.get("visual", {}).duplicate(true)
	return true

static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value == floor(float(value)) and value >= minimum and value <= maximum

func _read_point(raw: Variant) -> bool:
	if not raw is Dictionary:
		push_error("地图点必须是字典")
		return false
	for field: StringName in POINT_FIELDS:
		if not raw.has(field):
			push_error("地图点缺少必填字段：%s" % field)
			return false
	var color: String = str(raw["color"])
	if color not in ["plain", "black", "blue", "white"]:
		push_error("MapData 点颜色无效：%s" % color)
		return false
	var id := StringName(str(raw["id"]))
	if id == &"" or points.has(id):
		push_error("地图点 id 为空或重复：%s" % id)
		return false
	var grid: Variant = raw["grid"]
	if not grid is Array or grid.size() != 2:
		push_error("地图点坐标必须包含两个值：%s" % id)
		return false
	if not _integer_in_range(grid[0], 0, grid_size.x - 1) or not _integer_in_range(grid[1], 0, grid_size.y - 1):
		push_error("地图点坐标必须是范围内的整数：%s" % id)
		return false
	var point: Dictionary = raw.duplicate(true)
	point["grid"] = [int(grid[0]), int(grid[1])]
	points[id] = point
	return true

func _validate_edges() -> bool:
	for id: StringName in points:
		var edges: Variant = points[id]["edges"]
		if not edges is Array:
			push_error("地图边必须是数组：%s" % id)
			return false
		for edge: Variant in edges:
			var target := StringName(str(edge))
			if not points.has(target):
				push_error("地图边目标不存在：%s -> %s" % [id, target])
				return false
	return true

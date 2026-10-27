extends RefCounted

class_name MapData

const POINT_FIELDS: Array[StringName] = [
	&"id", &"display_name", &"grid", &"color", &"surveyable", &"survey_kind", &"edges"]

var grid_size: Vector2i = Vector2i.ZERO
var start_id: StringName = &""
var visual: Dictionary = {}
var points: Dictionary = {}

static func from_dictionary(raw: Dictionary, fallback_start_id: StringName = &""):
	var result = new()
	if not result._load(raw, fallback_start_id):
		return null
	return result

static func validate_dictionary(raw: Dictionary) -> bool:
	return from_dictionary(raw) != null

func _load(raw: Dictionary, fallback_start_id: StringName = &"") -> bool:
	var valid := true
	for field: StringName in [&"grid_size", &"points"]:
		if not raw.has(field):
			push_error("地图数据缺少必填字段：%s" % field)
			valid = false
	if not valid:
		return false
	var raw_grid: Variant = raw.get("grid_size")
	if not raw_grid is Array or (raw_grid as Array).size() != 2:
		push_error("地图网格尺寸必须包含两个值")
		return false
	var grid_array: Array = raw_grid as Array
	grid_size = Vector2i(int(grid_array[0]), int(grid_array[1]))
	if grid_size.x <= 0 or grid_size.y <= 0:
		push_error("地图网格尺寸必须大于零")
		return false
	start_id = StringName(str(raw.get("start_id", "")))
	visual = raw.get("visual", {}) as Dictionary
	var raw_points: Variant = raw.get("points")
	if not raw_points is Array:
		push_error("地图点列表必须是数组")
		return false
	for point_variant: Variant in raw_points as Array:
		if not point_variant is Dictionary:
			push_error("地图点必须是字典")
			valid = false
			continue
		var point: Dictionary = point_variant as Dictionary
		for field: StringName in POINT_FIELDS:
			if not point.has(field):
				push_error("地图点缺少必填字段：%s" % field)
				valid = false
		var point_color: String = str(point.get("color", ""))
		if not ["plain", "black", "blue", "white"].has(point_color):
			push_error("MapData 点颜色无效：%s" % point_color)
			valid = false
		var point_id := StringName(str(point.get("id", "")))
		if point_id == &"":
			push_error("地图点 id 不能为空")
			valid = false
		elif points.has(point_id):
			push_error("地图点 id 重复：%s" % point_id)
			valid = false
		else:
			points[point_id] = point
		var point_grid: Variant = point.get("grid", [])
		if not point_grid is Array or (point_grid as Array).size() != 2:
			push_error("地图点坐标必须包含两个值：%s" % point_id)
			valid = false
		elif int((point_grid as Array)[0]) < 0 or int((point_grid as Array)[0]) >= grid_size.x \
			or int((point_grid as Array)[1]) < 0 or int((point_grid as Array)[1]) >= grid_size.y:
			push_error("地图点坐标越界：%s" % point_id)
			valid = false
	for point_id: StringName in points:
		var point: Dictionary = points[point_id] as Dictionary
		var edges: Variant = point.get("edges", [])
		if not edges is Array:
			push_error("地图边必须是数组：%s" % point_id)
			valid = false
			continue
		for edge_variant: Variant in edges as Array:
			var edge_id := StringName(str(edge_variant))
			if not points.has(edge_id):
				push_error("地图边目标不存在：%s -> %s" % [point_id, edge_id])
				valid = false
	if not points.has(start_id):
		var fallback: StringName = fallback_start_id if fallback_start_id != &"" else &"entry_exit"
		if points.has(fallback):
			if fallback_start_id == &"":
				push_warning("MapData start_id 缺失或不存在，回落 entry_exit")
			start_id = fallback
		else:
			push_error("地图起点不存在：%s" % start_id)
			valid = false
	return valid

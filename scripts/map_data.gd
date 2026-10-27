extends RefCounted

class_name MapData

const POINT_FIELDS: Array[StringName] = [
	&"id", &"display_name", &"grid", &"color", &"surveyable", &"survey_kind", &"edges"]

var grid_size: Vector2i = Vector2i.ZERO
var start_id: StringName = &""
var visual: Dictionary = {}
var points: Dictionary = {}

static func from_dictionary(raw: Dictionary):
	var result = new()
	if not result._load(raw):
		return null
	return result

static func validate_dictionary(raw: Dictionary) -> bool:
	return from_dictionary(raw) != null

func _load(raw: Dictionary) -> bool:
	var valid := true
	for field: StringName in [&"grid_size", &"start_id", &"points"]:
		if not raw.has(field):
			push_error("MapData missing required field: %s" % field)
			valid = false
	if not valid:
		return false
	var raw_grid: Variant = raw.get("grid_size")
	if not raw_grid is Array or (raw_grid as Array).size() != 2:
		push_error("MapData grid_size must contain two values")
		return false
	var grid_array: Array = raw_grid as Array
	grid_size = Vector2i(int(grid_array[0]), int(grid_array[1]))
	if grid_size.x <= 0 or grid_size.y <= 0:
		push_error("MapData grid_size must be positive")
		return false
	start_id = StringName(str(raw.get("start_id", "")))
	visual = raw.get("visual", {}) as Dictionary
	var raw_points: Variant = raw.get("points")
	if not raw_points is Array:
		push_error("MapData points must be an array")
		return false
	for point_variant: Variant in raw_points as Array:
		if not point_variant is Dictionary:
			push_error("MapData point must be a Dictionary")
			valid = false
			continue
		var point: Dictionary = point_variant as Dictionary
		for field: StringName in POINT_FIELDS:
			if not point.has(field):
				push_error("MapData point missing required field: %s" % field)
				valid = false
		var point_id := StringName(str(point.get("id", "")))
		if point_id == &"":
			push_error("MapData point id must not be empty")
			valid = false
		elif points.has(point_id):
			push_error("MapData duplicate point id: %s" % point_id)
			valid = false
		else:
			points[point_id] = point
		var point_grid: Variant = point.get("grid", [])
		if not point_grid is Array or (point_grid as Array).size() != 2:
			push_error("MapData point grid must contain two values: %s" % point_id)
			valid = false
		elif int((point_grid as Array)[0]) < 0 or int((point_grid as Array)[0]) >= grid_size.x \
			or int((point_grid as Array)[1]) < 0 or int((point_grid as Array)[1]) >= grid_size.y:
			push_error("MapData point grid out of bounds: %s" % point_id)
			valid = false
	for point_id: StringName in points:
		var point: Dictionary = points[point_id] as Dictionary
		var edges: Variant = point.get("edges", [])
		if not edges is Array:
			push_error("MapData edges must be an array: %s" % point_id)
			valid = false
			continue
		for edge_variant: Variant in edges as Array:
			var edge_id := StringName(str(edge_variant))
			if not points.has(edge_id):
				push_error("MapData edge target missing: %s -> %s" % [point_id, edge_id])
				valid = false
	if not points.has(start_id):
		push_error("MapData start_id does not exist: %s" % start_id)
		valid = false
	return valid

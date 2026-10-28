## 地图只负责接线与文字框；可点、已读、扣点与重复确认都由共用组件处理。
extends RefCounted

signal investigated(point_id: StringName)
signal repeated(point_id: StringName)

const INTERACTABLE = preload("res://scripts/interactable.gd")
var _map: Control
var _items: Dictionary = {}
var _narration: Control
var _text: Label
var _hovered: StringName = &""

func _init(map: Control) -> void:
	_map = map
	_narration = map.get_node("../../../InvestigationText")
	_text = _narration.get_node("Margin/Text")
	_map.moved.connect(_on_moved)
	_map.resized.connect(sync)

func reset() -> void:
	for item: Control in _items.values():
		item.free()
	_items.clear()
	_narration.hide()
	for point_id: StringName in _map._points:
		var point: Dictionary = _map._points[point_id]
		if not bool(point.get("surveyable", false)):
			continue
		var item = INTERACTABLE.new()
		item.hint_key = &"investigate"
		item.cost_kind = StringName(point.get("survey_kind", ""))
		item.size = Vector2.ONE * (_map._float_visual("point_radius") * 2.0 + 4.0)
		item.activated.connect(_on_investigated.bind(point_id))
		item.repeated.connect(_on_repeated.bind(point_id))
		_items[point_id] = item
		_map.add_child(item)
	_hovered = &""
	sync()

func get_interactable(point_id: StringName) -> Control:
	return _items.get(point_id) as Control

func sync() -> void:
	for point_id: StringName in _items:
		var item: Control = _items[point_id]
		item.position = _map._point_position(point_id) - item.size * 0.5
		item.visible = _map._revealed.has(point_id)
		item.active = point_id == _hovered or point_id == _map.get_pending_node_id()
	_map.queue_redraw()

func hover_at(local_position: Vector2) -> void:
	_hovered = &""
	for point_id: StringName in _items:
		var item: Control = _items[point_id]
		if item.visible and item.get_rect().has_point(local_position):
			_hovered = point_id
			break
	sync()

func confirm_current() -> bool:
	var item = get_interactable(_map.get_current_node_id())
	if item == null:
		return false
	item.activate()
	_map.queue_redraw()
	return true

func click_current(local_position: Vector2) -> bool:
	var item = get_interactable(_map.get_current_node_id())
	if item == null or not item.get_rect().has_point(local_position):
		return false
	return confirm_current()

func get_labels() -> Array[Dictionary]:
	var labels: Array[Dictionary] = []
	var point_id: StringName = _hovered if _hovered != &"" else _map.get_current_node_id()
	var item = get_interactable(point_id)
	if item != null and item.visible:
		var hint: String = item.get_hint_text()
		if not hint.is_empty():
			labels.append({"text": hint, "position": item.position + Vector2(item.size.x + 5.0, 0.0)})
	return labels

func _on_investigated(point_id: StringName) -> void:
	_text.text = INTERACTABLE.text_for(str(point_id))
	_narration.show()
	investigated.emit(point_id)
	_map.queue_redraw()

func _on_repeated(point_id: StringName) -> void:
	_narration.hide()
	repeated.emit(point_id)
	_map.queue_redraw()

func _on_moved(_from_id: StringName, _to_id: StringName, _steps: int) -> void:
	_narration.hide()
	_hovered = &""
	sync()

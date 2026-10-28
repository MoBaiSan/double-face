## 页面共用的候选导航与描边表现；由页面场景持有，不依赖剧情或地图逻辑。
## 通过共用组件成功确认后才发业务信号；重复确认不会再次发出。
extends Control

signal confirmed(node: Control)
signal reading_requested(node: Control)

const SELECTABLE_GROUP: StringName = &"selectable"
const FORWARD_EPSILON: float = 0.01
const CROSS_AXIS_WEIGHT: float = 4.0
const ACTION_DIRECTIONS: Dictionary = {
	&"ui_left": Vector2.LEFT, &"ui_right": Vector2.RIGHT,
	&"ui_up": Vector2.UP, &"ui_down": Vector2.DOWN,
}

@export var selectable_root: NodePath = NodePath("..")

@onready var _scope: Node = get_node_or_null(selectable_root)

var _candidates: Array[Control] = []
var _outlines: Dictionary = {}
var _progress_notice: Label
var _selected: Control = null
var reading: bool = false


const SelectionOutline = preload("res://scripts/interactable.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _scope == null:
		push_error("PageNav 的候选范围不存在。")
		set_process(false)
		return
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_on_layout_changed)
	_sync_candidates()
	_progress_notice = Label.new()
	_progress_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_notice.position = Vector2(64.0, 648.0)
	_progress_notice.add_theme_color_override("font_color", Color("777777"))
	_progress_notice.add_theme_font_size_override("font_size", 18)
	add_child(_progress_notice)
	_refresh_progress_notice()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh_candidates()


func _on_layout_changed() -> void:
	_sync_outline_rects()


func refresh_candidates() -> void:
	if not is_visible_in_tree():
		return
	_sync_candidates()


func _on_node_added(node: Node) -> void:
	if node is Control and _scope != null and _scope.is_ancestor_of(node):
		_connect_visibility(node as Control)
	refresh_candidates()


func _on_candidate_visibility_changed(_node: Node) -> void:
	if is_visible_in_tree():
		refresh_candidates()


## 仅自身在可见树且启用输入时处理并吞键；隐藏或停用时原样返回。
func _input(event: InputEvent) -> void:
	if reading or not is_visible_in_tree() or not is_processing_input():
		return
	_sync_candidates()
	if _candidates.is_empty():
		return
	# 在 GUI 消费事件前统一处理，Button 等原生控件也遵守相同确认语义。
	for action: StringName in ACTION_DIRECTIONS:
		if event.is_action_pressed(action):
			move_selection(ACTION_DIRECTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"ui_accept"):
		confirm_selection()
		get_viewport().set_input_as_handled()


## 将范围内的 Control 标为候选；无返回值，重复注册不会重复连接。
func register_selectable(node: Control) -> void:
	if not is_instance_valid(node):
		return
	node.add_to_group(SELECTABLE_GROUP)
	_sync_candidates()


## 取消可选标记并更新当前选择；无返回值。
func unregister_selectable(node: Control) -> void:
	if not is_instance_valid(node):
		return
	_disconnect_candidate(node)
	node.remove_from_group(SELECTABLE_GROUP)
	_sync_candidates()


## 返回当前有效候选的副本，调用方不能改写导航持有的列表。
func get_candidates() -> Array[Control]:
	_sync_candidates()
	return _candidates.duplicate()


## 返回当前候选；页面没有可选项时返回 null。
func get_selected() -> Control:
	_sync_candidates()
	return _selected


## 按页面空间方向移动选择，边界外没有候选时保持原项；无返回值。
func move_selection(direction: Vector2) -> void:
	_sync_candidates()
	if _selected == null or direction.is_zero_approx():
		return
	var axis: Vector2 = direction.normalized()
	var origin: Vector2 = _selected.get_global_rect().get_center()
	var next: Control = null
	var best_score: float = INF
	for node: Control in _candidates:
		var offset: Vector2 = node.get_global_rect().get_center() - origin
		var forward: float = offset.dot(axis)
		if forward <= FORWARD_EPSILON:
			continue
		var score: float = forward + absf(offset.cross(axis)) * CROSS_AXIS_WEIGHT
		if score < best_score:
			best_score = score
			next = node
	if next != null:
		_select(next)


## 共用组件接受首次交互后发出确认信号；阅读文本与翻页仍由接收方处理。
func confirm_selection() -> void:
	_sync_candidates()
	if _selected == null or reading:
		return
	var interaction = get_interactable(_selected)
	if interaction == null:
		return
	if interaction.progression and not interaction.read:
		reading_requested.emit(_selected)
	elif interaction.activate():
		confirmed.emit(_selected)


## 同步共用组件的已读状态，不维护第二份已读字典。
func mark_used(node: Control, used: bool = true) -> void:
	if not is_instance_valid(node) or not _candidates.has(node):
		return
	var interaction = get_interactable(node)
	if interaction != null:
		interaction.set_read(used)


func _is_eligible(node: Control) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if not is_instance_valid(_scope) or not _scope.is_ancestor_of(node):
		return false
	if not node.is_visible_in_tree():
		return false
	return not (node is BaseButton and (node as BaseButton).disabled)


func _sync_candidates() -> void:
	if not is_inside_tree() or not is_instance_valid(_scope):
		return
	var fresh: Array[Control] = []
	for node: Node in get_tree().get_nodes_in_group(SELECTABLE_GROUP):
		if node is Control and _is_eligible(node as Control):
			_connect_visibility(node as Control)
			fresh.append(node as Control)
	fresh.sort_custom(_comes_before)
	if fresh == _candidates:
		return
	_candidates = fresh
	var fresh_ids: Array[int] = []
	for node: Control in _candidates:
		fresh_ids.append(node.get_instance_id())
		if not _outlines.has(node.get_instance_id()):
			_add_outline(node)
	for identity: int in _outlines.keys():
		if not fresh_ids.has(identity):
			var outline: SelectionOutline = _outlines[identity] as SelectionOutline
			var candidate: Control = outline.candidate.get_ref() as Control if outline != null else null
			if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and _scope.is_ancestor_of(candidate):
				continue
			_release_outline(identity)
	if not is_instance_valid(_selected) or not _candidates.has(_selected):
		_selected = _candidates[0] if not _candidates.is_empty() else null
	_refresh_outlines()
	_sync_outline_rects()


func _add_outline(node: Control) -> void:
	var outline: SelectionOutline = SelectionOutline.new()
	outline.candidate = weakref(node)
	outline.hint_key = StringName(node.get_meta("hint_key", ""))
	outline.progression = bool(node.get_meta("progression", false))
	outline.state_changed.connect(_refresh_progress_notice)
	# 放在导航层，避免覆盖层被候选自身的 Container 当作额外布局元素。
	add_child(outline)
	_outlines[node.get_instance_id()] = outline
	if not node.mouse_entered.is_connected(_on_hover.bind(node)):
		node.mouse_entered.connect(_on_hover.bind(node))
	if not node.gui_input.is_connected(_on_candidate_input.bind(node)):
		node.gui_input.connect(_on_candidate_input.bind(node))
	if not node.resized.is_connected(_on_layout_changed):
		node.resized.connect(_on_layout_changed)


func _connect_visibility(node: Control) -> void:
	var callback: Callable = _on_candidate_visibility_changed.bind(node)
	if not node.visibility_changed.is_connected(callback):
		node.visibility_changed.connect(callback)


func _release_outline(identity: int) -> void:
	var outline: SelectionOutline = _outlines[identity] as SelectionOutline
	if is_instance_valid(outline):
		var node: Control = outline.candidate.get_ref() as Control
		if node != null:
			_disconnect_candidate(node)
		outline.queue_free()
	_outlines.erase(identity)


func _disconnect_candidate(node: Control) -> void:
	var hover: Callable = _on_hover.bind(node)
	var clicked: Callable = _on_candidate_input.bind(node)
	if node.mouse_entered.is_connected(hover):
		node.mouse_entered.disconnect(hover)
	if node.gui_input.is_connected(clicked):
		node.gui_input.disconnect(clicked)
	if node.resized.is_connected(_on_layout_changed):
		node.resized.disconnect(_on_layout_changed)
	var visibility: Callable = _on_candidate_visibility_changed.bind(node)
	if node.visibility_changed.is_connected(visibility):
		node.visibility_changed.disconnect(visibility)


func _refresh_outlines() -> void:
	for node: Control in _candidates:
		var outline: SelectionOutline = _outlines[node.get_instance_id()] as SelectionOutline
		if outline == null:
			continue
		outline.active = node == _selected
		outline.queue_redraw()
	_refresh_progress_notice()


func _sync_outline_rects() -> void:
	for node: Control in _candidates:
		var outline: SelectionOutline = _outlines[node.get_instance_id()] as SelectionOutline
		if outline == null:
			continue
		var relative: Transform2D = get_global_transform().affine_inverse()
		relative *= node.get_global_transform()
		outline.position = relative.origin
		outline.rotation = relative.get_rotation()
		outline.scale = relative.get_scale()
		outline.size = node.size


func _select(node: Control) -> void:
	if not _candidates.has(node):
		return
	_selected = node
	_refresh_outlines()


func _on_hover(node: Control) -> void:
	_select(node)


func _on_candidate_input(event: InputEvent, node: Control) -> void:
	_sync_candidates()
	if not _candidates.has(node):
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_select(node)
			confirm_selection()
			node.accept_event()


func _on_node_removed(node: Node) -> void:
	if node.is_in_group(SELECTABLE_GROUP):
		refresh_candidates()


func _comes_before(first: Control, second: Control) -> bool:
	# 候选组不承诺顺序，默认项因此显式服从场景树中的页面顺序。
	return second.is_greater_than(first)

## 返回同一个交互组件；页面控制器只提供阅读完成状态，不另存一套已读。
func get_interactable(node: Control) -> Control:
	return _outlines.get(node.get_instance_id()) as Control

func _refresh_progress_notice() -> void:
	if not is_instance_valid(_progress_notice):
		return
	var pending: bool = false
	var selected_item = get_interactable(_selected) if is_instance_valid(_selected) else null
	if selected_item != null and selected_item.progression:
		pending = not selected_item.read
	else:
		for interaction: Control in _outlines.values():
			pending = pending or (interaction.progression and not interaction.read)
	_progress_notice.text = SelectionOutline.text_for("progress_pending") if pending else ""
	_progress_notice.visible = pending

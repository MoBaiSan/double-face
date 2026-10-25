## 页面共用的候选导航与描边表现；由页面场景持有，不依赖剧情或地图逻辑。
## 确认只发信号，已使用标记由接收方决定何时调用。
extends Control

signal confirmed(node: Control)

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
var _used_ids: Dictionary = {}
var _selected: Control = null


class SelectionOutline extends Control:
	const OUTLINE_PX: int = 1
	const DARK: Color = Color("443b2c")
	const BRIGHT: Color = Color("fff9e5")
	const USED_SHADE: Color = Color(0.34, 0.34, 0.34, 0.48)
	const CHECK_MARGIN: float = 24.0
	const CHECK_WIDTH: float = 2.0
	const CHECK_BEND: Vector2 = Vector2(5.0, 5.0)
	const CHECK_END: Vector2 = Vector2(14.0, -5.0)
	var active: bool = false
	var used: bool = false
	var candidate: WeakRef
	var _border: StyleBoxFlat = StyleBoxFlat.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_border.bg_color = Color.TRANSPARENT
		_border.set_border_width_all(OUTLINE_PX)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var bounds: Rect2 = Rect2(Vector2.ZERO, size)
		if used:
			draw_rect(bounds, USED_SHADE)
		# StyleBox 的边框向内绘制，不改变候选本身的容器尺寸。
		_border.border_color = BRIGHT if active else DARK
		draw_style_box(_border, bounds)
		if used:
			var start: Vector2 = Vector2(size.x - CHECK_MARGIN, size.y * 0.5)
			draw_line(start, start + CHECK_BEND, DARK, CHECK_WIDTH)
			draw_line(start + CHECK_BEND, start + CHECK_END, DARK, CHECK_WIDTH)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _scope == null:
		push_error("PageNav 的候选范围不存在。")
		set_process(false)
		return
	get_tree().node_removed.connect(_on_node_removed)
	_sync_candidates()


func _process(_delta: float) -> void:
	_sync_candidates()
	_sync_outline_rects()


func _input(event: InputEvent) -> void:
	_sync_candidates()
	if not is_visible_in_tree() or _candidates.is_empty():
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


## 仅发出当前候选的确认信号，不读取文本、不翻页、不代替接收方完成业务。
func confirm_selection() -> void:
	_sync_candidates()
	if _selected != null:
		confirmed.emit(_selected)


## 只设置灰底与勾的表现；由信号接收者决定调用时机，无返回值。
func mark_used(node: Control, used: bool = true) -> void:
	if not is_instance_valid(node) or not _candidates.has(node):
		return
	_used_ids[node.get_instance_id()] = used
	_refresh_outlines()


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
			_release_outline(identity)
	if not is_instance_valid(_selected) or not _candidates.has(_selected):
		_selected = _candidates[0] if not _candidates.is_empty() else null
	_refresh_outlines()
	_sync_outline_rects()


func _add_outline(node: Control) -> void:
	var outline: SelectionOutline = SelectionOutline.new()
	outline.candidate = weakref(node)
	# 放在导航层，避免覆盖层被候选自身的 Container 当作额外布局元素。
	add_child(outline)
	_outlines[node.get_instance_id()] = outline
	if not node.mouse_entered.is_connected(_on_hover.bind(node)):
		node.mouse_entered.connect(_on_hover.bind(node))
	if not node.gui_input.is_connected(_on_candidate_input.bind(node)):
		node.gui_input.connect(_on_candidate_input.bind(node))


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


func _refresh_outlines() -> void:
	for node: Control in _candidates:
		var outline: SelectionOutline = _outlines[node.get_instance_id()] as SelectionOutline
		if outline == null:
			continue
		outline.active = node == _selected
		outline.used = bool(_used_ids.get(node.get_instance_id(), false))
		outline.queue_redraw()


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
	_used_ids.erase(node.get_instance_id())


func _comes_before(first: Control, second: Control) -> bool:
	# 候选组不承诺顺序，默认项因此显式服从场景树中的页面顺序。
	return second.is_greater_than(first)

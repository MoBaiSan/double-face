## 七点调查只编排既有播放器与共用已读组件，不另算费用或复制状态。
extends Node

signal progress_changed(value: int)

const DATA_PATH: String = "res://data/points.json"
const DIALOGUE_SCENE: PackedScene = preload("res://scenes/ui/DialogueBox.tscn")
const LINE_KEYS: Dictionary = {
	"p1": "T134", "p2": "T136", "p3": "T137", "p4": "T139",
	"p5": "T142", "p6": "T144", "p7": "T145",
}
const MAP_IDS: Dictionary = {
	&"point1": "p1", &"point2": "p2", &"point3": "p3", &"point4": "p4",
	&"point5": "p5", &"point6": "p6", &"point7": "p7",
}
var _main: Control
var _map: Control
var _page: Control
var _story: Control
var _dialogue: Control
var _interactions: RefCounted
var _definitions: Dictionary = {}
var _valid: bool = false
var _pending_map_id: StringName = &""
var _pending_item: WeakRef
var _pending_run: int = -1
var last_error: String = ""

func configure(main: Control, story: Control) -> void:
	name = &"Points"
	_main = main
	_story = story
	_page = main.get_node("Pages/MapPage")
	_map = _page.get_node("MapArea/CursorContainer/MapGrid")
	_dialogue = DIALOGUE_SCENE.instantiate()
	_dialogue.name = &"InvestigationDialogue"
	add_child(_dialogue)
	_configure_layout()
	_valid = _load_points()
	_dialogue.sequence_finished.connect(_on_dialogue_finished)
	_interactions = _map._interactions
	_interactions.request_investigation = investigate
	_interactions.investigated.connect(_on_investigated)
	_page.visibility_changed.connect(_on_visibility_changed)
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_user_args().has("--sp09-self-test"):
		call_deferred("_run_self_test")

func _configure_layout() -> void:
	var panel: PanelContainer = _dialogue.get_node("Panel")
	panel.anchor_right = panel.anchor_left
	panel.offset_right = 408.0
	var body: RichTextLabel = _dialogue.get_node("Panel/Margin/TextLayout/Body")
	body.scroll_active = true

func _load_points() -> bool:
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return _reject("无法读取调查点数据")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _reject("调查点 JSON 解析失败：%s" % json.get_error_message())
	var error: String = validate_data(json.data, _dialogue.get_lines())
	if not error.is_empty():
		return _reject(error)
	for entry: Dictionary in json.data:
		_definitions[str(entry["id"])] = entry.duplicate(true)
	return true

static func validate_data(data: Variant, source_lines: Dictionary) -> String:
	if not data is Array:
		return "调查点根必须是数组"
	if data.size() != 7:
		return "调查点条数必须为 7"
	var seen: Dictionary = {}
	for entry: Variant in data:
		var error: String = _validate_entry(entry, source_lines)
		if not error.is_empty():
			return error
		var id: String = str(entry["id"])
		if seen.has(id):
			return "调查点 id 重复：%s" % id
		seen[id] = true
	return ""

static func _validate_entry(entry: Variant, source_lines: Dictionary) -> String:
	if not entry is Dictionary:
		return "调查点条目必须是对象"
	for field: String in ["id", "kind", "cost", "lines", "progress"]:
		if not entry.has(field):
			return "调查点缺少字段：%s" % field
	if not entry["id"] is String or not LINE_KEYS.has(entry["id"]):
		return "调查点 id 不在 p1…p7 中"
	var id: String = entry["id"]
	var required: bool = id not in ["p6", "p7"]
	var expected_kind: String = "must" if required else "optional"
	if not entry["kind"] is String or entry["kind"] != expected_kind:
		return "调查点 kind 非法：%s" % id
	if not (entry["cost"] is int or entry["cost"] is float):
		return "调查点 cost 必须是数值：%s" % id
	if entry["cost"] != GameState.get_point_cost(GameState.REQUIRED_KIND if required else GameState.OPTIONAL_KIND):
		return "调查点 cost 与 kind 不一致：%s" % id
	if not entry["progress"] is bool or entry["progress"] != required:
		return "调查点 progress 与必查/可选不一致：%s" % id
	if not entry["lines"] is String or str(entry["lines"]).strip_edges().is_empty():
		return "调查点正文为空或类型非法：%s" % id
	var source: Variant = source_lines.get(LINE_KEYS[id])
	if not source is Dictionary or source.get("text") != entry["lines"] or source.get("mode") != "read":
		return "调查点正文与 lines.json 不一致：%s" % id
	return ""

func _reject(reason: String) -> bool:
	last_error = reason
	push_error("[Points] %s" % reason)
	return false

func get_definitions() -> Dictionary:
	return _definitions.duplicate(true)

func get_dialogue() -> Control:
	return _dialogue

func get_progress_count() -> int:
	var count: int = 0
	for map_id: StringName in MAP_IDS:
		var entry: Dictionary = _definitions.get(MAP_IDS[map_id], {})
		var item: Control = _map.get_interactable(map_id)
		if bool(entry.get("progress", false)) and item != null and item.read:
			count += 1
	return count

func investigate(map_id: StringName) -> bool:
	if not GameState.can_investigate():
		return false
	_pending_run = GameState.run_id
	var id: String = str(MAP_IDS.get(map_id, ""))
	var item: Control = _map.get_interactable(map_id)
	if not _valid or item == null or not _definitions.has(id):
		return false
	var story_blocks: bool = _story.is_playing() and _story.get_current_mode() != "caption"
	if _dialogue.is_playing() or story_blocks:
		return false
	if item.read:
		item.activate()
		return false
	_pending_map_id = map_id
	_pending_item = weakref(item)
	if not _dialogue.play(str(LINE_KEYS[id])):
		_clear_pending()
		return false
	return true

## 先移除待结算记录，再调用共用组件；重复回调也不能再次收费。
func _on_dialogue_finished(skipped: bool) -> void:
	var map_id: StringName = _pending_map_id
	var pending: WeakRef = _pending_item
	_clear_pending()
	if skipped or pending == null or _pending_run != GameState.run_id or not _page.is_visible_in_tree():
		return
	var item: Control = pending.get_ref() as Control
	if item == null or item != _map.get_interactable(map_id) or item.read:
		return
	var entry: Dictionary = _definitions[str(MAP_IDS[map_id])]
	item.cost_kind = &"required" if entry["kind"] == "must" else &"optional"
	if not item.activate():
		push_warning("[Points] 调查扣费失败（余额不足或当前不可扣费），保持未读：%s" % MAP_IDS[map_id])

func cancel_pending_for_failure() -> void:
	_clear_pending()
	_pending_run = -1
	_dialogue._finish(true)

func _clear_pending() -> void:
	_pending_map_id = &""
	_pending_item = null

func _on_investigated(map_id: StringName) -> void:
	var entry: Dictionary = _definitions.get(MAP_IDS.get(map_id, ""), {})
	if bool(entry.get("progress", false)):
		progress_changed.emit(get_progress_count())

func _on_visibility_changed() -> void:
	if not _page.is_visible_in_tree() and _dialogue.is_playing():
		_dialogue.skip()

func _exit_tree() -> void:
	_clear_pending()
	if is_instance_valid(_dialogue):
		if _dialogue.is_playing():
			_dialogue.skip()
		if _dialogue.sequence_finished.is_connected(_on_dialogue_finished):
			_dialogue.sequence_finished.disconnect(_on_dialogue_finished)
	if _interactions != null:
		if _interactions.request_investigation == investigate:
			_interactions.request_investigation = Callable()
		if _interactions.investigated.is_connected(_on_investigated):
			_interactions.investigated.disconnect(_on_investigated)
	if is_instance_valid(_page) and _page.visibility_changed.is_connected(_on_visibility_changed):
		_page.visibility_changed.disconnect(_on_visibility_changed)

func _run_self_test() -> void:
	var test: RefCounted = load("res://scripts/sp09_selftest.gd").new()
	var failures: int = await test.run(_main, self)
	get_tree().quit(0 if failures == 0 else 1)

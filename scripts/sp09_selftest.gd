## 仅显式运行；固定期望与真实调查链共同验证，正文以独立哈希防同源假绿。
extends RefCounted

const POINTS_SCRIPT = preload("res://scripts/points.gd")
const EXPECTED_IDS: Array[String] = ["p1", "p2", "p3", "p4", "p5", "p6", "p7"]
const EXPECTED_KEYS: Array[String] = ["T134", "T136", "T137", "T139", "T142", "T144", "T145"]
const TEXT_HASHES: Array[String] = [
	"077b73c5f25897fbbdfdf1949f1ccc374832ee28702a3add77ae979db3e8fcb6",
	"af8e28fee3816d083f9b922bd8c918d0d510db31d54b3a6b3a9ae0bb5d93ed6c",
	"b35c48386ca5b338ffb678ec0a7e12c0128f6274f423a30bd5c7c5d90f0d38ec",
	"a2a36dc3e71d26da11b574c5768cf5d4edbcd7badf47fdcd1ef5103bbe58a43d",
	"48a450c2ee0cd2cce0be4447bb6338233f5d4758c2224ace027cac69fe7e7128",
	"a4fa2543ef81d888abedc7c5d9d211ae0e20bc534fa209d633028dd869b22eda",
	"afc02a9f159610213f191a02ee2a87f3299d200a7150c3f6eef6cf2de053f32c",
]
var _main: Control
var _points: Node
var _map: Control
var _dialogue: Control
var _body: RichTextLabel
var _failures: int = 0
var _progress_events: int = 0
var _investigated: int = 0
var _repeated: int = 0
var _line_events: int = 0
var _played: Array[String] = []
var _cost_ok: Array[bool] = [true, true]
var _progress_ok: Array[bool] = [true, true]
var _repeat_ok: bool = true
var _move_ok: bool = true

func run(main: Control, points: Node) -> int:
	_main = main
	_points = points
	_map = main.get_node("Pages/MapPage/MapArea/CursorContainer/MapGrid")
	_dialogue = points.get_dialogue()
	_body = _dialogue.get_node("Panel/Margin/TextLayout/Body")
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	GameState.set_process(false)
	_main.show_page(&"MapPage")
	_points.progress_changed.connect(_on_progress)
	_map._interactions.investigated.connect(_on_investigated)
	_map._interactions.repeated.connect(_on_repeated)
	_dialogue.line_started.connect(_on_line)
	_test_data()
	_test_schema()
	_reset()
	for index: int in range(7):
		await _test_real_point(index)
	_test_totals()
	_test_four_investigations()
	_test_payment_failure()
	_test_close_restores_input()
	_test_caption_allows_investigation()
	_test_deferred_settlement()
	_test_interrupt_and_reopen()
	_test_insufficient_balance()
	_points.progress_changed.disconnect(_on_progress)
	_map._interactions.investigated.disconnect(_on_investigated)
	_map._interactions.repeated.disconnect(_on_repeated)
	_dialogue.line_started.disconnect(_on_line)
	print("[SP-09] failures=%d" % _failures)
	return _failures

func _test_data() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/points.json"))
	var definitions: Dictionary = _points.get_definitions()
	var ids: Array = definitions.keys()
	ids.sort()
	_check(raw is Array and raw.size() == 7 and ids == EXPECTED_IDS, "points_count_and_ids expected=7 p1..p7")
	var metadata_ok: bool = true
	var forbidden: bool = false
	for index: int in range(7):
		var entry: Dictionary = definitions.get(EXPECTED_IDS[index], {})
		metadata_ok = metadata_ok and entry.get("kind") == ("must" if index < 5 else "optional")
		metadata_ok = metadata_ok and entry.get("cost") == (6 if index < 5 else 4)
		metadata_ok = metadata_ok and entry.get("progress") == (index < 5)
		var body: String = str(entry.get("lines", ""))
		_check(body.sha256_text() == TEXT_HASHES[index], "point_text_exact_%s" % EXPECTED_IDS[index])
		forbidden = forbidden or body.contains("净化") or body.contains("天然共鸣")
	_check(metadata_ok, "points_kinds_costs_progress expected=5must6true 2optional4false")
	var p5: String = str(definitions.get("p5", {}).get("lines", ""))
	_check(p5.contains("正对着一面空墙") and p5.contains("坐过"), "point5_required_wording expected=both_original_fragments")
	_check(not forbidden, "no_forbidden_terms expected=0")
	_check(_dialogue.get_script() == preload("res://scripts/dialogue.gd")
		and _dialogue.scene_file_path == "res://scenes/ui/DialogueBox.tscn" and _dialogue != _main._dialogue,
		"shared_dialogue_implementation expected=same_scene_script separate_instance")

func _test_schema() -> void:
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/points.json"))
	var cases: Array[Dictionary] = [{"name": "root", "data": {}}, {"name": "count", "data": raw.slice(0, 6)}]
	var duplicate: Array = raw.duplicate(true)
	duplicate[6] = duplicate[0].duplicate(true)
	cases.append({"name": "duplicate", "data": duplicate})
	var missing: Array = raw.duplicate(true)
	missing[0].erase("lines")
	cases.append({"name": "missing", "data": missing})
	cases.append({"name": "unknown_id", "data": _changed(raw, "id", "p8")})
	cases.append({"name": "kind", "data": _changed(raw, "kind", "invalid")})
	cases.append({"name": "cost", "data": _changed(raw, "cost", 5)})
	cases.append({"name": "cost_type", "data": _changed(raw, "cost", "6")})
	cases.append({"name": "progress", "data": _changed(raw, "progress", false)})
	cases.append({"name": "empty", "data": _changed(raw, "lines", "")})
	cases.append({"name": "mismatch", "data": _changed(raw, "lines", str(raw[0]["lines"]) + " ")})
	var all_rejected: bool = true
	for entry: Dictionary in cases:
		var reason: String = POINTS_SCRIPT.validate_data(entry["data"], _dialogue.get_lines())
		var rejected: bool = not reason.is_empty()
		all_rejected = all_rejected and rejected
		_check(rejected, "points_schema_reject_invalid_%s reason=%s" % [entry["name"], reason])
	_check(all_rejected and cases.size() == 11, "points_schema_reject_invalid expected=11 rejected")

func _changed(raw: Array, field: String, value: Variant) -> Array:
	var result: Array = raw.duplicate(true)
	result[0][field] = value
	return result

func _reset() -> void:
	if _dialogue.is_playing():
		_dialogue.skip()
	_main.show_page(&"MapPage")
	GameState.set_frozen(false)
	_map.reset_map()
	GameState.vital_now = 100.0
	_progress_events = 0
	_investigated = 0
	_repeated = 0
	_line_events = 0

func _test_real_point(index: int) -> void:
	var target: StringName = StringName("point%d" % (index + 1))
	var arrived: bool = _walk_to(target)
	var before: Array = [GameState.vital_now, GameState.get_point_pay_call_count(), _points.get_progress_count(),
		_progress_events, _map.get_step_count(), _investigated]
	if index % 2 == 0:
		_click_current()
	else:
		_key(KEY_ENTER)
	await _main.get_tree().process_frame
	_dialogue.finish_text()
	await _main.get_tree().process_frame
	var key: String = _dialogue.get_current_key()
	_played.append(key)
	var item: Control = _map.get_interactable(target)
	var displayed: bool = _dialogue.is_playing() and _body.get_parsed_text().sha256_text() == TEXT_HASHES[index]
	var unpaid: bool = not item.read and is_equal_approx(GameState.vital_now, before[0])
	unpaid = unpaid and GameState.get_point_pay_call_count() == before[1] and _investigated == before[5]
	unpaid = unpaid and _points.get_progress_count() == before[2] and _progress_events == before[3]
	var line_count: int = _body.get_line_count()
	var fits: bool = _body.get_content_height() <= _body.size.y + 1.0
	_check(line_count >= 2 and line_count <= 4 and fits and _body.visible_characters == -1,
		"point_layout_2_to_4_%s lines=%d body=%.1fx%.1f content_h=%d" %
		[EXPECTED_IDS[index], line_count, _body.size.x, _body.size.y, _body.get_content_height()])
	_close()
	_check(arrived and displayed and unpaid and key == EXPECTED_KEYS[index] and item.read and _investigated == before[5] + 1,
		"investigate_real_input_%s key=%s" % [EXPECTED_IDS[index], key])
	_accumulate(index, before, target)
	if index == 4:
		_check(_map._points[target]["color"] == "white" and _main._current_page == &"MapPage",
			"point5_identity_preserved expected=white MapPage")
	_check_repeat(target)

func _accumulate(index: int, before: Array, target: StringName) -> void:
	var category: int = 0 if index < 5 else 1
	var expected_cost: float = 6.0 if category == 0 else 4.0
	_cost_ok[category] = _cost_ok[category] and absf(float(before[0]) - GameState.vital_now - expected_cost) <= 1e-6
	_cost_ok[category] = _cost_ok[category] and GameState.get_point_pay_call_count() == before[1] + 1
	var increase: int = 1 if category == 0 else 0
	_progress_ok[category] = _progress_ok[category] and _points.get_progress_count() == before[2] + increase
	_progress_ok[category] = _progress_ok[category] and _progress_events == before[3] + increase
	_move_ok = _move_ok and _map.get_current_node_id() == target and _map.get_step_count() == before[4]

func _check_repeat(target: StringName) -> void:
	var before: Array = [GameState.vital_now, GameState.get_point_pay_call_count(),
		_points.get_progress_count(), _progress_events, _investigated, _repeated, _line_events]
	_click_current()
	var hint_shown: bool = false
	for label: Dictionary in _map._interactions.get_labels():
		hint_shown = hint_shown or label.get("text") == "已经看过了"
	_repeat_ok = _repeat_ok and is_equal_approx(GameState.vital_now, before[0])
	_repeat_ok = _repeat_ok and GameState.get_point_pay_call_count() == before[1]
	_repeat_ok = _repeat_ok and _points.get_progress_count() == before[2] and _progress_events == before[3]
	_repeat_ok = _repeat_ok and _investigated == before[4] and _repeated == before[5] + 1
	_repeat_ok = _repeat_ok and _line_events == before[6] and not _dialogue.is_playing() and hint_shown
	_repeat_ok = _repeat_ok and _map.get_current_node_id() == target

func _test_totals() -> void:
	_check(_played == EXPECTED_KEYS, "point_line_key_alignment expected=7 exact_keys")
	_check(_cost_ok[0] and _investigated == 7, "required_spends_6_once expected=6 calls=1 each")
	_check(_cost_ok[1] and _investigated == 7, "optional_spends_4_once expected=4 calls=1 each")
	_check(_progress_ok[0] and _points.get_progress_count() == 5 and _progress_events == 5,
		"mandatory_progress_once expected=5")
	_check(_progress_ok[1] and _map.get_interactable(&"point6").read and _map.get_interactable(&"point7").read,
		"optional_never_progresses expected=0 increments")
	_check(_repeat_ok and _repeated == 7, "repeat_hint_only expected=7 repeats no_spend_progress_replay")
	_check(_move_ok and _investigated == 7, "investigation_does_not_move expected=0 investigation_steps")

func _test_four_investigations() -> void:
	_reset()
	var before_calls: int = GameState.get_point_pay_call_count()
	var accepted: int = 0
	for target: StringName in [&"point1", &"point2", &"point6", &"point7"]:
		if _points.investigate(target):
			accepted += 1
		_close()
	_check(accepted == 4 and absf(GameState.vital_now - 80.0) <= 1e-6
		and GameState.get_point_pay_call_count() == before_calls + 4 and _map.get_step_count() == 0
		and _points.get_progress_count() == 2, "four_investigations_only expected=80 actual=%.6f" % GameState.vital_now)

func _test_payment_failure() -> void:
	_reset()
	_walk_to(&"point1")
	var before: float = GameState.vital_now
	var calls: int = GameState.get_point_pay_call_count()
	GameState.set_frozen(true)
	_key(KEY_ENTER)
	_close()
	_check(not _map.get_interactable(&"point1").read and _points.get_progress_count() == 0
		and _investigated == 0 and not _dialogue.is_playing() and is_equal_approx(GameState.vital_now, before)
		and GameState.get_point_pay_call_count() == calls + 1, "payment_failure_keeps_unread expected=no_read_no_progress_no_box")
	GameState.set_frozen(false)

func _test_close_restores_input() -> void:
	_reset()
	_walk_to(&"point1")
	_click_current()
	_close()
	var before: int = _map.get_step_count()
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	var moved: bool = _map.get_current_node_id() == &"point2" and _map.get_step_count() == before + 1
	var opened: bool = _points.investigate(&"point2")
	_main.show_page(&"ScenePage")
	var closed: bool = not _dialogue.is_playing()
	_main.show_page(&"MapPage")
	_check(moved and opened and closed, "close_restores_map_input expected=move_after_close hidden_box_stopped")

func _test_caption_allows_investigation() -> void:
	_reset()
	var caption_key: String = ""
	for entry: Dictionary in _main._dialogue.get_lines().values():
		if entry["mode"] == "caption":
			caption_key = str(entry["id"])
			break
	var caption_started: bool = _main._dialogue.play(caption_key)
	_walk_to(&"point1")
	_key(KEY_ENTER)
	var opened: bool = caption_started and _main._dialogue.is_playing() and _dialogue.is_playing()
	opened = opened and not _map.get_interactable(&"point1").read
	_close()
	_check(opened and _map.get_interactable(&"point1").read, "caption_allows_investigation expected=nonblocking")
	_main._dialogue.skip()

func _test_deferred_settlement() -> void:
	_reset()
	_walk_to(&"point1")
	var before: float = GameState.vital_now
	var calls: int = GameState.get_point_pay_call_count()
	var item: Control = _map.get_interactable(&"point1")
	_click_current()
	var opened_unpaid: bool = _dialogue.is_playing() and not item.read and is_equal_approx(GameState.vital_now, before)
	opened_unpaid = opened_unpaid and GameState.get_point_pay_call_count() == calls and _investigated == 0
	_key(KEY_ENTER)
	var filled_unpaid: bool = _dialogue.is_playing() and not item.read and is_equal_approx(GameState.vital_now, before)
	_key(KEY_ENTER)
	_check(opened_unpaid and filled_unpaid and not _dialogue.is_playing() and item.read
		and absf(before - GameState.vital_now - 6.0) <= 1e-6 and GameState.get_point_pay_call_count() == calls + 1
		and _points.get_progress_count() == 1 and _investigated == 1,
		"charge_after_dialogue_finishes expected=open0 fill0 finish6")

func _test_interrupt_and_reopen() -> void:
	_reset()
	_walk_to(&"point1")
	var before: float = GameState.vital_now
	var calls: int = GameState.get_point_pay_call_count()
	var item: Control = _map.get_interactable(&"point1")
	_click_current()
	_dialogue.skip()
	var skipped: bool = not _dialogue.is_playing() and not item.read and is_equal_approx(GameState.vital_now, before)
	_click_current()
	_main.show_page(&"ScenePage")
	var hidden: bool = not _dialogue.is_playing() and not item.read and is_equal_approx(GameState.vital_now, before)
	_main.show_page(&"MapPage")
	_check(skipped and hidden and GameState.get_point_pay_call_count() == calls
		and _investigated == 0 and _points.get_progress_count() == 0,
		"interrupt_keeps_unread_and_unpaid expected=skip_and_hide_no_charge")
	_click_current()
	_close()
	_click_current()
	_check(item.read and absf(before - GameState.vital_now - 6.0) <= 1e-6
		and GameState.get_point_pay_call_count() == calls + 1 and _investigated == 1 and _repeated == 1
		and _points.get_progress_count() == 1 and not _dialogue.is_playing(),
		"reopen_after_interrupt_still_charges expected=one_charge_one_read")

func _test_insufficient_balance() -> void:
	_reset()
	_walk_to(&"point1")
	GameState.vital_now = 5.0
	var calls: int = GameState.get_point_pay_call_count()
	_click_current()
	var opened: bool = _dialogue.is_playing() and not _map.get_interactable(&"point1").read
	_close()
	_check(opened and not _map.get_interactable(&"point1").read and is_equal_approx(GameState.vital_now, 5.0)
		and _points.get_progress_count() == 0 and _investigated == 0 and not _dialogue.is_playing()
		and GameState.get_point_pay_call_count() == calls + 1, "insufficient_balance_keeps_unread expected=5 no_read")

func _walk_to(target: StringName) -> bool:
	var start: StringName = _map.get_current_node_id()
	var queue: Array[StringName] = [start]
	var previous: Dictionary = {start: &""}
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		if current == target:
			break
		for next_value: Variant in _map._points[current]["edges"]:
			var next: StringName = StringName(next_value)
			if not previous.has(next):
				previous[next] = current
				queue.append(next)
	if not previous.has(target):
		return false
	var path: Array[StringName] = []
	var cursor: StringName = target
	while cursor != start:
		path.push_front(cursor)
		cursor = previous[cursor]
	for step: StringName in path:
		if not _map.try_move_to(step):
			return false
	return _map.get_current_node_id() == target

func _close() -> void:
	_dialogue.finish_text()
	_key(KEY_ENTER)

func _click_current() -> void:
	var position: Vector2 = _map.get_global_transform_with_canvas() * _map.get_point_position_for_test(_map.get_current_node_id())
	var motion := InputEventMouseMotion.new()
	motion.position = position
	_main.get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		_main.get_viewport().push_input(event, true)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		_main.get_viewport().push_input(event)

func _on_progress(_value: int) -> void:
	_progress_events += 1

func _on_investigated(_id: StringName) -> void:
	_investigated += 1

func _on_repeated(_id: StringName) -> void:
	_repeated += 1

func _on_line(_key: String) -> void:
	_line_events += 1

func _check(passed: bool, label: String) -> void:
	print("[SP-09] %s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		_failures += 1

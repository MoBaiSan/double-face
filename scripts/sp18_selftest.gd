## U-08 / SP-18：独立入口，真实输入、固定逐字预期与原保存链路。
extends SceneTree
const IDS: Array[String] = ["T178", "T179", "T180", "T181", "T182", "T183", "T184", "T185", "T186", "T187", "T188", "T189"]
const LINES: Array = [
	["T178", "琥珀", "斑さん。"],
	["T179", "琥珀", "刚才那句。「站在前面是我的工作」——那个，是工作吗。"],
	["T180", "斑", "怎么，突然问这个。"],
	["T181", "斑", "工作啊。不然呢。报告是我写的，路线是我定的，门是我开的。你在里头多待两分钟，我这边就有一堆数字要盯着。"],
	["T182", "斑", "再说，站在前面这件事我很擅长。擅长的事不拿来当工作，难道拿去当爱好吗。"],
	["T183", "琥珀", "我问的是——"],
	["T184", "斑", "哎，等一下，你那个绷带别绕那么紧，绕太紧肩膀会麻。……对，就这样。你手比我有数，你自己来。"],
	["T185", "斑", "咖啡还剩半罐。你喝完再过去，别剩。"],
	["T186", "旁白", "琥珀没有再说下去。他把手收回来，看了斑一会儿。"],
	["T187", "斑", "……看什么。我脸上有东西？"],
	["T188", "琥珀", "没有。"],
	["T189", "琥珀", "晚安，斑さん。"],
]
var h: RefCounted
var state: Node
var host: Control
var results: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	host = load("res://scenes/Main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	await process_frame
	state = root.get_node("GameState")
	h = load("res://scripts/sp17_test_context.gd").new()
	for test: Callable in [_layout, _reading, _replay, _permissions, _medical, _exit_paths, _lifecycle, _keyboard]:
		await test.call()
	await h.close()
	if not h.clean:
		failures += 1
	print("[SP-18] assertions=%d failures=%d" % [results.size(), failures])
	quit(0 if results.size() == 32 and failures == 0 else 1)

func ck(id: int, ok: bool, label: String) -> void:
	if results.has(id):
		ok = false
	results[id] = ok
	if not ok:
		failures += 1
	print("[SP-18] %s %02d %s" % ["PASS" if ok else "FAIL", id, label])

func _fresh() -> void:
	await h.fresh(host)
	await process_frame

func _layout() -> void:
	await _fresh()
	var art: Control = h.room.visual
	var canvas: Rect2 = art.get_global_rect()
	ck(1, canvas.is_equal_approx(h.room.get_global_rect()) and art.get_parent().name == &"Illustration", "single_full_page_illustration_layer")
	ck(2, _clear_targets() and _shapes_at_targets(), "four_visible_shapes_match_disjoint_targets")
	var words: Array[String] = []
	for node: Node in h.descendants(h.room):
		if node is Label or node is Button or node is RichTextLabel:
			if node == h.room.get_node("SofaOptions/Choices/Medical/Text") or node == h.room.get_node("SofaOptions/Choices/ScarDetail/Text"):
				continue
			if not node.text.is_empty(): words.append(node.text)
	ck(3, words == ["安全屋"] and h.room.get_node("SofaOptions/Choices/Medical/Text").text == "上药" and h.room.get_node("SofaOptions/Choices/ScarDetail/Text").text == "看斑的旧伤", "room_and_popup_have_no_placeholder_words")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color("#86724F"))
	var texture := ImageTexture.create_from_image(image)
	var rect: Rect2 = h.button("Sofa").get_global_rect()
	art.set_artwork(texture)
	ck(4, art.get_node("Artwork").texture == texture and art.get_node("Artwork").visible and not art.get_node("Placeholder").visible and h.button("Sofa").get_global_rect() == rect, "replace_entire_artwork_at_one_property")
	h.click("Sofa")
	ck(5, h.player.get_current_key() == "T178" and h.room.busy, "artwork_does_not_steal_real_click")
	art.set_artwork(null)
	h.finish_reading()
	print("[SP-18] geometry=%s" % JSON.stringify({"canvas":str(canvas), "targets":_target_rects()}))

func _clear_targets() -> bool:
	var rects: Array[Rect2] = []
	if h.room.get_node("Objects").get_child_count() != 3:
		return false
	for id: String in ["Sofa", "Speaker", "Door"]:
		var rect: Rect2 = h.button(id).get_global_rect()
		if not h.room.visual.get_global_rect().encloses(rect) or rect.size.x <= 0 or rect.size.y <= 0:
			return false
		for other: Rect2 in rects:
			if rect.intersects(other): return false
		for bar: Control in [h.c.main._page_switch_bar, h.c.main._throat_placeholder]:
			if rect.intersects(bar.get_global_rect()): return false
		rects.append(rect)
	return h.room.visual.mouse_filter == Control.MOUSE_FILTER_IGNORE

func _shapes_at_targets() -> bool:
	for id: String in ["Sofa", "Speaker", "Door"]:
		var center: Vector2 = h.room.grid.get_global_transform_with_canvas() * h.room.grid.center(h.room.grid.objects[id].cell)
		if not center.is_equal_approx(h.button(id).get_global_rect().get_center()):
			return false
	return h.room.grid.valid and h.room.grid.dimensions == Vector2i(5, 5)

func _target_rects() -> Dictionary:
	var out: Dictionary = {}
	for id: String in ["Sofa", "Speaker", "Door"]:
		out[id] = str(h.button(id).get_global_rect())
	return out

func _reading() -> void:
	await _fresh()
	state.vital_now = 73.0
	h.click("Sofa")
	ck(6, h.player.get_current_key() == "T178" and not h.room.interaction("Sofa").read and not state.event_done(&"E12"), "ban_available_immediately_on_s6_entry")
	var exact: bool = true
	var single: bool = true
	for row: Array in LINES:
		exact = exact and h.player.get_current_key() == row[0] and h.player.get_current_mode() == "read"
		h.key(KEY_ENTER)
		exact = exact and h.player.get_visible_text() == row[2] and h.player._speaker.text == row[1]
		exact = exact and h.player.get_lines()[row[0]].text == row[2] and h.player.get_lines()[row[0]].speaker == row[1]
		single = single and h.player.get_current_key() == row[0] and not h.player.is_typing()
		h.key(KEY_ENTER)
	ck(7, exact, "trust_exact_text_and_speakers_t178_to_t189")
	ck(8, single and not h.player.is_playing() and h.ids() == IDS, "trust_confirm_advances_exactly_twelve_in_order")
	await process_frame
	ck(9, state.state == state.State.S6 and h.c.main._current_page == &"ScenePage" and not h.room.busy and root.gui_get_focus_owner() == h.room.grid, "trust_returns_to_room_and_ban_focus")
	ck(10, state.vital_now == 73.0 and not h.room.interaction("Sofa").read and not h.room.interaction("Sofa").has_checkmark() and h.room.interaction("Sofa").get_read_shade().a == 0.0, "trust_does_not_pay_or_gray_ban")

func _replay() -> void:
	await _fresh()
	h.click("Sofa")
	h.finish_reading()
	h.click("Sofa")
	var choices: bool = h.room.options_open and not h.player.is_playing() and h.ids() == IDS and h.room.options_nav.get_candidates().size() == 2
	h.choose_option("Medical")
	var again: bool = h.player.get_current_key() == "T176" and h.player.is_playing() and h.room.medical.visible
	h.finish_reading()
	ck(11, choices and again and h.ids() == IDS + ["T176", "T177"] and h.room.interaction("Sofa").read, "completed_trust_opens_menu_then_original_medical")
	ck(12, h.c.event_count(&"E13") == 1 and h.c.event_count(&"E13", false) == 1 and not state.event_done(&"E12"), "replay_records_e13_once_without_r13")
	ck(13, _clear_targets() and h.room.get_node("Objects").visible and h.room.interaction("Sofa").read and not h.room.has_node("Objects/Scar"), "menu_keeps_three_locations")
	await _fresh()
	h.click("Sofa")
	h.player._finish(true)
	var partial: bool = not state.event_done(&"E13") and not h.room.busy
	h.click("Sofa")
	ck(14, partial and h.player.get_current_key() == "T178" and h.ids() == ["T178", "T178"], "interrupted_trust_not_marked_complete")
	h.finish_reading()

func _permissions() -> void:
	await _fresh()
	var invalid: Array = [[], ["T178"], ["T189","T178"], IDS + ["T190"], IDS + ["missing"]]
	var rejected: bool = true
	for ids: Array in invalid:
		rejected = not h.room.request_room_sequence(&"trust", ids) and rejected
	ck(15, rejected and h.lines.is_empty() and not h.player.is_playing(), "trust_rejects_partial_mixed_sequences_before_any_line")
	h.click("Sofa")
	var key: String = h.player.get_current_key()
	for id: String in ["Sofa", "Speaker", "Door"]:
		h.click(id)
	ck(16, h.player.get_current_key() == key and h.ids() == ["T178"] and h.exit_service.accepted == 0, "busy_trust_cannot_be_replaced_by_objects")
	h.key(KEY_ESCAPE)
	var denied: bool = not h.player.skip()
	ck(17, denied and not h.player.is_typing() and h.player.get_current_key() == "T178" and not state.event_done(&"E13"), "trust_escape_finishes_sentence_without_skipping")
	h.finish_reading()
	h.click("Scar")
	var scar_denied: bool = not h.player.is_playing() and not h.room.request_object("Scar") and h.player.get_lines().has("T190")
	h.lines.clear()
	var detail: bool = true
	for n: int in range(2):
		h.click("Sofa")
		detail = detail and h.room.options_open and not h.player.is_playing()
		h.choose_option("ScarDetail")
		h.player.finish_text()
		detail = detail and h.player.get_current_key() == "T190" and h.player.get_visible_text() == h.T190 and h.player._speaker.text == "旁白" and h.player.get_current_mode() == "read"
		h.finish_reading()
		detail = detail and not h.room.options_open and not h.room.interaction("Sofa").read and not state.event_done(&"E12")
	ck(18, scar_denied and detail and h.ids() == ["T190","T190"] and h.c.event_count(&"E13") == 1, "scar_only_through_repeatable_sofa_option")
	h.finish_reading()

func _medical() -> void:
	await _fresh()
	h.begin_medical()
	var med: Control = h.room.medical
	var rect: Rect2 = med.frame.get_global_rect()
	var style: StyleBoxFlat = med.frame.get_theme_stylebox("panel") as StyleBoxFlat
	ck(19, med.is_visible_in_tree() and rect.get_center().is_equal_approx(h.room.get_global_rect().get_center()) and med.picture.size.x >= 320 and med.picture.size.x <= 560 and style.get_border_width(SIDE_LEFT) == 2, "medical_popup_centered_small_and_framed")
	ck(20, h.player.get_current_key() == "T176" and h.player.is_playing() and not h.player.visible, "sofa_keeps_original_story_under_picture")
	h.c.click(med.frame)
	ck(21, not med.visible and h.player.is_visible_in_tree() and h.player.get_current_key() == "T176" and h.ids() == ["T176"] and not state.event_done(&"E12"), "medical_real_click_closes_without_advancing_or_clickthrough")
	h.player.finish_text()
	var original: bool = h.player.get_visible_text() == h.T176
	h.key(KEY_ENTER)
	h.key(KEY_ENTER)
	original = original and h.player.get_current_key() == "T177" and h.player.get_visible_text() == h.T177
	h.key(KEY_ENTER)
	await process_frame
	ck(22, original and h.ids() == ["T176","T177"] and h.room.interaction("Sofa").read and not h.room.busy and root.gui_get_focus_owner() == h.room.grid, "medical_close_restores_original_two_line_story")
	h.click("Sofa")
	h.choose_option("Medical")
	ck(23, state.event_done(&"E12") and h.c.event_count(&"E12") == 1 and state.event_done(&"E13"), "medical_does_not_change_sofa_confirmation")
	print("[SP-18] medical=%s" % JSON.stringify({"popup":str(rect), "picture":str(med.picture.get_global_rect()), "dialogue":str(h.player._body.get_global_rect())}))

func _exit_paths() -> void:
	await _fresh()
	h.click("Door")
	h.finish_reading()
	ck(24, h.finished.size() == 1 and h.c.flow.checkpoint.writes == 1 and h.document().progress.trust_read == false and h.document().progress.r13_done == false and not state.event_started(&"E13") and not state.event_done(&"E12"), "unread_trust_still_finishes_prologue_once")
	await _fresh()
	h.click("Sofa")
	h.finish_reading()
	h.complete_sofa()
	h.click("Door")
	h.finish_reading()
	ck(25, h.finished.size() == 1 and h.c.flow.checkpoint.writes == 1 and h.document().progress.trust_read == true and state.event_done(&"E14"), "read_trust_uses_same_single_exit_save")
	ck(26, not h.room.request_object("Sofa") and not h.room.get_node("Objects").visible, "finished_prologue_cannot_reopen_trust")

func _lifecycle() -> void:
	await _fresh()
	for node: Node in [h.c.main] + h.descendants(h.c.main):
		if node.is_processing() and node.can_process() and node.has_method("_process"):
			node.call("_process", 60.0)
	ck(27, h.lines.is_empty() and not h.player.is_playing() and not state.event_started(&"E13"), "trust_never_starts_from_waiting")
	h.c.main.show_page(&"MapPage")
	var hidden: bool = not h.room.request_object("Sofa")
	h.c.main.show_page(&"ScenePage")
	ck(28, hidden and not h.room.busy and h.lines.is_empty(), "hidden_room_does_not_start_trust")
	h.click("Sofa")
	h.room._sequence_run -= 1
	h.finish_reading()
	ck(29, not state.event_done(&"E13") and not h.room.busy, "stale_trust_completion_cannot_mark_watched")
	var clean: bool = true
	for row: Array in LINES:
		clean = clean and not row[2].contains("净化") and not row[2].contains("天然共鸣")
	ck(30, clean and LINES.size() == 12, "trust_fixed_text_obeys_a15")

func _keyboard() -> void:
	await _fresh()
	h.focus_object("Sofa")
	h.key(KEY_ENTER)
	ck(31, h.player.get_current_key() == "T178" and h.player.is_playing() and not state.event_done(&"E12"), "keyboard_ban_starts_without_sofa")
	h.finish_reading()
	h.click("Sofa")
	h.choose_option("Medical")
	h.c.main.show_page(&"MapPage")
	var cleared: bool = not h.room.medical.visible and h.player.visible
	h.c.main.show_page(&"ScenePage")
	h.finish_reading()
	ck(32, cleared and not h.room.busy and not h.room.medical.visible and h.room.get_node("Objects").visible, "leaving_popup_restores_input_and_page")

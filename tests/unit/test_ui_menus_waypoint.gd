extends TestCase
## ui-menus: WaypointPanel — depth tiles 1..max_depth (+ one locked), travel emits
## Events.area_change_requested("dungeon", {"depth": d}) and closes.

var _requests: Array = []


func _on_request(area_id: String, params: Dictionary) -> void:
	_requests.append([area_id, params])


func _panel(max_depth: int) -> WaypointPanel:
	var c := make_character("ranger")
	c.max_depth = max_depth
	c.mark_depth_cleared(1)
	var p := WaypointPanel.new()
	add_child(p)
	p.on_opened({"max_depth": max_depth})
	Events.area_change_requested.connect(_on_request)
	return p


func _cleanup() -> void:
	if Events.area_change_requested.is_connected(_on_request):
		Events.area_change_requested.disconnect(_on_request)


func _settle(frames: int = 2) -> void:
	for i in frames:
		await get_tree().process_frame


func test_tiles_for_each_depth() -> void:
	var p := _panel(4)
	await _settle()
	assert_eq(p.get_max_depth(), 4, "max depth from context")
	assert_eq(p.get_depths(), [1, 2, 3, 4] as Array[int], "depths listed")
	for d in range(1, 5):
		var t := p.get_tile(d)
		assert_not_null(t, "tile %d" % d)
		assert_false(t.disabled, "tile %d enabled" % d)
		assert_eq(int(t.get("monster_level")), Balance.area_level_for_depth(d), "monster level %d" % d)
		assert_eq(String(t.get("theme_id")), World.theme_for_depth(d), "theme %d" % d)
	assert_true(bool(p.get_tile(1).get("cleared")), "depth 1 marked cleared")
	assert_false(bool(p.get_tile(2).get("cleared")), "depth 2 not cleared")
	assert_true(bool(p.get_tile(4).get("deepest")), "deepest marked")
	assert_true(p.get_tile(5).disabled, "next depth shown locked")
	assert_null_tile(p.get_tile(6))
	_cleanup()


func assert_null_tile(t: Button) -> void:
	assert_true(t == null, "no tile beyond the locked one")


func test_click_travels_and_closes() -> void:
	var p := _panel(6)
	await _settle(3)
	var t := p.get_tile(3)
	var pos := t.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(ev, true)
	await _settle()
	assert_eq(_requests.size(), 1, "one travel request")
	if _requests.size() == 1:
		assert_eq(_requests[0][0], "dungeon", "area id")
		assert_eq(int((_requests[0][1] as Dictionary).get("depth", 0)), 3, "depth param")
	assert_false(p.visible, "panel closed after travelling")
	_cleanup()


func test_travel_api_bounds() -> void:
	var p := _panel(2)
	await _settle()
	assert_false(p.travel_to(3), "beyond max depth refused")
	assert_false(p.travel_to(0), "depth 0 refused")
	p.get_tile(3).pressed.emit()   # locked tile: no handler
	assert_eq(_requests.size(), 0, "no request for locked/out-of-range depths")
	assert_true(p.travel_to(2), "valid depth")
	assert_false(p.travel_to(1), "only one request per opening")
	assert_eq(_requests.size(), 1, "exactly one request")
	p.visible = true
	p.on_opened({"max_depth": 2})
	assert_true(p.travel_to(1), "reopened: can travel again")
	_cleanup()


func test_max_depth_fallback_and_clamp() -> void:
	var c := make_character("warrior")
	c.max_depth = 7
	var p := WaypointPanel.new()
	add_child(p)
	p.on_opened({})
	assert_eq(p.get_max_depth(), 7, "falls back to character.max_depth")
	p.on_opened({"max_depth": 999})
	assert_eq(p.get_max_depth(), Balance.MAX_DEPTH, "clamped to MAX_DEPTH")
	assert_true(p.get_tile(Balance.MAX_DEPTH + 1) == null, "no locked tile past the last depth")
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_IGNORE, "windowed panel root ignores the mouse")
	p.close_button.pressed.emit()
	assert_false(p.visible, "Close hides it")


func test_tooltip_lines() -> void:
	var p := _panel(3)
	await _settle()
	var texts: Array = p.get_tooltip_lines(2).map(func(l: Dictionary) -> String: return String(l.get("text", "")))
	assert_has(texts, "Depth 2", "title")
	assert_has(texts, "Monster Level %d" % Balance.area_level_for_depth(2), "monster level")
	assert_has(texts, "Click to descend", "hint")
	var locked: Array = p.get_tooltip_lines(4).map(func(l: Dictionary) -> String: return String(l.get("text", "")))
	assert_has(locked, "Locked: slay the guardian of Depth 3 first", "locked hint")
	p.preview_tooltip(1)
	p.close()
	_cleanup()

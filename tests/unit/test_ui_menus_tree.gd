extends TestCase
## ui-menus: PassiveTreePanel — allocation / refund / path preview through the API and through
## synthesised mouse input (push_input), view math (zoom around a point, pan, limits), search.


func _panel(level: int = 5, class_id: String = "warrior") -> PassiveTreePanel:
	var c := make_character(class_id)
	c.level = level
	var p := PassiveTreePanel.new()
	add_child(p)
	p.on_opened({})
	p.get_tree_canvas().set("smooth_zoom", false)
	return p


func _settle(frames: int = 2) -> void:
	for i in frames:
		await get_tree().process_frame


func _click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	get_viewport().push_input(mv, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		get_viewport().push_input(ev, true)


func _move(pos: Vector2, mask: int = 0) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	mv.button_mask = mask
	get_viewport().push_input(mv, true)


## A node reachable from the start in exactly `n` steps (-1 if none).
func _node_at_distance(class_id: String, n: int) -> int:
	for id in TreeDB.get_all_ids():
		var nid := int(id)
		if TreeDB.is_start(nid):
			continue
		if TreeDB.find_path([], nid, class_id).size() == n:
			return nid
	return -1


func test_opens_centred_on_class_start() -> void:
	var p := _panel(5, "ranger")
	await _settle()
	var start := TreeDB.get_start_node("ranger")
	assert_true(p.get_view_center().distance_to(TreeDB.get_node_position(start)) < 1.0, "view centred on the ranger start")
	var centre := p.get_tree_canvas().get_global_rect().get_center()
	assert_true(p.node_screen_position(start).distance_to(centre) < 1.0, "start node drawn at the screen centre")
	assert_eq(p.get_node_state(start), "start", "own start state")
	assert_eq(p.get_node_state(TreeDB.get_start_node("warrior")), "other_start", "other class start")


func test_zoom_math_keeps_point_under_cursor_and_clamps() -> void:
	var p := _panel()
	await _settle()
	p.set_view(Vector2(-300, 175), 0.8)
	var anchor := p.get_tree_canvas().get_global_rect().get_center() + Vector2(180, -90)
	var tree_pt := p.screen_to_tree(anchor)
	p.zoom_at(anchor, 1.5)
	assert_near(p.get_zoom(), 1.2, 0.0001, "zoom multiplied")
	assert_true(p.tree_to_screen(tree_pt).distance_to(anchor) < 0.01, "tree point stays under the cursor")
	assert_true(p.screen_to_tree(p.tree_to_screen(Vector2(123, -45))).distance_to(Vector2(123, -45)) < 0.001, "round trip")
	p.zoom_at(anchor, 100.0)
	assert_near(p.get_zoom(), 2.0, 0.0001, "max zoom 2")
	p.zoom_at(anchor, 0.0001)
	assert_near(p.get_zoom(), 0.25, 0.0001, "min zoom 0.25")


func test_pan_moves_view_by_screen_delta() -> void:
	var p := _panel()
	await _settle()
	p.set_view(Vector2(0, 0), 0.5)
	p.pan_by(Vector2(100, -40))
	assert_true(p.get_view_center().distance_to(Vector2(-200, 80)) < 0.001, "pan divides by zoom: got %s" % p.get_view_center())
	# The view stays near the tree.
	p.pan_by(Vector2(-100000, 0))
	assert_true(p.get_view_center().x <= TreeDB.get_bounds().end.x + 400.0, "view clamped to the tree bounds")


func test_wheel_and_drag_input() -> void:
	var p := _panel()
	await _settle()
	p.set_view(Vector2(-300, 175), 0.8)
	var pos := p.get_tree_canvas().get_global_rect().get_center() + Vector2(60, 40)
	var before := p.get_zoom()
	var tree_pt := p.screen_to_tree(pos)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = pos
	wheel.global_position = pos
	get_viewport().push_input(wheel, true)
	await _settle()
	assert_true(p.get_zoom() > before, "wheel up zooms in (%s -> %s)" % [before, p.get_zoom()])
	assert_true(p.tree_to_screen(tree_pt).distance_to(pos) < 0.5, "wheel zoom keeps the point under the cursor")
	# Drag with the left button: pans, never allocates.
	var c := GameState.character
	var centre_before := p.get_view_center()
	var z := p.get_zoom()
	var a := p.get_tree_canvas().get_global_rect().get_center() + Vector2(-200, 150)
	_move(a)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a
	down.global_position = a
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(down, true)
	_move(a + Vector2(80, 0), MOUSE_BUTTON_MASK_LEFT)
	_move(a + Vector2(160, 30), MOUSE_BUTTON_MASK_LEFT)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = a + Vector2(160, 30)
	up.global_position = up.position
	get_viewport().push_input(up, true)
	await _settle()
	var moved := p.get_view_center() - centre_before
	assert_true(moved.distance_to(Vector2(-160, -30) / z) < 0.5, "drag pans by the mouse delta / zoom (moved %s)" % moved)
	assert_eq(c.allocated_passives.size(), 0, "dragging allocates nothing")


func test_click_allocates_adjacent_node() -> void:
	var p := _panel(5)
	await _settle()
	var c := GameState.character
	var frontier := TreeDB.get_allocatable([], "warrior")
	assert_true(not frontier.is_empty(), "warrior start has neighbours")
	var id: int = frontier[0]
	assert_eq(p.get_node_state(id), "allocatable", "frontier state")
	p.center_on_node(id, false)
	await _settle()
	_click(p.node_screen_position(id))
	await _settle()
	assert_true(c.allocated_passives.has(id), "left click allocated the node")
	assert_eq(p.get_node_state(id), "allocated", "state after allocation")
	assert_eq(c.passive_points_unspent(), 3, "one point spent")
	# Clicking an allocated node again does nothing.
	_click(p.node_screen_position(id))
	await _settle()
	assert_eq(c.allocated_passives.size(), 1, "no double allocation")


func test_hover_previews_path_and_click_allocates_it() -> void:
	var p := _panel(6)
	await _settle()
	var c := GameState.character
	var target := _node_at_distance("warrior", 3)
	assert_true(target >= 0, "a node 3 steps away exists")
	p.center_on_node(target, false)
	await _settle()
	var pos := p.node_screen_position(target)
	_move(pos)
	await _settle()
	assert_eq(p.get_hovered(), target, "mouse hover sets the hovered node")
	var path := p.get_preview_path()
	assert_eq(path.size(), 3, "path preview length")
	assert_eq(int(path[-1]), target, "path ends at the hovered node")
	assert_eq(p.get_node_state(int(path[0])), "path", "path nodes are marked")
	var lines := p.get_tooltip_lines(target)
	var texts: Array = lines.map(func(l: Dictionary) -> String: return String(l.get("text", "")))
	assert_has(texts, "Click to allocate (3 points)", "tooltip shows the cost")
	_click(pos)
	await _settle()
	assert_eq(c.allocated_passives.size(), 3, "whole path allocated")
	assert_true(c.allocated_passives.has(target), "target allocated")
	assert_true(p.get_preview_path().is_empty(), "no preview on an allocated node")


func test_allocation_limited_by_unspent_points() -> void:
	var p := _panel(3)   # 2 points
	await _settle()
	var c := GameState.character
	var target := _node_at_distance("warrior", 4)
	assert_true(target >= 0, "a node 4 steps away exists")
	p.hover_node(target)
	var texts: Array = p.get_tooltip_lines(target).map(func(l: Dictionary) -> String: return String(l.get("text", "")))
	assert_has(texts, "Needs 4 points, you have 2", "tooltip shows the shortfall")
	assert_eq(p.allocate_to(target), 2, "allocates as far as the points go")
	assert_eq(c.passive_points_unspent(), 0, "no points left")
	assert_eq(p.allocate_to(target), 0, "nothing more without points")
	assert_false(c.allocated_passives.has(target), "target not reached")
	assert_eq(p.allocate_to(TreeDB.get_start_node("ranger")), 0, "other class start can't be allocated")


func test_right_click_refunds_with_gold_cost() -> void:
	var p := _panel(8)
	await _settle()
	var c := GameState.character
	var target := _node_at_distance("warrior", 3)
	assert_eq(p.allocate_to(target), 3, "allocated a 3-node chain")
	var path := TreeDB.find_path([], target, "warrior")
	var middle := int(path[1])
	var cost := c.refund_cost()
	c.gold = cost + 5
	# The middle of the chain holds the tip: blocked.
	assert_eq(p.get_refund_block_reason(middle), "Other passives depend on this one", "articulation node")
	assert_false(p.refund(middle), "middle node refused")
	# The tip can go, by right-click.
	assert_eq(p.get_refund_block_reason(target), "", "tip refundable")
	p.center_on_node(target, false)
	await _settle()
	_click(p.node_screen_position(target), MOUSE_BUTTON_RIGHT)
	await _settle()
	assert_false(c.allocated_passives.has(target), "right click refunded the tip")
	assert_eq(c.gold, 5, "refund cost paid")
	# Not enough gold now.
	var tip2 := int(path[1])
	assert_true(p.get_refund_block_reason(tip2).begins_with("Not enough gold"), "gold check: %s" % p.get_refund_block_reason(tip2))
	assert_false(p.refund(tip2), "refused without gold")
	assert_true(c.allocated_passives.has(tip2), "still allocated")


func test_search_highlights_matches() -> void:
	var p := _panel()
	await _settle()
	var n := p.set_search("life")
	assert_true(n > 0, "some passives mention life")
	assert_eq(p.get_search_matches(), TreeDB.search("life"), "matches = TreeDB.search")
	var canvas_matches: Dictionary = p.get_tree_canvas().get("matches")
	assert_eq(canvas_matches.size(), n, "canvas highlights every match")
	var first := p.focus_next_match()
	assert_eq(first, p.get_search_matches()[0], "first match focused")
	var second := p.focus_next_match()
	if n > 1:
		assert_ne(second, first, "next match cycles")
	p.search_edit.text = ""
	p.search_edit.text_changed.emit("")
	assert_eq(p.get_search_matches().size(), 0, "clearing the box clears matches")
	assert_eq(p.set_search("zzzz-no-such-passive"), 0, "no matches")


func test_header_close_and_no_character() -> void:
	var p := PassiveTreePanel.new()
	add_child(p)
	p.on_opened({})   # no character at all
	await _settle()
	assert_eq(p.get_node_state(TreeDB.get_start_node("warrior")), "other_start", "no character: no own start")
	assert_eq(p.allocate_to(TreeDB.get_allocatable([], "warrior")[0]), 0, "no character: nothing allocated")
	assert_true(p.get_tooltip_lines(0).size() > 0, "tooltips still work")
	p.close_button.pressed.emit()
	assert_false(p.visible, "Close hides the standalone panel")


func test_mouse_filters() -> void:
	var p := _panel()
	await _settle()
	assert_eq(p.mouse_filter, Control.MOUSE_FILTER_STOP, "full-screen panel root stops the mouse")
	assert_eq(p.get_tree_canvas().mouse_filter, Control.MOUSE_FILTER_STOP, "tree surface stops the mouse")
	assert_eq(p.close_button.focus_mode, Control.FOCUS_NONE, "buttons never take focus")


func test_static_layer_not_rerecorded_while_panning() -> void:
	var p := _panel(5)
	await _settle(4)
	var canvas := p.get_tree_canvas()
	var r0 := int(canvas.get("static_records"))
	assert_true(r0 >= 1, "static layer recorded once opened")
	for i in 5:
		p.pan_by(Vector2(37, -21))
		await _settle(1)
	await _settle(2)
	assert_eq(int(canvas.get("static_records")), r0, "panning only moves the recorded layer")
	# A big zoom change re-records (pixel sizes are re-evaluated).
	p.zoom_at(canvas.get_global_rect().get_center(), 3.0)
	await _settle(3)
	var r1 := int(canvas.get("static_records"))
	assert_true(r1 > r0, "zooming x3 re-records")
	# Allocation changes the look: only the small state layer is re-recorded, the base stays.
	var s1 := int(canvas.get("state_records"))
	p.allocate_to(TreeDB.get_allocatable([], "warrior")[0])
	await _settle(3)
	assert_eq(int(canvas.get("state_records")), s1 + 1, "allocation re-records the state layer once")
	assert_eq(int(canvas.get("static_records")), r1, "allocation leaves the base layer alone")


## Zoomed out, the static layer holds the whole tree: idle frames and panning to any edge (also on a
## very wide screen) never re-record it (regression: it re-recorded every frame near the edges).
func test_zoomed_out_static_layer_holds_everywhere() -> void:
	var p := _panel(5)
	await _settle(3)
	var canvas := p.get_tree_canvas()
	var b := TreeDB.get_bounds()
	for x: float in [b.end.x, b.position.x, 0.0, b.end.x * 0.8]:
		p.set_view(Vector2(x, b.end.y * 0.5), 0.25)
		await _settle(3)
		var r := int(canvas.get("static_records")) + int(canvas.get("state_records"))
		await _settle(10)
		assert_eq(int(canvas.get("static_records")) + int(canvas.get("state_records")), r, "no re-record while idle at x=%d, zoom 0.25" % int(x))
	assert_true(bool(canvas.call("is_static_full")), "zoomed out: the whole tree is recorded")
	var r0 := int(canvas.get("static_records")) + int(canvas.get("state_records"))
	for i in 16:
		p.pan_by(Vector2(-500.0 if i < 8 else 500.0, 60.0 if i % 2 == 0 else -60.0))
		await _settle(1)
	await _settle(2)
	assert_eq(int(canvas.get("static_records")) + int(canvas.get("state_records")), r0, "panning across the zoomed-out tree never re-records")
	# A 32:9 screen at the minimum zoom sees more than the tree: still recorded once.
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.size = Vector2(3840, 1080)
	await _settle(3)
	p.set_view(Vector2(b.end.x, 0.0), 0.25)
	await _settle(3)
	var r1 := int(canvas.get("static_records"))
	await _settle(10)
	assert_eq(int(canvas.get("static_records")), r1, "wide screen at the right edge: no re-record")
	# Zoomed in, only the area around the view is recorded (and re-recorded when the view leaves it).
	p.set_view(Vector2.ZERO, 1.0)
	await _settle(3)
	assert_false(bool(canvas.call("is_static_full")), "zoomed in: culled recording")


## Allocating a long path rebuilds the panel state once (not once per passives_changed signal).
func test_long_path_allocation_refreshes_once() -> void:
	var p := _panel(30)
	await _settle(3)
	var c := GameState.character
	var target := _node_at_distance("warrior", 10)
	assert_true(target >= 0, "a node 10 steps away exists")
	var n0 := p.state_refreshes
	assert_eq(p.allocate_to(target), 10, "whole path allocated")
	assert_eq(p.state_refreshes - n0, 1, "one state rebuild for a 10-node path")
	await _settle(3)
	assert_eq(p.state_refreshes - n0, 1, "no extra rebuild on the next frames")
	assert_eq(p.get_node_state(target), "allocated", "state shows the allocation")
	# Changes made elsewhere are picked up once, on the next frame.
	c.add_gold(50)
	c.add_bonus_passive_points(1)
	await _settle(2)
	assert_eq(p.state_refreshes - n0, 2, "signals from elsewhere coalesce into one rebuild")
	# Refunding the tip: one rebuild, refund look only on the hovered node.
	c.gold = c.refund_cost() + 1
	await _settle(2)
	var n1 := p.state_refreshes
	p.hover_node(target)
	var refundable: Dictionary = p.get_tree_canvas().get("refundable")
	assert_true(refundable.has(target), "hovered tip is refundable")
	assert_true(p.refund(target), "tip refunded")
	assert_eq(p.state_refreshes - n1, 1, "one rebuild for a refund")
	assert_false(c.allocated_passives.has(target), "tip gone")

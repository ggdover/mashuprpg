extends Control
## Overview map of the whole passive tree (bottom-left of the panel): every link and node as a
## dot, allocated ones in gold, search matches in teal, and the visible area as a frame. Click or
## drag on it to move the main view there. Visible frame => MOUSE_FILTER_STOP.
## Internal: preload("res://scripts/ui/passive_tree/tree_panel_overview.gd").

signal jump_requested(tree_pos: Vector2)

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const TreeCanvas := preload("res://scripts/ui/passive_tree/tree_panel_canvas.gd")

## The main canvas (for the allocated/matches state and the visible rect).
var canvas: Control = null

var _segments := PackedVector2Array()   # tree-space line segments (arcs sampled)
var _built := false
var _dragging := false
var _dots: Node2D                        # links + node dots, redrawn only when the state changes
var _view: Node2D                        # the visible-area frame, every frame
var _sig := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(230, 230)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	_dots = Node2D.new()
	add_child(_dots)
	_dots.draw.connect(_draw_dots)
	_view = Node2D.new()
	add_child(_view)
	_view.draw.connect(_draw_view)


func _build() -> void:
	_built = true
	_segments = PackedVector2Array()
	for lk: Vector2i in TreeDB.get_links():
		var arc := TreeDB.get_link_arc(lk.x, lk.y)
		if arc.is_empty():
			_segments.append(TreeDB.get_node_position(lk.x))
			_segments.append(TreeDB.get_node_position(lk.y))
			continue
		var c: Vector2 = arc["centre"]
		var rad := float(arc["radius"])
		var a0 := float(arc["start_angle"])
		var a1 := float(arc["end_angle"])
		var steps := 5
		for i in steps:
			_segments.append(c + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * rad)
			_segments.append(c + Vector2.from_angle(lerpf(a0, a1, float(i + 1) / steps)) * rad)


## Tree rect mapped into this control (square, centred).
func _mapping() -> Array:
	var b := TreeDB.get_bounds().grow(120.0)
	var side := maxf(b.size.x, b.size.y)
	if side <= 0.0:
		side = 1.0
	var centre := b.get_center()
	var inner := minf(size.x, size.y) - 16.0
	var s := inner / side
	return [centre, s]


func tree_to_map(p: Vector2) -> Vector2:
	var m := _mapping()
	return (p - (m[0] as Vector2)) * float(m[1]) + size * 0.5


func map_to_tree(p: Vector2) -> Vector2:
	var m := _mapping()
	return (p - size * 0.5) / float(m[1]) + (m[0] as Vector2)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				jump_requested.emit(map_to_tree(mb.position))
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _dragging and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			jump_requested.emit(map_to_tree(mm.position))
		accept_event()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var sig := _state_signature()
	if sig != _sig:
		_sig = sig
		_dots.queue_redraw()
	_view.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_dots.queue_redraw()


func _state_signature() -> String:
	if canvas == null:
		return ""
	var alloc: Dictionary = canvas.get("allocated")
	var matches: Dictionary = canvas.get("matches")
	return "%d|%d|%d|%d|%d|%s" % [alloc.size(), alloc.hash(), matches.size(), matches.hash(), int(canvas.get("start_id")), size]


func _draw() -> void:
	var sb := MenuStyle.frame_style(Color(0.03, 0.03, 0.045, 0.88), UIStyle.COLOR_BORDER, 6, 0)
	sb.shadow_size = 10
	draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _draw_dots() -> void:
	if not _built:
		_build()
	var m := _mapping()
	var centre: Vector2 = m[0]
	var s := float(m[1])
	var off := size * 0.5
	_dots.draw_set_transform_matrix(Transform2D(0.0, Vector2(s, s), 0.0, off - centre * s))
	_dots.draw_multiline(_segments, Color(0.42, 0.38, 0.3, 0.55), -1.0)
	_dots.draw_set_transform_matrix(Transform2D.IDENTITY)
	var alloc: Dictionary = canvas.get("allocated") if canvas != null else {}
	var matches: Dictionary = canvas.get("matches") if canvas != null else {}
	var start_id: int = int(canvas.get("start_id")) if canvas != null else -1
	for id in TreeDB.get_all_ids():
		var nid := int(id)
		var t := TreeDB.get_node_type(nid)
		var p := tree_to_map(TreeDB.get_node_position(nid))
		var col: Color
		var r := 1.3
		if alloc.has(nid):
			col = TreeCanvas.GOLD
			r = 1.9
		elif matches.has(nid):
			col = TreeCanvas.SEARCH_COL
			r = 2.2
		else:
			col = Color(TreeDB.REGION_COLORS.get(TreeDB.get_region(nid), Color.WHITE), 0.55)
		if t == "notable":
			r += 0.8
		elif t == "keystone":
			r += 1.4
		elif t == "start":
			r = 4.0
			col = ClassDefs.get_color(TreeDB.get_start_class(nid))
			if nid != start_id:
				col = Color(col, 0.45)
		_dots.draw_circle(p, r, col, true, -1.0, true)
	_dots.draw_string(get_theme_default_font(), Vector2(10, size.y - 9), "OVERVIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UIStyle.COLOR_TEXT_DIM, 0.8))


func _draw_view() -> void:
	if canvas == null or not canvas.has_method("get_visible_tree_rect"):
		return
	var vr: Rect2 = canvas.call("get_visible_tree_rect")
	var a := tree_to_map(vr.position)
	var b := tree_to_map(vr.end)
	var view := Rect2(a, b - a).intersection(Rect2(Vector2.ZERO, size).grow(-3.0))
	if view.size.x > 0.0 and view.size.y > 0.0:
		_view.draw_rect(view, Color(1.0, 0.9, 0.6, 0.08), true)
		_view.draw_rect(view, Color(1.0, 0.88, 0.55, 0.8), false, 1.5)

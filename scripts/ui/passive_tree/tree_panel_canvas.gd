extends Control
## The drawing surface of the passive tree panel. Owns the view (pan / zoom around the cursor)
## and the raw mouse input; the allocation logic lives in PassiveTreePanel, which fills the state
## fields below. Visible surface => MOUSE_FILTER_STOP.
## Internal: preload("res://scripts/ui/passive_tree/tree_panel_canvas.gd").
##
## View math (local = this control's coordinates, tree = TreeDB units, y down):
##   local = (tree - view_center) * zoom + size / 2
##
## Drawing is layered for 60 fps at any zoom:
##   1. this control's _draw (every frame, cheap): background gradient + parallax starfield.
##   2. a static base Node2D layer, RECORDED in tree space (x the zoom at recording time) only when
##      the zoom settles at a new level (or a culled recording runs out, see CULL_ZOOM): nebulae,
##      the astrolabe ring, region titles, every link (orbit links as arcs via
##      TreeDB.get_link_arc) and every node, all in their locked look.
##   3. a state Node2D layer on top, recorded with the same transform, re-recorded when the
##      allocation changes: the allocatable / allocated links and nodes (they cover their locked
##      look below), so an allocation only redraws the build, not the whole tree.
##      Panning and zooming only change the two layers' transforms, so the recorded commands are
##      replayed without any script work.
##   4. an overlay Node2D (every frame, culled with TreeDB.get_nodes_in_rect): pulses of the
##      allocatable nodes, the path preview, search highlights, the own class start, the hovered
##      node, node labels, allocation bursts and the vignette.
## Circles and rings are drawn with small anti-aliased sprite textures (mipmapped), glows with
## MenuStyle's radial textures.

signal hover_changed(id: int)
## A node was clicked (press + release without dragging). button = MOUSE_BUTTON_LEFT / RIGHT.
signal node_clicked(id: int, button: int)
signal view_changed()

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const TreeGlyphs := preload("res://scripts/ui/passive_tree/tree_panel_glyphs.gd")

const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.0
const WHEEL_STEP := 1.2
const DRAG_THRESHOLD := 5.0
const VIEW_MARGIN := 350.0
## The static layer is re-recorded when the zoom leaves [rec / RERECORD_RATIO, rec * RERECORD_RATIO]
## or has rested at a new value for ZOOM_SETTLE seconds.
const RERECORD_RATIO := 1.6
const ZOOM_SETTLE := 0.12
## From this zoom on, the static layer only records the area around the view (the visible rect
## grown by one view size on every side) and re-records when the view leaves it (about once per
## view size of panning). Below it the whole tree is recorded, so panning never re-records.
const CULL_ZOOM := 0.45

const BG_TOP := Color(0.022, 0.024, 0.042)
const BG_BOTTOM := Color(0.045, 0.036, 0.032)
const LINK_DIM := Color(0.3, 0.27, 0.22, 0.85)
const LINK_FRONTIER := Color(0.62, 0.55, 0.4, 0.95)
const LINK_ALLOC := Color(1.0, 0.8, 0.36)
const GOLD := Color(1.0, 0.82, 0.4)
const GOLD_HOT := Color(1.0, 0.94, 0.7)
const BRONZE := Color(0.5, 0.39, 0.22)
const PATH_COL := Color(0.62, 0.9, 1.0)
const PATH_BAD := Color(1.0, 0.38, 0.3)
const SEARCH_COL := Color(0.4, 1.0, 0.85)
const NODE_FILL := Color(0.055, 0.05, 0.045)
const NODE_DARK := Color(0.02, 0.018, 0.016)
const REFUND_COL := Color(1.0, 0.35, 0.28)
## Attribute node colours (by the attribute they give).
const ATTR_COLORS := {
	"strength": Color(0.92, 0.36, 0.3), "dexterity": Color(0.42, 0.85, 0.4), "intelligence": Color(0.45, 0.6, 1.0),
}
## Direction of each region (degrees, y down) for the background nebulae and region titles.
const REGION_ANGLES := {"str": 150.0, "dex": 30.0, "int": -90.0, "str_dex": 90.0, "dex_int": -30.0, "int_str": -150.0}

enum { S_LOCKED, S_FRONTIER, S_ALLOCATED, S_PATH, S_PATH_BAD }

## Tree units at the centre of the control.
var view_center := Vector2.ZERO
## Screen pixels per tree unit (MIN_ZOOM..MAX_ZOOM).
var zoom := 0.8
## Wheel zoom is animated (tests turn it off for exact math).
var smooth_zoom := true

# ---- state filled by the panel (setters re-record the static layer)
## Allocated node ids (the class start included) -> true.
var allocated: Dictionary = {}:
	set(v):
		allocated = v
		_mark_state()
## Allocatable (frontier) node ids -> true.
var frontier: Dictionary = {}:
	set(v):
		frontier = v
		_mark_state()
## Allocated nodes that can be refunded right now -> true.
var refundable: Dictionary = {}
var class_id: String = "":
	set(v):
		if v != class_id:
			class_id = v
			_mark_static()
var start_id: int = -1:
	set(v):
		if v != start_id:
			start_id = v
			_mark_static()
## Path preview (ordered ids, from the allocated set towards the hovered node).
var path: Array = []
## How many of `path` the unspent points cover.
var affordable: int = 0
## Search matches -> true.
var matches: Dictionary = {}
## Node under the mouse (-1 = none).
var hovered: int = -1
## Show the refund preview (hovered allocated node would be refunded by a right-click).
var refund_preview: bool = false

## Microseconds the last per-frame draw took (background + overlay), the last static base
## recording and the last state-layer recording (CPU side; the demo prints them).
var last_draw_usec: int = 0
var last_static_usec: int = 0
var last_state_usec: int = 0
## How many times the static base layer / the state layer was recorded (tests / perf checks).
var static_records: int = 0
var state_records: int = 0

static var _disc_tex: Texture2D = null
static var _ring_tex: Texture2D = null
static var _ring_thin_tex: Texture2D = null

var _t := 0.0
var _zoom_target := 0.8
var _zoom_anchor := Vector2.ZERO
var _center_target := Vector2.ZERO
var _centering := false
var _press_button := 0
var _press_pos := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _dragging := false
var _mouse_inside := false
var _bursts: Array = []            # [id, age, kind ("alloc" | "refund")]
var _path_links: Dictionary = {}   # Vector2i(min, max) -> index along the path
var _path_set: Dictionary = {}     # id -> index along the path
var _font: Font
var _title_font: Font
var _heading_font: Font
var _static: Node2D
var _state: Node2D
var _overlay: Node2D
var _static_dirty := true
var _state_dirty := true
var _rec_zoom := -1.0
var _rec_rect := Rect2()           # tree area recorded in the static layer (culling)
var _rec_full := false             # the whole tree is recorded (recorded below CULL_ZOOM)
var _zoom_rest := 0.0
var _overlay_t0 := 0
# Precomputed node / link data.
var _data_ready := false
var _npos: Dictionary = {}         # id -> Vector2
var _ntype: Dictionary = {}        # id -> String
var _nrad: Dictionary = {}         # id -> float (tree units)
var _ncol: Dictionary = {}         # id -> Color
var _order: Array[int] = []        # static draw order (small first)
var _links: Array = []             # [a, b, arc Dictionary]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_static = Node2D.new()
	_static.name = "StaticLayer"
	_static.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_static)
	_static.draw.connect(_draw_static)
	_state = Node2D.new()
	_state.name = "StateLayer"
	_state.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_state)
	_state.draw.connect(_draw_state)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func _ready() -> void:
	_font = get_theme_default_font()
	_title_font = MenuStyle.title_font()
	_heading_font = MenuStyle.heading_font()
	_zoom_target = zoom
	_ensure_textures()


# ------------------------------------------------------------------ view math

func tree_to_local(p: Vector2) -> Vector2:
	return (p - view_center) * zoom + size * 0.5


func local_to_tree(p: Vector2) -> Vector2:
	return (p - size * 0.5) / zoom + view_center


## Tree rectangle currently visible.
func get_visible_tree_rect() -> Rect2:
	return Rect2(local_to_tree(Vector2.ZERO), size / zoom)


## Zoom so that the tree point under `local_pos` stays under it. Immediate.
func set_zoom_at(local_pos: Vector2, new_zoom: float) -> void:
	var before := local_to_tree(local_pos)
	zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	view_center = before - (local_pos - size * 0.5) / zoom
	_clamp_view()
	_view_moved(true)


## Multiply the zoom around `local_pos` (immediate; cancels any running zoom animation).
func zoom_at(local_pos: Vector2, factor: float) -> void:
	set_zoom_at(local_pos, zoom * factor)
	_zoom_target = zoom


## Animated zoom towards `zoom * factor` (mouse wheel). Falls back to zoom_at when smooth_zoom is off.
func zoom_smooth(local_pos: Vector2, factor: float) -> void:
	if not smooth_zoom:
		zoom_at(local_pos, factor)
		return
	_zoom_target = clampf(_zoom_target * factor, MIN_ZOOM, MAX_ZOOM)
	_zoom_anchor = local_pos


## Target of the running zoom animation (== zoom when idle).
func get_target_zoom() -> float:
	return _zoom_target


## Move the view by a screen-space delta (dragging moves the tree with the mouse).
func pan_by(local_delta: Vector2) -> void:
	_centering = false
	view_center -= local_delta / zoom
	_clamp_view()
	_view_moved(false)


## Centre the view on a tree position, optionally animated, optionally changing the zoom.
func center_on(tree_pos: Vector2, animated: bool = false, new_zoom: float = -1.0) -> void:
	var zoomed := false
	if new_zoom > 0.0:
		zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
		_zoom_target = zoom
		zoomed = true
	if animated and is_inside_tree():
		_center_target = tree_pos
		_centering = true
		if zoomed:
			_view_moved(true)
	else:
		_centering = false
		view_center = tree_pos
		_clamp_view()
		_view_moved(zoomed)


func _clamp_view() -> void:
	var b := TreeDB.get_bounds().grow(VIEW_MARGIN)
	if b.size == Vector2.ZERO:
		return
	view_center = view_center.clamp(b.position, b.end)


func _view_moved(zoom_changed: bool) -> void:
	if zoom_changed:
		_zoom_rest = 0.0
	_update_static_transform()
	view_changed.emit()
	queue_redraw()
	_overlay.queue_redraw()


func _update_static_transform() -> void:
	if _rec_zoom <= 0.0:
		return
	var s := zoom / _rec_zoom
	for layer: Node2D in [_static, _state]:
		layer.scale = Vector2(s, s)
		layer.position = size * 0.5 - view_center * zoom


## Re-record everything (base + state) next frame.
func _mark_static() -> void:
	_static_dirty = true
	_state_dirty = true


## Re-record only the state layer next frame (the allocation changed).
func _mark_state() -> void:
	_state_dirty = true


## Re-record the recorded layers now if they are out of date: both when the zoom changed a lot
## (or settled) or a culled recording ran out, only the state layer when the allocation changed.
func _maybe_rerecord() -> void:
	var need := _static_dirty or _rec_zoom <= 0.0
	if not need:
		var ratio := zoom / _rec_zoom
		need = ratio > RERECORD_RATIO or ratio < 1.0 / RERECORD_RATIO
		if not need and absf(ratio - 1.0) > 0.001 and _zoom_rest >= ZOOM_SETTLE:
			need = true
		# A full recording covers every view position: only a culled one can run out.
		if not need and not _rec_full and not _rec_rect.encloses(get_visible_tree_rect()):
			need = true
	if need:
		_static_dirty = false
		_rec_zoom = zoom
		_rec_full = zoom < CULL_ZOOM
		if _rec_full:
			_rec_rect = TreeDB.get_bounds().grow(VIEW_MARGIN)
		else:
			var vis := get_visible_tree_rect()
			_rec_rect = vis.grow_individual(vis.size.x, vis.size.y, vis.size.x, vis.size.y)
		_update_static_transform()
		_static.queue_redraw()
		_state_dirty = true
	if _state_dirty:
		_state_dirty = false
		_state.queue_redraw()


## True when the static layer holds the whole tree (recorded zoomed out), false when it holds only
## the area around the view.
func is_static_full() -> bool:
	return _rec_full


# ------------------------------------------------------------------ state helpers

## Recompute the link lookup of the path preview (call after changing `path`).
func set_path(p_path: Array, p_affordable: int) -> void:
	path = p_path
	affordable = p_affordable
	_path_links.clear()
	_path_set.clear()
	var prev := -1
	# The first path node links to an allocated neighbour (or the start): find it.
	if not path.is_empty():
		for nb in TreeDB.get_neighbors(int(path[0])):
			if allocated.has(int(nb)):
				prev = int(nb)
				break
	for i in path.size():
		var id := int(path[i])
		_path_set[id] = i
		if prev >= 0:
			_path_links[Vector2i(mini(prev, id), maxi(prev, id))] = i
		prev = id
	_overlay.queue_redraw()


## Expanding ring effect on a node ("alloc" gold, "refund" red).
func add_burst(id: int, kind: String = "alloc", delay: float = 0.0) -> void:
	_bursts.append([id, -delay, kind])


## The node under a local position (-1 if none).
func node_at_local(local_pos: Vector2) -> int:
	var slack := clampf(7.0 / zoom, 4.0, 30.0)
	return TreeDB.find_node_at(local_to_tree(local_pos), slack)


## Screen-space rect (local) of a node.
func node_local_rect(id: int) -> Rect2:
	var c := tree_to_local(TreeDB.get_node_position(id))
	var r := maxf(4.0, TreeDB.get_node_radius(id) * zoom)
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


func is_dragging() -> bool:
	return _dragging


## The node's main colour: region colour, or the attribute's colour for attribute nodes.
func node_color(id: int) -> Color:
	_ensure_data()
	return _ncol.get(id, Color(0.8, 0.78, 0.7))


# ------------------------------------------------------------------ input & process

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var f := WHEEL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_STEP
					if mb.factor > 0.0 and mb.factor != 1.0:
						f = pow(f, clampf(mb.factor, 0.1, 3.0))
					zoom_smooth(mb.position, f)
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					if get_viewport() != null:
						get_viewport().gui_release_focus()
					_press_button = mb.button_index
					_press_pos = mb.position
					_last_mouse = mb.position
					_dragging = false
				elif mb.button_index == _press_button:
					var was_drag := _dragging
					_dragging = false
					_press_button = 0
					mouse_default_cursor_shape = Control.CURSOR_ARROW
					_set_hovered(node_at_local(mb.position))
					if not was_drag and mb.button_index != MOUSE_BUTTON_MIDDLE and hovered >= 0:
						node_clicked.emit(hovered, mb.button_index)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse_inside = true
		if _press_button != 0:
			if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
				mouse_default_cursor_shape = Control.CURSOR_DRAG
				_set_hovered(-1)
			if _dragging:
				pan_by(mm.position - _last_mouse)
		_last_mouse = mm.position
		if not _dragging:
			_set_hovered(node_at_local(mm.position))
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_mouse_inside = false
			if not _dragging:
				_set_hovered(-1)
		NOTIFICATION_RESIZED:
			_clamp_view()
			_update_static_transform()
			queue_redraw()
			if _overlay != null:
				_overlay.queue_redraw()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				_dragging = false
				_press_button = 0
				_bursts.clear()


func _set_hovered(id: int) -> void:
	if id == hovered:
		return
	hovered = id
	hover_changed.emit(id)
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_zoom_rest += delta
	var moved := false
	var zoomed := false
	if absf(_zoom_target - zoom) > 0.0005:
		var nz := lerpf(zoom, _zoom_target, 1.0 - exp(-delta * 16.0))
		if absf(_zoom_target - nz) < 0.001:
			nz = _zoom_target
		var before := local_to_tree(_zoom_anchor)
		zoom = nz
		view_center = before - (_zoom_anchor - size * 0.5) / zoom
		_clamp_view()
		moved = true
		zoomed = true
	if _centering:
		view_center = view_center.lerp(_center_target, 1.0 - exp(-delta * 9.0))
		if view_center.distance_to(_center_target) * zoom < 0.5:
			view_center = _center_target
			_centering = false
		_clamp_view()
		moved = true
	if moved:
		_view_moved(zoomed)
		if _mouse_inside and not _dragging:
			_set_hovered(node_at_local(get_local_mouse_position()))
	_maybe_rerecord()
	for b: Array in _bursts:
		b[1] = float(b[1]) + delta
	_bursts = _bursts.filter(func(b: Array) -> bool: return float(b[1]) < 0.8)
	queue_redraw()
	_overlay.queue_redraw()


# ------------------------------------------------------------------ data & textures

func _ensure_data() -> void:
	if _data_ready:
		return
	_data_ready = true
	var smalls: Array[int] = []
	var bigs: Array[int] = []
	for raw in TreeDB.get_all_ids():
		var id := int(raw)
		var n := TreeDB.get_passive(id)
		var t := String(n.get("type", "small"))
		_npos[id] = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
		_ntype[id] = t
		_nrad[id] = float(TreeDB.NODE_RADIUS.get(t, 14.0))
		var col: Color = TreeDB.REGION_COLORS.get(String(n.get("region", "")), Color(0.8, 0.78, 0.7))
		if t == "attribute":
			col = Color(0.7, 0.66, 0.58)
			var mods: Array = n.get("mods", [])
			if not mods.is_empty():
				col = ATTR_COLORS.get(String((mods[0] as Dictionary).get("stat", "")), col)
		elif t == "start":
			col = ClassDefs.get_color(String(n.get("class", "")))
		_ncol[id] = col
		if t == "small" or t == "attribute":
			smalls.append(id)
		else:
			bigs.append(id)
	smalls.sort()
	bigs.sort()
	_order = smalls
	_order.append_array(bigs)
	for lk: Vector2i in TreeDB.get_links():
		_links.append([lk.x, lk.y, TreeDB.get_link_arc(lk.x, lk.y)])


static func _ensure_textures() -> void:
	if _disc_tex != null:
		return
	_disc_tex = _make_circle_tex(0.0)
	_ring_tex = _make_circle_tex(0.8)
	_ring_thin_tex = _make_circle_tex(0.9)


## White anti-aliased disc (inner = 0) or ring (inner = inner radius / outer radius), mipmapped.
static func _make_circle_tex(inner: float) -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n * 0.5
	var ro := c - 1.0
	var ri := ro * inner
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			var a := clampf(ro - d + 0.5, 0.0, 1.0)
			if inner > 0.0:
				a *= clampf(d - ri + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(_disc_tex, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, col)


## Ring of outer radius r (thickness 0.2 r; thin = 0.1 r).
func _ring(ci: CanvasItem, c: Vector2, r: float, col: Color, thin: bool = false) -> void:
	ci.draw_texture_rect(_ring_thin_tex if thin else _ring_tex, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, col)


# ------------------------------------------------------------------ background (every frame)

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	_overlay_t0 = Time.get_ticks_usec()
	_ensure_data()
	_ensure_textures()
	var w := size.x
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
	var stars := MenuStyle.stars_texture()
	for layer in 2:
		var par := 0.12 if layer == 0 else 0.3
		var sc := 1.0 if layer == 0 else 1.6
		var tile := Vector2(512, 512) * sc
		var off := Vector2(fposmod(-view_center.x * zoom * par, tile.x), fposmod(-view_center.y * zoom * par, tile.y))
		draw_texture_rect(stars, Rect2(off - tile, size + tile * 2.0), true, Color(1, 1, 1, 0.55 if layer == 0 else 0.35))


# ------------------------------------------------------------------ recorded layers

## The static base layer: decorations plus every link and node in its locked look.
func _draw_static() -> void:
	if size.x < 2.0 or _rec_zoom <= 0.0:
		return
	var t0 := Time.get_ticks_usec()
	_ensure_data()
	_ensure_textures()
	var ci := _static
	var sc := _rec_zoom
	# Region nebulae.
	for region: String in REGION_ANGLES:
		var dir := Vector2.from_angle(deg_to_rad(float(REGION_ANGLES[region])))
		var col: Color = TreeDB.REGION_COLORS.get(region, Color.WHITE)
		MenuStyle.draw_glow(ci, dir * 1350.0 * sc, 1500.0 * sc, Color(col, 0.085), true)
		MenuStyle.draw_glow(ci, dir * 2000.0 * sc, 900.0 * sc, Color(col.darkened(0.2), 0.06), true)
	MenuStyle.draw_glow(ci, Vector2.ZERO, 900.0 * sc, Color(1.0, 0.85, 0.6, 0.07), true)
	_draw_decorations(ci, sc)
	var base_w := maxf(1.2, 3.2 * sc)
	for lk: Array in _links:
		if _rec_full or _rec_rect.intersects(_link_bounds(lk)):
			_stroke(ci, lk, sc, Vector2.ZERO, LINK_DIM, base_w)
	# Culled with TreeDB.get_nodes_in_rect when zoomed in (the recorded area around the view).
	var in_area := {}
	if not _rec_full:
		for id in TreeDB.get_nodes_in_rect(_rec_rect, 60.0):
			in_area[id] = true
	for id in _order:
		if id == start_id or (not _rec_full and not in_area.has(id)):
			continue   # the own start is animated (overlay)
		_draw_node(ci, id, _npos[id] * sc, maxf(2.5, float(_nrad[id]) * sc), S_LOCKED, false)
	static_records += 1
	last_static_usec = Time.get_ticks_usec() - t0


## The state layer (same transform as the base): the allocatable and allocated links and nodes,
## drawn over their locked look.
func _draw_state() -> void:
	if size.x < 2.0 or _rec_zoom <= 0.0:
		return
	var t0 := Time.get_ticks_usec()
	_ensure_data()
	_ensure_textures()
	var ci := _state
	var sc := _rec_zoom
	_draw_state_links(ci, sc)
	var area := _rec_rect.grow(60.0)
	for id in _order:
		if id == start_id or _ntype[id] == "start":
			continue
		var st := S_ALLOCATED if allocated.has(id) else (S_FRONTIER if frontier.has(id) else S_LOCKED)
		if st == S_LOCKED or not (_rec_full or area.has_point(_npos[id])):
			continue
		_draw_node(ci, id, _npos[id] * sc, maxf(2.5, float(_nrad[id]) * sc), st, false)
	state_records += 1
	last_state_usec = Time.get_ticks_usec() - t0


func _draw_decorations(ci: CanvasItem, sc: float) -> void:
	var outer := 2290.0 * sc
	ci.draw_arc(Vector2.ZERO, outer, 0, TAU, 256, Color(BRONZE, 0.35), maxf(1.0, 3.0 * sc), true)
	ci.draw_arc(Vector2.ZERO, outer + 16.0 * sc, 0, TAU, 256, Color(BRONZE, 0.18), maxf(1.0, 1.5 * sc), true)
	var ticks := PackedVector2Array()
	for i in 72:
		var d := Vector2.from_angle(TAU * i / 72.0)
		var l := (26.0 if i % 6 == 0 else 12.0) * sc
		ticks.append(d * outer)
		ticks.append(d * (outer - l))
	ci.draw_multiline(ticks, Color(BRONZE, 0.3), maxf(1.0, 2.0 * sc))
	for i in 12:
		var a := TAU * i / 12.0 + PI / 12.0
		MenuStyle.draw_diamond(ci, Vector2.from_angle(a) * (outer + 8.0 * sc), maxf(2.0, 9.0 * sc), Color(BRONZE, 0.45))
	# Region titles just outside the outer ring.
	var fs := int(clampf(62.0 * sc, 13.0, 64.0))
	for region: String in REGION_ANGLES:
		var dir := Vector2.from_angle(deg_to_rad(float(REGION_ANGLES[region])))
		var p := dir * 2450.0 * sc
		var text := String(TreeDB.REGION_NAMES.get(region, region)).to_upper()
		var col: Color = TreeDB.REGION_COLORS.get(region, Color.WHITE)
		var tw := _title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(_title_font, p + Vector2(-tw * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.2), 0.2))


## Links of the state layer: allocated -> allocatable links, then the allocated links (glow + core).
## The dim link of the base layer lies under each of them.
func _draw_state_links(ci: CanvasItem, sc: float) -> void:
	var base_w := maxf(1.2, 3.2 * sc)
	var alloc_links: Array = []
	for lk: Array in _links:
		var a: int = lk[0]
		var b: int = lk[1]
		var a_al := allocated.has(a)
		var b_al := allocated.has(b)
		if not (a_al or b_al):
			continue
		if not _rec_full and not _rec_rect.intersects(_link_bounds(lk)):
			continue
		if a_al and b_al:
			alloc_links.append(lk)
		elif (a_al and frontier.has(b)) or (b_al and frontier.has(a)):
			_stroke(ci, lk, sc, Vector2.ZERO, LINK_FRONTIER, base_w * 1.25)
	for lk: Array in alloc_links:
		_stroke(ci, lk, sc, Vector2.ZERO, Color(GOLD, 0.16), maxf(4.0, 14.0 * sc))
	for lk: Array in alloc_links:
		_stroke(ci, lk, sc, Vector2.ZERO, LINK_ALLOC, maxf(2.0, 5.5 * sc))
		_stroke(ci, lk, sc, Vector2.ZERO, Color(GOLD_HOT, 0.8), maxf(1.0, 1.6 * sc))


## Bounding box of a link (arcs bulge a little: grown by 15% of the chord).
func _link_bounds(lk: Array) -> Rect2:
	var pa: Vector2 = _npos[lk[0]]
	var bb := Rect2(pa, Vector2.ZERO).expand(_npos[lk[1]])
	return bb.grow(bb.size.length() * 0.15 + 20.0)


## Stroke a link ([a, b, arc]) mapped by p = tree * sc + off.
func _stroke(ci: CanvasItem, lk: Array, sc: float, off: Vector2, col: Color, width: float) -> void:
	var arc: Dictionary = lk[2]
	if arc.is_empty():
		ci.draw_line(_npos[lk[0]] * sc + off, _npos[lk[1]] * sc + off, col, width, true)
		return
	var r := float(arc["radius"]) * sc
	var a0 := float(arc["start_angle"])
	var a1 := float(arc["end_angle"])
	var pts := clampi(int(r * absf(a1 - a0) / 7.0), 6, 96)
	ci.draw_arc((arc["centre"] as Vector2) * sc + off, r, a0, a1, pts, col, width, true)


## One node at `c` (target coordinates) with drawn radius `r` (px) in state `st`.
func _draw_node(ci: CanvasItem, id: int, c: Vector2, r: float, st: int, hover: bool) -> void:
	var t: String = _ntype[id]
	var col: Color = _ncol[id]
	if t == "start":
		_draw_start(ci, id, c, r, hover)
		return
	var ring := Color(col.darkened(0.52), 0.95)
	var fill := NODE_FILL
	var core := col.darkened(0.5)
	var frame_col := BRONZE.darkened(0.22)
	match st:
		S_ALLOCATED:
			MenuStyle.draw_glow(ci, c, r * 3.2, Color(GOLD, 0.42))
			ring = GOLD
			fill = col.darkened(0.35).lerp(GOLD, 0.2)
			core = col.lightened(0.35)
			frame_col = GOLD
		S_PATH, S_PATH_BAD:
			var pc := PATH_COL if st == S_PATH else PATH_BAD
			MenuStyle.draw_glow(ci, c, r * 3.0, Color(pc, 0.4))
			ring = pc
			fill = col.darkened(0.6)
			core = col.lerp(pc, 0.3)
			frame_col = BRONZE.lightened(0.25)
		S_FRONTIER:
			MenuStyle.draw_glow(ci, c, r * 2.6, Color(col.lightened(0.2), 0.22))
			ring = col.lightened(0.35)
			fill = col.darkened(0.7)
			core = col.lightened(0.1)
			frame_col = BRONZE.lightened(0.25)
	if hover:
		MenuStyle.draw_glow(ci, c, r * 3.4, Color(1, 1, 1, 0.18))
		ring = ring.lightened(0.35)
		if st == S_ALLOCATED and refund_preview and refundable.has(id):
			ring = REFUND_COL
	var lit := st != S_LOCKED
	match t:
		"keystone":
			_draw_star_frame(ci, c, r * 1.32, frame_col, 8)
			_disc(ci, c, r * 1.02, NODE_DARK)
			_disc(ci, c, r * 0.92, fill if st == S_ALLOCATED else fill.darkened(0.25))
			_ring(ci, c, r * 0.95, ring, true)
			if r >= 9.0:
				_draw_glyph(ci, id, c, r * 0.6, col, st)
			else:
				_disc(ci, c, r * 0.5, core)
		"notable":
			_disc(ci, c, r * 1.2, NODE_DARK)
			_ring(ci, c, r * 1.2, frame_col)
			if r >= 6.0:
				for k in 4:
					MenuStyle.draw_diamond(ci, c + Vector2.from_angle(PI * 0.25 + k * PI * 0.5) * r * 1.14, maxf(1.5, r * 0.17), frame_col)
			_disc(ci, c, r * 0.94, fill if st == S_ALLOCATED else fill.darkened(0.2))
			_ring(ci, c, r * 0.94, ring, true)
			if r >= 9.0:
				_draw_glyph(ci, id, c, r * 0.58, col, st)
			else:
				_disc(ci, c, r * 0.5, core)
		"attribute":
			_disc(ci, c, r, fill)
			_ring(ci, c, r, ring)
			if r >= 5.0:
				MenuStyle.draw_diamond(ci, c, r * 0.5, core)
			else:
				_disc(ci, c, r * 0.45, core)
		_:
			_disc(ci, c, r, fill)
			_ring(ci, c, r, ring)
			if r >= 15.0:
				_draw_glyph(ci, id, c, r * 0.55, col, st)
			else:
				_disc(ci, c, r * 0.52, core)
				if lit and r >= 5.0:
					_disc(ci, c - Vector2(r, r) * 0.16, r * 0.17, Color(1, 1, 1, 0.4 if st == S_ALLOCATED else 0.25))


func _draw_glyph(ci: CanvasItem, id: int, c: Vector2, s: float, node_col: Color, st: int) -> void:
	var kind := TreeGlyphs.glyph_for(id)
	var gc := TreeGlyphs.glyph_color(kind, node_col.lightened(0.25))
	match st:
		S_ALLOCATED:
			gc = gc.lerp(Color(1.0, 0.97, 0.88), 0.45)
		S_PATH, S_PATH_BAD:
			gc = gc.lerp(PATH_COL if st == S_PATH else PATH_BAD, 0.3)
		S_FRONTIER:
			gc = gc.lightened(0.1)
		_:
			gc = Color(gc.darkened(0.35), 0.75)
	TreeGlyphs.draw(ci, kind, c, s, gc)


func _draw_star_frame(ci: CanvasItem, c: Vector2, r: float, col: Color, points: int) -> void:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI * 0.5 + PI * i / float(points)
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.82))
	ci.draw_colored_polygon(pts, col)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.88)
	ci.draw_colored_polygon(inner, col.darkened(0.45))


func _draw_start(ci: CanvasItem, id: int, c: Vector2, r: float, hover: bool) -> void:
	var cid := TreeDB.get_start_class(id)
	var col: Color = _ncol[id]
	if id == start_id:
		var pulse := 0.5 + 0.5 * sin(_t * 2.0)
		MenuStyle.draw_glow(ci, c, r * 4.2, Color(col, 0.28 + 0.1 * pulse), true)
		MenuStyle.draw_glow(ci, c, r * 2.4, Color(GOLD, 0.35))
		_disc(ci, c, r * 1.24, NODE_DARK)
		_ring(ci, c, r * 1.24, GOLD, true)
		ci.draw_arc(c, r * 1.02, 0, TAU, 64, Color(GOLD, 0.5), maxf(1.0, r * 0.04), true)
		for k in 8:
			var a := k * TAU / 8.0 + _t * 0.15
			MenuStyle.draw_diamond(ci, c + Vector2.from_angle(a) * r * 1.36, maxf(1.5, r * (0.1 if k % 2 == 0 else 0.06)), GOLD)
		_disc(ci, c, r * 0.92, col.darkened(0.7))
		_ring(ci, c, r * 0.92, col, true)
		MenuStyle.draw_class_glyph(ci, cid, c, r * 0.55, col.lightened(0.35))
	else:
		var dim := col.lerp(Color(0.4, 0.4, 0.4), 0.55)
		_disc(ci, c, r * 1.12, NODE_DARK)
		_ring(ci, c, r * 1.1, Color(dim.darkened(0.3), 0.9), true)
		_disc(ci, c, r * 0.9, Color(dim.darkened(0.78), 1.0))
		ci.draw_arc(c, r * 0.88, 0, TAU, 48, Color(dim, 0.6), maxf(1.0, r * 0.05), true)
		MenuStyle.draw_class_glyph(ci, cid, c, r * 0.5, Color(dim, 0.55))
	if hover:
		ci.draw_arc(c, r * 1.32, 0, TAU, 48, Color(1, 1, 1, 0.5), maxf(1.0, r * 0.05), true)


# ------------------------------------------------------------------ overlay (every frame)

func _draw_overlay() -> void:
	if size.x < 2.0:
		return
	_ensure_data()
	_ensure_textures()
	var ci := _overlay
	var sc := zoom
	var off := size * 0.5 - view_center * zoom
	var view := get_visible_tree_rect().grow(60.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_draw_motes(ci, sc, off, view)
	# Pulsing halo on the allocatable nodes.
	for raw in frontier:
		var id := int(raw)
		if _path_set.has(id) or id == hovered:
			continue
		var p: Vector2 = _npos.get(id, Vector2.INF)
		if not view.has_point(p):
			continue
		var c := p * sc + off
		var r := maxf(2.5, float(_nrad[id]) * sc)
		var ph := 0.5 + 0.5 * sin(_t * 4.0 + float(id) * 0.37)
		MenuStyle.draw_glow(ci, c, r * 3.0, Color(_ncol[id].lightened(0.3), 0.1 + 0.2 * ph))
		_ring(ci, c, r * (1.3 + 0.12 * ph), Color(1.0, 0.95, 0.8, 0.3 + 0.35 * ph), true)
	# Path preview: links then nodes.
	if not _path_links.is_empty():
		for lk: Array in _links:
			var key := Vector2i(mini(lk[0], lk[1]), maxi(lk[0], lk[1]))
			if not _path_links.has(key) or not view.intersects(_link_bounds(lk)):
				continue
			var ok := int(_path_links[key]) < affordable
			var pcol := PATH_COL if ok else PATH_BAD
			_stroke(ci, lk, sc, off, Color(pcol, 0.18 + 0.12 * pulse), maxf(4.0, 14.0 * sc))
			_stroke(ci, lk, sc, off, Color(pcol, 0.75 + 0.25 * pulse), maxf(2.0, 5.0 * sc))
	for i in path.size():
		var id := int(path[i])
		if id == hovered or not _npos.has(id):
			continue
		_draw_node(ci, id, _npos[id] * sc + off, maxf(2.5, float(_nrad[id]) * sc), S_PATH if i < affordable else S_PATH_BAD, false)
	# Search highlights.
	for raw in matches:
		var id := int(raw)
		var p: Vector2 = _npos.get(id, Vector2.INF)
		if not view.has_point(p):
			continue
		var c := p * sc + off
		var r := maxf(2.5, float(_nrad[id]) * sc)
		var ph := 0.5 + 0.5 * sin(_t * 4.0 + float(id) * 0.37)
		MenuStyle.draw_glow(ci, c, r * 3.6, Color(SEARCH_COL, 0.28 + 0.22 * ph))
		_ring(ci, c, r * (1.6 + 0.15 * ph), Color(SEARCH_COL, 0.9), true)
	# The own class start (animated).
	if start_id >= 0 and _npos.has(start_id) and view.has_point(_npos[start_id]):
		_draw_start(ci, start_id, _npos[start_id] * sc + off, maxf(2.5, float(_nrad[start_id]) * sc), hovered == start_id)
	# The hovered node, slightly enlarged, on top.
	if hovered >= 0 and hovered != start_id and _npos.has(hovered):
		var st := S_LOCKED
		if allocated.has(hovered):
			st = S_ALLOCATED
		elif _path_set.has(hovered):
			st = S_PATH if int(_path_set[hovered]) < affordable else S_PATH_BAD
		elif frontier.has(hovered):
			st = S_FRONTIER
		_draw_node(ci, hovered, _npos[hovered] * sc + off, maxf(2.5, float(_nrad[hovered]) * sc) * 1.12, st, true)
	elif hovered >= 0 and _npos.has(hovered):
		pass
	_draw_labels(ci, sc, off, view)
	_draw_bursts(ci, sc, off)
	ci.draw_texture_rect(MenuStyle.vignette_texture(), Rect2(-size * 0.1, size * 1.2), false, Color(1, 1, 1, 0.85))
	last_draw_usec = Time.get_ticks_usec() - _overlay_t0


## Small light motes drifting along the allocated links (energy flowing through the build).
func _draw_motes(ci: CanvasItem, sc: float, off: Vector2, view: Rect2) -> void:
	if allocated.size() < 2:
		return
	var mr := maxf(1.2, 3.2 * sc)
	for lk: Array in _links:
		var a: int = lk[0]
		var b: int = lk[1]
		if not (allocated.has(a) and allocated.has(b)):
			continue
		if not view.intersects(_link_bounds(lk)):
			continue
		var k := fposmod(_t * 0.22 + float((a * 7919 + b * 104729) % 1000) / 1000.0, 1.0)
		var p: Vector2
		var arc: Dictionary = lk[2]
		if arc.is_empty():
			p = (_npos[a] as Vector2).lerp(_npos[b], k)
		else:
			var ang := lerpf(float(arc["start_angle"]), float(arc["end_angle"]), k)
			p = (arc["centre"] as Vector2) + Vector2.from_angle(ang) * float(arc["radius"])
		var fade := sin(k * PI)
		var c := p * sc + off
		MenuStyle.draw_glow(ci, c, mr * 4.0, Color(GOLD_HOT, 0.35 * fade))
		_disc(ci, c, mr, Color(1.0, 0.98, 0.9, 0.85 * fade))


func _draw_labels(ci: CanvasItem, sc: float, off: Vector2, view: Rect2) -> void:
	for id in TreeDB.get_nodes_in_rect(view, 0.0):
		var fs := _label_font_size(String(_ntype.get(id, "")))
		if fs > 0:
			_draw_node_label(ci, id, (_npos[id] as Vector2) * sc + off, fs)


## Font size of a node type's name label at the current zoom (0 = no label): class starts always,
## keystones from zoom 0.42, notables from 0.62.
func _label_font_size(t: String) -> int:
	var fs := int(clampf(15.0 * zoom + 3.0, 11.0, 22.0))
	if zoom < 0.42:
		return 13 if t == "start" else 0
	match t:
		"start":
			return fs + 4
		"keystone":
			return fs + 1
		"notable":
			return fs - 1 if zoom >= 0.62 else 0
	return 0


## Font, text and baseline (local) of a node's name label.
func _label_layout(id: int, c: Vector2, fs: int) -> Array:
	var t: String = _ntype[id]
	var r := float(_nrad[id]) * zoom
	var text := String(TreeDB.get_passive(id).get("name", ""))
	var font := _heading_font if t in ["start", "keystone"] else _font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := c.y + r * (1.5 if t == "keystone" else 1.3) + fs + 2.0
	return [font, text, Vector2(c.x - tw * 0.5, y), tw]


## Screen-space rect (local) of a node's name label at the current zoom (empty when none is drawn),
## so tooltips can sit beside the label instead of covering it.
func node_label_local_rect(id: int) -> Rect2:
	_ensure_data()
	if not _ntype.has(id) or _font == null or _heading_font == null:
		return Rect2()
	var fs := _label_font_size(String(_ntype[id]))
	if fs <= 0:
		return Rect2()
	var lay := _label_layout(id, tree_to_local(_npos[id]), fs)
	var font: Font = lay[0]
	var p: Vector2 = lay[2]
	return Rect2(p.x, p.y - font.get_ascent(fs), float(lay[3]), font.get_height(fs))


func _draw_node_label(ci: CanvasItem, id: int, c: Vector2, fs: int) -> void:
	var t: String = _ntype[id]
	var lay := _label_layout(id, c, fs)
	var font: Font = lay[0]
	var text: String = lay[1]
	var col := Color(0.86, 0.8, 0.68, 0.9)
	if allocated.has(id):
		col = GOLD_HOT
	elif t == "start":
		col = (_ncol[id] as Color).lightened(0.35) if id == start_id else Color(0.6, 0.58, 0.54, 0.8)
	elif t == "keystone":
		col = Color(1.0, 0.72, 0.42, 0.95)
	elif not frontier.has(id) and not _path_set.has(id):
		col = Color(0.7, 0.66, 0.58, 0.7)
	var p: Vector2 = lay[2]
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_bursts(ci: CanvasItem, sc: float, off: Vector2) -> void:
	for b: Array in _bursts:
		var age := float(b[1])
		var id := int(b[0])
		if age < 0.0 or not _npos.has(id):
			continue
		var k := age / 0.8
		var c: Vector2 = _npos[id] * sc + off
		var r := float(_nrad[id]) * zoom
		var col := GOLD_HOT if String(b[2]) == "alloc" else REFUND_COL
		var a := (1.0 - k) * (1.0 - k)
		ci.draw_arc(c, r * (1.2 + 2.4 * k), 0, TAU, 40, Color(col, 0.9 * a), maxf(1.5, 4.0 * zoom * (1.0 - k)), true)
		MenuStyle.draw_glow(ci, c, r * (2.0 + 3.0 * k), Color(col, 0.5 * a))

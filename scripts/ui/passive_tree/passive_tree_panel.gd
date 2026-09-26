class_name PassiveTreePanel
extends Control
## Full-screen passive tree: pan (drag), zoom (wheel), hover tooltips, click to allocate (path preview), right-click to refund, search box, unspent points.
## OWNER: UI tree/skills/menus module (wave 2). See docs/ARCHITECTURE.md §10, §16.
##
## Layout: the tree canvas (TreePanelCanvas: starfield, links, nodes, all drawn in _draw with
## culling) fills the screen; a header bar on top (title, character, unspent points, search, gold
## and refund cost, Bonuses toggle, Close), a "Passive Bonuses" summary on the right, an overview
## map bottom-left and a controls hint bottom-centre.
## Interaction: hover a node for its tooltip (UI.show_tooltip) and — if it is not allocated — a
## preview of the shortest path to it (TreeDB.find_path; the part beyond the unspent points is
## red). Left-click allocates that path (as far as the unspent points go) through
## CharacterData.allocate_passives. Right-click refunds an allocated node through
## CharacterData.refund_passive (costs Balance.passive_refund_cost gold; the reason is shown when
## it is blocked). Drag to pan, wheel to zoom (0.25-2) around the cursor, Home re-centres on the
## class start, Enter in the search box jumps to the next match. The view centres on the class
## start every time the panel opens.
## The character is GameState.character, or context {"character": CharacterData} (demos/tests).
## Standalone: `var p := PassiveTreePanel.new(); add_child(p); p.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")
const TreeCanvas := preload("res://scripts/ui/passive_tree/tree_panel_canvas.gd")
const TreeOverview := preload("res://scripts/ui/passive_tree/tree_panel_overview.gd")

const PANEL_NAME := "passives"
const DEFAULT_ZOOM := 0.75
const HEADER_HEIGHT := 84.0
const TYPE_NAMES := {
	"start": "Class Start", "small": "Passive", "attribute": "Attribute", "notable": "Notable Passive",
	"keystone": "Keystone",
}
const KEYSTONE_COLOR := Color(1.0, 0.7, 0.4)
const NOTABLE_COLOR := Color(1.0, 0.86, 0.52)

## Show the Passive Bonuses summary (remembered between openings).
static var show_summary: bool = true

var search_edit: LineEdit
var close_button: Button
var summary_button: Button

var _built := false
var _character: CharacterData = null
var _context_character: CharacterData = null
var _canvas: Control
var _overview: Control
var _summary: Control
var _summary_box: VBoxContainer
var _summary_scroll: ScrollContainer
var _title_sub: Label
var _points_label: Label
var _points_caption: Label
var _alloc_label: Label
var _gold_label: Label
var _refund_label: Label
var _match_label: Label
var _hint_refund: Label
var _search_text := ""
var _matches: Array[int] = []
var _match_cursor := -1
var _state_sig := ""
var _tooltip_id := -1
## How many times the panel state (canvas sets, header, summary, tooltip) was rebuilt (tests / perf).
var state_refreshes: int = 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuStyle.get_theme()


func _ready() -> void:
	_ensure_built()
	Events.passives_changed.connect(_on_character_changed)
	Events.gold_changed.connect(func(_g: int) -> void: _on_character_changed())
	Events.level_up.connect(func(_l: int) -> void: _on_character_changed())


## Called by UIRoot after the panel becomes visible.
func on_opened(context: Dictionary) -> void:
	_ensure_built()
	var c: Variant = context.get("character")
	_context_character = c as CharacterData if c is CharacterData else null
	_character = _resolve_character()
	_state_sig = ""
	_refresh_state()
	_canvas.call("center_on", _start_position(), false, DEFAULT_ZOOM)
	if context.has("focus"):
		center_on_node(int(context["focus"]), false)
	if _search_text != "":
		set_search(_search_text)


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	_tooltip_id = -1
	if _canvas != null:
		_canvas.set("hovered", -1)
		_canvas.call("set_path", [], 0)


# ------------------------------------------------------------------ public API (tests, flow)

## The character shown (context override, else GameState.character; may be null).
func get_character() -> CharacterData:
	return _resolve_character()


## The drawing surface (TreePanelCanvas).
func get_tree_canvas() -> Control:
	_ensure_built()
	return _canvas


func get_zoom() -> float:
	return float(_canvas.get("zoom"))


func get_view_center() -> Vector2:
	return _canvas.get("view_center")


## Immediate view change (zoom clamped to 0.25..2).
func set_view(tree_center: Vector2, zoom: float) -> void:
	_canvas.call("center_on", tree_center, false, zoom)


## Tree position -> screen (global canvas) position.
func tree_to_screen(tree_pos: Vector2) -> Vector2:
	return _canvas.get_global_transform() * (_canvas.call("tree_to_local", tree_pos) as Vector2)


## Screen (global) position -> tree position.
func screen_to_tree(screen_pos: Vector2) -> Vector2:
	return _canvas.call("local_to_tree", _canvas.get_global_transform().affine_inverse() * screen_pos)


## Screen position of a node's centre.
func node_screen_position(id: int) -> Vector2:
	return tree_to_screen(TreeDB.get_node_position(id))


## Zoom by `factor` keeping the tree point under `screen_pos` fixed (immediate).
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	_canvas.call("zoom_at", _canvas.get_global_transform().affine_inverse() * screen_pos, factor)


## Pan by a screen-space delta.
func pan_by(delta: Vector2) -> void:
	_canvas.call("pan_by", delta)


func center_on_start(animated: bool = true) -> void:
	_canvas.call("center_on", _start_position(), animated)


func center_on_node(id: int, animated: bool = true) -> void:
	if TreeDB.get_passive(id).is_empty():
		return
	_canvas.call("center_on", TreeDB.get_node_position(id), animated)


## Hover a node programmatically (-1 clears): path preview + tooltip, like the mouse does.
func hover_node(id: int) -> void:
	_canvas.set("hovered", id)
	_on_hover_changed(id)


func get_hovered() -> int:
	return int(_canvas.get("hovered"))


## Current path preview (ordered node ids; [] when nothing is previewed).
func get_preview_path() -> Array:
	return (_canvas.get("path") as Array).duplicate()


## "start" (own class start), "other_start", "allocated", "allocatable", "path", "locked".
func get_node_state(id: int) -> String:
	var c := get_character()
	var n := TreeDB.get_passive(id)
	if n.is_empty():
		return "locked"
	if String(n["type"]) == "start":
		return "start" if c != null and id == TreeDB.get_start_node(c.class_id) else "other_start"
	if c == null:
		return "locked"
	if c.allocated_passives.has(id):
		return "allocated"
	if (_canvas.get("path") as Array).has(id):
		return "path"
	if TreeDB.can_allocate(c.allocated_passives, id, c.class_id):
		return "allocatable"
	return "locked"


## Allocate the shortest path to `id` as far as the unspent points go. Returns how many nodes were
## allocated (0 with a notification when nothing could be).
func allocate_to(id: int) -> int:
	var c := get_character()
	if c == null:
		return 0
	if c.allocated_passives.has(id) or TreeDB.is_start(id):
		return 0
	var p := TreeDB.find_path(c.allocated_passives, id, c.class_id)
	if p.is_empty():
		_notify("That passive can't be reached", UIStyle.COLOR_BAD)
		return 0
	var pts := c.passive_points_unspent()
	if pts <= 0:
		_notify("No unspent passive points", UIStyle.COLOR_BAD)
		return 0
	var n := c.allocate_passives(p.slice(0, mini(pts, p.size())))
	if n > 0:
		Sfx.play_ui("ui_click")
		for i in n:
			_canvas.call("add_burst", int(p[i]), "alloc", 0.06 * i)
	_refresh_state()
	return n


## Why `id` can't be refunded right now ("" = it can).
func get_refund_block_reason(id: int) -> String:
	var c := get_character()
	if c == null:
		return "No character"
	if TreeDB.is_start(id):
		return "The class start can't be refunded"
	if not c.allocated_passives.has(id):
		return "Not allocated"
	if not TreeDB.can_refund(c.allocated_passives, id, c.class_id):
		return "Other passives depend on this one"
	if c.gold < c.refund_cost():
		return "Not enough gold (%s needed)" % MenuStyle.thousands(c.refund_cost())
	return ""


## Refund an allocated node (costs gold). Returns true on success; notifies the reason otherwise.
func refund(id: int) -> bool:
	var c := get_character()
	var reason := get_refund_block_reason(id)
	if reason != "":
		if reason != "Not allocated":
			_notify(reason, UIStyle.COLOR_BAD)
		return false
	if not c.refund_passive(id):
		return false
	Sfx.play_ui("ui_close")
	_canvas.call("add_burst", id, "refund")
	_refresh_state()
	return true


## Highlight TreeDB.search matches ("" clears). Returns the match count.
func set_search(text: String) -> int:
	_ensure_built()
	_search_text = text
	if search_edit.text != text:
		search_edit.text = text
	_matches = TreeDB.search(text)
	_match_cursor = -1
	var d := {}
	for id in _matches:
		d[id] = true
	_canvas.set("matches", d)
	if text.strip_edges() == "":
		_match_label.text = ""
	elif _matches.is_empty():
		_match_label.text = "No matches"
	else:
		_match_label.text = "%d match%s" % [_matches.size(), "" if _matches.size() == 1 else "es"]
	_canvas.queue_redraw()
	return _matches.size()


func get_search_matches() -> Array[int]:
	return _matches.duplicate()


## Centre the view on the next search match (cycles). Returns its id (-1 if none).
func focus_next_match() -> int:
	if _matches.is_empty():
		return -1
	_match_cursor = (_match_cursor + 1) % _matches.size()
	var id := _matches[_match_cursor]
	center_on_node(id, true)
	return id


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_canvas = TreeCanvas.new()
	_canvas.name = "TreeCanvas"
	add_child(_canvas)
	_canvas.connect("hover_changed", _on_hover_changed)
	_canvas.connect("node_clicked", _on_node_clicked)
	_canvas.connect("view_changed", _on_view_changed)
	add_child(_build_header())
	_summary = _build_summary()
	add_child(_summary)
	_overview = TreeOverview.new()
	_overview.set("canvas", _canvas)
	_overview.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_overview.offset_left = 22
	_overview.offset_right = 22 + 230
	_overview.offset_top = -22 - 230
	_overview.offset_bottom = -22
	_overview.connect("jump_requested", func(p: Vector2) -> void: _canvas.call("center_on", p, false))
	add_child(_overview)
	add_child(_build_hints())
	_apply_summary_visibility()


func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = HEADER_HEIGHT
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.03, 0.028, 0.93)
	sb.border_color = UIStyle.COLOR_BORDER
	sb.border_width_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	sb.content_margin_left = 28
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	var h := MenuStyle.hbox(18)
	bar.add_child(h)
	# Title + character.
	var tv := MenuStyle.vbox(0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.custom_minimum_size = Vector2(360, 0)
	tv.add_child(MenuStyle.title_label("PASSIVE TREE", 32, UIStyle.COLOR_TITLE))
	_title_sub = MenuStyle.label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM)
	tv.add_child(_title_sub)
	h.add_child(tv)
	h.add_child(MenuStyle.spacer())
	# Unspent points badge.
	var pts := MenuStyle.hbox(12)
	var badge := MenuCanvas.new(_paint_points_badge, Vector2(62, 62), true)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pts.add_child(badge)
	var pv := MenuStyle.vbox(0)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	_points_caption = MenuStyle.label("Passive Points", UIStyle.FONT_LARGE, UIStyle.COLOR_TITLE, 3)
	pv.add_child(_points_caption)
	_alloc_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	pv.add_child(_alloc_label)
	pts.add_child(pv)
	_points_label = Label.new()   # value drawn by the badge; kept for tests/readers
	_points_label.visible = false
	pts.add_child(_points_label)
	h.add_child(pts)
	h.add_child(MenuStyle.spacer())
	# Search.
	var sv := MenuStyle.vbox(2)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	search_edit = LineEdit.new()
	search_edit.custom_minimum_size = Vector2(300, 38)
	search_edit.placeholder_text = "Search passives...  (e.g. fire, life)"
	search_edit.clear_button_enabled = true
	search_edit.max_length = 40
	search_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	search_edit.text_changed.connect(func(t: String) -> void: set_search(t))
	search_edit.text_submitted.connect(func(_t: String) -> void: focus_next_match())
	sv.add_child(search_edit)
	_match_label = MenuStyle.label("", UIStyle.FONT_SMALL, TreeCanvas.SEARCH_COL)
	_match_label.custom_minimum_size = Vector2(0, 16)
	sv.add_child(_match_label)
	h.add_child(sv)
	h.add_child(MenuStyle.spacer(Vector2(6, 0), false))
	# Gold + refund cost.
	var gv := MenuStyle.vbox(2)
	gv.alignment = BoxContainer.ALIGNMENT_CENTER
	gv.custom_minimum_size = Vector2(150, 0)
	var gh := MenuStyle.hbox(8)
	gh.add_child(MenuCanvas.new(func(ci: Control) -> void: MenuStyle.draw_coin(ci, ci.size * 0.5, 9.0), Vector2(22, 26)))
	_gold_label = MenuStyle.label("0", UIStyle.FONT_LARGE, MenuStyle.GOLD, 3)
	gh.add_child(_gold_label)
	gv.add_child(gh)
	_refund_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	gv.add_child(_refund_label)
	h.add_child(gv)
	summary_button = MenuStyle.make_button("Bonuses", UIStyle.FONT_NORMAL)
	summary_button.toggle_mode = true
	summary_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary_button.toggled.connect(func(on: bool) -> void:
		show_summary = on
		_apply_summary_visibility())
	h.add_child(summary_button)
	close_button = MenuStyle.make_button("Close", UIStyle.FONT_NORMAL)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	h.add_child(close_button)
	return bar


func _build_summary() -> Control:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := MenuStyle.frame_style(Color(0.04, 0.036, 0.034, 0.9), UIStyle.COLOR_BORDER, 6, 16)
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -360
	frame.offset_right = -20
	frame.offset_top = HEADER_HEIGHT + 20
	frame.offset_bottom = HEADER_HEIGHT + 220
	var v := MenuStyle.vbox(8)
	frame.add_child(v)
	v.add_child(MenuStyle.title_label("Passive Bonuses", 24, UIStyle.COLOR_TITLE))
	v.add_child(MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(0, ci.size.y * 0.5), Vector2(ci.size.x, ci.size.y * 0.5), UIStyle.COLOR_BORDER_BRIGHT), Vector2(0, 10)))
	var scroll := ScrollContainer.new()
	_summary_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(scroll)
	_summary_box = MenuStyle.vbox(5)
	_summary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_summary_box)
	return frame


func _build_hints() -> Control:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UIStyle.panel_style(Color(0.03, 0.028, 0.026, 0.82), Color(UIStyle.COLOR_BORDER, 0.6), 1, 16)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.offset_bottom = -22
	var h := MenuStyle.hbox(8)
	frame.add_child(h)
	var items := [["LMB", "Allocate"], ["RMB", "Refund"], ["Drag", "Pan"], ["Wheel", "Zoom"], ["Home", "Centre"], ["P / Esc", "Close"]]
	for i in items.size():
		if i > 0:
			h.add_child(MenuStyle.label("·", UIStyle.FONT_NORMAL, Color(UIStyle.COLOR_BORDER, 0.9)))
		h.add_child(MenuStyle.label(String(items[i][0]), UIStyle.FONT_SMALL + 1, MenuStyle.GOLD))
		var l := MenuStyle.label(String(items[i][1]), UIStyle.FONT_SMALL + 1, UIStyle.COLOR_TEXT_DIM)
		h.add_child(l)
		if items[i][0] == "RMB":
			_hint_refund = l
	return frame


func _apply_summary_visibility() -> void:
	if _summary != null:
		_summary.visible = show_summary
	if summary_button != null:
		summary_button.set_pressed_no_signal(show_summary)


func _paint_points_badge(ci: Control) -> void:
	var c := ci.size * 0.5
	var r := minf(ci.size.x, ci.size.y) * 0.5 - 4.0
	var ch := get_character()
	var pts := ch.passive_points_unspent() if ch != null else 0
	var t := Time.get_ticks_msec() / 1000.0
	var active := pts > 0
	if active:
		MenuStyle.draw_glow(ci, c, r * 2.3, Color(MenuStyle.GOLD, 0.35 + 0.15 * sin(t * 3.0)))
	ci.draw_circle(c, r, Color(0.05, 0.04, 0.03), true, -1.0, true)
	ci.draw_arc(c, r, 0, TAU, 48, MenuStyle.GOLD if active else UIStyle.COLOR_BORDER, 2.5, true)
	ci.draw_arc(c, r - 5.0, 0, TAU, 48, Color(MenuStyle.GOLD, 0.35 if active else 0.12), 1.0, true)
	var font := MenuStyle.title_font()
	var text := str(pts)
	var fs := 30 if text.length() < 3 else 22
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(c.x - sz.x * 0.5, c.y + font.get_ascent(fs) * 0.5 - 2.0)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MenuStyle.GOLD_BRIGHT if active else UIStyle.COLOR_TEXT_DIM)


# ------------------------------------------------------------------ state

func _resolve_character() -> CharacterData:
	if _context_character != null:
		return _context_character
	return GameState.character


func _start_position() -> Vector2:
	var c := get_character()
	if c == null:
		return Vector2.ZERO
	var s := TreeDB.get_start_node(c.class_id)
	return TreeDB.get_node_position(s) if s >= 0 else Vector2.ZERO


func _signature(c: CharacterData) -> String:
	if c == null:
		return "none"
	return "%d|%s|%d|%d|%d|%d|%d" % [c.get_instance_id(), c.class_id, c.allocated_passives.size(), c.allocated_passives.hash(), c.level, c.bonus_passive_points, c.gold]


## Rebuild the canvas state, header and summary from the character (cheap when nothing changed).
func _refresh_state(force: bool = false) -> void:
	if not _built:
		return
	var c := get_character()
	var sig := _signature(c)
	if sig == _state_sig and not force:
		return
	_state_sig = sig
	_character = c
	state_refreshes += 1
	var alloc := {}
	var frontier := {}
	var start := -1
	var cid := ""
	if c != null:
		cid = c.class_id
		start = TreeDB.get_start_node(cid)
		if start >= 0:
			alloc[start] = true
		for id in c.allocated_passives:
			alloc[int(id)] = true
		for id in TreeDB.get_allocatable(c.allocated_passives, cid):
			frontier[id] = true
	_canvas.set("allocated", alloc)
	_canvas.set("frontier", frontier)
	_canvas.set("class_id", cid)
	_canvas.set("start_id", start)
	_update_header()
	_update_summary()
	_update_preview()
	_update_tooltip(true)
	_canvas.queue_redraw()


func _update_header() -> void:
	var c := get_character()
	if c == null:
		_title_sub.text = "No character"
		_points_label.text = "0"
		_alloc_label.text = ""
		_gold_label.text = "0"
		_refund_label.text = ""
		return
	_title_sub.text = "%s  ·  Level %d %s" % [c.char_name, c.level, ClassDefs.get_display_name(c.class_id)]
	_title_sub.add_theme_color_override("font_color", ClassDefs.get_color(c.class_id).lightened(0.3))
	var pts := c.passive_points_unspent()
	_points_label.text = str(pts)
	_points_caption.text = "Passive Point%s" % ("" if pts == 1 else "s")
	_points_caption.add_theme_color_override("font_color", UIStyle.COLOR_TITLE if pts > 0 else UIStyle.COLOR_TEXT_DIM)
	_alloc_label.text = "%d allocated  ·  %d earned" % [c.allocated_passives.size(), c.passive_points_total()]
	_gold_label.text = MenuStyle.thousands(c.gold)
	var cost := c.refund_cost()
	_refund_label.text = "Refund: %s gold" % MenuStyle.thousands(cost)
	_refund_label.add_theme_color_override("font_color", UIStyle.COLOR_TEXT_DIM if c.gold >= cost else UIStyle.COLOR_BAD.darkened(0.1))
	if _hint_refund != null:
		_hint_refund.text = "Refund (%sg)" % MenuStyle.thousands(cost)


func _update_summary() -> void:
	_fill_summary()
	_fit_summary.call_deferred()


## Size the summary frame to its content (at most down to the hint bar), scrolling beyond that.
func _fit_summary() -> void:
	if _summary == null or not is_inside_tree():
		return
	var content := _summary_box.get_combined_minimum_size().y
	var max_h := maxf(120.0, size.y - (HEADER_HEIGHT + 20.0) - 90.0)
	var chrome := 16.0 * 2.0 + 58.0
	var h := clampf(content + chrome, 140.0, max_h)
	_summary_scroll.custom_minimum_size.y = maxf(40.0, h - chrome)
	_summary.offset_bottom = _summary.offset_top + h


## Fill the summary list. Rows are reused by (kind, text), so an allocation only creates / shapes
## the lines that actually changed.
func _fill_summary() -> void:
	var entries := _summary_entries(get_character())
	var pool := {}   # "kind|text" -> [Control]
	for ch in _summary_box.get_children():
		var key := String(ch.get_meta("summary_key", ""))
		if not pool.has(key):
			pool[key] = []
		(pool[key] as Array).append(ch)
	for i in entries.size():
		var kind := String(entries[i][0])
		var text := String(entries[i][1])
		var key := "%s|%s" % [kind, text]
		var node: Control = null
		if pool.has(key) and not (pool[key] as Array).is_empty():
			node = (pool[key] as Array).pop_back()
		else:
			node = _make_summary_row(kind, text)
			node.set_meta("summary_key", key)
			_summary_box.add_child(node)
		_summary_box.move_child(node, i)
	for key: String in pool:
		for ch: Node in pool[key]:
			_summary_box.remove_child(ch)
			ch.queue_free()


## The summary rows as [kind, text]: "intro" | "counts" | "keystone" | "gap" | "mod".
func _summary_entries(c: CharacterData) -> Array:
	if c == null or c.allocated_passives.is_empty():
		return [["intro", "Allocate passives to see their combined bonuses here.\n\nClick a highlighted node next to your class start to begin."]]
	var keystones: Array[String] = []
	var notables := 0
	for id in c.allocated_passives:
		var t := TreeDB.get_node_type(int(id))
		if t == "keystone":
			keystones.append(String(TreeDB.get_passive(int(id)).get("name", "")))
		elif t == "notable":
			notables += 1
	var out: Array = [["counts", "%d passives  ·  %d notable%s  ·  %d keystone%s" % [c.allocated_passives.size(), notables, "" if notables == 1 else "s", keystones.size(), "" if keystones.size() == 1 else "s"]]]
	for k in keystones:
		out.append(["keystone", k])
	out.append(["gap", ""])
	for line in TreeDB.get_allocated_lines(c.allocated_passives, c.class_id):
		out.append(["mod", String(line)])
	return out


func _make_summary_row(kind: String, text: String) -> Control:
	match kind:
		"gap":
			return MenuStyle.spacer(Vector2(0, 4), false)
		"counts":
			return MenuStyle.label(text, UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
		"keystone":
			var kl := MenuStyle.label(text, UIStyle.FONT_NORMAL, KEYSTONE_COLOR)
			kl.add_theme_font_override("font", MenuStyle.heading_font())
			return kl
	var l := MenuStyle.label(text, UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM if kind == "intro" else UIStyle.COLOR_MOD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _update_preview() -> void:
	var c := get_character()
	var id := int(_canvas.get("hovered"))
	var p: Array = []
	var afford := 0
	if c != null and id >= 0 and not TreeDB.is_start(id) and not c.allocated_passives.has(id):
		p = TreeDB.find_path(c.allocated_passives, id, c.class_id)
		afford = mini(c.passive_points_unspent(), p.size())
	_canvas.call("set_path", p, afford)
	# Only the hovered node shows its refund look, so only it needs the (graph walk) refund check.
	var hovered_alloc := c != null and id >= 0 and c.allocated_passives.has(id)
	var refundable := {}
	if hovered_alloc and TreeDB.can_refund(c.allocated_passives, id, c.class_id):
		refundable[id] = true
	_canvas.set("refundable", refundable)
	_canvas.set("refund_preview", hovered_alloc)


## Character signals only mark the state dirty: allocating an N-node path emits passives_changed
## N times, and _process (or the allocate / refund call itself) rebuilds the state once.
func _on_character_changed() -> void:
	_state_sig = ""


func _on_hover_changed(_id: int) -> void:
	_update_preview()
	_update_tooltip()


func _on_view_changed() -> void:
	if _tooltip_id >= 0:
		_update_tooltip(true)


func _on_node_clicked(id: int, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		var c := get_character()
		if c != null and c.allocated_passives.has(id):
			return
		allocate_to(id)
	elif button == MOUSE_BUTTON_RIGHT:
		refund(id)


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not _built:
		return
	# Catch changes made without an Events signal (tests, other code paths).
	if _signature(get_character()) != _state_sig:
		_refresh_state()


# ------------------------------------------------------------------ tooltip

func _update_tooltip(force: bool = false) -> void:
	var id := int(_canvas.get("hovered"))
	if not is_visible_in_tree():
		return
	if id < 0 or bool(_canvas.call("is_dragging")):
		if _tooltip_id >= 0:
			_tooltip_id = -1
			UI.hide_tooltip()
		return
	if id == _tooltip_id and not force:
		return
	_tooltip_id = id
	var r: Rect2 = _canvas.call("node_local_rect", id)
	# Beside the node AND its name label (never covering the label).
	var lr: Rect2 = _canvas.call("node_label_local_rect", id)
	if lr.size != Vector2.ZERO:
		r = r.merge(lr)
	var anchor := Rect2(_canvas.get_global_transform() * r.position, r.size)
	UI.show_tooltip(get_tooltip_lines(id), anchor.grow(6.0))


## Tooltip lines of a node for the current character (Item.get_tooltip_lines format).
func get_tooltip_lines(id: int) -> Array:
	var n := TreeDB.get_passive(id)
	if n.is_empty():
		return []
	var c := get_character()
	var t := String(n["type"])
	var lines: Array = []
	var title_col := UIStyle.COLOR_TEXT
	match t:
		"keystone":
			title_col = KEYSTONE_COLOR
		"notable":
			title_col = NOTABLE_COLOR
		"start":
			title_col = ClassDefs.get_color(String(n.get("class", ""))).lightened(0.3)
	lines.append(_line(String(n.get("name", "")), title_col, "title"))
	var sub := String(TYPE_NAMES.get(t, "Passive"))
	var region := String(TreeDB.REGION_NAMES.get(String(n.get("region", "")), ""))
	if region != "" and t != "start":
		sub += "  ·  " + region
	lines.append(_line(sub, UIStyle.COLOR_TEXT_DIM, "small"))
	var mods := TreeDB.get_node_lines(id)
	if not mods.is_empty():
		lines.append(_separator())
		for m in mods:
			lines.append(_line(m, UIStyle.COLOR_MOD, "normal"))
	lines.append(_separator())
	if t == "start":
		var cid := String(n.get("class", ""))
		if c != null and cid == c.class_id:
			lines.append(_line("Your class starts here (always allocated)", UIStyle.COLOR_TEXT_DIM, "small"))
			lines.append(_line("Class attributes come from the %s" % ClassDefs.get_display_name(cid), UIStyle.COLOR_TEXT_DIM, "small"))
		else:
			lines.append(_line("%s start: can't be allocated or passed" % ClassDefs.get_display_name(cid), UIStyle.COLOR_TEXT_DIM, "small"))
		return lines
	if c == null:
		lines.append(_line("No character", UIStyle.COLOR_TEXT_DIM, "small"))
		return lines
	if c.allocated_passives.has(id):
		lines.append(_line("Allocated", MenuStyle.GOLD, "normal"))
		var reason := get_refund_block_reason(id)
		if reason == "":
			lines.append(_line("Right-click to refund (%s gold)" % MenuStyle.thousands(c.refund_cost()), UIStyle.COLOR_TEXT_DIM, "small"))
		else:
			lines.append(_line("Can't refund: %s" % reason, UIStyle.COLOR_BAD, "small"))
		return lines
	var p: Array = _canvas.get("path")
	if p.is_empty() or int(p[-1]) != id:
		p = TreeDB.find_path(c.allocated_passives, id, c.class_id)
	if p.is_empty():
		lines.append(_line("Unreachable", UIStyle.COLOR_BAD, "small"))
		return lines
	var need := p.size()
	var have := c.passive_points_unspent()
	if need >= 2:
		# What the passives on the way grant (merged), so a long path shows its whole value.
		var before: Array = p.slice(0, need - 1)
		var way := StatDefs.describe_mods(TreeDB.get_mods(before))
		if not way.is_empty():
			lines.append(_line("Along the way (%d passive%s):" % [before.size(), "" if before.size() == 1 else "s"], UIStyle.COLOR_TEXT_DIM, "small"))
			for i in mini(way.size(), 6):
				lines.append(_line(way[i], Color(UIStyle.COLOR_MOD, 0.8), "small"))
			if way.size() > 6:
				lines.append(_line("...and %d more" % (way.size() - 6), UIStyle.COLOR_TEXT_DIM, "small"))
			lines.append(_separator())
	var pts_text := "%d point%s" % [need, "" if need == 1 else "s"]
	if have >= need:
		lines.append(_line("Click to allocate (%s)" % pts_text, UIStyle.COLOR_GOOD, "normal"))
	elif have > 0:
		lines.append(_line("Needs %s, you have %d" % [pts_text, have], UIStyle.COLOR_BAD, "normal"))
		lines.append(_line("Click to allocate the first %d" % have, UIStyle.COLOR_TEXT_DIM, "small"))
	else:
		lines.append(_line("Needs %s (no unspent points)" % pts_text, UIStyle.COLOR_BAD, "normal"))
		lines.append(_line("You gain a point every level", UIStyle.COLOR_TEXT_DIM, "small"))
	return lines


static func _line(text: String, color: Color, size: String = "normal") -> Dictionary:
	return {"text": text, "color": color, "size": size}


static func _separator() -> Dictionary:
	return {"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true}


# ------------------------------------------------------------------ misc

## Close the panel (through UIRoot when it manages this panel, else just hide).
func close() -> void:
	if UI.is_panel_open(PANEL_NAME) and UI.get_panel(PANEL_NAME) == self:
		UI.close_panel(PANEL_NAME)
	else:
		visible = false
		on_closed()
		UI.hide_tooltip()


func _notify(text: String, color: Color) -> void:
	Events.notify.emit(text, color)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	if k == null:
		return
	if k.keycode == KEY_HOME:
		center_on_start(true)
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F and k.ctrl_pressed:
		search_edit.grab_focus()
		search_edit.select_all()
		get_viewport().set_input_as_handled()

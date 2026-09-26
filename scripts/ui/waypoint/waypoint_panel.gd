class_name WaypointPanel
extends Control
## Waypoint (dungeon gate in town): list depths 1..max_depth with monster level; click to travel.
## OWNER: UI tree/skills/menus module (wave 2). See docs/ARCHITECTURE.md §13, §15, §16.
##
## A centred window (root MOUSE_FILTER_IGNORE; the frame and tiles STOP) with a grid of depth
## tiles 1..max_depth: depth number, dungeon theme (World.theme_display_name(World.theme_for_depth(d))),
## monster level (Balance.area_level_for_depth), boss slain / awaits (character.cleared_depths) and
## a "Deepest" ribbon; plus one locked tile for the next depth. Clicking a tile emits
## Events.area_change_requested("dungeon", {"depth": d}) and closes the panel. When a town portal
## to a kept dungeon is open, a note warns that travelling closes it.
## Context: {"max_depth": int} (the gate passes character.max_depth); falls back to the character.
## Standalone: `var p := WaypointPanel.new(); add_child(p); p.on_opened({"max_depth": 5})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuFrame := preload("res://scripts/ui/menus/menu_frame.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")
const WaypointTile := preload("res://scripts/ui/waypoint/waypoint_tile.gd")

const PANEL_NAME := "waypoint"
const COLUMNS := 5

var close_button: Button

var _built := false
var _max_depth := 1
var _grid: GridContainer
var _scroll: ScrollContainer
var _tiles: Dictionary = {}     # depth -> tile
var _subtitle: Label
var _portal_note: Label
var _travelled := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuStyle.get_theme()


func _ready() -> void:
	_ensure_built()


## Called by UIRoot after the panel becomes visible.
func on_opened(context: Dictionary) -> void:
	_ensure_built()
	_travelled = false
	var c := GameState.character
	var md := int(context.get("max_depth", c.max_depth if c != null else 1))
	_max_depth = clampi(md, 1, Balance.MAX_DEPTH)
	_rebuild()
	_scroll_to_depth.call_deferred(_max_depth)


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	UI.hide_tooltip()


# ------------------------------------------------------------------ public API

func get_max_depth() -> int:
	return _max_depth


## The tile button of a depth (null if not listed). Tiles above max_depth are locked.
func get_tile(depth: int) -> Button:
	return _tiles.get(depth) as Button


## Depths that can be travelled to.
func get_depths() -> Array[int]:
	var out: Array[int] = []
	for d in range(1, _max_depth + 1):
		out.append(d)
	return out


## Travel: emits Events.area_change_requested("dungeon", {"depth": depth}) and closes the panel.
## Returns false for depths out of range (or after a travel request, until reopened).
func travel_to(depth: int) -> bool:
	if depth < 1 or depth > _max_depth or _travelled:
		return false
	_travelled = true
	Sfx.play_ui("ui_click")
	Events.area_change_requested.emit("dungeon", {"depth": depth})
	close()
	return true


## Tooltip lines of a depth: theme, monster level, resistance penalty, its guardian (EnemyDB def
## name + description when known), cleared state and the click hint.
func get_tooltip_lines(depth: int) -> Array:
	var theme_id := World.theme_for_depth(depth)
	var lines: Array = []
	lines.append({"text": "Depth %d" % depth, "color": UIStyle.COLOR_TITLE, "size": "title"})
	lines.append({"text": World.theme_display_name(theme_id), "color": MenuStyle.theme_color(theme_id), "size": "normal"})
	lines.append({"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true})
	var lvl := Balance.area_level_for_depth(depth)
	lines.append({"text": "Monster Level %d" % lvl, "color": UIStyle.COLOR_TEXT, "size": "normal"})
	var pen := Balance.resist_penalty(lvl)
	if pen < 0.0:
		lines.append({"text": "%d%% to elemental and chaos resistances" % int(pen), "color": UIStyle.COLOR_BAD, "size": "small"})
	var boss_id := "boss_lich" if depth % 2 == 1 else "boss_gravebreaker"
	var def: Dictionary = EnemyDB.get_def(boss_id)
	lines.append({"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true})
	lines.append({"text": "Guardian: %s" % String(def.get("name", "the depth's guardian")), "color": Color(1.0, 0.62, 0.45), "size": "normal"})
	if String(def.get("description", "")) != "":
		lines.append({"text": String(def["description"]), "color": UIStyle.COLOR_TEXT_DIM, "size": "small"})
	lines.append({"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true})
	if depth > _max_depth:
		lines.append({"text": "Locked: slay the guardian of Depth %d first" % (depth - 1), "color": UIStyle.COLOR_BAD, "size": "normal"})
		return lines
	var c := GameState.character
	if c != null and c.cleared_depths.has(depth):
		lines.append({"text": "Guardian slain", "color": UIStyle.COLOR_GOOD, "size": "normal"})
	if depth <= Balance.BONUS_POINT_MAX_DEPTH and (c == null or not c.cleared_depths.has(depth)):
		lines.append({"text": "First kill grants a passive point", "color": MenuStyle.GOLD, "size": "small"})
	lines.append({"text": "Click to descend", "color": UIStyle.COLOR_GOOD, "size": "small"})
	return lines


## Show a depth's tooltip as if its tile were hovered (demos / tests).
func preview_tooltip(depth: int) -> void:
	var t := get_tile(depth)
	if t != null:
		_on_tile_hovered(depth, t)


func _on_tile_hovered(depth: int, tile: Control) -> void:
	UI.show_tooltip(get_tooltip_lines(depth), tile.get_global_rect())


func _on_tile_unhovered(_depth: int) -> void:
	UI.hide_tooltip()


func close() -> void:
	if UI.is_panel_open(PANEL_NAME) and UI.get_panel(PANEL_NAME) == self:
		UI.close_panel(PANEL_NAME)
	else:
		visible = false
		on_closed()


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -60
	add_child(center)
	var frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BORDER, 22)
	frame.set("accent", Color(MenuStyle.EMBER, 0.8))
	frame.custom_minimum_size = Vector2(COLUMNS * 164 + (COLUMNS - 1) * 10 + 44 + 16, 0)
	center.add_child(frame)
	var v := MenuStyle.vbox(12)
	frame.add_child(v)
	var head := MenuStyle.hbox(12)
	head.add_child(MenuCanvas.new(_paint_gate_glyph, Vector2(56, 56)))
	var tv := MenuStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(MenuStyle.title_label("THE DUNGEON GATE", 32, UIStyle.COLOR_TITLE))
	_subtitle = MenuStyle.label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM)
	tv.add_child(_subtitle)
	head.add_child(tv)
	close_button = MenuStyle.make_button("Close", UIStyle.FONT_NORMAL)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	v.add_child(MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(0, ci.size.y * 0.5), Vector2(ci.size.x, ci.size.y * 0.5), UIStyle.COLOR_BORDER_BRIGHT), Vector2(0, 12)))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.custom_minimum_size = Vector2(0, 128 * 4 + 10 * 3 + 8)
	v.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	pad.add_child(_grid)
	v.add_child(MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(0, ci.size.y * 0.5), Vector2(ci.size.x, ci.size.y * 0.5), UIStyle.COLOR_BORDER), Vector2(0, 10)))
	var foot := MenuStyle.hbox(16)
	for th in ["crypt", "cave", "inferno"]:
		var col := MenuStyle.theme_color(th)
		foot.add_child(MenuCanvas.new(func(ci: Control) -> void:
			ci.draw_circle(ci.size * 0.5, 6.0, col, true, -1.0, true), Vector2(14, 20)))
		foot.add_child(MenuStyle.label(World.theme_display_name(th), UIStyle.FONT_SMALL, col.lightened(0.1)))
	foot.add_child(MenuStyle.spacer())
	_portal_note = MenuStyle.label("", UIStyle.FONT_SMALL, Color(0.75, 0.6, 1.0))
	foot.add_child(_portal_note)
	v.add_child(foot)


func _rebuild() -> void:
	for ch in _grid.get_children():
		_grid.remove_child(ch)
		ch.queue_free()
	_tiles.clear()
	var c := GameState.character
	var cleared: Array = c.cleared_depths if c != null else []
	for d in range(1, _max_depth + 1):
		var tile: Button = WaypointTile.new(d, cleared.has(d), d == _max_depth, false)
		var depth := d
		tile.pressed.connect(func() -> void: travel_to(depth))
		tile.connect("hovered", _on_tile_hovered)
		tile.connect("unhovered", _on_tile_unhovered)
		_grid.add_child(tile)
		_tiles[d] = tile
	if _max_depth < Balance.MAX_DEPTH:
		var next: Button = WaypointTile.new(_max_depth + 1, false, false, true)
		next.connect("hovered", _on_tile_hovered)
		next.connect("unhovered", _on_tile_unhovered)
		_grid.add_child(next)
		_tiles[_max_depth + 1] = next
	var rows := ceili(float(_tiles.size()) / COLUMNS)
	_scroll.custom_minimum_size.y = mini(rows, 4) * 128 + (mini(rows, 4) - 1) * 10 + 8
	var n_cleared := 0
	for d in cleared:
		if int(d) <= _max_depth:
			n_cleared += 1
	_subtitle.text = "Choose a depth to descend to  ·  Deepest: %d  ·  Bosses slain: %d" % [_max_depth, n_cleared]
	var kept: Variant = GameState.town_portal_state.get("world")
	if kept != null and is_instance_valid(kept) and kept is World:
		var dd := int((kept as World).area_info.get("depth", 0))
		_portal_note.text = ("Travelling closes your open portal to Depth %d" % dd) if dd > 0 else "Travelling closes your open town portal"
	else:
		_portal_note.text = ""


func _scroll_to_depth(depth: int) -> void:
	if not is_inside_tree():
		return
	var t := get_tile(depth)
	if t != null:
		_scroll.ensure_control_visible(t)


func _paint_gate_glyph(ci: Control) -> void:
	var c := ci.size * 0.5
	var s := minf(ci.size.x, ci.size.y) * 0.5 - 2.0
	MenuStyle.draw_glow(ci, c, s * 1.8, Color(MenuStyle.EMBER, 0.3), true)
	var stone := Color(0.42, 0.38, 0.33)
	# Two pillars and an arch.
	ci.draw_rect(Rect2(c + Vector2(-0.8, -0.3) * s, Vector2(0.3, 1.2) * s), stone)
	ci.draw_rect(Rect2(c + Vector2(0.5, -0.3) * s, Vector2(0.3, 1.2) * s), stone)
	ci.draw_arc(c + Vector2(0, -0.3) * s, 0.65 * s, PI, TAU, 24, stone, 0.3 * s, true)
	# Glowing portal inside.
	ci.draw_circle(c + Vector2(0, 0.2) * s, 0.42 * s, Color(1.0, 0.55, 0.2, 0.55), true, -1.0, true)
	ci.draw_circle(c + Vector2(0, 0.2) * s, 0.22 * s, Color(1.0, 0.85, 0.5, 0.8), true, -1.0, true)
	# Runes.
	for k in 3:
		MenuStyle.draw_diamond(ci, c + Vector2(-0.65, 0.05 + 0.3 * k) * s, 0.06 * s + 1.0, MenuStyle.EMBER)
		MenuStyle.draw_diamond(ci, c + Vector2(0.65, 0.05 + 0.3 * k) * s, 0.06 * s + 1.0, MenuStyle.EMBER)

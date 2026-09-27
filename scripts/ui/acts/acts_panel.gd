class_name ActsPanel
extends Control
## The Act Explorer (demo menu): travel straight to any act's hub, wilds or dungeon, back to
## Emberfall, and
## set demo options — monster level (the act's own, your level, or a custom one), monsters on/off
## and god mode. Opened with M, from the pause menu, from an act hub's waystone, or from the main
## menu's "Explore the Acts" button. OWNER: acts framework.
##
## Travel emits Events.area_change_requested("act", {"act", "zone"}) (or ("town", {}) for Emberfall)
## and closes the panel. Options live in GameState.act_options.
## Standalone: `var p := ActsPanel.new(); add_child(p); p.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuFrame := preload("res://scripts/ui/menus/menu_frame.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")
const FlowAreas := preload("res://scripts/main/flow_areas.gd")

const PANEL_NAME := "acts"
const CARD_WIDTH := 330

var close_button: Button
var emberfall_button: Button
## act id -> {region id ("hub", "outskirts", ...): Button, "dungeon": Button}
var travel_buttons: Dictionary = {}

var _built := false
var _travelled := false
var _level_buttons: Dictionary = {}   # mode -> Button
var _level_value: Label
var _minus: Button
var _plus: Button
var _monsters_button: Button
var _god_button: Button
var _here_labels: Dictionary = {}     # act -> Label
var _wilds_levels: Dictionary = {}    # act -> Label
var _note: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuStyle.get_theme()


func _ready() -> void:
	_ensure_built()


## Called by UIRoot after the panel becomes visible. context: {"act": id} highlights that act.
func on_opened(_context: Dictionary) -> void:
	_ensure_built()
	_travelled = false
	_refresh()


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	UI.hide_tooltip()


# ------------------------------------------------------------------ public API

## Travel to an act region ("hub", "outskirts", ... or "wilds"). False when unknown or already
## travelling.
func travel(act: String, zone: String) -> bool:
	if _travelled or not ActDefs.has_act(act) or not ActDefs.canonical_zone(act, zone) in ActDefs.region_ids(act):
		return false
	_travelled = true
	Sfx.play_ui("ui_click")
	Events.area_change_requested.emit("act", {"act": act, "zone": zone})
	close()
	return true


## Go down into an act's dungeon.
func travel_dungeon(act: String) -> bool:
	if _travelled or not ActDefs.has_act(act):
		return false
	_travelled = true
	Sfx.play_ui("ui_click")
	Events.area_change_requested.emit("act_dungeon", {"act": act})
	close()
	return true


func travel_emberfall() -> bool:
	if _travelled:
		return false
	if GameState.is_in_town():
		close()
		return false
	_travelled = true
	Sfx.play_ui("ui_click")
	Events.area_change_requested.emit("town", {})
	close()
	return true


## "act" (each act's suggested level), "character" (your level) or "custom".
func set_level_mode(mode: String) -> void:
	GameState.act_options["level_mode"] = mode if mode in ["act", "character", "custom"] else "act"
	_refresh()


func set_custom_level(level: int) -> void:
	GameState.act_options["level"] = clampi(level, 1, 100)
	GameState.act_options["level_mode"] = "custom"
	_refresh()


func set_monsters(on: bool) -> void:
	GameState.act_options["monsters"] = on
	_refresh()


func set_god_mode(on: bool) -> void:
	GameState.act_options["god_mode"] = on
	var p := GameState.player
	if p != null and is_instance_valid(p):
		p.god_mode = on
	_refresh()


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
	frame.set("accent", Color(MenuStyle.GOLD, 0.8))
	center.add_child(frame)
	var v := MenuStyle.vbox(12)
	frame.add_child(v)
	# Header.
	var head := MenuStyle.hbox(12)
	head.add_child(MenuCanvas.new(_paint_compass, Vector2(56, 56)))
	var tv := MenuStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(MenuStyle.title_label("ACT EXPLORER", 32, UIStyle.COLOR_TITLE))
	tv.add_child(MenuStyle.label("Travel anywhere in the three acts  ·  press M to open this anytime", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM))
	head.add_child(tv)
	close_button = MenuStyle.make_button("Close", UIStyle.FONT_NORMAL)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	v.add_child(_divider(UIStyle.COLOR_BORDER_BRIGHT))
	# Act cards.
	var cards := MenuStyle.hbox(14)
	for act in ActDefs.ACT_ORDER:
		cards.add_child(_make_card(act))
	v.add_child(cards)
	v.add_child(_divider(UIStyle.COLOR_BORDER))
	# Options.
	var opts := MenuStyle.hbox(10)
	opts.add_child(MenuStyle.label("Monster level:", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT))
	for m in [["act", "Act default"], ["character", "My level"], ["custom", "Custom"]]:
		var b := MenuStyle.make_button(m[1], UIStyle.FONT_SMALL)
		var mode: String = m[0]
		b.pressed.connect(func() -> void: set_level_mode(mode))
		opts.add_child(b)
		_level_buttons[mode] = b
	_minus = MenuStyle.make_button("−", UIStyle.FONT_NORMAL)
	_minus.custom_minimum_size = Vector2(36, 0)
	_minus.pressed.connect(func() -> void: set_custom_level(int(GameState.act_options.get("level", 10)) - (5 if Input.is_key_pressed(KEY_SHIFT) else 1)))
	opts.add_child(_minus)
	_level_value = MenuStyle.label("", UIStyle.FONT_LARGE, MenuStyle.GOLD)
	_level_value.custom_minimum_size = Vector2(44, 0)
	_level_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opts.add_child(_level_value)
	_plus = MenuStyle.make_button("+", UIStyle.FONT_NORMAL)
	_plus.custom_minimum_size = Vector2(36, 0)
	_plus.pressed.connect(func() -> void: set_custom_level(int(GameState.act_options.get("level", 10)) + (5 if Input.is_key_pressed(KEY_SHIFT) else 1)))
	opts.add_child(_plus)
	opts.add_child(MenuStyle.spacer(Vector2(18, 0), false))
	_monsters_button = MenuStyle.make_button("", UIStyle.FONT_SMALL)
	_monsters_button.pressed.connect(func() -> void: set_monsters(not bool(GameState.act_options.get("monsters", true))))
	opts.add_child(_monsters_button)
	_god_button = MenuStyle.make_button("", UIStyle.FONT_SMALL)
	_god_button.pressed.connect(func() -> void: set_god_mode(not _god_on()))
	opts.add_child(_god_button)
	v.add_child(opts)
	var foot := MenuStyle.hbox(12)
	_note = MenuStyle.label("", UIStyle.FONT_SMALL, Color(0.75, 0.6, 1.0))
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_note)
	emberfall_button = MenuStyle.make_button("Return to Emberfall", UIStyle.FONT_NORMAL)
	emberfall_button.pressed.connect(travel_emberfall)
	foot.add_child(emberfall_button)
	v.add_child(foot)


func _make_card(act: String) -> Control:
	var def := ActDefs.get_act(act)
	var accent := ActDefs.accent(act)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := MenuStyle.frame_style(MenuStyle.FRAME_BG_LIGHT, accent.darkened(0.45), 6, 14)
	card.add_theme_stylebox_override("panel", sb)
	var v := MenuStyle.vbox(8)
	card.add_child(v)
	var art := MenuCanvas.new(func(ci: Control) -> void: _paint_act(ci, act), Vector2(CARD_WIDTH - 28, 150))
	v.add_child(art)
	var top := MenuStyle.hbox(6)
	top.add_child(MenuStyle.label(ActDefs.act_label(act).to_upper(), UIStyle.FONT_SMALL, accent))
	top.add_child(MenuStyle.spacer())
	var here := MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_GOOD)
	top.add_child(here)
	_here_labels[act] = here
	v.add_child(top)
	v.add_child(MenuStyle.title_label(String(def["title"]), 24, UIStyle.COLOR_TITLE))
	var tag := MenuStyle.label(String(def["tagline"]), UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(CARD_WIDTH - 28, 0)
	v.add_child(tag)
	var btns := {}
	# The town, then every zone of the act (with its monster level), then the dungeon.
	var town := MenuStyle.make_button("%s  (town)" % ActDefs.zone_name(act, "hub"), UIStyle.FONT_NORMAL, true)
	town.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var at := act
	town.pressed.connect(func() -> void: travel(at, "hub"))
	v.add_child(town)
	btns["hub"] = town
	var lv := MenuStyle.label("", UIStyle.FONT_SMALL, Color(1.0, 0.62, 0.45))
	lv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.custom_minimum_size = Vector2(CARD_WIDTH - 28, 0)
	v.add_child(lv)
	_wilds_levels[act] = lv
	for r in ActDefs.regions(act):
		var zone := String(r["id"])
		if zone == "hub":
			continue
		var b := MenuStyle.make_button(String(r["name"]), UIStyle.FONT_SMALL)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var a := act
		var z := zone
		b.pressed.connect(func() -> void: travel(a, z))
		var tagl := MenuStyle.label("", UIStyle.FONT_SMALL, accent.lerp(UIStyle.COLOR_TEXT_DIM, 0.3))
		tagl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tagl.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		tagl.offset_left = -80
		tagl.offset_right = -8
		tagl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tagl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tagl.name = "Level"
		b.add_child(tagl)
		v.add_child(b)
		btns[zone] = b
	var dd := ActDefs.dungeon(act)
	if not dd.is_empty():
		var db := MenuStyle.make_button("%s  (dungeon)" % String(dd.get("name", "Dungeon")), UIStyle.FONT_SMALL)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var a2 := act
		db.pressed.connect(func() -> void: travel_dungeon(a2))
		v.add_child(db)
		btns["dungeon"] = db
	travel_buttons[act] = btns
	return card


func _refresh() -> void:
	if not _built:
		return
	var mode := String(GameState.act_options.get("level_mode", "act"))
	for m in _level_buttons:
		MenuStyle.style_key_button(_level_buttons[m] as Button, m == mode)
	_level_value.text = str(int(GameState.act_options.get("level", 10)))
	_level_value.modulate.a = 1.0 if mode == "custom" else 0.45
	var mon := bool(GameState.act_options.get("monsters", true))
	_monsters_button.text = "Monsters: %s" % ("On" if mon else "Off")
	MenuStyle.style_key_button(_monsters_button, mon)
	_god_button.text = "God mode: %s" % ("On" if _god_on() else "Off")
	MenuStyle.style_key_button(_god_button, _god_on())
	var info: Dictionary = GameState.current_area
	for act in ActDefs.ACT_ORDER:
		var here := ""
		if String(info.get("id", "")) == "act" and String(info.get("act", "")) == act:
			here = "You are here: %s" % ActDefs.zone_name(act, String(info.get("zone", "hub")))
		(_here_labels[act] as Label).text = here
		var boss: Dictionary = EnemyDB.get_def(String(ActDefs.get_act(act).get("boss", "")))
		var lvl := FlowAreas.act_level(act)
		var txt := "Monster Level %d – %d" % [lvl, lvl + ActDefs.DUNGEON_LEVEL_OFFSET]
		if not mon:
			txt = "Monsters off — explore in peace"
		elif not boss.is_empty():
			txt += "  ·  %s awaits in the dungeon" % String(boss.get("name", ""))
		(_wilds_levels[act] as Label).text = txt
		for r in ActDefs.regions(act):
			var b: Variant = (travel_buttons[act] as Dictionary).get(String(r["id"]))
			if b != null and (b as Node).has_node("Level"):
				((b as Node).get_node("Level") as Label).text = "lvl %d" % (lvl + int(r["level"]))
	var kept: Variant = GameState.town_portal_state.get("world")
	if kept != null and is_instance_valid(kept) and kept is World:
		_note.text = "Your open town portal stays open until you enter new wilds or depths"
	else:
		_note.text = "Tip: Shift-click − / + to change the custom level by 5"


func _god_on() -> bool:
	var p := GameState.player
	if p != null and is_instance_valid(p):
		return bool(p.god_mode)
	return bool(GameState.act_options.get("god_mode", false))


func _divider(color: Color) -> Control:
	return MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(0, ci.size.y * 0.5), Vector2(ci.size.x, ci.size.y * 0.5), color), Vector2(0, 12))


# ------------------------------------------------------------------ painting

func _paint_compass(ci: Control) -> void:
	var c := ci.size * 0.5
	var s := minf(ci.size.x, ci.size.y) * 0.5 - 2.0
	MenuStyle.draw_glow(ci, c, s * 1.8, Color(MenuStyle.GOLD, 0.28), true)
	ci.draw_arc(c, s * 0.82, 0.0, TAU, 40, Color(MenuStyle.GOLD_DARK, 0.9), 3.0, true)
	var cols := [ActDefs.accent("desert"), ActDefs.accent("forest"), ActDefs.accent("gothic")]
	for k in 3:
		var a := -PI * 0.5 + k * TAU / 3.0
		var tip := c + Vector2(cos(a), sin(a)) * s * 0.78
		var l := c + Vector2(cos(a + 1.9), sin(a + 1.9)) * s * 0.18
		var r := c + Vector2(cos(a - 1.9), sin(a - 1.9)) * s * 0.18
		ci.draw_colored_polygon(PackedVector2Array([tip, l, c, r]), cols[k])
	ci.draw_circle(c, s * 0.12, MenuStyle.GOLD_BRIGHT, true, -1.0, true)


## Small painted vignette per act (sky gradient + silhouettes).
func _paint_act(ci: Control, act: String) -> void:
	var w := ci.size.x
	var h := ci.size.y
	var r := Rect2(Vector2.ZERO, ci.size)
	match act:
		"desert":
			_sky(ci, r, Color(0.36, 0.55, 0.82), Color(0.98, 0.8, 0.52))
			ci.draw_circle(Vector2(w * 0.8, h * 0.28), h * 0.12, Color(1.0, 0.93, 0.7), true, -1.0, true)
			for p in [[0.28, 0.62, 0.5], [0.52, 0.66, 0.36], [0.1, 0.7, 0.26]]:
				var cx: float = w * p[0]
				var base: float = h * 0.78
				var ph: float = h * p[2]
				ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - ph * 0.95, base), Vector2(cx, base - ph), Vector2(cx + ph * 0.95, base)]), Color(0.86, 0.66, 0.38))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(cx, base - ph), Vector2(cx + ph * 0.95, base), Vector2(cx + ph * 0.2, base)]), Color(0.7, 0.5, 0.28))
			ci.draw_rect(Rect2(0, h * 0.78, w, h * 0.08), Color(0.25, 0.5, 0.62))
			ci.draw_rect(Rect2(0, h * 0.86, w, h * 0.14), Color(0.84, 0.7, 0.46))
			_palm(ci, Vector2(w * 0.72, h * 0.95), h * 0.62)
			_palm(ci, Vector2(w * 0.9, h * 0.97), h * 0.5)
		"forest":
			_sky(ci, r, Color(0.46, 0.66, 0.86), Color(0.86, 0.9, 0.78))
			ci.draw_rect(Rect2(0, h * 0.6, w, h * 0.12), Color(0.5, 0.66, 0.74))
			for k in 14:
				var x := w * (k / 13.0) + sin(k * 7.1) * 8.0
				var th := h * (0.45 + 0.2 * absf(sin(k * 3.3)))
				_pine(ci, Vector2(x, h * 0.75), th, Color(0.16, 0.3, 0.2).lerp(Color(0.25, 0.4, 0.26), absf(sin(k * 1.7))))
			var lx := w * 0.3
			var ly := h * 0.9
			ci.draw_rect(Rect2(0, h * 0.82, w, h * 0.18), Color(0.3, 0.42, 0.2))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(lx - 44, ly), Vector2(lx - 44, ly - 22), Vector2(lx, ly - 48), Vector2(lx + 44, ly - 22), Vector2(lx + 44, ly)]), Color(0.36, 0.26, 0.16))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(lx - 52, ly - 20), Vector2(lx, ly - 52), Vector2(lx + 52, ly - 20)]), Color(0.6, 0.5, 0.28))
			ci.draw_line(Vector2(lx - 8, ly - 58), Vector2(lx + 6, ly - 44), Color(0.36, 0.26, 0.16), 3.0)
			ci.draw_line(Vector2(lx + 8, ly - 58), Vector2(lx - 6, ly - 44), Color(0.36, 0.26, 0.16), 3.0)
		"gothic":
			_sky(ci, r, Color(0.05, 0.08, 0.12), Color(0.22, 0.32, 0.36))
			ci.draw_circle(Vector2(w * 0.72, h * 0.3), h * 0.13, Color(0.9, 0.95, 0.96), true, -1.0, true)
			MenuStyle.draw_glow(ci, Vector2(w * 0.72, h * 0.3), h * 0.4, Color(0.7, 0.85, 0.9, 0.35), true)
			var dark := Color(0.06, 0.07, 0.09)
			for k in 9:
				var x2 := w * (0.04 + k * 0.12)
				var sh := h * (0.35 + 0.3 * absf(sin(k * 2.3)))
				ci.draw_rect(Rect2(x2 - 12, h - sh * 0.7, 24, sh * 0.7), dark)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x2 - 12, h - sh * 0.7), Vector2(x2, h - sh * 1.15), Vector2(x2 + 12, h - sh * 0.7)]), dark)
				if k % 2 == 0:
					ci.draw_rect(Rect2(x2 - 3, h - sh * 0.45, 6, 8), Color(1.0, 0.72, 0.35))
			var cx2 := w * 0.45
			ci.draw_rect(Rect2(cx2 - 30, h * 0.35, 60, h * 0.65), Color(0.08, 0.09, 0.12))
			for dx in [-26, 0, 26]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(cx2 + dx - 7, h * 0.36), Vector2(cx2 + dx, h * (0.06 if dx == 0 else 0.16)), Vector2(cx2 + dx + 7, h * 0.36)]), Color(0.08, 0.09, 0.12))
			ci.draw_circle(Vector2(cx2, h * 0.5), 9, Color(0.95, 0.75, 0.45), true, -1.0, true)
	ci.draw_rect(r, Color(ActDefs.accent(act), 0.5), false, 2.0)


func _sky(ci: Control, r: Rect2, top: Color, bottom: Color) -> void:
	var steps := 16
	for k in steps:
		var y0 := r.size.y * k / steps
		ci.draw_rect(Rect2(0, y0, r.size.x, r.size.y / steps + 1.0), top.lerp(bottom, float(k) / (steps - 1)))


func _palm(ci: Control, base: Vector2, height: float) -> void:
	var top := base + Vector2(height * 0.12, -height)
	ci.draw_line(base, top, Color(0.42, 0.3, 0.18), 4.0, true)
	for k in 7:
		var a := -PI * 0.5 + (k - 3) * 0.5
		var tip := top + Vector2(cos(a), sin(a) + 0.55) * height * 0.32
		ci.draw_line(top, tip, Color(0.22, 0.42, 0.18), 3.0, true)


func _pine(ci: Control, base: Vector2, height: float, col: Color) -> void:
	ci.draw_line(base, base - Vector2(0, height), Color(0.36, 0.24, 0.16), 2.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(base.x - height * 0.16, base.y - height * 0.25), Vector2(base.x, base.y - height), Vector2(base.x + height * 0.16, base.y - height * 0.25)]), col)

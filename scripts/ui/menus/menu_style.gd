extends RefCounted
## Shared look & small helpers of the ui-menus module (passive tree, skill book, waypoint, main /
## pause / death menus), built on top of UIStyle. Internal to the module:
##   const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
## Everything here is static; generated textures, fonts and the theme are cached.

const GOLD := Color(0.98, 0.8, 0.36)
const GOLD_BRIGHT := Color(1.0, 0.92, 0.66)
const GOLD_DARK := Color(0.55, 0.42, 0.2)
const EMBER := Color(1.0, 0.52, 0.18)
const BLOOD := Color(0.72, 0.08, 0.06)
const FRAME_BG := Color(0.065, 0.058, 0.052, 0.97)
const FRAME_BG_LIGHT := Color(0.11, 0.098, 0.085, 0.97)
const ROW_BG := Color(0.1, 0.09, 0.08, 0.92)
const ROW_BG_HOVER := Color(0.17, 0.15, 0.12, 0.96)
const ROW_BG_SELECTED := Color(0.2, 0.16, 0.1, 0.98)
const OVERLAY := Color(0.0, 0.0, 0.0, 0.62)

## Dungeon theme id -> accent colour (waypoint, death screen).
const THEME_COLORS := {
	"crypt": Color(0.66, 0.78, 0.62),
	"cave": Color(0.42, 0.74, 0.92),
	"inferno": Color(1.0, 0.5, 0.2),
	"town": Color(0.95, 0.82, 0.5),
}

## Skill tag -> chip colour (skill book).
const TAG_COLORS := {
	"attack": Color(0.85, 0.62, 0.4),
	"spell": Color(0.6, 0.55, 1.0),
	"melee": Color(0.9, 0.38, 0.3),
	"projectile": Color(0.5, 0.82, 0.45),
	"area": Color(0.4, 0.78, 0.75),
	"physical": Color(0.85, 0.83, 0.78),
	"fire": Color(1.0, 0.5, 0.15),
	"cold": Color(0.45, 0.78, 1.0),
	"lightning": Color(1.0, 0.92, 0.35),
	"chaos": Color(0.78, 0.4, 0.95),
	"movement": Color(0.55, 0.9, 0.9),
	"warcry": Color(0.95, 0.6, 0.3),
	"channel": Color(0.75, 0.7, 0.95),
	"duration": Color(0.7, 0.7, 0.62),
	"chain": Color(0.95, 0.9, 0.5),
	"nova": Color(0.55, 0.85, 1.0),
}

## Serif for small headings (the display cut's hairlines vanish below ~34 px).
const HEADING_FONT_NAMES: PackedStringArray = [
	"Noto Serif", "C059", "DejaVu Serif", "Liberation Serif", "Nimbus Roman", "Georgia", "serif",
]
## Below this size title_label() uses the heading font instead of the display font.
const DISPLAY_MIN_SIZE := 34

const TITLE_FONT_NAMES: PackedStringArray = [
	"Cinzel", "Trajan Pro", "Cormorant Garamond", "Noto Serif Display", "Noto Serif", "C059",
	"DejaVu Serif", "Liberation Serif", "Nimbus Roman", "Georgia", "serif",
]

static var _theme: Theme = null
static var _title_font: Font = null
static var _heading_font: Font = null
static var _glow_tex: Texture2D = null
static var _soft_tex: Texture2D = null
static var _vignette_tex: Texture2D = null
static var _stars_tex: Texture2D = null


# ------------------------------------------------------------------ theme & fonts

## UIStyle.make_theme() plus scroll bars, focus boxes and LineEdit colours. Shared instance.
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := UIStyle.make_theme()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.35)
	track.set_corner_radius_all(4)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := StyleBoxFlat.new()
	grab.bg_color = UIStyle.COLOR_BORDER.darkened(0.15)
	grab.set_corner_radius_all(4)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = UIStyle.COLOR_BORDER_BRIGHT
	for sb_class in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_class, track)
		t.set_stylebox("scroll_focus", sb_class, track)
		t.set_stylebox("grabber", sb_class, grab)
		t.set_stylebox("grabber_highlight", sb_class, grab_hi)
		t.set_stylebox("grabber_pressed", sb_class, grab_hi)
	var le_focus := UIStyle.panel_style(Color(0, 0, 0, 0), UIStyle.COLOR_BORDER_BRIGHT, 1, 3)
	le_focus.shadow_size = 0
	t.set_stylebox("focus", "LineEdit", le_focus)
	var le_normal := UIStyle.panel_style(Color(0.03, 0.028, 0.025, 0.95), UIStyle.COLOR_BORDER, 1, 3)
	le_normal.shadow_size = 0
	le_normal.content_margin_left = 10
	le_normal.content_margin_right = 10
	le_normal.content_margin_top = 6
	le_normal.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le_normal)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("font_placeholder_color", "LineEdit", UIStyle.COLOR_TEXT_DIM.darkened(0.15))
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", UIStyle.COLOR_TEXT_DIM)
	t.set_color("font_pressed_color", "Button", GOLD_BRIGHT)
	_theme = t
	return t


## Serif display font for titles (system font with fallbacks; the default font if none exists).
static func title_font() -> Font:
	if _title_font != null:
		return _title_font
	var sf := SystemFont.new()
	sf.font_names = TITLE_FONT_NAMES
	sf.font_weight = 600
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 1
	_title_font = fv
	return fv


## Bold text serif for small headings (skill names, section titles...).
static func heading_font() -> Font:
	if _heading_font != null:
		return _heading_font
	var sf := SystemFont.new()
	sf.font_names = HEADING_FONT_NAMES
	sf.font_weight = 700
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 1
	_heading_font = fv
	return fv


## The title font for a size: the display serif when large, the heading serif when small.
static func title_font_for(font_size: int) -> Font:
	return title_font() if font_size >= DISPLAY_MIN_SIZE else heading_font()


# ------------------------------------------------------------------ generated textures

## Soft radial glow (white centre fading to transparent), 128 px. Draw it tinted.
static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		_glow_tex = _radial([0.0, 0.12, 0.3, 0.55, 0.8, 1.0], [1.0, 0.72, 0.36, 0.12, 0.03, 0.0], 128)
	return _glow_tex


## Very soft, wide falloff (nebulae, fog, moon halo).
static func soft_texture() -> Texture2D:
	if _soft_tex == null:
		_soft_tex = _radial([0.0, 0.25, 0.5, 0.75, 1.0], [0.55, 0.38, 0.18, 0.05, 0.0], 128)
	return _soft_tex


## Transparent centre, dark edges. Stretch it over a full screen.
static func vignette_texture() -> Texture2D:
	if _vignette_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 0.92))
		g.set_offset(0, 0.0)
		g.set_offset(1, 1.0)
		g.add_point(0.45, Color(0, 0, 0, 0.0))
		g.add_point(0.75, Color(0, 0, 0, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.08, 0.5)
		t.width = 256
		t.height = 256
		_vignette_tex = t
	return _vignette_tex


## Tileable 512 px starfield (deterministic).
static func stars_texture() -> Texture2D:
	if _stars_tex != null:
		return _stars_tex
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in 520:
		var x := rng.randi_range(0, n - 1)
		var y := rng.randi_range(0, n - 1)
		var b := pow(rng.randf(), 2.6)
		var tint := Color(0.85, 0.88, 1.0).lerp(Color(1.0, 0.85, 0.65), rng.randf())
		var a := 0.18 + 0.82 * b
		_blend(img, x, y, Color(tint, a))
		if b > 0.55:
			var s := 0.35 * a
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_blend(img, posmod(x + d.x, n), posmod(y + d.y, n), Color(tint, s))
		if b > 0.9:
			for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				_blend(img, posmod(x + d.x, n), posmod(y + d.y, n), Color(tint, 0.14))
	_stars_tex = ImageTexture.create_from_image(img)
	return _stars_tex


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	var old := img.get_pixel(x, y)
	var a := c.a + old.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * c.a + Color(old.r, old.g, old.b) * old.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))


static func _radial(offsets: Array, alphas: Array, size: int) -> Texture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, alphas[0]))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, alphas[-1]))
	for i in range(1, offsets.size() - 1):
		g.add_point(offsets[i], Color(1, 1, 1, alphas[i]))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


# ------------------------------------------------------------------ styles & factories

## Ornate frame background (bronze border, deep shadow).
static func frame_style(bg: Color = FRAME_BG, border: Color = UIStyle.COLOR_BORDER, radius: int = 6, margin: int = 18) -> StyleBoxFlat:
	var sb := UIStyle.panel_style(bg, border, 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	sb.set_content_margin_all(margin)
	return sb


## Row background (list entries). state: "normal" | "hover" | "selected" | "disabled".
static func row_style(state: String = "normal", accent: Color = UIStyle.COLOR_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	match state:
		"hover":
			sb.bg_color = ROW_BG_HOVER
			sb.border_color = UIStyle.COLOR_BORDER_BRIGHT
		"selected":
			sb.bg_color = ROW_BG_SELECTED
			sb.border_color = GOLD
			sb.set_border_width_all(2)
			sb.shadow_color = Color(GOLD, 0.18)
			sb.shadow_size = 8
		"disabled":
			sb.bg_color = Color(0.06, 0.055, 0.05, 0.9)
			sb.border_color = UIStyle.COLOR_BORDER.darkened(0.5)
		_:
			sb.bg_color = ROW_BG
			sb.border_color = accent.darkened(0.35)
	return sb


## A styled button (FOCUS_NONE, click sound). primary = gold accent for the main action.
static func make_button(text: String, font_size: int = UIStyle.FONT_NORMAL, primary: bool = false) -> Button:
	var b := UIStyle.make_button(text, font_size)
	var pad := 10 if font_size >= UIStyle.FONT_LARGE else 6
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		if sb == null:
			continue
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = pad
		sb.content_margin_bottom = pad
		sb.shadow_size = 4
		if primary:
			match st:
				"normal":
					sb.bg_color = Color(0.2, 0.14, 0.07, 0.98)
					sb.border_color = GOLD.darkened(0.15)
					sb.set_border_width_all(2)
				"hover":
					sb.bg_color = Color(0.3, 0.21, 0.09, 1.0)
					sb.border_color = GOLD_BRIGHT
					sb.set_border_width_all(2)
					sb.shadow_color = Color(GOLD, 0.25)
					sb.shadow_size = 10
				"pressed":
					sb.bg_color = Color(0.12, 0.08, 0.04, 1.0)
					sb.border_color = GOLD
					sb.set_border_width_all(2)
		b.add_theme_stylebox_override(st, sb)
	if primary:
		b.add_theme_color_override("font_color", GOLD_BRIGHT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD_BRIGHT)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 3)
	b.pressed.connect(func() -> void: Sfx.play_ui("ui_click"))
	return b


## Small square key button (skill slot assignment). `active` = gold highlight.
static func style_key_button(b: Button, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(3)
	normal.set_border_width_all(1)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	if active:
		normal.bg_color = Color(0.32, 0.23, 0.08, 1.0)
		normal.border_color = GOLD
	else:
		normal.bg_color = Color(0.07, 0.065, 0.06, 1.0)
		normal.border_color = UIStyle.COLOR_BORDER.darkened(0.25)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.12)
	hover.border_color = GOLD_BRIGHT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.05, 0.045, 0.04, 0.8)
	disabled.border_color = UIStyle.COLOR_BORDER.darkened(0.6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", GOLD_BRIGHT if active else UIStyle.COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", UIStyle.COLOR_TEXT_DIM.darkened(0.3))


## Label helper with an optional outline (for text over busy backgrounds).
static func label(text: String, font_size: int = UIStyle.FONT_NORMAL, color: Color = UIStyle.COLOR_TEXT, outline: int = 0) -> Label:
	var l := UIStyle.make_label(text, font_size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	return l


## Label in the title font.
static func title_label(text: String, font_size: int = UIStyle.FONT_TITLE, color: Color = UIStyle.COLOR_TITLE) -> Label:
	var l := label(text, font_size, color, 4 if font_size >= DISPLAY_MIN_SIZE else 3)
	l.add_theme_font_override("font", title_font_for(font_size))
	return l


## Marks a layout-only control MOUSE_FILTER_IGNORE (§16 mouse rule) and returns it.
static func layout(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(min_size: Vector2 = Vector2.ZERO, expand: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = min_size
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Colour of a dungeon theme ("crypt", "cave", "inferno").
static func theme_color(theme_id: String) -> Color:
	return THEME_COLORS.get(theme_id, UIStyle.COLOR_TEXT)


static func tag_color(tag: String) -> Color:
	return TAG_COLORS.get(tag, UIStyle.COLOR_TEXT_DIM)


## "3 minutes ago", "2 days ago"... for save lists.
static func time_ago(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var d := int(Time.get_unix_time_from_system()) - unix_time
	if d < 60:
		return "just now"
	if d < 3600:
		var m := d / 60
		return "%d minute%s ago" % [m, "" if m == 1 else "s"]
	if d < 86400:
		var h := d / 3600
		return "%d hour%s ago" % [h, "" if h == 1 else "s"]
	var days := d / 86400
	if days < 60:
		return "%d day%s ago" % [days, "" if days == 1 else "s"]
	return Time.get_date_string_from_unix_time(unix_time)


## 12345 -> "12,345".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ------------------------------------------------------------------ drawing helpers

## Tinted soft glow centred on `centre`.
static func draw_glow(ci: CanvasItem, centre: Vector2, radius: float, color: Color, soft: bool = false) -> void:
	if radius <= 0.5 or color.a <= 0.003:
		return
	var tex := soft_texture() if soft else glow_texture()
	ci.draw_texture_rect(tex, Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## Text with a soft coloured glow, a dark outline and the fill colour (titles).
static func draw_glow_text(ci: CanvasItem, font: Font, pos: Vector2, text: String, font_size: int, color: Color, glow: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	if glow.a > 0.0:
		for pass_i in 3:
			var o: int = [26, 15, 8][pass_i]
			var a: float = [0.07, 0.13, 0.24][pass_i]
			ci.draw_string_outline(font, pos, text, align, width, font_size, o, Color(glow, glow.a * a))
	ci.draw_string_outline(font, pos, text, align, width, font_size, 5, Color(0.02, 0.012, 0.008, 0.92 * color.a))
	ci.draw_string(font, pos, text, align, width, font_size, color)


## Small diamond ornament.
static func draw_diamond(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)


## Horizontal ornamental divider (line fading at the ends, centre diamond).
static func draw_divider(ci: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var mid := (from + to) * 0.5
	var pts := PackedVector2Array([from, mid, to])
	var cols := PackedColorArray([Color(color, 0.0), color, Color(color, 0.0)])
	ci.draw_polyline_colors(pts, cols, 1.5, true)
	draw_diamond(ci, mid, 5.0, color)
	draw_diamond(ci, mid, 2.2, Color(0.05, 0.04, 0.03))


## Check mark (cleared depths).
static func draw_check(ci: CanvasItem, c: Vector2, s: float, color: Color, width: float = 3.0) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-0.5, 0.0) * s, c + Vector2(-0.12, 0.4) * s, c + Vector2(0.55, -0.45) * s]), color, width, true)


## Padlock (locked skills).
static func draw_lock(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var body := Rect2(c + Vector2(-0.42, -0.05) * s, Vector2(0.84, 0.62) * s)
	ci.draw_arc(c + Vector2(0, -0.08) * s, 0.27 * s, PI, TAU, 16, color, maxf(1.5, 0.12 * s), true)
	ci.draw_rect(body, color)
	ci.draw_circle(c + Vector2(0, 0.2) * s, 0.08 * s, Color(0, 0, 0, 0.7))


## Coin (gold amounts).
static func draw_coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, GOLD.darkened(0.35))
	ci.draw_circle(c + Vector2(-0.08, -0.08) * r, r * 0.82, GOLD)
	ci.draw_arc(c, r * 0.55, 0, TAU, 16, GOLD.darkened(0.3), maxf(1.0, r * 0.14), true)


## Skull (death screen).
static func draw_skull(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var dark := Color(0.02, 0.0, 0.0, color.a)
	ci.draw_circle(c + Vector2(0, -0.12) * s, 0.5 * s, color)
	ci.draw_rect(Rect2(c + Vector2(-0.3, 0.1) * s, Vector2(0.6, 0.38) * s), color)
	ci.draw_circle(c + Vector2(-0.19, -0.05) * s, 0.14 * s, dark)
	ci.draw_circle(c + Vector2(0.19, -0.05) * s, 0.14 * s, dark)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.08) * s, c + Vector2(-0.07, 0.22) * s, c + Vector2(0.07, 0.22) * s]), dark)
	for i in 3:
		var x := (-0.15 + 0.15 * i) * s
		ci.draw_line(c + Vector2(x, 0.32 * s), c + Vector2(x, 0.48 * s), dark, maxf(1.0, 0.04 * s))


## Class emblem: crossed swords (warrior), bow and arrow (ranger), arcane star (sorcerer).
## `s` = half size in px.
static func draw_class_glyph(ci: CanvasItem, class_id: String, c: Vector2, s: float, color: Color) -> void:
	var w := maxf(1.5, s * 0.11)
	match class_id:
		"warrior":
			for sgn in [-1.0, 1.0]:
				var dir := Vector2(sgn * 0.7071, -0.7071)
				var tip := c + dir * s * 0.95
				var hilt := c - dir * s * 0.62
				var guard_c := c - dir * s * 0.38
				var perp := Vector2(-dir.y, dir.x)
				ci.draw_line(hilt, tip - dir * s * 0.12, color, w * 1.25, true)
				ci.draw_colored_polygon(PackedVector2Array([tip, tip - dir * s * 0.2 + perp * w * 0.8, tip - dir * s * 0.2 - perp * w * 0.8]), color)
				ci.draw_line(guard_c + perp * s * 0.24, guard_c - perp * s * 0.24, color, w, true)
				ci.draw_circle(hilt - dir * s * 0.06, w * 0.95, color)
		"ranger":
			var bc := c + Vector2(-s * 0.95, 0)
			ci.draw_arc(bc, s * 1.25, -deg_to_rad(48), deg_to_rad(48), 24, color, w * 1.1, true)
			var top := bc + Vector2.from_angle(-deg_to_rad(48)) * s * 1.25
			var bot := bc + Vector2.from_angle(deg_to_rad(48)) * s * 1.25
			ci.draw_line(top, bot, Color(color, color.a * 0.7), maxf(1.0, w * 0.45), true)
			var a0 := c + Vector2(-s * 0.9, 0)
			var a1 := c + Vector2(s * 0.95, 0)
			ci.draw_line(a0, a1 - Vector2(s * 0.12, 0), color, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([a1, a1 + Vector2(-s * 0.3, -s * 0.16), a1 + Vector2(-s * 0.3, s * 0.16)]), color)
			for k in 2:
				var fx := a0.x + s * (0.06 + 0.16 * k)
				ci.draw_line(Vector2(fx, c.y), Vector2(fx - s * 0.14, c.y - s * 0.16), color, w * 0.6, true)
				ci.draw_line(Vector2(fx, c.y), Vector2(fx - s * 0.14, c.y + s * 0.16), color, w * 0.6, true)
		"sorcerer":
			var pts := PackedVector2Array()
			for i in 16:
				var ang := -PI * 0.5 + TAU * i / 16.0
				var rr := s * (0.98 if i % 4 == 0 else (0.42 if i % 2 == 0 else 0.3))
				pts.append(c + Vector2.from_angle(ang) * rr)
			ci.draw_colored_polygon(pts, color)
			ci.draw_arc(c, s * 0.62, 0, TAU, 32, Color(color, color.a * 0.6), maxf(1.0, w * 0.5), true)
			ci.draw_circle(c, s * 0.17, Color(1, 1, 1, 0.85 * color.a))
		_:
			ci.draw_circle(c, s * 0.5, color)

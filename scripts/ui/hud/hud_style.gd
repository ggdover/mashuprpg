extends RefCounted
## Shared look of the HUD: palette, fonts, cached styleboxes and small static drawing helpers
## (bronze frames, cooldown sweeps, procedural glyphs for ailments / markers / dodge).
## Internal to the ui-hud module:  const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")
## Everything is static; fonts, styleboxes and label settings are cached.

# ------------------------------------------------------------------ palette
const BRONZE := Color(0.62, 0.48, 0.27)
const BRONZE_DARK := Color(0.28, 0.21, 0.12)
const BRONZE_LIGHT := Color(0.93, 0.78, 0.47)
const GOLD := Color(0.98, 0.8, 0.36)
const GOLD_BRIGHT := Color(1.0, 0.93, 0.68)
const PLATE := Color(0.045, 0.04, 0.035, 0.86)
const PLATE_EDGE := Color(0.02, 0.018, 0.016, 0.95)
const SLOT_BG := Color(0.03, 0.028, 0.026, 0.96)
const SHADOW := Color(0, 0, 0, 0.55)
const TEXT := UIStyle.COLOR_TEXT
const TEXT_DIM := UIStyle.COLOR_TEXT_DIM
const UNUSABLE := Color(0.75, 0.06, 0.05, 0.5)
const COOLDOWN_SHADE := Color(0.0, 0.0, 0.0, 0.66)

const LIFE_DEEP := Color(0.32, 0.015, 0.02)
const LIFE_BRIGHT := Color(0.92, 0.13, 0.1)
const MANA_DEEP := Color(0.02, 0.05, 0.3)
const MANA_BRIGHT := Color(0.22, 0.48, 1.0)
const ES_COLOR := Color(0.62, 0.88, 1.0)
const XP_DEEP := Color(0.55, 0.36, 0.08)
const XP_BRIGHT := Color(1.0, 0.84, 0.36)

const BUFF_BORDER := Color(0.85, 0.7, 0.35)
const DEBUFF_BORDER := Color(0.85, 0.18, 0.14)

## Ailment kind -> {"name", "color", "desc"} for status icons and tooltips.
const AILMENTS := {
	"ignite": {"name": "Ignited", "color": Color(1.0, 0.45, 0.1), "desc": "Burning for %s fire damage per second"},
	"bleed": {"name": "Bleeding", "color": Color(0.85, 0.1, 0.12), "desc": "Losing %s life per second"},
	"poison": {"name": "Poisoned", "color": Color(0.42, 0.9, 0.25), "desc": "Taking %s chaos damage per second"},
	"shock": {"name": "Shocked", "color": Color(1.0, 0.92, 0.3), "desc": "Taking %s%% increased damage"},
	"chill": {"name": "Chilled", "color": Color(0.45, 0.78, 1.0), "desc": "Action and movement speed %s%% slower"},
	"freeze": {"name": "Frozen", "color": Color(0.7, 0.92, 1.0), "desc": "Cannot move or act"},
	"stun": {"name": "Stunned", "color": Color(1.0, 0.82, 0.3), "desc": "Cannot move or act"},
}
const AILMENT_ORDER: Array[String] = ["stun", "freeze", "shock", "chill", "ignite", "bleed", "poison"]

## Minimap marker kind -> colour.
const MARKER_COLORS := {
	"portal": Color(0.45, 0.75, 1.0),
	"waypoint": Color(0.98, 0.8, 0.36),
	"vendor": Color(0.5, 0.95, 0.5),
	"stash": Color(0.92, 0.68, 0.3),
	"chest": Color(0.95, 0.85, 0.45),
}

const SANS_FONTS: PackedStringArray = ["Noto Sans", "DejaVu Sans", "Liberation Sans", "Nimbus Sans", "sans-serif"]
const SERIF_FONTS: PackedStringArray = ["Noto Serif", "C059", "DejaVu Serif", "Liberation Serif", "Nimbus Roman", "serif"]
const DISPLAY_FONTS: PackedStringArray = ["Cinzel", "Trajan Pro", "Cormorant Garamond", "Noto Serif Display", "Noto Serif", "C059", "DejaVu Serif", "serif"]

static var _fonts: Dictionary = {}
static var _boxes: Dictionary = {}
static var _circle_cache: Dictionary = {}


# ------------------------------------------------------------------ fonts

static func _font(key: String, names: PackedStringArray, weight: int, spacing: int = 0) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var sf := SystemFont.new()
	sf.font_names = names
	sf.font_weight = weight
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	var f: Font = sf
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = sf
		fv.spacing_glyph = spacing
		f = fv
	_fonts[key] = f
	return f


## Regular UI text.
static func font() -> Font:
	return _font("sans", SANS_FONTS, 500)


## Bold UI text (key labels, numbers).
static func bold_font() -> Font:
	return _font("sans_bold", SANS_FONTS, 700)


## Heavy font for floating damage numbers.
static func number_font() -> Font:
	return _font("sans_black", SANS_FONTS, 800)


## Serif for names (boss, nameplate, area).
static func serif_font() -> Font:
	return _font("serif_bold", SERIF_FONTS, 700, 1)


## Display serif for big titles (area banner).
static func display_font() -> Font:
	return _font("display", DISPLAY_FONTS, 600, 2)


# ------------------------------------------------------------------ styleboxes

## Cached flat stylebox. Treat as read-only.
static func box(bg: Color, border: Color, width: int = 2, radius: int = 5, shadow: int = 0) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%d" % [bg.to_html(), border.to_html(), width, radius, shadow]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_color = SHADOW
		sb.shadow_size = shadow
	_boxes[key] = sb
	return sb


# ------------------------------------------------------------------ text helpers

## Draw text with an outline. `pos` is the baseline start (left alignment).
static func text(ci: CanvasItem, f: Font, pos: Vector2, s: String, fs: int, color: Color, outline: int = 4, outline_color: Color = Color(0, 0, 0, 0.9)) -> void:
	if outline > 0:
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, outline_color)
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Draw text centred horizontally on `center_x` with the baseline at `baseline`.
static func text_centered(ci: CanvasItem, f: Font, center_x: float, baseline: float, s: String, fs: int, color: Color, outline: int = 4, outline_color: Color = Color(0, 0, 0, 0.9)) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	text(ci, f, Vector2(center_x - w * 0.5, baseline), s, fs, color, outline, outline_color)


## Draw text right-aligned to `right_x`.
static func text_right(ci: CanvasItem, f: Font, right_x: float, baseline: float, s: String, fs: int, color: Color, outline: int = 4) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	text(ci, f, Vector2(right_x - w, baseline), s, fs, color, outline)


static func text_width(f: Font, s: String, fs: int) -> float:
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## "12,345"
static func thousands(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


## Compact number for floating text: 7, 1,234, 12.3k, 1.2M.
static func compact(v: float) -> String:
	var a := absf(v)
	if a > 0.0 and a < 0.95:
		return "%.1f" % v
	if a < 100000.0:
		return thousands(int(roundf(v)))
	if a < 10000000.0:
		return "%.0fk" % (v / 1000.0)
	return "%.1fM" % (v / 1000000.0)


## Seconds for a timer label: "12s", "3.4", "1m".
static func seconds(t: float) -> String:
	if t >= 60.0:
		return "%dm" % int(ceilf(t / 60.0))
	if t >= 10.0:
		return "%ds" % int(ceilf(t))
	if t >= 1.0:
		return "%ds" % int(ceilf(t))
	return "%.1f" % maxf(0.0, t)


# ------------------------------------------------------------------ shapes

## Points of a circle (cached per segment count, unit radius).
static func unit_circle(segments: int) -> PackedVector2Array:
	if _circle_cache.has(segments):
		return _circle_cache[segments]
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)))
	_circle_cache[segments] = pts
	return pts


## Polygon covering `ratio` (0..1) of `rect`, swept clockwise from 12 o'clock (cooldown shade:
## the remaining part, which shrinks toward 12 o'clock as the cooldown runs out). Empty when
## ratio <= 0.
static func sweep_polygon(rect: Rect2, ratio: float, steps: int = 48) -> PackedVector2Array:
	if ratio <= 0.0:
		return PackedVector2Array()
	return rect_arc_polygon(rect, -PI * 0.5 + TAU * (1.0 - ratio), PI * 1.5, ratio, steps)


## Polygon covering the ELAPSED part `ratio` of `rect`, growing clockwise from 12 o'clock
## (buff / ailment timers).
static func elapsed_polygon(rect: Rect2, ratio: float, steps: int = 48) -> PackedVector2Array:
	if ratio <= 0.0:
		return PackedVector2Array()
	return rect_arc_polygon(rect, -PI * 0.5, -PI * 0.5 + TAU * ratio, ratio, steps)


## Region of `rect` between the rays at angles a0..a1 (radians, y down) from its centre.
static func rect_arc_polygon(rect: Rect2, a0: float, a1: float, ratio: float, steps: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if ratio >= 0.999:
		pts.append(rect.position)
		pts.append(Vector2(rect.end.x, rect.position.y))
		pts.append(rect.end)
		pts.append(Vector2(rect.position.x, rect.end.y))
		return pts
	var c := rect.get_center()
	var hw := rect.size.x * 0.5
	var hh := rect.size.y * 0.5
	pts.append(c)
	var n := maxi(2, int(ceil(steps * ratio)) + 1)
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		var d := Vector2(cos(a), sin(a))
		var tx := hw / maxf(0.0001, absf(d.x))
		var ty := hh / maxf(0.0001, absf(d.y))
		pts.append(c + d * minf(tx, ty))
	return pts


## Pie (circle sector) polygon: `ratio` of a circle, clockwise from 12 o'clock.
static func pie_polygon(center: Vector2, radius: float, ratio: float, steps: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if ratio <= 0.0:
		return pts
	var start := -PI * 0.5 + TAU * (1.0 - clampf(ratio, 0.0, 1.0))
	var end := PI * 1.5
	pts.append(center)
	var n := maxi(2, int(ceil(steps * ratio)) + 1)
	for i in n + 1:
		var a := lerpf(start, end, float(i) / float(n))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


## Bronze frame around a rect (outer dark line, bronze body, light inner bevel).
static func draw_bronze_frame(ci: CanvasItem, rect: Rect2, radius: int = 6, highlight: float = 0.0) -> void:
	ci.draw_style_box(box(Color(0, 0, 0, 0), PLATE_EDGE, 1, radius + 1), rect.grow(1.0))
	var border := BRONZE.lerp(BRONZE_LIGHT, clampf(highlight, 0.0, 1.0))
	ci.draw_style_box(box(Color(0, 0, 0, 0), border, 2, radius), rect)
	ci.draw_style_box(box(Color(0, 0, 0, 0), Color(BRONZE_LIGHT, 0.18 + 0.3 * highlight), 1, maxi(0, radius - 2)), rect.grow(-2.0))


## Soft radial glow made of stacked translucent circles.
static func draw_glow(ci: CanvasItem, center: Vector2, radius: float, color: Color, layers: int = 6) -> void:
	for i in layers:
		var t := float(i + 1) / float(layers)
		ci.draw_circle(center, radius * (1.0 - t * 0.75), Color(color, color.a / float(layers) * 1.4))


## A small diamond.
static func draw_diamond(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)


# ------------------------------------------------------------------ glyphs (centre c, size s = half extent)

## Status glyph for an ailment kind, drawn in `color` inside a circle of radius s.
static func draw_ailment_glyph(ci: CanvasItem, kind: String, c: Vector2, s: float, color: Color) -> void:
	match kind:
		"ignite":
			_flame(ci, c + Vector2(0, s * 0.1), s * 0.9, color)
			_flame(ci, c + Vector2(0, s * 0.3), s * 0.45, color.lerp(Color(1, 0.95, 0.6), 0.7))
		"bleed":
			_drop(ci, c + Vector2(0, s * 0.05), s * 0.8, color)
			ci.draw_circle(c + Vector2(-s * 0.2, s * 0.2), s * 0.14, Color(1, 0.7, 0.7, 0.8))
		"poison":
			_drop(ci, c + Vector2(-s * 0.15, s * 0.1), s * 0.7, color)
			ci.draw_circle(c + Vector2(s * 0.45, -s * 0.35), s * 0.18, color.lightened(0.3))
			ci.draw_circle(c + Vector2(s * 0.5, s * 0.15), s * 0.12, color.lightened(0.2))
		"shock":
			var bolt := PackedVector2Array([
				c + Vector2(0.15, -0.95) * s, c + Vector2(-0.45, 0.1) * s, c + Vector2(-0.02, 0.1) * s,
				c + Vector2(-0.2, 0.95) * s, c + Vector2(0.45, -0.15) * s, c + Vector2(0.03, -0.15) * s,
			])
			ci.draw_colored_polygon(bolt, color)
		"chill":
			_snowflake(ci, c, s * 0.85, color, 2.2)
		"stun":
			for i in 3:
				var a := -PI * 0.5 + TAU * float(i) / 3.0
				_star(ci, c + Vector2(cos(a), sin(a)) * s * 0.5, s * 0.42, color)
		"freeze":
			var crystal := PackedVector2Array([c + Vector2(0, -0.95) * s, c + Vector2(0.55, -0.2) * s,
				c + Vector2(0.35, 0.8) * s, c + Vector2(-0.35, 0.8) * s, c + Vector2(-0.55, -0.2) * s])
			ci.draw_colored_polygon(crystal, color)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -0.95) * s, c + Vector2(0, 0.8) * s]), Color(1, 1, 1, 0.7), 1.5, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.55, -0.2) * s, c + Vector2(0, 0.1) * s, c + Vector2(0.55, -0.2) * s]), Color(1, 1, 1, 0.5), 1.2, true)
		_:
			ci.draw_circle(c, s * 0.5, color)


## Five-pointed star (stun).
static func _star(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * s * (1.0 if i % 2 == 0 else 0.45))
	ci.draw_colored_polygon(pts, color)


## Parry glyph: a round shield with two crossed blades behind it.
static func draw_parry_glyph(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var w := maxf(2.0, s * 0.16)
	ci.draw_line(c + Vector2(-0.85, -0.85) * s, c + Vector2(0.85, 0.85) * s, Color(color, 0.8), w, true)
	ci.draw_line(c + Vector2(0.85, -0.85) * s, c + Vector2(-0.85, 0.85) * s, Color(color, 0.8), w, true)
	ci.draw_circle(c, s * 0.58, Color(0.1, 0.07, 0.04, 0.9))
	ci.draw_arc(c, s * 0.5, 0.0, TAU, 24, color, maxf(2.0, s * 0.16), true)
	ci.draw_circle(c, s * 0.16, color)


## Generic buff glyph (buffs without a skill icon): an upward chevron over a shield.
static func draw_buff_glyph(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var shield := PackedVector2Array([c + Vector2(-0.7, -0.75) * s, c + Vector2(0.7, -0.75) * s, c + Vector2(0.7, 0.05) * s,
		c + Vector2(0, 0.9) * s, c + Vector2(-0.7, 0.05) * s])
	ci.draw_colored_polygon(shield, Color(color, 0.85))
	ci.draw_polyline(PackedVector2Array([c + Vector2(-0.38, 0.12) * s, c + Vector2(0, -0.3) * s, c + Vector2(0.38, 0.12) * s]), Color(0.1, 0.05, 0.02, 0.9), maxf(2.0, s * 0.18), true)


## Dodge roll glyph: a curved arrow.
static func draw_dodge_glyph(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	ci.draw_arc(c, s * 0.62, PI * 0.95, PI * 2.25, 20, color, maxf(2.0, s * 0.2), true)
	var tip := c + Vector2(cos(PI * 2.25), sin(PI * 2.25)) * s * 0.62
	var dirv := Vector2(-sin(PI * 2.25), cos(PI * 2.25))
	var side := Vector2(-dirv.y, dirv.x)
	ci.draw_colored_polygon(PackedVector2Array([tip + dirv * s * 0.38, tip - side * s * 0.3, tip + side * s * 0.3]), color)
	for i in 3:
		var y := c.y - s * 0.25 + i * s * 0.25
		ci.draw_line(Vector2(c.x - s * 0.95, y), Vector2(c.x - s * 0.55 - i * s * 0.05, y), Color(color, 0.6), maxf(1.0, s * 0.1), true)


## Skull glyph (boss marker).
static func draw_skull(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	ci.draw_circle(c + Vector2(0, -s * 0.15), s * 0.72, color)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.42, s * 0.2), Vector2(s * 0.84, s * 0.55)), color)
	var dark := Color(0.08, 0.02, 0.02, 1.0)
	ci.draw_circle(c + Vector2(-s * 0.28, -s * 0.12), s * 0.2, dark)
	ci.draw_circle(c + Vector2(s * 0.28, -s * 0.12), s * 0.2, dark)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.1), c + Vector2(-s * 0.1, s * 0.3), c + Vector2(s * 0.1, s * 0.3)]), dark)
	for i in 3:
		var x := c.x - s * 0.24 + i * s * 0.24
		ci.draw_line(Vector2(x, c.y + s * 0.45), Vector2(x, c.y + s * 0.75), dark, maxf(1.0, s * 0.1))


## Minimap marker glyph.
static func draw_marker(ci: CanvasItem, kind: String, c: Vector2, s: float) -> void:
	var col: Color = MARKER_COLORS.get(kind, Color.WHITE)
	match kind:
		"portal":
			ci.draw_circle(c, s * 1.05, Color(0, 0, 0, 0.6))
			ci.draw_arc(c, s * 0.8, 0, TAU, 20, col, maxf(2.0, s * 0.35), true)
			ci.draw_circle(c, s * 0.35, col.lightened(0.4))
		"waypoint":
			draw_diamond(ci, c, s * 1.25, Color(0, 0, 0, 0.6))
			draw_diamond(ci, c, s, col)
			draw_diamond(ci, c, s * 0.45, Color(1, 1, 0.9))
		"vendor":
			ci.draw_circle(c, s * 1.05, Color(0, 0, 0, 0.6))
			ci.draw_circle(c, s * 0.85, col)
			text_centered(ci, bold_font(), c.x, c.y + s * 0.42, "$", int(maxf(8.0, s * 1.3)), Color(0.05, 0.15, 0.05), 0)
		"stash":
			var r := Rect2(c - Vector2(s, s * 0.75), Vector2(s * 2.0, s * 1.5))
			ci.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.6))
			ci.draw_rect(r, col)
			ci.draw_line(Vector2(r.position.x, c.y - s * 0.1), Vector2(r.end.x, c.y - s * 0.1), Color(0.2, 0.1, 0.03), 1.5)
		"chest":
			var r2 := Rect2(c - Vector2(s * 0.8, s * 0.6), Vector2(s * 1.6, s * 1.2))
			ci.draw_rect(r2.grow(1.5), Color(0, 0, 0, 0.6))
			ci.draw_rect(r2, col)
		_:
			ci.draw_circle(c, s * 0.8, col)


static func _flame(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var a := t * TAU
		var r := s * (0.55 + 0.45 * pow(absf(sin(a * 0.5)), 3.0))
		var p := Vector2(sin(a) * 0.62, -cos(a)) * r
		p.y = p.y * 1.1 + s * 0.15
		pts.append(c + p)
	ci.draw_colored_polygon(pts, color)


static func _drop(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(c + Vector2(0, -s))
	for i in 13:
		var a := lerpf(-PI * 0.15, PI * 1.15, float(i) / 12.0)
		pts.append(c + Vector2(cos(a) * s * 0.6, s * 0.3 + sin(a) * s * 0.6))
	ci.draw_colored_polygon(pts, color)


static func _snowflake(ci: CanvasItem, c: Vector2, s: float, color: Color, w: float) -> void:
	for i in 3:
		var a := PI / 3.0 * i + PI * 0.5
		var d := Vector2(cos(a), sin(a)) * s
		ci.draw_line(c - d, c + d, color, w, true)
		for sign_ in [-1.0, 1.0]:
			var tip: Vector2 = c + d * sign_ * 0.6
			var side := Vector2(-d.y, d.x).normalized() * s * 0.25
			var back: Vector2 = d * sign_ * 0.25
			ci.draw_line(tip, tip + back + side, color, w * 0.8, true)
			ci.draw_line(tip, tip + back - side, color, w * 0.8, true)

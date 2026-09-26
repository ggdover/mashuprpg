class_name InvStyle
extends RefCounted
## Look & feel helpers shared by the item panels (inventory, character sheet, stash, vendor):
## window frames with an ornamented title bar, section headers, gold amounts and hint lines.
## Built on UIStyle (palette, fonts). Layout-only nodes get MOUSE_FILTER_IGNORE; frames and
## buttons STOP (§16). OWNER: ui-items.

const FRAME_BG := Color(0.07, 0.062, 0.055, 0.97)
const FRAME_BORDER := Color(0.52, 0.41, 0.24)
const TITLE_BG := Color(0.13, 0.105, 0.08, 1.0)
const INSET_BG := Color(0.045, 0.04, 0.036, 0.9)
const PANEL_TOP := 64.0
const SCREEN_MARGIN := 16.0
const TITLE_FONT_NAMES: PackedStringArray = [
	"Cinzel", "Trajan Pro", "Cormorant Garamond", "Noto Serif Display", "Noto Serif", "C059",
	"DejaVu Serif", "Liberation Serif", "Nimbus Roman", "Georgia", "serif",
]
const TAB_ACTIVE := Color(0.2, 0.16, 0.1, 1.0)

static var _title_font: Font = null


## Serif display font for window titles and item names (system font with fallbacks; matches the
## menus' title font).
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


## A window frame: {"frame": PanelContainer (STOP), "body": VBoxContainer, "title": Label,
## "close": Button or null}. Add content to "body".
static func make_frame(title: String, on_close: Callable = Callable(), min_width: float = 0.0) -> Dictionary:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = FRAME_BG
	sb.border_color = FRAME_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", sb)
	if min_width > 0.0:
		frame.custom_minimum_size.x = min_width
	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 0)
	frame.add_child(outer)
	# Title bar.
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = TITLE_BG
	bsb.border_color = FRAME_BORDER
	bsb.border_width_bottom = 1
	bsb.corner_radius_top_left = 4
	bsb.corner_radius_top_right = 4
	bsb.content_margin_left = 12
	bsb.content_margin_right = 8
	bsb.content_margin_top = 6
	bsb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", bsb)
	outer.add_child(bar)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(hb)
	var left := _ornament(true)
	hb.add_child(left)
	var l := UIStyle.make_label(title, UIStyle.FONT_LARGE + 2, UIStyle.COLOR_TITLE)
	l.add_theme_font_override("font", title_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	hb.add_child(l)
	var right := _ornament(false)
	hb.add_child(right)
	var close: Button = null
	if on_close.is_valid():
		close = make_close_button()
		close.pressed.connect(on_close)
		hb.add_child(close)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(28, 28)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(spacer)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	outer.add_child(margin)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	return {"frame": frame, "body": body, "title": l, "close": close}


static func make_close_button() -> Button:
	var b := UIStyle.make_button("✕", UIStyle.FONT_SMALL)
	b.custom_minimum_size = Vector2(28, 28)
	b.tooltip_text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


## A tab button (toggle look): bronze-bordered, highlighted while `active`.
static func make_tab(text: String) -> Button:
	var b := UIStyle.make_button(text, UIStyle.FONT_NORMAL)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(110, 34)
	var on := UIStyle.panel_style(TAB_ACTIVE, UIStyle.COLOR_BORDER_BRIGHT, 1, 3)
	on.border_width_bottom = 3
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", UIStyle.COLOR_TITLE)
	b.add_theme_color_override("font_hover_pressed_color", UIStyle.COLOR_TITLE)
	return b


## An action button; `primary` gets a gold border and brighter text.
static func make_action_button(text: String, primary: bool = false, font_size: int = UIStyle.FONT_NORMAL) -> Button:
	var b := UIStyle.make_button(text, font_size)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(0, 32)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if primary and st != "disabled":
			sb.border_color = UIStyle.COLOR_BORDER_BRIGHT if st != "normal" else UIStyle.COLOR_GOLD.darkened(0.25)
			sb.bg_color = sb.bg_color.lerp(Color(0.3, 0.22, 0.08), 0.35)
		b.add_theme_stylebox_override(st, sb)
	if primary:
		b.add_theme_color_override("font_color", UIStyle.COLOR_TITLE)
		b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
	return b


## A small decorative rule for title bars.
static func _ornament(left: bool) -> Control:
	var c := Ornament.new()
	c.flip = not left
	c.custom_minimum_size = Vector2(60, 28)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Section header: dim small caps text with a fading rule. `width` 0 = expand.
static func section_header(text: String) -> Control:
	var c := SectionHeader.new()
	c.text = text
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## "Label" in dim + value right-aligned; returns [HBoxContainer, value Label].
static func key_value_row(key: String, value: String = "", value_color: Color = UIStyle.COLOR_TEXT, font_size: int = 15) -> Array:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := UIStyle.make_label(key, font_size, UIStyle.COLOR_TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(k)
	var v := UIStyle.make_label(value, font_size, value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(v)
	return [hb, v]


## Coin icon + amount label; returns [HBoxContainer, Label].
static func gold_row(amount: int, font_size: int = UIStyle.FONT_NORMAL, icon_size: float = 22.0) -> Array:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 4)
	var tr := TextureRect.new()
	tr.texture = Assets.item_icon("loot_gold")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(icon_size, icon_size)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tr)
	var l := UIStyle.make_label(format_int(amount), font_size, UIStyle.COLOR_GOLD)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	return [hb, l]


## Small dim hint text (key hints under a panel).
static func hint_label(text: String) -> Label:
	var l := UIStyle.make_label(text, 13, UIStyle.COLOR_TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## An inset (darker) box for grouping; returns the PanelContainer (IGNORE: it sits inside a frame).
static func inset(margin: int = 8) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = INSET_BG
	sb.border_color = Color(FRAME_BORDER.r, FRAME_BORDER.g, FRAME_BORDER.b, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Tooltip anchor for a control inside `frame`: the frame's horizontal extent at the control's
## height, so tooltips open beside the panel instead of over its grid.
static func frame_anchor(frame: Control, ctrl: Control) -> Rect2:
	var r := ctrl.get_global_rect()
	if frame == null or not frame.is_inside_tree():
		return r
	var f := frame.get_global_rect()
	return Rect2(f.position.x, r.position.y, f.size.x, r.size.y)


## 12345 -> "12,345".
static func format_int(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


## Tooltip line helper (Item.get_tooltip_lines format).
static func line(text: String, color: Color = UIStyle.COLOR_TEXT, size: String = "small") -> Dictionary:
	return {"text": text, "color": color, "size": size}


static func separator() -> Dictionary:
	return {"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true}


## Anchor `frame` to the right edge of its parent (top at PANEL_TOP), growing leftwards.
static func dock_right(frame: Control, top: float = PANEL_TOP, margin: float = SCREEN_MARGIN) -> void:
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 0.0
	frame.anchor_bottom = 0.0
	frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame.offset_right = -margin
	frame.offset_left = -margin
	frame.offset_top = top
	frame.offset_bottom = top


## Anchor `frame` to the left edge of its parent at x = margin.
static func dock_left(frame: Control, top: float = PANEL_TOP, margin: float = SCREEN_MARGIN) -> void:
	frame.anchor_left = 0.0
	frame.anchor_right = 0.0
	frame.anchor_top = 0.0
	frame.anchor_bottom = 0.0
	frame.grow_horizontal = Control.GROW_DIRECTION_END
	frame.offset_left = margin
	frame.offset_right = margin
	frame.offset_top = top
	frame.offset_bottom = top


## Decorative fading rule with a diamond, used on both sides of window titles.
class Ornament:
	extends Control
	var flip := false

	func _draw() -> void:
		var y := roundf(size.y * 0.5) + 0.5
		var c := Color(InvStyle.FRAME_BORDER.r, InvStyle.FRAME_BORDER.g, InvStyle.FRAME_BORDER.b, 0.9)
		var c0 := Color(c.r, c.g, c.b, 0.0)
		var a := Vector2(4, y)
		var b := Vector2(size.x - 10, y)
		if flip:
			a = Vector2(size.x - 4, y)
			b = Vector2(10, y)
		draw_polyline_colors(PackedVector2Array([a, b]), PackedColorArray([c0, c]), 1.0)
		var d := 3.5
		var tip := b + Vector2(-4 if flip else 4, 0)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -d), tip + Vector2(d, 0), tip + Vector2(0, d), tip + Vector2(-d, 0)]), UIStyle.COLOR_BORDER_BRIGHT)


## Section header: small bronze caps text followed by a fading rule.
class SectionHeader:
	extends Control
	var text := "":
		set(v):
			text = v
			queue_redraw()
	var font_size := 14

	func _init() -> void:
		custom_minimum_size = Vector2(0, 24)

	func _draw() -> void:
		var font := get_theme_default_font()
		var t := text.to_upper()
		var baseline := 16.0
		draw_string(font, Vector2(0, baseline), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIStyle.COLOR_TITLE.darkened(0.12))
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var y := roundf(baseline - 4.0) + 0.5
		var c := Color(InvStyle.FRAME_BORDER.r, InvStyle.FRAME_BORDER.g, InvStyle.FRAME_BORDER.b, 0.8)
		if size.x > tw + 14.0:
			draw_polyline_colors(PackedVector2Array([Vector2(tw + 8.0, y), Vector2(size.x, y)]), PackedColorArray([c, Color(c.r, c.g, c.b, 0.0)]), 1.0)

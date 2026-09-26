class_name TooltipBox
extends Control
## One tooltip box: draws Item.get_tooltip_lines()-style lines (see Item.get_tooltip_lines):
##   {"text", "color", "size": "title"|"normal"|"small", "separator": bool,
##    "parts": [{"text", "color"}], "hint": String, "italic": bool}
## Lines are centred (classic ARPG look); the rows above the first separator sit on a header band
## tinted with the title colour; separators are thin fading rules; long single-colour lines wrap.
## `hint` texts (affix name + tier) are shown under their line while show_hints is on (Alt held).
## Used by TooltipPanel (the shared hover tooltip) and embedded by the vendor's crafting preview.
## Never takes the mouse. OWNER: ui-items.

const PAD_X := 16.0
const PAD_Y := 10.0
const LINE_GAP := 2.0
const SEP_HEIGHT := 13.0
const HEADER_GAP := 4.0
const MIN_WIDTH := 190.0
## Font sizes per line "size".
const SIZES := {"title": 22, "normal": 16, "small": 14}
## Titles shrink down to this size before wrapping.
const TITLE_MIN_SIZE := 17
const HINT_COLOR := Color(0.62, 0.6, 0.55)
const BG_COLOR := Color(0.035, 0.03, 0.028, 0.965)

## Maximum box width (lines wrap inside it).
var max_width: float = 470.0
## Minimum box width.
var min_width: float = MIN_WIDTH
## Dim caption drawn above the lines (e.g. "Currently Equipped"), "" = none.
var caption: String = ""
## Show the "hint" texts of lines.
var show_hints: bool = false
## Multiplies the whole box (e.g. dim a "before" preview). Separate from modulate so callers can
## fade the tooltip in.
var dim: float = 1.0

## Layout rows: {"kind": "text"|"sep", "runs": [{"text", "color", "font", "size"}], "w", "h",
## "y", "ascent"}.
var _rows: Array = []
var _band_bottom: float = 0.0
var _accent: Color = UIStyle.COLOR_BORDER
var _lines: Array = []
var _font: Font = null
var _bold: Font = null
var _italic: Font = null
var _title: Font = null
var _style: StyleBoxFlat = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


## Lay out `lines` and resize the box. Returns the new size.
func set_lines(lines: Array, p_caption: String = "", hints: bool = false) -> Vector2:
	_lines = lines
	caption = p_caption
	show_hints = hints
	_layout()
	return size


## Number of text rows laid out (wrapped lines count separately; separators excluded).
func get_text_row_count() -> int:
	var n := 0
	for r: Dictionary in _rows:
		if r["kind"] == "text":
			n += 1
	return n


## Plain text of every laid-out row (tests / debugging), separators as "---".
func get_row_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for r: Dictionary in _rows:
		if r["kind"] == "sep":
			out.append("---")
			continue
		var t := ""
		for run: Dictionary in r["runs"]:
			t += String(run["text"])
		out.append(t)
	return out


## Colour of the frame / header band (the title line's colour).
func get_accent() -> Color:
	return _accent


# ------------------------------------------------------------------ layout

func _ensure_fonts() -> void:
	var f := get_theme_default_font()
	if f == null:
		f = ThemeDB.fallback_font
	if f == _font and _bold != null:
		return
	_font = f
	var b := FontVariation.new()
	b.base_font = f
	b.variation_embolden = 0.55
	_bold = b
	var it := FontVariation.new()
	it.base_font = f
	it.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.2, 1.0), Vector2.ZERO)
	_italic = it
	_title = InvStyle.title_font()


func _layout() -> void:
	_ensure_fonts()
	_rows.clear()
	_accent = UIStyle.COLOR_BORDER
	for l: Variant in _lines:
		if l is Dictionary and String(l.get("size", "")) == "title" and not bool(l.get("separator", false)):
			_accent = _color_of(l.get("color", UIStyle.COLOR_TITLE))
			break
	var inner_max := maxf(60.0, max_width - PAD_X * 2.0)
	var y := PAD_Y
	var widest := 0.0
	if caption != "":
		var cap_size: int = SIZES["small"]
		var cw := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size).x
		_rows.append({"kind": "text", "runs": [{"text": caption, "color": UIStyle.COLOR_TEXT_DIM, "font": _font, "size": cap_size}], "w": cw, "h": _font.get_height(cap_size), "y": y, "ascent": _font.get_ascent(cap_size), "caption": true})
		y += _font.get_height(cap_size) + HEADER_GAP
		widest = maxf(widest, cw)
	var band_top := y - 4.0 if caption != "" else 0.0
	var in_band := true
	var saw_text := false
	_band_bottom = 0.0
	var last_was_sep := true
	for l: Variant in _lines:
		if not (l is Dictionary):
			continue
		var line: Dictionary = l
		if bool(line.get("separator", false)):
			if last_was_sep or not saw_text:
				continue
			if in_band:
				_band_bottom = y + SEP_HEIGHT * 0.5
				in_band = false
			_rows.append({"kind": "sep", "runs": [], "w": 0.0, "h": SEP_HEIGHT, "y": y, "ascent": 0.0})
			y += SEP_HEIGHT
			last_was_sep = true
			continue
		var size_key := String(line.get("size", "normal"))
		var fsize: int = SIZES.get(size_key, SIZES["normal"])
		var font: Font = _font
		if size_key == "title":
			font = _title
			# Long names shrink a little before they wrap.
			var tt := String(line.get("text", ""))
			while fsize > TITLE_MIN_SIZE and font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > inner_max:
				fsize -= 1
		elif bool(line.get("italic", false)):
			font = _italic
		var runs: Array = []
		var parts: Variant = line.get("parts", null)
		if parts is Array and not (parts as Array).is_empty():
			for p: Variant in parts:
				if p is Dictionary:
					runs.append({"text": String(p.get("text", "")), "color": _color_of(p.get("color", UIStyle.COLOR_TEXT)), "font": font, "size": fsize})
		else:
			runs.append({"text": String(line.get("text", "")), "color": _color_of(line.get("color", UIStyle.COLOR_TEXT)), "font": font, "size": fsize})
		for row_runs: Array in _wrap(runs, inner_max):
			var w := 0.0
			for r: Dictionary in row_runs:
				w += (r["font"] as Font).get_string_size(r["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, r["size"]).x
			var h := font.get_height(fsize)
			_rows.append({"kind": "text", "runs": row_runs, "w": w, "h": h, "y": y, "ascent": font.get_ascent(fsize)})
			y += h + LINE_GAP
			widest = maxf(widest, w)
		if show_hints and String(line.get("hint", "")) != "":
			var hs: int = SIZES["small"] - 1
			var ht := String(line["hint"])
			for hrow: Array in _wrap([{"text": ht, "color": HINT_COLOR, "font": _italic, "size": hs}], inner_max):
				var hw := 0.0
				for r: Dictionary in hrow:
					hw += (r["font"] as Font).get_string_size(r["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
				_rows.append({"kind": "text", "runs": hrow, "w": hw, "h": _font.get_height(hs), "y": y, "ascent": _font.get_ascent(hs)})
				y += _font.get_height(hs) + LINE_GAP
				widest = maxf(widest, hw)
		saw_text = true
		last_was_sep = false
	# Drop a trailing separator.
	if not _rows.is_empty() and _rows.back()["kind"] == "sep":
		y -= SEP_HEIGHT
		_rows.pop_back()
	if in_band:
		# No separator: the band covers the title rows only.
		_band_bottom = 0.0
		for r: Dictionary in _rows:
			if r["kind"] == "text" and not r.has("caption") and (r["runs"] as Array).size() > 0 and (r["runs"][0]["font"] == _title):
				_band_bottom = float(r["y"]) + float(r["h"]) + 3.0
	y += PAD_Y - LINE_GAP
	var w_total := clampf(widest + PAD_X * 2.0, minf(min_width, max_width), max_width)
	set_meta("band_top", band_top)
	custom_minimum_size = Vector2(ceilf(w_total), ceilf(y))
	size = custom_minimum_size
	queue_redraw()


## Split runs into rows no wider than max_w (word wrap). Spacing between runs is kept exactly
## ("Level 16" + ", " stays "Level 16, "); lines only break where the text has a space.
func _wrap(runs: Array, max_w: float) -> Array:
	var total := 0.0
	for r: Dictionary in runs:
		total += (r["font"] as Font).get_string_size(r["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, r["size"]).x
	if total <= max_w:
		return [runs]
	# Tokens: words with a flag telling whether whitespace preceded them in the whole line.
	var tokens: Array = []
	var pending_space := false
	for ri in runs.size():
		var t := String((runs[ri] as Dictionary)["text"])
		var word := ""
		var word_sp := false
		for ch in t:
			if ch == " ":
				if word != "":
					tokens.append({"text": word, "sp": word_sp, "src": ri})
					word = ""
				pending_space = true
			else:
				if word == "":
					word_sp = pending_space
					pending_space = false
				word += ch
		if word != "":
			tokens.append({"text": word, "sp": word_sp, "src": ri})
	var rows: Array = []
	var cur: Array = []
	var cur_w := 0.0
	for tok: Dictionary in tokens:
		var r: Dictionary = runs[int(tok["src"])]
		var font: Font = r["font"]
		var fs: int = r["size"]
		var sp := bool(tok["sp"]) and cur_w > 0.0
		var sep := " " if sp else ""
		var ww := font.get_string_size(sep + String(tok["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# Break only at spaces (a token glued to the previous one stays on its line).
		if bool(tok["sp"]) and cur_w > 0.0 and cur_w + ww > max_w:
			rows.append(cur)
			cur = []
			cur_w = 0.0
			sep = ""
			ww = font.get_string_size(String(tok["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if not cur.is_empty() and int(cur.back()["src"]) == int(tok["src"]):
			cur.back()["text"] = String(cur.back()["text"]) + sep + String(tok["text"])
		else:
			cur.append({"text": sep + String(tok["text"]), "color": r["color"], "font": font, "size": fs, "src": tok["src"]})
		cur_w += ww
	if not cur.is_empty():
		rows.append(cur)
	return rows


static func _color_of(v: Variant) -> Color:
	if v is Color:
		return v
	if v is String or v is StringName:
		return Color.from_string(String(v), UIStyle.COLOR_TEXT)
	return UIStyle.COLOR_TEXT


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _rows.is_empty():
		return
	var w := size.x
	var h := size.y
	var k := clampf(dim, 0.0, 1.0)
	if _style == null:
		_style = StyleBoxFlat.new()
		_style.set_corner_radius_all(3)
		_style.shadow_color = Color(0, 0, 0, 0.55)
		_style.shadow_size = 8
		_style.shadow_offset = Vector2(0, 3)
	_style.bg_color = BG_COLOR
	_style.border_color = _accent.darkened(0.45) * Color(1, 1, 1, 0.95)
	_style.set_border_width_all(1)
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	# Inner hairline for a double-frame look.
	draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(_accent.r, _accent.g, _accent.b, 0.13), false, 1.0)
	# Header band.
	var band_top := float(get_meta("band_top", 0.0))
	if _band_bottom > band_top + 2.0:
		var a := Vector2(3, band_top + 3.0)
		var b := Vector2(w - 3.0, _band_bottom)
		var top_c := Color(_accent.r, _accent.g, _accent.b, 0.24)
		var bot_c := Color(_accent.r, _accent.g, _accent.b, 0.05)
		draw_polygon(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]), PackedColorArray([top_c, top_c, bot_c, bot_c]))
	for r: Dictionary in _rows:
		var y: float = r["y"]
		if r["kind"] == "sep":
			var cy := roundf(y + SEP_HEIGHT * 0.5) + 0.5
			var c := Color(_accent.r, _accent.g, _accent.b, 0.55)
			var c0 := Color(c.r, c.g, c.b, 0.0)
			draw_polyline_colors(PackedVector2Array([Vector2(PAD_X * 0.5, cy), Vector2(w * 0.5, cy), Vector2(w - PAD_X * 0.5, cy)]), PackedColorArray([c0, c, c0]), 1.0)
			var d := 2.5
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, cy - d), Vector2(w * 0.5 + d, cy), Vector2(w * 0.5, cy + d), Vector2(w * 0.5 - d, cy)]), Color(c.r, c.g, c.b, 0.9))
			continue
		var x := roundf((w - float(r["w"])) * 0.5)
		var base_y := y + float(r["ascent"])
		for run: Dictionary in r["runs"]:
			var font: Font = run["font"]
			var fs: int = run["size"]
			var col: Color = run["color"]
			if k < 1.0:
				col = col.lerp(Color(0.35, 0.33, 0.3, col.a), 1.0 - k)
			draw_string(font, Vector2(x, base_y), run["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += font.get_string_size(run["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

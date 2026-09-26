extends Control
## Big fading area title shown when an area is entered ("Depth 4 — The Caves" / "Monster Level
## 4", "Emberfall" / "Town"), with ornamental rules. Display only.
## Internal: preload("res://scripts/ui/hud/hud_area_banner.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const FADE_IN := 0.45
const HOLD := 2.2
const FADE_OUT := 0.9

var title: String = ""
var subtitle: String = ""
var accent: Color = UIStyle.COLOR_TITLE
var _t := -1.0


func _init() -> void:
	name = "AreaBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(900, 110)
	visible = false


func play(p_title: String, p_subtitle: String, p_accent: Color) -> void:
	title = p_title
	subtitle = p_subtitle
	accent = p_accent
	_t = 0.0
	visible = title != ""
	modulate.a = 0.0
	queue_redraw()


func is_playing() -> bool:
	return _t >= 0.0


func step(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var total := FADE_IN + HOLD + FADE_OUT
	if _t >= total:
		_t = -1.0
		visible = false
		return
	var a := 1.0
	if _t < FADE_IN:
		a = _t / FADE_IN
	elif _t > FADE_IN + HOLD:
		a = 1.0 - (_t - FADE_IN - HOLD) / FADE_OUT
	modulate.a = clampf(a, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if title == "":
		return
	var cx := size.x * 0.5
	var f := HudStyle.display_font()
	var fs := 44
	var tw := HudStyle.text_width(f, title, fs)
	# Soft dark band behind the text.
	var band := Rect2(Vector2(cx - tw * 0.5 - 90.0, 8.0), Vector2(tw + 180.0, 92.0))
	for i in 6:
		var g := band.grow(-float(i) * 6.0)
		draw_rect(g, Color(0, 0, 0, 0.06))
	HudStyle.text_centered(self, f, cx, 58.0, title, fs, accent.lerp(Color.WHITE, 0.15), 7, Color(0, 0, 0, 0.85))
	# The rules grow outward while the title fades in.
	var lw := 40.0 + 80.0 * clampf(_t / (FADE_IN + 0.25), 0.0, 1.0)
	var ly := 74.0
	for side in [-1.0, 1.0]:
		var x0: float = cx + side * (tw * 0.5 + 16.0)
		var x1: float = x0 + side * lw
		draw_line(Vector2(x0, ly - 18.0), Vector2(x1, ly - 18.0), Color(accent, 0.7), 1.5, true)
		HudStyle.draw_diamond(self, Vector2(x0 - side * 2.0, ly - 18.0), 4.0, accent)
	if subtitle != "":
		HudStyle.text_centered(self, HudStyle.serif_font(), cx, 92.0, subtitle, 18, UIStyle.COLOR_TEXT, 4)

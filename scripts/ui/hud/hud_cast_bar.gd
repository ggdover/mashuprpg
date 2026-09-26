extends Control
## Small cast bar above the skill bar for the Town Portal cast (Player.is_casting_portal /
## get_portal_cast_ratio). Display only.
## Internal: preload("res://scripts/ui/hud/hud_cast_bar.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const BAR_W := 260.0
const BAR_H := 12.0

var label: String = "Town Portal"
var ratio: float = 0.0
var _fade := 0.0
var _active := false


func _init() -> void:
	name = "CastBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(BAR_W + 20.0, 44.0)
	visible = false


func step(active: bool, p_ratio: float, delta: float) -> void:
	_active = active
	if active:
		ratio = clampf(p_ratio, 0.0, 1.0)
		_fade = minf(1.0, _fade + delta * 8.0)
	else:
		_fade = maxf(0.0, _fade - delta * 4.0)
	visible = _fade > 0.0
	if visible:
		modulate.a = _fade
		queue_redraw()


func _draw() -> void:
	var cx := size.x * 0.5
	var bar := Rect2(Vector2(cx - BAR_W * 0.5, 24.0), Vector2(BAR_W, BAR_H))
	HudStyle.text_centered(self, HudStyle.serif_font(), cx, 17.0, label, 16, Color(0.7, 0.85, 1.0), 4)
	draw_rect(bar.grow(3.0), Color(0, 0, 0, 0.6))
	draw_rect(bar, Color(0.03, 0.04, 0.06))
	var fw := BAR_W * ratio
	if fw > 0.5:
		draw_rect(Rect2(bar.position, Vector2(fw, BAR_H)), Color(0.2, 0.45, 0.9))
		draw_rect(Rect2(bar.position, Vector2(fw, BAR_H * 0.5)), Color(0.5, 0.75, 1.0))
		draw_rect(Rect2(Vector2(bar.position.x + fw - 2.0, bar.position.y), Vector2(2.0, BAR_H)), Color(1, 1, 1, 0.85))
	draw_rect(bar.grow(1.0), HudStyle.BRONZE, false, 1.0)

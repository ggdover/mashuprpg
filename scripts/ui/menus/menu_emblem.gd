extends Control
## Round class emblem: dark disc, class-coloured ring, gold inner ring and the class glyph
## (MenuStyle.draw_class_glyph). Layout-only. Internal: preload("res://scripts/ui/menus/menu_emblem.gd").

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")

var class_id: String = "":
	set(v):
		class_id = v
		queue_redraw()
## Soft glow behind the emblem (selected cards).
var glow: float = 0.0:
	set(v):
		glow = v
		queue_redraw()
var dim: bool = false:
	set(v):
		dim = v
		queue_redraw()


func _init(p_class: String = "", px: float = 64.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_id = p_class
	custom_minimum_size = Vector2(px, px)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var col := ClassDefs.get_color(class_id) if ClassDefs.has_class(class_id) else UIStyle.COLOR_TEXT_DIM
	if dim:
		col = col.lerp(Color(0.4, 0.4, 0.4), 0.6)
	if glow > 0.0:
		MenuStyle.draw_glow(self, c, r * 1.9, Color(col, 0.55 * glow))
	draw_circle(c, r, Color(0.035, 0.03, 0.028), true, -1.0, true)
	draw_circle(c, r * 0.9, Color(col.darkened(0.8), 1.0), true, -1.0, true)
	draw_arc(c, r - 1.5, 0, TAU, 48, col, maxf(2.0, r * 0.08), true)
	draw_arc(c, r * 0.8, 0, TAU, 48, Color(MenuStyle.GOLD, 0.45), maxf(1.0, r * 0.03), true)
	MenuStyle.draw_class_glyph(self, class_id, c, r * 0.52, col.lightened(0.25))

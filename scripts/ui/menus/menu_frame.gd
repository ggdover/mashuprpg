extends PanelContainer
## Ornate window frame of the ui-menus module: MenuStyle.frame_style() background plus a thin
## inner bronze line, gold corner diamonds and an optional accent glow along the top edge.
## Visible frame => MOUSE_FILTER_STOP (§16). Internal: preload("res://scripts/ui/menus/menu_frame.gd").

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")

## Colour of the glow along the top edge (alpha 0 = none).
var accent: Color = Color(MenuStyle.GOLD, 0.0):
	set(v):
		accent = v
		queue_redraw()
## Draw the inner line and corner diamonds.
var ornaments: bool = true


func _init(bg: Color = MenuStyle.FRAME_BG, border: Color = UIStyle.COLOR_BORDER, margin: int = 18) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", MenuStyle.frame_style(bg, border, 6, margin))


func _draw() -> void:
	if not ornaments:
		return
	var r := Rect2(Vector2.ZERO, size)
	if accent.a > 0.0:
		var top := PackedVector2Array([Vector2(12, 2), Vector2(size.x * 0.5, 2), Vector2(size.x - 12, 2)])
		draw_polyline_colors(top, PackedColorArray([Color(accent, 0.0), accent, Color(accent, 0.0)]), 2.0, true)
		MenuStyle.draw_glow(self, Vector2(size.x * 0.5, 0), minf(size.x * 0.35, 220.0), Color(accent, accent.a * 0.18), true)
	var inner := r.grow(-6)
	draw_rect(inner, Color(UIStyle.COLOR_BORDER, 0.28), false, 1.0)
	for c in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		MenuStyle.draw_diamond(self, c, 5.0, UIStyle.COLOR_BORDER_BRIGHT)
		MenuStyle.draw_diamond(self, c, 2.0, Color(0.05, 0.04, 0.03))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

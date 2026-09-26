extends Control
## Dark bronze-trimmed backplate behind the potions, skill bar and dodge slot (bottom centre),
## with a thin divider between the mouse slots and the keyboard slots. Display only.
## Internal: preload("res://scripts/ui/hud/hud_plate.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

## X positions (local) of vertical dividers.
var dividers: PackedFloat32Array = []


func _init() -> void:
	name = "SkillPlate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.05, 0.043, 0.036, 0.9)
	body.set_corner_radius_all(12)
	body.corner_radius_bottom_left = 4
	body.corner_radius_bottom_right = 4
	body.border_color = HudStyle.BRONZE_DARK
	body.set_border_width_all(2)
	body.anti_aliasing = true
	body.shadow_color = Color(0, 0, 0, 0.5)
	body.shadow_size = 10
	draw_style_box(body, r)
	# Inner gradient: lighter top band.
	var top := Rect2(r.position + Vector2(4, 3), Vector2(r.size.x - 8, r.size.y * 0.42))
	draw_style_box(HudStyle.box(Color(1, 0.9, 0.7, 0.035), Color(0, 0, 0, 0), 0, 10), top)
	# Bronze top trim with end ornaments.
	draw_line(Vector2(14, 1.5), Vector2(size.x - 14, 1.5), HudStyle.BRONZE, 2.0, true)
	draw_line(Vector2(30, 4.5), Vector2(size.x - 30, 4.5), Color(HudStyle.BRONZE_LIGHT, 0.25), 1.0, true)
	for x in [10.0, size.x - 10.0]:
		HudStyle.draw_diamond(self, Vector2(x, 3.0), 7.0, HudStyle.BRONZE_DARK)
		HudStyle.draw_diamond(self, Vector2(x, 3.0), 4.5, HudStyle.BRONZE_LIGHT)
	HudStyle.draw_diamond(self, Vector2(size.x * 0.5, 2.0), 6.0, HudStyle.BRONZE_DARK)
	HudStyle.draw_diamond(self, Vector2(size.x * 0.5, 2.0), 3.5, HudStyle.GOLD)
	for dx in dividers:
		draw_line(Vector2(dx, 14.0), Vector2(dx, size.y - 14.0), Color(0, 0, 0, 0.7), 2.0)
		draw_line(Vector2(dx + 1.5, 14.0), Vector2(dx + 1.5, size.y - 14.0), Color(HudStyle.BRONZE, 0.35), 1.0)

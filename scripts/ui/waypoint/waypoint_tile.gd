extends Button
## One depth of the waypoint grid: big depth number, dungeon theme (name, colour, glyph), monster
## level, and the boss state (slain check / "Boss awaits" / "Deepest" ribbon). `locked` tiles show
## the next, not yet reachable depth. Visible button => MOUSE_FILTER_STOP, FOCUS_NONE.
## Internal: preload("res://scripts/ui/waypoint/waypoint_tile.gd").

signal hovered(depth: int, tile: Control)
signal unhovered(depth: int)

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")

var depth: int = 1
var theme_id: String = "crypt"
var monster_level: int = 1
var cleared: bool = false
var deepest: bool = false
var locked: bool = false
var _hover := false
var _t := 0.0


func _init(p_depth: int = 1, p_cleared: bool = false, p_deepest: bool = false, p_locked: bool = false) -> void:
	depth = p_depth
	cleared = p_cleared
	deepest = p_deepest
	locked = p_locked
	theme_id = World.theme_for_depth(depth)
	monster_level = Balance.area_level_for_depth(depth)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(164, 128)
	disabled = locked
	mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, empty)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		hovered.emit(depth, self))
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw()
		unhovered.emit(depth))
	set_process(deepest and not locked)


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := MenuStyle.theme_color(theme_id)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2 if (_hover and not locked) else 1)
	if locked:
		sb.bg_color = Color(0.045, 0.042, 0.04, 0.9)
		sb.border_color = Color(UIStyle.COLOR_BORDER, 0.35)
	else:
		sb.bg_color = col.darkened(0.86).lerp(Color(0.07, 0.06, 0.05), 0.3)
		sb.border_color = col.lightened(0.2) if _hover else Color(col.darkened(0.35), 0.9)
		if _hover:
			sb.shadow_color = Color(col, 0.35)
			sb.shadow_size = 12
		if deepest:
			sb.border_color = MenuStyle.GOLD.lerp(col, 0.2 if _hover else 0.0)
			sb.set_border_width_all(2)
	draw_style_box(sb, r)
	if not locked:
		# Theme gradient band + glyph.
		MenuStyle.draw_glow(self, Vector2(size.x - 34, 34), 70.0, Color(col, 0.16 if not _hover else 0.28), true)
		_draw_theme_glyph(Vector2(size.x - 30, 32), 15.0, Color(col, 0.75))
	var tf := MenuStyle.title_font()
	var font := get_theme_default_font()
	var num := str(depth)
	var num_col := UIStyle.COLOR_TEXT_DIM.darkened(0.3) if locked else (Color.WHITE if _hover else UIStyle.COLOR_TITLE)
	draw_string_outline(tf, Vector2(14, 50), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 4, Color(0, 0, 0, 0.8))
	draw_string(tf, Vector2(14, 50), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, num_col)
	if locked:
		MenuStyle.draw_lock(self, Vector2(size.x - 30, 32), 22.0, Color(UIStyle.COLOR_TEXT_DIM, 0.6))
		draw_string(font, Vector2(14, 78), "Locked", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIStyle.COLOR_TEXT_DIM)
		draw_string(font, Vector2(14, 100), "Slay the boss of", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UIStyle.COLOR_TEXT_DIM, 0.8))
		draw_string(font, Vector2(14, 117), "Depth %d first" % (depth - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UIStyle.COLOR_TEXT_DIM, 0.8))
		return
	draw_string(font, Vector2(14, 76), World.theme_display_name(theme_id), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 15, col.lightened(0.15))
	draw_string(font, Vector2(14, 97), "Monster Level %d" % monster_level, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.COLOR_TEXT)
	if cleared:
		MenuStyle.draw_check(self, Vector2(22, 112), 14.0, UIStyle.COLOR_GOOD, 2.5)
		draw_string(font, Vector2(34, 118), "Boss slain", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIStyle.COLOR_GOOD)
	else:
		MenuStyle.draw_skull(self, Vector2(21, 112), 12.0, Color(UIStyle.COLOR_BAD, 0.85))
		draw_string(font, Vector2(34, 118), "Boss awaits", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.6, 0.5))
	if deepest:
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		var tag := "DEEPEST"
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tr := Rect2(Vector2(size.x - tw - 66, 14), Vector2(tw + 12, 18))
		draw_rect(tr, Color(MenuStyle.GOLD, 0.2 + 0.15 * pulse))
		draw_rect(tr, MenuStyle.GOLD, false, 1.0)
		draw_string(font, tr.position + Vector2(6, 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MenuStyle.GOLD_BRIGHT)


func _draw_theme_glyph(c: Vector2, s: float, col: Color) -> void:
	match theme_id:
		"crypt":
			# Tombstone with a cross.
			var pts := PackedVector2Array()
			for i in 9:
				pts.append(c + Vector2(0, -0.2 * s) + Vector2.from_angle(PI + PI * i / 8.0) * 0.6 * s)
			pts.append(c + Vector2(0.6, 0.9) * s)
			pts.append(c + Vector2(-0.6, 0.9) * s)
			draw_colored_polygon(pts, col)
			var dark := Color(0, 0, 0, 0.7)
			draw_line(c + Vector2(0, -0.45) * s, c + Vector2(0, 0.45) * s, dark, maxf(1.5, 0.14 * s))
			draw_line(c + Vector2(-0.28, -0.15) * s, c + Vector2(0.28, -0.15) * s, dark, maxf(1.5, 0.14 * s))
		"cave":
			# Crystal cluster.
			for k in 3:
				var x := (-0.45 + 0.45 * k) * s
				var hgt := (1.1 if k == 1 else 0.75) * s
				var base := c + Vector2(x, 0.8 * s)
				draw_colored_polygon(PackedVector2Array([base + Vector2(-0.2 * s, 0), base + Vector2(-0.2 * s, -hgt * 0.7), base + Vector2(0, -hgt), base + Vector2(0.2 * s, -hgt * 0.7), base + Vector2(0.2 * s, 0)]), col if k == 1 else col.darkened(0.2))
		"inferno":
			# Flame.
			# Teardrop: tip on top, round base (convex, so it always triangulates).
			var pts := PackedVector2Array([c + Vector2(0, -1.0) * s])
			var bc := c + Vector2(0, 0.35) * s
			for i in 13:
				var a := deg_to_rad(-30.0 + 240.0 * i / 12.0)
				pts.append(bc + Vector2(cos(a), sin(a)) * 0.55 * s)
			draw_colored_polygon(pts, col)
			draw_circle(c + Vector2(0, 0.45 * s), 0.25 * s, Color(1, 0.9, 0.6, 0.8), true, -1.0, true)
		_:
			draw_circle(c, 0.5 * s, col, true, -1.0, true)

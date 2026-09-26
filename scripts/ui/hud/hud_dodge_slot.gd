extends Control
## Small round dodge-roll indicator next to the skill bar: roll glyph, cooldown pie
## (Player.get_dodge_cooldown_ratio), key label, a flash when it is ready again. Tooltip on hover.
## Internal: preload("res://scripts/ui/hud/hud_dodge_slot.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const SLOT_SIZE := 46.0

var hud: Control = null
var cooldown_ratio: float = 0.0
var available: bool = true

var _hover := false
var _flash := 0.0


func _init() -> void:
	name = "DodgeSlot"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE + 14.0)
	size = custom_minimum_size
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		if hud != null and hud.has_method("show_tooltip_for"):
			hud.call("show_tooltip_for", self, get_tooltip_lines(), false))
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw()
		if hud != null and hud.has_method("hide_tooltip_for"):
			hud.call("hide_tooltip_for", self))


func _ready() -> void:
	set_process(false)


func _has_point(point: Vector2) -> bool:
	return point.distance_to(Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)) <= SLOT_SIZE * 0.5 + 2.0


func set_state(ratio: float, p_available: bool) -> void:
	if ratio <= 0.0 and cooldown_ratio > 0.0:
		_flash = 1.0
		set_process(true)
	if absf(ratio - cooldown_ratio) > 0.0005 or p_available != available:
		cooldown_ratio = ratio
		available = p_available
		queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.5)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


func get_tooltip_lines() -> Array:
	return [
		{"text": "Dodge Roll", "color": UIStyle.COLOR_TITLE, "size": "title"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Roll 6 metres through monsters, briefly avoiding all hits.", "color": UIStyle.COLOR_TEXT, "size": "normal"},
		{"text": "Cancels the current skill.  Cooldown: 1.2 s", "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Press %s" % Controls.label_for("dodge"), "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
	]


func _draw() -> void:
	var c := Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
	var r := SLOT_SIZE * 0.5
	draw_circle(c + Vector2(0, 2), r + 2.0, Color(0, 0, 0, 0.45))
	draw_circle(c, r, HudStyle.SLOT_BG)
	var ready := cooldown_ratio <= 0.0 and available
	var glyph_col := Color(0.86, 0.9, 0.95) if ready else Color(0.5, 0.5, 0.52)
	HudStyle.draw_dodge_glyph(self, c, r * 0.62, glyph_col)
	if cooldown_ratio > 0.0:
		var poly := HudStyle.pie_polygon(c, r - 2.0, cooldown_ratio)
		if poly.size() >= 3:
			draw_colored_polygon(poly, HudStyle.COOLDOWN_SHADE)
	if _flash > 0.0:
		draw_circle(c, r - 2.0, Color(1, 1, 1, 0.3 * _flash))
	draw_arc(c, r - 1.0, 0.0, TAU, 40, HudStyle.BRONZE_DARK, 4.0, true)
	draw_arc(c, r - 1.0, 0.0, TAU, 40, HudStyle.BRONZE.lerp(HudStyle.BRONZE_LIGHT, 0.6 if _hover else 0.0), 2.0, true)
	var key := Controls.label_for("dodge")
	HudStyle.text_centered(self, HudStyle.bold_font(), c.x, SLOT_SIZE + 12.0, key, 12, HudStyle.GOLD if ready else HudStyle.TEXT_DIM, 4)

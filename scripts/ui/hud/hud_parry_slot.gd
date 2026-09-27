extends Control
## Small round parry indicator next to the dodge slot: shield glyph, cooldown pie
## (Player.get_parry_cooldown_ratio), key label, a golden glow and a pip while a parry charge is
## held (Player.get_parry_charges), a flash when it is ready again. Tooltip on hover.
## Internal: preload("res://scripts/ui/hud/hud_parry_slot.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const SLOT_SIZE := 46.0
const CHARGE_COLOR := Color(1.0, 0.8, 0.32)

var hud: Control = null
var cooldown_ratio: float = 0.0
var available: bool = true
var charges: int = 0
var guarding: bool = false

var _hover := false
var _flash := 0.0
var _time := 0.0


func _init() -> void:
	name = "ParrySlot"
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


func set_state(ratio: float, p_available: bool, p_charges: int, p_guarding: bool) -> void:
	if ratio <= 0.0 and cooldown_ratio > 0.0:
		_flash = 1.0
	if p_charges > charges:
		_flash = 1.0
	var changed := absf(ratio - cooldown_ratio) > 0.0005 or p_available != available or p_charges != charges or p_guarding != guarding
	cooldown_ratio = ratio
	available = p_available
	charges = p_charges
	guarding = p_guarding
	set_process(_flash > 0.0 or charges > 0)
	if changed:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()
	if _flash <= 0.0 and charges <= 0:
		set_process(false)


func get_tooltip_lines() -> Array:
	return [
		{"text": "Parry", "color": UIStyle.COLOR_TITLE, "size": "title"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Hold to keep your guard up (you move slowly and can't use skills meanwhile). A blow that lands while it is up deals no damage, knocks back and stuns every monster in front of you, and gives a Parry Charge.", "color": UIStyle.COLOR_TEXT, "size": "normal"},
		{"text": "Parry Charge: your next damaging skill deals 50% more damage, fires 2 more projectiles, covers a bigger area, and attacks strike twice.", "color": UIStyle.COLOR_MOD, "size": "normal"},
		{"text": "Cancels the current skill.  Cooldown: 3 s after a parry (none otherwise)", "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Hold %s" % Controls.label_for("parry"), "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
	]


func _draw() -> void:
	var c := Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
	var r := SLOT_SIZE * 0.5
	draw_circle(c + Vector2(0, 2), r + 2.0, Color(0, 0, 0, 0.45))
	if charges > 0:
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		draw_circle(c, r + 4.0 + pulse * 2.0, Color(CHARGE_COLOR, 0.25 + 0.2 * pulse))
	draw_circle(c, r, HudStyle.SLOT_BG)
	var ready := cooldown_ratio <= 0.0 and available
	var glyph_col := Color(0.86, 0.9, 0.95) if ready else Color(0.5, 0.5, 0.52)
	if charges > 0 or guarding:
		glyph_col = CHARGE_COLOR
	HudStyle.draw_parry_glyph(self, c, r * 0.62, glyph_col)
	if cooldown_ratio > 0.0:
		var poly := HudStyle.pie_polygon(c, r - 2.0, cooldown_ratio)
		if poly.size() >= 3:
			draw_colored_polygon(poly, HudStyle.COOLDOWN_SHADE)
	if _flash > 0.0:
		draw_circle(c, r - 2.0, Color(1, 0.95, 0.8, 0.3 * _flash))
	var rim := HudStyle.BRONZE.lerp(HudStyle.BRONZE_LIGHT, 0.6 if _hover else 0.0)
	if charges > 0:
		rim = CHARGE_COLOR
	draw_arc(c, r - 1.0, 0.0, TAU, 40, HudStyle.BRONZE_DARK, 4.0, true)
	draw_arc(c, r - 1.0, 0.0, TAU, 40, rim, 2.0, true)
	for i in charges:
		draw_circle(c + Vector2(r * 0.72 - i * 9.0, -r * 0.72), 4.5, CHARGE_COLOR)
		draw_arc(c + Vector2(r * 0.72 - i * 9.0, -r * 0.72), 4.5, 0.0, TAU, 12, HudStyle.BRONZE_DARK, 1.5, true)
	var key := Controls.label_for("parry")
	HudStyle.text_centered(self, HudStyle.bold_font(), c.x, SLOT_SIZE + 12.0, key, 12, HudStyle.GOLD if ready else HudStyle.TEXT_DIM, 4)

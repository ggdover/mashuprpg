extends Control
## A potion slot: potion icon (Assets.item_icon("loot_potion_<kind>")), charge pips (partial
## pips fill up as kills refill them), a bright sweep + glow while the potion is healing, key
## label, greyed out below one charge. Click drinks it (same as the key). Hover: tooltip.
## Internal: preload("res://scripts/ui/hud/hud_potion_slot.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const SLOT_W := 52.0
const SLOT_H := 72.0

## "life" or "mana".
var kind: String = "life"
var hud: Control = null
var charges: float = 0.0
var max_charges: float = 3.0
## Remaining fraction of the running potion (0 = none).
var active_ratio: float = 0.0

var _icon: Texture2D = null
var _hover := false
var _gain_flash := 0.0
var _use_flash := 0.0
var _initialized := false


func _init(p_kind: String = "life") -> void:
	kind = p_kind
	name = "LifePotion" if kind == "life" else "ManaPotion"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	size = custom_minimum_size
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		_refresh_tooltip())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw()
		if hud != null and hud.has_method("hide_tooltip_for"):
			hud.call("hide_tooltip_for", self))


func _ready() -> void:
	_icon = Assets.item_icon("loot_potion_" + kind)
	set_process(false)


## Forget the previous values (a different character): the next set_state doesn't flash.
func reset() -> void:
	_initialized = false


func set_state(p_charges: float, p_max: float, p_active: float) -> void:
	var changed := absf(p_charges - charges) > 0.001 or absf(p_max - max_charges) > 0.001 or absf(p_active - active_ratio) > 0.0005
	if not _initialized:
		_initialized = true
		charges = p_charges
		active_ratio = p_active
		changed = true
	if floorf(p_charges + 0.0001) > floorf(charges + 0.0001) and is_inside_tree():
		_gain_flash = 1.0
		set_process(true)
	if p_active > 0.0 and active_ratio <= 0.0:
		_use_flash = 1.0
		set_process(true)
	var charges_changed := absf(p_charges - charges) > 0.001
	charges = p_charges
	max_charges = p_max
	active_ratio = p_active
	if changed:
		queue_redraw()
	if charges_changed and _hover:
		_refresh_tooltip()


func _process(delta: float) -> void:
	_gain_flash = maxf(0.0, _gain_flash - delta * 2.5)
	_use_flash = maxf(0.0, _use_flash - delta * 3.0)
	queue_redraw()
	if _gain_flash <= 0.0 and _use_flash <= 0.0:
		set_process(false)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if hud != null and hud.has_method("use_potion"):
			hud.call("use_potion", kind)


func _refresh_tooltip() -> void:
	if hud != null and hud.has_method("show_tooltip_for"):
		hud.call("show_tooltip_for", self, get_tooltip_lines(), false)


func get_tooltip_lines() -> Array:
	var is_life := kind == "life"
	var title := "Life Potion" if is_life else "Mana Potion"
	var col := Color(1.0, 0.5, 0.45) if is_life else Color(0.55, 0.7, 1.0)
	var pct := 40 if is_life else 50
	var action := "potion_life" if is_life else "potion_mana"
	return [
		{"text": title, "color": col, "size": "title"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Restores %d%% of maximum %s over 1.5 seconds" % [pct, "Life" if is_life else "Mana"], "color": UIStyle.COLOR_TEXT, "size": "normal"},
		{"text": "Charges: %s / %s" % [StatDefs.fmt(floorf(charges * 10.0) / 10.0), StatDefs.fmt(max_charges)], "color": UIStyle.COLOR_TEXT if charges >= 1.0 else UIStyle.COLOR_BAD, "size": "normal"},
		{"text": "Refills as you slay monsters and in town", "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Press %s or click to drink" % Controls.label_for(action), "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
	]


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var icon_rect := Rect2(Vector2(2, 2), Vector2(size.x - 4.0, size.x - 4.0))
	var liquid := HudStyle.LIFE_BRIGHT if kind == "life" else HudStyle.MANA_BRIGHT
	draw_style_box(HudStyle.box(HudStyle.SLOT_BG, Color(0, 0, 0, 0), 0, 6), rect)
	if active_ratio > 0.0:
		draw_style_box(HudStyle.box(Color(liquid, 0.22), Color(0, 0, 0, 0), 0, 5), icon_rect)
	var usable := charges >= 1.0 - 0.0001
	if _icon != null:
		var mod := Color.WHITE if usable else Color(0.35, 0.35, 0.35, 0.9)
		draw_texture_rect(_icon, icon_rect.grow(-3.0), false, mod)
	if active_ratio > 0.0:
		# Remaining heal time: a bright ring sweep around the icon.
		var c := icon_rect.get_center()
		var r := icon_rect.size.x * 0.5 - 2.0
		var span := TAU * active_ratio
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + span, 40, Color(liquid.lightened(0.45), 0.9), 3.0, true)
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + span, 40, Color(liquid, 0.35), 7.0, true)
	if _use_flash > 0.0:
		HudStyle.draw_glow(self, icon_rect.get_center(), icon_rect.size.x * 0.8, Color(liquid.lightened(0.4), 0.7 * _use_flash))
	# Charge pips.
	var n := maxi(1, int(roundf(max_charges)))
	var pip_w := (size.x - 12.0 - (n - 1) * 3.0) / float(n)
	var y := size.y - 13.0
	for i in n:
		var pr := Rect2(Vector2(6.0 + i * (pip_w + 3.0), y), Vector2(pip_w, 7.0))
		draw_rect(pr, Color(0.0, 0.0, 0.0, 0.85))
		var fill := clampf(charges - float(i), 0.0, 1.0)
		if fill > 0.0:
			var fc := liquid if fill >= 1.0 else Color(liquid.darkened(0.35), 0.8)
			draw_rect(Rect2(pr.position + Vector2(1, 1), Vector2((pr.size.x - 2.0) * fill, pr.size.y - 2.0)), fc)
			if fill >= 1.0:
				draw_rect(Rect2(pr.position + Vector2(1, 1), Vector2(pr.size.x - 2.0, 2.0)), Color(1, 1, 1, 0.35))
		draw_rect(pr, Color(HudStyle.BRONZE_DARK, 0.9), false, 1.0)
	if _gain_flash > 0.0:
		draw_style_box(HudStyle.box(Color(0, 0, 0, 0), Color(liquid.lightened(0.5), _gain_flash), 2, 7), rect.grow(2.0 + 3.0 * (1.0 - _gain_flash)))
	HudStyle.draw_bronze_frame(self, rect, 6, 0.55 if _hover else 0.0)
	# Key label.
	var key := Controls.label_for("potion_life" if kind == "life" else "potion_mana")
	var f := HudStyle.bold_font()
	var tag := Rect2(Vector2(3.0, 3.0), Vector2(maxf(15.0, HudStyle.text_width(f, key, 12) + 8.0), 15.0))
	draw_style_box(HudStyle.box(Color(0.02, 0.018, 0.016, 0.92), HudStyle.BRONZE_DARK, 1, 3), tag)
	HudStyle.text_centered(self, f, tag.get_center().x, tag.end.y - 3.0, key, 12, HudStyle.GOLD if usable else HudStyle.TEXT_DIM, 0)

extends Control
## Hovered-enemy card (top centre): name in the monster rarity colour, subtitle (archetype for
## magic / rare), monster mods in their colours, level, a life bar with a trailing chunk and the
## target's ailments. Fed by Events.hovered_target_changed through the HUD; uses
## Enemy.get_nameplate_info() when available (any hostile Actor works). Display only.
## Internal: preload("res://scripts/ui/hud/hud_nameplate.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")
const HudStatusBar := preload("res://scripts/ui/hud/hud_status_bar.gd")

const CARD_W := 400.0
const BAR_W := 330.0
const BAR_H := 12.0

var hud: Control = null
## Compact card (name + bar only), used while the boss bar is up.
var compact: bool = false
## Cached nameplate info of the target: name, subtitle, rarity, mods, level, is_boss.
var info: Dictionary = {}
var mod_colors: Array[Color] = []
var display_ratio: float = 1.0
var trail_ratio: float = 1.0

var _target: WeakRef = null
var _target_id := 0
var _fade := 0.0
var _active := false
var _hold := 0.0
var _ratio := 1.0
var _status: Control = null


func _init() -> void:
	name = "Nameplate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(CARD_W, 90.0)
	visible = false
	_status = HudStatusBar.new(false, 22.0)
	_status.name = "TargetStatus"
	add_child(_status)


## Show the card for this node (null / non-actor clears it).
func set_target(t: Node) -> void:
	if t == null or not is_instance_valid(t) or not (t is Actor) or (t as Actor).dead:
		clear()
		return
	if t.get_instance_id() == _target_id and _active:
		return
	_target = weakref(t)
	_target_id = t.get_instance_id()
	_read_info(t as Actor)
	_ratio = (t as Actor).life_ratio()
	display_ratio = _ratio
	trail_ratio = _ratio
	_hold = 0.0
	_active = true
	visible = true
	_layout()
	queue_redraw()


func clear() -> void:
	_active = false
	_target = null
	_target_id = 0


func is_active() -> bool:
	return _active


func get_target() -> Node:
	var t: Variant = _target.get_ref() if _target != null else null
	return t as Node if t != null and is_instance_valid(t) else null


func step(delta: float, hidden_by_boss_bar: bool) -> void:
	var t := get_target()
	if _active and (t == null or (t is Actor and (t as Actor).dead)):
		clear()
	var want := _active and not hidden_by_boss_bar
	if want:
		_fade = minf(1.0, _fade + delta * 10.0)
	else:
		_fade = maxf(0.0, _fade - delta * 6.0)
		if _fade <= 0.0:
			visible = false
			return
	visible = true
	modulate.a = _fade
	if t is Actor:
		var r := (t as Actor).life_ratio()
		if r < _ratio - 0.0005:
			_hold = 0.4
		_ratio = r
		_status.update_from(t as Actor, delta)
	display_ratio = lerpf(display_ratio, _ratio, 1.0 - exp(-delta * 18.0))
	if _ratio >= trail_ratio:
		trail_ratio = display_ratio
	elif _hold > 0.0:
		_hold -= delta
	else:
		trail_ratio = maxf(_ratio, trail_ratio - 0.6 * delta)
	_layout()
	queue_redraw()


func _read_info(a: Actor) -> void:
	if a.has_method("get_nameplate_info"):
		info = a.call("get_nameplate_info")
	else:
		var nm := a.display_name if a.display_name != "" else String(a.name).capitalize()
		info = {"name": nm, "subtitle": "", "rarity": 0, "mods": PackedStringArray(), "level": a.level, "is_boss": a.is_boss_actor}
	if String(info.get("name", "")) == "":
		info["name"] = "Monster"
	mod_colors.clear()
	var ids: Variant = a.get("monster_mods")
	if ids is Array:
		for id in ids:
			var c: Color = EnemyDB.get_mod_color(String(id)) if EnemyDB.has_method("get_mod_color") else Color(0, 0, 0, 0)
			mod_colors.append(c if c.a > 0.0 else UIStyle.COLOR_MOD)


func _rarity() -> int:
	if bool(info.get("is_boss", false)):
		return 3
	return clampi(int(info.get("rarity", 0)), 0, 3)


func _layout() -> void:
	var h := 34.0
	if String(info.get("subtitle", "")) != "" and not compact:
		h += 17.0
	if not PackedStringArray(info.get("mods", [])).is_empty() and not compact:
		h += 18.0
	h += BAR_H + 14.0
	var status_h := 0.0
	if _status.size.x > 0.0:
		status_h = _status.size.y + 4.0
	size = Vector2(CARD_W, h + status_h)
	_status.position = Vector2((CARD_W - _status.size.x) * 0.5, h)


func _draw() -> void:
	var rar := _rarity()
	var col := UIStyle.rarity_color(rar)
	var card_h := size.y - (_status.size.y + 4.0 if _status.size.x > 0.0 else 0.0)
	var card := Rect2(Vector2.ZERO, Vector2(CARD_W, card_h))
	draw_style_box(HudStyle.box(Color(0.03, 0.026, 0.024, 0.82), Color(0, 0, 0, 0), 0, 6, 6), card)
	draw_style_box(HudStyle.box(Color(0, 0, 0, 0), Color(col.darkened(0.35), 0.8), 1, 6), card)
	draw_rect(Rect2(Vector2(10, 0), Vector2(CARD_W - 20, 2)), Color(col, 0.85))
	var cx := CARD_W * 0.5
	var y := 26.0
	HudStyle.text_centered(self, HudStyle.serif_font(), cx, y, String(info.get("name", "")), 21, col, 5)
	var sub := String(info.get("subtitle", "")) if not compact else ""
	if sub != "":
		y += 17.0
		HudStyle.text_centered(self, HudStyle.font(), cx, y, sub, 14, HudStyle.TEXT_DIM, 3)
	var mods := PackedStringArray(info.get("mods", [])) if not compact else PackedStringArray()
	if not mods.is_empty():
		y += 18.0
		var f := HudStyle.font()
		var sep := "  ·  "
		var total := 0.0
		for i in mods.size():
			total += HudStyle.text_width(f, mods[i], 14)
			if i > 0:
				total += HudStyle.text_width(f, sep, 14)
		var x := cx - total * 0.5
		for i in mods.size():
			if i > 0:
				HudStyle.text(self, f, Vector2(x, y), sep, 14, HudStyle.TEXT_DIM, 3)
				x += HudStyle.text_width(f, sep, 14)
			var mc: Color = mod_colors[i] if i < mod_colors.size() else UIStyle.COLOR_MOD
			HudStyle.text(self, f, Vector2(x, y), mods[i], 14, mc, 3)
			x += HudStyle.text_width(f, mods[i], 14)
	y += 9.0
	var bar := Rect2(Vector2(cx - BAR_W * 0.5 + 18.0, y), Vector2(BAR_W - 18.0, BAR_H))
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.85))
	var fw := bar.size.x * clampf(display_ratio, 0.0, 1.0)
	var tw := bar.size.x * clampf(trail_ratio, 0.0, 1.0)
	if tw > fw + 0.5:
		draw_rect(Rect2(bar.position + Vector2(fw, 0), Vector2(tw - fw, BAR_H)), Color(1.0, 0.85, 0.6, 0.7))
	if fw > 0.5:
		draw_rect(Rect2(bar.position, Vector2(fw, BAR_H)), Color(0.5, 0.03, 0.03))
		draw_rect(Rect2(bar.position, Vector2(fw, BAR_H * 0.55)), Color(0.85, 0.12, 0.1))
	draw_rect(bar.grow(2.0), Color(HudStyle.BRONZE, 0.8), false, 1.0)
	# Level badge at the left of the bar.
	var lc := Vector2(bar.position.x - 16.0, bar.get_center().y)
	draw_circle(lc, 13.0, HudStyle.BRONZE_DARK)
	draw_circle(lc, 11.5, Color(0.05, 0.045, 0.04))
	HudStyle.text_centered(self, HudStyle.bold_font(), lc.x, lc.y + 5.0, str(int(info.get("level", 1))), 13, HudStyle.TEXT, 0)

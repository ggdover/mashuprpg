extends Control
## Boss life bar (top centre): the boss name in the unique colour, level, an ornate bar with a
## pale trailing "recent damage" chunk, life percent, an "Enraged" pulse, and the boss's ailments
## underneath. Shown by the HUD on Events.boss_spawned; hidden when the boss dies (its `died`
## signal), on Events.boss_killed and on Events.area_entered; fades in and out.
## Internal: preload("res://scripts/ui/hud/hud_boss_bar.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")
const HudStatusBar := preload("res://scripts/ui/hud/hud_status_bar.gd")

const BAR_W := 680.0
const BAR_H := 22.0
const TOP_H := 34.0
const TRAIL_HOLD := 0.5
const TRAIL_SPEED := 0.35
## Seconds a boss may be out of combat before its bar hides.
const OUT_OF_COMBAT_HIDE := 1.5

var hud: Control = null
var boss_name: String = ""
var boss_level: int = 0
## Eased life ratio and the trailing chunk.
var display_ratio: float = 1.0
var trail_ratio: float = 1.0

var _boss: WeakRef = null
var _boss_id := 0
var _showing := false
var _fade := 0.0
var _hold := 0.0
var _target := 1.0
var _enraged := false
var _time := 0.0
var _status: Control = null
var _hit_flash := 0.0
var _out_of_combat := 0.0


func _init() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(BAR_W + 60.0, TOP_H + BAR_H + 10.0)
	visible = false
	_status = HudStatusBar.new(false, 26.0)
	_status.name = "BossStatus"
	add_child(_status)


## Show the bar for this boss (any Actor; Enemy bosses give their nameplate info).
func show_boss(b: Node) -> void:
	if b == null or not is_instance_valid(b):
		return
	_disconnect_boss()
	_boss = weakref(b)
	_boss_id = b.get_instance_id()
	var info: Dictionary = b.call("get_nameplate_info") if b.has_method("get_nameplate_info") else {}
	boss_name = String(info.get("name", b.get("display_name") if b.get("display_name") != null else "Boss"))
	if boss_name == "":
		boss_name = "Boss"
	boss_level = int(info.get("level", b.get("level") if b.get("level") != null else 0))
	if b.has_signal("died") and not b.is_connected("died", _on_boss_died):
		b.connect("died", _on_boss_died)
	var r := _life_ratio(b)
	_out_of_combat = 0.0
	_target = r
	display_ratio = r
	trail_ratio = r
	_hold = 0.0
	_showing = true
	visible = true
	queue_redraw()


## Start fading out (immediate = hide now).
func hide_boss(immediate: bool = false) -> void:
	_disconnect_boss()
	_boss = null
	_boss_id = 0
	_showing = false
	if immediate:
		_fade = 0.0
		visible = false


func is_showing() -> bool:
	return _showing


func get_boss() -> Node:
	var b: Variant = _boss.get_ref() if _boss != null else null
	return b as Node if b != null and is_instance_valid(b) else null


func get_boss_instance_id() -> int:
	return _boss_id


## Local y of the bottom of what is drawn (the bar and its frame).
func get_content_bottom() -> float:
	return TOP_H + BAR_H + 8.0


func step(delta: float) -> void:
	_time += delta
	var b := get_boss()
	if _showing and (b == null or bool(b.get("dead"))):
		hide_boss()
	# A boss that left combat (leashed home, reset after the player died) drops its bar; it
	# announces itself again (Events.boss_spawned) on its next aggro.
	if _showing and b != null and b.has_method("is_in_combat") and not bool(b.call("is_in_combat")):
		_out_of_combat += delta
		if _out_of_combat >= OUT_OF_COMBAT_HIDE:
			hide_boss()
	else:
		_out_of_combat = 0.0
	if _showing:
		_fade = minf(1.0, _fade + delta * 4.0)
	else:
		_fade = maxf(0.0, _fade - delta * 2.5)
		if _fade <= 0.0:
			visible = false
			return
	modulate.a = _fade
	if b != null:
		var r := _life_ratio(b)
		if r < _target - 0.0005:
			_hold = TRAIL_HOLD
			_hit_flash = 1.0
		_target = r
		_enraged = bool(b.get("enraged")) if b.get("enraged") != null else false
		if b is Actor:
			_status.update_from(b as Actor, delta)
	display_ratio = lerpf(display_ratio, _target, 1.0 - exp(-delta * 16.0))
	if _target >= trail_ratio:
		trail_ratio = display_ratio
	elif _hold > 0.0:
		_hold -= delta
	else:
		trail_ratio = maxf(_target, trail_ratio - TRAIL_SPEED * delta)
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	# Ailments sit right of the bar's end cap (keeps the top-centre stack short).
	_status.position = Vector2(size.x * 0.5 + BAR_W * 0.5 + 34.0, TOP_H + (BAR_H - 26.0) * 0.5)
	queue_redraw()


func _life_ratio(b: Node) -> float:
	if b is Actor:
		return clampf((b as Actor).life_ratio(), 0.0, 1.0)
	return 1.0


func _on_boss_died(_actor: Variant = null, _killer: Variant = null) -> void:
	_target = 0.0
	hide_boss()


func _disconnect_boss() -> void:
	var b := get_boss()
	if b != null and b.has_signal("died") and b.is_connected("died", _on_boss_died):
		b.disconnect("died", _on_boss_died)


func _draw() -> void:
	var cx := size.x * 0.5
	var bar := Rect2(Vector2(cx - BAR_W * 0.5, TOP_H), Vector2(BAR_W, BAR_H))
	var name_col := UIStyle.rarity_color(3)
	# Name + level.
	var sf := HudStyle.serif_font()
	HudStyle.text_centered(self, sf, cx, TOP_H - 8.0, boss_name, 26, name_col, 6)
	var nw := HudStyle.text_width(sf, boss_name, 26)
	if boss_level > 0:
		HudStyle.text(self, HudStyle.font(), Vector2(cx + nw * 0.5 + 12.0, TOP_H - 9.0), "Level %d" % boss_level, 14, HudStyle.TEXT_DIM, 4)
	if _enraged:
		var ea := 0.6 + 0.4 * sin(_time * 7.0)
		HudStyle.text_right(self, HudStyle.serif_font(), cx - nw * 0.5 - 12.0, TOP_H - 9.0, "Enraged", 15, Color(1.0, 0.3, 0.15, ea), 4)
	# Frame.
	if _enraged:
		var pulse := 0.5 + 0.5 * sin(_time * 7.0)
		draw_style_box(HudStyle.box(Color(0, 0, 0, 0), Color(1.0, 0.2, 0.1, 0.35 + 0.35 * pulse), 4, 6), bar.grow(6.0))
	draw_rect(bar.grow(6.0), Color(0, 0, 0, 0.55))
	draw_style_box(HudStyle.box(Color(0.03, 0.02, 0.02, 0.95), Color(0, 0, 0, 0), 0, 3), bar.grow(3.0))
	# Trail + fill.
	var fw := BAR_W * display_ratio
	var tw := BAR_W * trail_ratio
	if tw > fw + 0.5:
		draw_rect(Rect2(bar.position + Vector2(fw, 0), Vector2(tw - fw, BAR_H)), Color(1.0, 0.85, 0.55, 0.75))
	if fw > 0.5:
		var fill := Rect2(bar.position, Vector2(fw, BAR_H))
		var deep := Color(0.42, 0.02, 0.03) if not _enraged else Color(0.55, 0.05, 0.0)
		var bright := Color(0.86, 0.1, 0.08) if not _enraged else Color(1.0, 0.35, 0.05)
		draw_rect(fill, deep)
		draw_rect(Rect2(fill.position, Vector2(fw, BAR_H * 0.55)), bright)
		draw_rect(Rect2(fill.position + Vector2(0, 2), Vector2(fw, 2.0)), Color(1, 0.8, 0.7, 0.35))
		draw_rect(Rect2(Vector2(fill.end.x - 2.0, fill.position.y), Vector2(2.0, BAR_H)), Color(1, 0.9, 0.8, 0.6 + 0.4 * _hit_flash))
	for i in range(1, 4):
		var x := bar.position.x + BAR_W * float(i) / 4.0
		draw_line(Vector2(x, bar.position.y + 2.0), Vector2(x, bar.end.y - 2.0), Color(0, 0, 0, 0.45), 1.5)
	# Bronze frame with end caps.
	HudStyle.draw_bronze_frame(self, bar.grow(3.0), 3, 0.35 + 0.4 * _hit_flash)
	for side in [-1.0, 1.0]:
		var ec := Vector2(cx + side * (BAR_W * 0.5 + 12.0), bar.get_center().y)
		HudStyle.draw_diamond(self, ec, 14.0, HudStyle.BRONZE_DARK)
		HudStyle.draw_diamond(self, ec, 10.5, HudStyle.BRONZE)
		HudStyle.draw_diamond(self, ec, 5.5, name_col if not _enraged else Color(1.0, 0.25, 0.1))
		draw_line(ec + Vector2(-side * 14.0, 0), ec + Vector2(-side * 3.0, 0), HudStyle.BRONZE_LIGHT, 1.0)
	# Percent.
	var pct := "%d%%" % int(ceilf(_target * 100.0)) if _target > 0.0 else "0%"
	HudStyle.text_centered(self, HudStyle.bold_font(), cx, bar.get_center().y + 6.0, pct, 16, Color(1, 0.95, 0.9), 4)


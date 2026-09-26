extends Control
## Experience bar along the bottom edge: gold fill easing toward the character's XP with a bright
## "just gained" band, 10% ticks, a level medallion at the left end and a glow on level up. Hover
## shows the exact numbers in a tooltip.
## Internal: preload("res://scripts/ui/hud/hud_xp_bar.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const BAR_H := 10.0
const BADGE_R := 15.0

var hud: Control = null
var level: int = 1
var xp: int = 0
var xp_needed: int = 1
var max_level: bool = false
## Displayed fill 0..1 (eases toward the real ratio).
var display_ratio: float = 0.0

var _target := 0.0
var _gain := 0.0
var _level_flash := 0.0
var _hover := false
var _initialized := false


func _init() -> void:
	name = "XpBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(200, BAR_H + 12.0)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		_refresh_tooltip())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw()
		if hud != null and hud.has_method("hide_tooltip_for"):
			hud.call("hide_tooltip_for", self))


## Forget the previous values (a different character): no level-up flash on the next set_xp.
func reset() -> void:
	_initialized = false
	_gain = 0.0
	_level_flash = 0.0


func set_xp(p_xp: int, p_needed: int, p_level: int, p_max_level: bool = false) -> void:
	var ratio := 1.0 if p_max_level else (clampf(float(p_xp) / float(maxi(1, p_needed)), 0.0, 1.0))
	if not _initialized:
		_initialized = true
		display_ratio = ratio
	elif p_level > level:
		_level_flash = 1.0
		display_ratio = 0.0
	elif ratio > _target + 0.0001:
		_gain = 1.0
	elif ratio < _target:
		display_ratio = ratio
	var changed := p_xp != xp or p_needed != xp_needed or p_level != level
	level = p_level
	xp = p_xp
	xp_needed = p_needed
	max_level = p_max_level
	_target = ratio
	if changed:
		queue_redraw()
		if _hover:
			_refresh_tooltip()


func get_target_ratio() -> float:
	return _target


func step(delta: float) -> void:
	var busy := false
	if absf(display_ratio - _target) > 0.0005:
		display_ratio = move_toward(display_ratio, _target, delta * maxf(0.25, absf(_target - display_ratio) * 3.0))
		busy = true
	else:
		display_ratio = _target
	if _gain > 0.0:
		_gain = maxf(0.0, _gain - delta * 1.2)
		busy = true
	if _level_flash > 0.0:
		_level_flash = maxf(0.0, _level_flash - delta * 0.7)
		busy = true
	if busy:
		queue_redraw()


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2(-BADGE_R, -6.0), size + Vector2(BADGE_R, 10.0)).has_point(point)


func _refresh_tooltip() -> void:
	if hud != null and hud.has_method("show_tooltip_for"):
		hud.call("show_tooltip_for", self, get_tooltip_lines(), false)


func get_tooltip_lines() -> Array:
	var lines: Array = [{"text": "Level %d" % level, "color": UIStyle.COLOR_TITLE, "size": "title"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true}]
	if max_level:
		lines.append({"text": "Maximum level reached", "color": UIStyle.COLOR_GOLD, "size": "normal"})
		return lines
	lines.append({"text": "Experience: %s / %s  (%.1f%%)" % [HudStyle.thousands(xp), HudStyle.thousands(xp_needed), 100.0 * _target], "color": UIStyle.COLOR_TEXT, "size": "normal"})
	lines.append({"text": "%s to level %d" % [HudStyle.thousands(maxi(0, xp_needed - xp)), level + 1], "color": UIStyle.COLOR_TEXT_DIM, "size": "small"})
	return lines


func _draw() -> void:
	var bar := Rect2(Vector2(0, (size.y - BAR_H) * 0.5), Vector2(size.x, BAR_H))
	draw_rect(bar.grow(3.0), Color(0, 0, 0, 0.55))
	draw_rect(bar.grow(1.0), HudStyle.BRONZE_DARK)
	draw_rect(bar, Color(0.05, 0.04, 0.02, 0.95))
	var fw := bar.size.x * clampf(display_ratio, 0.0, 1.0)
	if _target > display_ratio + 0.0005:
		var gw := bar.size.x * _target - fw
		draw_rect(Rect2(bar.position + Vector2(fw, 0), Vector2(gw, bar.size.y)), Color(1.0, 0.95, 0.7, 0.35 + 0.35 * _gain))
	if fw > 0.5:
		var fill := Rect2(bar.position, Vector2(fw, bar.size.y))
		draw_rect(fill, HudStyle.XP_DEEP)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.55)), HudStyle.XP_BRIGHT.darkened(0.08))
		draw_rect(Rect2(fill.position + Vector2(0, 1), Vector2(fill.size.x, 1.5)), Color(1, 1, 0.9, 0.45))
		draw_rect(Rect2(Vector2(fill.end.x - 2.0, fill.position.y), Vector2(2.0, fill.size.y)), Color(1, 0.97, 0.8, 0.8 + 0.2 * _gain))
	for i in range(1, 10):
		var x := bar.position.x + bar.size.x * float(i) / 10.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.6), 1.5)
		draw_line(Vector2(x + 1.0, bar.position.y + 1.0), Vector2(x + 1.0, bar.end.y - 1.0), Color(HudStyle.BRONZE_LIGHT, 0.12), 1.0)
	draw_rect(bar.grow(1.0), Color(HudStyle.BRONZE, 0.9 if not _hover else 1.0), false, 1.0)
	if _level_flash > 0.0:
		draw_rect(bar.grow(2.0 + 5.0 * (1.0 - _level_flash)), Color(HudStyle.GOLD_BRIGHT, _level_flash * 0.8), false, 2.0)
	# Level medallion at the left end.
	var bc := Vector2(0.0, size.y * 0.5)
	draw_circle(bc + Vector2(0, 2), BADGE_R + 3.0, Color(0, 0, 0, 0.5))
	draw_circle(bc, BADGE_R + 2.0, HudStyle.BRONZE_DARK)
	draw_circle(bc, BADGE_R, Color(0.06, 0.05, 0.035))
	draw_arc(bc, BADGE_R, 0.0, TAU, 40, HudStyle.BRONZE.lerp(HudStyle.GOLD_BRIGHT, _level_flash), 2.0, true)
	if _level_flash > 0.0:
		HudStyle.draw_glow(self, bc, BADGE_R * 2.6, Color(HudStyle.GOLD, 0.9 * _level_flash))
	var lt := str(level)
	HudStyle.text_centered(self, HudStyle.bold_font(), bc.x, bc.y + 6.0, lt, 17 if level < 100 else 14, HudStyle.GOLD_BRIGHT, 4)

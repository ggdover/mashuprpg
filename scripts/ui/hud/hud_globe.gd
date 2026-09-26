extends Control
## A life or mana globe: liquid (canvas shader: waving surface, swirls, rising specks, glass
## highlights) that eases to the current value with a pale "recent loss" trail, a bronze ring,
## an energy-shield ring (life globe), a flash on big changes, poison/freeze tints and a low-life
## pulse. The numbers show above the globe while hovered. The hover area is the circle only.
## Internal: preload("res://scripts/ui/hud/hud_globe.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const RADIUS := 88.0
## Margin around the liquid circle (bronze ring + ES ring).
const PAD := 24.0
const TRAIL_HOLD := 0.45
const TRAIL_SPEED := 0.9

const SHADER_CODE := """
shader_type canvas_item;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 1.0;
uniform vec4 deep_color : source_color = vec4(0.3, 0.0, 0.0, 1.0);
uniform vec4 bright_color : source_color = vec4(0.9, 0.1, 0.1, 1.0);
uniform vec4 tint_color : source_color = vec4(0.4, 0.9, 0.3, 1.0);
uniform float tint_amount = 0.0;
uniform float flash = 0.0;
uniform float pulse = 0.0;
uniform float seed = 0.0;

float waves(float x, float t) {
	return sin(x * 10.0 + t * 2.3) * 0.55 + sin(x * 17.0 - t * 3.1 + 1.3) * 0.25 + sin(x * 5.0 - t * 1.2 + 4.0) * 0.35;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	float mask = 1.0 - smoothstep(1.0 - aa * 1.5, 1.0, r);
	float t = TIME + seed;
	float h = 1.0 - UV.y;
	float edge = smoothstep(0.0, 0.05, fill) * smoothstep(1.0, 0.95, fill);
	float surf = fill + 0.016 * edge * waves(UV.x, t);
	float e = max(fwidth(h), 0.003);
	float liquid = (1.0 - smoothstep(surf - e, surf + e, h)) * step(0.0005, fill);

	float depth = clamp((surf - h) / max(surf, 0.05), 0.0, 1.0);
	vec3 col_l = mix(bright_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, depth * 0.85 + r * 0.35));
	float swirl = sin(p.x * 4.0 + t * 0.6 + sin(p.y * 3.0 - t * 0.45) * 1.8) * sin(p.y * 5.0 - t * 0.8 + p.x * 1.5);
	col_l *= 1.0 + swirl * 0.13;
	vec2 q = vec2(p.x * 6.0, h * 6.0 - t * 0.35);
	vec2 cell = floor(q);
	float rnd = fract(sin(dot(cell + vec2(seed), vec2(12.9898, 78.233))) * 43758.5453);
	vec2 f = fract(q) - vec2(0.5 + (rnd - 0.5) * 0.6, 0.5);
	float speck = (1.0 - smoothstep(0.0, 0.07, length(f))) * step(0.72, rnd);
	vec3 speck_col = mix(bright_color.rgb, tint_color.rgb * 1.3, tint_amount);
	col_l += speck_col * speck * (0.35 + 0.5 * tint_amount) * step(h, surf - 0.03);
	// Status tint (poison / freeze): a coloured film under the surface, keeping the liquid's hue.
	float band = smoothstep(surf - 0.28, surf, h);
	col_l = mix(col_l, tint_color.rgb * (0.55 + 0.45 * band), tint_amount * (0.12 + 0.45 * band));
	col_l *= 1.0 + pulse * 0.5;
	float d = (h - surf) / 0.018;
	float sh = exp(-d * d) * edge;
	vec3 surf_col = mix(mix(bright_color.rgb, vec3(1.0), 0.5), tint_color.rgb * 1.4, tint_amount * 0.8);
	col_l += surf_col * sh * 0.55;

	vec3 col = vec3(0.03, 0.025, 0.025) + deep_color.rgb * 0.22 * (1.0 - r * 0.7);
	float trail_m = (1.0 - liquid) * (1.0 - smoothstep(trail - e, trail + e, h)) * step(fill + 0.002, trail);
	col = mix(col, mix(bright_color.rgb, vec3(1.0, 0.95, 0.8), 0.45) * 0.8, trail_m * 0.7);
	col = mix(col, col_l, liquid);
	col *= 1.0 - smoothstep(0.55, 1.0, r) * 0.55;
	float spec = 1.0 - smoothstep(0.0, 0.42, length((p - vec2(-0.32, -0.48)) * vec2(1.0, 1.7)));
	col += vec3(1.0) * spec * 0.2;
	float spec2 = 1.0 - smoothstep(0.0, 0.14, length((p - vec2(0.44, 0.56)) * vec2(1.6, 1.0)));
	col += vec3(1.0) * spec2 * 0.06;
	col = mix(col, vec3(1.0), flash * 0.4);
	COLOR = vec4(col, mask * 0.98);
}
"""

static var _shader: Shader = null

## "life" or "mana".
var kind: String = "life"
var value: float = 0.0
var max_value: float = 0.0
var es: float = 0.0
var max_es: float = 0.0
var regen: float = 0.0
## Displayed (eased) fill 0..1 and the recent-loss trail level.
var display_fill: float = 1.0
var trail_fill: float = 1.0
var hovered: bool = false

var _liquid: ColorRect
var _overlay: Control
var _mat: ShaderMaterial
var _target := 1.0
var _trail_hold := 0.0
var _flash := 0.0
var _es_display := 0.0
var _tint := Color(0.4, 0.9, 0.3)
var _tint_amount := 0.0
var _tint_target := 0.0
var _pulse := 0.0
var _low := false
var _time := 0.0
var _last_text := ""
var _initialized := false
var _params: Dictionary = {}


func _init(p_kind: String = "life") -> void:
	kind = p_kind
	name = "LifeGlobe" if kind == "life" else "ManaGlobe"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	var s := Vector2.ONE * (RADIUS + PAD) * 2.0
	custom_minimum_size = s
	size = s
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	var deep := HudStyle.LIFE_DEEP if kind == "life" else HudStyle.MANA_DEEP
	var bright := HudStyle.LIFE_BRIGHT if kind == "life" else HudStyle.MANA_BRIGHT
	_mat.set_shader_parameter("deep_color", deep)
	_mat.set_shader_parameter("bright_color", bright)
	_mat.set_shader_parameter("seed", 0.0 if kind == "life" else 17.3)
	_liquid = ColorRect.new()
	_liquid.name = "Liquid"
	_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_liquid.material = _mat
	_liquid.position = Vector2(PAD, PAD)
	_liquid.size = Vector2.ONE * RADIUS * 2.0
	add_child(_liquid)
	_overlay = Control.new()
	_overlay.name = "Frame"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.size = s
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	mouse_entered.connect(func() -> void:
		hovered = true
		_overlay.queue_redraw())
	mouse_exited.connect(func() -> void:
		hovered = false
		_overlay.queue_redraw())


## Only the globe circle (and its ring) takes the mouse.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= RADIUS + 10.0


## Feed the current pool values (every frame). Pass es/max_es 0 for the mana globe.
func set_values(p_value: float, p_max: float, p_es: float, p_max_es: float, p_regen: float, delta: float) -> void:
	var target := clampf(p_value / p_max, 0.0, 1.0) if p_max > 0.0 else 0.0
	if not _initialized:
		_initialized = true
		display_fill = target
		trail_fill = target
		_target = target
		_es_display = clampf(p_es / p_max_es, 0.0, 1.0) if p_max_es > 0.0 else 0.0
	# Only real hits (not per-frame DoT ticks) restart the trail's hold, so it keeps draining.
	if target < _target - 0.02:
		_trail_hold = TRAIL_HOLD
		if _target - target > 0.12:
			_flash = maxf(_flash, 0.55)
	_target = target
	var text_changed := absf(p_value - value) >= 0.5 or absf(p_max - max_value) >= 0.5 or absf(p_es - es) >= 0.5 or absf(p_max_es - max_es) >= 0.5
	var ring_changed := (p_max_es > 0.0) != (max_es > 0.0)
	value = p_value
	max_value = p_max
	es = p_es
	max_es = p_max_es
	regen = p_regen
	_step(delta)
	if (text_changed and hovered) or ring_changed:
		_overlay.queue_redraw()


## Snap the display to the current values (after binding a new player).
func snap() -> void:
	display_fill = _target
	trail_fill = _target
	_es_display = clampf(es / max_es, 0.0, 1.0) if max_es > 0.0 else 0.0
	_trail_hold = 0.0
	_apply()
	_overlay.queue_redraw()


## Show the numbers as if hovered (demos / screenshots).
func show_numbers(on: bool) -> void:
	hovered = on
	_overlay.queue_redraw()


## Tint the liquid (poison green, frozen ice) — amount 0 removes it.
func set_tint(color: Color, amount: float) -> void:
	_tint = color
	_tint_target = clampf(amount, 0.0, 1.0)


func get_tint_color() -> Color:
	return _tint


func get_tint_amount() -> float:
	return _tint_target


## Low-life heartbeat pulse on the liquid.
func set_low(on: bool) -> void:
	_low = on


## Bright flash (level up, potion).
func flash(amount: float = 0.8) -> void:
	_flash = maxf(_flash, amount)


func get_target_fill() -> float:
	return _target


func _step(delta: float) -> void:
	_time += delta
	display_fill = lerpf(display_fill, _target, 1.0 - exp(-delta * 14.0))
	if absf(display_fill - _target) < 0.0005:
		display_fill = _target
	if _target >= trail_fill:
		trail_fill = display_fill
	elif _trail_hold > 0.0:
		_trail_hold -= delta
	else:
		trail_fill = maxf(_target, trail_fill - TRAIL_SPEED * delta)
	var es_t := clampf(es / max_es, 0.0, 1.0) if max_es > 0.0 else 0.0
	var es_prev := _es_display
	_es_display = lerpf(_es_display, es_t, 1.0 - exp(-delta * 12.0))
	_flash = maxf(0.0, _flash - delta * 2.5)
	_tint_amount = move_toward(_tint_amount, _tint_target, delta * 3.0)
	if _low:
		var beat := fmod(_time, 1.1)
		_pulse = maxf(0.0, 1.0 - beat * 5.0) + maxf(0.0, 0.6 - absf(beat - 0.28) * 4.0)
	else:
		_pulse = move_toward(_pulse, 0.0, delta * 3.0)
	_apply()
	if max_es > 0.0 and absf(es_prev - _es_display) > 0.0005 or _flash > 0.0:
		_overlay.queue_redraw()


func _apply() -> void:
	_param("fill", snappedf(display_fill, 0.0005))
	_param("trail", snappedf(trail_fill, 0.0005))
	_param("flash", snappedf(_flash, 0.01))
	_param("pulse", snappedf(_pulse * 0.6, 0.005))
	_param("tint_color", _tint)
	_param("tint_amount", snappedf(_tint_amount, 0.01))


## Set a shader parameter only when it changed (material updates are not free).
func _param(param: String, v: Variant) -> void:
	if _params.get(param) == v:
		return
	_params[param] = v
	_mat.set_shader_parameter(param, v)


func _draw() -> void:
	# Drop shadow + dark backplate behind the liquid.
	var c := size * 0.5
	draw_circle(c + Vector2(0, 4), RADIUS + 14.0, Color(0, 0, 0, 0.45))
	draw_circle(c, RADIUS + 11.0, Color(0.02, 0.018, 0.016, 0.95))


func _draw_overlay() -> void:
	var ci := _overlay
	var c := size * 0.5
	var ring_r := RADIUS + 5.0
	# Bronze ring: dark body, bronze band, bevel highlights.
	ci.draw_arc(c, ring_r, 0.0, TAU, 96, HudStyle.BRONZE_DARK, 11.0, true)
	ci.draw_arc(c, ring_r, 0.0, TAU, 96, HudStyle.BRONZE, 6.0, true)
	ci.draw_arc(c, ring_r - 2.0, PI * 1.05, PI * 1.75, 32, Color(HudStyle.BRONZE_LIGHT, 0.75), 1.6, true)
	ci.draw_arc(c, ring_r + 2.5, PI * 0.1, PI * 0.8, 32, Color(0, 0, 0, 0.5), 1.5, true)
	ci.draw_arc(c, RADIUS + 0.5, 0.0, TAU, 96, Color(0, 0, 0, 0.8), 1.5, true)
	# Rivets.
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI / 8.0
		var rp := c + Vector2(cos(a), sin(a)) * ring_r
		ci.draw_circle(rp, 2.4, HudStyle.BRONZE_DARK)
		ci.draw_circle(rp - Vector2(0.6, 0.6), 1.3, HudStyle.BRONZE_LIGHT)
	# Gem on top.
	var gem_c := c + Vector2(0, -ring_r)
	var gem_col := HudStyle.LIFE_BRIGHT if kind == "life" else HudStyle.MANA_BRIGHT
	HudStyle.draw_diamond(ci, gem_c, 11.0, HudStyle.BRONZE_DARK)
	HudStyle.draw_diamond(ci, gem_c, 8.0, HudStyle.BRONZE)
	HudStyle.draw_diamond(ci, gem_c, 5.0, gem_col.lightened(0.2 + _flash * 0.5))
	# Energy shield ring (fills symmetrically up from the bottom).
	if max_es > 0.0:
		var er := RADIUS + 15.5
		ci.draw_arc(c, er, 0.0, TAU, 96, Color(0.02, 0.05, 0.08, 0.85), 6.0, true)
		if _es_display > 0.001:
			var span := PI * _es_display
			ci.draw_arc(c, er, PI * 0.5 - span, PI * 0.5 + span, 96, Color(HudStyle.ES_COLOR, 0.35), 8.0, true)
			ci.draw_arc(c, er, PI * 0.5 - span, PI * 0.5 + span, 96, HudStyle.ES_COLOR, 4.0, true)
			ci.draw_arc(c, er - 1.0, PI * 0.5 - span, PI * 0.5 + span, 96, Color(1, 1, 1, 0.5), 1.0, true)
	# Numbers while hovered.
	if hovered:
		var f := HudStyle.bold_font()
		var label := "Life" if kind == "life" else "Mana"
		var main := "%s / %s" % [HudStyle.thousands(int(ceilf(value))), HudStyle.thousands(int(roundf(max_value)))]
		var y := -6.0
		if max_es > 0.0:
			var es_txt := "Energy Shield %s / %s" % [HudStyle.thousands(int(ceilf(es))), HudStyle.thousands(int(roundf(max_es)))]
			HudStyle.text_centered(ci, f, c.x, y, es_txt, 16, HudStyle.ES_COLOR, 5)
			y -= 22.0
		if regen > 0.05:
			HudStyle.text_centered(ci, HudStyle.font(), c.x, y, "%s +%.1f/s" % [label, regen], 14, HudStyle.TEXT_DIM, 4)
			y -= 20.0
		var col := Color(1.0, 0.55, 0.5) if kind == "life" else Color(0.6, 0.72, 1.0)
		HudStyle.text_centered(ci, f, c.x, y, main, 22, col, 6)

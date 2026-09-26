extends ColorRect
## Subtle red screen-edge vignette: fades in below 35% life with a slow heartbeat pulse, plus a
## brief flash on big hits. Display only (MOUSE_FILTER_IGNORE).
## Internal: preload("res://scripts/ui/hud/hud_vignette.gd").

const LOW_START := 0.35
const LOW_FULL := 0.1

const SHADER_CODE := """
shader_type canvas_item;

uniform float intensity = 0.0;
uniform float hit = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.0, 0.02, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p * vec2(0.9, 1.0));
	float v = smoothstep(0.5, 1.4, r);
	float a = v * clamp(intensity * 0.85 + hit * 0.5, 0.0, 0.9);
	COLOR = vec4(tint.rgb * (0.55 + 0.45 * v), a);
}
"""

static var _shader: Shader = null

## Current low-life strength 0..1 (before the pulse) and hit flash.
var low: float = 0.0
var hit: float = 0.0

var _mat: ShaderMaterial
var _target := 0.0
var _time := 0.0


func _init() -> void:
	name = "LowLifeVignette"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	color = Color(1, 1, 1, 1)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	material = _mat
	visible = false


## life_ratio 0..1 of the bound player (1 = no vignette), every frame.
func step(life_ratio: float, alive: bool, delta: float) -> void:
	_time += delta
	_target = 0.0
	if alive:
		_target = clampf((LOW_START - life_ratio) / (LOW_START - LOW_FULL), 0.0, 1.0)
	low = move_toward(low, _target, delta * 1.5)
	hit = maxf(0.0, hit - delta * 2.2)
	var beat := fmod(_time, 1.05)
	var pulse := 0.72 + 0.28 * maxf(maxf(0.0, 1.0 - beat * 6.0), maxf(0.0, 0.7 - absf(beat - 0.26) * 5.0))
	var inten := low * pulse
	visible = inten > 0.002 or hit > 0.002
	if visible:
		_mat.set_shader_parameter("intensity", inten)
		_mat.set_shader_parameter("hit", hit)


## Flash the edges (a big hit). strength 0..1.
func flash_hit(strength: float) -> void:
	hit = clampf(maxf(hit, strength), 0.0, 1.0)

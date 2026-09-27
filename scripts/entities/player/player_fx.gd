extends RefCounted
## Small self-freeing visual effects of the player: level-up ring + light column + sparkles, potion
## swirl, dodge dust, the town-portal cast swirl, and the parry guard / counter burst / charge aura. Built in code (unshaded additive shaders,
## tiny GPUParticles3D, one short-lived OmniLight3D for the level up). Every effect animates with
## node-owned tweens and frees itself. OWNER: player (wave 2).
## Internal helper of Player: `const PlayerFx := preload("res://scripts/entities/player/player_fx.gd")`.

const GOLD := Color(1.0, 0.78, 0.3)
const PORTAL_BLUE := Color(0.35, 0.62, 1.0)
const LIFE_RED := Color(1.0, 0.22, 0.18)
const MANA_BLUE := Color(0.25, 0.45, 1.0)
const DUST := Color(0.55, 0.5, 0.44)

## Ring on a horizontal plane (UV space), additive. `thickness` in UV units, `alpha` fades it.
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float alpha = 1.0;
uniform float thickness = 0.06;
uniform float energy = 2.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float ring = 1.0 - smoothstep(0.0, thickness, abs(d - 0.86));
	float fill = (1.0 - smoothstep(0.0, 0.86, d)) * 0.18;
	ALBEDO = color.rgb * (ring + fill) * alpha * energy;
}
"""
## Soft disc (dust), alpha blended.
const DISC_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float alpha = 1.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = (1.0 - smoothstep(0.35, 1.0, d)) * alpha;
	ALBEDO = color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
## Vertical light column fading toward the top, additive.
const COLUMN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float alpha = 1.0;
uniform float height = 4.5;
varying float v_h;
void vertex() {
	v_h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}
void fragment() {
	float low = 1.0 - v_h;
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color.rgb * low * low * edge * alpha * 1.6;
}
"""
## Billboarded swirling portal disc; `grow` 0..1 scales it up during the cast.
const SWIRL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform float grow = 1.0;
uniform float alpha = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 / max(grow, 0.001);
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = smoothstep(0.72, 0.88, r) * (1.0 - smoothstep(0.88, 1.0, r));
	float swirl = 0.5 + 0.5 * sin(a * 3.0 - TIME * 9.0 + r * 9.0);
	float inner = (1.0 - smoothstep(0.0, 0.9, r)) * (0.25 + 0.55 * swirl);
	ALBEDO = color.rgb * (ring * 2.2 + inner) * alpha * 1.4;
}
"""

## Round translucent guard disc (the parry stance) standing in front of the player, additive.
const GUARD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float alpha = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float rim = 1.0 - smoothstep(0.0, 0.1, abs(r - 0.84));
	float fill = (1.0 - smoothstep(0.0, 0.84, r)) * (0.1 + 0.08 * sin(r * 20.0 - TIME * 12.0));
	ALBEDO = color.rgb * (rim * 1.9 + fill) * alpha;
}
"""

static var _shaders: Dictionary = {}


static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]


static func _mat(key: String, code: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(key, code)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _plane(size: float, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Tiny one-shot sparkle burst (billboard quads) rising from a ring.
static func _sparkles(color: Color, amount: int, radius: float, up_speed: float, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.55
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = radius * 0.6
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = up_speed * 0.6
	pm.initial_velocity_max = up_speed
	pm.gravity = Vector3(0, -0.6, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.2
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color = color
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(1.6, 1.6, 1.6)
	quad.material = qm
	p.draw_pass_1 = quad
	p.emitting = true
	return p


## Golden ring expanding on the ground, a fading light column, rising sparkles and a short warm
## light flash. Parented to `actor` (follows it); frees itself after ~1.6 s.
static func level_up(actor: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "LevelUpFx"
	actor.add_child(root)
	var ring_mat := _mat("ring", RING_SHADER, {"color": GOLD, "alpha": 1.0, "thickness": 0.05, "energy": 2.4})
	var ring := _plane(1.0, ring_mat)
	ring.position = Vector3(0, 0.04, 0)
	ring.scale = Vector3(0.6, 1, 0.6)
	root.add_child(ring)
	var ring2_mat := _mat("ring", RING_SHADER, {"color": GOLD, "alpha": 0.8, "thickness": 0.09, "energy": 1.6})
	var ring2 := _plane(1.0, ring2_mat)
	ring2.position = Vector3(0, 0.05, 0)
	ring2.scale = Vector3(0.3, 1, 0.3)
	root.add_child(ring2)
	var col_mat := _mat("column", COLUMN_SHADER, {"color": GOLD, "alpha": 1.0, "height": 4.5})
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.75
	cyl.height = 4.5
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 20
	cyl.rings = 1
	var col := MeshInstance3D.new()
	col.mesh = cyl
	col.material_override = col_mat
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	col.position = Vector3(0, 2.25, 0)
	root.add_child(col)
	var sp := _sparkles(GOLD, 40, 0.7, 3.2, 1.3)
	sp.position = Vector3(0, 0.2, 0)
	root.add_child(sp)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.5, 0)
	root.add_child(light)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(7.0, 1, 7.0), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "shader_parameter/alpha", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.tween_property(ring2, "scale", Vector3(4.0, 1, 4.0), 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring2_mat, "shader_parameter/alpha", 0.0, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_property(col, "scale", Vector3(0.15, 1.2, 0.15), 1.1).set_ease(Tween.EASE_IN)
	tw.tween_property(col_mat, "shader_parameter/alpha", 0.0, 1.1).set_ease(Tween.EASE_IN)
	tw.tween_property(light, "light_energy", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tw.chain().tween_interval(0.5)
	tw.chain().tween_callback(root.queue_free)
	return root


## A coloured ring rising from the feet to the chest plus a few sparkles (drinking a potion).
static func potion(actor: Node3D, kind: String) -> Node3D:
	var color := LIFE_RED if kind == "life" else MANA_BLUE
	var root := Node3D.new()
	root.name = "PotionFx"
	actor.add_child(root)
	var mat := _mat("ring", RING_SHADER, {"color": color, "alpha": 1.0, "thickness": 0.12, "energy": 2.2})
	var ring := _plane(1.3, mat)
	ring.position = Vector3(0, 0.1, 0)
	root.add_child(ring)
	var sp := _sparkles(color.lightened(0.3), 18, 0.45, 2.0, 0.9)
	sp.position = Vector3(0, 0.3, 0)
	root.add_child(sp)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(ring, "position:y", 1.7, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3(0.55, 1, 0.55), 0.7)
	tw.tween_property(mat, "shader_parameter/alpha", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_interval(0.4)
	tw.chain().tween_callback(root.queue_free)
	return root


## Two dust puffs where a dodge roll starts. Added to `parent` (the World's dynamic root or the
## player's parent) at a fixed world position so it stays behind.
static func dodge_dust(parent: Node, pos: Vector3, dir: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in 2:
		var mat := _mat("disc", DISC_SHADER, {"color": DUST, "alpha": 0.55 - i * 0.15})
		var disc := _plane(1.0, mat)
		parent.add_child(disc)
		disc.global_position = pos + Vector3(0, 0.05 + i * 0.02, 0) - dir * (0.3 + i * 0.4)
		disc.scale = Vector3(0.5, 1, 0.5)
		var tw := disc.create_tween().set_parallel(true)
		tw.tween_property(disc, "scale", Vector3(1.9 - i * 0.4, 1, 1.9 - i * 0.4), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "shader_parameter/alpha", 0.0, 0.55)
		tw.chain().tween_callback(disc.queue_free)


## The swirling portal forming beside the caster (front right, so it never hides the character
## from the camera) during the Town Portal cast, over a shrinking ground ring. The caller frees it
## (cancel) or calls portal_burst() on completion.
static func portal_cast(actor: Node3D, cast_time: float) -> Node3D:
	var root := Node3D.new()
	root.name = "PortalCastFx"
	actor.add_child(root)
	var mat := _mat("swirl", SWIRL_SHADER, {"color": PORTAL_BLUE, "grow": 0.05, "alpha": 1.0})
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "Swirl"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(-1.15, 1.3, 0.55)   # the character's right hand side (models face +Z)
	root.add_child(mi)
	var ring_mat := _mat("ring", RING_SHADER, {"color": PORTAL_BLUE, "alpha": 0.9, "thickness": 0.08, "energy": 1.8})
	var ring := _plane(1.0, ring_mat)
	ring.name = "GroundRing"
	ring.position = Vector3(0, 0.05, 0)
	ring.scale = Vector3(2.4, 1, 2.4)
	root.add_child(ring)
	var sp := _sparkles(PORTAL_BLUE.lightened(0.35), 16, 0.5, 1.4, 1.0)
	sp.position = mi.position + Vector3(0, -0.9, 0)
	root.add_child(sp)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(mat, "shader_parameter/grow", 1.0, cast_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3(1.0, 1, 1.0), cast_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return root


## Completion flash of the portal cast effect; frees it.
static func portal_burst(fx: Node3D) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	var swirl := fx.get_node_or_null("Swirl") as MeshInstance3D
	var tw := fx.create_tween().set_parallel(true)
	if swirl != null and swirl.material_override is ShaderMaterial:
		var m := swirl.material_override as ShaderMaterial
		tw.tween_property(m, "shader_parameter/grow", 1.4, 0.25)
		tw.tween_property(m, "shader_parameter/alpha", 0.0, 0.25)
	var ring := fx.get_node_or_null("GroundRing") as MeshInstance3D
	if ring != null and ring.material_override is ShaderMaterial:
		tw.tween_property(ring.material_override, "shader_parameter/alpha", 0.0, 0.25)
	tw.chain().tween_callback(fx.queue_free)


## The parry stance: a golden guard disc in front of the chest and a ring at the feet, fading in
## fast (and out over `duration` when it is > 0). With duration <= 0 it stays (a gentle pulse)
## until the caller frees it (the guard is held).
static func parry_guard(actor: Node3D, duration: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ParryGuardFx"
	actor.add_child(root)
	var mat := _mat("guard", GUARD_SHADER, {"color": GOLD, "alpha": 0.0})
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var disc := MeshInstance3D.new()
	disc.name = "Guard"
	disc.mesh = quad
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0, 1.1, 0.65)   # in front of the chest (models face +Z)
	root.add_child(disc)
	var ring_mat := _mat("ring", RING_SHADER, {"color": GOLD, "alpha": 0.8, "thickness": 0.06, "energy": 1.6})
	var ring := _plane(1.6, ring_mat)
	ring.position = Vector3(0, 0.05, 0)
	root.add_child(ring)
	var tw := root.create_tween()
	tw.tween_property(mat, "shader_parameter/alpha", 1.0, 0.06)
	if duration <= 0.0:
		# Held: settle to a steady glow that breathes a little.
		tw.tween_property(mat, "shader_parameter/alpha", 0.6, 0.25)
		var pulse := root.create_tween().set_loops()
		pulse.tween_interval(0.31)
		pulse.tween_property(ring_mat, "shader_parameter/alpha", 0.45, 0.5).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(ring_mat, "shader_parameter/alpha", 0.8, 0.5).set_trans(Tween.TRANS_SINE)
		return root
	tw.tween_property(mat, "shader_parameter/alpha", 0.35, maxf(0.05, duration - 0.06)).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ring_mat, "shader_parameter/alpha", 0.0, maxf(0.05, duration - 0.06))
	tw.tween_callback(root.queue_free)
	return root


## A successful parry: a bright flash where the blow was caught, golden sparks, an expanding
## ring and a short warm light. Parented to `actor`; frees itself.
static func parry_burst(actor: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ParryBurstFx"
	actor.add_child(root)
	var mat := _mat("guard", GUARD_SHADER, {"color": GOLD.lightened(0.2), "alpha": 1.6})
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0, 1.1, 0.65)
	root.add_child(disc)
	var ring_mat := _mat("ring", RING_SHADER, {"color": GOLD, "alpha": 1.0, "thickness": 0.05, "energy": 2.6})
	var ring := _plane(1.0, ring_mat)
	ring.position = Vector3(0, 0.05, 0)
	ring.scale = Vector3(0.8, 1, 0.8)
	root.add_child(ring)
	var sp := _sparkles(GOLD.lightened(0.3), 28, 0.35, 3.6, 0.6)
	sp.position = Vector3(0, 1.0, 0.7)
	root.add_child(sp)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 3.5
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.3, 0.8)
	root.add_child(light)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(disc, "scale", Vector3(1.8, 1.8, 1.8), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/alpha", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, "scale", Vector3(9.0, 1, 9.0), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "shader_parameter/alpha", 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_property(light, "light_energy", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_interval(0.35)
	tw.chain().tween_callback(root.queue_free)
	return root


## While the player holds a parry charge: a slowly turning golden ring at the feet and a thin
## stream of rising sparks. The caller frees it when the charge is used.
static func charge_aura(actor: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ParryChargeFx"
	actor.add_child(root)
	var ring_mat := _mat("ring", RING_SHADER, {"color": GOLD, "alpha": 0.75, "thickness": 0.05, "energy": 1.7})
	var ring := _plane(1.35, ring_mat)
	ring.position = Vector3(0, 0.05, 0)
	root.add_child(ring)
	var sp := _sparkles(GOLD.lightened(0.25), 10, 0.45, 1.6, 1.0)
	sp.one_shot = false
	sp.explosiveness = 0.0
	sp.position = Vector3(0, 0.15, 0)
	root.add_child(sp)
	var tw := root.create_tween().set_loops()
	tw.tween_property(ring_mat, "shader_parameter/alpha", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring_mat, "shader_parameter/alpha", 0.8, 0.6).set_trans(Tween.TRANS_SINE)
	return root

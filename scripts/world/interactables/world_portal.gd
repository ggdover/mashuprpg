class_name WorldPortal
extends WorldInteractable
## A standing portal (env_portal ring + animated swirl, sparks and a light). Destinations:
##   "town"   -> Events.area_change_requested("town", {"keep_dungeon": true})  (from a dungeon)
##   "next"   -> ("dungeon", {"depth": target_depth})       "Descend to Depth N"
##   "return" -> ("dungeon_return", {})                     "Return to Depth N"
##   "dungeon"-> ("dungeon", {"depth": target_depth})       (generic, e.g. debug)
## Interaction happens inside the player's physics step: it only emits the event (the game flow
## defers the actual change). OWNER: world.

const SWIRL_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color_a : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.8, 0.95, 1.0, 1.0);
uniform float intensity = 1.4;
uniform float speed = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float s1 = sin(a * 3.0 + r * 10.0 - TIME * 3.2 * speed) * 0.5 + 0.5;
	float s2 = sin(a * 5.0 - r * 16.0 + TIME * 2.3 * speed) * 0.5 + 0.5;
	float edge = 1.0 - smoothstep(0.78, 1.0, r);
	float rim = smoothstep(0.55, 0.95, r) * edge;
	float core = 1.0 - smoothstep(0.0, 0.6, r);
	vec3 c = mix(color_a.rgb, color_b.rgb, s1 * s2 + core * 0.6);
	float k = edge * (0.25 + 0.55 * s1 * (0.6 + 0.4 * s2)) + rim * 0.6 + core * 0.35;
	ALBEDO = c * k * intensity;
}
"""

const COLORS := {
	"town": [Color(0.2, 0.5, 1.0), Color(0.75, 0.92, 1.0)],
	"next": [Color(1.0, 0.32, 0.08), Color(1.0, 0.82, 0.35)],
	"dungeon": [Color(1.0, 0.32, 0.08), Color(1.0, 0.82, 0.35)],
	"return": [Color(0.15, 0.9, 0.55), Color(0.8, 1.0, 0.85)],
}

static var _swirl_shader: Shader = null

var destination := "town"
var target_depth := 0
var swirl: MeshInstance3D = null
var swirl_material: ShaderMaterial = null
var particles: GPUParticles3D = null
var _cooldown := 0.0
var _time := 0.0


func _init() -> void:
	super._init()
	marker_kind = "portal"
	always_show_label = true
	label_height = 3.4


## destination "town" | "next" | "return" | "dungeon"; depth = the depth it leads to (for
## "next"/"dungeon"/"return").
func setup(p_destination: String, p_depth: int = 0) -> WorldPortal:
	destination = p_destination
	target_depth = p_depth
	match destination:
		"town":
			display_name = "Town"
		"next":
			display_name = "Descend to Depth %d" % target_depth
		"return":
			display_name = "Return to Depth %d" % target_depth
		_:
			display_name = "Depth %d" % target_depth
	return self


func get_hover_color() -> Color:
	var cols: Array = COLORS.get(destination, COLORS["town"])
	return (cols[1] as Color).lerp(Color.WHITE, 0.2)


func get_interact_range() -> float:
	return 2.2


func _build() -> void:
	model = Assets.model("env_portal")
	model.name = "Model"
	var opening_center := Vector3(0, 1.45, 0)
	var opening_size := Vector2(1.7, 2.3)
	if WorldInteractable.is_placeholder(model):
		model.free()
		model = _fallback_model()
	else:
		var box := WorldInteractable.model_aabb(model)
		if box.size.x > 0.3 and box.size.y > 0.3:
			opening_center = box.get_center()
			opening_size = Vector2(box.size.x * 0.74, box.size.y * 0.8)
			label_height = box.end.y + 0.6
	add_child(model)
	var cols: Array = COLORS.get(destination, COLORS["town"])
	# Swirl disc filling the ring opening, facing +Z (towards the camera).
	if _swirl_shader == null:
		_swirl_shader = Shader.new()
		_swirl_shader.code = SWIRL_SHADER_CODE
	swirl_material = ShaderMaterial.new()
	swirl_material.shader = _swirl_shader
	swirl_material.set_shader_parameter("color_a", cols[0])
	swirl_material.set_shader_parameter("color_b", cols[1])
	var quad := QuadMesh.new()
	quad.size = opening_size
	swirl = MeshInstance3D.new()
	swirl.name = "Swirl"
	swirl.mesh = quad
	swirl.material_override = swirl_material
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	swirl.position = opening_center
	add_child(swirl)
	particles = _make_particles(cols[1], opening_center, opening_size)
	add_child(particles)
	add_light(cols[0].lerp(cols[1], 0.3), 1.8, 7.0, opening_center + Vector3(0, 0, 0.9))
	# Pick shape over the whole ring.
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(opening_size.x * 1.3, 1.6), opening_center.y + opening_size.y * 0.6, 1.0)
	add_pick_shape(shape, Vector3(0, shape.size.y * 0.5, 0))


func _fallback_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.95
	ring.outer_radius = 1.2
	ring.rings = 24
	ring.ring_segments = 8
	var stone := WorldInteractable.stone_material(Color(0.42, 0.42, 0.46))
	root.add_child(WorldInteractable.mesh_node(ring, stone, Vector3(0, 1.45, 0), Vector3(PI * 0.5, 0, 0)))
	var base := BoxMesh.new()
	base.size = Vector3(1.6, 0.25, 0.7)
	root.add_child(WorldInteractable.mesh_node(base, stone, Vector3(0, 0.125, 0)))
	return root


func _make_particles(color: Color, center: Vector3, opening: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.amount = 20
	p.lifetime = 1.6
	p.local_coords = true
	p.position = center
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = minf(opening.x, opening.y) * 0.5
	pm.emission_ring_inner_radius = minf(opening.x, opening.y) * 0.3
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = color
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _process(delta: float) -> void:
	_time += delta
	if light != null:
		light.light_energy = 1.8 + 0.35 * sin(_time * 2.7) + (0.6 if hovered else 0.0)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


func _on_hover_changed(on: bool) -> void:
	super._on_hover_changed(on)
	if swirl_material != null:
		swirl_material.set_shader_parameter("intensity", 2.0 if on else 1.4)


func interact(_player: Node) -> void:
	if not enabled or _cooldown > 0.0:
		return
	_cooldown = 1.0
	Sfx.play("portal", global_position)
	match destination:
		"town":
			Events.area_change_requested.emit("town", {"keep_dungeon": true})
		"return":
			Events.area_change_requested.emit("dungeon_return", {})
		_:
			Events.area_change_requested.emit("dungeon", {"depth": target_depth})

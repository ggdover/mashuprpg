class_name VfxUtil
extends RefCounted
## Shared building blocks for skill visuals: shaders (additive glow, ground rings / sectors,
## telegraphs, sweeping arcs, fresnel orbs), cached meshes, particle bursts, capped flash lights
## and the spawn helper that puts effects into the live World. OWNER: skills (wave 2).
##
## Conventions: every effect is unshaded; glow effects use additive blending with HDR colours
## (energy > 1 blooms through the World's glow); ground effects sit at GROUND_Y above the floor.
## Meshes and shaders are shared; materials are created per effect (they animate uniforms).

const GROUND_Y := 0.05
## Direction from the ground toward the gameplay camera (pitch 56°, yaw 0): ribbons face it.
const VIEW_DIR := Vector3(0.0, 0.829, 0.559)
const MAX_VFX_LIGHTS := 6
const MAX_PARTICLE_SYSTEMS := 60

static var _shaders: Dictionary = {}
static var _meshes: Dictionary = {}
static var _process_mats: Dictionary = {}
static var _draw_meshes: Dictionary = {}
static var _light_count: int = 0
static var _particle_count: int = 0


# ------------------------------------------------------------------ spawning

## Where effects go: the live World's dynamic root, else the current scene (demos, tests).
static func get_parent_node() -> Node:
	var w: Variant = GameState.world
	if is_instance_valid(w) and (w as Node).is_inside_tree():
		return (w as World).dynamic_root
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


## Add an effect / delivery node to the World (GameState.world.add_dynamic) at a position.
## Returns the node, or frees it and returns null when there is nowhere to put it.
static func spawn(node: Node3D, pos: Vector3) -> Node3D:
	var w: Variant = GameState.world
	if is_instance_valid(w) and (w as Node).is_inside_tree():
		(w as World).add_dynamic(node)
	else:
		var p := get_parent_node()
		if p == null:
			node.free()
			return null
		p.add_child(node)
	node.global_position = pos
	return node


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


# ------------------------------------------------------------------ shaders

const _GROUND_CODE := """
shader_type spatial;
render_mode %s, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;
uniform float radius = 0.85;
uniform float thickness = 0.2;
uniform float softness = 1.0;
uniform float fill = 0.0;
uniform float fill_radius = 1.0;
uniform float half_angle = 3.2;
uniform float swirl = 0.0;
uniform float gaps = 0.0;
uniform float spin = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	if (d > 1.0) { discard; }
	float ang = atan(p.x, p.y);
	if (abs(ang) > half_angle) { discard; }
	float w = max(thickness * 0.5, 0.002);
	float ring = 1.0 - smoothstep(w * (1.0 - softness), w, abs(d - radius));
	float inner = fill * (1.0 - smoothstep(fill_radius - 0.08, fill_radius, d)) * (0.55 + 0.45 * d);
	float g = 1.0;
	if (gaps > 0.0) {
		g = 0.35 + 0.65 * smoothstep(0.1, 0.5, abs(sin(ang * gaps * 0.5 + spin)));
	}
	float sw = 1.0;
	if (swirl > 0.0) {
		sw = 0.6 + 0.4 * sin(ang * 5.0 + d * swirl * 10.0 - spin * 3.0);
	}
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(max(ring * g * sw, inner) * alpha * color.a, 0.0, 1.0);
}
"""

const _TELEGRAPH_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.95, 0.12, 0.06, 1.0);
uniform float progress = 0.0;
uniform float half_angle = 3.2;
uniform int shape = 0;
uniform float alpha = 1.0;
uniform float edge_width = 0.035;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 0.0;
	if (shape == 0) {
		float d = length(p);
		float ang = abs(atan(p.x, p.y));
		if (d > 1.0 || ang > half_angle) { discard; }
		float edge = smoothstep(1.0 - edge_width * 2.0, 1.0 - edge_width * 0.4, d);
		if (half_angle < 3.1) {
			float side = d * sin(clamp(half_angle - ang, 0.0, 1.57));
			edge = max(edge, 1.0 - smoothstep(edge_width * 0.6, edge_width * 1.6, side));
		}
		float filled = 1.0 - step(progress, d);
		float front = filled * smoothstep(progress - 0.08, progress, d);
		a = 0.16 + filled * (0.2 + 0.08 * d) + front * 0.3 + edge * (0.6 + 0.3 * pulse);
	} else {
		float along = UV.y;
		float side = 1.0 - abs(p.x);
		float edge = 1.0 - smoothstep(edge_width, edge_width * 2.5, side);
		edge = max(edge, 1.0 - smoothstep(0.0, 0.025, min(along, 1.0 - along)));
		float filled = 1.0 - step(progress, along);
		float front = filled * smoothstep(progress - 0.05, progress, along);
		a = 0.16 + filled * 0.22 + front * 0.3 + edge * (0.6 + 0.3 * pulse);
	}
	ALBEDO = color.rgb;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

const _SWEEP_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.5;
uniform float progress = 1.0;
uniform float tail = 0.7;
uniform float alpha = 1.0;

void fragment() {
	float x = UV.x;
	if (x > progress) { discard; }
	float t = clamp(1.0 - (progress - x) / max(tail, 0.01), 0.0, 1.0);
	float r = UV.y;
	float body = smoothstep(0.0, 0.7, r) * (1.0 - smoothstep(0.92, 1.0, r));
	float edge = smoothstep(0.72, 0.9, r) * (1.0 - smoothstep(0.93, 1.0, r));
	float a = t * t * (body * 0.28 + edge * 1.35);
	ALBEDO = mix(color.rgb, vec3(1.0), edge * t * 0.55) * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

const _ORB_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float energy = 2.5;
uniform float alpha = 1.0;
uniform float core = 0.6;
uniform float rim = 1.6;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = core * (1.0 - f) + rim * pow(f, 2.0);
	ALBEDO = mix(color.rgb, vec3(1.0), (1.0 - f) * core * 0.35) * energy;
	ALPHA = clamp(glow * alpha * color.a, 0.0, 1.0);
}
"""

const _ADD_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;

void fragment() {
	ALBEDO = color.rgb * COLOR.rgb * energy;
	ALPHA = clamp(color.a * COLOR.a * alpha, 0.0, 1.0);
}
"""

const _SOLID_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_opaque, shadows_disabled;
uniform vec4 color : source_color = vec4(0.9, 0.9, 0.9, 1.0);
uniform float energy = 1.0;
uniform float alpha = 1.0;
uniform float rim = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0);

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float light = 0.55 + 0.45 * clamp(dot(NORMAL, normalize(vec3(0.3, 1.0, 0.4))), 0.0, 1.0);
	ALBEDO = color.rgb * energy * light + rim_color.rgb * rim * f;
	ALPHA = clamp(color.a * alpha, 0.0, 1.0);
}
"""

const _GLASS_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float alpha = 0.5;
uniform float energy = 1.3;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = mix(color.rgb, vec3(1.0), f * 0.6) * energy;
	ALPHA = clamp((0.25 + 0.75 * f) * alpha, 0.0, 1.0);
}
"""


## Flat trail behind a projectile: UV.y = 0 at the head .. 1 at the tail, UV.x across.
const _STREAK_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;

void fragment() {
	float along = 1.0 - UV.y;
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float a = along * along * smoothstep(0.0, 0.8, across);
	float core = smoothstep(0.55, 1.0, across) * along;
	ALBEDO = mix(color.rgb, vec3(1.0), core * 0.5) * energy;
	ALPHA = clamp(a * alpha * color.a, 0.0, 1.0);
}
"""


## Vertical light column (teleport, war cry, level up): bright at the base fading upward, rim-lit.
const _BEAM_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha = 1.0;
varying float h;

void vertex() {
	h = VERTEX.y;
}

void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	float fade = pow(clamp(1.0 - h, 0.0, 1.0), 1.4) * smoothstep(0.0, 0.08, h);
	float a = (0.18 + 0.82 * f * f) * fade;
	ALBEDO = mix(color.rgb, vec3(1.0), 0.25 * fade) * energy;
	ALPHA = clamp(a * alpha * color.a, 0.0, 1.0);
}
"""


static func _shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var code := ""
	match key:
		"ground_add":
			code = _GROUND_CODE % "blend_add"
		"ground_mix":
			code = _GROUND_CODE % "blend_mix"
		"telegraph":
			code = _TELEGRAPH_CODE
		"sweep":
			code = _SWEEP_CODE
		"orb":
			code = _ORB_CODE
		"add":
			code = _ADD_CODE
		"solid":
			code = _SOLID_CODE
		"glass":
			code = _GLASS_CODE
		"streak":
			code = _STREAK_CODE
		"beam":
			code = _BEAM_CODE
	var s := Shader.new()
	s.code = code
	_shaders[key] = s
	return s


## A new ShaderMaterial for one of the shaders above ("ground_add", "ground_mix", "telegraph",
## "sweep", "orb", "add", "solid", "glass", "streak", "beam") with initial uniforms.
static func material(key: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(key)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## Additive glow material for plain meshes (vertex colours multiply the colour).
static func glow_material(color: Color, energy: float = 2.0, alpha: float = 1.0) -> ShaderMaterial:
	return material("add", {"color": color, "energy": energy, "alpha": alpha})


# ------------------------------------------------------------------ meshes (shared)

## Unit ground quad: vertices ±1 on X/Z at y = 0, UV (0,0) at (-1,-1), UV.y grows toward +Z.
static func quad_mesh() -> ArrayMesh:
	if _meshes.has("quad"):
		return _meshes["quad"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	var m := st.commit()
	_meshes["quad"] = m
	return m


## Unit rectangle from z = 0 to z = 1 (x ±1): charge / line telegraphs (scale z by length).
static func strip_mesh() -> ArrayMesh:
	if _meshes.has("strip"):
		return _meshes["strip"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	var m := st.commit()
	_meshes["strip"] = m
	return m


## Flat trail quad lying in the XZ plane from z = 0 (head) back to z = -1 (tail), x ±0.5.
## Scale z by the trail length and x by its width.
static func streak_mesh() -> ArrayMesh:
	if _meshes.has("streak"):
		return _meshes["streak"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, -1)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	var m := st.commit()
	_meshes["streak"] = m
	return m


static func sphere_mesh(rings: int = 8) -> SphereMesh:
	var key := "sphere%d" % rings
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = rings * 2
	s.rings = rings
	_meshes[key] = s
	return s


## Open cylinder of radius 1, height 1 (base at y = 0): light columns.
static func column_mesh() -> ArrayMesh:
	if _meshes.has("column"):
		return _meshes["column"]
	var c := CylinderMesh.new()
	c.top_radius = 1.0
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 16
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var am := ArrayMesh.new()
	var arrays := c.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.5
	arrays[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes["column"] = am
	return am


## A cone pointing up (+Y), radius 1 at the base (y = 0), height 1: spikes, ice shards.
static func spike_mesh() -> ArrayMesh:
	if _meshes.has("spike"):
		return _meshes["spike"]
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 5
	c.rings = 1
	var arrays := c.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.5
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes["spike"] = am
	return am


## Flat arc ribbon in the XZ plane (y = 0) from angle a0 to a1 (radians from +Z toward +X),
## between radii r_in and r_out. UV.x = 0 at a0 .. 1 at a1 (sweep direction), UV.y = 0 inner .. 1
## outer. Not cached (the geometry depends on the arguments).
static func arc_mesh(a0: float, a1: float, r_in: float, r_out: float, segments: int = 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	for i in segments + 1:
		var f := float(i) / float(segments)
		var a := lerpf(a0, a1, f)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var p_in := dir * r_in
		var p_out := dir * r_out
		if i > 0:
			var f0 := float(i - 1) / float(segments)
			_quad(st, prev_in, prev_out, p_out, p_in, Vector2(f0, 0), Vector2(f0, 1), Vector2(f, 1), Vector2(f, 0))
		prev_in = p_in
		prev_out = p_out
	return st.commit()


## A ribbon through `points` facing the camera (VIEW_DIR), `width` wide, vertex alpha from
## `alphas` (same size as points, optional). For beams and trails.
static func ribbon_mesh(points: PackedVector3Array, width: float, alphas: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	if n < 2:
		var empty := ArrayMesh.new()
		return empty
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in n:
		var d: Vector3
		if i == 0:
			d = points[1] - points[0]
		elif i == n - 1:
			d = points[i] - points[i - 1]
		else:
			d = points[i + 1] - points[i - 1]
		var side := d.cross(VIEW_DIR)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * width * 0.5
		lefts.append(points[i] - side)
		rights.append(points[i] + side)
	for i in range(1, n):
		var a0 := alphas[i - 1] if alphas.size() == n else 1.0
		var a1 := alphas[i] if alphas.size() == n else 1.0
		var c0 := Color(1, 1, 1, a0)
		var c1 := Color(1, 1, 1, a1)
		var v0 := float(i - 1) / float(n - 1)
		var v1 := float(i) / float(n - 1)
		st.set_color(c0)
		st.set_uv(Vector2(0, v0))
		st.add_vertex(lefts[i - 1])
		st.set_color(c0)
		st.set_uv(Vector2(1, v0))
		st.add_vertex(rights[i - 1])
		st.set_color(c1)
		st.set_uv(Vector2(1, v1))
		st.add_vertex(rights[i])
		st.set_color(c0)
		st.set_uv(Vector2(0, v0))
		st.add_vertex(lefts[i - 1])
		st.set_color(c1)
		st.set_uv(Vector2(1, v1))
		st.add_vertex(rights[i])
		st.set_color(c1)
		st.set_uv(Vector2(0, v1))
		st.add_vertex(lefts[i])
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for pair in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_normal(Vector3.UP)
		st.set_color(Color.WHITE)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## Jagged lightning polyline from a to b (kinks every ~0.6 m, or `segments` kinks, offsets
## perpendicular to the line).
static func jagged_points(a: Vector3, b: Vector3, amplitude: float = 0.35, segments: int = 0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var d := b - a
	var length := d.length()
	var n := clampi(int(length / 0.6), 2, 40) if segments <= 0 else segments
	var side := d.cross(VIEW_DIR)
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	side = side.normalized()
	for i in n + 1:
		var f := float(i) / float(n)
		var p := a + d * f
		if i > 0 and i < n:
			p += side * randf_range(-amplitude, amplitude) + Vector3.UP * randf_range(-amplitude, amplitude) * 0.5
		pts.append(p)
	return pts


# ------------------------------------------------------------------ nodes

## A MeshInstance3D with a mesh + material (no shadows).
static func mesh_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


## A ground decal quad (ring/disc/sector shader) of `size` metres radius.
static func ground_node(size: float, params: Dictionary, additive: bool = true) -> MeshInstance3D:
	var mi := mesh_node(quad_mesh(), material("ground_add" if additive else "ground_mix", params))
	mi.scale = Vector3(size, 1.0, size)
	mi.position.y = GROUND_Y
	return mi


## Try to take one of the few VFX light slots. Pair with release_light() (VfxLight does it).
static func take_light() -> bool:
	if _light_count >= MAX_VFX_LIGHTS:
		return false
	_light_count += 1
	return true


static func release_light() -> void:
	_light_count = maxi(0, _light_count - 1)


static func light_count() -> int:
	return _light_count


## Short-lived omni light (fades out over `duration`, then frees itself); null when the VFX light
## budget is used up.
static func flash_light(parent: Node3D, color: Color, energy: float, light_range: float, duration: float, offset: Vector3 = Vector3(0, 1.0, 0)) -> OmniLight3D:
	if parent == null or not take_light():
		return null
	var l := preload("res://scripts/vfx/vfx_light.gd").new()
	l.setup(color, energy, light_range, duration)
	l.position = offset
	parent.add_child(l)
	return l


## A persistent light (lives until its parent is freed); null when the budget is used up.
static func steady_light(parent: Node3D, color: Color, energy: float, light_range: float, offset: Vector3 = Vector3.ZERO) -> OmniLight3D:
	if parent == null or not take_light():
		return null
	var l := preload("res://scripts/vfx/vfx_light.gd").new()
	l.setup(color, energy, light_range, 0.0)
	l.position = offset
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ particles

## Particle process material (cached by its arguments). `ramp` (optional Array of Colors) is the
## colour over the particle's life (multiplied with `color`); by default white fading out.
static func _process_material(color: Color, speed: Vector2, gravity: float, spread: float, direction: Vector3, scale: Vector2, emit_radius: float, damping: float, ramp: Array = [], grow: bool = false) -> ParticleProcessMaterial:
	var rkey := ""
	for c in ramp:
		rkey += (c as Color).to_html()
	var key := "%s|%s|%.2f|%.1f|%s|%s|%.2f|%.1f|%s|%s" % [color.to_html(), speed, gravity, spread, direction, scale, emit_radius, damping, rkey, grow]
	if _process_mats.has(key):
		return _process_mats[key]
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = scale.x
	pm.scale_max = scale.y
	pm.damping_min = damping
	pm.damping_max = damping
	if emit_radius > 0.0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = emit_radius
	pm.color = color
	var grad := Gradient.new()
	if ramp.size() >= 2:
		grad.set_color(0, ramp[0])
		grad.set_color(1, ramp[ramp.size() - 1])
		for i in range(1, ramp.size() - 1):
			grad.add_point(float(i) / float(ramp.size() - 1), ramp[i])
	else:
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		grad.add_point(0.6, Color(1, 1, 1, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var curve := Curve.new()
	if grow:
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(0.4, 1.0))
		curve.add_point(Vector2(1, 1.15))
	else:
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, 0.25))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	_process_mats[key] = pm
	return pm


## Billboard quad for particles (additive, vertex colour), cached per energy/size.
static func _draw_mesh(size: float, energy: float, additive: bool) -> QuadMesh:
	var key := "%.2f|%.2f|%s" % [size, energy, additive]
	if _draw_meshes.has(key):
		return _draw_meshes[key]
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(energy, energy, energy, 1.0) if additive else Color.WHITE
	m.albedo_texture = _soft_dot_texture()
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	_draw_meshes[key] = q
	return q


static func _soft_dot_texture() -> Texture2D:
	if _meshes.has("dot_tex"):
		return _meshes["dot_tex"]
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0 - 0.5, size / 2.0 - 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_meshes["dot_tex"] = tex
	return tex


## One-shot particle burst (or a continuous emitter with one_shot = false). Returns the
## GPUParticles3D (added under parent at `offset`), or null if the particle budget is used up.
## opts: amount, lifetime, speed (Vector2), gravity, spread, direction, scale (Vector2), size,
## emit_radius, damping, energy, one_shot, explosiveness, additive, local, ramp (Array of Colors:
## colour over life), grow (particles swell instead of shrinking: smoke, fire puffs).
static func particles(parent: Node3D, color: Color, opts: Dictionary = {}, offset: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	if parent == null or _particle_count >= MAX_PARTICLE_SYSTEMS:
		return null
	var p := GPUParticles3D.new()
	p.amount = int(opts.get("amount", 12))
	p.lifetime = float(opts.get("lifetime", 0.5))
	p.one_shot = bool(opts.get("one_shot", true))
	p.explosiveness = float(opts.get("explosiveness", 0.95 if p.one_shot else 0.0))
	p.randomness = 0.4
	p.local_coords = bool(opts.get("local", false))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = _process_material(color, opts.get("speed", Vector2(2, 5)), float(opts.get("gravity", -6.0)),
		float(opts.get("spread", 180.0)), opts.get("direction", Vector3.UP), opts.get("scale", Vector2(0.6, 1.2)),
		float(opts.get("emit_radius", 0.1)), float(opts.get("damping", 0.0)), opts.get("ramp", []), bool(opts.get("grow", false)))
	p.draw_pass_1 = _draw_mesh(float(opts.get("size", 0.2)), float(opts.get("energy", 2.5)), bool(opts.get("additive", true)))
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 10, 12))
	p.position = offset
	_particle_count += 1
	p.tree_exited.connect(_on_particles_freed, CONNECT_ONE_SHOT)
	parent.add_child(p)
	p.emitting = true
	return p


static func _on_particles_freed() -> void:
	_particle_count = maxi(0, _particle_count - 1)


static func particle_count() -> int:
	return _particle_count

class_name WorldKit
extends RefCounted
## Builds renderable geometry for a World from Assets models: extracts every mesh part of a
## model id (with its transform and imported materials), converts the materials into the world
## shaders (theme tint, per-instance colour variation, optional wall cut-out) on DUPLICATED
## meshes, and emits chunked MultiMeshInstance3Ds. One WorldKit per World build. OWNER: world.
##
## Shared Assets resources are never mutated: meshes are duplicated before their surface
## materials are replaced, and materials are always new ShaderMaterials.

const CHUNK_CELLS := 8
const TILE := 2.0

## World geometry shader. The CUTOUT variant dithers away fragments near the camera -> player
## line that are in front of the player (global uniform player_world_pos, set by the CameraRig),
## so the player stays visible behind walls. Skipped in orthographic (directional shadow) passes.
const WORLD_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#ifdef CUTOUT
global uniform vec3 player_world_pos;
uniform float cut_radius = 1.75;
uniform float cut_max_distance = 8.0;
#endif
uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float use_instance_color = 1.0;
uniform float top_darken = 0.0;
varying vec3 v_tint;
varying float v_up;

void vertex() {
	v_tint = mix(vec3(1.0), COLOR.rgb, use_instance_color);
	v_up = NORMAL.y;
}

#ifdef CUTOUT
float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	float m[16] = {0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0};
	return (m[x + y * 4] + 0.5) / 16.0;
}
#endif

void fragment() {
#ifdef CUTOUT
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 target = player_world_pos + vec3(0.0, 1.0, 0.0);
		vec3 seg = target - cam;
		float seg_len = max(length(seg), 0.001);
		vec3 dir = seg / seg_len;
		float s = dot(wp - cam, dir);
		vec3 closest = cam + dir * clamp(s, 0.0, seg_len);
		float d = distance(wp, closest);
		float r = cut_radius * clamp(s / seg_len, 0.3, 1.0);
		float near_player = length(wp.xz - player_world_pos.xz);
		float fade = 1.0 - smoothstep(r * 0.55, r, d);
		fade *= 1.0 - smoothstep(seg_len - 0.25, seg_len - 0.02, s);
		fade *= 1.0 - smoothstep(cut_max_distance - 2.0, cut_max_distance, near_player);
		if (fade > 0.001 && fade * 1.08 > bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
#endif
	vec3 c = albedo.rgb * v_tint;
	c *= mix(1.0, 1.0 - top_darken, smoothstep(0.6, 0.95, v_up));
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission.rgb * emission_energy;
}
"""

## Flowing lava (unshaded, HDR bright so it blooms).
const LAVA_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 hot : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform vec4 crust : source_color = vec4(0.13, 0.035, 0.02, 1.0);
uniform float energy = 1.9;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// Distance between the two nearest cell points: ~0 on the cracks between crust plates.
float plates(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			o = 0.5 + 0.38 * sin(t + 6.2831 * o);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz * 0.95;
	float e = plates(uv, TIME * 0.35);
	float crack = 1.0 - smoothstep(0.03, 0.2, e);
	float flow = smoothstep(0.55, 0.8, vnoise(uv * 0.7 + vec2(TIME * 0.12, TIME * 0.05)));
	float heat = clamp(crack + flow * 0.8, 0.0, 1.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.6 + wp.x * 0.6 + wp.z * 0.4);
	vec3 molten = mix(hot.rgb, core.rgb, crack * crack) * energy * pulse;
	vec3 plate = crust.rgb * (0.8 + 0.6 * vnoise(uv * 3.0));
	ALBEDO = mix(plate, molten, heat);
}
"""

## Additive radial light pool on the floor (fake light for torches / crystals without an
## OmniLight3D). Colour per instance.
const GLOW_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float intensity = 0.3;
varying vec3 v_col;
void vertex() { v_col = COLOR.rgb; }
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	a = a * a * (3.0 - 2.0 * a);
	ALBEDO = v_col * a * a * intensity;
}
"""

static var _world_shader: Shader = null
static var _cutout_shader: Shader = null
static var _lava_shader: Shader = null
static var _glow_shader: Shader = null

var theme: Dictionary = {}
var _parts_cache: Dictionary = {}   # id -> Array[Dictionary]
var _mat_cache: Dictionary = {}     # key -> Material
var _mesh_cache: Dictionary = {}    # key -> Mesh


func _init(p_theme: Dictionary = {}) -> void:
	theme = p_theme


static func world_shader(cutout: bool) -> Shader:
	if cutout:
		if _cutout_shader == null:
			_cutout_shader = Shader.new()
			_cutout_shader.code = WORLD_SHADER_CODE.replace("shader_type spatial;", "shader_type spatial;\n#define CUTOUT")
		return _cutout_shader
	if _world_shader == null:
		_world_shader = Shader.new()
		_world_shader.code = WORLD_SHADER_CODE
	return _world_shader


static func lava_material() -> ShaderMaterial:
	if _lava_shader == null:
		_lava_shader = Shader.new()
		_lava_shader.code = LAVA_SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _lava_shader
	return m


static func glow_material(intensity: float) -> ShaderMaterial:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("intensity", intensity)
	return m


## A world material with explicit values (placeholder parts, generated meshes).
static func make_material(albedo: Color, cutout: bool = false, roughness: float = 0.85, emission: Color = Color.BLACK, emission_energy: float = 0.0, instanced: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = world_shader(cutout)
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("metallic", 0.0)
	m.set_shader_parameter("emission", emission)
	m.set_shader_parameter("emission_energy", emission_energy)
	m.set_shader_parameter("use_instance_color", 1.0 if instanced else 0.0)
	return m


# ------------------------------------------------------------------ model parts

## Every mesh part of a model: [{"mesh": Mesh, "xform": Transform3D (relative to the model root),
## "mats": Array (active material per surface), "name": String, "placeholder": bool}].
func parts(id: String) -> Array:
	if _parts_cache.has(id):
		return _parts_cache[id]
	var out: Array = []
	if not Assets.has_model(id):
		var fb := WorldFallbacks.parts(id)
		if not fb.is_empty():
			_parts_cache[id] = fb
			return fb
	var inst := Assets.model(id)
	var placeholder: bool = inst.get_meta("placeholder", false)
	var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		meshes.push_front(inst)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != inst:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var mats: Array = []
		for s in mi.mesh.get_surface_count():
			mats.append(mi.get_active_material(s))
		out.append({"mesh": mi.mesh, "xform": xf, "mats": mats, "name": String(mi.name), "placeholder": placeholder})
	inst.free()
	_parts_cache[id] = out
	return out


## Combined AABB of a model in its own space.
func model_aabb(id: String) -> AABB:
	var box := AABB()
	var first := true
	for p in parts(id):
		var mesh: Mesh = p["mesh"]
		var xf: Transform3D = p["xform"]
		var b := xf * mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


## The part's mesh duplicated with converted materials (cached per id/part/tint/mode).
func prepared_mesh(id: String, part_index: int, tint: Color, cutout: bool, instanced: bool = true, params: Dictionary = {}) -> Mesh:
	var key := "%s|%d|%s|%s|%s|%s" % [id, part_index, tint.to_html(), cutout, instanced, params]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var p: Dictionary = parts(id)[part_index]
	var src_mesh: Mesh = p["mesh"]
	var mesh: Mesh = src_mesh.duplicate()
	var mats: Array = p["mats"]
	var any_tint_named := _model_has_tint_materials(id)
	for s in mesh.get_surface_count():
		var src: Material = mats[s] if s < mats.size() else null
		mesh.surface_set_material(s, convert_material(id, src, tint, any_tint_named, cutout, instanced, p["placeholder"], params))
	_mesh_cache[key] = mesh
	return mesh


func _model_has_tint_materials(id: String) -> bool:
	for p in parts(id):
		for m in p["mats"]:
			if m != null and (m as Material).resource_name.begins_with("tint"):
				return true
	return false


## Convert an imported material to a world ShaderMaterial copying its albedo / roughness /
## metallic / emission. Tintable surfaces (tint_* names, or every surface if the model has none)
## are multiplied by `tint`.
## params: extra shader parameters ("top_darken": float, "emission_color": Color replaces the
## emission colour of emissive surfaces).
func convert_material(id: String, src: Material, tint: Color, any_tint_named: bool, cutout: bool, instanced: bool, placeholder: bool, params: Dictionary = {}) -> Material:
	var key := "%s|%d|%s|%s|%s|%s|%s" % [id, src.get_instance_id() if src else 0, tint.to_html(), cutout, instanced, placeholder, params]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var albedo := Color(0.7, 0.7, 0.7)
	var roughness := 0.85
	var metallic := 0.0
	var emission := Color.BLACK
	var emission_energy := 0.0
	var tintable := true
	if placeholder:
		albedo = WorldThemes.PLACEHOLDER_COLORS.get(id, Color(0.7, 0.7, 0.7))
		if id in WorldThemes.PLACEHOLDER_EMISSIVE:
			emission = albedo
			emission_energy = 2.0
			tintable = false
	elif src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		albedo = bm.albedo_color
		roughness = bm.roughness
		metallic = bm.metallic
		if bm.emission_enabled:
			emission = bm.emission
			emission_energy = bm.emission_energy_multiplier
		tintable = (not any_tint_named) or bm.resource_name.begins_with("tint")
		if emission_energy > 0.0 and emission.get_luminance() > 0.01:
			tintable = tintable and any_tint_named
	if tintable:
		albedo = Color(albedo.r * tint.r, albedo.g * tint.g, albedo.b * tint.b, albedo.a)
	if params.has("emission_color") and emission_energy > 0.0:
		var ec: Color = params["emission_color"]
		emission = ec
		albedo = Color(albedo.r * 0.5 + ec.r * 0.5, albedo.g * 0.5 + ec.g * 0.5, albedo.b * 0.5 + ec.b * 0.5, albedo.a)
	var m := make_material(albedo, cutout, roughness, emission, emission_energy, instanced)
	m.set_shader_parameter("metallic", metallic)
	if params.has("top_darken"):
		m.set_shader_parameter("top_darken", float(params["top_darken"]))
	_mat_cache[key] = m
	return m


# ------------------------------------------------------------------ builders

## Add MultiMeshInstance3Ds for every part of `id` at the given transforms, grouped in spatial
## chunks for frustum culling. colors: per-instance colour (variation), or empty for white.
## Returns the number of MultiMeshInstance3Ds created.
func add_multimesh(parent: Node3D, id: String, xforms: Array, colors: Array, tint: Color, cutout: bool, shadows: bool, params: Dictionary = {}) -> int:
	if xforms.is_empty():
		return 0
	var chunks: Dictionary = {}   # Vector2i -> Array[int]
	var chunk_size := CHUNK_CELLS * TILE
	for k in xforms.size():
		var xf: Transform3D = xforms[k]
		var key := Vector2i(floori(xf.origin.x / chunk_size), floori(xf.origin.z / chunk_size))
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append(k)
	var created := 0
	var part_list := parts(id)
	for pi in part_list.size():
		var p: Dictionary = part_list[pi]
		var mesh := prepared_mesh(id, pi, tint, cutout, true, params)
		var pxf: Transform3D = p["xform"]
		for key in chunks:
			var idxs: Array = chunks[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = idxs.size()
			for n in idxs.size():
				var k2: int = idxs[n]
				var xf2: Transform3D = xforms[k2]
				mm.set_instance_transform(n, xf2 * pxf)
				mm.set_instance_color(n, colors[k2] if k2 < colors.size() else Color.WHITE)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d_%d" % [id, pi, key.x, key.y]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
			created += 1
	return created

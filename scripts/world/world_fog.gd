extends MeshInstance3D
## Fog of war: one full-screen pass drawn over the 3D scene (after everything else, below the 2D
## HUD). It rebuilds each pixel's floor position from the depth buffer and darkens it:
##   - ground farther than CLEAR_RADIUS from the player fades to a darker shade (full at DIM_RADIUS),
##   - ground never explored (World grid "explored" cells, the minimap's data) is nearly black, with
##     slowly drifting murk and ragged edges, so what is there can't be told.
## The explored mask is uploaded as an R8 texture whenever World.grid.explored changes (throttled).
## Child of the World (added by World._setup_fog). OWNER: world.
## Internal helper: `const WorldFog := preload("res://scripts/world/world_fog.gd")`.

const CLEAR_RADIUS := 14.0
const DIM_RADIUS := 27.0
## Fastest re-upload of the explored mask (seconds).
const UPLOAD_INTERVAL := 0.1

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

global uniform vec3 player_world_pos;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D explored_tex : filter_linear, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_world_size = vec2(32.0);
uniform vec3 fog_color : source_color = vec3(0.02, 0.025, 0.035);
uniform float clear_radius = 14.0;
uniform float dim_radius = 27.0;
uniform float far_dim = 0.45;
uniform float unexplored_dim = 1.0;
uniform float use_explored = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 wp = world.xyz / world.w;
	// Farther from the player: darker.
	float d = length(wp.xz - player_world_pos.xz);
	float dim = far_dim * smoothstep(clear_radius, dim_radius, d);
	// Never explored: nearly black, ragged edges, drifting murk.
	float murk = vnoise(wp.xz * 0.11 + vec2(TIME * 0.03, -TIME * 0.02)) * 0.6 + vnoise(wp.xz * 0.33 - vec2(TIME * 0.05)) * 0.4;
	float unex = 0.0;
	if (use_explored > 0.5) {
		vec2 wob = (vec2(vnoise(wp.xz * 0.4 + 3.1), vnoise(wp.xz * 0.4 + 17.3)) - 0.5) * 2.6;
		vec2 uv = (wp.xz + wob - grid_origin) / grid_world_size;
		float ex = 0.0;
		if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
			ex = clamp(texture(explored_tex, uv).r * 255.0, 0.0, 1.0);
		}
		unex = 1.0 - smoothstep(0.2, 0.8, ex);
	}
	// Unexplored ground is fully covered (nothing shows through, not even lamps); the murk only
	// moves in its colour.
	float a = max(dim, unex * unexplored_dim);
	ALBEDO = fog_color * (1.0 + 0.9 * murk * unex);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _shader: Shader = null

var world: World = null
var _mat: ShaderMaterial = null
var _tex: ImageTexture = null
var _version := -1
var _since_upload := 0.0


## Set up for `w` (after its grid is built). params: "far_dim", "unexplored_dim", "fog_color",
## "use_explored" (false: only the distance shade, e.g. towns).
func setup(w: World, params: Dictionary = {}) -> void:
	world = w
	name = "FogOfWar"
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.render_priority = Material.RENDER_PRIORITY_MAX
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mesh = quad
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	ignore_occlusion_culling = true
	_mat.set_shader_parameter("clear_radius", CLEAR_RADIUS)
	_mat.set_shader_parameter("dim_radius", DIM_RADIUS)
	_mat.set_shader_parameter("far_dim", float(params.get("far_dim", 0.45)))
	_mat.set_shader_parameter("unexplored_dim", float(params.get("unexplored_dim", 1.0)))
	_mat.set_shader_parameter("fog_color", params.get("fog_color", Color(0.02, 0.025, 0.035)))
	_mat.set_shader_parameter("use_explored", 1.0 if bool(params.get("use_explored", true)) else 0.0)
	var g := w.grid
	if g != null and g.size.x > 0:
		_mat.set_shader_parameter("grid_origin", Vector2(g.origin.x, g.origin.z))
		_mat.set_shader_parameter("grid_world_size", Vector2(g.size.x, g.size.y) * WorldGrid.TILE)
	_upload()


func _process(delta: float) -> void:
	_since_upload += delta
	if world == null or not is_instance_valid(world) or world.grid == null:
		return
	# Only with a player in this world (map previews and shot tools have none).
	var p := GameState.player
	visible = World.fog_of_war_enabled and p != null and is_instance_valid(p) and world.is_ancestor_of(p)
	if world.grid.explored_version != _version and _since_upload >= UPLOAD_INTERVAL:
		_upload()


## The explored cells as an R8 texture (values 0 / 1; the shader scales them by 255).
func _upload() -> void:
	_since_upload = 0.0
	var g := world.grid if world != null else null
	if g == null or g.size.x <= 0 or g.explored.size() != g.size.x * g.size.y:
		return
	_version = g.explored_version
	var img := Image.create_from_data(g.size.x, g.size.y, false, Image.FORMAT_R8, g.explored)
	if _tex != null and _tex.get_width() == g.size.x and _tex.get_height() == g.size.y:
		_tex.update(img)
	else:
		_tex = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter("explored_tex", _tex)


## Share of the view the fog can darken, for tests: the current parameters.
func get_params() -> Dictionary:
	return {"far_dim": float(_mat.get_shader_parameter("far_dim")), "unexplored_dim": float(_mat.get_shader_parameter("unexplored_dim")),
		"use_explored": float(_mat.get_shader_parameter("use_explored")) > 0.5, "version": _version}

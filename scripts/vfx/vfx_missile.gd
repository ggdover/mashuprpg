class_name VfxMissile
extends Node3D
## The visual of one flying projectile (arrow / bolt / ice spear / meteor model or a glowing
## orb), with a camera-facing ribbon trail built from its recent positions, a particle trail for
## orbs and an optional light. The owner (SkillProjectile, a falling meteor...) moves this node's
## parent and calls face(dir) when the heading changes; fizzle() hides it and lets the trail fade
## (returns the linger time before the owner may free it). OWNER: skills (wave 2).
##
## vfx keys (SkillDB "vfx"): color, model, orb (bool), scale, trail (bool), glow (bool),
## light (bool).

## proj_* models are scaled up a little so arrows / bolts read from the high gameplay camera.
const MODEL_SCALE := 1.3
const MAX_TRAIL_POINTS := 16

## Heading node: looks along the flight direction (+Z forward, like the proj_* models).
var heading: Node3D = null
var color: Color = Color.WHITE
var _trail_mi: MeshInstance3D = null
var _trail_mat: ShaderMaterial = null
## [Vector3 global position, float time]
var _trail_pts: Array = []
var _trail_time := 0.14
var _trail_width := 0.2
var _particles: GPUParticles3D = null
var _light: OmniLight3D = null
var _orb_mats: Array = []
var _time := 0.0
var _flicker := false
var _fizzled := false


## Build the visual. `model_id` "" (or a missing model) gives a glowing orb.
static func build(vfx: Dictionary, model_id: String = "", size_scale: float = 1.0) -> VfxMissile:
	var m := VfxMissile.new()
	m.name = "Missile"
	m._build(vfx, model_id, size_scale)
	return m


func _build(vfx: Dictionary, model_id: String, size_scale: float) -> void:
	color = vfx.get("color", Color.WHITE)
	var s := float(vfx.get("scale", 1.0)) * size_scale
	heading = Node3D.new()
	heading.name = "Heading"
	add_child(heading)
	var use_orb := bool(vfx.get("orb", false)) or model_id == "" or not Assets.has_model(model_id)
	if use_orb:
		_build_orb(s)
	else:
		var model := Assets.model(model_id)
		model.scale = Vector3.ONE * s * MODEL_SCALE
		_no_shadows(model)
		heading.add_child(model)
		if bool(vfx.get("glow", false)):
			var gm := VfxUtil.material("orb", {"color": color, "energy": 2.2, "core": 0.25, "rim": 1.4, "alpha": 0.8})
			var g := VfxUtil.mesh_node(VfxUtil.sphere_mesh(6), gm)
			g.scale = Vector3(0.24, 0.24, 0.6) * s
			heading.add_child(g)
			_orb_mats.append(gm)
	if bool(vfx.get("trail", true)):
		_trail_time = 0.16 if use_orb else 0.11
		_trail_width = (0.5 if use_orb else 0.16) * s
		_trail_mat = VfxUtil.material("streak", {"color": color, "energy": 2.4 if use_orb else 2.0, "alpha": 1.0})
		_trail_mi = VfxUtil.mesh_node(ArrayMesh.new(), _trail_mat)
		_trail_mi.top_level = true
		add_child(_trail_mi)
	if bool(vfx.get("light", false)):
		_light = VfxUtil.steady_light(self, color, 2.2, 5.5 * clampf(s, 0.6, 2.0))


func _build_orb(s: float) -> void:
	var core_mat := VfxUtil.material("orb", {"color": color.lerp(Color.WHITE, 0.35), "energy": 3.0, "core": 1.0, "rim": 1.0})
	var core := VfxUtil.mesh_node(VfxUtil.sphere_mesh(), core_mat)
	core.scale = Vector3.ONE * 0.2 * s
	heading.add_child(core)
	var halo_mat := VfxUtil.material("orb", {"color": color, "energy": 2.0, "core": 0.35, "rim": 1.5, "alpha": 0.75})
	var halo := VfxUtil.mesh_node(VfxUtil.sphere_mesh(), halo_mat)
	halo.scale = Vector3.ONE * 0.38 * s
	heading.add_child(halo)
	_orb_mats.append(core_mat)
	_orb_mats.append(halo_mat)
	_flicker = true
	_particles = VfxUtil.particles(self, Color.WHITE, {"amount": int(40 * clampf(s, 0.5, 1.5)), "lifetime": 0.35, "speed": Vector2(0.3, 1.1),
		"gravity": 1.5 if color.r > color.b else -0.5, "spread": 180.0, "size": 0.14 * s, "emit_radius": 0.16 * s,
		"one_shot": false, "energy": 2.0, "damping": 1.5, "ramp": VfxSpawn.hot_ramp(color)})


func _process(delta: float) -> void:
	_time += delta
	if _flicker and not _orb_mats.is_empty() and not _fizzled:
		var f := 0.9 + 0.1 * sin(_time * 37.0) + 0.05 * sin(_time * 91.0)
		heading.scale = Vector3.ONE * f
	if _trail_mi != null:
		_update_trail()


func _update_trail() -> void:
	if not is_inside_tree():
		return
	var now := _time
	if not _fizzled:
		var p := heading.global_position
		if _trail_pts.is_empty() or (_trail_pts[_trail_pts.size() - 1][0] as Vector3).distance_squared_to(p) > 0.0004:
			_trail_pts.append([p, now])
	while not _trail_pts.is_empty() and now - float(_trail_pts[0][1]) > _trail_time:
		_trail_pts.pop_front()
	while _trail_pts.size() > MAX_TRAIL_POINTS:
		_trail_pts.pop_front()
	var n := _trail_pts.size()
	if n < 2:
		_trail_mi.visible = false
		return
	_trail_mi.visible = true
	_trail_mi.global_transform = Transform3D.IDENTITY
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * 2)
	uvs.resize(n * 2)
	for i in n:
		var pt: Vector3 = _trail_pts[i][0]
		var d: Vector3
		if i == 0:
			d = (_trail_pts[1][0] as Vector3) - pt
		elif i == n - 1:
			d = pt - (_trail_pts[i - 1][0] as Vector3)
		else:
			d = (_trail_pts[i + 1][0] as Vector3) - (_trail_pts[i - 1][0] as Vector3)
		var side := d.cross(VfxUtil.VIEW_DIR)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		# f: 0 at the tail .. 1 at the head (age based, so the trail shrinks smoothly).
		var f := clampf(1.0 - (now - float(_trail_pts[i][1])) / _trail_time, 0.0, 1.0)
		side = side.normalized() * _trail_width * (0.25 + 0.75 * f) * 0.5
		verts[i * 2] = pt - side
		verts[i * 2 + 1] = pt + side
		uvs[i * 2] = Vector2(0.0, 1.0 - f)
		uvs[i * 2 + 1] = Vector2(1.0, 1.0 - f)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var am := _trail_mi.mesh as ArrayMesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)


## Turn the visual to fly along `dir` (any 3D direction).
func face(dir: Vector3) -> void:
	if heading == null or dir.length_squared() < 0.000001:
		return
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
	heading.basis = Basis.looking_at(d, up, true)


## Hide the missile and stop the trail. Returns how long the owner should keep this node alive so
## the trail can fade (0 when there is nothing to fade).
func fizzle() -> float:
	_fizzled = true
	var linger := 0.0
	if heading != null:
		heading.visible = false
	if _light != null and is_instance_valid(_light):
		(_light as VfxLight).fade_out(0.15)
		_light = null
	if _particles != null and is_instance_valid(_particles):
		_particles.emitting = false
		linger = _particles.lifetime
	if _trail_mi != null:
		linger = maxf(linger, _trail_time)
	return linger


static func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)

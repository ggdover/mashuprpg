class_name VfxTelegraph
extends RefCounted
## Red ground telegraphs for monster wind-ups: translucent discs / cones / lines with a bright
## edge that fill up (centre -> edge, or along the line) over `fill_time`, flash when full and
## fade. Each returns the VfxEffect (or null without a place to spawn it); call
## `effect.end_now()` to fade one out early (the caster was interrupted). OWNER: skills (wave 2).
##
##   VfxTelegraph.disc(pos, 3.5, 0.9)
##   VfxTelegraph.cone(caster_pos, dir, 6.0, 90.0, 1.2)
##   VfxTelegraph.line(caster_pos, dir, 12.0, 1.6, 0.7)

const COLOR := Color(0.95, 0.12, 0.06, 0.85)
## How long the full telegraph flashes and fades after filling.
const TAIL := 0.22


static func disc(pos: Vector3, radius: float, fill_time: float, color: Color = COLOR) -> VfxEffect:
	return _make(pos, Vector3.BACK, radius, 360.0, fill_time, color, 0)


## Cone from `pos` toward `dir`, `angle_deg` wide in total.
static func cone(pos: Vector3, dir: Vector3, radius: float, angle_deg: float, fill_time: float, color: Color = COLOR) -> VfxEffect:
	return _make(pos, dir, radius, angle_deg, fill_time, color, 0)


## Rectangle from `pos` along `dir`, `length` long and `width` wide (fills from pos outward).
static func line(pos: Vector3, dir: Vector3, length: float, width: float, fill_time: float, color: Color = COLOR) -> VfxEffect:
	var e := VfxEffect.new()
	e.life = maxf(0.05, fill_time) + TAIL
	if VfxUtil.spawn(e, VfxUtil.flat(pos)) == null:
		return null
	e.rotation.y = VfxUtil.yaw_of(dir)
	var mat := VfxUtil.material("telegraph", {"color": color, "progress": 0.0, "shape": 1, "edge_width": clampf(0.09 / maxf(width, 0.3), 0.02, 0.2)})
	var mi := VfxUtil.mesh_node(VfxUtil.strip_mesh(), mat)
	mi.scale = Vector3(width * 0.5, 1.0, maxf(0.1, length))
	mi.position.y = VfxUtil.GROUND_Y + 0.01
	e.add_child(mi)
	_animate(e, mat, fill_time)
	return e


static func _make(pos: Vector3, dir: Vector3, radius: float, angle_deg: float, fill_time: float, color: Color, shape: int) -> VfxEffect:
	var e := VfxEffect.new()
	e.life = maxf(0.05, fill_time) + TAIL
	if VfxUtil.spawn(e, VfxUtil.flat(pos)) == null:
		return null
	e.rotation.y = VfxUtil.yaw_of(dir)
	var half := deg_to_rad(clampf(angle_deg, 5.0, 360.0)) * 0.5
	if angle_deg >= 359.0:
		half = 3.2
	var mat := VfxUtil.material("telegraph", {"color": color, "progress": 0.0, "shape": shape, "half_angle": half,
		"edge_width": clampf(0.08 / maxf(radius, 0.5), 0.012, 0.08)})
	var mi := VfxUtil.mesh_node(VfxUtil.quad_mesh(), mat)
	mi.scale = Vector3(radius, 1.0, radius)
	mi.position.y = VfxUtil.GROUND_Y + 0.01
	e.add_child(mi)
	_animate(e, mat, fill_time)
	return e


static func _animate(e: VfxEffect, mat: ShaderMaterial, fill_time: float) -> void:
	var ft := maxf(0.05, fill_time)
	e.updater = func(_t: float, age: float) -> void:
		var p := clampf(age / ft, 0.0, 1.0)
		mat.set_shader_parameter("progress", p * 1.02)
		mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(age * 18.0))
		var a := clampf(age / 0.12, 0.0, 1.0)
		if age > ft:
			var k := clampf((age - ft) / TAIL, 0.0, 1.0)
			a = (1.0 + 0.6 * (1.0 - k)) * (1.0 - k)
		mat.set_shader_parameter("alpha", a)

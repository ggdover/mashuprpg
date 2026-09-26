class_name VfxSpawn
extends RefCounted
## Library of skill effects (static constructors). Each returns the VfxEffect it spawned into the
## World (GameState.world.add_dynamic, see VfxUtil.spawn) or null when there is no place to put
## it. Effects free themselves. Colours: pass UIStyle.DAMAGE_COLORS / SkillDB colours; the
## functions add HDR energy themselves. OWNER: skills (wave 2).
##
##   VfxSpawn.explosion(pos, 2.2, SkillDB.C_FIRE)
##   VfxSpawn.swing(caster_pos, dir, 2.5, 80.0, color, "slash")
##   VfxSpawn.hit_spark(target.get_aim_point(), color, is_crit)
##   VfxSpawn.nova(pos, 4.5, SkillDB.C_COLD, 0.3, "frost")
##   VfxSpawn.beam([a, b, c], SkillDB.C_LIGHT)
##   VfxSpawn.level_up(actor)   # golden column + rings (for the player module)

const MAX_SPARKS := 28
static var _spark_count: int = 0


static func _effect(pos: Vector3, life: float) -> VfxEffect:
	var e := VfxEffect.new()
	e.life = life
	return VfxUtil.spawn(e, pos) as VfxEffect


static func _ease_out(t: float, p: float = 2.0) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), p)


# ------------------------------------------------------------------ explosions & impacts

## Colour over life for fire-like particles of `color`: hot white-yellow, the colour, a dark
## transparent tail.
static func hot_ramp(color: Color) -> Array:
	var hot := color.lerp(Color(1.0, 0.95, 0.8), 0.4)
	var tail := color.darkened(0.55)
	tail.a = 0.0
	return [Color(hot.r, hot.g, hot.b, 1.0), Color(color.r, color.g, color.b, 0.9), tail]


## Area blast (Fireball, Explosive Bolt, Infernal Blow, Meteor): a white-hot flash, a quickly
## fading core, billowing puffs in the damage colour, flying embers, smoke, an expanding ground ring
## that shows the radius, a scorch mark and a brief light.
static func explosion(pos: Vector3, radius: float, color: Color, strength: float = 1.0) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 1.6)
	if e == null:
		return null
	var sp := clampf(radius / 2.2, 0.5, 2.5)
	var flash_mat := VfxUtil.material("orb", {"color": color.lerp(Color(1, 0.97, 0.9), 0.7), "energy": 4.0, "core": 1.0, "rim": 0.25})
	var flash := VfxUtil.mesh_node(VfxUtil.sphere_mesh(), flash_mat)
	flash.position.y = 0.6
	e.add_child(flash)
	var core_mat := VfxUtil.material("orb", {"color": color, "energy": 2.2, "core": 1.0, "rim": 0.35})
	var core := VfxUtil.mesh_node(VfxUtil.sphere_mesh(), core_mat)
	core.position.y = 0.45
	e.add_child(core)
	var fill := VfxUtil.ground_node(radius, {"color": color, "energy": 1.6, "radius": 3.0, "fill": 0.55, "fill_radius": 0.2})
	e.add_child(fill)
	var fill_mat := fill.material_override as ShaderMaterial
	var ring := VfxUtil.ground_node(radius * 1.05, {"color": color.lerp(Color.WHITE, 0.2), "energy": 3.0, "radius": 0.2, "thickness": 0.07})
	e.add_child(ring)
	var ring_mat := ring.material_override as ShaderMaterial
	var scorch := VfxUtil.ground_node(radius * 0.75, {"color": Color(0.04, 0.03, 0.025), "energy": 1.0, "fill": 0.8, "fill_radius": 0.9, "radius": 3.0, "alpha": 0.65, "gaps": 6.0}, false)
	scorch.position.y = 0.03
	e.add_child(scorch)
	var scorch_mat := scorch.material_override as ShaderMaterial
	VfxUtil.particles(e, Color.WHITE, {"amount": int(20 * clampf(strength, 0.6, 2.0)), "lifetime": 0.55, "speed": Vector2(1.5, 4.5) * sp,
		"gravity": 2.5, "spread": 180.0, "size": 0.62 * sp, "emit_radius": radius * 0.3, "damping": 5.0, "ramp": hot_ramp(color),
		"grow": true, "energy": 1.35}, Vector3(0, 0.6, 0))
	VfxUtil.particles(e, Color.WHITE, {"amount": int(14 * clampf(strength, 0.6, 2.0)), "lifetime": 0.7, "speed": Vector2(4.0, 9.0) * sp,
		"gravity": -9.0, "spread": 70.0, "size": 0.11, "emit_radius": 0.3, "damping": 1.0, "ramp": hot_ramp(color), "energy": 3.5}, Vector3(0, 0.5, 0))
	VfxUtil.particles(e, Color(0.16, 0.14, 0.13, 0.55), {"amount": 8, "lifetime": 1.2, "speed": Vector2(0.4, 1.4) * sp, "gravity": 1.6,
		"spread": 180.0, "size": 0.9 * sp, "emit_radius": radius * 0.35, "damping": 2.0, "additive": false, "grow": true,
		"ramp": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)]}, Vector3(0, 0.8, 0))
	VfxUtil.flash_light(e, color, 6.0 * strength, radius * 3.5, 0.5)
	e.updater = func(t: float, age: float) -> void:
		var tf := clampf(age / 0.12, 0.0, 1.0)
		flash.visible = tf < 1.0
		flash.scale = Vector3.ONE * lerpf(0.3, 0.75, tf) * radius * 0.55
		flash_mat.set_shader_parameter("alpha", 1.0 - tf)
		var tc := clampf(age / 0.3, 0.0, 1.0)
		core.visible = tc < 1.0
		core.scale = Vector3(1.0, 0.75, 1.0) * lerpf(0.35, 0.62, _ease_out(tc, 2.5)) * radius
		core_mat.set_shader_parameter("alpha", (1.0 - tc) * (1.0 - tc) * 0.75)
		var tr := clampf(age / 0.3, 0.0, 1.0)
		ring_mat.set_shader_parameter("radius", lerpf(0.2, 0.96, _ease_out(tr, 2.5)))
		ring_mat.set_shader_parameter("alpha", 1.0 - clampf((age - 0.15) / 0.35, 0.0, 1.0))
		fill_mat.set_shader_parameter("fill_radius", lerpf(0.2, 1.0, _ease_out(tr, 2.0)))
		fill_mat.set_shader_parameter("alpha", 0.9 * (1.0 - clampf(age / 0.45, 0.0, 1.0)))
		scorch_mat.set_shader_parameter("alpha", 0.65 * (1.0 - clampf((t - 0.5) / 0.5, 0.0, 1.0)))
	return e


## Small burst where a hit lands: sparks + a flash in the damage colour (bigger for crits).
static func hit_spark(pos: Vector3, color: Color, crit: bool = false) -> VfxEffect:
	if _spark_count >= MAX_SPARKS:
		return null
	var e := _effect(pos, 0.45)
	if e == null:
		return null
	_spark_count += 1
	e.tree_exiting.connect(_spark_done)
	VfxUtil.particles(e, color, {"amount": 16 if crit else 9, "lifetime": 0.32, "speed": Vector2(3.0, 8.0) if crit else Vector2(2.5, 6.0),
		"gravity": -10.0, "spread": 180.0, "size": 0.15 if crit else 0.11, "energy": 3.5, "damping": 3.0})
	var fm := VfxUtil.material("orb", {"color": color.lerp(Color.WHITE, 0.5), "energy": 3.0, "core": 1.0, "rim": 0.8})
	var f := VfxUtil.mesh_node(VfxUtil.sphere_mesh(6), fm)
	e.add_child(f)
	var size := 0.55 if crit else 0.32
	e.updater = func(_t: float, age: float) -> void:
		var tf := clampf(age / 0.12, 0.0, 1.0)
		f.visible = tf < 1.0
		f.scale = Vector3.ONE * lerpf(0.4, 1.0, tf) * size
		fm.set_shader_parameter("alpha", 1.0 - tf)
	return e


static func _spark_done() -> void:
	_spark_count = maxi(0, _spark_count - 1)


## A projectile hitting a wall or fizzling: small puff in its colour.
static func impact_puff(pos: Vector3, color: Color) -> VfxEffect:
	var e := _effect(pos, 0.4)
	if e == null:
		return null
	VfxUtil.particles(e, color, {"amount": 8, "lifetime": 0.3, "speed": Vector2(1.5, 4.0), "gravity": -6.0, "spread": 180.0, "size": 0.12, "damping": 3.0})
	return e


# ------------------------------------------------------------------ melee

## Weapon swing arc (a sweeping glowing ribbon) from the caster's right to left. style:
## "slash" (default), "wide" (cleave), "slam" (low, heavy), "stab" (a straight thrust).
static func swing(pos: Vector3, dir: Vector3, radius: float, angle_deg: float, color: Color, style: String = "slash", duration: float = 0.24) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), duration + 0.2)
	if e == null:
		return null
	e.rotation.y = VfxUtil.yaw_of(dir)
	var half := deg_to_rad(clampf(angle_deg, 12.0, 350.0)) * 0.5
	var width := clampf(radius * 0.32, 0.4, 1.2)
	var y := 1.0
	var mesh: Mesh
	match style:
		"stab":
			mesh = _thrust_mesh(maxf(radius, 1.0), 0.3)
			y = 1.1
		"slam":
			mesh = VfxUtil.arc_mesh(-half, half, maxf(0.25, radius - width * 1.2), radius)
			y = 0.45
		"wide":
			mesh = VfxUtil.arc_mesh(-half, half, maxf(0.3, radius - width * 1.25), radius, 32)
			y = 0.9
		_:
			mesh = VfxUtil.arc_mesh(-half, half, maxf(0.3, radius - width), radius)
	var mat := VfxUtil.material("sweep", {"color": color, "energy": 2.8, "progress": 0.0, "tail": 0.6})
	var mi := VfxUtil.mesh_node(mesh, mat)
	mi.position.y = y
	if style == "slash":
		mi.rotation.z = deg_to_rad(8.0)
	e.add_child(mi)
	e.updater = func(_t: float, age: float) -> void:
		var p := clampf(age / (duration * 0.55), 0.0, 1.0)
		mat.set_shader_parameter("progress", _ease_out(p, 2.0) + 0.001)
		mat.set_shader_parameter("tail", lerpf(0.45, 1.05, p))
		var fade := clampf((age - duration * 0.45) / (duration * 0.55 + 0.2), 0.0, 1.0)
		mat.set_shader_parameter("alpha", 1.0 - fade)
	return e


## Straight thrust ribbon along +Z (UV.x along the thrust, bright centre line).
static func _thrust_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	for side in [-1.0, 1.0]:
		for i in n:
			var f0 := float(i) / n
			var f1 := float(i + 1) / n
			var z0 := lerpf(0.3, length, f0)
			var z1 := lerpf(0.3, length, f1)
			var w0 := width * (1.0 - f0 * 0.7)
			var w1 := width * (1.0 - f1 * 0.7)
			var a := Vector3(0, 0, z0)
			var b := Vector3(side * w0, 0, z0)
			var c := Vector3(side * w1, 0, z1)
			var d := Vector3(0, 0, z1)
			for v in [[a, Vector2(f0, 0.85)], [b, Vector2(f0, 0.0)], [c, Vector2(f1, 0.0)], [a, Vector2(f0, 0.85)], [c, Vector2(f1, 0.0)], [d, Vector2(f1, 0.85)]]:
				st.set_normal(Vector3.UP)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	return st.commit()


## Ground shockwave through a cone (Ground Slam, monster slams): a glowing band races outward
## with dust behind it, cracks split the floor along the cone and rock chunks burst up as the
## wave passes.
static func shockwave(pos: Vector3, dir: Vector3, radius: float, angle_deg: float, color: Color, duration: float = 0.35) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), duration + 1.0)
	if e == null:
		return null
	e.rotation.y = VfxUtil.yaw_of(dir)
	var half := deg_to_rad(clampf(angle_deg, 10.0, 360.0)) * 0.5
	if angle_deg >= 359.0:
		half = 3.2
	var dust := VfxUtil.ground_node(radius, {"color": Color(0.36, 0.31, 0.26), "energy": 1.0, "radius": 0.05, "thickness": 0.35, "half_angle": half, "alpha": 0.75, "fill": 0.3, "fill_radius": 0.05}, false)
	dust.position.y = 0.035
	e.add_child(dust)
	var band := VfxUtil.ground_node(radius, {"color": color, "energy": 2.4, "radius": 0.05, "thickness": 0.09, "half_angle": half})
	e.add_child(band)
	var dust_mat := dust.material_override as ShaderMaterial
	var band_mat := band.material_override as ShaderMaterial
	var cracks: Array = []
	var ncr := 3 if angle_deg < 180.0 else 6
	for i in ncr:
		var ca := 0.0 if ncr == 1 else lerpf(-half * 0.6, half * 0.6, float(i) / float(ncr - 1))
		if angle_deg >= 180.0:
			ca = TAU * float(i) / float(ncr)
		var cr := VfxUtil.ground_node(radius * randf_range(0.7, 0.95), {"color": Color(0.05, 0.04, 0.035), "energy": 1.0, "radius": 3.0,
			"fill": 0.85, "fill_radius": 0.0, "half_angle": 0.035, "alpha": 0.8}, false)
		cr.position.y = 0.04
		cr.rotation.y = ca + randf_range(-0.08, 0.08)
		e.add_child(cr)
		cracks.append(cr.material_override)
	var rocks: Array = []
	var rock_mat := VfxUtil.material("solid", {"color": Color(0.4, 0.37, 0.34), "rim": 0.6, "rim_color": color})
	var n := clampi(int(radius * 3.0), 6, 22)
	for i in n:
		var ang := randf_range(-half * 0.9, half * 0.9)
		var d := randf_range(0.6, radius * 0.95)
		var rock := VfxUtil.mesh_node(VfxUtil.sphere_mesh(4), rock_mat)
		rock.position = Vector3(sin(ang) * d, 0.0, cos(ang) * d)
		rock.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		rock.scale = Vector3.ZERO
		e.add_child(rock)
		rocks.append([rock, d / radius, randf_range(0.1, 0.22), randf_range(2.5, 5.0), Vector3(randf_range(0.7, 1.3), randf_range(0.6, 1.0), randf_range(0.7, 1.3))])
	VfxUtil.particles(e, Color(0.55, 0.49, 0.42, 0.8), {"amount": 18, "lifetime": 0.9, "speed": Vector2(1.0, 3.0), "gravity": -2.0,
		"spread": 60.0, "size": 0.55, "emit_radius": radius * 0.3, "additive": false, "damping": 2.0, "grow": true,
		"ramp": [Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)]}, Vector3(0, 0.2, radius * 0.5))
	e.updater = func(t: float, age: float) -> void:
		var tw := clampf(age / duration, 0.0, 1.0)
		var r := lerpf(0.05, 0.97, _ease_out(tw, 1.6))
		band_mat.set_shader_parameter("radius", r)
		band_mat.set_shader_parameter("alpha", 1.0 - clampf((age - duration * 0.7) / 0.35, 0.0, 1.0))
		dust_mat.set_shader_parameter("radius", r * 0.97)
		dust_mat.set_shader_parameter("fill_radius", r)
		dust_mat.set_shader_parameter("alpha", 0.75 * (1.0 - clampf((age - duration) / 0.9, 0.0, 1.0)))
		for cm in cracks:
			(cm as ShaderMaterial).set_shader_parameter("fill_radius", r)
			(cm as ShaderMaterial).set_shader_parameter("alpha", 0.8 * (1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)))
		for rk in rocks:
			var node: MeshInstance3D = rk[0]
			var pass_t: float = age - float(rk[1]) * duration
			if pass_t <= 0.0:
				continue
			var up_v: float = rk[3]
			var y := up_v * pass_t - 9.0 * pass_t * pass_t
			var size: float = rk[2]
			var fade := 1.0 - clampf((pass_t - 0.5) / 0.3, 0.0, 1.0)
			node.position.y = maxf(0.0, y)
			node.scale = (rk[4] as Vector3) * size * clampf(pass_t * 10.0, 0.0, 1.0) * fade
			node.rotation.x += 0.15
	return e


# ------------------------------------------------------------------ areas

## Expanding ring centred on pos (Frost Nova, boss fire nova). style "frost" adds ice shards
## and a frosty floor, "fire" embers and a light.
static func nova(pos: Vector3, radius: float, color: Color, expand_time: float = 0.3, style: String = "") -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), expand_time + 0.9)
	if e == null:
		return null
	var ring := VfxUtil.ground_node(radius * 1.05, {"color": color, "energy": 3.0, "radius": 0.02, "thickness": 0.1})
	e.add_child(ring)
	var ring2 := VfxUtil.ground_node(radius * 1.05, {"color": color, "energy": 1.6, "radius": 0.02, "thickness": 0.22, "alpha": 0.6})
	e.add_child(ring2)
	var floor_n := VfxUtil.ground_node(radius, {"color": color, "energy": 0.9, "radius": 3.0, "fill": 0.45, "fill_radius": 0.0})
	floor_n.position.y = 0.04
	e.add_child(floor_n)
	var rm := ring.material_override as ShaderMaterial
	var rm2 := ring2.material_override as ShaderMaterial
	var fm := floor_n.material_override as ShaderMaterial
	var shards: Array = []
	if style == "frost":
		var sm := VfxUtil.material("glass", {"color": color, "alpha": 0.85, "energy": 1.5})
		for i in 16:
			var a := randf() * TAU
			var d := randf_range(0.35, 0.95) * radius
			var sh := VfxUtil.mesh_node(VfxUtil.spike_mesh(), sm)
			sh.position = Vector3(sin(a) * d, -0.02, cos(a) * d)
			sh.rotation = Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6))
			sh.scale = Vector3.ZERO
			e.add_child(sh)
			shards.append([sh, d / radius, randf_range(0.12, 0.22), randf_range(0.5, 1.1)])
		VfxUtil.particles(e, color.lerp(Color.WHITE, 0.5), {"amount": 24, "lifetime": 0.8, "speed": Vector2(radius * 1.2, radius * 2.2),
			"gravity": -1.0, "spread": 180.0, "direction": Vector3(1, 0.15, 0), "size": 0.13, "damping": 4.0}, Vector3(0, 0.4, 0))
	elif style == "fire":
		VfxUtil.particles(e, color, {"amount": 26, "lifetime": 0.8, "speed": Vector2(radius * 1.2, radius * 2.0),
			"gravity": 1.5, "spread": 180.0, "direction": Vector3(1, 0.2, 0), "size": 0.28, "damping": 3.0}, Vector3(0, 0.4, 0))
		VfxUtil.flash_light(e, color, 5.0, radius * 1.8, expand_time + 0.4)
	e.updater = func(_t: float, age: float) -> void:
		var te := clampf(age / maxf(expand_time, 0.05), 0.0, 1.0)
		var r := lerpf(0.05, 0.95, _ease_out(te, 1.8))
		rm.set_shader_parameter("radius", r)
		rm2.set_shader_parameter("radius", r * 0.93)
		var fade := clampf((age - expand_time) / 0.5, 0.0, 1.0)
		rm.set_shader_parameter("alpha", 1.0 - fade)
		rm2.set_shader_parameter("alpha", 0.6 * (1.0 - fade))
		fm.set_shader_parameter("fill_radius", r)
		fm.set_shader_parameter("alpha", 1.0 - clampf((age - expand_time) / 0.8, 0.0, 1.0))
		for sh in shards:
			var node: MeshInstance3D = sh[0]
			var pass_t: float = te - float(sh[1])
			var s := 0.0
			if pass_t > 0.0:
				s = clampf(pass_t * 6.0, 0.0, 1.0) * (1.0 - clampf((age - expand_time - 0.35) / 0.45, 0.0, 1.0))
			var w: float = sh[2]
			node.scale = Vector3(w, w * 4.0 * float(sh[3]), w) * s
	return e


## Jagged lightning beam through `points` (world positions), flickering for `duration`.
static func beam(points: Array, color: Color, duration: float = 0.32, width: float = 1.0) -> VfxEffect:
	if points.size() < 2:
		return null
	var e := _effect(Vector3.ZERO, duration)
	if e == null:
		return null
	e.global_position = Vector3.ZERO
	var glow_mat := VfxUtil.material("add", {"color": color, "energy": 1.3, "alpha": 0.4})
	var core_mat := VfxUtil.material("add", {"color": color.lerp(Color.WHITE, 0.7), "energy": 3.0, "alpha": 1.0})
	var glow := VfxUtil.mesh_node(ArrayMesh.new(), glow_mat)
	var core := VfxUtil.mesh_node(ArrayMesh.new(), core_mat)
	e.add_child(glow)
	e.add_child(core)
	var pts: Array = []
	for p in points:
		pts.append(p)
	var flashes: Array = []
	for i in range(1, pts.size()):
		var fm := VfxUtil.material("orb", {"color": color, "energy": 3.0, "core": 1.0, "rim": 1.2})
		var f := VfxUtil.mesh_node(VfxUtil.sphere_mesh(6), fm)
		f.position = pts[i]
		f.scale = Vector3.ONE * 0.28
		e.add_child(f)
		flashes.append([f, fm])
	var forks: Array = []
	for i in mini(6, 2 * (pts.size() - 1)):
		var fk := VfxUtil.mesh_node(ArrayMesh.new(), core_mat)
		e.add_child(fk)
		forks.append(fk)
	for i in range(1, pts.size()):
		VfxUtil.particles(e, color, {"amount": 8, "lifetime": 0.3, "speed": Vector2(2.0, 5.0), "gravity": -6.0, "spread": 180.0,
			"size": 0.08, "energy": 3.5}, pts[i])
	var state := {"next": 0.0}
	e.updater = func(t: float, age: float) -> void:
		if age >= float(state["next"]):
			state["next"] = age + 0.05
			var all := PackedVector3Array()
			for i in range(1, pts.size()):
				var seg := VfxUtil.jagged_points(pts[i - 1], pts[i], 0.35 * width)
				if i > 1:
					seg.remove_at(0)
				all.append_array(seg)
			glow.mesh = VfxUtil.ribbon_mesh(all, 0.42 * width)
			core.mesh = VfxUtil.ribbon_mesh(all, 0.08 * width)
			# Short side forks off random kinks of the bolt.
			for fk in forks:
				if all.size() < 3 or randf() < 0.3:
					(fk as MeshInstance3D).visible = false
					continue
				var k := randi_range(1, all.size() - 2)
				var from: Vector3 = all[k]
				var along := (all[k + 1] - all[k - 1]).normalized()
				var side := along.cross(VfxUtil.VIEW_DIR).normalized() * (1.0 if randf() < 0.5 else -1.0)
				var to := from + (along * 0.5 + side).normalized() * randf_range(0.5, 1.1) * width + Vector3.DOWN * randf_range(0.0, 0.4)
				(fk as MeshInstance3D).visible = true
				(fk as MeshInstance3D).mesh = VfxUtil.ribbon_mesh(VfxUtil.jagged_points(from, to, 0.12 * width), 0.05 * width)
		var a := 1.0 - t * t
		glow_mat.set_shader_parameter("alpha", 0.4 * a)
		core_mat.set_shader_parameter("alpha", a)
		for fl in flashes:
			(fl[1] as ShaderMaterial).set_shader_parameter("alpha", a * 0.9)
	return e


## Teleport flash: a column of light that collapses (vanish) or bursts (appear).
static func blink(pos: Vector3, color: Color, appear: bool) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.6)
	if e == null:
		return null
	var cm := VfxUtil.material("beam", {"color": color, "energy": 2.6})
	var col := VfxUtil.mesh_node(VfxUtil.column_mesh(), cm)
	e.add_child(col)
	var ring := VfxUtil.ground_node(2.2, {"color": color, "energy": 3.0, "radius": 0.1, "thickness": 0.12})
	e.add_child(ring)
	var rmat := ring.material_override as ShaderMaterial
	VfxUtil.particles(e, color, {"amount": 22, "lifetime": 0.6, "speed": Vector2(1.5, 4.5), "gravity": 3.0, "spread": 35.0,
		"size": 0.14, "emit_radius": 0.5, "damping": 1.0}, Vector3(0, 0.3, 0))
	VfxUtil.flash_light(e, color, 3.0, 6.0, 0.4)
	e.updater = func(t: float, age: float) -> void:
		var tc := clampf(age / 0.35, 0.0, 1.0)
		col.visible = tc < 1.0
		if appear:
			var r := lerpf(1.3, 0.25, _ease_out(tc, 2.0))
			col.scale = Vector3(r, lerpf(3.2, 2.2, tc), r)
		else:
			var r2 := lerpf(0.7, 0.05, _ease_out(tc, 2.0))
			col.scale = Vector3(r2, lerpf(2.2, 3.6, tc), r2)
		cm.set_shader_parameter("alpha", 1.0 - tc)
		rmat.set_shader_parameter("radius", lerpf(0.1, 0.95, _ease_out(t, 2.0)))
		rmat.set_shader_parameter("alpha", 1.0 - t)
	return e


## Landing impact of a leap: dust ring, warm shock ring and rocks.
static func leap_dust(pos: Vector3, radius: float, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 1.1)
	if e == null:
		return null
	var dust := VfxUtil.ground_node(radius * 1.25, {"color": Color(0.45, 0.39, 0.32), "energy": 1.0, "radius": 0.1, "thickness": 0.35, "alpha": 0.85}, false)
	dust.position.y = 0.035
	e.add_child(dust)
	var shock := VfxUtil.ground_node(radius * 1.1, {"color": color, "energy": 2.6, "radius": 0.1, "thickness": 0.1})
	e.add_child(shock)
	var crack := VfxUtil.ground_node(radius * 0.8, {"color": Color(0.06, 0.05, 0.04), "energy": 1.0, "radius": 3.0, "fill": 0.6, "fill_radius": 1.0, "alpha": 0.6, "gaps": 7.0}, false)
	crack.position.y = 0.03
	e.add_child(crack)
	var dm := dust.material_override as ShaderMaterial
	var sm := shock.material_override as ShaderMaterial
	var cm := crack.material_override as ShaderMaterial
	var rocks: Array = []
	var rock_mat := VfxUtil.material("solid", {"color": Color(0.33, 0.29, 0.25), "rim": 0.5, "rim_color": color})
	for i in 8:
		var a := float(i) / 8.0 * TAU + randf_range(-0.3, 0.3)
		var d := randf_range(0.5, 0.9) * radius
		var rock := VfxUtil.mesh_node(VfxUtil.spike_mesh(), rock_mat)
		rock.position = Vector3(sin(a) * d, -0.05, cos(a) * d)
		rock.rotation = Vector3(sin(a) * 0.6, randf() * TAU, cos(a) * 0.6)
		e.add_child(rock)
		rocks.append([rock, randf_range(0.15, 0.28)])
	VfxUtil.particles(e, Color(0.6, 0.53, 0.45, 0.8), {"amount": 18, "lifetime": 0.9, "speed": Vector2(2.0, 4.5), "gravity": -2.5,
		"spread": 80.0, "size": 0.5, "emit_radius": radius * 0.4, "additive": false, "damping": 2.5}, Vector3(0, 0.2, 0))
	e.updater = func(t: float, age: float) -> void:
		var tr := clampf(age / 0.4, 0.0, 1.0)
		dm.set_shader_parameter("radius", lerpf(0.1, 0.92, _ease_out(tr, 2.0)))
		dm.set_shader_parameter("alpha", 0.85 * (1.0 - t))
		sm.set_shader_parameter("radius", lerpf(0.1, 0.95, _ease_out(clampf(age / 0.25, 0.0, 1.0), 2.0)))
		sm.set_shader_parameter("alpha", 1.0 - clampf(age / 0.35, 0.0, 1.0))
		cm.set_shader_parameter("alpha", 0.6 * (1.0 - t))
		for rk in rocks:
			var s := clampf(age / 0.08, 0.0, 1.0) * (1.0 - clampf((age - 0.45) / 0.5, 0.0, 1.0))
			var w: float = rk[1]
			(rk[0] as MeshInstance3D).scale = Vector3(w, w * 2.5, w) * s
	return e


## War cry shout: stacked expanding rings (sound waves), a flash column and rising motes.
static func warcry(pos: Vector3, radius: float, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 1.0)
	if e == null:
		return null
	var rings: Array = []
	for i in 3:
		var r := VfxUtil.ground_node(radius, {"color": color, "energy": 2.6, "radius": 0.05, "thickness": 0.05 + 0.03 * i, "gaps": 14.0})
		e.add_child(r)
		rings.append(r.material_override)
	var cm := VfxUtil.material("beam", {"color": color, "energy": 2.2})
	var col := VfxUtil.mesh_node(VfxUtil.column_mesh(), cm)
	e.add_child(col)
	VfxUtil.particles(e, color, {"amount": 24, "lifetime": 0.8, "speed": Vector2(2.0, 5.0), "gravity": 1.0, "spread": 60.0,
		"size": 0.16, "emit_radius": 0.8, "damping": 2.0}, Vector3(0, 0.4, 0))
	VfxUtil.flash_light(e, color, 3.0, radius, 0.5)
	e.updater = func(_t: float, age: float) -> void:
		for i in rings.size():
			var tr := clampf((age - i * 0.12) / 0.55, 0.0, 1.0)
			var m: ShaderMaterial = rings[i]
			m.set_shader_parameter("radius", lerpf(0.05, 0.97, _ease_out(tr, 2.0)))
			m.set_shader_parameter("alpha", (1.0 - tr) if tr > 0.0 else 0.0)
			m.set_shader_parameter("spin", age * 2.0)
		var tc := clampf(age / 0.4, 0.0, 1.0)
		col.visible = tc < 1.0
		var cr := lerpf(0.6, 1.4, tc)
		col.scale = Vector3(cr, lerpf(1.5, 2.8, tc), cr)
		cm.set_shader_parameter("alpha", (1.0 - tc) * 0.8)
	return e


## Buff glow under an actor while it has buff `buff_id` (one per actor and buff).
static func buff_aura(actor: Actor, buff_id: String, color: Color) -> VfxEffect:
	if actor == null or not is_instance_valid(actor):
		return null
	var key := "vfx_aura_" + buff_id
	if actor.has_meta(key):
		var old: Variant = actor.get_meta(key)
		if is_instance_valid(old):
			return old as VfxEffect
	var e := _effect(VfxUtil.flat(actor.global_position), 0.6)
	if e == null:
		return null
	actor.set_meta(key, e)
	e.follow = actor
	e.hold_t = 0.5
	var ref: WeakRef = weakref(actor)
	e.keep_while = func() -> bool:
		var a: Variant = ref.get_ref()
		return a != null and is_instance_valid(a) and not (a as Actor).dead and (a as Actor).has_buff(buff_id)
	var size := actor.get_collision_radius() * 2.2 + 0.3
	var ring := VfxUtil.ground_node(size, {"color": color, "energy": 2.4, "radius": 0.8, "thickness": 0.12, "gaps": 6.0})
	e.add_child(ring)
	var glow := VfxUtil.ground_node(size, {"color": color, "energy": 1.0, "radius": 3.0, "fill": 0.25, "fill_radius": 0.85})
	e.add_child(glow)
	var rm := ring.material_override as ShaderMaterial
	var gm := glow.material_override as ShaderMaterial
	VfxUtil.particles(e, color, {"amount": 8, "lifetime": 0.9, "speed": Vector2(0.6, 1.4), "gravity": 1.2, "spread": 15.0,
		"size": 0.1, "emit_radius": size * 0.6, "one_shot": false}, Vector3(0, 0.1, 0))
	e.updater = func(t: float, age: float) -> void:
		var a := clampf(age / 0.2, 0.0, 1.0)
		if t > 0.5:
			a = 1.0 - (t - 0.5) / 0.5
		rm.set_shader_parameter("spin", Time.get_ticks_msec() * 0.003)
		rm.set_shader_parameter("alpha", a)
		gm.set_shader_parameter("alpha", a * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.006)))
	return e


## Poison cloud visual lasting `duration` (+ fade): a murky floor stain with a glowing rim,
## rolling gas puffs and rising bubbles.
static func cloud(pos: Vector3, radius: float, color: Color, duration: float) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), duration + 0.8)
	if e == null:
		return null
	var stain := VfxUtil.ground_node(radius, {"color": color.darkened(0.55), "energy": 1.0, "radius": 0.93, "thickness": 0.1, "fill": 0.45, "fill_radius": 0.95, "swirl": 1.0}, false)
	stain.position.y = 0.035
	e.add_child(stain)
	var glow := VfxUtil.ground_node(radius, {"color": color, "energy": 1.1, "radius": 0.92, "thickness": 0.07, "swirl": 1.0})
	e.add_child(glow)
	var sm := stain.material_override as ShaderMaterial
	var gm := glow.material_override as ShaderMaterial
	var gas := color.lerp(Color(0.2, 0.25, 0.1), 0.35)
	var size_k := clampf(radius / 2.5, 0.6, 1.6)
	var puffs := VfxUtil.particles(e, gas, {"amount": int(22 * size_k), "lifetime": 1.5, "speed": Vector2(0.1, 0.5), "gravity": 0.25,
		"spread": 180.0, "size": 1.5 * size_k, "emit_radius": radius * 0.6, "one_shot": false, "additive": false, "grow": true,
		"damping": 0.5, "ramp": [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)]}, Vector3(0, 0.5, 0))
	var bubbles := VfxUtil.particles(e, color, {"amount": 16, "lifetime": 1.0, "speed": Vector2(0.4, 1.2), "gravity": 0.8, "spread": 20.0,
		"size": 0.12, "emit_radius": radius * 0.7, "one_shot": false, "energy": 2.0}, Vector3(0, 0.15, 0))
	var life := duration + 0.8
	e.updater = func(_t: float, age: float) -> void:
		var a := clampf(age / 0.25, 0.0, 1.0) * (1.0 - clampf((age - duration) / 0.8, 0.0, 1.0))
		sm.set_shader_parameter("alpha", a)
		sm.set_shader_parameter("spin", age)
		gm.set_shader_parameter("alpha", a * 0.8)
		gm.set_shader_parameter("spin", age)
		if age >= duration:
			for p in [puffs, bubbles]:
				if p != null and is_instance_valid(p):
					(p as GPUParticles3D).emitting = false
		if age > life:
			e.queue_free()
	return e


## Dark summoning circle with a glowing rune ring and rising motes.
static func summon_circle(pos: Vector3, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 1.4)
	if e == null:
		return null
	var dark := VfxUtil.ground_node(1.2, {"color": Color(0.05, 0.02, 0.08), "energy": 1.0, "radius": 3.0, "fill": 0.75, "fill_radius": 0.8}, false)
	dark.position.y = 0.035
	e.add_child(dark)
	var ring := VfxUtil.ground_node(1.3, {"color": color, "energy": 2.6, "radius": 0.85, "thickness": 0.07, "gaps": 12.0})
	e.add_child(ring)
	var inner := VfxUtil.ground_node(1.3, {"color": color, "energy": 2.0, "radius": 0.55, "thickness": 0.05, "gaps": 6.0})
	e.add_child(inner)
	var dm := dark.material_override as ShaderMaterial
	var rm := ring.material_override as ShaderMaterial
	var im := inner.material_override as ShaderMaterial
	VfxUtil.particles(e, color, {"amount": 18, "lifetime": 0.9, "speed": Vector2(1.0, 2.6), "gravity": 1.5, "spread": 12.0,
		"size": 0.11, "emit_radius": 0.8, "energy": 2.6}, Vector3(0, 0.1, 0))
	e.updater = func(t: float, age: float) -> void:
		var a := clampf(age / 0.15, 0.0, 1.0) * (1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0))
		rm.set_shader_parameter("spin", age * 3.0)
		im.set_shader_parameter("spin", -age * 4.0)
		rm.set_shader_parameter("alpha", a)
		im.set_shader_parameter("alpha", a)
		dm.set_shader_parameter("alpha", a * 0.8)
	return e


## Bone spikes erupting from the ground (boss spikes).
static func spikes(pos: Vector3, radius: float, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.95)
	if e == null:
		return null
	var mat := VfxUtil.material("solid", {"color": color, "rim": 0.8, "rim_color": Color(1.0, 0.9, 0.7)})
	var list: Array = []
	for i in 5:
		var a := randf() * TAU
		var d := randf_range(0.0, 0.6) * radius
		var sp := VfxUtil.mesh_node(VfxUtil.spike_mesh(), mat)
		sp.position = Vector3(sin(a) * d, -0.05, cos(a) * d)
		sp.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		sp.scale = Vector3.ZERO
		e.add_child(sp)
		list.append([sp, randf_range(0.18, 0.3), randf_range(1.2, 2.2)])
	var dust := VfxUtil.ground_node(radius * 1.3, {"color": Color(0.45, 0.39, 0.32), "energy": 1.0, "radius": 0.2, "thickness": 0.3, "alpha": 0.7}, false)
	e.add_child(dust)
	var dm := dust.material_override as ShaderMaterial
	e.updater = func(t: float, age: float) -> void:
		var up := clampf(age / 0.08, 0.0, 1.0)
		var down := clampf((age - 0.5) / 0.4, 0.0, 1.0)
		for s in list:
			var w: float = s[1]
			(s[0] as MeshInstance3D).scale = Vector3(w, float(s[2]), w) * up
			(s[0] as MeshInstance3D).position.y = -0.05 - float(s[2]) * down
		dm.set_shader_parameter("radius", lerpf(0.2, 0.9, _ease_out(clampf(age / 0.3, 0.0, 1.0))))
		dm.set_shader_parameter("alpha", 0.7 * (1.0 - t))
	return e


## Small ground marker where the player aimed a delayed area skill (meteor): a ring that
## tightens while it fills. Not a hostile telegraph (those are red, VfxTelegraph).
static func target_marker(pos: Vector3, radius: float, color: Color, duration: float) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), duration + 0.1)
	if e == null:
		return null
	var ring := VfxUtil.ground_node(radius, {"color": color, "energy": 1.8, "radius": 0.95, "thickness": 0.05, "gaps": 8.0, "fill": 0.18, "fill_radius": 0.0})
	e.add_child(ring)
	var rm := ring.material_override as ShaderMaterial
	e.updater = func(t: float, age: float) -> void:
		rm.set_shader_parameter("fill_radius", t * 0.95)
		rm.set_shader_parameter("spin", age * 2.0)
		rm.set_shader_parameter("alpha", clampf(age / 0.1, 0.0, 1.0))
	return e


## Golden level-up burst around an actor (for the player module): column, rings, motes.
static func level_up(actor: Actor) -> VfxEffect:
	if actor == null or not is_instance_valid(actor):
		return null
	var color := UIStyle.COLOR_GOLD
	var e := _effect(VfxUtil.flat(actor.global_position), 1.6)
	if e == null:
		return null
	e.follow = actor
	var cm := VfxUtil.material("beam", {"color": color, "energy": 2.2})
	var col := VfxUtil.mesh_node(VfxUtil.column_mesh(), cm)
	e.add_child(col)
	var ring := VfxUtil.ground_node(3.0, {"color": color, "energy": 2.8, "radius": 0.1, "thickness": 0.08, "gaps": 10.0})
	e.add_child(ring)
	var rm := ring.material_override as ShaderMaterial
	VfxUtil.particles(e, color, {"amount": 30, "lifetime": 1.2, "speed": Vector2(1.5, 4.0), "gravity": 1.5, "spread": 25.0,
		"size": 0.14, "emit_radius": 0.7}, Vector3(0, 0.2, 0))
	VfxUtil.flash_light(e, color, 3.0, 7.0, 1.0)
	e.updater = func(t: float, age: float) -> void:
		var r := lerpf(0.9, 0.5, t)
		col.scale = Vector3(r, lerpf(1.0, 4.0, _ease_out(clampf(age / 0.5, 0.0, 1.0))), r)
		cm.set_shader_parameter("alpha", 1.0 - t)
		rm.set_shader_parameter("radius", lerpf(0.1, 0.95, _ease_out(clampf(age / 0.7, 0.0, 1.0))))
		rm.set_shader_parameter("alpha", 1.0 - t)
		rm.set_shader_parameter("spin", age * 2.0)
	return e


# ------------------------------------------------------------------ additions (deliveries)

## Heavy weapon impact on the ground in front of the caster (Heavy Strike): crack decal, warm
## flash ring, dust and a few pebbles.
static func ground_impact(pos: Vector3, color: Color, strength: float = 1.0) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.8)
	if e == null:
		return null
	var r := 1.3 * strength
	var ring := VfxUtil.ground_node(r, {"color": color, "energy": 2.8, "radius": 0.1, "thickness": 0.14})
	e.add_child(ring)
	var rm := ring.material_override as ShaderMaterial
	var crack := VfxUtil.ground_node(r * 0.8, {"color": Color(0.05, 0.04, 0.03), "energy": 1.0, "radius": 3.0, "fill": 0.7, "fill_radius": 1.0, "alpha": 0.65, "gaps": 5.0}, false)
	crack.position.y = 0.03
	e.add_child(crack)
	var cm := crack.material_override as ShaderMaterial
	VfxUtil.particles(e, Color(0.62, 0.55, 0.46, 0.8), {"amount": 10, "lifetime": 0.6, "speed": Vector2(1.5, 3.5), "gravity": -6.0,
		"spread": 70.0, "size": 0.3, "emit_radius": 0.3, "additive": false, "damping": 2.0}, Vector3(0, 0.15, 0))
	VfxUtil.particles(e, color, {"amount": 10, "lifetime": 0.35, "speed": Vector2(2.5, 6.0), "gravity": -9.0,
		"spread": 60.0, "size": 0.12, "energy": 3.0, "damping": 2.0}, Vector3(0, 0.2, 0))
	e.updater = func(t: float, age: float) -> void:
		rm.set_shader_parameter("radius", lerpf(0.1, 0.95, _ease_out(clampf(age / 0.25, 0.0, 1.0), 2.0)))
		rm.set_shader_parameter("alpha", 1.0 - clampf(age / 0.3, 0.0, 1.0))
		cm.set_shader_parameter("alpha", 0.65 * (1.0 - t))
	return e


## Bright expanding shock ring (meteor landings, big impacts).
static func shock_ring(pos: Vector3, radius: float, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.55)
	if e == null:
		return null
	var ring := VfxUtil.ground_node(radius, {"color": color.lerp(Color.WHITE, 0.25), "energy": 3.2, "radius": 0.1, "thickness": 0.06})
	e.add_child(ring)
	var rm := ring.material_override as ShaderMaterial
	e.updater = func(t: float, _age: float) -> void:
		rm.set_shader_parameter("radius", lerpf(0.2, 0.98, _ease_out(t, 2.5)))
		rm.set_shader_parameter("thickness", lerpf(0.1, 0.03, t))
		rm.set_shader_parameter("alpha", 1.0 - t * t)
	return e


## A rain arrow landing: the arrow stuck in the floor for a moment, a dust puff and a small ring.
static func arrow_landing(pos: Vector3, dir: Vector3, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.9)
	if e == null:
		return null
	if Assets.has_model("proj_arrow"):
		var arrow := Assets.model("proj_arrow")
		var holder := Node3D.new()
		e.add_child(holder)
		holder.add_child(arrow)
		var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.DOWN
		holder.basis = Basis.looking_at(d, Vector3.RIGHT if absf(d.y) > 0.98 else Vector3.UP, true)
		holder.position = Vector3(0, 0.25, 0)
		VfxMissile._no_shadows(arrow)
		e.set_meta("arrow", holder)
	var ring := VfxUtil.ground_node(0.9, {"color": color, "energy": 2.2, "radius": 0.1, "thickness": 0.16})
	e.add_child(ring)
	var rm := ring.material_override as ShaderMaterial
	VfxUtil.particles(e, Color(0.6, 0.53, 0.45, 0.75), {"amount": 6, "lifetime": 0.45, "speed": Vector2(0.8, 2.0), "gravity": -4.0,
		"spread": 70.0, "size": 0.26, "emit_radius": 0.15, "additive": false, "damping": 2.0}, Vector3(0, 0.1, 0))
	e.updater = func(t: float, age: float) -> void:
		rm.set_shader_parameter("radius", lerpf(0.1, 0.9, _ease_out(clampf(age / 0.2, 0.0, 1.0), 2.0)))
		rm.set_shader_parameter("alpha", 1.0 - clampf(age / 0.3, 0.0, 1.0))
		if e.has_meta("arrow"):
			var h: Node3D = e.get_meta("arrow")
			h.position.y = 0.25 - 0.45 * clampf((t - 0.55) / 0.45, 0.0, 1.0)
	return e


## Small dust puff on the floor (leap take-off, footfalls).
static func dust_puff(pos: Vector3, size: float = 1.0) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.7)
	if e == null:
		return null
	VfxUtil.particles(e, Color(0.6, 0.53, 0.45, 0.7), {"amount": 10, "lifetime": 0.6, "speed": Vector2(1.0, 2.5) * size, "gravity": -1.5,
		"spread": 80.0, "size": 0.4 * size, "emit_radius": 0.3 * size, "additive": false, "damping": 3.0}, Vector3(0, 0.15, 0))
	return e


## Dust and sparks trailing an actor while it charges (ends with end_now()).
static func charge_trail(actor: Actor, color: Color) -> VfxEffect:
	if actor == null or not is_instance_valid(actor):
		return null
	var e := _effect(VfxUtil.flat(actor.global_position), 0.6)
	if e == null:
		return null
	e.follow = actor
	e.hold_t = 0.3
	var ref: WeakRef = weakref(actor)
	e.keep_while = func() -> bool:
		var a: Variant = ref.get_ref()
		return a != null and is_instance_valid(a) and not (a as Actor).dead
	VfxUtil.particles(e, Color(0.55, 0.48, 0.4, 0.8), {"amount": 24, "lifetime": 0.7, "speed": Vector2(0.5, 1.5), "gravity": 0.5,
		"spread": 60.0, "size": 0.55, "emit_radius": 0.5, "additive": false, "damping": 1.5, "one_shot": false}, Vector3(0, 0.2, 0))
	VfxUtil.particles(e, color, {"amount": 14, "lifetime": 0.3, "speed": Vector2(1.0, 3.0), "gravity": -6.0,
		"spread": 90.0, "size": 0.1, "emit_radius": 0.4, "one_shot": false}, Vector3(0, 0.1, 0))
	return e


## Short flash at a crossbow / bow when a shot leaves.
static func muzzle_flash(pos: Vector3, color: Color) -> VfxEffect:
	var e := _effect(pos, 0.16)
	if e == null:
		return null
	var fm := VfxUtil.material("orb", {"color": color.lerp(Color(1.0, 0.85, 0.5), 0.6), "energy": 2.4, "core": 1.0, "rim": 0.5})
	var f := VfxUtil.mesh_node(VfxUtil.sphere_mesh(6), fm)
	e.add_child(f)
	e.updater = func(t: float, _age: float) -> void:
		f.scale = Vector3.ONE * lerpf(0.08, 0.22, t)
		fm.set_shader_parameter("alpha", 1.0 - t)
	return e


## One whirlwind tick: a full-circle blade sweep around the caster plus a thin dust ring.
static func whirl_pulse(pos: Vector3, radius: float, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.32)
	if e == null:
		return null
	e.rotation.y = randf() * TAU
	var mat := VfxUtil.material("sweep", {"color": color, "energy": 2.4, "progress": 0.0, "tail": 0.9})
	var mi := VfxUtil.mesh_node(VfxUtil.arc_mesh(0.0, TAU * 0.92, maxf(0.3, radius * 0.55), radius, 36), mat)
	mi.position.y = 0.8
	e.add_child(mi)
	var dust := VfxUtil.ground_node(radius, {"color": Color(0.5, 0.44, 0.37), "energy": 1.0, "radius": 0.8, "thickness": 0.18, "alpha": 0.5}, false)
	e.add_child(dust)
	var dm := dust.material_override as ShaderMaterial
	e.updater = func(t: float, _age: float) -> void:
		mat.set_shader_parameter("progress", _ease_out(clampf(t * 1.6, 0.0, 1.0), 2.0) + 0.001)
		mat.set_shader_parameter("alpha", 1.0 - clampf((t - 0.45) / 0.55, 0.0, 1.0))
		mi.rotation.y = -t * 1.5
		dm.set_shader_parameter("radius", lerpf(0.6, 0.95, t))
		dm.set_shader_parameter("alpha", 0.5 * (1.0 - t))
	return e


## Continuous whirling blades around a channelling actor while `keep` returns true.
static func whirl(actor: Actor, radius: float, color: Color, keep: Callable) -> VfxEffect:
	if actor == null or not is_instance_valid(actor):
		return null
	var e := _effect(VfxUtil.flat(actor.global_position), 0.5)
	if e == null:
		return null
	e.follow = actor
	e.hold_t = 0.5
	e.keep_while = keep
	var holder := Node3D.new()
	holder.position.y = 0.85
	e.add_child(holder)
	var mats: Array = []
	for i in 2:
		var m := VfxUtil.material("sweep", {"color": color, "energy": 2.0, "progress": 1.0, "tail": 1.0, "alpha": 0.8})
		var mi := VfxUtil.mesh_node(VfxUtil.arc_mesh(0.0, PI * 0.75, maxf(0.3, radius * 0.45), radius * 0.95, 20), m)
		mi.rotation.y = PI * i
		mi.position.y = 0.12 * i
		holder.add_child(mi)
		mats.append(m)
	var ring := VfxUtil.ground_node(radius, {"color": color, "energy": 1.4, "radius": 0.9, "thickness": 0.08, "gaps": 8.0})
	e.add_child(ring)
	var rm := ring.material_override as ShaderMaterial
	VfxUtil.particles(e, Color(0.55, 0.48, 0.4, 0.7), {"amount": 16, "lifetime": 0.6, "speed": Vector2(1.0, 2.5), "gravity": -1.0,
		"spread": 180.0, "direction": Vector3(1, 0.2, 0), "size": 0.35, "emit_radius": radius * 0.6, "additive": false,
		"damping": 2.0, "one_shot": false}, Vector3(0, 0.1, 0))
	e.updater = func(t: float, age: float) -> void:
		holder.rotation.y = -age * 14.0
		var a := clampf(age / 0.1, 0.0, 1.0)
		if t > 0.5:
			a = 1.0 - (t - 0.5) / 0.5
		for m in mats:
			(m as ShaderMaterial).set_shader_parameter("alpha", 0.8 * a)
		rm.set_shader_parameter("alpha", a)
		rm.set_shader_parameter("spin", age * 6.0)
	return e


## Self-buff flourish (Blood Rite): a swirling column of motes and a ground sigil.
static func empower(actor: Actor, color: Color) -> VfxEffect:
	if actor == null or not is_instance_valid(actor):
		return null
	var e := _effect(VfxUtil.flat(actor.global_position), 1.0)
	if e == null:
		return null
	e.follow = actor
	var sigil := VfxUtil.ground_node(1.6, {"color": color, "energy": 2.6, "radius": 0.75, "thickness": 0.1, "swirl": 1.0, "fill": 0.25, "fill_radius": 0.75})
	e.add_child(sigil)
	var sm := sigil.material_override as ShaderMaterial
	var cm := VfxUtil.material("beam", {"color": color, "energy": 2.0})
	var col := VfxUtil.mesh_node(VfxUtil.column_mesh(), cm)
	e.add_child(col)
	VfxUtil.particles(e, color, {"amount": 26, "lifetime": 0.8, "speed": Vector2(1.5, 3.5), "gravity": 2.0, "spread": 25.0,
		"size": 0.13, "emit_radius": 0.6}, Vector3(0, 0.1, 0))
	VfxUtil.flash_light(e, color, 2.5, 5.0, 0.6)
	e.updater = func(t: float, age: float) -> void:
		sm.set_shader_parameter("spin", age * 4.0)
		sm.set_shader_parameter("alpha", clampf(age / 0.1, 0.0, 1.0) * (1.0 - t))
		var r := lerpf(0.9, 0.3, t)
		col.scale = Vector3(r, lerpf(0.5, 2.8, _ease_out(clampf(age / 0.4, 0.0, 1.0))), r)
		cm.set_shader_parameter("alpha", (1.0 - t) * 0.8)
	return e


## Ice shell breaking when a freeze ends: glassy shards burst outward and fall.
static func ice_shatter(pos: Vector3, radius: float, height: float, color: Color) -> VfxEffect:
	var e := _effect(VfxUtil.flat(pos), 0.7)
	if e == null:
		return null
	var mat := VfxUtil.material("glass", {"color": color, "alpha": 0.7, "energy": 1.5})
	var shards: Array = []
	for i in 9:
		var a := TAU * float(i) / 9.0 + randf_range(-0.3, 0.3)
		var sh := VfxUtil.mesh_node(VfxUtil.spike_mesh(), mat)
		sh.position = Vector3(sin(a) * radius, randf_range(0.2, 0.8) * height, cos(a) * radius)
		sh.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var w := radius * randf_range(0.2, 0.35)
		sh.scale = Vector3(w, w * 2.5, w)
		e.add_child(sh)
		shards.append([sh, Vector3(sin(a), randf_range(0.5, 1.4), cos(a)) * randf_range(2.0, 4.0), Vector3(randf(), randf(), randf()) * 8.0])
	VfxUtil.particles(e, color.lerp(Color.WHITE, 0.5), {"amount": 14, "lifetime": 0.5, "speed": Vector2(1.5, 4.0), "gravity": -8.0,
		"spread": 180.0, "size": 0.1, "emit_radius": radius, "energy": 2.5}, Vector3(0, height * 0.5, 0))
	var last := {"age": 0.0}
	e.updater = func(t: float, age: float) -> void:
		var dt := age - float(last["age"])
		last["age"] = age
		for s in shards:
			var node: MeshInstance3D = s[0]
			var v: Vector3 = s[1]
			v.y -= 12.0 * dt
			s[1] = v
			node.position += v * dt
			node.rotation += (s[2] as Vector3) * dt
			if node.position.y < 0.05:
				node.position.y = 0.05
		mat.set_shader_parameter("alpha", 0.7 * (1.0 - t))
	return e


## Spell-casting sigil under an actor during a cast: a rotating rune ring in the skill colour that
## brightens toward the release and a few rising motes. Lasts `cast_time` (+ fade); cancel() it
## when the cast is interrupted.
static func cast_circle(actor: Actor, color: Color, cast_time: float) -> VfxEffect:
	if actor == null or not is_instance_valid(actor):
		return null
	var ct := maxf(0.1, cast_time)
	var e := _effect(VfxUtil.flat(actor.global_position), ct + 0.25)
	if e == null:
		return null
	e.follow = actor
	var size := actor.get_collision_radius() * 2.4 + 0.5
	var ring := VfxUtil.ground_node(size, {"color": color, "energy": 2.2, "radius": 0.82, "thickness": 0.07, "gaps": 9.0})
	e.add_child(ring)
	var inner := VfxUtil.ground_node(size, {"color": color, "energy": 1.6, "radius": 0.55, "thickness": 0.05, "gaps": 5.0, "fill": 0.12, "fill_radius": 0.55})
	e.add_child(inner)
	var rm := ring.material_override as ShaderMaterial
	var im := inner.material_override as ShaderMaterial
	VfxUtil.particles(e, color, {"amount": 10, "lifetime": 0.5, "speed": Vector2(0.6, 1.6), "gravity": 1.0, "spread": 15.0,
		"size": 0.08, "emit_radius": size * 0.55, "one_shot": false, "energy": 2.6}, Vector3(0, 0.1, 0))
	e.updater = func(_t: float, age: float) -> void:
		var k := clampf(age / ct, 0.0, 1.0)
		var a := clampf(age / 0.08, 0.0, 1.0) * (1.0 - clampf((age - ct) / 0.25, 0.0, 1.0))
		rm.set_shader_parameter("spin", age * 3.0)
		im.set_shader_parameter("spin", -age * 4.5)
		rm.set_shader_parameter("alpha", a * (0.5 + 0.5 * k))
		im.set_shader_parameter("alpha", a * (0.3 + 0.7 * k))
		rm.set_shader_parameter("radius", lerpf(0.95, 0.8, k))
	return e

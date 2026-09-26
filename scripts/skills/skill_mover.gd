class_name SkillMover
extends Node3D
## Moves the caster for movement skills (§8.3 "leap": arc to the planned landing point, AoE on
## landing; "charge": dash along a committed line, hitting everything touched, slam at the end).
## Lives in the World (not under the caster); the landing point was planned by
## SkillDeliveries.prepare() with CombatQuery.raycast_world + world.get_nearest_walkable, so the
## caster never ends inside a wall. The leap arc lifts the caster's visual root ("visuals" /
## "model" member or a child named "Model"), never the body (actors stay at y = 0).
## abort() (SkillRunner.cancel) stops the move where it is. Frees itself. OWNER: skills (wave 2).

var use: SkillUse = null
var mode := "leap"
var from := Vector3.ZERO
var to := Vector3.ZERO
var duration := 0.5
var elapsed := 0.0
var radius := 2.5
var height := 1.5
var landed := false
var aborted := false

var _caster: WeakRef = null
var _visual: WeakRef = null
var _visual_y := 0.0
var _trail: VfxEffect = null


static func leap(p_use: SkillUse, caster: Actor) -> SkillMover:
	var m := _make(p_use, caster, "leap")
	m.to = p_use.plan.get("landing", SkillUse.walkable(p_use.target_pos))
	m.duration = maxf(0.1, float(p_use.params.get("duration", 0.5)))
	m.radius = float(p_use.plan.get("radius", float(p_use.params.get("radius", 2.5)) * p_use.area_mult))
	var dist := CombatQuery.distance_xz(m.from, m.to)
	m.height = clampf(dist * 0.22, 0.6, 2.2) * clampf(caster.get_collision_radius() / 0.4, 0.8, 1.6)
	if VfxUtil.spawn(m, m.from) == null:
		return null
	VfxSpawn.dust_puff(m.from, 0.8)
	return m


static func charge(p_use: SkillUse, caster: Actor) -> SkillMover:
	var m := _make(p_use, caster, "charge")
	m.to = p_use.plan.get("end", p_use.origin + p_use.direction * 6.0)
	var speed := maxf(1.0, float(p_use.params.get("speed", 16.0)))
	m.duration = maxf(0.05, CombatQuery.distance_xz(m.from, m.to) / speed)
	m.radius = float(p_use.plan.get("radius", float(p_use.params.get("radius", 2.0)) * p_use.area_mult))
	m.height = 0.0
	if VfxUtil.spawn(m, m.from) == null:
		return null
	m._trail = VfxSpawn.charge_trail(caster, p_use.color)
	return m


static func _make(p_use: SkillUse, caster: Actor, p_mode: String) -> SkillMover:
	var m := SkillMover.new()
	m.name = "Mover_%s" % p_use.skill_id
	m.use = p_use
	m.mode = p_mode
	m._caster = weakref(caster)
	m.from = VfxUtil.flat(caster.global_position)
	var v := find_visual_root(caster)
	if v != null:
		m._visual = weakref(v)
		m._visual_y = v.position.y
	return m


## The node that shows an actor (lifted during leaps), or null.
static func find_visual_root(a: Actor) -> Node3D:
	for key in ["visuals", "model"]:
		var v: Variant = a.get(key)
		if v is Node3D and is_instance_valid(v) and (v as Node3D).get_parent() == a:
			return v as Node3D
	return a.get_node_or_null("Model") as Node3D


func get_caster() -> Actor:
	var c: Variant = _caster.get_ref() if _caster != null else null
	if c == null or not is_instance_valid(c):
		return null
	return c as Actor


func _physics_process(delta: float) -> void:
	if landed or aborted:
		queue_free()
		return
	var c := get_caster()
	if c == null or c.dead or not c.is_inside_tree():
		abort()
		queue_free()
		return
	elapsed += delta
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var e := t
	if mode == "leap":
		e = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65
	var pos := from.lerp(to, e)
	c.global_position = Vector3(pos.x, c.global_position.y, pos.z)
	c.velocity = Vector3.ZERO
	c.knockback_velocity = Vector3.ZERO
	global_position = pos
	_set_lift(4.0 * height * t * (1.0 - t))
	if mode == "charge":
		_charge_hits(c)
	if t >= 1.0:
		_land(c)


func _charge_hits(c: Actor) -> void:
	var center := VfxUtil.flat(c.global_position)
	for a in use.hostiles_in_radius(center, maxf(0.6, radius * 0.55)):
		if use.was_hit(a):
			continue
		use.deal_hit(a, {"origin": center})


func _land(c: Actor) -> void:
	landed = true
	_set_lift(0.0)
	c.global_position = Vector3(to.x, c.global_position.y, to.z)
	if _trail != null and is_instance_valid(_trail):
		_trail.end_now(0.5)
	var sid := String(use.skill.get("sfx", {}).get("impact", ""))
	if sid != "":
		Sfx.play(sid, to)
	if mode == "leap":
		VfxSpawn.leap_dust(to, radius, use.color)
	else:
		VfxSpawn.shockwave(to, use.direction, radius * 1.2, 360.0, use.color, 0.3)
	use.hit_area(to, radius, {"origin": to})


## Stop where the caster is now (no landing hit) and put its visual back on the ground.
func abort() -> void:
	if landed or aborted:
		return
	aborted = true
	_set_lift(0.0)
	if _trail != null and is_instance_valid(_trail):
		_trail.end_now(0.5)
	var c := get_caster()
	if c != null and c.is_inside_tree():
		var p := SkillUse.walkable(c.global_position)
		c.global_position = Vector3(p.x, c.global_position.y, p.z)


func _set_lift(y: float) -> void:
	if _visual == null:
		return
	var v: Variant = _visual.get_ref()
	if v != null and is_instance_valid(v):
		(v as Node3D).position.y = _visual_y + y


func _exit_tree() -> void:
	if not landed:
		_set_lift(0.0)

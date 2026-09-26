class_name SkillProjectile
extends Node3D
## One flying projectile of a skill use (§8.3 "projectile"): flies at y ≈ 1.1 along the XZ plane,
## sweeps its path each physics frame against hostiles (CombatQuery.hostiles_along_segment) and
## walls (CombatQuery.raycast_world), and handles pierce, chain, explosions (no separate direct
## hit), shotgun falloff, wandering (Spark), landing at the aim point (Venom Arrow's cloud) and max
## range. Frees itself; never holds the caster (SkillUse keeps a weak reference).
## OWNER: skills (wave 2).
##
##   SkillProjectile.launch(use, from, dir)   # added to the World by VfxUtil.spawn

## Default hit radius of model projectiles (arrows, bolts) around their flight line.
const DEFAULT_RADIUS := 0.25
## Range of one chain hop.
const CHAIN_RANGE := 9.0
## Wandering projectiles pick a new turn rate this often (s) within ±WANDER_TURN rad/s.
const WANDER_INTERVAL := 0.12
const WANDER_TURN := 4.0
## Shotgun: every projectile after the first on the same target deals 50% less.
const SHOTGUN_FALLOFF := 0.5

var use: SkillUse = null
var dir := Vector3.BACK
var speed := 20.0
var max_range := 20.0
var travelled := 0.0
var hit_radius := DEFAULT_RADIUS
var pierce_left := 0
var chain_left := 0
var explode_radius := 0.0
var explode_effectiveness := 1.0
var shotgun := false
var wander := false
var lifetime := 0.0
var ground_dot: Dictionary = {}
var fire_origin := Vector3.ZERO
var missile: VfxMissile = null
## Actors this projectile already hit (pierce / chain never hit one twice).
var own_hits: Dictionary = {}
var alive := true

var _age := 0.0
var _linger := 0.0
var _turn := 0.0
var _wander_timer := 0.0


## Launch a projectile of `use` from `from` (world position, flight height) along `p_dir`.
## Returns it, or null when there is no place to spawn it.
static func launch(p_use: SkillUse, from: Vector3, p_dir: Vector3) -> SkillProjectile:
	var pr := SkillProjectile.new()
	pr.name = "Projectile_%s" % p_use.skill_id
	pr._setup(p_use, from, p_dir)
	if VfxUtil.spawn(pr, from) == null:
		return null
	pr._first_check(from)
	return pr


func _setup(p_use: SkillUse, from: Vector3, p_dir: Vector3) -> void:
	use = p_use
	var p := use.params
	var caster := use.get_caster()
	dir = VfxUtil.flat(p_dir).normalized() if VfxUtil.flat(p_dir).length_squared() > 0.0001 else Vector3.BACK
	speed = float(p.get("speed", 20.0)) * use.projectile_speed_mult
	max_range = float(p.get("range", 20.0))
	if bool(p.get("land_at_target", false)):
		max_range = clampf(CombatQuery.distance_xz(use.origin, use.target_pos), 2.0, max_range)
	hit_radius = float(p.get("radius", DEFAULT_RADIUS))
	pierce_left = DamageCalc.get_pierce(caster, use.skill) if caster != null else int(p.get("pierce", 0))
	chain_left = DamageCalc.get_chain(caster, use.skill) if caster != null else int(p.get("chain", 0))
	explode_radius = float(p.get("explode_radius", 0.0)) * use.area_mult
	explode_effectiveness = float(p.get("explode_effectiveness", 1.0))
	shotgun = bool(p.get("shotgun", false))
	wander = bool(p.get("wander", false))
	lifetime = float(p.get("lifetime", 0.0)) * (use.duration_mult if wander else 1.0)
	ground_dot = p.get("ground_dot", {})
	fire_origin = VfxUtil.flat(from)
	var vfx: Dictionary = use.skill.get("vfx", {})
	var model := String(vfx.get("model", p.get("model", "")))
	var by_weapon: Dictionary = vfx.get("model_by_weapon", {})
	if by_weapon.has(use.weapon_type):
		model = String(by_weapon[use.weapon_type])
	if bool(vfx.get("orb", false)) or bool(p.get("orb", false)):
		model = ""
	missile = VfxMissile.build(vfx, model)
	add_child(missile)
	missile.face(dir)
	if wander:
		_turn = randf_range(-WANDER_TURN, WANDER_TURN)


## The spawn point may already be past a wall the caster is hugging: check caster -> spawn.
func _first_check(from: Vector3) -> void:
	var c := use.get_caster()
	if c == null or not c.is_inside_tree():
		return
	var base := VfxUtil.flat(c.global_position) + Vector3(0, from.y, 0)
	var hit := CombatQuery.raycast_world(base, from)
	if not hit.is_empty():
		global_position = (hit["position"] as Vector3) - dir * 0.1
		_on_wall(global_position, hit.get("normal", -dir))


func _physics_process(delta: float) -> void:
	if not alive:
		_linger -= delta
		if _linger <= 0.0:
			queue_free()
		return
	_age += delta
	if wander:
		_wander(delta)
		if lifetime > 0.0 and _age >= lifetime:
			_end_of_range(global_position)
			return
	var from := global_position
	var step := speed * delta
	var remaining := max_range - travelled
	var end_reached := false
	if step >= remaining:
		step = maxf(remaining, 0.0)
		end_reached = true
	var to := from + dir * step
	var wall := CombatQuery.raycast_world(from, to) if step > 0.0001 else {}
	var seg_end := to
	if not wall.is_empty():
		seg_end = (wall["position"] as Vector3) - dir * 0.08
		seg_end.y = from.y
	# Actors along the swept segment (nearest first).
	if seg_end.distance_squared_to(from) > 0.000001 or _age <= delta * 1.5:
		for a in _along_segment(from, seg_end):
			if not alive:
				return
			var id := a.get_instance_id()
			if own_hits.has(id):
				continue
			if use.was_hit(a) and not shotgun:
				continue
			if _hit_actor(a):
				return
	travelled += from.distance_to(seg_end)
	global_position = seg_end
	if not wall.is_empty():
		if wander:
			_bounce(wall.get("normal", -dir))
			return
		_on_wall(seg_end, wall.get("normal", -dir))
		return
	if end_reached:
		_end_of_range(seg_end)


## Hostiles whose collision circle touches the swept segment, nearest first. Uses a per-physics-
## frame cache of the hostile list shared by every projectile (big volleys stay cheap).
func _along_segment(from: Vector3, to: Vector3) -> Array[Actor]:
	var out: Array[Actor] = []
	var a2 := Vector2(from.x, from.z)
	var b2 := Vector2(to.x, to.z)
	var mid := (a2 + b2) * 0.5
	var reach := a2.distance_to(b2) * 0.5 + hit_radius
	var dists := {}
	for n in _hostiles(use.team):
		if not is_instance_valid(n):
			continue
		var act := n as Actor
		if act.dead or not act.is_inside_tree():
			continue
		var gp := act.global_position
		var p := Vector2(gp.x, gp.z)
		var cr := act.get_collision_radius()
		if p.distance_squared_to(mid) > (reach + cr) * (reach + cr):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(p, a2, b2)
		var r := hit_radius + cr
		if p.distance_squared_to(closest) <= r * r:
			out.append(act)
			dists[act] = closest.distance_squared_to(a2)
	if out.size() > 1:
		out.sort_custom(func(x: Actor, y: Actor) -> bool: return float(dists[x]) < float(dists[y]))
	return out


static var _cache_frame := -1
static var _cache: Dictionary = {}


## Hostiles of `team`, computed once per physics frame (untyped: entries may die / be freed later
## in the frame, callers check).
static func _hostiles(team: int) -> Array:
	var f := Engine.get_physics_frames()
	if f != _cache_frame:
		_cache.clear()
		_cache_frame = f
	if not _cache.has(team):
		var list: Array = []
		for a in CombatQuery.get_hostiles(team):
			list.append(a)
		_cache[team] = list
	return _cache[team]


## Returns true when the projectile stopped (or changed course) at this actor.
func _hit_actor(a: Actor) -> bool:
	var at := Vector3(a.global_position.x, global_position.y, a.global_position.z)
	own_hits[a.get_instance_id()] = true
	if explode_radius > 0.0:
		global_position = at - dir * minf(0.3, a.get_collision_radius())
		_explode(VfxUtil.flat(a.global_position))
		return true
	var eff := 1.0
	if shotgun and use.hit_count(a) > 0:
		eff = SHOTGUN_FALLOFF
	use.deal_hit(a, {"effectiveness": eff, "fire_origin": fire_origin, "origin": fire_origin})
	if not ground_dot.is_empty():
		global_position = at
		SkillGroundDot.spawn(use, VfxUtil.flat(at), ground_dot)
		_die()
		return true
	if chain_left > 0:
		var next := _chain_target(VfxUtil.flat(at))
		if next != null:
			chain_left -= 1
			var d := VfxUtil.flat(next.global_position) - VfxUtil.flat(at)
			dir = d.normalized() if d.length_squared() > 0.0001 else dir
			global_position = at
			travelled = 0.0
			max_range = CHAIN_RANGE + 1.0
			missile.face(dir)
			return true
	if pierce_left > 0:
		pierce_left -= 1
		return false
	global_position = at
	_die()
	return true


func _chain_target(from: Vector3) -> Actor:
	for cand in CombatQuery.hostiles_sorted_by_distance(use.team, from, CHAIN_RANGE):
		if own_hits.has(cand.get_instance_id()) or use.was_hit(cand):
			continue
		if CombatQuery.raycast_world(from, cand.global_position).is_empty():
			return cand
	return null


func _on_wall(pos: Vector3, _normal: Vector3) -> void:
	global_position = pos
	if explode_radius > 0.0:
		_explode(VfxUtil.flat(pos) - dir * 0.25)
		return
	if not ground_dot.is_empty():
		SkillGroundDot.spawn(use, VfxUtil.flat(pos) - dir * 0.6, ground_dot)
	else:
		VfxSpawn.impact_puff(pos, use.color)
	_die()


func _end_of_range(pos: Vector3) -> void:
	if explode_radius > 0.0:
		_explode(VfxUtil.flat(pos))
		return
	if not ground_dot.is_empty():
		SkillGroundDot.spawn(use, VfxUtil.flat(pos), ground_dot)
		VfxSpawn.impact_puff(pos - Vector3(0, 0.9, 0), use.color)
	elif wander:
		VfxSpawn.impact_puff(pos, use.color)
	_die()


## Explosion: every hostile in radius (the impacted one included) at explode_effectiveness; no
## separate direct hit. Actors already hit by this use are skipped (shared hit set).
func _explode(center: Vector3) -> void:
	VfxSpawn.explosion(center, explode_radius, use.color)
	var sid := String(use.skill.get("sfx", {}).get("impact", ""))
	if sid != "":
		Sfx.play(sid, center)
	use.hit_area(center, explode_radius, {"effectiveness": explode_effectiveness, "origin": center, "fire_origin": fire_origin})
	_die()


func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = WANDER_INTERVAL
		_turn = clampf(_turn + randf_range(-WANDER_TURN, WANDER_TURN), -WANDER_TURN, WANDER_TURN)
	dir = dir.rotated(Vector3.UP, _turn * delta).normalized()
	missile.face(dir)


func _bounce(normal: Vector3) -> void:
	var n := VfxUtil.flat(normal)
	if n.length_squared() < 0.0001:
		dir = -dir
	else:
		n = n.normalized()
		dir = (dir - 2.0 * dir.dot(n) * n).normalized()
	missile.face(dir)


func _die() -> void:
	if not alive:
		return
	alive = false
	_linger = missile.fizzle() if missile != null else 0.0
	if _linger <= 0.0:
		queue_free()

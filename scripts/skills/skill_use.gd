class_name SkillUse
extends RefCounted
## One use of a skill: the caster (held weakly: deliveries outlive it safely), the resolved skill
## dictionary, the team, the aim, the shared hit set of the use and the hit helpers every delivery
## goes through. Created by SkillRunner (or directly by tests / demos). OWNER: skills (wave 2).
##
##   var use := SkillUse.create(caster, SkillDB.get_resolved("fireball", caster), aim, target)
##   use.deal_hit(enemy, {"effectiveness": 0.6, "origin": pos})
##
## Hit set: `hit_set` maps actor instance ids to how often this use hit them. Every projectile of a
## use shares it (each target is hit at most once), shotgun skills count repeats (50% less each),
## secondary explosions exclude actors already hit. Sequence skills make one SkillUse per shot
## (fork()), sharing the use id (life on hit budget).

## Resolved skill dictionary (SkillDB.resolve_for_weapon). Shared: never mutate it.
var skill: Dictionary = {}
var skill_id: String = ""
var params: Dictionary = {}
var tags: PackedStringArray = PackedStringArray()
## Team of the caster at creation (hits target the other team even after the caster is freed).
var team: int = Actor.Team.PLAYER
var level: int = 1
## DamageCalc.next_use_id() of this use (life on hit counts at most 5 targets per use).
var use_id: int = 0
var weapon_type: String = ""
## Caster position when the use was created / refreshed (floor level).
var origin: Vector3 = Vector3.ZERO
## Aim point on the floor (y = 0).
var target_pos: Vector3 = Vector3.ZERO
## Flat unit direction from origin toward target_pos (caster forward when they coincide).
var direction: Vector3 = Vector3.FORWARD
## Main effect colour (skill vfx colour).
var color: Color = Color.WHITE
## Radius multiplier (area_of_effect) for area skills, 1 otherwise.
var area_mult: float = 1.0
## Skill duration multiplier (skill_duration).
var duration_mult: float = 1.0
var projectile_speed_mult: float = 1.0
## instance id -> number of times this use hit that actor.
var hit_set: Dictionary = {}
## Precomputed positions for telegraphs / committed effects (landing point, impact points...).
var plan: Dictionary = {}
## True once the aim is committed (windup skills: the telegraph shows where it lands).
var committed: bool = false
## Multiplier for internal timings of the use (sequence intervals): 1 at the skill's nominal
## speed, smaller with faster attacks / casts, larger while chilled. Set by SkillRunner.
var time_scale: float = 1.0

var _caster: WeakRef = null
var _target: WeakRef = null
## Hit rolled at creation, used when the caster has been freed before a delayed hit lands.
var _fallback: HitData = null


## A new use of `p_skill` (already resolved for the caster's weapon) by `caster` toward target_pos
## (or the target actor's position when it is valid).
static func create(caster: Actor, p_skill: Dictionary, p_target_pos: Vector3, p_target: Actor = null) -> SkillUse:
	var u := SkillUse.new()
	u.skill = p_skill
	u.skill_id = String(p_skill.get("id", ""))
	u.params = p_skill.get("params", {})
	u.tags = PackedStringArray(p_skill.get("tags", PackedStringArray()))
	u.use_id = DamageCalc.next_use_id()
	var vfx: Dictionary = p_skill.get("vfx", {})
	u.color = vfx.get("color", Color.WHITE)
	if caster != null and is_instance_valid(caster):
		u._caster = weakref(caster)
		u.team = caster.team
		u.level = caster.level
		u.weapon_type = String(caster.get_weapon().get("weapon_type", "unarmed")) if u.tags.has("attack") else ""
		u.area_mult = DamageCalc.get_area_mult(caster, p_skill) if u.tags.has("area") else 1.0
		u.duration_mult = DamageCalc.get_duration_mult(caster, p_skill)
		u.projectile_speed_mult = DamageCalc.get_projectile_speed_mult(caster, p_skill)
		u._fallback = DamageCalc.build_hit(caster, p_skill, {"use_id": u.use_id})
	else:
		u._fallback = DamageCalc.build_hit(null, p_skill, {"use_id": u.use_id})
	if p_target != null and is_instance_valid(p_target):
		u._target = weakref(p_target)
	u.set_aim(p_target_pos)
	return u


## Same skill and caster, fresh hit set (one shot of a sequence). Keeps the use id.
func fork() -> SkillUse:
	var u := SkillUse.new()
	u.skill = skill
	u.skill_id = skill_id
	u.params = params
	u.tags = tags
	u.team = team
	u.level = level
	u.use_id = use_id
	u.weapon_type = weapon_type
	u.origin = origin
	u.target_pos = target_pos
	u.direction = direction
	u.color = color
	u.area_mult = area_mult
	u.duration_mult = duration_mult
	u.projectile_speed_mult = projectile_speed_mult
	u.plan = plan.duplicate(true)
	u.committed = committed
	u.time_scale = time_scale
	u._caster = _caster
	u._target = _target
	u._fallback = _fallback
	return u


## The caster, or null once it has been freed (or died and was freed).
func get_caster() -> Actor:
	if _caster == null:
		return null
	var c: Variant = _caster.get_ref()
	if c == null or not is_instance_valid(c):
		return null
	return c as Actor


## The aimed actor, or null (freed / dead / never set).
func get_target() -> Actor:
	if _target == null:
		return null
	var t: Variant = _target.get_ref()
	if t == null or not is_instance_valid(t):
		return null
	var a := t as Actor
	if a == null or a.dead:
		return null
	return a


func set_target(t: Actor) -> void:
	_target = weakref(t) if t != null and is_instance_valid(t) else null


## Re-aim: refreshes origin (caster position), target_pos (the target actor's position when it is
## valid) and direction. Ignored once committed.
func set_aim(p_target_pos: Vector3) -> void:
	if committed:
		return
	var c := get_caster()
	if c != null:
		origin = VfxUtil.flat(c.global_position if c.is_inside_tree() else c.position)
	var t := get_target()
	if t != null and t.is_inside_tree():
		target_pos = VfxUtil.flat(t.global_position)
	else:
		target_pos = VfxUtil.flat(p_target_pos)
	var d := target_pos - origin
	d.y = 0.0
	if d.length_squared() > 0.0004:
		direction = d.normalized()
	elif c != null:
		var f := c.get_forward()
		f.y = 0.0
		direction = f.normalized() if f.length_squared() > 0.0001 else Vector3.BACK
	elif direction.length_squared() < 0.0001:
		direction = Vector3.BACK


## Distance from origin to target_pos clamped to max_range.
func aim_distance(max_range: float) -> float:
	return minf(CombatQuery.distance_xz(origin, target_pos), max_range)


## Hostile actors of this use within radius of center (collision radius included).
func hostiles_in_radius(center: Vector3, radius: float) -> Array[Actor]:
	return CombatQuery.hostiles_in_radius(team, center, radius)


func was_hit(a: Object) -> bool:
	return a != null and hit_set.has(a.get_instance_id())


func hit_count(a: Object) -> int:
	if a == null:
		return 0
	return int(hit_set.get(a.get_instance_id(), 0))


func mark_hit(a: Object) -> void:
	if a != null:
		hit_set[a.get_instance_id()] = hit_count(a) + 1


## A HitData for `target` (rolled fresh while the caster lives, else the creation-time roll scaled
## by opts.effectiveness). opts as DamageCalc.build_hit (use_id / target are filled in).
func build_hit(target: Actor, opts: Dictionary = {}) -> HitData:
	var o := opts.duplicate()
	o["use_id"] = use_id
	if target != null and is_instance_valid(target) and not o.has("target"):
		o["target"] = target
	if not o.has("knockback") and params.has("knockback"):
		o["knockback"] = float(params["knockback"])
	var c := get_caster()
	var hit: HitData
	if c != null:
		hit = DamageCalc.build_hit(c, skill, o)
	else:
		var f := float(o.get("effectiveness", 1.0)) * (1.0 + float(o.get("more", 0.0)) / 100.0)
		hit = _fallback.scaled(f)
		hit.knockback = float(o.get("knockback", 0.0))
		if bool(o.get("no_ailments", false)):
			hit.ailments.clear()
	if o.has("origin"):
		hit.origin = o["origin"]
	return hit


## Build a hit for `target`, mark it in the hit set, apply it (Actor.take_hit) and play the hit
## feedback (spark in the dominant damage colour, the skill's hit sound, hit_crit on crits).
## Returns the damage dealt (0 when evaded / blocked / invalid target).
func deal_hit(target: Actor, opts: Dictionary = {}) -> float:
	if target == null or not is_instance_valid(target) or target.dead or not target.is_inside_tree():
		return 0.0
	var hit := build_hit(target, opts)
	mark_hit(target)
	var dealt := target.take_hit(hit)
	if dealt > 0.0 and is_instance_valid(target):
		var pos := target.get_aim_point()
		var kind := hit.dominant_type()
		var c: Color = UIStyle.damage_color(kind)
		if kind == "physical":
			c = color.lerp(c, 0.5)
		VfxSpawn.hit_spark(pos, c, hit.is_crit)
		var sid := String(skill.get("sfx", {}).get("hit", ""))
		if sid != "" and not bool(opts.get("silent", false)):
			Sfx.play(sid, pos)
		if hit.is_crit:
			Sfx.play("hit_crit", pos)
	return dealt


## Hit every hostile within radius of center that this use has not hit yet (explosions, landings,
## novas). Returns the number of actors hit.
func hit_area(center: Vector3, radius: float, opts: Dictionary = {}, skip_hit: bool = true) -> int:
	var n := 0
	var o := opts.duplicate()
	if not o.has("origin"):
		o["origin"] = center
	for a in hostiles_in_radius(center, radius):
		if skip_hit and was_hit(a):
			continue
		deal_hit(a, o)
		n += 1
	return n


## The World for ground snapping, or null (tests without a world).
static func get_world() -> World:
	var w: Variant = GameState.world
	if w != null and is_instance_valid(w) and (w as Node).is_inside_tree():
		return w as World
	return null


## Nearest walkable floor point (the point itself without a World).
static func walkable(pos: Vector3) -> Vector3:
	var w := get_world()
	var p := VfxUtil.flat(pos)
	if w == null:
		return p
	return VfxUtil.flat(w.get_nearest_walkable(p))


## Furthest point from `from` toward `to` that is not behind a wall (stops `margin` before it).
static func clear_point(from: Vector3, to: Vector3, margin: float = 0.5) -> Vector3:
	var a := VfxUtil.flat(from)
	var b := VfxUtil.flat(to)
	var hit := CombatQuery.raycast_world(a + Vector3.UP, b + Vector3.UP)
	if hit.is_empty():
		return b
	var p: Vector3 = VfxUtil.flat(hit["position"])
	var d := p - a
	var len := d.length()
	if len <= margin:
		return a
	return a + d / len * (len - margin)

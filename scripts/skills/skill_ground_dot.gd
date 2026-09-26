class_name SkillGroundDot
extends Node3D
## A damaging ground area (§8.3 "ground_dot": Venom Arrow's caustic cloud). Every `tick` seconds
## each hostile inside takes `effectiveness` × the use's average hit per second as damage over
## time (Actor.take_damage_from(caster, dps × tick, type, true): resistances and shock apply, the
## caster gets the kill credit while it lives). Lasts `duration` × skill duration. Frees itself.
## OWNER: skills (wave 2).
##
## params: radius, duration, tick, effectiveness, optional "type" (default chaos for chaos skills,
## else the dominant damage type of the skill).

var use: SkillUse = null
var radius := 2.5
var duration := 3.0
var tick := 0.25
## Damage per second per hostile inside.
var dps := 0.0
var damage_type := "chaos"
var elapsed := 0.0
var _tick_timer := 0.0
var _ticks := 0


static func spawn(p_use: SkillUse, center: Vector3, p: Dictionary) -> SkillGroundDot:
	var g := SkillGroundDot.new()
	g.name = "GroundDot_%s" % p_use.skill_id
	g.use = p_use
	g.radius = float(p.get("radius", 2.5)) * p_use.area_mult
	g.duration = float(p.get("duration", 3.0)) * p_use.duration_mult
	g.tick = maxf(0.05, float(p.get("tick", 0.25)))
	g.damage_type = String(p.get("type", _default_type(p_use)))
	g.dps = average_hit(p_use) * float(p.get("effectiveness", 0.3)) * _dot_mult(p_use)
	if VfxUtil.spawn(g, VfxUtil.flat(center)) == null:
		return null
	var col: Color = UIStyle.damage_color(g.damage_type)
	if g.damage_type == "chaos" and p_use.tags.has("chaos"):
		col = p_use.color
	VfxSpawn.cloud(VfxUtil.flat(center), g.radius, col, g.duration)
	return g


## Average hit of the use's skill for its caster (the creation-time roll once it is gone).
static func average_hit(u: SkillUse) -> float:
	var c := u.get_caster()
	if c != null:
		return DamageCalc.get_average_hit(c, u.skill)
	return u._fallback.total() if u._fallback != null else 0.0


static func _dot_mult(u: SkillUse) -> float:
	var c := u.get_caster()
	if c == null:
		return 1.0
	return maxf(0.0, 1.0 + c.stats.inc("damage_over_time") / 100.0) * c.stats.more("damage_over_time")


static func _default_type(u: SkillUse) -> String:
	if u.tags.has("chaos"):
		return "chaos"
	var best := "physical"
	var best_v := -1.0
	var c := u.get_caster()
	var ranges := DamageCalc.get_damage_range(c, u.skill) if c != null else {}
	for t in ranges:
		var r: Vector2 = ranges[t]
		if r.x + r.y > best_v:
			best_v = r.x + r.y
			best = t
	return best


func _physics_process(delta: float) -> void:
	elapsed += delta
	_tick_timer += delta
	while _tick_timer >= tick - 0.00001 and elapsed <= duration + 0.0001:
		_tick_timer -= tick
		_do_tick()
	if elapsed >= duration:
		queue_free()


func _do_tick() -> void:
	_ticks += 1
	var amount := dps * tick
	if amount <= 0.0:
		return
	var src: Actor = use.get_caster()
	for a in CombatQuery.hostiles_in_radius(use.team, global_position, radius):
		a.take_damage_from(src, amount, damage_type, true)


## Number of damage ticks so far (tests).
func get_tick_count() -> int:
	return _ticks

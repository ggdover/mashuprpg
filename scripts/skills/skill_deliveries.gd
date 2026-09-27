class_name SkillDeliveries
extends RefCounted
## The delivery implementations of docs/ARCHITECTURE.md §8.3, dispatched by SkillRunner at the
## hit frame: instant ones live here (melee_arc, chain, blink, buff, summon, channel ticks), the
## ones that exist over time are nodes spawned into the World (SkillProjectile, SkillImpact,
## SkillNova, SkillMover, SkillSequence, SkillGroundDot). Also plans committed positions (landing
## points, impact points) and draws wind-up telegraphs. OWNER: skills (wave 2).
##
##   var use := SkillUse.create(caster, SkillDB.get_resolved("cleave", caster), aim)
##   SkillDeliveries.prepare(use)          # plan (landing / impact points)
##   SkillDeliveries.execute(use)          # run the delivery now
##
## Every delivery works without a World (tests / demos: effects go to the current scene) and with
## a freed caster for everything that outlives the hit frame.

## Hostiles closer than this to a melee swing's origin are hit even behind thin geometry.
const MELEE_LOS_FREE := 1.4
## Chain Lightning: an explicit target / the aim point may be this far from the cursor.
const CHAIN_AIM_SLACK := 2.5
## Max secondary explosions per melee use (Infernal Blow: one burst at the first enemy struck).
const MAX_MELEE_EXPLOSIONS := 1
## Projectile flight height (§8.3).
const PROJECTILE_HEIGHT := 1.1


# ================================================================== planning & telegraphs

## Fill use.plan with the committed positions of the delivery (called at use start and again at the
## hit frame unless the use is committed by a wind-up). Also fixes derived numbers (radii).
static func prepare(use: SkillUse) -> void:
	var p := use.params
	var delivery := String(use.skill.get("delivery", ""))
	var plan := {}
	match delivery:
		"melee_arc", "weapon_default":
			plan["radius"] = melee_radius(use)
			plan["angle"] = float(p.get("angle", 80.0))
		"nova":
			plan["radius"] = float(p.get("radius", 4.0)) * use.area_mult
		"channel_aoe":
			plan["radius"] = float(p.get("radius", 2.5)) * use.area_mult
		"aoe_target":
			var center := _aim_point(use, float(p.get("max_range", 18.0)))
			var pts: Array = [center]
			var delays: Array = [0.0]
			var n := maxi(1, int(p.get("count", 1)))
			var scatter := float(p.get("scatter", 3.0))
			for i in range(1, n):
				var a := TAU * float(i) / float(n - 1) + randf_range(-0.5, 0.5)
				pts.append(SkillUse.walkable(center + Vector3(sin(a), 0, cos(a)) * randf_range(scatter * 0.5, scatter)))
				delays.append(0.28 * i)
			plan["points"] = pts
			plan["delays"] = delays
			plan["radius"] = float(p.get("radius", 3.0)) * use.area_mult
		"rain":
			_plan_rain(use, plan)
		"leap":
			var to := use.origin + use.direction * use.aim_distance(float(p.get("max_range", 10.0)))
			plan["landing"] = SkillUse.walkable(SkillUse.clear_point(use.origin, to, 0.6))
			plan["radius"] = float(p.get("radius", 2.5)) * use.area_mult
		"charge":
			var dist := minf(float(p.get("max_range", 12.0)), CombatQuery.distance_xz(use.origin, use.target_pos) + 1.5)
			var end := SkillUse.clear_point(use.origin, use.origin + use.direction * maxf(dist, 1.0), 0.7)
			plan["end"] = end
			plan["distance"] = CombatQuery.distance_xz(use.origin, end)
			plan["radius"] = float(p.get("radius", 2.0)) * use.area_mult
		"blink":
			var dest := use.origin + use.direction * use.aim_distance(float(p.get("max_range", 12.0)))
			plan["destination"] = SkillUse.walkable(dest)
		"ground_dot":
			plan["center"] = _aim_point(use, float(p.get("max_range", 16.0)))
			plan["radius"] = float(p.get("radius", 2.5)) * use.area_mult
	use.plan = plan


## Seconds the delivery keeps the caster busy after the hit frame (leap flight, charge dash).
static func travel_time(use: SkillUse) -> float:
	var p := use.params
	match String(use.skill.get("delivery", "")):
		"leap":
			return float(p.get("duration", 0.5))
		"charge":
			return float(use.plan.get("distance", 0.0)) / maxf(1.0, float(p.get("speed", 16.0)))
	return 0.0


## Red wind-up telegraphs for the planned delivery that fill over `fill_time` s. Returns the
## VfxEffects (the runner cancels them when the use is interrupted).
static func telegraph(use: SkillUse, fill_time: float) -> Array:
	var out: Array = []
	var p := use.params
	match String(use.skill.get("delivery", "")):
		"melee_arc", "weapon_default":
			out.append(VfxTelegraph.cone(use.origin, use.direction, float(use.plan.get("radius", 3.0)), float(use.plan.get("angle", 90.0)), fill_time))
		"nova", "channel_aoe":
			out.append(VfxTelegraph.disc(use.origin, float(use.plan.get("radius", 4.0)), fill_time))
		"aoe_target", "rain":
			var pts: Array = use.plan.get("points", [])
			var delays: Array = use.plan.get("delays", [])
			var r := float(use.plan.get("impact_radius", use.plan.get("radius", 2.0)))
			for i in pts.size():
				var d := float(delays[i]) if i < delays.size() else 0.0
				out.append(VfxTelegraph.disc(pts[i], r, fill_time + d + float(p.get("delay", 0.0))))
		"leap":
			out.append(VfxTelegraph.disc(use.plan.get("landing", use.target_pos), float(use.plan.get("radius", 2.0)), fill_time + float(p.get("duration", 0.5))))
		"charge":
			var w := float(use.plan.get("radius", 2.0)) * 1.2
			out.append(VfxTelegraph.line(use.origin, use.direction, float(use.plan.get("distance", 6.0)) + w * 0.5, w, fill_time))
		"projectile", "sequence":
			out.append(VfxTelegraph.line(use.origin, use.direction, minf(float(p.get("range", 12.0)), 14.0), 1.0, fill_time))
		"ground_dot":
			out.append(VfxTelegraph.disc(use.plan.get("center", use.target_pos), float(use.plan.get("radius", 2.5)), fill_time))
	var list: Array = []
	for e in out:
		if e != null:
			list.append(e)
	return list


static func _aim_point(use: SkillUse, max_range: float) -> Vector3:
	var d := CombatQuery.distance_xz(use.origin, use.target_pos)
	var p := use.target_pos
	if d > max_range:
		p = use.origin + use.direction * max_range
	return SkillUse.walkable(p)


static func _plan_rain(use: SkillUse, plan: Dictionary) -> void:
	var p := use.params
	var n := maxi(1, int(p.get("impacts", 6)))
	var dur := float(p.get("duration", 0.5))
	var pts: Array = []
	var delays: Array = []
	var ir := float(p.get("impact_radius", 1.2)) * use.area_mult
	if String(p.get("pattern", "scatter")) == "line":
		var start := use.origin + use.direction * 1.6
		var end := SkillUse.clear_point(use.origin, use.origin + use.direction * use.aim_distance(float(p.get("max_range", 14.0))), 0.3)
		if CombatQuery.distance_xz(use.origin, end) < 5.0:
			end = SkillUse.clear_point(use.origin, use.origin + use.direction * 5.0, 0.3)
		for i in n:
			var f := float(i) / maxf(1.0, float(n - 1))
			pts.append(start.lerp(end, f))
			delays.append(dur * f)
		plan["radius"] = ir
	else:
		var center := _aim_point(use, float(p.get("max_range", 18.0)))
		var radius := float(p.get("radius", 3.0)) * use.area_mult
		# Stratified: one impact near the centre, the rest spread around evenly with jitter, so the
		# whole circle is covered.
		for i in n:
			var off := Vector3.ZERO
			if i > 0:
				var a := TAU * float(i) / float(n - 1) + randf_range(-0.35, 0.35)
				var r := radius * lerpf(0.45, 0.85, float(i % 2)) + randf_range(-0.2, 0.2) * radius
				off = Vector3(sin(a), 0.0, cos(a)) * clampf(r, 0.0, radius - ir * 0.3)
			pts.append(center + off)
			delays.append(randf_range(0.0, dur))
		plan["center"] = center
		plan["radius"] = radius
	plan["points"] = pts
	plan["delays"] = delays
	plan["impact_radius"] = ir


# ================================================================== dispatch

## Run the delivery of `use` now (at the hit frame). Returns the long-running node the use owns
## (SkillMover for leap / charge, SkillSequence) so the runner can abort it on cancel, else null.
static func execute(use: SkillUse) -> Variant:
	if use.plan.is_empty():
		prepare(use)
	var caster := use.get_caster()
	var delivery := String(use.skill.get("delivery", ""))
	var release_sfx := String(use.skill.get("sfx", {}).get("release", ""))
	if release_sfx != "":
		Sfx.play(release_sfx, use.origin)
	match delivery:
		"melee_arc", "weapon_default":
			melee_arc(use)
		"projectile":
			fire_projectiles(use, caster)
		"sequence":
			return SkillSequence.spawn(use)
		"aoe_target":
			aoe_target(use)
		"rain":
			rain(use)
		"nova":
			SkillNova.spawn(use, use.origin, float(use.plan.get("radius", 4.0)), float(use.params.get("expand_time", 0.3)))
		"chain":
			chain(use)
		"channel_aoe":
			channel_tick(use)
		"leap":
			if caster != null:
				return SkillMover.leap(use, caster)
		"charge":
			if caster != null:
				return SkillMover.charge(use, caster)
		"blink":
			if caster != null:
				blink(use, caster)
		"buff":
			buff(use, caster)
		"ground_dot":
			SkillGroundDot.spawn(use, use.plan.get("center", use.target_pos), use.params)
		"summon":
			summon(use, caster)
		_:
			push_warning("SkillDeliveries: unknown delivery '%s' (%s)" % [delivery, use.skill_id])
	return null


# ================================================================== melee

## Cone radius of a melee swing: params.radius, else weapon range + range_add (× area for area
## skills).
static func melee_radius(use: SkillUse) -> float:
	var p := use.params
	if p.has("radius"):
		return float(p["radius"]) * use.area_mult
	var reach := float(DamageCalc.UNARMED["range"])
	var c := use.get_caster()
	if c != null:
		reach = float(c.get_weapon().get("range", reach))
	return (reach + float(p.get("range_add", 0.0))) * use.area_mult


## Cone hit at the hit frame (+ swing arc, shockwave, secondary explosions).
static func melee_arc(use: SkillUse) -> Array[Actor]:
	var p := use.params
	var radius := float(use.plan.get("radius", melee_radius(use)))
	var angle := float(use.plan.get("angle", float(p.get("angle", 80.0))))
	var origin := use.origin
	var targets := CombatQuery.hostiles_in_cone(use.team, origin, use.direction, radius, angle)
	targets = _sorted_by_distance(targets, origin)
	var max_targets := int(p.get("max_targets", 0))
	var hit: Array[Actor] = []
	for a in targets:
		if max_targets > 0 and hit.size() >= max_targets:
			break
		if CombatQuery.distance_xz(origin, a.global_position) > MELEE_LOS_FREE and not CombatQuery.raycast_world(origin, a.global_position).is_empty():
			continue
		use.deal_hit(a, {"origin": origin})
		hit.append(a)
	_melee_visuals(use, origin, radius, angle, hit)
	var er := float(p.get("explode_radius", 0.0))
	if er > 0.0:
		var centers: Array = []
		# Burst at the struck enemies closest to where the player aimed.
		var by_aim: Array = hit.duplicate()
		by_aim.sort_custom(func(x: Actor, y: Actor) -> bool:
			return CombatQuery.distance_xz(use.target_pos, x.global_position) < CombatQuery.distance_xz(use.target_pos, y.global_position))
		for a in by_aim:
			if centers.size() >= MAX_MELEE_EXPLOSIONS:
				break
			if is_instance_valid(a):
				centers.append(VfxUtil.flat(a.global_position))
		if centers.is_empty():
			centers.append(SkillUse.clear_point(origin, origin + use.direction * minf(radius, 2.4), 0.4))
		var eff := float(p.get("explode_effectiveness", 1.0))
		for ctr in centers:
			secondary_explosion(use, ctr, er * use.area_mult, eff)
	return hit


## A secondary explosion of a melee use: hits every hostile in radius not hit by the use yet.
static func secondary_explosion(use: SkillUse, center: Vector3, radius: float, effectiveness: float) -> void:
	VfxSpawn.explosion(center, radius, use.color, 0.8)
	var sid := String(use.skill.get("sfx", {}).get("impact", ""))
	if sid != "":
		Sfx.play(sid, center)
	use.hit_area(center, radius, {"effectiveness": effectiveness, "origin": center, "no_ailments": false})


static func _melee_visuals(use: SkillUse, origin: Vector3, radius: float, angle: float, hit: Array[Actor]) -> void:
	var vfx: Dictionary = use.skill.get("vfx", {})
	var style := String(vfx.get("swing", "slash"))
	var c := use.color
	var caster := use.get_caster()
	var height_scale := 1.0
	if caster != null:
		height_scale = clampf(caster.get_collision_radius() / 0.4, 0.8, 2.2)
	if bool(vfx.get("shockwave", false)) or bool(use.params.get("shockwave", false)):
		VfxSpawn.swing(origin, use.direction, minf(radius, 2.6 * height_scale), minf(angle + 30.0, 140.0), c, "slam", 0.22)
		VfxSpawn.shockwave(origin + use.direction * 0.4, use.direction, radius, angle, c, clampf(radius * 0.06, 0.22, 0.45))
		var imp := String(use.skill.get("sfx", {}).get("impact", ""))
		if imp != "":
			Sfx.play(imp, origin + use.direction * minf(radius, 2.0))
	else:
		VfxSpawn.swing(origin, use.direction, radius, angle, c, style, 0.22 if style != "slam" else 0.26)
		if bool(vfx.get("impact", false)):
			VfxSpawn.ground_impact(origin + use.direction * maxf(0.8, radius * 0.75), c, 1.0 if hit.is_empty() else 1.3)


static func _sorted_by_distance(list: Array[Actor], from: Vector3) -> Array[Actor]:
	var out: Array[Actor] = list.duplicate()
	out.sort_custom(func(a: Actor, b: Actor) -> bool:
		return CombatQuery.distance_xz(from, a.global_position) < CombatQuery.distance_xz(from, b.global_position))
	return out


# ================================================================== projectiles

## Spawn params.count projectiles (+ additional_projectiles) fanned over params.spread degrees.
static func fire_projectiles(use: SkillUse, caster: Actor) -> Array:
	var p := use.params
	var n := DamageCalc.get_projectile_count(caster, use.skill) if caster != null else maxi(1, int(p.get("count", 1)))
	var spread := float(p.get("spread", 0.0))
	if use.extra_projectiles > 0:
		# Empowered: extra projectiles widen the fan so they stay as far apart as before.
		if spread > 0.0 and n > 1:
			spread *= float(n + use.extra_projectiles - 1) / float(n - 1)
		n += use.extra_projectiles
	if n > 1 and spread <= 0.0:
		spread = 10.0 * (n - 1)
	var out: Array = []
	var start := use.origin + Vector3(0, PROJECTILE_HEIGHT, 0)
	for i in n:
		var ang := 0.0
		if n > 1:
			ang = deg_to_rad(-spread * 0.5 + spread * float(i) / float(n - 1))
		var jitter := float(p.get("jitter", 0.0))
		if jitter > 0.0:
			ang += deg_to_rad(randf_range(-jitter, jitter))
		var dir := use.direction.rotated(Vector3.UP, ang)
		var pr := SkillProjectile.launch(use, start, dir)
		if pr != null:
			out.append(pr)
	return out


# ================================================================== areas

## Meteor-style delayed impacts at the planned points.
static func aoe_target(use: SkillUse) -> void:
	var p := use.params
	var pts: Array = use.plan.get("points", [use.target_pos])
	var delays: Array = use.plan.get("delays", [0.0])
	var radius := float(use.plan.get("radius", float(p.get("radius", 3.0)) * use.area_mult))
	var model := String(use.skill.get("vfx", {}).get("model", ""))
	var style := "meteor" if model == "proj_meteor" else "blast"
	for i in pts.size():
		var d := float(p.get("delay", 1.0)) + (float(delays[i]) if i < delays.size() else 0.0)
		SkillImpact.spawn(use, pts[i], radius, d, {
			"style": style,
			"telegraph": bool(p.get("telegraph", false)) or use.team == Actor.Team.ENEMY,
			"marker": use.team != Actor.Team.ENEMY,
			"shared_hits": false,
		})


## Rain of impacts at the planned points (each hostile is hit once per use).
static func rain(use: SkillUse) -> void:
	var p := use.params
	var pts: Array = use.plan.get("points", [])
	var delays: Array = use.plan.get("delays", [])
	var ir := float(use.plan.get("impact_radius", 1.2))
	var fall := float(p.get("delay", 0.0))
	var line := String(p.get("pattern", "scatter")) == "line"
	var model := String(use.skill.get("vfx", {}).get("model", ""))
	var style := "arrow" if model == "proj_arrow" else ("spike" if line else "blast")
	if not line and use.plan.has("center"):
		VfxSpawn.target_marker(use.plan["center"], float(use.plan.get("radius", 3.0)), use.color, fall + float(p.get("duration", 0.5)) + 0.1)
	for i in pts.size():
		var d := fall + (float(delays[i]) if i < delays.size() else 0.0)
		SkillImpact.spawn(use, pts[i], ir, d, {"style": style, "shared_hits": true, "telegraph": false, "marker": false, "fall": fall})


# ================================================================== chain

## Instant lightning: first target near the aim, then `chain` hops to the nearest unhit hostile
## within chain_range (line of sight required). Draws one jagged beam through all of them.
static func chain(use: SkillUse) -> Array[Actor]:
	var p := use.params
	var caster := use.get_caster()
	var max_range := float(p.get("range", 14.0))
	var hops := (DamageCalc.get_chain(caster, use.skill) if caster != null else int(p.get("chain", 3))) + use.extra_chains
	var chain_range := float(p.get("chain_range", 7.0))
	var start := use.origin + Vector3(0, 1.3, 0)
	if caster != null and caster.is_inside_tree():
		start = VfxUtil.flat(caster.global_position) + Vector3(0, 1.3, 0) + use.direction * 0.4
	var first := _chain_first_target(use, max_range)
	var points: Array = [start]
	var hit: Array[Actor] = []
	if first == null:
		var end := SkillUse.clear_point(use.origin, use.origin + use.direction * use.aim_distance(max_range), 0.2)
		if CombatQuery.distance_xz(use.origin, end) < 2.0:
			end = use.origin + use.direction * 2.0
		points.append(end + Vector3(0, 0.3, 0))
		VfxSpawn.beam(points, use.color, 0.25, 0.8)
		VfxSpawn.impact_puff(end + Vector3(0, 0.3, 0), use.color)
		return hit
	var cur: Actor = first
	var excluded: Array = []
	while cur != null:
		points.append(cur.get_aim_point())
		excluded.append(cur)
		hit.append(cur)
		use.deal_hit(cur, {"origin": use.origin})
		if hit.size() > hops:
			break
		var from := VfxUtil.flat(cur.global_position) if is_instance_valid(cur) else Vector3.ZERO
		cur = null
		for cand in CombatQuery.hostiles_sorted_by_distance(use.team, from, chain_range, excluded):
			if use.was_hit(cand):
				continue
			if not CombatQuery.raycast_world(from, cand.global_position).is_empty():
				continue
			cur = cand
			break
	VfxSpawn.beam(points, use.color, 0.32, 1.0)
	var imp := String(use.skill.get("sfx", {}).get("impact", ""))
	if imp != "":
		Sfx.play(imp, use.origin)
	return hit


static func _chain_first_target(use: SkillUse, max_range: float) -> Actor:
	var t := use.get_target()
	if t != null and t.team != use.team and t.is_inside_tree():
		if CombatQuery.distance_to_actor(use.origin, t) <= max_range and CombatQuery.raycast_world(use.origin, t.global_position).is_empty():
			return t
	# Nearest hostile to the cursor.
	var aim := use.target_pos
	if CombatQuery.distance_xz(use.origin, aim) > max_range:
		aim = use.origin + use.direction * max_range
	for a in CombatQuery.hostiles_sorted_by_distance(use.team, aim, CHAIN_AIM_SLACK):
		if CombatQuery.distance_to_actor(use.origin, a) <= max_range and CombatQuery.raycast_world(use.origin, a.global_position).is_empty():
			return a
	# Nearest hostile in a narrow cone toward the aim.
	for a in CombatQuery.hostiles_in_cone(use.team, use.origin, use.direction, max_range, 50.0):
		if CombatQuery.raycast_world(use.origin, a.global_position).is_empty():
			return a
	return null


# ================================================================== channel

## One tick of a channelled area skill around the caster: a fresh hit set and use id per tick.
static func channel_tick(use: SkillUse) -> int:
	var caster := use.get_caster()
	if caster == null or caster.dead:
		return 0
	use.hit_set.clear()
	use.use_id = DamageCalc.next_use_id()
	var center := VfxUtil.flat(caster.global_position)
	var radius := float(use.plan.get("radius", float(use.params.get("radius", 2.5)) * use.area_mult))
	var eff := float(use.params.get("effectiveness", 1.0))
	var n := 0
	for a in use.hostiles_in_radius(center, radius):
		use.deal_hit(a, {"effectiveness": eff, "origin": center, "silent": n >= 3})
		n += 1
	VfxSpawn.whirl_pulse(center, radius, use.color)
	return n


# ================================================================== movement

## Teleport to the planned walkable destination with flashes at both ends.
static func blink(use: SkillUse, caster: Actor) -> void:
	var from := VfxUtil.flat(caster.global_position)
	var dest: Vector3 = use.plan.get("destination", SkillUse.walkable(use.target_pos))
	VfxSpawn.blink(from, use.color, false)
	caster.global_position = Vector3(dest.x, caster.global_position.y, dest.z)
	caster.velocity = Vector3.ZERO
	VfxSpawn.blink(dest, use.color, true)
	Sfx.play("teleport", dest)


# ================================================================== buffs & summons

## Add the buff to the caster (and allies within params.radius) with the warcry / aura visuals.
static func buff(use: SkillUse, caster: Actor) -> Array[Actor]:
	var out: Array[Actor] = []
	if caster == null or caster.dead:
		return out
	var p := use.params
	var id := String(p.get("buff_id", use.skill_id))
	var data := {
		"name": String(p.get("buff_name", use.skill.get("name", id))),
		"mods": p.get("mods", []),
		"duration": float(p.get("duration", 5.0)) * use.duration_mult,
		"icon": use.skill_id,
	}
	var radius := float(p.get("radius", 0.0))
	var targets: Array[Actor] = [caster]
	if radius > 0.0:
		for a in CombatQuery.allies_in_radius(caster.team, caster.global_position, radius):
			if a != caster:
				targets.append(a)
	for a in targets:
		a.add_buff(id, data)
		VfxSpawn.buff_aura(a, id, use.color)
		out.append(a)
	var pos := VfxUtil.flat(caster.global_position)
	if use.tags.has("warcry"):
		VfxSpawn.warcry(pos, maxf(radius, 3.0), use.color)
	else:
		VfxSpawn.empower(caster, use.color)
	return out


## Monster summons via EnemyDB.spawn_enemy (tolerates a missing / stub EnemyDB).
static func summon(use: SkillUse, caster: Actor) -> Array:
	var out: Array = []
	if caster == null or caster.dead:
		return out
	var p := use.params
	var enemy_id := String(p.get("enemy_id", ""))
	var count := int(p.get("count", 1))
	var max_alive := int(p.get("max_alive", 0))
	var alive := _living_summons(caster)
	if max_alive > 0:
		count = mini(count, max_alive - alive.size())
	var w := SkillUse.get_world()
	var center := VfxUtil.flat(caster.global_position)
	for i in maxi(0, count):
		var a := TAU * float(i) / float(maxi(1, count)) + randf_range(-0.4, 0.4)
		var pos := center + Vector3(sin(a), 0, cos(a)) * float(p.get("radius", 2.5)) * randf_range(0.6, 1.0)
		if w != null:
			pos = VfxUtil.flat(w.random_walkable_near(pos, 1.0))
		VfxSpawn.summon_circle(pos, use.color)
		var e: Variant = EnemyDB.spawn_enemy(enemy_id, pos, caster.level, 0, [], w)
		if e != null and is_instance_valid(e):
			alive.append(weakref(e))
			out.append(e)
	caster.set_meta("skill_summons", alive)
	return out


static func _living_summons(caster: Actor) -> Array:
	var out: Array = []
	if caster.has_meta("skill_summons"):
		for r in caster.get_meta("skill_summons"):
			var e: Variant = (r as WeakRef).get_ref()
			if e != null and is_instance_valid(e) and not (e as Actor).dead:
				out.append(r)
	return out

extends "res://tests/unit/test_skills_util.gd"
## Area, movement and utility deliveries (§8.3): nova, chain lightning, meteor delay, rain hit
## sets, leap / blink / charge never ending in walls, buffs, ground clouds, summons.


func _hits(a: Actor) -> Array:
	var list: Array = []
	a.damaged.connect(func(amount: float, _c: bool, _s: Node) -> void: list.append(amount))
	return list


func test_frost_nova() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	var inside: Array = []
	for i in 4:
		var a := TAU * i / 4.0
		inside.append(target(Vector3(sin(a), 0, cos(a)) * 3.8))
	var out := target(Vector3(6.0, 0, 0))
	var hits := _hits(inside[0])
	assert_true(await use_and_wait(c, "frost_nova", Vector3(0, 0, 2), 0.4), "nova")
	for t in inside:
		assert_true(lost(t) > 0.0, "inside hit")
		assert_true((t as Actor).has_ailment("chill") or (t as Actor).is_frozen(), "chilled")
	assert_eq(hits.size(), 1, "hit once")
	assert_eq(lost(out), 0.0, "outside the radius")


func test_chain_lightning() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	var a := target(Vector3(0, 0, 6))
	var b := target(Vector3(4, 0, 8))
	var d := target(Vector3(8, 0, 9))
	var far := target(Vector3(-14, 0, 6))
	var ha := _hits(a)
	assert_true(await use_and_wait(c, "chain_lightning", Vector3(0.5, 0, 6.3), 0.1), "cast near a")
	assert_eq(ha.size(), 1, "first target hit once")
	assert_true(lost(b) > 0.0 and lost(d) > 0.0, "chained")
	assert_eq(lost(far), 0.0, "out of chain range")
	# 1 + chain targets at most.
	var many: Array = []
	for i in 8:
		many.append(target(Vector3(-6 + 1.5 * i, 0, -8)))
	var n0 := 0
	assert_true(await use_and_wait(c, "chain_lightning", Vector3(-6, 0, -8), 0.1), "cast at the row")
	for t in many:
		if lost(t) > 0.0:
			n0 += 1
	assert_eq(n0, 5, "first target + 4 chains")


func test_meteor_delay() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("staff", 10.0, 1.0), 20)
	var a := target(Vector3(0, 0, 8))
	var b := target(Vector3(2.5, 0, 8))
	assert_true(c.skill_runner.try_use("meteor", a.global_position, a), "meteor")
	await wait_until(func() -> bool: return count_nodes("SkillImpact") > 0, 2.0)
	await wait_time(0.6)
	assert_eq(lost(a), 0.0, "still falling")
	await wait_until(func() -> bool: return lost(a) > 0.0, 1.5)
	assert_true(lost(a) > 0.0 and lost(b) > 0.0, "impact radius")
	assert_true(c.skill_runner.get_cooldown_remaining("meteor") > 0.0, "cooldown")


func test_rain_each_enemy_once() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 10.0, 1.4), 10)
	var ts: Array = []
	var hs: Array = []
	for p in [Vector3(0, 0, 9), Vector3(1.0, 0, 9.5), Vector3(-1.0, 0, 8.6)]:
		var t := target(p)
		ts.append(t)
		hs.append(_hits(t))
	assert_true(await use_and_wait(c, "rain_of_arrows", Vector3(0, 0, 9), 1.2), "rain")
	for i in ts.size():
		assert_eq((hs[i] as Array).size(), 1, "target %d hit exactly once" % i)
	assert_eq(count_nodes("SkillImpact"), 0, "impacts freed")


func test_boss_spikes_line() -> void:
	await make_world()
	var e := make_caster(Actor.Team.ENEMY, Vector3.ZERO, weapon("monster", 10.0, 1.0), 10)
	var p := target(Vector3(0, 0, 7), 10000.0, Actor.Team.PLAYER)
	var side := target(Vector3(4, 0, 4), 10000.0, Actor.Team.PLAYER)
	var hp := _hits(p)
	assert_true(await use_and_wait(e, "m_boss_spikes", p.global_position, 0.8, p), "spikes")
	assert_eq(hp.size(), 1, "target on the line hit once")
	assert_eq(lost(side), 0.0, "off the line")


func test_leap_lands_and_hits() -> void:
	var w := await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.2), 10)
	var a := target(Vector3(0, 0, 7))
	assert_true(await use_and_wait(c, "leap_slam", a.global_position, 0.1), "leap")
	assert_true(CombatQuery.distance_xz(c.global_position, a.global_position) < 1.5, "landed at the target")
	assert_true(lost(a) > 0.0, "landing hit")
	# Max range 10 m.
	var start := c.global_position
	assert_true(await use_and_wait(c, "leap_slam", start + Vector3(0, 0, -30), 0.1), "long leap")
	assert_near(CombatQuery.distance_xz(start, c.global_position), 10.0, 0.6, "clamped to 10 m")
	# Never into / through a wall: the arena's perimeter wall is at |z| > 16.
	c.global_position = Vector3(0, 0, 12)
	await get_tree().physics_frame
	assert_true(await use_and_wait(c, "leap_slam", Vector3(0, 0, 30), 0.1), "leap at the wall")
	assert_true(w.is_walkable(c.global_position), "landed on floor")
	assert_true(c.global_position.z < 16.2, "stopped before the wall")


func test_blink() -> void:
	var w := await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	assert_true(await use_and_wait(c, "teleport", Vector3(5, 0, 0), 0.05), "short blink")
	assert_true(CombatQuery.distance_xz(c.global_position, Vector3(5, 0, 0)) < 1.2, "at the aim")
	c.skill_runner.reset_cooldowns()
	assert_true(await use_and_wait(c, "teleport", Vector3(5, 0, 40), 0.05), "into the wall")
	assert_true(w.is_walkable(c.global_position), "on floor")
	assert_true(CombatQuery.distance_xz(Vector3(5, 0, 0), c.global_position) <= 12.5, "max 12 m")


func test_charge() -> void:
	await make_world()
	var e := make_caster(Actor.Team.ENEMY, Vector3.ZERO, weapon("monster", 10.0, 1.0), 10)
	var p := target(Vector3(0, 0, 8), 10000.0, Actor.Team.PLAYER)
	var hp := _hits(p)
	assert_true(await use_and_wait(e, "m_boss_charge", p.global_position, 0.1, p), "charge")
	assert_true(e.global_position.z > 6.0, "dashed forward")
	assert_eq(hp.size(), 1, "hit once")


func test_war_cry_buffs_allies() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var ally := target(Vector3(3, 0, 0), 1000.0, Actor.Team.PLAYER)
	var far_ally := target(Vector3(14, 0, 0), 1000.0, Actor.Team.PLAYER)
	var foe := target(Vector3(-3, 0, 0))
	assert_true(await use_and_wait(c, "war_cry", Vector3(0, 0, 2), 0.05), "war cry")
	assert_true(c.has_buff("war_cry"), "caster buffed")
	assert_true(ally.has_buff("war_cry"), "ally buffed")
	assert_false(far_ally.has_buff("war_cry"), "far ally not")
	assert_false(foe.has_buff("war_cry"), "enemy not")
	assert_near(c.stats.inc("damage"), 30.0, 0.001, "30% increased damage")
	assert_near(c.stats.inc("attack_speed"), 10.0, 0.001, "10% increased attack speed")
	assert_eq(String(c.buffs["war_cry"]["icon"]), "war_cry", "icon = skill id")
	assert_near(float(c.buffs["war_cry"]["duration"]), 6.0, 0.001, "duration")
	var br := make_caster(Actor.Team.PLAYER, Vector3(0, 0, 5), weapon("wand", 5.0, 1.0), 20)
	assert_true(await use_and_wait(br, "blood_rite", Vector3(0, 0, 8), 0.05), "blood rite")
	assert_true(br.has_buff("blood_rite"), "self buff")
	assert_false(c.has_buff("blood_rite"), "self only")
	assert_near(br.stats.more("spell_damage"), 1.3, 0.001, "30% more spell damage")


func test_venom_cloud() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 12.0, 1.4), 15)
	var a := target(Vector3(0, 0, 8))
	var b := target(Vector3(1.6, 0, 8.4))
	var hb := _hits(b)
	assert_true(await use_and_wait(c, "venom_arrow", a.global_position, 0.1, a), "venom arrow")
	assert_true(a.has_ailment("poison"), "100% poison")
	assert_eq(count_nodes("SkillGroundDot"), 1, "cloud")
	await wait_time(1.0)
	assert_true(lost(b) > 0.0, "cloud damage over time")
	assert_eq(hb.size(), 0, "DoT, not hits")
	await wait_until(func() -> bool: return count_nodes("SkillGroundDot") == 0, 4.0)
	assert_eq(count_nodes("SkillGroundDot"), 0, "cloud expires")


func test_summon_tolerates_enemy_db() -> void:
	await make_world()
	var e := make_caster(Actor.Team.ENEMY, Vector3.ZERO, weapon("monster", 10.0, 1.0), 5)
	var before := GameState.world.enemies_root.get_child_count()
	assert_true(await use_and_wait(e, "m_summon", Vector3(0, 0, 4), 0.1), "summon")
	var spawned := GameState.world.enemies_root.get_child_count() - before
	if EnemyDB.get_def("skeleton_warrior").is_empty():
		assert_eq(spawned, 0, "stub EnemyDB spawns nothing")
	else:
		assert_eq(spawned, 2, "two skeletons")

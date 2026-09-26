extends "res://tests/unit/test_skills_util.gd"
## Melee arcs and projectiles (§8.3): cone hits, max targets, damage ranges, pierce, chain,
## explosions without a separate direct hit, shared hit sets, shotgun falloff, walls, max range,
## sequences.


func _hits(a: Actor) -> Array:
	var list: Array = []
	a.damaged.connect(func(amount: float, _c: bool, _s: Node) -> void: list.append(amount))
	return list


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.position = pos + Vector3(0, size.y * 0.5, 0)
	GameState.world.add_child(b)
	return b


func test_melee_cone() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 2.0), 10)
	var front := target(Vector3(0, 0, 1.8))
	var side := target(Vector3(1.8, 0, 0.3))
	var behind := target(Vector3(0, 0, -1.8))
	var far := target(Vector3(0, 0, 4.0))
	var ally := target(Vector3(-0.5, 0, 1.5), 1000.0, Actor.Team.PLAYER)
	assert_true(await use_and_wait(c, "basic_attack", front.global_position, 0.05), "swing")
	assert_near(lost(front), 10.0, 0.01, "front hit for the weapon damage")
	assert_eq(lost(side), 0.0, "outside the 80 degree arc")
	assert_eq(lost(behind), 0.0, "behind")
	assert_eq(lost(far), 0.0, "out of reach")
	assert_eq(lost(ally), 0.0, "allies are never hit")
	assert_true(await use_and_wait(c, "cleave", front.global_position, 0.05), "cleave")
	assert_near(lost(side), 13.0, 0.01, "cleave's wide arc hits the side (130%)")
	assert_eq(lost(behind), 0.0, "cleave still misses behind")


func test_melee_max_targets_and_secondary_explosion() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 10)
	var a := target(Vector3(0, 0, 1.5))
	var b := target(Vector3(0.6, 0, 1.6))
	var skill := {"id": "t_one", "tags": PackedStringArray(["attack", "melee"]), "damage_effectiveness": 1.0,
		"delivery": "melee_arc", "params": {"angle": 90.0, "max_targets": 1}, "vfx": {"color": Color.WHITE}, "sfx": {}}
	var use := SkillUse.create(c, skill, a.global_position)
	SkillDeliveries.execute(use)
	assert_true(lost(a) > 0.0, "nearest hit")
	assert_eq(lost(b), 0.0, "max_targets 1")
	# Infernal Blow: the explosion at the struck enemy hits others once, never the struck one again.
	var ha := _hits(a)
	var hb := _hits(b)
	var outside := target(Vector3(0, 0, 5.5))
	var hbe := _hits(outside)
	var near := target(Vector3(1.8, 0, 3.0))
	var hn := _hits(near)
	c.level = 12
	assert_true(await use_and_wait(c, "infernal_blow", a.global_position, 0.05, a), "infernal blow")
	assert_eq(ha.size(), 1, "struck enemy hit once")
	assert_eq(hb.size(), 1, "second enemy in the arc hit once")
	assert_eq(hn.size(), 1, "explosion hits a nearby enemy outside the arc")
	assert_eq(hbe.size(), 0, "explosion radius respected")
	assert_true(hn[0] < ha[0], "explosion deals 60%")


func test_projectile_hits_first_only() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 12.0, 1.4), 10)
	var a := target(Vector3(0, 0, 6))
	var b := target(Vector3(0, 0, 9))
	assert_true(await use_and_wait(c, "basic_attack", a.global_position, 0.5), "shot")
	assert_near(lost(a), 12.0, 0.01, "arrow damage")
	assert_eq(lost(b), 0.0, "no pierce")
	assert_true(await use_and_wait(c, "power_shot", a.global_position, 0.5), "power shot")
	assert_near(lost(b), 12.0 * 1.65, 0.01, "power shot pierces")


func test_crossbow_bolt_pierces_once() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("crossbow", 20.0, 1.0), 10)
	var a := target(Vector3(0, 0, 5))
	var b := target(Vector3(0, 0, 7))
	var d := target(Vector3(0, 0, 9))
	assert_true(await use_and_wait(c, "basic_attack", a.global_position, 0.5), "bolt")
	assert_true(lost(a) > 0.0 and lost(b) > 0.0, "pierces the first")
	assert_eq(lost(d), 0.0, "stops at the second")


func test_projectile_chain() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	var a := target(Vector3(0, 0, 5))
	var b := target(Vector3(4, 0, 6))
	var d := target(Vector3(8, 0, 7))
	var far := target(Vector3(-15, 0, 5))
	var skill := {"id": "t_chain", "tags": PackedStringArray(["spell", "projectile"]), "base_damage": {"fire": [10, 10]},
		"delivery": "projectile", "params": {"speed": 30.0, "range": 20.0, "chain": 2}, "vfx": {"color": Color.ORANGE, "orb": true}, "sfx": {}}
	var use := SkillUse.create(c, skill, a.global_position, a)
	SkillDeliveries.execute(use)
	await wait_until(func() -> bool: return lost(d) > 0.0, 2.0)
	assert_true(lost(a) > 0.0 and lost(b) > 0.0 and lost(d) > 0.0, "chained twice")
	assert_eq(lost(far), 0.0, "never the far one")


func test_explosion_no_direct_hit() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	var a := target(Vector3(0, 0, 8))
	var b := target(Vector3(1.4, 0, 8.6))
	var out := target(Vector3(4.5, 0, 8))
	var ha := _hits(a)
	var hb := _hits(b)
	assert_true(await use_and_wait(c, "fireball", a.global_position, 0.8, a), "fireball")
	assert_eq(ha.size(), 1, "impacted target hit once (explosion only)")
	assert_eq(hb.size(), 1, "neighbour hit by the explosion")
	assert_eq(lost(out), 0.0, "outside the radius")
	var r := DamageCalc.get_damage_range(c, SkillDB.get_skill("fireball"))
	assert_between(ha[0], r["fire"].x - 0.01, r["fire"].y + 0.01, "explosion damage in range")
	assert_eq(count_nodes("SkillProjectile"), 0, "projectile freed")


func test_split_arrow_shared_hit_set() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 10.0, 1.4), 10)
	var a := target(Vector3(0, 0, 3))
	var ha := _hits(a)
	var left := target(Vector3(-3.6, 0, 7.5))
	var right := target(Vector3(3.6, 0, 7.5))
	assert_true(await use_and_wait(c, "split_arrow", a.global_position, 0.6), "split arrow")
	assert_eq(ha.size(), 1, "one arrow per target")
	assert_true(lost(left) > 0.0 and lost(right) > 0.0, "the fan covers the sides")


func test_scatter_shot_shotgun() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("crossbow", 20.0, 1.0), 10)
	var a := target(Vector3(0, 0, 1.5))
	var ha := _hits(a)
	assert_true(await use_and_wait(c, "scatter_shot", a.global_position, 0.4), "scatter")
	assert_true(ha.size() >= 3, "several bolts hit point blank (%d)" % ha.size())
	ha.sort()
	assert_near(ha[ha.size() - 1], 20.0 * 0.65, 0.01, "first bolt full damage")
	assert_near(ha[0], 20.0 * 0.65 * 0.5, 0.01, "further bolts 50% less")


func test_walls_stop_projectiles() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 12.0, 1.4), 10)
	_wall(Vector3(0, 0, 4), Vector3(4, 3, 0.5))
	await get_tree().physics_frame
	var behind := target(Vector3(0, 0, 7))
	assert_true(await use_and_wait(c, "power_shot", behind.global_position, 0.5), "shot")
	assert_eq(lost(behind), 0.0, "wall blocks the arrow")
	assert_true(await use_and_wait(c, "basic_attack", behind.global_position, 0.5), "arrow")
	assert_eq(lost(behind), 0.0, "wall blocks")
	var mage := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 10)
	assert_true(await use_and_wait(mage, "fireball", behind.global_position, 0.6), "fireball")
	assert_eq(lost(behind), 0.0, "explodes on the wall, out of radius")
	# Hugging the wall: the spawn point is already past it.
	var hug := make_caster(Actor.Team.PLAYER, Vector3(0, 0, 3.55), weapon("bow", 12.0, 1.4), 10)
	assert_true(await use_and_wait(hug, "basic_attack", behind.global_position, 0.5), "point blank at the wall")
	assert_eq(lost(behind), 0.0, "never tunnels through")
	# Melee through a wall.
	var sw := make_caster(Actor.Team.PLAYER, Vector3(0, 0, 2.3), weapon("sword", 10.0, 1.0, 0.0, 2.7), 10)
	var close := target(Vector3(0, 0, 5.8))
	assert_true(await use_and_wait(sw, "ground_slam", close.global_position, 0.1), "slam at the wall")
	assert_eq(lost(close), 0.0, "melee cone blocked by the wall")


func test_max_range() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3(-12, 0, 0), weapon("bow", 12.0, 1.4), 10)
	var far := target(Vector3(9.5, 0, 0))
	assert_true(await use_and_wait(c, "basic_attack", far.global_position, 1.0), "shot")
	assert_eq(lost(far), 0.0, "beyond 20 m")
	assert_eq(count_nodes("SkillProjectile"), 0, "freed at max range")


func test_sequence_rapid_fire() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("crossbow", 20.0, 1.0), 10)
	var a := target(Vector3(0, 0, 6))
	var ha := _hits(a)
	assert_true(await use_and_wait(c, "rapid_fire", a.global_position, 0.6, a), "rapid fire")
	assert_eq(ha.size(), 5, "five bolts, each hits")
	for h in ha:
		assert_near(h, 20.0 * 0.5, 0.01, "bolt damage")


func test_spark_wanders_and_hits_once() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("wand", 5.0, 1.0), 12)
	var a := target(Vector3(0, 0, 4))
	var ha := _hits(a)
	assert_true(await use_and_wait(c, "spark", a.global_position, 1.8), "spark")
	assert_true(ha.size() <= 1, "each target hit at most once per cast")
	assert_eq(count_nodes("SkillProjectile"), 0, "sparks expire")


func test_ice_shot_converts_and_pierces() -> void:
	await make_world()
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow", 10.0, 1.4), 10)
	var ts: Array = []
	for i in 4:
		ts.append(target(Vector3(0, 0, 4 + 2 * i)))
	assert_true(await use_and_wait(c, "ice_shot", ts[0].global_position, 0.6), "ice shot")
	assert_true(lost(ts[0]) > 0.0 and lost(ts[1]) > 0.0 and lost(ts[2]) > 0.0, "pierces 2")
	assert_eq(lost(ts[3]), 0.0, "stops at the third")
	assert_true((ts[0] as Actor).has_ailment("chill"), "cold damage chills")

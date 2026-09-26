extends TestCase
## Enemy death (§12): XP via GameState.award_kill_xp (def.xp_mult × rarity xp), loot via
## LootSystem, Events.enemy_killed / boss_killed, collision off, die animation, corpse fade + free.
## OWNER: enemies.


func _loot_count() -> int:
	return get_tree().get_nodes_in_group("loot").size()


func _kill(e: Enemy, source: Node = null) -> void:
	e.take_damage_from(source, e.max_life * 5.0, "physical")


func test_kill_awards_xp() -> void:
	await make_world()
	var c := make_character("warrior")
	for spec in [["zombie", 0], ["skeleton_warrior", 1], ["ghoul", 2]]:
		var e := EnemyDB.spawn_enemy(String(spec[0]), Vector3(3, 0, 3), 1, int(spec[1]), ["berserker"] if int(spec[1]) > 0 else [])
		var before := c.xp + Balance.total_xp_for_level(c.level)
		var want := Balance.kill_xp(1, float(e.def["xp_mult"]) * float(Balance.monster_rarity(e.rarity)["xp"]), c.level)
		_kill(e)
		assert_true(e.dead, "dead")
		var gained := GameState.last_xp_award
		assert_between(float(gained), floorf(want) - 0.001, ceilf(want) + 0.001, "%s r%d xp (%.2f)" % [spec[0], spec[1], want])
		var after := c.xp + Balance.total_xp_for_level(c.level)
		assert_eq(after - before, gained, "character gained it")


func test_boss_xp_and_signals() -> void:
	await make_world()
	var c := make_character("sorcerer")
	var killed: Array = []
	var bosses: Array = []
	var cb1 := func(n: Node) -> void: killed.append(n)
	var cb2 := func(n: Node) -> void: bosses.append(n)
	Events.enemy_killed.connect(cb1)
	Events.boss_killed.connect(cb2)
	var z := EnemyDB.spawn_enemy("zombie", Vector3(-3, 0, 0), 2)
	_kill(z)
	assert_eq(killed, [z], "enemy_killed(self)")
	assert_eq(bosses.size(), 0, "no boss_killed for normal monsters")
	var b := EnemyDB.spawn_enemy("boss_gravebreaker", Vector3(4, 0, 4), 2)
	var want := Balance.kill_xp(2, 40.0, c.level)
	_kill(b)
	assert_eq(killed.size(), 2, "boss counts as an enemy kill")
	assert_eq(bosses, [b], "boss_killed(self)")
	assert_true(GameState.last_xp_award >= int(floorf(want)) or c.level > 1, "boss xp x40")
	Events.enemy_killed.disconnect(cb1)
	Events.boss_killed.disconnect(cb2)


func test_rare_drops_loot() -> void:
	await make_world()
	make_character()
	var before := _loot_count()
	var e := EnemyDB.spawn_enemy("zombie", Vector3(2, 0, -2), 3, 2)
	_kill(e)
	await get_tree().physics_frame
	var n := _loot_count() - before
	assert_true(n >= 3, "rare: items + 2 gold piles (%d)" % n)
	for gi in get_tree().get_nodes_in_group("loot"):
		assert_true((gi as Node3D).global_position.distance_to(e.global_position) < 6.0, "near the corpse")


func test_boss_drops_loot() -> void:
	await make_world()
	var before := _loot_count()
	var b := EnemyDB.spawn_enemy("boss_lich", Vector3(0, 0, 5), 4)
	_kill(b)
	await get_tree().physics_frame
	assert_true(_loot_count() - before >= 9, "boss: 4-6 items + 5 gold piles (%d)" % (_loot_count() - before))


func test_normal_drops_sometimes() -> void:
	await make_world()
	var before := _loot_count()
	for i in 30:
		var e := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(-12 + (i % 6) * 4, 0, -10 + (i / 6) * 4), 2)
		_kill(e)
	await get_tree().physics_frame
	var n := _loot_count() - before
	# 14% items + 20% gold per kill -> about 10 drops from 30 kills.
	assert_between(float(n), 2.0, 25.0, "normal monsters drop now and then (%d)" % n)


func test_summons_give_half_xp_and_no_loot() -> void:
	await make_world()
	var c := make_character()
	var necro := EnemyDB.spawn_enemy("necromancer", Vector3(0, 0, 0), 1)
	EnemyDB.register_summon_cast(necro, 1.0)
	var s := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(1.5, 0, 0), 1)
	assert_true(s.is_summon, "summon")
	var before := _loot_count()
	var want := Balance.kill_xp(1, 1.0 * Enemy.SUMMON_XP_MULT, c.level)
	_kill(s)
	await get_tree().physics_frame
	assert_eq(_loot_count(), before, "summons drop nothing")
	assert_between(float(GameState.last_xp_award), floorf(want) - 0.001, ceilf(want) + 0.001, "half xp")


func test_corpse_collision_and_fade() -> void:
	await make_world()
	var e := EnemyDB.spawn_enemy("zombie", Vector3(0, 0, 0), 2)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(8, 0, 8), 500.0)
	_kill(e, d)
	assert_true(e.dead, "dead")
	assert_eq(e.collision_layer, 0, "collision layer off")
	assert_eq(e.collision_mask, 0, "collision mask off")
	assert_false(e.is_in_group("enemies"), "left group enemies")
	assert_eq(e.state, Enemy.State.DEAD, "state dead")
	assert_eq(e.visuals.get_action(), "die", "die animation")
	assert_false(e.visuals.is_bar_visible(), "no life bar on corpses")
	assert_false(CombatQuery.get_hostiles(Actor.Team.PLAYER).has(e), "not targetable")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(e._collision.disabled, "shape disabled")
	var ref: WeakRef = weakref(e)
	var model: Node3D = e.visuals.model
	Engine.time_scale = 4.0
	var saw_fade := false
	for i in 200:
		await get_tree().physics_frame
		if ref.get_ref() == null:
			break
		for g in model.find_children("*", "GeometryInstance3D", true, false):
			if (g as GeometryInstance3D).transparency > 0.2:
				saw_fade = true
	Engine.time_scale = 1.0
	assert_true(saw_fade, "corpse fades out")
	assert_true(ref.get_ref() == null, "corpse freed after ~%.1f s" % (Enemy.CORPSE_TIME + Enemy.FADE_TIME))


func test_death_is_idempotent_and_quiet() -> void:
	await make_world()
	var killed := [0]
	var cb := func(_n: Node) -> void: killed[0] += 1
	Events.enemy_killed.connect(cb)
	var e := EnemyDB.spawn_enemy("ghoul", Vector3(0, 0, 0), 2)
	_kill(e)
	_kill(e)
	e.die(null)
	assert_eq(killed[0], 1, "killed once")
	assert_eq(e.take_damage(10.0, "fire"), 0.0, "corpses take no damage")
	Events.enemy_killed.disconnect(cb)


func test_killed_while_asleep_still_fades() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(8, 0, 8), 5000.0)
	var e := EnemyDB.spawn_enemy("zombie", Vector3(0, 0, 0), 2)
	e.aggro(d)
	EnemyDB.apply_sleep(Vector3(80, 0, 0))
	assert_true(e.sleeping and not e.is_physics_processing(), "asleep while fighting")
	_kill(e, d)
	assert_true(e.dead, "dead")
	assert_false(e.sleeping, "a corpse is awake")
	assert_true(e.visible and e.is_physics_processing(), "visible + processing")
	var ref: WeakRef = weakref(e)
	Engine.time_scale = 4.0
	for i in 200:
		await get_tree().physics_frame
		if ref.get_ref() == null:
			break
	Engine.time_scale = 1.0
	assert_true(ref.get_ref() == null, "corpse freed")

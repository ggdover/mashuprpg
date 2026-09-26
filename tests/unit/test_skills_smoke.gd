extends "res://tests/unit/test_skills_util.gd"
## Every skill (player and monster) runs start to finish against dummies without script errors,
## and everything it spawned frees itself.


func test_player_skills_a() -> void:
	await _run_player_skills(SkillDB.PLAYER_SKILL_IDS.slice(0, 8))


func test_player_skills_b() -> void:
	await _run_player_skills(SkillDB.PLAYER_SKILL_IDS.slice(8, 16))


func test_player_skills_c() -> void:
	await _run_player_skills(SkillDB.PLAYER_SKILL_IDS.slice(16))


func _run_player_skills(ids: Array) -> void:
	await make_world()
	Engine.time_scale = 3.0
	for id in ids:
		var w := _weapon_for(id)
		var c := make_caster(Actor.Team.PLAYER, Vector3(-4, 0, 0), w, 30)
		var t1 := target(Vector3(2, 0, 0))
		var t2 := target(Vector3(3, 0, 1.2))
		var ok := await use_and_wait(c, id, t1.global_position, 0.0, t1)
		assert_true(ok, "%s could start" % id)
		if id == "whirlwind":
			await wait_time(0.6)
			c.skill_runner.release(id)
		await wait_time(1.4)
		assert_false(c.skill_runner.is_busy(), "%s finished" % id)
		c.queue_free()
		t1.queue_free()
		t2.queue_free()
		await get_tree().physics_frame
	await wait_time(3.0)
	Engine.time_scale = 1.0
	var left := GameState.world.dynamic_root.get_child_count()
	assert_eq(left, 0, "every effect / delivery node freed itself")


func test_every_monster_skill_runs() -> void:
	await make_world()
	Engine.time_scale = 3.0
	for id in SkillDB.MONSTER_SKILL_IDS:
		var c := make_caster(Actor.Team.ENEMY, Vector3(-3, 0, 0), {"weapon_type": "monster", "phys_min": 8.0, "phys_max": 12.0, "added": {}, "attack_speed": 1.0, "crit_chance": 5.0, "range": 1.8, "two_handed": false}, 10)
		var reach := clampf(SkillDB.get_skill_range(id, c) * 0.6, 1.2, 6.0)
		var p := target(Vector3(-3 + reach, 0, 0), 100000.0, Actor.Team.PLAYER)
		var ok := await use_and_wait(c, id, p.global_position, 0.0, p)
		assert_true(ok, "%s could start" % id)
		await wait_time(2.0)
		assert_false(c.skill_runner.is_busy(), "%s finished" % id)
		if not SkillDB.get_skill(id)["delivery"] in ["summon", "buff"]:
			assert_true(lost(p) > 0.0, "%s damaged the target" % id)
		c.queue_free()
		p.queue_free()
		await get_tree().physics_frame
	await wait_time(3.0)
	Engine.time_scale = 1.0
	assert_eq(GameState.world.dynamic_root.get_child_count(), 0, "every effect / delivery node freed itself")


func _weapon_for(id: String) -> Dictionary:
	var types: Array = SkillDB.get_skill(id).get("weapon_types", [])
	if types.has("bow"):
		return weapon("bow", 12.0, 1.4)
	if types.has("crossbow"):
		return weapon("crossbow", 16.0, 1.0)
	return weapon("sword", 10.0, 1.4)

extends "res://tests/unit/test_skills_util.gd"
## Performance smoke test: stepping 100 projectiles (hit tests, walls, visuals) by hand stays well
## inside a frame budget (script time, headless).


func test_many_projectiles_budget() -> void:
	await make_world({"id": "arena", "name": "Arena", "level": 10, "size": 20})
	for i in 12:
		target(Vector3(-11 + 2 * i, 0, 14), 100000.0, Actor.Team.PLAYER)
	var casters: Array = []
	for i in 30:
		casters.append(make_caster(Actor.Team.ENEMY, Vector3(-15 + i, 0, -8), weapon("monster", 10.0, 1.0), 10))
	var skill := SkillDB.get_skill("m_boss_volley")
	var projectiles: Array = []
	for i in 15:
		var c: Caster = casters[i]
		var use := SkillUse.create(c, skill, Vector3(c.position.x, 0, 14))
		projectiles.append_array(SkillDeliveries.fire_projectiles(use, c))
	assert_eq(projectiles.size(), 105, "105 fireballs")
	for p in projectiles:
		(p as Node).set_physics_process(false)
		((p as SkillProjectile).missile as Node).set_process(false)
	await get_tree().process_frame
	var t_phys := 0
	var t_vis := 0
	var steps := 30
	for s in steps:
		var t0 := Time.get_ticks_usec()
		for p in projectiles:
			if is_instance_valid(p):
				(p as SkillProjectile)._physics_process(1.0 / 60.0)
		var t1 := Time.get_ticks_usec()
		for p in projectiles:
			if is_instance_valid(p) and is_instance_valid((p as SkillProjectile).missile):
				(p as SkillProjectile).missile._process(1.0 / 60.0)
		t_vis += Time.get_ticks_usec() - t1
		t_phys += t1 - t0
		await get_tree().process_frame
	var ms_phys := t_phys / 1000.0 / steps
	var ms_vis := t_vis / 1000.0 / steps
	print("[perf] 105 projectiles: flight + hit tests %.2f ms/step, visuals %.2f ms/frame" % [ms_phys, ms_vis])
	assert_true(ms_phys < 4.0, "projectile step under 4 ms (%.2f)" % ms_phys)
	assert_true(ms_vis < 4.0, "missile visuals under 4 ms (%.2f)" % ms_vis)
	for p in projectiles:
		if is_instance_valid(p):
			(p as Node).queue_free()

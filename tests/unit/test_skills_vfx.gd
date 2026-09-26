extends "res://tests/unit/test_skills_util.gd"
## VFX: StatusVisuals (all six ailments, attach / detach), every VfxSpawn effect frees itself,
## light / particle budgets, telegraphs and missiles.


func test_status_visuals_attach_detach() -> void:
	await make_world()
	var d := target(Vector3.ZERO)
	var sv := StatusVisuals.attach(d)
	assert_not_null(sv, "attached")
	assert_true(is_same(StatusVisuals.attach(d), sv), "attach twice -> same instance")
	var data := {
		"ignite": {"dps": 5.0, "duration": 5.0}, "bleed": {"dps": 5.0, "duration": 5.0}, "poison": {"dps": 5.0, "duration": 5.0},
		"shock": {"effect": 0.2, "duration": 5.0}, "chill": {"effect": 0.2, "duration": 5.0}, "freeze": {"duration": 5.0},
	}
	for k in data:
		d.apply_ailment(k, data[k])
		assert_true(sv.has_visual(k), "%s shown" % k)
	assert_eq(sv.get_active_kinds().size(), 6, "all six")
	await wait_time(0.2)
	d.remove_ailment("freeze")
	assert_false(sv.has_visual("freeze"), "freeze removed")
	assert_true(sv.has_visual("ignite"), "others kept")
	d.clear_ailments()
	assert_eq(sv.get_active_kinds().size(), 0, "cleared")
	d.apply_ailment("ignite", data["ignite"])
	d.die(null)
	assert_false(sv.has_visual("ignite"), "death clears")
	var cb := Callable(sv, "_on_ailment_changed")
	sv.detach()
	assert_false(d.ailment_changed.is_connected(cb), "disconnected")
	await get_tree().process_frame
	assert_false(is_instance_valid(sv), "detached and freed")


func test_status_visuals_sync_existing() -> void:
	await make_world()
	var d := target(Vector3.ZERO)
	d.apply_ailment("shock", {"effect": 0.2, "duration": 5.0})
	var sv := StatusVisuals.attach(d)
	await get_tree().process_frame
	assert_true(sv.has_visual("shock"), "existing ailment shown at attach")
	d.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(sv), "freed with the actor")


func test_effects_free_themselves() -> void:
	var w := await make_world()
	var d := target(Vector3(2, 0, 2), 1000.0, Actor.Team.PLAYER)
	d.add_buff("x", {"name": "X", "mods": [], "duration": 0.4, "icon": ""})
	var c := SkillDB.C_FIRE
	var fx: Array = [
		VfxSpawn.explosion(Vector3.ZERO, 2.2, c), VfxSpawn.hit_spark(Vector3(0, 1, 0), c, true), VfxSpawn.impact_puff(Vector3(0, 1, 0), c),
		VfxSpawn.swing(Vector3.ZERO, Vector3.BACK, 2.5, 80.0, c, "slash"), VfxSpawn.swing(Vector3.ZERO, Vector3.BACK, 2.5, 80.0, c, "stab"),
		VfxSpawn.shockwave(Vector3.ZERO, Vector3.BACK, 6.0, 50.0, c), VfxSpawn.nova(Vector3.ZERO, 4.5, SkillDB.C_COLD, 0.3, "frost"),
		VfxSpawn.nova(Vector3.ZERO, 7.0, c, 0.7, "fire"), VfxSpawn.beam([Vector3(0, 1, 0), Vector3(3, 1, 3), Vector3(6, 1, 0)], SkillDB.C_LIGHT),
		VfxSpawn.blink(Vector3.ZERO, SkillDB.C_ARCANE, true), VfxSpawn.leap_dust(Vector3.ZERO, 2.5, c), VfxSpawn.warcry(Vector3.ZERO, 8.0, c),
		VfxSpawn.buff_aura(d, "x", c), VfxSpawn.cloud(Vector3.ZERO, 2.5, SkillDB.C_POISON, 0.5), VfxSpawn.summon_circle(Vector3.ZERO, c),
		VfxSpawn.spikes(Vector3.ZERO, 1.2, c), VfxSpawn.target_marker(Vector3.ZERO, 3.0, c, 0.5), VfxSpawn.level_up(d),
		VfxSpawn.ground_impact(Vector3.ZERO, c), VfxSpawn.shock_ring(Vector3.ZERO, 3.0, c), VfxSpawn.arrow_landing(Vector3.ZERO, Vector3.DOWN, c),
		VfxSpawn.dust_puff(Vector3.ZERO), VfxSpawn.charge_trail(d, c), VfxSpawn.muzzle_flash(Vector3(0, 1, 0), c),
		VfxSpawn.whirl_pulse(Vector3.ZERO, 2.6, c), VfxSpawn.empower(d, c), VfxSpawn.ice_shatter(Vector3.ZERO, 0.4, 1.8, SkillDB.C_COLD),
		VfxTelegraph.disc(Vector3.ZERO, 3.0, 0.5), VfxTelegraph.cone(Vector3.ZERO, Vector3.BACK, 4.0, 60.0, 0.5),
		VfxTelegraph.line(Vector3.ZERO, Vector3.BACK, 8.0, 2.0, 0.5),
	]
	for e in fx:
		assert_not_null(e, "spawned")
	assert_true(VfxUtil.light_count() <= VfxUtil.MAX_VFX_LIGHTS, "light budget")
	var tr := fx[22] as VfxEffect
	tr.end_now(0.5)
	await wait_until(func() -> bool: return w.dynamic_root.get_child_count() == 0, 3.5)
	assert_eq(w.dynamic_root.get_child_count(), 0, "all effects freed")
	await get_tree().process_frame
	assert_eq(VfxUtil.light_count(), 0, "light slots released")


func test_light_and_particle_budget() -> void:
	var w := await make_world()
	for i in 20:
		VfxSpawn.explosion(Vector3(i * 0.5, 0, 0), 2.0, SkillDB.C_FIRE)
	assert_eq(VfxUtil.light_count(), VfxUtil.MAX_VFX_LIGHTS, "lights capped")
	var lights := w.dynamic_root.find_children("*", "OmniLight3D", true, false).size()
	assert_eq(lights, VfxUtil.MAX_VFX_LIGHTS, "no more omni lights than the cap")
	assert_true(VfxUtil.particle_count() <= VfxUtil.MAX_PARTICLE_SYSTEMS, "particle systems capped")
	for i in 40:
		VfxSpawn.hit_spark(Vector3(0, 1, 0), Color.WHITE)
	assert_true(VfxSpawn._spark_count <= VfxSpawn.MAX_SPARKS, "sparks capped")
	await wait_until(func() -> bool: return w.dynamic_root.get_child_count() == 0, 3.0)
	await get_tree().process_frame
	assert_eq(VfxUtil.light_count(), 0, "released")


func test_telegraph_cancel() -> void:
	var w := await make_world()
	var t := VfxTelegraph.disc(Vector3.ZERO, 3.0, 5.0)
	await wait_time(0.2)
	t.cancel(0.1)
	await wait_time(0.3)
	assert_false(is_instance_valid(t), "cancelled telegraph freed")
	assert_eq(w.dynamic_root.get_child_count(), 0, "nothing left")


func test_missile_visuals() -> void:
	await make_world()
	for entry in [[{"color": Color.ORANGE, "orb": true, "light": true}, ""], [{"color": Color.WHITE}, "proj_arrow"],
			[{"color": Color.CYAN, "glow": true}, "proj_ice_spear"], [{"color": Color.WHITE}, "proj_missing_model"]]:
		var holder := Node3D.new()
		GameState.world.add_dynamic(holder)
		var m := VfxMissile.build(entry[0], entry[1])
		holder.add_child(m)
		m.face(Vector3(1, -0.5, 0))
		for i in 5:
			holder.global_position += Vector3(0.5, 0, 0)
			await get_tree().process_frame
		var linger := m.fizzle()
		assert_true(linger >= 0.0, "fizzle")
		assert_false(m.heading.visible, "hidden")
		holder.queue_free()
	await get_tree().process_frame
	assert_eq(VfxUtil.light_count(), 0, "missile light released")


func test_effects_without_world() -> void:
	# Demos / tests without a World: effects go to the current scene and still free themselves.
	var e := VfxSpawn.hit_spark(Vector3(0, 1, 0), Color.WHITE)
	assert_not_null(e, "spawned without a world")
	var ref: WeakRef = weakref(e)
	await wait_until(func() -> bool: return ref.get_ref() == null, 1.5)
	assert_true(ref.get_ref() == null, "freed")

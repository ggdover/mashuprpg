extends TestCase
## Enemy visuals: model + carried weapons, rarity look (rim, ring, size), life bar rules (after the
## first damage; always for rares/bosses), rarity-coloured names, status visuals, hit flash,
## action animations with fallbacks. OWNER: enemies.


func test_model_and_parts() -> void:
	await make_world()
	var e := EnemyDB.spawn_enemy("skeleton_archer", Vector3(0, 0, 0), 3)
	assert_not_null(e.visuals, "visuals")
	assert_not_null(e.visuals.model, "model")
	assert_false(e.visuals.model.get_meta("placeholder", false), "real char_skeleton model")
	assert_not_null(e.visuals.anim, "animation player")
	assert_true(e.visuals.model.find_child("Carried_grip_r", true, false) != null, "bow in hand")
	assert_true(e.visuals.model.find_child("Carried_chest", true, false) != null, "quiver on the back")
	assert_not_null(e.get_node_or_null("StatusVisuals"), "StatusVisuals attached")
	var b := EnemyDB.spawn_enemy("boss_gravebreaker", Vector3(6, 0, 6), 3)
	assert_not_null(Assets.find_part(b.visuals.model, "Weapon"), "boss weapon is part of its mesh")
	assert_true(b.get_height() > 2.6, "bosses are big")


func test_life_bar_rules() -> void:
	await make_world()
	var n := EnemyDB.spawn_enemy("zombie", Vector3(0, 0, 0), 3, 0)
	var m := EnemyDB.spawn_enemy("zombie", Vector3(3, 0, 0), 3, 1, ["hasted"])
	var r := EnemyDB.spawn_enemy("zombie", Vector3(-3, 0, 0), 3, 2, ["hasted", "fiery"])
	var b := EnemyDB.spawn_enemy("boss_lich", Vector3(0, 0, 6), 3)
	assert_false(n.visuals.is_bar_visible(), "normal: no bar before damage")
	assert_false(m.visuals.is_bar_visible(), "magic: no bar before damage")
	assert_true(r.visuals.is_bar_visible(), "rare: always")
	assert_true(b.visuals.is_bar_visible(), "boss: always")
	n.take_damage(1.0, "physical")
	assert_true(n.visuals.is_bar_visible(), "normal: bar after damage")
	var lbl := n.find_child("NameLabel", true, false) as Label3D
	assert_false(lbl.visible, "normal: no name")
	var ml := m.find_child("NameLabel", true, false) as Label3D
	assert_true(ml.visible and ml.text.contains("Zombie"), "magic name: %s" % ml.text)
	assert_true(ml.modulate.is_equal_approx(UIStyle.rarity_color(1)), "magic name blue")
	var rl := r.find_child("NameLabel", true, false) as Label3D
	assert_eq(rl.text, r.display_name, "rare name shown")
	assert_true(rl.modulate.is_equal_approx(UIStyle.rarity_color(2)), "rare name yellow")


func test_rarity_look() -> void:
	await make_world()
	var n := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(0, 0, 0), 3, 0)
	var m := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(3, 0, 0), 3, 1, ["hasted"])
	var r := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(-3, 0, 0), 3, 2, ["hasted", "frigid"])
	assert_eq(n.visuals.get_rim().a, 0.0, "normal: no rim")
	var mr := m.visuals.get_rim()
	assert_true(mr.a > 0.0 and mr.b > mr.r, "magic: blue rim")
	var rr := r.visuals.get_rim()
	assert_true(rr.a > 0.0 and rr.r > rr.b and rr.g > rr.b, "rare: yellow rim")
	assert_true(m.visuals.has_overlay() and r.visuals.has_overlay(), "rim overlay on")
	assert_true(r.find_child("RarityRing", true, false) != null, "rare ground ring")
	assert_true(n.find_child("RarityRing", true, false) == null, "no ring on normals")
	assert_true(r.find_child("ModAura", true, false) != null, "elemental mod aura")
	assert_true(r.get_collision_radius() > n.get_collision_radius(), "rares are a bit bigger")
	assert_true(r.visuals.model.scale.x > n.visuals.model.scale.x, "rare model scaled up")


func test_tints() -> void:
	await make_world()
	var fc := EnemyDB.spawn_enemy("frost_cultist", Vector3(0, 0, 0), 3)
	var tinted := false
	for mi in fc.visuals.model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			if m.get_surface_override_material(i) != null:
				tinted = true
	assert_true(tinted, "frost cultist robe tinted")


func test_hit_flash() -> void:
	await make_world()
	var e := EnemyDB.spawn_enemy("zombie", Vector3(0, 0, 0), 3)
	await get_tree().physics_frame
	assert_false(e.visuals.has_overlay(), "no overlay at rest")
	e.take_damage(2.0, "physical")
	assert_true(e.visuals.has_overlay(), "flash overlay on hit")
	for i in 30:
		await get_tree().physics_frame
	assert_false(e.visuals.has_overlay(), "flash fades")


func test_action_animations_and_fallbacks() -> void:
	await make_world()
	var e := EnemyDB.spawn_enemy("ghoul", Vector3(0, 0, 0), 3)
	e.play_action_animation("attack_stab", 0.5)
	assert_eq(e.visuals.get_action(), "attack_stab", "plays the action")
	assert_near(e.visuals.anim.get_playing_speed(), e.visuals.anim.get_animation("attack_stab").length / 0.5, 0.01, "time-scaled to the duration")
	e.stop_action_animation()
	assert_eq(e.visuals.get_action(), "", "stopped")
	e.play_action_animation("shoot_crossbow", 0.6)
	assert_ne(e.visuals.get_action(), "", "known animation or a fallback")
	e.play_action_animation("no_such_anim", 0.6)
	assert_eq(e.visuals.get_action(), "", "unknown animation is ignored")
	var b := EnemyDB.spawn_enemy("boss_lich", Vector3(5, 0, 5), 3)
	b.play_action_animation("roar", 1.2)
	assert_eq(b.visuals.get_action(), "roar", "bosses roar")


func test_freeze_holds_the_pose() -> void:
	await make_world()
	var e := EnemyDB.spawn_enemy("zombie", Vector3(0, 0, 0), 3)
	await get_tree().physics_frame
	assert_true(e.visuals.anim.is_playing(), "animating")
	e.apply_ailment("freeze", {"duration": 0.5})
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(e.visuals.anim.is_playing(), "paused while frozen")
	e.play_action_animation("hit", 0.3)
	assert_false(e.visuals.anim.is_playing(), "no new actions while frozen")
	for i in 40:
		await get_tree().physics_frame
	assert_false(e.is_frozen(), "thawed")
	assert_true(e.visuals.anim.is_playing(), "animating again")


func test_enrage_look() -> void:
	await make_world()
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(-12, 0, -12), 100000.0)
	var b := EnemyDB.spawn_enemy("boss_gravebreaker", Vector3(6, 0, 6), 3)
	b.aggro(d)
	b.take_damage(b.max_life * 0.6, "physical")
	for i in 100:
		await get_tree().physics_frame
		if b.enraged:
			break
	assert_true(b.enraged, "enraged")
	assert_true(b.visuals.is_enraged_look(), "enrage aura")
	assert_true(b.visuals.get_rim().r > 0.9 and b.visuals.get_rim().g < 0.4, "red rim")
	b.reset_boss()
	assert_false(b.visuals.is_enraged_look(), "aura removed on reset")
	assert_true(b.visuals.get_rim().is_equal_approx(b.visuals.BOSS_RIM), "boss rim restored")

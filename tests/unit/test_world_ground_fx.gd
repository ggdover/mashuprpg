extends TestCase

const WorldFog := preload("res://scripts/world/world_fog.gd")
## Ground detail framework (WorldGroundFx) and the fog of war (WorldFog): the grass tuft meshes,
## details and grass built into chunked MultiMeshes, the grass pushers following the player and
## the monsters (and their fading trails), the act ground shaders, the fog's explored mask and its
## visibility (only with a player in the world), the debug toggle.


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func test_tufts_and_materials() -> void:
	for kind in WorldGroundFx.GRASS_KINDS.values():
		var m := WorldGroundFx.tuft_mesh(int(kind))
		assert_not_null(m, "tuft mesh %d" % int(kind))
		assert_true(m.surface_get_array_len(0) > 40, "blades in the tuft")
		var box := m.get_aabb()
		assert_true(box.size.y > 0.25 and box.size.y < 1.4, "tuft height %.2f" % box.size.y)
	for style in ["forest", "desert", "gothic"]:
		var mat := WorldGroundFx.ground_material(style)
		assert_true(mat is ShaderMaterial, "%s ground material" % style)
		assert_true((mat as ShaderMaterial).shader.code.contains("#define STYLE_%s" % style.to_upper()), "%s style define" % style)
	assert_true(WorldGroundFx.ground_material("") == null, "no style: plain ground")


func test_build_and_pushers() -> void:
	var w := await make_world()
	make_character()
	var details: Array = []
	var grass: Array = []
	for i in 40:
		details.append([i % WorldGroundFx.DETAIL_KINDS.size(), -10.0 + i * 0.5, 3.0, 0.3 * i, 1.0, 1.0, Color.WHITE, 0.0])
	for i in 60:
		grass.append([-6.0 + (i % 10) * 0.4, -2.0 + (i / 10) * 0.4, 0.0, 1.0, Color(0.3, 0.5, 0.1), i % 2])
	var fx := WorldGroundFx.new()
	w.level_root.add_child(fx)
	fx.build(w, details, grass)
	assert_eq(fx.detail_count, 40, "details")
	assert_eq(fx.grass_count, 60, "grass")
	var inst := 0
	for n in fx.get_children():
		var mmi := n as MultiMeshInstance3D
		assert_not_null(mmi, "chunks are MultiMeshInstance3D")
		inst += mmi.multimesh.instance_count
		assert_true(mmi.visibility_range_end > 0.0, "chunks fade out with distance")
	assert_eq(inst, 100, "every detail and tuft is an instance")
	# No player yet: no pushers.
	await get_tree().process_frame
	assert_eq(fx.last_pushers.size(), 0, "no pushers without a player")
	# The player pushes; a monster near them too; they leave fading trail points.
	var p := spawn_player(Vector3(-4, 0, -1))
	var d := spawn_dummy(Actor.Team.ENEMY, Vector3(-1, 0, 1), 100.0)
	d.add_to_group("enemies")
	await _wait(3)
	await get_tree().process_frame
	assert_true(fx.last_pushers.size() >= 1, "the player pushes the grass")
	var first: Vector4 = fx.last_pushers[0]
	assert_near(Vector2(first.x, first.y).distance_to(Vector2(p.global_position.x, p.global_position.z)), 0.0, 0.6, "nearest pusher = the player")
	assert_true(first.z > 0.5 and first.w > 0.9, "radius and full strength")
	p.ai_move(Vector3(1, 0, 0))
	await _wait(40)
	p.ai_move(Vector3.ZERO)
	await get_tree().process_frame
	var trail := 0
	for v in fx.last_pushers:
		if (v as Vector4).w < 0.99:
			trail += 1
	assert_true(trail >= 1, "fading trail points behind the player (%d)" % trail)
	assert_true(fx.last_pushers.size() <= WorldGroundFx.MAX_PUSHERS, "capped")
	await _wait(int(WorldGroundFx.TRAIL_LIFE * 60.0) + 10)
	await get_tree().process_frame
	trail = 0
	for v in fx.last_pushers:
		if (v as Vector4).w < 0.99:
			trail += 1
	assert_eq(trail, 0, "the trail fades away (the grass springs back)")


func test_fog_of_war() -> void:
	var town := await make_world({"id": "town", "name": "Emberfall", "level": 1})
	assert_not_null(town.fog, "the town has the fog (distance shade only)")
	assert_false(bool(town.fog.call("get_params")["use_explored"]), "the town is fully explored")
	await get_tree().process_frame
	assert_false(town.fog.visible, "hidden without a player (previews, tools)")
	make_character()
	spawn_player(Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(town.fog.visible, "shown with a player in the world")
	remove_child(town)
	town.free()
	var dun := await make_world({"id": "dungeon", "name": "Depth 1", "depth": 1, "level": 1, "seed": 7})
	assert_not_null(dun.fog, "dungeons have the fog")
	assert_true(bool(dun.fog.call("get_params")["use_explored"]), "dungeons black out unexplored ground")
	var v0 := int(dun.fog.call("get_params")["version"])
	# Explore a spot far from the start (the explored version changes).
	dun.mark_explored(Vector3(dun.grid.size.x, 0, dun.grid.size.y) * World.TILE_SIZE * 0.85, 12.0)
	await get_tree().create_timer(WorldFog.UPLOAD_INTERVAL * 3.0).timeout
	await get_tree().process_frame
	assert_true(int(dun.fog.call("get_params")["version"]) != v0, "the explored mask follows exploration")
	dun.set_fog_enabled(false)
	assert_false(dun.fog.visible, "debug toggle hides it")
	assert_false(World.fog_of_war_enabled, "and keeps it off for the next worlds")
	dun.set_fog_enabled(true)
	assert_true(World.fog_of_war_enabled, "back on")
	var arena := await make_world()
	assert_true(arena.fog == null, "test arenas have no fog")

extends TestCase
## Performance sanity: build time of the biggest (64 x 64) dungeons, light / collision shape /
## draw node budgets, and the moving light pool.


func _info(depth: int, seed_value: int) -> Dictionary:
	var theme := World.theme_for_depth(depth)
	return {"id": "dungeon", "depth": depth, "level": depth, "seed": seed_value, "theme": theme, "name": "perf"}


func test_build_time_64x64() -> void:
	for depth in [10, 13, 16]:
		var w := await make_world(_info(depth, 1000 + depth))
		assert_eq(w.grid.size, Vector2i(64, 64), "64 x 64 at depth %d" % depth)
		assert_true(w.build_time_ms < 1500.0, "build %s in %.0f ms" % [w.theme, w.build_time_ms])
		print("    [perf] depth %d (%s) built in %.0f ms" % [depth, w.theme, w.build_time_ms])


func test_generator_time() -> void:
	var t0 := Time.get_ticks_msec()
	for s in 5:
		WorldDungeonGen.new().generate(10, s, "cave")
	var per := (Time.get_ticks_msec() - t0) / 5.0
	assert_true(per < 600.0, "cave generator %.0f ms per 64x64 layout" % per)


func test_budgets() -> void:
	for depth in [1, 4, 7, 10]:
		var w := await make_world(_info(depth, 31 + depth))
		var lights := w.get_light_count()
		assert_true(lights <= WorldDungeonGen.MAX_BUILD_LIGHTS, "d%d build lights %d <= %d" % [depth, lights, WorldDungeonGen.MAX_BUILD_LIGHTS])
		var shadowed := 0
		for l in w.find_children("*", "OmniLight3D", true, false):
			if (l as OmniLight3D).shadow_enabled:
				shadowed += 1
		assert_eq(shadowed, 0, "omni lights are shadowless")
		assert_true(w.get_collision_shape_count() < 400, "d%d collision shapes %d" % [depth, w.get_collision_shape_count()])
		var bodies := w.level_root.find_children("*", "StaticBody3D", true, false)
		assert_eq(bodies.size(), 1, "one merged StaticBody3D")
		if bodies.size() == 1:
			assert_eq((bodies[0] as StaticBody3D).collision_layer, 1, "layer 1")
		var mmis := w.find_children("*", "MultiMeshInstance3D", true, false).size()
		assert_true(mmis > 10 and mmis < 700, "d%d multimesh nodes %d" % [depth, mmis])
		var meshes := w.level_root.find_children("*", "MeshInstance3D", true, false).size()
		assert_true(meshes < 40, "d%d loose MeshInstance3Ds %d (geometry must be multimeshed)" % [depth, meshes])
		w.spawn_exit_portals(w.get_boss_room_center())
		assert_true(w.get_light_count() <= World.MAX_LIGHTS, "d%d with exit portals %d" % [depth, w.get_light_count()])


func test_wall_blocks_touch_floor_only() -> void:
	for depth in [2, 5, 8]:
		var w := await make_world(_info(depth, 606))
		var g := w.grid
		assert_true(w.wall_cells.size() > 100, "walls built (%d)" % w.wall_cells.size())
		var seen := {}
		for c in w.wall_cells:
			assert_false(seen.has(c), "one block per cell")
			seen[c] = true
			assert_false(g.is_walkable_cell(c), "wall cell not walkable")
			var touches := false
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if g.is_floor(c + Vector2i(di, dj)):
						touches = true
			if not touches:
				fail("wall at cell %s touches no floor" % [c])
				return
		# Every floor cell's 8 neighbours are floor, lava or wall (no holes into the void).
		for j in g.size.y:
			for i in g.size.x:
				if not g.is_floor(Vector2i(i, j)):
					continue
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var n := Vector2i(i + di, j + dj)
						if not g.is_floor(n) and not seen.has(n) and w.layout["cells"][n.y * g.size.x + n.x] != WorldDungeonGen.CELL_LAVA:
							fail("floor %s borders open void at %s" % [Vector2i(i, j), n])
							return


func test_light_pool_follows_focus() -> void:
	var w := await make_world(_info(1, 2468))
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.make_current()
	var boss := w.get_boss_room_center()
	cam.position = boss + Vector3(0, 15, 10)
	cam.rotation = Vector3(-deg_to_rad(56.0), 0, 0)
	await get_tree().process_frame
	w.snap_light_pool()
	var focus := boss + Vector3(0, 0, 10 - 15.0 / tan(deg_to_rad(56.0)))
	var near := 0
	for l in w.find_children("PoolLight*", "OmniLight3D", true, false):
		var lp := (l as OmniLight3D).global_position
		if (l as OmniLight3D).visible and Vector2(lp.x - focus.x, lp.z - focus.z).length() < 16.0:
			near += 1
	assert_true(near >= 3, "pool lights gathered around the camera focus (%d)" % near)
	cam.queue_free()


func test_pathfinding_speed() -> void:
	var w := await make_world(_info(10, 777))
	var g := w.grid
	var cells: Array = []
	for j in g.size.y:
		for i in g.size.x:
			if g.is_walkable_cell(Vector2i(i, j)):
				cells.append(Vector2i(i, j))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t0 := Time.get_ticks_usec()
	var found := 0
	for k in 200:
		var a: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var b: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var path := w.find_path(g.cell_center(a), g.cell_center(b))
		if not path.is_empty():
			found += 1
	var per_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 200.0
	print("    [perf] find_path on 64x64: %.3f ms per call" % per_ms)
	assert_eq(found, 200, "every pair connected")
	assert_true(per_ms < 3.0, "find_path %.2f ms per call" % per_ms)

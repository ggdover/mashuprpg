extends TestCase
## World grid queries: arena layout, pathfinding, walkability, nearest / random walkable, grid
## line of sight, minimap indexing and exploration.


func _dungeon(depth: int = 2, seed_value: int = 77) -> World:
	var theme := World.theme_for_depth(depth)
	return await make_world({"id": "dungeon", "depth": depth, "level": depth, "seed": seed_value, "theme": theme, "name": "test"})


## Every point along the polyline (from `start`) lies on walkable cells.
func _path_walkable(w: World, start: Vector3, path: PackedVector3Array) -> bool:
	var prev := Vector3(start.x, 0, start.z)
	for p in path:
		var d := prev.distance_to(p)
		var n := int(ceil(d / 0.2)) + 1
		for k in n + 1:
			var q := prev.lerp(p, float(k) / float(n))
			if not w.is_walkable(q):
				return false
		prev = p
	return true


func test_arena_layout() -> void:
	var w := await make_world()
	assert_eq(w.grid.size, Vector2i(18, 18), "16 floor cells + perimeter walls")
	assert_eq(w.get_player_start(), Vector3.ZERO, "start at the centre")
	assert_true(w.is_walkable(Vector3.ZERO), "origin walkable (fixtures spawn there)")
	assert_true(w.is_walkable(Vector3(3, 0, 0)), "dummy spot walkable")
	assert_true(w.is_walkable(Vector3(15.5, 0, -15.5)), "inner corner walkable")
	assert_false(w.is_walkable(Vector3(16.5, 0, 0)), "perimeter wall")
	assert_false(w.is_walkable(Vector3(40, 0, 0)), "outside")
	assert_eq(w.grid.walkable_count(), 256, "16 x 16 floor")
	assert_eq(w.get_spawn_groups().size(), 0, "no spawns")
	assert_eq(w.get_interactables().size(), 0, "no interactables")
	assert_true(w.get_collision_shape_count() > 0, "wall collision")
	var md := w.get_minimap_data()
	assert_eq(md["origin"], Vector3(-18, 0, -18), "arena grid centred on the origin")
	# Physics: the wall collision stops a ray at the perimeter (layer 1).
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(40, 1, 0), 1)
	var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
	assert_false(hit.is_empty(), "ray hits the perimeter wall")
	if not hit.is_empty():
		assert_near((hit["position"] as Vector3).x, 16.0, 0.05, "wall face at x = 16")
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(-10, 1, 3), Vector3(10, 1, -3), 1)
	assert_true(w.get_world_3d().direct_space_state.intersect_ray(q2).is_empty(), "open floor has no colliders")


func test_arena_custom_size() -> void:
	var w := await make_world({"id": "arena", "name": "Arena", "level": 1, "size": 8})
	assert_eq(w.grid.walkable_count(), 64, "8 x 8")
	assert_true(w.is_walkable(Vector3(7.5, 0, 7.5)), "inner corner")
	assert_false(w.is_walkable(Vector3(8.5, 0, 0)), "wall")


func test_find_path_open_and_blocked() -> void:
	var w := await make_world()
	var p := w.find_path(Vector3(-10, 0, 0), Vector3(10, 0.5, 2))
	assert_eq(p.size(), 1, "clear line -> direct")
	assert_eq(p[p.size() - 1], Vector3(10, 0, 2), "ends at the target (y = 0)")
	# Wall across the arena with a gap at the top row.
	for j in range(2, 17):
		w.grid.set_walkable(Vector2i(9, j), false)
		w.grid.set_opaque(Vector2i(9, j), true)
	w.grid.rebuild_astar()
	var from := Vector3(-8, 0, 8)
	var to := Vector3(8, 0, 8)
	var path := w.find_path(from, to)
	assert_true(path.size() >= 2, "path goes around the wall")
	assert_eq(path[path.size() - 1], to, "target included")
	assert_true(_path_walkable(w, from, path), "every segment on walkable cells")
	var length := 0.0
	var prev := from
	for pt in path:
		length += prev.distance_to(pt)
		prev = pt
	assert_true(length > from.distance_to(to) + 10.0, "detour is longer (%.1f)" % length)
	assert_false(w.has_line_of_sight(from, to), "wall blocks grid LOS")
	# Close the gap: unreachable.
	w.grid.set_walkable(Vector2i(9, 1), false)
	w.grid.rebuild_astar()
	assert_eq(w.find_path(from, to).size(), 0, "unreachable -> empty")
	assert_true(is_inf(w.get_path_distance(from, to)), "unreachable distance INF")


func test_find_path_snaps_target_and_start() -> void:
	var w := await make_world()
	var path := w.find_path(Vector3(0, 0, 0), Vector3(30, 0, 0))
	assert_true(path.size() >= 1, "path to a point inside the wall")
	var last := path[path.size() - 1]
	assert_true(w.is_walkable(last), "snapped target walkable")
	assert_true(last.x > 14.0 and last.x < 16.0, "snapped next to the wall (%s)" % last)
	var path2 := w.find_path(Vector3(-17, 0, 0), Vector3(0, 0, 5))
	assert_true(path2.size() >= 1, "start inside the wall is snapped")
	assert_eq(path2[path2.size() - 1], Vector3(0, 0, 5), "ends at the target")


func test_dungeon_paths() -> void:
	var w := await _dungeon(3, 4242)
	var start := w.get_player_start()
	for r in w.get_rooms():
		var target: Vector3 = r["center"]
		var path := w.find_path(start, target)
		if r["kind"] == "start":
			continue
		assert_true(path.size() >= 1, "path to room %s" % [r["rect"]])
		assert_true(path[path.size() - 1].distance_to(w.get_nearest_walkable(target)) < 0.01, "ends at the room centre")
		assert_true(_path_walkable(w, start, path), "path stays on walkable cells")
		var d := w.get_path_distance(start, target)
		assert_true(d >= start.distance_to(target) - 2.9, "grid distance >= straight distance")


func test_nearest_and_random_walkable() -> void:
	var w := await _dungeon(5, 99)
	var start := w.get_player_start()
	assert_eq(w.get_nearest_walkable(start), start, "walkable point is returned as is")
	var g := w.grid
	var checked := 0
	for j in g.size.y:
		for i in g.size.x:
			var c := Vector2i(i, j)
			if g.is_walkable_cell(c) or checked > 60 or (i + j) % 7 != 0:
				continue
			var p := g.cell_center(c)
			var n := w.get_nearest_walkable(p)
			assert_true(w.is_walkable(n), "nearest walkable is walkable")
			assert_near(n.y, 0.0, 0.001, "y = 0")
			checked += 1
	assert_true(checked > 10, "checked some wall cells")
	for k in 60:
		var q := w.random_walkable_near(start, 5.0)
		assert_true(w.is_walkable(q), "random point walkable")
		assert_true(q.distance_to(start) <= 5.01, "within radius")
		assert_true(w.has_line_of_sight(start, q), "visible from the centre")
	assert_eq(w.random_walkable_near(start, 0.0), start, "radius 0")


func test_line_of_sight() -> void:
	var w := await make_world()
	assert_true(w.has_line_of_sight(Vector3(-15, 0, -15), Vector3(15, 0, 15)), "open arena diagonal")
	assert_false(w.has_line_of_sight(Vector3(0, 0, 0), Vector3(20, 0, 0)), "into the wall")
	w.grid.set_opaque(Vector2i(9, 9), true)
	# Cell (9, 9) spans x, z in [0, 2].
	assert_false(w.has_line_of_sight(Vector3(-3, 0, 1), Vector3(5, 0, 1)), "blocked by the cell")
	assert_true(w.has_line_of_sight(Vector3(-3, 0, 3), Vector3(5, 0, 3)), "passes beside it")
	assert_false(w.has_line_of_sight(Vector3(-1, 0, -1), Vector3(3, 0, 3)), "diagonal through the cell")
	# Exactly through a corner of the blocked cell is conservative.
	assert_false(w.has_line_of_sight(Vector3(1, 0, -1), Vector3(3, 0, 1)), "corner graze blocked")
	assert_true(w.has_line_of_sight(Vector3(-3, 0, -3), Vector3(-1, 0, -1.5)), "short open segment")


func test_minimap_indexing() -> void:
	var w := await _dungeon(6, 5150)
	var md := w.get_minimap_data()
	var size: Vector2i = md["size"]
	var cells: PackedByteArray = md["cells"]
	var explored: PackedByteArray = md["explored"]
	assert_eq(cells.size(), size.x * size.y, "cells length")
	assert_eq(explored.size(), size.x * size.y, "explored length")
	assert_eq(md["tile_size"], World.TILE_SIZE, "tile size")
	assert_eq(md["origin"], Vector3.ZERO, "dungeon origin")
	assert_true(md["markers"] is Array, "markers")
	var floors := 0
	for j in size.y:
		for i in size.x:
			var v := cells[j * size.x + i]
			var centre := Vector3((i + 0.5) * md["tile_size"], 0, (j + 0.5) * md["tile_size"])
			if (v == 1) != w.grid.is_floor(Vector2i(i, j)):
				fail("cell (%d, %d) minimap flag %d != grid floor" % [i, j, v])
			if w.is_walkable(centre):
				assert_eq(v, 1, "walkable cell is floor on the minimap")
			if v == 1:
				floors += 1
	assert_true(floors > 300, "plenty of floor (%d)" % floors)
	# Exploration: the start is revealed on build; a far point is revealed by mark_explored.
	var s := w.world_to_cell(w.get_player_start())
	assert_eq(explored[s.y * size.x + s.x], 1, "start explored")
	var boss := w.get_boss_room_center()
	var bc := w.world_to_cell(boss)
	assert_eq(explored[bc.y * size.x + bc.x], 0, "boss room unexplored")
	var v0: int = md["version"]
	w.mark_explored(boss, 14.0)
	var md2 := w.get_minimap_data()
	assert_eq((md2["explored"] as PackedByteArray)[bc.y * size.x + bc.x], 1, "boss room explored")
	assert_true(int(md2["version"]) > v0, "version bumped")
	var far := w.world_to_cell(boss + Vector3(40, 0, 0))
	if w.grid.in_bounds(far):
		assert_eq((md2["explored"] as PackedByteArray)[far.y * size.x + far.x], 0, "beyond the radius stays hidden")
	var v1: int = md2["version"]
	w.mark_explored(boss, 14.0)
	assert_eq(int(w.get_minimap_data()["version"]), v1, "no change -> same version")


func test_world_without_build_is_permissive() -> void:
	var w := World.new()
	add_child(w)
	assert_true(w.is_walkable(Vector3(5, 0, 5)), "unbuilt world walkable")
	assert_eq(w.find_path(Vector3.ZERO, Vector3(3, 0, 4)), PackedVector3Array([Vector3(3, 0, 4)]), "direct path")
	assert_eq(w.get_nearest_walkable(Vector3(1, 0, 1)), Vector3(1, 0, 1), "nearest")
	assert_true(w.has_line_of_sight(Vector3.ZERO, Vector3(9, 0, 9)), "LOS")
	assert_eq(w.get_minimap_data(), {}, "no minimap")
	w.mark_explored(Vector3.ZERO, 10.0)
	var n := Node3D.new()
	w.add_dynamic(n)
	assert_eq(n.get_parent(), w.dynamic_root, "add_dynamic")
	var e := Node3D.new()
	w.add_enemy(e)
	assert_eq(e.get_parent(), w.enemies_root, "add_enemy")
	assert_true(w.is_in_group("world"), "group world")

extends "res://tests/unit/test_kernel_util.gd"
## CombatQuery: hostility, radius / cone / segment / nearest geometry (XZ + collision radius),
## raycasts against physics layer 1.


func test_hostiles_and_allies() -> void:
	var p := dummy(Actor.Team.PLAYER, 100.0, [], {}, Vector3.ZERO)
	var e1 := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(3, 0, 0))
	var e2 := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(-3, 0, 0))
	var dead := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(1, 0, 0))
	dead.die(null)
	var h := CombatQuery.get_hostiles(Actor.Team.PLAYER)
	assert_true(h.has(e1) and h.has(e2), "enemies are hostile to the player")
	assert_false(h.has(p), "not self")
	assert_false(h.has(dead), "no dead actors")
	assert_eq(CombatQuery.get_hostiles(Actor.Team.ENEMY), [p] as Array[Actor], "player hostile to enemies")
	var allies := CombatQuery.get_allies(Actor.Team.ENEMY)
	assert_true(allies.has(e1) and not allies.has(dead) and not allies.has(p), "allies")
	assert_true(CombatQuery.is_hostile(p, e1), "is_hostile")
	assert_false(CombatQuery.is_hostile(e1, e2), "same team")
	assert_false(CombatQuery.is_hostile(null, e1), "null")
	var gone := dummy(Actor.Team.PLAYER, 100.0, [], {}, Vector3(9, 0, 0))
	gone.free()
	assert_false(CombatQuery.is_hostile(gone, e1), "freed a")
	assert_false(CombatQuery.is_hostile(e1, gone), "freed b")
	var not_actor := Node3D.new()
	add_child(not_actor)
	assert_false(CombatQuery.is_hostile(not_actor, e1), "not an actor")
	not_actor.queue_free()


func test_radius_includes_collision_radius() -> void:
	var e1 := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(3.3, 5.0, 0))
	var e2 := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(0, 0, 3.5))
	var r := CombatQuery.hostiles_in_radius(Actor.Team.PLAYER, Vector3.ZERO, 3.0)
	assert_true(r.has(e1), "3.3 m (edge at 2.9) inside radius 3; y ignored")
	assert_false(r.has(e2), "3.5 m (edge at 3.1) outside")
	var a := CombatQuery.allies_in_radius(Actor.Team.ENEMY, Vector3.ZERO, 3.0)
	assert_true(a.has(e1) and not a.has(e2), "allies in radius")
	assert_near(CombatQuery.distance_to_actor(Vector3.ZERO, e2), 3.1, 0.001, "edge distance")
	assert_near(CombatQuery.distance_xz(Vector3(0, 9, 0), Vector3(3, 0, 4)), 5.0, 0.001, "xz distance")


func test_cone() -> void:
	var front := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(3, 0, 0))
	var side := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(0, 0, 3))
	var diag := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(3, 0, 2.9))
	var edge := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(3, 0, 3.3))
	var behind := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(-3, 0, 0))
	var far := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(6, 0, 0))
	var c := CombatQuery.hostiles_in_cone(Actor.Team.PLAYER, Vector3.ZERO, Vector3(1, 0, 0), 5.0, 90.0)
	assert_true(c.has(front), "in front")
	assert_true(c.has(diag), "44° inside the 45° half angle")
	assert_true(c.has(edge), "48° but its circle overlaps the edge")
	assert_false(c.has(side), "90° outside")
	assert_false(c.has(behind), "behind")
	assert_false(c.has(far), "out of range")
	var wide := CombatQuery.hostiles_in_cone(Actor.Team.PLAYER, Vector3.ZERO, Vector3(1, 0, 0), 5.0, 360.0)
	assert_true(wide.has(behind) and wide.has(side), "360° = circle")
	var overlap := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(-0.2, 0, 0))
	assert_true(CombatQuery.hostiles_in_cone(Actor.Team.PLAYER, Vector3.ZERO, Vector3(1, 0, 0), 5.0, 10.0).has(overlap), "overlapping the origin counts")


func test_segment_sorted() -> void:
	var a := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(8, 0, 0.8))
	var b := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(2, 0, -0.5))
	var off := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(5, 0, 1.0))
	var past := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(11, 0, 0))
	var s := CombatQuery.hostiles_along_segment(Actor.Team.PLAYER, Vector3.ZERO, Vector3(10, 0, 0), 0.5)
	assert_eq(s, [b, a] as Array[Actor], "hit and sorted by distance from start")
	assert_false(s.has(off), "1.0 m off the line (reach 0.9)")
	assert_false(s.has(past), "beyond the end (edge 1 m away)")


func test_nearest_and_sorted() -> void:
	var a := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(4, 0, 0))
	var b := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(0, 0, 2))
	var c := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(0, 0, 20))
	assert_eq(CombatQuery.nearest_hostile(Actor.Team.PLAYER, Vector3.ZERO, 10.0), b, "nearest")
	assert_eq(CombatQuery.nearest_hostile(Actor.Team.PLAYER, Vector3.ZERO, 10.0, [b]), a, "exclude")
	assert_eq(CombatQuery.nearest_hostile(Actor.Team.PLAYER, Vector3.ZERO, 1.0), null, "none in range")
	assert_eq(CombatQuery.nearest_hostile(Actor.Team.PLAYER, Vector3.ZERO, 1.6), b, "range to the edge (1.6)")
	assert_eq(CombatQuery.hostiles_sorted_by_distance(Actor.Team.PLAYER, Vector3.ZERO, 100.0), [b, a, c] as Array[Actor], "sorted")
	assert_eq(CombatQuery.nearest_hostile(Actor.Team.ENEMY, Vector3.ZERO, 100.0), null, "no players")


func test_raycast_and_line_of_sight() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2.4, 4)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(5, 1.2, 0)
	add_child(wall)
	var other := StaticBody3D.new()
	other.collision_layer = 4
	var cs2 := CollisionShape3D.new()
	cs2.shape = box
	other.add_child(cs2)
	other.position = Vector3(0, 1.2, 5)
	add_child(other)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := CombatQuery.raycast_world(Vector3(0, 1.1, 0), Vector3(10, 1.1, 0))
	assert_false(hit.is_empty(), "wall hit")
	assert_near((hit["position"] as Vector3).x, 4.5, 0.01, "hit at the wall face")
	assert_true((hit["normal"] as Vector3).distance_to(Vector3(-1, 0, 0)) < 0.01, "normal faces back")
	assert_true(CombatQuery.raycast_world(Vector3(0, 1.1, 0), Vector3(3, 1.1, 0)).is_empty(), "short of the wall")
	assert_false(CombatQuery.raycast_world(Vector3(0, 0, 0), Vector3(10, 0, 0)).is_empty(), "floor points are raised")
	assert_true(CombatQuery.raycast_world(Vector3(0, 1.1, 0), Vector3(0, 1.1, 10)).is_empty(), "only layer 1")
	assert_false(CombatQuery.has_line_of_sight(Vector3.ZERO, Vector3(10, 0, 0)), "LOS blocked")
	assert_true(CombatQuery.has_line_of_sight(Vector3.ZERO, Vector3(0, 0, -10)), "LOS clear")
	assert_true(CombatQuery.has_line_of_sight(Vector3(10, 0, 3), Vector3(0, 0, 3)), "passes beside the wall")
	assert_true(CombatQuery.raycast_world(Vector3(1, 1, 1), Vector3(1, 1, 1)).is_empty(), "zero-length ray")


func test_queries_inside_a_world() -> void:
	var w := await make_world()
	assert_eq(GameState.world, w, "world set")
	var p := spawn_dummy(Actor.Team.PLAYER, Vector3.ZERO, 100.0)
	var e := spawn_dummy(Actor.Team.ENEMY, Vector3(4, 0, 0), 100.0)
	assert_eq(CombatQuery.nearest_hostile(p.team, Vector3.ZERO, 10.0), e, "actors inside the World")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2.4, 4)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(2, 1.2, 0)
	w.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(CombatQuery.has_line_of_sight(p.global_position, e.global_position), "wall inside the World blocks")
	assert_near((CombatQuery.raycast_world(Vector3(0, 1.1, 0), Vector3(4, 1.1, 0))["position"] as Vector3).x, 1.5, 0.01, "hit position")

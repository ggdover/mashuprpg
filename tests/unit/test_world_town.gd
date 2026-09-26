extends TestCase
## Town (Emberfall): interactables, their events, return portal, reachability, markers.

const TOWN := {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}


func _find(w: World, cls: Variant) -> Node:
	for n in w.get_interactables():
		if is_instance_of(n, cls):
			return n
	return null


func test_town_has_all_interactables() -> void:
	var w := await make_world(TOWN)
	assert_true(w.is_town(), "is_town")
	assert_eq(w.get_spawn_groups().size(), 0, "no monsters in town")
	var gate := _find(w, WorldWaypointGate) as WorldWaypointGate
	var merchant := _find(w, WorldVendorNpc) as WorldVendorNpc
	var stash := _find(w, WorldStashChest) as WorldStashChest
	assert_not_null(gate, "Dungeon Gate")
	assert_not_null(merchant, "Merchant")
	assert_not_null(stash, "Stash")
	assert_eq(_find(w, WorldPortal), null, "no return portal without a kept dungeon")
	for n in [gate, merchant, stash]:
		if n == null:
			continue
		var it := n as Interactable
		assert_true(it.is_in_group("interactable"), "%s in group" % it.name)
		assert_eq(it.collision_layer, Interactable.LAYER_INTERACTABLE, "%s layer 5" % it.name)
		assert_true(it.find_children("*", "CollisionShape3D", false, false).size() > 0, "%s pick shape" % it.name)
		assert_ne(it.get_hover_name(), "", "%s hover name" % it.name)
		assert_true(it.can_interact(null), "%s enabled" % it.name)
	assert_eq(gate.get_hover_name(), "Dungeon Gate", "gate name")
	assert_eq(merchant.get_hover_name(), "Merchant", "merchant name")
	assert_eq(stash.get_hover_name(), "Stash", "stash name")
	var kinds := {}
	for m in w.get_minimap_data()["markers"]:
		kinds[m["kind"]] = true
	assert_true(kinds.has("waypoint") and kinds.has("vendor") and kinds.has("stash"), "markers %s" % [kinds])
	assert_true(w.get_light_count() <= World.MAX_LIGHTS, "light budget")
	assert_true(w.world_environment != null and w.world_environment.environment.background_mode == Environment.BG_SKY, "daylight sky")
	assert_true(w.sun != null and w.sun.shadow_enabled, "sun with shadows")


func test_town_interaction_events() -> void:
	var w := await make_world(TOWN)
	var c := make_character("ranger")
	c.max_depth = 5
	var got: Array = []
	var cb := func(panel: String, ctx: Dictionary) -> void: got.append([panel, ctx])
	Events.panel_open_requested.connect(cb)
	(_find(w, WorldVendorNpc) as Interactable).interact(null)
	(_find(w, WorldStashChest) as Interactable).interact(null)
	(_find(w, WorldWaypointGate) as Interactable).interact(null)
	Events.panel_open_requested.disconnect(cb)
	assert_eq(got.size(), 3, "three panel requests")
	if got.size() == 3:
		assert_eq(got[0][0], "vendor", "vendor panel")
		assert_eq(got[1][0], "stash", "stash panel")
		assert_eq(got[2][0], "waypoint", "waypoint panel")
		assert_eq(int(got[2][1].get("max_depth", 0)), 5, "max_depth passed")


func test_return_portal() -> void:
	var kept := World.new()
	add_child(kept)
	kept.build({"id": "dungeon", "depth": 3, "level": 3, "seed": 9, "theme": "crypt", "name": "Depth 3"})
	remove_child(kept)
	GameState.town_portal_state = {"world": kept, "position": kept.get_player_start()}
	var w := await make_world(TOWN)
	var portal := _find(w, WorldPortal) as WorldPortal
	assert_not_null(portal, "return portal")
	if portal != null:
		assert_eq(portal.destination, "return", "destination")
		assert_eq(portal.get_hover_name(), "Return to Depth 3", "label")
		assert_true(w.is_walkable(portal.position), "on walkable ground")
		var got: Array = []
		var cb := func(id: String, params: Dictionary) -> void: got.append([id, params])
		Events.area_change_requested.connect(cb)
		portal.interact(null)
		Events.area_change_requested.disconnect(cb)
		assert_eq(got.size(), 1, "one request")
		if got.size() == 1:
			assert_eq(got[0][0], "dungeon_return", "dungeon_return")
	# Discarding the kept dungeon removes the portal on refresh.
	GameState.town_portal_state = {}
	w.refresh_town_portal()
	await get_tree().process_frame
	assert_eq(_find(w, WorldPortal), null, "portal gone")
	kept.free()


func test_town_reachability() -> void:
	var w := await make_world(TOWN)
	var start := w.get_player_start()
	assert_true(w.is_walkable(start), "start walkable")
	assert_true(w.grid.is_fully_connected(), "town walkable area connected")
	for n in w.get_interactables():
		var it := n as Interactable
		var target := it.get_interact_position()
		var path := w.find_path(start, target)
		assert_true(path.size() >= 1, "path to %s" % it.name)
		if path.size() >= 1:
			var end := path[path.size() - 1]
			assert_true(end.distance_to(Vector3(target.x, 0, target.z)) <= it.get_interact_range(), "%s reachable within range (%.2f)" % [it.name, end.distance_to(target)])
	# The town is about 40 x 40 m and fully revealed.
	assert_between(w.grid.walkable_count() * 4.0, 1200.0, 1700.0, "walkable area m^2")
	var md := w.get_minimap_data()
	assert_eq((md["explored"] as PackedByteArray).count(0), 0, "fully explored")


func test_town_props_keep_clear() -> void:
	var w := await make_world(TOWN)
	var lay := w.layout
	var keeps: Array = lay["keepouts"]
	var paths: PackedByteArray = lay["paths"]
	var lamps: Array = lay["lamps"]
	var gate: Vector3 = lay["gate"]["pos"]
	var shapes: Array = lay["shapes"]
	for p in lay["props"]:
		var pos: Vector3 = p["pos"]
		var r: float = p["r"]
		var id: String = p["id"]
		for l in lamps:
			assert_true((l["pos"] as Vector3).distance_to(pos) >= r + 0.35, "%s at %s clear of lamp %s" % [id, pos, l["pos"]])
		if id in ["town_bush", "town_rock"]:
			assert_true(gate.distance_to(pos) >= 3.0, "%s at %s clear of the Dungeon Gate" % [id, pos])
			var c := w.world_to_cell(pos)
			assert_eq(paths[c.y * WorldTownGen.SIZE + c.x], 0, "%s off the paths" % id)
			for k in keeps:
				if k.has("rect"):
					var rect: Rect2 = k["rect"]
					assert_false(rect.grow(r - 0.05).has_point(Vector2(pos.x, pos.z)), "%s at %s clear of %s" % [id, pos, k["id"]])
				else:
					assert_true((k["pos"] as Vector3).distance_to(pos) >= float(k["r"]) + r - 0.01, "%s at %s clear of %s" % [id, pos, k["id"]])
		elif id in ["env_crate", "env_barrel"]:
			# Solid: off the paths, blocking its cell, with a collision shape.
			var c2 := w.world_to_cell(pos)
			assert_eq(paths[c2.y * WorldTownGen.SIZE + c2.x], 0, "%s at %s off the paths" % [id, pos])
			assert_false(w.is_walkable(pos), "%s at %s blocks its cell" % [id, pos])
			var has_shape := false
			for sh in shapes:
				if (sh["pos"] as Vector3).distance_to(pos) < 0.05:
					has_shape = true
			assert_true(has_shape, "%s at %s has collision" % [id, pos])
			for k2 in keeps:
				if not k2.has("rect") and (k2["pos"] as Vector3).distance_to(pos) > 0.01:
					assert_true((k2["pos"] as Vector3).distance_to(pos) >= float(k2["r"]) + r - 0.01, "%s at %s clear of %s" % [id, pos, k2["id"]])
	assert_true(w.grid.is_fully_connected(), "still connected")

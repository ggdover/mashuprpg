extends TestCase
## Dungeon generator + World.build("dungeon"): determinism, connectivity, rooms, spawn group
## constraints, boss room, chests, lights, exit portals.


func _info(depth: int, seed_value: int) -> Dictionary:
	var theme := World.theme_for_depth(depth)
	return {"id": "dungeon", "depth": depth, "level": depth, "seed": seed_value, "theme": theme,
		"name": "Depth %d — %s" % [depth, World.theme_display_name(theme)]}


func _layout(depth: int, seed_value: int) -> Dictionary:
	return WorldDungeonGen.new().generate(depth, seed_value, World.theme_for_depth(depth))


func test_theme_for_depth() -> void:
	assert_eq(World.theme_for_depth(1), "crypt", "d1")
	assert_eq(World.theme_for_depth(3), "crypt", "d3")
	assert_eq(World.theme_for_depth(4), "cave", "d4")
	assert_eq(World.theme_for_depth(7), "inferno", "d7")
	assert_eq(World.theme_for_depth(10), "crypt", "d10")
	assert_eq(World.theme_display_name("cave"), "Echoing Caves", "name")


func test_size_grows_with_depth() -> void:
	assert_eq(WorldDungeonGen.dungeon_size(1), 44, "depth 1")
	assert_eq(WorldDungeonGen.dungeon_size(10), 64, "depth 10")
	assert_eq(WorldDungeonGen.dungeon_size(30), 64, "deep")
	assert_true(WorldDungeonGen.dungeon_size(5) > 44 and WorldDungeonGen.dungeon_size(5) < 64, "depth 5 in between")


func test_determinism_per_seed() -> void:
	for depth in [1, 4, 7]:
		var a := _layout(depth, 1234)
		var b := _layout(depth, 1234)
		var c := _layout(depth, 98765)
		assert_eq(a["cells"], b["cells"], "cells same seed d%d" % depth)
		assert_eq(str(a["spawn_groups"]), str(b["spawn_groups"]), "spawns same seed d%d" % depth)
		assert_eq(str(a["chests"]), str(b["chests"]), "chests same seed d%d" % depth)
		assert_eq(str(a["rooms"]), str(b["rooms"]), "rooms same seed d%d" % depth)
		assert_eq(str(a["debris"]), str(b["debris"]), "debris same seed d%d" % depth)
		assert_eq((a["grid"] as WorldGrid).walk, (b["grid"] as WorldGrid).walk, "walk same seed d%d" % depth)
		assert_ne(a["cells"], c["cells"], "different seed d%d" % depth)


func test_world_build_is_deterministic() -> void:
	var w1 := await make_world(_info(2, 555))
	var w2 := await make_world(_info(2, 555))
	assert_eq(w1.get_player_start(), w2.get_player_start(), "start")
	assert_eq(str(w1.get_spawn_groups()), str(w2.get_spawn_groups()), "spawn groups")
	assert_eq(w1.get_minimap_data()["cells"], w2.get_minimap_data()["cells"], "minimap cells")
	assert_eq(w1.get_interactables().size(), w2.get_interactables().size(), "interactables")


func test_all_floor_connected() -> void:
	for depth in [1, 2, 4, 5, 7, 8, 10]:
		for s in [1, 42, 777]:
			var lay := _layout(depth, s)
			var g: WorldGrid = lay["grid"]
			assert_true(g.is_fully_connected(), "connected d%d s%d" % [depth, s])
			var seen := g.flood_walkable(lay["start_cell"])
			assert_eq(seen.count(1), g.walkable_count(), "reachable from start d%d s%d" % [depth, s])
			# Border ring is never floor.
			for i in g.size.x:
				assert_false(g.is_floor(Vector2i(i, 0)) or g.is_floor(Vector2i(i, g.size.y - 1)), "border row d%d" % depth)


func test_rooms() -> void:
	for depth in [1, 6, 10]:
		for s in [3, 11]:
			var lay := _layout(depth, s)
			var rooms: Array = lay["rooms"]
			assert_between(rooms.size(), 10, 16, "room count d%d" % depth)
			var kinds := {}
			for r in rooms:
				var rect: Rect2i = r["rect"]
				kinds[r["kind"]] = int(kinds.get(r["kind"], 0)) + 1
				assert_between(rect.size.x, 5, 12, "room w")
				assert_between(rect.size.y, 5, 12, "room h")
			assert_eq(kinds.get("start", 0), 1, "one start room")
			assert_eq(kinds.get("boss", 0), 1, "one boss room")
			assert_between(int(kinds.get("room", 0)), 8, 14, "8-14 other rooms")


func test_boss_room_is_farthest() -> void:
	for depth in [1, 4, 7, 9]:
		for s in [5, 17, 2024]:
			var lay := _layout(depth, s)
			var g: WorldGrid = lay["grid"]
			var start_cell: Vector2i = lay["start_cell"]
			var rooms: Array = lay["rooms"]
			var boss_d := -1.0
			var max_other := -1.0
			for r in rooms:
				var c := g.nearest_walkable_cell(g.world_to_cell(r["center"]))
				var d := g.cell_path_length(start_cell, c)
				assert_false(is_inf(d), "room reachable")
				if r["kind"] == "boss":
					boss_d = d
				elif r["kind"] == "room":
					max_other = maxf(max_other, d)
			assert_true(boss_d >= max_other - 0.001, "boss room farthest d%d s%d (%s vs %s)" % [depth, s, boss_d, max_other])
			# The boss spawn group sits in the boss room.
			var boss_groups := (lay["spawn_groups"] as Array).filter(func(gr: Dictionary) -> bool: return gr["kind"] == "boss")
			assert_eq(boss_groups.size(), 1, "one boss group")
			var bi: int = lay["boss_room"]
			var brect: Rect2i = rooms[bi]["rect"]
			assert_true(brect.has_point(g.world_to_cell(boss_groups[0]["position"])), "boss inside boss room")


func test_spawn_group_constraints() -> void:
	for depth in [1, 3, 5, 8, 10, 25]:
		for s in [1, 99, 4242]:
			var lay := _layout(depth, s)
			var g: WorldGrid = lay["grid"]
			var start: Vector3 = lay["start"]
			var packs := 0
			var rares := 0
			var bosses := 0
			var total := 0
			for gr in lay["spawn_groups"]:
				var pos: Vector3 = gr["position"]
				var cnt: int = gr["count"]
				total += cnt
				assert_true(pos.distance_to(start) >= 12.0, "group %s at %.1f m from start (d%d s%d)" % [gr["kind"], pos.distance_to(start), depth, s])
				assert_true(g.is_walkable_cell(g.world_to_cell(pos)), "group position walkable")
				assert_true(float(gr["radius"]) > 0.0, "radius")
				assert_true(gr.has("room"), "room key")
				match gr["kind"]:
					"pack":
						packs += 1
						assert_between(cnt, 3, 6, "pack size")
					"rare_pack":
						rares += 1
						assert_between(cnt, 4, 5, "rare pack size")
					"boss":
						bosses += 1
						assert_eq(cnt, 1, "boss count")
			assert_between(packs, 8, 12, "packs d%d s%d" % [depth, s])
			assert_between(rares, 2, 4, "rare packs d%d s%d" % [depth, s])
			assert_eq(bosses, 1, "boss")
			assert_true(total <= 70, "<= 70 monsters (got %d)" % total)


func test_chests_and_start_portal() -> void:
	var w := await make_world(_info(3, 31337))
	var chests := 0
	var portals := 0
	for n in w.get_interactables():
		if n is WorldChest:
			chests += 1
			assert_true((n as WorldChest).position.distance_to(w.get_player_start()) > 8.0, "chest away from start")
		elif n is WorldPortal:
			portals += 1
			assert_eq((n as WorldPortal).destination, "town", "start portal leads to town")
			assert_true((n as WorldPortal).position.distance_to(w.get_player_start()) < 6.0, "portal near start")
	assert_between(chests, 2, 4, "chests")
	assert_eq(portals, 1, "one start portal")
	assert_true(w.is_walkable(w.get_player_start()), "start walkable")
	var kinds := {}
	for m in w.get_minimap_data()["markers"]:
		kinds[m["kind"]] = true
	assert_true(kinds.has("portal") and kinds.has("chest"), "minimap markers %s" % [kinds])


func test_lights_budget_and_exit_portals() -> void:
	for depth in [1, 4, 7]:
		var w := await make_world(_info(depth, 7 + depth))
		assert_true(w.get_light_count() <= WorldDungeonGen.MAX_BUILD_LIGHTS, "lights after build d%d: %d" % [depth, w.get_light_count()])
		assert_true(w.get_light_count() >= 8, "atmospheric lighting d%d: %d" % [depth, w.get_light_count()])
		var boss_pos := w.get_boss_room_center()
		w.spawn_exit_portals(boss_pos)
		w.spawn_exit_portals(boss_pos)   # idempotent
		assert_true(w.get_light_count() <= World.MAX_LIGHTS, "lights with exit portals d%d" % depth)
		var dests := []
		for n in w.get_interactables():
			if n is WorldPortal and n.name.begins_with("Portal"):
				dests.append((n as WorldPortal).destination)
				assert_true(w.is_walkable((n as Node3D).position), "exit portal on walkable floor")
				assert_true((n as Node3D).position.distance_to(boss_pos) < 6.0, "exit portal near boss")
		dests.sort()
		assert_eq(dests, ["next", "town"], "exit portals d%d" % depth)


func test_exit_portals_at_max_depth() -> void:
	var w := await make_world(_info(Balance.MAX_DEPTH, 3))
	w.spawn_exit_portals(w.get_boss_room_center())
	var dests := []
	for n in w.get_interactables():
		if n is WorldPortal and n.name.begins_with("Portal"):
			dests.append((n as WorldPortal).destination)
	assert_eq(dests, ["town"], "only a town portal at max depth")


func test_portal_events() -> void:
	var w := await make_world(_info(4, 12))
	w.spawn_exit_portals(w.get_boss_room_center())
	var got: Array = []
	var cb := func(id: String, params: Dictionary) -> void: got.append([id, params])
	Events.area_change_requested.connect(cb)
	for n in w.get_interactables():
		if n is WorldPortal:
			(n as WorldPortal).interact(null)
	Events.area_change_requested.disconnect(cb)
	var ids := {}
	for g in got:
		ids[g[0]] = g[1]
	assert_true(ids.has("town") and ids["town"].get("keep_dungeon", false), "town portal keeps the dungeon: %s" % [got])
	assert_true(ids.has("dungeon") and int(ids["dungeon"].get("depth", 0)) == 5, "descend to depth 5: %s" % [got])


## Every live portal of the world.
func _portals(w: World) -> Array:
	var out: Array = []
	for n in w.get_interactables():
		if n is WorldPortal:
			out.append(n)
	return out


## A walkable spot >= 12 m from every existing portal (for a Town Portal cast in the open).
func _open_spot(w: World) -> Vector3:
	for r in w.get_rooms():
		var c: Vector3 = r["center"]
		var ok := w.is_walkable(c)
		for p in _portals(w):
			if (p as Node3D).position.distance_to(c) < 12.0:
				ok = false
		if ok:
			return c
	return w.get_player_start() + Vector3(20, 0, 0)


func test_town_portal_is_replaced_and_within_light_budget() -> void:
	for depth in [1, 4, 7]:
		var w := await make_world(_info(depth, 50 + depth))
		w.spawn_exit_portals(w.get_boss_room_center())
		var spot := _open_spot(w)
		var last: WorldPortal = null
		for i in 3:
			last = w.spawn_town_portal(spot + Vector3(0.5 * i, 0, 0))
			assert_true(w.get_light_count() <= World.MAX_LIGHTS, "d%d lights after town portal %d: %d" % [depth, i, w.get_light_count()])
		await get_tree().process_frame
		var town_portals := 0
		for p in _portals(w):
			if p.name == "TownPortal":
				town_portals += 1
		assert_eq(town_portals, 1, "d%d exactly one TownPortal" % depth)
		assert_eq(w.interactables_root.find_children("TownPortal*", "WorldPortal", false, false).size(), 1, "d%d one TownPortal node" % depth)
		assert_true(is_instance_valid(last) and last.destination == "town", "returns the portal")
		assert_true(is_instance_valid(last) and last.light != null, "d%d the town portal is lit" % depth)
		assert_true(last.position.distance_to(spot) < 7.0, "d%d near the cast position" % depth)
		assert_true(w.is_walkable(last.position), "on walkable floor")
		assert_true(w.get_light_count() <= World.MAX_LIGHTS, "d%d final lights %d" % [depth, w.get_light_count()])


func test_town_portal_reuses_a_nearby_town_portal() -> void:
	var w := await make_world(_info(2, 77))
	var start_portal: WorldPortal = null
	for p in _portals(w):
		if p.name == "StartPortal":
			start_portal = p
	assert_not_null(start_portal, "start portal")
	# Death respawn: the kept dungeon is re-entered at its player start, right by the start portal.
	var got := w.spawn_town_portal(w.get_player_start())
	assert_eq(got, start_portal, "the start portal is reused")
	assert_eq(_portals(w).size(), 1, "no extra portal")


func test_town_portal_in_a_detached_world() -> void:
	var w := await make_world(_info(5, 91))
	w.spawn_exit_portals(w.get_boss_room_center())
	var parent := w.get_parent()
	parent.remove_child(w)
	var spot := _open_spot(w)
	w.spawn_town_portal(spot)
	w.spawn_town_portal(spot)
	parent.add_child(w)
	await get_tree().process_frame
	var n := 0
	for p in _portals(w):
		if p.name == "TownPortal":
			n += 1
	assert_eq(n, 1, "one TownPortal after re-attaching")
	assert_true(w.get_light_count() <= World.MAX_LIGHTS, "light budget after re-attaching: %d" % w.get_light_count())


func test_light_budget_is_enforced_for_extra_interactables() -> void:
	var w := await make_world(_info(7, 19))
	w.spawn_exit_portals(w.get_boss_room_center())
	w.spawn_town_portal(_open_spot(w))
	for i in 4:
		var s := WorldShrine.new().setup("fury")
		s.position = w.get_player_start() + Vector3(2.0 * i, 0, 3)
		w.interactables_root.add_child(s)
		assert_not_null(s.light, "shrine %d lit (a pool light made room)" % i)
		assert_true(w.get_light_count() <= World.MAX_LIGHTS, "budget with extra shrine %d: %d" % [i, w.get_light_count()])


func test_player_light_is_not_counted() -> void:
	var w := await make_world(_info(1, 5))
	var before := w.get_light_count()
	var player_light := OmniLight3D.new()
	w.add_child(player_light)   # the Player (and its light) is a direct child of the World
	var holder := Node3D.new()
	w.add_child(holder)
	holder.add_child(OmniLight3D.new())
	assert_eq(w.get_light_count(), before, "player / camera rig lights are outside the area budget")
	player_light.queue_free()
	holder.queue_free()


func test_exit_portals_keep_clear() -> void:
	for depth in [1, 4, 7, 10]:
		var w := await make_world(_info(depth, 200 + depth))
		var boss := w.get_boss_room_center()
		# A town portal cast in the boss room first: the exit portals must not touch it.
		var tp := w.spawn_town_portal(boss)
		w.spawn_exit_portals(boss)
		var portals := _portals(w)
		for i in portals.size():
			for j in range(i + 1, portals.size()):
				var d := (portals[i] as Node3D).position.distance_to((portals[j] as Node3D).position)
				assert_true(d >= 3.3, "d%d portals %s / %s %.2f m apart" % [depth, portals[i].name, portals[j].name, d])
		for p in portals:
			if p == tp or not String(p.name).begins_with("Portal"):
				continue
			var pos := (p as Node3D).position
			for n in w.get_interactables():
				if n is WorldChest or n is WorldShrine:
					assert_true((n as Node3D).position.distance_to(pos) >= 2.2, "d%d %s clear of %s" % [depth, p.name, n.name])
			for d in w.layout["debris"]:
				assert_true((d["pos"] as Vector3).distance_to(pos) >= 1.5, "d%d %s clear of debris %s" % [depth, p.name, d["id"]])
			# The platform (~3.2 x 2 m) stands on walkable floor: no pillar / wall inside it.
			for o in [Vector3(1.6, 0, 0), Vector3(-1.6, 0, 0), Vector3(0, 0, 0.9), Vector3(0, 0, -0.9)]:
				assert_true(w.is_walkable(pos + o), "d%d %s footprint %s walkable" % [depth, p.name, o])

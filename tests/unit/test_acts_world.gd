extends TestCase
## Acts: ActDefs data and the act layouts, every act builds into ONE seamless World (the town and
## the layout's zones joined by paths, all reachable, zone levels rising away from the town,
## services in the town, packs / chests / the zone boss / the dungeon entrance in the zones,
## border pieces on open edges), deterministic layouts, act monster pools. OWNER: acts framework.

const FlowAreas := preload("res://scripts/main/flow_areas.gd")
## Border pieces per act (the gothic town is walled by its houses).
const BORDER_IDS := {"desert": "desert_ruinwall", "forest": "forest_gardsgard"}
## Build budget of a whole act (ms) in a test run.
const BUILD_BUDGET_MS := 9000.0


func _exit_tree() -> void:
	GameState.world = null
	GameState.current_area = {}


func test_act_defs() -> void:
	assert_eq(ActDefs.ACT_ORDER, ["forest", "desert", "gothic"] as Array[String], "act order: forest, desert, gothic")
	for act in ActDefs.ACT_ORDER:
		assert_true(ActDefs.has_act(act), "%s defined" % act)
		var d := ActDefs.get_act(act)
		for k in ["number", "title", "tagline", "accent", "level", "daylight", "generator", "layout", "boss", "zone_boss", "dungeon", "town"]:
			assert_true(d.has(k), "%s has %s" % [act, k])
		assert_eq(int(d["number"]), ActDefs.ACT_ORDER.find(act) + 1, "%s number" % act)
		var lay := ActDefs.layout(act)
		assert_false(lay.is_empty(), "%s layout loads" % act)
		var regs := ActDefs.regions(act)
		assert_eq(String(regs[0]["id"]), "hub", "%s: the town comes first" % act)
		assert_eq(String(regs[1]["id"]), "outskirts", "%s: then the outskirts" % act)
		assert_true(regs.size() >= 5, "%s has several zones (%d)" % [act, regs.size()])
		for r in regs:
			assert_true(String(r["name"]) != "", "%s %s name" % [act, r["id"]])
		assert_true(EnemyDB.has_def(String(d["boss"])), "%s act boss %s exists" % [act, d["boss"]])
		assert_true(EnemyDB.has_def(String(d["zone_boss"])), "%s zone boss %s exists" % [act, d["zone_boss"]])
		var dd := ActDefs.dungeon(act)
		assert_eq(String(dd["boss"]), String(d["boss"]), "%s: the act boss waits in the dungeon" % act)
		assert_true(ActDefs.region_ids(act).has(String(dd["region"])), "%s dungeon region exists" % act)
		assert_true(WorldThemes.THEMES.has(String(dd["theme"])), "%s dungeon palette exists" % act)
		assert_true(ResourceLoader.exists(String(d["generator"])), "%s generator script exists" % act)
		assert_true(ActDefs.make_generator(act) is WorldActGen, "%s generator instantiates" % act)
	assert_eq(ActDefs.next_act("forest"), "desert", "forest -> desert")
	assert_eq(ActDefs.next_act("desert"), "gothic", "desert -> gothic")
	assert_eq(ActDefs.next_act("gothic"), "", "last act")
	assert_eq(ActDefs.act_label("desert"), "Act II", "act label")
	assert_eq(ActDefs.canonical_zone("desert", "wilds"), "outskirts", "wilds = outskirts")
	assert_eq(ActDefs.zone_name("desert", "oasis"), "The Oasis", "region name from the layout")
	assert_eq(ActDefs.zone_level_offset("desert", "courtyard"), 3, "region level offset")
	assert_false(ActDefs.has_act("nope"), "unknown act")


func test_act_info() -> void:
	var info := FlowAreas.act_info("forest", "wilds", 9, 123, true)
	assert_eq(String(info["id"]), "act", "id")
	assert_eq(String(info["act"]), "forest", "act")
	assert_eq(String(info["zone"]), "outskirts", "wilds -> outskirts")
	assert_eq(int(info["level"]), 9, "level")
	assert_eq(int(info["seed"]), 123, "seed")
	assert_eq(String(info["theme"]), "forest", "theme")
	assert_eq(String(info["name"]), ActDefs.zone_name("forest", "outskirts"), "name")
	assert_true(bool(info["monsters"]), "monsters on")
	var old: Dictionary = GameState.act_options.duplicate()
	GameState.act_options["level_mode"] = "custom"
	GameState.act_options["level"] = 33
	assert_eq(int(FlowAreas.act_info("gothic", "hub")["level"]), 33, "custom level")
	var di := FlowAreas.act_dungeon_info("gothic", 5)
	assert_eq(String(di["id"]), "dungeon", "act dungeon id")
	assert_eq(String(di["act"]), "gothic", "act dungeon act")
	assert_eq(int(di["level"]), 33 + ActDefs.DUNGEON_LEVEL_OFFSET, "act dungeon level")
	assert_eq(String(di["theme"]), "undercroft", "act dungeon palette")
	assert_eq(String(di["boss"]), "boss_crimson_vicar", "the act boss in the dungeon")
	GameState.act_options["level_mode"] = "act"
	assert_eq(int(FlowAreas.act_info("gothic", "hub")["level"]), int(ActDefs.get_act("gothic")["level"]), "act level")
	GameState.act_options = old
	var t := FlowAreas.title_for(FlowAreas.act_info("desert", "hub", 5, 1))
	assert_eq(String(t[0]), ActDefs.zone_name("desert", "hub"), "title")


func test_forest_world() -> void:
	await _check_act("forest")


func test_desert_world() -> void:
	await _check_act("desert")


func test_gothic_world() -> void:
	await _check_act("gothic")


func test_layout_is_deterministic() -> void:
	for act in ActDefs.ACT_ORDER:
		var a := WorldActComposite.new().compose(act, 77, 10)
		var b := WorldActComposite.new().compose(act, 77, 10)
		assert_eq(a["start"], b["start"], "%s start" % act)
		assert_eq((a["props"] as Array).size(), (b["props"] as Array).size(), "%s props" % act)
		assert_eq((a["spawn_groups"] as Array).size(), (b["spawn_groups"] as Array).size(), "%s spawn groups" % act)
		assert_eq((a["grid"] as WorldGrid).walk, (b["grid"] as WorldGrid).walk, "%s walkability" % act)


func test_act_monster_pools() -> void:
	for act in ActDefs.ACT_ORDER:
		var pool := EnemyDB.get_pool_for_depth(10, act)
		assert_true(pool.size() >= 4, "%s pool has several monsters" % act)
		for id in pool:
			assert_true(EnemyDB.get_act_monster_ids().has(id), "%s pool only has act monsters (%s)" % [act, id])
			var d := EnemyDB.get_def(id)
			assert_false(bool(d["boss"]), "%s is not a boss" % id)
			assert_true(Assets.has_model(String(d["model"])), "%s model" % id)
	# Act monsters never leak into the Emberfall depths.
	for th in ["crypt", "cave", "inferno"]:
		for id in EnemyDB.get_pool_for_depth(20, th):
			assert_false(EnemyDB.get_act_monster_ids().has(id), "%s not in %s" % [id, th])
	for act in ActDefs.ACT_ORDER:
		for bid in [String(ActDefs.get_act(act)["boss"]), String(ActDefs.get_act(act)["zone_boss"])]:
			var boss := EnemyDB.get_def(bid)
			assert_true(bool(boss["boss"]), "%s boss flag" % bid)
			assert_near(float(boss["life_mult"]), 25.0, 0.001, "%s boss life" % bid)


func _check_act(act: String) -> void:
	var info := FlowAreas.act_info(act, "hub", 10, 4242)
	var w := await make_world(info)
	var tag := act
	assert_true(w.is_act(), "%s is an act world" % tag)
	assert_eq(w.theme, act, "%s theme" % tag)
	assert_true(w.build_time_ms < BUILD_BUDGET_MS, "%s builds in %.0f ms" % [tag, w.build_time_ms])
	var ids: Array = []
	for r in w.get_regions():
		ids.append(String(r["id"]))
	assert_eq(ids, ActDefs.region_ids(act), "%s regions" % tag)
	assert_true(w.grid.is_fully_connected(), "%s walkable area connected" % tag)
	var hub := w.get_region_arrival("hub")
	assert_true(w.is_safe_at(hub), "%s: the town is safe" % tag)
	for r in w.get_regions():
		var rid := String(r["id"])
		var arr := w.get_region_arrival(rid)
		assert_eq(w.region_at(arr), rid, "%s: %s arrival lies in it" % [tag, rid])
		assert_true(w.is_walkable(arr), "%s: %s arrival walkable" % [tag, rid])
		assert_true(w.get_path_distance(hub, arr) < INF, "%s: walk from the town to %s" % [tag, rid])
		if rid != "hub":
			assert_false(w.is_safe_at(arr), "%s: %s is not safe" % [tag, rid])
			assert_eq(w.region_level(rid), 10 + ActDefs.zone_level_offset(act, rid), "%s: %s level" % [tag, rid])
	# Walking into a deeper zone raises the area level.
	assert_true(w.region_level(ActDefs.dungeon(act)["region"]) > w.region_level("outskirts"), "%s: deeper zones are higher level" % tag)
	assert_true(w.world_environment != null and w.sun != null, "%s environment + sun" % tag)
	assert_true(w.get_light_count() <= World.MAX_LIGHTS, "%s light budget (%d)" % [tag, w.get_light_count()])
	assert_true((w.layout["props"] as Array).size() <= 12000, "%s prop budget (%d)" % [tag, (w.layout["props"] as Array).size()])
	var kinds := {}
	for n in w.get_interactables():
		var pos := (n as Node3D).position
		var region := w.region_at(pos)
		if n is WorldActWaystone or n is WorldVendorNpc or n is WorldStashChest:
			assert_eq(region, "hub", "%s %s in the town" % [tag, (n as Node).name])
		if n is WorldActWaystone:
			kinds["waystone"] = true
		elif n is WorldVendorNpc:
			kinds["vendor"] = true
		elif n is WorldStashChest:
			kinds["stash"] = true
		elif n is WorldChest:
			kinds["chest"] = int(kinds.get("chest", 0)) + 1
			assert_true(w.get_path_distance(hub, (n as Interactable).get_interact_position()) < INF, "%s chest reachable" % tag)
		elif n is WorldDungeonEntrance:
			kinds["dungeon"] = true
			var ip := (n as Interactable).get_interact_position()
			assert_eq(w.region_at(ip), String(ActDefs.dungeon(act)["region"]), "%s dungeon entrance in its zone" % tag)
			assert_true(w.is_walkable(ip), "%s dungeon door approach walkable" % tag)
			assert_true(w.get_path_distance(hub, ip) < INF, "%s dungeon entrance reachable" % tag)
			assert_true(w.is_walkable(w.get_region_arrival("dungeon_exit")), "%s dungeon exit spot walkable" % tag)
		elif n is WorldPortal:
			var wp := n as WorldPortal
			assert_false(wp.destination == "act" and wp.act_target == act, "%s: no portals between its own zones" % tag)
	for k in ["waystone", "vendor", "stash", "dungeon"]:
		assert_true(kinds.has(k), "%s has %s" % [tag, k])
	var packs := {}
	var bosses := 0
	for g in w.get_spawn_groups():
		var gp: Vector3 = g["position"]
		var gr := w.region_at(gp)
		assert_true(gr != "" and gr != "hub", "%s monster group outside the town (%s)" % [tag, gr])
		assert_true(w.get_path_distance(hub, gp) < INF, "%s group reachable" % tag)
		assert_eq(int(g.get("level", 0)), w.region_level(gr), "%s group level = its zone's" % tag)
		if String(g["kind"]) == "boss":
			bosses += 1
			assert_eq(String(g.get("enemy", "")), String(ActDefs.get_act(act)["zone_boss"]), "%s zone boss id" % tag)
			assert_eq(gr, String(ActDefs.dungeon(act)["region"]), "%s zone boss guards the dungeon's zone" % tag)
		else:
			packs[gr] = int(packs.get(gr, 0)) + 1
	assert_eq(bosses, 1, "%s one zone boss" % tag)
	for rid in ActDefs.region_ids(act):
		if rid != "hub":
			assert_true(int(packs.get(rid, 0)) >= 3, "%s: %s has packs (%d)" % [tag, rid, int(packs.get(rid, 0))])
	# Border pieces line the open edges (desert ruins, forest roundpole fences).
	if BORDER_IDS.has(act):
		var n_border := 0
		for d in w.layout["props"]:
			if String(d["id"]).begins_with(String(BORDER_IDS[act])):
				n_border += 1
		assert_true(n_border > 200, "%s border pieces (%d)" % [tag, n_border])
	remove_child(w)
	w.free()
	GameState.world = null

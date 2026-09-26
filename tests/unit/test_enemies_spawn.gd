extends TestCase
## EnemyDB.spawn_enemy (walkable snapping, parenting via world.add_enemy) and populate_area against
## real dungeon Worlds (packs, magic packs, rare packs, the boss, the 70-monster budget).
## OWNER: enemies.


func _info(depth: int, seed_value: int) -> Dictionary:
	var theme := World.theme_for_depth(depth)
	return {"id": "dungeon", "depth": depth, "level": Balance.area_level_for_depth(depth), "seed": seed_value,
		"theme": theme, "name": "Depth %d" % depth}


func test_spawn_parents_and_snaps() -> void:
	var w := await make_world()
	var e := EnemyDB.spawn_enemy("zombie", Vector3(2, 3, -1), 5)
	assert_not_null(e, "spawned")
	assert_true(e.is_inside_tree(), "returned inside the tree")
	assert_eq(e.get_parent(), w.enemies_root, "parented via world.add_enemy")
	assert_true(e.is_in_group("enemies"), "group enemies")
	assert_near(e.global_position.y, 0.0, 0.0001, "on the floor")
	assert_near(e.global_position.x, 2.0, 0.0001, "kept walkable x")
	assert_true(e.skill_runner != null and e.skill_runner.actor == e, "SkillRunner created and set up")
	assert_true(e.visuals != null and e.visuals.model != null, "model built")
	# A position inside the perimeter wall / outside the arena snaps onto walkable floor.
	var out := EnemyDB.spawn_enemy("skeleton_warrior", Vector3(40, 0, 3), 5)
	assert_not_null(out, "spawned outside")
	assert_true(w.is_walkable(out.global_position), "snapped to walkable")
	assert_true(out.global_position.x < 16.0, "inside the arena")
	assert_eq(out.home_position, out.global_position, "home = spawn point")


func test_spawn_explicit_world_and_unknown() -> void:
	var w := await make_world()
	GameState.world = null
	var e := EnemyDB.spawn_enemy("ghoul", Vector3(1, 0, 1), 3, 1, ["hasted"], w)
	assert_not_null(e, "spawned into an explicit world")
	assert_eq(e.get_parent(), w.enemies_root, "explicit world used")
	assert_eq(e.monster_mods, ["hasted"], "explicit mods")
	assert_eq(e.rarity, 1, "rarity")
	assert_true(EnemyDB.spawn_enemy("does_not_exist", Vector3.ZERO, 1, 0, [], w) == null, "unknown id -> null")
	assert_eq(EnemyDB.get_enemies(w).size(), 1, "get_enemies(world)")


func test_spawn_without_world_uses_scene() -> void:
	GameState.world = null
	var e := EnemyDB.spawn_enemy("cultist", Vector3(3, 0, 0), 2)
	assert_not_null(e, "spawned without a world")
	if e != null:
		assert_true(e.is_inside_tree(), "in the tree")
		e.queue_free()


func _check_population(w: World, depth: int) -> void:
	var groups := w.get_spawn_groups()
	var rare_groups := 0
	for g in groups:
		if String(g["kind"]) == "rare_pack":
			rare_groups += 1
	EnemyDB.populate_area(w)
	var enemies := EnemyDB.get_enemies(w)
	var bosses: Array[Enemy] = []
	var rares := 0
	var pool := EnemyDB.get_pool_for_depth(depth, w.theme)
	var by_pack := {}
	for e in enemies:
		assert_eq(e.level, Balance.area_level_for_depth(depth), "monster level = area level")
		assert_true(w.is_walkable(e.global_position), "%s on walkable floor" % e.enemy_id)
		if e.is_boss:
			bosses.append(e)
			continue
		assert_has(pool, e.enemy_id, "archetype allowed at depth %d" % depth)
		if e.rarity == 2:
			rares += 1
		if not by_pack.has(e.pack_id):
			by_pack[e.pack_id] = []
		by_pack[e.pack_id].append(e)
	assert_eq(bosses.size(), 1, "one boss")
	if bosses.size() == 1:
		assert_eq(bosses[0].enemy_id, EnemyDB.get_boss_for_depth(depth), "the depth's boss")
		assert_true(CombatQuery.distance_xz(bosses[0].global_position, w.get_boss_room_center()) < 8.0, "boss in its room")
	assert_true(enemies.size() - bosses.size() <= 70, "<= 70 monsters + boss (%d)" % enemies.size())
	assert_true(enemies.size() - bosses.size() >= 20, "a populated dungeon (%d)" % enemies.size())
	assert_eq(rares, rare_groups, "one rare per rare pack")
	for pid in by_pack:
		var members: Array = by_pack[pid]
		var kinds := {}
		var rarities := {}
		for m in members:
			kinds[(m as Enemy).enemy_id] = true
			rarities[(m as Enemy).rarity] = true
		assert_true(kinds.size() <= 2, "packs have 1-2 archetypes (%s)" % str(kinds.keys()))
		if rarities.has(2):
			assert_eq(members.filter(func(x: Enemy) -> bool: return x.rarity == 2).size(), 1, "one rare in a rare pack")
		elif rarities.has(1):
			assert_eq(rarities.size(), 1, "a magic pack is all magic")
			for m in members:
				assert_eq((m as Enemy).monster_mods, (members[0] as Enemy).monster_mods, "a magic pack shares its mod")
	# Nobody spawns right next to the player start.
	for e in enemies:
		assert_true(CombatQuery.distance_xz(e.global_position, w.get_player_start()) > 9.0, "not at the start")


func test_populate_depth_1() -> void:
	var w := await make_world(_info(1, 4242))
	_check_population(w, 1)


func test_populate_depth_6() -> void:
	var w := await make_world(_info(6, 99))
	_check_population(w, 6)


func test_populate_depth_12_mod_counts() -> void:
	var w := await make_world(_info(12, 7))
	EnemyDB.populate_area(w)
	var saw_rare := false
	for e in EnemyDB.get_enemies(w):
		match e.rarity:
			0:
				assert_eq(e.monster_mods.size(), 0, "normal no mods")
			1:
				assert_eq(e.monster_mods.size(), 1, "magic 1 mod")
			2:
				saw_rare = true
				assert_between(e.monster_mods.size(), 3, 4, "rare 3-4 mods from depth 10")
	assert_true(saw_rare, "rares present")


func test_magic_pack_rate() -> void:
	# Over several dungeons roughly 15% of the normal packs are magic.
	var packs := 0
	var magic := 0
	for s in [11, 12, 13]:
		var w := await make_world(_info(2, s))
		EnemyDB.populate_area(w)
		var seen := {}
		for e in EnemyDB.get_enemies(w):
			if e.is_boss or seen.has(e.pack_id):
				continue
			seen[e.pack_id] = true
			var has_rare := false
			for o in EnemyDB.get_enemies(w):
				if o.pack_id == e.pack_id and o.rarity == 2:
					has_rare = true
			if has_rare:
				continue
			packs += 1
			if e.rarity == 1:
				magic += 1
		w.queue_free()
		await get_tree().process_frame
	assert_true(packs >= 20, "enough packs (%d)" % packs)
	assert_between(float(magic) / float(packs), 0.0, 0.4, "magic pack share (%d/%d)" % [magic, packs])


func test_pack_composition() -> void:
	var pool := EnemyDB.get_pool_for_depth(8, "inferno")
	for primary in pool:
		for n in range(1, 7):
			for k in 6:
				var m: Array = EnemyDB._pack_members(String(primary), n, pool, false)
				assert_true(m.size() >= 1 and m.size() <= n, "%s x%d: size %d" % [primary, n, m.size()])
				var kinds := {}
				for id in m:
					kinds[id] = true
					assert_has(pool, id, "pool archetype")
				assert_true(kinds.size() <= 2, "at most two archetypes")
				assert_true(m.count(primary) >= 1, "primary present")
				for id in kinds:
					assert_true(m.count(id) <= int(EnemyDB.get_def(String(id)).get("max_per_pack", 6)), "cap %s" % id)
	# Brutes (cap 2) and necromancers (cap 1) get company to fill the pack.
	assert_eq(EnemyDB._pack_members("brute", 5, pool, false).size(), 5, "brute pack filled")
	assert_eq(EnemyDB._pack_members("necromancer", 4, pool, false).size(), 4, "necromancer pack filled")
	assert_eq(EnemyDB._pack_members("necromancer", 3, pool, true).count("necromancer"), 0, "rare necromancer escorts")


func test_populate_is_budgeted_and_safe() -> void:
	var w := await make_world()
	# The arena has no spawn groups: nothing spawns, nothing breaks.
	EnemyDB.populate_area(w)
	assert_eq(EnemyDB.get_enemies(w).size(), 0, "arena: no spawns")
	EnemyDB.populate_area(null)

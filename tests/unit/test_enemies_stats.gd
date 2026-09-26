extends TestCase
## Enemy stats (§6.2, §7, §12): life per rarity, the damage more-mod, weapon, armour, resistances,
## monster mods, boss flags, nameplate info. OWNER: enemies.


func _spawn(id: String, level: int, rarity: int, mods: Array = [], pos: Vector3 = Vector3(4, 0, 4)) -> Enemy:
	var e := EnemyDB.spawn_enemy(id, pos, level, rarity, mods)
	assert_not_null(e, "spawned %s" % id)
	return e


func test_life_per_rarity() -> void:
	await make_world()
	for id in ["zombie", "skeleton_warrior", "brute", "ghoul"]:
		var d := EnemyDB.get_def(id)
		for r in [0, 1, 2]:
			# Explicit mods so no random extra_life / regenerating mod changes the numbers.
			var e := _spawn(id, 10, r, ["berserker"] if r > 0 else [])
			var want := Balance.monster_life(10) * float(d["life_mult"]) * float(Balance.monster_rarity(r)["life"])
			assert_near(e.max_life, want, 0.01, "%s rarity %d life" % [id, r])
			assert_near(e.life, e.max_life, 0.01, "%s starts full" % id)
			assert_eq(e.rarity, r, "rarity")
			assert_eq(e.level, 10, "level")
	var boss := _spawn("boss_lich", 7, 0)
	assert_eq(boss.rarity, 3, "bosses are always rarity 3")
	assert_near(boss.max_life, Balance.monster_life(7) * 25.0, 0.01, "boss life = life_mult 25")


func test_damage_more_mod() -> void:
	await make_world()
	for id in ["zombie", "brute", "skeleton_archer", "boss_gravebreaker"]:
		var d := EnemyDB.get_def(id)
		for r in [0, 1, 2]:
			var e := _spawn(id, 12, r, ["armoured"] if r > 0 else [])
			var mult := float(d["damage_mult"]) * float(Balance.monster_rarity(e.rarity)["damage"])
			assert_near(e.stats.more("damage"), mult, 0.0001, "%s r%d damage more" % [id, e.rarity])
			var found := false
			for m in e.get_base_mods():
				if String(m["stat"]) == "damage" and String(m["op"]) == "more":
					found = true
					assert_near(float(m["value"]), (mult - 1.0) * 100.0, 0.001, "more-mod value")
			assert_eq(found, absf(mult - 1.0) > 0.0001, "%s damage more-mod present" % id)
			# Monster skill damage: monster_damage(L) x fraction x skill mult x the more-mod.
			var skill := {"id": "t", "tags": ["attack", "melee"], "monster_damage": {"physical": 1.0}, "damage_mult": 1.0}
			assert_near(DamageCalc.get_average_hit(e, skill), Balance.monster_damage(12) * mult, 0.01, "%s monster skill avg" % id)
			# Plain weapon attacks scale the same way (weapon phys = monster_damage x [0.8, 1.2]).
			var basic := {"id": "b", "tags": ["attack", "melee"]}
			assert_near(DamageCalc.get_average_hit(e, basic), Balance.monster_damage(12) * mult, 0.01, "%s weapon avg" % id)
	var boss := _spawn("boss_lich", 5, 3)
	assert_near(boss.stats.more("damage"), 2.0, 0.0001, "boss damage x2")


func test_weapon_dict() -> void:
	await make_world()
	var e := _spawn("zombie", 9, 0)
	var w := e.get_weapon()
	var avg := Balance.monster_damage(9)
	assert_eq(String(w["weapon_type"]), "monster", "weapon type")
	assert_near(float(w["phys_min"]), avg * 0.8, 0.001, "phys min")
	assert_near(float(w["phys_max"]), avg * 1.2, 0.001, "phys max (no multipliers)")
	assert_near(float(w["attack_speed"]), float(e.def["attack_speed"]), 0.001, "attack speed from def")
	assert_near(float(w["crit_chance"]), 5.0, 0.001, "crit 5")
	assert_near(float(w["range"]), float(e.def["melee_range"]), 0.001, "range = melee_range")
	assert_false(bool(w["two_handed"]), "not two handed")
	for k in ["weapon_type", "phys_min", "phys_max", "added", "attack_speed", "crit_chance", "range", "two_handed"]:
		assert_has(w, k, "weapon key")
	assert_near(DamageCalc.get_attack_speed(e), float(e.def["attack_speed"]), 0.001, "attack speed via DamageCalc")


func test_armour_and_resistances() -> void:
	await make_world()
	var e := _spawn("brute", 10, 0)
	var d := EnemyDB.get_def("brute")
	assert_near(e.armour, Balance.monster_armour(10) * float(d["armour_mult"]), 0.01, "armour")
	for t in (d["resist"] as Dictionary):
		assert_near(float(e.resistances[t]), float(d["resist"][t]), 0.01, "resist %s" % t)
	var c := _spawn("cultist", 3, 0)
	assert_near(float(c.resistances["fire"]), 40.0, 0.01, "cultist fire res")
	assert_near(float(c.resistances["cold"]), 0.0, 0.01, "cultist cold res")


func test_monster_mods_apply() -> void:
	await make_world()
	var plain := _spawn("skeleton_warrior", 10, 2, ["berserker", "vampiric"])
	var e := _spawn("skeleton_warrior", 10, 2, ["hasted", "armoured", "extra_life", "resilient"], Vector3(-4, 0, 4))
	assert_eq(e.monster_mods, ["hasted", "armoured", "extra_life", "resilient"], "mods kept")
	assert_near(e.get_move_speed(), plain.get_move_speed() * 1.3, 0.01, "hasted: +30% move speed")
	assert_near(DamageCalc.get_attack_speed(e), DamageCalc.get_attack_speed(plain) * 1.3, 0.01, "hasted: +30% attack speed")
	assert_near(DamageCalc.get_cast_speed_mult(e), 1.3, 0.01, "hasted: +30% cast speed")
	assert_near(e.max_life, plain.max_life * 1.6, 0.05, "extra_life +60% life")
	assert_near(e.armour, plain.armour * 2.0, 0.05, "armoured +100% armour")
	assert_near(float(e.resistances["physical"]), 20.0, 0.01, "armoured +20 phys reduction")
	assert_near(float(e.resistances["fire"]), 30.0, 0.01, "resilient +30 fire")
	assert_near(float(e.resistances["cold"]), 45.0, 0.01, "resilient + skeleton cold 15")
	assert_near(plain.stats.flat("life_leech"), 8.0, 0.001, "vampiric leech")
	assert_near(plain.stats.inc("damage"), 40.0, 0.001, "berserker +40% damage")
	var skill := {"id": "t", "tags": ["attack", "melee"], "monster_damage": {"physical": 1.0}}
	var mult := 1.5 * 1.4
	assert_near(DamageCalc.get_average_hit(plain, skill), Balance.monster_damage(10) * mult, 0.02, "berserker scales hits")
	var fiery := _spawn("zombie", 10, 1, ["fiery"], Vector3(4, 0, -4))
	var ranges := DamageCalc.get_damage_range(fiery, skill)
	assert_has(ranges, "fire", "fiery adds fire damage to monster attacks")
	assert_near(float(fiery.resistances["fire"]), 40.0, 0.01, "fiery fire res")
	var regen := _spawn("zombie", 10, 1, ["regenerating"], Vector3(-4, 0, -4))
	assert_near(regen.life_regen, regen.max_life * 0.02, 0.01, "2% life regen")


func test_random_mods_per_rarity() -> void:
	await make_world()
	for i in 6:
		var n := _spawn("zombie", 4, 0, [], Vector3(i - 3, 0, 2))
		assert_eq(n.monster_mods.size(), 0, "normal: none")
		var m := _spawn("zombie", 4, 1, [], Vector3(i - 3, 0, 0))
		assert_eq(m.monster_mods.size(), 1, "magic: 1 rolled mod")
		var r := _spawn("zombie", 4, 2, [], Vector3(i - 3, 0, -2))
		assert_between(r.monster_mods.size(), 2, 3, "rare: 2-3 rolled mods")


func test_boss_flags() -> void:
	await make_world()
	var b := _spawn("boss_gravebreaker", 4, 0)
	assert_true(b.is_boss, "is_boss")
	assert_true(b.is_boss_actor, "is_boss_actor for ailment rules")
	assert_true(b.is_in_group("boss"), "group boss")
	assert_true(b.is_in_group("enemies"), "group enemies")
	assert_true(b.is_in_group("team_1"), "team 1")
	assert_eq(b.team, Actor.Team.ENEMY, "enemy team")
	assert_eq(b.display_name, "Grothak the Gravebreaker", "fixed name")
	var e := _spawn("zombie", 4, 0, [], Vector3(-3, 0, 0))
	assert_false(e.is_boss_actor, "normal not boss actor")
	assert_false(e.is_in_group("boss"), "normal not in boss group")
	assert_eq(e.collision_layer, 4, "enemy layer 3")
	assert_eq(e.collision_mask, 7, "mask world+player+enemies")


func test_nameplate_info() -> void:
	await make_world()
	var n := _spawn("skeleton_warrior", 6, 0)
	var info := n.get_nameplate_info()
	for k in ["name", "subtitle", "rarity", "mods", "level", "life_ratio", "is_boss"]:
		assert_has(info, k, "nameplate key")
	assert_eq(String(info["name"]), "Skeleton Warrior", "normal name")
	assert_eq(String(info["subtitle"]), "", "normal: no subtitle")
	assert_eq(int(info["level"]), 6, "level")
	assert_near(float(info["life_ratio"]), 1.0, 0.001, "full life")
	assert_true(info["mods"] is PackedStringArray, "mods packed")
	var m := _spawn("skeleton_warrior", 6, 1, ["hasted"], Vector3(-2, 0, 0))
	var mi := m.get_nameplate_info()
	assert_eq(String(mi["subtitle"]), "Skeleton Warrior", "magic subtitle = archetype")
	assert_eq(Array(mi["mods"]), ["Hasted"], "mod display names")
	assert_true(String(mi["name"]).contains("Skeleton Warrior"), "magic name mentions the archetype")
	var r := _spawn("zombie", 6, 2, ["fiery", "hasted"], Vector3(2, 0, -3))
	var ri := r.get_nameplate_info()
	assert_eq(int(ri["rarity"]), 2, "rare")
	assert_eq(String(ri["subtitle"]), "Rotting Zombie", "rare subtitle = archetype")
	assert_eq(String(ri["name"]).split(" ").size(), 2, "rare generated name")
	assert_eq((ri["mods"] as PackedStringArray).size(), 2, "rare mods")
	var b := _spawn("boss_lich", 6, 3, [], Vector3(-5, 0, -5))
	var bi := b.get_nameplate_info()
	assert_true(bool(bi["is_boss"]), "boss flag")
	assert_eq(String(bi["subtitle"]), "", "boss: no subtitle")
	r.take_damage(r.max_life * 0.25, "physical")
	assert_near(float(r.get_nameplate_info()["life_ratio"]), 0.75, 0.02, "life ratio updates")

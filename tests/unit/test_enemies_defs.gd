extends TestCase
## EnemyDB data: archetype / boss definitions (§12 schema, §8.5 skill ids, models), spawn pools,
## bosses per depth, monster mods and rare names. OWNER: enemies.

## §8.5 (frozen ids).
const MONSTER_SKILLS: Array[String] = ["m_melee", "m_bite", "m_arrow", "m_firebolt", "m_frostbolt", "m_slam",
	"m_summon", "m_leap", "m_boss_nova", "m_boss_volley", "m_boss_charge", "m_boss_meteors", "m_boss_slam",
	"m_boss_spikes"]
const ARCHETYPES: Array[String] = ["skeleton_warrior", "skeleton_archer", "zombie", "ghoul", "cultist",
	"frost_cultist", "brute", "necromancer"]
const BOSSES: Array[String] = ["boss_lich", "boss_gravebreaker"]
const SCHEMA_KEYS: Array[String] = ["id", "name", "model", "scale", "tint", "life_mult", "damage_mult", "move_speed",
	"attack_speed", "melee_range", "aggro_radius", "xp_mult", "armour_mult", "resist", "skills", "ai",
	"preferred_range", "min_depth", "boss"]


func test_all_ids_present() -> void:
	var ids := EnemyDB.get_all_ids()
	for id in ARCHETYPES + BOSSES:
		assert_has(ids, id, "EnemyDB id")
	assert_eq(ids.size(), ARCHETYPES.size() + BOSSES.size(), "id count")
	assert_eq(EnemyDB.get_archetype_ids().size(), ARCHETYPES.size(), "archetypes")
	assert_eq(EnemyDB.get_boss_ids().size(), BOSSES.size(), "bosses")
	assert_true(EnemyDB.get_def("nope").is_empty(), "unknown id -> {}")


func test_defs_follow_schema() -> void:
	for id in EnemyDB.get_all_ids():
		var d := EnemyDB.get_def(id)
		for k in SCHEMA_KEYS:
			assert_true(d.has(k), "%s has %s" % [id, k])
		assert_eq(String(d["id"]), String(id), "id field")
		assert_true(String(d["name"]) != "", "%s name" % id)
		assert_true(float(d["life_mult"]) > 0.0 and float(d["damage_mult"]) > 0.0, "%s multipliers" % id)
		assert_between(float(d["move_speed"]), 1.5, 7.0, "%s move speed" % id)
		assert_between(float(d["attack_speed"]), 0.6, 1.5, "%s attack speed (§7)" % id)
		assert_between(float(d["aggro_radius"]), 6.0, 20.0, "%s aggro radius" % id)
		assert_true(d["tint"] is Color, "%s tint is a Color" % id)
		assert_has(["melee", "ranged", "caster", "summoner", "boss"], String(d["ai"]), "%s ai" % id)
		for t in (d["resist"] as Dictionary):
			assert_has(StatDefs.DAMAGE_TYPES, String(t), "%s resist type" % id)
		var skills: Array = d["skills"]
		assert_true(skills.size() >= 1, "%s has skills" % id)
		for s in skills:
			assert_has(MONSTER_SKILLS, String(s["id"]), "%s skill id in §8.5" % id)
			assert_true((s as Dictionary).has("range") and s.has("weight") and s.has("cooldown"), "%s skill entry keys" % id)
		if String(d["ai"]) in ["ranged", "caster", "summoner"]:
			assert_true(float(d["preferred_range"]) > 3.0, "%s preferred range" % id)


func test_archetype_skill_lists_match_contract() -> void:
	var expected := {
		"skeleton_warrior": ["m_melee"], "skeleton_archer": ["m_arrow"], "zombie": ["m_melee"],
		"ghoul": ["m_bite", "m_leap"], "cultist": ["m_firebolt"], "frost_cultist": ["m_frostbolt"],
		"brute": ["m_melee", "m_slam"], "necromancer": ["m_summon", "m_firebolt"],
		"boss_lich": ["m_boss_volley", "m_boss_nova", "m_boss_meteors", "m_summon"],
		"boss_gravebreaker": ["m_melee", "m_boss_slam", "m_boss_charge", "m_boss_spikes"],
	}
	for id in expected:
		var got: Array = []
		for s in EnemyDB.get_def(id)["skills"]:
			got.append(String(s["id"]))
		for sid in expected[id]:
			assert_has(got, sid, "%s skills" % id)
		assert_eq(got.size(), (expected[id] as Array).size(), "%s skill count" % id)


func test_contract_numbers() -> void:
	var z := EnemyDB.get_def("zombie")
	assert_near(float(z["life_mult"]), 1.8, 0.001, "zombie life")
	assert_near(float(z["damage_mult"]), 1.3, 0.001, "zombie damage")
	assert_near(float(z["move_speed"]), 2.3, 0.001, "zombie speed")
	assert_near(float(EnemyDB.get_def("skeleton_warrior")["move_speed"]), 3.6, 0.001, "skeleton speed")
	var g := EnemyDB.get_def("ghoul")
	assert_near(float(g["move_speed"]), 5.5, 0.001, "ghoul speed")
	assert_near(float(g["life_mult"]), 0.6, 0.001, "ghoul life")
	var b := EnemyDB.get_def("brute")
	assert_near(float(b["scale"]), 1.0, 0.001, "brute scale 1.0")
	assert_near(float(b["life_mult"]), 3.0, 0.001, "brute life")
	assert_between(float(EnemyDB.get_def("skeleton_archer")["preferred_range"]), 8.0, 10.0, "archer keeps 8-10 m")
	assert_eq(int(EnemyDB.get_def("necromancer")["min_depth"]), 5, "necromancer depth")
	assert_eq(String(EnemyDB.get_def("frost_cultist")["model"]), "char_cultist", "frost cultist model")
	assert_eq(String(EnemyDB.get_def("necromancer")["model"]), "char_cultist", "necromancer model")
	var fc: Color = EnemyDB.get_def("frost_cultist")["tint"]
	assert_true(fc.b > fc.r, "frost cultist tinted blue")
	var nc: Color = EnemyDB.get_def("necromancer")["tint"]
	assert_true(nc.b > nc.g and nc.r > nc.g, "necromancer tinted purple")
	for id in BOSSES:
		var d := EnemyDB.get_def(id)
		assert_true(bool(d["boss"]), "%s boss flag" % id)
		assert_near(float(d["life_mult"]), 25.0, 0.001, "%s life_mult 25" % id)
		assert_eq(String(d["ai"]), "boss", "%s ai" % id)
	for id in ARCHETYPES:
		assert_false(bool(EnemyDB.get_def(id)["boss"]), "%s is not a boss" % id)
	assert_eq(String(EnemyDB.get_def("boss_lich")["model"]), "char_lich", "lich model")
	assert_eq(String(EnemyDB.get_def("boss_gravebreaker")["model"]), "char_gravebreaker", "gravebreaker model")


func test_models_exist() -> void:
	for id in EnemyDB.get_all_ids():
		var d := EnemyDB.get_def(id)
		assert_true(Assets.has_model(String(d["model"])), "%s model %s exists" % [id, d["model"]])
		for bone in (d.get("attach", {}) as Dictionary):
			assert_true(Assets.has_model(String(d["attach"][bone])), "%s carried %s exists" % [id, d["attach"][bone]])


func test_models_have_animations() -> void:
	var needed: Array[String] = ["idle", "run", "attack_slash", "attack_slam", "attack_stab", "shoot_bow", "cast",
		"cast_area", "hit", "die"]
	var seen := {}
	for id in EnemyDB.get_all_ids():
		var mid := String(EnemyDB.get_def(id)["model"])
		if seen.has(mid):
			continue
		seen[mid] = true
		var m := Assets.model(mid)
		var ap := Assets.prepare_animations(m)
		assert_not_null(ap, "%s AnimationPlayer" % mid)
		if ap != null:
			for a in needed:
				assert_true(ap.has_animation(a), "%s has %s" % [mid, a])
			if mid in ["char_lich", "char_gravebreaker"]:
				assert_true(ap.has_animation("roar"), "%s has roar" % mid)
		m.free()


func test_get_def_is_a_copy() -> void:
	var d := EnemyDB.get_def("zombie")
	d["life_mult"] = 99.0
	(d["skills"] as Array).clear()
	var again := EnemyDB.get_def("zombie")
	assert_near(float(again["life_mult"]), 1.8, 0.001, "shared def not mutated")
	assert_eq((again["skills"] as Array).size(), 1, "skills not mutated")


func test_pool_for_depth() -> void:
	var p1 := EnemyDB.get_pool_for_depth(1)
	assert_false(p1.has("necromancer"), "no necromancers at depth 1")
	assert_false(p1.has("brute"), "no brutes at depth 1")
	assert_has(p1, "skeleton_warrior", "skeletons at depth 1")
	assert_has(p1, "zombie", "zombies at depth 1")
	var p5 := EnemyDB.get_pool_for_depth(5)
	for id in ARCHETYPES:
		assert_has(p5, id, "depth 5 pool")
	for id in p5:
		assert_true(float(p5[id]) > 0.0, "positive weight")
		assert_false(String(id).begins_with("boss_"), "no bosses in packs")
	# Theme weighting: caves favour ghouls, infernos cultists.
	var cave := EnemyDB.get_pool_for_depth(5, "cave")
	var inferno := EnemyDB.get_pool_for_depth(8, "inferno")
	assert_true(float(cave["ghoul"]) > float(cave["cultist"]), "cave: ghouls")
	assert_true(float(inferno["cultist"]) > float(inferno["zombie"]), "inferno: cultists")


func test_pick_archetype_respects_weights() -> void:
	var counts := {"a": 0, "b": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		counts[EnemyDB.pick_archetype({"a": 3.0, "b": 1.0}, rng)] += 1
	assert_between(float(counts["a"]) / 2000.0, 0.68, 0.82, "weighted pick")
	assert_eq(EnemyDB.pick_archetype({}), "skeleton_warrior", "empty pool fallback")


func test_boss_for_depth() -> void:
	for d in [1, 3, 5, 7, 59]:
		assert_eq(EnemyDB.get_boss_for_depth(d), "boss_lich", "odd depth %d" % d)
	for d2 in [2, 4, 10, 60]:
		assert_eq(EnemyDB.get_boss_for_depth(d2), "boss_gravebreaker", "even depth %d" % d2)


func test_rare_names() -> void:
	var names := {}
	for i in 60:
		var n := EnemyDB.generate_rare_name()
		var parts := n.split(" ")
		assert_eq(parts.size(), 2, "two words: %s" % n)
		assert_true(parts[0].length() >= 2 and parts[1].length() >= 2, "words: %s" % n)
		names[n] = true
	assert_true(names.size() >= 30, "varied names (%d)" % names.size())


func test_roll_mods_counts() -> void:
	for i in 40:
		assert_eq(EnemyDB.roll_mods(0, 5).size(), 0, "normal: no mods")
		assert_eq(EnemyDB.roll_mods(1, 5).size(), 1, "magic: 1 mod")
		assert_eq(EnemyDB.roll_mods(3, 5).size(), 0, "boss: no mods")
		var r1 := EnemyDB.roll_mods(2, 3)
		assert_between(r1.size(), 2, 3, "rare 2-3 mods")
		var r10 := EnemyDB.roll_mods(2, 12)
		assert_between(r10.size(), 3, 4, "rare 3-4 mods from depth 10")
		var groups := {}
		for m in r10:
			assert_has(EnemyDB.get_mod_ids(), m, "known mod")
			var g := EnemyDB.get_mod_group(String(m))
			assert_false(groups.has(g), "one mod per group")
			groups[g] = true


func test_monster_mods_are_valid_stat_mods() -> void:
	var expected: Array[String] = ["hasted", "armoured", "fiery", "frigid", "shocking", "regenerating", "vampiric",
		"berserker", "resilient", "extra_life"]
	for id in expected:
		assert_has(EnemyDB.get_mod_ids(), id, "mod id")
		assert_true(EnemyDB.get_mod_name(id) != "", "mod name")
		assert_true(EnemyDB.get_mod_description(id) != "", "mod description")
		var mods := EnemyDB.get_mod_stats(id, 10)
		assert_true(mods.size() >= 1, "%s has stat mods" % id)
		for m in mods:
			assert_true(StatDefs.has_stat(String(m["stat"])), "%s stat %s in StatDefs" % [id, m["stat"]])
			assert_has(["flat", "inc", "more", "flag"], String(m["op"]), "op")
	for el in ["fiery", "frigid", "shocking"]:
		assert_true(EnemyDB.get_mod_color(el).a > 0.0, "%s aura colour" % el)
	# Elemental added damage grows with the level.
	var lo: Dictionary = EnemyDB.get_mod_stats("fiery", 1)[0]
	var hi: Dictionary = EnemyDB.get_mod_stats("fiery", 40)[0]
	assert_true(float(hi["value"]) > float(lo["value"]) * 3.0, "added damage scales with level")


func test_model_run_speeds() -> void:
	assert_near(EnemyDB.get_model_run_speed("char_skeleton"), 5.2, 0.001, "skeleton ref")
	assert_near(EnemyDB.get_model_run_speed("char_ghoul"), 3.5, 0.001, "ghoul ref")
	assert_near(EnemyDB.get_model_run_speed("char_brute"), 5.4, 0.001, "brute ref")
	assert_true(EnemyDB.get_model_run_speed("unknown") > 0.0, "fallback")

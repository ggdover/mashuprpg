extends "res://tests/unit/test_kernel_util.gd"
## Balance curves (§7) and ClassDefs.


func test_xp_curves() -> void:
	assert_eq(Balance.xp_to_next(1), 140, "xp L1")
	assert_eq(Balance.xp_to_next(2), 359, "xp L2")
	assert_eq(Balance.xp_to_next(10), 6415, "xp L10")
	assert_eq(Balance.xp_to_next(30), 51301, "xp L30")
	assert_eq(Balance.xp_to_next(59), 185289, "xp L59")
	assert_eq(Balance.total_xp_for_level(10), 19377, "total to 10")
	assert_eq(Balance.total_xp_for_level(1), 0, "total to 1")
	assert_near(Balance.monster_xp(1), 10.9, 0.0001, "monster xp 1")
	assert_near(Balance.monster_xp(10), 89.733105, 0.0001, "monster xp 10")
	assert_near(Balance.monster_xp(50), 851.14934, 0.001, "monster xp 50")


func test_xp_penalty() -> void:
	assert_eq(Balance.xp_penalty(10, 10), 1.0, "same level")
	assert_eq(Balance.xp_penalty(10, 13), 1.0, "inside safe range (3.625)")
	assert_near(Balance.xp_penalty(10, 14), 1.0 - 0.12 * 0.375, 0.0001, "just outside")
	assert_near(Balance.xp_penalty(10, 6), 1.0 - 0.12 * 0.375, 0.0001, "symmetric below")
	assert_eq(Balance.xp_penalty(30, 1), 0.05, "floor")
	assert_eq(Balance.xp_penalty(48, 42), 1.0, "safe grows with level (6)")
	assert_near(Balance.kill_xp(10, 2.5, 10), Balance.monster_xp(10) * 2.5, 0.0001, "kill xp")


func test_monster_curves() -> void:
	assert_near(Balance.monster_life(1), 18.25, 0.0001, "life 1")
	assert_near(Balance.monster_life(10), 97.0, 0.0001, "life 10")
	assert_near(Balance.monster_life(50), 937.0, 0.0001, "life 50")
	assert_near(Balance.monster_damage(1), 5.83, 0.0001, "dmg 1")
	assert_near(Balance.monster_damage(10), 25.0, 0.0001, "dmg 10")
	assert_near(Balance.monster_damage(50), 169.0, 0.0001, "dmg 50")
	assert_near(Balance.monster_armour(5), 40.0, 0.0001, "armour")
	assert_eq(Balance.MONSTER_RARITY.size(), 4, "rarities")
	assert_near(float(Balance.MONSTER_RARITY[1]["life"]), 2.2, 0.0001, "magic life")
	assert_near(float(Balance.MONSTER_RARITY[2]["xp"]), 8.0, 0.0001, "rare xp")
	assert_near(float(Balance.MONSTER_RARITY[3]["damage"]), 2.0, 0.0001, "boss damage")
	assert_eq(Balance.monster_mod_count(2, 5), Vector2i(2, 3), "rare mods shallow")
	assert_eq(Balance.monster_mod_count(2, 10), Vector2i(3, 4), "rare mods deep")
	assert_eq(Balance.monster_mod_count(1, 30), Vector2i(1, 1), "magic mods")
	assert_eq(Balance.monster_rarity(9), Balance.MONSTER_RARITY[3], "clamped rarity")


func test_player_and_scaling_curves() -> void:
	assert_near(Balance.spell_damage_scale(1), 1.0, 0.0001, "sds 1")
	assert_near(Balance.spell_damage_scale(11), 2.95, 0.0001, "sds 11")
	assert_near(Balance.spell_damage_scale(30), 8.5835, 0.0001, "sds 30")
	assert_near(Balance.weapon_damage_scale(30), Balance.spell_damage_scale(30), 0.0001, "wds = sds")
	assert_near(Balance.mana_cost_scale(1), 1.0, 0.0001, "mcs 1")
	assert_near(Balance.mana_cost_scale(11), 1.3, 0.0001, "mcs 11")
	assert_eq(Balance.resist_penalty(1), -1.0, "res pen 1")
	assert_eq(Balance.resist_penalty(10), -8.0, "res pen 10")
	assert_eq(Balance.resist_penalty(60), -40.0, "res pen cap")
	assert_eq(Balance.player_base_life(1), 50.0, "life 1")
	assert_eq(Balance.player_base_life(10), 140.0, "life 10")
	assert_eq(Balance.player_base_mana(1), 46.0, "mana 1")
	assert_eq(Balance.player_base_mana(10), 100.0, "mana 10")
	assert_eq(Balance.gold_drop(10), 24, "gold")
	assert_eq(Balance.area_level_for_depth(7), 7, "depth")
	assert_eq(Balance.area_level_for_depth(0), 1, "depth clamp low")
	assert_eq(Balance.passive_refund_cost(10), 100, "refund")
	assert_eq(Balance.MAX_LEVEL, 60, "max level")
	assert_eq(Balance.MAX_DEPTH, 60, "max depth")
	assert_eq(Balance.PLAYER_BASE_MOVE_SPEED, 5.2, "move speed")


func test_class_defs() -> void:
	assert_eq(ClassDefs.get_class_ids().size(), 3, "3 classes")
	assert_eq(ClassDefs.get_attributes("warrior"), {"strength": 20, "dexterity": 12, "intelligence": 10}, "warrior")
	assert_eq(ClassDefs.get_attributes("ranger")["dexterity"], 20, "ranger dex")
	assert_eq(ClassDefs.get_attributes("sorcerer")["intelligence"], 20, "sorc int")
	assert_eq(ClassDefs.get_main_attribute("ranger"), "dexterity", "main attr")
	assert_eq(ClassDefs.get_display_name("sorcerer"), "Sorcerer", "name")
	var mods := ClassDefs.get_attribute_mods("warrior")
	assert_eq(mods.size(), 3, "attr mods")
	var sb := StatBlock.new()
	sb.add_mods(mods)
	assert_eq(sb.flat("strength"), 20.0, "str mod")
	var bar := ClassDefs.get_start_skill_bar("sorcerer")
	assert_eq(bar.size(), 6, "bar size")
	assert_eq(bar[0], "fireball", "sorc bar")
	assert_true(ClassDefs.get_class_def("nope").is_empty(), "unknown class")
	for cid in ClassDefs.get_class_ids():
		for base_id in ClassDefs.get_class_def(cid)["start_items"]:
			assert_false(ItemDB.get_base(base_id).is_empty(), "start item %s exists" % base_id)

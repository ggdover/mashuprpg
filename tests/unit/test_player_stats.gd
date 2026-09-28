extends TestCase
## Player stats: base mods (Balance + ClassDefs + base evasion), class attributes per class,
## equipment / passive recalculation with Events.player_stats_changed, weapon dict, the dungeon
## resistance penalty, and level up (level from the character, full heal, notification, FX,
## once per multi-level gain).


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _flat_sum(mods: Array, stat: String) -> float:
	var t := 0.0
	for m in mods:
		if m.get("stat", "") == stat and m.get("op", "") == "flat":
			t += float(m.get("value", 0.0))
	return t


func _inc_sum(mods: Array, stat: String) -> float:
	var t := 0.0
	for m in mods:
		if m.get("stat", "") == stat and m.get("op", "") == "inc":
			t += float(m.get("value", 0.0))
	return t


func test_base_mods_and_class_attributes() -> void:
	await make_world()
	for class_id in ["warrior", "ranger", "sorcerer"]:
		var c := make_character(class_id)
		var p := spawn_player(Vector3.ZERO)
		await _wait(1)
		assert_eq(p.level, 1, "level from the character")
		assert_eq(p.team, Actor.Team.PLAYER, "player team")
		var base := p.get_base_mods()
		assert_eq(_flat_sum(base, "max_life"), Balance.player_base_life(1), "%s base life" % class_id)
		assert_eq(_flat_sum(base, "max_mana"), Balance.player_base_mana(1), "%s base mana" % class_id)
		assert_eq(_flat_sum(base, "evasion"), Balance.PLAYER_BASE_EVASION, "%s base evasion" % class_id)
		var cls := ClassDefs.get_attributes(class_id)
		for a in ClassDefs.ATTRIBUTES:
			assert_eq(_flat_sum(base, a), float(cls[a]), "%s class %s" % [class_id, a])
		# Attributes: class + gear (+ passives) — matches CharacterData.compute_attributes().
		var expect := c.compute_attributes()
		var got := p.get_attributes()
		for a in ClassDefs.ATTRIBUTES:
			assert_near(float(got[a]), float(expect[a]), 0.001, "%s %s" % [class_id, a])
			assert_true(float(got[a]) >= float(cls[a]), "%s %s at least the class value" % [class_id, a])
		# Derived pools from base + gear + attribute bonuses (starting gear has no inc life/mana).
		var all := p.get_all_mods()
		var str_v := float(got["strength"])
		var int_v := float(got["intelligence"])
		var dex_v := float(got["dexterity"])
		var life := (_flat_sum(all, "max_life") + floorf(str_v / 2.0)) * (1.0 + _inc_sum(all, "max_life") / 100.0)
		assert_near(p.max_life, life, 0.01, "%s max life" % class_id)
		var mana := (_flat_sum(all, "max_mana") + floorf(int_v / 2.0)) * (1.0 + _inc_sum(all, "max_mana") / 100.0)
		assert_near(p.max_mana, mana, 0.01, "%s max mana" % class_id)
		var ev := _flat_sum(all, "evasion") * (1.0 + (floorf(dex_v / 5.0) + _inc_sum(all, "evasion")) / 100.0)
		assert_near(p.evasion, ev, 0.01, "%s evasion" % class_id)
		assert_near(p.life, p.max_life, 0.001, "spawns at full life")
		assert_eq(p.get_resist_penalty(), 0.0, "no penalty in the arena")
		assert_eq(p.resistances["fire"], _flat_sum(all, "fire_resistance") + _flat_sum(all, "elemental_resistance"), "no resist penalty outside dungeons")
		# The weapon is the main-hand item.
		var main: Item = c.get_equipped("main_hand")
		assert_not_null(main, "%s starts with a weapon" % class_id)
		if main != null:
			assert_eq(p.get_weapon()["weapon_type"], main.get_weapon_type(), "%s weapon type" % class_id)
		p.queue_free()
		GameState.player = null
		await _wait(1)


func test_equipment_changes_recalculate() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var changes := [0]
	var cb := func() -> void: changes[0] += 1
	Events.player_stats_changed.connect(cb)
	var life0 := p.max_life
	p.life = p.max_life * 0.5
	var ring := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 1)
	ring.implicit_mods = [StatBlock.mod("max_life", "flat", 25.0), StatBlock.mod("fire_resistance", "flat", 20.0)]
	var displaced := c.equip(ring, "ring_1")
	assert_eq(displaced.size(), 0, "empty ring slot")
	assert_near(p.max_life, life0 + 25.0, 0.001, "ring life added")
	assert_near(p.life / p.max_life, 0.5, 0.001, "life ratio kept")
	assert_near(p.resistances["fire"], 20.0, 0.001, "ring resistance")
	assert_true(changes[0] >= 1, "player_stats_changed emitted")
	var n: int = changes[0]
	c.unequip("ring_1")
	assert_near(p.max_life, life0, 0.001, "ring removed")
	assert_true(changes[0] > n, "emitted again")
	# Weapon swaps change get_weapon(); no weapon = unarmed.
	var axe := ItemDB.create_item("greataxe_1", Item.Rarity.NORMAL, 1)
	c.equip(axe, "main_hand")
	var w := p.get_weapon()
	assert_eq(w["weapon_type"], "axe", "greataxe weapon type")
	assert_true(bool(w["two_handed"]), "two-handed")
	c.unequip("main_hand")
	assert_eq(p.get_weapon()["weapon_type"], "unarmed", "unarmed without a weapon")
	# Body armour defences come in as flat mods (heroes start without armour).
	assert_eq(c.get_equipped("body"), null, "no starting body armour")
	var armour0 := p.armour
	var body := ItemDB.create_item("body_str_1", Item.Rarity.NORMAL, 1)
	c.equip(body, "body")
	assert_true(p.armour >= armour0 + float(body.get_defence_stats()["armour"]) - 0.01, "armour from the body armour")
	Events.player_stats_changed.disconnect(cb)


func test_passives_recalculate() -> void:
	await make_world()
	var c := make_character("ranger")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	c.add_bonus_passive_points(4)
	# First allocatable node whose single mod is flat / inc.
	var pick := -1
	for id in TreeDB.get_allocatable(c.allocated_passives, c.class_id):
		var mods: Array = TreeDB.get_passive(id).get("mods", [])
		if mods.size() == 1 and String(mods[0].get("op", "")) in ["flat", "inc"]:
			pick = id
			break
	assert_true(pick >= 0, "found an allocatable node")
	if pick < 0:
		return
	var m: Dictionary = TreeDB.get_passive(pick)["mods"][0]
	var stat := String(m["stat"])
	var op := String(m["op"])
	var is_attr := stat in ClassDefs.ATTRIBUTES
	var before := float(p.attributes[stat]) if is_attr else (p.stats.flat(stat) if op == "flat" else p.stats.inc(stat))
	var changes := [0]
	var cb := func() -> void: changes[0] += 1
	Events.player_stats_changed.connect(cb)
	assert_true(c.allocate_passive(pick), "allocated")
	Events.player_stats_changed.disconnect(cb)
	var after := float(p.attributes[stat]) if is_attr else (p.stats.flat(stat) if op == "flat" else p.stats.inc(stat))
	assert_near(after - before, float(m["value"]), 0.001, "passive %s %s %s applied" % [stat, op, m["value"]])
	assert_true(changes[0] >= 1, "player_stats_changed on passives_changed")
	var tree_mods := TreeDB.get_mods(c.allocated_passives, c.class_id)
	assert_eq(p.get_all_mods().size(), p.get_base_mods().size() + c.get_equipment_mods().size() + tree_mods.size(), "all mods = base + gear + passives")


func test_dungeon_resist_penalty() -> void:
	var w := await make_world()
	w.area_info = {"id": "dungeon", "depth": 10, "level": 10, "name": "Depth 10"}
	make_character("sorcerer")
	var p := spawn_player(Vector3.ZERO)
	await _wait(1)
	assert_true(p.is_in_dungeon(), "in a dungeon")
	assert_eq(p.get_resist_penalty(), Balance.resist_penalty(10), "penalty -8 at area level 10")
	for t in ["fire", "cold", "lightning", "chaos"]:
		assert_near(p.resistances[t], Balance.resist_penalty(10), 0.001, "%s resistance penalised" % t)
	var penalty_mods := 0
	for m in p.get_all_mods():
		if m["stat"] in ["elemental_resistance", "chaos_resistance"] and float(m["value"]) < 0.0:
			penalty_mods += 1
	assert_eq(penalty_mods, 2, "penalty as elemental + chaos flat mods")
	w.area_info = {"id": "dungeon", "depth": 60, "level": 60}
	p.recalculate_stats()
	assert_eq(p.get_resist_penalty(), -40.0, "capped at -40")
	assert_near(p.resistances["cold"], -40.0, 0.001, "cold -40")
	w.area_info = {"id": "dungeon", "depth": 5}
	assert_eq(p.get_resist_penalty(), Balance.resist_penalty(5), "level from depth when missing")
	w.area_info = {"id": "town", "level": 1}
	p.recalculate_stats()
	assert_eq(p.get_resist_penalty(), 0.0, "no penalty in town")
	assert_near(p.resistances["fire"], 0.0, 0.001, "town resistances")


func test_level_up() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var notes: Array = []
	var cb := func(text: String, _col: Color) -> void: notes.append(text)
	Events.notify.connect(cb)
	var life0 := p.max_life
	var mana0 := p.max_mana
	p.life = 5.0
	p.mana = 1.0
	c.add_xp(c.xp_to_next())
	assert_eq(c.level, 2, "character levelled")
	assert_eq(p.level, 2, "player level follows the character")
	assert_near(p.max_life, life0 + 10.0, 0.001, "+10 base life per level")
	assert_near(p.max_mana, mana0 + 6.0, 0.001, "+6 base mana per level")
	assert_near(p.life, p.max_life, 0.001, "full heal")
	assert_near(p.mana, p.max_mana, 0.001, "full mana")
	assert_has(notes, "Level 2", "level notification")
	assert_not_null(p.get_node_or_null("LevelUpFx"), "level up ring VFX")
	# Several levels at once: one celebration at the final level.
	notes.clear()
	c.add_xp(Balance.total_xp_for_level(5) - Balance.total_xp_for_level(2) - c.xp)
	assert_eq(c.level, 5, "level 5")
	assert_eq(p.level, 5, "player level 5")
	assert_eq(notes.size(), 1, "one notification for a multi-level gain")
	assert_has(notes, "Level 5", "final level announced")
	Events.notify.disconnect(cb)
	# The VFX frees itself.
	await _wait(150)
	assert_eq(p.find_children("*LevelUpFx*", "", false, false).size(), 0, "level up VFX freed")

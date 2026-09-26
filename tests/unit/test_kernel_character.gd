extends "res://tests/unit/test_kernel_util.gd"
## CharacterData (§9.1, §11): new characters, XP/levels, gold, passives, equip rules, inventory,
## stash, skill bar, potions, serialization.

## Captured Events: ["level_up:5", "equipment_changed:off_hand", "inventory_changed", ...]
var events: Array = []


func listen() -> void:
	events.clear()
	Events.level_up.connect(_on_level_up)
	Events.xp_changed.connect(_on_xp_changed)
	Events.gold_changed.connect(_on_gold)
	Events.equipment_changed.connect(_on_equipment)
	Events.inventory_changed.connect(_on_simple.bind("inventory_changed"))
	Events.stash_changed.connect(_on_simple.bind("stash_changed"))
	Events.potions_changed.connect(_on_simple.bind("potions_changed"))
	Events.passives_changed.connect(_on_simple.bind("passives_changed"))
	Events.skill_bar_changed.connect(_on_simple.bind("skill_bar_changed"))


func _on_level_up(l: int) -> void:
	events.append("level_up:%d" % l)


func _on_xp_changed(x: int, need: int, l: int) -> void:
	events.append("xp_changed:%d/%d@%d" % [x, need, l])


func _on_gold(g: int) -> void:
	events.append("gold_changed:%d" % g)


func _on_equipment(slot: String) -> void:
	events.append("equipment_changed:" + slot)


func _on_simple(name_: String) -> void:
	events.append(name_)


func item(base_id: String) -> Item:
	return ItemDB.create_item(base_id, Item.Rarity.NORMAL)


func test_new_character_per_class() -> void:
	var expected := {"warrior": ["sword_1", "body_str_1"], "ranger": ["bow_1", "body_dex_1"], "sorcerer": ["wand_1", "body_int_1"]}
	for cid in expected:
		var c := GameState.new_character("  Tester  ", cid)
		assert_eq(GameState.character, c, "current character")
		assert_eq(c.char_name, "Tester", "name trimmed")
		assert_eq(c.class_id, cid, "class")
		assert_eq(c.level, 1, "level 1")
		assert_eq(c.xp, 0, "xp 0")
		assert_eq(c.gold, 0, "gold 0")
		assert_eq(c.max_depth, 1, "depth 1")
		assert_eq(c.life_potion_charges, 3.0, "life potions")
		assert_eq(c.mana_potion_charges, 3.0, "mana potions")
		assert_eq(c.get_equipped("main_hand").base_id, expected[cid][0], "%s weapon" % cid)
		assert_eq(c.get_equipped("body").base_id, expected[cid][1], "%s armour" % cid)
		assert_eq(c.get_equipped("main_hand").rarity, Item.Rarity.NORMAL, "normal start item")
		assert_eq(c.first_free_inventory_index(), 0, "empty inventory")
		assert_eq(c.skill_bar, ClassDefs.get_start_skill_bar(cid), "skill bar")
		assert_eq(c.skill_bar.get_typed_builtin(), TYPE_STRING, "typed skill bar")
		assert_ne(GameState.save_id, "", "save id")
		assert_true(GameState.save_id.begins_with("tester_"), "sanitized save id")
		assert_true(c.allocated_passives.is_empty(), "no passives")
	var bad := GameState.new_character("", "necromancer")
	assert_eq(bad.class_id, "warrior", "unknown class falls back")
	assert_eq(bad.char_name, "Hero", "empty name")


func test_add_xp_levels() -> void:
	listen()
	var c := CharacterData.new()
	assert_eq(c.add_xp(100), 0, "no level")
	assert_eq(c.xp, 100, "xp")
	assert_eq(events, ["xp_changed:100/140@1"], "xp event")
	events.clear()
	assert_eq(c.add_xp(40), 1, "exactly one level")
	assert_eq(c.level, 2, "level 2")
	assert_eq(c.xp, 0, "xp reset")
	assert_eq(events, ["level_up:2", "xp_changed:0/359@2"], "level events")
	events.clear()
	# 359 (L2) + 580 (L3) + 10 = 949
	var need3 := Balance.xp_to_next(3)
	assert_eq(c.add_xp(359 + need3 + 10), 2, "multi level")
	assert_eq(c.level, 4, "level 4")
	assert_eq(c.xp, 10, "carry")
	assert_eq(events.slice(0, 2), ["level_up:3", "level_up:4"], "one event per level")
	assert_eq(c.add_xp(0), 0, "zero")
	assert_eq(c.add_xp(-50), 0, "negative ignored")
	assert_eq(c.xp, 10, "unchanged")
	assert_eq(c.passive_points_total(), 3, "1 point per level after 1")


func test_level_cap() -> void:
	var c := CharacterData.new()
	c.level = Balance.MAX_LEVEL - 1
	assert_eq(c.add_xp(100000000), 1, "only to the cap")
	assert_eq(c.level, Balance.MAX_LEVEL, "cap")
	assert_eq(c.xp, 0, "no xp at cap")
	assert_true(c.is_max_level(), "max")
	assert_eq(c.add_xp(1000), 0, "nothing more")
	assert_eq(c.xp, 0, "still 0")


func test_lose_xp() -> void:
	listen()
	var c := CharacterData.new()
	c.xp = 100
	c.lose_xp_fraction(0.1)
	assert_eq(c.xp, 86, "lose 10% of 140")
	assert_eq(c.last_xp_loss, 14, "last loss")
	assert_has(events, "xp_changed:86/140@1", "event")
	c.xp = 5
	c.lose_xp_fraction(0.1)
	assert_eq(c.xp, 0, "never below 0")
	assert_eq(c.level, 1, "never de-level")
	assert_eq(c.last_xp_loss, 5, "only what there was")


func test_gold() -> void:
	listen()
	var c := CharacterData.new()
	c.add_gold(50)
	assert_eq(c.gold, 50, "added")
	assert_false(c.spend_gold(60), "not enough")
	assert_eq(c.gold, 50, "unchanged")
	assert_true(c.spend_gold(20), "spent")
	assert_eq(c.gold, 30, "left")
	assert_false(c.spend_gold(-5), "negative")
	c.add_gold(-100)
	assert_eq(c.gold, 0, "floor 0")
	assert_eq(events, ["gold_changed:50", "gold_changed:30", "gold_changed:0"], "events")


func test_passives() -> void:
	listen()
	var c := CharacterData.new()
	c.class_id = "warrior"
	assert_eq(c.passive_points_unspent(), 0, "no points at level 1")
	c.add_bonus_passive_points(2)
	assert_eq(c.bonus_passive_points, 2, "bonus")
	assert_has(events, "passives_changed", "event")
	c.level = 5
	assert_eq(c.passive_points_total(), 6, "4 + 2")
	assert_eq(c.passive_points_unspent(), 6, "unspent")
	assert_eq(c.refund_cost(), Balance.passive_refund_cost(5), "refund cost")
	if not TreeDB.is_loaded():
		print("    [info] TreeDB stub: testing rejection only")
		assert_false(c.allocate_passive(12345), "stub tree: nothing allocatable")
		assert_false(c.refund_passive(12345), "stub tree: nothing to refund")
		return
	var start: int = TreeDB.get_start_node("warrior")
	var first := -1
	for n in TreeDB.get_neighbors(start):
		if TreeDB.can_allocate([], int(n), "warrior"):
			first = int(n)
			break
	assert_true(first >= 0, "a node next to the start")
	print("    [info] real TreeDB: allocating node %d next to start %d" % [first, start])
	events.clear()
	assert_true(c.allocate_passive(first), "allocated")
	assert_eq(c.allocated_passives, [first] as Array[int], "stored")
	assert_eq(events, ["passives_changed"], "event")
	assert_false(c.allocate_passive(first), "twice")
	assert_eq(c.passive_points_unspent(), 5, "point spent")
	assert_false(c.refund_passive(first), "no gold")
	c.add_gold(c.refund_cost())
	assert_true(c.refund_passive(first), "refunded")
	assert_eq(c.gold, 0, "paid")
	assert_true(c.allocated_passives.is_empty(), "removed")
	c.level = 1
	c.bonus_passive_points = 0
	assert_false(c.allocate_passive(first), "no points")


func test_can_equip_rules() -> void:
	var c := GameState.new_character("T", "warrior")
	var ring := item("ring_1")
	assert_false(c.can_equip(ring, "helmet").get("ok"), "wrong slot type")
	assert_true(c.can_equip(ring, "ring_2").get("ok"), "ring slot")
	assert_false(c.can_equip(ring, "nope").get("ok"), "unknown slot")
	assert_false(c.can_equip(null, "ring_1").get("ok"), "null")
	var wand := item("wand_1")
	assert_true(c.can_equip(wand, "main_hand").get("ok"), "warrior has 10 int (own attributes)")
	var r: Dictionary = c.can_equip(wand, "main_hand", {"strength": 50, "dexterity": 50, "intelligence": 5})
	assert_false(r.get("ok"), "attributes passed in")
	assert_eq(r.get("reason"), "Requires 10 Intelligence", "reason text")
	var attrs := c.compute_attributes()
	assert_eq(attrs["strength"], 20.0, "class strength")
	assert_eq(attrs["intelligence"], 10.0, "class int")
	# Level requirement (only with a real item database that has higher-tier bases).
	for b in ItemDB.get_all_bases():
		var base: Dictionary = b if b is Dictionary else ItemDB.get_base(String(b))
		if int(base.get("level", 1)) > 1:
			var hi := ItemDB.create_item(String(base["id"]))
			var slot := c.get_default_slot_for(hi)
			var res: Dictionary = c.can_equip(hi, slot, {"strength": 999, "dexterity": 999, "intelligence": 999})
			assert_false(res.get("ok"), "level requirement")
			assert_true(String(res.get("reason")).begins_with("Requires Level"), "level reason")
			print("    [info] level requirement checked with base %s (level %d)" % [base["id"], int(base["level"])])
			break


func test_two_hander_displaces_offhand() -> void:
	listen()
	var c := CharacterData.new()
	var sword := item("sword_1")
	var shield := item("shield_str_1")
	assert_eq(c.equip(sword, "main_hand"), [], "empty slot")
	assert_true(c.can_equip(shield, "off_hand").get("ok"), "shield with 1h")
	c.equip(shield, "off_hand")
	var axe := item("greataxe_1")
	assert_eq(c.get_equip_conflicts(axe, "main_hand"), ["off_hand"] as Array[String], "conflict preview")
	events.clear()
	var displaced := c.equip(axe, "main_hand")
	assert_eq(displaced, [sword, shield], "previous weapon and shield displaced")
	assert_eq(c.get_equipped("main_hand"), axe, "axe equipped")
	assert_eq(c.get_equipped("off_hand"), null, "off hand emptied")
	assert_has(events, "equipment_changed:main_hand", "main event")
	assert_has(events, "equipment_changed:off_hand", "off event")
	var r: Dictionary = c.can_equip(shield, "off_hand")
	assert_false(r.get("ok"), "shield with a 2h")
	assert_eq(r.get("reason"), "Requires a one-handed weapon", "reason")
	assert_eq(c.equip(shield, "off_hand"), [shield], "refused: item handed back")
	assert_eq(c.get_equipped("off_hand"), null, "nothing changed")
	assert_eq(c.unequip("main_hand"), axe, "unequip")
	assert_true(c.can_equip(shield, "off_hand").get("ok"), "shield with an empty main hand")


func test_quiver_rules() -> void:
	var c := CharacterData.new()
	c.class_id = "ranger"
	var bow := item("bow_1")
	var quiver := item("quiver_1")
	c.equip(bow, "main_hand")
	assert_true(c.can_equip(quiver, "off_hand").get("ok"), "quiver with bow")
	c.equip(quiver, "off_hand")
	var xbow := item("crossbow_1")
	assert_eq(c.equip(xbow, "main_hand"), [bow], "quiver kept with a crossbow")
	assert_eq(c.get_equipped("off_hand"), quiver, "quiver stays")
	var sword := item("sword_1")
	assert_eq(c.get_equip_conflicts(sword, "main_hand"), ["off_hand"] as Array[String], "1h melee drops the quiver")
	assert_eq(c.equip(sword, "main_hand"), [xbow, quiver], "displaced")
	var r: Dictionary = c.can_equip(quiver, "off_hand")
	assert_false(r.get("ok"), "quiver with a sword")
	assert_true(String(r.get("reason")).contains("Bow"), "reason")
	c.unequip("main_hand")
	assert_true(c.can_equip(quiver, "off_hand").get("ok"), "quiver with an empty main hand")
	var axe := item("greataxe_1")
	c.equip(quiver, "off_hand")
	assert_eq(c.equip(axe, "main_hand"), [quiver], "a melee 2h drops the quiver")


func test_default_slot_and_ring_swap() -> void:
	listen()
	var c := CharacterData.new()
	var r1 := item("ring_1")
	var r2 := item("ring_1")
	var r3 := item("ring_1")
	assert_eq(c.get_default_slot_for(r1), "ring_1", "first empty")
	c.equip(r1, "ring_1")
	assert_eq(c.get_default_slot_for(r2), "ring_2", "second ring slot")
	c.equip(r2, "ring_2")
	assert_eq(c.get_default_slot_for(r3), "ring_1", "both full: first matching")
	assert_eq(c.get_default_slot_for(item("body_str_1")), "body", "body")
	assert_eq(c.get_default_slot_for(item("quiver_1")), "off_hand", "offhand")
	assert_eq(c.get_default_slot_for(null), "", "null")
	events.clear()
	assert_eq(c.equip(r1, "ring_2"), [], "moving swaps")
	assert_eq(c.get_equipped("ring_2"), r1, "r1 moved")
	assert_eq(c.get_equipped("ring_1"), r2, "r2 swapped in")
	assert_eq(c.find_equipped_slot(r2), "ring_1", "find slot")
	assert_has(events, "equipment_changed:ring_1", "both slots changed")
	assert_eq(c.equip(r1, "ring_2"), [], "same slot is a no-op")
	assert_eq(c.equip(item("ring_1"), "main_hand").size(), 1, "wrong slot handed back")


func test_equipment_mods() -> void:
	var c := GameState.new_character("T", "warrior")
	var expected := 0
	for slot in CharacterData.EQUIP_SLOTS:
		var it := c.get_equipped(slot)
		if it != null:
			expected += it.get_global_mods().size()
	assert_eq(c.get_equipment_mods().size(), expected, "all equipped items' global mods")


func test_inventory_ops() -> void:
	listen()
	var c := CharacterData.new()
	assert_eq(c.inventory.size(), 60, "10×6")
	var a := item("ring_1")
	var b := item("sword_1")
	assert_true(c.add_to_inventory(a), "add")
	assert_true(c.add_to_inventory(b), "add 2")
	assert_false(c.add_to_inventory(a), "no duplicates")
	assert_false(c.add_to_inventory(null), "null")
	assert_eq(c.inventory[0], a, "first cell")
	assert_eq(c.find_inventory_index(b), 1, "find")
	c.move_inventory(0, 5)
	assert_eq(c.inventory[5], a, "moved")
	assert_eq(c.inventory[0], null, "old cell empty")
	c.move_inventory(1, 5)
	assert_eq(c.inventory[5], b, "swapped")
	assert_eq(c.inventory[1], a, "swapped back")
	var d := item("wand_1")
	assert_eq(c.put_in_inventory(1, d), a, "put returns previous")
	assert_eq(c.put_in_inventory(1, null), d, "put null clears")
	assert_eq(c.put_in_inventory(99, a), a, "bad index hands the item back")
	assert_eq(c.take_from_inventory(5), b, "take")
	assert_eq(c.take_from_inventory(5), null, "empty")
	assert_eq(c.take_from_inventory(-1), null, "bad index")
	for i in 60:
		c.add_to_inventory(item("ring_1"))
	assert_eq(c.first_free_inventory_index(), -1, "full")
	assert_eq(c.inventory_free_count(), 0, "no free cells")
	assert_false(c.add_to_inventory(item("ring_1")), "full inventory")
	assert_true(c.remove_from_inventory(c.inventory[10]), "remove by item")
	assert_eq(c.inventory_free_count(), 1, "one free")
	assert_true(events.count("inventory_changed") >= 60, "events")


func test_stash_ops() -> void:
	listen()
	var c := CharacterData.new()
	assert_eq(c.stash.size(), 120, "stash size")
	var a := item("ring_1")
	assert_true(c.add_to_stash(a), "add")
	assert_eq(events, ["stash_changed"], "event")
	c.move_stash(0, 119)
	assert_eq(c.stash[119], a, "move")
	var b := item("bow_1")
	assert_eq(c.put_in_stash(119, b), a, "put returns previous")
	assert_eq(c.take_from_stash(119), b, "take")
	assert_eq(c.put_in_stash(500, a), a, "bad index")
	assert_eq(c.first_free_stash_index(), 0, "free")
	for i in 120:
		c.add_to_stash(item("ring_1"))
	assert_false(c.add_to_stash(item("ring_1")), "full stash")


func test_skill_bar() -> void:
	listen()
	var c := CharacterData.new()
	c.set_skill_in_slot(0, "cleave")
	c.set_skill_in_slot(2, "fireball")
	assert_eq(c.skill_bar, ["cleave", "", "fireball", "", "", ""] as Array[String], "set")
	c.set_skill_in_slot(0, "fireball")
	assert_eq(c.skill_bar, ["fireball", "", "cleave", "", "", ""] as Array[String], "swap")
	c.set_skill_in_slot(1, "fireball")
	assert_eq(c.skill_bar, ["", "fireball", "cleave", "", "", ""] as Array[String], "move into empty slot")
	c.set_skill_in_slot(2, "")
	assert_eq(c.get_skill_in_slot(2), "", "clear")
	c.set_skill_in_slot(9, "x")
	assert_eq(c.skill_bar.size(), 6, "bad slot ignored")
	assert_eq(events.count("skill_bar_changed"), 5, "one event per valid call")


func test_potions() -> void:
	listen()
	var c := CharacterData.new()
	assert_true(c.consume_potion_charge("life"), "use")
	assert_eq(c.life_potion_charges, 2.0, "2 left")
	assert_eq(c.mana_potion_charges, 3.0, "mana untouched")
	c.add_potion_charges(0.5)
	assert_eq(c.life_potion_charges, 2.5, "added")
	assert_eq(c.mana_potion_charges, 3.0, "clamped")
	c.consume_potion_charge("life")
	c.consume_potion_charge("life")
	assert_eq(c.life_potion_charges, 0.5, "half charge")
	assert_false(c.consume_potion_charge("life"), "need a full charge")
	for i in 2:
		c.add_potion_charges(0.25)
	assert_true(c.consume_potion_charge("life"), "0.25 steps add up")
	assert_false(c.consume_potion_charge("elixir"), "unknown kind")
	c.refill_potions()
	assert_eq(c.get_potion_charges("life"), 3.0, "refilled")
	assert_eq(c.get_potion_charges("mana"), 3.0, "refilled mana")
	assert_true(events.count("potions_changed") >= 6, "events")


func test_serialization_round_trip() -> void:
	var c := GameState.new_character("Round Trip", "ranger")
	c.add_xp(300)
	c.add_gold(1234)
	c.add_bonus_passive_points(2)
	c.allocated_passives.assign([5, 17, 23])
	c.set_skill_in_slot(4, "power_shot")
	c.consume_potion_charge("mana")
	c.max_depth = 7
	c.cleared_depths.assign([1, 2, 3])
	c.play_time = 321.5
	var inv_item := item("crossbow_1")
	c.put_in_inventory(13, inv_item)
	var stash_item := item("ring_1")
	c.put_in_stash(42, stash_item)
	c.equip(item("quiver_1"), "off_hand")
	var text := JSON.stringify(c.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "json")
	var r := CharacterData.from_dict(parsed)
	assert_eq(r.char_name, "Round Trip", "name")
	assert_eq(r.class_id, "ranger", "class")
	assert_eq(r.level, c.level, "level")
	assert_eq(typeof(r.level), TYPE_INT, "int level")
	assert_eq(r.xp, c.xp, "xp")
	assert_eq(r.gold, 1234, "gold")
	assert_eq(typeof(r.gold), TYPE_INT, "int gold")
	assert_eq(r.bonus_passive_points, 2, "bonus")
	assert_eq(r.allocated_passives, [5, 17, 23] as Array[int], "passives")
	assert_eq(r.allocated_passives.get_typed_builtin(), TYPE_INT, "typed int array")
	assert_eq(typeof(r.allocated_passives[0]), TYPE_INT, "int ids")
	assert_eq(r.skill_bar, c.skill_bar, "skill bar")
	assert_eq(r.skill_bar.get_typed_builtin(), TYPE_STRING, "typed skill bar")
	assert_eq(r.mana_potion_charges, 2.0, "potions")
	assert_eq(r.max_depth, 7, "depth")
	assert_eq(r.cleared_depths, [1, 2, 3] as Array[int], "cleared")
	assert_eq(r.cleared_depths.get_typed_builtin(), TYPE_INT, "typed cleared")
	assert_near(r.play_time, 321.5, 0.001, "play time")
	assert_eq(r.get_equipped("main_hand").base_id, "bow_1", "weapon")
	assert_eq(r.get_equipped("main_hand").uid, c.get_equipped("main_hand").uid, "uid kept")
	assert_eq(r.get_equipped("off_hand").base_id, "quiver_1", "quiver")
	assert_eq(r.get_equipped("body").base_id, "body_dex_1", "armour")
	assert_eq((r.inventory[13] as Item).base_id, "crossbow_1", "inventory position")
	assert_eq((r.inventory[13] as Item).uid, inv_item.uid, "inventory uid")
	assert_eq((r.stash[42] as Item).base_id, "ring_1", "stash position")
	assert_eq(r.inventory.size(), 60, "inventory size")
	assert_eq(r.stash.size(), 120, "stash size")
	assert_true(Item._next_uid > inv_item.uid, "uid counter past loaded items")
	assert_eq(JSON.stringify(r.to_dict()), text, "stable round trip")


func test_from_dict_robustness() -> void:
	var d := {
		"char_name": "Old", "class_id": "bard", "level": 5.0, "xp": 12.0, "gold": -5.0,
		"equipment": {"main_hand": {"uid": 900.0, "base_id": "sword_1", "rarity": 0.0, "item_level": 1.0}, "tail": {"base_id": "ring_1"}},
		"inventory": [{"index": 3.0, "item": {"uid": 901.0, "base_id": "ring_1"}}, {"index": 3.0, "item": {"uid": 902.0, "base_id": "ring_1"}}, {"index": 4.0, "item": {"base_id": "no_such_base"}}],
		"stash": [null, {"uid": 903.0, "base_id": "bow_1"}],
		"allocated_passives": [3.0, 3.0, 9.0],
		"skill_bar": ["fireball", null],
		"life_potion_charges": 99.0,
		"max_depth": 500.0,
		"cleared_depths": [2.0],
	}
	var c := CharacterData.from_dict(d)
	assert_eq(c.class_id, "warrior", "unknown class")
	assert_eq(c.level, 5, "float level")
	assert_eq(c.gold, 0, "negative gold")
	assert_eq(c.get_equipped("main_hand").uid, 900, "equipped uid")
	assert_false(c.equipment.has("tail"), "unknown slot skipped")
	assert_eq((c.inventory[3] as Item).uid, 901, "index 3")
	assert_eq((c.inventory[0] as Item).uid, 902, "collision goes to the first free cell")
	assert_eq(c.inventory[4], null, "unknown base dropped")
	assert_eq((c.stash[1] as Item).uid, 903, "dense stash format")
	assert_eq(c.allocated_passives, [3, 9] as Array[int], "deduplicated ints")
	assert_eq(c.skill_bar, ["fireball", "", "", "", "", ""] as Array[String], "padded bar")
	assert_eq(c.life_potion_charges, 3.0, "clamped charges")
	assert_eq(c.max_depth, Balance.MAX_DEPTH, "clamped depth")
	assert_true(Item._next_uid > 903, "uid bumped")
	var empty := CharacterData.from_dict({})
	assert_eq(empty.level, 1, "defaults")
	assert_eq(empty.skill_bar.size(), 6, "default bar")


func test_equip_from_inventory() -> void:
	var c := GameState.new_character("T", "warrior")
	var sword: Item = c.get_equipped("main_hand")
	var shield := item("shield_str_1")
	c.put_in_inventory(5, shield)
	var r := c.equip_from_inventory(5)
	assert_true(r.get("ok"), "shield equipped")
	assert_eq(c.get_equipped("off_hand"), shield, "in the off hand")
	assert_eq(c.inventory[5], null, "cell freed")
	var axe := item("greataxe_1")
	c.put_in_inventory(9, axe)
	assert_true(c.equip_from_inventory(9).get("ok"), "two-hander equipped")
	assert_eq(c.get_equipped("main_hand"), axe, "axe")
	assert_eq(c.get_equipped("off_hand"), null, "shield displaced")
	assert_eq(c.inventory[9], sword, "old weapon took the freed cell")
	assert_true(c.inventory.has(shield), "shield back in the inventory")
	var wand := item("wand_1")
	c.put_in_inventory(20, wand)
	var bad := c.equip_from_inventory(20, "main_hand", {"strength": 0, "dexterity": 0, "intelligence": 0})
	assert_false(bad.get("ok"), "requirements checked")
	assert_eq(c.inventory[20], wand, "item stays")
	assert_false(c.equip_from_inventory(33).get("ok"), "empty cell")
	# Full inventory: a two-hander displacing two items needs two cells.
	c.equip_from_inventory(c.find_inventory_index(sword))
	c.equip_from_inventory(c.find_inventory_index(shield))
	var axe_idx := c.find_inventory_index(axe)
	for i in c.inventory.size():
		if c.inventory[i] == null:
			c.put_in_inventory(i, item("ring_1"))
	var full := c.equip_from_inventory(axe_idx)
	assert_false(full.get("ok"), "no room for sword + shield")
	assert_eq(full.get("reason"), "Inventory full", "reason")
	assert_eq(c.get_equipped("off_hand"), shield, "nothing changed")
	assert_false(c.unequip_to_inventory("off_hand"), "full inventory")
	c.take_from_inventory(0)
	assert_true(c.unequip_to_inventory("off_hand"), "unequipped")
	assert_eq(c.inventory[0], shield, "into the free cell")
	assert_false(c.unequip_to_inventory("off_hand"), "empty slot")

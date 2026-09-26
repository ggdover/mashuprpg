extends TestCase
## Random generation statistics (§9.5), vendor stock (§9.7) and crafting.


func test_rarity_weights() -> void:
	assert_eq(ItemDB.get_rarity_weights(0.0, 0), [72.0, 22.0, 5.5, 0.5] as Array[float], "base weights")
	var w := ItemDB.get_rarity_weights(100.0, 0)
	assert_near(w[0], 72.0, 0.001, "normal weight fixed")
	assert_near(w[1], 44.0, 0.001, "magic ×2")
	assert_near(w[3], 1.0, 0.001, "unique ×2")
	var mw := ItemDB.get_rarity_weights(0.0, 1)
	assert_near(mw[2], 5.5 * 1.5, 0.001, "magic monster +50")
	var rw := ItemDB.get_rarity_weights(0.0, 2)
	assert_near(rw[2], 5.5 * 2.5, 0.001, "rare monster +150")
	var bw := ItemDB.get_rarity_weights(20.0, 3)
	assert_near(bw[1], 22.0 * 5.2, 0.001, "boss +400 plus player bonus")


func test_rarity_distribution() -> void:
	seed(1)
	var n := 20000
	var c := [0, 0, 0, 0]
	for i in n:
		c[ItemDB.roll_rarity()] += 1
	assert_between(float(c[0]) / n, 0.70, 0.74, "normal 72%")
	assert_between(float(c[1]) / n, 0.20, 0.24, "magic 22%")
	assert_between(float(c[2]) / n, 0.045, 0.065, "rare 5.5%")
	assert_between(float(c[3]) / n, 0.002, 0.009, "unique 0.5%")
	# Boss drops are much richer.
	var b := [0, 0, 0, 0]
	for i in 5000:
		b[ItemDB.roll_rarity(0.0, 3)] += 1
	assert_between(float(b[0]) / 5000.0, 0.28, 0.40, "boss normal share (72/262)")
	assert_true(b[2] > 5000 * 0.08, "boss rares common")


func test_slot_type_weights() -> void:
	seed(2)
	var n := 6000
	var counts := {}
	for i in n:
		var it := ItemDB.generate_random_item(30, Item.Rarity.NORMAL)
		var s := it.get_slot_type()
		counts[s] = counts.get(s, 0) + 1
	var expected := {"weapon": 18, "offhand": 8, "helmet": 10, "body": 10, "gloves": 10, "boots": 10, "ring": 14, "amulet": 10, "belt": 10}
	for s: String in expected:
		var share := float(counts.get(s, 0)) / n
		var e := float(expected[s]) / 100.0
		assert_between(share, e - 0.025, e + 0.025, "%s share %.3f" % [s, share])


func test_base_tier_choice() -> void:
	seed(3)
	var n := 4000
	var tiers := {}
	for i in n:
		var it := ItemDB.generate_random_item(30, Item.Rarity.NORMAL, "body")
		var t := it.get_tier()
		tiers[t] = tiers.get(t, 0) + 1
		assert_true(int(it.get_base()["level"]) <= 30, "no base above item level")
	# ilvl 30: highest tier with level <= 30 is tier 4 (26).
	assert_between(float(tiers.get(4, 0)) / n, 0.66, 0.74, "top tier 70%")
	assert_between(float(tiers.get(3, 0)) / n, 0.21, 0.29, "next lower 25%")
	assert_between(float(tiers.get(1, 0) + tiers.get(2, 0)) / n, 0.03, 0.07, "any lower 5%")
	assert_eq(tiers.get(5, 0) + tiers.get(6, 0), 0, "no higher tiers")
	# Level 1: always tier 1; level 8: tiers 1-2 only.
	for i in 200:
		assert_eq(ItemDB.generate_random_item(1).get_tier(), 1, "ilvl 1 tier 1")
		assert_true(ItemDB.generate_random_item(8).get_tier() <= 2, "ilvl 8 tiers 1-2")


func test_generate_random_item_options() -> void:
	seed(4)
	for s in Item.SLOT_TYPES:
		for i in 20:
			var it := ItemDB.generate_random_item(25, -1, s)
			assert_eq(it.get_slot_type(), s, "slot filter " + s)
			assert_eq(it.item_level, 25, "item level")
	for i in 20:
		var bow := ItemDB.generate_random_item(40, Item.Rarity.MAGIC, "bow")
		assert_eq(bow.get_base()["category"], "bow", "category filter")
		assert_eq(bow.rarity, Item.Rarity.MAGIC, "fixed rarity")
	# Uniques: need a unique with level <= ilvl (and matching slot).
	for i in 30:
		var u := ItemDB.generate_random_item(60, Item.Rarity.UNIQUE)
		assert_eq(u.rarity, Item.Rarity.UNIQUE, "unique at ilvl 60")
		assert_true(u.unique_id != "" and u.item_level == 60, "unique id + ilvl")
	assert_eq(ItemDB.generate_random_item(1, Item.Rarity.UNIQUE).rarity, Item.Rarity.RARE, "no unique that low: rare instead")
	var belt := ItemDB.generate_random_item(20, Item.Rarity.UNIQUE, "belt")
	assert_eq(belt.unique_id, "seraphs_cord", "unique belt")
	# create_item with rarity UNIQUE on a base that has a unique.
	assert_eq(ItemDB.create_item("axe_3", Item.Rarity.UNIQUE, 20).unique_id, "gorebinder", "unique by base")
	assert_eq(ItemDB.create_item("axe_2", Item.Rarity.UNIQUE, 20).rarity, Item.Rarity.RARE, "no unique for base -> rare")


func test_create_item_defaults() -> void:
	var it := ItemDB.create_item("sword_1")
	assert_eq(it.item_level, 1, "ilvl = base level")
	assert_eq(it.rarity, Item.Rarity.NORMAL, "normal")
	assert_eq(it.affixes.size(), 0, "no affixes")
	assert_eq(it.implicit_mods.size(), 1, "implicit rolled")
	assert_eq(it.get_display_name(), "Rusted Sword", "name")
	var hi := ItemDB.create_item("wand_4", Item.Rarity.MAGIC, 33)
	assert_eq(hi.item_level, 33, "explicit ilvl")
	assert_between(float(hi.implicit_mods[0]["value"]), 14.0, 18.0, "wand_4 implicit range")
	# Unknown base: warning, but a usable item.
	var bad := ItemDB.create_item("nope_9", Item.Rarity.RARE, 5)
	assert_not_null(bad, "item for unknown base")
	assert_eq(bad.get_display_name() != "", true, "has some name")
	assert_true(bad.get_tooltip_lines().size() > 0, "tooltip still works")
	var bad_u := ItemDB.create_unique("nope")
	assert_not_null(bad_u, "fallback item for unknown unique")


func test_vendor_stock_guarantees() -> void:
	seed(6)
	for lvl in [1, 5, 8, 12, 26, 37, 50, 60]:
		for rep in 4:
			var stock := ItemDB.generate_vendor_stock(lvl)
			assert_eq(stock.size(), 12, "12 items")
			var tier := ItemDB.tier_for_level(lvl)
			var melee := false
			var ranged := false
			var caster := false
			for it: Item in stock:
				assert_true(it is Item, "Item instances")
				assert_eq(it.item_level, lvl, "vendor ilvl = area level")
				assert_true(it.rarity <= Item.Rarity.RARE, "no uniques at vendors")
				assert_true(int(it.get_base()["level"]) <= lvl, "base usable at this level")
				var cat: String = it.get_base()["category"]
				if it.get_tier() == tier:
					if cat in ItemDB.MELEE_CATEGORIES:
						melee = true
					elif cat in ["bow", "crossbow"]:
						ranged = true
					elif cat in ["wand", "staff"]:
						caster = true
			assert_true(melee, "melee weapon at current tier (lvl %d)" % lvl)
			assert_true(ranged, "bow/crossbow at current tier (lvl %d)" % lvl)
			assert_true(caster, "wand/staff at current tier (lvl %d)" % lvl)
	assert_eq(ItemDB.generate_vendor_stock(10, 20).size(), 20, "custom count")
	# Sorted by slot type.
	var st := ItemDB.generate_vendor_stock(20)
	for i in range(1, st.size()):
		assert_true(Item.SLOT_TYPES.find((st[i - 1] as Item).get_slot_type()) <= Item.SLOT_TYPES.find((st[i] as Item).get_slot_type()), "sorted by slot")


func test_crafting_reroll() -> void:
	seed(7)
	var normal := ItemDB.create_item("ring_2", Item.Rarity.NORMAL, 20)
	assert_false(ItemDB.reroll_affixes(normal), "normal items can't be rerolled")
	assert_eq(ItemDB.reroll_cost(normal), 0, "no reroll cost for normal")
	var unique := ItemDB.create_unique("voidheart_ring")
	var before_u := JSON.stringify(unique.to_dict())
	assert_false(ItemDB.reroll_affixes(unique), "uniques can't be rerolled")
	assert_eq(JSON.stringify(unique.to_dict()), before_u, "unique unchanged")
	assert_false(ItemDB.reroll_affixes(null), "null tolerated")
	var changed := 0
	for i in 30:
		var magic := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 20)
		var old := JSON.stringify(magic.affixes)
		assert_true(ItemDB.reroll_affixes(magic), "magic reroll")
		assert_eq(magic.rarity, Item.Rarity.MAGIC, "stays magic")
		assert_between(magic.affixes.size(), 1, 2, "magic affix count")
		if JSON.stringify(magic.affixes) != old:
			changed += 1
	assert_true(changed > 20, "rerolls change the affixes")
	var rare := ItemDB.create_item("gloves_str_3", Item.Rarity.RARE, 30)
	assert_true(ItemDB.reroll_affixes(rare), "rare reroll")
	assert_between(rare.affixes.size(), 3, 6, "rare affix count")
	assert_true(rare.name != "", "rare keeps a name")
	var m10 := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 10)
	assert_eq(ItemDB.reroll_cost(m10), 80, "magic reroll 20 + 6 × ilvl")
	var r10 := ItemDB.create_item("ring_2", Item.Rarity.RARE, 10)
	assert_eq(ItemDB.reroll_cost(r10), 210, "rare reroll 60 + 15 × ilvl")


func test_crafting_upgrade() -> void:
	seed(8)
	for i in 40:
		var it := ItemDB.create_item("boots_dex_3", Item.Rarity.NORMAL, 25)
		assert_eq(ItemDB.upgrade_cost(it), 30 + 5 * 25, "normal -> magic cost")
		assert_true(ItemDB.upgrade_rarity(it), "normal -> magic")
		assert_eq(it.rarity, Item.Rarity.MAGIC, "now magic")
		assert_between(it.affixes.size(), 1, 2, "1-2 affixes")
		assert_eq(ItemDB.upgrade_cost(it), 150 + 20 * 25, "magic -> rare cost")
		var old_ids: Array = []
		for a: Dictionary in it.affixes:
			old_ids.append(a["id"])
		var n_before := it.affixes.size()
		assert_true(ItemDB.upgrade_rarity(it), "magic -> rare")
		assert_eq(it.rarity, Item.Rarity.RARE, "now rare")
		assert_true(it.affixes.size() > n_before and it.affixes.size() >= 3 and it.affixes.size() <= 6, "rare adds affixes (%d)" % it.affixes.size())
		for j in old_ids.size():
			assert_eq(it.affixes[j]["id"], old_ids[j], "keeps the magic affixes")
		assert_true(it.name != "", "rare named")
		var np := 0
		var ns := 0
		for a: Dictionary in it.affixes:
			if a["kind"] == "prefix":
				np += 1
			else:
				ns += 1
		assert_true(np <= 3 and ns <= 3, "rare limits after upgrade")
		assert_false(ItemDB.upgrade_rarity(it), "rare can't be upgraded")
		assert_eq(ItemDB.upgrade_cost(it), 0, "no upgrade cost for rare")
	assert_false(ItemDB.upgrade_rarity(ItemDB.create_unique("mindwell")), "unique can't be upgraded")
	assert_false(ItemDB.upgrade_rarity(null), "null tolerated")

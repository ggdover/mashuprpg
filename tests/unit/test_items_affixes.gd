extends TestCase
## Affix pool, uniques and generation constraints (docs §9.3–9.5).

const TIER_ILVLS := [1, 8, 16, 26, 38, 50]
const WEAPON_LOCAL := ["local_physical_damage", "local_added_physical", "local_added_fire", "local_added_cold", "local_added_lightning", "local_added_chaos", "local_attack_speed", "local_crit_chance"]
const ARMOUR_LOCAL := ["local_armour", "local_evasion", "local_energy_shield", "local_block"]



func test_affix_schema() -> void:
	var affixes := ItemDB.get_all_affixes()
	assert_true(affixes.size() >= 50, "rich affix pool (%d)" % affixes.size())
	var n_pre := 0
	var n_suf := 0
	for a: Dictionary in affixes:
		var id: String = a["id"]
		assert_has(["prefix", "suffix"], a["kind"], id + " kind")
		if a["kind"] == "prefix":
			n_pre += 1
		else:
			n_suf += 1
		assert_true(String(a["group"]) != "", id + " group")
		assert_true(int(a["weight"]) > 0, id + " weight")
		assert_false((a["slot_types"] as Array).is_empty(), id + " slot types")
		for s in a["slot_types"]:
			assert_has(Item.SLOT_TYPES, s, id + " slot type")
		var tiers: Array = a["tiers"]
		assert_eq(tiers.size(), 6, id + " has 6 tiers")
		for i in tiers.size():
			var t: Dictionary = tiers[i]
			assert_eq(int(t["tier"]), i + 1, id + " tier number")
			assert_eq(int(t["ilvl"]), TIER_ILVLS[i], id + " tier ilvl")
			var nm: String = t["name"]
			assert_true(nm != "", id + " tier name")
			if a["kind"] == "suffix":
				assert_true(nm.begins_with("of "), "%s suffix name '%s' starts with 'of '" % [id, nm])
			else:
				assert_false(nm.begins_with("of "), "%s prefix name '%s'" % [id, nm])
			for m: Dictionary in t["mods"]:
				assert_true(StatDefs.has_stat(m["stat"]), "%s stat %s exists" % [id, m["stat"]])
				assert_has(["flat", "inc", "more", "flag"], m["op"], id + " op")
				assert_true(float(m["min"]) <= float(m["max"]), id + " min <= max")
				if m.has("min2"):
					assert_true(StatDefs.is_range(m["stat"]), id + " range values only on range stats")
					assert_true(float(m["min2"]) <= float(m["max2"]) and float(m["min"]) <= float(m["min2"]), id + " range ordering")
				elif StatDefs.is_range(m["stat"]):
					fail(id + " range stat without min2/max2")
			if i > 0:
				var prev: Dictionary = tiers[i - 1]["mods"][0]
				assert_true(float(t["mods"][0]["max"]) >= float(prev["max"]), id + " values grow with tier")
	assert_true(n_pre >= 25 and n_suf >= 25, "prefixes %d / suffixes %d" % [n_pre, n_suf])


func test_reference_values() -> void:
	var life := ItemDB.get_affix("max_life")
	var exp_life := [[10, 19], [20, 29], [30, 44], [45, 59], [60, 79], [80, 99]]
	for i in 6:
		var m: Dictionary = life["tiers"][i]["mods"][0]
		assert_eq([int(m["min"]), int(m["max"])], exp_life[i], "max_life tier %d" % (i + 1))
	var res := ItemDB.get_affix("fire_resistance")
	var exp_res := [[6, 11], [12, 17], [18, 23], [24, 29], [30, 35], [36, 42]]
	for i in 6:
		var m: Dictionary = res["tiers"][i]["mods"][0]
		assert_eq([int(m["min"]), int(m["max"])], exp_res[i], "fire res tier %d" % (i + 1))
	var str_a := ItemDB.get_affix("strength")
	assert_eq(int(str_a["tiers"][0]["mods"][0]["min"]), 10, "attribute min 10")
	assert_eq(int(str_a["tiers"][5]["mods"][0]["max"]), 40, "attribute max 40")
	assert_has(str_a["slot_types"], "amulet", "amulets roll attributes")


func test_local_affixes_on_the_right_slots() -> void:
	for a: Dictionary in ItemDB.get_all_affixes():
		var stat: String = a["tiers"][0]["mods"][0]["stat"]
		if stat in WEAPON_LOCAL:
			assert_eq(a["slot_types"], ["weapon"], a["id"] + " weapon-local only on weapons")
		elif stat in ARMOUR_LOCAL:
			for s in a["slot_types"]:
				assert_has(["offhand", "helmet", "body", "gloves", "boots"], s, a["id"] + " armour-local slot")
		else:
			assert_false(StatDefs.is_local(stat), a["id"] + " unexpected local stat")
	# Global added attack damage only on rings, amulets, gloves, quivers.
	var ga := ItemDB.get_affix("added_fire_attack")
	for bid in ["ring_2", "amulet_3", "gloves_str_2", "quiver_4"]:
		assert_true(ItemDB.affix_allowed_on_base(ga, ItemDB.get_base(bid)), "added fire attack on " + bid)
	for bid in ["sword_2", "shield_str_2", "focus_2", "body_dex_3", "boots_int_1", "belt_1"]:
		assert_false(ItemDB.affix_allowed_on_base(ga, ItemDB.get_base(bid)), "no added fire attack on " + bid)
	# Local armour only on bases with armour.
	var la := ItemDB.get_affix("local_armour")
	assert_true(ItemDB.affix_allowed_on_base(la, ItemDB.get_base("body_str_dex_2")), "armour on str/dex body")
	assert_false(ItemDB.affix_allowed_on_base(la, ItemDB.get_base("body_dex_int_2")), "no armour on dex/int body")
	assert_false(ItemDB.affix_allowed_on_base(la, ItemDB.get_base("quiver_2")), "no armour on quivers")
	# Spell affixes on caster weapons, foci and amulets; movement speed on boots only.
	var sd := ItemDB.get_affix("spell_damage")
	for bid in ["wand_1", "staff_3", "focus_1", "amulet_1"]:
		assert_true(ItemDB.affix_allowed_on_base(sd, ItemDB.get_base(bid)), "spell damage on " + bid)
	for bid in ["sword_1", "bow_2", "shield_int_2", "ring_1"]:
		assert_false(ItemDB.affix_allowed_on_base(sd, ItemDB.get_base(bid)), "no spell damage on " + bid)
	assert_eq(ItemDB.get_affix("movement_speed")["slot_types"], ["boots"], "movement speed on boots")
	assert_eq(ItemDB.get_affix("local_block")["tags"], ["shield"], "local block on shields")


func test_every_base_can_roll_a_full_rare() -> void:
	for b: Dictionary in ItemDB.get_all_bases():
		var id: String = b["id"]
		var pre := ItemDB.get_affixes_for_base(id, "prefix")
		var suf := ItemDB.get_affixes_for_base(id, "suffix")
		var groups_p := {}
		for a in pre:
			groups_p[ItemDB.get_affix(a)["group"]] = true
		var groups_s := {}
		for a in suf:
			groups_s[ItemDB.get_affix(a)["group"]] = true
		assert_true(groups_p.size() >= 3, "%s has >= 3 prefix groups (%d)" % [id, groups_p.size()])
		assert_true(groups_s.size() >= 3, "%s has >= 3 suffix groups (%d)" % [id, groups_s.size()])


func test_magic_generation_constraints() -> void:
	seed(101)
	for i in 400:
		var ilvl := randi_range(1, 60)
		var it := ItemDB.generate_random_item(ilvl, Item.Rarity.MAGIC)
		assert_eq(it.rarity, Item.Rarity.MAGIC, "magic rarity")
		var n := it.affixes.size()
		assert_true(n >= 1 and n <= 2, "magic affix count %d" % n)
		_check_affixes(it, 1, 1)
		assert_eq(it.name, "", "magic items have derived names")


func test_rare_generation_constraints() -> void:
	seed(202)
	var counts := {}
	for i in 400:
		var ilvl := randi_range(1, 60)
		var it := ItemDB.generate_random_item(ilvl, Item.Rarity.RARE)
		assert_eq(it.rarity, Item.Rarity.RARE, "rare rarity")
		var n := it.affixes.size()
		counts[n] = counts.get(n, 0) + 1
		assert_true(n >= 3 and n <= 6, "rare affix count %d (%s)" % [n, it.base_id])
		_check_affixes(it, 3, 3)
		assert_eq(it.name.split(" ").size(), 2, "rare name has two words: " + it.name)
		assert_eq(it.get_display_name(), it.name, "rare display name")
	for n in [3, 4, 5, 6]:
		assert_true(counts.get(n, 0) > 10, "rare with %d affixes occurs" % n)


func _check_affixes(it: Item, max_p: int, max_s: int) -> void:
	var base := it.get_base()
	var groups := {}
	var np := 0
	var ns := 0
	for a: Dictionary in it.affixes:
		var def := ItemDB.get_affix(a["id"])
		assert_false(def.is_empty(), "affix %s exists" % a["id"])
		assert_eq(a["kind"], def["kind"], "affix kind matches")
		if a["kind"] == "prefix":
			np += 1
		else:
			ns += 1
		assert_false(groups.has(def["group"]), "one affix per group on %s (%s)" % [it.base_id, def["group"]])
		groups[def["group"]] = true
		assert_true(ItemDB.affix_allowed_on_base(def, base), "%s allowed on %s" % [a["id"], it.base_id])
		var tier: Dictionary = def["tiers"][int(a["tier"]) - 1]
		assert_true(int(tier["ilvl"]) <= it.item_level, "tier ilvl %d <= item level %d" % [tier["ilvl"], it.item_level])
		assert_eq(a["name"], tier["name"], "affix name = tier name")
		var mult: float = def["two_handed_mult"] if it.is_two_handed() else 1.0
		for j in (a["mods"] as Array).size():
			var m: Dictionary = a["mods"][j]
			var t: Dictionary = tier["mods"][j]
			var lo := roundf(float(t["min"]) * mult * 10.0) / 10.0
			var hi := roundf(float(t["max"]) * mult * 10.0) / 10.0
			assert_between(float(m["value"]), lo - 0.51, hi + 0.51, "%s value in tier range" % a["id"])
			if t.has("min2"):
				assert_true(m.has("value2"), a["id"] + " range mod has value2")
				assert_true(float(m["value2"]) >= float(m["value"]), a["id"] + " value2 >= value")
				assert_between(float(m["value2"]), roundf(float(t["min2"]) * mult) - 0.51, roundf(float(t["max2"]) * mult) + 0.51, "%s value2 in range" % a["id"])
			if int(t.get("decimals", 0)) == 0:
				assert_near(float(m["value"]), roundf(float(m["value"])), 0.0001, a["id"] + " integer value")
	assert_true(np <= max_p, "prefixes %d <= %d" % [np, max_p])
	assert_true(ns <= max_s, "suffixes %d <= %d" % [ns, max_s])


func test_item_level_gating() -> void:
	seed(303)
	for i in 200:
		var it := ItemDB.generate_random_item(1, Item.Rarity.RARE)
		assert_eq(int(it.get_base()["level"]), 1, "ilvl 1 drops tier-1 bases")
		for a: Dictionary in it.affixes:
			assert_eq(int(a["tier"]), 1, "ilvl 1 rolls tier-1 affixes")
	for i in 200:
		var it := ItemDB.generate_random_item(12, Item.Rarity.RARE)
		assert_true(int(it.get_base()["level"]) <= 12, "base level <= ilvl")
		for a: Dictionary in it.affixes:
			assert_true(int(a["tier"]) <= 2, "ilvl 12 rolls tiers 1-2")
	# High item levels mostly roll high tiers.
	var high := 0
	var total := 0
	for i in 200:
		var it := ItemDB.generate_random_item(60, Item.Rarity.RARE)
		for a: Dictionary in it.affixes:
			total += 1
			if int(a["tier"]) >= 5:
				high += 1
	assert_true(float(high) / total > 0.45, "ilvl 60: tiers 5-6 common (%.2f)" % (float(high) / total))


func test_all_stats_exist_in_statdefs() -> void:
	for b: Dictionary in ItemDB.get_all_bases():
		for m: Dictionary in b["implicits"]:
			assert_true(StatDefs.has_stat(m["stat"]), "base stat " + String(m["stat"]))
	for a: Dictionary in ItemDB.get_all_affixes():
		for t: Dictionary in a["tiers"]:
			for m: Dictionary in t["mods"]:
				assert_true(StatDefs.has_stat(m["stat"]), "affix stat " + String(m["stat"]))
	for u: Dictionary in ItemDB.get_all_uniques():
		for m: Dictionary in u["mods"]:
			assert_true(StatDefs.has_stat(m["stat"]), "unique stat " + String(m["stat"]))
			assert_has(["flat", "inc", "more", "flag"], m["op"], "unique op")


func test_uniques_valid() -> void:
	var ids := ItemDB.get_unique_ids()
	assert_true(ids.size() >= 12 and ids.size() <= 15, "12-15 uniques (%d)" % ids.size())
	var doc := {"Gorebinder": "axe", "Emberheart": "staff", "Windshear": "bow", "Frostbite Grips": "gloves",
		"Stormcrown": "helmet", "Wanderer's Steps": "boots", "Bulwark of the Fallen": "shield",
		"Bloodbond Plate": "body", "Voidheart Ring": "ring", "Glasswork Amulet": "amulet",
		"The Arbalest": "crossbow", "Seraph's Cord": "belt"}
	var by_name := {}
	for u: Dictionary in ItemDB.get_all_uniques():
		by_name[u["name"]] = u
		assert_true(ItemDB.has_base(u["base"]), u["name"] + " base exists")
		assert_true(String(u["flavour"]).length() > 10, u["name"] + " has flavour text")
		assert_true((u["mods"] as Array).size() >= 3, u["name"] + " has mods")
		assert_eq(int(u["level"]), int(ItemDB.get_base(u["base"])["level"]), u["name"] + " level = base level")
	for n: String in doc:
		assert_true(by_name.has(n), "unique %s exists" % n)
		if not by_name.has(n):
			continue
		var b := ItemDB.get_base(by_name[n]["base"])
		var kind: String = doc[n]
		assert_true(b["slot_type"] == kind or b["weapon_type"] == kind, "%s is a %s (%s)" % [n, kind, b["id"]])
	seed(5)
	for uid in ids:
		var it := ItemDB.create_unique(uid)
		var u := ItemDB.get_unique(uid)
		assert_eq(it.rarity, Item.Rarity.UNIQUE, uid + " rarity")
		assert_eq(it.unique_id, uid, uid + " id")
		assert_eq(it.get_display_name(), u["name"], uid + " name")
		assert_eq(it.affixes.size(), 1, uid + " one unique affix entry")
		assert_eq(it.affixes[0]["kind"], "unique", uid + " kind unique")
		var mods: Array = it.affixes[0]["mods"]
		assert_eq(mods.size(), (u["mods"] as Array).size(), uid + " all mods rolled")
		for j in mods.size():
			var t: Dictionary = u["mods"][j]
			var m: Dictionary = mods[j]
			if t.has("value"):
				assert_near(m["value"], float(t["value"]), 0.001, uid + " fixed value")
			else:
				assert_between(m["value"], float(t["min"]) - 0.01, float(t["max"]) + 0.01, uid + " value in range")
		assert_eq(it.item_level, int(u["level"]), uid + " default item level")
		assert_true(it.get_tint() != it.get_base()["tint"] or not u.has("tint"), uid + " unique tint override")
	var glass := ItemDB.create_unique("glasswork_amulet")
	var gm := glass.get_global_mods()
	assert_true(_has_mod(gm, "damage", "more", 30.0), "glasswork 30% more damage")
	assert_true(_has_mod(gm, "max_life", "more", -25.0), "glasswork 25% less life")
	assert_true(_has_mod(ItemDB.create_unique("bloodbond_plate").get_global_mods(), "blood_magic", "flag", 1.0), "bloodbond blood magic")
	assert_true(_has_mod(ItemDB.create_unique("the_arbalest").get_global_mods(), "pierce", "flat", 3.0), "arbalest +3 pierce")
	assert_true(_has_mod(ItemDB.create_unique("windshear").get_global_mods(), "additional_projectiles", "flat", 2.0), "windshear +2 projectiles")
	assert_true(_has_mod(ItemDB.create_unique("wanderers_steps").get_global_mods(), "movement_speed", "inc", 30.0), "wanderer 30% move speed")


func _has_mod(mods: Array, stat: String, op: String, value: float) -> bool:
	for m: Dictionary in mods:
		if m["stat"] == stat and m["op"] == op and (op == "flag" or absf(float(m["value"]) - value) < 0.001):
			return true
	return false

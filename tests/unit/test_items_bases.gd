extends TestCase
## Item bases (docs §9.2): categories, tiers, requirements, weapon numbers, defences, models.

const TIER_LEVELS := [1, 8, 16, 26, 38, 50]
const WEAPON_TEMPLATES := {
	# category: [weapon_type, two_handed, min, max, aps, crit, range]
	"sword": ["sword", false, 7, 15, 1.45, 5, 2.2],
	"axe": ["axe", false, 8, 18, 1.30, 5, 2.2],
	"mace": ["mace", false, 9, 17, 1.25, 5, 2.2],
	"dagger": ["dagger", false, 5, 13, 1.60, 8, 1.8],
	"wand": ["wand", false, 4, 9, 1.40, 7, 20.0],
	"greatsword": ["sword", true, 13, 25, 1.20, 5, 2.7],
	"greataxe": ["axe", true, 14, 30, 1.10, 5, 2.7],
	"maul": ["mace", true, 17, 31, 1.00, 5, 2.7],
	"staff": ["staff", true, 11, 21, 1.15, 6, 2.6],
	"bow": ["bow", true, 9, 21, 1.40, 5, 20.0],
	"crossbow": ["crossbow", true, 16, 30, 1.00, 6, 20.0],
}
## Attribute requirements per weapon category (§9.2).
const WEAPON_REQ := {
	"sword": ["strength", "dexterity"], "axe": ["strength"], "mace": ["strength"], "maul": ["strength"],
	"greataxe": ["strength"], "greatsword": ["strength"], "dagger": ["dexterity", "intelligence"],
	"wand": ["intelligence"], "staff": ["strength", "intelligence"], "bow": ["dexterity"],
	"crossbow": ["dexterity", "strength"],
}
const ATTR := {"str": "strength", "dex": "dexterity", "int": "intelligence"}


func test_required_stub_ids_keep_semantics() -> void:
	var expect := {
		"sword_1": ["weapon", "sword", false], "greataxe_1": ["weapon", "axe", true],
		"bow_1": ["weapon", "bow", true], "crossbow_1": ["weapon", "crossbow", true],
		"wand_1": ["weapon", "wand", false], "shield_str_1": ["offhand", "shield", false],
		"quiver_1": ["offhand", "quiver", false], "body_str_1": ["body", "", false],
		"body_dex_1": ["body", "", false], "body_int_1": ["body", "", false], "ring_1": ["ring", "", false],
	}
	for id: String in expect:
		var b := ItemDB.get_base(id)
		assert_false(b.is_empty(), "required base %s exists" % id)
		assert_eq(b.get("slot_type"), expect[id][0], id + " slot")
		assert_eq(b.get("weapon_type"), expect[id][1], id + " weapon_type")
		assert_eq(b.get("two_handed"), expect[id][2], id + " two_handed")
		assert_eq(int(b.get("level")), 1, id + " level")
	assert_eq(ItemDB.get_base("sword_1")["name"], "Rusted Sword", "starting sword name")
	assert_near(ItemDB.get_base("body_str_1")["armour"], 15.0, 0.01, "body_str_1 armour")
	assert_near(ItemDB.get_base("body_dex_1")["evasion"], 50.0, 0.01, "body_dex_1 evasion")
	assert_near(ItemDB.get_base("body_int_1")["energy_shield"], 12.0, 0.01, "body_int_1 es")
	assert_near(ItemDB.get_base("shield_str_1")["armour"], 9.0, 0.01, "shield_str_1 armour")
	assert_near(ItemDB.get_base("shield_str_1")["block"], 20.0, 0.01, "shield_str_1 block")
	assert_near(ItemDB.get_base("sword_1")["phys_min"], 7.0, 0.01, "sword_1 phys_min")
	assert_near(ItemDB.get_base("sword_1")["phys_max"], 15.0, 0.01, "sword_1 phys_max")
	# Class starting items must be creatable.
	for cid in ClassDefs.get_class_ids():
		for bid: String in ClassDefs.get_class_def(cid)["start_items"]:
			assert_true(ItemDB.has_base(bid), "start item %s exists" % bid)


func test_categories_and_six_tiers() -> void:
	var cats := ItemDB.get_categories()
	assert_eq(ItemDB.get_categories("weapon").size(), 11, "weapon categories")
	assert_eq(ItemDB.get_categories("offhand").size(), 5, "offhand categories")
	for slot in ["helmet", "body", "gloves", "boots"]:
		assert_eq(ItemDB.get_categories(slot).size(), 6, slot + " categories (str/dex/int + hybrids)")
	for slot in ["ring", "amulet", "belt"]:
		assert_eq(ItemDB.get_categories(slot).size(), 1, slot + " categories")
	assert_eq(cats.size(), 43, "total categories")
	for cat in cats:
		var ids := ItemDB.get_category_bases(cat)
		assert_eq(ids.size(), 6, cat + " has 6 tiers")
		for t in ids.size():
			assert_eq(ids[t], "%s_%d" % [cat, t + 1], "tier id")
			var b := ItemDB.get_base(ids[t])
			assert_eq(int(b["level"]), TIER_LEVELS[t], ids[t] + " level")
			assert_eq(int(b["tier"]), t + 1, ids[t] + " tier")
			assert_eq(b["category"], cat, ids[t] + " category")
	assert_eq(ItemDB.get_all_bases().size(), 258, "43 categories x 6 tiers")


func test_base_fields_valid() -> void:
	var names := {}
	for b: Dictionary in ItemDB.get_all_bases():
		var id: String = b["id"]
		var slot: String = b["slot_type"]
		assert_has(Item.SLOT_TYPES, slot, id + " slot type")
		assert_true(String(b["name"]) != "", id + " has a name")
		assert_false(names.has(b["name"]), "duplicate base name %s" % b["name"])
		names[b["name"]] = true
		assert_true(b["tint"] is Color, id + " tint is a Color")
		assert_has(b["tags"], slot, id + " tagged with its slot")
		var model: String = b["model"]
		match slot:
			"weapon":
				assert_eq(model, "weapon_" + String(b["category"]), id + " model")
				assert_has(StatDefs.WEAPON_TYPES, b["weapon_type"], id + " weapon type")
				assert_false(b["weapon_type"] in ["unarmed", "monster"], id + " real weapon type")
			"offhand":
				assert_has(["shield", "quiver", "focus"], b["weapon_type"], id + " offhand type")
				assert_eq(model, "offhand_" + String(b["weapon_type"]), id + " model")
			"helmet":
				assert_true(model.begins_with("armor_helmet_") and model.substr(13) in ["str", "dex", "int"], id + " helmet model " + model)
			"body", "gloves", "boots":
				assert_eq(model, "armor_" + slot, id + " model")
			_:
				assert_eq(model, "jewel_" + slot, id + " model")
		for m: Dictionary in b["implicits"]:
			assert_true(StatDefs.has_stat(m["stat"]), "%s implicit stat %s exists" % [id, m["stat"]])
			assert_true(float(m.get("min", 0)) <= float(m.get("max", 0)), id + " implicit min <= max")


func test_requirement_formula() -> void:
	for b: Dictionary in ItemDB.get_all_bases():
		var id: String = b["id"]
		var it := ItemDB.create_item(id)
		var req := it.get_requirements()
		var level := int(b["level"])
		assert_eq(req["level"], level, id + " level requirement")
		var attrs: Array = []
		var cat: String = b["category"]
		match String(b["slot_type"]):
			"weapon":
				attrs = WEAPON_REQ[cat]
			"offhand":
				attrs = {"shield_str": ["strength"], "shield_dex": ["dexterity"], "shield_int": ["intelligence"], "focus": ["intelligence"], "quiver": ["dexterity"]}[cat]
			"helmet", "body", "gloves", "boots":
				for a in cat.split("_").slice(1):
					attrs.append(ATTR[a])
		var expected := {"strength": 0, "dexterity": 0, "intelligence": 0}
		for a in attrs:
			expected[a] = int(roundf(5.0 + level)) if attrs.size() > 1 else int(roundf(8.0 + 1.6 * level))
		for a in expected:
			assert_eq(req[a], expected[a], "%s %s requirement" % [id, a])


func test_weapon_numbers_scale_with_effective_level() -> void:
	for cat: String in WEAPON_TEMPLATES:
		var t: Array = WEAPON_TEMPLATES[cat]
		for bid in ItemDB.get_category_bases(cat):
			var b := ItemDB.get_base(bid)
			assert_eq(b["weapon_type"], t[0], bid + " weapon type")
			assert_eq(b["two_handed"], t[1], bid + " two handed")
			var lvl := int(b["level"])
			for ilvl in [lvl, lvl + 5, lvl + 12, lvl + 30]:
				var it := ItemDB.create_item(bid, Item.Rarity.NORMAL, ilvl)
				it.implicit_mods = []   # sword implicit is local attack speed
				var w := it.get_weapon_stats()
				var eff := mini(ilvl, lvl + 12)
				var s := Balance.weapon_damage_scale(eff)
				assert_near(w["phys_min"], roundf(float(t[2]) * s), 0.01, "%s@%d phys_min" % [bid, ilvl])
				assert_near(w["phys_max"], roundf(float(t[3]) * s), 0.01, "%s@%d phys_max" % [bid, ilvl])
				assert_near(w["attack_speed"], t[4], 0.001, bid + " aps")
				assert_near(w["crit_chance"], t[5], 0.001, bid + " crit")
				assert_near(w["range"], t[6], 0.001, bid + " range")
				assert_eq(w["weapon_type"], t[0], bid + " weapon dict type")
				assert_eq(w["two_handed"], t[1], bid + " weapon dict two handed")
				assert_true(w["added"] is Dictionary and (w["added"] as Dictionary).is_empty(), bid + " no added damage")
			# Base numbers are the values at the base level.
			assert_near(b["phys_min"], roundf(float(t[2]) * Balance.weapon_damage_scale(lvl)), 0.01, bid + " base phys_min")
	# Higher tiers are never worse at the same item level.
	for cat: String in WEAPON_TEMPLATES:
		var prev := 0.0
		for bid in ItemDB.get_category_bases(cat):
			var it := ItemDB.create_item(bid, Item.Rarity.NORMAL, 60)
			it.implicit_mods = []
			var avg := float(it.get_weapon_stats()["phys_max"])
			assert_true(avg >= prev, bid + " not worse than lower tier at ilvl 60")
			prev = avg


func test_weapon_implicits_per_doc() -> void:
	var expect := {"wand": ["spell_damage"], "staff": ["spell_damage", "block_chance"], "dagger": ["crit_chance"],
		"mace": ["area_damage"], "maul": ["area_damage"], "axe": ["bleed_chance"], "greataxe": ["bleed_chance"],
		"sword": ["local_attack_speed"], "greatsword": ["local_attack_speed"], "crossbow": ["pierce"], "bow": []}
	for cat: String in expect:
		for bid in ItemDB.get_category_bases(cat):
			var stats: Array = []
			for m: Dictionary in ItemDB.get_base(bid)["implicits"]:
				stats.append(m["stat"])
			assert_eq(stats, expect[cat], bid + " implicits")
	for bid in ItemDB.get_category_bases("focus"):
		assert_eq(ItemDB.get_base(bid)["implicits"][0]["stat"], "spell_damage", bid + " focus implicit")
	for bid in ItemDB.get_category_bases("quiver"):
		var st: String = ItemDB.get_base(bid)["implicits"][0]["stat"]
		assert_true(st in ["added_physical_attack", "projectile_speed", "added_fire_attack"], bid + " quiver implicit " + st)


func test_defence_numbers() -> void:
	var slot_factor := {"body": 1.0, "helmet": 0.45, "gloves": 0.35, "boots": 0.35}
	for slot: String in slot_factor:
		for cat in ItemDB.get_categories(slot):
			var kinds := cat.split("_").slice(1)
			var factor: float = slot_factor[slot] * (0.6 if kinds.size() > 1 else 1.0)
			for bid in ItemDB.get_category_bases(cat):
				var lvl := int(ItemDB.get_base(bid)["level"])
				for ilvl in [lvl, lvl + 7, lvl + 40]:
					var d := ItemDB.create_item(bid, Item.Rarity.NORMAL, ilvl).get_defence_stats()
					var e := float(mini(ilvl, lvl + 12) - 1)
					var exp_armour := roundf((15.0 + 7.5 * e) * factor) if "str" in kinds else 0.0
					var exp_eva := roundf((50.0 + 9.0 * e) * factor) if "dex" in kinds else 0.0
					var exp_es := roundf((12.0 + 3.2 * e) * factor) if "int" in kinds else 0.0
					assert_near(d["armour"], exp_armour, 0.01, "%s@%d armour" % [bid, ilvl])
					assert_near(d["evasion"], exp_eva, 0.01, "%s@%d evasion" % [bid, ilvl])
					assert_near(d["energy_shield"], exp_es, 0.01, "%s@%d es" % [bid, ilvl])
					assert_near(d["block"], 0.0, 0.01, bid + " block")
	# Shields: 60% of body + block; focus: ES only.
	var sd := ItemDB.create_item("shield_dex_3", Item.Rarity.NORMAL, 16).get_defence_stats()
	assert_near(sd["evasion"], roundf((50.0 + 9.0 * 15.0) * 0.6), 0.01, "shield_dex_3 evasion")
	assert_true(sd["block"] >= 20.0, "buckler block")
	var fd := ItemDB.create_item("focus_2", Item.Rarity.NORMAL, 8).get_defence_stats()
	assert_true(fd["energy_shield"] > 0.0 and fd["block"] == 0.0 and fd["armour"] == 0.0, "focus defences")
	# Jewellery and weapons have no defences.
	for bid in ["ring_3", "amulet_2", "belt_4", "sword_2", "bow_5"]:
		var dd := ItemDB.create_item(bid).get_defence_stats()
		assert_eq(dd, {"armour": 0.0, "evasion": 0.0, "energy_shield": 0.0, "block": 0.0}, bid + " no defences")


func test_tints_per_tier_and_attribute() -> void:
	for cat in ["sword", "bow", "body_str", "helmet_dex", "gloves_int"]:
		var seen := {}
		for bid in ItemDB.get_category_bases(cat):
			seen[(ItemDB.get_base(bid)["tint"] as Color).to_html()] = true
		assert_true(seen.size() >= 5, cat + " tints vary per tier")
	var s: Color = ItemDB.get_base("body_str_3")["tint"]
	var d: Color = ItemDB.get_base("body_dex_3")["tint"]
	var i: Color = ItemDB.get_base("body_int_3")["tint"]
	assert_true(absf(s.r - s.b) < 0.1, "str tint is grey")
	assert_true(d.r > d.b and d.g > d.b, "dex tint is brown/green")
	assert_true(i.b > i.r and i.b > i.g, "int tint is violet/blue")
	var sw1: Color = ItemDB.get_base("sword_1")["tint"]
	var sw6: Color = ItemDB.get_base("sword_6")["tint"]
	assert_true(sw6.get_luminance() > sw1.get_luminance(), "top weapon tier brighter than iron")


func test_get_base_for_level_and_tier_for_level() -> void:
	assert_eq(ItemDB.get_base_for_level("bow", 1), "bow_1", "lvl 1")
	assert_eq(ItemDB.get_base_for_level("bow", 7), "bow_1", "lvl 7")
	assert_eq(ItemDB.get_base_for_level("bow", 8), "bow_2", "lvl 8")
	assert_eq(ItemDB.get_base_for_level("bow", 49), "bow_5", "lvl 49")
	assert_eq(ItemDB.get_base_for_level("bow", 60), "bow_6", "lvl 60")
	assert_eq(ItemDB.tier_for_level(26), 4, "tier for 26")
	assert_true(ItemDB.get_base("no_such_base").is_empty(), "unknown base -> {}")


## Paths of every Array/Dictionary inside v that is NOT read-only.
func _writable_paths(v: Variant, path: String, out: Array) -> void:
	if v is Dictionary:
		if not (v as Dictionary).is_read_only():
			out.append(path)
		for k: Variant in v:
			_writable_paths(v[k], "%s.%s" % [path, k], out)
	elif v is Array:
		if not (v as Array).is_read_only():
			out.append(path)
		for i in (v as Array).size():
			_writable_paths(v[i], "%s[%d]" % [path, i], out)


func test_shared_data_is_read_only() -> void:
	# Every base / affix / unique dict and everything nested in it is read-only.
	var writable: Array = []
	var n := 0
	for id in ItemDB.get_base_ids():
		_writable_paths(ItemDB.get_base(id), id, writable)
		n += 1
	for a: Dictionary in ItemDB.get_all_affixes():
		_writable_paths(a, "affix " + String(a["id"]), writable)
		n += 1
	for u: Dictionary in ItemDB.get_all_uniques():
		_writable_paths(u, "unique " + String(u["id"]), writable)
		n += 1
	assert_eq(n, 258 + ItemDB.get_all_affixes().size() + ItemDB.get_unique_ids().size(), "walked every entry")
	assert_eq(writable.size(), 0, "shared containers are read-only (first: %s)" % [writable.slice(0, 5)])
	var sword: Dictionary = ItemDB.get_base("sword_1")
	assert_true(sword.is_read_only() and (sword["tags"] as Array).is_read_only() and (sword["req"] as Dictionary).is_read_only(), "sword_1 deep read-only")
	assert_true(((ItemDB.get_affix("max_life")["tiers"] as Array)[0]["mods"] as Array).is_read_only(), "affix tier mods read-only")
	assert_true((ItemDB.get_unique("gorebinder")["mods"] as Array).is_read_only(), "unique mods read-only")
	for bid in ItemDB.get_base_ids():
		for k in ["prefix", "suffix"]:
			for aid in ItemDB.get_affixes_for_base(bid, k):
				assert_true(ItemDB.get_affix(aid).is_read_only(), "pool affix read-only")
	# Unknown ids give an (also read-only) empty dict.
	for d: Dictionary in [ItemDB.get_base("nope"), ItemDB.get_affix("nope"), ItemDB.get_unique("nope")]:
		assert_true(d.is_empty() and d.is_read_only(), "unknown id -> read-only {}")
	# List lookups hand out writable copies (of read-only dicts); changing them changes nothing.
	var ids := ItemDB.get_base_ids()
	ids.append("x")
	var cats := ItemDB.get_categories("weapon")
	cats.append("x")
	var cb := ItemDB.get_category_bases("bow")
	cb.append("x")
	var pool := ItemDB.get_affixes_for_base("ring_3")
	pool.append("x")
	var all := ItemDB.get_all_bases()
	all.append({})
	var slot_bases := ItemDB.get_bases_for_slot("ring")
	slot_bases.append({})
	var uids := ItemDB.get_unique_ids()
	uids.append("x")
	var affs := ItemDB.get_all_affixes()
	affs.append({})
	var uniqs := ItemDB.get_all_uniques()
	uniqs.append({})
	assert_eq(ItemDB.get_base_ids().size(), 258, "base ids unchanged")
	assert_eq(ItemDB.get_categories("weapon").size(), cats.size() - 1, "categories unchanged")
	assert_eq(ItemDB.get_category_bases("bow").size(), 6, "category bases unchanged")
	assert_false("x" in ItemDB.get_affixes_for_base("ring_3"), "affix pool unchanged")
	assert_eq(ItemDB.get_all_bases().size(), 258, "all bases unchanged")
	assert_eq(ItemDB.get_unique_ids().size(), uids.size() - 1, "unique ids unchanged")
	# duplicate() gives a writable deep copy; the original stays untouched.
	var copy: Dictionary = sword.duplicate(true)
	assert_false(copy.is_read_only(), "copy writable")
	copy["name"] = "Changed"
	(copy["tags"] as Array).append("x")
	(copy["req"] as Dictionary)["strength"] = 999
	assert_eq(ItemDB.get_base("sword_1")["name"], "Rusted Sword", "original name kept")
	assert_false("x" in ItemDB.get_base("sword_1")["tags"], "original tags kept")
	assert_true(int(ItemDB.get_base("sword_1")["req"]["strength"]) < 999, "original req kept")
	# Everything that reads the tables works without writing to them (a write into a read-only
	# container raises an engine error, which fails this test).
	seed(77)
	for bid in ItemDB.get_base_ids():
		var plain := ItemDB.create_item(bid)
		for r in [Item.Rarity.MAGIC, Item.Rarity.RARE, Item.Rarity.UNIQUE]:
			var it := ItemDB.create_item(bid, r, 50)
			it.get_tooltip_lines({"strength": 10, "dexterity": 10, "intelligence": 10, "level": 5}, plain)
			it.get_global_mods()
			it.get_weapon_dps()
			it.get_defence_stats()
			ItemDB.reroll_affixes(it)
			Item.from_dict(it.to_dict()).clone()
		ItemDB.upgrade_rarity(plain)
		ItemDB.upgrade_rarity(plain)
	for uid in ItemDB.get_unique_ids():
		ItemDB.create_unique(uid).get_tooltip_lines()
	for i in 100:
		ItemDB.generate_random_item(randi_range(1, 60), -1, ["", "bow", "ring", "body"][i % 4], 100.0)
	assert_true(ItemDB.generate_vendor_stock(30).size() >= 12, "vendor stock")
	assert_false(LootSystem.roll_monster_drops(40, 3).is_empty(), "boss drops")
	assert_false(LootSystem.roll_chest_drops(20, 2).is_empty(), "chest drops")
	assert_eq(writable.size(), 0, "still no writable shared data")

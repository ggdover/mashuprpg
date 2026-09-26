extends TestCase
## Item instance behaviour: local folding, global mods, names, tooltips, values, serialization.


func _mod(stat: String, op: String, v: float, v2: Variant = null) -> Dictionary:
	return StatBlock.mod(stat, op, v, v2)


func _affix(id: String, kind: String, mods: Array, tier: int = 1) -> Dictionary:
	var name := String(ItemDB.get_affix(id).get("tiers", [{}])[tier - 1].get("name", id)) if not ItemDB.get_affix(id).is_empty() else id
	return {"id": id, "kind": kind, "tier": tier, "name": name, "mods": mods}


func test_local_weapon_folding() -> void:
	var it := ItemDB.create_item("sword_2", Item.Rarity.MAGIC, 10)
	it.implicit_mods = []
	it.affixes = [
		_affix("local_physical_damage", "prefix", [_mod("local_physical_damage", "inc", 50.0), _mod("local_added_physical", "flat", 2.0, 4.0), _mod("local_added_fire", "flat", 3.0, 6.0)]),
		_affix("local_attack_speed", "suffix", [_mod("local_attack_speed", "inc", 10.0), _mod("local_crit_chance", "inc", 20.0)]),
	]
	var s := Balance.weapon_damage_scale(10)
	var w := it.get_weapon_stats()
	assert_near(w["phys_min"], roundf((roundf(7.0 * s) + 2.0) * 1.5), 0.001, "phys min: (base + flat) × (1 + inc)")
	assert_near(w["phys_max"], roundf((roundf(15.0 * s) + 4.0) * 1.5), 0.001, "phys max")
	assert_near(w["attack_speed"], snappedf(1.45 * 1.1, 0.01), 0.0001, "local attack speed")
	assert_near(w["crit_chance"], 6.0, 0.0001, "local crit")
	assert_eq(w["added"], {"fire": Vector2(3, 6)}, "local added fire")
	assert_eq(w["weapon_type"], "sword", "weapon type")
	# Local mods never reach the character.
	for m: Dictionary in it.get_global_mods():
		assert_false(StatDefs.is_local(m["stat"]), "no local stat in global mods: " + String(m["stat"]))
	assert_true(it.get_global_mods().is_empty(), "weapon with only local mods has no global mods")
	assert_eq(it.get_all_mods().size(), 5, "all mods include local ones")
	assert_eq(it.get_local_mods().size(), 5, "local mods")
	# Implicit local attack speed stacks with explicit.
	it.implicit_mods = [_mod("local_attack_speed", "inc", 5.0)]
	assert_near(it.get_weapon_stats()["attack_speed"], snappedf(1.45 * 1.15, 0.01), 0.0001, "implicit + explicit local attack speed")


func test_weapon_effective_level_cap() -> void:
	var it := ItemDB.create_item("sword_1", Item.Rarity.NORMAL, 60)
	assert_eq(it.get_effective_level(), 13, "tier 1 grows only to base level + 12")
	assert_near(it.get_weapon_stats()["phys_max"], roundf(15.0 * Balance.weapon_damage_scale(13)), 0.001, "capped growth")
	var top := ItemDB.create_item("sword_6", Item.Rarity.NORMAL, 60)
	assert_eq(top.get_effective_level(), 60, "tier 6 at ilvl 60")
	assert_true(ItemDB.create_item("ring_2").get_weapon_stats().is_empty(), "non-weapons have no weapon dict")
	assert_true(ItemDB.create_item("shield_str_2").get_weapon_stats().is_empty(), "shields are not weapons")


func test_local_defence_folding_and_global_defences() -> void:
	var it := ItemDB.create_item("body_str_dex_3", Item.Rarity.RARE, 20)
	it.affixes = [
		_affix("local_armour", "prefix", [_mod("local_armour", "flat", 20.0)]),
		_affix("local_armour_inc", "prefix", [_mod("local_armour", "inc", 50.0)]),
		_affix("local_evasion_inc", "prefix", [_mod("local_evasion", "inc", 30.0)]),
		_affix("max_life", "prefix", [_mod("max_life", "flat", 25.0)]),
		_affix("fire_resistance", "suffix", [_mod("fire_resistance", "flat", 12.0)]),
	]
	var e := 19.0
	var base_armour := roundf((15.0 + 7.5 * e) * 0.6)
	var base_eva := roundf((50.0 + 9.0 * e) * 0.6)
	var d := it.get_defence_stats()
	assert_near(d["armour"], roundf((base_armour + 20.0) * 1.5), 0.001, "armour folded")
	assert_near(d["evasion"], roundf(base_eva * 1.3), 0.001, "evasion folded")
	assert_near(d["energy_shield"], 0.0, 0.001, "no es")
	var g := it.get_global_mods()
	var found := {}
	for m: Dictionary in g:
		found["%s|%s" % [m["stat"], m["op"]]] = float(m["value"])
		assert_false(StatDefs.is_local(m["stat"]), "no local mods globally")
	assert_near(found.get("max_life|flat", -1.0), 25.0, 0.001, "life global")
	assert_near(found.get("fire_resistance|flat", -1.0), 12.0, 0.001, "res global")
	assert_near(found.get("armour|flat", -1.0), d["armour"], 0.001, "final armour as flat mod")
	assert_near(found.get("evasion|flat", -1.0), d["evasion"], 0.001, "final evasion as flat mod")
	assert_false(found.has("max_energy_shield|flat"), "no ES mod without ES")
	# A StatBlock fed with the global mods sees the item's armour.
	var sb := StatBlock.new()
	sb.add_mods(g)
	assert_near(sb.compute("armour"), d["armour"], 0.001, "statblock armour")
	# Shields contribute block_chance; ES items contribute max_energy_shield.
	var sh := ItemDB.create_item("shield_int_2", Item.Rarity.NORMAL, 8)
	var sg := {}
	for m: Dictionary in sh.get_global_mods():
		sg[m["stat"]] = float(m["value"])
	assert_near(sg.get("block_chance", 0.0), sh.get_defence_stats()["block"], 0.001, "shield block as global mod")
	assert_near(sg.get("max_energy_shield", 0.0), sh.get_defence_stats()["energy_shield"], 0.001, "shield ES as global mod")
	# Local block adds to shield block.
	sh.affixes = [_affix("local_block", "suffix", [_mod("local_block", "flat", 4.0)])]
	assert_near(sh.get_defence_stats()["block"], float(ItemDB.get_base("shield_int_2")["block"]) + 4.0, 0.001, "local block")
	# Staff implicit block is a global block_chance mod.
	var staff := ItemDB.create_item("staff_1")
	var has_block := false
	for m: Dictionary in staff.get_global_mods():
		if m["stat"] == "block_chance":
			has_block = true
	assert_true(has_block, "staff implicit block reaches the character")


func test_display_names() -> void:
	var it := ItemDB.create_item("sword_1", Item.Rarity.MAGIC, 5)
	it.affixes = [_affix("local_physical_damage", "prefix", [_mod("local_physical_damage", "inc", 45.0)], 1), _affix("dexterity", "suffix", [_mod("dexterity", "flat", 12.0)], 1)]
	assert_eq(it.get_display_name(), "Heavy Rusted Sword of the Mongoose", "magic prefix + base + suffix")
	it.affixes = [_affix("dexterity", "suffix", [_mod("dexterity", "flat", 16.0)], 2)]
	assert_eq(it.get_display_name(), "Rusted Sword of the Lynx", "magic suffix only")
	it.affixes = [_affix("max_life", "prefix", [_mod("max_life", "flat", 22.0)], 2)]
	it.base_id = "ring_1"
	assert_eq(it.get_display_name(), "Healthy Iron Ring", "magic prefix only")
	var n := ItemDB.create_item("body_int_1")
	assert_eq(n.get_display_name(), "Simple Robe", "normal = base name")
	assert_eq(n.get_base_name(), "Simple Robe", "base name")
	var r := ItemDB.create_item("gloves_dex_2", Item.Rarity.RARE, 10)
	assert_true(r.get_display_name() != r.get_base_name(), "rare generated name")
	assert_eq(ItemDB.create_unique("stormcrown").get_display_name(), "Stormcrown", "unique name")
	assert_eq(n.get_rarity_color(), UIStyle.RARITY_COLORS[0], "rarity colour")
	assert_eq(r.get_rarity_color(), UIStyle.RARITY_COLORS[2], "rare colour")


func test_requirements_and_unmet() -> void:
	var it := ItemDB.create_item("sword_3")
	var req := it.get_requirements()
	assert_eq(req, {"level": 16, "strength": 21, "dexterity": 21, "intelligence": 0}, "sword_3 requirements")
	assert_true(it.meets_requirements({"strength": 21, "dexterity": 30, "intelligence": 0, "level": 16}), "exactly met")
	var unmet := it.get_unmet_requirements({"strength": 10, "dexterity": 30, "level": 12})
	assert_eq(unmet, ["level", "strength"] as Array[String], "unmet list")
	assert_true(it.get_unmet_requirements({"strength": 99, "dexterity": 99}).is_empty(), "level unchecked without level")
	assert_eq(ItemDB.create_item("ring_4").get_requirements()["strength"], 0, "jewellery has no attribute requirement")


func _check_line_format(lines: Array, what: String) -> void:
	assert_true(lines.size() >= 3, what + " has lines")
	for l: Dictionary in lines:
		assert_true(l.has("text") and l["text"] is String, what + " line text")
		assert_true(l.has("color") and l["color"] is Color, what + " line colour")
		assert_has(["title", "normal", "small"], l.get("size", ""), what + " line size")
		if l.get("separator", false):
			assert_eq(l["text"], "", what + " separator has no text")
	assert_false(lines[-1].get("separator", false), what + " does not end with a separator")
	for i in range(1, lines.size()):
		assert_false(lines[i].get("separator", false) and lines[i - 1].get("separator", false), what + " no double separators")


func _texts(lines: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for l: Dictionary in lines:
		out.append(l["text"])
	return out


func _find(lines: Array, prefix: String) -> Dictionary:
	for l: Dictionary in lines:
		if String(l["text"]).begins_with(prefix):
			return l
	return {}


func test_tooltip_lines_sanity() -> void:
	seed(77)
	var w := ItemDB.create_item("greataxe_3", Item.Rarity.RARE, 20)
	var lines := w.get_tooltip_lines()
	_check_line_format(lines, "rare weapon")
	assert_eq(lines[0]["text"], w.get_display_name(), "title = display name")
	assert_eq(lines[0]["size"], "title", "title size")
	assert_eq(lines[0]["color"], w.get_rarity_color(), "title in rarity colour")
	assert_eq(lines[1]["text"], w.get_base_name(), "rare shows base name")
	assert_true(_texts(lines).has("Rare Two Handed Axe"), "item class line")
	assert_false(_find(lines, "Physical Damage: ").is_empty(), "weapon damage line")
	assert_false(_find(lines, "Attacks per Second: ").is_empty(), "aps line")
	assert_false(_find(lines, "Critical Strike Chance: ").is_empty(), "crit line")
	assert_false(_find(lines, "Item Level: 20").is_empty(), "item level line")
	var req := _find(lines, "Requires ")
	assert_false(req.is_empty(), "requirement line")
	assert_true(req.has("parts"), "requirement parts for rich text")
	assert_ne(req["color"], UIStyle.COLOR_BAD, "no attributes given: not red")
	# Implicit and explicit mod colours.
	var implicit_line := _find(lines, "%d%% chance to cause Bleeding" % int(w.implicit_mods[0]["value"]))
	assert_eq(implicit_line.get("color"), UIStyle.COLOR_IMPLICIT, "implicit colour")
	var n_mod := 0
	for l: Dictionary in lines:
		if l["color"] == UIStyle.COLOR_MOD and l.has("hint"):
			n_mod += 1
	var n_explicit := 0
	for a: Dictionary in w.affixes:
		n_explicit += (a["mods"] as Array).size()
	assert_eq(n_mod, n_explicit, "one mod line (with a tier hint) per explicit mod")
	# Requirements red when unmet, not red when met.
	var low := w.get_tooltip_lines({"strength": 5, "dexterity": 5, "intelligence": 5, "level": 3})
	assert_eq(_find(low, "Requires ")["color"], UIStyle.COLOR_BAD, "unmet requirements red")
	var parts: Array = _find(low, "Requires ")["parts"]
	var red_parts := 0
	for p: Dictionary in parts:
		if p["color"] == UIStyle.COLOR_BAD:
			red_parts += 1
	assert_eq(red_parts, 2, "level and strength parts red")
	var high := w.get_tooltip_lines({"strength": 200, "dexterity": 200, "intelligence": 200, "level": 60})
	assert_ne(_find(high, "Requires ")["color"], UIStyle.COLOR_BAD, "met requirements not red")
	# Modified properties highlighted.
	var plain := ItemDB.create_item("axe_2", Item.Rarity.NORMAL, 8)
	assert_eq(_find(plain.get_tooltip_lines(), "Physical Damage: ")["color"], UIStyle.COLOR_TEXT, "unmodified damage plain")
	plain.rarity = Item.Rarity.MAGIC
	plain.affixes = [_affix("local_physical_damage", "prefix", [_mod("local_physical_damage", "inc", 60.0)])]
	assert_eq(_find(plain.get_tooltip_lines(), "Physical Damage: ")["color"], UIStyle.COLOR_MOD, "modified damage highlighted")
	# Defence item.
	var body := ItemDB.create_item("body_int_2", Item.Rarity.MAGIC, 10)
	var bl := body.get_tooltip_lines()
	_check_line_format(bl, "body")
	assert_false(_find(bl, "Energy Shield: ").is_empty(), "ES property line")
	assert_true(_find(bl, "Physical Damage").is_empty(), "no weapon lines on armour")
	# Unique flavour.
	var u := ItemDB.create_unique("gorebinder")
	var ul := u.get_tooltip_lines()
	_check_line_format(ul, "unique")
	var fl := _find(ul, "It drinks deep")
	assert_eq(fl.get("color"), UIStyle.COLOR_UNIQUE_FLAVOR, "flavour colour")
	assert_true(fl.get("italic", false), "flavour italic")
	assert_true(_texts(ul).has("Unique One Handed Axe"), "unique class line")


func test_tooltip_comparison() -> void:
	var weak := ItemDB.create_item("sword_1", Item.Rarity.NORMAL, 1)
	var strong := ItemDB.create_item("sword_4", Item.Rarity.MAGIC, 30)
	strong.affixes = [_affix("max_life", "prefix", [_mod("max_life", "flat", 30.0)])]
	var full := strong.get_tooltip_lines({}, weak)
	var cmp := _find(full, "Compared to ")
	assert_false(cmp.is_empty(), "comparison header")
	var lines := strong.get_comparison_lines(weak)
	assert_eq(_texts(full).slice(full.size() - lines.size()), _texts(lines), "tooltip ends with the comparison lines")
	var dps := _find(lines, "+")
	var found_dps := false
	var found_life := false
	for l: Dictionary in lines:
		if String(l["text"]).ends_with("Damage per Second") and String(l["text"]).begins_with("+"):
			found_dps = true
			assert_eq(l["color"], UIStyle.COLOR_GOOD, "dps gain green")
		if l["text"] == "+30 to maximum Life":
			found_life = true
			assert_eq(l["color"], UIStyle.COLOR_GOOD, "life gain green")
	assert_true(found_dps, "dps diff line")
	assert_true(found_life, "stat diff line")
	# Reverse comparison: losses in red.
	var rev := weak.get_comparison_lines(strong)
	var lose_life := false
	for l: Dictionary in rev:
		if l["text"] == "-30 to maximum Life":
			lose_life = true
			assert_eq(l["color"], UIStyle.COLOR_BAD, "life loss red")
	assert_true(lose_life, "life loss line")
	# Armour vs armour.
	var a1 := ItemDB.create_item("body_str_1")
	var a2 := ItemDB.create_item("body_str_3", Item.Rarity.NORMAL, 16)
	var al := a2.get_tooltip_lines({}, a1)
	assert_false(_find(al, "+").is_empty(), "armour diff")
	var armour_line := {}
	for l: Dictionary in al:
		if String(l["text"]).ends_with(" Armour") and String(l["text"]).begins_with("+"):
			armour_line = l
	assert_false(armour_line.is_empty(), "armour gain line")
	# Identical items: no stat changes.
	var same := a1.get_tooltip_lines({}, ItemDB.create_item("body_str_1"))
	assert_true(_texts(same).has("No stat changes"), "identical items")
	assert_true(_find(a1.get_tooltip_lines({}, a1), "Compared to").is_empty(), "no comparison with itself")
	assert_true(dps is Dictionary, "dps lookup ok")


func test_comparison_signs() -> void:
	var a := ItemDB.create_item("ring_2", Item.Rarity.RARE, 20)
	var b := ItemDB.create_item("ring_2", Item.Rarity.NORMAL, 20)
	a.implicit_mods = []
	b.implicit_mods = []
	a.affixes = [
		_affix("life_regen", "suffix", [_mod("life_regen", "flat", 5.0)]),
		_affix("added_fire_attack", "prefix", [_mod("added_fire_attack", "flat", 2.0, 4.0)]),
		_affix("fire_resistance", "suffix", [_mod("fire_resistance", "flat", 10.0)]),
		_affix("life_leech", "suffix", [_mod("life_leech", "flat", 0.4)]),
		_affix("max_life", "prefix", [_mod("max_life", "flat", 12.0)]),
		_affix("attack_speed", "suffix", [_mod("attack_speed", "inc", 6.0)]),
	]
	var gain := _texts(a.get_comparison_lines(b))
	var lose := _texts(b.get_comparison_lines(a))
	# Unsigned templates: positive differences get a "+" like negative ones get a "-".
	assert_true(gain.has("Regenerate +5 Life per second"), "unsigned flat gain signed: %s" % [gain])
	assert_true(lose.has("Regenerate -5 Life per second"), "unsigned flat loss signed: %s" % [lose])
	assert_true(gain.has("Adds +2 to +4 Fire Damage to Attacks"), "range gain signed")
	assert_true(lose.has("Adds -2 to -4 Fire Damage to Attacks"), "range loss signed")
	assert_true(gain.has("+0.4% of Hit Damage Leeched as Life"), "decimal gain signed")
	assert_true(lose.has("-0.4% of Hit Damage Leeched as Life"), "decimal loss signed")
	# Templates that already carry a sign (and the generic flat template) are unchanged.
	assert_true(gain.has("+10% to Fire Resistance") and lose.has("-10% to Fire Resistance"), "signed template")
	assert_true(gain.has("+12 to maximum Life") and lose.has("-12 to maximum Life"), "generic flat template")
	# inc/more use words, not signs.
	assert_true(gain.has("6% increased Attack Speed") and lose.has("6% reduced Attack Speed"), "inc words")
	for t: String in gain + lose:
		assert_false(t.contains("++") or t.contains("+-") or t.contains("-+") or t.contains("--"), "no doubled signs: " + t)
	# Mixed range difference: each end carries its own sign.
	var c := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 20)
	c.implicit_mods = []
	c.affixes = [_affix("added_fire_attack", "prefix", [_mod("added_fire_attack", "flat", 3.0, 3.0)])]
	var d := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 20)
	d.implicit_mods = []
	d.affixes = [_affix("added_fire_attack", "prefix", [_mod("added_fire_attack", "flat", 3.0, 6.0)])]
	assert_true(_texts(c.get_comparison_lines(d)).has("Adds 0 to -3 Fire Damage to Attacks"), "zero end unsigned: %s" % [_texts(c.get_comparison_lines(d))])
	# Item mod lines themselves stay unsigned where the template has no sign.
	assert_true(_texts(a.get_tooltip_lines()).has("Regenerate 5 Life per second"), "tooltip mod line unchanged")


func test_tooltips_for_every_base_and_rarity() -> void:
	seed(9)
	for b: Dictionary in ItemDB.get_all_bases():
		for r in [Item.Rarity.NORMAL, Item.Rarity.MAGIC, Item.Rarity.RARE]:
			var it := ItemDB.create_item(b["id"], r, int(b["level"]) + 4)
			var lines := it.get_tooltip_lines({"strength": 50, "dexterity": 50, "intelligence": 50, "level": 30})
			assert_true(lines.size() >= 3, "%s tooltip" % b["id"])
			for l: Dictionary in lines:
				assert_false(String(l["text"]).contains("+-"), "no '+-' in " + String(l["text"]))
				assert_false(String(l["text"]).contains("{"), "no template leftovers in " + String(l["text"]))


func test_tier_hints_toggle() -> void:
	var it := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 10)
	it.affixes = [_affix("max_life", "prefix", [_mod("max_life", "flat", 25.0)], 2)]
	Item.tooltip_show_tiers = true
	var with_tiers := _texts(it.get_tooltip_lines())
	Item.tooltip_show_tiers = false
	var without := _texts(it.get_tooltip_lines())
	assert_true(with_tiers.has("+25 to maximum Life  [T2]"), "tier hint shown")
	assert_true(without.has("+25 to maximum Life"), "no tier hint by default")


func test_sell_and_buy_values() -> void:
	var it := ItemDB.create_item("sword_2", Item.Rarity.NORMAL, 10)
	assert_eq(it.get_sell_value(), 20, "normal 2 × ilvl")
	it.rarity = Item.Rarity.MAGIC
	assert_eq(it.get_sell_value(), 60, "magic ×3")
	it.rarity = Item.Rarity.RARE
	assert_eq(it.get_sell_value(), 160, "rare ×8")
	it.rarity = Item.Rarity.UNIQUE
	assert_eq(it.get_sell_value(), 300, "unique ×15")
	assert_eq(it.get_buy_value(), 1200, "buy = 4 × sell")
	var cheap := ItemDB.create_item("ring_1", Item.Rarity.NORMAL, 1)
	assert_true(cheap.get_sell_value() >= 1, "min 1")


func test_model_and_tint() -> void:
	assert_eq(ItemDB.create_item("helmet_int_2").get_model_id(), "armor_helmet_int", "helmet model")
	assert_eq(ItemDB.create_item("helmet_str_int_2").get_model_id(), "armor_helmet_str", "hybrid helmet model")
	assert_eq(ItemDB.create_item("gloves_dex_4").get_model_id(), "armor_gloves", "gloves model")
	assert_eq(ItemDB.create_item("focus_3").get_model_id(), "offhand_focus", "focus model")
	assert_eq(ItemDB.create_item("amulet_6").get_model_id(), "jewel_amulet", "amulet model")
	assert_eq(ItemDB.create_item("maul_2").get_model_id(), "weapon_maul", "maul model")
	var u := ItemDB.create_unique("emberheart")
	assert_eq(u.get_tint(), ItemDB.get_unique("emberheart")["tint"], "unique tint override")
	assert_eq(ItemDB.create_item("staff_3").get_tint(), ItemDB.get_base("staff_3")["tint"], "base tint")


func _assert_json_native(v: Variant, path: String) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				assert_eq(typeof(k), TYPE_STRING, path + " string keys")
				_assert_json_native(v[k], path + "." + str(k))
		TYPE_ARRAY:
			for i in (v as Array).size():
				_assert_json_native(v[i], "%s[%d]" % [path, i])
		TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL:
			pass
		_:
			fail("%s is not JSON-native (%s)" % [path, type_string(typeof(v))])


func test_serialization_round_trip() -> void:
	seed(31)
	var items: Array = []
	for i in 60:
		items.append(ItemDB.generate_random_item(randi_range(1, 60)))
	for uid in ItemDB.get_unique_ids():
		items.append(ItemDB.create_unique(uid))
	for it: Item in items:
		var d := it.to_dict()
		_assert_json_native(d, it.base_id)
		var parsed: Variant = JSON.parse_string(JSON.stringify(d))
		assert_true(parsed is Dictionary, "json parse")
		var back := Item.from_dict(parsed)
		assert_eq(back.uid, it.uid, "uid kept")
		assert_eq(back.base_id, it.base_id, "base kept")
		assert_eq(back.rarity, it.rarity, "rarity kept")
		assert_eq(typeof(back.rarity), TYPE_INT, "rarity int")
		assert_eq(typeof(back.item_level), TYPE_INT, "ilvl int")
		assert_eq(back.get_display_name(), it.get_display_name(), "name kept")
		assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(d), "dict round trip")
		assert_eq(back.get_weapon_stats(), it.get_weapon_stats(), "weapon stats identical")
		assert_eq(back.get_defence_stats(), it.get_defence_stats(), "defences identical")
		assert_eq(_texts(back.get_tooltip_lines()), _texts(it.get_tooltip_lines()), "tooltip identical")
		for a: Dictionary in back.affixes:
			assert_eq(typeof(a["tier"]), TYPE_INT, "affix tier int")


func test_from_dict_bumps_next_uid() -> void:
	var before := Item.new()
	var big := before.uid + 100000
	var it := Item.from_dict({"uid": float(big), "base_id": "ring_1", "rarity": 0.0, "item_level": 3.0})
	assert_eq(it.uid, big, "uid restored from a JSON float")
	var fresh := Item.new()
	assert_true(fresh.uid > big, "new items get a larger uid")
	# Garbage tolerated.
	var odd := Item.from_dict({"uid": 5, "base_id": "ring_1", "affixes": [{"id": "x", "mods": [{"stat": "max_life", "value": 3}], "tier": 2.0}, "junk"], "implicit_mods": "bad"})
	assert_eq(odd.affixes.size(), 1, "junk affix entries dropped")
	assert_eq(odd.implicit_mods.size(), 0, "bad implicit list tolerated")
	assert_eq(odd.affixes[0]["tier"], 2, "tier to int")


func test_clone() -> void:
	var it := ItemDB.create_item("bow_3", Item.Rarity.RARE, 20)
	var c := it.clone()
	assert_ne(c.uid, it.uid, "clone gets a new uid")
	var a := it.to_dict()
	var b := c.to_dict()
	a.erase("uid")
	b.erase("uid")
	assert_eq(JSON.stringify(a), JSON.stringify(b), "clone identical otherwise")

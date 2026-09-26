extends RefCounted
## Item base types: categories × 6 tiers (docs/ARCHITECTURE.md §9.2). Pure data + one builder.
## OWNER: items. Used by ItemDB (preload); no class_name on purpose.
##
## A built base (ItemDB.get_base) has these keys:
##   "id", "name", "category", "tier" (1..6), "item_class" (display, e.g. "One Handed Sword"),
##   "slot_type", "weapon_type", "two_handed", "level", "req" {"strength","dexterity","intelligence"},
##   "model", "tint", "tags" (Array of String, used by affix filters), "implicits" (mod templates
##   {"stat","op","min","max"[,"min2","max2"][,"decimals"]}),
##   weapons: "template_min", "template_max" (level-1 phys), "phys_min", "phys_max" (at the base
##   level), "attack_speed", "crit_chance", "range";
##   armour-like: "defence_types" (Array), "defence_factor" (slot × hybrid factor), "armour",
##   "evasion", "energy_shield" (at the base level), "block".

const TIER_LEVELS: Array[int] = [1, 8, 16, 26, 38, 50]
## Tiers cap weapon/defence growth: effective level = min(item_level, base.level + TIER_GROWTH).
const TIER_GROWTH := 12

const SLOT_DEFENCE_FACTOR := {"body": 1.0, "helmet": 0.45, "gloves": 0.35, "boots": 0.35, "shield": 0.6, "focus": 0.6}
const HYBRID_DEFENCE_FACTOR := 0.6

## Per-tier tints. Metal weapons brighten iron -> bronze -> steel -> blued steel -> gold -> runic.
const METAL_TINTS: Array[Color] = [
	Color(0.6, 0.55, 0.5), Color(0.74, 0.57, 0.4), Color(0.78, 0.8, 0.84),
	Color(0.62, 0.73, 0.92), Color(0.96, 0.8, 0.42), Color(0.8, 0.58, 1.0),
]
## Wooden weapons: driftwood -> yew -> ash -> ironwood -> bone -> gilded.
const WOOD_TINTS: Array[Color] = [
	Color(0.6, 0.47, 0.32), Color(0.68, 0.47, 0.28), Color(0.8, 0.68, 0.52),
	Color(0.7, 0.72, 0.78), Color(0.92, 0.88, 0.76), Color(0.98, 0.8, 0.45),
]
## Armour by attribute: str steel grey, dex leather brown/green, int cloth violet/blue.
const ATTR_TINTS := {
	"str": [Color(0.56, 0.56, 0.58), Color(0.62, 0.62, 0.64), Color(0.7, 0.7, 0.72), Color(0.72, 0.75, 0.82), Color(0.82, 0.8, 0.72), Color(0.92, 0.82, 0.55)],
	"dex": [Color(0.46, 0.36, 0.23), Color(0.52, 0.39, 0.25), Color(0.44, 0.46, 0.26), Color(0.36, 0.5, 0.3), Color(0.58, 0.44, 0.3), Color(0.3, 0.56, 0.42)],
	"int": [Color(0.42, 0.33, 0.62), Color(0.36, 0.42, 0.72), Color(0.52, 0.36, 0.72), Color(0.32, 0.47, 0.82), Color(0.62, 0.42, 0.86), Color(0.46, 0.57, 0.96)],
}
const ATTR_NAMES := {"str": "strength", "dex": "dexterity", "int": "intelligence"}

## Weapons. "req": attributes used (one = pure formula, two = hybrid formula).
## "implicit": per-tier value ranges of a single implicit mod (null = none).
const WEAPONS := {
	"sword": {
		"weapon_type": "sword", "two_handed": false, "min": 7.0, "max": 15.0, "aps": 1.45, "crit": 5.0, "range": 2.2,
		"req": ["str", "dex"], "model": "weapon_sword", "wood": false, "class": "One Handed Sword", "tags": ["melee", "one_handed"],
		"names": ["Rusted Sword", "Copper Sword", "Broadsword", "War Sword", "Runic Blade", "Eternal Sword"],
		"implicits": [{"stat": "local_attack_speed", "op": "inc", "tiers": [[4, 6], [5, 7], [6, 8], [7, 9], [8, 10], [9, 12]]}],
	},
	"greatsword": {
		"weapon_type": "sword", "two_handed": true, "min": 13.0, "max": 25.0, "aps": 1.2, "crit": 5.0, "range": 2.7,
		"req": ["str"], "model": "weapon_greatsword", "wood": false, "class": "Two Handed Sword", "tags": ["melee", "two_handed"],
		"names": ["Corroded Blade", "Bastard Sword", "Two-Handed Sword", "Executioner Sword", "Lion Sword", "Infernal Sword"],
		"implicits": [{"stat": "local_attack_speed", "op": "inc", "tiers": [[4, 6], [5, 7], [6, 8], [7, 9], [8, 10], [9, 12]]}],
	},
	"axe": {
		"weapon_type": "axe", "two_handed": false, "min": 8.0, "max": 18.0, "aps": 1.3, "crit": 5.0, "range": 2.2,
		"req": ["str"], "model": "weapon_axe", "wood": false, "class": "One Handed Axe", "tags": ["melee", "one_handed"],
		"names": ["Rusted Hatchet", "Jade Hatchet", "Boarding Axe", "Cleaver", "Siege Axe", "Runic Hatchet"],
		"implicits": [{"stat": "bleed_chance", "op": "flat", "tiers": [[10, 15], [12, 17], [14, 19], [16, 21], [18, 23], [20, 25]]}],
	},
	"greataxe": {
		"weapon_type": "axe", "two_handed": true, "min": 14.0, "max": 30.0, "aps": 1.1, "crit": 5.0, "range": 2.7,
		"req": ["str"], "model": "weapon_greataxe", "wood": false, "class": "Two Handed Axe", "tags": ["melee", "two_handed"],
		"names": ["Woodsplitter", "Poleaxe", "Double Axe", "Labrys", "Headsman Axe", "Despot Axe"],
		"implicits": [{"stat": "bleed_chance", "op": "flat", "tiers": [[15, 20], [17, 22], [19, 24], [21, 26], [23, 28], [25, 30]]}],
	},
	"mace": {
		"weapon_type": "mace", "two_handed": false, "min": 9.0, "max": 17.0, "aps": 1.25, "crit": 5.0, "range": 2.2,
		"req": ["str"], "model": "weapon_mace", "wood": false, "class": "One Handed Mace", "tags": ["melee", "one_handed"],
		"names": ["Driftwood Club", "Tribal Club", "Spiked Club", "Flanged Mace", "Ornate Mace", "Behemoth Mace"],
		"implicits": [{"stat": "area_damage", "op": "inc", "tiers": [[8, 12], [10, 14], [12, 16], [14, 18], [16, 20], [18, 24]]}],
	},
	"maul": {
		"weapon_type": "mace", "two_handed": true, "min": 17.0, "max": 31.0, "aps": 1.0, "crit": 5.0, "range": 2.7,
		"req": ["str"], "model": "weapon_maul", "wood": false, "class": "Two Handed Mace", "tags": ["melee", "two_handed"],
		"names": ["Driftwood Maul", "Mallet", "Sledgehammer", "Great Mallet", "Meatgrinder", "Colossus Mallet"],
		"implicits": [{"stat": "area_damage", "op": "inc", "tiers": [[12, 18], [15, 21], [18, 24], [21, 27], [24, 30], [27, 36]]}],
	},
	"dagger": {
		"weapon_type": "dagger", "two_handed": false, "min": 5.0, "max": 13.0, "aps": 1.6, "crit": 8.0, "range": 1.8,
		"req": ["dex", "int"], "model": "weapon_dagger", "wood": false, "class": "Dagger", "tags": ["melee", "one_handed", "caster"],
		"names": ["Glass Shank", "Skinning Knife", "Carving Knife", "Stiletto", "Kris", "Ambusher"],
		"implicits": [{"stat": "crit_chance", "op": "inc", "tiers": [[20, 30], [22, 32], [25, 35], [28, 38], [30, 40], [35, 45]]}],
	},
	"wand": {
		"weapon_type": "wand", "two_handed": false, "min": 4.0, "max": 9.0, "aps": 1.4, "crit": 7.0, "range": 20.0,
		"req": ["int"], "model": "weapon_wand", "wood": true, "class": "Wand", "tags": ["ranged_caster", "one_handed", "caster"],
		"names": ["Driftwood Wand", "Goat's Horn", "Carved Wand", "Quartz Wand", "Spiraled Wand", "Prophecy Wand"],
		"implicits": [{"stat": "spell_damage", "op": "inc", "tiers": [[8, 12], [10, 14], [12, 16], [14, 18], [16, 20], [18, 22]]}],
	},
	"staff": {
		"weapon_type": "staff", "two_handed": true, "min": 11.0, "max": 21.0, "aps": 1.15, "crit": 6.0, "range": 2.6,
		"req": ["str", "int"], "model": "weapon_staff", "wood": true, "class": "Staff", "tags": ["melee", "two_handed", "caster"],
		"names": ["Gnarled Branch", "Primitive Staff", "Long Staff", "Iron Staff", "Coiled Staff", "Judgement Staff"],
		"implicits": [
			{"stat": "spell_damage", "op": "inc", "tiers": [[14, 20], [16, 22], [18, 24], [20, 26], [22, 28], [24, 30]]},
			{"stat": "block_chance", "op": "flat", "tiers": [[6, 6], [6, 7], [7, 7], [7, 8], [8, 8], [8, 9]]},
		],
	},
	"bow": {
		"weapon_type": "bow", "two_handed": true, "min": 9.0, "max": 21.0, "aps": 1.4, "crit": 5.0, "range": 20.0,
		"req": ["dex"], "model": "weapon_bow", "wood": true, "class": "Bow", "tags": ["ranged", "two_handed"],
		"names": ["Short Bow", "Long Bow", "Composite Bow", "Recurve Bow", "Royal Bow", "Thicket Bow"],
		"implicits": [],
	},
	"crossbow": {
		"weapon_type": "crossbow", "two_handed": true, "min": 16.0, "max": 30.0, "aps": 1.0, "crit": 6.0, "range": 20.0,
		"req": ["dex", "str"], "model": "weapon_crossbow", "wood": true, "class": "Crossbow", "tags": ["ranged", "two_handed"],
		"names": ["Light Crossbow", "Hunter's Crossbow", "Windlass Crossbow", "Heavy Crossbow", "Siege Crossbow", "Dragonbone Crossbow"],
		"implicits": [{"stat": "pierce", "op": "flat", "tiers": [[1, 1], [1, 1], [1, 1], [1, 1], [1, 1], [1, 1]]}],
	},
}

## Shields: armour-like off-hands with block. "attrs" gives defences, requirements and tint.
const SHIELDS := {
	"shield_str": {"attrs": ["str"], "block": 20.0, "names": ["Splintered Tower Shield", "Corroded Tower Shield", "Bronze Tower Shield", "Girded Tower Shield", "Crested Tower Shield", "Colossal Tower Shield"]},
	"shield_dex": {"attrs": ["dex"], "block": 22.0, "names": ["Goathide Buckler", "Pine Buckler", "Painted Buckler", "Hammered Buckler", "Enameled Buckler", "Imperial Buckler"]},
	"shield_int": {"attrs": ["int"], "block": 18.0, "names": ["Twig Spirit Shield", "Yew Spirit Shield", "Bone Spirit Shield", "Tarnished Spirit Shield", "Ivory Spirit Shield", "Ancient Spirit Shield"]},
}

const FOCUS_NAMES: Array[String] = ["Cracked Orb", "Quartz Focus", "Moonstone Focus", "Runed Tome", "Seer's Orb", "Astral Orb"]
const FOCUS_IMPLICIT := [[10, 14], [12, 16], [14, 18], [16, 20], [18, 22], [20, 25]]

const QUIVER_NAMES: Array[String] = ["Rugged Quiver", "Cured Quiver", "Serrated Arrow Quiver", "Fire Arrow Quiver", "Broadhead Quiver", "Spike-Point Quiver"]
## Per-tier implicit mod templates (quivers alternate added physical damage / projectile speed).
const QUIVER_IMPLICITS := [
	[{"stat": "added_physical_attack", "op": "flat", "min": 1, "max": 2, "min2": 3, "max2": 4}],
	[{"stat": "projectile_speed", "op": "inc", "min": 15, "max": 20}],
	[{"stat": "added_physical_attack", "op": "flat", "min": 3, "max": 5, "min2": 7, "max2": 9}],
	[{"stat": "added_fire_attack", "op": "flat", "min": 4, "max": 6, "min2": 9, "max2": 12}],
	[{"stat": "projectile_speed", "op": "inc", "min": 25, "max": 30}, {"stat": "added_physical_attack", "op": "flat", "min": 3, "max": 4, "min2": 7, "max2": 8}],
	[{"stat": "added_physical_attack", "op": "flat", "min": 8, "max": 10, "min2": 16, "max2": 20}],
]

## Armour slots × attribute kinds. Names per slot and kind (6 tiers each).
const ARMOUR_KINDS: Array[String] = ["str", "dex", "int", "str_dex", "str_int", "dex_int"]
const ARMOUR_SLOTS := {
	"helmet": {"class": "Helmet", "names": {
		"str": ["Iron Hat", "Cone Helmet", "Barbute Helmet", "Close Helmet", "Gladiator Helmet", "Royal Burgonet"],
		"dex": ["Leather Cap", "Tricorne", "Leather Hood", "Wolf Pelt", "Hunter Hood", "Lion Pelt"],
		"int": ["Vine Circlet", "Iron Circlet", "Bone Circlet", "Lunaris Circlet", "Steel Circlet", "Hubris Circlet"],
		"str_dex": ["Battered Helm", "Sallet", "Visored Sallet", "Gilded Sallet", "Secutor Helm", "Fencer Helm"],
		"str_int": ["Rusted Coif", "Soldier Helmet", "Great Helmet", "Crusader Helmet", "Aventail Helmet", "Zealot Helmet"],
		"dex_int": ["Scare Mask", "Plague Mask", "Iron Mask", "Festival Mask", "Golden Mask", "Raven Mask"],
	}},
	"body": {"class": "Body Armour", "names": {
		"str": ["Plate Vest", "Chestplate", "Copper Plate", "War Plate", "Full Plate", "Glorious Plate"],
		"dex": ["Shabby Jerkin", "Strapped Leather", "Buckskin Tunic", "Wild Leather", "Sharkskin Tunic", "Zodiac Leather"],
		"int": ["Simple Robe", "Silken Vest", "Scholar's Robe", "Silken Garb", "Mage's Vestment", "Arcane Regalia"],
		"str_dex": ["Scale Vest", "Light Brigandine", "Scale Doublet", "Full Scale Armour", "Field Lamellar", "Wyrmscale Doublet"],
		"str_int": ["Chainmail Vest", "Chainmail Tunic", "Ringmail Coat", "Chainmail Doublet", "Saint's Hauberk", "Crusader Chainmail"],
		"dex_int": ["Padded Vest", "Oiled Vest", "Padded Jacket", "Oiled Coat", "Sadist Garb", "Assassin's Garb"],
	}},
	"gloves": {"class": "Gloves", "names": {
		"str": ["Iron Gauntlets", "Plated Gauntlets", "Bronze Gauntlets", "Steel Gauntlets", "Antique Gauntlets", "Titan Gauntlets"],
		"dex": ["Rawhide Gloves", "Goathide Gloves", "Deerskin Gloves", "Nubuck Gloves", "Eelskin Gloves", "Sharkskin Gloves"],
		"int": ["Wool Gloves", "Velvet Gloves", "Silk Gloves", "Embroidered Gloves", "Satin Gloves", "Sorcerer Gloves"],
		"str_dex": ["Fishscale Gauntlets", "Ironscale Gauntlets", "Bronzescale Gauntlets", "Steelscale Gauntlets", "Serpentscale Gauntlets", "Dragonscale Gauntlets"],
		"str_int": ["Chain Gloves", "Ringmail Gloves", "Mesh Gloves", "Riveted Gloves", "Zealot Gloves", "Crusader Gloves"],
		"dex_int": ["Wrapped Mitts", "Strapped Mitts", "Clasped Mitts", "Trapper Mitts", "Ambush Mitts", "Carnal Mitts"],
	}},
	"boots": {"class": "Boots", "names": {
		"str": ["Iron Greaves", "Steel Greaves", "Plated Greaves", "Reinforced Greaves", "Antique Greaves", "Titan Greaves"],
		"dex": ["Rawhide Boots", "Goathide Boots", "Deerskin Boots", "Nubuck Boots", "Eelskin Boots", "Stealth Boots"],
		"int": ["Wool Shoes", "Velvet Slippers", "Silk Slippers", "Scholar Boots", "Satin Slippers", "Sorcerer Boots"],
		"str_dex": ["Leatherscale Boots", "Ironscale Boots", "Bronzescale Boots", "Steelscale Boots", "Serpentscale Boots", "Dragonscale Boots"],
		"str_int": ["Chain Boots", "Ringmail Boots", "Mesh Boots", "Riveted Boots", "Zealot Boots", "Crusader Boots"],
		"dex_int": ["Wrapped Boots", "Strapped Boots", "Clasped Boots", "Shackled Boots", "Trapper Boots", "Murder Boots"],
	}},
}

## Jewellery: no requirements, implicits vary per tier.
const JEWELLERY := {
	"ring": {"class": "Ring", "model": "jewel_ring",
		"names": ["Iron Ring", "Coral Ring", "Paua Ring", "Prismatic Ring", "Moonstone Ring", "Diamond Ring"],
		"tints": [Color(0.6, 0.6, 0.6), Color(0.95, 0.52, 0.46), Color(0.42, 0.72, 0.76), Color(0.82, 0.62, 0.92), Color(0.76, 0.82, 0.96), Color(0.96, 0.96, 1.0)],
		"implicits": [
			[{"stat": "added_physical_attack", "op": "flat", "min": 1, "max": 1, "min2": 3, "max2": 4}],
			[{"stat": "max_life", "op": "flat", "min": 20, "max": 30}],
			[{"stat": "max_mana", "op": "flat", "min": 20, "max": 25}],
			[{"stat": "elemental_resistance", "op": "flat", "min": 8, "max": 10}],
			[{"stat": "max_energy_shield", "op": "flat", "min": 15, "max": 25}],
			[{"stat": "crit_chance", "op": "inc", "min": 20, "max": 30}],
		]},
	"amulet": {"class": "Amulet", "model": "jewel_amulet",
		"names": ["Amber Amulet", "Jade Amulet", "Lapis Amulet", "Agate Amulet", "Turquoise Amulet", "Onyx Amulet"],
		"tints": [Color(0.96, 0.66, 0.26), Color(0.42, 0.82, 0.5), Color(0.32, 0.42, 0.92), Color(0.82, 0.52, 0.42), Color(0.32, 0.82, 0.8), Color(0.36, 0.34, 0.4)],
		"implicits": [
			[{"stat": "strength", "op": "flat", "min": 12, "max": 18}],
			[{"stat": "dexterity", "op": "flat", "min": 14, "max": 20}],
			[{"stat": "intelligence", "op": "flat", "min": 16, "max": 22}],
			[{"stat": "strength", "op": "flat", "min": 14, "max": 18}, {"stat": "intelligence", "op": "flat", "min": 14, "max": 18}],
			[{"stat": "dexterity", "op": "flat", "min": 14, "max": 18}, {"stat": "intelligence", "op": "flat", "min": 14, "max": 18}],
			[{"stat": "all_attributes", "op": "flat", "min": 10, "max": 16}],
		]},
	"belt": {"class": "Belt", "model": "jewel_belt",
		"names": ["Leather Belt", "Chain Belt", "Studded Belt", "Heavy Belt", "Crystal Belt", "Vanguard Belt"],
		"tints": [Color(0.52, 0.39, 0.26), Color(0.66, 0.66, 0.7), Color(0.56, 0.42, 0.3), Color(0.46, 0.34, 0.22), Color(0.72, 0.86, 0.96), Color(0.86, 0.72, 0.42)],
		"implicits": [
			[{"stat": "max_life", "op": "flat", "min": 15, "max": 25}],
			[{"stat": "max_energy_shield", "op": "flat", "min": 10, "max": 20}],
			[{"stat": "armour", "op": "flat", "min": 60, "max": 100}],
			[{"stat": "max_life", "op": "flat", "min": 30, "max": 40}],
			[{"stat": "max_energy_shield", "op": "flat", "min": 25, "max": 40}],
			[{"stat": "armour", "op": "flat", "min": 220, "max": 300}, {"stat": "max_life", "op": "flat", "min": 25, "max": 35}],
		]},
}

## Categories per slot type (order = display order).
const SLOT_CATEGORIES := {
	"weapon": ["sword", "greatsword", "axe", "greataxe", "mace", "maul", "dagger", "wand", "staff", "bow", "crossbow"],
	"offhand": ["shield_str", "shield_dex", "shield_int", "focus", "quiver"],
	"helmet": ["helmet_str", "helmet_dex", "helmet_int", "helmet_str_dex", "helmet_str_int", "helmet_dex_int"],
	"body": ["body_str", "body_dex", "body_int", "body_str_dex", "body_str_int", "body_dex_int"],
	"gloves": ["gloves_str", "gloves_dex", "gloves_int", "gloves_str_dex", "gloves_str_int", "gloves_dex_int"],
	"boots": ["boots_str", "boots_dex", "boots_int", "boots_str_dex", "boots_str_int", "boots_dex_int"],
	"ring": ["ring"],
	"amulet": ["amulet"],
	"belt": ["belt"],
}


# ------------------------------------------------------------------ formulas (also used by Item)

## Requirement for one attribute: pure bases round(8 + 1.6 L), hybrids round(5 + 1.0 L) each.
static func attribute_requirement(level: int, hybrid: bool) -> int:
	if hybrid:
		return int(roundf(5.0 + 1.0 * level))
	return int(roundf(8.0 + 1.6 * level))


## Body-armour defence value of one type at an effective level (before slot/hybrid factors).
static func body_defence(kind: String, eff: int) -> float:
	var e := float(maxi(eff, 1) - 1)
	match kind:
		"armour":
			return 15.0 + 7.5 * e
		"evasion":
			return 50.0 + 9.0 * e
		"energy_shield":
			return 12.0 + 3.2 * e
	return 0.0


## Effective level for weapon/defence numbers.
static func effective_level(item_level: int, base_level: int) -> int:
	return maxi(1, mini(item_level, base_level + TIER_GROWTH))


# ------------------------------------------------------------------ builder

static func build_bases() -> Dictionary:
	var out := {}
	for cat: String in WEAPONS:
		_build_weapon(out, cat, WEAPONS[cat])
	for cat: String in SHIELDS:
		_build_shield(out, cat, SHIELDS[cat])
	_build_focus(out)
	_build_quiver(out)
	for slot: String in ARMOUR_SLOTS:
		for kind in ARMOUR_KINDS:
			_build_armour(out, slot, kind)
	for cat: String in JEWELLERY:
		_build_jewellery(out, cat, JEWELLERY[cat])
	return out


static func _req_for(attrs: Array, level: int) -> Dictionary:
	var req := {"strength": 0, "dexterity": 0, "intelligence": 0}
	var hybrid := attrs.size() > 1
	for a in attrs:
		req[ATTR_NAMES[a]] = attribute_requirement(level, hybrid)
	return req


static func _blend_tint(attrs: Array, tier_index: int) -> Color:
	var c := Color(0, 0, 0)
	for a in attrs:
		c += (ATTR_TINTS[a] as Array)[tier_index]
	c /= float(attrs.size())
	c.a = 1.0
	return c


static func _range_templates(specs: Array, tier_index: int) -> Array:
	var out: Array = []
	for s: Dictionary in specs:
		var r: Array = s["tiers"][tier_index]
		out.append({"stat": s["stat"], "op": s["op"], "min": r[0], "max": r[1]})
	return out


static func _common(id: String, cat: String, tier_index: int, name: String, slot: String, item_class: String) -> Dictionary:
	return {
		"id": id, "name": name, "category": cat, "tier": tier_index + 1, "item_class": item_class,
		"slot_type": slot, "weapon_type": "", "two_handed": false, "level": TIER_LEVELS[tier_index],
		"req": {"strength": 0, "dexterity": 0, "intelligence": 0}, "model": "", "tint": Color.WHITE,
		"tags": [slot, cat], "implicits": [],
	}


static func _build_weapon(out: Dictionary, cat: String, d: Dictionary) -> void:
	for t in 6:
		var id := "%s_%d" % [cat, t + 1]
		var b := _common(id, cat, t, d["names"][t], "weapon", d["class"])
		var level: int = b["level"]
		b["weapon_type"] = d["weapon_type"]
		b["two_handed"] = d["two_handed"]
		b["req"] = _req_for(d["req"], level)
		b["model"] = d["model"]
		b["tint"] = (WOOD_TINTS if d["wood"] else METAL_TINTS)[t]
		var tags: Array = b["tags"]
		tags.append(d["weapon_type"])
		tags.append_array(d["tags"])
		b["implicits"] = _range_templates(d["implicits"], t)
		var scale := Balance.weapon_damage_scale(level)
		b["template_min"] = d["min"]
		b["template_max"] = d["max"]
		b["phys_min"] = roundf(float(d["min"]) * scale)
		b["phys_max"] = roundf(float(d["max"]) * scale)
		b["attack_speed"] = d["aps"]
		b["crit_chance"] = d["crit"]
		b["range"] = d["range"]
		out[id] = b


static func _apply_defences(b: Dictionary, types: Array, factor: float) -> void:
	var level: int = b["level"]
	b["defence_types"] = types
	b["defence_factor"] = factor
	for k in ["armour", "evasion", "energy_shield"]:
		b[k] = roundf(body_defence(k, level) * factor) if k in types else 0.0
	var tags: Array = b["tags"]
	for k: String in types:
		tags.append({"armour": "armour_def", "evasion": "evasion_def", "energy_shield": "es_def"}[k])


static func _defence_types(attrs: Array) -> Array:
	var types: Array = []
	for a in attrs:
		types.append({"str": "armour", "dex": "evasion", "int": "energy_shield"}[a])
	return types


static func _build_shield(out: Dictionary, cat: String, d: Dictionary) -> void:
	for t in 6:
		var id := "%s_%d" % [cat, t + 1]
		var b := _common(id, cat, t, d["names"][t], "offhand", "Shield")
		b["weapon_type"] = "shield"
		b["req"] = _req_for(d["attrs"], b["level"])
		b["model"] = "offhand_shield"
		b["tint"] = _blend_tint(d["attrs"], t)
		(b["tags"] as Array).append("shield")
		_apply_defences(b, _defence_types(d["attrs"]), SLOT_DEFENCE_FACTOR["shield"])
		b["block"] = float(d["block"]) + float(t)
		out[id] = b


static func _build_focus(out: Dictionary) -> void:
	for t in 6:
		var id := "focus_%d" % (t + 1)
		var b := _common(id, "focus", t, FOCUS_NAMES[t], "offhand", "Focus")
		b["weapon_type"] = "focus"
		b["req"] = _req_for(["int"], b["level"])
		b["model"] = "offhand_focus"
		b["tint"] = _blend_tint(["int"], t).lightened(0.15)
		(b["tags"] as Array).append_array(["focus", "caster"])
		_apply_defences(b, ["energy_shield"], SLOT_DEFENCE_FACTOR["focus"])
		b["block"] = 0.0
		var r: Array = FOCUS_IMPLICIT[t]
		b["implicits"] = [{"stat": "spell_damage", "op": "inc", "min": r[0], "max": r[1]}]
		out[id] = b


static func _build_quiver(out: Dictionary) -> void:
	for t in 6:
		var id := "quiver_%d" % (t + 1)
		var b := _common(id, "quiver", t, QUIVER_NAMES[t], "offhand", "Quiver")
		b["weapon_type"] = "quiver"
		b["req"] = _req_for(["dex"], b["level"])
		b["model"] = "offhand_quiver"
		b["tint"] = _blend_tint(["dex"], t)
		(b["tags"] as Array).append("quiver")
		b["implicits"] = (QUIVER_IMPLICITS[t] as Array).duplicate(true)
		out[id] = b


static func _build_armour(out: Dictionary, slot: String, kind: String) -> void:
	var attrs: Array = Array(kind.split("_"))
	var cat := "%s_%s" % [slot, kind]
	var sd: Dictionary = ARMOUR_SLOTS[slot]
	for t in 6:
		var id := "%s_%d" % [cat, t + 1]
		var b := _common(id, cat, t, sd["names"][kind][t], slot, sd["class"])
		b["req"] = _req_for(attrs, b["level"])
		match slot:
			"helmet":
				b["model"] = "armor_helmet_" + String(attrs[0])
			"body":
				b["model"] = "armor_body"
			"gloves":
				b["model"] = "armor_gloves"
			"boots":
				b["model"] = "armor_boots"
		b["tint"] = _blend_tint(attrs, t)
		var factor: float = SLOT_DEFENCE_FACTOR[slot] * (HYBRID_DEFENCE_FACTOR if attrs.size() > 1 else 1.0)
		_apply_defences(b, _defence_types(attrs), factor)
		b["block"] = 0.0
		out[id] = b


static func _build_jewellery(out: Dictionary, cat: String, d: Dictionary) -> void:
	for t in 6:
		var id := "%s_%d" % [cat, t + 1]
		var b := _common(id, cat, t, d["names"][t], cat, d["class"])
		b["model"] = d["model"]
		b["tint"] = d["tints"][t]
		b["implicits"] = (d["implicits"][t] as Array).duplicate(true)
		out[id] = b

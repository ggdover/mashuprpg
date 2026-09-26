class_name StatDefs
extends RefCounted
## The stat vocabulary shared by items, passives, skills, buffs and monsters, plus the text for
## describing mods in tooltips. OWNER: orchestrator. See docs/ARCHITECTURE.md §5.
## FROZEN during waves 1-2: module agents must NOT edit this file. Need a new signal/stat/helper?
## Keep it in a file you own and list it in your final report; the orchestrator merges between waves.
## A module that truly needs a private stat may register it at runtime from its own autoload's
## _init(): StatDefs.register_stats({"my_stat": {"name": "..."}}) — but prefer existing stats.
##
## Each entry: stat_id -> {
##   "name":  noun used by the generic templates ("maximum Life"),
##   "flat":  optional template for op "flat"  ("{v}" value, "{v2}" max of a range),
##   "inc":   optional template for op "inc"   (defaults to "{v}% increased {name}" / "reduced"),
##   "more":  optional template for op "more"  (defaults to "{v}% more {name}" / "less"),
##   "flag":  template for op "flag" (keystones),
##   "local": true if the stat only exists on items and modifies that item's own base properties,
##   "range": true if the flat value is a min-max range (mods carry "value2"),
## }

const DAMAGE_TYPES: Array[String] = ["physical", "fire", "cold", "lightning", "chaos"]
const ELEMENTAL_TYPES: Array[String] = ["fire", "cold", "lightning"]
const AILMENTS: Array[String] = ["ignite", "chill", "freeze", "shock", "bleed", "poison"]
## Weapon categories a weapon's "weapon_type" can have ("unarmed" is used when nothing is equipped).
## "monster" is the weapon type of every monster weapon (never scales with weapon-type stats).
const WEAPON_TYPES: Array[String] = ["sword", "axe", "mace", "dagger", "wand", "staff", "bow", "crossbow", "unarmed", "monster"]
const MELEE_WEAPON_TYPES: Array[String] = ["sword", "axe", "mace", "dagger", "staff", "unarmed"]
## Maximum for resistances unless something raises it.
const RESIST_CAP := 75.0

const STATS := {
	# ---------------------------------------------------------------- attributes
	"strength": {"name": "Strength"},
	"dexterity": {"name": "Dexterity"},
	"intelligence": {"name": "Intelligence"},
	"all_attributes": {"name": "all Attributes"},

	# ---------------------------------------------------------------- pools & recovery
	"max_life": {"name": "maximum Life"},
	"max_mana": {"name": "maximum Mana"},
	"max_energy_shield": {"name": "maximum Energy Shield"},
	"life_regen": {"name": "Life Regeneration", "flat": "Regenerate {v} Life per second"},
	"life_regen_percent": {"name": "Life Regeneration", "flat": "Regenerate {v}% of maximum Life per second"},
	"mana_regen": {"name": "Mana Regeneration Rate"},
	"energy_shield_recharge": {"name": "Energy Shield Recharge Rate"},
	"life_leech": {"name": "Life Leech", "flat": "{v}% of Hit Damage Leeched as Life"},
	"mana_leech": {"name": "Mana Leech", "flat": "{v}% of Hit Damage Leeched as Mana"},
	"life_on_hit": {"name": "Life on Hit", "flat": "Gain {v} Life per Enemy Hit"},
	"life_on_kill": {"name": "Life on Kill", "flat": "Gain {v} Life per Enemy Killed"},
	"mana_on_kill": {"name": "Mana on Kill", "flat": "Gain {v} Mana per Enemy Killed"},
	"potion_effect": {"name": "Potion Effect"},

	# ---------------------------------------------------------------- defences
	"armour": {"name": "Armour"},
	"evasion": {"name": "Evasion Rating"},
	"block_chance": {"name": "Block Chance", "flat": "+{v}% Chance to Block Attack Damage"},
	"evade_chance": {"name": "Evade Chance", "flat": "+{v}% Chance to Evade Attacks"},
	"fire_resistance": {"name": "Fire Resistance", "flat": "+{v}% to Fire Resistance"},
	"cold_resistance": {"name": "Cold Resistance", "flat": "+{v}% to Cold Resistance"},
	"lightning_resistance": {"name": "Lightning Resistance", "flat": "+{v}% to Lightning Resistance"},
	"chaos_resistance": {"name": "Chaos Resistance", "flat": "+{v}% to Chaos Resistance"},
	"elemental_resistance": {"name": "Elemental Resistances", "flat": "+{v}% to all Elemental Resistances"},
	"physical_damage_reduction": {"name": "Physical Damage Reduction", "flat": "{v}% additional Physical Damage Reduction"},
	"damage_taken": {"name": "Damage taken"},

	# ---------------------------------------------------------------- speed
	"movement_speed": {"name": "Movement Speed"},
	"attack_speed": {"name": "Attack Speed"},
	"cast_speed": {"name": "Cast Speed"},

	# ---------------------------------------------------------------- damage scaling (inc / more)
	"damage": {"name": "Damage"},
	"physical_damage": {"name": "Physical Damage"},
	"fire_damage": {"name": "Fire Damage"},
	"cold_damage": {"name": "Cold Damage"},
	"lightning_damage": {"name": "Lightning Damage"},
	"chaos_damage": {"name": "Chaos Damage"},
	"elemental_damage": {"name": "Elemental Damage"},
	"attack_damage": {"name": "Attack Damage"},
	"spell_damage": {"name": "Spell Damage"},
	"melee_damage": {"name": "Melee Damage"},
	"projectile_damage": {"name": "Projectile Damage"},
	"area_damage": {"name": "Area Damage"},
	"damage_over_time": {"name": "Damage over Time"},
	"sword_damage": {"name": "Damage with Swords"},
	"axe_damage": {"name": "Damage with Axes"},
	"mace_damage": {"name": "Damage with Maces"},
	"dagger_damage": {"name": "Damage with Daggers"},
	"wand_damage": {"name": "Damage with Wands"},
	"staff_damage": {"name": "Damage with Staves"},
	"bow_damage": {"name": "Damage with Bows"},
	"crossbow_damage": {"name": "Damage with Crossbows"},
	"one_handed_damage": {"name": "Damage with One Handed Weapons"},
	"two_handed_damage": {"name": "Damage with Two Handed Weapons"},

	# ---------------------------------------------------------------- added damage (flat ranges)
	"added_physical_attack": {"name": "Added Physical Damage", "range": true, "flat": "Adds {v} to {v2} Physical Damage to Attacks"},
	"added_fire_attack": {"name": "Added Fire Damage", "range": true, "flat": "Adds {v} to {v2} Fire Damage to Attacks"},
	"added_cold_attack": {"name": "Added Cold Damage", "range": true, "flat": "Adds {v} to {v2} Cold Damage to Attacks"},
	"added_lightning_attack": {"name": "Added Lightning Damage", "range": true, "flat": "Adds {v} to {v2} Lightning Damage to Attacks"},
	"added_chaos_attack": {"name": "Added Chaos Damage", "range": true, "flat": "Adds {v} to {v2} Chaos Damage to Attacks"},
	"added_physical_spell": {"name": "Added Physical Damage", "range": true, "flat": "Adds {v} to {v2} Physical Damage to Spells"},
	"added_fire_spell": {"name": "Added Fire Damage", "range": true, "flat": "Adds {v} to {v2} Fire Damage to Spells"},
	"added_cold_spell": {"name": "Added Cold Damage", "range": true, "flat": "Adds {v} to {v2} Cold Damage to Spells"},
	"added_lightning_spell": {"name": "Added Lightning Damage", "range": true, "flat": "Adds {v} to {v2} Lightning Damage to Spells"},
	"added_chaos_spell": {"name": "Added Chaos Damage", "range": true, "flat": "Adds {v} to {v2} Chaos Damage to Spells"},

	# ---------------------------------------------------------------- critical strikes
	"crit_chance": {"name": "Critical Strike Chance"},
	"base_crit_chance": {"name": "Critical Strike Chance", "flat": "+{v}% to Critical Strike Chance"},
	"crit_multiplier": {"name": "Critical Strike Multiplier", "flat": "+{v}% to Critical Strike Multiplier"},

	# ---------------------------------------------------------------- skill behaviour
	"area_of_effect": {"name": "Area of Effect"},
	"projectile_speed": {"name": "Projectile Speed"},
	"additional_projectiles": {"name": "additional Projectiles", "flat": "Skills fire {v} additional Projectiles"},
	"pierce": {"name": "Pierce", "flat": "Projectiles Pierce {v} additional Targets"},
	"chain": {"name": "Chain", "flat": "Chaining Skills Chain {v} additional times"},
	"skill_duration": {"name": "Skill Effect Duration"},
	"cooldown_recovery": {"name": "Cooldown Recovery Rate"},
	"mana_cost": {"name": "Mana Cost of Skills"},

	# ---------------------------------------------------------------- ailments
	"ignite_chance": {"name": "Ignite Chance", "flat": "{v}% chance to Ignite"},
	"freeze_chance": {"name": "Freeze Chance", "flat": "{v}% chance to Freeze"},
	"shock_chance": {"name": "Shock Chance", "flat": "{v}% chance to Shock"},
	"bleed_chance": {"name": "Bleed Chance", "flat": "{v}% chance to cause Bleeding with Attacks"},
	"poison_chance": {"name": "Poison Chance", "flat": "{v}% chance to Poison on Hit"},

	# ---------------------------------------------------------------- loot
	"item_rarity": {"name": "Rarity of Items found"},
	"item_quantity": {"name": "Quantity of Items found"},
	"gold_find": {"name": "Gold found"},

	# ---------------------------------------------------------------- LOCAL item stats (only on items;
	# they modify the item's own base properties and are never added to a character's StatBlock)
	"local_physical_damage": {"name": "Physical Damage", "local": true},
	"local_added_physical": {"name": "Physical Damage", "local": true, "range": true, "flat": "Adds {v} to {v2} Physical Damage"},
	"local_added_fire": {"name": "Fire Damage", "local": true, "range": true, "flat": "Adds {v} to {v2} Fire Damage"},
	"local_added_cold": {"name": "Cold Damage", "local": true, "range": true, "flat": "Adds {v} to {v2} Cold Damage"},
	"local_added_lightning": {"name": "Lightning Damage", "local": true, "range": true, "flat": "Adds {v} to {v2} Lightning Damage"},
	"local_added_chaos": {"name": "Chaos Damage", "local": true, "range": true, "flat": "Adds {v} to {v2} Chaos Damage"},
	"local_attack_speed": {"name": "Attack Speed", "local": true},
	"local_crit_chance": {"name": "Critical Strike Chance", "local": true},
	"local_armour": {"name": "Armour", "local": true},
	"local_evasion": {"name": "Evasion Rating", "local": true},
	"local_energy_shield": {"name": "Energy Shield", "local": true},
	"local_block": {"name": "Block Chance", "local": true, "flat": "+{v}% Chance to Block"},

	# ---------------------------------------------------------------- flags (keystones / uniques)
	"blood_magic": {"name": "Blood Magic", "flag": "Skills cost Life instead of Mana"},
	"iron_reflexes": {"name": "Iron Reflexes", "flag": "Converts all Evasion Rating to Armour"},
	"mind_over_matter": {"name": "Mind over Matter", "flag": "30% of Damage is taken from Mana before Life"},
	"no_crit": {"name": "Resolute Technique", "flag": "Your Hits can't be Critical Strikes"},
	"point_blank": {"name": "Point Blank", "flag": "Projectiles deal up to 50% more Damage to targets close to you, and up to 30% less Damage at long range"},
	"cannot_evade": {"name": "Unwavering", "flag": "Cannot Evade enemy Attacks"},
	"pain_attunement": {"name": "Pain Attunement", "flag": "30% more Spell Damage while on Low Life (35% or less)"},
}


## Stats registered at runtime by modules (see header). Looked up after STATS.
static var _extra: Dictionary = {}


static func register_stats(d: Dictionary) -> void:
	_extra.merge(d, true)


static func get_info(stat: String) -> Dictionary:
	if STATS.has(stat):
		return STATS[stat]
	return _extra.get(stat, {})


static func has_stat(stat: String) -> bool:
	return STATS.has(stat) or _extra.has(stat)


static func is_local(stat: String) -> bool:
	return get_info(stat).get("local", false)


static func is_range(stat: String) -> bool:
	return get_info(stat).get("range", false)


static func get_stat_name(stat: String) -> String:
	return get_info(stat).get("name", stat.capitalize())


## Format a number for tooltips: whole numbers without decimals, otherwise one decimal.
static func fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(int(roundf(v)))
	return "%.1f" % v


## Human-readable line for one mod, e.g. "+25 to maximum Life", "12% reduced Mana Cost of Skills".
static func describe(m: Dictionary) -> String:
	var stat: String = m.get("stat", "")
	var op: String = m.get("op", "flat")
	var v: float = float(m.get("value", 0.0))
	var info: Dictionary = get_info(stat)
	var stat_name: String = info.get("name", stat.capitalize())
	match op:
		"flat":
			var tpl: String = info.get("flat", "")
			if tpl == "":
				tpl = ("+{v} to {name}" if v >= 0.0 else "{v} to {name}")
			var v2: float = float(m.get("value2", v))
			return tpl.replace("{v2}", fmt(v2)).replace("{v}", fmt(v)).replace("{name}", stat_name)
		"inc":
			var tpl_inc: String = info.get("inc", "")
			if tpl_inc != "":
				return tpl_inc.replace("{v}", fmt(v)).replace("{name}", stat_name)
			if v >= 0.0:
				return "%s%% increased %s" % [fmt(v), stat_name]
			return "%s%% reduced %s" % [fmt(-v), stat_name]
		"more":
			var tpl_more: String = info.get("more", "")
			if tpl_more != "":
				return tpl_more.replace("{v}", fmt(v)).replace("{name}", stat_name)
			if v >= 0.0:
				return "%s%% more %s" % [fmt(v), stat_name]
			return "%s%% less %s" % [fmt(-v), stat_name]
		"flag":
			return info.get("flag", stat_name)
	return "%s %s %s" % [stat, op, fmt(v)]


## Describe several mods, merging mods with the same stat+op first (values summed).
## Order of first appearance is kept.
static func describe_mods(mods: Array) -> PackedStringArray:
	var merged: Array[Dictionary] = []
	var index := {}
	for m in mods:
		var op: String = m.get("op", "flat")
		var key: String = "%s|%s" % [m.get("stat", ""), op]
		if op == "more" or op == "flag" or not index.has(key):
			index[key] = merged.size()
			merged.append((m as Dictionary).duplicate())
		else:
			var target: Dictionary = merged[index[key]]
			target["value"] = float(target.get("value", 0.0)) + float(m.get("value", 0.0))
			if m.has("value2") or target.has("value2"):
				target["value2"] = float(target.get("value2", target["value"])) + float(m.get("value2", m.get("value", 0.0)))
	var out: PackedStringArray = []
	for m in merged:
		out.append(describe(m))
	return out

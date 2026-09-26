extends RefCounted
## Pure data for monsters: archetype + boss definitions (§12 schema), monster modifiers, spawn pools
## per dungeon theme, rare-name parts and per-model constants (reference run speed, height).
## Accessed through the EnemyDB autoload; internal to the enemies module (preloaded, no
## class_name). OWNER: enemies (wave 2). See docs/ARCHITECTURE.md §12.
##
## Def schema (EnemyDB.get_def returns a deep copy with "id" filled in):
##   "name", "model", "scale", "tint", "life_mult", "damage_mult", "move_speed" (m/s),
##   "attack_speed" (monster weapon attacks/s), "melee_range" (m, centre to target edge),
##   "aggro_radius", "xp_mult", "armour_mult", "resist": {type: %} (physical = extra phys reduction),
##   "skills": [{"id", "range" (0 = melee reach), "weight", "cooldown" (extra AI delay, s),
##   "min_range" (optional)}], "ai": "melee"|"ranged"|"caster"|"summoner"|"boss",
##   "preferred_range", "min_depth", "boss": bool
## Extra keys used by Enemy: "radius" (collision radius, m), "height" (model height, m),
##   "attach": {bone: model id} (weapons carried in the hand), "attach_tint", "max_per_pack",
##   "companions" (archetypes a mixed pack pairs it with), "summon_cap" (summoners),
##   "enrage_at" (bosses: life ratio that triggers the enrage roar), "description".

## Monster skill ids (§8.5, frozen). Defs may only use these.
const MONSTER_SKILLS: Array[String] = ["m_melee", "m_bite", "m_arrow", "m_firebolt", "m_frostbolt", "m_slam",
	"m_summon", "m_leap", "m_boss_nova", "m_boss_volley", "m_boss_charge", "m_boss_meteors", "m_boss_slam",
	"m_boss_spikes"]

const ARCHETYPES := {
	"skeleton_warrior": {
		"name": "Skeleton Warrior", "model": "char_skeleton", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 1.0, "damage_mult": 1.0, "move_speed": 3.6, "attack_speed": 0.9, "melee_range": 1.9,
		"aggro_radius": 11.0, "xp_mult": 1.0, "armour_mult": 1.2, "resist": {"cold": 15, "chaos": 20},
		"skills": [{"id": "m_melee", "range": 0.0, "weight": 1.0, "cooldown": 0.0}],
		"ai": "melee", "preferred_range": 0.0, "min_depth": 1, "boss": false,
		"radius": 0.42, "height": 1.85, "attach": {"grip_r": "weapon_sword"}, "attach_tint": Color(0.72, 0.66, 0.6),
		"companions": ["skeleton_archer", "necromancer"], "max_per_pack": 6,
		"description": "Rattling bones and a rusted blade.",
	},
	"skeleton_archer": {
		"name": "Skeleton Archer", "model": "char_skeleton", "scale": 0.97, "tint": Color(0.92, 0.9, 0.84),
		"life_mult": 0.75, "damage_mult": 0.9, "move_speed": 3.4, "attack_speed": 0.8, "melee_range": 1.8,
		"aggro_radius": 14.0, "xp_mult": 1.0, "armour_mult": 0.8, "resist": {"cold": 15, "chaos": 20},
		"skills": [{"id": "m_arrow", "range": 12.0, "weight": 1.0, "cooldown": 0.3}],
		"ai": "ranged", "preferred_range": 9.0, "min_depth": 1, "boss": false,
		"radius": 0.4, "height": 1.8, "attach": {"grip_r": "weapon_bow", "chest": "offhand_quiver"},
		"attach_tint": Color(0.7, 0.62, 0.52), "companions": ["skeleton_warrior"], "max_per_pack": 4,
		"description": "Keeps its distance and looses arrows.",
	},
	"zombie": {
		"name": "Rotting Zombie", "model": "char_zombie", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 1.8, "damage_mult": 1.3, "move_speed": 2.3, "attack_speed": 0.7, "melee_range": 1.8,
		"aggro_radius": 9.0, "xp_mult": 1.15, "armour_mult": 0.5, "resist": {"chaos": 30, "cold": 10},
		"skills": [{"id": "m_melee", "range": 0.0, "weight": 1.0, "cooldown": 0.0}],
		"ai": "melee", "preferred_range": 0.0, "min_depth": 1, "boss": false,
		"radius": 0.42, "height": 1.75, "attach": {},
		"companions": ["ghoul", "necromancer"], "max_per_pack": 6,
		"description": "Slow, tough and hits hard.",
	},
	"ghoul": {
		"name": "Ghoul", "model": "char_ghoul", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 0.6, "damage_mult": 0.8, "move_speed": 5.5, "attack_speed": 1.0, "melee_range": 1.6,
		"aggro_radius": 12.0, "xp_mult": 0.85, "armour_mult": 0.4, "resist": {"chaos": 20},
		"skills": [
			{"id": "m_bite", "range": 0.0, "weight": 3.0, "cooldown": 0.0},
			{"id": "m_leap", "range": 8.0, "min_range": 3.5, "weight": 2.0, "cooldown": 5.0},
		],
		"ai": "melee", "preferred_range": 0.0, "min_depth": 2, "boss": false,
		"radius": 0.4, "height": 1.5, "attach": {},
		"companions": ["zombie", "brute"], "max_per_pack": 6,
		"description": "Fast, fragile and leaps at its prey.",
	},
	"cultist": {
		"name": "Ember Cultist", "model": "char_cultist", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 0.8, "damage_mult": 1.1, "move_speed": 3.2, "attack_speed": 0.8, "melee_range": 1.8,
		"aggro_radius": 13.0, "xp_mult": 1.1, "armour_mult": 0.4, "resist": {"fire": 40},
		"skills": [{"id": "m_firebolt", "range": 12.0, "weight": 1.0, "cooldown": 0.6}],
		"ai": "caster", "preferred_range": 8.5, "min_depth": 2, "boss": false,
		"radius": 0.4, "height": 1.9, "attach": {"grip_r": "weapon_dagger"}, "attach_tint": Color(0.85, 0.7, 0.45),
		"companions": ["frost_cultist", "brute"], "max_per_pack": 5,
		"description": "Hurls exploding firebolts.",
	},
	"frost_cultist": {
		"name": "Frost Cultist", "model": "char_cultist", "scale": 1.0, "tint": Color(0.5, 0.72, 1.0),
		"life_mult": 0.8, "damage_mult": 1.05, "move_speed": 3.2, "attack_speed": 0.8, "melee_range": 1.8,
		"aggro_radius": 13.0, "xp_mult": 1.1, "armour_mult": 0.4, "resist": {"cold": 40},
		"skills": [{"id": "m_frostbolt", "range": 12.0, "weight": 1.0, "cooldown": 0.6}],
		"ai": "caster", "preferred_range": 8.5, "min_depth": 3, "boss": false,
		"radius": 0.4, "height": 1.9, "attach": {"grip_r": "weapon_wand"}, "attach_tint": Color(0.6, 0.8, 1.0),
		"companions": ["cultist", "brute"], "max_per_pack": 5,
		"description": "Chilling bolts slow the unwary.",
	},
	"brute": {
		"name": "Cave Brute", "model": "char_brute", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 3.0, "damage_mult": 1.6, "move_speed": 3.0, "attack_speed": 0.7, "melee_range": 2.5,
		"aggro_radius": 10.0, "xp_mult": 2.6, "armour_mult": 2.0, "resist": {"physical": 10, "fire": 15, "cold": 15, "lightning": 15},
		"skills": [
			{"id": "m_melee", "range": 0.0, "weight": 3.0, "cooldown": 0.0},
			{"id": "m_slam", "range": 3.2, "weight": 2.0, "cooldown": 5.0},
		],
		"ai": "melee", "preferred_range": 0.0, "min_depth": 3, "boss": false,
		"radius": 0.62, "height": 2.45, "attach": {"grip_r": "weapon_maul"}, "attach_tint": Color(0.6, 0.52, 0.45),
		"companions": ["cultist", "ghoul", "zombie"], "max_per_pack": 2,
		"description": "A hulking brute whose slam shakes the floor.",
	},
	"necromancer": {
		"name": "Necromancer", "model": "char_cultist", "scale": 1.04, "tint": Color(0.62, 0.42, 0.85),
		"life_mult": 1.2, "damage_mult": 1.0, "move_speed": 3.0, "attack_speed": 0.8, "melee_range": 1.8,
		"aggro_radius": 13.0, "xp_mult": 2.0, "armour_mult": 0.5, "resist": {"chaos": 40, "cold": 15},
		"skills": [
			{"id": "m_summon", "range": 16.0, "weight": 3.0, "cooldown": 9.0},
			{"id": "m_firebolt", "range": 12.5, "weight": 2.0, "cooldown": 1.2},
		],
		"ai": "summoner", "preferred_range": 10.0, "min_depth": 5, "boss": false,
		"radius": 0.42, "height": 1.95, "attach": {"grip_r": "weapon_staff"}, "attach_tint": Color(0.55, 0.45, 0.6),
		"companions": ["skeleton_warrior", "zombie"], "max_per_pack": 1, "summon_cap": 4,
		"description": "Raises skeletons from the dead.",
	},
}

const BOSSES := {
	"boss_lich": {
		"name": "Vexis, the Pale Lich", "model": "char_lich", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 25.0, "damage_mult": 1.0, "move_speed": 2.9, "attack_speed": 0.9, "melee_range": 2.6,
		"aggro_radius": 15.0, "xp_mult": 1.0, "armour_mult": 1.0,
		"resist": {"fire": 25, "cold": 35, "lightning": 25, "chaos": 40},
		"skills": [
			{"id": "m_boss_volley", "range": 16.0, "weight": 3.0, "cooldown": 1.2},
			{"id": "m_boss_nova", "range": 5.5, "weight": 4.0, "cooldown": 7.0},
			{"id": "m_boss_meteors", "range": 18.0, "weight": 3.0, "cooldown": 9.0},
			{"id": "m_summon", "range": 20.0, "weight": 2.0, "cooldown": 14.0},
		],
		"ai": "boss", "preferred_range": 8.0, "min_depth": 1, "boss": true,
		"radius": 0.85, "height": 3.2, "attach": {}, "summon_cap": 6, "enrage_at": 0.5,
		"description": "Guardian of the odd depths: firebolt volleys, fire novas and meteors.",
	},
	"boss_gravebreaker": {
		"name": "Grothak the Gravebreaker", "model": "char_gravebreaker", "scale": 1.0, "tint": Color(1, 1, 1),
		"life_mult": 25.0, "damage_mult": 1.0, "move_speed": 3.9, "attack_speed": 0.8, "melee_range": 3.1,
		"aggro_radius": 15.0, "xp_mult": 1.0, "armour_mult": 3.0,
		"resist": {"physical": 10, "fire": 25, "cold": 25, "lightning": 25, "chaos": 25},
		"skills": [
			{"id": "m_melee", "range": 0.0, "weight": 3.0, "cooldown": 0.0},
			{"id": "m_boss_slam", "range": 5.0, "weight": 4.0, "cooldown": 6.0},
			{"id": "m_boss_charge", "range": 14.0, "min_range": 5.0, "weight": 4.0, "cooldown": 8.0},
			{"id": "m_boss_spikes", "range": 14.0, "weight": 3.0, "cooldown": 9.0},
		],
		"ai": "boss", "preferred_range": 0.0, "min_depth": 1, "boss": true,
		"radius": 0.95, "height": 3.2, "attach": {}, "enrage_at": 0.5,
		"description": "Guardian of the even depths: tombstone slams, charges and bone spikes.",
	},
}

## Spawn weights per dungeon theme (archetypes whose min_depth is above the depth are skipped).
const THEME_WEIGHTS := {
	"crypt": {"skeleton_warrior": 5.0, "skeleton_archer": 3.5, "zombie": 4.0, "ghoul": 1.0, "cultist": 1.0,
		"frost_cultist": 1.0, "brute": 1.0, "necromancer": 2.5},
	"cave": {"ghoul": 5.0, "zombie": 3.0, "brute": 3.0, "skeleton_warrior": 2.0, "skeleton_archer": 2.0,
		"frost_cultist": 2.5, "cultist": 1.0, "necromancer": 1.0},
	"inferno": {"cultist": 5.0, "brute": 3.0, "ghoul": 2.0, "skeleton_warrior": 2.0, "skeleton_archer": 2.0,
		"necromancer": 2.0, "frost_cultist": 1.0, "zombie": 1.0},
}

## Monster modifiers (§12). "stats" is built per level by EnemyDB.get_mod_stats(); "color" tints
## the small aura of elemental mods; "group" mods exclude each other.
const MONSTER_MODS := {
	"hasted": {"name": "Hasted", "group": "speed", "desc": "+30% movement, attack and cast speed"},
	"armoured": {"name": "Armoured", "group": "armour", "desc": "+100% armour, +20% physical damage reduction"},
	"fiery": {"name": "Fiery", "group": "element", "color": Color(1.0, 0.45, 0.12), "desc": "Adds fire damage, +40% fire resistance"},
	"frigid": {"name": "Frigid", "group": "element", "color": Color(0.45, 0.78, 1.0), "desc": "Adds cold damage, +40% cold resistance"},
	"shocking": {"name": "Shocking", "group": "element", "color": Color(1.0, 0.92, 0.3), "desc": "Adds lightning damage, +40% lightning resistance"},
	"regenerating": {"name": "Regenerating", "group": "regen", "desc": "Regenerates 2% of life per second"},
	"vampiric": {"name": "Vampiric", "group": "leech", "desc": "Leeches 8% of damage as life"},
	"berserker": {"name": "Berserker", "group": "damage", "desc": "+40% damage"},
	"resilient": {"name": "Resilient", "group": "resist", "desc": "+30% elemental resistances"},
	"extra_life": {"name": "Hulking", "group": "life", "desc": "+60% maximum life"},
}

## Reference run speed (m/s) of each model's run cycle (§19): run speed_scale = speed / ref.
const MODEL_RUN_SPEED := {
	"char_player": 5.2, "char_skeleton": 5.2, "char_brute": 5.4, "char_gravebreaker": 6.7,
	"char_ghoul": 3.5, "char_cultist": 2.8, "char_zombie": 3.3, "char_lich": 3.0,
}

## Rare monster names: "<prefix> <suffix>" ("Grim Howl").
const RARE_PREFIXES: Array[String] = ["Grim", "Blood", "Dread", "Gore", "Rot", "Doom", "Night", "Bone", "Ash",
	"Storm", "Soul", "Death", "Vile", "Plague", "Shadow", "Wrath", "Grave", "Hollow", "Rust", "Ember", "Frost",
	"Venom", "Carrion", "Dusk", "Iron", "Wretch", "Gloom", "Pyre", "Mourn", "Blight", "Sorrow", "Hate"]
const RARE_SUFFIXES: Array[String] = ["Howl", "Fang", "Maw", "Bane", "Gnash", "Shriek", "Grasp", "Hunger",
	"Wound", "Rend", "Thorn", "Brand", "Scourge", "Spawn", "Wail", "Gnaw", "Clutch", "Tongue", "Eye", "Heart",
	"Whisper", "Mangler", "Harrow", "Reaver", "Stalker", "Ripper", "Chill", "Flayer", "Husk", "Marrow", "Spite",
	"Talon"]

extends RefCounted
## Unique items (docs/ARCHITECTURE.md §9.4): fixed mod lists (values roll inside the ranges) plus
## flavour text. OWNER: items. Used by ItemDB (preload); no class_name on purpose.
##
## Schema: {"id", "name", "base" (base id), "level" (minimum drop level = base level), "tint"
## (optional model tint override), "mods": [{"stat","op","min","max"[,"min2","max2"]} or
## {"stat","op","value"}], "flavour": String}.

const UNIQUES := {
	"gorebinder": {
		"name": "Gorebinder", "base": "axe_3", "tint": Color(0.75, 0.2, 0.18),
		"mods": [
			{"stat": "local_physical_damage", "op": "inc", "min": 120, "max": 160},
			{"stat": "local_added_physical", "op": "flat", "min": 6, "max": 9, "min2": 16, "max2": 22},
			{"stat": "bleed_chance", "op": "flat", "value": 25},
			{"stat": "life_leech", "op": "flat", "min": 1.0, "max": 1.5, "decimals": 1},
			{"stat": "max_life", "op": "flat", "min": 20, "max": 30},
		],
		"flavour": "It drinks deep, and it never forgets the taste.",
	},
	"emberheart": {
		"name": "Emberheart", "base": "staff_3", "tint": Color(1.0, 0.45, 0.2),
		"mods": [
			{"stat": "added_fire_spell", "op": "flat", "min": 8, "max": 12, "min2": 18, "max2": 26},
			{"stat": "fire_damage", "op": "inc", "min": 40, "max": 60},
			{"stat": "additional_projectiles", "op": "flat", "value": 1},
			{"stat": "ignite_chance", "op": "flat", "value": 20},
			{"stat": "fire_resistance", "op": "flat", "min": 20, "max": 30},
		],
		"flavour": "A coal that never cools, a will that never bends.",
	},
	"windshear": {
		"name": "Windshear", "base": "bow_4", "tint": Color(0.7, 0.95, 0.85),
		"mods": [
			{"stat": "local_physical_damage", "op": "inc", "min": 60, "max": 90},
			{"stat": "local_attack_speed", "op": "inc", "min": 15, "max": 20},
			{"stat": "additional_projectiles", "op": "flat", "value": 2},
			{"stat": "movement_speed", "op": "inc", "value": 10},
			{"stat": "dexterity", "op": "flat", "min": 20, "max": 30},
		],
		"flavour": "The wind does not aim. It simply arrives.",
	},
	"frostbite_grips": {
		"name": "Frostbite Grips", "base": "gloves_int_2", "tint": Color(0.55, 0.8, 1.0),
		"mods": [
			{"stat": "added_cold_attack", "op": "flat", "min": 4, "max": 6, "min2": 10, "max2": 14},
			{"stat": "freeze_chance", "op": "flat", "value": 15},
			{"stat": "cold_damage", "op": "inc", "min": 20, "max": 30},
			{"stat": "local_energy_shield", "op": "inc", "min": 60, "max": 80},
			{"stat": "cold_resistance", "op": "flat", "min": 25, "max": 35},
		],
		"flavour": "Hold on to what you love until it stops struggling.",
	},
	"stormcrown": {
		"name": "Stormcrown", "base": "helmet_int_3", "tint": Color(1.0, 0.92, 0.45),
		"mods": [
			{"stat": "lightning_damage", "op": "inc", "min": 30, "max": 40},
			{"stat": "shock_chance", "op": "flat", "value": 20},
			{"stat": "local_energy_shield", "op": "flat", "min": 25, "max": 35},
			{"stat": "local_energy_shield", "op": "inc", "min": 60, "max": 80},
			{"stat": "lightning_resistance", "op": "flat", "min": 20, "max": 30},
		],
		"flavour": "The heavens chose a king, and armed him with their anger.",
	},
	"wanderers_steps": {
		"name": "Wanderer's Steps", "base": "boots_dex_2", "tint": Color(0.55, 0.45, 0.3),
		"mods": [
			{"stat": "movement_speed", "op": "inc", "value": 30},
			{"stat": "local_evasion", "op": "inc", "min": 60, "max": 90},
			{"stat": "dexterity", "op": "flat", "min": 15, "max": 25},
			{"stat": "evade_chance", "op": "flat", "value": 5},
		],
		"flavour": "Every road ends somewhere. These boots have never noticed.",
	},
	"bulwark_of_the_fallen": {
		"name": "Bulwark of the Fallen", "base": "shield_str_3", "tint": Color(0.62, 0.55, 0.45),
		"mods": [
			{"stat": "local_block", "op": "flat", "value": 8},
			{"stat": "local_armour", "op": "inc", "min": 100, "max": 140},
			{"stat": "max_life", "op": "flat", "min": 40, "max": 60},
			{"stat": "life_regen", "op": "flat", "min": 8, "max": 12},
			{"stat": "physical_damage_reduction", "op": "flat", "value": 4},
		],
		"flavour": "Carried from the field by the last one still standing.",
	},
	"bloodbond_plate": {
		"name": "Bloodbond Plate", "base": "body_str_4", "tint": Color(0.6, 0.12, 0.12),
		"mods": [
			{"stat": "max_life", "op": "flat", "min": 80, "max": 100},
			{"stat": "blood_magic", "op": "flag", "value": 1},
			{"stat": "life_regen_percent", "op": "flat", "value": 1.5},
			{"stat": "local_armour", "op": "inc", "min": 80, "max": 110},
			{"stat": "strength", "op": "flat", "min": 20, "max": 30},
		],
		"flavour": "Pay the toll in blood. The plate will see to the rest.",
	},
	"voidheart_ring": {
		"name": "Voidheart Ring", "base": "ring_3", "tint": Color(0.55, 0.25, 0.75),
		"mods": [
			{"stat": "added_chaos_attack", "op": "flat", "min": 4, "max": 7, "min2": 11, "max2": 15},
			{"stat": "chaos_damage", "op": "inc", "min": 25, "max": 35},
			{"stat": "poison_chance", "op": "flat", "value": 20},
			{"stat": "chaos_resistance", "op": "flat", "min": 25, "max": 35},
		],
		"flavour": "In the hollow at the heart of the world, something hungry dreams.",
	},
	"glasswork_amulet": {
		"name": "Glasswork Amulet", "base": "amulet_2", "tint": Color(0.75, 0.95, 1.0),
		"mods": [
			{"stat": "damage", "op": "more", "value": 30},
			{"stat": "max_life", "op": "more", "value": -25},
			{"stat": "crit_chance", "op": "inc", "min": 20, "max": 30},
		],
		"flavour": "Beautiful, brilliant, and one bad day from shattering.",
	},
	"the_arbalest": {
		"name": "The Arbalest", "base": "crossbow_4", "tint": Color(0.45, 0.4, 0.38),
		"mods": [
			{"stat": "pierce", "op": "flat", "value": 3},
			{"stat": "projectile_damage", "op": "inc", "min": 40, "max": 60},
			{"stat": "local_physical_damage", "op": "inc", "min": 70, "max": 100},
			{"stat": "local_attack_speed", "op": "inc", "value": -10},
		],
		"flavour": "Built for sieges. Used on people.",
	},
	"seraphs_cord": {
		"name": "Seraph's Cord", "base": "belt_3", "tint": Color(1.0, 0.95, 0.75),
		"mods": [
			{"stat": "max_life", "op": "flat", "min": 40, "max": 60},
			{"stat": "max_energy_shield", "op": "flat", "min": 30, "max": 50},
			{"stat": "elemental_resistance", "op": "flat", "min": 10, "max": 15},
			{"stat": "energy_shield_recharge", "op": "inc", "value": 20},
		],
		"flavour": "Woven from a feather that fell for a thousand years.",
	},
	"serpents_fang": {
		"name": "Serpent's Fang", "base": "dagger_3", "tint": Color(0.45, 0.85, 0.35),
		"mods": [
			{"stat": "local_added_chaos", "op": "flat", "min": 5, "max": 8, "min2": 14, "max2": 20},
			{"stat": "poison_chance", "op": "flat", "value": 40},
			{"stat": "local_crit_chance", "op": "inc", "min": 30, "max": 40},
			{"stat": "damage_over_time", "op": "inc", "min": 20, "max": 30},
			{"stat": "dexterity", "op": "flat", "min": 20, "max": 30},
		],
		"flavour": "One kiss is all it ever takes.",
	},
	"mindwell": {
		"name": "Mindwell", "base": "focus_4", "tint": Color(0.4, 0.6, 1.0),
		"mods": [
			{"stat": "max_mana", "op": "flat", "min": 50, "max": 70},
			{"stat": "mind_over_matter", "op": "flag", "value": 1},
			{"stat": "spell_damage", "op": "inc", "min": 30, "max": 40},
			{"stat": "mana_regen", "op": "inc", "min": 40, "max": 60},
		],
		"flavour": "When the body falters, the mind holds the line.",
	},
	"earthbreaker": {
		"name": "Earthbreaker", "base": "maul_4", "tint": Color(0.55, 0.42, 0.3),
		"mods": [
			{"stat": "local_physical_damage", "op": "inc", "min": 140, "max": 180},
			{"stat": "area_of_effect", "op": "inc", "min": 20, "max": 25},
			{"stat": "area_damage", "op": "inc", "min": 30, "max": 40},
			{"stat": "local_attack_speed", "op": "inc", "value": -10},
			{"stat": "strength", "op": "flat", "min": 25, "max": 35},
		],
		"flavour": "The mountain is patient. It has been waiting for you.",
	},
}

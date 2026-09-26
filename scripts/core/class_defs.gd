class_name ClassDefs
extends RefCounted
## Playable classes. All classes can use every skill/item; the class sets starting attributes,
## starting gear/skills and the start position on the passive tree. OWNER: kernel (wave 1).
## Keep ids, keys and signatures. See docs/ARCHITECTURE.md §11.
## Class attributes are NOT stored on the character: Player.get_base_mods() adds
## get_attribute_mods(class_id) (flat Strength / Dexterity / Intelligence).

const ATTRIBUTES: Array[String] = ["strength", "dexterity", "intelligence"]
const DEFAULT_CLASS := "warrior"

const CLASSES := {
	"warrior": {
		"name": "Warrior",
		"description": "A hardened fighter. Strength: life, armour and melee damage.",
		"attributes": {"strength": 20, "dexterity": 12, "intelligence": 10},
		"start_items": ["sword_1", "body_str_1"],
		"skill_bar": ["basic_attack", "cleave", "", "", "", ""],
		"color": Color(0.8, 0.25, 0.2),
	},
	"ranger": {
		"name": "Ranger",
		"description": "A deadly marksman. Dexterity: evasion, attack speed and projectiles.",
		"attributes": {"strength": 12, "dexterity": 20, "intelligence": 10},
		"start_items": ["bow_1", "body_dex_1"],
		"skill_bar": ["basic_attack", "split_arrow", "", "", "", ""],
		"color": Color(0.3, 0.75, 0.3),
	},
	"sorcerer": {
		"name": "Sorcerer",
		"description": "A master of the elements. Intelligence: mana, energy shield and spells.",
		"attributes": {"strength": 10, "dexterity": 12, "intelligence": 20},
		"start_items": ["wand_1", "body_int_1"],
		"skill_bar": ["fireball", "basic_attack", "", "", "", ""],
		"color": Color(0.3, 0.45, 0.95),
	},
}


static func get_class_def(class_id: String) -> Dictionary:
	return CLASSES.get(class_id, {})


static func get_class_ids() -> Array:
	return CLASSES.keys()


static func has_class(class_id: String) -> bool:
	return CLASSES.has(class_id)


## Display name ("Warrior"); the id capitalised for unknown ids.
static func get_display_name(class_id: String) -> String:
	return String(get_class_def(class_id).get("name", class_id.capitalize()))


## {"strength": int, "dexterity": int, "intelligence": int} starting attributes (zeros if unknown).
static func get_attributes(class_id: String) -> Dictionary:
	var a: Dictionary = get_class_def(class_id).get("attributes", {})
	var out := {}
	for k in ATTRIBUTES:
		out[k] = int(a.get(k, 0))
	return out


## The class attributes as flat mods, for Player.get_base_mods().
static func get_attribute_mods(class_id: String) -> Array:
	var mods: Array = []
	var a := get_attributes(class_id)
	for k in ATTRIBUTES:
		if int(a[k]) != 0:
			mods.append(StatBlock.mod(k, "flat", float(a[k])))
	return mods


## The class's main attribute (highest starting value): "strength" for warrior, ...
static func get_main_attribute(class_id: String) -> String:
	var a := get_attributes(class_id)
	var best := "strength"
	for k in ATTRIBUTES:
		if int(a[k]) > int(a[best]):
			best = k
	return best


## Starting skill bar (always SKILL_BAR_SIZE = 6 entries, "" = empty).
static func get_start_skill_bar(class_id: String) -> Array[String]:
	var out: Array[String] = []
	for s in get_class_def(class_id).get("skill_bar", []):
		out.append(String(s))
	while out.size() < 6:
		out.append("")
	out.resize(6)
	return out


static func get_color(class_id: String) -> Color:
	return get_class_def(class_id).get("color", Color.WHITE)

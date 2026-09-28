extends RefCounted
## Gear looks of the player model (docs/ARCHITECTURE.md §14): which gear piece of the model shows
## for an equipped armour item and which base parts it hides. The pieces are listed in
## data/player_gear.json (written by tools/blender/player/build_player.py):
##   {"pieces": {"Helm_str_2": {"slot": "helm", "family": "str", "tier": 2, "hides": ["HairTop"]}, ...}}
## Every look's model (char_player_<look>.glb) has every piece as a mesh part of that name.
## family = the base's first attribute (str / str_dex / str_int -> str, dex / dex_int -> dex,
## int -> int); tier = 1 for base tiers 1-2, 2 for 3-4, 3 for 5-6, uniques one tier higher (max 3).
## Internal helper of PlayerVisuals: `const PlayerGear := preload("res://scripts/entities/player/player_gear.gd")`.

const DATA_PATH := "res://data/player_gear.json"
## Equipment slot -> gear piece slot.
const SLOT_PIECES := {"helmet": "helm", "body": "chest", "gloves": "gloves", "boots": "boots"}
const FAMILIES: Array[String] = ["str", "dex", "int"]
const MAX_TIER := 3

static var _pieces: Dictionary = {}
static var _loaded := false


## Every gear piece: part name -> {"slot", "family", "tier", "hides"}.
static func pieces() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f == null:
			push_warning("PlayerGear: %s missing" % DATA_PATH)
			return _pieces
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary and d.get("pieces") is Dictionary:
			_pieces = d["pieces"]
		else:
			push_warning("PlayerGear: %s unreadable" % DATA_PATH)
	return _pieces


## The gear family of an armour item: "str", "dex" or "int" ("" for other items).
static func family_of(item: Item) -> String:
	if item == null:
		return ""
	var cat := String(item.get_base().get("category", ""))
	for slot in SLOT_PIECES:
		if cat.begins_with(String(slot) + "_"):
			var fam := cat.substr(String(slot).length() + 1).get_slice("_", 0)
			return fam if FAMILIES.has(fam) else ""
	return ""


## The gear look tier (1..MAX_TIER) of an item: from its base tier, uniques one higher.
static func tier_of(item: Item) -> int:
	if item == null:
		return 1
	var base_tier := int(item.get_base().get("tier", 1))
	var t := clampi(ceili(base_tier / 2.0), 1, MAX_TIER)
	if item.rarity == Item.Rarity.UNIQUE:
		t += 1
	return mini(t, MAX_TIER)


## Part name of a piece: "Helm_str_2".
static func piece_name(piece_slot: String, family: String, tier: int) -> String:
	return "%s_%s_%d" % [piece_slot.capitalize(), family, tier]


## The piece shown for `item` worn in equipment slot `slot` ("" = none: no item, not armour, or
## no such piece). Falls back to lower tiers of the family when a tier is missing.
static func piece_for(slot: String, item: Item) -> String:
	if item == null or not SLOT_PIECES.has(slot):
		return ""
	var fam := family_of(item)
	if fam == "":
		return ""
	var all := pieces()
	for t in range(tier_of(item), 0, -1):
		var n := piece_name(String(SLOT_PIECES[slot]), fam, t)
		if all.has(n):
			return n
	return ""


## The base parts a piece hides (HairTop, Outfit_Top, ...).
static func hides_of(piece: String) -> Array:
	var p: Variant = pieces().get(piece)
	return (p as Dictionary).get("hides", []) if p is Dictionary else []


## True for gear piece part names (hidden unless worn).
static func is_piece(part: String) -> bool:
	return pieces().has(part)

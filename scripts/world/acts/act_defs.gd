class_name ActDefs
extends RefCounted
## The three acts (Act I forest, Act II desert, Act III gothic town): names, regions, monster levels,
## colours, the act's layout and the generator script that fills it. Pure data + small helpers.
## OWNER: acts framework.
##
## Every act is ONE seamless world (WorldActComposite) you walk around in:
##   "hub"        — the act's town: merchant, stash, a waystone (opens the Act Explorer). Monsters
##                  stay out; potions refill and the vendor restocks when you walk in.
##   the regions  — from the act's layout (data/layouts/act_<act>.json, built by
##                  tools/layouts/build_layouts.py): the big outskirts next to the town
##                  ("outskirts") and further zones joined to it by paths, each a little higher in
##                  level ("level" offsets in the layout). One of them holds the dungeon entrance
##                  and its guardian ("zone_boss").
## Crossing into a region shows its name (Events.zone_entered). Only the act's dungeon (its door
## sits in the "dungeon.region") and travel to another act use a screen transition. The act boss
## waits at the bottom of the dungeon; killing it opens portals back out and on to the next act.
## Area info (FlowAreas.act_info): {"id": "act", "act", "zone" (the region the player is in),
## "level", "depth", "seed", "theme" (= act id), "name" (the region's name), "monsters": bool,
## "daylight": bool}; the act dungeon's: FlowAreas.act_dungeon_info().

const ACT_ORDER: Array[String] = ["forest", "desert", "gothic"]
## Old two-zone names still accepted everywhere: "wilds" = the act's outskirts.
const ZONES: Array[String] = ["hub", "wilds"]
## Level offset of the act dungeon over the act's base (outskirts) level.
const DUNGEON_LEVEL_OFFSET := 4

const ACTS := {
	"forest": {
		"number": 1,
		"title": "The Whispering Pines",
		"tagline": "Moss, granite and old pines — and the village by the lake",
		"accent": Color(0.58, 0.86, 0.46),
		"level": 5,
		"daylight": true,
		"generator": "res://scripts/world/acts/act_forest.gd",
		"layout": "res://data/layouts/act_forest.json",
		"boss": "boss_barrow_king",
		"zone_boss": "boss_barrow_wight",
		"dungeon": {"name": "The Old Barrow", "theme": "barrow", "region": "downs"},
		"town": {"name": "Birkavik", "subtitle": "A longhouse village on the lake shore"},
	},
	"desert": {
		"number": 2,
		"title": "The Gilded Sands",
		"tagline": "Sun-baked walls, the great river and the temple of the jackal god",
		"accent": Color(1.0, 0.78, 0.38),
		"level": 12,
		"daylight": true,
		"generator": "res://scripts/world/acts/act_desert.gd",
		"layout": "res://data/layouts/act_desert.json",
		"boss": "boss_pharaoh",
		"zone_boss": "boss_tomb_lord",
		"dungeon": {"name": "The Anubis Temple", "theme": "tomb", "region": "courtyard"},
		"town": {"name": "Qadesh", "subtitle": "The walled city of the river kings"},
	},
	"gothic": {
		"number": 3,
		"title": "The Night of the Hunt",
		"tagline": "Spires, gaslight and fog under a pale moon",
		"accent": Color(0.62, 0.78, 0.95),
		"level": 20,
		"daylight": false,
		"generator": "res://scripts/world/acts/act_gothic.gd",
		"layout": "res://data/layouts/act_gothic.json",
		"boss": "boss_crimson_vicar",
		"zone_boss": "boss_undertaker",
		"dungeon": {"name": "The Abbey Undercroft", "theme": "undercroft", "region": "abbey"},
		"town": {"name": "Cathedral Square", "subtitle": "The last lit lamps before the cathedral"},
	},
}

static var _layout_cache: Dictionary = {}


static func has_act(act: String) -> bool:
	return ACTS.has(act)


static func get_act(act: String) -> Dictionary:
	return ACTS.get(act, ACTS[ACT_ORDER[0]])


## The act's layout file, parsed (cached): {"size", "cell_m", "regions": [{"id", "name", "level",
## "letter", "cells", "bbox", "centroid", "deepest", ...}], "links", "exit", "dungeon", "rows"}.
## {} when missing.
static func layout(act: String) -> Dictionary:
	if _layout_cache.has(act):
		return _layout_cache[act]
	var path := String(get_act(act).get("layout", ""))
	var data := {}
	if path != "" and FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			data = json.data
		else:
			push_warning("ActDefs: %s is not valid JSON" % path)
	elif path != "":
		push_warning("ActDefs: layout %s missing" % path)
	_layout_cache[act] = data
	return data


## Every region of an act, the town first: [{"id", "name", "level" (offset), "safe"}].
static func regions(act: String) -> Array:
	var out: Array = [{"id": "hub", "name": String(get_act(act)["town"]["name"]), "level": 0, "safe": true}]
	for r in layout(act).get("regions", []):
		out.append({"id": String(r["id"]), "name": String(r.get("name", r["id"])), "level": int(r.get("level", 0)), "safe": false})
	return out


## Region ids of an act, the town first ("hub", "outskirts", ...).
static func region_ids(act: String) -> Array:
	var out: Array = []
	for r in regions(act):
		out.append(r["id"])
	return out


## "wilds" (the old name of the outskirts) -> "outskirts"; other ids unchanged.
static func canonical_zone(act: String, zone: String) -> String:
	if zone == "wilds":
		var ids := region_ids(act)
		return ids[1] if ids.size() > 1 else "hub"
	return zone


static func zone_name(act: String, zone: String) -> String:
	var z := canonical_zone(act, zone)
	for r in regions(act):
		if r["id"] == z:
			return String(r["name"])
	return z.capitalize()


static func zone_subtitle(act: String, zone: String) -> String:
	var z := canonical_zone(act, zone)
	if z == "hub":
		return String(get_act(act)["town"].get("subtitle", ""))
	for r in layout(act).get("regions", []):
		if String(r["id"]) == z:
			return String(r.get("subtitle", ""))
	return ""


## Level offset of a region over the act's base level (0 for the town and unknown ids).
static func zone_level_offset(act: String, zone: String) -> int:
	var z := canonical_zone(act, zone)
	for r in regions(act):
		if r["id"] == z:
			return int(r["level"])
	return 0


## "Act I", "Act II", "Act III".
static func act_label(act: String) -> String:
	var n := int(get_act(act)["number"])
	return "Act %s" % ["I", "II", "III", "IV", "V"][clampi(n - 1, 0, 4)]


## The act's dungeon: {"name", "theme", "region", "boss" (= the act boss), "level_offset"}.
static func dungeon(act: String) -> Dictionary:
	var d: Dictionary = (get_act(act).get("dungeon", {}) as Dictionary).duplicate()
	d["boss"] = String(get_act(act).get("boss", ""))
	d["level_offset"] = DUNGEON_LEVEL_OFFSET
	return d


static func accent(act: String) -> Color:
	return get_act(act)["accent"]


## The act after this one ("" after the last).
static func next_act(act: String) -> String:
	var i := ACT_ORDER.find(act)
	if i < 0 or i + 1 >= ACT_ORDER.size():
		return ""
	return ACT_ORDER[i + 1]


## A pseudo dungeon depth for a monster level (EnemyDB pools / mods are depth based).
static func depth_for_level(level: int) -> int:
	var best := 1
	for d in range(1, Balance.MAX_DEPTH + 1):
		if Balance.area_level_for_depth(d) <= level:
			best = d
	return best


## New generator instance for an act (WorldActGen). Falls back to the base generator (a plain,
## fully working layout) when the act's script is missing or broken.
static func make_generator(act: String) -> WorldActGen:
	var path := String(get_act(act).get("generator", ""))
	if path != "" and ResourceLoader.exists(path):
		var script := load(path) as GDScript
		if script != null and script.can_instantiate():
			var inst: Variant = script.new()
			if inst is WorldActGen:
				return inst
			push_warning("ActDefs: %s is not a WorldActGen" % path)
	return WorldActGen.new()

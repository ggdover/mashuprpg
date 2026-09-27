extends RefCounted
## Area info dictionaries (§15) and title-card texts for the game flow. Pure functions.
## OWNER: flow (wave 2).

const TOWN_NAME := "Emberfall"
## Title-card accent per theme (matches the waypoint / menu theme colours).
const THEME_ACCENTS := {
	"town": Color(0.98, 0.82, 0.5),
	"crypt": Color(0.72, 0.84, 0.66),
	"cave": Color(0.48, 0.78, 0.96),
	"inferno": Color(1.0, 0.55, 0.22),
}


## {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}
static func town_info() -> Dictionary:
	return {"id": "town", "name": TOWN_NAME, "level": 1, "theme": "town"}


## {"id": "dungeon", "depth", "level", "seed", "theme", "name"} for a fresh dungeon. The depth is
## clamped to 1..Balance.MAX_DEPTH; seed < 0 = random.
static func dungeon_info(depth: int, seed_value: int = -1) -> Dictionary:
	var d := clampi(depth, 1, Balance.MAX_DEPTH)
	var th := World.theme_for_depth(d)
	var s := seed_value if seed_value >= 0 else (randi() & 0x7fffffff)
	return {
		"id": "dungeon",
		"depth": d,
		"level": Balance.area_level_for_depth(d),
		"seed": s,
		"theme": th,
		"name": "Depth %d — %s" % [d, World.theme_display_name(th)],
	}


## {"id": "act", "act", "zone", "level", "depth", "seed", "theme", "name", "monsters", "daylight"}
## for an act world (one World: hub + wilds); zone = the region the player arrives in (the World
## keeps "zone" / "name" up to date as the player walks). level <= 0 = the Act Explorer's choice
## (GameState.act_options) or the act's suggested level; seed < 0 = random.
static func act_info(act: String, zone: String, level: int = 0, seed_value: int = -1, monsters: bool = true) -> Dictionary:
	var a := act if ActDefs.has_act(act) else ActDefs.ACT_ORDER[0]
	var z := ActDefs.canonical_zone(a, zone)
	if not z in ActDefs.region_ids(a):
		z = "hub"
	var lvl := level if level > 0 else act_level(a)
	var s := seed_value if seed_value >= 0 else (randi() & 0x7fffffff)
	return {
		"id": "act",
		"act": a,
		"zone": z,
		"arrival": z,
		"level": lvl,
		"depth": ActDefs.depth_for_level(lvl),
		"seed": s,
		"theme": a,
		"name": ActDefs.zone_name(a, z),
		"monsters": monsters,
		"daylight": bool(ActDefs.get_act(a).get("daylight", true)),
	}


## Monster level for an act from the Act Explorer options: "act" (the act's suggested level),
## "character" (the character's level) or "custom" (GameState.act_options.level).
static func act_level(act: String) -> int:
	var opts: Dictionary = GameState.act_options
	match String(opts.get("level_mode", "act")):
		"character":
			return GameState.character.level if GameState.character != null else 1
		"custom":
			return clampi(int(opts.get("level", 1)), 1, 100)
	return int(ActDefs.get_act(act).get("level", 1))


## The act's dungeon: {"id": "dungeon", "act", "depth", "level" (the act's monster level +
## ActDefs.DUNGEON_LEVEL_OFFSET), "seed", "theme" (its palette: "tomb" / "barrow" / "undercroft"),
## "name", "boss" (the act boss waits at its bottom)}.
static func act_dungeon_info(act: String, seed_value: int = -1) -> Dictionary:
	var a := act if ActDefs.has_act(act) else ActDefs.ACT_ORDER[0]
	var dd := ActDefs.dungeon(a)
	var lvl := clampi(act_level(a) + int(dd.get("level_offset", ActDefs.DUNGEON_LEVEL_OFFSET)), 1, 100)
	var s := seed_value if seed_value >= 0 else (randi() & 0x7fffffff)
	return {
		"id": "dungeon",
		"act": a,
		"depth": ActDefs.depth_for_level(lvl),
		"level": lvl,
		"seed": s,
		"theme": String(dd.get("theme", "crypt")),
		"name": String(dd.get("name", "Dungeon")),
		"boss": String(dd.get("boss", "")),
	}


## [title, subtitle, accent colour] for the area title card.
static func title_for(info: Dictionary) -> Array:
	var id := String(info.get("id", ""))
	var th := String(info.get("theme", "town"))
	var accent: Color = THEME_ACCENTS.get(th, THEME_ACCENTS["town"])
	if id == "town":
		return [String(info.get("name", TOWN_NAME)), "A safe haven at the edge of the dark", accent]
	if id == "dungeon" and info.has("act"):
		var a := String(info["act"])
		return [String(info.get("name", "Dungeon")), "%s  ·  Monster Level %d" % [ActDefs.act_label(a), int(info.get("level", 1))], ActDefs.accent(a)]
	if id == "dungeon":
		var d := int(info.get("depth", 1))
		var sub := "%s  ·  Monster Level %d" % [World.theme_display_name(th), int(info.get("level", d))]
		return ["Depth %d" % d, sub, accent]
	if id == "act":
		var act := String(info.get("act", ""))
		var zone := String(info.get("zone", "hub"))
		var sub2 := "%s  ·  %s" % [ActDefs.act_label(act), ActDefs.get_act(act)["title"]]
		if not bool(info.get("safe", zone == "hub")):
			sub2 += "  ·  Monster Level %d" % int(info.get("level", 1))
		return [String(info.get("name", "")), sub2, ActDefs.accent(act)]
	return [String(info.get("name", id.capitalize())), "", accent]

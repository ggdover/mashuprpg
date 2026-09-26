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


## [title, subtitle, accent colour] for the area title card.
static func title_for(info: Dictionary) -> Array:
	var id := String(info.get("id", ""))
	var th := String(info.get("theme", "town"))
	var accent: Color = THEME_ACCENTS.get(th, THEME_ACCENTS["town"])
	if id == "town":
		return [String(info.get("name", TOWN_NAME)), "A safe haven at the edge of the dark", accent]
	if id == "dungeon":
		var d := int(info.get("depth", 1))
		var sub := "%s  ·  Monster Level %d" % [World.theme_display_name(th), int(info.get("level", d))]
		return ["Depth %d" % d, sub, accent]
	return [String(info.get("name", id.capitalize())), "", accent]

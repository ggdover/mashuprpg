extends RefCounted
## Small procedural icons drawn inside passive tree nodes (notables, keystones, and small nodes
## when zoomed in), chosen from the node's main stat: heart (life), shield (armour/block), sword
## (melee/physical/weapons), arrow (projectiles/bows), flame (fire), snowflake (cold), bolt
## (lightning), drop (chaos/poison/mana), star (critical strikes), hexagon (energy shield),
## chevrons (speed), eye (evasion), hexagram (spells/elements), rings (area), coin (rarity/gold),
## hourglass (duration), gem (anything else). Every filled shape is a simple polygon.
## Internal: preload("res://scripts/ui/passive_tree/tree_panel_glyphs.gd").

const STAT_GLYPHS := {
	"max_life": "heart", "life_regen_percent": "heart", "life_leech": "heart", "life_on_kill": "heart",
	"potion_effect": "heart", "pain_attunement": "heart",
	"armour": "shield", "block_chance": "shield", "physical_damage_reduction": "shield", "iron_reflexes": "shield",
	"cannot_evade": "shield",
	"melee_damage": "sword", "physical_damage": "sword", "attack_damage": "sword", "sword_damage": "sword",
	"axe_damage": "sword", "mace_damage": "sword", "dagger_damage": "sword", "staff_damage": "sword",
	"one_handed_damage": "sword", "two_handed_damage": "sword", "bleed_chance": "sword", "no_crit": "sword",
	"projectile_damage": "arrow", "bow_damage": "arrow", "crossbow_damage": "arrow", "additional_projectiles": "arrow",
	"projectile_speed": "arrow", "point_blank": "arrow", "chain": "bolt",
	"fire_damage": "flame", "ignite_chance": "flame", "fire_resistance": "flame",
	"cold_damage": "snow", "freeze_chance": "snow", "cold_resistance": "snow",
	"lightning_damage": "bolt", "shock_chance": "bolt", "lightning_resistance": "bolt",
	"chaos_damage": "drop_chaos", "poison_chance": "drop_chaos", "damage_over_time": "drop_chaos", "chaos_resistance": "drop_chaos",
	"crit_chance": "star", "crit_multiplier": "star",
	"max_mana": "drop_mana", "mana_regen": "drop_mana", "mana_cost": "drop_mana", "blood_magic": "drop_blood",
	"max_energy_shield": "hex", "energy_shield_recharge": "hex", "mind_over_matter": "hex",
	"movement_speed": "speed", "attack_speed": "speed", "cast_speed": "speed", "cooldown_recovery": "speed",
	"evasion": "eye", "evade_chance": "eye",
	"spell_damage": "rune", "elemental_damage": "rune", "elemental_resistance": "rune",
	"area_damage": "rings", "area_of_effect": "rings",
	"item_rarity": "coin", "gold_find": "coin",
	"skill_duration": "hourglass",
}
## Fixed glyph colours (others use the node colour).
const GLYPH_COLORS := {
	"flame": Color(1.0, 0.55, 0.2), "snow": Color(0.6, 0.85, 1.0), "bolt": Color(1.0, 0.92, 0.4),
	"drop_chaos": Color(0.72, 0.45, 0.95), "drop_mana": Color(0.45, 0.6, 1.0), "drop_blood": Color(0.95, 0.2, 0.2),
	"heart": Color(0.95, 0.35, 0.35), "coin": Color(1.0, 0.82, 0.35), "hex": Color(0.65, 0.88, 1.0),
}

static var _cache: Dictionary = {}


## Glyph kind for a node id (cached).
static func glyph_for(id: int) -> String:
	if _cache.has(id):
		return _cache[id]
	var n := TreeDB.get_passive(id)
	var kind := "gem"
	for m in n.get("mods", []):
		var st := String((m as Dictionary).get("stat", ""))
		if STAT_GLYPHS.has(st):
			kind = STAT_GLYPHS[st]
			break
	_cache[id] = kind
	return kind


## Preferred colour of a glyph (fallback: `node_col`).
static func glyph_color(kind: String, node_col: Color) -> Color:
	return GLYPH_COLORS.get(kind, node_col)


## Draw glyph `kind` centred on `c`, `s` = half size in px.
static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	if s < 2.0:
		ci.draw_circle(c, maxf(1.0, s * 0.6), col, true, -1.0, true)
		return
	var w := maxf(1.0, s * 0.2)
	match kind:
		"heart":
			ci.draw_circle(c + Vector2(-0.27, -0.18) * s, 0.32 * s, col, true, -1.0, true)
			ci.draw_circle(c + Vector2(0.27, -0.18) * s, 0.32 * s, col, true, -1.0, true)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.58, -0.06), Vector2(0.58, -0.06), Vector2(0, 0.66)]), col)
		"shield":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.55, -0.62), Vector2(0.55, -0.62), Vector2(0.55, 0.0), Vector2(0, 0.7), Vector2(-0.55, 0.0)]), col)
			ci.draw_line(c + Vector2(0, -0.45) * s, c + Vector2(0, 0.45) * s, Color(0, 0, 0, 0.45), maxf(1.0, s * 0.12))
		"sword":
			var d := Vector2(0.7071, -0.7071)
			var tip := c + d * 0.78 * s
			var base := c - d * 0.35 * s
			ci.draw_line(base, tip - d * 0.2 * s, col, w * 1.3, true)
			var perp := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([tip, tip - d * 0.28 * s + perp * w * 0.75, tip - d * 0.28 * s - perp * w * 0.75]), col)
			ci.draw_line(base + perp * 0.32 * s, base - perp * 0.32 * s, col, w, true)
			ci.draw_line(base, base - d * 0.3 * s, col, w * 0.9, true)
			ci.draw_circle(base - d * 0.38 * s, w * 0.8, col, true, -1.0, true)
		"arrow":
			var d := Vector2(0.7071, -0.7071)
			var tip := c + d * 0.78 * s
			var tail := c - d * 0.72 * s
			ci.draw_line(tail, tip - d * 0.25 * s, col, w, true)
			var perp := Vector2(-d.y, d.x)
			ci.draw_colored_polygon(PackedVector2Array([tip, tip - d * 0.38 * s + perp * 0.24 * s, tip - d * 0.38 * s - perp * 0.24 * s]), col)
			for k in 2:
				var f := tail + d * (0.08 + 0.18 * k) * s
				ci.draw_line(f, f - d * 0.18 * s + perp * 0.22 * s, col, w * 0.7, true)
				ci.draw_line(f, f - d * 0.18 * s - perp * 0.22 * s, col, w * 0.7, true)
		"flame":
			ci.draw_colored_polygon(_teardrop(c + Vector2(0, 0.1) * s, s * 0.95, false), col)
			ci.draw_colored_polygon(_teardrop(c + Vector2(0, 0.32) * s, s * 0.45, false), col.lightened(0.55))
		"snow":
			for k in 3:
				var a := PI * 0.5 + PI * k / 3.0
				var v := Vector2.from_angle(a) * 0.78 * s
				ci.draw_line(c - v, c + v, col, w, true)
				for sgn in [-1.0, 1.0]:
					var p: Vector2 = c + v * 0.55 * sgn
					var b1 := Vector2.from_angle(a + 0.6) * 0.22 * s
					var b2 := Vector2.from_angle(a - 0.6) * 0.22 * s
					ci.draw_line(p, p + b1 * sgn, col, w * 0.7, true)
					ci.draw_line(p, p + b2 * sgn, col, w * 0.7, true)
		"bolt":
			ci.draw_polyline(_pts(c, s, [Vector2(0.28, -0.78), Vector2(-0.22, 0.02), Vector2(0.2, 0.02), Vector2(-0.3, 0.8)]), col, w * 1.2, true)
		"drop_chaos", "drop_mana", "drop_blood":
			ci.draw_colored_polygon(_teardrop(c + Vector2(0, 0.12) * s, s * 0.9, false), col)
			ci.draw_circle(c + Vector2(-0.16, 0.28) * s, 0.12 * s, Color(1, 1, 1, 0.55), true, -1.0, true)
		"star":
			var pts := PackedVector2Array()
			for i in 8:
				var a := -PI * 0.5 + PI * i / 4.0
				pts.append(c + Vector2.from_angle(a) * (0.82 if i % 2 == 0 else 0.26) * s)
			ci.draw_colored_polygon(pts, col)
		"hex":
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * i / 6.0) * 0.72 * s)
			ci.draw_polyline(pts, col, w, true)
			var inner := PackedVector2Array()
			for i in 6:
				inner.append(c + Vector2.from_angle(-PI * 0.5 + TAU * i / 6.0) * 0.36 * s)
			ci.draw_colored_polygon(inner, col)
		"speed":
			for k in 2:
				var o := Vector2(-0.28 + 0.4 * k, 0) * s
				ci.draw_polyline(_pts(c + o, s, [Vector2(-0.2, -0.55), Vector2(0.2, 0.0), Vector2(-0.2, 0.55)]), col, w * 1.1, true)
		"eye":
			ci.draw_arc(c + Vector2(0, 0.5) * s, 0.9 * s, deg_to_rad(-145), deg_to_rad(-35), 16, col, w, true)
			ci.draw_arc(c + Vector2(0, -0.5) * s, 0.9 * s, deg_to_rad(35), deg_to_rad(145), 16, col, w, true)
			ci.draw_circle(c, 0.24 * s, col, true, -1.0, true)
		"rune":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0, -0.8), Vector2(0.69, 0.4), Vector2(-0.69, 0.4)]), col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0, 0.8), Vector2(-0.69, -0.4), Vector2(0.69, -0.4)]), col)
			ci.draw_circle(c, 0.2 * s, Color(0, 0, 0, 0.45), true, -1.0, true)
		"rings":
			ci.draw_arc(c, 0.75 * s, 0, TAU, 24, col, w * 0.8, true)
			ci.draw_arc(c, 0.45 * s, 0, TAU, 20, col, w * 0.8, true)
			ci.draw_circle(c, 0.16 * s, col, true, -1.0, true)
		"coin":
			ci.draw_circle(c, 0.66 * s, col, true, -1.0, true)
			ci.draw_arc(c, 0.42 * s, 0, TAU, 20, Color(0, 0, 0, 0.4), maxf(1.0, s * 0.1), true)
		"hourglass":
			ci.draw_colored_polygon(_pts(c, s, [Vector2(-0.5, -0.7), Vector2(0.5, -0.7), Vector2(0, 0)]), col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0, 0), Vector2(0.5, 0.7), Vector2(-0.5, 0.7)]), col)
		_:
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0, -0.75), Vector2(0.55, 0), Vector2(0, 0.75), Vector2(-0.55, 0)]), col)
			ci.draw_colored_polygon(_pts(c, s, [Vector2(0, -0.75), Vector2(0.55, 0), Vector2(0, 0)]), col.lightened(0.35))


static func _pts(c: Vector2, s: float, unit: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in unit:
		out.append(c + p * s)
	return out


## Teardrop with the tip up, round part centred slightly below `c` (convex).
static func _teardrop(c: Vector2, s: float, _tip_down: bool) -> PackedVector2Array:
	var pts := PackedVector2Array([c + Vector2(0, -0.85) * s])
	var bc := c + Vector2(0, 0.2) * s
	for i in 13:
		var a := deg_to_rad(-30.0 + 240.0 * i / 12.0)
		pts.append(bc + Vector2(cos(a), sin(a)) * 0.5 * s)
	return pts

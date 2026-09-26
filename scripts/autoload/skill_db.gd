extends Node
## Autoload "SkillDB": definitions of every player and monster skill (pure data) plus the
## weapon resolution, tooltip and DPS helpers built on DamageCalc.
## OWNER: skills (wave 2). CONTRACT — keep every public signature.
## Schema: docs/ARCHITECTURE.md §8.1. Skill ids (§8.4 / §8.5) are frozen.
##
## Every dictionary returned by get_skill() / get_resolved() / get_player_skills() is SHARED:
## never mutate it (duplicate(true) first if you need a modified copy).
##
## Fields beyond §8.1 (all optional, read with .get()):
##   "anim_by_weapon": {weapon_type: anim}  animation override per weapon (bow skills on crossbows)
##   "vfx": {"color": Color, "model": String, "model_by_weapon": {weapon_type: model}, "orb": bool,
##           "scale": float, "trail": bool, "swing": "slash"|"slam"|"stab", "shockwave": bool}
##   "sfx": {"use": id (on start), "release": id (at the hit frame), "hit": id (per target hit),
##           "impact": id (explosions / landings / impacts)}
## params extras (on top of the §8.3 table):
##   every delivery: "windup" (s) — red telegraph that fills before the effect (monsters);
##   melee_arc: "radius" (absolute cone radius instead of weapon range + range_add), "knockback",
##              "explode_radius"/"explode_effectiveness" (secondary explosion, infernal blow)
##   projectile: "orb", "wander" + "lifetime" (spark), "land_at_target" + "ground_dot" (venom
##              arrow), "knockback"
##   aoe_target: "count", "scatter" (several impacts around the target)
##   rain: "pattern" ("scatter" | "line"), "delay" (fall time of each impact)
##   buff: "buff_id", "buff_name"
##   summon: "max_alive" (cap of living summons per caster)

const ANIM_HIT_FRAMES := {
	"attack_slash": 0.45,
	"attack_slam": 0.55,
	"attack_stab": 0.5,
	"shoot_bow": 0.6,
	"shoot_crossbow": 0.4,
	"cast": 0.5,
	"cast_area": 0.55,
	"channel": 0.0,
	"roar": 0.5,
	"dodge": 0.3,
}
const DELIVERIES: Array[String] = ["weapon_default", "melee_arc", "projectile", "aoe_target", "rain", "nova",
	"chain", "channel_aoe", "leap", "blink", "buff", "sequence", "ground_dot", "summon", "charge"]

const PLAYER_SKILL_IDS: Array[String] = ["basic_attack", "heavy_strike", "cleave", "ground_slam", "leap_slam",
	"whirlwind", "infernal_blow", "war_cry", "power_shot", "split_arrow", "rain_of_arrows",
	"explosive_bolt", "scatter_shot", "rapid_fire", "ice_shot", "venom_arrow", "fireball", "ice_spear",
	"frost_nova", "chain_lightning", "teleport", "spark", "meteor", "blood_rite"]
const MONSTER_SKILL_IDS: Array[String] = ["m_melee", "m_bite", "m_arrow", "m_firebolt", "m_frostbolt", "m_slam",
	"m_summon", "m_leap", "m_boss_nova", "m_boss_volley", "m_boss_charge", "m_boss_meteors",
	"m_boss_slam", "m_boss_spikes"]

## VFX colours (UIStyle.DAMAGE_COLORS plus a few effect colours).
const C_PHYS := Color(0.95, 0.92, 0.85)
const C_STEEL := Color(0.85, 0.9, 1.0)
const C_FIRE := Color(1.0, 0.5, 0.15)
const C_COLD := Color(0.45, 0.78, 1.0)
const C_LIGHT := Color(1.0, 0.95, 0.35)
const C_CHAOS := Color(0.78, 0.35, 0.95)
const C_POISON := Color(0.45, 0.95, 0.3)
const C_ARCANE := Color(0.7, 0.5, 1.0)
const C_BLOOD := Color(0.95, 0.15, 0.2)
const C_WAR := Color(1.0, 0.72, 0.3)
const C_NATURE := Color(0.6, 0.95, 0.5)

const WEAPON_NAMES := {
	"melee": "Melee Weapon", "sword": "Sword", "axe": "Axe", "mace": "Mace", "dagger": "Dagger",
	"wand": "Wand", "staff": "Staff", "bow": "Bow", "crossbow": "Crossbow", "unarmed": "Unarmed",
}
const TAG_ORDER: Array[String] = ["attack", "spell", "warcry", "melee", "projectile", "area", "channel",
	"movement", "duration", "chain", "nova", "physical", "fire", "cold", "lightning", "chaos"]

var _skills: Dictionary = {}
var _player_sorted: Array = []
## weapon_type -> resolved basic_attack (cached, shared).
var _basic_cache: Dictionary = {}


func _init() -> void:
	_build_player_skills()
	_build_monster_skills()
	var list: Array = []
	for id in _skills:
		if not bool(_skills[id]["monster_only"]):
			list.append(_skills[id])
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["unlock_level"]) != int(b["unlock_level"]):
			return int(a["unlock_level"]) < int(b["unlock_level"])
		return String(a["name"]) < String(b["name"]))
	_player_sorted = list


# ================================================================== public API

func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {})


func has_skill(skill_id: String) -> bool:
	return not get_skill(skill_id).is_empty()


## get_skill(id) resolved for the actor's current weapon:
## resolve_for_weapon(get_skill(id), actor.get_weapon().weapon_type). {} if unknown.
## Every caller outside SkillRunner (character sheet, tooltips, HUD, bot) uses this before calling
## DamageCalc.
func get_resolved(skill_id: String, actor: Actor) -> Dictionary:
	var s := get_skill(skill_id)
	if s.is_empty() or actor == null or not is_instance_valid(actor):
		return s
	return resolve_for_weapon(s, actor.get_weapon().get("weapon_type", "unarmed"))


## Array of skill definition Dictionaries (monster_only == false), sorted by unlock_level then name.
func get_player_skills() -> Array:
	return _player_sorted.duplicate()


## Every skill id (player and monster).
func get_all_ids() -> Array:
	return _skills.keys()


## True if the skill can be used with this weapon type (StatDefs.WEAPON_TYPES entry).
## Spells and warcries accept anything. "melee" in a skill's weapon_types means
## StatDefs.MELEE_WEAPON_TYPES (sword, axe, mace, dagger, staff, unarmed).
func is_weapon_compatible(skill_id: String, weapon_type: String) -> bool:
	var s := get_skill(skill_id)
	if s.is_empty():
		return false
	return _types_accept(s.get("weapon_types", []), weapon_type)


## Concrete version of a skill for a weapon type. Needed for "weapon_default" skills
## (basic_attack): returns a copy whose "tags", "delivery", "params" and "anim" match the weapon
## (melee swing, bow arrow, crossbow bolt, wand bolt). Other skills are returned unchanged.
func resolve_for_weapon(skill: Dictionary, weapon_type: String) -> Dictionary:
	if String(skill.get("delivery", "")) != "weapon_default":
		return skill
	var key := "%s|%s" % [skill.get("id", ""), weapon_type]
	if _basic_cache.has(key):
		return _basic_cache[key]
	var r := skill.duplicate(true)
	var tags: PackedStringArray = PackedStringArray(skill.get("tags", PackedStringArray()))
	var vfx: Dictionary = r.get("vfx", {})
	var sfx: Dictionary = r.get("sfx", {})
	var eff_params: Dictionary = r.get("params", {})
	match weapon_type:
		"bow":
			tags.append("projectile")
			r["delivery"] = "projectile"
			r["params"] = {"speed": 28.0, "range": 20.0, "model": "proj_arrow"}
			r["anim"] = "shoot_bow"
			vfx["color"] = C_PHYS
			vfx["model"] = "proj_arrow"
			sfx["use"] = ""
			sfx["release"] = "bow_shoot"
			sfx["hit"] = "hit_flesh"
		"crossbow":
			tags.append("projectile")
			r["delivery"] = "projectile"
			r["params"] = {"speed": 34.0, "range": 20.0, "pierce": 1, "model": "proj_bolt"}
			r["anim"] = "shoot_crossbow"
			vfx["color"] = C_PHYS
			vfx["model"] = "proj_bolt"
			sfx["use"] = ""
			sfx["release"] = "crossbow_shoot"
			sfx["hit"] = "hit_flesh"
		"wand":
			tags.append("projectile")
			r["delivery"] = "projectile"
			r["params"] = {"speed": 22.0, "range": 18.0, "orb": true, "radius": 0.3}
			r["anim"] = "cast"
			vfx["color"] = C_ARCANE
			vfx["orb"] = true
			vfx["scale"] = 0.8
			sfx["use"] = ""
			sfx["release"] = "spell_cast"
			sfx["hit"] = "hit_flesh"
		_:
			tags.append("melee")
			r["delivery"] = "melee_arc"
			var p := {"angle": 80.0, "range_add": 0.25}
			for k in eff_params:
				p[k] = eff_params[k]
			r["params"] = p
			r["anim"] = "attack_stab" if weapon_type in ["dagger", "unarmed"] else "attack_slash"
			vfx["color"] = C_STEEL
			vfx["swing"] = "stab" if weapon_type in ["dagger", "unarmed"] else "slash"
			sfx["use"] = "swing"
			sfx["release"] = ""
			sfx["hit"] = "hit_flesh"
	r["tags"] = tags
	r["vfx"] = vfx
	r["sfx"] = sfx
	r["hit_frame"] = float(ANIM_HIT_FRAMES.get(r["anim"], 0.5))
	r["resolved_weapon"] = weapon_type
	_basic_cache[key] = r
	return r


## Human-readable weapon requirement ("Requires a Bow or Crossbow"), "" if none.
func get_weapon_requirement_text(skill_id: String) -> String:
	var s := get_skill(skill_id)
	if s.is_empty():
		return ""
	var types: Array = s.get("weapon_types", [])
	if types.is_empty():
		return ""
	var names: PackedStringArray = []
	for t in types:
		names.append(String(WEAPON_NAMES.get(t, String(t).capitalize())))
	var first := names[0]
	var article := "an" if first.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
	return "Requires %s %s" % [article, " or ".join(names)]


## Animation to play for a (resolved) skill with a weapon type (bow skills used with a crossbow
## play "shoot_crossbow").
func get_anim(skill: Dictionary, weapon_type: String) -> String:
	var by: Dictionary = skill.get("anim_by_weapon", {})
	if by.has(weapon_type):
		return String(by[weapon_type])
	return String(skill.get("anim", "cast"))


## Hit frame (0..1 of the use) for a skill played with `anim`.
func get_hit_frame(skill: Dictionary, anim: String) -> float:
	if anim != String(skill.get("anim", "")):
		return float(ANIM_HIT_FRAMES.get(anim, skill.get("hit_frame", 0.5)))
	return float(skill.get("hit_frame", ANIM_HIT_FRAMES.get(anim, 0.5)))


## Useful reach of a skill in metres for the actor (AI / bot: "am I in range?").
func get_skill_range(skill_id: String, actor: Actor = null) -> float:
	var s := get_resolved(skill_id, actor) if actor != null else get_skill(skill_id)
	if s.is_empty():
		return 0.0
	var p: Dictionary = s.get("params", {})
	var weapon: Dictionary = actor.get_weapon() if actor != null and is_instance_valid(actor) else DamageCalc.UNARMED
	var area := DamageCalc.get_area_mult(actor, s)
	match String(s.get("delivery", "")):
		"melee_arc":
			if p.has("radius"):
				return float(p["radius"]) * area
			return (float(weapon.get("range", 2.0)) + float(p.get("range_add", 0.0))) * area
		"projectile", "sequence":
			return float(p.get("range", 20.0))
		"aoe_target", "rain":
			return float(p.get("max_range", 18.0))
		"nova", "channel_aoe":
			return float(p.get("radius", 3.0)) * area
		"chain":
			return float(p.get("range", 14.0))
		"leap", "blink", "charge":
			return float(p.get("max_range", 10.0))
		"buff":
			return float(p.get("radius", 0.0))
		"summon":
			return 30.0
		"weapon_default":
			return float(weapon.get("range", 2.0))
	return 3.0


## Main colour of a skill's effects.
func get_skill_color(skill_id: String) -> Color:
	return get_skill(skill_id).get("vfx", {}).get("color", C_PHYS)


## Single-target damage per second estimate of the skill for the actor (delivery-aware: shared
## hit sets, shotgun, sequences, explosions, ground clouds, channel ticks, cooldowns). Crits and
## stacking poison included, other ailment damage over time excluded. 0 for skills that deal no
## damage.
func estimate_dps(skill_id: String, actor: Actor) -> float:
	var s := get_resolved(skill_id, actor)
	if s.is_empty():
		return 0.0
	var delivery := String(s.get("delivery", ""))
	if delivery in ["buff", "blink", "summon"]:
		return 0.0
	var avg := DamageCalc.get_average_hit(actor, s)
	if avg <= 0.0:
		return 0.0
	var cc := DamageCalc.get_crit_chance(actor, s) / 100.0
	var cm := DamageCalc.get_crit_multiplier(actor) / 100.0
	var per_hit := avg * (1.0 + cc * (cm - 1.0))
	var p: Dictionary = s.get("params", {})
	var per_use := per_hit
	match delivery:
		"projectile", "sequence":
			if float(p.get("explode_radius", 0.0)) > 0.0:
				per_use *= float(p.get("explode_effectiveness", 1.0))
			if bool(p.get("shotgun", false)):
				var extra := mini(DamageCalc.get_projectile_count(actor, s) - 1, 2)
				per_use *= 1.0 + 0.5 * maxf(0.0, float(extra))
			if delivery == "sequence":
				per_use *= maxf(1.0, float(p.get("repeat", 1)))
		"channel_aoe":
			per_use *= float(p.get("effectiveness", 1.0))
	# Guaranteed-ish stacking poison (Venom Arrow): expected poison damage per use.
	var pchance := clampf(DamageCalc.get_ailment_chance(actor, s, "poison") / 100.0, 0.0, 1.0)
	if pchance > 0.0:
		var ranges := DamageCalc.get_damage_range(actor, s)
		var pc := 0.0
		for k in ["physical", "chaos"]:
			if ranges.has(k):
				pc += ((ranges[k] as Vector2).x + (ranges[k] as Vector2).y) * 0.5
		var dotm := 1.0
		if actor != null and is_instance_valid(actor):
			dotm = maxf(0.0, 1.0 + actor.stats.inc("damage_over_time") / 100.0) * actor.stats.more("damage_over_time")
		per_use += pchance * DamageCalc.POISON_DPS * pc * dotm * DamageCalc.POISON_DURATION * DamageCalc.get_duration_mult(actor, s)
	var t := DamageCalc.get_use_time(actor, s)
	var speed := 1.0
	if actor != null and is_instance_valid(actor):
		speed = maxf(0.05, actor.get_action_speed_mult())
	t = maxf(t / speed, DamageCalc.get_cooldown(actor, s))
	var dps := per_use / maxf(0.05, t)
	var gd: Dictionary = p.get("ground_dot", {})
	if not gd.is_empty():
		dps += per_hit * float(gd.get("effectiveness", 0.0))
	return dps


## Tooltip lines (same line format as Item.get_tooltip_lines: {"text", "color", "size"
## ("title"|"normal"|"small")}, separators {"separator": true}, optional "parts"). With an actor,
## includes computed damage, cost, use time and DPS for that actor.
func get_tooltip_lines(skill_id: String, actor: Actor = null) -> Array:
	var base := get_skill(skill_id)
	if base.is_empty():
		return []
	var has_actor := actor != null and is_instance_valid(actor)
	var s := get_resolved(skill_id, actor) if has_actor else base
	var weapon_type := String(actor.get_weapon().get("weapon_type", "unarmed")) if has_actor else ""
	var lines: Array = []
	lines.append(_line(String(s["name"]), UIStyle.COLOR_TITLE, "title"))
	lines.append(_line(format_tags(s.get("tags", [])), UIStyle.COLOR_TEXT_DIM, "small"))
	lines.append(_separator())
	lines.append(_line(String(s.get("description", "")), UIStyle.COLOR_TEXT, "normal"))

	# ---- requirements
	var req: Array = []
	var unlock := int(s.get("unlock_level", 1))
	if unlock > 1 and not bool(s.get("monster_only", false)):
		var lvl_ok := not has_actor or actor.level >= unlock or actor.team != Actor.Team.PLAYER
		req.append(_line("Requires Level %d" % unlock, UIStyle.COLOR_TEXT_DIM if lvl_ok else UIStyle.COLOR_BAD, "small"))
	var wtext := get_weapon_requirement_text(skill_id)
	if wtext != "":
		var w_ok := not has_actor or is_weapon_compatible(skill_id, weapon_type)
		req.append(_line(wtext, UIStyle.COLOR_TEXT_DIM if w_ok else UIStyle.COLOR_BAD, "small"))
	if not req.is_empty():
		lines.append(_separator())
		lines.append_array(req)

	# ---- numbers
	lines.append(_separator())
	var tags: PackedStringArray = PackedStringArray(s.get("tags", PackedStringArray()))
	var p: Dictionary = s.get("params", {})
	var delivery := String(s.get("delivery", ""))
	var pool := "Life" if has_actor and actor.stats.has_flag("blood_magic") else "Mana"
	if delivery == "channel_aoe":
		var per_tick := DamageCalc.scale_cost(actor if has_actor else null, float(p.get("cost_per_tick", 0.0)))
		if per_tick > 0.0:
			lines.append(_line("Cost: %s %s per hit" % [StatDefs.fmt(per_tick), pool], UIStyle.COLOR_TEXT, "normal"))
	else:
		var cost := DamageCalc.get_cost(actor if has_actor else null, s)
		if cost > 0.0:
			lines.append(_line("Cost: %s %s" % [StatDefs.fmt(cost), pool], UIStyle.COLOR_TEXT, "normal"))
	var cd := DamageCalc.get_cooldown(actor if has_actor else null, s)
	if cd > 0.0:
		lines.append(_line("Cooldown: %.1f s" % cd, UIStyle.COLOR_TEXT, "normal"))
	var use_label := "Cast Time"
	if tags.has("attack"):
		use_label = "Attack Time"
	if delivery == "channel_aoe":
		use_label = "Hit Interval"
	if has_actor:
		lines.append(_line("%s: %.2f s" % [use_label, DamageCalc.get_use_time(actor, s)], UIStyle.COLOR_TEXT, "normal"))
	elif tags.has("attack"):
		lines.append(_line("Attack Time: %d%% of weapon" % int(roundf(float(s.get("attack_time_mult", 1.0)) * 100.0)), UIStyle.COLOR_TEXT, "normal"))
	else:
		lines.append(_line("Cast Time: %.2f s" % float(s.get("cast_time", DamageCalc.DEFAULT_CAST_TIME)), UIStyle.COLOR_TEXT, "normal"))

	var deals_damage := not (delivery in ["buff", "blink", "summon"])
	if deals_damage:
		if tags.has("attack") and not bool(s.get("monster_only", false)):
			lines.append(_line("Damage Effectiveness: %d%%" % int(roundf(float(s.get("damage_effectiveness", 1.0)) * 100.0)), UIStyle.COLOR_TEXT, "normal"))
		var ranges: Dictionary
		if has_actor:
			ranges = DamageCalc.get_damage_range(actor, s)
		elif not tags.has("attack"):
			ranges = DamageCalc.get_base_damage_range(null, s)
		else:
			ranges = {}
		for t in StatDefs.DAMAGE_TYPES:
			if ranges.has(t):
				var r: Vector2 = ranges[t]
				lines.append(_line("%s Damage: %d-%d" % [t.capitalize(), int(roundf(r.x)), int(roundf(r.y))], UIStyle.damage_color(t), "normal"))
		if has_actor:
			lines.append(_line("Critical Strike Chance: %.1f%%" % DamageCalc.get_crit_chance(actor, s), UIStyle.COLOR_TEXT, "normal"))
		elif not tags.has("attack"):
			lines.append(_line("Critical Strike Chance: %.1f%%" % float(s.get("crit_chance", DamageCalc.DEFAULT_SPELL_CRIT)), UIStyle.COLOR_TEXT, "normal"))

	# ---- modifiers
	var mods := _mod_lines(s, actor if has_actor else null)
	if not mods.is_empty():
		lines.append(_separator())
		for m in mods:
			lines.append(_line(m, UIStyle.COLOR_MOD, "normal"))

	if has_actor and deals_damage:
		var dps := estimate_dps(skill_id, actor)
		if dps > 0.0:
			lines.append(_separator())
			lines.append(_line("Estimated DPS (single target): %.1f" % dps, UIStyle.COLOR_TEXT_DIM, "small"))
	return lines


## "Attack, Melee, Area" in a stable order.
func format_tags(tags: Variant) -> String:
	var src: PackedStringArray = PackedStringArray(tags)
	var out: PackedStringArray = []
	for t in TAG_ORDER:
		if src.has(t):
			out.append(t.capitalize())
	for t in src:
		if not TAG_ORDER.has(t):
			out.append(String(t).capitalize())
	return ", ".join(out)


# ================================================================== internals

func _types_accept(types: Array, weapon_type: String) -> bool:
	if types.is_empty():
		return true
	for t in types:
		if t == weapon_type:
			return true
		if t == "melee" and StatDefs.MELEE_WEAPON_TYPES.has(weapon_type):
			return true
	return false


func _mod_lines(s: Dictionary, actor: Actor) -> PackedStringArray:
	var out: PackedStringArray = []
	var p: Dictionary = s.get("params", {})
	var delivery := String(s.get("delivery", ""))
	var area := DamageCalc.get_area_mult(actor, s)
	var dur := DamageCalc.get_duration_mult(actor, s)
	var conv: Dictionary = s.get("conversion", {})
	for from_t in conv:
		var to: Dictionary = conv[from_t]
		for to_t in to:
			out.append("%d%% of %s Damage Converted to %s" % [int(roundf(float(to[to_t]) * 100.0)), String(from_t).capitalize(), String(to_t).capitalize()])
	var ail: Dictionary = s.get("ailments", {})
	var ail_names := {"ignite": "Ignite", "freeze": "Freeze", "shock": "Shock", "bleed": "cause Bleeding", "poison": "Poison"}
	for k in ["ignite", "freeze", "shock", "bleed", "poison"]:
		var c := DamageCalc.get_ailment_chance(actor, s, k) if (actor != null or ail.has(k)) else 0.0
		if not ail.has(k) and actor != null:
			continue
		if c > 0.0:
			out.append("%s%% chance to %s" % [StatDefs.fmt(c), ail_names[k]])
	match delivery:
		"melee_arc":
			if p.has("radius"):
				out.append("Radius: %.1f m" % (float(p["radius"]) * area))
			elif float(p.get("range_add", 0.0)) >= 0.5:
				out.append("+%.1f m Reach" % float(p["range_add"]))
			if float(p.get("explode_radius", 0.0)) > 0.0:
				out.append("Explodes on impact for %d%% of the damage (radius %.1f m) against other enemies" % [int(roundf(float(p.get("explode_effectiveness", 1.0)) * 100.0)), float(p["explode_radius"]) * area])
			if float(p.get("knockback", 0.0)) > 0.0:
				out.append("Knocks enemies back")
		"projectile", "sequence":
			var n := DamageCalc.get_projectile_count(actor, s)
			if n > 1:
				out.append("Fires %d Projectiles" % n)
			if delivery == "sequence":
				out.append("Fires %d times in quick succession" % int(p.get("repeat", 1)))
			if float(p.get("explode_radius", 0.0)) > 0.0:
				out.append("Explodes on impact (radius %.1f m)" % (float(p["explode_radius"]) * area))
			else:
				var pierce := DamageCalc.get_pierce(actor, s)
				if pierce >= 50:
					out.append("Pierces all Targets")
				elif pierce > 0:
					out.append("Pierces %d Target%s" % [pierce, "" if pierce == 1 else "s"])
			var ch := DamageCalc.get_chain(actor, s)
			if ch > 0:
				out.append("Chains %d time%s" % [ch, "" if ch == 1 else "s"])
			if bool(p.get("shotgun", false)):
				out.append("Each additional Projectile hitting the same target deals 50% less Damage")
			if bool(p.get("wander", false)):
				out.append("Projectiles wander erratically for %.1f s" % (float(p.get("lifetime", 1.5)) * dur))
			var gd: Dictionary = p.get("ground_dot", {})
			if not gd.is_empty():
				out.append("Leaves a Caustic Cloud (radius %.1f m) for %.1f s dealing %d%% of the hit's Damage per second" % [
					float(gd.get("radius", 2.5)) * area, float(gd.get("duration", 3.0)) * dur, int(roundf(float(gd.get("effectiveness", 0.3)) * 100.0))])
		"aoe_target":
			out.append("Radius: %.1f m" % (float(p.get("radius", 3.0)) * area))
			if int(p.get("count", 1)) > 1:
				out.append("%d impacts" % int(p["count"]))
			out.append("Lands after %.1f s" % float(p.get("delay", 1.0)))
		"rain":
			out.append("Radius: %.1f m" % (float(p.get("radius", 3.0)) * area))
			out.append("%d impacts, each enemy is hit once" % int(p.get("impacts", 6)))
		"nova":
			out.append("Radius: %.1f m" % (float(p.get("radius", 4.0)) * area))
		"chain":
			out.append("Chains %d times (%.0f m between targets)" % [DamageCalc.get_chain(actor, s), float(p.get("chain_range", 7.0))])
		"channel_aoe":
			out.append("Channelled. Radius: %.1f m" % (float(p.get("radius", 2.5)) * area))
			if float(s.get("move_mult", 0.0)) > 0.0:
				out.append("%d%% Movement Speed while channelling" % int(roundf(float(s["move_mult"]) * 100.0)))
		"leap":
			out.append("Leaps up to %.0f m. Landing radius %.1f m" % [float(p.get("max_range", 10.0)), float(p.get("radius", 2.5)) * area])
		"blink":
			out.append("Teleports up to %.0f m" % float(p.get("max_range", 12.0)))
		"buff":
			var bdur := float(p.get("duration", 5.0)) * dur
			out.append("Buff lasts %.1f s" % bdur)
			if float(p.get("radius", 0.0)) > 0.0:
				out.append("Affects you and allies within %.0f m" % float(p["radius"]))
			for line in StatDefs.describe_mods(p.get("mods", [])):
				out.append(line)
		"summon":
			out.append("Summons %d minions" % int(p.get("count", 1)))
		"charge":
			out.append("Charges up to %.0f m" % float(p.get("max_range", 12.0)))
	return out


static func _line(text: String, color: Color, size: String = "normal") -> Dictionary:
	return {"text": text, "color": color, "size": size}


static func _separator() -> Dictionary:
	return {"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true}


## Defaults for every definition (§8.1).
func _add(id: String, d: Dictionary) -> void:
	var s := {
		"id": id,
		"name": id.capitalize(),
		"description": "",
		"tags": PackedStringArray(),
		"weapon_types": [],
		"unlock_level": 1,
		"monster_only": false,
		"mana_cost": 0.0,
		"cooldown": 0.0,
		"cast_time": 0.8,
		"attack_time_mult": 1.0,
		"base_damage": {},
		"damage_effectiveness": 1.0,
		"more_damage": 0.0,
		"monster_damage": {},
		"damage_mult": 1.0,
		"conversion": {},
		"crit_chance": 5.0,
		"ailments": {},
		"delivery": "melee_arc",
		"params": {},
		"anim": "attack_slash",
		"hit_frame": -1.0,
		"move_mult": 0.0,
		"vfx": {"color": C_PHYS},
		"sfx": {},
	}
	for k in d:
		s[k] = d[k]
	s["tags"] = PackedStringArray(s["tags"])
	if float(s["hit_frame"]) < 0.0:
		s["hit_frame"] = float(ANIM_HIT_FRAMES.get(s["anim"], 0.5))
	for k in ["mana_cost", "cooldown", "cast_time", "attack_time_mult", "damage_effectiveness", "more_damage", "damage_mult", "crit_chance", "move_mult"]:
		s[k] = float(s[k])
	s["unlock_level"] = int(s["unlock_level"])
	_skills[id] = s


# ------------------------------------------------------------------ player skills (§8.4)

func _build_player_skills() -> void:
	_add("basic_attack", {
		"name": "Attack",
		"description": "A basic attack with your weapon: a swing with melee weapons, an arrow with a bow, a bolt with a crossbow, an arcane bolt with a wand.",
		"tags": ["attack"],
		"delivery": "weapon_default",
		"params": {},
		"damage_effectiveness": 1.0,
		"attack_time_mult": 1.0,
		"anim": "attack_slash",
		"vfx": {"color": C_STEEL, "swing": "slash"},
		"sfx": {"use": "swing", "hit": "hit_flesh"},
	})
	_add("heavy_strike", {
		"name": "Heavy Strike",
		"description": "A slow, crushing overhead blow against a narrow arc in front of you that knocks enemies back.",
		"tags": ["attack", "melee", "physical"],
		"weapon_types": ["melee"],
		"mana_cost": 4.0,
		"damage_effectiveness": 1.9,
		"attack_time_mult": 1.3,
		"delivery": "melee_arc",
		"params": {"angle": 55.0, "range_add": 0.35, "knockback": 6.0},
		"anim": "attack_slam",
		"vfx": {"color": C_WAR, "swing": "slam", "impact": true},
		"sfx": {"use": "swing", "hit": "hit_flesh"},
	})
	_add("cleave", {
		"name": "Cleave",
		"description": "A wide, sweeping swing that strikes every enemy in a broad arc in front of you.",
		"tags": ["attack", "melee", "area"],
		"weapon_types": ["melee"],
		"mana_cost": 4.0,
		"damage_effectiveness": 1.3,
		"attack_time_mult": 1.0,
		"delivery": "melee_arc",
		"params": {"angle": 160.0, "range_add": 0.8},
		"anim": "attack_slash",
		"vfx": {"color": C_STEEL, "swing": "wide"},
		"sfx": {"use": "swing", "hit": "hit_flesh"},
	})
	_add("ground_slam", {
		"name": "Ground Slam",
		"description": "Slam the ground, sending a shockwave through the earth that damages and knocks back enemies in a long cone.",
		"tags": ["attack", "melee", "area"],
		"weapon_types": ["melee"],
		"unlock_level": 4,
		"mana_cost": 7.0,
		"damage_effectiveness": 1.5,
		"attack_time_mult": 1.15,
		"delivery": "melee_arc",
		"params": {"angle": 50.0, "range_add": 4.0, "knockback": 4.0, "shockwave": true},
		"anim": "attack_slam",
		"vfx": {"color": C_WAR, "swing": "slam", "shockwave": true},
		"sfx": {"use": "swing", "impact": "leap_land", "hit": "hit_flesh"},
	})
	_add("leap_slam", {
		"name": "Leap Slam",
		"description": "Leap through the air to the target location and slam down, damaging and knocking back enemies where you land.",
		"tags": ["attack", "melee", "area", "movement"],
		"weapon_types": ["melee"],
		"unlock_level": 6,
		"mana_cost": 10.0,
		"damage_effectiveness": 1.75,
		"attack_time_mult": 1.35,
		"delivery": "leap",
		"params": {"max_range": 10.0, "radius": 2.5, "duration": 0.5, "knockback": 6.0},
		"anim": "attack_slam",
		"hit_frame": 0.08,
		"vfx": {"color": C_WAR},
		"sfx": {"use": "swing", "impact": "leap_land", "hit": "hit_flesh"},
	})
	_add("whirlwind", {
		"name": "Whirlwind",
		"description": "Spin with your weapon while moving, repeatedly hitting every enemy around you. Channelled: hold the key.",
		"tags": ["attack", "melee", "area", "channel"],
		"weapon_types": ["melee"],
		"unlock_level": 8,
		"mana_cost": 0.0,
		"damage_effectiveness": 0.6,
		"attack_time_mult": 0.45,
		"delivery": "channel_aoe",
		"params": {"radius": 2.6, "cost_per_tick": 2.5, "effectiveness": 1.0},
		"anim": "channel",
		"hit_frame": 0.5,
		"move_mult": 0.6,
		"vfx": {"color": C_STEEL},
		"sfx": {"use": "whirlwind", "hit": "hit_flesh"},
	})
	_add("infernal_blow", {
		"name": "Infernal Blow",
		"description": "A blazing strike that converts half its damage to fire and bursts into flames at the point of impact, burning nearby enemies.",
		"tags": ["attack", "melee", "area", "fire"],
		"weapon_types": ["melee"],
		"unlock_level": 10,
		"mana_cost": 7.0,
		"damage_effectiveness": 1.45,
		"attack_time_mult": 1.0,
		"conversion": {"physical": {"fire": 0.5}},
		"ailments": {"ignite": 20.0},
		"delivery": "melee_arc",
		"params": {"angle": 70.0, "range_add": 0.4, "explode_radius": 2.5, "explode_effectiveness": 0.6},
		"anim": "attack_slash",
		"vfx": {"color": C_FIRE, "swing": "slash"},
		"sfx": {"use": "swing", "impact": "explosion", "hit": "hit_flesh"},
	})
	_add("war_cry", {
		"name": "War Cry",
		"description": "A mighty shout that empowers you and nearby allies: more damage and faster attacks for a short time.",
		"tags": ["warcry", "area", "duration"],
		"unlock_level": 3,
		"mana_cost": 8.0,
		"cooldown": 10.0,
		"cast_time": 0.6,
		"delivery": "buff",
		"params": {"duration": 6.0, "radius": 8.0, "buff_id": "war_cry", "buff_name": "War Cry",
			"mods": [StatBlock.mod("damage", "inc", 30.0), StatBlock.mod("attack_speed", "inc", 10.0)]},
		"anim": "cast_area",
		"vfx": {"color": C_WAR},
		"sfx": {"use": "warcry"},
	})
	_add("power_shot", {
		"name": "Power Shot",
		"description": "A heavy, fully drawn arrow that pierces through every enemy in its path.",
		"tags": ["attack", "projectile"],
		"weapon_types": ["bow"],
		"mana_cost": 5.0,
		"damage_effectiveness": 1.65,
		"attack_time_mult": 1.05,
		"delivery": "projectile",
		"params": {"speed": 34.0, "pierce": 99, "range": 24.0, "model": "proj_arrow", "knockback": 2.0},
		"anim": "shoot_bow",
		"vfx": {"color": C_WAR, "model": "proj_arrow", "trail": true, "scale": 1.25},
		"sfx": {"release": "bow_shoot", "hit": "hit_flesh"},
	})
	_add("split_arrow", {
		"name": "Split Arrow",
		"description": "Fire a fan of arrows at once. Each enemy can be hit by only one of them.",
		"tags": ["attack", "projectile"],
		"weapon_types": ["bow"],
		"mana_cost": 5.0,
		"damage_effectiveness": 1.3,
		"attack_time_mult": 1.0,
		"delivery": "projectile",
		"params": {"speed": 28.0, "count": 5, "spread": 45.0, "range": 20.0, "model": "proj_arrow"},
		"anim": "shoot_bow",
		"vfx": {"color": C_NATURE, "model": "proj_arrow", "trail": true},
		"sfx": {"release": "bow_shoot", "hit": "hit_flesh"},
	})
	_add("rain_of_arrows", {
		"name": "Rain of Arrows",
		"description": "Fire a volley of arrows into the sky that rains down on the target area, hitting every enemy there once.",
		"tags": ["attack", "projectile", "area"],
		"weapon_types": ["bow"],
		"unlock_level": 8,
		"mana_cost": 10.0,
		"damage_effectiveness": 1.45,
		"attack_time_mult": 1.1,
		"delivery": "rain",
		"params": {"radius": 3.5, "impacts": 9, "impact_radius": 1.4, "duration": 0.45, "delay": 0.4, "max_range": 18.0, "pattern": "scatter"},
		"anim": "shoot_bow",
		"vfx": {"color": C_NATURE, "model": "proj_arrow"},
		"sfx": {"release": "bow_shoot", "hit": "hit_flesh"},
	})
	_add("explosive_bolt", {
		"name": "Explosive Bolt",
		"description": "Fire a bolt with an explosive charge that bursts on impact, damaging all enemies around it.",
		"tags": ["attack", "projectile", "area", "fire"],
		"weapon_types": ["crossbow"],
		"mana_cost": 6.0,
		"damage_effectiveness": 1.45,
		"attack_time_mult": 1.0,
		"conversion": {"physical": {"fire": 0.4}},
		"ailments": {"ignite": 20.0},
		"delivery": "projectile",
		"params": {"speed": 30.0, "range": 20.0, "explode_radius": 2.5, "explode_effectiveness": 1.0, "model": "proj_bolt"},
		"anim": "shoot_crossbow",
		"vfx": {"color": C_FIRE, "model": "proj_bolt", "trail": true},
		"sfx": {"release": "crossbow_shoot", "impact": "explosion"},
	})
	_add("scatter_shot", {
		"name": "Scatter Shot",
		"description": "Blast a spray of bolts at short range. Point blank, several bolts hit the same enemy (each additional one for 50% less).",
		"tags": ["attack", "projectile"],
		"weapon_types": ["crossbow"],
		"unlock_level": 4,
		"mana_cost": 7.0,
		"damage_effectiveness": 0.65,
		"attack_time_mult": 1.0,
		"delivery": "projectile",
		"params": {"speed": 32.0, "count": 7, "spread": 40.0, "range": 11.0, "shotgun": true, "model": "proj_bolt"},
		"anim": "shoot_crossbow",
		"vfx": {"color": C_WAR, "model": "proj_bolt", "trail": true, "scale": 0.8},
		"sfx": {"release": "crossbow_shoot", "hit": "hit_flesh"},
	})
	_add("rapid_fire", {
		"name": "Rapid Fire",
		"description": "Loose a quick burst of five bolts at the target.",
		"tags": ["attack", "projectile"],
		"weapon_types": ["crossbow"],
		"unlock_level": 8,
		"mana_cost": 8.0,
		"damage_effectiveness": 0.5,
		"attack_time_mult": 1.5,
		"delivery": "sequence",
		"params": {"repeat": 5, "interval": 0.24, "speed": 36.0, "range": 20.0, "model": "proj_bolt", "jitter": 3.0},
		"anim": "shoot_crossbow",
		"hit_frame": 0.12,
		"vfx": {"color": C_PHYS, "model": "proj_bolt", "trail": true},
		"sfx": {"release": "crossbow_shoot", "hit": "hit_flesh"},
	})
	_add("ice_shot", {
		"name": "Ice Shot",
		"description": "An arrow or bolt of ice: all its damage becomes cold, it pierces two enemies and can freeze them.",
		"tags": ["attack", "projectile", "cold"],
		"weapon_types": ["bow", "crossbow"],
		"unlock_level": 6,
		"mana_cost": 6.0,
		"damage_effectiveness": 1.4,
		"attack_time_mult": 1.0,
		"conversion": {"physical": {"cold": 1.0}},
		"ailments": {"freeze": 10.0},
		"delivery": "projectile",
		"params": {"speed": 32.0, "pierce": 2, "range": 22.0, "model": "proj_arrow"},
		"anim": "shoot_bow",
		"anim_by_weapon": {"crossbow": "shoot_crossbow"},
		"vfx": {"color": C_COLD, "model": "proj_arrow", "model_by_weapon": {"crossbow": "proj_bolt"}, "trail": true, "glow": true},
		"sfx": {"release": "bow_shoot", "hit": "ice_shatter"},
	})
	_add("venom_arrow", {
		"name": "Venom Arrow",
		"description": "Fire a poisoned arrow at the target location. It always poisons, and leaves a caustic cloud that damages enemies standing in it.",
		"tags": ["attack", "projectile", "area", "chaos", "duration"],
		"weapon_types": ["bow", "crossbow"],
		"unlock_level": 12,
		"mana_cost": 8.0,
		"damage_effectiveness": 0.95,
		"attack_time_mult": 1.0,
		"conversion": {"physical": {"chaos": 0.3}},
		"ailments": {"poison": 100.0},
		"delivery": "projectile",
		"params": {"speed": 26.0, "range": 18.0, "model": "proj_arrow", "land_at_target": true,
			"ground_dot": {"radius": 2.5, "duration": 3.0, "tick": 0.25, "effectiveness": 0.4}},
		"anim": "shoot_bow",
		"anim_by_weapon": {"crossbow": "shoot_crossbow"},
		"vfx": {"color": C_POISON, "model": "proj_arrow", "model_by_weapon": {"crossbow": "proj_bolt"}, "trail": true, "glow": true},
		"sfx": {"release": "bow_shoot", "hit": "hit_flesh"},
	})
	_add("fireball", {
		"name": "Fireball",
		"description": "Hurl a ball of fire that explodes on impact, burning all enemies in the blast.",
		"tags": ["spell", "projectile", "area", "fire"],
		"mana_cost": 5.0,
		"cast_time": 0.75,
		"base_damage": {"fire": [13, 20]},
		"crit_chance": 6.0,
		"ailments": {"ignite": 25.0},
		"delivery": "projectile",
		"params": {"speed": 18.0, "range": 20.0, "explode_radius": 2.2, "explode_effectiveness": 1.0, "orb": true, "radius": 0.35},
		"anim": "cast",
		"vfx": {"color": C_FIRE, "orb": true, "scale": 1.0, "light": true},
		"sfx": {"use": "fireball_cast", "impact": "explosion"},
	})
	_add("ice_spear", {
		"name": "Ice Spear",
		"description": "Launch a fast shard of ice that pierces through several enemies.",
		"tags": ["spell", "projectile", "cold"],
		"unlock_level": 3,
		"mana_cost": 6.0,
		"cast_time": 0.7,
		"base_damage": {"cold": [14, 22]},
		"crit_chance": 8.0,
		"ailments": {"freeze": 5.0},
		"delivery": "projectile",
		"params": {"speed": 32.0, "pierce": 3, "range": 22.0, "model": "proj_ice_spear"},
		"anim": "cast",
		"vfx": {"color": C_COLD, "model": "proj_ice_spear", "trail": true, "glow": true},
		"sfx": {"use": "spell_cast", "hit": "ice_shatter"},
	})
	_add("frost_nova", {
		"name": "Frost Nova",
		"description": "Release a ring of frost around you that damages, chills and can freeze every nearby enemy.",
		"tags": ["spell", "area", "cold", "nova"],
		"unlock_level": 4,
		"mana_cost": 10.0,
		"cooldown": 3.0,
		"cast_time": 0.7,
		"base_damage": {"cold": [19, 29]},
		"ailments": {"freeze": 25.0},
		"delivery": "nova",
		"params": {"radius": 4.5, "expand_time": 0.3},
		"anim": "cast_area",
		"vfx": {"color": C_COLD},
		"sfx": {"use": "spell_cast", "impact": "frost_nova"},
	})
	_add("chain_lightning", {
		"name": "Chain Lightning",
		"description": "A bolt of lightning that strikes the target and then arcs to nearby enemies.",
		"tags": ["spell", "lightning", "chain"],
		"unlock_level": 5,
		"mana_cost": 7.0,
		"cast_time": 0.7,
		"base_damage": {"lightning": [4, 30]},
		"crit_chance": 6.0,
		"ailments": {"shock": 20.0},
		"delivery": "chain",
		"params": {"range": 14.0, "chain": 4, "chain_range": 7.0},
		"anim": "cast",
		"vfx": {"color": C_LIGHT},
		"sfx": {"use": "spell_cast", "impact": "lightning"},
	})
	_add("teleport", {
		"name": "Teleport",
		"description": "Vanish in a flash and reappear at the target location.",
		"tags": ["spell", "movement"],
		"unlock_level": 6,
		"mana_cost": 8.0,
		"cooldown": 3.0,
		"cast_time": 0.35,
		"delivery": "blink",
		"params": {"max_range": 12.0},
		"anim": "cast",
		"hit_frame": 0.45,
		"vfx": {"color": C_ARCANE},
		"sfx": {"use": "teleport"},
	})
	_add("spark", {
		"name": "Spark",
		"description": "Release a spray of crackling sparks that wander erratically, shocking every enemy they touch.",
		"tags": ["spell", "projectile", "lightning"],
		"unlock_level": 10,
		"mana_cost": 7.0,
		"cast_time": 0.65,
		"base_damage": {"lightning": [4, 25]},
		"crit_chance": 6.0,
		"ailments": {"shock": 10.0},
		"delivery": "projectile",
		"params": {"speed": 14.0, "count": 5, "spread": 60.0, "pierce": 99, "wander": true, "lifetime": 1.5, "range": 21.0, "orb": true, "radius": 0.45},
		"anim": "cast",
		"vfx": {"color": C_LIGHT, "orb": true, "scale": 0.55},
		"sfx": {"use": "spell_cast", "hit": "lightning"},
	})
	_add("meteor", {
		"name": "Meteor",
		"description": "Call down a burning meteor on the target location. It crashes down after a moment, devastating everything in a wide area.",
		"tags": ["spell", "area", "fire"],
		"unlock_level": 14,
		"mana_cost": 20.0,
		"cooldown": 4.0,
		"cast_time": 0.8,
		"base_damage": {"fire": [52, 78]},
		"crit_chance": 6.0,
		"ailments": {"ignite": 30.0},
		"delivery": "aoe_target",
		"params": {"radius": 3.5, "max_range": 18.0, "delay": 1.0},
		"anim": "cast_area",
		"vfx": {"color": C_FIRE, "model": "proj_meteor"},
		"sfx": {"use": "spell_cast", "impact": "meteor_impact"},
	})
	_add("blood_rite", {
		"name": "Blood Rite",
		"description": "Sacrifice your safety for power: your spells deal much more damage, but you take increased damage while it lasts.",
		"tags": ["spell", "duration"],
		"unlock_level": 16,
		"mana_cost": 8.0,
		"cooldown": 12.0,
		"cast_time": 0.5,
		"delivery": "buff",
		"params": {"duration": 8.0, "radius": 0.0, "buff_id": "blood_rite", "buff_name": "Blood Rite",
			"mods": [StatBlock.mod("spell_damage", "more", 30.0), StatBlock.mod("damage_taken", "inc", 20.0)]},
		"anim": "cast",
		"vfx": {"color": C_BLOOD},
		"sfx": {"use": "spell_cast"},
	})


# ------------------------------------------------------------------ monster skills (§8.5)

func _monster(id: String, d: Dictionary) -> void:
	d["monster_only"] = true
	d["weapon_types"] = []
	d["mana_cost"] = 0.0
	if not d.has("name"):
		d["name"] = id.trim_prefix("m_").replace("boss_", "").capitalize()
	_add(id, d)


func _build_monster_skills() -> void:
	_monster("m_melee", {
		"name": "Strike",
		"description": "A melee swing.",
		"tags": ["attack", "melee"],
		"monster_damage": {"physical": 1.0},
		"delivery": "melee_arc",
		"params": {"angle": 70.0, "range_add": 0.3},
		"anim": "attack_slash",
		"vfx": {"color": C_PHYS, "swing": "slash"},
		"sfx": {"use": "swing", "hit": "hit_flesh"},
	})
	_monster("m_bite", {
		"name": "Bite",
		"description": "A quick bite.",
		"tags": ["attack", "melee"],
		"monster_damage": {"physical": 1.0},
		"damage_mult": 0.75,
		"attack_time_mult": 0.7,
		"delivery": "melee_arc",
		"params": {"angle": 60.0, "range_add": 0.2},
		"anim": "attack_stab",
		"vfx": {"color": C_BLOOD, "swing": "stab"},
		"sfx": {"use": "swing", "hit": "hit_flesh"},
	})
	_monster("m_arrow", {
		"name": "Arrow",
		"description": "Shoots an arrow.",
		"tags": ["attack", "projectile"],
		"monster_damage": {"physical": 1.0},
		"delivery": "projectile",
		"params": {"speed": 22.0, "range": 22.0, "model": "proj_arrow"},
		"anim": "shoot_bow",
		"vfx": {"color": C_PHYS, "model": "proj_arrow"},
		"sfx": {"release": "bow_shoot", "hit": "hit_flesh"},
	})
	_monster("m_firebolt", {
		"name": "Firebolt",
		"description": "Hurls an exploding bolt of fire.",
		"tags": ["spell", "projectile", "fire"],
		"monster_damage": {"fire": 1.0},
		"cast_time": 1.0,
		"ailments": {"ignite": 10.0},
		"delivery": "projectile",
		"params": {"speed": 15.0, "range": 20.0, "explode_radius": 1.5, "explode_effectiveness": 1.0, "orb": true, "radius": 0.3},
		"anim": "cast",
		"vfx": {"color": C_FIRE, "orb": true, "scale": 0.75, "light": true},
		"sfx": {"use": "fireball_cast", "impact": "explosion"},
	})
	_monster("m_frostbolt", {
		"name": "Frostbolt",
		"description": "Hurls a chilling bolt of frost.",
		"tags": ["spell", "projectile", "cold"],
		"monster_damage": {"cold": 1.0},
		"cast_time": 1.0,
		"delivery": "projectile",
		"params": {"speed": 17.0, "range": 20.0, "orb": true, "radius": 0.3},
		"anim": "cast",
		"vfx": {"color": C_COLD, "orb": true, "scale": 0.7},
		"sfx": {"use": "spell_cast", "hit": "ice_shatter"},
	})
	_monster("m_slam", {
		"name": "Slam",
		"description": "A telegraphed ground slam in a cone.",
		"tags": ["attack", "melee", "area"],
		"monster_damage": {"physical": 1.0},
		"damage_mult": 1.6,
		"cooldown": 3.0,
		"delivery": "melee_arc",
		"params": {"angle": 70.0, "radius": 3.5, "windup": 0.9, "knockback": 5.0, "shockwave": true},
		"anim": "attack_slam",
		"vfx": {"color": C_WAR, "swing": "slam", "shockwave": true},
		"sfx": {"use": "swing", "impact": "leap_land", "hit": "hit_flesh"},
	})
	_monster("m_summon", {
		"name": "Raise Dead",
		"description": "Raises skeletal warriors.",
		"tags": ["spell"],
		"cooldown": 8.0,
		"cast_time": 1.0,
		"delivery": "summon",
		"params": {"enemy_id": "skeleton_warrior", "count": 2, "radius": 2.5, "max_alive": 6},
		"anim": "cast_area",
		"vfx": {"color": C_CHAOS},
		"sfx": {"use": "spell_cast"},
	})
	_monster("m_leap", {
		"name": "Pounce",
		"description": "Leaps onto its prey.",
		"tags": ["attack", "melee", "area", "movement"],
		"monster_damage": {"physical": 1.0},
		"damage_mult": 1.2,
		"cooldown": 4.0,
		"attack_time_mult": 1.3,
		"delivery": "leap",
		"params": {"max_range": 8.0, "radius": 1.8, "duration": 0.45, "windup": 0.3},
		"anim": "attack_slam",
		"hit_frame": 0.1,
		"vfx": {"color": C_BLOOD},
		"sfx": {"impact": "leap_land", "hit": "hit_flesh"},
	})
	_monster("m_boss_nova", {
		"name": "Hellfire Nova",
		"description": "An expanding ring of fire.",
		"tags": ["spell", "area", "fire", "nova"],
		"monster_damage": {"fire": 1.0},
		"damage_mult": 1.8,
		"cooldown": 6.0,
		"cast_time": 1.4,
		"ailments": {"ignite": 20.0},
		"delivery": "nova",
		"params": {"radius": 7.0, "expand_time": 0.7, "windup": 1.0},
		"anim": "cast_area",
		"vfx": {"color": C_FIRE},
		"sfx": {"use": "spell_cast", "impact": "explosion"},
	})
	_monster("m_boss_volley", {
		"name": "Fire Volley",
		"description": "A fan of firebolts.",
		"tags": ["spell", "projectile", "fire"],
		"monster_damage": {"fire": 1.0},
		"damage_mult": 1.1,
		"cooldown": 3.0,
		"cast_time": 1.0,
		"delivery": "projectile",
		"params": {"speed": 15.0, "count": 7, "spread": 70.0, "range": 22.0, "orb": true, "radius": 0.35},
		"anim": "cast",
		"vfx": {"color": C_FIRE, "orb": true, "scale": 0.8},
		"sfx": {"use": "fireball_cast", "hit": "explosion"},
	})
	_monster("m_boss_charge", {
		"name": "Charge",
		"description": "A thundering charge that smashes everything in its path.",
		"tags": ["attack", "melee", "area", "movement"],
		"monster_damage": {"physical": 1.0},
		"damage_mult": 1.8,
		"cooldown": 5.0,
		"attack_time_mult": 1.6,
		"delivery": "charge",
		"params": {"max_range": 14.0, "speed": 18.0, "radius": 2.0, "windup": 0.7, "knockback": 9.0},
		"anim": "attack_slam",
		"hit_frame": 0.45,
		"vfx": {"color": C_WAR},
		"sfx": {"use": "boss_roar", "impact": "leap_land", "hit": "hit_flesh"},
	})
	_monster("m_boss_meteors", {
		"name": "Meteor Storm",
		"description": "Calls down several meteors around its target.",
		"tags": ["spell", "area", "fire"],
		"monster_damage": {"fire": 1.0},
		"damage_mult": 1.6,
		"cooldown": 7.0,
		"cast_time": 1.2,
		"ailments": {"ignite": 20.0},
		"delivery": "aoe_target",
		"params": {"radius": 2.5, "max_range": 20.0, "delay": 1.3, "count": 3, "scatter": 3.5, "telegraph": true},
		"anim": "cast_area",
		"vfx": {"color": C_FIRE, "model": "proj_meteor"},
		"sfx": {"use": "spell_cast", "impact": "meteor_impact"},
	})
	_monster("m_boss_slam", {
		"name": "Grave Slam",
		"description": "A huge telegraphed slam in a wide cone.",
		"tags": ["attack", "melee", "area"],
		"monster_damage": {"physical": 1.0},
		"damage_mult": 2.2,
		"cooldown": 4.0,
		"delivery": "melee_arc",
		"params": {"angle": 90.0, "radius": 6.0, "windup": 1.2, "knockback": 8.0, "shockwave": true},
		"anim": "attack_slam",
		"vfx": {"color": C_WAR, "swing": "slam", "shockwave": true},
		"sfx": {"use": "boss_roar", "impact": "leap_land", "hit": "hit_flesh"},
	})
	_monster("m_boss_spikes", {
		"name": "Bone Spikes",
		"description": "Spikes of bone erupt along a line toward the target.",
		"tags": ["spell", "area", "physical"],
		"monster_damage": {"physical": 1.0},
		"damage_mult": 1.4,
		"cooldown": 6.0,
		"cast_time": 1.0,
		"delivery": "rain",
		"params": {"pattern": "line", "impacts": 6, "impact_radius": 1.2, "radius": 1.0, "windup": 0.8, "duration": 0.5, "max_range": 14.0},
		"anim": "cast_area",
		"vfx": {"color": Color(0.9, 0.86, 0.75)},
		"sfx": {"use": "spell_cast", "impact": "leap_land"},
	})

class_name DamageCalc
extends RefCounted
## All combat math: building hits from skills + stats, mitigation, and the derived skill numbers
## (speed, cost, area, projectile count...). Pure static functions. OWNER: kernel (wave 1).
## Every function expects a RESOLVED skill dict: SkillDB.get_resolved(id, actor) (weapon-dependent
## skills like basic_attack resolved for the actor's current weapon). `attacker` may be null
## (level 1, no stats, unarmed).
##
## Formulas: docs/ARCHITECTURE.md §6. Keep every public signature.

## Weapon dictionary used when nothing is equipped. Schema of every weapon dict (§6.2):
## {"weapon_type": String, "phys_min": float, "phys_max": float,
##  "added": {"fire": Vector2(min, max), ...}, "attack_speed": float (attacks/s),
##  "crit_chance": float (%), "range": float (melee reach in m), "two_handed": bool}
const UNARMED := {
	"weapon_type": "unarmed",
	"phys_min": 2.0,
	"phys_max": 5.0,
	"added": {},
	"attack_speed": 1.3,
	"crit_chance": 5.0,
	"range": 1.8,
	"two_handed": false,
}

## Weapon types that never scale with "<weapon_type>_damage" / one/two-handed stats.
const NON_WEAPON_TYPES: Array[String] = ["", "unarmed", "monster"]
## Hit ailments rolled by build_hit (chill is derived by the target from cold damage taken).
const HIT_AILMENTS: Array[String] = ["ignite", "bleed", "poison", "shock", "freeze"]

const CRIT_CAP := 95.0
const BASE_CRIT_MULTIPLIER := 150.0
const DEFAULT_SPELL_CRIT := 5.0
const DEFAULT_CAST_TIME := 0.8
const MIN_USE_TIME := 0.1
const EVADE_CAP := 75.0
const ARMOUR_CAP := 0.9
## Monster skill damage spread around the average (§6.3).
const MONSTER_SPREAD := Vector2(0.8, 1.2)

## Ailment numbers (§6.3 step 6).
const IGNITE_DPS := 0.5
const BLEED_DPS := 0.5
const POISON_DPS := 0.2
const IGNITE_DURATION := 4.0
const BLEED_DURATION := 4.0
const POISON_DURATION := 2.0
const SHOCK_EFFECT := 0.2
const SHOCK_DURATION := 4.0
const FREEZE_DURATION := 0.8

## Keystones.
const PAIN_ATTUNEMENT_MULT := 1.3
const POINT_BLANK_NEAR := 2.0
const POINT_BLANK_FAR := 12.0
const POINT_BLANK_MAX := 1.5
const POINT_BLANK_MIN := 0.7

static var _use_counter: int = 0
static var _empty_stats: StatBlock = StatBlock.new()


## A fresh id for one skill use (pass it as opts "use_id" to every build_hit of that use, so life
## on hit counts at most 5 targets per use). Never returns 0.
static func next_use_id() -> int:
	_use_counter += 1
	return _use_counter


## Roll one hit of `skill` (a SkillDB definition) used by `attacker`. Rolls damage, crit and
## ailment chances. opts (all optional):
##   "effectiveness": float  multiplies all damage (per-tick fraction, secondary explosions)
##   "more": float           extra percent-more for this hit (e.g. 20 for 20% more)
##   "target": Actor         the target (Point Blank distance, ...)
##   "target_pos": Vector3   target position when there is no target Actor (Point Blank)
##   "origin": Vector3       where the hit comes from (defaults to attacker position)
##   "fire_origin": Vector3  where a projectile was FIRED from (Point Blank; defaults to origin)
##   "use_id": int           DamageCalc.next_use_id() of this skill use (life-on-hit budget)
##   "knockback": float      knockback speed (m/s) stored in the hit
##   "force_crit": bool      force the crit roll outcome (no_crit still wins)
##   "no_ailments": bool     skip the ailment rolls (e.g. secondary hits)
static func build_hit(attacker: Actor, skill: Dictionary, opts: Dictionary = {}) -> HitData:
	var valid := _valid(attacker)
	var st := _stats_of(attacker)
	var tags := _tags_of(skill)
	var weapon := _weapon_for(attacker, tags)
	var h := HitData.new()
	h.source = attacker if valid else null
	h.source_team = attacker.team if valid else int(opts.get("team", 0))
	h.source_level = attacker.level if valid else 1
	h.skill_id = String(skill.get("id", ""))
	h.tags = tags
	h.weapon_type = String(weapon.get("weapon_type", ""))
	h.use_id = int(opts.get("use_id", 0))
	h.knockback = float(opts.get("knockback", 0.0))
	if opts.has("origin"):
		h.origin = opts["origin"]
	elif valid:
		h.origin = _pos_of(attacker)
	h.can_evade = tags.has("attack")
	h.can_block = tags.has("attack") or tags.has("projectile")

	var ranges := _final_ranges(attacker, skill, opts, tags, weapon)
	for t in ranges:
		var r: Vector2 = ranges[t]
		h.damage[t] = randf_range(r.x, r.y) if r.y > r.x else r.x

	# Crit.
	var crit := false
	if not st.has_flag("no_crit"):
		if opts.has("force_crit"):
			crit = bool(opts["force_crit"])
		else:
			var chance := _crit_chance(st, skill, tags, weapon)
			crit = chance > 0.0 and randf() * 100.0 < chance
	if crit:
		h.is_crit = true
		var cm := get_crit_multiplier(attacker) / 100.0
		for t in h.damage:
			h.damage[t] = float(h.damage[t]) * cm

	if not bool(opts.get("no_ailments", false)):
		_roll_ailments(attacker, skill, tags, h)
	return h


## Damage per type as Vector2(min, max) after inc/more, before crit and mitigation.
## Used by tooltips and the character sheet. Pain Attunement counts if the attacker is on low life
## right now; Point Blank is ignored (no target).
static func get_damage_range(attacker: Actor, skill: Dictionary) -> Dictionary:
	var tags := _tags_of(skill)
	return _final_ranges(attacker, skill, {}, tags, _weapon_for(attacker, tags))


## Unscaled base ranges per type after conversion (step 1 + 2 of §6.3), for tooltips.
static func get_base_damage_range(attacker: Actor, skill: Dictionary) -> Dictionary:
	var tags := _tags_of(skill)
	var ranges := _base_ranges(attacker, skill, tags, _weapon_for(attacker, tags))
	_apply_conversion(ranges, skill.get("conversion", {}))
	return _drop_empty(ranges)


## Average hit (midpoint of every range, no crit).
static func get_average_hit(attacker: Actor, skill: Dictionary) -> float:
	var total := 0.0
	var ranges := get_damage_range(attacker, skill)
	for t in ranges:
		var r: Vector2 = ranges[t]
		total += (r.x + r.y) * 0.5
	return total


## Final crit chance in percent (0..95). 0 under the no_crit flag.
static func get_crit_chance(attacker: Actor, skill: Dictionary) -> float:
	var tags := _tags_of(skill)
	return _crit_chance(_stats_of(attacker), skill, tags, _weapon_for(attacker, tags))


## Crit multiplier in percent (150 = x1.5).
static func get_crit_multiplier(attacker: Actor) -> float:
	return maxf(100.0, BASE_CRIT_MULTIPLIER + _stats_of(attacker).flat("crit_multiplier"))


## Attacks per second of the attacker's weapon after attack speed modifiers (no chill).
static func get_attack_speed(attacker: Actor) -> float:
	var st := _stats_of(attacker)
	var w := _weapon_for(attacker, PackedStringArray(["attack"]))
	var base := float(w.get("attack_speed", UNARMED["attack_speed"]))
	return maxf(0.05, base * maxf(0.05, 1.0 + st.inc("attack_speed") / 100.0) * st.more("attack_speed"))


## Cast speed multiplier (1 = base).
static func get_cast_speed_mult(attacker: Actor) -> float:
	var st := _stats_of(attacker)
	return maxf(0.05, maxf(0.05, 1.0 + st.inc("cast_speed") / 100.0) * st.more("cast_speed"))


## Seconds one use of the skill takes (attack: 1/attack speed * attack_time_mult;
## spell: cast_time / cast speed modifiers; other skills: cast_time). Minimum 0.1.
## Chill is NOT included (SkillRunner divides by 1 − chill).
static func get_use_time(attacker: Actor, skill: Dictionary) -> float:
	var tags := _tags_of(skill)
	var t: float
	if tags.has("attack"):
		t = float(skill.get("attack_time_mult", 1.0)) / get_attack_speed(attacker)
	elif tags.has("spell"):
		t = float(skill.get("cast_time", DEFAULT_CAST_TIME)) / get_cast_speed_mult(attacker)
	else:
		t = float(skill.get("cast_time", DEFAULT_CAST_TIME))
	return maxf(MIN_USE_TIME, t)


## Average damage per second estimate (hit damage * crit factor / use time). Character sheet.
## Counts sequence repeats, explosion effectiveness and per-tick effectiveness; the time per use
## is at least the cooldown. Damage over time from ailments is not included.
static func estimate_dps(attacker: Actor, skill: Dictionary) -> float:
	var avg := get_average_hit(attacker, skill)
	if avg <= 0.0:
		return 0.0
	var cc := get_crit_chance(attacker, skill) / 100.0
	var cm := get_crit_multiplier(attacker) / 100.0
	var per_hit := avg * (1.0 + cc * (cm - 1.0))
	var params: Dictionary = skill.get("params", {})
	var per_use := per_hit * maxf(1.0, float(params.get("repeat", 1)))
	if float(params.get("explode_radius", 0.0)) > 0.0:
		per_use *= float(params.get("explode_effectiveness", 1.0))
	if params.has("effectiveness"):
		per_use *= float(params["effectiveness"])
	var t := maxf(get_use_time(attacker, skill), get_cooldown(attacker, skill))
	return per_use / t


## Mana (or life under Blood Magic) cost: skill.mana_cost × Balance.mana_cost_scale(level)
## × (1 + inc(mana_cost)/100) × more(mana_cost). Monster skills cost 0.
static func get_cost(attacker: Actor, skill: Dictionary) -> float:
	if bool(skill.get("monster_only", false)):
		return 0.0
	return scale_cost(attacker, float(skill.get("mana_cost", 0.0)))


## Any base cost scaled like get_cost() (level curve + mana_cost modifiers), e.g. a channel
## skill's params.cost_per_tick.
static func scale_cost(attacker: Actor, base_cost: float) -> float:
	if base_cost <= 0.0:
		return 0.0
	var st := _stats_of(attacker)
	var lvl := attacker.level if _valid(attacker) else 1
	return maxf(0.0, base_cost * Balance.mana_cost_scale(lvl) * maxf(0.0, 1.0 + st.inc("mana_cost") / 100.0) * st.more("mana_cost"))


## Cooldown in seconds after cooldown_recovery.
static func get_cooldown(attacker: Actor, skill: Dictionary) -> float:
	var cd := float(skill.get("cooldown", 0.0))
	if cd <= 0.0:
		return 0.0
	var st := _stats_of(attacker)
	var rate := maxf(0.05, maxf(0.05, 1.0 + st.inc("cooldown_recovery") / 100.0) * st.more("cooldown_recovery"))
	return cd / rate


## Radius multiplier from area_of_effect: sqrt(max(0.1, 1 + inc/100) * more).
static func get_area_mult(attacker: Actor, _skill: Dictionary) -> float:
	var st := _stats_of(attacker)
	return sqrt(maxf(0.1, 1.0 + st.inc("area_of_effect") / 100.0) * st.more("area_of_effect"))


## Total projectiles: skill params.count + additional_projectiles (projectile skills only).
static func get_projectile_count(attacker: Actor, skill: Dictionary) -> int:
	var n := int(skill.get("params", {}).get("count", 1))
	if _tags_of(skill).has("projectile"):
		n += int(_stats_of(attacker).flat("additional_projectiles"))
	return maxi(1, n)


## params.pierce + flat(pierce) (projectile skills).
static func get_pierce(attacker: Actor, skill: Dictionary) -> int:
	var n := int(skill.get("params", {}).get("pierce", 0))
	if _tags_of(skill).has("projectile"):
		n += int(_stats_of(attacker).flat("pierce"))
	return maxi(0, n)


## params.chain + flat(chain) (skills that chain: "chain" tag or a chain param).
static func get_chain(attacker: Actor, skill: Dictionary) -> int:
	var n := int(skill.get("params", {}).get("chain", 0))
	if n > 0 or _tags_of(skill).has("chain"):
		n += int(_stats_of(attacker).flat("chain"))
	return maxi(0, n)


static func get_projectile_speed_mult(attacker: Actor, _skill: Dictionary) -> float:
	var st := _stats_of(attacker)
	return maxf(0.1, 1.0 + st.inc("projectile_speed") / 100.0) * st.more("projectile_speed")


## Skill effect duration multiplier (skill_duration); also scales ailment durations.
static func get_duration_mult(attacker: Actor, _skill: Dictionary) -> float:
	var st := _stats_of(attacker)
	return maxf(0.1, 1.0 + st.inc("skill_duration") / 100.0) * st.more("skill_duration")


## Total chance in percent for a hit ailment kind: skill.ailments[kind] + flat(<kind>_chance).
static func get_ailment_chance(attacker: Actor, skill: Dictionary, kind: String) -> float:
	var a: Dictionary = skill.get("ailments", {})
	return float(a.get(kind, 0.0)) + _stats_of(attacker).flat(kind + "_chance")


## The inc/more stat ids that apply to damage of `type` from a hit with `tags`, e.g.
## ("fire", ["spell","projectile"], "") -> ["damage","fire_damage","elemental_damage",
## "spell_damage","projectile_damage"]. For attacks with a real weapon (not "unarmed"/"monster"/""),
## adds "<weapon_type>_damage" and "two_handed_damage" or "one_handed_damage".
static func get_scaling_stats(type: String, tags: PackedStringArray, weapon_type: String, two_handed: bool = false) -> Array[String]:
	var s: Array[String] = ["damage", type + "_damage"]
	if StatDefs.ELEMENTAL_TYPES.has(type):
		s.append("elemental_damage")
	var is_attack := tags.has("attack")
	if is_attack:
		s.append("attack_damage")
	if tags.has("spell"):
		s.append("spell_damage")
	if tags.has("melee"):
		s.append("melee_damage")
	if tags.has("projectile"):
		s.append("projectile_damage")
	if tags.has("area"):
		s.append("area_damage")
	if is_attack and not NON_WEAPON_TYPES.has(weapon_type):
		s.append(weapon_type + "_damage")
		s.append("two_handed_damage" if two_handed else "one_handed_damage")
	return s


## Mitigation preview WITHOUT side effects (no rolls for evade/block — those are done by
## Actor.take_hit). Returns {"total": float, "by_type": Dictionary}.
## physical × (1 − armour_reduction) × (1 − phys reduction); others × (1 − resist); then
## × damage_taken_mult (damage_taken inc/more and shock).
static func mitigate(target: Actor, hit: HitData) -> Dictionary:
	var by := {}
	var total := 0.0
	if not _valid(target):
		for t in hit.damage:
			by[t] = float(hit.damage[t])
			total += float(hit.damage[t])
		return {"total": total, "by_type": by}
	var taken := damage_taken_mult(target)
	for t in hit.damage:
		var raw := float(hit.damage[t])
		if raw <= 0.0:
			continue
		var d := raw
		if t == "physical":
			d *= 1.0 - armour_reduction(target.armour, raw)
		d *= 1.0 - float(target.resistances.get(t, 0.0)) / 100.0
		d = maxf(0.0, d * taken)
		by[t] = d
		total += d
	return {"total": total, "by_type": by}


## Multiplier on all damage the target takes (hits and DoTs):
## (1 + inc(damage_taken)/100) × more(damage_taken) × (1 + shock effect).
static func damage_taken_mult(target: Actor) -> float:
	if not _valid(target):
		return 1.0
	var st := target.stats
	var m := maxf(0.0, 1.0 + st.inc("damage_taken") / 100.0) * st.more("damage_taken")
	return m * (1.0 + target.get_shock_effect())


## Chance in percent (0..75) that `defender` evades an attack from a level `attacker_level` foe:
## 100 × evasion / (evasion + 200 + 40 × level) + flat(evade_chance). 0 under cannot_evade.
static func evade_chance(defender: Actor, attacker_level: int) -> float:
	if not _valid(defender) or defender.stats.has_flag("cannot_evade"):
		return 0.0
	var ev := maxf(0.0, defender.evasion)
	var c := 100.0 * ev / (ev + 200.0 + 40.0 * maxi(1, attacker_level)) + defender.stats.flat("evade_chance")
	return clampf(c, 0.0, EVADE_CAP)


## Fraction (0..0.9) of a physical hit of `raw` size removed by `armour_value`:
## min(0.9, armour / (armour + 10 × raw)).
static func armour_reduction(armour_value: float, raw: float) -> float:
	if armour_value <= 0.0 or raw <= 0.0:
		return 0.0
	return minf(ARMOUR_CAP, armour_value / (armour_value + 10.0 * raw))


## Point Blank multiplier for a projectile travelling `distance` metres: ×1.5 at ≤ 2 m, lerp to ×0.7
## at ≥ 12 m.
static func point_blank_mult(distance: float) -> float:
	var t := clampf((distance - POINT_BLANK_NEAR) / (POINT_BLANK_FAR - POINT_BLANK_NEAR), 0.0, 1.0)
	return lerpf(POINT_BLANK_MAX, POINT_BLANK_MIN, t)


## Vector2(min, max) from Vector2 / Vector2i / [min, max] / {"min", "max"} / number.
static func to_range(v: Variant) -> Vector2:
	match typeof(v):
		TYPE_VECTOR2:
			return v
		TYPE_VECTOR2I:
			return Vector2(v)
		TYPE_INT, TYPE_FLOAT:
			return Vector2(float(v), float(v))
		TYPE_DICTIONARY:
			var lo := float(v.get("min", 0.0))
			return Vector2(lo, float(v.get("max", lo)))
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			if v.size() >= 2:
				return Vector2(float(v[0]), float(v[1]))
			if v.size() == 1:
				return Vector2(float(v[0]), float(v[0]))
	return Vector2.ZERO


# ------------------------------------------------------------------ internals

static func _valid(a: Actor) -> bool:
	return a != null and is_instance_valid(a)


static func _stats_of(a: Actor) -> StatBlock:
	return a.stats if _valid(a) else _empty_stats


static func _pos_of(a: Node3D) -> Vector3:
	return a.global_position if a.is_inside_tree() else a.position


static func _tags_of(skill: Dictionary) -> PackedStringArray:
	var t: Variant = skill.get("tags", PackedStringArray())
	if t is PackedStringArray:
		return t
	var out := PackedStringArray()
	if t is Array:
		for x in t:
			out.append(String(x))
	return out


## The attacker's weapon for attack skills, {} for everything else.
static func _weapon_for(attacker: Actor, tags: PackedStringArray) -> Dictionary:
	if not tags.has("attack"):
		return {}
	if _valid(attacker):
		var w: Dictionary = attacker.get_weapon()
		if not w.is_empty():
			return w
	return UNARMED


static func _add_range(ranges: Dictionary, t: String, r: Vector2) -> void:
	if not StatDefs.DAMAGE_TYPES.has(t):
		push_warning("DamageCalc: unknown damage type '%s'" % t)
		return
	if r.x <= 0.0 and r.y <= 0.0:
		return
	ranges[t] = ranges.get(t, Vector2.ZERO) + r


static func _add_flat_added(ranges: Dictionary, st: StatBlock, kind: String, eff: float) -> void:
	for t in StatDefs.DAMAGE_TYPES:
		var r := st.flat_range("added_%s_%s" % [t, kind])
		if r.x > 0.0 or r.y > 0.0:
			_add_range(ranges, t, r * eff)


## §6.3 step 1: base ranges per type.
static func _base_ranges(attacker: Actor, skill: Dictionary, tags: PackedStringArray, weapon: Dictionary) -> Dictionary:
	var ranges := {}
	var st := _stats_of(attacker)
	var lvl := attacker.level if _valid(attacker) else 1
	var is_attack := tags.has("attack")
	var md: Dictionary = skill.get("monster_damage", {})
	if not md.is_empty():
		var avg := Balance.monster_damage(lvl) * float(skill.get("damage_mult", 1.0))
		for t in md:
			_add_range(ranges, t, MONSTER_SPREAD * (avg * float(md[t])))
		# Monster mods such as "fiery" add flat damage: it applies to monster skills too.
		if is_attack:
			_add_flat_added(ranges, st, "attack", 1.0)
		elif tags.has("spell"):
			_add_flat_added(ranges, st, "spell", 1.0)
	elif is_attack:
		var eff := float(skill.get("damage_effectiveness", 1.0))
		_add_range(ranges, "physical", Vector2(float(weapon.get("phys_min", 0.0)), float(weapon.get("phys_max", 0.0))))
		var added: Dictionary = weapon.get("added", {})
		for t in added:
			_add_range(ranges, t, to_range(added[t]))
		_add_flat_added(ranges, st, "attack", 1.0)
		for t in ranges:
			ranges[t] = (ranges[t] as Vector2) * eff
	else:
		var bd: Dictionary = skill.get("base_damage", {})
		var scale := Balance.spell_damage_scale(lvl)
		for t in bd:
			_add_range(ranges, t, to_range(bd[t]) * scale)
		if tags.has("spell"):
			_add_flat_added(ranges, st, "spell", float(skill.get("damage_effectiveness", 1.0)))
	return ranges


## §6.3 step 2: skill.conversion = {"physical": {"fire": 0.5}}. Fractions above 1 in total are
## normalised.
static func _apply_conversion(ranges: Dictionary, conv: Dictionary) -> void:
	for from_t in conv:
		if not ranges.has(from_t):
			continue
		var targets: Dictionary = conv[from_t]
		var src: Vector2 = ranges[from_t]
		var total := 0.0
		for to_t in targets:
			if to_t != from_t:
				total += maxf(0.0, float(targets[to_t]))
		if total <= 0.0:
			continue
		var norm := 1.0 if total <= 1.0 else 1.0 / total
		for to_t in targets:
			if to_t == from_t:
				continue
			var f := maxf(0.0, float(targets[to_t])) * norm
			if f > 0.0:
				_add_range(ranges, to_t, src * f)
		ranges[from_t] = src * maxf(0.0, 1.0 - total * norm)


static func _drop_empty(ranges: Dictionary) -> Dictionary:
	var out := {}
	for t in ranges:
		var r: Vector2 = ranges[t]
		if r.y > 0.0001:
			out[t] = r
	return out


## Base + conversion + scaling (steps 1, 2, 4) as ranges.
static func _final_ranges(attacker: Actor, skill: Dictionary, opts: Dictionary, tags: PackedStringArray, weapon: Dictionary) -> Dictionary:
	var ranges := _base_ranges(attacker, skill, tags, weapon)
	_apply_conversion(ranges, skill.get("conversion", {}))
	ranges = _drop_empty(ranges)
	if ranges.is_empty():
		return ranges
	var st := _stats_of(attacker)
	var wtype := String(weapon.get("weapon_type", ""))
	var two_handed := bool(weapon.get("two_handed", false))
	var common := (1.0 + float(skill.get("more_damage", 0.0)) / 100.0)
	common *= 1.0 + float(opts.get("more", 0.0)) / 100.0
	common *= float(opts.get("effectiveness", 1.0))
	common *= _keystone_mult(attacker, st, tags, opts)
	common = maxf(0.0, common)
	for t in ranges:
		var s := get_scaling_stats(t, tags, wtype, two_handed)
		var m := maxf(0.0, 1.0 + st.sum_inc(s) / 100.0) * st.product_more(s) * common
		ranges[t] = (ranges[t] as Vector2) * m
	return ranges


static func _keystone_mult(attacker: Actor, st: StatBlock, tags: PackedStringArray, opts: Dictionary) -> float:
	var m := 1.0
	if not _valid(attacker):
		return m
	if tags.has("spell") and st.has_flag("pain_attunement") and attacker.is_low_life():
		m *= PAIN_ATTUNEMENT_MULT
	if tags.has("projectile") and st.has_flag("point_blank"):
		var has_target := false
		var target_pos := Vector3.ZERO
		var target: Variant = opts.get("target", null)
		if is_instance_valid(target) and target is Node3D:
			target_pos = _pos_of(target)
			has_target = true
		elif opts.has("target_pos"):
			target_pos = opts["target_pos"]
			has_target = true
		if has_target:
			var from: Vector3 = opts.get("fire_origin", opts.get("origin", _pos_of(attacker)))
			var d := Vector2(target_pos.x - from.x, target_pos.z - from.z).length()
			m *= point_blank_mult(d)
	return m


static func _crit_chance(st: StatBlock, skill: Dictionary, tags: PackedStringArray, weapon: Dictionary) -> float:
	if st.has_flag("no_crit"):
		return 0.0
	var base: float
	if tags.has("attack"):
		base = float(weapon.get("crit_chance", UNARMED["crit_chance"]))
	else:
		base = float(skill.get("crit_chance", DEFAULT_SPELL_CRIT))
	var c := (base + st.flat("base_crit_chance")) * maxf(0.0, 1.0 + st.inc("crit_chance") / 100.0) * st.more("crit_chance")
	return clampf(c, 0.0, CRIT_CAP)


## §6.3 step 6: roll the ailment chances against the (post-crit) hit damage.
static func _roll_ailments(attacker: Actor, skill: Dictionary, tags: PackedStringArray, h: HitData) -> void:
	var st := _stats_of(attacker)
	var a: Dictionary = skill.get("ailments", {})
	var dot := maxf(0.0, 1.0 + st.inc("damage_over_time") / 100.0) * st.more("damage_over_time")
	var dur := get_duration_mult(attacker, skill)
	var phys := h.get_amount("physical")
	var fire := h.get_amount("fire")
	var cold := h.get_amount("cold")
	var light := h.get_amount("lightning")
	var chaos := h.get_amount("chaos")
	if fire > 0.0 and _roll(float(a.get("ignite", 0.0)) + st.flat("ignite_chance")):
		h.ailments["ignite"] = {"dps": IGNITE_DPS * fire * dot, "duration": IGNITE_DURATION * dur}
	if tags.has("attack") and phys > 0.0 and _roll(float(a.get("bleed", 0.0)) + st.flat("bleed_chance")):
		h.ailments["bleed"] = {"dps": BLEED_DPS * phys * dot, "duration": BLEED_DURATION * dur}
	if phys + chaos > 0.0 and _roll(float(a.get("poison", 0.0)) + st.flat("poison_chance")):
		h.ailments["poison"] = {"dps": POISON_DPS * (phys + chaos) * dot, "duration": POISON_DURATION * dur}
	if light > 0.0 and _roll(float(a.get("shock", 0.0)) + st.flat("shock_chance")):
		h.ailments["shock"] = {"effect": SHOCK_EFFECT, "duration": SHOCK_DURATION * dur}
	if cold > 0.0 and _roll(float(a.get("freeze", 0.0)) + st.flat("freeze_chance")):
		h.ailments["freeze"] = {"duration": FREEZE_DURATION * dur}


static func _roll(chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 100.0:
		return true
	return randf() * 100.0 < chance

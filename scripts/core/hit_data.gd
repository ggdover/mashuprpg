class_name HitData
extends RefCounted
## One hit's damage package. Built by DamageCalc.build_hit(), consumed by Actor.take_hit().
## Amounts are PRE-mitigation (the target applies armour / resistances / block / evasion) but
## POST-crit. OWNER: kernel (wave 1). See docs/ARCHITECTURE.md §6.

## The attacking Actor. May be freed later, so always check is_instance_valid(source).
var source: Node = null
var source_team: int = 0
## Attacker level at build time (evasion formula), so a freed source still works.
var source_level: int = 1
var skill_id: String = ""
## Skill tags that produced the hit ("attack", "spell", "melee", "projectile", "area", ...).
var tags: PackedStringArray = PackedStringArray()
## damage type -> amount, e.g. {"physical": 12.0, "fire": 30.5}
var damage: Dictionary = {}
var is_crit: bool = false
## Attacks can be evaded (evasion) and attacks + projectiles can be blocked.
var can_evade: bool = false
var can_block: bool = false
## Ailments this hit WILL apply (chances already rolled by DamageCalc). kind -> data, see §6.4:
##   "ignite": {"dps": float, "duration": float}
##   "bleed":  {"dps": float, "duration": float}
##   "poison": {"dps": float, "duration": float}
##   "shock":  {"effect": float (0.15 = +15% damage taken), "duration": float}
##   "freeze": {"duration": float}
## Chill is never listed here: the target derives it from the cold damage it actually takes.
var ailments: Dictionary = {}
## World position the hit came from (block direction, knockback, point blank).
var origin: Vector3 = Vector3.ZERO
## Knockback speed in m/s pushed onto the target (Actor.knockback_velocity); 0 = none.
var knockback: float = 0.0
## Identifies one skill use (DamageCalc.next_use_id(), passed as opts "use_id"): life on hit
## counts at most 5 targets per use. 0 = unknown (then one use = same skill in the same physics
## frame).
var use_id: int = 0
## Weapon type of the attack ("sword", "bow", "unarmed", "monster"; "" for spells).
var weapon_type: String = ""


## Convenience constructor (environment damage, tests, custom skill effects).
## p_source is untyped on purpose: a stored caster that has been freed since may be passed as is
## (it is then treated as "no source"). A valid Actor also sets source_team / source_level.
static func create(p_damage: Dictionary, p_source: Variant = null, p_tags: PackedStringArray = PackedStringArray()) -> HitData:
	var h := HitData.new()
	h.damage = p_damage.duplicate()
	h.tags = p_tags
	h.can_evade = p_tags.has("attack")
	h.can_block = p_tags.has("attack") or p_tags.has("projectile")
	if is_instance_valid(p_source) and p_source is Node:
		h.source = p_source as Node
		if p_source is Actor:
			h.source_team = (p_source as Actor).team
			h.source_level = (p_source as Actor).level
	return h


func total() -> float:
	var t := 0.0
	for k in damage:
		t += float(damage[k])
	return t


func get_amount(type: String) -> float:
	return float(damage.get(type, 0.0))


## The damage type contributing the most (used for floating-number colour).
func dominant_type() -> String:
	var best := "physical"
	var best_v := -1.0
	for k in damage:
		if float(damage[k]) > best_v:
			best_v = float(damage[k])
			best = k
	return best


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Deep copy. Safe when the source has been freed since the hit was built (projectiles, delayed
## impacts): the copy then has source = null but keeps source_team / source_level.
func duplicate_hit() -> HitData:
	var h := HitData.new()
	h.source = source if is_instance_valid(source) else null
	h.source_team = source_team
	h.source_level = source_level
	h.skill_id = skill_id
	h.tags = tags.duplicate()
	h.damage = damage.duplicate()
	h.is_crit = is_crit
	h.can_evade = can_evade
	h.can_block = can_block
	h.ailments = ailments.duplicate(true)
	h.origin = origin
	h.knockback = knockback
	h.use_id = use_id
	h.weapon_type = weapon_type
	return h


## Copy with every damage amount (and ailment dps) multiplied by factor. Safe with a freed source
## (see duplicate_hit()).
func scaled(factor: float) -> HitData:
	var h := duplicate_hit()
	for k in h.damage:
		h.damage[k] = float(h.damage[k]) * factor
	for kind in h.ailments:
		var a: Dictionary = h.ailments[kind]
		if a.has("dps"):
			a["dps"] = float(a["dps"]) * factor
	return h


func _to_string() -> String:
	return "HitData(%s %s%s)" % [skill_id, damage, " CRIT" if is_crit else ""]

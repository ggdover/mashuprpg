class_name SkillEmpower
extends RefCounted
## Parry empowerment: the player's next damaging skill after a successful parry (Player parry
## charge; SkillRunner.try_use consumes it through actor.consume_empower()). What it gets depends
## on the skill:
##   every damaging skill  MORE_DAMAGE percent more damage on all its hits
##   projectiles           EXTRA_PROJECTILES more (projectile / sequence deliveries, bow shots)
##   chains                EXTRA_CHAINS more hops (chain lightning)
##   areas                 AREA_MULT × radius (novas, impacts, rains, clouds, whirlwind, leaps,
##                         explosions, melee swings)
##   attacks               the delivery repeats once, ECHO_DELAY s later (melee swings and
##                         projectile attacks; not channels, rapid fire or movement skills)
## Buffs, teleports and summons never use the charge. OWNER: skills.

const MORE_DAMAGE := 50.0
const EXTRA_PROJECTILES := 2
const EXTRA_CHAINS := 2
const AREA_MULT := 1.4
const ECHO_DELAY := 0.22
## Length of the echo's quick replay of the attack animation.
const ECHO_ANIM_TIME := 0.28
## Gold used by every empowered effect (echo flash, charge aura).
const COLOR := Color(1.0, 0.78, 0.3)

const _NO_EMPOWER: Array[String] = ["buff", "blink", "summon"]
const _AREA_DELIVERIES: Array[String] = ["melee_arc", "weapon_default", "nova", "aoe_target", "rain",
	"channel_aoe", "leap", "charge", "ground_dot"]
const _ECHO_DELIVERIES: Array[String] = ["melee_arc", "weapon_default", "projectile"]


## True if `skill` (resolved) can use a parry charge (it deals damage).
static func can_empower(skill: Dictionary) -> bool:
	if skill.is_empty() or bool(skill.get("monster_only", false)):
		return false
	return not _NO_EMPOWER.has(String(skill.get("delivery", "")))


## Mark `use` as empowered (before SkillDeliveries.prepare, so radii include the bigger area).
static func apply(use: SkillUse) -> void:
	if use == null or use.empowered:
		return
	use.empowered = true
	use.more_damage += MORE_DAMAGE
	var delivery := String(use.skill.get("delivery", ""))
	if delivery == "projectile" or delivery == "sequence":
		use.extra_projectiles += EXTRA_PROJECTILES
	if delivery == "chain":
		use.extra_chains += EXTRA_CHAINS
	if _AREA_DELIVERIES.has(delivery) or use.tags.has("area") or float(use.params.get("explode_radius", 0.0)) > 0.0:
		use.area_mult *= AREA_MULT
	if use.tags.has("attack") and not use.tags.has("movement") and _ECHO_DELIVERIES.has(delivery):
		use.echo = true


## The echo of an empowered attack: the same delivery again from where the caster stands now, in
## the same direction, with a fresh hit set. Called by the runner ECHO_DELAY s after the effect.
static func run_echo(use: SkillUse) -> void:
	var c := use.get_caster()
	if c == null or c.dead or not c.is_inside_tree():
		return
	var e := use.fork()
	e.hit_set = {}
	e.echo = false
	e.origin = VfxUtil.flat(c.global_position)
	e.target_pos = e.origin + e.direction * maxf(1.0, CombatQuery.distance_xz(use.origin, use.target_pos))
	e.committed = true
	SkillDeliveries.prepare(e)
	# A quick second swing / shot (unless the caster is busy with another skill by now).
	var rn := c.skill_runner
	if rn == null or not is_instance_valid(rn) or not rn.is_busy() or rn.is_recovering():
		c.face_towards(e.origin + e.direction)
		c.play_action_animation(SkillDB.get_anim(use.skill, use.weapon_type), ECHO_ANIM_TIME)
	VfxSpawn.hit_spark(e.origin + Vector3(0, 1.1, 0) + e.direction * 0.6, COLOR, true)
	SkillDeliveries.execute(e)

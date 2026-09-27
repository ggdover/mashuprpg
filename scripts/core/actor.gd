class_name Actor
extends CharacterBody3D
## Base class for everything that fights: Player and Enemy. OWNER: kernel (wave 1).
## Semantics and formulas: docs/ARCHITECTURE.md §5 (stats), §6 (combat), §6.4 (ailments).
## Keep every public member, signal and signature (adding more is fine).
##
## Subclass rules:
##   - Override _actor_physics(delta) for movement / AI. NEVER override _physics_process().
##   - Override get_base_mods(), get_all_mods(), get_weapon(), play_action_animation(),
##     _on_death() as needed, and call recalculate_stats() whenever a mod source changes.
##   - Models face +Z. Forward is get_forward() (= global basis.z). face_towards() turns the body.
##   - _ready(): subclasses that override it must call super._ready(). Actor._ready() runs a first
##     recalculate_stats() if none ran yet, so pools are valid (and full) from the start.
##   - Never keep references to other Actors across frames without is_instance_valid().
##   - Timing uses _physics_process counters / node Timers / node tweens, never
##     `await get_tree().create_timer()` (a World kept for a town portal leaves the tree).
##   - Movement: use get_move_speed() (0 while frozen, chill applied) and optionally add
##     knockback_velocity (decays by itself) to the velocity.

signal died(actor: Actor, killer: Node)
signal damaged(amount: float, is_crit: bool, source: Node)
signal ailment_changed(kind: String, active: bool)
signal buffs_changed()
signal stats_recalculated()

enum Team { PLAYER = 0, ENEMY = 1 }

const ATTRIBUTES: Array[String] = ["strength", "dexterity", "intelligence"]
## Energy shield starts recharging this long after the last damage, at ES_RECHARGE_RATE of max ES/s.
const ES_RECHARGE_DELAY := 2.0
const ES_RECHARGE_RATE := 0.25
## Leech + life on hit restore at most this fraction of max life (mana leech: max mana) per rolling
## second.
const LEECH_CAP_FRACTION := 0.2
## Life on hit counts at most this many targets per skill use / tick.
const LIFE_ON_HIT_MAX_TARGETS := 5
## Mind over Matter: this fraction of damage is taken from mana first.
const MOM_FRACTION := 0.3
## DoT (and heal) floating numbers are summed and emitted this often.
const NUMBER_INTERVAL := 0.5
const MAX_POISON_STACKS := 20
## Freeze needs a hit whose mitigated cold damage is >= this fraction of max life.
const FREEZE_THRESHOLD := 0.05
const BOSS_FREEZE_THRESHOLD := 0.10
const FREEZE_IMMUNE_TIME := 2.0
const BOSS_FREEZE_IMMUNE_TIME := 6.0
const BOSS_AILMENT_DURATION_MULT := 0.5
const BOSS_FREEZE_DURATION_MULT := 0.3
const CHILL_DURATION := 2.0
const CHILL_MIN := 0.1
const CHILL_MAX := 0.3
## Upper bound for chill / shock effects from any source.
const AILMENT_EFFECT_CAP := 0.5
## Timers within this of zero count as expired (float accumulation of frame deltas).
const TIME_EPSILON := 0.00001
## Knockback velocity decays at this rate (m/s²).
const KNOCKBACK_DECAY := 25.0
## Explicit heal()/restore_mana() amounts show a floating number when the amount summed over one
## NUMBER_INTERVAL reaches this fraction of the pool (and at least 1).
const HEAL_NUMBER_FRACTION := 0.02

var team: int = Team.ENEMY
var level: int = 1
var display_name: String = ""
## Aggregated modifiers (base + gear + passives + buffs + monster mods + attribute bonuses).
## Read-only for others.
var stats: StatBlock = StatBlock.new()

# ---- pools
var max_life: float = 1.0
var life: float = 1.0
var max_mana: float = 0.0
var mana: float = 0.0
var max_es: float = 0.0
var es: float = 0.0

# ---- derived values, rebuilt by recalculate_stats()
## Attribute totals after all mods (§5.2): {"strength": float, "dexterity": float, "intelligence": float}
var attributes: Dictionary = {"strength": 0.0, "dexterity": 0.0, "intelligence": 0.0}
var armour: float = 0.0
var evasion: float = 0.0
## Percent chance to block attacks/projectiles, capped at 75.
var block_chance: float = 0.0
## Percent mitigation per damage type. "physical" = physical_damage_reduction (armour is applied
## separately per hit). Elemental/chaos are capped at StatDefs.RESIST_CAP.
var resistances: Dictionary = {"physical": 0.0, "fire": 0.0, "cold": 0.0, "lightning": 0.0, "chaos": 0.0}
## Resistances before the cap (character sheet: "75% (92%)").
var resistances_uncapped: Dictionary = {"physical": 0.0, "fire": 0.0, "cold": 0.0, "lightning": 0.0, "chaos": 0.0}
## Per second.
var life_regen: float = 0.0
var mana_regen: float = 0.0
## Energy shield recharged per second once recharging (ES_RECHARGE_DELAY after damage).
var es_recharge_rate: float = 0.0
## Movement speed in m/s before modifiers and ailments.
var base_move_speed: float = 5.0

var dead: bool = false
## Debug god mode (F11): take_hit/take_damage deal 0 to this actor.
var god_mode: bool = false
## While > 0 the actor cannot be frozen (set to 2 s after a freeze ends, 6 s for bosses).
var freeze_immune_time: float = 0.0
## Bosses: halved ailment durations, freeze threshold 10%, never flinch.
var is_boss_actor: bool = false
## While > 0 the actor ignores hits (dodge-roll i-frames). Counts down automatically.
var invulnerable_time: float = 0.0
## id -> {"name": String, "mods": Array, "duration": float, "time_left": float, "icon": String}
## duration <= 0 = permanent (time_left INF) until remove_buff().
var buffs: Dictionary = {}
## kind -> state dictionary (see §6.4). Always includes "time_left" and "duration".
##   ignite/bleed: {"dps", "time_left", "duration", "source"}
##   poison: {"stacks": [{"dps", "time_left", "duration"}], "dps" (total), "time_left" (longest),
##            "duration", "source"}
##   shock/chill: {"effect", "time_left", "duration"}; freeze: {"time_left", "duration"}
## "source" may be a freed Node: check is_instance_valid() before using it.
var ailments: Dictionary = {}
## Created by the subclass (wave 2). May be null.
var skill_runner: SkillRunner = null
## Seconds since damage was last taken (energy shield recharge delay).
var time_since_damaged: float = 999.0
## Push from hits with knockback (m/s, XZ). Decays automatically; subclasses add it to velocity.
var knockback_velocity: Vector3 = Vector3.ZERO

var _stats_initialized := false
## Set once the actor has been ticked or damaged. Before that (spawning, setup, equipping the
## starting gear) a pool whose maximum grows from 0 starts full; afterwards it starts empty and
## fills through mana regen / ES recharge (no refill by re-equipping the only ES item).
var _pools_live := false
var _move_mult := 1.0
## Actor-local clock (advances only while the actor is processed): leech windows.
var _clock := 0.0
## Rolling one-second windows of recovered life / mana from leech + life on hit: [Vector2(t, amount)].
var _life_recovery_log: Array[Vector2] = []
var _mana_recovery_log: Array[Vector2] = []
## Life on hit targets counted per use key.
var _loh_counts: Dictionary = {}
## Accumulated floating numbers: kind -> amount (DoT damage per type, "heal", "mana").
var _number_accum: Dictionary = {}
var _number_timer := 0.0


func _init() -> void:
	# Top-down movement: every contact is a wall, no floor snapping, no gravity.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0


func _ready() -> void:
	add_to_group("actors")
	add_to_group("team_%d" % team)
	if not _stats_initialized:
		recalculate_stats()


func _physics_process(delta: float) -> void:
	_tick_actor(delta)
	_actor_physics(delta)


## Regen, ES recharge, buff and ailment timers (DoT ticks), invulnerability / freeze immunity
## countdowns, knockback decay and the batched floating numbers.
func _tick_actor(delta: float) -> void:
	if dead:
		if not _number_accum.is_empty():
			_flush_numbers()
		return
	_pools_live = true
	_clock += delta
	if invulnerable_time > 0.0:
		invulnerable_time = maxf(0.0, invulnerable_time - delta)
	if freeze_immune_time > 0.0:
		freeze_immune_time = maxf(0.0, freeze_immune_time - delta)
	time_since_damaged += delta
	if life < max_life and life_regen > 0.0:
		life = minf(max_life, life + life_regen * delta)
	if mana < max_mana and mana_regen > 0.0:
		mana = minf(max_mana, mana + mana_regen * delta)
	if es < max_es and es_recharge_rate > 0.0 and time_since_damaged >= ES_RECHARGE_DELAY:
		es = minf(max_es, es + es_recharge_rate * delta)
	if not buffs.is_empty():
		_tick_buffs(delta)
	if not ailments.is_empty():
		_tick_ailments(delta)
	if knockback_velocity != Vector3.ZERO:
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	if not _number_accum.is_empty():
		_number_timer += delta
		if _number_timer >= NUMBER_INTERVAL - TIME_EPSILON:
			_flush_numbers()


# ------------------------------------------------------------------ virtual hooks

## Movement / AI. Override in subclasses.
func _actor_physics(_delta: float) -> void:
	pass


## Base stats for this actor (base life/mana, attributes, base crit multiplier, ...).
func get_base_mods() -> Array:
	return []


## Every mod source except buffs: base + equipment + passives (player) or monster mods (enemy).
## recalculate_stats() adds the buff mods itself.
func get_all_mods() -> Array:
	return get_base_mods()


## Weapon used for attack skills. Schema in §6.2. Default: unarmed.
func get_weapon() -> Dictionary:
	return DamageCalc.UNARMED.duplicate()


## Play an action animation ("attack_slash", "cast", ...) time-scaled to last `duration` seconds.
## duration <= 0 loops it (e.g. "channel") until stop_action_animation(). While the action
## animation is "channel" the subclass spins its model at ~2 turns/s (whirlwind).
func play_action_animation(_anim: String, _duration: float) -> void:
	pass


## Return to idle/run immediately (skill cancel, channel release).
func stop_action_animation() -> void:
	pass


## Called once when the actor dies, after `died` is emitted.
func _on_death(_killer: Node) -> void:
	pass


## Point projectiles aim at / spawn from.
func get_aim_point() -> Vector3:
	return _gpos() + Vector3(0, 1.1, 0)


## Radius used by CombatQuery hit tests (added to AoE radii).
func get_collision_radius() -> float:
	return 0.4


# ------------------------------------------------------------------ stats

## Rebuild `stats` from get_all_mods() + buff mods, then derive attributes (§5.2), pools, defences,
## regen and speed (§5.3). Keeps the current life/mana/ES *ratios* when maxima change; the first
## call fills the pools. A mana/ES pool whose old maximum was 0 starts full only while the actor
## is not live yet (never ticked or damaged); on a live actor it starts at 0 and refills through
## regen / the normal ES recharge (use refill_pools() for an explicit refill).
func recalculate_stats() -> void:
	var r_new := 0.0 if _pools_live else 1.0
	var r_life := clampf(life / max_life, 0.0, 1.0) if max_life > 0.0 else 1.0
	var r_mana := clampf(mana / max_mana, 0.0, 1.0) if max_mana > 0.0 else r_new
	var r_es := clampf(es / max_es, 0.0, 1.0) if max_es > 0.0 else r_new
	stats.clear()
	stats.add_mods(get_all_mods())
	for id in buffs:
		stats.add_mods((buffs[id] as Dictionary).get("mods", []))
	_compute_attributes()
	_add_attribute_bonuses()
	_derive_values()
	if _stats_initialized:
		life = 0.0 if dead else r_life * max_life
		mana = r_mana * max_mana
		es = r_es * max_es
	else:
		life = 0.0 if dead else max_life
		mana = max_mana
		es = max_es
		_stats_initialized = true
	stats_recalculated.emit()


func _compute_attributes() -> void:
	var all_flat := stats.flat("all_attributes")
	var all_inc := stats.inc("all_attributes")
	var all_more := stats.more("all_attributes")
	for a in ATTRIBUTES:
		var v := (stats.flat(a) + all_flat) * (1.0 + (stats.inc(a) + all_inc) / 100.0) * stats.more(a) * all_more
		attributes[a] = maxf(0.0, v)


## §5.2 attribute bonuses, injected as extra mods.
func _add_attribute_bonuses() -> void:
	var s: float = attributes["strength"]
	var d: float = attributes["dexterity"]
	var i: float = attributes["intelligence"]
	_add_bonus("max_life", "flat", floorf(s / 2.0))
	_add_bonus("melee_damage", "inc", floorf(s / 5.0))
	_add_bonus("evasion", "inc", floorf(d / 5.0))
	_add_bonus("attack_speed", "inc", floorf(d / 10.0))
	_add_bonus("projectile_damage", "inc", floorf(d / 10.0))
	_add_bonus("max_mana", "flat", floorf(i / 2.0))
	_add_bonus("max_energy_shield", "inc", floorf(i / 5.0))
	_add_bonus("spell_damage", "inc", floorf(i / 10.0))


func _add_bonus(stat: String, op: String, value: float) -> void:
	if value > 0.0:
		stats.add_mod(StatBlock.mod(stat, op, value))


func _derive_values() -> void:
	max_life = maxf(1.0, stats.compute("max_life"))
	max_mana = 0.0 if stats.has_flag("blood_magic") else maxf(0.0, stats.compute("max_mana"))
	max_es = maxf(0.0, stats.compute("max_energy_shield"))
	life_regen = stats.flat("life_regen") + max_life * stats.flat("life_regen_percent") / 100.0
	if max_mana > 0.0:
		mana_regen = maxf(0.0, (2.0 + 0.03 * max_mana) * (1.0 + stats.inc("mana_regen") / 100.0) * stats.more("mana_regen"))
	else:
		mana_regen = 0.0
	es_recharge_rate = maxf(0.0, ES_RECHARGE_RATE * max_es * (1.0 + stats.inc("energy_shield_recharge") / 100.0))
	var ar := maxf(0.0, stats.compute("armour"))
	var ev := maxf(0.0, stats.compute("evasion"))
	if stats.has_flag("iron_reflexes"):
		armour = ar + ev * stats.more("armour")
		evasion = 0.0
	else:
		armour = ar
		evasion = ev
	block_chance = clampf(stats.flat("block_chance"), 0.0, 75.0)
	var ele := stats.flat("elemental_resistance")
	for t in StatDefs.ELEMENTAL_TYPES:
		var raw := stats.flat(t + "_resistance") + ele
		resistances_uncapped[t] = raw
		resistances[t] = clampf(raw, -100.0, StatDefs.RESIST_CAP)
	var chaos := stats.flat("chaos_resistance")
	resistances_uncapped["chaos"] = chaos
	resistances["chaos"] = clampf(chaos, -100.0, StatDefs.RESIST_CAP)
	var phys := stats.flat("physical_damage_reduction")
	resistances_uncapped["physical"] = phys
	resistances["physical"] = clampf(phys, 0.0, 75.0)
	_move_mult = maxf(0.0, 1.0 + stats.inc("movement_speed") / 100.0) * stats.more("movement_speed")


## Current movement speed in m/s (modifiers, chill, freeze applied).
func get_move_speed() -> float:
	if dead or is_frozen():
		return 0.0
	return base_move_speed * _move_mult * (1.0 - get_chill_effect())


## Movement speed multiplier from modifiers only (1 = base), without ailments.
func get_move_speed_mult() -> float:
	return _move_mult


## Action speed multiplier from chill (1 = normal). SkillRunner divides use times by it.
func get_action_speed_mult() -> float:
	return 1.0 - get_chill_effect()


## Attribute total after all mods (strength / dexterity / intelligence).
func get_attribute(attr: String) -> float:
	if attributes.has(attr):
		return float(attributes[attr])
	return stats.compute(attr)


func get_forward() -> Vector3:
	return global_transform.basis.z


func face_towards(pos: Vector3) -> void:
	var d := pos - _gpos()
	d.y = 0.0
	if d.length_squared() > 0.0001:
		rotation.y = atan2(d.x, d.z)


## {"life": 0..1, "mana": 0..1, "es": 0..1} — carried across area changes by the game flow.
func get_pool_ratios() -> Dictionary:
	return {
		"life": life / max_life if max_life > 0.0 else 1.0,
		"mana": mana / max_mana if max_mana > 0.0 else 1.0,
		"es": es / max_es if max_es > 0.0 else 1.0,
	}


func set_pool_ratios(r: Dictionary) -> void:
	life = maxf(1.0, max_life * clampf(float(r.get("life", 1.0)), 0.0, 1.0))
	mana = max_mana * clampf(float(r.get("mana", 1.0)), 0.0, 1.0)
	es = max_es * clampf(float(r.get("es", 1.0)), 0.0, 1.0)


func life_ratio() -> float:
	return life / max_life if max_life > 0.0 else 0.0


func is_low_life() -> bool:
	return life_ratio() <= 0.35


## Life, mana and energy shield to their maxima (level up, respawn).
func refill_pools() -> void:
	if dead:
		return
	life = max_life
	mana = max_mana
	es = max_es


# ------------------------------------------------------------------ combat

## Apply a hit (§6.5): invulnerability, evade/block rolls, mitigation (DamageCalc.mitigate), mind
## over matter, ES before life, ailments (freeze threshold/immunity, chill from cold taken),
## floating numbers, leech/on-hit callbacks, death.
## Returns the damage actually dealt (0 when evaded/blocked).
func take_hit(hit: HitData) -> float:
	if hit == null or dead:
		return 0.0
	# A subclass may catch the hit before anything else (the player's parry, also in god mode).
	if _intercept_hit(hit):
		return 0.0
	if god_mode or invulnerable_time > 0.0:
		return 0.0
	var src: Node = hit.source if is_instance_valid(hit.source) else null
	# Evade (attacks) and block (attacks + projectiles).
	if hit.can_evade and not stats.has_flag("cannot_evade"):
		var ec := DamageCalc.evade_chance(self, hit.source_level)
		if ec > 0.0 and randf() * 100.0 < ec:
			Events.damage_number.emit(get_aim_point(), 0.0, "evade", false)
			Sfx.play("evade", _gpos())
			return 0.0
	if hit.can_block and block_chance > 0.0 and randf() * 100.0 < block_chance:
		Events.damage_number.emit(get_aim_point(), 0.0, "block", false)
		Sfx.play("hit_block", _gpos())
		return 0.0
	# Mitigation.
	var m := DamageCalc.mitigate(self, hit)
	var total: float = m["total"]
	var by_type: Dictionary = m["by_type"]
	if total > 0.0:
		_absorb_damage(total)
	# Ailments (skipped on a killing blow): freeze needs enough mitigated cold damage; chill comes
	# from the cold damage taken.
	var cold: float = by_type.get("cold", 0.0)
	if life > 0.0:
		for kind in hit.ailments:
			var data: Dictionary = hit.ailments[kind]
			if kind == "freeze":
				var threshold := (BOSS_FREEZE_THRESHOLD if is_boss_actor else FREEZE_THRESHOLD) * max_life
				if cold < threshold:
					continue
			var d := data.duplicate()
			d["source"] = src
			apply_ailment(kind, d)
		if cold > 0.0:
			_chill_from_cold(cold)
	if hit.knockback > 0.0 and not is_boss_actor and is_inside_tree():
		var push := _gpos() - hit.origin
		push.y = 0.0
		if push.length_squared() > 0.0001:
			knockback_velocity += push.normalized() * hit.knockback
	# Feedback.
	if total > 0.0:
		damaged.emit(total, hit.is_crit, src)
		var number_kind := "player_hurt" if team == Team.PLAYER else hit.dominant_type()
		Events.damage_number.emit(get_aim_point(), total, number_kind, hit.is_crit)
	elif hit.total() > 0.0:
		Events.damage_number.emit(get_aim_point(), 0.0, "immune", false)
	# Leech / life on hit on the attacker.
	if src is Actor and src != self and total > 0.0:
		(src as Actor).on_hit_dealt(self, hit, total)
	if life <= 0.0:
		die(src)
	return total


## Override: return true to swallow a hit completely (checked first: before god mode,
## invulnerability and the evade / block rolls). Player: a hit during the parry window.
func _intercept_hit(_hit: HitData) -> bool:
	return false


## Unmitigated-by-evasion damage of one type (resistance still applies). Used by DoTs and
## environmental damage. Returns damage dealt. DoT damage (is_dot) is never evaded, blocked or
## stopped by invulnerability; its floating numbers are summed per type and emitted every 0.5 s.
## Non-DoT damage respects invulnerable_time, emits `damaged` and a number at once, and chills
## when cold.
func take_damage(amount: float, type: String, is_dot: bool = false) -> float:
	return take_damage_from(null, amount, type, is_dot)


## take_damage() crediting `source` (kill credit: died/on_kill get it as the killer). `source` is
## untyped on purpose: a stored caster (ground effect, cloud) that has been freed since may be
## passed as is; it then counts as "no source".
func take_damage_from(source: Variant, amount: float, type: String, is_dot: bool = false) -> float:
	if dead or god_mode or amount <= 0.0:
		return 0.0
	if not is_dot and invulnerable_time > 0.0:
		return 0.0
	var src: Node = null
	if is_instance_valid(source) and source is Node:
		src = source as Node
	var res: float = resistances.get(type, 0.0)
	var dmg := amount * (1.0 - res / 100.0) * DamageCalc.damage_taken_mult(self)
	if dmg <= 0.0:
		return 0.0
	_absorb_damage(dmg)
	if is_dot:
		_add_number(type, dmg)
	else:
		if type == "cold" and life > 0.0:
			_chill_from_cold(dmg)
		damaged.emit(dmg, false, src)
		Events.damage_number.emit(get_aim_point(), dmg, "player_hurt" if team == Team.PLAYER else type, false)
	if life <= 0.0:
		die(src)
	return dmg


## Mind over Matter (30% from mana first), then energy shield, then life.
func _absorb_damage(total: float) -> void:
	var rest := total
	if mana > 0.0 and stats.has_flag("mind_over_matter"):
		var from_mana := minf(mana, rest * MOM_FRACTION)
		mana -= from_mana
		rest -= from_mana
	if es > 0.0:
		var absorbed := minf(es, rest)
		es -= absorbed
		rest -= absorbed
	life -= rest
	time_since_damaged = 0.0
	_pools_live = true


func _chill_from_cold(cold_taken: float) -> void:
	if cold_taken <= 0.0 or dead:
		return
	var effect := clampf(cold_taken / maxf(1.0, max_life) * 2.0, CHILL_MIN, CHILL_MAX)
	apply_ailment("chill", {"effect": effect, "duration": CHILL_DURATION})


## Apply / refresh an ailment. See §6.4 for kinds and data. data keys: "dps" (ignite, bleed,
## poison), "effect" (shock, chill), "duration" (all), optional "source" (kill credit for DoTs).
## Bosses take ×0.5 durations (freeze ×0.3). Freeze here only checks freeze immunity (the damage
## threshold is checked by take_hit).
func apply_ailment(kind: String, data: Dictionary) -> void:
	if dead:
		return
	var dur := float(data.get("duration", 0.0))
	if is_boss_actor:
		dur *= BOSS_FREEZE_DURATION_MULT if kind == "freeze" else BOSS_AILMENT_DURATION_MULT
	if dur <= 0.0:
		return
	var src: Variant = data.get("source", null)
	match kind:
		"ignite", "bleed":
			var dps := float(data.get("dps", 0.0))
			if dps <= 0.0:
				return
			if ailments.has(kind):
				var cur: Dictionary = ailments[kind]
				if dps > float(cur["dps"]):
					cur["dps"] = dps
					cur["duration"] = dur
					cur["time_left"] = dur
					cur["source"] = src
				else:
					cur["time_left"] = maxf(float(cur["time_left"]), dur)
					cur["duration"] = maxf(float(cur["duration"]), dur)
			else:
				ailments[kind] = {"dps": dps, "duration": dur, "time_left": dur, "source": src}
				ailment_changed.emit(kind, true)
		"poison":
			var pdps := float(data.get("dps", 0.0))
			if pdps <= 0.0:
				return
			var fresh := not ailments.has("poison")
			if fresh:
				ailments["poison"] = {"stacks": [], "dps": 0.0, "time_left": 0.0, "duration": 0.0, "source": src}
			var p: Dictionary = ailments["poison"]
			var stacks: Array = p["stacks"]
			stacks.append({"dps": pdps, "time_left": dur, "duration": dur})
			while stacks.size() > MAX_POISON_STACKS:
				_remove_weakest_stack(stacks)
			p["source"] = src
			_update_poison(p)
			if fresh:
				ailment_changed.emit("poison", true)
		"shock", "chill":
			var default_effect := DamageCalc.SHOCK_EFFECT if kind == "shock" else CHILL_MIN
			var eff := clampf(float(data.get("effect", default_effect)), 0.0, AILMENT_EFFECT_CAP)
			if eff <= 0.0:
				return
			if ailments.has(kind):
				var c: Dictionary = ailments[kind]
				if eff > float(c["effect"]):
					c["effect"] = eff
					c["duration"] = dur
					c["time_left"] = dur
				elif is_equal_approx(eff, float(c["effect"])):
					c["time_left"] = maxf(float(c["time_left"]), dur)
					c["duration"] = maxf(float(c["duration"]), dur)
			else:
				ailments[kind] = {"effect": eff, "duration": dur, "time_left": dur}
				ailment_changed.emit(kind, true)
		"stun":
			# Parry counters: cannot move or act (like freeze, without the ice or an immunity).
			if ailments.has("stun"):
				var st: Dictionary = ailments["stun"]
				st["time_left"] = maxf(float(st["time_left"]), dur)
				st["duration"] = maxf(float(st["duration"]), dur)
			else:
				ailments["stun"] = {"duration": dur, "time_left": dur}
				velocity = Vector3.ZERO
				if skill_runner != null and is_instance_valid(skill_runner):
					skill_runner.cancel()
				ailment_changed.emit("stun", true)
		"freeze":
			if freeze_immune_time > 0.0:
				return
			if ailments.has("freeze"):
				var f: Dictionary = ailments["freeze"]
				f["time_left"] = maxf(float(f["time_left"]), dur)
				f["duration"] = maxf(float(f["duration"]), dur)
			else:
				ailments["freeze"] = {"duration": dur, "time_left": dur}
				velocity = Vector3.ZERO
				if skill_runner != null and is_instance_valid(skill_runner):
					skill_runner.cancel()
				ailment_changed.emit("freeze", true)
		_:
			push_warning("Actor.apply_ailment: unknown ailment '%s'" % kind)


func _remove_weakest_stack(stacks: Array) -> void:
	var idx := 0
	var best := INF
	for i in stacks.size():
		var s: Dictionary = stacks[i]
		var score := float(s["dps"]) * float(s["time_left"])
		if score < best:
			best = score
			idx = i
	stacks.remove_at(idx)


func _update_poison(p: Dictionary) -> void:
	var total := 0.0
	var longest := 0.0
	var dur := 0.0
	for s in p["stacks"]:
		total += float(s["dps"])
		if float(s["time_left"]) > longest:
			longest = float(s["time_left"])
			dur = float(s["duration"])
	p["dps"] = total
	p["time_left"] = longest
	p["duration"] = dur


## Remove an ailment now (cleanse, respawn). Freeze removal grants the usual freeze immunity.
func remove_ailment(kind: String) -> void:
	if not ailments.has(kind):
		return
	ailments.erase(kind)
	if kind == "freeze":
		freeze_immune_time = BOSS_FREEZE_IMMUNE_TIME if is_boss_actor else FREEZE_IMMUNE_TIME
	ailment_changed.emit(kind, false)


func clear_ailments() -> void:
	for kind in ailments.keys():
		ailments.erase(kind)
		ailment_changed.emit(kind, false)


func has_ailment(kind: String) -> bool:
	return ailments.has(kind)


func is_frozen() -> bool:
	return ailments.has("freeze")


func is_stunned() -> bool:
	return ailments.has("stun")


## False while dead, frozen or stunned.
func can_act() -> bool:
	return not dead and not is_frozen() and not ailments.has("stun")


## Current chill slow (0..0.5; 0.3 max from cold hits).
func get_chill_effect() -> float:
	var c: Variant = ailments.get("chill")
	return float(c["effect"]) if c != null else 0.0


## Current shock (extra damage taken fraction, 0.2 = +20%).
func get_shock_effect() -> float:
	var s: Variant = ailments.get("shock")
	return float(s["effect"]) if s != null else 0.0


func _tick_ailments(delta: float) -> void:
	var expired: PackedStringArray = []
	# Iterate a copy of the keys: a killing DoT tick clears the dictionary.
	for kind in ailments.keys():
		var a: Dictionary = ailments[kind]
		var left := float(a["time_left"])
		match kind:
			"ignite":
				_dot_tick(float(a["dps"]) * minf(delta, maxf(left, 0.0)), "fire", a.get("source"))
			"bleed":
				_dot_tick(float(a["dps"]) * minf(delta, maxf(left, 0.0)), "physical", a.get("source"))
			"poison":
				# Each stack deals damage only for the time it has left (exact totals).
				var stacks: Array = a["stacks"]
				var amount := 0.0
				for s in stacks:
					amount += float(s["dps"]) * minf(delta, maxf(float(s["time_left"]), 0.0))
				_dot_tick(amount, "chaos", a.get("source"))
				if dead:
					return
				var i := stacks.size() - 1
				while i >= 0:
					var st: Dictionary = stacks[i]
					st["time_left"] = float(st["time_left"]) - delta
					if float(st["time_left"]) <= TIME_EPSILON:
						stacks.remove_at(i)
					i -= 1
				_update_poison(a)
				if stacks.is_empty():
					expired.append(kind)
				continue
		if dead:
			return
		var tl := left - delta
		a["time_left"] = tl
		if tl <= TIME_EPSILON:
			expired.append(kind)
	for kind in expired:
		ailments.erase(kind)
		if kind == "freeze":
			freeze_immune_time = BOSS_FREEZE_IMMUNE_TIME if is_boss_actor else FREEZE_IMMUNE_TIME
		ailment_changed.emit(kind, false)


func _dot_tick(amount: float, type: String, source: Variant) -> void:
	if amount <= 0.0:
		return
	var src: Node = null
	if is_instance_valid(source) and source is Node:
		src = source
	take_damage_from(src, amount, type, true)


## data: {"name": String, "mods": Array, "duration": float, "icon": String}. Re-adding refreshes
## (and replaces the mods). duration <= 0 = permanent until remove_buff().
func add_buff(id: String, data: Dictionary) -> void:
	if dead:
		return
	var dur := float(data.get("duration", 0.0))
	buffs[id] = {
		"name": String(data.get("name", id)),
		"mods": (data.get("mods", []) as Array).duplicate(true),
		"duration": dur,
		"time_left": dur if dur > 0.0 else INF,
		"icon": String(data.get("icon", "")),
		"desc": String(data.get("desc", "")),
	}
	recalculate_stats()
	buffs_changed.emit()


func remove_buff(id: String) -> void:
	if not buffs.has(id):
		return
	buffs.erase(id)
	recalculate_stats()
	buffs_changed.emit()


func has_buff(id: String) -> bool:
	return buffs.has(id)


func _tick_buffs(delta: float) -> void:
	var expired: PackedStringArray = []
	for id in buffs:
		var b: Dictionary = buffs[id]
		var tl: float = b["time_left"]
		if tl == INF:
			continue
		tl -= delta
		b["time_left"] = tl
		if tl <= TIME_EPSILON:
			expired.append(id)
	if expired.is_empty():
		return
	for id in expired:
		buffs.erase(id)
	recalculate_stats()
	buffs_changed.emit()


## Returns the amount actually healed. Explicit heals (potions, skills) show a "heal" number when
## significant (summed per 0.5 s); leech / on-hit / on-kill recovery is silent.
func heal(amount: float) -> float:
	var healed := _heal_silent(amount)
	if healed > 0.0:
		_add_number("heal", healed)
	return healed


func restore_mana(amount: float) -> float:
	var restored := _mana_silent(amount)
	if restored > 0.0:
		_add_number("mana", restored)
	return restored


func _heal_silent(amount: float) -> float:
	if dead or amount <= 0.0 or life >= max_life:
		return 0.0
	var h := minf(amount, max_life - life)
	life += h
	return h


func _mana_silent(amount: float) -> float:
	if dead or amount <= 0.0 or mana >= max_mana:
		return 0.0
	var m := minf(amount, max_mana - mana)
	mana += m
	return m


## True if the actor can pay this cost now (Blood Magic: pays with life, must stay above 1).
## Enemies never pay costs (always true).
func can_pay_cost(amount: float) -> bool:
	if amount <= 0.0 or team == Team.ENEMY:
		return true
	if dead:
		return false
	if stats.has_flag("blood_magic"):
		return life - amount >= 1.0
	return mana + 0.0001 >= amount


## Pays a skill cost (mana, or life under Blood Magic). Returns false if it can't be paid.
func pay_cost(amount: float) -> bool:
	if amount <= 0.0 or team == Team.ENEMY:
		return true
	if not can_pay_cost(amount):
		return false
	if stats.has_flag("blood_magic"):
		life -= amount
	else:
		mana = maxf(0.0, mana - amount)
	return true


## Kill the actor: dead, collision layer cleared, ailments cleared, `died` emitted,
## killer.on_kill(self), then _on_death(killer). Safe to call twice (no-op).
func die(killer: Node = null) -> void:
	if dead:
		return
	dead = true
	life = 0.0
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	collision_layer = 0
	if skill_runner != null and is_instance_valid(skill_runner):
		skill_runner.cancel()
	if not _number_accum.is_empty():
		_flush_numbers()
	clear_ailments()
	var k: Node = killer if is_instance_valid(killer) else null
	died.emit(self, k)
	if k is Actor and k != self:
		(k as Actor).on_kill(self)
	_on_death(k)


## Called on the ATTACKER after its hit landed on `target` (leech, life on hit, ...).
## Leech + life on hit restore at most 20% of max life per rolling second (mana leech 20% of max
## mana); life on hit counts at most 5 targets per skill use (hit.use_id) / tick.
func on_hit_dealt(_target: Actor, hit: HitData, dealt: float) -> void:
	if dead or dealt <= 0.0:
		return
	var gain := dealt * stats.flat("life_leech") / 100.0
	var loh := stats.flat("life_on_hit")
	if loh > 0.0 and hit != null:
		var key: Variant = hit.use_id if hit.use_id != 0 else "%s@%d" % [hit.skill_id, Engine.get_physics_frames()]
		var n := int(_loh_counts.get(key, 0))
		if n < LIFE_ON_HIT_MAX_TARGETS:
			if _loh_counts.size() > 32:
				_loh_counts.clear()
			_loh_counts[key] = n + 1
			gain += loh
	if gain > 0.0 and life < max_life:
		var allowed := _recovery_budget(_life_recovery_log, LEECH_CAP_FRACTION * max_life)
		var healed := _heal_silent(minf(gain, allowed))
		if healed > 0.0:
			_life_recovery_log.append(Vector2(_clock, healed))
	var mgain := dealt * stats.flat("mana_leech") / 100.0
	if mgain > 0.0 and mana < max_mana:
		var mallowed := _recovery_budget(_mana_recovery_log, LEECH_CAP_FRACTION * max_mana)
		var restored := _mana_silent(minf(mgain, mallowed))
		if restored > 0.0:
			_mana_recovery_log.append(Vector2(_clock, restored))


## How much more may be recovered inside the rolling one-second window.
func _recovery_budget(entries: Array[Vector2], cap: float) -> float:
	var cutoff := _clock - 1.0
	while not entries.is_empty() and entries[0].x <= cutoff:
		entries.pop_front()
	var used := 0.0
	for e in entries:
		used += e.y
	return maxf(0.0, cap - used)


## Called on the killer when it killed `target` (life/mana on kill, ...).
func on_kill(_target: Actor) -> void:
	if dead:
		return
	var l := stats.flat("life_on_kill")
	if l > 0.0:
		_heal_silent(l)
	var m := stats.flat("mana_on_kill")
	if m > 0.0:
		_mana_silent(m)


# ------------------------------------------------------------------ floating numbers

func _add_number(kind: String, amount: float) -> void:
	if _number_accum.is_empty():
		_number_timer = 0.0
	_number_accum[kind] = float(_number_accum.get(kind, 0.0)) + amount


## Emit the summed DoT numbers (one per type) and significant heal / mana numbers.
func _flush_numbers() -> void:
	var pos := get_aim_point()
	for kind in _number_accum:
		var v: float = _number_accum[kind]
		if kind == "heal":
			if v >= maxf(1.0, HEAL_NUMBER_FRACTION * max_life):
				Events.damage_number.emit(pos, v, "heal", false)
		elif kind == "mana":
			if v >= maxf(1.0, HEAL_NUMBER_FRACTION * max_mana):
				Events.damage_number.emit(pos, v, "mana", false)
		elif v > 0.0:
			Events.damage_number.emit(pos, v, "player_hurt" if team == Team.PLAYER else kind, false)
	_number_accum.clear()
	_number_timer = 0.0


func _gpos() -> Vector3:
	return global_position if is_inside_tree() else position

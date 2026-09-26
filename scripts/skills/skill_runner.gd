class_name SkillRunner
extends Node
## Per-actor skill execution: validation (weapon, cost, cooldown), the use timeline (wind-up,
## effect at the hit frame, recovery), channelling, cooldowns, and dispatching to the delivery
## implementations (melee arc, projectile, nova, ...). Used identically by Player and Enemy.
## OWNER: skills (wave 2). CONTRACT — keep every public member/signature.
## See docs/ARCHITECTURE.md §8.
##
## Timeline of one use (all times divided by the actor's action speed, i.e. 1 − chill):
##   U = DamageCalc.get_use_time(actor, skill); hit = hit_frame × U (with a wind-up W:
##   max(W, hit_frame × U), the red telegraph fills exactly until then); movement skills add their
##   travel time (leap flight / charge dash) before the impact. The animation is stretched so its
##   own impact frame lands on the skill's impact: duration = max(U, impact / anim_hit_frame).
##   skill_started at 0, the delivery + skill_effect at the hit time, skill_finished at the end.
## Channelled skills (channel_aoe) loop "channel", tick every U seconds (cost_per_tick each tick,
## the first tick at hit_frame × U) until release() / out of mana / cancel().
## The node processes itself (_physics_process -> tick(delta)); tests may call tick() directly.

signal skill_started(skill_id: String, anim: String, duration: float)
signal skill_effect(skill_id: String)
signal skill_finished(skill_id: String)

## Minimum time between two identical failure notifications for the player.
const FAIL_THROTTLE_MS := 1000
## Non-player actors stop channelling after this long even without release().
const AI_CHANNEL_MAX := 2.5
## try_use calls closer together than this count as one held key (no repeated "not ready").
const HELD_RETRY_MS := 300
## Whirlwind's sound repeats this often while channelling.
const CHANNEL_SFX_INTERVAL := 0.6

var actor: Actor = null
## The most recent SkillUse started by this runner (tests / demos / HUD).
var last_use: SkillUse = null

## skill id -> Vector2(time left, total)
var _cooldowns: Dictionary = {}
## reason -> Time.get_ticks_msec() of the last notification
var _fail_times: Dictionary = {}
## skill id -> Time.get_ticks_msec() of the previous try_use (held keys retry every frame).
var _last_attempt: Dictionary = {}
var _attempt_gap_ms := 1000000
var _current := ""
var _skill: Dictionary = {}
var _use: SkillUse = null
var _anim := ""
var _elapsed := 0.0
var _duration := 0.0
var _hit_time := 0.0
var _effect_done := false
var _channel := false
var _channel_interval := 0.0
var _channel_next := 0.0
var _channel_ticks := 0
var _release_pending := false
var _channel_sfx := 0.0
var _telegraphs: Array = []
## WeakRefs to long-running deliveries owned by the use (SkillMover, SkillSequence).
var _owned: Array = []
var _channel_fx: VfxEffect = null


func setup(p_actor: Actor) -> void:
	actor = p_actor


func _physics_process(delta: float) -> void:
	tick(delta)


## {"ok": bool, "reason": String, "code": String}. code is one of
## "ok" | "unknown" | "cannot_act" | "level" | "weapon" | "cost" | "cooldown".
## Does NOT fail for "busy" (try_use handles that). "level": player actors need
## actor.level >= skill.unlock_level. Enemies skip the cost check (monster skills cost 0).
## The HUD tints a slot red for codes "cost", "weapon", "level".
func can_use(skill_id: String) -> Dictionary:
	var s := SkillDB.get_skill(skill_id)
	if s.is_empty():
		return _result(false, "Unknown skill", "unknown")
	if not _actor_ok() or not actor.can_act():
		var why := "Frozen" if _actor_ok() and actor.is_frozen() else "Cannot act"
		return _result(false, why, "cannot_act")
	var player_side := actor.team == Actor.Team.PLAYER
	if player_side and not bool(s.get("monster_only", false)) and actor.level < int(s.get("unlock_level", 1)):
		return _result(false, "%s requires Level %d" % [String(s.get("name", skill_id)), int(s.get("unlock_level", 1))], "level")
	var wt := _weapon_type()
	if not SkillDB.is_weapon_compatible(skill_id, wt):
		var txt := SkillDB.get_weapon_requirement_text(skill_id)
		return _result(false, txt if txt != "" else "Can't use that with this weapon", "weapon")
	if get_cooldown_remaining(skill_id) > 0.0:
		return _result(false, "%s is not ready yet" % String(s.get("name", skill_id)), "cooldown")
	if player_side:
		var r := SkillDB.resolve_for_weapon(s, wt)
		var cost := DamageCalc.get_cost(actor, r)
		if String(r.get("delivery", "")) == "channel_aoe":
			cost += DamageCalc.scale_cost(actor, float(r.get("params", {}).get("cost_per_tick", 0.0)))
		if cost > 0.0 and not actor.can_pay_cost(cost):
			return _result(false, _cost_reason(), "cost")
	return _result(true, "", "ok")


## Start using a skill toward target_pos (y is ignored for ground targets) / target.
## Faces the actor toward the target, pays the cost, plays the animation via
## actor.play_action_animation(). Returns false if it could not start.
func try_use(skill_id: String, target_pos: Vector3, target: Actor = null) -> bool:
	var now := Time.get_ticks_msec()
	_attempt_gap_ms = now - int(_last_attempt.get(skill_id, -1000000))
	_last_attempt[skill_id] = now
	if is_busy():
		return false
	var check := can_use(skill_id)
	if not bool(check["ok"]):
		_notify_failure(check)
		return false
	var wt := _weapon_type()
	var s := SkillDB.resolve_for_weapon(SkillDB.get_skill(skill_id), wt)
	var cost := DamageCalc.get_cost(actor, s)
	if cost > 0.0 and not actor.pay_cost(cost):
		_notify_failure(_result(false, _cost_reason(), "cost"))
		return false
	var cd := DamageCalc.get_cooldown(actor, s)
	if cd > 0.0:
		_cooldowns[skill_id] = Vector2(cd, cd)
	var use := SkillUse.create(actor, s, target_pos, target)
	_use = use
	last_use = use
	_current = skill_id
	_skill = s
	_elapsed = 0.0
	_effect_done = false
	_telegraphs.clear()
	_owned.clear()
	actor.face_towards(use.origin + use.direction)

	var speed := maxf(0.05, actor.get_action_speed_mult())
	var u_time := DamageCalc.get_use_time(actor, s)
	var tags: PackedStringArray = PackedStringArray(s.get("tags", PackedStringArray()))
	var nominal := float(s.get("attack_time_mult", 1.0)) if tags.has("attack") else float(s.get("cast_time", DamageCalc.DEFAULT_CAST_TIME))
	use.time_scale = u_time / maxf(0.05, nominal) / speed
	_anim = SkillDB.get_anim(s, wt)
	var hf := clampf(SkillDB.get_hit_frame(s, _anim), 0.0, 1.0)
	var windup := float(use.params.get("windup", 0.0))
	SkillDeliveries.prepare(use)
	if windup > 0.0:
		use.committed = true
	var sfx_use := String(s.get("sfx", {}).get("use", ""))
	if sfx_use != "":
		Sfx.play(sfx_use, use.origin)

	if String(s.get("delivery", "")) == "channel_aoe":
		_start_channel(skill_id, u_time, speed, hf)
		return true

	var t_hit := hf * u_time
	if windup > 0.0:
		t_hit = maxf(windup, t_hit)
	var t_impact := t_hit + SkillDeliveries.travel_time(use)
	var anim_hf := float(SkillDB.ANIM_HIT_FRAMES.get(_anim, hf))
	var d_anim := u_time
	if anim_hf >= 0.2:
		d_anim = maxf(u_time, t_impact / anim_hf)
	else:
		d_anim = maxf(u_time, t_impact + 0.3)
	var duration := maxf(d_anim, t_impact + 0.05)
	_hit_time = t_hit / speed
	_duration = duration / speed
	actor.play_action_animation(_anim, _duration)
	skill_started.emit(skill_id, _anim, _duration)
	if windup > 0.0:
		_telegraphs = SkillDeliveries.telegraph(use, _hit_time)
	if tags.has("spell") and _hit_time >= 0.25 and String(s.get("delivery", "")) != "blink":
		var sigil := VfxSpawn.cast_circle(actor, use.color, _hit_time)
		if sigil != null:
			_telegraphs.append(sigil)
	if _hit_time <= 0.0:
		_do_effect()
	return true


## While the skill button is held: update aim (channelled skills, repeated use).
func update_target(target_pos: Vector3, target: Actor = null) -> void:
	if _use == null or _current == "":
		return
	if _use.committed:
		return
	_use.set_target(target)
	_use.set_aim(target_pos)
	if not _channel and not _effect_done and _actor_ok():
		actor.face_towards(_use.origin + _use.direction)


## Skill button released (stops channelling).
func release(skill_id: String) -> void:
	if not _channel or _current != skill_id:
		return
	if _channel_ticks >= 1:
		_end_channel()
	else:
		_release_pending = true


## True while a skill's use animation is running.
func is_busy() -> bool:
	return _current != ""


func get_current_skill() -> String:
	return _current


## Movement speed multiplier while using the current skill (0 = rooted, 1 = free).
func movement_multiplier() -> float:
	if _current == "":
		return 1.0
	return clampf(float(_skill.get("move_mult", 0.0)), 0.0, 1.0)


func get_cooldown_remaining(skill_id: String) -> float:
	if not _cooldowns.has(skill_id):
		return 0.0
	return maxf(0.0, (_cooldowns[skill_id] as Vector2).x)


## 0 = ready, 1 = just used.
func get_cooldown_ratio(skill_id: String) -> float:
	if not _cooldowns.has(skill_id):
		return 0.0
	var c: Vector2 = _cooldowns[skill_id]
	return clampf(c.x / maxf(0.0001, c.y), 0.0, 1.0)


## Abort the current use (e.g. when frozen or dodge-rolling).
func cancel() -> void:
	if _current == "":
		return
	var id := _current
	for t in _telegraphs:
		if t != null and is_instance_valid(t):
			(t as VfxEffect).cancel(0.15)
	for r in _owned:
		var n: Variant = (r as WeakRef).get_ref()
		if n != null and is_instance_valid(n) and n.has_method("abort"):
			n.abort()
	_end_channel_fx()
	_clear_state()
	if _actor_ok():
		actor.stop_action_animation()
	skill_finished.emit(id)


# ------------------------------------------------------------------ additions

## Advance the timeline and cooldowns by delta seconds (called by _physics_process).
func tick(delta: float) -> void:
	if not _cooldowns.is_empty():
		for id in _cooldowns.keys():
			var c: Vector2 = _cooldowns[id]
			c.x -= delta
			if c.x <= 0.00001:
				_cooldowns.erase(id)
			else:
				_cooldowns[id] = c
	if _current == "":
		return
	if not _actor_ok() or not actor.can_act():
		cancel()
		return
	_elapsed += delta
	if _channel:
		_tick_channel(delta)
		return
	if not _effect_done and _elapsed >= _hit_time - 0.00001:
		_do_effect()
	if _current != "" and _elapsed >= _duration - 0.00001:
		_finish()


func is_channelling() -> bool:
	return _channel and _current != ""


## Progress of the current use 0..1 (0 when idle; channels report 0).
func get_use_progress() -> float:
	if _current == "" or _channel or _duration <= 0.0:
		return 0.0
	return clampf(_elapsed / _duration, 0.0, 1.0)


## The SkillUse of the running skill (null when idle).
func get_current_use() -> SkillUse:
	return _use if _current != "" else null


## Seconds from start to the effect / to the end of the current use (0 when idle).
func get_hit_time() -> float:
	return _hit_time if _current != "" else 0.0


func get_duration() -> float:
	return _duration if _current != "" else 0.0


func reset_cooldowns() -> void:
	_cooldowns.clear()


# ------------------------------------------------------------------ internals

func _do_effect() -> void:
	_effect_done = true
	var use := _use
	if use == null:
		return
	if not use.committed:
		use.set_aim(use.target_pos)
		SkillDeliveries.prepare(use)
		if _actor_ok():
			actor.face_towards(use.origin + use.direction)
	_telegraphs.clear()
	var id := _current
	var owned: Variant = SkillDeliveries.execute(use)
	if owned != null and is_instance_valid(owned):
		_owned.append(weakref(owned))
	if _current == id:
		skill_effect.emit(id)


func _finish() -> void:
	var id := _current
	_clear_state()
	skill_finished.emit(id)


func _start_channel(skill_id: String, u_time: float, speed: float, hf: float) -> void:
	_channel = true
	_channel_interval = maxf(0.05, u_time / speed)
	_channel_next = _channel_interval * clampf(hf, 0.05, 1.0)
	_channel_ticks = 0
	_release_pending = false
	_channel_sfx = CHANNEL_SFX_INTERVAL
	_hit_time = _channel_next
	_duration = 0.0
	_anim = "channel"
	actor.play_action_animation("channel", 0.0)
	skill_started.emit(skill_id, "channel", 0.0)
	var radius := float(_use.plan.get("radius", 2.5))
	var runner_ref: WeakRef = weakref(self)
	_channel_fx = VfxSpawn.whirl(actor, radius, _use.color, func() -> bool:
		var r: Variant = runner_ref.get_ref()
		return r != null and is_instance_valid(r) and (r as SkillRunner).is_channelling())


func _tick_channel(delta: float) -> void:
	var id := _current
	if actor.team != Actor.Team.PLAYER and _elapsed >= AI_CHANNEL_MAX:
		_release_pending = true
	_channel_sfx -= delta
	if _channel_sfx <= 0.0:
		_channel_sfx = CHANNEL_SFX_INTERVAL
		var sid := String(_skill.get("sfx", {}).get("use", ""))
		if sid != "":
			Sfx.play(sid, actor.global_position)
	while _current == id and _channel and _elapsed >= _channel_next - 0.00001:
		var per_tick := DamageCalc.scale_cost(actor, float(_skill.get("params", {}).get("cost_per_tick", 0.0)))
		if per_tick > 0.0 and not actor.pay_cost(per_tick):
			_notify_failure(_result(false, _cost_reason(), "cost"))
			_end_channel()
			return
		SkillDeliveries.channel_tick(_use)
		_channel_ticks += 1
		skill_effect.emit(id)
		if _current != id:
			return
		var speed := maxf(0.05, actor.get_action_speed_mult())
		_channel_interval = maxf(0.05, DamageCalc.get_use_time(actor, _skill) / speed)
		_channel_next += _channel_interval
		if _release_pending:
			_end_channel()
			return


func _end_channel() -> void:
	if _current == "":
		return
	var id := _current
	_end_channel_fx()
	_clear_state()
	if _actor_ok():
		actor.stop_action_animation()
	skill_finished.emit(id)


func _end_channel_fx() -> void:
	if _channel_fx != null and is_instance_valid(_channel_fx):
		_channel_fx.end_now(0.5)
	_channel_fx = null


func _clear_state() -> void:
	_current = ""
	_skill = {}
	_use = null
	_anim = ""
	_elapsed = 0.0
	_duration = 0.0
	_hit_time = 0.0
	_effect_done = false
	_channel = false
	_channel_ticks = 0
	_release_pending = false
	_telegraphs.clear()
	_owned.clear()


func _actor_ok() -> bool:
	return actor != null and is_instance_valid(actor)


func _weapon_type() -> String:
	if not _actor_ok():
		return "unarmed"
	return String(actor.get_weapon().get("weapon_type", "unarmed"))


func _cost_reason() -> String:
	if _actor_ok() and actor.stats.has_flag("blood_magic"):
		return "Not enough life"
	return "Not enough mana"


static func _result(ok: bool, reason: String, code: String) -> Dictionary:
	return {"ok": ok, "reason": reason, "code": code}


## Throttled Events.skill_use_failed for the real player (≥ 1 s per reason).
func _notify_failure(r: Dictionary) -> void:
	if not _actor_ok() or not actor.is_in_group("player"):
		return
	var code := String(r.get("code", ""))
	if code in ["unknown", "cannot_act", "ok"]:
		return
	# A held key retries every frame: "not ready" only for a fresh press.
	if code == "cooldown" and _attempt_gap_ms < HELD_RETRY_MS:
		return
	var reason := String(r.get("reason", ""))
	var now := Time.get_ticks_msec()
	if _fail_times.has(reason) and now - int(_fail_times[reason]) < FAIL_THROTTLE_MS:
		return
	_fail_times[reason] = now
	Events.skill_use_failed.emit(reason)

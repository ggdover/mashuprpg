class_name SkillSequence
extends Node3D
## Rapid fire (§8.3 "sequence"): `repeat` shots of the projectile params, `interval` seconds apart
## (scaled like the use: faster attacks shoot faster), re-aimed at the current aim before each
## shot. Each shot has its own hit set (a burst can hit one target every time) but shares the
## use id. The caster's SkillRunner aborts it on cancel; it also stops when the caster dies.
## Frees itself. OWNER: skills (wave 2).

var use: SkillUse = null
var repeat := 3
var interval := 0.1
var shots := 0
var elapsed := 0.0
var _next := 0.0
var aborted := false


static func spawn(p_use: SkillUse) -> SkillSequence:
	var s := SkillSequence.new()
	s.name = "Sequence_%s" % p_use.skill_id
	s.use = p_use
	s.repeat = maxi(1, int(p_use.params.get("repeat", 3)))
	s.interval = maxf(0.02, float(p_use.params.get("interval", 0.1)) * p_use.time_scale)
	if VfxUtil.spawn(s, p_use.origin) == null:
		return null
	s._shoot()
	return s


func _physics_process(delta: float) -> void:
	if aborted or shots >= repeat:
		queue_free()
		return
	var c := use.get_caster()
	if c == null or c.dead or not c.can_act():
		queue_free()
		return
	elapsed += delta
	while shots < repeat and elapsed >= _next:
		_shoot()
	if shots >= repeat:
		queue_free()


func _shoot() -> void:
	var c := use.get_caster()
	if c == null or c.dead:
		aborted = true
		return
	use.set_aim(use.target_pos)
	c.face_towards(use.origin + use.direction)
	var shot := use.fork()
	shot.hit_set = {}
	SkillDeliveries.fire_projectiles(shot, c)
	VfxSpawn.muzzle_flash(VfxUtil.flat(c.global_position) + use.direction * 0.7 + Vector3(0, SkillDeliveries.PROJECTILE_HEIGHT, 0), use.color)
	if shots > 0:
		var sid := String(use.skill.get("sfx", {}).get("release", ""))
		if sid != "":
			Sfx.play(sid, use.origin)
	shots += 1
	_next = shots * interval


## Stop firing (the use was cancelled).
func abort() -> void:
	aborted = true

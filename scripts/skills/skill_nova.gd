class_name SkillNova
extends Node3D
## An expanding ring centred where it was cast (§8.3 "nova": Frost Nova, the Lich's fire nova):
## each hostile is hit once, when the ring reaches it (radius grows linearly over expand_time).
## Frees itself. OWNER: skills (wave 2).

var use: SkillUse = null
var radius := 4.0
var expand_time := 0.3
var elapsed := 0.0
var current_radius := 0.0


static func spawn(p_use: SkillUse, center: Vector3, p_radius: float, p_expand_time: float) -> SkillNova:
	var n := SkillNova.new()
	n.name = "Nova_%s" % p_use.skill_id
	n.use = p_use
	n.radius = p_radius
	n.expand_time = maxf(0.0, p_expand_time)
	if VfxUtil.spawn(n, VfxUtil.flat(center)) == null:
		return null
	var style := ""
	if p_use.tags.has("cold"):
		style = "frost"
	elif p_use.tags.has("fire"):
		style = "fire"
	VfxSpawn.nova(VfxUtil.flat(center), p_radius, p_use.color, maxf(0.12, n.expand_time), style)
	var sid := String(p_use.skill.get("sfx", {}).get("impact", ""))
	if sid != "":
		Sfx.play(sid, center)
	if n.expand_time <= 0.0:
		n._sweep(p_radius)
		n.queue_free()
	return n


func _physics_process(delta: float) -> void:
	elapsed += delta
	var r := radius if expand_time <= 0.0 else radius * clampf(elapsed / expand_time, 0.0, 1.0)
	_sweep(r)
	if elapsed >= expand_time:
		queue_free()


func _sweep(r: float) -> void:
	current_radius = r
	var center := global_position
	for a in use.hostiles_in_radius(center, r):
		if use.was_hit(a):
			continue
		use.deal_hit(a, {"origin": center})

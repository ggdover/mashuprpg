class_name SkillImpact
extends Node3D
## One delayed area impact (§8.3 "aoe_target" and each impact of "rain"): shows what is coming
## (a player target ring, a red telegraph for monsters, a falling meteor / arrow), then after
## `delay` seconds hits every hostile within `radius` and plays the impact effect. Frees itself.
## OWNER: skills (wave 2).
##
## opts: "style" ("meteor" | "arrow" | "spike" | "blast"), "telegraph" (red filling disc),
## "marker" (the caster's coloured target ring), "shared_hits" (skip hostiles this use already hit:
## Rain of Arrows / Bone Spikes hit each enemy once per use), "fall" (s the falling visual takes,
## default = delay), "effectiveness".

## Where a meteor starts relative to its impact point (falls toward the camera side).
## (Kept on the camera side so the whole fall stays on screen under the high gameplay camera.)
const METEOR_OFFSET := Vector3(2.5, 7.5, 0.5)
const ARROW_OFFSET := Vector3(0.5, 7.5, 1.2)

var use: SkillUse = null
var radius := 2.0
var delay := 1.0
var style := "blast"
var shared_hits := false
var effectiveness := 1.0
var fall := 1.0
var elapsed := 0.0
var done := false

var _faller: Node3D = null
var _missile: VfxMissile = null
var _fall_from := Vector3.ZERO
var _linger := 0.0


static func spawn(p_use: SkillUse, pos: Vector3, p_radius: float, p_delay: float, opts: Dictionary = {}) -> SkillImpact:
	var s := SkillImpact.new()
	s.name = "Impact_%s" % p_use.skill_id
	s.use = p_use
	s.radius = p_radius
	s.delay = maxf(0.0, p_delay)
	s.style = String(opts.get("style", "blast"))
	s.shared_hits = bool(opts.get("shared_hits", false))
	s.effectiveness = float(opts.get("effectiveness", 1.0))
	s.fall = clampf(float(opts.get("fall", s.delay)), 0.0, s.delay)
	if VfxUtil.spawn(s, VfxUtil.flat(pos)) == null:
		return null
	if bool(opts.get("telegraph", false)) and s.delay > 0.05:
		VfxTelegraph.disc(pos, p_radius, s.delay)
	elif bool(opts.get("marker", false)) and s.delay > 0.05:
		VfxSpawn.target_marker(pos, p_radius, p_use.color, s.delay)
	s._build_faller()
	return s


func _build_faller() -> void:
	match style:
		"meteor":
			_fall_from = METEOR_OFFSET
			_missile = VfxMissile.build({"color": use.color, "trail": false, "light": true, "scale": clampf(radius / 3.5, 0.6, 1.2)}, "proj_meteor", 0.75)
			add_child(_missile)
			_missile.position = _fall_from
			_missile.face(-_fall_from)
			_add_meteor_glow(_missile)
		"arrow":
			_fall_from = ARROW_OFFSET + Vector3(randf_range(-0.3, 0.3), randf_range(-1.0, 1.0), 0)
			_missile = VfxMissile.build({"color": use.color, "trail": true, "scale": 1.1}, "proj_arrow", 1.0)
			add_child(_missile)
			_missile.face(-_fall_from)
	if _missile != null:
		_missile.visible = false


func _add_meteor_glow(m: VfxMissile) -> void:
	var gm := VfxUtil.material("orb", {"color": use.color, "energy": 2.2, "core": 0.5, "rim": 1.4, "alpha": 0.8})
	var g := VfxUtil.mesh_node(VfxUtil.sphere_mesh(), gm)
	g.scale = Vector3.ONE * 0.55 * clampf(radius / 3.5, 0.6, 1.2)
	m.heading.add_child(g)
	VfxUtil.particles(m, Color.WHITE, {"amount": 60, "lifetime": 0.45, "speed": Vector2(0.3, 1.2), "gravity": 1.0, "spread": 180.0,
		"size": 0.45, "emit_radius": 0.35, "one_shot": false, "energy": 1.6, "damping": 1.0, "ramp": VfxSpawn.hot_ramp(use.color), "grow": true})


func _physics_process(delta: float) -> void:
	if done:
		_linger -= delta
		if _linger <= 0.0:
			queue_free()
		return
	elapsed += delta
	if _missile != null and fall > 0.0:
		var start := delay - fall
		if elapsed >= start:
			_missile.visible = true
			var t := clampf((elapsed - start) / fall, 0.0, 1.0)
			var e := t * t if style == "meteor" else t
			_missile.position = _fall_from * (1.0 - e) + Vector3(0, 0.3 if style == "meteor" else 0.4, 0) * e
	if elapsed >= delay:
		_impact()


func _impact() -> void:
	done = true
	var center := global_position
	var sfx := String(use.skill.get("sfx", {}).get("impact", ""))
	match style:
		"meteor":
			VfxSpawn.explosion(center, radius, use.color, 1.6)
			VfxSpawn.shock_ring(center, radius * 1.25, use.color)
		"arrow":
			VfxSpawn.arrow_landing(center, -_fall_from.normalized(), use.color)
		"spike":
			VfxSpawn.spikes(center, radius, use.color)
		_:
			VfxSpawn.explosion(center, radius, use.color, 1.0)
	if _missile != null:
		_linger = _missile.fizzle()
		_missile.visible = _linger > 0.0
	if sfx != "":
		Sfx.play(sfx, center)
	use.hit_area(center, radius, {"effectiveness": effectiveness, "origin": center}, shared_hits)
	if _linger <= 0.0:
		queue_free()

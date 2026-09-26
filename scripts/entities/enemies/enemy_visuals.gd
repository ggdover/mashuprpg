extends Node3D
## Visual side of an Enemy (child node "Visuals"): the Blender model with carried weapons and
## archetype tint, animations (idle/run by speed with the run cycle matched to the move speed,
## time-scaled one-shots), a per-enemy overlay material for the rarity rim glow + hit flash, an
## overhead life bar (billboard shader, shared material with per-instance parameters) with a
## trailing damage segment and the rarity-coloured name, a pulsing ground ring for rares/bosses and
## a small particle aura for elemental monster mods. Internal to the enemies module.
## OWNER: enemies (wave 2).

## Fallbacks when a model lacks an action animation.
const ANIM_FALLBACKS := {
	"roar": "cast_area", "attack_stab": "attack_slash", "shoot_crossbow": "shoot_bow",
	"cast_area": "cast", "channel": "cast", "dodge": "hit", "shoot_bow": "cast",
}
const LOCO_BLEND := 0.18
const ACTION_BLEND := 0.08
## Speed (m/s) above which the run cycle plays.
const RUN_THRESHOLD := 0.35
const FLASH_DECAY := 6.5
const PUNCH_DECAY := 9.0
const TRAIL_DELAY := 0.35
const TRAIL_SPEED := 0.9
const BAR_HEIGHT := 0.13
const BAR_OFFSET := 0.32
## Rarity rim glows (a = strength).
const MAGIC_RIM := Color(0.3, 0.48, 1.0, 1.35)
const RARE_RIM := Color(1.0, 0.82, 0.25, 1.05)
const BOSS_RIM := Color(1.0, 0.55, 0.2, 0.5)
const ENRAGE_RIM := Color(1.0, 0.22, 0.1, 1.1)
## Life bar thickness (m) per rarity (normal, magic, rare, boss).
const BAR_HEIGHTS: Array[float] = [0.12, 0.12, 0.14, 0.18]
## Name label font size per rarity (normal, magic, rare, boss).
const NAME_FONT_SIZES: Array[int] = [28, 28, 34, 40]

const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 rim_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float rim_power = 2.2;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * rim_color.a * fres + flash_color.rgb * flash;
}
"""

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, blend_mix;
instance uniform float fill = 1.0;
instance uniform float trail = 1.0;
instance uniform vec4 bar_color : source_color = vec4(0.78, 0.1, 0.08, 1.0);
instance uniform float opacity = 1.0;
instance uniform float aspect = 9.0;
void vertex() {
	// Camera-facing billboard (the quad's own size is kept, the node's rotation is ignored).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 border = vec2(0.14 / aspect, 0.16);
	vec2 inner = (UV - border) / (vec2(1.0) - 2.0 * border);
	vec4 col = vec4(0.02, 0.015, 0.015, 0.9);
	if (inner.x >= 0.0 && inner.x <= 1.0 && inner.y >= 0.0 && inner.y <= 1.0) {
		col = vec4(0.16, 0.05, 0.05, 0.88);
		if (inner.x <= trail) {
			col = vec4(0.98, 0.86, 0.62, 0.95);
		}
		if (inner.x <= fill) {
			col = bar_color;
			col.rgb *= mix(1.35, 0.7, inner.y);
		}
	}
	ALBEDO = col.rgb;
	ALPHA = col.a * opacity;
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 ring_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.66, 0.8, r) * (1.0 - smoothstep(0.84, 0.98, r));
	float inner = (1.0 - smoothstep(0.1, 0.9, r)) * 0.16;
	float pulse = 0.7 + 0.3 * sin(TIME * 3.2);
	ALBEDO = ring_color.rgb * clamp((ring * pulse + inner) * ring_color.a, 0.0, 1.0);
}
"""

static var _rim_shader: Shader = null
static var _bar_shader: Shader = null
static var _bar_material: ShaderMaterial = null
static var _ring_shader: Shader = null
static var _ring_materials: Dictionary = {}
static var _bar_meshes: Dictionary = {}
static var _aura_mesh: QuadMesh = null
static var _aura_materials: Dictionary = {}
static var _dot_texture: GradientTexture2D = null

var model: Node3D = null
var anim: AnimationPlayer = null
## Reference run speed of the model's run cycle (m/s).
var ref_run_speed := 5.0
## Model height (m, after scaling).
var height := 1.8
var model_id := ""

var _size := 1.0
var _base_scale := 1.0
var _action := ""
var _action_left := 0.0
var _loco := ""
var _dead := false
var _overlay: ShaderMaterial = null
var _overlay_on := false
var _rim := Color(0, 0, 0, 0)
var _highlight := false
var _flash := 0.0
var _flash_color := Color.WHITE
var _punch := 0.0
var _geoms: Array[GeometryInstance3D] = []
var _bar_root: Node3D = null
var _bar: MeshInstance3D = null
var _label: Label3D = null
var _bar_shown := false
var _bar_color := Color(0.78, 0.1, 0.08)
var _fill := 1.0
var _trail := 1.0
var _trail_hold := 0.0
var _ring: MeshInstance3D = null
var _aura: GPUParticles3D = null
var _rise := 0.0
var _rise_total := 0.0
var _frozen := false
var _enrage_aura: GPUParticles3D = null
var _loco_speed := -1.0
var _idle_speed := 1.0


## Build everything. opts: "rarity" (int), "size" (scale multiplier on top of def.scale),
## "name" (label text, "" = none), "name_color", "always_bar", "aura_color" (Color, a = 0: none),
## "bar_width".
func build(def: Dictionary, opts: Dictionary) -> void:
	name = "Visuals"
	_size = float(opts.get("size", 1.0))
	model_id = String(def.get("model", "char_skeleton"))
	ref_run_speed = EnemyDB.get_model_run_speed(model_id)
	height = float(def.get("height", 1.8)) * float(def.get("scale", 1.0)) * _size
	model = Assets.model(model_id)
	model.name = "Model"
	_base_scale = float(def.get("scale", 1.0)) * _size
	model.scale = Vector3.ONE * _base_scale
	add_child(model)
	var tint: Color = def.get("tint", Color.WHITE)
	if tint != Color.WHITE:
		Assets.tint(model, tint)
	var attach: Dictionary = def.get("attach", {})
	for bone in attach:
		var item := Assets.model(String(attach[bone]))
		item.name = "Carried_" + String(bone)
		var at: Color = def.get("attach_tint", Color.WHITE)
		if at != Color.WHITE:
			Assets.tint(item, at)
		Assets.attach_to_bone(model, String(bone), item)
	anim = Assets.prepare_animations(model)
	_collect_geoms()
	for g in _geoms:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Desynchronise packs: random idle phase and a slightly different idle tempo per monster.
	_idle_speed = randf_range(0.88, 1.12)
	_play_loco("idle", _idle_speed, true)
	if anim != null and anim.has_animation("idle"):
		anim.seek(randf() * anim.get_animation("idle").length, true)
	# Rarity look.
	var rarity := int(opts.get("rarity", 0))
	match rarity:
		1:
			_rim = MAGIC_RIM
		2:
			_rim = RARE_RIM
		3:
			_rim = BOSS_RIM
	if rarity >= 2:
		_add_ring(UIStyle.rarity_color(rarity), float(def.get("radius", 0.45)) * _size)
	var aura: Color = opts.get("aura_color", Color(0, 0, 0, 0))
	if aura.a > 0.0:
		_add_aura(aura)
	_build_bar(float(opts.get("bar_width", 1.15)), String(opts.get("name", "")), opts.get("name_color", Color.WHITE),
		NAME_FONT_SIZES[clampi(rarity, 0, 3)], BAR_HEIGHTS[clampi(rarity, 0, 3)])
	if bool(opts.get("always_bar", false)):
		show_bar()
	_apply_overlay()


## Per-frame update: locomotion animation from the current horizontal speed, action timers,
## flash / punch decay, life bar fill + trail.
## frozen: the pose holds still (animation paused) until the freeze ends.
func tick(delta: float, speed: float, life_ratio: float, frozen: bool = false) -> void:
	if frozen != _frozen and not _dead:
		_frozen = frozen
		if anim != null:
			if frozen:
				anim.pause()
			else:
				anim.play()
				_loco = ""
	if not _frozen:
		if _action != "":
			if _action_left > 0.0:
				_action_left -= delta
				if _action_left <= 0.0:
					_action = ""
		if _action == "" and not _dead:
			if speed > RUN_THRESHOLD:
				_play_loco("run", clampf(speed / maxf(0.5, ref_run_speed), 0.35, 2.5))
			else:
				_play_loco("idle", _idle_speed)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - FLASH_DECAY * delta)
		if _overlay != null:
			_overlay.set_shader_parameter("flash", _flash)
		if _flash <= 0.0:
			_apply_overlay()
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - PUNCH_DECAY * delta)
		_apply_punch()
	if _rise > 0.0:
		_rise = maxf(0.0, _rise - delta)
		var k := 1.0 - _rise / maxf(0.01, _rise_total)
		model.position.y = -height * 0.9 * pow(1.0 - k, 2.0)
	_update_bar(delta, life_ratio)


## Play an action animation lasting `duration` seconds (<= 0: loop until stop_action()).
## Returns false if the model has no such animation (nor a fallback).
func play_action(anim_name: String, duration: float) -> bool:
	if _dead or _frozen:
		return false
	var a := _resolve(anim_name)
	if a == "" or anim == null:
		_action = ""
		return false
	var length := anim.get_animation(a).length
	var speed := 1.0
	if duration > 0.0 and length > 0.0:
		speed = length / duration
	anim.speed_scale = 1.0
	anim.play(a, ACTION_BLEND, speed)
	if duration > 0.0:
		# Restart when the same one-shot is played again.
		anim.seek(0.0, true)
	_action = a
	_action_left = duration if duration > 0.0 else -1.0
	_loco = ""
	return true


## Summoned monsters: climb out of the ground over `duration` seconds.
func play_rise(duration: float) -> void:
	if model == null or duration <= 0.0:
		return
	_rise = duration
	_rise_total = duration
	model.position.y = -height * 0.9


func is_rising() -> bool:
	return _rise > 0.0


## Back to idle/run immediately.
func stop_action() -> void:
	_action = ""
	_action_left = 0.0


func get_action() -> String:
	return _action


func play_die() -> void:
	_dead = true
	_frozen = false
	set_enraged(false)
	_action = "die"
	_action_left = -1.0
	if anim != null and anim.has_animation("die"):
		anim.speed_scale = 1.0
		anim.play("die", 0.1, 1.0)
	hide_overhead()
	_rim = Color(0, 0, 0, 0)
	_highlight = false
	_apply_overlay()
	if _ring != null:
		_ring.visible = false
	if _aura != null:
		_aura.emitting = false


## Hit feedback: white flash on the whole model and a small scale punch.
func flash(amount: float = 0.85, color: Color = Color.WHITE) -> void:
	if _dead:
		return
	_flash = maxf(_flash, clampf(amount, 0.0, 1.0))
	_flash_color = color
	_punch = 1.0
	_apply_overlay()


## Rarity rim colour (a = strength); Color(0,0,0,0) removes it.
func set_rim(color: Color) -> void:
	_rim = color
	_apply_overlay()


func get_rim() -> Color:
	return _rim


## Boss enrage look: a red rim and rising embers (off restores the rarity rim given).
func set_enraged(on: bool, rim_after: Color = Color(0, 0, 0, 0)) -> void:
	if on:
		set_rim(ENRAGE_RIM)
		if _enrage_aura == null:
			_enrage_aura = _make_particles(ENRAGE_RIM, 36, 0.75 * _size * maxf(1.0, height / 2.2), 1.2)
			_enrage_aura.name = "EnrageAura"
			add_child(_enrage_aura)
	else:
		if _enrage_aura != null:
			_enrage_aura.queue_free()
			_enrage_aura = null
		if not _dead:
			set_rim(rim_after)


func is_enraged_look() -> bool:
	return _enrage_aura != null


## Mouse-over highlight (a bright rim).
func set_highlight(on: bool) -> void:
	if _highlight == on:
		return
	_highlight = on
	_apply_overlay()


## Show the overhead life bar (+ name).
func show_bar() -> void:
	if _dead or _bar_root == null:
		return
	_bar_shown = true
	_bar_root.visible = true


func is_bar_visible() -> bool:
	return _bar_shown and _bar_root != null and _bar_root.visible


func hide_overhead() -> void:
	_bar_shown = false
	if _bar_root != null:
		_bar_root.visible = false


func set_name_text(text: String, color: Color) -> void:
	if _label == null:
		return
	_label.text = text
	_label.modulate = color
	_label.visible = text != ""


## AnimationPlayer / particles on or off (sleeping enemies).
func set_active(on: bool) -> void:
	if anim != null:
		anim.active = on
	if _aura != null and not _dead:
		_aura.emitting = on


## Corpse fade: 0 opaque .. 1 invisible, sinking a little into the floor.
func set_fade(t: float) -> void:
	if model == null:
		return
	Assets.set_fade(model, t)
	model.position.y = -0.45 * t


func has_overlay() -> bool:
	return _overlay_on


# ------------------------------------------------------------------ internals

func _collect_geoms() -> void:
	_geoms.clear()
	for n in model.find_children("*", "GeometryInstance3D", true, false):
		if n is Label3D or n is GPUParticles3D:
			continue
		_geoms.append(n as GeometryInstance3D)
	if model is GeometryInstance3D:
		_geoms.append(model as GeometryInstance3D)


func _resolve(anim_name: String) -> String:
	if anim == null:
		return ""
	if anim.has_animation(anim_name):
		return anim_name
	var fb := String(ANIM_FALLBACKS.get(anim_name, ""))
	if fb != "" and anim.has_animation(fb):
		return fb
	return ""


func _play_loco(anim_name: String, speed: float, force: bool = false) -> void:
	if anim == null:
		return
	# Fast path (every frame): same cycle, nearly the same speed.
	if _loco == anim_name and not force and absf(_loco_speed - speed) < 0.02:
		return
	if anim_name == "run" and not anim.has_animation("run"):
		anim_name = "idle"
	if not anim.has_animation(anim_name):
		return
	anim.speed_scale = speed
	_loco_speed = speed
	if _loco == anim_name and not force and anim.is_playing():
		return
	_loco = anim_name
	anim.play(anim_name, LOCO_BLEND, 1.0)


func _apply_punch() -> void:
	var k := 1.0 + 0.07 * _punch * _punch
	model.scale = Vector3(_base_scale * k, _base_scale * (1.0 + 0.03 * _punch * _punch), _base_scale * k)


func _apply_overlay() -> void:
	var rim := _rim
	if _highlight:
		rim = Color(1.0, 0.95, 0.85, 1.2) if rim.a <= 0.0 else Color(rim.r, rim.g, rim.b, rim.a + 0.8)
	var want := rim.a > 0.0 or _flash > 0.0
	if want:
		if _overlay == null:
			if _rim_shader == null:
				_rim_shader = Shader.new()
				_rim_shader.code = RIM_SHADER
			_overlay = ShaderMaterial.new()
			_overlay.shader = _rim_shader
		_overlay.set_shader_parameter("rim_color", rim)
		_overlay.set_shader_parameter("flash", _flash)
		_overlay.set_shader_parameter("flash_color", _flash_color)
	if want == _overlay_on:
		return
	_overlay_on = want
	for g in _geoms:
		if is_instance_valid(g):
			g.material_overlay = _overlay if want else null


func _build_bar(width: float, text: String, color: Color, font_size: int = 30, bar_height: float = BAR_HEIGHT) -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "Overhead"
	_bar_root.position = Vector3(0, height + BAR_OFFSET, 0)
	add_child(_bar_root)
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = BAR_SHADER
		_bar_material = ShaderMaterial.new()
		_bar_material.shader = _bar_shader
		_bar_material.render_priority = 10
	var w := snappedf(width, 0.05)
	var key := "%.2f|%.2f" % [w, bar_height]
	if not _bar_meshes.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(w, bar_height)
		_bar_meshes[key] = q
	_bar = MeshInstance3D.new()
	_bar.name = "LifeBar"
	_bar.mesh = _bar_meshes[key]
	_bar.material_override = _bar_material
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.set_instance_shader_parameter("aspect", w / bar_height)
	_bar.set_instance_shader_parameter("bar_color", _bar_color)
	_bar_root.add_child(_bar)
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.0075
	_label.font_size = font_size
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.render_priority = 12
	_label.outline_render_priority = 11
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.position = Vector3(0, bar_height * 0.5 + 0.02, 0)
	_label.shaded = false
	_label.double_sided = true
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(_label)
	set_name_text(text, color)
	_bar_root.visible = false


func _update_bar(delta: float, life_ratio: float) -> void:
	if _bar == null:
		return
	var r := clampf(life_ratio, 0.0, 1.0)
	if r < _fill:
		# Took damage: the trail holds a moment, then slides down.
		if _trail < _fill:
			_trail = _fill
		_trail_hold = TRAIL_DELAY
	_fill = r
	if _trail > _fill:
		if _trail_hold > 0.0:
			_trail_hold -= delta
		else:
			_trail = maxf(_fill, _trail - TRAIL_SPEED * delta)
	else:
		_trail = _fill
	if _bar_shown:
		_bar.set_instance_shader_parameter("fill", _fill)
		_bar.set_instance_shader_parameter("trail", _trail)


func _add_ring(color: Color, radius: float) -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	var key := color.to_html()
	if not _ring_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = _ring_shader
		m.set_shader_parameter("ring_color", Color(color.r, color.g, color.b, 0.85))
		_ring_materials[key] = m
	var pm := PlaneMesh.new()
	var d := maxf(1.2, radius * 3.4)
	pm.size = Vector2(d, d)
	_ring = MeshInstance3D.new()
	_ring.name = "RarityRing"
	_ring.mesh = pm
	_ring.material_override = _ring_materials[key]
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 0.04, 0)
	add_child(_ring)


## Soft round dot (radial gradient) for particles.
static func _soft_dot() -> GradientTexture2D:
	if _dot_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.75))
		_dot_texture = GradientTexture2D.new()
		_dot_texture.gradient = g
		_dot_texture.fill = GradientTexture2D.FILL_RADIAL
		_dot_texture.fill_from = Vector2(0.5, 0.5)
		_dot_texture.fill_to = Vector2(1.0, 0.5)
		_dot_texture.width = 32
		_dot_texture.height = 32
	return _dot_texture


func _add_aura(color: Color) -> void:
	_aura = _make_particles(color, 14, 0.42 * _size, 0.9)
	_aura.name = "ModAura"
	add_child(_aura)


## Soft rising particles around the body (mod auras, enrage).
func _make_particles(color: Color, amount: int, radius: float, lifetime: float) -> GPUParticles3D:
	if _aura_mesh == null:
		_aura_mesh = QuadMesh.new()
		_aura_mesh.size = Vector2(0.2, 0.2)
	var key := color.to_html()
	if not _aura_materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1.0)
		m.albedo_texture = _soft_dot()
		m.disable_receive_shadows = true
		_aura_materials[key] = m
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.4
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, height + 2.0, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.gravity = Vector3(0, 1.4, 0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.45
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _aura_mesh
	p.material_override = _aura_materials[key]
	p.position = Vector3(0, height * 0.45, 0)
	return p

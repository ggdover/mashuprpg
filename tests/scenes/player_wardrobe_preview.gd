extends Node3D
## Windowed preview of the player models (tools/blender/player): every look in its default outfit and
## wearing every gear family / tier, through the game's own PlayerVisuals (gear pieces, hides, item
## tints), with game-like lighting. Screenshots go to docs/screenshots/player/:
##   looks              the three looks (f, m1, m2) in the default outfit, front / 3/4 / side / back
##   looks_game         the same from the in-game camera
##   <fam>_t<tier>      each look wearing the family's full set of that tier (front 3/4 + back 3/4)
##   game_<fam>         tiers 1-3 of a family side by side from the in-game camera
##   mixed              mixed sets (helmet / body / gloves / boots from different families)
##   poses_<look>       key animation poses (run, walk, slash, slam, bow, cast, dodge, parry, die)
## Run:  GTEST_WINDOWED=1 tools/gtest.sh player res://tests/scenes/player_wardrobe_preview.tscn
##       [-- --shots=looks,str_t1]   (headless runs build every setup but skip the captures)

const PlayerVisuals := preload("res://scripts/entities/player/player_visuals.gd")

const SHOT_DIR := "/docs/screenshots/player/"
const LOOKS: Array[String] = ["f", "m1", "m2"]
const FAMILIES: Array[String] = ["str", "dex", "int"]
## Base tier used for each gear look tier (PlayerGear: base 1-2 -> 1, 3-4 -> 2, 5-6 -> 3).
const TIER_BASE := {1: 1, 2: 3, 3: 5}
## The family's weapon (+ off-hand) in the shots.
const FAMILY_WEAPONS := {"str": ["sword_1", "shield_str_1"], "dex": ["bow_1", "quiver_1"], "int": ["staff_1", ""]}
const POSES := [["run", 0.25], ["walk", 0.25], ["attack_slash", 0.45], ["attack_slam", 0.55], ["shoot_bow", 0.55],
	["cast", 0.5], ["cast_area", 0.5], ["dodge", 0.3], ["parry", 0.6], ["die", 1.0]]

var cam: Camera3D
var stage: Node3D
var ui_layer: CanvasLayer
var shots: Array[String] = []
var capture := false


func _ready() -> void:
	get_tree().create_timer(60).timeout.connect(get_tree().quit)
	capture = DisplayServer.get_name() != "headless"
	shots = _all_shots()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots.assign(a.substr(8).split(",", false))
	_build_env()
	_run.call_deferred()


func _all_shots() -> Array[String]:
	var out: Array[String] = ["looks", "looks_game"]
	for fam in FAMILIES:
		for t in [1, 2, 3]:
			out.append("%s_t%d" % [fam, t])
	for fam in FAMILIES:
		out.append("game_" + fam)
	out.append("mixed")
	for l in LOOKS:
		out.append("poses_" + l)
	return out


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.3, 0.31)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.72)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.7, 0.95)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-25, 150, 0)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.35, 0.33)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)


func _run() -> void:
	for s in shots:
		stage = Node3D.new()
		stage.name = "Stage_" + s
		add_child(stage)
		if s == "looks":
			_shot_looks(false)
		elif s == "looks_game":
			_shot_looks(true)
		elif s == "mixed":
			_shot_mixed()
		elif s.begins_with("game_"):
			_shot_game(s.substr(5))
		elif s.begins_with("poses_"):
			_shot_poses(s.substr(6))
		elif s.length() == 6 and s.substr(3, 2) == "_t":
			_shot_set(s.substr(0, 3), int(s.substr(5)))
		else:
			push_warning("unknown shot " + s)
		for i in 6:
			await get_tree().process_frame
		await _capture(s)
		stage.queue_free()
		for c in ui_layer.get_children():
			c.queue_free()
		await get_tree().process_frame
	print("[wardrobe] done: ", shots)
	get_tree().quit()


func _capture(shot_name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("GTEST_REPO") + SHOT_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + shot_name + ".png")
	print("[wardrobe] saved ", dir + shot_name + ".png")


# ------------------------------------------------------------------ helpers

## A character of `look` wearing `bases` (equipment slot -> base id; "" = empty).
func _character(look: String, bases: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.class_id = "warrior" if look.begins_with("m") else "ranger"
	c.appearance = look
	for slot in bases:
		var b := String(bases[slot])
		if b != "":
			c.equipment[slot] = ItemDB.create_item(b, Item.Rarity.NORMAL, 1)
	return c


## PlayerVisuals of `look` at pos, facing yaw_deg, holding `anim` at frac of its length.
func _spawn(look: String, bases: Dictionary, pos: Vector3, yaw_deg: float = 0.0, anim: String = "idle", frac: float = 0.3) -> PlayerVisuals:
	var v := PlayerVisuals.new()
	stage.add_child(v)
	v.position = pos
	v.rotation_degrees.y = yaw_deg
	v.build(look)
	v.apply_equipment(_character(look, bases))
	if v.anim != null and v.anim.has_animation(anim):
		v.anim.play(anim)
		v.anim.seek(frac * v.anim.get_animation(anim).length, true)
		v.anim.pause()
	return v


func _set_bases(fam: String, tier: int) -> Dictionary:
	var bt: int = TIER_BASE[tier]
	var w: Array = FAMILY_WEAPONS[fam]
	return {"helmet": "helmet_%s_%d" % [fam, bt], "body": "body_%s_%d" % [fam, bt], "gloves": "gloves_%s_%d" % [fam, bt],
		"boots": "boots_%s_%d" % [fam, bt], "main_hand": w[0], "off_hand": w[1]}


func _ortho(center: Vector3, size: float, yaw_deg: float = 0.0, pitch_deg: float = -8.0) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	var dir := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)) * Vector3(0, 0, 1)
	cam.position = center + dir * 30.0
	cam.look_at(center, Vector3.UP)


## Orthographic front-ish view fitting x in [x0, x1] (figures ~1.9 m tall) with a margin.
func _fit(x0: float, x1: float, yaw_deg: float = 0.0, pitch_deg: float = -8.0) -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	var width := x1 - x0 + 1.4
	_ortho(Vector3((x0 + x1) * 0.5, 0.95, 0), maxf(2.6, width / aspect), yaw_deg, pitch_deg)


func _game_cam(center: Vector3) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 45.0
	var yaw := deg_to_rad(37.5)
	var pitch := deg_to_rad(49.4)
	var d := 19.5 * 0.55
	cam.position = center + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
	cam.look_at(center + Vector3(0, 0.9, 0), Vector3.UP)


func _label(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	ui_layer.add_child(l)


# ------------------------------------------------------------------ shots

func _shot_looks(game: bool) -> void:
	var x := 0.0
	for l in LOOKS:
		for yaw in [0.0, 90.0, 180.0]:
			_spawn(l, {}, Vector3(x, 0, 0), yaw)
			x += 0.85
		x += 0.45
	if game:
		_game_cam(Vector3(x * 0.5, 0, 0))
	else:
		_fit(0.0, x - 1.3)
		_label("f (ranger / sorcerer)  ·  m1 (warrior)  ·  m2 (warrior, 2nd look): front, side, back", Vector2(30, 20))


func _shot_set(fam: String, tier: int) -> void:
	var x := 0.0
	for l in LOOKS:
		_spawn(l, _set_bases(fam, tier), Vector3(x, 0, 0), 30.0)
		_spawn(l, _set_bases(fam, tier), Vector3(x + 0.95, 0, 0), 150.0)
		x += 2.1
	_fit(0.0, x - 1.15)
	_label("%s tier %d (base tier %d)" % [fam.to_upper(), tier, TIER_BASE[tier]], Vector2(30, 20))


func _shot_game(fam: String) -> void:
	var x := -3.0
	for tier in [1, 2, 3]:
		_spawn("f" if fam != "str" else "m1", _set_bases(fam, tier), Vector3(x, 0, 0), 20.0, "run", 0.2)
		_spawn("m2", _set_bases(fam, tier), Vector3(x + 1.0, 0, 0.6), 200.0, "idle", 0.3)
		x += 2.4
	_game_cam(Vector3(0, 0, 0))
	_label("%s tiers 1 / 2 / 3 (game camera)" % fam.to_upper(), Vector2(30, 20))


func _shot_mixed() -> void:
	var sets := [
		{"helmet": "helmet_str_3", "body": "body_dex_1", "gloves": "gloves_int_5", "boots": "boots_str_1"},
		{"helmet": "helmet_int_5", "body": "body_str_5", "gloves": "gloves_dex_3", "boots": "boots_int_1"},
		{"helmet": "helmet_dex_1", "body": "body_int_3", "gloves": "", "boots": "boots_dex_5"},
		{"helmet": "", "body": "body_str_1", "gloves": "gloves_str_1", "boots": ""},
	]
	var x := 0.0
	for i in sets.size():
		var l: String = LOOKS[i % LOOKS.size()]
		_spawn(l, sets[i], Vector3(x, 0, 0), 25.0)
		_spawn(l, sets[i], Vector3(x + 0.95, 0, 0), 155.0)
		x += 2.05
	_fit(0.0, x - 1.1)
	_label("mixed sets", Vector2(30, 20))


func _shot_poses(look: String) -> void:
	var x := -4.5
	var z := 0.0
	for i in POSES.size():
		var p: Array = POSES[i]
		var anim := String(p[0])
		var fam := "dex" if anim == "shoot_bow" else ("int" if anim.begins_with("cast") else "str")
		var bases := _set_bases(fam, 1)
		if anim == "attack_slam":
			bases["main_hand"] = "maul_1"
			bases["off_hand"] = ""
		_spawn(look, bases, Vector3(x, 0, z), 35.0, anim, float(p[1]))
		x += 1.9
		if i == 4:
			x = -4.5
			z = 2.6
	_ortho(Vector3(-0.7, 0.8, 1.3), 6.0, 35.0, -22.0)
	_label("%s: run, walk, slash, slam, bow / cast, cast_area, dodge, parry, die" % look, Vector2(30, 20))

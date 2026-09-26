extends Node3D
## Windowed preview of the assets-characters module (docs/ARCHITECTURE.md §14.5): renders
## screenshots into docs/screenshots/assets-characters/ with game-like lighting (warm key light,
## dim cool ambient, a warm light above the models, dark stone floor):
##   lineup        every character in idle (orthographic 3/4 view)
##   lineup_game   the same from the in-game camera (pitch 56, distance 18, FOV 45)
##   weapons       char_player holding every weapon type (+ shield / focus / quiver), idle
##   weapons_side  the same from the side
##   helmets       helmets on char_player + quiver from behind
##   poses_a/b     char_player key poses (seeked to the hit frame / mid animation)
##   monsters_a/b  every monster in idle, run, slash, slam, cast, die
##   items         every item model (upright, normalised size)   items_ground  lying like GroundItem
##   icons         every item icon at 128 and 48 px              closeups      grip checks
##   turn_<id>     one character from four sides (front, 3/4, side, back) in idle
##   gait          every walking character's run from the side at 4 phases (feet planted on y = 0)
##   corpses       every character's final die pose from the game camera angle
##   slam          char_gravebreaker attack_slam around the hit frame (maul on the floor), side view
## Run:  GTEST_WINDOWED=1 tools/gtest.sh assets-characters res://tests/scenes/assets_characters_preview.tscn
##       [-- --shots=lineup,weapons]   (headless runs build every setup but skip the captures)

const SHOT_DIR := "/docs/screenshots/assets-characters/"
const CHARS: Array[String] = ["char_player", "char_skeleton", "char_zombie", "char_ghoul", "char_cultist",
	"char_brute", "char_lich", "char_gravebreaker", "char_merchant"]
const ITEMS: Array[String] = ["weapon_sword", "weapon_greatsword", "weapon_axe", "weapon_greataxe", "weapon_mace",
	"weapon_maul", "weapon_dagger", "weapon_wand", "weapon_staff", "weapon_bow", "weapon_crossbow",
	"offhand_shield", "offhand_focus", "offhand_quiver", "armor_helmet_str", "armor_helmet_dex", "armor_helmet_int",
	"armor_body", "armor_gloves", "armor_boots", "jewel_ring", "jewel_amulet", "jewel_belt", "loot_gold",
	"loot_potion_life", "loot_potion_mana"]
const ALL_SHOTS: Array[String] = ["lineup", "lineup_game", "weapons", "weapons_side", "helmets", "poses_a",
	"poses_b", "monsters_a", "monsters_b", "items", "items_ground", "icons", "closeups", "turn_player", "turn_skeleton",
	"turn_zombie", "turn_ghoul", "turn_cultist", "turn_brute", "turn_lich", "turn_gravebreaker", "turn_merchant",
	"gait", "corpses", "slam"]
## Example tints (like ItemDB bases) so the preview shows gear the way the game does.
const BODY_TINTS := [Color(0.6, 0.6, 0.62), Color(0.45, 0.35, 0.22), Color(0.4, 0.32, 0.6)]

var cam: Camera3D
var stage: Node3D
var ui_layer: CanvasLayer
var shots: Array[String] = []
var capture := false


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	capture = DisplayServer.get_name() != "headless"
	shots = ALL_SHOTS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots.assign(a.substr(8).split(",", false))
	_build_env()
	_run.call_deferred()


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.7)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.65, 0.95)
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-30, 150, 0)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.23, 0.22)
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
		match s:
			"lineup":
				_shot_lineup(false)
			"lineup_game":
				_shot_lineup(true)
			"weapons":
				_shot_weapons(false)
			"weapons_side":
				_shot_weapons(true)
			"helmets":
				_shot_helmets()
			"poses_a":
				_shot_poses(0)
			"poses_b":
				_shot_poses(1)
			"monsters_a":
				_shot_monsters(["char_skeleton", "char_zombie", "char_ghoul", "char_cultist"])
			"monsters_b":
				_shot_monsters(["char_brute", "char_lich", "char_gravebreaker"])
			"items":
				_shot_items(false)
			"items_ground":
				_shot_items(true)
			"icons":
				_shot_icons()
			"closeups":
				_shot_closeups()
			"gait":
				_shot_gait()
			"corpses":
				_shot_corpses()
			"slam":
				_shot_slam()
			_:
				if s.begins_with("turn_"):
					_shot_turnaround("char_" + s.substr(5))
				else:
					push_warning("unknown shot " + s)
		for i in 4:
			await get_tree().process_frame
		await _capture(s)
		stage.queue_free()
		for c in ui_layer.get_children():
			c.queue_free()
		await get_tree().process_frame
	print("[preview] done: ", shots)
	get_tree().quit()


func _capture(shot_name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("GTEST_REPO") + SHOT_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + shot_name + ".png")
	print("[preview] saved ", dir + shot_name + ".png")


# ------------------------------------------------------------------ helpers

func _spawn(id: String, pos: Vector3, anim: String = "idle", frac: float = 0.25, yaw_deg: float = 0.0) -> Node3D:
	var m := Assets.model(id)
	stage.add_child(m)
	m.position = pos
	m.rotation_degrees.y = yaw_deg
	_pose(m, anim, frac)
	return m


## Seek `anim` to `frac` of its length and hold it.
func _pose(m: Node3D, anim: String, frac: float) -> void:
	var ap := Assets.prepare_animations(m)
	if ap == null:
		return
	if not ap.has_animation(anim):
		push_warning("%s has no animation %s" % [m.name, anim])
		return
	ap.play(anim)
	ap.seek(frac * ap.get_animation(anim).length, true)
	ap.pause()


func _equip(m: Node3D, main: String, off: String = "", helmet: String = "", body_tint: int = -1) -> void:
	if main != "":
		Assets.attach_to_bone(m, "grip_r", Assets.model(main))
	if off != "":
		var bone := "chest" if off == "offhand_quiver" else "grip_l"
		Assets.attach_to_bone(m, bone, Assets.model(off))
	if helmet != "":
		Assets.attach_to_bone(m, "head", Assets.model(helmet))
		# Plate helmet and hood cover the hair (it would poke through); the circlet shows it.
		var hair := Assets.find_part(m, "Hair")
		if hair and helmet != "armor_helmet_int":
			hair.visible = false
	if body_tint >= 0:
		Assets.tint(m, BODY_TINTS[body_tint % BODY_TINTS.size()], PackedStringArray(["Torso", "Arms"]))
		Assets.tint(m, Color(0.5, 0.38, 0.26), PackedStringArray(["Hands", "Feet"]))


func _label(text: String, pos: Vector3, size: int = 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 8
	l.position = pos
	stage.add_child(l)


func _warm_light(pos: Vector3, rng: float = 10.0, energy: float = 1.0) -> void:
	var o := OmniLight3D.new()
	o.light_color = Color(1.0, 0.75, 0.5)
	o.light_energy = energy
	o.omni_range = rng
	o.position = pos
	stage.add_child(o)


## Orthographic camera looking at `target` from yaw/elevation (degrees); `height` = visible metres.
func _ortho(target: Vector3, height: float, yaw: float = 0.0, elev: float = 15.0) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = height
	var y := deg_to_rad(yaw)
	var e := deg_to_rad(elev)
	var d := Vector3(sin(y) * cos(e), sin(e), cos(y) * cos(e))
	cam.position = target + d * 40.0
	cam.near = 0.1
	cam.far = 200.0
	cam.look_at(target, Vector3.UP)


## The in-game camera (§11.4): perspective, pitch 56 deg down, yaw 0 (looking toward -Z), distance 18.
func _game_camera(target: Vector3, dist: float = 18.0) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var pitch := deg_to_rad(56.0)
	cam.fov = 45.0
	cam.position = target + Vector3(0, sin(pitch), cos(pitch)) * dist
	cam.look_at(target, Vector3.UP)


func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb := m.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


# ------------------------------------------------------------------ shots

func _shot_lineup(game_cam: bool) -> void:
	var widths := {"char_brute": 2.1, "char_lich": 2.4, "char_gravebreaker": 2.8, "char_ghoul": 1.6}
	var x := 0.0
	var xs: Array[float] = []
	for id in CHARS:
		var w: float = widths.get(id, 1.35)
		xs.append(x + w * 0.5)
		x += w
	var total := x
	for i in CHARS.size():
		var id := CHARS[i]
		var px := xs[i] - total * 0.5
		var m := _spawn(id, Vector3(px, 0, 0), "idle", 0.3)
		if id == "char_player":
			_equip(m, "weapon_sword", "offhand_shield", "", 0)
		elif id == "char_skeleton":
			_equip(m, "weapon_sword")
		if not game_cam:
			_label(id.substr(5), Vector3(px, -0.15, 0.8), 36)
	_warm_light(Vector3(0, 5, 4), 30.0, 0.7)
	if game_cam:
		_game_camera(Vector3(0, 0.8, 0), 18.0)
	else:
		_ortho(Vector3(0, 1.45, 0), total / 1.75, 0.0, 10.0)

func _shot_weapons(side: bool) -> void:
	var sets := [
		["weapon_sword", "offhand_shield"], ["weapon_greatsword", ""], ["weapon_axe", "offhand_shield"],
		["weapon_greataxe", ""], ["weapon_mace", "offhand_focus"], ["weapon_maul", ""],
		["weapon_dagger", "offhand_focus"], ["weapon_wand", "offhand_focus"], ["weapon_staff", ""],
		["weapon_bow", "offhand_quiver"], ["weapon_crossbow", "offhand_quiver"], ["", ""],
	]
	for i in sets.size():
		var pos := Vector3(-7.15 + i * 1.3, 0, 0)
		var m := _spawn("char_player", pos, "idle", 0.25, -90.0 if side else 35.0)
		_equip(m, sets[i][0], sets[i][1], "", i)
		_label(String(sets[i][0]).replace("weapon_", ""), pos + Vector3(0, -0.15, 0.8), 30)
	_warm_light(Vector3(0, 5, 3), 25.0, 0.7)
	_ortho(Vector3(0, 1.3, 0), 8.9, 0.0, 12.0)

func _shot_helmets() -> void:
	var sets := ["", "armor_helmet_str", "armor_helmet_dex", "armor_helmet_int"]
	for i in sets.size():
		var pos := Vector3(-1.95 + i * 0.75, 0, 0)
		var m := _spawn("char_player", pos, "idle", 0.25, 25.0)
		_equip(m, "", "", sets[i], i)
	# Quiver + hood from behind, beside the front row (not hidden behind it).
	for i in 2:
		var pos := Vector3(1.2 + i * 0.75, 0, 0)
		var m := _spawn("char_player", pos, "idle", 0.25, 160.0 + i * 50.0)
		_equip(m, "weapon_bow", "offhand_quiver", "armor_helmet_dex", 1)
	_warm_light(Vector3(0, 3.5, 2), 10.0, 0.7)
	_ortho(Vector3(-0.1, 1.25, 0), 2.75, 0.0, 12.0)


func _shot_poses(part: int) -> void:
	# [anim, time fraction, main, off]
	var sets := [
		["idle", 0.3, "weapon_sword", "offhand_shield"], ["run", 0.25, "weapon_sword", "offhand_shield"],
		["run", 0.75, "weapon_bow", "offhand_quiver"], ["attack_slash", 0.3, "weapon_sword", ""],
		["attack_slash", 0.45, "weapon_sword", ""], ["attack_slam", 0.4, "weapon_maul", ""],
		["attack_slam", 0.55, "weapon_maul", ""], ["attack_stab", 0.45, "weapon_dagger", "offhand_shield"],
		["shoot_bow", 0.55, "weapon_bow", "offhand_quiver"], ["shoot_crossbow", 0.3, "weapon_crossbow", "offhand_quiver"],
		["cast", 0.5, "weapon_wand", "offhand_focus"], ["cast_area", 0.35, "weapon_staff", ""],
		["cast_area", 0.55, "weapon_staff", ""], ["channel", 0.5, "weapon_greatsword", ""],
		["hit", 0.25, "weapon_axe", "offhand_shield"], ["dodge", 0.25, "weapon_sword", ""],
		["die", 0.45, "weapon_sword", ""], ["die", 1.0, "weapon_sword", ""],
	]
	var chunk := sets.slice(part * 9, part * 9 + 9)
	for i in chunk.size():
		var pos := Vector3(-7.2 + i * 1.8, 0, 0)
		var m := _spawn("char_player", pos, chunk[i][0], float(chunk[i][1]), -40.0)
		_equip(m, chunk[i][2], chunk[i][3], "", i)
		_label("%s %.2f" % [chunk[i][0], chunk[i][1]], pos + Vector3(0, -0.15, 1.0), 26)
	_warm_light(Vector3(0, 5, 3), 25.0, 0.7)
	_ortho(Vector3(0, 1.2, 0), 9.4, 0.0, 16.0)

func _shot_monsters(ids: Array) -> void:
	var anims := [["idle", 0.3], ["run", 0.25], ["attack_slash", 0.45], ["attack_slam", 0.55], ["cast", 0.5], ["die", 1.0]]
	var z := 0.0
	var rows: Array[float] = []
	for id in ids:
		var big: bool = id in ["char_lich", "char_gravebreaker", "char_brute"]
		rows.append(z)
		z -= 5.6 if big else 3.6
	for r in ids.size():
		var id: String = ids[r]
		var big: bool = id in ["char_lich", "char_gravebreaker"]
		var dx := 3.2 if big else 2.4
		for c in anims.size():
			var pos := Vector3((c - 2.5) * dx, 0, rows[r])
			var m := _spawn(id, pos, anims[c][0], float(anims[c][1]), -35.0)
			if id == "char_skeleton":
				_equip(m, "weapon_sword")
	_warm_light(Vector3(0, 8, 2), 30.0, 0.7)
	var span := -z
	_ortho(Vector3(0, 1.0, z * 0.5 + 1.2), span * 0.62 + 1.2, 0.0, 36.0)

func _shot_items(ground: bool) -> void:
	var pitch := 2.0 if not ground else 1.4
	for i in ITEMS.size():
		var col := i % 7
		var row := i / 7
		var pos := Vector3(-4.2 + col * 1.4, 0, -row * pitch)
		var id: String = ITEMS[i]
		var holder := Node3D.new()
		stage.add_child(holder)
		var m := Assets.model(id)
		holder.add_child(m)
		if ground:
			m.basis = _ground_basis(id)
		var bb: AABB = m.transform * _model_aabb(m)
		var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		var s := 0.9 / maxf(longest, 0.05)
		if ground:
			s = 0.6 / maxf(longest, 0.05)
		holder.scale = Vector3.ONE * s
		holder.position = pos - Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * s
		holder.rotation_degrees.y = 0.0
		_label(id, pos + Vector3(0, -0.02, 0.62), 22)
	_warm_light(Vector3(0, 4, 2), 20.0, 0.7)
	if ground:
		_ortho(Vector3(0, 0.3, -2.1), 6.0, 0.0, 56.0)
	else:
		_ortho(Vector3(0, 0.4, -2.75), 6.9, 0.0, 42.0)


## The orientation GroundItem uses (items module): weapons/quivers on the flat of the blade,
## shields, body armour, gloves and belts on their back, the rest upright.
func _ground_basis(id: String) -> Basis:
	if id.begins_with("weapon_") or id == "offhand_quiver":
		return Basis(Vector3.FORWARD, deg_to_rad(90.0))
	if id in ["offhand_shield", "armor_body", "armor_gloves", "jewel_belt"]:
		return Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	return Basis()


func _shot_icons() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.09, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(bg)
	for i in ITEMS.size():
		var id: String = ITEMS[i]
		var tex := Assets.item_icon(id)
		var col := i % 9
		var row := i / 9
		var origin := Vector2(40 + col * 205, 30 + row * 340)
		var frame := ColorRect.new()
		frame.color = Color(0.2, 0.18, 0.16)
		frame.position = origin
		frame.size = Vector2(140, 140)
		ui_layer.add_child(frame)
		var big := TextureRect.new()
		big.texture = tex
		big.position = origin + Vector2(6, 6)
		big.size = Vector2(128, 128)
		ui_layer.add_child(big)
		var small_frame := ColorRect.new()
		small_frame.color = Color(0.2, 0.18, 0.16)
		small_frame.position = origin + Vector2(40, 150)
		small_frame.size = Vector2(56, 56)
		ui_layer.add_child(small_frame)
		var small := TextureRect.new()
		small.texture = tex
		small.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		small.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		small.position = small_frame.position + Vector2(4, 4)
		small.size = Vector2(48, 48)
		ui_layer.add_child(small)
		var l := Label.new()
		l.text = id
		l.position = origin + Vector2(0, 212)
		l.add_theme_font_size_override("font_size", 17)
		ui_layer.add_child(l)


func _shot_closeups() -> void:
	# Grip checks: sword idle, sword slash hit frame, bow at full draw, wand cast, crossbow aim, staff idle.
	var sets := [["idle", 0.0, "weapon_sword", "offhand_shield"], ["attack_slash", 0.45, "weapon_sword", ""],
		["shoot_bow", 0.57, "weapon_bow", "offhand_quiver"], ["cast", 0.5, "weapon_wand", "offhand_focus"],
		["shoot_crossbow", 0.3, "weapon_crossbow", ""], ["idle", 0.0, "weapon_staff", ""]]
	for i in sets.size():
		var pos := Vector3(-3.75 + i * 1.5, 0, 0)
		var m := _spawn("char_player", pos, sets[i][0], float(sets[i][1]), -55.0)
		_equip(m, sets[i][2], sets[i][3], "", i)
	_warm_light(Vector3(0, 3, 3), 12.0, 0.7)
	_ortho(Vector3(0, 1.2, 0), 5.0, 0.0, 12.0)


func _shot_turnaround(id: String) -> void:
	var h := 1.8
	if id in ["char_lich", "char_gravebreaker"]:
		h = 3.2
	elif id == "char_brute":
		h = 2.4
	var yaws := [0.0, -40.0, -90.0, 160.0]
	for i in yaws.size():
		var pos := Vector3((i - 1.5) * h * 0.72, 0, 0)
		var m := _spawn(id, pos, "idle", 0.3, yaws[i])
		if id == "char_player":
			_equip(m, "weapon_sword", "offhand_shield", "", 0)
	_warm_light(Vector3(0, h * 2.0, 3), 20.0, 0.6)
	_ortho(Vector3(0, h * 0.52, 0), maxf(h * 1.15, h * 0.72 * 4.0 / 1.7), 0.0, 10.0)


## Side view of every walking character's run at 4 phases, one row each (stacked on floor strips):
## planted feet sit on the strip, and all runs share the same planted-foot speed (5.2 m/s).
func _shot_gait() -> void:
	var blocks := [["char_player", "char_skeleton", "char_zombie", "char_ghoul"], ["char_cultist", "char_brute", "char_gravebreaker"]]
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(0.55, 0.5, 0.45)
	for b in blocks.size():
		var bx := -12.2 + b * 12.2
		var y := 0.0
		for id in blocks[b]:
			for c in 4:
				_spawn(id, Vector3(bx + 2.3 + c * 2.45, y, 0), "run", c / 4.0, 90.0)
			var strip := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(11.4, 0.04, 1.2)
			strip.mesh = bm
			strip.material_override = strip_mat
			strip.position = Vector3(bx + 5.9, y - 0.02, 0)
			stage.add_child(strip)
			_label(String(id).substr(5), Vector3(bx + 0.75, y + 0.3, 0.8), 30)
			y += 3.6 if id == "char_gravebreaker" else (3.0 if id == "char_brute" else 2.45)
	_warm_light(Vector3(0, 6, 6), 40.0, 0.6)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 13.6
	cam.position = Vector3(-0.15, 5.4, 40)
	cam.rotation_degrees = Vector3(0, 0, 0)
	cam.near = 0.1
	cam.far = 200.0


## Every character's corpse (die at its end) from the in-game camera angle.
func _shot_corpses() -> void:
	for i in CHARS.size():
		var id := CHARS[i]
		if id == "char_merchant":
			continue
		var pos := Vector3(-7.0 + (i % 4) * 4.6, 0, -1.5 + (i / 4) * 4.2)
		var m := _spawn(id, pos, "die", 1.0, -25.0)
		if id == "char_player":
			_equip(m, "weapon_sword", "offhand_shield", "", 0)
		_label(id.substr(5), pos + Vector3(0, 0, 0.9), 34)
	_warm_light(Vector3(0, 7, 3), 30.0, 0.7)
	_game_camera(Vector3(0, 0, 0.7), 13.5)


## char_gravebreaker attack_slam from the side: wind-up, impact (hit frame 55%), hold, recovery.
func _shot_slam() -> void:
	var fr := [0.4, 0.5, 0.55, 0.64, 0.72, 0.85]
	for i in fr.size():
		var pos := Vector3(-8.0 + i * 2.95, 0, 0)
		_spawn("char_gravebreaker", pos, "attack_slam", fr[i], 90.0)
		_label("%.2f" % fr[i], pos + Vector3(0, -0.2, 1.5), 34)
	_warm_light(Vector3(0, 6, 4), 30.0, 0.7)
	_ortho(Vector3(-0.1, 1.9, 0), 9.6, 0.0, 6.0)

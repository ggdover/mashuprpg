extends Node3D
## Windowed preview of the environment assets (docs/ARCHITECTURE.md §14.5). Builds a few stages
## and saves screenshots to docs/screenshots/assets-environment/:
##   dungeon_room.png        small room at the in-game camera (floors/walls via MultiMesh, pillars,
##                           torches, props, lights, crypt tint)
##   dungeon_room_close.png  same room, closer
##   dungeon_themes.png      the kit tinted crypt / cave / inferno (tint_ materials)
##   dungeon_props.png       the small env_* props in a lineup (torch on a wall block)
##   dungeon_props_large.png chest (closed + opened via Lid), portal, waypoint, pillar, walls
##   wall_base.png           close-up of wall bases, a convex wall corner and a wall stub at the
##                           shallowest in-game camera pitch (no see-through slit / corner holes
##                           with backface culling)
##   world_dungeon.png       a real World dungeon (depth 1, crypt) built by the world module from
##                           these assets (WorldKit shaders, cull back), at the game camera
##   world_cave.png          the same for depth 4 (cave theme)
##   town_lineup.png         the town set in daylight
##   town_close.png          the houses at the in-game camera distance
##   projectiles.png         proj_* (all fly along +Z; red markers show +Z)
##   skill_icons.png         contact sheet of the 24 skill icons at 128 px and 48 px
## Run: GTEST_WINDOWED=1 tools/gtest.sh assets-environment-demo res://tests/scenes/assets_environment_preview.tscn [-- --shots=room,town]
## Headless: builds every stage (catches script/asset errors) but saves nothing.
## OWNER: assets-environment.

const SHOTS: Array[String] = ["room", "room_close", "themes", "props", "props_large", "wall_base", "world_dungeon", "world_cave", "town", "town_close", "projectiles", "icons"]
const SKILL_IDS: Array[String] = [
	"basic_attack", "heavy_strike", "cleave", "ground_slam", "leap_slam", "whirlwind",
	"infernal_blow", "war_cry", "power_shot", "split_arrow", "rain_of_arrows", "explosive_bolt",
	"scatter_shot", "rapid_fire", "ice_shot", "venom_arrow", "fireball", "ice_spear", "frost_nova",
	"chain_lightning", "teleport", "spark", "meteor", "blood_rite",
]
const THEME_TINTS := {
	"crypt": Color(0.78, 0.76, 0.72),
	"cave": Color(0.72, 0.62, 0.5),
	"inferno": Color(0.72, 0.42, 0.36),
}
const TILE := 2.0

var _stage: Node3D = null
var _ui: CanvasLayer = null
var _headless := false


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	_headless = DisplayServer.get_name() == "headless"
	_run.call_deferred()


func _run() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			only = a.substr(8).split(",", false)
	for shot in SHOTS:
		if not only.is_empty() and not (shot in only):
			continue
		_clear()
		call("_stage_" + shot)
		for i in 6:
			await get_tree().process_frame
		await _capture(shot)
	print("[assets_environment_preview] done")
	get_tree().quit()


func _clear() -> void:
	if _stage != null:
		_stage.free()
	if _ui != null:
		_ui.free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	_ui = null


func _capture(shot: String) -> void:
	if _headless:
		print("[assets_environment_preview] headless: skipping screenshot ", shot)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("GTEST_REPO")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://")
	dir = dir.path_join("docs/screenshots/assets-environment")
	DirAccess.make_dir_recursive_absolute(dir)
	var names := {"room": "dungeon_room", "room_close": "dungeon_room_close", "themes": "dungeon_themes",
		"props": "dungeon_props", "props_large": "dungeon_props_large", "wall_base": "wall_base", "world_dungeon": "world_dungeon", "world_cave": "world_cave", "town": "town_lineup", "town_close": "town_close", "projectiles": "projectiles",
		"icons": "skill_icons"}
	var path := dir.path_join(String(names.get(shot, shot)) + ".png")
	img.save_png(path)
	print("[assets_environment_preview] saved ", path)


# ------------------------------------------------------------------ shared helpers

func _cell_center(i: int, j: int) -> Vector3:
	return Vector3((i + 0.5) * TILE, 0.0, (j + 0.5) * TILE)


func _tinted_mesh(id: String, tint: Color) -> Mesh:
	var src := Assets.mesh(id)
	var m := src.duplicate() as Mesh
	if m is ArrayMesh:
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat is BaseMaterial3D and mat.resource_name.begins_with("tint"):
				var t := mat.duplicate() as BaseMaterial3D
				t.albedo_color = t.albedo_color * tint
				m.surface_set_material(s, t)
	return m


func _multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


func _place(id: String, pos: Vector3, yaw_deg: float = 0.0, parent: Node3D = null, tint: Color = Color.WHITE) -> Node3D:
	var m := Assets.model(id)
	m.position = pos
	m.rotation.y = deg_to_rad(yaw_deg)
	(parent if parent != null else _stage).add_child(m)
	if tint != Color.WHITE:
		Assets.tint(m, tint)
	return m


func _omni(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	_stage.add_child(l)
	return l


func _game_camera(target: Vector3, distance: float = 18.0, pitch_deg: float = 56.0, yaw_deg: float = 0.0, fov: float = 45.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	_stage.add_child(cam)
	cam.look_at_from_position(target + offset, target, Vector3.UP)
	cam.current = true
	return cam


func _dungeon_env(fog_color: Color = Color(0.05, 0.05, 0.07)) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.33, 0.4)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.8)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-62, 28, 0)
	_stage.add_child(moon)


func _day_env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.42)
	sky_mat.ground_bottom_color = Color(0.25, 0.22, 0.18)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.rotation_degrees = Vector3(-50, 35, 0)
	_stage.add_child(sun)


func _ground(size: Vector2, color: Color, center: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = center + Vector3(0, -0.005, 0)
	_stage.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, size: int = 48, color: Color = Color(1, 0.95, 0.8)) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	_stage.add_child(l)


# ------------------------------------------------------------------ dungeon room

## Room layout (cells): '#' wall, '.' floor, 'P' pillar on floor, ' ' void.
const ROOM := [
	"###########",
	"#.........#",
	"#.P.....P.#",
	"#.........###",
	"#...........#",
	"#.........###",
	"#.P.....P.#",
	"#.........#",
	"###########",
]


func _room_cells(layout: Array) -> Dictionary:
	var floors: Array[Vector2i] = []
	var walls: Array[Vector2i] = []
	var pillars: Array[Vector2i] = []
	for j in layout.size():
		var row: String = layout[j]
		for i in row.length():
			var ch := row[i]
			if ch == "#":
				walls.append(Vector2i(i, j))
			elif ch == "." or ch == "P":
				floors.append(Vector2i(i, j))
				if ch == "P":
					pillars.append(Vector2i(i, j))
	return {"floors": floors, "walls": walls, "pillars": pillars}


func _build_kit(layout: Array, origin: Vector3, tint: Color, seed_value: int) -> Dictionary:
	var cells := _room_cells(layout)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var floor_x: Dictionary = {"env_floor_a": [] as Array[Transform3D], "env_floor_b": [] as Array[Transform3D], "env_floor_c": [] as Array[Transform3D]}
	for c: Vector2i in cells["floors"]:
		var r := rng.randf()
		var id := "env_floor_a" if r < 0.45 else ("env_floor_b" if r < 0.8 else "env_floor_c")
		var b := Basis(Vector3.UP, deg_to_rad(90.0 * rng.randi_range(0, 3)))
		(floor_x[id] as Array[Transform3D]).append(Transform3D(b, origin + _cell_center(c.x, c.y)))
	var wall_x: Dictionary = {"env_wall_a": [] as Array[Transform3D], "env_wall_b": [] as Array[Transform3D]}
	for c: Vector2i in cells["walls"]:
		var id := "env_wall_a" if rng.randf() < 0.6 else "env_wall_b"
		var b := Basis(Vector3.UP, deg_to_rad(90.0 * rng.randi_range(0, 3)))
		(wall_x[id] as Array[Transform3D]).append(Transform3D(b, origin + _cell_center(c.x, c.y)))
	for id in floor_x:
		_stage.add_child(_multimesh(_tinted_mesh(id, tint), floor_x[id]))
	for id in wall_x:
		_stage.add_child(_multimesh(_tinted_mesh(id, tint), wall_x[id]))
	var pillar_x: Array[Transform3D] = []
	for c: Vector2i in cells["pillars"]:
		pillar_x.append(Transform3D(Basis.IDENTITY, origin + _cell_center(c.x, c.y)))
	if not pillar_x.is_empty():
		_stage.add_child(_multimesh(_tinted_mesh("env_pillar", tint), pillar_x))
	return cells


## Torch on the wall cell `w`, facing the floor cell in direction d.
func _torch(origin: Vector3, w: Vector2i, d: Vector2i, light: bool = true) -> void:
	var dir := Vector3(d.x, 0, d.y)
	var pos := origin + _cell_center(w.x, w.y) + dir * (TILE * 0.5)
	_place("env_torch", pos, rad_to_deg(atan2(dir.x, dir.z)))
	if light:
		_omni(pos + dir * 0.45 + Vector3(0, 2.1, 0), Color(1.0, 0.62, 0.3), 2.2, 8.0)


func _stage_room() -> void:
	_dungeon_env()
	var o := Vector3.ZERO
	_build_kit(ROOM, o, THEME_TINTS["crypt"], 7)
	# torches on the north and west/east walls
	_torch(o, Vector2i(3, 0), Vector2i(0, 1))
	_torch(o, Vector2i(7, 0), Vector2i(0, 1))
	_torch(o, Vector2i(0, 4), Vector2i(1, 0))
	_torch(o, Vector2i(10, 1), Vector2i(-1, 0))
	_torch(o, Vector2i(10, 7), Vector2i(-1, 0))
	_torch(o, Vector2i(5, 8), Vector2i(0, -1))
	# props
	_place("env_brazier", _cell_center(5, 4))
	_omni(_cell_center(5, 4) + Vector3(0, 1.4, 0), Color(1.0, 0.55, 0.25), 2.5, 9.0)
	_place("env_crate", _cell_center(1, 1) + Vector3(-0.2, 0, -0.2), 12)
	_place("env_crate", _cell_center(2, 1) + Vector3(-0.3, 0, -0.35), -20)
	_place("env_barrel", _cell_center(1, 2) + Vector3(-0.3, 0, 0))
	_place("env_barrel", _cell_center(9, 1) + Vector3(0.3, 0, -0.3))
	_place("env_bones", _cell_center(4, 6), 40)
	_place("env_rubble", _cell_center(7, 2), 10)
	_place("env_rock_a", _cell_center(9, 6) + Vector3(0.2, 0, 0.1), 30)
	_place("env_rock_b", _cell_center(8, 7), 0)
	_place("env_crystal", _cell_center(1, 7) + Vector3(-0.1, 0, 0.1), 20)
	_omni(_cell_center(1, 7) + Vector3(0.3, 1.2, -0.2), Color(0.35, 0.8, 1.0), 2.0, 7.0)
	var chest := _place("env_chest", _cell_center(3, 1) + Vector3(0, 0, -0.1), 0)
	var chest2 := _place("env_chest", _cell_center(6, 7), 180)
	var lid := Assets.find_part(chest2, "Lid")
	if lid != null:
		lid.rotation.x = -deg_to_rad(110)
	if chest == null:
		push_warning("chest missing")
	_place("env_portal", _cell_center(11, 4) + Vector3(-0.2, 0, 0), -90)
	_omni(_cell_center(11, 4) + Vector3(-1.0, 1.6, 0), Color(0.4, 0.55, 1.0), 1.5, 6.0)
	_game_camera(_cell_center(6, 4) + Vector3(0, 0, 0.5))


func _stage_room_close() -> void:
	_stage_room()
	_game_camera(_cell_center(3, 2) + Vector3(0, 0.5, 0), 9.0)


func _stage_themes() -> void:
	_dungeon_env()
	var small := [
		"#######",
		"#.....#",
		"#.....#",
		"#..P..#",
		"#.....#",
		"#######",
	]
	var k := 0
	for theme in ["crypt", "cave", "inferno"]:
		var o := Vector3(k * 15.0, 0, 0)
		_build_kit(small, o, THEME_TINTS[theme], 3 + k)
		_torch(o, Vector2i(2, 0), Vector2i(0, 1))
		_torch(o, Vector2i(0, 3), Vector2i(1, 0))
		if theme == "cave":
			_place("env_crystal", o + _cell_center(4, 2))
			_omni(o + _cell_center(4, 2) + Vector3(0, 1.2, 0), Color(0.35, 0.8, 1.0), 2.0, 7.0)
			_place("env_rock_a", o + _cell_center(2, 2), 30)
			_place("env_rock_b", o + _cell_center(4, 4), 0)
		elif theme == "inferno":
			_place("env_brazier", o + _cell_center(4, 2))
			_omni(o + _cell_center(4, 2) + Vector3(0, 1.4, 0), Color(1.0, 0.45, 0.2), 2.5, 8.0)
			_place("env_rubble", o + _cell_center(2, 2), 0)
			_place("env_bones", o + _cell_center(4, 4), 70)
		else:
			_place("env_bones", o + _cell_center(2, 2))
			_place("env_rubble", o + _cell_center(4, 4), 0)
			_place("env_chest", o + _cell_center(4, 1) + Vector3(0, 0, -0.2))
		_label(theme, o + Vector3(7, 3.2, 12.6), 64)
		k += 1
	_game_camera(Vector3(21.5, 0, 6.5), 30.0)


func _props_floor(cols: int, rows: int, offset: Vector3) -> void:
	var floors: Array[Transform3D] = []
	for i in cols:
		for j in rows:
			floors.append(Transform3D(Basis.IDENTITY, _cell_center(i, j) + offset))
	_stage.add_child(_multimesh(_tinted_mesh("env_floor_a", THEME_TINTS["crypt"]), floors))


func _stage_props() -> void:
	_dungeon_env()
	_props_floor(12, 4, Vector3(-2, 0, -3))
	var ids := ["env_torch", "env_brazier", "env_crate", "env_barrel", "env_bones", "env_rubble", "env_rock_a", "env_rock_b", "env_crystal"]
	var x := 0.0
	for id in ids:
		var pos := Vector3(x, 0, 0.6)
		if id == "env_torch":
			# on a wall block, as in game
			_place("env_wall_a", pos + Vector3(0, 0, -1.0), 0, null, THEME_TINTS["crypt"])
			_place(id, pos)
			_omni(pos + Vector3(0, 2.2, 0.5), Color(1.0, 0.6, 0.3), 1.5, 5.0)
		else:
			_place(id, pos, 0)
		_label(id.substr(4), pos + Vector3(0, -0.1, 1.4), 30)
		x += 2.0
	_omni(Vector3(4, 3.0, 3), Color(1.0, 0.88, 0.75), 2.5, 14.0)
	_omni(Vector3(13, 3.0, 3), Color(0.9, 0.92, 1.0), 2.5, 14.0)
	_game_camera(Vector3(8.0, 0.3, 1.2), 12.5, 42.0, 0.0, 45.0)


func _stage_props_large() -> void:
	_dungeon_env()
	_props_floor(12, 4, Vector3(-2, 0, -3))
	var ids := ["env_chest", "env_chest", "env_portal", "env_waypoint", "env_pillar", "env_wall_a", "env_wall_b"]
	var x := 0.0
	var n := 0
	for id in ids:
		var pos := Vector3(x, 0, 0.5)
		var m := _place(id, pos, 0, null, THEME_TINTS["crypt"] if id.begins_with("env_wall") or id == "env_pillar" else Color.WHITE)
		var label: String = id.substr(4)
		if id == "env_chest" and n == 1:
			var lid := Assets.find_part(m, "Lid")
			if lid != null:
				lid.rotation.x = -deg_to_rad(110)
			label += " (open)"
		_label(label, pos + Vector3(0, -0.1, 2.6), 30)
		n += 1
		x += 3.6 if id in ["env_portal", "env_waypoint"] else 2.4
	_omni(Vector3(4, 3.5, 3), Color(1.0, 0.85, 0.7), 3.0, 16.0)
	_omni(Vector3(14, 3.5, 3), Color(0.9, 0.9, 1.0), 3.0, 16.0)
	_game_camera(Vector3(9.0, 0.5, 1.0), 15.0, 40.0, 0.0, 45.0)


## Wall bases and corners up close: a room corner, a one-cell wall stub (four convex corners)
## and a corridor mouth, seen at the shallowest pitch of the game camera (56 - 22.5 deg) from a
## short distance, with a bright light so any gap would show the black void.
func _stage_wall_base() -> void:
	_dungeon_env()
	var layout := [
		"#########",
		"#.......#",
		"#.......#",
		"#..#....#",
		"#.......#",
		"#....####",
		"#....#   ",
	]
	_build_kit(layout, Vector3.ZERO, THEME_TINTS["crypt"], 11)
	_omni(_cell_center(3, 4) + Vector3(0.5, 2.2, 1.5), Color(1.0, 0.9, 0.75), 3.0, 9.0)
	_omni(_cell_center(6, 2) + Vector3(0, 2.2, 1.0), Color(0.9, 0.9, 1.0), 2.0, 8.0)
	_game_camera(_cell_center(4, 3) + Vector3(0, 0.3, 0.2), 9.0, 34.0, 18.0, 45.0)


## A real World (world module) built from these assets; camera at the game pitch/distance over
## the player start (the light pool follows the camera focus).
func _stage_world_dungeon() -> void:
	_world_stage(1, 4242)


func _stage_world_cave() -> void:
	_world_stage(4, 777)


func _world_stage(depth: int, seed_value: int) -> void:
	var w := World.new()
	_stage.add_child(w)
	w.build({"id": "dungeon", "depth": depth, "seed": seed_value, "level": depth, "theme": World.theme_for_depth(depth)})
	var start := w.get_player_start()
	RenderingServer.global_shader_parameter_set("player_world_pos", start)
	var cam := Camera3D.new()
	cam.fov = 45.0
	w.add_child(cam)
	var pitch := deg_to_rad(56.0)
	cam.look_at_from_position(start + Vector3(0, sin(pitch), cos(pitch)) * 16.0, start, Vector3.UP)
	cam.current = true
	w.snap_light_pool()


# ------------------------------------------------------------------ town

func _stage_town() -> void:
	_day_env()
	_ground(Vector2(60, 40), Color(0.34, 0.47, 0.22), Vector3(12, 0, 4))
	# dirt path
	var path := _ground(Vector2(44, 3.0), Color(0.45, 0.37, 0.26), Vector3(12, 0.003, 5.5))
	path.name = "Path"
	_place("town_house_a", Vector3(0, 0, -2))
	_place("town_house_b", Vector3(8, 0, -2))
	_place("town_house_c", Vector3(16, 0, -2))
	_place("town_tree_a", Vector3(22.5, 0, -3))
	_place("town_tree_b", Vector3(26, 0, -2))
	_place("town_tree_a", Vector3(-5.5, 0, 1.5), 120)
	for k in 5:
		_place("town_fence", Vector3(21 + k * 2.0, 0, 2.2))
	_place("town_fence", Vector3(31.0, 0, 3.2), 90)
	_place("town_well", Vector3(4, 0, 9))
	_place("town_lamp", Vector3(-2, 0, 4))
	_place("town_lamp", Vector3(12, 0, 4))
	_place("town_stall", Vector3(9, 0, 9.5))
	_place("char_merchant", Vector3(9, 0, 8.8))
	_place("town_stash", Vector3(13, 0, 9.5))
	_place("town_cart", Vector3(17.5, 0, 9.5), -20)
	_place("town_bush", Vector3(-1, 0, 8.5))
	_place("town_bush", Vector3(21, 0, 6.5), 60)
	_place("town_rock", Vector3(1, 0, 11.5))
	_place("env_waypoint", Vector3(25, 0, 9.5))
	_place("env_portal", Vector3(30, 0, 9.5))
	_game_camera(Vector3(13, 0, 4), 34.0, 50.0, 0.0, 45.0)


func _stage_town_close() -> void:
	_stage_town()
	_game_camera(Vector3(9, 0, 3), 18.0)


# ------------------------------------------------------------------ projectiles

func _stage_projectiles() -> void:
	_dungeon_env()
	var floors: Array[Transform3D] = []
	for i in 6:
		for j in 4:
			floors.append(Transform3D(Basis.IDENTITY, _cell_center(i, j) + Vector3(-5, 0, -4)))
	_stage.add_child(_multimesh(_tinted_mesh("env_floor_a", THEME_TINTS["crypt"]), floors))
	var ids := ["proj_arrow", "proj_bolt", "proj_ice_spear", "proj_meteor"]
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(0.9, 0.15, 0.1)
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for k in ids.size():
		var pos := Vector3(-3.0 + k * 2.0, 1.1, 0)
		_place(ids[k], pos)
		# +Z marker cone ahead of the projectile
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.08
		cone.height = 0.25
		cone.material = arrow_mat
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.position = pos + Vector3(0, -0.5, 1.2)
		mi.rotation.x = deg_to_rad(90)
		_stage.add_child(mi)
		_label(ids[k].substr(5), pos + Vector3(0, -0.9, 1.6), 32)
	_omni(Vector3(-1, 3, 2), Color(1, 0.9, 0.8), 3.0, 12.0)
	_omni(Vector3(3, 3, 1), Color(0.9, 0.9, 1.0), 2.0, 12.0)
	_game_camera(Vector3(0, 0.9, 0.3), 6.5, 40.0, 30.0, 45.0)


# ------------------------------------------------------------------ icons

func _stage_icons() -> void:
	_dungeon_env()
	var cam := Camera3D.new()
	_stage.add_child(cam)
	cam.current = true
	_ui = CanvasLayer.new()
	add_child(_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(bg)
	var vb := VBoxContainer.new()
	vb.position = Vector2(24, 16)
	vb.add_theme_constant_override("separation", 10)
	_ui.add_child(vb)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for sid in SKILL_IDS:
		var cell := VBoxContainer.new()
		var tr := TextureRect.new()
		tr.texture = Assets.skill_icon(sid)
		tr.custom_minimum_size = Vector2(128, 128)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(tr)
		var l := Label.new()
		l.text = sid
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(150, 0)
		cell.add_child(l)
		grid.add_child(cell)
	var small_title := Label.new()
	small_title.text = "at 48 px (HUD skill bar size):"
	small_title.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	vb.add_child(small_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	for sid in SKILL_IDS:
		var tr := TextureRect.new()
		tr.texture = Assets.skill_icon(sid)
		tr.custom_minimum_size = Vector2(48, 48)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(tr)

extends Node3D
## Enemies demo: an arena with every archetype (normal / magic / rare packs) and both bosses
## fighting a player-team dummy. Windowed runs save screenshots to docs/screenshots/enemies/.
## OWNER: enemies.
##
##   GTEST_WINDOWED=1 tools/gtest.sh enemies-demo res://tests/scenes/enemies_demo.tscn -- --mode=lineup
##   Real monster attacks need the skills module:
##   GTEST_EXTRA="scripts/skills scripts/vfx scripts/autoload/skill_db.gd" GTEST_WINDOWED=1 \
##       tools/gtest.sh enemies-int res://tests/scenes/enemies_demo.tscn -- --mode=fight
##   modes: lineup  all archetypes x rarity + bosses, idle, bars shown (visual check)
##          fight   packs of every archetype engage the dummy; the dummy hits back (bars, flashes,
##                  staggers, deaths, loot)
##          boss    both bosses: roar, ability rotation, summons, enrage
##          dungeon a real dungeon depth populated by EnemyDB.populate_area (--depth=N)
##          perf    70 monsters idle, then all fighting (physics ms in the log)
##          player  a real Player (god mode, bot) in a dungeon: sleep, aggro, fights (GTEST_FULL=1)
##   extra args: --depth=N, --shots=t1,t2 (override screenshot times)

const SHOT_DIR := "/docs/screenshots/enemies/"

var mode := "fight"
var world: World = null
var dummy: TestDummy = null
var camera: Camera3D = null
var info_label: Label = null
var _t := 0.0
var _shots: Array = []
var _shot_index := 0
var _hit_timer := 0.0
var _dummy_model: Node3D = null
var _dummy_anim: AnimationPlayer = null
var _cam_target := Vector3.ZERO
var _cam_dist := 18.0
var _cam_pitch := 56.0
var _cam_yaw := 0.0
var _hit_interval := 0.55
var _hit_fraction := 0.3
var _kills := 0
var _spawned := 0
var _depth := 3
var _log_timer := 0.0
var _dmg_taken := 0.0
var _hits_taken := 0
var player: Player = null


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--depth="):
			_depth = int(a.substr(8))
	Events.enemy_killed.connect(func(_e: Node) -> void: _kills += 1)
	Events.boss_spawned.connect(func(b: Node) -> void: print("[demo] boss_spawned: ", (b as Enemy).display_name))
	_build_ui()
	match mode:
		"lineup":
			await _setup_lineup()
		"boss":
			await _setup_boss()
		"dungeon":
			await _setup_dungeon()
		"perf":
			await _setup_perf()
		"player":
			await _setup_player()
		_:
			mode = "fight"
			await _setup_fight()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots.clear()
			for s in a.substr(8).split(",", false):
				_shots.append([float(s), "%s_%s" % [mode, s]])
	print("[demo] mode=%s enemies=%d" % [mode, EnemyDB.get_enemies(world).size()])


# ------------------------------------------------------------------ setups

func _make_world(info: Dictionary) -> void:
	world = World.new()
	add_child(world)
	GameState.world = world
	GameState.current_area = info
	world.build(info)
	LootSystem.fallback_parent = world
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	await get_tree().physics_frame


func _make_dummy(pos: Vector3) -> void:
	dummy = TestDummy.new()
	dummy.team = Actor.Team.PLAYER
	dummy.base_life = 1000000.0
	dummy.position = pos
	dummy.display_name = "Dummy"
	world.add_child(dummy)
	dummy.damaged.connect(func(amount: float, _crit: bool, _src: Node) -> void:
		_dmg_taken += amount
		_hits_taken += 1)
	_dummy_model = Assets.model("char_player")
	dummy.add_child(_dummy_model)
	Assets.attach_to_bone(_dummy_model, "grip_r", Assets.model("weapon_sword"))
	Assets.attach_to_bone(_dummy_model, "grip_l", Assets.model("offhand_shield"))
	Assets.tint(_dummy_model, Color(0.55, 0.6, 0.7), ["Torso", "Arms"])
	_dummy_anim = Assets.prepare_animations(_dummy_model)
	if _dummy_anim != null:
		_dummy_anim.play("idle")
	var light := OmniLight3D.new()
	light.position = Vector3(0, 4.0, 0)
	light.omni_range = 14.0
	light.light_energy = 1.4
	light.light_color = Color(1.0, 0.85, 0.65)
	dummy.add_child(light)


func _setup_lineup() -> void:
	await _make_world({"id": "arena", "name": "Arena", "level": 5, "size": 24})
	var ids: Array[String] = ["skeleton_warrior", "skeleton_archer", "zombie", "ghoul", "cultist", "frost_cultist",
		"brute", "necromancer"]
	var mods := [[], ["hasted"], ["fiery", "armoured"]]
	for r in 3:
		for i in ids.size():
			var pos := Vector3(-9.8 + i * 2.8, 0, -3.0 + r * 3.2)
			var e := EnemyDB.spawn_enemy(ids[i], pos, 5, r, mods[r])
			e.rotation.y = 0.35
			if r == 1:
				e.take_damage(e.max_life * 0.3, "physical")
			_spawned += 1
	var lich := EnemyDB.spawn_enemy("boss_lich", Vector3(-4.0, 0, -8.5), 5)
	lich.rotation.y = 0.3
	var gb := EnemyDB.spawn_enemy("boss_gravebreaker", Vector3(4.0, 0, -8.5), 5)
	gb.rotation.y = -0.3
	gb.take_damage(gb.max_life * 0.35, "physical")
	_cam_target = Vector3(0, 0.6, -1.5)
	_cam_dist = 23.0
	_cam_pitch = 42.0
	_shots = [[1.2, "lineup_all"], [1.6, "lineup_close_a"], [2.0, "lineup_close_b"], [2.4, "lineup_bosses"],
		[2.8, "lineup_game_angle"]]
	info_label.text = "Lineup: normal / magic (damaged) / rare rows, bosses at the back"


func _setup_fight() -> void:
	await _make_world({"id": "arena", "name": "Arena", "level": 6, "size": 26})
	_make_dummy(Vector3.ZERO)
	var packs := [
		["skeleton_warrior", 0, 4, Vector3(-11, 0, -8)],
		["skeleton_archer", 1, 3, Vector3(11, 0, -9)],
		["zombie", 2, 4, Vector3(-12, 0, 7)],
		["ghoul", 0, 4, Vector3(12, 0, 8)],
		["cultist", 0, 3, Vector3(0, 0, -13)],
		["frost_cultist", 1, 3, Vector3(0, 0, 13)],
		["brute", 2, 2, Vector3(-16, 0, 0)],
		["necromancer", 0, 1, Vector3(16, 0, 0)],
	]
	var pid := 100
	for p in packs:
		for k in int(p[2]):
			var rarity := int(p[1])
			if rarity == 2 and k > 0:
				rarity = 0
			var pos: Vector3 = p[3] + Vector3(randf_range(-1.8, 1.8), 0, randf_range(-1.8, 1.8))
			var e := EnemyDB.spawn_enemy(String(p[0]), pos, 6, rarity)
			if e != null:
				e.pack_id = pid
				_spawned += 1
		pid += 1
	# Wake everybody up: the dummy is the target.
	for e in EnemyDB.get_enemies(world):
		e.aggro(dummy, false)
	_cam_target = Vector3(0, 0, 0)
	_cam_dist = 24.0
	_shots = [[1.0, "fight_engage"], [3.5, "fight_melee"], [6.0, "fight_brawl"], [9.0, "fight_late"],
		[9.4, "fight_close"]]
	info_label.text = "Fight: packs of every archetype vs a player-team dummy (dummy hits back)"


func _setup_boss() -> void:
	await _make_world({"id": "arena", "name": "Arena", "level": 8, "size": 22})
	_make_dummy(Vector3(0, 0, 2))
	var lich := EnemyDB.spawn_enemy("boss_lich", Vector3(-8, 0, -6), 8)
	var gb := EnemyDB.spawn_enemy("boss_gravebreaker", Vector3(8, 0, -6), 8)
	_spawned = 2
	lich.aggro(dummy)
	gb.aggro(dummy)
	_hit_fraction = 0.045
	_hit_interval = 0.35
	_cam_target = Vector3(0, 0.8, -2)
	_cam_dist = 20.0
	_shots = [[0.55, "boss_roar"], [3.0, "boss_fight"], [7.5, "boss_enraged"], [11.0, "boss_late"]]
	info_label.text = "Bosses: roar on aggro, ability rotation, enrage at 50%"


func _setup_dungeon() -> void:
	var theme := World.theme_for_depth(_depth)
	var info := {"id": "dungeon", "depth": _depth, "level": Balance.area_level_for_depth(_depth), "seed": 1234 + _depth,
		"theme": theme, "name": "Depth %d" % _depth}
	await _make_world(info)
	var t0 := Time.get_ticks_usec()
	EnemyDB.populate_area(world)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var counts := {}
	for e in EnemyDB.get_enemies(world):
		var k := "%s/%d" % [e.enemy_id, e.rarity]
		counts[k] = int(counts.get(k, 0)) + 1
	print("[demo] populate_area: %d enemies in %.1f ms: %s" % [EnemyDB.get_enemies(world).size(), ms, counts])
	# Put the dummy in front of the first pack that is visible from the start.
	var groups := world.get_spawn_groups()
	var target := world.get_player_start()
	var best := INF
	for g in groups:
		var d := CombatQuery.distance_xz(g["position"], world.get_player_start())
		if String(g["kind"]) == "rare_pack" and d < best:
			best = d
			target = g["position"]
	var spot := world.random_walkable_near(target, 7.0)
	_make_dummy(spot)
	_hit_fraction = 0.35
	_cam_target = spot
	_cam_dist = 20.0
	_shots = [[2.5, "dungeon_d%d_a" % _depth], [6.0, "dungeon_d%d_b" % _depth], [9.0, "dungeon_d%d_c" % _depth]]
	info_label.text = "Depth %d (%s): populated by EnemyDB.populate_area" % [_depth, theme]


## A real Player (god mode, bot-driven toward the nearest monster, attacking with slot 1) in a
## populated dungeon: sleeping beyond 40 m, aggro on the player, real attacks both ways.
func _setup_player() -> void:
	var theme := World.theme_for_depth(_depth)
	var info := {"id": "dungeon", "depth": _depth, "level": Balance.area_level_for_depth(_depth), "seed": 777 + _depth,
		"theme": theme, "name": "Depth %d" % _depth}
	await _make_world(info)
	GameState.new_character("Demo", "warrior")
	GameState.character.level = maxi(1, _depth)
	player = Player.new()
	player.setup(GameState.character)
	player.position = world.get_player_start()
	GameState.player = player
	world.add_child(player)
	player.god_mode = true
	player.ai_control = true
	player.damaged.connect(func(amount: float, _crit: bool, _src: Node) -> void:
		_dmg_taken += amount
		_hits_taken += 1)
	EnemyDB.populate_area(world)
	Events.player_spawned.emit(player)
	_cam_target = player.global_position
	_cam_dist = 18.0
	_shots = [[1.5, "player_start"], [6.0, "player_fight_a"], [10.0, "player_fight_b"], [14.0, "player_fight_c"]]
	info_label.text = "Real Player (god mode, bot) in depth %d" % _depth


## 70 monsters in a big arena: idle for 4 s, then everything fights the dummy (physics ms logged).
func _setup_perf() -> void:
	await _make_world({"id": "arena", "name": "Arena", "level": 10, "size": 40})
	var ids := EnemyDB.get_archetype_ids()
	for i in 70:
		var p := Vector3(randf_range(-36, 36), 0, randf_range(-36, 36))
		EnemyDB.spawn_enemy(String(ids[i % ids.size()]), p, 10, 1 if i % 7 == 0 else 0)
	_spawned = 70
	_cam_target = Vector3.ZERO
	_cam_dist = 40.0
	_shots = [[3.5, "perf_idle"], [9.0, "perf_fight"]]
	info_label.text = "Perf: 70 monsters idle, then all fighting"
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		_make_dummy(Vector3.ZERO)
		for e in EnemyDB.get_enemies(world):
			e.aggro(dummy, false))


# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	if dummy != null and is_instance_valid(dummy):
		dummy.refill_pools()
		_dummy_hits(delta)
	if mode == "fight" or mode == "dungeon":
		if dummy != null:
			_cam_target = _cam_target.lerp(dummy.global_position, clampf(delta * 3.0, 0.0, 1.0))
	if mode == "player" and is_instance_valid(player):
		_drive_player()
		_cam_target = _cam_target.lerp(player.global_position, clampf(delta * 4.0, 0.0, 1.0))
	_update_camera()
	_log_timer += delta
	if _log_timer >= 1.0:
		_log_timer = 0.0
		_log_state()


func _process(_delta: float) -> void:
	if _shot_index < _shots.size() and _t >= float(_shots[_shot_index][0]):
		var shot: Array = _shots[_shot_index]
		_shot_index += 1
		_prepare_shot(String(shot[1]))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_save_shot(String(shot[1]))
		if _shot_index >= _shots.size():
			await get_tree().create_timer(0.3).timeout
			print("[demo] done: kills=%d" % _kills)
			get_tree().quit()
	elif _shots.is_empty() and _t > 12.0:
		get_tree().quit()


## Camera presets per shot name.
func _prepare_shot(shot: String) -> void:
	match shot:
		"lineup_close_a":
			_cam_target = Vector3(-5.6, 1.0, -0.5)
			_cam_dist = 11.0
			_cam_pitch = 30.0
		"lineup_close_b":
			_cam_target = Vector3(5.6, 1.0, -0.5)
			_cam_dist = 11.0
			_cam_pitch = 30.0
		"lineup_bosses":
			_cam_target = Vector3(0, 1.6, -8.5)
			_cam_dist = 13.0
			_cam_pitch = 24.0
		"lineup_game_angle":
			_cam_target = Vector3(0, 0, -1.5)
			_cam_dist = 18.0
			_cam_pitch = 56.0
		"fight_close":
			_cam_dist = 13.0
			_cam_pitch = 50.0
		"boss_enraged":
			_cam_dist = 16.0
	_update_camera()


## Bot: walk toward the nearest awake monster, attack it when close.
func _drive_player() -> void:
	var best: Enemy = null
	var best_d := INF
	for e in EnemyDB.get_enemies(world):
		if e.sleeping:
			continue
		var d := CombatQuery.distance_xz(player.global_position, e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		player.ai_move(Vector3.ZERO)
		player.ai_hold_skill(0, false)
		return
	player.ai_aim(best.global_position, best)
	if best_d > 2.2:
		var path := world.find_path(player.global_position, best.global_position)
		var goal := path[0] if path.size() > 0 else best.global_position
		var dir := goal - player.global_position
		dir.y = 0.0
		player.ai_move(dir.normalized())
		player.ai_hold_skill(0, false)
	else:
		player.ai_move(Vector3.ZERO)
		player.ai_hold_skill(0, true)


func _update_camera() -> void:
	if camera == null:
		return
	var p := deg_to_rad(_cam_pitch)
	var y := deg_to_rad(_cam_yaw)
	var offset := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _cam_dist
	camera.global_position = _cam_target + offset
	camera.look_at(_cam_target, Vector3.UP)


## The dummy fights back: every _hit_interval it hits the nearest enemy in reach for a fraction
## of its max life (shows bars, flashes, staggers, deaths, loot).
func _dummy_hits(delta: float) -> void:
	if mode == "lineup":
		return
	_hit_timer -= delta
	if _hit_timer > 0.0:
		return
	_hit_timer = _hit_interval
	var t := CombatQuery.nearest_hostile(dummy.team, dummy.global_position, 3.0)
	if t == null:
		return
	dummy.face_towards(t.global_position)
	if _dummy_anim != null and _dummy_anim.has_animation("attack_slash"):
		_dummy_anim.play("attack_slash", 0.05, 1.4)
		_dummy_anim.queue("idle")
	var amount := t.max_life * _hit_fraction * randf_range(0.8, 1.25)
	var h := HitData.create({"physical": amount}, dummy, PackedStringArray(["attack", "melee"]))
	h.can_evade = false
	h.is_crit = randf() < 0.2
	t.take_hit(h)


func _log_state() -> void:
	var states := {}
	for e in EnemyDB.get_enemies(world):
		var k: String = ["idle", "combat", "return", "dead"][e.state]
		states[k] = int(states.get(k, 0)) + 1
	var busy := 0
	for e in EnemyDB.get_enemies(world):
		if e.skill_runner != null and e.skill_runner.is_busy():
			busy += 1
	var dists := {}
	var sleeping := 0
	for e in EnemyDB.get_enemies(world):
		if e.sleeping:
			sleeping += 1
	if mode == "player":
		print("[demo] sleeping=%d player_life=%.0f" % [sleeping, player.life if is_instance_valid(player) else 0.0])
	if dummy != null:
		for e in EnemyDB.get_enemies(world):
			if e.is_in_combat():
				var dd := CombatQuery.distance_to_actor(e.global_position, dummy)
				dists[e.enemy_id] = "%.1f" % minf(dd, float(String(dists.get(e.enemy_id, "999")).to_float()))
	print("[demo] t=%.1f states=%s busy=%d kills=%d dummy_hits=%d dmg=%.0f physics=%.2f ms fps=%d nearest=%s" % [_t,
		states, busy, _kills, _hits_taken, _dmg_taken, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Engine.get_frames_per_second(), dists])


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = Label.new()
	info_label.position = Vector2(16, 12)
	info_label.add_theme_font_size_override("font_size", 22)
	info_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(info_label)


func _save_shot(shot: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var repo := OS.get_environment("GTEST_REPO")
	if repo == "":
		return
	var dir := repo + SHOT_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	var path := dir + shot + ".png"
	img.save_png(path)
	print("[demo] saved ", path)

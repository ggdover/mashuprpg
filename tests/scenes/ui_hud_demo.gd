extends Node3D
## ui-hud demo: the real HUD (created by the UI autoload) bound to a real Player driven through
## the Player.ai_* API.
##   fight    arena, level 14 warrior with an ES ward buff, War Cry, Cleave on a pack (normal /
##            magic / rare) and a Gravebreaker boss (boss bar), ailments on the player (globe
##            tint + debuff icons), a hovered rare (nameplate), lots of damage numbers, then a
##            1.5 s stress of ~160 live numbers (hud_numbers_stress + printed cost / fps)
##   tooltip  a skill-bar tooltip
##   lowlife  15% life, potion running, mana drained (red slots), low-life vignette
##   dungeon  depth 5 cave, a sorcerer exploring (corner minimap with fog, portal marker, enemy
##            dots, the boss skull), the large Tab overlay and the town portal cast bar
##   town     Emberfall with a shrine buff (corner map + overlay with vendor / stash markers,
##            the waypoint pinned to the rim)
## Windowed runs save docs/screenshots/ui-hud/<shot>.png; headless runs are a smoke test.
##
##   GTEST_WINDOWED=1 tools/gtest.sh ui-hud-demo res://tests/scenes/ui_hud_demo.tscn
##   ... -- --shots=fight,dungeon       (subset)    ... -- --quit_after=40
## OWNER: ui-hud.

const ALL_SHOTS: Array[String] = ["fight", "tooltip", "lowlife", "dungeon", "town"]
const ARENA := {"id": "arena", "name": "The Proving Grounds", "level": 14, "size": 22, "theme": "crypt"}
const TOWN := {"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}
const DUNGEON := {"id": "dungeon", "depth": 5, "level": 5, "seed": 5150, "theme": "cave", "name": "Depth 5 — The Caves"}

var world: World = null
var player: Player = null
var rig: CameraRig = null
var hud: HUD = null
var shots := false
var out_dir := ""
var wanted: Array[String] = []
var count := 0
var _spray := 0.0
var _spray_on := false
var _targets: Array = []


func _ready() -> void:
	get_tree().create_timer(_arg_float("--quit_after", 40.0)).timeout.connect(get_tree().quit)
	wanted.assign(ALL_SHOTS)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			wanted.assign(Array(a.substr(8).split(",", false)))
	shots = DisplayServer.get_name() != "headless"
	out_dir = OS.get_environment("GTEST_REPO") + "/docs/screenshots/ui-hud/"
	if shots:
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _arg_float(key: String, def: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return float(a.substr(key.length() + 1))
	return def


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(shot_name: String) -> void:
	if not shots:
		print("[ui_hud_demo] (headless) would save ", shot_name)
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + shot_name + ".png")
	count += 1
	print("[ui_hud_demo] saved ", shot_name)


func _run() -> void:
	if wanted.has("fight") or wanted.has("tooltip") or wanted.has("lowlife"):
		await _fight()
	if wanted.has("dungeon"):
		await _dungeon()
	if wanted.has("town"):
		await _town()
	print("[ui_hud_demo] done, %d screenshots" % count)
	get_tree().quit()


func _process(delta: float) -> void:
	if not _spray_on:
		return
	_spray -= delta
	if _spray > 0.0:
		return
	_spray = 0.09
	# Extra combat text over live enemies (the real hits add their own).
	var live: Array = []
	for e in _targets:
		if is_instance_valid(e) and not (e as Actor).dead:
			live.append(e)
	if live.is_empty():
		return
	var e: Actor = live[randi() % live.size()]
	var kinds := ["physical", "physical", "fire", "cold", "lightning", "chaos"]
	var kind: String = kinds[randi() % kinds.size()]
	var crit := randf() < 0.18
	var amount := randf_range(18.0, 95.0) * (2.2 if crit else 1.0)
	Events.damage_number.emit(e.get_aim_point(), amount, kind, crit)
	if randf() < 0.12 and is_instance_valid(player):
		Events.damage_number.emit(player.get_aim_point(), randf_range(8.0, 40.0), "player_hurt", false)
	if randf() < 0.05 and is_instance_valid(player):
		Events.damage_number.emit(player.get_aim_point(), 0.0, "evade", false)


# ------------------------------------------------------------------ setup

func _make_area(info: Dictionary) -> void:
	if world != null:
		GameState.player = null
		GameState.world = null
		world.queue_free()
		world = null
		await get_tree().process_frame
	world = World.new()
	add_child(world)
	GameState.world = world
	GameState.current_area = info
	world.build(info)


func _spawn_player(c: CharacterData, pos: Vector3) -> void:
	player = Player.new()
	player.setup(c)
	player.position = pos
	world.add_child(player)
	GameState.player = player
	rig = CameraRig.new()
	rig.target = player
	world.add_child(rig)
	player.camera_rig = rig
	rig.snap_to_target()
	if world.has_method("snap_light_pool"):
		world.snap_light_pool()
	UI.show_hud(true)
	hud = UI.get_hud() as HUD
	Events.player_spawned.emit(player)
	Events.area_entered.emit(GameState.current_area)


func _enemy(id: String, pos: Vector3, level: int, rarity: int) -> Enemy:
	var e: Enemy = EnemyDB.spawn_enemy(id, pos, level, rarity, [], world)
	if e != null:
		_targets.append(e)
	return e


# ------------------------------------------------------------------ scenes

func _fight() -> void:
	await _make_area(ARENA)
	var c := GameState.new_character("Aldric", "warrior")
	c.level = 14
	c.xp = int(c.xp_to_next() * 0.62)
	var sword := ItemDB.create_item("sword_2", Item.Rarity.RARE, 14)
	if sword != null:
		c.equip(sword, "main_hand")
	c.set_skill_in_slot(0, "basic_attack")
	c.set_skill_in_slot(1, "cleave")
	c.set_skill_in_slot(2, "ground_slam")
	c.set_skill_in_slot(3, "war_cry")
	c.set_skill_in_slot(4, "leap_slam")
	c.set_skill_in_slot(5, "whirlwind")
	c.life_potion_charges = 2.6
	c.mana_potion_charges = 1.4
	await _spawn_player(c, Vector3.ZERO)
	player.add_buff("demo_ward", {"name": "Arcane Ward", "duration": 0.0, "icon": "frost_nova",
		"mods": [StatBlock.mod("max_energy_shield", "flat", 90.0)]})
	await _wait(0.4)
	# A pack in front (screen-up = world -Z) and the boss behind it.
	var pack := [
		_enemy("skeleton_warrior", Vector3(-2.2, 0, -3.2), 14, 0),
		_enemy("skeleton_warrior", Vector3(2.4, 0, -3.0), 14, 0),
		_enemy("zombie", Vector3(0.2, 0, -4.4), 14, 1),
		_enemy("brute", Vector3(-3.8, 0, -5.4), 14, 2),
	]
	var boss := _enemy("boss_gravebreaker", Vector3(3.5, 0, -8.5), 14, 3)
	for e in pack:
		if e != null:
			e.base_move_speed *= 0.4
	player.god_mode = true
	player.life = player.max_life * 0.62
	if boss != null:
		boss.aggro(player)
		boss.take_damage(boss.max_life * 0.32, "fire")
		boss.apply_ailment("shock", {"effect": 0.2, "duration": 8.0})
		boss.apply_ailment("ignite", {"dps": 30.0, "duration": 8.0})
	# War Cry (buff + cooldown), then Cleave into the pack.
	var tgt: Enemy = pack[0]
	player.ai_aim(tgt.global_position if tgt != null else Vector3(0, 0, -3), tgt)
	player.ai_hold_skill(3, true)
	await _wait(0.1)
	player.ai_hold_skill(3, false)
	await _wait(0.9)
	player.apply_ailment("ignite", {"dps": 4.0, "duration": 9.0})
	player.apply_ailment("chill", {"effect": 0.2, "duration": 9.0})
	for i in 3:
		player.apply_ailment("poison", {"dps": 2.0, "duration": 7.0})
	player.ai_use_potion("mana")
	_spray_on = true
	player.ai_hold_skill(1, true)
	for e in pack:
		if e != null:
			e.aggro(player)
	var rare: Enemy = pack[3]
	await _wait(1.2)
	if rare != null and is_instance_valid(rare):
		# Hovering the rare: the player aims at it (and reports the hover like the mouse would).
		player.ai_aim(rare.global_position, rare)
		await get_tree().physics_frame
		Events.hovered_target_changed.emit(rare)
	await _wait(1.2)
	var dn: Variant = hud.damage_numbers
	print("[ui_hud_demo] HUD update %.0f us/frame, %d numbers active, %d labels, fps %d" % [hud.frame_cost_usec, dn.get_active_count(), dn.get_label_count(), Engine.get_frames_per_second()])
	if wanted.has("fight"):
		await _shot("hud_fight")
	player.ai_hold_skill(1, false)
	if wanted.has("tooltip"):
		var slot: Control = hud.skill_slots[1]
		hud.show_tooltip_for(slot, slot.call("get_tooltip_lines"), false)
		hud.life_globe.call("show_numbers", true)
		hud.mana_globe.call("show_numbers", true)
		await _wait(0.25)
		await _shot("hud_skill_tooltip")
		hud.hide_tooltip_for(null)
		hud.life_globe.call("show_numbers", false)
		hud.mana_globe.call("show_numbers", false)
	if wanted.has("lowlife"):
		player.life = player.max_life * 0.14
		player.mana = 2.0
		player.use_potion("life")
		player.life = player.max_life * 0.14
		await _wait(0.55)
		player.life = player.max_life * 0.15
		await _wait(0.3)
		await _shot("hud_low_life")
	# Stress: ~150 live numbers.
	_spray_on = false
	var dnl: Variant = hud.damage_numbers
	var frames := 0
	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < 1500:
		for k in 3:
			var kinds := ["physical", "fire", "cold", "lightning", "chaos", "player_hurt"]
			Events.damage_number.emit(Vector3(randf_range(-5, 5), 1.2, randf_range(-8, 2)), randf_range(5, 400), kinds[randi() % kinds.size()], randf() < 0.2)
		await get_tree().process_frame
		frames += 1
		if frames == 50 and wanted.has("fight"):
			await _shot("hud_numbers_stress")
	print("[ui_hud_demo] stress: %d numbers active, %d labels, numbers update %.0f us/frame, %.0f fps" % [dnl.get_active_count(), dnl.get_label_count(), dnl.frame_cost_usec, frames / 1.5])
	player.ai_release_control()


func _dungeon() -> void:
	_targets.clear()
	await _make_area(DUNGEON)
	var c := GameState.new_character("Syl", "sorcerer")
	c.level = 12
	c.xp = int(c.xp_to_next() * 0.2)
	c.set_skill_in_slot(0, "fireball")
	c.set_skill_in_slot(1, "ice_spear")
	c.set_skill_in_slot(2, "frost_nova")
	c.set_skill_in_slot(3, "chain_lightning")
	c.set_skill_in_slot(4, "teleport")
	c.set_skill_in_slot(5, "spark")
	var start := world.get_player_start()
	await _spawn_player(c, start)
	player.god_mode = true
	EnemyDB.populate_area(world)
	await _wait(0.5)
	# Walk (teleport in steps) along the path toward the boss room, revealing the map.
	var path := world.find_path(start, world.get_boss_room_center())
	var steps := int(path.size() * 0.55)
	for i in steps:
		player.global_position = path[i]
		world.mark_explored(path[i], 14.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
	if rig != null:
		rig.snap_to_target()
	player.ai_release_control()
	await _wait(1.2)
	for e in EnemyDB.get_enemies(world):
		if e.is_boss:
			Events.hovered_target_changed.emit(null)
	if wanted.has("dungeon"):
		await _shot("hud_dungeon")
		hud.set_minimap_large(true)
		await _wait(0.3)
		await _shot("hud_minimap_overlay")
		hud.set_minimap_large(false)
		# Town portal cast bar (no game flow here, so nothing happens when it completes).
		player.ai_town_portal()
		await _wait(0.55)
		await _shot("hud_portal_cast")
		await _wait(0.6)


func _town() -> void:
	_targets.clear()
	await _make_area(TOWN)
	var c := GameState.new_character("Mira", "ranger")
	c.level = 9
	c.xp = int(c.xp_to_next() * 0.85)
	c.allocated_passives.assign([])
	var start := world.get_player_start()
	await _spawn_player(c, start)
	player.add_buff("shrine_swiftness", {"name": "Shrine of Swiftness", "duration": 30.0, "icon": "teleport",
		"mods": [StatBlock.mod("movement_speed", "inc", 25.0)]})
	await _wait(1.0)
	await _shot("hud_town")
	hud.set_minimap_large(true)
	await _wait(0.3)
	await _shot("hud_town_overlay")
	hud.set_minimap_large(false)

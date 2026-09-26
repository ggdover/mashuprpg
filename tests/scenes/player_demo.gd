extends Node3D
## Player demo: players of every class driven through the ai_* API (the same code paths as
## keyboard / mouse), training dummies wearing monster models, ground loot and interactables.
## Character shots use an open arena; gameplay / skill shots use the start room of a crypt
## dungeon (depth 1, fixed seed). Windowed runs save screenshots to docs/screenshots/player/:
##   classes / classes_close        starting kits (warrior, ranger, sorcerer) at the game angle / close
##   gear / gear_close / gear_back  full gear sets: armour tints, helmets (no hair), shield, focus,
##   gear_uniques                   quiver on the back, two-handers, uniques
##   poses / poses_game             attack / shoot / cast one-shots near their hit frames
##   dodge, channel                 mid-roll with dust; whirlwind spin
##   fx                             level-up ring, potion swirl, town-portal cast
##   hit, death                     hit flash + flinch; the die pose
##   gameplay, hover, hover_walk    the camera view (distance 18) in a dungeon with dummies, loot
##                                  and the portal; mouse_override hover of a loot label + walk
##   skills_<class>, skills_leap_slam, skills_whirlwind, skills_frost_nova
##                                  real skills (needs GTEST_EXTRA with the skills module): each
##                                  shot is taken just after the skill's effect
##   fight                          (GTEST_FULL=1: real enemies + skills) a warrior driven by a tiny
##                                  ai_* bot (approach, attack, potion, dodge) against a pack
##
##   GTEST_WINDOWED=1 tools/gtest.sh player-demo res://tests/scenes/player_demo.tscn
##   ... -- --shots=gear,poses        (subset)
##   GTEST_EXTRA="scripts/skills scripts/vfx scripts/autoload/skill_db.gd" ... (real skills)
## Headless runs play the same script as a smoke test (no screenshots).

const ALL_SHOTS: Array[String] = ["classes", "gear", "poses", "dodge", "channel", "fx", "hit", "death", "gameplay", "hover", "skills", "fight"]
const ARENA := {"id": "arena", "name": "Arena", "level": 1, "size": 14}
const DUNGEON := {"id": "dungeon", "depth": 1, "level": 1, "seed": 424242, "theme": "crypt", "name": "Depth 1 — The Crypts"}

var world: World = null
var world_kind := ""
var rig: CameraRig = null
var close_cam: Camera3D = null
var out_dir := ""
var shots := false
var wanted: Array[String] = []
var players: Array[Player] = []
var dummies: Array[Node3D] = []
var extras: Array[Node] = []
## Ground point used as the centre of dungeon scenes.
var stage := Vector3.ZERO


func _ready() -> void:
	get_tree().create_timer(75).timeout.connect(get_tree().quit)
	wanted.assign(ALL_SHOTS)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			wanted.assign(Array(a.substr(8).split(",", false)))
	shots = DisplayServer.get_name() != "headless"
	out_dir = OS.get_environment("GTEST_REPO") + "/docs/screenshots/player/"
	if shots:
		DirAccess.make_dir_recursive_absolute(out_dir)
	close_cam = Camera3D.new()
	close_cam.fov = 35.0
	add_child(close_cam)
	_run.call_deferred()


func _run() -> void:
	for s in wanted:
		match s:
			"classes": await _shot_classes()
			"gear": await _shot_gear()
			"poses": await _shot_poses()
			"dodge": await _shot_dodge()
			"channel": await _shot_channel()
			"fx": await _shot_fx()
			"hit": await _shot_hit()
			"death": await _shot_death()
			"gameplay": await _shot_gameplay()
			"hover": await _shot_hover()
			"skills": await _shot_skills()
			"fight": await _shot_fight()
			_: push_warning("player_demo: unknown shot '%s'" % s)
	print("[player_demo] done")
	get_tree().quit()


# ------------------------------------------------------------------ helpers

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _save(shot_name: String) -> void:
	if not shots:
		# Headless: no frames are drawn (frame_post_draw never fires).
		await get_tree().process_frame
		print("[player_demo] (headless) %s" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + shot_name + ".png")
	print("[player_demo] saved %s.png" % shot_name)


## Switch to the arena or the dungeon (built once each time it is entered).
func _use_world(kind: String) -> void:
	if kind == world_kind and world != null and is_instance_valid(world):
		return
	await _clear()
	if world != null and is_instance_valid(world):
		world.queue_free()
		await _frames(1)
	world = World.new()
	add_child(world)
	GameState.world = world
	var info: Dictionary = (DUNGEON if kind == "dungeon" else ARENA).duplicate()
	GameState.current_area = info
	world.build(info)
	world_kind = kind
	stage = world.get_player_start()
	if kind == "dungeon":
		# The middle of the start room if it is roomy, else of the largest ordinary room.
		var best: Dictionary = {}
		for r: Dictionary in world.get_rooms():
			var rect: Rect2i = r.get("rect", Rect2i())
			if r.get("kind", "") == "start" and rect.size.x >= 7 and rect.size.y >= 7:
				best = r
				break
			if r.get("kind", "") == "room" and (best.is_empty() or rect.get_area() > (best["rect"] as Rect2i).get_area()):
				best = r
		if not best.is_empty():
			stage = world.get_nearest_walkable(best["center"])
		print("[player_demo] dungeon stage %s (%s)" % [stage, best.get("kind", "start")])
	await _physics(2)


func _clear() -> void:
	for p in players:
		if is_instance_valid(p):
			p.queue_free()
	players.clear()
	for d in dummies:
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()
	for e in extras:
		if is_instance_valid(e):
			e.queue_free()
	extras.clear()
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	rig = null
	GameState.player = null
	if world != null and is_instance_valid(world):
		for n in world.dynamic_root.get_children():
			n.queue_free()
		world.area_info = (DUNGEON if world_kind == "dungeon" else ARENA).duplicate()
	await _frames(2)


## A player of `class_id` at `pos` (relative to the stage) facing `yaw` (0 = toward the camera).
func _spawn(class_id: String, pos: Vector3, yaw: float = 0.0, lvl: int = 1) -> Player:
	var c := GameState.new_character(class_id.capitalize(), class_id)
	c.level = lvl
	var p := Player.new()
	p.setup(c)
	p.position = stage + pos
	p.rotation.y = yaw
	p.ai_control = true
	world.add_child(p)
	players.append(p)
	if GameState.player == null:
		GameState.player = p
	return p


func _camera_on(target: Node3D, zoom: float) -> void:
	if rig == null or not is_instance_valid(rig):
		rig = CameraRig.new()
		world.add_child(rig)
	rig.target = target
	rig.zoom_target = zoom
	rig.distance = zoom
	if target is Player:
		(target as Player).camera_rig = rig
	rig.snap_to_target()
	rig.camera.make_current()


func _marker(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	world.add_child(n)
	n.position = stage + pos
	extras.append(n)
	return n


## Close portrait camera looking at `center` (relative to the stage) from the front (+Z).
func _close_on(center: Vector3, dist: float, height: float = 1.6) -> void:
	var c := stage + center
	close_cam.position = c + Vector3(0, height, dist)
	close_cam.look_at(c + Vector3(0, 0.95, 0), Vector3.UP)
	close_cam.make_current()


func _equip(p: Player, base_ids: Array, rarity: int = Item.Rarity.RARE, ilvl: int = 30) -> void:
	for b in base_ids:
		var it: Item = null
		if String(b).begins_with("u:"):
			it = ItemDB.create_unique(String(b).substr(2), ilvl)
		else:
			it = ItemDB.create_item(String(b), rarity, ilvl)
		if it == null or it.get_base().is_empty():
			push_warning("player_demo: unknown base %s" % b)
			continue
		var slot := p.character.get_default_slot_for(it)
		if slot == "":
			continue
		for displaced in p.character.equip(it, slot):
			p.character.add_to_inventory(displaced)


## A TestDummy dressed with a monster model (idle animation) — stands in for the Enemy module.
func _dummy(model_id: String, pos: Vector3, yaw: float = PI, life: float = 400.0) -> TestDummy:
	var d := TestDummy.new()
	d.team = Actor.Team.ENEMY
	d.base_life = life
	d.position = stage + pos
	d.rotation.y = yaw
	world.add_child(d)
	var m := Assets.model(model_id)
	d.add_child(m)
	var ap := Assets.prepare_animations(m)
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")
		ap.seek(randf() * 1.5, true)
	dummies.append(d)
	return d


## Freeze an action pose: play `anim` stretched over a long time and seek to `at` (fraction).
func _pose(p: Player, anim: String, at: float) -> void:
	p.play_action_animation(anim, 30.0)
	var ap := p.anim_player
	if ap != null and ap.current_animation != "":
		ap.seek(ap.current_animation_length * at, true)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


# ------------------------------------------------------------------ character shots (arena)

func _shot_classes() -> void:
	await _use_world("arena")
	await _clear()
	var w := _spawn("warrior", Vector3(-1.6, 0, 0), 0.35)
	_spawn("ranger", Vector3(0, 0, 0.3), 0.0)
	_spawn("sorcerer", Vector3(1.6, 0, 0), -0.35)
	await _physics(3)
	_camera_on(_marker(Vector3(0, 0, 0.2)), CameraRig.MIN_DISTANCE)
	await _frames(20)
	await _save("classes")
	_close_on(Vector3(0, 0, 0.1), 5.2, 1.5)
	await _frames(4)
	await _save("classes_close")
	print("[player_demo] warrior weapon attached: %s" % (w.visuals.get_attachment("grip_r") != null))


func _shot_gear() -> void:
	await _use_world("arena")
	await _clear()
	var a := _spawn("warrior", Vector3(-2.4, 0, 0), 0.3)
	_equip(a, ["mace_4", "shield_str_4", "helmet_str_4", "body_str_4", "gloves_str_4", "boots_str_4"])
	var b := _spawn("warrior", Vector3(-0.8, 0, 0.3), 0.1)
	_equip(b, ["greatsword_5", "helmet_str_dex_3", "body_str_dex_5", "gloves_str_dex_3", "boots_str_dex_3"])
	var c := _spawn("ranger", Vector3(0.8, 0, 0.3), -0.1)
	_equip(c, ["crossbow_3", "quiver_3", "helmet_dex_3", "body_dex_4", "gloves_dex_2", "boots_dex_4"])
	var d := _spawn("sorcerer", Vector3(2.4, 0, 0), -0.3)
	_equip(d, ["wand_4", "focus_4", "helmet_int_4", "body_int_5", "gloves_int_3", "boots_int_3"])
	await _physics(3)
	_camera_on(_marker(Vector3(0, 0, 0.2)), CameraRig.MIN_DISTANCE)
	await _frames(20)
	await _save("gear")
	_close_on(Vector3(0, 0, 0.1), 6.6, 1.5)
	await _frames(4)
	await _save("gear_close")
	for p in players:
		p.rotation.y = PI + p.rotation.y * 0.3
	await _frames(4)
	await _save("gear_back")
	# Uniques and more two-handers.
	await _clear()
	var e := _spawn("warrior", Vector3(-2.4, 0, 0), 0.3)
	_equip(e, ["u:gorebinder", "u:bulwark_of_the_fallen", "u:stormcrown", "u:bloodbond_plate", "u:frostbite_grips", "u:wanderers_steps"])
	var f := _spawn("warrior", Vector3(-0.8, 0, 0.3), 0.1)
	_equip(f, ["maul_6", "helmet_str_int_6", "body_str_int_6", "gloves_str_int_6", "boots_str_int_6"])
	var g := _spawn("ranger", Vector3(0.8, 0, 0.3), -0.1)
	_equip(g, ["u:windshear", "quiver_6", "helmet_dex_int_6", "body_dex_int_6", "gloves_dex_int_6", "boots_dex_int_6"])
	var h := _spawn("sorcerer", Vector3(2.4, 0, 0), -0.3)
	_equip(h, ["u:emberheart", "helmet_int_6", "body_int_6", "gloves_int_6", "boots_int_6"])
	await _physics(3)
	_close_on(Vector3(0, 0, 0.1), 6.6, 1.5)
	await _frames(6)
	await _save("gear_uniques")


func _shot_poses() -> void:
	await _use_world("arena")
	await _clear()
	var specs := [
		["warrior", ["sword_3", "shield_str_3", "body_str_3", "helmet_str_2"], "attack_slash", 0.42],
		["warrior", ["greataxe_4", "body_str_dex_4", "helmet_str_dex_4"], "attack_slam", 0.5],
		["ranger", ["bow_4", "quiver_4", "body_dex_4", "helmet_dex_4"], "shoot_bow", 0.55],
		["ranger", ["crossbow_4", "quiver_4", "body_dex_3"], "shoot_crossbow", 0.35],
		["sorcerer", ["wand_4", "focus_4", "body_int_4", "helmet_int_4"], "cast", 0.5],
		["sorcerer", ["staff_4", "body_int_5"], "cast_area", 0.45],
	]
	var i := 0
	for s in specs:
		var x := -4.0 + i * 1.6
		var p := _spawn(s[0], Vector3(x, 0, 0.0 if i % 2 == 0 else 0.4), 0.9 if x < 0 else -0.9)
		_equip(p, s[1])
		i += 1
	await _physics(3)
	i = 0
	for s in specs:
		_pose(players[i], s[2], s[3])
		i += 1
	_close_on(Vector3(0, 0, 0.2), 8.2, 1.8)
	await _frames(4)
	await _save("poses")
	# The same from the game camera (poses re-seeked: the stretched playback keeps running).
	_camera_on(_marker(Vector3.ZERO), 13.0)
	i = 0
	for s in specs:
		_pose(players[i], s[2], s[3])
		i += 1
	await _frames(3)
	await _save("poses_game")


func _shot_dodge() -> void:
	await _use_world("arena")
	await _clear()
	var p := _spawn("ranger", Vector3(-3, 0, 1), 0.0)
	_equip(p, ["bow_3", "quiver_3", "helmet_dex_3", "body_dex_3", "gloves_dex_3", "boots_dex_3"])
	await _physics(3)
	_camera_on(p, 12.0)
	await _frames(4)
	var from := p.global_position
	p.ai_dodge(Vector3(1, 0, 0))
	await _physics(8)
	await _save("dodge")
	await _physics(30)
	print("[player_demo] dodge moved %.2f m" % p.global_position.distance_to(from))


func _shot_channel() -> void:
	await _use_world("arena")
	await _clear()
	var p := _spawn("warrior", Vector3(0, 0, 0), 0.0)
	_equip(p, ["greatsword_4", "helmet_str_4", "body_str_4", "gloves_str_4", "boots_str_4"])
	_dummy("char_skeleton", Vector3(-1.8, 0, -1.2), 0.9)
	_dummy("char_zombie", Vector3(1.9, 0, -0.6), -1.2)
	await _physics(3)
	_camera_on(p, 12.0)
	p.play_action_animation("channel", 0.0)
	await _frames(17)
	await _save("channel")
	p.stop_action_animation()


func _shot_fx() -> void:
	await _use_world("arena")
	await _clear()
	world.area_info = {"id": "dungeon", "depth": 3, "level": 3, "name": "Depth 3"}
	var a := _spawn("warrior", Vector3(-3.5, 0, 0), 0.2)
	var b := _spawn("sorcerer", Vector3(0, 0, 0), 0.0)
	var c := _spawn("ranger", Vector3(3.5, 0, 0), PI)
	await _physics(3)
	_camera_on(_marker(Vector3.ZERO), 13.0)
	GameState.player = a
	a.character.add_xp(a.character.xp_to_next())
	b.life = b.max_life * 0.3
	b.use_potion("life")
	c.ai_town_portal()
	await _physics(24)
	await _save("fx")
	await _physics(40)
	print("[player_demo] fx: level %d, life %.0f/%.0f, portal casting %s" % [a.level, b.life, b.max_life, c.is_casting_portal()])


func _shot_hit() -> void:
	await _use_world("arena")
	await _clear()
	var p := _spawn("warrior", Vector3(0, 0, 0), PI - 0.3)
	var d := _dummy("char_skeleton", Vector3(0.6, 0, -1.6), -0.3)
	await _physics(3)
	_camera_on(p, 11.0)
	await _frames(3)
	var hit := HitData.create({"physical": p.max_life * 0.25}, d, PackedStringArray(["attack", "melee"]))
	p.take_hit(hit)
	await _frames(3)
	await _save("hit")


func _shot_death() -> void:
	await _use_world("arena")
	await _clear()
	var p := _spawn("sorcerer", Vector3(0, 0, 0), 0.4)
	_equip(p, ["staff_3", "helmet_int_3", "body_int_3"])
	await _physics(3)
	_camera_on(p, 11.0)
	p.take_damage(p.max_life * 10.0, "fire")
	await _physics(80)
	await _save("death")


# ------------------------------------------------------------------ gameplay shots (dungeon)

func _shot_gameplay() -> void:
	await _use_world("dungeon")
	await _clear()
	var p := _spawn("warrior", Vector3(0, 0, 1.5), PI)
	_equip(p, ["axe_3", "shield_str_3", "helmet_str_3", "body_str_3", "gloves_str_2", "boots_str_3"])
	var sk := _dummy("char_skeleton", Vector3(0.3, 0, -0.4), 0.2)
	_dummy("char_skeleton", Vector3(2.2, 0, -2.2), -0.6)
	_dummy("char_zombie", Vector3(-2.6, 0, -2.8), 0.4)
	_dummy("char_ghoul", Vector3(3.6, 0, 0.6), -1.6)
	var drops: Array = []
	drops.append({"type": "item", "item": ItemDB.generate_random_item(12, Item.Rarity.RARE)})
	drops.append({"type": "item", "item": ItemDB.generate_random_item(12, Item.Rarity.MAGIC)})
	drops.append({"type": "item", "item": ItemDB.create_unique("windshear", 12)})
	drops.append({"type": "item", "item": ItemDB.generate_random_item(12, Item.Rarity.NORMAL)})
	drops.append({"type": "gold", "amount": 37})
	LootSystem.spawn_drops(drops, stage + Vector3(-3.0, 0, 3.0))
	await _physics(3)
	_camera_on(p, CameraRig.DEFAULT_DISTANCE)
	world.snap_light_pool()
	p.ai_aim(sk.global_position, sk)
	await _physics(40)
	_pose(p, "attack_slash", 0.45)
	await _frames(3)
	await _save("gameplay")
	p.stop_action_animation()


func _shot_hover() -> void:
	# Continues the gameplay scene: hover a loot label with the mouse and auto-walk to it.
	if players.is_empty() or rig == null or world_kind != "dungeon":
		await _shot_gameplay()
	var p := players[0]
	var loot: GroundItem = null
	for n in world.dynamic_root.get_children():
		if n is GroundItem and (n as GroundItem).item != null and (n as GroundItem).item.rarity == Item.Rarity.UNIQUE:
			loot = n
	if loot == null:
		push_warning("player_demo: no loot to hover")
		return
	p.ai_release_control()
	rig.mouse_override = rig.camera.unproject_position(loot.get_label_position())
	await _physics(3)
	var h := p.get_hovered()
	print("[player_demo] hovered: %s" % ((h as Interactable).get_hover_name() if h is Interactable else "nothing"))
	await _save("hover")
	p.ai_interact(loot)
	await _physics(18)
	rig.mouse_override = null
	await _save("hover_walk")
	await _physics(90)
	print("[player_demo] picked up the unique: %s" % (not is_instance_valid(loot)))


## Real skills (GTEST_EXTRA): players use skills on dummies through ai_hold_skill; each shot is
## taken a few frames after the skill's effect.
func _shot_skills() -> void:
	await _use_world("dungeon")
	var kits := [
		["warrior", "cleave", ["sword_2", "shield_str_2", "helmet_str_2", "body_str_2"], 2.4, 1, 4],
		["ranger", "split_arrow", ["bow_2", "quiver_2", "helmet_dex_2", "body_dex_2"], 7.0, 1, 10],
		["sorcerer", "fireball", ["wand_2", "focus_2", "helmet_int_2", "body_int_2"], 7.0, 1, 12],
		["warrior", "leap_slam", ["greataxe_2", "helmet_str_2", "body_str_2"], 7.0, 8, 12],
		["warrior", "whirlwind", ["greatsword_2", "helmet_str_dex_2", "body_str_dex_2"], 1.8, 10, 12],
		["sorcerer", "frost_nova", ["staff_2", "body_int_2"], 2.2, 5, 8],
	]
	for k in kits:
		await _clear()
		var skill_id: String = k[1]
		var dist: float = k[3]
		var p := _spawn(k[0], Vector3(0, 0, 3.5), PI, int(k[4]))
		_equip(p, k[2])
		var slot := p.character.skill_bar.find(skill_id)
		if slot < 0:
			slot = 2
			p.character.set_skill_in_slot(slot, skill_id)
		var targets: Array = []
		for i in 3:
			var ang := (float(i) - 1.0) * 0.45
			var pos := Vector3(0, 0, 3.5) + Vector3(sin(ang), 0, -cos(ang)) * dist
			targets.append(_dummy("char_skeleton", pos, _yaw_to(pos, Vector3(0, 0, 3.5))))
		await _physics(3)
		_camera_on(p, 13.0)
		world.snap_light_pool()
		var t: TestDummy = targets[1]
		p.ai_aim(t.global_position, t)
		var check: Dictionary = p.skill_runner.can_use(skill_id)
		var effects := [0]
		var on_effect := func(_id: String) -> void: effects[0] += 1
		p.skill_runner.skill_effect.connect(on_effect)
		p.ai_hold_skill(slot, true)
		var shot_taken := false
		var wait_after: int = k[5]
		var waited := -1
		for f in 110:
			await get_tree().physics_frame
			if effects[0] > 0 and waited < 0:
				waited = 0
			if waited >= 0:
				waited += 1
				if waited == wait_after and not shot_taken:
					await _save("skills_%s" % (k[0] if skill_id in ["cleave", "split_arrow", "fireball"] else skill_id))
					shot_taken = true
			if f == 60:
				p.ai_hold_skill(slot, false)
		p.ai_hold_skill(slot, false)
		var dealt := 0.0
		for d in targets:
			dealt += (d as TestDummy).max_life - (d as TestDummy).life
		print("[player_demo] skills: %s %s -> %d effects, %.0f damage to dummies, can_use %s" % [k[0], skill_id, effects[0], dealt, check.get("code", "?")])
		if not shot_taken:
			await _save("skills_%s" % (k[0] if skill_id in ["cleave", "split_arrow", "fireball"] else skill_id))


## Real enemies (GTEST_FULL=1): a tiny bot drives a warrior through ai_* against a skeleton pack.
func _shot_fight() -> void:
	await _use_world("dungeon")
	await _clear()
	if EnemyDB.get_def("skeleton_warrior").is_empty():
		print("[player_demo] fight: EnemyDB is the stub - skipped")
		return
	var p := _spawn("warrior", Vector3(0, 0, 3.0), PI, 2)
	_equip(p, ["sword_1", "shield_str_1", "helmet_str_1", "body_str_1"], Item.Rarity.MAGIC, 3)
	p.refill_pools()
	var foes: Array = []
	for i in 5:
		var id := "zombie" if i == 4 else "skeleton_warrior"
		var e: Node3D = EnemyDB.spawn_enemy(id, stage + Vector3(-3.0 + i * 1.5, 0, -4.0 - (i % 2)), 3, 1 if i == 2 else 0, [], world)
		if e != null:
			foes.append(e)
	await _physics(3)
	_camera_on(p, 15.0)
	world.snap_light_pool()
	var kills := [0]
	var on_kill := func(_e: Node) -> void: kills[0] += 1
	Events.enemy_killed.connect(on_kill)
	var life_lost := [0.0]
	var on_hit := func(amount: float, _crit: bool, _src: Node) -> void: life_lost[0] += amount
	p.damaged.connect(on_hit)
	var shot_taken := false
	var potions := 0
	for f in 420:
		await get_tree().physics_frame
		if not is_instance_valid(p) or p.dead:
			break
		var t := CombatQuery.nearest_hostile(p.team, p.global_position, 40.0)
		if t == null:
			p.ai_stop()
			if f > 60:
				break
			continue
		var to := t.global_position - p.global_position
		to.y = 0.0
		p.ai_aim(t.global_position, t)
		if to.length() > 2.3:
			p.ai_hold_skill(0, false)
			p.ai_move(to.normalized())
		else:
			p.ai_move(Vector3.ZERO)
			p.ai_hold_skill(0, true)
		if p.life < p.max_life * 0.5 and not p.is_potion_active("life") and p.use_potion("life"):
			potions += 1
		if f == 150 and not shot_taken:
			await _save("fight")
			shot_taken = true
	p.ai_stop()
	Events.enemy_killed.disconnect(on_kill)
	if not shot_taken:
		await _save("fight")
	print("[player_demo] fight: %d/%d killed, life %.0f/%.0f, took %.0f damage, %d potions, xp %d, dead %s" % [
		kills[0], foes.size(), p.life, p.max_life, life_lost[0], potions, p.character.xp, p.dead])

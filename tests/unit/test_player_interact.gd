extends TestCase
## Hover + interaction: hovering Interactables (set_hovered, Events.hovered_target_changed), auto-
## walk + interact via ai_interact, path finding around obstacles (incl. solid cells that do not
## block sight, like pillars), WASD / skill press cancelling the walk, disabled targets, picking up
## a GroundItem, LMB on a hovered interactable through the CameraRig ray and push_input, and the
## Town Portal cast (dungeon only, 1 s rooted, emits once, cancelled by dodge / freeze / death).

const FakeRunner := preload("res://tests/unit/test_player_fake_runner.gd")


## An Interactable that counts interactions.
class CountTarget extends Interactable:
	var count := 0
	var last_player: Node = null

	func interact(player: Node) -> void:
		count += 1
		last_player = player


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _target(pos: Vector3) -> CountTarget:
	var t := CountTarget.new()
	t.display_name = "Lever"
	var sh := SphereShape3D.new()
	sh.radius = 0.7
	t.add_pick_shape(sh, Vector3(0, 0.8, 0))
	t.position = pos
	GameState.world.add_child(t)
	return t


## Wait until pred() is true or `max_frames` physics frames passed. Returns pred().
func _until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()


func test_hover_interactables() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var a := _target(Vector3(4, 0, 0))
	var b := _target(Vector3(-4, 0, 0))
	await _wait(2)
	var events: Array = []
	var cb := func(n: Node) -> void: events.append(n)
	Events.hovered_target_changed.connect(cb)
	p.ai_aim(Vector3(4, 0, 0), a)
	await _wait(2)
	assert_true(a.hovered, "a hovered")
	assert_eq(p.get_hovered(), a, "get_hovered")
	assert_eq(p.get_aim_target(), null, "an interactable is not a skill target")
	p.ai_aim(Vector3(-4, 0, 0), b)
	await _wait(2)
	assert_false(a.hovered, "a unhovered")
	assert_true(b.hovered, "b hovered")
	p.ai_aim(Vector3(0, 0, 5))
	await _wait(2)
	assert_false(b.hovered, "nothing hovered")
	assert_eq(p.get_hovered(), null, "hover cleared")
	assert_eq(events, [a, b, null], "one event per change")
	# A hovered node that gets freed reports null.
	p.ai_aim(Vector3(4, 0, 0), a)
	await _wait(2)
	a.queue_free()
	await _wait(3)
	assert_eq(p.get_hovered(), null, "freed node unhovered")
	assert_eq(events.back(), null, "event for the freed node")
	# A disabled interactable can't be hovered.
	b.enabled = false
	p.ai_aim(Vector3(-4, 0, 0), b)
	await _wait(2)
	assert_false(b.hovered, "disabled not hovered")
	Events.hovered_target_changed.disconnect(cb)


func test_auto_walk_interacts_once() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var t := _target(Vector3(9, 0, 3))
	await _wait(2)
	p.ai_interact(t)
	assert_true(p.is_auto_walking(), "walking")
	assert_eq(p.get_auto_walk_target(), t, "walk target")
	var ok := await _until(func() -> bool: return t.count > 0, 150)
	assert_true(ok, "reached and interacted")
	assert_eq(t.count, 1, "exactly once")
	assert_eq(t.last_player, p, "interact(player)")
	assert_false(p.is_auto_walking(), "walk over")
	var d := Vector2(p.global_position.x - 9, p.global_position.z - 3).length()
	assert_true(d <= t.get_interact_range() + 0.1, "stopped in range (%.2f)" % d)
	assert_true(d > t.get_interact_range() - 0.6, "did not walk further than needed (%.2f)" % d)
	var here := p.global_position
	await _wait(20)
	assert_true(p.global_position.distance_to(here) < 0.01, "stands still afterwards")
	assert_eq(t.count, 1, "no repeat")


func test_auto_walk_cancel_and_disabled() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var t := _target(Vector3(-10, 0, 0))
	await _wait(2)
	# WASD cancels.
	p.ai_interact(t)
	await _wait(10)
	p.ai_move(Vector3(0, 0, 1))
	await _wait(1)
	assert_false(p.is_auto_walking(), "movement input cancels the walk")
	p.ai_move(Vector3.ZERO)
	await _wait(80)
	assert_eq(t.count, 0, "never interacted")
	# A skill press cancels.
	p.ai_interact(t)
	await _wait(5)
	p.ai_hold_skill(0, true)
	p.ai_hold_skill(0, false)
	assert_false(p.is_auto_walking(), "skill press cancels the walk")
	# A target that becomes disabled stops the walk.
	p.ai_interact(t)
	await _wait(5)
	t.enabled = false
	await _wait(3)
	assert_false(p.is_auto_walking(), "disabled target ends the walk")
	await _wait(60)
	assert_eq(t.count, 0, "no interaction with a disabled target")
	# A freed target ends it too.
	t.enabled = true
	p.ai_interact(t)
	await _wait(3)
	t.queue_free()
	await _wait(3)
	assert_false(p.is_auto_walking(), "freed target ends the walk")


func test_auto_walk_paths_around_obstacles() -> void:
	var w := await make_world()
	make_character()
	# A 2 x 12 m block at x 2..4, z -6..6: solid cells that do NOT block line of sight (pillar-like).
	for j in range(6, 12):
		var cell := Vector2i(10, j)
		assert_eq(w.world_to_cell(w.grid.cell_center(cell)), cell, "cell mapping")
		w.grid.set_walkable(cell, false)
	w.grid.rebuild_astar()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 12)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(3, 1.5, 0)
	w.add_child(body)
	assert_true(w.has_line_of_sight(Vector3(-2, 0, 0), Vector3(8, 0, 0)), "block does not stop sight")
	var p := spawn_player(Vector3(-2, 0, 0))
	var t := _target(Vector3(8, 0, 0))
	await _wait(3)
	p.ai_interact(t)
	var ok := await _until(func() -> bool: return t.count > 0, 400)
	assert_true(ok, "walked around the block and interacted (at %s)" % p.global_position)
	assert_eq(t.count, 1, "once")


func test_pick_up_ground_item() -> void:
	await make_world()
	var c := make_character("ranger")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var item := ItemDB.create_item("ring_1", Item.Rarity.MAGIC, 3)
	var gi := LootSystem.spawn_item(item, Vector3(6, 0, -4))
	assert_not_null(gi, "spawned")
	await _wait(45)
	p.ai_aim(gi.global_position, gi)
	await _wait(2)
	assert_true(gi.hovered, "loot hovered")
	p.ai_interact(gi)
	var ok := await _until(func() -> bool: return c.find_inventory_index(item) >= 0, 150)
	assert_true(ok, "picked up into the inventory")
	await _wait(2)
	assert_false(is_instance_valid(gi), "ground item freed")
	assert_eq(p.get_hovered(), null, "hover cleared after pickup")


func test_click_through_camera_ray() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	var rig := CameraRig.new()
	rig.target = p
	GameState.world.add_child(rig)
	p.camera_rig = rig
	rig.snap_to_target()
	var t := _target(Vector3(5, 0, -3))
	await _wait(3)
	# Mouse over the lever (screen point of its pick sphere).
	rig.mouse_override = rig.camera.unproject_position(Vector3(5, 0.8, -3))
	await _wait(2)
	assert_eq(rig.get_hover_target(), t, "camera ray hits the lever")
	assert_true(t.hovered, "player hovers what the camera ray hits")
	assert_eq(p.get_hovered(), t, "get_hovered")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = rig.mouse_override
	get_viewport().push_input(mb, true)
	await _wait(1)
	assert_true(p.is_auto_walking(), "LMB on a hovered interactable walks there")
	var ok := await _until(func() -> bool: return t.count > 0, 150)
	assert_true(ok, "interacted after the click")
	# Mouse over empty ground: the ground point is the aim.
	rig.snap_to_target()
	rig.mouse_override = rig.camera.unproject_position(Vector3(-4, 0, 2))
	await _wait(2)
	assert_eq(p.get_hovered(), null, "nothing hovered")
	var aim := p.get_aim_position()
	assert_true(aim.distance_to(Vector3(-4, 0, 2)) < 0.05, "aim follows the mouse ground point (%s)" % aim)


func test_town_portal_cast() -> void:
	var w := await make_world()
	make_character("sorcerer")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var requests := [0]
	var cb := func() -> void: requests[0] += 1
	Events.town_portal_requested.connect(cb)
	# Not in a dungeon: ignored.
	assert_false(p.ai_town_portal(), "ignored outside dungeons")
	await _wait(70)
	assert_eq(requests[0], 0, "no request in the arena")
	w.area_info = {"id": "dungeon", "depth": 2, "level": 2}
	assert_true(p.ai_town_portal(), "cast starts in a dungeon")
	assert_true(p.is_casting_portal(), "casting")
	assert_eq(p.visuals.action_anim, "cast", "cast animation")
	assert_not_null(p.get_node_or_null("PortalCastFx"), "portal swirl VFX")
	p.ai_move(Vector3(1, 0, 0))
	await _wait(30)
	assert_true(absf(p.global_position.x) < 0.01, "rooted while casting")
	assert_between(p.get_portal_cast_ratio(), 0.4, 0.6, "half cast")
	assert_false(p.ai_town_portal(), "no second cast")
	await _wait(35)
	assert_eq(requests[0], 1, "town_portal_requested after 1 s")
	assert_false(p.is_casting_portal(), "cast over")
	await _wait(30)
	assert_eq(requests[0], 1, "emitted once")
	assert_true(p.global_position.x > 0.5, "free to move again")
	p.ai_move(Vector3.ZERO)
	# Dodge cancels.
	assert_true(p.ai_town_portal(), "second cast")
	await _wait(20)
	p.ai_dodge(Vector3(-1, 0, 0))
	assert_false(p.is_casting_portal(), "dodge cancels")
	await _wait(1)
	assert_true(p.get_node_or_null("PortalCastFx") == null, "VFX removed")
	await _wait(80)
	assert_eq(requests[0], 1, "no request after a cancelled cast")
	# Freeze cancels.
	assert_true(p.ai_town_portal(), "third cast")
	await _wait(10)
	p.apply_ailment("freeze", {"duration": 0.3})
	assert_false(p.is_casting_portal(), "freeze cancels")
	await _wait(80)
	assert_eq(requests[0], 1, "still one")
	# Death cancels.
	assert_true(p.ai_town_portal(), "fourth cast")
	await _wait(10)
	p.die(null)
	assert_false(p.is_casting_portal(), "death cancels")
	await _wait(70)
	assert_eq(requests[0], 1, "never after death")
	Events.town_portal_requested.disconnect(cb)


func test_town_portal_waits_for_a_busy_skill() -> void:
	var w := await make_world()
	w.area_info = {"id": "dungeon", "depth": 1, "level": 1}
	make_character("warrior")
	var p := Player.new()
	p.setup(GameState.character)
	var r := FakeRunner.new()
	r.fk_use_time = 0.15
	p.skill_runner = r
	w.add_child(p)
	GameState.player = p
	await _wait(2)
	p.ai_hold_skill(0, true)
	await _wait(2)
	p.ai_hold_skill(0, false)
	assert_true(r.is_busy(), "busy")
	assert_false(p.ai_town_portal(), "can't start while busy")
	await _wait(15)
	assert_true(p.is_casting_portal(), "the buffered T press starts the cast when the skill ends")

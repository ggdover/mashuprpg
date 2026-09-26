extends TestCase
## CameraRig: placement (pitch 56°, yaw 0 looking toward -Z, FOV 45, distance 18), smooth follow
## and snap, mouse ground position with mouse_override (round trip through unproject), hover ray
## (mask 28: enemies / loot / interactables, not allies / walls), wheel zoom (clamped 11..26),
## shake, the player_world_pos shader global, the AudioListener3D, and big-hit shakes.


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _procs(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _rig_for(p: Node3D) -> CameraRig:
	var rig := CameraRig.new()
	rig.target = p
	GameState.world.add_child(rig)
	if p is Player:
		(p as Player).camera_rig = rig
	rig.snap_to_target()
	return rig


func test_placement_and_follow() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3(5, 0, 3))
	var rig := _rig_for(p)
	await _wait(2)
	var cam := rig.camera
	assert_not_null(cam, "camera")
	assert_true(cam.current, "current camera")
	assert_near(cam.fov, 45.0, 0.001, "fov 45")
	assert_eq(cam.projection, Camera3D.PROJECTION_PERSPECTIVE, "perspective")
	assert_near(rig.distance, 18.0, 0.001, "default distance 18")
	var focus := rig.get_focus_point()
	assert_true(focus.distance_to(Vector3(5, CameraRig.FOCUS_HEIGHT, 3)) < 0.01, "focus on the player")
	var fwd := -cam.global_transform.basis.z
	assert_near(rad_to_deg(asin(-fwd.y)), 56.0, 0.1, "pitch 56° down")
	assert_near(fwd.x, 0.0, 0.0001, "yaw 0")
	assert_true(fwd.z < 0.0, "looking toward -Z")
	assert_near(cam.global_position.distance_to(focus), 18.0, 0.01, "18 m from the focus")
	# The camera looks at the focus point.
	var to_focus := (focus - cam.global_position).normalized()
	assert_near(to_focus.dot(fwd), 1.0, 0.0001, "focus centred")
	assert_eq(CameraRig.offset_for_distance(10.0).length(), 10.0, "offset length = distance")
	# Smooth follow, then snap.
	p.global_position = Vector3(-6, 0, 0)
	await _procs(2)
	assert_true(rig.get_focus_point().distance_to(Vector3(-6, CameraRig.FOCUS_HEIGHT, 0)) > 1.0, "follows smoothly (not instantly)")
	await _wait(90)
	await _procs(1)
	assert_true(rig.get_focus_point().distance_to(Vector3(-6, CameraRig.FOCUS_HEIGHT, 0)) < 0.05, "caught up")
	p.global_position = Vector3(8, 0, -8)
	rig.snap_to_target()
	assert_true(rig.get_focus_point().distance_to(Vector3(8, CameraRig.FOCUS_HEIGHT, -8)) < 0.01, "snap_to_target")
	# Audio listener at the focus, current.
	assert_not_null(rig.listener, "AudioListener3D")
	assert_true(rig.listener.is_current(), "listener current")
	# The wall cut-out shader global follows the player.
	await _procs(1)
	var v: Variant = RenderingServer.global_shader_parameter_get("player_world_pos")
	if v is Vector3:
		assert_true((v as Vector3).distance_to(p.global_position) < 0.01, "player_world_pos = player position")


func test_mouse_ground_position() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3(2, 0, -3))
	var rig := _rig_for(p)
	await _wait(2)
	# Centre of the screen hits the ground a bit beyond the focus (the focus is 0.8 m up).
	var size := rig.get_viewport().get_visible_rect().size
	rig.mouse_override = size * 0.5
	var g := rig.get_mouse_ground_position()
	var expect := Vector3(2, 0, -3 - CameraRig.FOCUS_HEIGHT / tan(deg_to_rad(CameraRig.PITCH_DEG)))
	assert_true(g.distance_to(expect) < 0.02, "centre ray hits %s (got %s)" % [expect, g])
	# Round trip: world -> screen -> ground.
	for pt in [Vector3(-5, 0, 4), Vector3(9, 0, -7), Vector3(2.5, 0, -3.5)]:
		rig.mouse_override = rig.camera.unproject_position(pt)
		assert_true(rig.get_mouse_ground_position().distance_to(pt) < 0.01, "round trip %s" % pt)
		var raised := rig.get_mouse_ground_position(1.0)
		assert_near(raised.y, 1.0, 0.0001, "other plane height")
	# Vector2i overrides work too; null = the real mouse.
	rig.mouse_override = Vector2i(int(size.x * 0.5), int(size.y * 0.5))
	assert_true(rig.get_mouse_ground_position().distance_to(expect) < 0.1, "Vector2i override")
	rig.mouse_override = null
	assert_eq(rig.get_mouse_screen_position(), rig.get_viewport().get_mouse_position(), "real mouse")


func test_hover_ray() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var rig := _rig_for(p)
	var enemy := spawn_dummy(Actor.Team.ENEMY, Vector3(6, 0, 0), 100.0)
	var ally := spawn_dummy(Actor.Team.PLAYER, Vector3(-6, 0, 0), 100.0)
	var gate := Interactable.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.6
	gate.add_pick_shape(sh, Vector3(0, 0.6, 0))
	gate.position = Vector3(0, 0, -7)
	GameState.world.add_child(gate)
	await _wait(3)
	rig.mouse_override = rig.camera.unproject_position(Vector3(6, 1.0, 0))
	assert_eq(rig.get_hover_target(), enemy, "enemy under the mouse")
	rig.mouse_override = rig.camera.unproject_position(Vector3(0, 0.6, -7))
	assert_eq(rig.get_hover_target(), gate, "interactable under the mouse")
	gate.enabled = false
	assert_eq(rig.get_hover_target(), null, "disabled interactable ignored")
	rig.mouse_override = rig.camera.unproject_position(Vector3(-6, 1.0, 0))
	assert_eq(rig.get_hover_target(), null, "allies are not hover targets")
	rig.mouse_override = rig.camera.unproject_position(Vector3(3, 0, 5))
	assert_eq(rig.get_hover_target(), null, "empty ground")
	# Slightly off the enemy's body: the screen-space fallback still picks it.
	var s := rig.camera.unproject_position(Vector3(6, 1.0, 0))
	rig.mouse_override = s + Vector2(0, -rig.get_viewport().get_visible_rect().size.y * 0.02)
	assert_eq(rig.get_hover_target(), enemy, "near miss still targets the enemy")
	enemy.die(null)
	rig.mouse_override = rig.camera.unproject_position(Vector3(6, 1.0, 0))
	assert_eq(rig.get_hover_target(), null, "dead enemies are not hovered")
	assert_eq(ally.team, Actor.Team.PLAYER, "ally team")


func test_zoom_and_shake() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var rig := _rig_for(p)
	await _wait(2)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(400, 300)
	get_viewport().push_input(wheel, true)
	await _procs(1)
	assert_near(rig.zoom_target, 18.0 - CameraRig.ZOOM_STEP, 0.001, "wheel up zooms in")
	for i in 20:
		rig.zoom_by(-1)
	assert_near(rig.zoom_target, CameraRig.MIN_DISTANCE, 0.001, "clamped at 11")
	for i in 30:
		rig.zoom_by(1)
	assert_near(rig.zoom_target, CameraRig.MAX_DISTANCE, 0.001, "clamped at 26")
	await _wait(60)
	await _procs(1)
	assert_near(rig.distance, CameraRig.MAX_DISTANCE, 0.05, "distance eases to the target")
	assert_near(rig.camera.global_position.distance_to(rig.get_focus_point()), rig.distance, 0.01, "camera at the zoom distance")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	down.position = Vector2(400, 300)
	rig.zoom_by(-4)
	var zt := rig.zoom_target
	get_viewport().push_input(down, true)
	await _procs(1)
	assert_near(rig.zoom_target, zt + CameraRig.ZOOM_STEP, 0.001, "wheel down zooms out")
	# Shake.
	rig.shake(0.4, 0.3)
	assert_true(rig.is_shaking(), "shaking")
	var moved := false
	for i in 8:
		await _procs(1)
		if absf(rig.camera.h_offset) > 0.001 or absf(rig.camera.v_offset) > 0.001:
			moved = true
	assert_true(moved, "the view shakes")
	await _wait(30)
	await _procs(2)
	assert_false(rig.is_shaking(), "shake over")
	assert_near(rig.camera.h_offset, 0.0, 0.0001, "h offset reset")
	assert_near(rig.camera.v_offset, 0.0, 0.0001, "v offset reset")


func test_big_hits_shake_the_camera() -> void:
	await make_world()
	make_character()
	var p := spawn_player(Vector3.ZERO)
	var rig := _rig_for(p)
	await _wait(2)
	p.take_damage(p.max_life * 0.08, "physical")
	assert_false(rig.is_shaking(), "small hits don't shake")
	p.take_damage(p.max_life * 0.2, "physical")
	assert_true(rig.is_shaking(), "hits > 15% of max life shake")

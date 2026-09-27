extends TestCase
## Free camera: middle-mouse orbit (yaw / pitch), limits, reset, the F2 camera info overlay (text,
## wider zoom range) and camera-relative movement. OWNER: player.


func _exit_tree() -> void:
	CameraRig.saved_view = {}


func test_orbit_and_info() -> void:
	var w := await make_world()
	var p := spawn_player(Vector3.ZERO)
	var rig := CameraRig.new()
	rig.target = p
	w.add_child(rig)
	p.camera_rig = rig
	rig.snap_to_target()
	await get_tree().process_frame
	assert_near(rig.yaw_deg, CameraRig.YAW_DEG, 0.001, "default yaw")
	assert_near(rig.pitch_deg, CameraRig.PITCH_DEG, 0.001, "default pitch")
	rig.yaw_deg = 0.0
	rig.orbit_by(Vector2(-120, 0))
	assert_near(rig.yaw_deg, 30.0, 0.001, "mouse left 120 px = yaw +30")
	var p0 := rig.pitch_deg
	rig.orbit_by(Vector2(0, -80))
	assert_near(rig.pitch_deg, p0 - 20.0, 0.001, "mouse up = lower pitch")
	rig.orbit_by(Vector2(0, -10000))
	assert_near(rig.pitch_deg, CameraRig.PITCH_MIN, 0.001, "pitch clamped low")
	rig.orbit_by(Vector2(0, 10000))
	assert_near(rig.pitch_deg, CameraRig.PITCH_MAX, 0.001, "pitch clamped high")
	rig.pitch_deg = 40.0
	await get_tree().process_frame
	var off := rig.camera.global_position - rig.get_focus_point()
	assert_true(off.distance_to(CameraRig.offset_for(rig.distance, 30.0, 40.0)) < 0.05, "camera placed by yaw/pitch")
	# Camera-relative movement: "up" moves away from the camera.
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(rig.yaw_deg))
	var away := -Vector3(off.x, 0, off.z).normalized()
	assert_true(fwd.dot(away) > 0.99, "forward = away from the camera")
	# Info overlay.
	rig.set_camera_info_visible(true)
	assert_true(rig.is_camera_info_visible(), "overlay shown")
	var txt := rig.get_camera_info_text()
	assert_true(txt.contains("yaw 30.0") and txt.contains("pitch 40.0") and txt.contains("camera position"), "overlay text")
	for i in 60:
		rig.zoom_by(1)
	assert_near(rig.zoom_target, CameraRig.TUNE_MAX_DISTANCE, 0.001, "wide zoom range while tuning")
	rig.set_camera_info_visible(false)
	assert_near(rig.zoom_target, CameraRig.MAX_DISTANCE, 0.001, "back in the normal range")
	rig.reset_view()
	assert_near(rig.yaw_deg, CameraRig.YAW_DEG, 0.001, "reset yaw")
	assert_near(rig.pitch_deg, CameraRig.PITCH_DEG, 0.001, "reset pitch")

class_name CameraRig
extends Node3D
## Isometric-style follow camera (perspective, ~50 degree pitch, looking north-west by default;
## free orbit with the right mouse button), zoom on mouse wheel, screen
## shake, mouse picking, and the audio listener. Also updates the global shader parameter
## "player_world_pos" every frame (wall cut-out shader). OWNER: player (wave 2).
## CONTRACT — keep every public member/signature. See docs/ARCHITECTURE.md §11.4.
##
## Layout (§11.4): the rig is a child of the World (not of the Player). The rig node sits at the
## smoothed focus point (target position + FOCUS_HEIGHT); the Camera3D is its child at
## distance d along the view direction: local offset (0, sin(pitch)·d, cos(pitch)·d), rotated
## -pitch about X (yaw 0: looking toward -Z, screen-up = world -Z). Default (PRESETS "diagonal"):
## yaw 37.5°, pitch 49.4°, distance 19.5 m; the older straight view was yaw 0°, pitch 56°, distance
## 18 (wheel zoom 11..26 in _unhandled_input, ignored while the mouse is over UI). An
## AudioListener3D sits at the focus point.
##
## Picking: get_mouse_ground_position() intersects the mouse ray with a horizontal plane;
## get_hover_target() ray-casts mask 28 (enemies, loot, interactables; areas and bodies), and
## falls back to the living hostile actor drawn nearest to the cursor (within
## HOVER_SCREEN_SLACK px), so enemies are easy to target. Both use `mouse_override` (a viewport
## position like get_viewport().get_mouse_position(), e.g. from camera.unproject_position())
## instead of the real mouse when it is set; the UI check is skipped then.

const FOV := 45.0
## The default view (the "diagonal" preset): looking north-west from the south-east.
const PITCH_DEG := 49.4
const YAW_DEG := 37.5
const DEFAULT_DISTANCE := 19.5
## Camera presets (the debug menu switches; Home in the camera overlay returns to the current one):
## "diagonal" = the default, "straight" = looking north.
const PRESETS := {
	"diagonal": {"yaw": 37.5, "pitch": 49.4, "distance": 19.5, "label": "Diagonal (yaw 37.5°)"},
	"straight": {"yaw": 0.0, "pitch": 54.1, "distance": 19.5, "label": "Straight (yaw 0°)"},
}
const MIN_DISTANCE := 11.0
const MAX_DISTANCE := 26.0
const ZOOM_STEP := 1.5
## Follow / zoom smoothing rates (1/s, exponential).
const FOLLOW_RATE := 9.0
const ZOOM_RATE := 12.0
## The camera looks at this height above the target's feet (chest), so the character is centred.
const FOCUS_HEIGHT := 0.8
const HOVER_MASK := 4 | 8 | 16
const HOVER_RAY_LENGTH := 250.0
## Proximity fallback for enemies: max screen distance (px at 1080p) from the cursor to an
## enemy's body line (feet .. head).
const HOVER_SCREEN_SLACK := 34.0
const HOVER_ENEMY_HEIGHT := 1.7
## Shake: offsets are strength * noise * (time_left / duration) metres.
const SHAKE_FREQ := 28.0

var target: Node3D = null
var camera: Camera3D = null
## Screen position used instead of the real mouse (tests, screenshot tour, bot). null = real mouse.
var mouse_override: Variant = null
## Current (smoothed) camera distance and the wheel-zoom target.
var distance: float = float(PRESETS[preset]["distance"])
var zoom_target: float = float(PRESETS[preset]["distance"])
var listener: AudioListener3D = null

## Free camera (WoW style): hold the right mouse button (ORBIT_BUTTON) and move the mouse to orbit around the
## player. Current yaw / pitch (degrees); PITCH_DEG / YAW_DEG are the defaults.
var yaw_deg: float = float(PRESETS[preset]["yaw"])
var pitch_deg: float = float(PRESETS[preset]["pitch"])
## Wheel zoom range (widened while the camera info overlay is shown).
var min_distance: float = MIN_DISTANCE
var max_distance: float = MAX_DISTANCE
## The mouse button that orbits the camera while held.
const ORBIT_BUTTON := MOUSE_BUTTON_RIGHT
## Orbit sensitivity (degrees per pixel) and pitch limits.
const ORBIT_SENSITIVITY := 0.25
const PITCH_MIN := 5.0
const PITCH_MAX := 89.0
## Zoom / FOV ranges while tuning (camera info overlay, F2).
const TUNE_MIN_DISTANCE := 3.0
const TUNE_MAX_DISTANCE := 80.0

## The last view (yaw, pitch, fov, info overlay), carried over to the next rig (area changes).
static var saved_view: Dictionary = {}
## The preset new rigs and reset_view() use.
static var preset := "diagonal"

var _orbiting := false
var _orbit_mouse := Vector2.ZERO
var _info_layer: CanvasLayer = null
var _info_label: Label = null
var _focus := Vector3.ZERO
var _has_focus := false
var _shake_strength := 0.0
var _shake_duration := 0.0
var _shake_left := 0.0
var _shake_t := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = FOV
	camera.near = 0.3
	camera.far = 300.0
	add_child(camera)
	listener = AudioListener3D.new()
	listener.name = "Listener"
	listener.position = Vector3(0, 0.3, 0)
	add_child(listener)
	camera.make_current()
	listener.make_current()
	top_level = true
	if not saved_view.is_empty():
		yaw_deg = float(saved_view.get("yaw", YAW_DEG))
		pitch_deg = float(saved_view.get("pitch", PITCH_DEG))
		camera.fov = float(saved_view.get("fov", FOV))
		if bool(saved_view.get("info", false)):
			set_camera_info_visible(true)
			zoom_target = float(saved_view.get("zoom", zoom_target))
	snap_to_target()


func _exit_tree() -> void:
	if _orbiting:
		_set_orbiting(false)
	_save_view()


func _save_view() -> void:
	if camera == null:
		return
	saved_view = {"yaw": yaw_deg, "pitch": pitch_deg, "fov": camera.fov, "info": is_camera_info_visible(), "zoom": zoom_target}


func _process(delta: float) -> void:
	var t: Variant = _target_pos()
	if t != null:
		var tp: Vector3 = t
		if not _has_focus:
			_focus = tp
			_has_focus = true
		else:
			_focus = _focus.lerp(tp, 1.0 - exp(-FOLLOW_RATE * delta))
		RenderingServer.global_shader_parameter_set("player_world_pos", tp)
	distance = lerpf(distance, zoom_target, 1.0 - exp(-ZOOM_RATE * delta))
	if absf(distance - zoom_target) < 0.001:
		distance = zoom_target
	_update_shake(delta)
	_apply()
	if _info_label != null and _info_layer.visible:
		_info_label.text = get_camera_info_text()


func _unhandled_input(event: InputEvent) -> void:
	# Free camera: right mouse drag orbits.
	if event is InputEventMouseButton and event.button_index == ORBIT_BUTTON:
		if event.pressed and not _orbiting and not UI.is_mouse_over_ui():
			_set_orbiting(true)
			get_viewport().set_input_as_handled()
		elif not event.pressed and _orbiting:
			_set_orbiting(false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbiting:
		orbit_by(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("toggle_camera_info"):
			set_camera_info_visible(not is_camera_info_visible())
			get_viewport().set_input_as_handled()
		elif is_camera_info_visible():
			var k := (event as InputEventKey).keycode
			if k == KEY_HOME:
				reset_view()
			elif k == KEY_PAGEUP:
				camera.fov = clampf(camera.fov - 5.0, 15.0, 100.0)
			elif k == KEY_PAGEDOWN:
				camera.fov = clampf(camera.fov + 5.0, 15.0, 100.0)
			elif k == KEY_C and (event as InputEventKey).ctrl_pressed:
				DisplayServer.clipboard_set(get_camera_info_text())
				Events.notify.emit("Camera values copied to the clipboard", UIStyle.COLOR_GOOD)
			else:
				return
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton) or not event.is_pressed():
		return
	var steps := 0
	if event.is_action_pressed("zoom_in"):
		steps = -1
	elif event.is_action_pressed("zoom_out"):
		steps = 1
	if steps == 0:
		return
	if UI.is_mouse_over_ui():
		return
	zoom_by(steps)
	get_viewport().set_input_as_handled()


## Change the zoom target by `steps` wheel notches (negative = closer), clamped to 11..26 m
## (3..80 m while the camera info overlay is shown).
func zoom_by(steps: float) -> void:
	zoom_target = clampf(zoom_target + steps * ZOOM_STEP, min_distance, max_distance)


## Orbit by a mouse movement in pixels (right = turn right, down = look more from above).
func orbit_by(rel: Vector2) -> void:
	yaw_deg = wrapf(yaw_deg - rel.x * ORBIT_SENSITIVITY, -180.0, 180.0)
	pitch_deg = clampf(pitch_deg + rel.y * ORBIT_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	_apply()


## Back to the current preset's angle and distance, and the default FOV.
func reset_view() -> void:
	var pr: Dictionary = PRESETS.get(preset, PRESETS["diagonal"])
	yaw_deg = float(pr["yaw"])
	pitch_deg = float(pr["pitch"])
	zoom_target = float(pr["distance"])
	if camera != null:
		camera.fov = FOV
	_save_view()
	Events.notify.emit("Camera: %s" % String(pr["label"]), UIStyle.COLOR_TEXT_DIM)


## Switch the default view ("diagonal" / "straight") and apply it.
static func set_preset(id: String) -> void:
	preset = id if PRESETS.has(id) else "diagonal"
	saved_view = {}


func is_camera_info_visible() -> bool:
	return _info_layer != null and _info_layer.visible


## Camera info overlay (F2): the numbers of the current view, plus a wider zoom range.
func set_camera_info_visible(on: bool) -> void:
	if on and _info_layer == null:
		_info_layer = CanvasLayer.new()
		_info_layer.layer = 50
		add_child(_info_layer)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0, 0, 0, 0.72), UIStyle.COLOR_BORDER, 1, 4))
		panel.position = Vector2(470, 18)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_info_layer.add_child(panel)
		_info_label = Label.new()
		_info_label.add_theme_font_size_override("font_size", UIStyle.FONT_SMALL)
		_info_label.add_theme_color_override("font_color", UIStyle.COLOR_TEXT)
		panel.add_child(_info_label)
	if _info_layer != null:
		_info_layer.visible = on
	min_distance = TUNE_MIN_DISTANCE if on else MIN_DISTANCE
	max_distance = TUNE_MAX_DISTANCE if on else MAX_DISTANCE
	if not on:
		zoom_target = clampf(zoom_target, MIN_DISTANCE, MAX_DISTANCE)


## The current view as text (shown by the overlay, copied with Ctrl+C).
func get_camera_info_text() -> String:
	var fp := get_focus_point()
	var cp := camera.global_position if camera != null and camera.is_inside_tree() else fp + offset_for(distance, yaw_deg, pitch_deg)
	var t: Variant = _target_pos()
	var pp: Vector3 = t if t != null else _focus
	var rel := cp - pp
	return "\n".join([
		"CAMERA  (F2 hide · right mouse orbit · wheel zoom · PgUp/PgDn FOV · Home reset · Ctrl+C copy)",
		"yaw %.1f°   pitch %.1f°   distance %.2f m   FOV %.0f°   focus height %.2f m" % [yaw_deg, pitch_deg, distance, camera.fov if camera != null else FOV, FOCUS_HEIGHT],
		"camera position  (%.2f, %.2f, %.2f)" % [cp.x, cp.y, cp.z],
		"camera offset from player  (%.2f, %.2f, %.2f)   height above ground %.2f m" % [rel.x, rel.y, rel.z, cp.y],
		"player position  (%.2f, %.2f, %.2f)" % [pp.x, pp.y, pp.z],
		"look-at point  (%.2f, %.2f, %.2f)" % [fp.x, fp.y, fp.z],
	])


func _set_orbiting(on: bool) -> void:
	_orbiting = on
	if on:
		_orbit_mouse = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.warp_mouse(_orbit_mouse)


## Where the mouse ray hits the horizontal plane y = plane_y.
func get_mouse_ground_position(plane_y: float = 0.0) -> Vector3:
	var fallback := _fallback_ground(plane_y)
	if camera == null or not camera.is_inside_tree():
		return fallback
	var screen := get_mouse_screen_position()
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return fallback
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return fallback
	return from + dir * t


## Enemy (layer 3), GroundItem (layer 4) or Interactable (layer 5) under the mouse, else null.
## Ray: collision_mask = 4 | 8 | 16 (= 28), collide_with_areas and bodies. Returns null while
## UI.is_mouse_over_ui().
func get_hover_target() -> Node:
	if mouse_override == null and UI.is_mouse_over_ui():
		return null
	if camera == null or not camera.is_inside_tree():
		return null
	var screen := get_mouse_screen_position()
	var from := camera.project_ray_origin(screen)
	var to := from + camera.project_ray_normal(screen) * HOVER_RAY_LENGTH
	var q := PhysicsRayQueryParameters3D.create(from, to, HOVER_MASK)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space != null:
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var c: Object = hit.get("collider")
			if _is_hoverable(c):
				return c as Node
	return _nearest_enemy_on_screen(screen)


## The mouse position used for picking (mouse_override when set).
func get_mouse_screen_position() -> Vector2:
	if mouse_override is Vector2:
		return mouse_override
	if mouse_override is Vector2i:
		return Vector2(mouse_override)
	var vp := get_viewport()
	return vp.get_mouse_position() if vp != null else Vector2.ZERO


func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	# Keep the stronger of the running and the new shake.
	var cur := _shake_strength * (_shake_left / _shake_duration) if _shake_left > 0.0 and _shake_duration > 0.0 else 0.0
	if strength >= cur:
		_shake_strength = strength
		_shake_duration = duration
		_shake_left = duration


## True while a shake is running.
func is_shaking() -> bool:
	return _shake_left > 0.0


## Snap to the target immediately (after teleports / area changes).
func snap_to_target() -> void:
	var t: Variant = _target_pos()
	if t != null:
		_focus = t
		_has_focus = true
		if is_inside_tree():
			RenderingServer.global_shader_parameter_set("player_world_pos", t)
	distance = zoom_target
	_shake_left = 0.0
	_apply()


## The point the camera looks at (smoothed target position + FOCUS_HEIGHT).
func get_focus_point() -> Vector3:
	return _focus + Vector3(0, FOCUS_HEIGHT, 0)


## Camera offset from the focus point for a distance (default pitch 56°, yaw 0).
static func offset_for_distance(d: float) -> Vector3:
	return offset_for(d, YAW_DEG, PITCH_DEG)


## Camera offset from the focus point for a distance, yaw and pitch (degrees).
static func offset_for(d: float, yaw: float, pitch: float) -> Vector3:
	var p := deg_to_rad(pitch)
	return Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0.0, sin(p) * d, cos(p) * d)


# ------------------------------------------------------------------ internals

func _target_pos() -> Variant:
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		# Follow where the target is drawn (the Player interpolates its model between physics
		# ticks), so the view stays smooth on screens faster than the physics rate.
		if target.has_method("get_visual_position"):
			return target.call("get_visual_position")
		if get_tree().physics_interpolation:
			return target.get_global_transform_interpolated().origin
		return target.global_position
	return null


func _apply() -> void:
	if camera == null:
		return
	var fp := get_focus_point()
	if is_inside_tree():
		global_transform = Transform3D(Basis.IDENTITY, fp)
	else:
		transform = Transform3D(Basis.IDENTITY, fp)
	camera.position = offset_for(distance, yaw_deg, pitch_deg)
	camera.rotation = Vector3(-deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)


func _update_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake_left <= 0.0:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	_shake_t += delta
	var k := _shake_strength * (_shake_left / maxf(_shake_duration, 0.001))
	k *= k / maxf(_shake_strength, 0.001)   # quadratic falloff
	camera.h_offset = k * (sin(_shake_t * SHAKE_FREQ) * 0.7 + sin(_shake_t * SHAKE_FREQ * 2.3 + 1.3) * 0.3)
	camera.v_offset = k * (sin(_shake_t * SHAKE_FREQ * 1.3 + 0.7) * 0.7 + sin(_shake_t * SHAKE_FREQ * 2.9) * 0.3)


func _fallback_ground(plane_y: float) -> Vector3:
	var t: Variant = _target_pos()
	var p: Vector3 = t if t != null else _focus
	return Vector3(p.x, plane_y, p.z)


func _is_hoverable(c: Object) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if c is Interactable:
		return (c as Interactable).enabled
	if c is Actor:
		var a := c as Actor
		return not a.dead and a.team != Actor.Team.PLAYER and a.is_visible_in_tree()
	return false


## Living hostile actor whose body (feet..head line on screen) is nearest the cursor, within
## HOVER_SCREEN_SLACK pixels (scaled to the viewport height); null if none.
func _nearest_enemy_on_screen(screen: Vector2) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var vp_h := 1080.0
	var vp := get_viewport()
	if vp != null:
		vp_h = maxf(1.0, vp.get_visible_rect().size.y)
	var slack := HOVER_SCREEN_SLACK * vp_h / 1080.0
	var best: Node = null
	var best_d := slack
	for n in tree.get_nodes_in_group("team_%d" % Actor.Team.ENEMY):
		var a := n as Actor
		if a == null or a.dead or not a.is_inside_tree() or not a.is_visible_in_tree():
			continue
		var feet := a.global_position
		var head := feet + Vector3(0, HOVER_ENEMY_HEIGHT * maxf(0.6, a.scale.y), 0)
		if camera.is_position_behind(feet):
			continue
		var s0 := camera.unproject_position(feet)
		var s1 := camera.unproject_position(head)
		var d := Geometry2D.get_closest_point_to_segment(screen, s0, s1).distance_to(screen)
		if d < best_d:
			best_d = d
			best = a
	return best

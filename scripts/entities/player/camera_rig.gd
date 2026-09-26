class_name CameraRig
extends Node3D
## Isometric-style follow camera (perspective, ~55 degree pitch), zoom on mouse wheel, screen
## shake, mouse picking, and the audio listener. Also updates the global shader parameter
## "player_world_pos" every frame (wall cut-out shader). OWNER: player (wave 2).
## CONTRACT — keep every public member/signature. See docs/ARCHITECTURE.md §11.4.
##
## Layout (§11.4): the rig is a child of the World (not of the Player). The rig node sits at the
## smoothed focus point (target position + FOCUS_HEIGHT); the Camera3D is its child at
## distance d along the view direction: local offset (0, sin(pitch)·d, cos(pitch)·d), rotated
## -pitch about X (yaw 0: looking toward -Z, screen-up = world -Z). FOV 45°, pitch 56°, distance
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
const PITCH_DEG := 56.0
const YAW_DEG := 0.0
const DEFAULT_DISTANCE := 18.0
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
var distance: float = DEFAULT_DISTANCE
var zoom_target: float = DEFAULT_DISTANCE
var listener: AudioListener3D = null

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
	snap_to_target()


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


func _unhandled_input(event: InputEvent) -> void:
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


## Change the zoom target by `steps` wheel notches (negative = closer), clamped to 11..26 m.
func zoom_by(steps: float) -> void:
	zoom_target = clampf(zoom_target + steps * ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)


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


## Camera offset from the focus point for a distance (pitch 56°, yaw 0).
static func offset_for_distance(d: float) -> Vector3:
	var p := deg_to_rad(PITCH_DEG)
	return Basis(Vector3.UP, deg_to_rad(YAW_DEG)) * Vector3(0.0, sin(p) * d, cos(p) * d)


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
	camera.position = offset_for_distance(distance)
	camera.rotation = Vector3(-deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0)


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

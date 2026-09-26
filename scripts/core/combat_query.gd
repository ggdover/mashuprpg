class_name CombatQuery
extends RefCounted
## Spatial queries over live Actors (group "actors"), used by skills and AI instead of physics
## overlap tests. Distances are measured on the XZ plane and include the target's
## get_collision_radius(). Dead actors are never returned. Hostile = a different `team`.
## OWNER: kernel (wave 1). Keep every public signature.

const WORLD_MASK := 1  # physics layer 1 "world"
## Height at which line-of-sight rays are cast.
const LOS_HEIGHT := 1.0
## Points lower than this are treated as floor positions by raycast_world (raised to LOS_HEIGHT).
const FLOOR_EPSILON := 0.2


## Every live Actor in the tree (group "actors", not dead).
static func get_actors() -> Array[Actor]:
	var out: Array[Actor] = []
	var tree := _tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("actors"):
		var a := n as Actor
		if a != null and not a.dead and a.is_inside_tree():
			out.append(a)
	return out


## All living actors hostile to `team`.
static func get_hostiles(team: int) -> Array[Actor]:
	var out: Array[Actor] = []
	var tree := _tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("actors"):
		var a := n as Actor
		if a != null and a.team != team and not a.dead and a.is_inside_tree():
			out.append(a)
	return out


## All living actors on `team` (allies, the caster included).
static func get_allies(team: int) -> Array[Actor]:
	var out: Array[Actor] = []
	var tree := _tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("actors"):
		var a := n as Actor
		if a != null and a.team == team and not a.dead and a.is_inside_tree():
			out.append(a)
	return out


## True when both are valid Actors on different teams. The parameters are untyped on purpose, so a
## stored reference that has been freed since can be passed as is (-> false, no script error).
static func is_hostile(a: Variant, b: Variant) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var aa := a as Actor
	var bb := b as Actor
	return aa != null and bb != null and aa.team != bb.team


## Distance on the XZ plane.
static func distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## XZ distance from `pos` to the EDGE of the actor's collision circle (0 when inside it).
static func distance_to_actor(pos: Vector3, a: Actor) -> float:
	return maxf(0.0, distance_xz(pos, a.global_position) - a.get_collision_radius())


static func hostiles_in_radius(team: int, center: Vector3, radius: float) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in get_hostiles(team):
		var r := radius + a.get_collision_radius()
		var p := a.global_position
		var dx := p.x - center.x
		var dz := p.z - center.z
		if dx * dx + dz * dz <= r * r:
			out.append(a)
	return out


## Allies of `team` within radius (buffs / warcries around the caster).
static func allies_in_radius(team: int, center: Vector3, radius: float) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in get_allies(team):
		var r := radius + a.get_collision_radius()
		var p := a.global_position
		var dx := p.x - center.x
		var dz := p.z - center.z
		if dx * dx + dz * dz <= r * r:
			out.append(a)
	return out


## Hostiles within `radius` of `origin` and within `angle_deg` total cone width around `dir`.
## The target's collision circle counts: a target whose circle overlaps the cone edge is hit.
static func hostiles_in_cone(team: int, origin: Vector3, dir: Vector3, radius: float, angle_deg: float) -> Array[Actor]:
	var out: Array[Actor] = []
	var d2 := Vector2(dir.x, dir.z)
	if d2.length_squared() < 0.000001:
		return hostiles_in_radius(team, origin, radius)
	d2 = d2.normalized()
	var half := deg_to_rad(clampf(angle_deg, 0.0, 360.0)) * 0.5
	for a in get_hostiles(team):
		var cr := a.get_collision_radius()
		var p := a.global_position
		var v := Vector2(p.x - origin.x, p.z - origin.z)
		var dist := v.length()
		if dist > radius + cr:
			continue
		if dist <= cr or half >= PI:
			out.append(a)
			continue
		var ang := absf(d2.angle_to(v))
		# Widen the cone by the angular size of the target's circle.
		var slack := asin(clampf(cr / dist, 0.0, 1.0))
		if ang <= half + slack:
			out.append(a)
	return out


## Hostiles whose circle intersects the capsule from->to of `width` radius, sorted by distance
## from `from`.
static func hostiles_along_segment(team: int, from: Vector3, to: Vector3, width: float) -> Array[Actor]:
	var out: Array[Actor] = []
	var a2 := Vector2(from.x, from.z)
	var b2 := Vector2(to.x, to.z)
	var dists := {}
	for a in get_hostiles(team):
		var p := Vector2(a.global_position.x, a.global_position.z)
		var closest := Geometry2D.get_closest_point_to_segment(p, a2, b2)
		var r := width + a.get_collision_radius()
		if p.distance_squared_to(closest) <= r * r:
			out.append(a)
			dists[a] = p.distance_squared_to(a2)
	out.sort_custom(func(x: Actor, y: Actor) -> bool: return float(dists[x]) < float(dists[y]))
	return out


## Nearest hostile whose collision circle is within max_range of pos (edge distance), or null.
static func nearest_hostile(team: int, pos: Vector3, max_range: float, exclude: Array = []) -> Actor:
	var best: Actor = null
	var best_d := INF
	for a in get_hostiles(team):
		if not exclude.is_empty() and exclude.has(a):
			continue
		var d := distance_xz(pos, a.global_position) - a.get_collision_radius()
		if d <= max_range and d < best_d:
			best_d = d
			best = a
	return best


## Hostiles within max_range sorted by distance (nearest first).
static func hostiles_sorted_by_distance(team: int, pos: Vector3, max_range: float, exclude: Array = []) -> Array[Actor]:
	var out: Array[Actor] = []
	var dists := {}
	for a in get_hostiles(team):
		if not exclude.is_empty() and exclude.has(a):
			continue
		var d := distance_xz(pos, a.global_position) - a.get_collision_radius()
		if d <= max_range:
			out.append(a)
			dists[a] = d
	out.sort_custom(func(x: Actor, y: Actor) -> bool: return float(dists[x]) < float(dists[y]))
	return out


## Physics ray against layer 1 (walls, static props) at y = 1.0 above the given points.
static func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var a := Vector3(from.x, LOS_HEIGHT, from.z)
	var b := Vector3(to.x, LOS_HEIGHT, to.z)
	return _ray(a, b).is_empty()


## First wall hit between from and to (physics layer 1), or {} if clear.
## Returns {"position": Vector3, "normal": Vector3, "collider": Object}. Points at floor level
## (y < 0.2) are raised to y = 1.0 (projectiles fly at ~1.1 m; walls start at the floor).
static func raycast_world(from: Vector3, to: Vector3) -> Dictionary:
	var a := from
	var b := to
	if a.y < FLOOR_EPSILON:
		a.y = LOS_HEIGHT
	if b.y < FLOOR_EPSILON:
		b.y = LOS_HEIGHT
	return _ray(a, b)


static func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if a.is_equal_approx(b):
		return {}
	var w3d := _world_3d()
	if w3d == null:
		return {}
	var space := w3d.direct_space_state
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(a, b, WORLD_MASK)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var r := space.intersect_ray(q)
	if r.is_empty():
		return {}
	return {"position": r["position"], "normal": r["normal"], "collider": r.get("collider")}


## The physics world of the live World node (its viewport), else the root viewport's.
static func _world_3d() -> World3D:
	var w: Node = GameState.world
	if is_instance_valid(w) and w.is_inside_tree():
		return (w as Node3D).get_world_3d()
	var tree := _tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_world_3d()


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

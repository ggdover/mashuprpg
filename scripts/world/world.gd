class_name World
extends Node3D
## One playable area (the town or a generated dungeon depth): geometry, lighting, environment,
## walkability grid + pathfinding, interactables, and containers for dynamic content.
## The game flow creates a World, calls build(), then spawns the player and enemies into it.
## OWNER: world (wave 1). CONTRACT STUB — keep every public member/signature.
## See docs/ARCHITECTURE.md §13.
##
## Implementation: layouts come from WorldDungeonGen / WorldTownGen (pure data + WorldGrid),
## geometry from WorldKit (chunked MultiMeshInstance3Ds of duplicated Assets meshes with the
## world shaders; walls / pillars / houses / trees use the wall cut-out shader), one merged
## StaticBody3D (layer 1) for collision, <= 20 shadowless OmniLight3Ds, a WorldEnvironment and a
## directional moon / sun light per theme. Interactables live under "Interactables".
##
## Grid note: towns and dungeons use the §13 grid (origin Vector3.ZERO). The test "arena" is
## centred on the world origin instead (player start = Vector3.ZERO, as the TestCase fixtures
## expect); get_minimap_data().origin / world_to_cell() / cell_to_world() account for it.

signal build_finished()

## Size of one grid cell in metres.
const TILE_SIZE := 2.0
## OmniLight3D budget per area (the player's own light comes on top).
const MAX_LIGHTS := 20
const FLOOR_IDS := ["env_floor_a", "env_floor_b", "env_floor_c"]
const WALL_IDS := ["env_wall_a", "env_wall_b"]
const COLLISION_HEIGHT := 3.0
## Centre distance between two standing portals (env_portal is ~3.23 m wide, 2 m deep).
const PORTAL_GAP := 4.2
## Footprint probes of a standing portal: every probe must be on walkable floor.
const PORTAL_PROBES_STRICT: Array[Vector3] = [Vector3(1.7, 0, 0), Vector3(-1.7, 0, 0), Vector3(0, 0, 1.1), Vector3(0, 0, -1.1),
	Vector3(1.5, 0, 1.0), Vector3(-1.5, 0, 1.0), Vector3(1.5, 0, -1.0), Vector3(-1.5, 0, -1.0)]
const PORTAL_PROBES_LOOSE: Array[Vector3] = [Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0)]
## Centre distance a portal keeps from debris (tall props need a little more than flat ones).
const DEBRIS_CLEARANCE := {"env_crate": 2.3, "env_barrel": 2.1, "env_rock_a": 2.3, "env_rock_b": 2.1, "env_crystal": 2.3}

## {"id": "town"|"dungeon"|"arena", "name": String, "depth": int, "level": int (monster level),
##  "seed": int, "theme": "town"|"crypt"|"cave"|"inferno"|"arena", "size": int (arena only)}
## "arena" = test/demo area: open size x size cells of floor with perimeter walls, player start at
## the centre, no spawns/chests/props, simple lighting.
var area_info: Dictionary = {}
## Parent for projectiles, effects and ground loot.
var dynamic_root: Node3D = null
## Parent for enemies.
var enemies_root: Node3D = null

## Theme actually built ("crypt", "cave", "inferno", "town", "arena").
var theme: String = ""
## Walkability / pathfinding / LOS grid (null before build()).
var grid: WorldGrid = null
## Static geometry, lights, environment and collision.
var level_root: Node3D = null
## Portals, gate, merchant, stash, chests, shrines.
var interactables_root: Node3D = null
var world_environment: WorldEnvironment = null
## The directional moon (dungeons) / sun (town).
var sun: DirectionalLight3D = null
## Raw layout data from the generator (read-only; handy for tests and debugging).
var layout: Dictionary = {}
## Milliseconds the last build() took.
var build_time_ms: float = 0.0
## Cells that got a wall block (read-only; walls are drawn by MultiMeshes).
var wall_cells: Array[Vector2i] = []

var _player_start := Vector3.ZERO
var _spawn_groups: Array = []
var _rooms: Array = []
var _interactables: Array = []
var _extra_markers: Array = []
var _flicker: Array = []            # [OmniLight3D, base_energy, phase, amount]
## Moving light pool (dungeons): OmniLight3Ds re-assigned to the light sources nearest the
## camera focus, so every visible torch lights its surroundings within the light budget.
var _pool: Array = []               # [{"light": OmniLight3D, "cand": int, "fade": float}]
var _candidates: Array = []         # {"pos", "color", "energy", "range", "flicker"}
var _pool_timer := 0.0
var _minimap_cells := PackedByteArray()
var _exit_portals: Array = []
var _return_portal: WorldPortal = null
var _town_portal: WorldPortal = null
var _kit: WorldKit = null
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _geo: Node3D = null
var _lights_root: Node3D = null
var _collision_body: StaticBody3D = null


func _init() -> void:
	add_to_group("world")
	dynamic_root = Node3D.new()
	dynamic_root.name = "Dynamic"
	add_child(dynamic_root)
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)


## Build the area described by info (see area_info). SYNCHRONOUS: the World must already be in the
## tree; build_finished is emitted before build() returns (informational — never await it).
## For dungeons, the layout is deterministic for a given seed.
func build(info: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	_clear()
	area_info = info
	var id := String(info.get("id", "arena"))
	match id:
		"town":
			theme = "town"
			_build_town()
		"dungeon":
			var depth := maxi(int(info.get("depth", 1)), 1)
			theme = String(info.get("theme", theme_for_depth(depth)))
			if not theme in ["crypt", "cave", "inferno"]:
				theme = theme_for_depth(depth)
			_build_dungeon(depth, int(info.get("seed", depth * 7919)))
		_:
			theme = "arena"
			_build_arena(maxi(int(info.get("size", 16)), 2))
	build_time_ms = (Time.get_ticks_usec() - t0) / 1000.0
	build_finished.emit()


## Theme by depth: crypt (1-3), cave (4-6), inferno (7-9), then repeating.
static func theme_for_depth(depth: int) -> String:
	var themes := ["crypt", "cave", "inferno"]
	return themes[int((maxi(depth, 1) - 1) / 3) % 3]


## "The Crypts", "Echoing Caves", "Infernal Depths"...
static func theme_display_name(theme_name: String) -> String:
	match theme_name:
		"crypt":
			return "The Crypts"
		"cave":
			return "Echoing Caves"
		"inferno":
			return "Infernal Depths"
		"town":
			return "Emberfall"
	return theme_name.capitalize()


func is_town() -> bool:
	return area_info.get("id", "") == "town"


func is_dungeon() -> bool:
	return area_info.get("id", "") == "dungeon"


func get_player_start() -> Vector3:
	return _player_start


## Where monsters go: [{"position": Vector3, "radius": float, "kind": "pack"|"rare_pack"|"boss",
## "count": int (suggested pack size), "room": int}]. Empty in town.
func get_spawn_groups() -> Array:
	return _spawn_groups.duplicate(true)


## Grid path (A*) from -> to as world positions at y = 0, including `to` (snapped to the nearest
## walkable cell). Empty if unreachable.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if grid == null:
		return PackedVector3Array([Vector3(to.x, 0.0, to.z)])
	return grid.find_path(from, to)


func is_walkable(pos: Vector3) -> bool:
	if grid == null:
		return true
	return grid.is_walkable_cell(grid.world_to_cell(pos))


## Nearest walkable position to pos (itself if walkable).
func get_nearest_walkable(pos: Vector3) -> Vector3:
	if grid == null:
		return pos
	return grid.nearest_walkable(pos)


## Random walkable position within radius of center (for scattering loot / summons).
func random_walkable_near(center: Vector3, radius: float) -> Vector3:
	if grid == null:
		return center
	return grid.random_walkable_near(center, radius)


## Grid line-of-sight (no wall cells between a and b).
func has_line_of_sight(a: Vector3, b: Vector3) -> bool:
	if grid == null:
		return true
	return grid.has_line_of_sight(a, b)


## Add projectiles, effects and loot (enemies/summons go through add_enemy via EnemyDB).
func add_dynamic(node: Node3D) -> void:
	dynamic_root.add_child(node)


func add_enemy(node: Node3D) -> void:
	enemies_root.add_child(node)


## Called by the game flow when the boss dies: a "Descend to Depth N+1" portal (not at
## Balance.MAX_DEPTH) and a "Town" portal near position.
func spawn_exit_portals(pos: Vector3) -> void:
	for p in _exit_portals:
		if is_instance_valid(p):
			return
	_exit_portals.clear()
	var depth := maxi(int(area_info.get("depth", 1)), 1)
	var base := get_nearest_walkable(pos)
	var spots := _portal_spots(base, 2 if depth < Balance.MAX_DEPTH else 1, _occupied_spots([]))
	if depth < Balance.MAX_DEPTH:
		var down := WorldPortal.new().setup("next", depth + 1)
		down.name = "PortalNext"
		_add_interactable(down, spots[0], 0.0)
		_exit_portals.append(down)
	var home := WorldPortal.new().setup("town")
	home.name = "PortalTown"
	_add_interactable(home, spots[spots.size() - 1], 0.0)
	_exit_portals.append(home)


## Minimap: {"size": Vector2i, "cells": PackedByteArray (0 wall/void, 1 floor),
## "explored": PackedByteArray (0/1), "tile_size": float, "origin": Vector3}
## Index cells[j * size.x + i] for cell (i, j): i along +X, j along +Z. origin = world position of
## the MIN corner of cell (0, 0) (= Vector3.ZERO with the §13 grid). Also includes
## "markers": [{"position": Vector3, "kind": "portal"|"waypoint"|"vendor"|"stash"|"chest"}].
## Extra key: "version" (int, changes whenever "explored" changes).
func get_minimap_data() -> Dictionary:
	if grid == null:
		return {}
	var markers: Array = []
	for n in _interactables:
		if not is_instance_valid(n):
			continue
		var kind := ""
		if n is WorldInteractable:
			kind = (n as WorldInteractable).get_minimap_kind()
		if kind != "":
			markers.append({"position": (n as Node3D).position, "kind": kind})
	for m in _extra_markers:
		markers.append(m.duplicate())
	return {
		"size": grid.size, "cells": _minimap_cells, "explored": grid.explored,
		"tile_size": TILE_SIZE, "origin": grid.origin, "markers": markers,
		"version": grid.explored_version,
	}


## Reveal cells within radius (called by the player every few frames).
func mark_explored(pos: Vector3, radius: float) -> void:
	if grid != null:
		grid.mark_explored(pos, radius)


# ------------------------------------------------------------------ extra public helpers

## Grid cell containing a world position.
func world_to_cell(pos: Vector3) -> Vector2i:
	if grid == null:
		return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.z / TILE_SIZE))
	return grid.world_to_cell(pos)


## Centre of a grid cell (y = 0).
func cell_to_world(cell: Vector2i) -> Vector3:
	if grid == null:
		return Vector3((cell.x + 0.5) * TILE_SIZE, 0.0, (cell.y + 0.5) * TILE_SIZE)
	return grid.cell_center(cell)


## Rooms of a dungeon: [{"rect": Rect2i (cells), "center": Vector3, "kind": "start"|"boss"|"room"}].
func get_rooms() -> Array:
	return _rooms.duplicate(true)


## Centre of the boss room (dungeons), else the player start.
func get_boss_room_center() -> Vector3:
	for r in _rooms:
		if r["kind"] == "boss":
			return r["center"]
	return _player_start


## Length in metres of the shortest grid path (A*, unsmoothed) between two points; INF if none.
func get_path_distance(from: Vector3, to: Vector3) -> float:
	if grid == null:
		return from.distance_to(to)
	var a := grid.nearest_walkable_cell(grid.world_to_cell(from))
	var b := grid.nearest_walkable_cell(grid.world_to_cell(to))
	if a.x < 0 or b.x < 0:
		return INF
	return grid.cell_path_length(a, b) * TILE_SIZE


## Live interactables of this area (portals, gate, merchant, stash, chests, shrines).
func get_interactables() -> Array:
	var out: Array = []
	for n in _interactables:
		if is_instance_valid(n):
			out.append(n)
	return out


## A "Town" portal near pos (e.g. where the player cast Town Portal, when re-entering a kept
## dungeon): just north of pos when there is room, clear of other portals / chests / pillars.
## There is at most one: a previous portal spawned by this call is removed first. If another
## portal to town (the start portal or the exit "Town" portal) already stands within 4.5 m of pos,
## no new portal is made and that one is returned. Safe to call on every re-entry, also while the
## World is detached from the tree.
func spawn_town_portal(pos: Vector3) -> WorldPortal:
	if is_instance_valid(_town_portal):
		_interactables.erase(_town_portal)
		if _town_portal.get_parent() != null:
			_town_portal.get_parent().remove_child(_town_portal)
		_town_portal.queue_free()
	_town_portal = null
	var flat := Vector3(pos.x, 0.0, pos.z)
	for n in _interactables:
		if is_instance_valid(n) and n is WorldPortal and (n as WorldPortal).destination == "town" and (n as Node3D).position.distance_to(flat) < 4.5:
			return n as WorldPortal
	var base := get_nearest_walkable(flat)
	var spot: Vector3 = _portal_spots(base, 1, _occupied_spots([]))[0]
	_town_portal = WorldPortal.new().setup("town")
	_town_portal.name = "TownPortal"
	_add_interactable(_town_portal, spot, 0.0)
	return _town_portal


## (Re)create the town's "Return to Depth N" portal from GameState.town_portal_state.
func refresh_town_portal() -> void:
	if not is_town():
		return
	if is_instance_valid(_return_portal):
		_return_portal.queue_free()
		_interactables.erase(_return_portal)
	_return_portal = null
	var st: Dictionary = GameState.town_portal_state
	if st.is_empty() or not st.has("world") or not is_instance_valid(st["world"]):
		return
	var kept: Node = st["world"]
	var depth := 1
	if kept is World:
		depth = int((kept as World).area_info.get("depth", 1))
	var spot: Dictionary = layout.get("portal_spot", {"pos": _player_start + Vector3(0, 0, -6), "yaw": 0.0})
	_return_portal = WorldPortal.new().setup("return", depth)
	_return_portal.name = "ReturnPortal"
	_add_interactable(_return_portal, spot["pos"], spot["yaw"])


## Re-assign the moving light pool to the current focus immediately (no fade), e.g. after a
## teleport. It also follows the player / camera automatically every 0.25 s.
func snap_light_pool() -> void:
	_assign_light_pool(_light_focus(), true)
	_pool_timer = 0.25


## Extra minimap marker (kind as in get_minimap_data).
func add_minimap_marker(pos: Vector3, kind: String) -> void:
	_extra_markers.append({"position": pos, "kind": kind})


## OmniLight3Ds of the area itself (level lights, light pool, interactables), i.e. what the
## §2 budget of MAX_LIGHTS counts. The player's light, enemies and dynamic content are excluded.
func get_light_count() -> int:
	var n := 0
	for r in [level_root, interactables_root]:
		if r != null and is_instance_valid(r):
			n += (r as Node).find_children("*", "OmniLight3D", true, false).size()
	return n


## Called by an interactable before it creates its own OmniLight3D: true if the area's light
## budget has room, making room by retiring one light of the moving pool when it is full. False
## (the caller then goes without a light) only when nothing can be freed.
func reserve_light_slot() -> bool:
	if get_light_count() < MAX_LIGHTS:
		return true
	if _pool.is_empty():
		return false
	var slot: Dictionary = _pool.pop_back()
	var l: OmniLight3D = slot["light"]
	if is_instance_valid(l):
		l.get_parent().remove_child(l)
		l.queue_free()
	return true


func get_collision_shape_count() -> int:
	if _collision_body == null:
		return 0
	return _collision_body.get_child_count()


# ------------------------------------------------------------------ build: common

func _clear() -> void:
	for n in [level_root, interactables_root]:
		if n != null and is_instance_valid(n):
			(n as Node).free()
	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	move_child(level_root, 0)
	interactables_root = Node3D.new()
	interactables_root.name = "Interactables"
	add_child(interactables_root)
	_geo = Node3D.new()
	_geo.name = "Geometry"
	level_root.add_child(_geo)
	_lights_root = Node3D.new()
	_lights_root.name = "Lights"
	level_root.add_child(_lights_root)
	grid = null
	layout = {}
	wall_cells = []
	_player_start = Vector3.ZERO
	_spawn_groups = []
	_rooms = []
	_interactables = []
	_extra_markers = []
	_flicker = []
	_pool = []
	_candidates = []
	_exit_portals = []
	_return_portal = null
	_town_portal = null
	_collision_body = null
	world_environment = null
	sun = null


func _add_interactable(node: Interactable, pos: Vector3, yaw: float) -> Interactable:
	node.position = Vector3(pos.x, 0.0, pos.z)
	node.rotation.y = yaw
	interactables_root.add_child(node)
	_interactables.append(node)
	return node


## What new portals keep clear of: existing interactables, debris, braziers and crystals, as
## [{"pos": Vector3, "r": float}] (r = the minimum distance between their centres and a portal's).
func _occupied_spots(exclude: Array) -> Array:
	var out: Array = []
	for n in _interactables:
		if not is_instance_valid(n) or n in exclude:
			continue
		out.append({"pos": (n as Node3D).position, "r": PORTAL_GAP if n is WorldPortal else 2.8})
	for d in layout.get("debris", []):
		out.append({"pos": d["pos"], "r": DEBRIS_CLEARANCE.get(d["id"], 1.9) * float(d.get("scale", 1.0))})
	for b in layout.get("braziers", []):
		out.append({"pos": b["pos"], "r": 2.3})
	for c in layout.get("crystals", []):
		out.append({"pos": c["pos"], "r": 2.3})
	return out


## Up to `count` spots near base for standing portals (env_portal: ~3.2 x 2 m platform): the
## footprint must be walkable (clear of walls, pillars, lava, chests), visible from base,
## preferably north of it (towards the top of the screen), portals PORTAL_GAP apart and clear of
## the `occupied` spots (see _occupied_spots). Falls back to looser spots in cramped places.
func _portal_spots(base: Vector3, count: int, occupied: Array = []) -> Array:
	var out: Array = []
	# Two portals side by side, preferably just north of base.
	if count == 2:
		for dz in [-2.4, -3.6, -1.2, 2.4, 0.0, 3.6, -5.0]:
			for dx in [0.0, -1.5, 1.5, -3.0, 3.0]:
				var a := base + Vector3(dx - PORTAL_GAP * 0.5, 0, dz)
				var b := base + Vector3(dx + PORTAL_GAP * 0.5, 0, dz)
				if _portal_spot_ok(a, base, [], occupied, true) and _portal_spot_ok(b, base, [a], occupied, true):
					return [a, b]
	var candidates: Array = []
	for ring in [2.4, 3.6, 5.0, 6.5]:
		for k in 12:
			var ang := -PI * 0.5 + (k / 2) * (PI / 6.0) * (1 if k % 2 == 0 else -1)
			candidates.append(base + Vector3(cos(ang), 0, sin(ang)) * ring)
	for strict in [true, false]:
		for p in candidates:
			if out.size() >= count:
				return out
			if not _portal_spot_ok(p, base, out, occupied, strict):
				continue
			out.append(p)
	while out.size() < count:
		out.append(get_nearest_walkable(base + Vector3(4.0 * out.size(), 0, 0)))
	return out


func _portal_spot_ok(p: Vector3, base: Vector3, taken: Array, occupied: Array, strict: bool) -> bool:
	if not is_walkable(p) or not has_line_of_sight(base, p):
		return false
	for o in (PORTAL_PROBES_STRICT if strict else PORTAL_PROBES_LOOSE):
		if not is_walkable(p + o):
			return false
	for q in taken:
		if (q as Vector3).distance_to(p) < (PORTAL_GAP - 0.1 if strict else 3.3):
			return false
	for occ in occupied:
		if (occ["pos"] as Vector3).distance_to(p) < float(occ["r"]) * (1.0 if strict else 0.8):
			return false
	return true


func _theme() -> Dictionary:
	return WorldThemes.get_theme(theme)


func _cell_xf(c: Vector2i, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), grid.cell_center(c))


func _prop_xf(pos: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)


func _variation(amount: float) -> Color:
	var v := _rng.randf_range(1.0 - amount, 1.0 + amount * 0.4)
	return Color(v, v, v)


## Floors: env_floor_a/b/c (random), random quarter turns, per-instance brightness / hue jitter.
func _build_floor_tiles(cells: Array, tint: Color, hue_tints: Array) -> void:
	var by_id := {}
	for c in cells:
		var r := _rng.randf()
		var id: String = FLOOR_IDS[0] if r < 0.55 else (FLOOR_IDS[1] if r < 0.8 else FLOOR_IDS[2])
		if not by_id.has(id):
			by_id[id] = [[], []]
		var hue: Color = hue_tints[_rng.randi_range(0, hue_tints.size() - 1)] if not hue_tints.is_empty() else tint
		var v := _rng.randf_range(0.95, 1.03)
		var col := Color(hue.r / maxf(tint.r, 0.01) * v, hue.g / maxf(tint.g, 0.01) * v, hue.b / maxf(tint.b, 0.01) * v)
		by_id[id][0].append(_cell_xf(c, _rng.randi_range(0, 3) * PI * 0.5))
		by_id[id][1].append(col)
	for id in by_id:
		_kit.add_multimesh(_geo, id, by_id[id][0], by_id[id][1], tint, false, false)


## Wall blocks on every non-floor cell touching floor (8-neighbourhood).
func _build_wall_blocks(is_floorish: Callable, tint: Color) -> void:
	var by_id := {}
	var bases: Array[Transform3D] = []
	for j in grid.size.y:
		for i in grid.size.x:
			var c := Vector2i(i, j)
			if is_floorish.call(c):
				continue
			var touches := false
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if (di != 0 or dj != 0) and grid.in_bounds(c + Vector2i(di, dj)) and is_floorish.call(c + Vector2i(di, dj)):
						touches = true
			if not touches:
				continue
			var id: String = WALL_IDS[0] if _rng.randf() < 0.75 else WALL_IDS[1]
			if not by_id.has(id):
				by_id[id] = [[], []]
			by_id[id][0].append(_cell_xf(c, _rng.randi_range(0, 3) * PI * 0.5))
			by_id[id][1].append(_variation(0.06))
			bases.append(Transform3D(Basis.IDENTITY, grid.cell_center(c) + Vector3(0, 0.004, 0)))
			wall_cells.append(c)
	for id in by_id:
		_kit.add_multimesh(_geo, id, by_id[id][0], by_id[id][1], tint, true, true, {"top_darken": 0.45})
	# Dark ground under wall blocks: what the wall cut-out reveals instead of the empty void.
	if bases.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(TILE_SIZE, TILE_SIZE)
	var ft: Color = _theme()["floor_tint"]
	plane.material = WorldKit.make_material(Color(ft.r * 0.3, ft.g * 0.3, ft.b * 0.3), false, 1.0, Color.BLACK, 0.0, false)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = bases.size()
	for n in bases.size():
		mm.set_instance_transform(n, bases[n])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "WallBase"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geo.add_child(mmi)


## One StaticBody3D (layer 1): merged boxes over solid cells (greedy rectangles) plus explicit
## shapes for pillars / props (soft cells).
func _build_collision(soft: Dictionary, shapes: Array) -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "WallCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0
	level_root.add_child(_collision_body)
	var w := grid.size.x
	var h := grid.size.y
	var need := PackedByteArray()
	need.resize(w * h)
	for j in h:
		for i in w:
			var k := j * w + i
			if grid.walk[k] == 0 and not soft.has(Vector2i(i, j)):
				need[k] = 1
	var used := PackedByteArray()
	used.resize(w * h)
	for j in h:
		for i in w:
			var k := j * w + i
			if need[k] == 0 or used[k] == 1:
				continue
			var rw := 1
			while i + rw < w and need[k + rw] == 1 and used[k + rw] == 0:
				rw += 1
			var rh := 1
			var can := true
			while j + rh < h and can:
				for x in range(i, i + rw):
					var k2 := (j + rh) * w + x
					if need[k2] == 0 or used[k2] == 1:
						can = false
						break
				if can:
					rh += 1
			for y in range(j, j + rh):
				for x in range(i, i + rw):
					used[y * w + x] = 1
			var box := BoxShape3D.new()
			box.size = Vector3(rw * TILE_SIZE, COLLISION_HEIGHT, rh * TILE_SIZE)
			var cs := CollisionShape3D.new()
			cs.shape = box
			cs.position = grid.origin + Vector3((i + rw * 0.5) * TILE_SIZE, COLLISION_HEIGHT * 0.5, (j + rh * 0.5) * TILE_SIZE)
			_collision_body.add_child(cs)
	for s in shapes:
		var cs2 := CollisionShape3D.new()
		var pos: Vector3 = s["pos"]
		if s["type"] == "cylinder":
			var cyl := CylinderShape3D.new()
			cyl.radius = s["radius"]
			cyl.height = s.get("height", COLLISION_HEIGHT)
			cs2.shape = cyl
			cs2.position = Vector3(pos.x, cyl.height * 0.5, pos.z)
		else:
			var b := BoxShape3D.new()
			b.size = s["size"]
			cs2.shape = b
			cs2.position = Vector3(pos.x, b.size.y * 0.5 + pos.y, pos.z)
			cs2.rotation.y = float(s.get("yaw", 0.0))
		_collision_body.add_child(cs2)


func _add_light(pos: Vector3, color: Color, energy: float, light_range: float, flicker: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_specular = 0.3
	_lights_root.add_child(l)
	if flicker:
		_flicker.append([l, energy, _rng.randf() * TAU, 0.14])
	return l


## Additive light pools on the floor (fake lighting for every torch / crystal / brazier).
func _build_glows(glows: Array, intensity: float) -> void:
	if glows.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	plane.material = WorldKit.glow_material(intensity)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = glows.size()
	for n in glows.size():
		var g: Dictionary = glows[n]
		var r: float = g["radius"]
		var p: Vector3 = g["pos"]
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(r * 2.0, 1.0, r * 2.0)), Vector3(p.x, 0.035, p.z)))
		mm.set_instance_color(n, g["color"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LightPools"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geo.add_child(mmi)


func _build_props(items: Array, tint: Color, cutout: bool, shadows: bool, params: Dictionary = {}) -> void:
	var by_id := {}
	for d in items:
		var id: String = d["id"]
		if not by_id.has(id):
			by_id[id] = [[], []]
		var sc: float = d.get("scale", 1.0)
		if d.has("fit"):
			# Keep the footprint within `fit` metres of the origin, whatever the model's size.
			var box := _kit.model_aabb(id)
			var half := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
			if half > 0.05:
				sc = minf(sc, float(d["fit"]) / half)
		by_id[id][0].append(_prop_xf(d["pos"], d.get("yaw", 0.0), sc))
		by_id[id][1].append(_variation(0.1))
	for id in by_id:
		var big: bool = id.begins_with("town_house") or id.begins_with("town_tree") or id == "env_pillar"
		_kit.add_multimesh(_geo, id, by_id[id][0], by_id[id][1], tint, cutout or big, shadows or big, params)


func _setup_environment() -> void:
	var th := _theme()
	var env := Environment.new()
	if theme == "town":
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.32, 0.46, 0.72)
		sky_mat.sky_horizon_color = Color(0.86, 0.72, 0.56)
		sky_mat.ground_horizon_color = Color(0.62, 0.55, 0.45)
		sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.15)
		sky_mat.sun_angle_max = 20.0
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.55
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = th["background"]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_color = th["ambient"]
	env.ambient_light_energy = th["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = th["exposure"]
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var fog_density: float = th["fog_density"]
	env.fog_enabled = fog_density > 0.0
	env.fog_light_color = th["fog"]
	env.fog_light_energy = 1.0
	env.fog_density = fog_density
	env.fog_sky_affect = 0.25 if theme == "town" else 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0
	world_environment = WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = env
	level_root.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun" if theme == "town" else "Moon"
	sun.rotation_degrees = th["moon_rot"]
	sun.light_color = th["moon"]
	sun.light_energy = th["moon_energy"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.light_specular = 0.4
	level_root.add_child(sun)


func _process(delta: float) -> void:
	if _flicker.is_empty() and _pool.is_empty():
		return
	_time += delta
	for f in _flicker:
		var l: OmniLight3D = f[0]
		if is_instance_valid(l):
			l.light_energy = float(f[1]) * _flicker_factor(f[2], f[3])
	if _pool.is_empty():
		return
	_pool_timer -= delta
	if _pool_timer <= 0.0:
		_pool_timer = 0.25
		_assign_light_pool(_light_focus(), false)
	for slot in _pool:
		var l2: OmniLight3D = slot["light"]
		var ci: int = slot["cand"]
		if ci < 0:
			l2.visible = false
			continue
		l2.visible = true
		slot["fade"] = minf(1.0, float(slot["fade"]) + delta * 3.0)
		var c: Dictionary = _candidates[ci]
		var k := _flicker_factor(float(ci) * 1.7, 0.14) if c["flicker"] else 1.0
		l2.light_energy = float(c["energy"]) * float(slot["fade"]) * k


func _flicker_factor(phase: float, amount: float) -> float:
	return 1.0 - amount + amount * (0.55 * sin(_time * 7.3 + phase) + 0.3 * sin(_time * 17.9 + phase * 2.1) + 0.15 * sin(_time * 31.0 + phase * 0.7))


## Where the light pool gathers: the player (if in this World), else the ground point the
## active camera looks at, else the player start.
func _light_focus() -> Vector3:
	var p := GameState.player
	if is_instance_valid(p) and is_ancestor_of(p):
		return p.global_position
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var o := cam.global_position
			var dir := -cam.global_transform.basis.z
			if dir.y < -0.01:
				return o + dir * (-o.y / dir.y)
			return o
	return _player_start


func _setup_light_pool(cands: Array, count: int) -> void:
	_candidates = cands
	for i in mini(count, cands.size()):
		var l := OmniLight3D.new()
		l.name = "PoolLight%d" % i
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		l.light_specular = 0.3
		_lights_root.add_child(l)
		_pool.append({"light": l, "cand": -1, "fade": 0.0})
	_assign_light_pool(_player_start, true)


## Give the pool's lights to the candidates nearest `focus` (lights already on a wanted source
## stay; the others jump and fade in).
func _assign_light_pool(focus: Vector3, instant: bool) -> void:
	if _pool.is_empty():
		return
	var dist: Array[float] = []
	for c in _candidates:
		var cp: Vector3 = c["pos"]
		dist.append(Vector2(cp.x - focus.x, cp.z - focus.z).length_squared())
	var order: Array = range(_candidates.size())
	order.sort_custom(func(a: int, b: int) -> bool: return dist[a] < dist[b])
	var wanted := {}
	for i in mini(_pool.size(), order.size()):
		wanted[order[i]] = true
	var have := {}
	var free: Array = []
	for slot in _pool:
		if wanted.has(slot["cand"]):
			have[slot["cand"]] = true
		else:
			free.append(slot)
	for ci in wanted:
		if have.has(ci) or free.is_empty():
			continue
		var slot2: Dictionary = free.pop_back()
		var c2: Dictionary = _candidates[ci]
		var l: OmniLight3D = slot2["light"]
		slot2["cand"] = ci
		slot2["fade"] = 1.0 if instant else 0.0
		l.position = c2["pos"]
		l.light_color = c2["color"]
		l.omni_range = c2["range"]
		l.light_energy = float(c2["energy"]) * float(slot2["fade"])
		l.visible = true


# ------------------------------------------------------------------ build: dungeon

func _build_dungeon(depth: int, seed_value: int) -> void:
	var th := _theme()
	var gen := WorldDungeonGen.new()
	layout = gen.generate(depth, seed_value, theme)
	grid = layout["grid"]
	_player_start = layout["start"]
	_spawn_groups = layout["spawn_groups"]
	_rooms = layout["rooms"]
	_kit = WorldKit.new(th)
	_rng.seed = seed_value * 31 + 17
	var cells: PackedByteArray = layout["cells"]
	# Floors (lava cells have none).
	var floor_list: Array = []
	for j in grid.size.y:
		for i in grid.size.x:
			if cells[j * grid.size.x + i] == WorldDungeonGen.CELL_FLOOR:
				floor_list.append(Vector2i(i, j))
	_build_floor_tiles(floor_list, th["floor_tint"], th["floor_tints"])
	var sz := grid.size.x
	_build_wall_blocks(func(c: Vector2i) -> bool: return cells[c.y * sz + c.x] != WorldDungeonGen.CELL_VOID, th["wall_tint"])
	# Pillars / rock formations.
	var soft := {}
	var shapes: Array = []
	var pillar_items: Array = []
	var rock_items: Array = []
	for p in layout["pillars"]:
		var c: Vector2i = p["cell"]
		soft[c] = true
		var pos := grid.cell_center(c)
		if p["kind"] == "rock":
			rock_items.append({"id": "env_rock_a" if _rng.randf() < 0.5 else "env_rock_b", "pos": pos, "yaw": _rng.randf() * TAU, "scale": 3.0, "fit": _rng.randf_range(0.95, 1.1)})
			shapes.append({"type": "cylinder", "pos": pos, "radius": 0.8, "height": COLLISION_HEIGHT})
		else:
			pillar_items.append({"id": "env_pillar", "pos": pos, "yaw": _rng.randi_range(0, 3) * PI * 0.5, "scale": 1.0})
			shapes.append({"type": "cylinder", "pos": pos, "radius": 0.55, "height": COLLISION_HEIGHT})
	_build_props(pillar_items, th["pillar_tint"], true, true)
	_build_props(rock_items, th["wall_tint"], true, true)
	# Lava pools: a glowing plane per pool, a low collision box (projectiles fly over it).
	for pool in layout["lava"]:
		var r: Rect2i = pool["rect"]
		var centre := grid.origin + Vector3((r.position.x + r.size.x * 0.5) * TILE_SIZE, 0.0, (r.position.y + r.size.y * 0.5) * TILE_SIZE)
		var plane := PlaneMesh.new()
		plane.size = Vector2(r.size.x * TILE_SIZE, r.size.y * TILE_SIZE)
		var mi := MeshInstance3D.new()
		mi.name = "Lava"
		mi.mesh = plane
		mi.material_override = WorldKit.lava_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = centre + Vector3(0, -0.32, 0)
		_geo.add_child(mi)
		# Sunken pit: an inside-out box gives the rock walls around the lava.
		var pit := BoxMesh.new()
		pit.size = Vector3(r.size.x * TILE_SIZE - 0.02, 0.7, r.size.y * TILE_SIZE - 0.02)
		pit.flip_faces = true
		var wt: Color = th["wall_tint"]
		pit.material = WorldKit.make_material(Color(wt.r * 0.35, wt.g * 0.3, wt.b * 0.3), false, 1.0, Color(0.5, 0.12, 0.02), 0.25, false)
		var pit_mi := MeshInstance3D.new()
		pit_mi.name = "LavaPit"
		pit_mi.mesh = pit
		pit_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pit_mi.position = centre + Vector3(0, -0.35, 0)
		_geo.add_child(pit_mi)
		for j in range(r.position.y, r.end.y):
			for i in range(r.position.x, r.end.x):
				soft[Vector2i(i, j)] = true
		shapes.append({"type": "box", "pos": centre, "size": Vector3(r.size.x * TILE_SIZE, 0.9, r.size.y * TILE_SIZE), "yaw": 0.0})
	# Chests / shrine cells get explicit shapes.
	for ch in layout["chests"]:
		var cc: Vector2i = ch["cell"]
		soft[cc] = true
		var f: Vector2i = ch["facing"]
		shapes.append({"type": "box", "pos": grid.cell_center(cc), "size": Vector3(1.1, 1.0, 0.8), "yaw": atan2(f.x, f.y)})
	if not layout["shrine"].is_empty():
		var sc: Vector2i = layout["shrine"]["cell"]
		soft[sc] = true
		shapes.append({"type": "cylinder", "pos": grid.cell_center(sc), "radius": 0.65, "height": COLLISION_HEIGHT})
	_build_collision(soft, shapes)
	_build_dungeon_lights(th)
	# Debris (decorative, non-colliding).
	_build_props(layout["debris"], th["prop_tint"], false, false)
	_build_props(layout["wall_rocks"], th["wall_tint"], true, true)
	_setup_environment()
	# Interactables.
	var portal := WorldPortal.new().setup("town")
	portal.name = "StartPortal"
	_add_interactable(portal, grid.cell_center(layout["portal_cell"]), 0.0)
	var level := int(area_info.get("level", Balance.area_level_for_depth(depth)))
	for ch in layout["chests"]:
		var chest := WorldChest.new().setup(ch["tier"], level)
		var fd: Vector2i = ch["facing"]
		_add_interactable(chest, grid.cell_center(ch["cell"]), atan2(fd.x, fd.y))
	if not layout["shrine"].is_empty():
		var shrine := WorldShrine.new().setup(layout["shrine"]["kind"])
		_add_interactable(shrine, grid.cell_center(layout["shrine"]["cell"]), 0.0)
	_minimap_cells = grid.floor_cells.duplicate()
	grid.mark_explored(_player_start, 14.0)


func _build_dungeon_lights(th: Dictionary) -> void:
	# Wall torches: the model's flame height decides whether it already includes the mount height.
	var torch_items: Array = []
	var torch_box := _kit.model_aabb("env_torch")
	var torch_y := 0.0 if torch_box.position.y > 0.6 else 1.6
	for t in layout["torches"]:
		var w: Vector2i = t["cell"]
		var d: Vector2i = t["dir"]
		var face := grid.cell_center(w) + Vector3(d.x, 0, d.y) * (TILE_SIZE * 0.5)
		torch_items.append({"id": "env_torch", "pos": face + Vector3(0, torch_y, 0), "yaw": atan2(d.x, d.y), "scale": 1.0})
	_build_props(torch_items, Color.WHITE, false, false)
	var crystal_items: Array = []
	for c in layout["crystals"]:
		crystal_items.append({"id": "env_crystal", "pos": c["pos"], "yaw": c["yaw"], "scale": c["scale"]})
	_build_props(crystal_items, th["prop_tint"], false, false, {"emission_color": th["light_color"]})
	var brazier_items: Array = []
	for b in layout["braziers"]:
		brazier_items.append({"id": "env_brazier", "pos": b["pos"], "yaw": _rng.randf() * TAU, "scale": 1.0})
	_build_props(brazier_items, Color.WHITE, false, true, {"emission_color": th["light_color"]})
	_setup_light_pool(layout["light_candidates"], layout["light_pool_size"])
	_build_glows(layout["glows"], th["glow_strength"])


# ------------------------------------------------------------------ build: town

func _build_town() -> void:
	var th := _theme()
	var gen := WorldTownGen.new()
	layout = gen.generate()
	grid = layout["grid"]
	_player_start = layout["start"]
	_kit = WorldKit.new(th)
	_rng.seed = 90210
	var paths: PackedByteArray = layout["paths"]
	_build_town_ground(paths)
	var plaza: Array = []
	for j in grid.size.y:
		for i in grid.size.x:
			if paths[j * grid.size.x + i] == WorldTownGen.PATH_PLAZA:
				plaza.append(Vector2i(i, j))
	_build_floor_tiles(plaza, Color(0.8, 0.74, 0.64), [Color(0.8, 0.74, 0.64), Color(0.74, 0.7, 0.62), Color(0.84, 0.78, 0.68)])
	var houses: Array = []
	for hdef in layout["houses"]:
		houses.append({"id": hdef["id"], "pos": hdef["pos"], "yaw": hdef["yaw"], "scale": 1.0})
	_build_props(houses, Color.WHITE, true, true)
	_build_props(layout["trees"], Color.WHITE, true, true)
	var fence_items: Array = []
	for f in layout["fences"]:
		fence_items.append({"id": "town_fence", "pos": f["pos"], "yaw": f["yaw"], "scale": 1.0})
	_build_props(fence_items, Color.WHITE, false, true)
	var misc: Array = [
		{"id": "town_well", "pos": layout["well"]["pos"], "yaw": layout["well"]["yaw"], "scale": 1.0},
		{"id": "town_stall", "pos": layout["stall"]["pos"], "yaw": layout["stall"]["yaw"], "scale": 1.0},
	]
	_build_props(misc, Color.WHITE, true, true)
	var clutter_big: Array = []
	var clutter_small: Array = []
	for p in layout["props"]:
		if p["id"] in ["town_cart", "env_crate", "env_barrel"]:
			clutter_big.append(p)
		else:
			clutter_small.append(p)
	_build_props(clutter_big, Color.WHITE, false, true)
	_build_props(clutter_small, Color.WHITE, false, false)
	# Lamp posts with warm lights.
	var lamp_items: Array = []
	var lamp_box := _kit.model_aabb("town_lamp")
	var lamp_h := clampf(lamp_box.end.y - 0.3, 1.5, 4.5) if lamp_box.size.y > 0.5 else 3.0
	var glows: Array = []
	for l in layout["lamps"]:
		lamp_items.append({"id": "town_lamp", "pos": l["pos"], "yaw": l["yaw"], "scale": 1.0})
		_add_light(l["pos"] + Vector3(0, lamp_h, 0), th["light_color"], th["light_energy"], th["light_range"], true)
		glows.append({"pos": l["pos"], "radius": 2.6, "color": th["glow_color"]})
	_build_props(lamp_items, Color.WHITE, false, true)
	_build_glows(glows, th["glow_strength"])
	_build_collision(layout["soft"], layout["shapes"])
	_setup_environment()
	# Interactables.
	var gate := WorldWaypointGate.new()
	gate.name = "DungeonGate"
	_add_interactable(gate, layout["gate"]["pos"], layout["gate"]["yaw"])
	var merchant := WorldVendorNpc.new()
	merchant.name = "Merchant"
	_add_interactable(merchant, layout["merchant"]["pos"], layout["merchant"]["yaw"])
	var stash := WorldStashChest.new()
	stash.name = "Stash"
	_add_interactable(stash, layout["stash"]["pos"], layout["stash"]["yaw"])
	refresh_town_portal()
	# Minimap: walkable ground plus small props; the town is fully revealed.
	_minimap_cells = PackedByteArray()
	_minimap_cells.resize(grid.size.x * grid.size.y)
	var soft: Dictionary = layout["soft"]
	for j in grid.size.y:
		for i in grid.size.x:
			var k := j * grid.size.x + i
			if grid.walk[k] == 1 or (soft.has(Vector2i(i, j)) and grid.floor_cells[k] == 1):
				_minimap_cells[k] = 1
	grid.explored.fill(1)
	grid.explored_version += 1


## One vertex-coloured ground mesh: grass with soft noise, dirt paths blended per cell, darker
## forest floor outside the fence. Slightly below y = 0 so plaza tiles sit on top.
func _build_town_ground(paths: PackedByteArray) -> void:
	var lo := -34.0
	var hi := 82.0
	var step := 1.0
	var n := int((hi - lo) / step) + 1
	var grass := Color(0.3, 0.43, 0.17)
	var grass_dry := Color(0.45, 0.47, 0.22)
	var grass_dark := Color(0.2, 0.32, 0.13)
	var forest := Color(0.16, 0.22, 0.11)
	var dirt := Color(0.46, 0.36, 0.24)
	var dirt_dark := Color(0.36, 0.28, 0.19)
	var inner_lo := WorldTownGen.INNER_MIN * TILE_SIZE
	var inner_hi := (WorldTownGen.INNER_MAX + 1) * TILE_SIZE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in n:
		for xi in n:
			var x := lo + xi * step
			var z := lo + zi * step
			var nz := _vnoise(x * 0.13, z * 0.13) * 0.65 + _vnoise(x * 0.41 + 17.0, z * 0.41 - 9.0) * 0.35
			var c := grass_dark.lerp(grass, smoothstep(0.2, 0.55, nz)).lerp(grass_dry, smoothstep(0.62, 0.9, nz))
			var outside := maxf(maxf(inner_lo - x, x - inner_hi), maxf(inner_lo - z, z - inner_hi))
			c = c.lerp(forest, clampf((outside + 1.0) / 8.0, 0.0, 0.85))
			var pw := _path_weight(paths, x, z)
			if pw > 0.0:
				var dc := dirt_dark.lerp(dirt, _vnoise(x * 0.7, z * 0.7))
				c = c.lerp(dc, pw)
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, -0.02, z))
	for zi in n - 1:
		for xi in n - 1:
			var a := zi * n + xi
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = WorldKit.make_material(Color.WHITE, false, 0.95, Color.BLACK, 0.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geo.add_child(mi)


## 0..1 dirt coverage at a ground point (bilinear over path cells; the road leaves town south).
func _path_weight(paths: PackedByteArray, x: float, z: float) -> float:
	var u := x / TILE_SIZE - 0.5
	var v := z / TILE_SIZE - 0.5
	var i0 := floori(u)
	var j0 := floori(v)
	var fu := u - i0
	var fv := v - j0
	var s := 0.0
	for dj in 2:
		for di in 2:
			var i := i0 + di
			var j := j0 + dj
			var val := 0.0
			if i >= 0 and j >= 0 and i < WorldTownGen.SIZE and j < WorldTownGen.SIZE:
				val = 1.0 if paths[j * WorldTownGen.SIZE + i] != 0 else 0.0
			elif j >= WorldTownGen.SIZE and (i == 11 or i == 12):
				val = clampf(1.0 - (z - 48.0) / 20.0, 0.0, 1.0)
			var wgt := (fu if di == 1 else 1.0 - fu) * (fv if dj == 1 else 1.0 - fv)
			s += val * wgt
	return smoothstep(0.15, 0.85, s)


func _vnoise(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := x - ix
	var fz := z - iz
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := _hash2(ix, iz)
	var b := _hash2(ix + 1.0, iz)
	var c := _hash2(ix, iz + 1.0)
	var d := _hash2(ix + 1.0, iz + 1.0)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz)


func _hash2(x: float, z: float) -> float:
	var h := sin(x * 127.1 + z * 311.7) * 43758.5453
	return h - floorf(h)


# ------------------------------------------------------------------ build: arena

func _build_arena(size: int) -> void:
	var th := _theme()
	var n := size + 2
	grid = WorldGrid.new()
	grid.setup(Vector2i(n, n), Vector3(-n * TILE_SIZE * 0.5, 0.0, -n * TILE_SIZE * 0.5))
	var floor_list: Array = []
	for j in n:
		for i in n:
			var c := Vector2i(i, j)
			if i == 0 or j == 0 or i == n - 1 or j == n - 1:
				grid.set_void(c)
			else:
				grid.set_floor(c, true)
				floor_list.append(c)
	grid.rebuild_astar()
	_player_start = Vector3.ZERO
	_kit = WorldKit.new(th)
	_rng.seed = 4242
	_build_floor_tiles(floor_list, th["floor_tint"], th["floor_tints"])
	_build_wall_blocks(func(c: Vector2i) -> bool: return grid.is_floor(c), th["wall_tint"])
	_build_collision({}, [])
	_setup_environment()
	_minimap_cells = grid.floor_cells.duplicate()
	grid.explored.fill(1)
	grid.explored_version += 1

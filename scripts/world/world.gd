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
## Acts: an "act" area is ONE seamless World per act (desert / forest / gothic): the hub and the
## wilds, merged by WorldActComposite (scripts/world/acts/) and built by _build_act(): a
## vertex-coloured ground mesh with relief, water, floor tiles, props, collision, lights, light
## shafts, ambient particles and the act's sky / fog. The World tracks the region (hub / wilds)
## the player stands in: area_info "zone" / "name" follow it, Events.zone_entered announces a
## crossing, and the environment blends to the region's look. Hubs are safe regions (monsters
## stay out, see is_safe_at()).
##
## Grid note: towns, dungeons and acts use the §13 grid (origin Vector3.ZERO). The test "arena" is
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

## {"id": "town"|"dungeon"|"act"|"arena", "name": String, "depth": int, "level": int (monster level),
##  "seed": int, "theme": "town"|"crypt"|"cave"|"inferno"|"arena"|<act id>, "size": int (arena only),
##  "act": String, "zone": the act region the player is in ("hub", "outskirts", ...; acts only; see
##  ActDefs), "arrival": where the player enters an act world}
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
## Fog of war over the view (WorldFog: far ground darker, unexplored ground nearly black), for
## towns, dungeons and acts; null in test arenas or when fog_of_war_enabled is off.
var fog: MeshInstance3D = null
## Act worlds: the ground's material (WorldGroundFx.ground_material for acts with a ground style)
## and the details + grass node (WorldGroundFx), else null.
var ground_material: Material = null
var ground_fx: WorldGroundFx = null
## Fog of war for newly built worlds (tools that shoot whole maps turn it off; the debug menu
## toggles it with set_fog_enabled).
static var fog_of_war_enabled := true
## Portals, gate, merchant, stash, chests, shrines.
var interactables_root: Node3D = null
var world_environment: WorldEnvironment = null
## The directional moon (dungeons) / sun (town).
var sun: DirectionalLight3D = null
## Raw layout data from the generator (read-only; handy for tests and debugging).
var layout: Dictionary = {}
## Milliseconds the last build() took.
var build_time_ms: float = 0.0
## Act builds: milliseconds per build phase (for tuning: layout, ground, props, collision...).
var build_profile: Dictionary = {}
var _prof_t := 0
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
## Acts: the generator that laid the zone out, its full theme and the ambient particles.
var _act_gen: WorldActGen = null
var _act_theme: Dictionary = {}
var _particles: GPUParticles3D = null
## Acts: regions [{"id", "name", "safe"}], the per-cell region map (index + 1, 0 = none), arrival
## spots {"hub", every region id, "wilds" (= the outskirts), "town_portal", "dungeon_exit"},
## per-region themes, and the region the
## player is in.
var _regions: Array = []
var _region_map := PackedByteArray()
var _arrivals: Dictionary = {}
var _region_themes: Dictionary = {}
var current_region := ""
## Acts: the act's base monster level (the outskirts); each region adds its level offset.
var act_base_level := 1
## Acts: monster groups not spawned yet (spawned when the player comes near, see start_lazy_spawns).
var _lazy: Array = []
var _lazy_buckets: Dictionary = {}
var _lazy_on := false
var _lazy_timer := 0.0
var _lazy_pack := 0
## A monster group is spawned when the player comes this close (beyond the sleep distance).
const LAZY_RADIUS := 56.0
const LAZY_BUCKET := 32.0
const LAZY_PER_TICK := 3
var _pending_region := ""
var _pending_time := 0.0
var _env_tween: Tween = null
## The town portal pair of an act world: [field portal, town portal] (see open_town_portal_pair).
var _tp_pair: Array = []
## Regions cleared (their boss slain), for the HUD.
var cleared_regions: Dictionary = {}
## Seconds the player must stay across a region border before it counts (no flicker).
const REGION_DEBOUNCE := 0.3


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
			if not theme in ["crypt", "cave", "inferno"] and not WorldThemes.THEMES.get(theme, {}).has("style"):
				theme = theme_for_depth(depth)
			_build_dungeon(depth, int(info.get("seed", depth * 7919)))
		"act":
			var act := String(info.get("act", "desert"))
			theme = act if ActDefs.has_act(act) else "desert"
			_build_act(theme, String(info.get("arrival", info.get("zone", "hub"))), int(info.get("seed", 1)), int(info.get("level", 1)))
		_:
			theme = "arena"
			_build_arena(maxi(int(info.get("size", 16)), 2))
	if id in ["town", "dungeon", "act"]:
		_setup_fog()
	build_time_ms = (Time.get_ticks_usec() - t0) / 1000.0
	build_finished.emit()


const WorldFog := preload("res://scripts/world/world_fog.gd")


## The fog of war for this area: towns only shade far ground (they are fully explored); dungeons
## and acts also black out what was never explored; night acts and dungeons shade deeper.
func _setup_fog() -> void:
	fog = null
	if not fog_of_war_enabled or grid == null:
		return
	var id := String(area_info.get("id", ""))
	var params := {}
	match id:
		"town":
			params = {"use_explored": false, "far_dim": 0.22, "fog_color": Color(0.03, 0.03, 0.04)}
		"dungeon":
			params = {"far_dim": 0.5, "unexplored_dim": 1.0, "fog_color": Color(0.008, 0.008, 0.012)}
		_:
			var day := bool(area_info.get("daylight", ActDefs.get_act(String(area_info.get("act", "desert"))).get("daylight", true)))
			params = {"far_dim": 0.38 if day else 0.5, "unexplored_dim": 1.0,
				"fog_color": Color(0.035, 0.035, 0.045) if day else Color(0.01, 0.014, 0.02)}
	var f := WorldFog.new()
	level_root.add_child(f)
	f.setup(self, params)
	fog = f


## Show / hide the fog of war now (and for the worlds built after this).
func set_fog_enabled(on: bool) -> void:
	fog_of_war_enabled = on
	if fog != null and is_instance_valid(fog):
		fog.visible = on
	elif on and grid != null and String(area_info.get("id", "")) in ["town", "dungeon", "act"]:
		_setup_fog()


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


func is_act() -> bool:
	return area_info.get("id", "") == "act"


## An act's safe settlement (merchant, stash, waystone): the player is in the act's town.
func is_act_hub() -> bool:
	return is_act() and bool(area_info.get("safe", String(area_info.get("zone", "hub")) == "hub"))


## An act's combat regions (the outskirts and every further zone): the player is outside the town.
func is_act_wilds() -> bool:
	return is_act() and not is_act_hub()


## Town or an act hub: no monsters, potions refill, the vendor restocks.
func is_safe_area() -> bool:
	return is_town() or is_act_hub()


## A dungeon depth or act wilds: monsters, town portal allowed, kept on town portal / death.
func is_combat_area() -> bool:
	return is_dungeon() or is_act_wilds()


## Daylit outdoor areas (town, sunny acts): softer hover highlights, weaker player light.
func is_daylit() -> bool:
	if is_town():
		return true
	if is_act():
		return bool(area_info.get("daylight", _act_theme.get("daylight", true)))
	return false


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
	if area_info.has("act"):
		# Act dungeon (the act boss fell): back out into the act, and on to the next act's town
		# (Emberfall after the last act).
		var act := String(area_info["act"])
		var aspots := _portal_spots(get_nearest_walkable(pos), 2, _occupied_spots([]))
		var out := WorldPortal.new().setup_overworld(act)
		out.name = "PortalOut"
		_add_interactable(out, aspots[0], 0.0)
		_exit_portals.append(out)
		var nxt := ActDefs.next_act(act)
		var onward := WorldPortal.new().setup_act(nxt, "hub") if nxt != "" else WorldPortal.new().setup_act("", "town")
		onward.name = "PortalActNext"
		_add_interactable(onward, aspots[aspots.size() - 1], 0.0)
		_exit_portals.append(onward)
		return
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
	if not is_town() and not is_act():
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
	var kept_name := ""
	if kept is World:
		depth = int((kept as World).area_info.get("depth", 1))
		if (kept as World).is_act():
			kept_name = String((kept as World).area_info.get("name", ""))
	var spot: Dictionary = layout.get("portal_spot", {})
	if spot.is_empty():
		spot = {"pos": _player_start + Vector3(0, 0, -6), "yaw": 0.0}
	_return_portal = WorldPortal.new().setup("return", depth)
	if kept_name != "":
		_return_portal.display_name = "Return to %s" % kept_name
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
	fog = null
	ground_material = null
	ground_fx = null
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
	_act_gen = null
	_act_theme = {}
	_particles = null
	_regions = []
	_region_map = PackedByteArray()
	_arrivals = {}
	_region_themes = {}
	current_region = ""
	_pending_region = ""
	_tp_pair = []
	cleared_regions = {}
	act_base_level = 1
	_lazy = []
	_lazy_buckets = {}
	_lazy_on = false
	_lazy_pack = 0


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
	if not _act_theme.is_empty():
		return _act_theme
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
	# The body enters the tree after all its shapes are added: adding shapes to a body that is
	# already in the physics space costs more with every shape (quadratic for big acts).
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
	level_root.add_child(_collision_body)


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
	if not _regions.is_empty():
		_update_region(delta)
	if _lazy_on:
		_lazy_timer -= delta
		if _lazy_timer <= 0.0:
			_lazy_timer = 0.25
			lazy_spawn_tick(false)
	if _particles != null and is_instance_valid(_particles):
		var f := _light_focus()
		_particles.global_position = Vector3(f.x, 0.0, f.z)
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
	# Act dungeon palettes ("tomb", ...) are built on a base layout style.
	gen.palette = theme
	layout = gen.generate(depth, seed_value, String(th.get("style", theme)))
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
	# The way out: town (Emberfall depths), or back into the act (act dungeons).
	var portal := WorldPortal.new()
	if area_info.has("act"):
		portal.setup_overworld(String(area_info["act"]))
	else:
		portal.setup("town")
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
	grid.mark_explored(_player_start, 22.0)


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


# ------------------------------------------------------------------ build: act zones

## Most real OmniLight3Ds an act zone gets; with more light sources a moving pool is used.
const ACT_STATIC_LIGHTS := 14
const ACT_LIGHT_POOL := 14

const WATER_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 shallow : source_color = vec4(0.22, 0.46, 0.5, 1.0);
uniform vec4 deep : source_color = vec4(0.04, 0.16, 0.24, 1.0);
uniform vec4 foam : source_color = vec4(0.85, 0.9, 0.88, 1.0);
uniform float depth_scale = 1.4;
uniform vec2 flow = vec2(0.0, 0.035);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float waves(vec2 p, float t) {
	return vnoise(p * 0.9 + flow * t * 6.0) * 0.6 + vnoise(p * 2.3 - flow.yx * t * 9.0 + 3.1) * 0.4;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec3 bottom = up.xyz / up.w;
	float thick = clamp(VERTEX.z - bottom.z, 0.0, 20.0);
	float t = 1.0 - exp(-thick * depth_scale);
	vec2 p = wp.xz * 0.55;
	float e = 0.08;
	float h0 = waves(p, TIME);
	float hx = waves(p + vec2(e, 0.0), TIME);
	float hz = waves(p + vec2(0.0, e), TIME);
	vec3 n = normalize(vec3((h0 - hx) * 2.2, 1.0, (h0 - hz) * 2.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float edge = 1.0 - smoothstep(0.0, 0.3, thick);
	float sparkle = smoothstep(0.72, 0.95, h0) * 0.25;
	ALBEDO = mix(mix(shallow.rgb, deep.rgb, t), foam.rgb, edge * 0.55 + sparkle * (1.0 - t));
	ALPHA = clamp(mix(0.45, 0.94, t) + edge * 0.3, 0.0, 1.0);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
"""

const SHAFT_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float strength = 0.35;
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	across = smoothstep(0.0, 1.0, across);
	float along = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float shimmer = 0.75 + 0.25 * sin(TIME * 0.7 + wp.x * 0.4 + wp.z * 0.3);
	vec3 vdir = normalize(VERTEX);
	float facing = abs(dot(NORMAL, -vdir));
	float k = across * along * shimmer * strength * smoothstep(0.05, 0.5, facing);
	ALBEDO = color.rgb * k;
}
"""

static var _water_shader: Shader = null
static var _shaft_shader: Shader = null


func _prof(phase: String) -> void:
	var now := Time.get_ticks_usec()
	build_profile[phase] = roundf((now - _prof_t) / 100.0) / 10.0
	_prof_t = now


func _build_act(act: String, zone: String, seed_value: int, level: int) -> void:
	build_profile = {}
	_prof_t = Time.get_ticks_usec()
	var gen := WorldActComposite.new()
	layout = gen.compose(act, seed_value, level)
	_prof("layout")
	for k in (layout.get("profile", {}) as Dictionary):
		build_profile["layout." + String(k)] = roundf(float(layout["profile"][k]) * 10.0) / 10.0
	_act_gen = gen
	_regions = layout["regions"]
	_region_map = layout["region_map"]
	_arrivals = layout["arrivals"]
	_region_themes = layout["region_themes"]
	grid = layout["grid"]
	var arrival := zone if _arrivals.has(zone) else "hub"
	_player_start = _arrivals[arrival]
	var region := region_at(_player_start)
	if region == "":
		region = "hub"
	_act_theme = _region_themes.get(region, gen.full_theme())
	var th := _act_theme
	act_base_level = maxi(1, level)
	_spawn_groups = layout["spawn_groups"]
	for g in _spawn_groups:
		var gl := act_base_level + int(g.get("level_offset", 0))
		g["level"] = gl
		g["depth"] = ActDefs.depth_for_level(gl)
	_kit = WorldKit.new(th)
	_rng.seed = seed_value * 31 + 7
	_build_act_ground(gen)
	_prof("ground")
	if bool(layout.get("has_water", false)):
		_build_act_water(th)
	for tg in layout["tiles"]:
		_build_act_tiles(tg)
	_prof("tiles")
	_build_act_props(layout["props"])
	_prof("props")
	ground_fx = WorldGroundFx.new()
	level_root.add_child(ground_fx)
	ground_fx.build(self, layout.get("details", []), layout.get("grass", []))
	build_profile["details"] = ground_fx.detail_count
	build_profile["grass"] = ground_fx.grass_count
	_prof("ground_fx")
	_build_collision(layout["soft"], layout["shapes"])
	_prof("collision")
	# Lights: real ones up to the budget, else a moving pool (like dungeon torches).
	var cands: Array = []
	for l in layout["lights"]:
		cands.append({"pos": l["pos"], "color": l.get("color", th["light_color"]), "energy": float(l.get("energy", th["light_energy"])),
			"range": float(l.get("range", th["light_range"])), "flicker": bool(l.get("flicker", true))})
	if cands.size() <= ACT_STATIC_LIGHTS:
		for c in cands:
			_add_light(c["pos"], c["color"], c["energy"], c["range"], c["flicker"])
	else:
		_setup_light_pool(cands, ACT_LIGHT_POOL)
	_build_glows(layout["glows"], float(th["glow_pool_strength"]))
	_build_act_shafts(layout["shafts"], float(th["shaft_strength"]))
	_setup_act_environment(th)
	_build_act_particles(th.get("particles", {}))
	# Interactables.
	for it in layout["interactables"]:
		_add_act_interactable(it, act, level)
	refresh_town_portal()
	# Custom decoration from the act.
	_prof("lights_env_interactables")
	var deco := Node3D.new()
	deco.name = "ActDecor"
	_geo.add_child(deco)
	gen.decorate(self, deco)
	_prof("decorate")
	# Minimap: walkable ground plus small solid props standing on floor (a blocked floor cell with at
	# least two walkable neighbours: a tree, a statue); big groves / outcrops show as blocked.
	# Safe regions (the town) are known from the start.
	_minimap_cells = PackedByteArray()
	_minimap_cells.resize(grid.size.x * grid.size.y)
	var soft: Dictionary = layout["soft"]
	var gw := grid.size.x
	var gh := grid.size.y
	for jj in gh:
		for ii in gw:
			var k := jj * gw + ii
			if grid.walk[k] == 1:
				_minimap_cells[k] = 1
			elif grid.floor_cells[k] == 1 and soft.has(Vector2i(ii, jj)):
				var nb := 0
				if ii > 0 and grid.walk[k - 1] == 1:
					nb += 1
				if ii < gw - 1 and grid.walk[k + 1] == 1:
					nb += 1
				if jj > 0 and grid.walk[k - gw] == 1:
					nb += 1
				if jj < gh - 1 and grid.walk[k + gw] == 1:
					nb += 1
				if nb >= 2:
					_minimap_cells[k] = 1
			var rv := int(_region_map[k]) if k < _region_map.size() else 0
			if rv > 0 and bool((_regions[rv - 1] as Dictionary).get("safe", false)):
				grid.explored[k] = 1
	grid.explored_version += 1
	grid.mark_explored(_player_start, 22.0)
	_set_region(region, false)
	_prof("minimap")


# ------------------------------------------------------------------ act regions

## Regions of an act world, the town first: [{"id", "name", "level" (offset), "safe"}] (empty
## elsewhere).
func get_regions() -> Array:
	return _regions.duplicate(true)


## Monster level of an act region (the act's base level + the region's offset).
func region_level(id: String) -> int:
	return act_base_level + int(get_region(id).get("level", 0))


# ------------------------------------------------------------------ lazy monster spawning

## Act worlds: spawn monster groups only when the player comes within LAZY_RADIUS (a few per
## 0.25 s), the ones near the player right away. Groups keep their region's level and pool.
func start_lazy_spawns() -> void:
	_lazy = []
	_lazy_buckets = {}
	for g in _spawn_groups:
		_lazy.append(g)
		var p: Vector3 = g["position"]
		var key := Vector2i(floori(p.x / LAZY_BUCKET), floori(p.z / LAZY_BUCKET))
		if not _lazy_buckets.has(key):
			_lazy_buckets[key] = []
		(_lazy_buckets[key] as Array).append(_lazy.size() - 1)
	_lazy_on = true
	_lazy_timer = 0.0
	lazy_spawn_tick(true)


## Stop spawning (monsters off / removed): pending groups are forgotten.
func stop_lazy_spawns() -> void:
	_lazy_on = false
	_lazy = []
	_lazy_buckets = {}


## Groups still waiting to be spawned (copies).
func pending_groups() -> Array:
	var out: Array = []
	for g in _lazy:
		if g != null:
			out.append((g as Dictionary).duplicate())
	return out


## Groups still waiting to be spawned.
func pending_spawn_count() -> int:
	var n := 0
	for g in _lazy:
		if g != null:
			n += 1
	return n


## Spawn the pending groups near the player (all of them when `all_near`, else a few).
func lazy_spawn_tick(all_near: bool = false) -> int:
	if not _lazy_on or _lazy.is_empty():
		return 0
	var f := _light_focus()
	var r := LAZY_RADIUS
	var cands: Array = []
	var lo := Vector2i(floori((f.x - r) / LAZY_BUCKET), floori((f.z - r) / LAZY_BUCKET))
	var hi := Vector2i(floori((f.x + r) / LAZY_BUCKET), floori((f.z + r) / LAZY_BUCKET))
	for bj in range(lo.y, hi.y + 1):
		for bi in range(lo.x, hi.x + 1):
			for idx in _lazy_buckets.get(Vector2i(bi, bj), []):
				var g: Variant = _lazy[idx]
				if g == null:
					continue
				var d := CombatQuery.distance_xz(f, (g as Dictionary)["position"])
				if d <= r:
					cands.append([d, idx])
	if cands.is_empty():
		return 0
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var n := 0
	for c in cands:
		if not all_near and n >= LAZY_PER_TICK:
			break
		var idx: int = c[1]
		var g: Dictionary = _lazy[idx]
		_lazy[idx] = null
		EnemyDB.spawn_group(self, g, _lazy_pack)
		_lazy_pack += 1
		n += 1
	return n


## The region id at a position ("" outside act worlds / off the map).
func region_at(pos: Vector3) -> String:
	if _regions.is_empty() or grid == null:
		return ""
	var c := grid.world_to_cell(pos)
	if not grid.in_bounds(c):
		return ""
	var v := int(_region_map[grid.idx(c)]) if grid.idx(c) < _region_map.size() else 0
	return String((_regions[v - 1] as Dictionary)["id"]) if v > 0 and v <= _regions.size() else ""


func get_region(id: String) -> Dictionary:
	for r in _regions:
		if String(r["id"]) == id:
			return r
	return {}


## True where monsters never go (an act hub). False outside act worlds.
func is_safe_at(pos: Vector3) -> bool:
	var id := region_at(pos)
	return id != "" and bool(get_region(id).get("safe", false))


## Where the player arrives for an act region / spot: "hub", a region id, "wilds", "town_portal",
## "dungeon_exit" (falls back to the hub arrival, then the player start).
func get_region_arrival(id: String) -> Vector3:
	if _arrivals.has(id):
		return _arrivals[id]
	return _arrivals.get("hub", _player_start)


## The act's dungeon entrance ({} when none): {"pos", "yaw", "model", "size", "zone"}.
func get_dungeon_entrance() -> Dictionary:
	return (layout.get("dungeon_entrance", {}) as Dictionary).duplicate()


## Set the current region (area_info "zone" / "name" follow it; GameState.current_area is the
## same dictionary). announce: emit Events.zone_entered and blend the environment.
func _set_region(id: String, announce: bool) -> void:
	var r := get_region(id)
	if r.is_empty():
		return
	var prev := current_region
	current_region = id
	_pending_region = ""
	area_info["zone"] = id
	area_info["name"] = String(r.get("name", id))
	area_info["safe"] = bool(r.get("safe", false))
	area_info["cleared"] = cleared_regions.has(id)
	var lvl := act_base_level + int(r.get("level", 0))
	area_info["level"] = lvl
	area_info["depth"] = ActDefs.depth_for_level(lvl)
	if announce and prev != id:
		_blend_environment(_region_themes.get(id, {}))
		Events.zone_entered.emit(area_info)


## Re-read the player's region right away (after the game flow places the player).
func sync_region(announce: bool = false) -> void:
	var p := GameState.player
	if p != null and is_instance_valid(p) and is_ancestor_of(p):
		var id := region_at(p.global_position if p.is_inside_tree() else p.position)
		if id != "" and id != current_region:
			_set_region(id, announce)
			if not announce:
				_apply_environment(_region_themes.get(id, {}))


func _update_region(delta: float) -> void:
	var p := GameState.player
	if p == null or not is_instance_valid(p) or not is_ancestor_of(p) or not p.is_inside_tree():
		return
	var id := region_at(p.global_position)
	if id == "" or id == current_region:
		_pending_region = ""
		return
	if id != _pending_region:
		_pending_region = id
		_pending_time = 0.0
	_pending_time += delta
	if _pending_time >= REGION_DEBOUNCE:
		_set_region(id, true)


## Blend the look (fog, ambient, sun, sky, tonemap) towards a region's theme over ~2.5 s.
func _blend_environment(th: Dictionary) -> void:
	if th.is_empty() or world_environment == null or not is_inside_tree():
		return
	if _env_tween != null and _env_tween.is_valid():
		_env_tween.kill()
	var env := world_environment.environment
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	var dur := 2.5
	tw.tween_property(env, "ambient_light_color", th["ambient"], dur)
	tw.tween_property(env, "ambient_light_energy", float(th["ambient_energy"]), dur)
	tw.tween_property(env, "fog_light_color", th["fog"], dur)
	tw.tween_property(env, "fog_density", float(th["fog_density"]), dur)
	tw.tween_property(env, "fog_height_density", float(th["fog_height_density"]), dur)
	tw.tween_property(env, "tonemap_exposure", float(th["exposure"]), dur)
	tw.tween_property(env, "adjustment_saturation", float(th["saturation"]), dur)
	tw.tween_property(env, "adjustment_contrast", float(th["contrast"]), dur)
	tw.tween_property(env, "adjustment_brightness", float(th["brightness"]), dur)
	if sun != null:
		tw.tween_property(sun, "light_color", th["sun"], dur)
		tw.tween_property(sun, "light_energy", float(th["sun_energy"]), dur)
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		tw.tween_property(sm, "sky_top_color", th["sky_top"], dur)
		tw.tween_property(sm, "sky_horizon_color", th["sky_horizon"], dur)
	# Volumetric fog (on for the whole act when any region has it; regions without it fade it out).
	var vf: Dictionary = th.get("volumetric_fog", {})
	if env.volumetric_fog_enabled and vf.is_empty():
		tw.tween_property(env, "volumetric_fog_density", 0.0, dur)
	elif env.volumetric_fog_enabled:
		tw.tween_property(env, "volumetric_fog_density", float(vf.get("density", 0.02)), dur)
		tw.tween_property(env, "volumetric_fog_albedo", vf.get("albedo", Color(0.8, 0.8, 0.8)), dur)
		tw.tween_property(env, "volumetric_fog_emission", vf.get("emission", Color.BLACK), dur)
		tw.tween_property(env, "volumetric_fog_emission_energy", float(vf.get("emission_energy", 1.0)), dur)
		tw.tween_property(env, "volumetric_fog_anisotropy", float(vf.get("anisotropy", 0.2)), dur)
	_act_theme = th
	_env_tween = tw


func _apply_environment(th: Dictionary) -> void:
	if th.is_empty() or world_environment == null:
		return
	var env := world_environment.environment
	env.ambient_light_color = th["ambient"]
	env.ambient_light_energy = float(th["ambient_energy"])
	env.fog_light_color = th["fog"]
	env.fog_density = float(th["fog_density"])
	env.fog_height_density = float(th["fog_height_density"])
	env.tonemap_exposure = float(th["exposure"])
	env.adjustment_saturation = float(th["saturation"])
	env.adjustment_contrast = float(th["contrast"])
	env.adjustment_brightness = float(th["brightness"])
	if sun != null:
		sun.light_color = th["sun"]
		sun.light_energy = float(th["sun_energy"])
	var vf: Dictionary = th.get("volumetric_fog", {})
	if env.volumetric_fog_enabled and vf.is_empty():
		env.volumetric_fog_density = 0.0
	elif env.volumetric_fog_enabled:
		env.volumetric_fog_density = float(vf.get("density", 0.02))
		env.volumetric_fog_albedo = vf.get("albedo", Color(0.8, 0.8, 0.8))
		env.volumetric_fog_emission = vf.get("emission", Color.BLACK)
		env.volumetric_fog_emission_energy = float(vf.get("emission_energy", 1.0))
		env.volumetric_fog_anisotropy = float(vf.get("anisotropy", 0.2))
	_act_theme = th


## Act world town portal: a portal where it was cast (to the hub) and one in the hub (back to that
## spot; using it closes both). Replaces an older pair. Returns where the player arrives in town.
func open_town_portal_pair(cast_pos: Vector3) -> Vector3:
	close_town_portal_pair()
	var act := String(area_info.get("act", theme))
	var hub_spot := get_region_arrival("town_portal")
	var field_base := get_nearest_walkable(Vector3(cast_pos.x, 0, cast_pos.z))
	var field_pos: Vector3 = _portal_spots(field_base, 1, _occupied_spots([]))[0]
	var home_pos: Vector3 = _portal_spots(get_nearest_walkable(hub_spot), 1, _occupied_spots([]))[0]
	var region_name := String(get_region(region_at(cast_pos)).get("name", "the wilds"))
	var field := WorldPortal.new().setup_local(_in_front_of(home_pos), ActDefs.zone_name(act, "hub"))
	field.name = "TownPortalField"
	var home := WorldPortal.new().setup_local(_in_front_of(field_pos), "Return to %s" % region_name, true)
	home.name = "TownPortalHome"
	_add_interactable(field, field_pos, 0.0)
	_add_interactable(home, home_pos, 0.0)
	_tp_pair = [field, home]
	return _in_front_of(home_pos)


func close_town_portal_pair() -> void:
	for n in _tp_pair:
		if is_instance_valid(n):
			_interactables.erase(n)
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_tp_pair = []


func get_town_portal_pair() -> Array:
	var out: Array = []
	for n in _tp_pair:
		if is_instance_valid(n):
			out.append(n)
	return out


## A walkable spot just in front of (south of) a standing portal.
func _in_front_of(portal_pos: Vector3) -> Vector3:
	return get_nearest_walkable(portal_pos + Vector3(0, 0, 2.2))


func _add_act_interactable(it: Dictionary, act: String, level: int) -> void:
	var pos: Vector3 = it.get("pos", _player_start)
	var yaw := float(it.get("yaw", 0.0))
	var nth := _interactables.size() + 1
	match String(it.get("kind", "")):
		"portal":
			var p := WorldPortal.new().setup_act(String(it.get("act", act)), String(it.get("zone", "hub")))
			p.name = "Portal_%s_%s" % [it.get("act", act), it.get("zone", "hub")]
			_add_interactable(p, pos, yaw)
		"vendor":
			var v := WorldVendorNpc.new()
			v.name = "Merchant"
			_add_interactable(v, pos, yaw)
		"stash":
			var s := WorldStashChest.new()
			s.name = "Stash"
			_add_interactable(s, pos, yaw)
		"waystone":
			var w := WorldActWaystone.new().setup(act, String(it.get("model", "")))
			w.name = "Waystone"
			_add_interactable(w, pos, yaw)
		"chest":
			var ch := WorldChest.new().setup(int(it.get("tier", 0)), level)
			ch.name = "Chest%d" % nth
			_add_interactable(ch, pos, yaw)
		"shrine":
			var sh := WorldShrine.new().setup(String(it.get("shrine", "fury")))
			sh.name = "Shrine%d" % nth
			_add_interactable(sh, pos, yaw)
		"dungeon":
			var de := WorldDungeonEntrance.new().setup(act, String(it.get("model", "")), it.get("size", Vector2(4, 4)))
			de.kit = _kit
			de.name = "DungeonEntrance"
			_add_interactable(de, pos, yaw)
		var other:
			push_warning("World: unknown act interactable kind '%s'" % other)


## Props grouped by look (cutout, shadows, tint, emission, sway) into chunked MultiMeshes.
func _build_act_props(items: Array) -> void:
	var groups := {}
	for d in items:
		var params := {}
		if d.has("emission_color"):
			params["emission_color"] = d["emission_color"]
		if float(d.get("sway", 0.0)) > 0.0:
			params["sway"] = float(d["sway"])
			params["sway_base"] = float(d.get("sway_base", 1.0))
		var tint: Color = d.get("tint", Color.WHITE)
		var key := "%s|%s|%s|%s|%s" % [d["id"], bool(d.get("cutout", false)), bool(d.get("shadows", true)), tint.to_html(), params]
		if not groups.has(key):
			groups[key] = {"id": d["id"], "cutout": bool(d.get("cutout", false)), "shadows": bool(d.get("shadows", true)),
				"tint": tint, "params": params, "xf": [], "col": []}
		var g: Dictionary = groups[key]
		var sc := float(d.get("scale", 1.0))
		(g["xf"] as Array).append(_prop_xf(d["pos"], float(d.get("yaw", 0.0)), sc))
		(g["col"] as Array).append(_variation(float(d.get("vary", 0.08))))
	for key in groups:
		var g2: Dictionary = groups[key]
		_kit.add_multimesh(_geo, g2["id"], g2["xf"], g2["col"], g2["tint"], g2["cutout"], g2["shadows"], g2["params"])


## Floor tiles from a tile group (random id per cell, random quarter turns, tint jitter).
func _build_act_tiles(tg: Dictionary) -> void:
	var ids: Array = tg.get("ids", FLOOR_IDS)
	if ids.is_empty():
		return
	var tint: Color = tg.get("tint", Color(0.8, 0.8, 0.8))
	var tints: Array = tg.get("tints", [])
	var by_id := {}
	for c in tg.get("cells", []):
		var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
		if not by_id.has(id):
			by_id[id] = [[], []]
		var hue: Color = tints[_rng.randi_range(0, tints.size() - 1)] if not tints.is_empty() else tint
		var v := _rng.randf_range(0.95, 1.03)
		by_id[id][0].append(Transform3D(Basis(Vector3.UP, _rng.randi_range(0, 3) * PI * 0.5), grid.cell_center(c) + Vector3(0, 0.001, 0)))
		by_id[id][1].append(Color(hue.r / maxf(tint.r, 0.01) * v, hue.g / maxf(tint.g, 0.01) * v, hue.b / maxf(tint.b, 0.01) * v))
	for id in by_id:
		_kit.add_multimesh(_geo, id, by_id[id][0], by_id[id][1], tint, bool(tg.get("cutout", false)), false)


## Distance (m) from every grid cell centre to the nearest walkable cell centre (chamfer 3-4).
func _walk_distance_field() -> PackedFloat32Array:
	var w := grid.size.x
	var h := grid.size.y
	var d := PackedFloat32Array()
	d.resize(w * h)
	for k in w * h:
		d[k] = 0.0 if grid.walk[k] == 1 or (grid.floor_cells[k] == 1 and layout["soft"].has(Vector2i(k % w, k / w))) else 1e6
	var diag := TILE_SIZE * 1.4142
	for pass_i in 2:
		var rng_j: Array = range(h) if pass_i == 0 else range(h - 1, -1, -1)
		var rng_i: Array = range(w) if pass_i == 0 else range(w - 1, -1, -1)
		var s := -1 if pass_i == 0 else 1
		for jv in rng_j:
			var j: int = jv
			for iv in rng_i:
				var i: int = iv
				var k: int = j * w + i
				var best := d[k]
				var i2: int = i + s
				var j2: int = j + s
				if i2 >= 0 and i2 < w:
					best = minf(best, d[j * w + i2] + TILE_SIZE)
				if j2 >= 0 and j2 < h:
					best = minf(best, d[j2 * w + i] + TILE_SIZE)
					if i2 >= 0 and i2 < w:
						best = minf(best, d[j2 * w + i2] + diag)
					var i3: int = i - s
					if i3 >= 0 and i3 < w:
						best = minf(best, d[j2 * w + i3] + diag)
				d[k] = best
	return d


func _sample_field(d: PackedFloat32Array, x: float, z: float) -> float:
	var w := grid.size.x
	var h := grid.size.y
	var u := x / TILE_SIZE - 0.5
	var v := z / TILE_SIZE - 0.5
	var cu := clampf(u, 0.0, w - 1.0)
	var cv := clampf(v, 0.0, h - 1.0)
	var outside := Vector2(u - cu, v - cv).length() * TILE_SIZE
	var i0 := mini(int(cu), w - 2)
	var j0 := mini(int(cv), h - 2)
	var fu := cu - i0
	var fv := cv - j0
	var a := lerpf(d[j0 * w + i0], d[j0 * w + i0 + 1], fu)
	var b := lerpf(d[(j0 + 1) * w + i0], d[(j0 + 1) * w + i0 + 1], fu)
	return lerpf(a, b, fv) + outside


## The ground: one vertex-coloured mesh over layout ground_rect, relief from the generator
## (flattened on and near walkable cells), normals from the height field.
## Ground tiles are GROUND_TILE metres square: fine (the layout's ground_step, at most
## GROUND_NEAR_MAX_STEP) where walkable ground is within GROUND_NEAR metres, coarse (GROUND_FAR_STEP)
## farther out, where only the far camera ever looks.
const GROUND_TILE := 32.0
const GROUND_NEAR := 36.0
const GROUND_NEAR_MAX_STEP := 2.0
const GROUND_FAR_STEP := 8.0

## The ground: vertex-coloured mesh tiles over layout ground_rect, relief from the generator
## (flattened on and near walkable cells; ground below a water plane's level eases in sooner, so
## shores sit close to the walkable edge), normals from the height field, one MeshInstance3D per
## tile (frustum culled).
func _build_act_ground(gen: WorldActGen) -> void:
	var rect: Rect2 = layout["ground_rect"]
	var near_step := clampf(float(layout.get("ground_step", 1.6)), 0.5, GROUND_NEAR_MAX_STEP)
	# A finer spacing on tiles around the town (its paths and plazas are drawn in the ground).
	var fine_step := clampf(float(layout.get("fine_step", near_step)), 0.5, near_step)
	var fine_rect: Rect2 = layout.get("fine_rect", Rect2())
	var field := _walk_distance_field()
	var root := Node3D.new()
	root.name = "Ground"
	_geo.add_child(root)
	_gprof_h = 0
	_gprof_c = 0
	# The act's procedural ground texture (WorldGroundFx) when it has a style, else plain colours.
	var style := String(layout.get("ground_style", ""))
	var mat: Material = WorldGroundFx.ground_material(style)
	var detailed := mat != null
	if mat == null:
		mat = WorldKit.make_material(Color.WHITE, false, 0.95, Color.BLACK, 0.0, true)
	ground_material = mat
	var waters := _act_water_areas()
	var ntx := int(ceil(rect.size.x / GROUND_TILE))
	var ntz := int(ceil(rect.size.y / GROUND_TILE))
	for tz in ntz:
		for tx in ntx:
			var r := Rect2(rect.position.x + tx * GROUND_TILE, rect.position.y + tz * GROUND_TILE,
				minf(GROUND_TILE, rect.end.x - (rect.position.x + tx * GROUND_TILE)), minf(GROUND_TILE, rect.end.y - (rect.position.y + tz * GROUND_TILE)))
			if r.size.x <= 0.01 or r.size.y <= 0.01:
				continue
			# Near walkable ground? (9 samples over the tile.)
			var dmin := INF
			for sz in 3:
				for sx in 3:
					dmin = minf(dmin, _sample_field(field, r.position.x + r.size.x * sx * 0.5, r.position.y + r.size.y * sz * 0.5))
			var step := near_step if dmin < GROUND_NEAR else GROUND_FAR_STEP
			if fine_rect.size.x > 0.0 and fine_rect.intersects(r):
				step = fine_step
			var tile_waters: Array = []
			for wa in waters:
				if (wa["rect"] as Rect2).intersects(r):
					tile_waters.append(wa)
			var mi := _ground_tile(gen, field, r, step, dmin >= GROUND_NEAR, tile_waters, detailed)
			mi.material_override = mat
			root.add_child(mi)
			build_profile["ground_tiles_near" if dmin < GROUND_NEAR else "ground_tiles_far"] = int(build_profile.get("ground_tiles_near" if dmin < GROUND_NEAR else "ground_tiles_far", 0)) + 1
			build_profile["ground_verts"] = int(build_profile.get("ground_verts", 0)) + (mi.mesh as ArrayMesh).surface_get_array_len(0)
	build_profile["ground_height_ms"] = _gprof_h / 1000
	build_profile["ground_color_ms"] = _gprof_c / 1000


var _gprof_h := 0
var _gprof_c := 0

func _ground_tile(gen: WorldActGen, field: PackedFloat32Array, r: Rect2, step: float, far: bool, waters: Array = [], detailed: bool = false) -> MeshInstance3D:
	var nx := maxi(2, int(ceil(r.size.x / step)) + 1)
	var nz := maxi(2, int(ceil(r.size.y / step)) + 1)
	var sx := r.size.x / (nx - 1)
	var sz := r.size.y / (nz - 1)
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var verts := PackedVector3Array()
	verts.resize(nx * nz)
	var cols := PackedColorArray()
	cols.resize(nx * nz)
	# Material weights of the ground shader (WorldActGen.ground_detail): UV = r, g; UV2 = b, a.
	var uv1 := PackedVector2Array()
	var uv2 := PackedVector2Array()
	if detailed:
		uv1.resize(nx * nz)
		uv2.resize(nx * nz)
	for zi in nz:
		for xi in nx:
			var x := r.position.x + xi * sx
			var z := r.position.y + zi * sz
			var t0 := Time.get_ticks_usec()
			var hgt := gen.ground_height(x, z)
			var t1 := Time.get_ticks_usec()
			if hgt != 0.0 and not far:
				# Ground meant to lie under water eases in right past the walkable cells (~2 m), so
				# shores sit close to the walkable edge; other relief eases in over ~3.5 m.
				var under := false
				for wa in waters:
					if hgt < float(wa["level"]) and (wa["rect"] as Rect2).has_point(Vector2(x, z)):
						under = true
						break
				hgt *= smoothstep(1.0, 3.0, _sample_field(field, x, z)) if under else smoothstep(1.2, 4.5, _sample_field(field, x, z))
			var k := zi * nx + xi
			heights[k] = hgt
			verts[k] = Vector3(x, hgt - 0.02, z)
			var t2 := Time.get_ticks_usec()
			cols[k] = gen.ground_color(x, z)
			if detailed:
				var dw := gen.ground_detail(x, z)
				uv1[k] = Vector2(dw.r, dw.g)
				uv2[k] = Vector2(dw.b, dw.a)
			var t3 := Time.get_ticks_usec()
			_gprof_h += t1 - t0
			_gprof_c += t3 - t2
	var normals := PackedVector3Array()
	normals.resize(nx * nz)
	for zi in nz:
		for xi in nx:
			var hl := heights[zi * nx + maxi(xi - 1, 0)]
			var hr := heights[zi * nx + mini(xi + 1, nx - 1)]
			var hd := heights[maxi(zi - 1, 0) * nx + xi]
			var hu := heights[mini(zi + 1, nz - 1) * nx + xi]
			normals[zi * nx + xi] = Vector3((hl - hr) / sx, 2.0, (hd - hu) / sz).normalized()
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var n := 0
	for zi in nz - 1:
		for xi in nx - 1:
			var a := zi * nx + xi
			idx[n] = a
			idx[n + 1] = a + 1
			idx[n + 2] = a + nx
			idx[n + 3] = a + 1
			idx[n + 4] = a + nx + 1
			idx[n + 5] = a + nx
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	if detailed:
		arrays[Mesh.ARRAY_TEX_UV] = uv1
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "GroundTile"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The act's water planes: [{"rect": Rect2, "level": float}] ([] without water).
func _act_water_areas() -> Array:
	if not bool(layout.get("has_water", false)):
		return []
	var areas: Array = layout.get("water_areas", [])
	if areas.is_empty():
		var rects: Array = layout.get("water_rects", [])
		if rects.is_empty():
			rects = [layout["ground_rect"]]
		for r in rects:
			areas.append({"rect": r, "level": float(layout.get("water_level", -0.35))})
	return areas


func _build_act_water(th: Dictionary) -> void:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER_CODE
	var areas := _act_water_areas()
	var mat := ShaderMaterial.new()
	mat.shader = _water_shader
	mat.set_shader_parameter("shallow", th["water_shallow"])
	mat.set_shader_parameter("deep", th["water_deep"])
	mat.set_shader_parameter("foam", th["water_foam"])
	mat.set_shader_parameter("depth_scale", float(th["water_depth_scale"]))
	for k in areas.size():
		var rect: Rect2 = areas[k]["rect"]
		var plane := PlaneMesh.new()
		plane.size = rect.size
		var mi := MeshInstance3D.new()
		mi.name = "Water" if k == 0 else "Water%d" % (k + 1)
		mi.mesh = plane
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(rect.get_center().x, float(areas[k]["level"]), rect.get_center().y)
		_geo.add_child(mi)


## God rays: two crossed additive quads per shaft, leaning with the light.
func _build_act_shafts(shafts: Array, strength: float) -> void:
	if shafts.is_empty() or strength <= 0.0:
		return
	if _shaft_shader == null:
		_shaft_shader = Shader.new()
		_shaft_shader.code = SHAFT_SHADER_CODE
	var root := Node3D.new()
	root.name = "LightShafts"
	_geo.add_child(root)
	for s in shafts:
		var height := float(s.get("height", 12.0))
		var width := float(s.get("width", 2.5))
		var mat := ShaderMaterial.new()
		mat.shader = _shaft_shader
		mat.set_shader_parameter("color", s.get("color", Color(1.0, 0.92, 0.7)))
		mat.set_shader_parameter("strength", 0.35 * strength)
		var quad := QuadMesh.new()
		quad.size = Vector2(width, height)
		var pivot := Node3D.new()
		pivot.position = s["pos"]
		pivot.rotation = Vector3(0.0, float(s.get("yaw", 0.0)), 0.0)
		root.add_child(pivot)
		var tilt := Node3D.new()
		tilt.rotation_degrees = Vector3(0.0, 0.0, float(s.get("tilt", 18.0)))
		pivot.add_child(tilt)
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(0.0, height * 0.5, 0.0)
			mi.rotation = Vector3(0.0, k * PI * 0.5, 0.0)
			tilt.add_child(mi)


## Ambient particles (dust, motes, snow, ash, embers) in a box that follows the player.
func _build_act_particles(p: Dictionary) -> void:
	if p.is_empty():
		return
	var kind := String(p.get("kind", "dust"))
	var color: Color = p.get("color", Color(1.0, 0.95, 0.8, 0.6))
	var amount := int(p.get("amount", 160))
	var size := float(p.get("size", 0.06))
	var speed := float(p.get("speed", 0.4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 5.0, 20.0)
	pm.direction = Vector3(1, 0, 0.3)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	var lifetime := 9.0
	match kind:
		"snow":
			pm.gravity = Vector3(0.3, -0.9, 0.1)
			pm.emission_box_extents = Vector3(22.0, 8.0, 20.0)
			lifetime = 12.0
		"ash":
			pm.gravity = Vector3(0.2, -0.35, 0.1)
			lifetime = 12.0
		"embers":
			pm.gravity = Vector3(0.0, 0.5, 0.0)
		"motes":
			pm.initial_velocity_max = speed * 0.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if kind in ["motes", "embers"] else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	var gp := GPUParticles3D.new()
	gp.name = "AmbientParticles"
	gp.amount = amount
	gp.lifetime = lifetime
	gp.preprocess = lifetime
	gp.process_material = pm
	gp.draw_pass_1 = quad
	gp.local_coords = false
	gp.visibility_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 16, 60))
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.position = Vector3(_player_start.x, 0.0, _player_start.z)
	level_root.add_child(gp)
	_particles = gp


func _setup_act_environment(th: Dictionary) -> void:
	var env := Environment.new()
	if bool(th.get("sky", true)):
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = th["sky_top"]
		sky_mat.sky_horizon_color = th["sky_horizon"]
		sky_mat.ground_horizon_color = th["ground_horizon"]
		sky_mat.ground_bottom_color = th["ground_bottom"]
		sky_mat.sky_energy_multiplier = float(th["sky_energy"])
		sky_mat.ground_energy_multiplier = float(th["sky_energy"])
		sky_mat.sun_angle_max = 20.0
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = float(th["ambient_sky"])
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = th["background"]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_color = th["ambient"]
	env.ambient_light_energy = float(th["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(th["exposure"])
	env.tonemap_white = float(th["white"])
	env.glow_enabled = true
	env.glow_intensity = float(th["glow_intensity"])
	env.glow_strength = float(th["glow_strength"])
	env.glow_bloom = float(th["glow_bloom"])
	env.glow_hdr_threshold = float(th["glow_hdr_threshold"])
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var fog_density := float(th["fog_density"])
	env.fog_enabled = fog_density > 0.0 or float(th["fog_height_density"]) > 0.0
	env.fog_light_color = th["fog"]
	env.fog_light_energy = 1.0
	env.fog_density = fog_density
	env.fog_sky_affect = float(th["fog_sky_affect"])
	env.fog_height = float(th["fog_height"])
	env.fog_height_density = float(th["fog_height_density"])
	var vf: Dictionary = th.get("volumetric_fog", {})
	var vf_density := float(vf.get("density", 0.02))
	if vf.is_empty():
		# Another region has volumetric fog: on (with none here) so walking there can blend it in.
		for rt in _region_themes.values():
			if not ((rt as Dictionary).get("volumetric_fog", {}) as Dictionary).is_empty():
				vf = (rt as Dictionary)["volumetric_fog"]
				vf_density = 0.0
				break
	if not vf.is_empty():
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = vf_density
		env.volumetric_fog_albedo = vf.get("albedo", Color(0.8, 0.8, 0.8))
		env.volumetric_fog_emission = vf.get("emission", Color.BLACK)
		env.volumetric_fog_emission_energy = float(vf.get("emission_energy", 1.0))
		env.volumetric_fog_anisotropy = float(vf.get("anisotropy", 0.2))
		env.volumetric_fog_length = float(vf.get("length", 64.0))
		env.volumetric_fog_detail_spread = float(vf.get("detail_spread", 2.0))
		env.volumetric_fog_gi_inject = float(vf.get("gi_inject", 1.0))
		env.volumetric_fog_sky_affect = float(vf.get("sky_affect", 1.0))
	env.adjustment_enabled = true
	env.adjustment_contrast = float(th["contrast"])
	env.adjustment_saturation = float(th["saturation"])
	env.adjustment_brightness = float(th["brightness"])
	world_environment = WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = env
	level_root.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun" if bool(th.get("daylight", true)) else "Moon"
	sun.rotation_degrees = th["sun_rot"]
	sun.light_color = th["sun"]
	sun.light_energy = float(th["sun_energy"])
	sun.shadow_enabled = bool(th.get("sun_shadows", true))
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.light_specular = 0.4
	level_root.add_child(sun)

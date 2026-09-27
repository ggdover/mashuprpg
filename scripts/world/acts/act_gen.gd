class_name WorldActGen
extends RefCounted
## Base class of the act zone generators (scripts/world/acts/act_<act>.gd). A generator produces
## PURE LAYOUT DATA for World._build_act(): the walkability grid, ground colours / relief, water,
## floor tiles, props, collision, lights, interactables and monster spawn groups — plus the zone's
## look (theme()) and an optional decorate() hook for custom nodes. OWNER: acts framework.
##
## How to write an act generator
##   extends WorldActGen
##   func generate_zone() -> void:          # zone is "hub" (the town) or "wilds"; rng is seeded
##       setup_grid(Vector2i(40, 40))        # all cells start as open, non-walkable "void"
##       carve_rect(Rect2i(4, 4, 32, 32))    # make cells walkable floor
##       start = cell_center(Vector2i(20, 34))
##       add_building("desert_house_a", pos, yaw, Vector2(6, 6))
##       add_obstacle("desert_palm_a", pos, yaw, 1.0, 0.4)
##       add_prop("desert_pot", pos, yaw)    # decoration, no collision
##       add_vendor(...); add_stash(...); add_waystone(...); add_portal_to("wilds", ...)
##       (wilds) add_portal_to("hub", ...); boss_pos = ...; auto_spawn_groups(14, 3)
##   func theme() -> Dictionary: return {...}             # overrides of default_theme()
##   func ground_color(x, z) -> Color: ...                 # vertex colour of the ground mesh
##   func ground_height(x, z) -> float: ...                # relief (dunes, hills, river beds)
##   func decorate(world, parent) -> void: ...             # optional extra nodes
##
## Coordinates: grid cell (i, j) spans x in [2i, 2i + 2], z in [2j, 2j + 2] (origin at 0, like the
## town and the dungeons). Screen-up is world -Z (north). Everything stands at y = 0; ground relief
## is visual only and is automatically flattened on and next to walkable cells (World masks it).
## Model conventions: see docs/ARCHITECTURE.md §14 (origin at the base centre, fronts face +Z).
##
## The generator must be deterministic for a given (act, zone, seed). Do not create nodes in
## generate_zone(); decorate() is the only place for nodes (it runs after the World is built).
##
## Seamless acts (WorldActComposite, act_compose.gd): the act's hub and wilds are generated
## separately (each zone by its own generator instance, in its own coordinates) and then merged
## into ONE map: the wilds are placed beyond the hub's exit so the two exits face each other
## across a short road (EXIT_GAP_CELLS of open ground, the road ROAD_WIDTH_CELLS wide), turned in
## quarter turns if needed. So each zone must:
##   - declare its exit with add_exit(other_zone, pos, dir): pos = the centre of a cell ON the grid
##     edge, dir = the outward direction (Vector2i(0, -1) north, (0, 1) south, (-1, 0) west,
##     (1, 0) east), with walkable ground from the zone's start to that edge cell (at least 3
##     cells wide) and nothing solid in the way. Hub and wilds exits should face opposite
##     directions (hub north <-> wilds south, ...); otherwise the wilds are turned to match.
##   - not add portals between its hub and wilds (the composer drops them anyway).
## Everything a zone lays out beyond the midline of the road (towards the other zone) is dropped,
## and the ground blends between the zones' ground_color()/ground_height() around that midline.
## border_style() describes the act's border pieces (low walls, fences) that the composer places
## along the edges of the walkable ground, so the limits of the map are visible.
## add_dungeon_entrance() places the act's dungeon entrance (entering it fades to the dungeon).
##
## Big open acts (layouts): the "wilds" zone of an act is its whole outdoor map outside the town,
## read from data/layouts/act_<act>.json with use_layout() (see tools/layouts/build_layouts.py):
## every walkable cell belongs to a region ("outskirts" next to the town, then further zones joined
## by paths, each with a level offset). The generator fills each region with content using the
## region helpers (region_cells / region_rect / region_center / region_links / region_at /
## is_region / region_open), scatter_region(), auto_spawn_region() (monster packs; set the region's
## monster pool with set_region_pool) and add_zone_boss(); set_region_theme() changes the look of a
## region (the World blends to it when the player walks in). use_layout() also declares the exit
## towards the town and dungeon_door() tells where the dungeon entrance goes. Budgets for a whole
## act: build (layout + World) under ~5 s, <= ~9000 prop instances, <= ~3000 collision shapes.
## Performance: keep()/is_clear() and scatter() use spatial hashes (cheap); ground_color() and
## ground_height() run for ~100k ground vertices — use noise2() (native FastNoiseLite) and cell
## fields (CellField / field_*()) instead of per-call loops or fbm(), and stay under ~8 us a call.
##
## Gotchas:
##   - ground_color() is used as a LINEAR albedo (the world shader does not convert vertex colours):
##     convert colours picked in sRGB with Color.srgb_to_linear(), or they come out pale.
##   - The default game camera looks north-west (CameraRig.YAW_DEG 37.5, pitch 49.4, 19.5 m): it
##     shows ~14 m of ground beyond the player and ~10 m behind. Tall things south-east of a path
##     stand between the camera and the player (use cutout), landmarks far away only show when the
##     player walks near them.

const TILE := 2.0
## Kinds of interactables World._build_act() understands.
const INTERACTABLE_KINDS: Array[String] = ["portal", "vendor", "stash", "waystone", "chest", "shrine", "dungeon"]

# ------------------------------------------------------------------ inputs (set by generate())

var act_id := ""
## "hub" or "wilds".
var zone := "hub"
var level := 1
var seed_value := 1
var rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------ outputs (fill in generate_zone)

var grid: WorldGrid = null
## Player start (hubs: where you arrive; wilds: next to the start portal).
var start := Vector3.ZERO
## XZ rectangle covered by the ground mesh (x, z, width, depth) and its vertex spacing (m).
var ground_rect := Rect2(-40, -40, 160, 160)
var ground_step := 1.0
## Water: a plane at water_level over ground_rect. Ground whose height is below water_level reads
## as water (rivers, ponds, lakes) — make ground_height() dip below it where water should be.
var has_water := false
var water_level := -0.35
## Optional XZ rectangles for the water planes (one plane each); empty = one plane over ground_rect.
## Use them when other dips below water_level (chasms, pits) must stay dry.
var water_rects: Array = []
## Floor tile groups (2 x 2 m kit pieces on walkable cells, like the town plaza):
## {"ids": ["env_floor_a", ...] (random per cell), "cells": Array of Vector2i, "tint": Color,
##  "tints": [Color, ...] (random per cell, optional), "cutout": false}
var tiles: Array = []
## Props: {"id", "pos": Vector3, "yaw": float, "scale": float, "cutout": bool (dithered away
## between camera and player — use for anything tall), "shadows": bool, "tint": Color (multiplies
## tint_* materials; WHITE = as modelled), "emission_color": Color (optional: replaces emissive
## colours), "vary": float (per-instance brightness jitter, default 0.08)}
var props: Array = []
## Explicit collision shapes (layer 1): {"type": "cylinder", "pos", "radius", "height"} or
## {"type": "box", "pos", "size": Vector3, "yaw"}. Cells covered by them are listed in `soft`.
var shapes: Array = []
## Cells whose collision comes from `shapes` (not from the merged per-cell boxes).
var soft := {}
## Point lights: {"pos", "color", "energy", "range", "flicker": bool}. Up to MAX_STATIC_LIGHTS are
## real lights; more become a moving pool around the player (like dungeon torches).
var lights: Array = []
## Fake light pools on the ground (additive decals): {"pos", "radius", "color"}.
var glows: Array = []
## Light shafts (god rays): {"pos": Vector3 ground point, "height": float, "width": float,
## "yaw": float, "tilt": float (degrees from vertical, leaning towards -yaw), "color": Color}.
var shafts: Array = []
## Flat ground details: [kind id, x, z, yaw, size x, size z, tint, lift] (add_detail).
var details: Array = []
## Grass tufts: [x, z, yaw, scale, tint, kind id] (add_grass).
var grass: Array = []
## {"kind": "portal"|"vendor"|"stash"|"waystone"|"chest"|"shrine", "pos", "yaw", ...}. Use the
## add_* helpers below; they also block cells, add collision and keep-outs.
var interactables: Array = []
## Monster groups (EnemyDB.populate_area): {"position", "radius", "kind": "pack"|"rare_pack"|"boss",
## "count", "enemy" (boss id, optional)}.
var spawn_groups: Array = []
## Hubs: where the "Return to <wilds>" portal opens when a town portal was used ({"pos", "yaw"}).
var portal_spot := {}
## Wilds: where the act boss waits (auto_spawn_groups adds the boss group there).
var boss_pos := Vector3.ZERO
## Minimap fully revealed on entry (hubs).
var reveal_all := false
## Exits towards the act's other zone: {other_zone: {"pos": Vector3, "dir": Vector2i}} (add_exit).
var exits: Dictionary = {}
## The act's dungeon entrance ({} = none): {"pos", "yaw", "model", "size": Vector2} (see
## add_dungeon_entrance; it is also listed in `interactables` with kind "dungeon").
var dungeon_entrance: Dictionary = {}
## Circles {"pos", "r"} that decoration keeps clear of (see is_clear / keep).
var keepouts: Array = []

# ------------------------------------------------------------------ regions (layouts)

## Regions of this zone's layout (use_layout): [{"id", "name", "level" (offset), "letter", "cells",
## "bbox", "centroid", "deepest", ...}] (empty for towns and layout-less zones).
var regions: Array = []
## Per cell: 1-based index into `regions` (0 = no region).
var region_map := PackedByteArray()
## Monster pools per region: {region id: {enemy id: weight}} (set_region_pool).
var region_pools: Dictionary = {}
## Look per region: {region id: theme overrides} on top of theme() (set_region_theme).
var region_themes: Dictionary = {}
## Where the player arrives in a region (debug menu, act travel): {region id: Vector3}.
var region_arrivals: Dictionary = {}
## The parsed layout (use_layout): "links", "exit", "dungeon", "size", "cell_m".
var layout_data: Dictionary = {}

var _region_index: Dictionary = {}   # id -> 1-based index
var _region_cells: Dictionary = {}   # id -> Array[Vector2i] (cache)
var _keep_hash: Dictionary = {}      # Vector2i bucket -> Array of keep-out indices
var _open_field := PackedFloat32Array()
const KEEP_BUCKET := 8.0

static var _noise: FastNoiseLite = null


# ------------------------------------------------------------------ entry point

## Build the layout. Returns the layout dictionary World._build_act() consumes.
func generate(p_act: String, p_zone: String, p_seed: int, p_level: int) -> Dictionary:
	act_id = p_act
	zone = p_zone if p_zone in ["hub", "wilds"] else "hub"
	level = maxi(1, p_level)
	seed_value = p_seed
	rng.seed = hash("%s|%s|%d" % [act_id, zone, seed_value])
	reveal_all = zone == "hub"
	details = []
	grass = []
	generate_zone()
	if grid == null:
		push_warning("WorldActGen(%s/%s): generate_zone() made no grid; using the default layout" % [act_id, zone])
		_reset_outputs()
		if zone == "hub":
			_default_hub()
		else:
			_default_wilds()
	finalize()
	return {
		"grid": grid, "start": start, "ground_rect": ground_rect, "ground_step": ground_step,
		"has_water": has_water, "water_level": water_level, "water_rects": water_rects, "tiles": tiles, "props": props,
		"shapes": shapes, "soft": soft, "lights": lights, "glows": glows, "shafts": shafts,
		"interactables": interactables, "spawn_groups": spawn_groups, "portal_spot": portal_spot,
		"boss_pos": boss_pos, "reveal_all": reveal_all, "act": act_id, "zone": zone,
		"exits": exits, "dungeon_entrance": dungeon_entrance,
		"regions": _region_outputs(), "region_map": region_map, "region_themes": region_themes,
		"region_arrivals": _arrival_outputs(), "links": layout_data.get("links", []),
		"details": details, "grass": grass, "ground_style": ground_style(),
	}


# ------------------------------------------------------------------ virtuals

## Fill the outputs for `zone`. The base version builds a plain but complete placeholder layout.
func generate_zone() -> void:
	if zone == "hub":
		_default_hub()
	else:
		_default_wilds()


## Look of the zone: keys overriding default_theme() (only the keys you change).
func theme() -> Dictionary:
	return {}


## Ground vertex colour at a world point (called for every ground vertex, 1.6-2 m apart).
func ground_color(x: float, z: float) -> Color:
	var n := noise2(x, z, 0.08, 3)
	var c := Color(0.3, 0.42, 0.18).lerp(Color(0.44, 0.46, 0.22), smoothstep(0.45, 0.8, n))
	if grid != null and not is_walkable_at(Vector3(x, 0, z)):
		c = c.lerp(Color(0.18, 0.24, 0.12), 0.5)
	return c


## Ground height (m) at a world point: decoration only. World flattens it to 0 on and around
## walkable cells (easing in over ~3.5 m), so hills / dunes only show off the walkable area. Ground
## below a water plane's level (inside water_rects) eases in over ~2 m past the walkable cells, so a
## bed that drops below the water there puts the shore ~1 m from the walkable edge (the cells make
## that edge a 2 m staircase: a water line drawn ~2 m out from the walkable edge reads smoother).
func ground_height(_x: float, _z: float) -> float:
	return 0.0


## Optional: add custom nodes (special shaders, animated bits, particles...) under `parent` after
## the World is built. `world` is the World being built (read-only use: world.grid, world.layout).
func decorate(_world: Node3D, _parent: Node3D) -> void:
	pass


## Border pieces the composer lines the walkable edges with ({} = none):
##   "segments": {prop id: weight} — straight pieces, modelled along the model's X axis (Blender
##               X), centred on the origin, front facing +Z; placed end to end along the edge
##   "length": float — a segment's length in metres (spacing between segment centres)
##   "posts": {prop id: weight} (optional) — placed at every `post_every`-th joint (and the ends)
##   "post_every": int (default 1)
##   "offset": float — metres outwards (into the non-walkable side) from the walkable edge (0.35)
##   "scale": Vector2(min, max) random uniform scale (default 1..1), "yaw_jitter": radians
##   "tint": Color, "shadows": bool (true), "cutout": bool (false)
##   "min_prop_height": float — an edge is left open when a prop at least this tall stands
##               within `prop_clearance` m of it (walls, trees, houses already mark it) (0.9)
##   "prop_clearance": float (1.3)
##   "skip_water": bool — no border where the ground beyond the edge dips under water (true)
func border_style() -> Dictionary:
	return {}


## Every theme key World._build_act() understands, with daylight defaults. theme() overrides them.
static func default_theme() -> Dictionary:
	return {
		# Sky (ProceduralSkyMaterial) — or a flat background colour when "sky" is false.
		"sky": true,
		"sky_top": Color(0.32, 0.46, 0.72),
		"sky_horizon": Color(0.86, 0.72, 0.56),
		"ground_horizon": Color(0.62, 0.55, 0.45),
		"ground_bottom": Color(0.2, 0.18, 0.15),
		"sky_energy": 1.0,
		"background": Color(0.05, 0.05, 0.07),
		# Ambient light: colour, energy and how much of it comes from the sky (0..1).
		"ambient": Color(0.75, 0.72, 0.68),
		"ambient_energy": 0.55,
		"ambient_sky": 0.55,
		# Sun / moon (DirectionalLight3D with shadows).
		"sun": Color(1.0, 0.86, 0.66),
		"sun_energy": 1.35,
		"sun_rot": Vector3(-42.0, 35.0, 0.0),
		"sun_shadows": true,
		# Depth fog (+ height fog) and optional volumetric fog
		# ({"density", "albedo": Color, "emission": Color, "emission_energy", "anisotropy",
		#   "length", "detail_spread", "gi_inject"}; empty = off).
		"fog": Color(0.78, 0.66, 0.52),
		"fog_density": 0.006,
		"fog_sky_affect": 0.25,
		"fog_height": 0.0,
		"fog_height_density": 0.0,
		"volumetric_fog": {},
		# Tonemap / adjustments / glow.
		"exposure": 1.0,
		"white": 6.0,
		"contrast": 1.06,
		"saturation": 1.0,
		"brightness": 1.0,
		"glow_intensity": 0.75,
		"glow_strength": 1.0,
		"glow_bloom": 0.02,
		"glow_hdr_threshold": 1.0,
		# Point lights placed with add_light() default to these; glow pools too.
		"light_color": Color(1.0, 0.72, 0.4),
		"light_energy": 1.4,
		"light_range": 8.0,
		"glow_color": Color(1.0, 0.7, 0.35),
		"glow_pool_strength": 0.3,
		# Water plane (only when has_water).
		"water_shallow": Color(0.22, 0.46, 0.5),
		"water_deep": Color(0.04, 0.16, 0.24),
		"water_foam": Color(0.85, 0.9, 0.88),
		"water_depth_scale": 1.4,
		# Ambient particles around the player: {"kind": "dust"|"motes"|"snow"|"ash"|"embers",
		# "color": Color, "amount": int, "size": float, "speed": float}; empty = none.
		"particles": {},
		# Light shafts (layout "shafts") strength.
		"shaft_strength": 1.0,
		# Daylit areas: softer hover highlight, weaker player light.
		"daylight": true,
	}


## default_theme() with this generator's overrides applied.
func full_theme() -> Dictionary:
	var th := default_theme()
	var over := theme()
	for k in over:
		th[k] = over[k]
	return th


# ------------------------------------------------------------------ grid helpers

func setup_grid(size: Vector2i) -> void:
	grid = WorldGrid.new()
	grid.setup(size)
	for j in size.y:
		for i in size.x:
			var c := Vector2i(i, j)
			grid.set_void(c)
			# Open land outside the walkable area hides nothing.
			grid.set_opaque(c, false)


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * TILE, 0.0, (c.y + 0.5) * TILE)


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.z / TILE))


## World position of fractional cell coordinates (corner based: (0, 0) = the grid's min corner).
func at(i: float, j: float) -> Vector3:
	return Vector3(i * TILE, 0.0, j * TILE)


func in_bounds(c: Vector2i) -> bool:
	return grid != null and grid.in_bounds(c)


func is_walkable_cell(c: Vector2i) -> bool:
	return grid != null and grid.is_walkable_cell(c)


func is_walkable_at(pos: Vector3) -> bool:
	return is_walkable_cell(world_to_cell(pos))


func is_floor_at(pos: Vector3) -> bool:
	return grid != null and grid.is_floor(world_to_cell(pos))


## Make a cell walkable floor.
func carve(c: Vector2i) -> void:
	if in_bounds(c):
		grid.set_floor(c, true)


func carve_rect(r: Rect2i) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			carve(Vector2i(i, j))


## Every cell whose centre lies within `radius` metres of `center`.
func carve_disc(center: Vector3, radius: float) -> void:
	for c in cells_in_disc(center, radius):
		carve(c)


## A walkable band `width` metres wide along the polyline `points` (Vector3s).
func carve_path(points: Array, width: float) -> void:
	for k in range(points.size() - 1):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 0.8)))
		for s in n + 1:
			carve_disc(a.lerp(b, float(s) / n), width * 0.5)


## Cells whose centre lies within radius of center.
func cells_in_disc(center: Vector3, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null:
		return out
	var c0 := world_to_cell(center)
	var r := int(ceil(radius / TILE)) + 1
	for j in range(c0.y - r, c0.y + r + 1):
		for i in range(c0.x - r, c0.x + r + 1):
			var c := Vector2i(i, j)
			if in_bounds(c) and cell_center(c).distance_to(Vector3(center.x, 0, center.z)) <= radius:
				out.append(c)
	return out


## Make cells non-walkable (optionally blocking line of sight). `is_soft`: collision comes from an
## explicit shape you add yourself (else a merged box covers the cell).
func block_cell(c: Vector2i, opaque: bool = false, is_soft: bool = false) -> void:
	if not in_bounds(c):
		return
	grid.set_walkable(c, false)
	if opaque:
		grid.set_opaque(c, true)
	if is_soft:
		soft[c] = true


func block_rect(r: Rect2i, opaque: bool = false, is_soft: bool = false) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			block_cell(Vector2i(i, j), opaque, is_soft)


# ------------------------------------------------------------------ props & obstacles

## Decorative prop (no collision). opts: cutout, shadows, tint, emission_color, vary,
## sway (wind sway amount for foliage, ~0.3-1.5) + sway_base (MODEL-space height in m where the
## swaying starts). Props are batched per (id, cutout, shadows, tint, emission, sway, sway_base):
## keep those constant per model, or every distinct value becomes its own MultiMesh.
func add_prop(id: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "pos": pos, "yaw": yaw, "scale": scale,
		"cutout": bool(opts.get("cutout", false)), "shadows": bool(opts.get("shadows", true)),
		"tint": opts.get("tint", Color.WHITE), "vary": float(opts.get("vary", 0.08))}
	if opts.has("emission_color"):
		d["emission_color"] = opts["emission_color"]
	if float(opts.get("sway", 0.0)) > 0.0:
		d["sway"] = float(opts["sway"])
		d["sway_base"] = float(opts.get("sway_base", 1.0))
	props.append(d)
	return d


## A round solid prop (tree, pillar, statue, rock): prop + collision cylinder + blocked cells +
## keep-out. radius = collision radius (m). Cutout and shadows default on.
func add_obstacle(id: String, pos: Vector3, yaw: float, scale: float, radius: float, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	if not o.has("cutout"):
		o["cutout"] = true
	var d := add_prop(id, pos, yaw, scale, o)
	shapes.append({"type": "cylinder", "pos": Vector3(pos.x, 0, pos.z), "radius": radius, "height": float(opts.get("height", 3.0))})
	var cells := cells_in_disc(pos, radius + 0.35)
	var own := world_to_cell(pos)
	if not own in cells:
		cells.append(own)
	for c in cells:
		if in_bounds(c) and grid.is_walkable_cell(c):
			block_cell(c, bool(opts.get("opaque", false)), true)
	keep(pos, radius + 0.3)
	return d


## A rectangular solid prop: footprint `size` (x, z in metres, before yaw) centred on pos.
## Collision box + blocked cells + keep-out. opts: opaque (blocks line of sight), height,
## cutout (default true), shadows (default true), tint...
func add_block(id: String, pos: Vector3, yaw: float, size: Vector2, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	if not o.has("cutout"):
		o["cutout"] = true
	var d := {}
	if id != "":
		d = add_prop(id, pos, yaw, float(opts.get("scale", 1.0)), o)
	var h := float(opts.get("height", 3.0))
	shapes.append({"type": "box", "pos": Vector3(pos.x, 0, pos.z), "size": Vector3(size.x, h, size.y), "yaw": yaw})
	var basis := Basis(Vector3.UP, yaw)
	var ax := basis * Vector3(1, 0, 0)
	var az := basis * Vector3(0, 0, 1)
	var reach := size.length() * 0.5 + TILE
	for c in cells_in_disc(pos, reach):
		var q := cell_center(c) - Vector3(pos.x, 0, pos.z)
		# Block cells whose centre is inside the footprint grown by 0.4 m.
		if absf(q.dot(ax)) <= size.x * 0.5 + 0.4 and absf(q.dot(az)) <= size.y * 0.5 + 0.4:
			block_cell(c, bool(opts.get("opaque", false)), true)
	var own := world_to_cell(pos)
	block_cell(own, bool(opts.get("opaque", false)), true)
	keep(pos, size.length() * 0.5)
	return d


## A building: add_block with opaque = true (blocks line of sight), cutout and shadows on.
func add_building(id: String, pos: Vector3, yaw: float, size: Vector2, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	o["opaque"] = bool(opts.get("opaque", true))
	return add_block(id, pos, yaw, size, o)


## Keep-out circle for later decoration.
func keep(pos: Vector3, r: float) -> void:
	keepouts.append({"pos": Vector3(pos.x, 0, pos.z), "r": r})
	_hash_keep(keepouts.size() - 1)


## True if a circle (pos, r) stays clear of every keep-out (spatial hash: cheap).
func is_clear(pos: Vector3, r: float) -> bool:
	var p := Vector3(pos.x, 0, pos.z)
	var lo := Vector2i(floori((p.x - r) / KEEP_BUCKET), floori((p.z - r) / KEEP_BUCKET))
	var hi := Vector2i(floori((p.x + r) / KEEP_BUCKET), floori((p.z + r) / KEEP_BUCKET))
	for bj in range(lo.y, hi.y + 1):
		for bi in range(lo.x, hi.x + 1):
			for idx in _keep_hash.get(Vector2i(bi, bj), []):
				var k: Dictionary = keepouts[idx]
				if (k["pos"] as Vector3).distance_to(p) < float(k["r"]) + r:
					return false
	return true


func _hash_keep(idx: int) -> void:
	var k: Dictionary = keepouts[idx]
	var p: Vector3 = k["pos"]
	var r := float(k["r"])
	for bj in range(floori((p.z - r) / KEEP_BUCKET), floori((p.z + r) / KEEP_BUCKET) + 1):
		for bi in range(floori((p.x - r) / KEEP_BUCKET), floori((p.x + r) / KEEP_BUCKET) + 1):
			var key := Vector2i(bi, bj)
			if not _keep_hash.has(key):
				_keep_hash[key] = []
			(_keep_hash[key] as Array).append(idx)


## Scatter up to `count` props with ids picked from `ids` (Array of ids, or {id: weight}) inside
## rect (XZ). opts:
##   "on": "void" (off the walkable area, default) | "walkable" | "any"
##   "min_dist": spacing between the new props (m, default 2.0)
##   "margin": distance kept from walkable cells when on void (m, default 0.0)
##   "scale": Vector2(min, max) (default 0.85..1.2), "keep": keep-out radius per prop (default 0)
##   "collide": collision radius (m) -> add_obstacle instead of add_prop (walkable placements)
##   "filter": Callable(pos: Vector3) -> bool, extra acceptance test
##   "region": region id — only cells of that region (with "on": "walkable")
##   "cutout", "shadows", "tint", "sway", "sway_base", "tries" (default count * 12)
## Returns the placed prop dictionaries.
func scatter(ids: Variant, count: int, rect: Rect2, opts: Dictionary = {}) -> Array:
	var out: Array = []
	var placed := {}   # bucket -> Array[Vector3]
	var on := String(opts.get("on", "void"))
	var min_dist := float(opts.get("min_dist", 2.0))
	var margin := float(opts.get("margin", 0.0))
	var sc_range: Vector2 = opts.get("scale", Vector2(0.85, 1.2))
	var keep_r := float(opts.get("keep", 0.0))
	var collide := float(opts.get("collide", 0.0))
	var filt: Callable = opts.get("filter", Callable())
	var in_region := String(opts.get("region", ""))
	var tries := int(opts.get("tries", count * 12))
	var bsz := maxf(min_dist, 1.0)
	for t in tries:
		if out.size() >= count:
			break
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
		var c := world_to_cell(p)
		var walk := is_walkable_cell(c)
		if on == "void" and (walk or (margin > 0.0 and walk_distance(p) < margin)):
			continue
		if on == "walkable" and not walk:
			continue
		if in_region != "" and region_of_cell(c) != in_region:
			continue
		if filt.is_valid() and not bool(filt.call(p)):
			continue
		var ok := true
		var bk := Vector2i(floori(p.x / bsz), floori(p.z / bsz))
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for q in placed.get(bk + Vector2i(di, dj), []):
					if (q as Vector3).distance_squared_to(p) < min_dist * min_dist:
						ok = false
		if not ok or not is_clear(p, maxf(keep_r, collide)):
			continue
		if not placed.has(bk):
			placed[bk] = []
		(placed[bk] as Array).append(p)
		var id := pick(ids)
		var sc := rng.randf_range(sc_range.x, sc_range.y)
		var o := {"cutout": opts.get("cutout", collide > 0.0), "shadows": opts.get("shadows", true), "tint": opts.get("tint", Color.WHITE),
			"sway": opts.get("sway", 0.0), "sway_base": opts.get("sway_base", 1.0)}
		var d: Dictionary
		if collide > 0.0 and walk:
			d = add_obstacle(id, p, rng.randf() * TAU, sc, collide * sc, o)
		else:
			d = add_prop(id, p, rng.randf() * TAU, sc, o)
			if keep_r > 0.0:
				keep(p, keep_r)
		out.append(d)
	return out


# ------------------------------------------------------------------ ground detail (WorldGroundFx)

## The ground shader style: "" (plain vertex colours), "forest", "desert" or "gothic" (the act's
## procedural ground texture, see WorldGroundFx). Default: the act id when it is one of those.
func ground_style() -> String:
	return act_id if act_id in ["forest", "desert", "gothic"] else ""


## Material weights of the ground at a point, 0..1 each, for the style's layers. Called for every
## ground vertex right after ground_color(x, z) (keep it cheap, reuse what ground_color sampled):
##   forest: r = gravel, g = mud / puddles, b = leaf litter, a = moss and needles
##   desert: r = pebbles, g = sandstone slabs, b = sand bricks, a = dried cracked mud (wet near 1)
##   gothic: r = wet mud, g = puddles, b = dead leaves, a = soot / grime
func ground_detail(_x: float, _z: float) -> Color:
	return Color(0, 0, 0, 0)


## A flat ground detail (WorldGroundFx.DETAIL_KINDS: leaf, leaves, twigs, needles, straw, pebbles,
## bones, splinters, blood, puddle, glass, bricks, cracks, sand, moss, stain). It lies on the ground
## or on paving; size = metres (x along the yaw); tint = its colour (alpha = opacity); lift raises
## it (a step, a quay).
func add_detail(kind: String, pos: Vector3, yaw: float = 0.0, size: Vector2 = Vector2.ONE, tint: Color = Color.WHITE, lift: float = 0.0) -> void:
	details.append([int(WorldGroundFx.DETAIL_KINDS.get(kind, 0)), pos.x, pos.z, yaw, size.x, size.y, tint, lift])


## A grass tuft: kind "grass" (~0.4 m) or "reeds" (~1 m), times scale, in its colour. It sways
## and bends away from the player and monsters walking through it.
func add_grass(pos: Vector3, scale: float = 1.0, tint: Color = Color(0.3, 0.45, 0.12), kind: String = "grass") -> void:
	grass.append([pos.x, pos.z, rng.randf() * TAU, scale, tint, int(WorldGroundFx.GRASS_KINDS.get(kind, 0))])


## Scatter `count` details (a kind, an Array of kinds or {kind: weight}) over rect. opts: "on"
## ("walkable" default, "void", "any"), "region", "filter" (Callable(Vector3) -> bool), "size"
## (Vector2 range of the side, m; default 0.6..1.2), "stretch" (x side × 1..this), "tints" (Array)
## or "tint", "min_dist", "tries", "clear" (skip spots too close to props / keep-outs: radius).
## Returns how many were placed.
func scatter_details(kinds: Variant, count: int, rect: Rect2, opts: Dictionary = {}) -> int:
	var on := String(opts.get("on", "walkable"))
	var in_region := String(opts.get("region", ""))
	var filt: Callable = opts.get("filter", Callable())
	var size: Vector2 = opts.get("size", Vector2(0.6, 1.2))
	var stretch := float(opts.get("stretch", 1.0))
	var tints: Array = opts.get("tints", [opts.get("tint", Color.WHITE)])
	var min_dist := float(opts.get("min_dist", 0.0))
	var clear_r := float(opts.get("clear", 0.0))
	var tries := int(opts.get("tries", count * 4))
	var placed := {}
	var bsz := maxf(min_dist, 1.0)
	var n := 0
	for t in tries:
		if n >= count:
			break
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
		var c := world_to_cell(p)
		if on != "any":
			var walk := is_walkable_cell(c) or soft.has(c)
			if (on == "walkable") != walk:
				continue
		if in_region != "" and region_of_cell(c) != in_region:
			continue
		if filt.is_valid() and not bool(filt.call(p)):
			continue
		if clear_r > 0.0 and not is_clear(p, clear_r):
			continue
		if min_dist > 0.0:
			var bk := Vector2i(floori(p.x / bsz), floori(p.z / bsz))
			var ok := true
			for dj in range(-1, 2):
				for di in range(-1, 2):
					for q in placed.get(bk + Vector2i(di, dj), []):
						if (q as Vector3).distance_squared_to(p) < min_dist * min_dist:
							ok = false
			if not ok:
				continue
			if not placed.has(bk):
				placed[bk] = []
			(placed[bk] as Array).append(p)
		var side := rng.randf_range(size.x, size.y)
		add_detail(pick(kinds) if not kinds is String else String(kinds), p, rng.randf() * TAU,
			Vector2(side * rng.randf_range(1.0, stretch), side), tints[rng.randi() % tints.size()])
		n += 1
	return n


## Grass patches: `patches` clusters over rect, each `per_patch` tufts (± 40%) in a disc (opts
## "radius": Vector2 range, m, default 1.2..3). opts: "on" ("walkable" default, "void", "any" —
## checked per tuft), "region", "filter" (per tuft), "scale" (Vector2 range), "tints" (Array; one
## per patch, varied per tuft), "kind" ("grass" / "reeds"), "clear" (keep clear of props / keep-outs
## by this radius). Returns the tufts placed.
func scatter_grass(patches: int, per_patch: int, rect: Rect2, opts: Dictionary = {}) -> int:
	var on := String(opts.get("on", "walkable"))
	var in_region := String(opts.get("region", ""))
	var filt: Callable = opts.get("filter", Callable())
	var rad: Vector2 = opts.get("radius", Vector2(1.2, 3.0))
	var sc: Vector2 = opts.get("scale", Vector2(0.8, 1.2))
	var tints: Array = opts.get("tints", [Color(0.3, 0.45, 0.12)])
	var kind := String(opts.get("kind", "grass"))
	var clear_r := float(opts.get("clear", 0.35))
	var n := 0
	var done := 0
	for pt in patches * 3:
		if done >= patches:
			break
		var centre := Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
		var cc := world_to_cell(centre)
		if in_region != "" and region_of_cell(cc) != in_region:
			continue
		if on == "walkable" and not (is_walkable_cell(cc) or soft.has(cc)):
			continue
		var r := rng.randf_range(rad.x, rad.y)
		var base: Color = tints[rng.randi() % tints.size()]
		var m := int(per_patch * rng.randf_range(0.6, 1.4))
		var got := 0
		for k in m * 2:
			if got >= m:
				break
			var a := rng.randf() * TAU
			# denser in the middle of the patch
			var d := r * sqrt(rng.randf()) * (0.55 + 0.45 * rng.randf())
			var p := centre + Vector3(cos(a) * d, 0.0, sin(a) * d)
			var c := world_to_cell(p)
			if on != "any":
				var walk := is_walkable_cell(c) or soft.has(c)
				if (on == "walkable") != walk:
					continue
			if in_region != "" and region_of_cell(c) != in_region:
				continue
			if filt.is_valid() and not bool(filt.call(p)):
				continue
			if clear_r > 0.0 and not is_clear(p, clear_r):
				continue
			var v := rng.randf_range(0.85, 1.12)
			var tint := Color(base.r * v * rng.randf_range(0.94, 1.06), base.g * v, base.b * v * rng.randf_range(0.9, 1.1))
			add_grass(p, rng.randf_range(sc.x, sc.y) * (1.0 - 0.35 * d / maxf(r, 0.01)), tint, kind)
			got += 1
		n += got
		if got > 0:
			done += 1
	return n


## Random id from an Array of ids or a {id: weight} Dictionary.
func pick(ids: Variant) -> String:
	if ids is Dictionary:
		var total := 0.0
		for k in ids:
			total += float(ids[k])
		var r := rng.randf() * total
		for k in ids:
			r -= float(ids[k])
			if r <= 0.0:
				return String(k)
		return String((ids as Dictionary).keys()[0])
	var arr: Array = ids
	return String(arr[rng.randi_range(0, arr.size() - 1)])


## Floor tiles (kit pieces) on these cells. ids: e.g. ["env_floor_a", "env_floor_b"].
func add_tiles(ids: Array, cells: Array, tint: Color, tints: Array = []) -> void:
	tiles.append({"ids": ids, "cells": cells, "tint": tint, "tints": tints})


# ------------------------------------------------------------------ lights

func add_light(pos: Vector3, color: Color, energy: float = 1.4, light_range: float = 8.0, flicker: bool = true) -> void:
	lights.append({"pos": pos, "color": color, "energy": energy, "range": light_range, "flicker": flicker})


func add_glow(pos: Vector3, radius: float, color: Color) -> void:
	glows.append({"pos": pos, "radius": radius, "color": color})


func add_shaft(pos: Vector3, height: float, width: float, color: Color, yaw: float = 0.0, tilt: float = 18.0) -> void:
	shafts.append({"pos": pos, "height": height, "width": width, "color": color, "yaw": yaw, "tilt": tilt})


# ------------------------------------------------------------------ exits & dungeon

## This zone's way to the act's other zone ("hub" / "wilds"): pos = centre of a cell on the grid
## edge, dir = outward direction (Vector2i(0, -1) = north). Keep the path from the start to it
## walkable and at least 3 cells wide.
func add_exit(to_zone: String, pos: Vector3, dir: Vector2i) -> void:
	exits[to_zone] = {"pos": Vector3(pos.x, 0.0, pos.z), "dir": dir}


## The act's dungeon entrance: a solid prop (model id, e.g. a tomb or a crypt) the player clicks
## to enter the dungeon (screen fade). It is drawn with cut-out materials (see-through between the
## camera and the player). `yaw` may turn it any way (not only the layout's door "dir": the camera
## looks north-west, so a door facing north or west only shows its back). The player comes back out
## 2 m in front of it (+Z local), or at set_region_arrival("dungeon_exit", pos) when set.
## size = collision footprint (x, z before yaw).
func add_dungeon_entrance(pos: Vector3, yaw: float, model: String, size: Vector2 = Vector2(4.0, 4.0)) -> Dictionary:
	var d := {"kind": "dungeon", "pos": Vector3(pos.x, 0.0, pos.z), "yaw": yaw, "model": model, "size": size}
	interactables.append(d)
	dungeon_entrance = {"pos": d["pos"], "yaw": yaw, "model": model, "size": size}
	shapes.append({"type": "box", "pos": d["pos"], "size": Vector3(size.x, 3.0, size.y), "yaw": yaw})
	var basis := Basis(Vector3.UP, yaw)
	for c in cells_in_disc(pos, size.length() * 0.5 + TILE):
		var q: Vector3 = basis.inverse() * (cell_center(c) - Vector3(pos.x, 0.0, pos.z))
		if absf(q.x) <= size.x * 0.5 + 0.3 and absf(q.z) <= size.y * 0.5 + 0.3:
			block_cell(c, false, true)
	block_cell(world_to_cell(pos), false, true)
	keep(pos, size.length() * 0.5 + 0.5)
	# Keep the approach in front of the door clear.
	keep(Vector3(pos.x, 0.0, pos.z) + basis * Vector3(0.0, 0.0, size.y * 0.5 + 1.5), 1.7)
	return d


# ------------------------------------------------------------------ interactables

## Portal to another zone of this act ("hub"/"wilds"), to another act (to_act), or to Emberfall
## (zone "town"). Stands on walkable ground (no collision); keeps decoration away.
func add_portal_to(target_zone: String, pos: Vector3, yaw: float = 0.0, to_act: String = "") -> Dictionary:
	var d := {"kind": "portal", "pos": pos, "yaw": yaw, "act": to_act if to_act != "" else act_id, "zone": target_zone}
	interactables.append(d)
	keep(pos, 2.4)
	return d


## The merchant NPC (char_merchant). Put a stall / awning prop next to it yourself.
func add_vendor(pos: Vector3, yaw: float = 0.0) -> Dictionary:
	var d := {"kind": "vendor", "pos": pos, "yaw": yaw}
	interactables.append(d)
	_solid_spot(pos, 0.45, 0.8)
	return d


func add_stash(pos: Vector3, yaw: float = 0.0) -> Dictionary:
	var d := {"kind": "stash", "pos": pos, "yaw": yaw}
	interactables.append(d)
	shapes.append({"type": "box", "pos": pos, "size": Vector3(1.0, 1.4, 1.6), "yaw": yaw + PI * 0.5})
	_block_spot(pos, 0.8)
	keep(pos, 1.0)
	return d


## The act waystone: opens the Act Explorer. model: a prop id with its own look (e.g. an obelisk or
## a rune stone), "" = env_waypoint. size: its collision footprint (x, z).
func add_waystone(pos: Vector3, yaw: float = 0.0, model: String = "", size: Vector2 = Vector2(4.2, 4.2)) -> Dictionary:
	var d := {"kind": "waystone", "pos": pos, "yaw": yaw, "model": model, "size": size}
	interactables.append(d)
	shapes.append({"type": "box", "pos": pos, "size": Vector3(size.x, 3.0, size.y), "yaw": yaw})
	var basis := Basis(Vector3.UP, yaw)
	for c in cells_in_disc(pos, size.length() * 0.5 + TILE):
		var q := basis.inverse() * (cell_center(c) - Vector3(pos.x, 0, pos.z))
		if absf(q.x) <= size.x * 0.5 + 0.3 and absf(q.z) <= size.y * 0.5 + 0.3:
			block_cell(c, false, true)
	block_cell(world_to_cell(pos), false, true)
	keep(pos, size.length() * 0.5 + 0.5)
	return d


## tier 0 chest, 1 ornate, 2 treasure hoard.
func add_chest(pos: Vector3, yaw: float = 0.0, tier: int = 0) -> Dictionary:
	var d := {"kind": "chest", "pos": pos, "yaw": yaw, "tier": tier}
	interactables.append(d)
	shapes.append({"type": "box", "pos": pos, "size": Vector3(1.1, 1.0, 0.8), "yaw": yaw})
	_block_spot(pos, 0.6)
	keep(pos, 1.2)
	return d


## Shrine kinds: "fury", "swiftness", "fortitude", "arcana" ("" = random).
func add_shrine(pos: Vector3, yaw: float = 0.0, kind: String = "") -> Dictionary:
	var k := kind if kind != "" else pick(["fury", "swiftness", "fortitude", "arcana"])
	var d := {"kind": "shrine", "pos": pos, "yaw": yaw, "shrine": k}
	interactables.append(d)
	shapes.append({"type": "cylinder", "pos": pos, "radius": 0.65, "height": 3.0})
	_block_spot(pos, 0.7)
	keep(pos, 1.3)
	return d


func _solid_spot(pos: Vector3, radius: float, keep_r: float) -> void:
	shapes.append({"type": "cylinder", "pos": pos, "radius": radius, "height": 2.0})
	_block_spot(pos, radius)
	keep(pos, keep_r)


func _block_spot(pos: Vector3, radius: float) -> void:
	block_cell(world_to_cell(pos), false, true)
	for c in cells_in_disc(pos, radius):
		block_cell(c, false, true)


# ------------------------------------------------------------------ monsters

## One monster group. In layouts the group remembers its region (its monster pool and level
## offset come from there).
func add_spawn_group(pos: Vector3, kind: String = "pack", count: int = 4, radius: float = 3.0, enemy: String = "") -> void:
	var g := {"position": Vector3(pos.x, 0, pos.z), "radius": radius, "kind": kind, "count": count}
	if enemy != "":
		g["enemy"] = enemy
	var rid := region_at(pos)
	if rid != "":
		g["region"] = rid
	spawn_groups.append(g)


## Spread `packs` normal packs (3-6 monsters) and `rares` rare packs over the reachable walkable
## area: at least min_start metres from the start, `spacing` metres apart, in open spots, clear of
## the boss arena; plus the act boss at boss_pos. Call after the layout is final (it floods from
## the start).
func auto_spawn_groups(packs: int, rares: int, min_start: float = 16.0, spacing: float = 11.0) -> void:
	grid.rebuild_astar()
	var reach := grid.flood_walkable(grid.nearest_walkable_cell(world_to_cell(start)))
	var cands: Array[Vector3] = []
	for j in grid.size.y:
		for i in grid.size.x:
			var c := Vector2i(i, j)
			if reach[grid.idx(c)] == 0:
				continue
			var p := cell_center(c)
			if p.distance_to(start) < min_start or p.distance_to(boss_pos) < 12.0:
				continue
			if _open_count(c, 2) < 18:
				continue
			cands.append(p)
	# Shuffle deterministically.
	for k in range(cands.size() - 1, 0, -1):
		var r := rng.randi_range(0, k)
		var tmp := cands[k]
		cands[k] = cands[r]
		cands[r] = tmp
	var chosen: Array[Vector3] = []
	for p in cands:
		if chosen.size() >= packs + rares:
			break
		var ok := true
		for q in chosen:
			if q.distance_to(p) < spacing:
				ok = false
				break
		if ok:
			chosen.append(p)
	for n in chosen.size():
		if n < rares:
			add_spawn_group(chosen[n], "rare_pack", rng.randi_range(4, 5), 3.5)
		else:
			add_spawn_group(chosen[n], "pack", rng.randi_range(3, 6), 3.0)
	var boss_id := String(ActDefs.get_act(act_id).get("zone_boss", "")) if ActDefs.has_act(act_id) else ""
	add_spawn_group(boss_pos, "boss", 1, 3.0, boss_id)


func _open_count(c: Vector2i, r: int) -> int:
	var n := 0
	for j in range(c.y - r, c.y + r + 1):
		for i in range(c.x - r, c.x + r + 1):
			if grid.is_walkable_cell(Vector2i(i, j)):
				n += 1
	return n


# ------------------------------------------------------------------ layouts & regions

## Read the act's layout (data/layouts/act_<act>.json): sets up the grid (every region cell
## walkable, the rest open void), the regions and the region map, the exit towards the town
## ("hub", on the grid edge the layout names), the start (in the outskirts, near that exit), the
## default region arrivals, and a ground rect around it all. Returns the parsed layout.
func use_layout(act: String = "") -> Dictionary:
	var a := act if act != "" else act_id
	layout_data = ActDefs.layout(a)
	if layout_data.is_empty():
		push_warning("WorldActGen(%s): no layout; using a plain one" % a)
		return {}
	var sz: Array = layout_data["size"]
	var size := Vector2i(int(sz[0]), int(sz[1]))
	setup_grid(size)
	regions = []
	_region_index = {}
	_region_cells = {}
	var by_letter := {}
	for r in layout_data.get("regions", []):
		regions.append((r as Dictionary).duplicate(true))
		_region_index[String(r["id"])] = regions.size()
		by_letter[String(r["letter"])] = regions.size()
	region_map = PackedByteArray()
	region_map.resize(size.x * size.y)
	var rows: Array = layout_data["rows"]
	for j in mini(rows.size(), size.y):
		var row := String(rows[j])
		for i in mini(row.length(), size.x):
			var ch := row[i]
			if ch == ".":
				continue
			var idx := int(by_letter.get(ch, 0))
			if idx == 0:
				continue
			var c := Vector2i(i, j)
			grid.set_floor(c, true)
			region_map[j * size.x + i] = idx
	ground_rect = Rect2(-40.0, -40.0, size.x * TILE + 80.0, size.y * TILE + 80.0)
	ground_step = 2.0
	# The exit towards the town.
	var ex: Dictionary = layout_data.get("exit", {})
	var ecell := Vector2i(roundi(float(ex["cell"][0])), roundi(float(ex["cell"][1])))
	var edir := Vector2i(int(ex["dir"][0]), int(ex["dir"][1]))
	var epos := cell_center(ecell)
	add_exit("hub", epos, edir)
	# Start: a few metres inside from the exit.
	start = epos - Vector3(edir.x, 0, edir.y) * 10.0
	if not is_walkable_at(start):
		var nc := grid.nearest_walkable_cell(world_to_cell(start))
		if nc.x >= 0:
			start = cell_center(nc)
	keep(start, 3.0)
	return layout_data


## Region ids of this zone's layout, in layout order ("outskirts" first).
func region_ids() -> Array:
	var out: Array = []
	for r in regions:
		out.append(String(r["id"]))
	return out


func get_region(id: String) -> Dictionary:
	var idx := int(_region_index.get(id, 0))
	return regions[idx - 1] if idx > 0 else {}


## The region of a cell ("" = none).
func region_of_cell(c: Vector2i) -> String:
	if regions.is_empty() or grid == null or not grid.in_bounds(c):
		return ""
	var v := int(region_map[c.y * grid.size.x + c.x])
	return String(regions[v - 1]["id"]) if v > 0 else ""


## The region at a world position ("" = none).
func region_at(pos: Vector3) -> String:
	return region_of_cell(world_to_cell(pos))


func is_region(c: Vector2i, id: String) -> bool:
	return region_of_cell(c) == id


## Every cell of a region (walkable when the layout was read; cached).
func region_cells(id: String) -> Array:
	if _region_cells.has(id):
		return _region_cells[id]
	# Every region's cells in one pass over the map (same order as a per-region scan).
	var lists: Array = []
	for r in regions:
		lists.append([])
	var w := grid.size.x if grid != null else 0
	for k in region_map.size():
		var v := region_map[k]
		if v > 0 and v <= lists.size():
			(lists[v - 1] as Array).append(Vector2i(k % w, k / w))
	for n in regions.size():
		_region_cells[String(regions[n]["id"])] = lists[n]
	if not _region_cells.has(id):
		_region_cells[id] = []
	return _region_cells[id]


## A region's bounding box in metres.
func region_rect(id: String) -> Rect2:
	var r := get_region(id)
	if r.is_empty():
		return Rect2()
	var bb: Array = r["bbox"]
	return Rect2(float(bb[0]) * TILE, float(bb[1]) * TILE, (float(bb[2]) - float(bb[0]) + 1.0) * TILE, (float(bb[3]) - float(bb[1]) + 1.0) * TILE)


## The most open spot of a region (the cell farthest from its edges).
func region_center(id: String) -> Vector3:
	var r := get_region(id)
	if r.is_empty():
		return start
	return cell_center(Vector2i(int(r["deepest"][0]), int(r["deepest"][1])))


## Level offset of a region (0 = the outskirts' level).
func region_level(id: String) -> int:
	return int(get_region(id).get("level", 0))


## The paths out of a region: [{"to": other region id, "pos": Vector3 (the border between them),
## "width": metres}].
func region_links(id: String) -> Array:
	var out: Array = []
	for l in layout_data.get("links", []):
		var a := String(l["a"])
		var b := String(l["b"])
		if a != id and b != id:
			continue
		var at_: Array = l["at"]
		out.append({"to": b if a == id else a, "pos": Vector3((float(at_[0]) + 0.5) * TILE, 0.0, (float(at_[1]) + 0.5) * TILE),
			"width": float(l.get("width_cells", 6)) * TILE})
	return out


## Cells of a region next to non-walkable ground (its rim): where edge decoration goes.
func region_edge_cells(id: String) -> Array:
	var out: Array = []
	for c in region_cells(id):
		var cc: Vector2i = c
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not grid.is_floor(cc + d):
				out.append(cc)
				break
	return out


## Metres from a cell to the nearest non-walkable cell (how open the ground is). Computed once
## (call after the layout, before placing obstacles — or call refresh_open_field()).
func region_open(c: Vector2i) -> float:
	if _open_field.is_empty():
		refresh_open_field()
	if grid == null or not grid.in_bounds(c):
		return 0.0
	return _open_field[c.y * grid.size.x + c.x]


func refresh_open_field() -> void:
	_open_field = distance_to_blocked(grid)


## The dungeon door from the layout: {"pos": Vector3 (a cell on the region's edge next to the
## dungeon box), "dir": Vector2i (towards the dungeon), "region"} or {}.
func dungeon_door() -> Dictionary:
	var d: Dictionary = layout_data.get("dungeon", {})
	if d.is_empty():
		return {}
	return {"pos": cell_center(Vector2i(int(d["cell"][0]), int(d["cell"][1]))), "dir": Vector2i(int(d["dir"][0]), int(d["dir"][1])),
		"region": String(d.get("region", ""))}


## Monster pool of a region: {enemy id: weight} (ids from EnemyDB; act monsters or any other).
func set_region_pool(id: String, pool: Dictionary) -> void:
	region_pools[id] = pool


## Theme overrides of a region (on top of theme()); the World blends to them on entry.
func set_region_theme(id: String, overrides: Dictionary) -> void:
	region_themes[id] = overrides


## Where the player arrives in a region (default: just inside its entrance from the town side).
## id "dungeon_exit": where the player comes back out of the act dungeon (default: in front of the
## entrance).
func set_region_arrival(id: String, pos: Vector3) -> void:
	region_arrivals[id] = Vector3(pos.x, 0.0, pos.z)


## Scatter props over a region's walkable cells, `per_100m2` of them per 100 m2 (a density), with
## the scatter() options (min_dist, scale, collide, filter, keep, tint...).
func scatter_region(id: String, ids: Variant, per_100m2: float, opts: Dictionary = {}) -> Array:
	var cells := region_cells(id)
	var count := int(round(cells.size() * TILE * TILE / 100.0 * per_100m2))
	if count <= 0:
		return []
	var o := opts.duplicate()
	o["on"] = "walkable"
	o["region"] = id
	if not o.has("tries"):
		o["tries"] = count * 14
	return scatter(ids, count, region_rect(id), o)


## Spread monster packs over a region: `packs` normal packs (3-6 monsters) + `rares` rare packs, in
## open spots at least `spacing` m apart, `clear` m away from the region's entrances and from
## keep-outs of radius > 3 m (landmarks), none near the start. Uses the region's pool.
func auto_spawn_region(id: String, packs: int, rares: int, spacing: float = 16.0, clear: float = 14.0) -> int:
	var cands: Array[Vector3] = []
	var links := region_links(id)
	for c in region_cells(id):
		var cc: Vector2i = c
		if not grid.is_walkable_cell(cc) or region_open(cc) < 5.0:
			continue
		var p := cell_center(cc)
		if p.distance_to(start) < 26.0:
			continue
		var near_link := false
		for l in links:
			if p.distance_to(l["pos"]) < clear:
				near_link = true
				break
		if near_link:
			continue
		cands.append(p)
	for k in range(cands.size() - 1, 0, -1):
		var r := rng.randi_range(0, k)
		var tmp := cands[k]
		cands[k] = cands[r]
		cands[r] = tmp
	var chosen := {}
	var placed := 0
	for p in cands:
		if placed >= packs + rares:
			break
		var bk := Vector2i(floori(p.x / spacing), floori(p.z / spacing))
		var ok := true
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for q in chosen.get(bk + Vector2i(di, dj), []):
					if (q as Vector3).distance_to(p) < spacing:
						ok = false
		if not ok or not is_clear(p, 2.0):
			continue
		if not chosen.has(bk):
			chosen[bk] = []
		(chosen[bk] as Array).append(p)
		if placed < rares:
			add_spawn_group(p, "rare_pack", rng.randi_range(4, 5), 3.5)
		else:
			add_spawn_group(p, "pack", rng.randi_range(3, 6), 3.0)
		placed += 1
	return placed


## The act's zone boss (ActDefs "zone_boss": the guardian of the dungeon's region) at pos.
func add_zone_boss(pos: Vector3) -> void:
	var boss_id := String(ActDefs.get_act(act_id).get("zone_boss", "")) if ActDefs.has_act(act_id) else ""
	boss_pos = Vector3(pos.x, 0.0, pos.z)
	keep(boss_pos, 6.0)
	add_spawn_group(boss_pos, "boss", 1, 3.0, boss_id)


func _region_outputs() -> Array:
	var out: Array = []
	for r in regions:
		out.append({"id": String(r["id"]), "name": String(r.get("name", r["id"])), "level": int(r.get("level", 0)),
			"safe": false, "pool": region_pools.get(String(r["id"]), {})})
	return out


## Region arrivals: the painter's choice, else just inside the region's entrance from the town side
## (from the region nearer to the outskirts), else its most open spot.
func _arrival_outputs() -> Dictionary:
	var out := {}
	# Spots that are no region ("dungeon_exit") pass straight through.
	if region_arrivals.has("dungeon_exit"):
		out["dungeon_exit"] = region_arrivals["dungeon_exit"]
	if regions.is_empty():
		return out
	# Hops from the outskirts (the first region) over the links.
	var hops := {String(regions[0]["id"]): 0}
	var frontier: Array = [String(regions[0]["id"])]
	while not frontier.is_empty():
		var nxt: Array = []
		for id in frontier:
			for l in region_links(id):
				if not hops.has(l["to"]):
					hops[l["to"]] = int(hops[id]) + 1
					nxt.append(l["to"])
		frontier = nxt
	for r in regions:
		var id := String(r["id"])
		if region_arrivals.has(id):
			out[id] = region_arrivals[id]
			continue
		if id == String(regions[0]["id"]):
			out[id] = start
			continue
		var entry := {}
		for l in region_links(id):
			if int(hops.get(l["to"], 99)) < int(hops.get(id, 99)):
				entry = l
				break
		out[id] = _inside_from(id, entry["pos"]) if not entry.is_empty() else region_center(id)
	return out


## A walkable, open spot of region `id` about 18 m in from `door` towards the region's centre.
func _inside_from(id: String, door: Vector3) -> Vector3:
	var goal := region_center(id)
	var dir := (goal - door)
	dir.y = 0.0
	if dir.length() < 0.1:
		return goal
	dir = dir.normalized()
	for d in [18.0, 22.0, 26.0, 14.0, 30.0, 36.0]:
		var p: Vector3 = door + dir * float(d)
		var c := world_to_cell(p)
		if region_of_cell(c) == id and grid.is_walkable_cell(c) and region_open(c) >= 3.0 and is_clear(p, 1.0):
			return cell_center(c)
	return goal


## A plain fill of a layout: every region gets rocks and packs, the dungeon door gets an entrance
## (env_waypoint look), the last region the zone boss. Stand-in until an act paints its regions.
func paint_regions_default() -> void:
	for r in regions:
		var id := String(r["id"])
		scatter_region(id, ["env_rock_a", "env_rock_b"], 0.08, {"collide": 0.8, "min_dist": 9.0, "scale": Vector2(0.9, 1.5)})
	var door := dungeon_door()
	if not door.is_empty():
		var dv: Vector2i = door["dir"]
		var yaw := atan2(-dv.x, -dv.y)
		add_dungeon_entrance(door["pos"] - Vector3(dv.x, 0, dv.y) * 3.0, yaw, "env_waypoint", Vector2(4.2, 2.4))
		add_zone_boss(door["pos"] - Vector3(dv.x, 0, dv.y) * 20.0)
	for r in regions:
		var id := String(r["id"])
		var area := float(r.get("cells", 0)) * TILE * TILE
		auto_spawn_region(id, maxi(3, int(area / 5200.0)), maxi(1, int(area / 30000.0)))
		scatter_region(id, ["env_rubble", "env_bones"], 0.05, {"min_dist": 5.0, "shadows": false})


# ------------------------------------------------------------------ fields & fast noise

## Distance (m) from every cell to the nearest non-walkable cell (chamfer), 0 on blocked cells.
static func distance_to_blocked(g: WorldGrid) -> PackedFloat32Array:
	var w := g.size.x
	var h := g.size.y
	var d := PackedFloat32Array()
	d.resize(w * h)
	var big := 1e6
	for k in w * h:
		d[k] = big if g.walk[k] == 1 else 0.0
	var diag := TILE * 1.4142
	for j in h:
		for i in w:
			var k := j * w + i
			if d[k] == 0.0:
				continue
			var best := d[k]
			best = minf(best, (d[k - 1] if i > 0 else 0.0) + TILE)
			best = minf(best, (d[k - w] if j > 0 else 0.0) + TILE)
			if j > 0:
				best = minf(best, (d[k - w - 1] if i > 0 else 0.0) + diag)
				best = minf(best, (d[k - w + 1] if i < w - 1 else 0.0) + diag)
			d[k] = best
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var k := j * w + i
			if d[k] == 0.0:
				continue
			var best := d[k]
			best = minf(best, (d[k + 1] if i < w - 1 else 0.0) + TILE)
			best = minf(best, (d[k + w] if j < h - 1 else 0.0) + TILE)
			if j < h - 1:
				best = minf(best, (d[k + w + 1] if i < w - 1 else 0.0) + diag)
				best = minf(best, (d[k + w - 1] if i > 0 else 0.0) + diag)
			d[k] = best
	return d


## Bilinear sample of a per-cell field (a PackedFloat32Array over this zone's grid) at a world
## point (cell centres), clamped at the edges. Cheap enough for ground_color().
func field_sample(field: PackedFloat32Array, x: float, z: float) -> float:
	var w := grid.size.x
	var h := grid.size.y
	var u := clampf(x / TILE - 0.5, 0.0, w - 1.001)
	var v := clampf(z / TILE - 0.5, 0.0, h - 1.001)
	var i0 := int(u)
	var j0 := int(v)
	var fu := u - i0
	var fv := v - j0
	var k := j0 * w + i0
	var i1 := 1 if i0 < w - 1 else 0
	var j1 := w if j0 < h - 1 else 0
	var a := lerpf(field[k], field[k + i1], fu)
	var b := lerpf(field[k + j1], field[k + j1 + i1], fu)
	return lerpf(a, b, fv)


## A per-cell field from a function of the cell centre (evaluated once per cell).
func field_from(fn: Callable) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(grid.size.x * grid.size.y)
	for j in grid.size.y:
		for i in grid.size.x:
			f[j * grid.size.x + i] = float(fn.call(Vector2i(i, j)))
	return f


## Distance (m) from every cell to the nearest cell where `mask` (PackedByteArray, per cell) is set.
func field_distance_to(mask: PackedByteArray) -> PackedFloat32Array:
	var g := WorldGrid.new()
	g.setup(grid.size)
	for k in mask.size():
		g.walk[k] = 0 if mask[k] != 0 else 1
	return distance_to_blocked(g)


## Fractal noise in [0, 1] (native FastNoiseLite: ~20x cheaper than fbm()). freq in 1/m.
static func noise2(x: float, z: float, freq: float = 0.05, octaves: int = 3) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.seed = 1337
		_noise.frequency = 1.0
	_noise.fractal_octaves = octaves
	return _noise.get_noise_2d(x * freq, z * freq) * 0.5 + 0.5


# ------------------------------------------------------------------ finishing

## Rebuild A*; walkable cells the start cannot reach become blocked (nothing spawns there).
func finalize() -> void:
	var sc := world_to_cell(start)
	if not grid.is_walkable_cell(sc):
		var nc := grid.nearest_walkable_cell(sc)
		if nc.x >= 0:
			start = cell_center(nc)
			sc = nc
	var reach := grid.flood_walkable(sc)
	for k in grid.walk.size():
		if grid.walk[k] == 1 and reach[k] == 0:
			grid.walk[k] = 0
	grid.rebuild_astar()


## Distance (m) from pos to the nearest walkable cell centre, searched up to 12 m (else 12).
func walk_distance(pos: Vector3) -> float:
	if grid == null:
		return 99.0
	var c0 := world_to_cell(pos)
	var best := 12.0
	for j in range(c0.y - 6, c0.y + 7):
		for i in range(c0.x - 6, c0.x + 7):
			var c := Vector2i(i, j)
			if grid.is_walkable_cell(c):
				best = minf(best, cell_center(c).distance_to(Vector3(pos.x, 0, pos.z)))
	return best


# ------------------------------------------------------------------ noise

## Smooth value noise in [0, 1].
static func vnoise(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := x - ix
	var fz := z - iz
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := hash2(ix, iz)
	var b := hash2(ix + 1.0, iz)
	var c := hash2(ix, iz + 1.0)
	var d := hash2(ix + 1.0, iz + 1.0)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz)


## Fractal value noise in [0, 1].
static func fbm(x: float, z: float, octaves: int = 4) -> float:
	var s := 0.0
	var amp := 0.5
	var norm := 0.0
	var f := 1.0
	for o in octaves:
		s += vnoise(x * f + o * 17.3, z * f - o * 9.1) * amp
		norm += amp
		amp *= 0.5
		f *= 2.03
	return s / norm


static func hash2(x: float, z: float) -> float:
	var h := sin(x * 127.1 + z * 311.7) * 43758.5453
	return h - floorf(h)


# ------------------------------------------------------------------ default layouts

func _reset_outputs() -> void:
	grid = null
	tiles = []
	props = []
	shapes = []
	soft = {}
	lights = []
	glows = []
	shafts = []
	details = []
	grass = []
	water_rects = []
	interactables = []
	exits = {}
	dungeon_entrance = {}
	spawn_groups = []
	keepouts = []
	_keep_hash = {}
	portal_spot = {}
	regions = []
	region_map = PackedByteArray()
	_region_index = {}
	_region_cells = {}
	_open_field = PackedFloat32Array()


## A plain square hub: plaza, four houses, merchant, stash, waystone, portal to the wilds.
func _default_hub() -> void:
	setup_grid(Vector2i(30, 30))
	carve_rect(Rect2i(3, 3, 24, 24))
	ground_rect = Rect2(-30, -30, 120, 120)
	start = at(15, 22)
	var plaza: Array = []
	for j in range(11, 19):
		for i in range(11, 19):
			plaza.append(Vector2i(i, j))
	add_tiles(["env_floor_a", "env_floor_b", "env_floor_c"], plaza, Color(0.8, 0.74, 0.64))
	add_waystone(at(15, 5), 0.0)
	add_vendor(at(8, 15), PI * 0.5)
	add_prop("town_stall", at(6.5, 15), PI * 0.5, 1.0, {"cutout": true})
	block_rect(Rect2i(5, 14, 2, 2), false, true)
	shapes.append({"type": "box", "pos": at(6.5, 15), "size": Vector3(2.2, 2.0, 2.8), "yaw": 0.0})
	add_stash(at(22, 15), -PI * 0.5)
	add_portal_to("wilds", at(15, 25.5), PI)
	portal_spot = {"pos": at(20, 22), "yaw": 0.0}
	keep(portal_spot["pos"], 2.4)
	keep(start, 1.5)
	for h in [[at(6.5, 6.5), 0.0], [at(23.5, 6.5), 0.0], [at(6.5, 23.5), PI * 0.5], [at(23.5, 23.5), -PI * 0.5]]:
		add_building(pick(["town_house_a", "town_house_b", "town_house_c"]), h[0], h[1], Vector2(6, 6))
	for l in [at(11, 10), at(19, 10), at(11, 20), at(19, 20)]:
		add_obstacle("town_lamp", l, 0.0, 1.0, 0.25, {"cutout": false})
		add_light(l + Vector3(0, 3.0, 0), Color(1.0, 0.72, 0.4), 1.4, 8.0, true)
		add_glow(l, 2.6, Color(1.0, 0.7, 0.35))
	scatter(["town_tree_a", "town_tree_b"], 120, Rect2(-24, -24, 108, 108), {"min_dist": 3.0, "scale": Vector2(0.9, 1.3)})


## The act's layout filled with a plain stand-in, or (no layout) a plain winding wilds: a noisy band
## from the south (start) to a boss clearing in the north.
func _default_wilds() -> void:
	if ActDefs.has_act(act_id) and not ActDefs.layout(act_id).is_empty():
		use_layout()
		paint_regions_default()
		return
	var w := 44
	var h := 64
	setup_grid(Vector2i(w, h))
	ground_rect = Rect2(-30, -30, w * TILE + 60, h * TILE + 60)
	var pts: Array = []
	var x := w * 0.5
	for k in 9:
		var j := h - 5 - k * (h - 10) / 8.0
		pts.append(at(x, j))
		x = clampf(x + rng.randf_range(-7.0, 7.0), 9.0, w - 9.0)
	for k in pts.size():
		carve_disc(pts[k], rng.randf_range(8.0, 12.0))
	carve_path(pts, 7.0)
	start = pts[0]
	boss_pos = pts[pts.size() - 1]
	carve_disc(boss_pos, 13.0)
	add_portal_to("hub", start + Vector3(0, 0, 3.0), 0.0)
	keep(start, 3.0)
	keep(boss_pos, 6.0)
	scatter(["env_rock_a", "env_rock_b"], 20, Rect2(0, 0, w * TILE, h * TILE), {"on": "walkable", "collide": 0.7, "min_dist": 7.0})
	scatter(["town_tree_a", "town_tree_b"], 400, ground_rect, {"min_dist": 2.6, "scale": Vector2(0.9, 1.35)})
	var chest_spots := 0
	for p in pts.slice(2, pts.size() - 1):
		if chest_spots < 3 and is_clear(p + Vector3(4, 0, 0), 1.2) and is_walkable_at(p + Vector3(4, 0, 0)):
			add_chest(p + Vector3(4, 0, 0), 0.0, 1 if chest_spots == 2 else 0)
			chest_spots += 1
	var mid: Vector3 = pts[pts.size() / 2]
	if is_walkable_at(mid + Vector3(-4, 0, 0)):
		add_shrine(mid + Vector3(-4, 0, 0))
	auto_spawn_groups(12, 3)

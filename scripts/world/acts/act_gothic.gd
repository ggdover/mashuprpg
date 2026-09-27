extends WorldActGen
## Act III — the gothic town (Yharnam / Irithyll references): moonlit night, dark stone
## townhouses with steep slate roofs and warm windows, gaslit lamps, iron fences, graves, teal fog.
##   hub   "Cathedral Square": a flagstone plaza before the great cathedral, fountain in the middle,
##         townhouses east and west, the merchant's stall, stash, lantern shrine (waystone), a
##         small churchyard, a fenced garden of graves to the south and the lane to the Old Ward.
##   wilds the act's layout (data/layouts/act_gothic.json): five big zones joined by broad paths,
##         a gateway (gate pillars under an iron arch) where each path crosses between two zones.
##     "outskirts" The Old Ward (+0): flagstone squares and wide cobbled boulevards between blocks
##         of townhouses and fenced gardens — the arrival square by the lane from Cathedral Square,
##         the great fountain plaza, the market, the clock tower square, the gallows square, the
##         chapel square and the undertaker's yard.
##     "canals" The Canal Quarter (+1): the Great Canal and the Sluice (water, not walkable) with
##         flagstone quays, balustrades, moored boats and three arched bridges; houses on the quays.
##     "cemetery" Ashgrove Cemetery (+2): grass plots with rows of graves, mausoleums, dead trees,
##         hooded statues and fenced family plots around a crossing; the Ashgrove Mausoleum; fog.
##     "bridge" Blackmoor Bridge (+2): a gorge splits the zone; the great bridge (statues, lamps,
##         towers at both ends) crosses it; balustrades line the rims.
##     "abbey" The Abbey Grounds (+3): the abbey church, its cloister, graveyards and braziers
##         along the pilgrims' way; the Abbey Undercroft (the act's dungeon) in the east wall,
##         guarded by the Undertaker.
## The camera looks north-west (CAM_DIR): a house only stands where it hides no walkable ground
## from the camera (_occludes). So rows of houses close the zones' north / west edges, facing in,
## iron railings (border_style) the south / east edges, and the blocks inside the zones have their
## houses along their south and east sides with fenced yards behind. The wilds are painted into
## per-cell fields (kind, open, depth, colour): the ground reads them (fast ground_color /
## ground_height), the paving follows the kinds. OWNER: acts-gothic.

const HOUSES_WIDE: Array = ["gothic_house_a", "gothic_house_b", "gothic_house_c"]
const HOUSE_NARROW := "gothic_house_d"
const TERRACES: Array = ["gothic_terrace_a", "gothic_terrace_b"]
const COBBLES: Array = ["gothic_cobble_a", "gothic_cobble_b"]
const FLAGS: Array = ["env_floor_a", "env_floor_b", "env_floor_c"]
const LAMP_LIGHT := Color(1.0, 0.64, 0.32)
const FIRE_LIGHT := Color(1.0, 0.36, 0.18)
const COBBLE_TINT := Color(0.42, 0.44, 0.5)
const COBBLE_TINTS: Array = [Color(0.42, 0.44, 0.5), Color(0.38, 0.4, 0.46), Color(0.46, 0.46, 0.51), Color(0.4, 0.41, 0.45)]
const FLAG_TINT := Color(0.4, 0.42, 0.48)
const FLAG_TINTS: Array = [Color(0.4, 0.42, 0.48), Color(0.35, 0.37, 0.43), Color(0.44, 0.45, 0.5), Color(0.38, 0.38, 0.42)]
const QUAY_TINTS: Array = [Color(0.45, 0.46, 0.5), Color(0.41, 0.42, 0.46), Color(0.48, 0.48, 0.51)]
const PATH_TINTS: Array = [Color(0.34, 0.37, 0.36), Color(0.3, 0.33, 0.32), Color(0.37, 0.39, 0.38)]
const DECK_TINTS: Array = [Color(0.47, 0.47, 0.5), Color(0.43, 0.43, 0.46), Color(0.5, 0.49, 0.5)]
## The zones' big streets: low-poly setts; street / flagstone tints per zone.
const WILDS_COBBLES: Array = ["gothic_cobble_c", "gothic_cobble_d"]
const ZONE_TINTS := {
	"canals": [Color(0.36, 0.4, 0.47), Color(0.33, 0.37, 0.43), Color(0.39, 0.42, 0.48)],
	"bridge": [Color(0.46, 0.46, 0.49), Color(0.42, 0.42, 0.45), Color(0.49, 0.48, 0.5)],
	"abbey": [Color(0.45, 0.42, 0.43), Color(0.41, 0.38, 0.39), Color(0.48, 0.44, 0.44)],
}
const ZONE_FLAG_TINTS := {
	"canals": [Color(0.38, 0.41, 0.47), Color(0.34, 0.37, 0.43), Color(0.41, 0.43, 0.48)],
	"abbey": [Color(0.46, 0.42, 0.42), Color(0.41, 0.37, 0.38), Color(0.5, 0.45, 0.44)],
}
## Grave-ish clutter for gardens and graveyards.
const GRAVE_IDS := {"gothic_grave_a": 3.0, "gothic_grave_b": 3.0, "gothic_dead_tree": 0.8, "gothic_statue": 0.35, "gothic_coffin": 0.5}
## From the player towards the game camera on the ground plane (the camera looks north-west).
const CAM_DIR := Vector2(0.609, 0.793)
## A house (eaves ~9 m, ridge ~13 m) hides the player when its near face is closer than this (m)
## along CAM_DIR: the camera is ~12.7 m away and ~15 m up.
const OCCLUDE_M := 7.5
## Kinds of wilds cells (_kind): paving, ground and what stands on it.
const K_VOID := 0     # outside the zones
const K_STREET := 1   # cobbles
const K_PLAZA := 2    # flagstones
const K_GRASS := 3    # graveyard grass, yards (no tiles)
const K_WATER := 4    # a canal (not walkable, under the water plane)
const K_CHASM := 5    # the gorge under Blackmoor Bridge
const K_BLOCK := 6    # houses on a block (not walkable)
const K_DECK := 7     # a bridge deck (flagstones)
const K_QUAY := 8     # a canal quay (flagstones)
const K_PATH := 9     # a graveyard path (old flagstones)
const WATER_Y := -0.8
const CANAL_DEPTH := -3.6
const GORGE_DEPTH := -26.0
## Ground colour per cell kind (sRGB; alpha = how much snow may settle on it).
const KIND_COLORS: Array = [
	Color(0.13, 0.14, 0.16, 0.3), Color(0.1, 0.1, 0.11, 0.0), Color(0.1, 0.1, 0.11, 0.0), Color(0.15, 0.18, 0.14, 0.8),
	Color(0.07, 0.085, 0.095, 0.0), Color(0.13, 0.14, 0.16, 0.2), Color(0.11, 0.11, 0.12, 0.5),
	Color(0.1, 0.1, 0.11, 0.0), Color(0.1, 0.1, 0.11, 0.0), Color(0.1, 0.1, 0.11, 0.0),
]
const SNOW_SRGB := Color(0.72, 0.78, 0.86)

## Hub: cells taken by buildings / landmarks / gardens (Vector2i -> kind).
var _occ := {}
## Hub: cells that must stay visible from the camera (streets, squares).
var _visible := {}
## Hub: graveyard / garden walkable cells (grass ground, no tiles).
var _grass := {}
var _lamps: Array[Vector3] = []

## Wilds: grid size, cell kinds, cells kept free of blocks, ground depth (canals, gorge) and
## ground colour (linear rgb + snow cover) per cell.
var _W := 0
var _H := 0
var _kind := PackedByteArray()
var _open := PackedByteArray()
var _depth := PackedFloat32Array()
var _ccol := PackedColorArray()
var _snow_lin := Color(0.47, 0.56, 0.7)
## Wilds: lamps (12 m buckets -> positions), edge buildings (8 m buckets -> [Vector2, radius]),
## chest / shrine spots per zone (painters' picks, placed by _loot()).
var _lamp_hash := {}
var _bld_hash := {}
var _chest_spots := {}
var _shrine_spots := {}


func theme() -> Dictionary:
	return {
		"sky": false,
		"background": Color(0.035, 0.05, 0.065),
		"ambient": Color(0.26, 0.4, 0.46),
		"ambient_energy": 0.4,
		"sun": Color(0.62, 0.78, 0.92),
		"sun_energy": 0.9,
		"sun_rot": Vector3(-52.0, -28.0, 0.0),
		"sun_shadows": true,
		"fog": Color(0.11, 0.2, 0.2),
		"fog_density": 0.016,
		"fog_sky_affect": 0.0,
		"fog_height": 1.2,
		"fog_height_density": 0.06,
		"volumetric_fog": {"density": 0.028, "albedo": Color(0.45, 0.66, 0.66), "emission": Color(0.025, 0.05, 0.05),
			"emission_energy": 1.0, "anisotropy": 0.35, "length": 56.0, "detail_spread": 2.0, "gi_inject": 0.6},
		"exposure": 1.1,
		"white": 5.0,
		"contrast": 1.16,
		"saturation": 0.86,
		"brightness": 1.0,
		"glow_intensity": 0.9,
		"glow_strength": 1.05,
		"glow_bloom": 0.05,
		"glow_hdr_threshold": 0.9,
		"light_color": LAMP_LIGHT,
		"light_energy": 2.8,
		"light_range": 9.5,
		"glow_color": Color(1.0, 0.6, 0.28),
		"glow_pool_strength": 0.34,
		"water_shallow": Color(0.13, 0.21, 0.25),
		"water_deep": Color(0.04, 0.08, 0.1),
		"water_foam": Color(0.5, 0.6, 0.64),
		"water_depth_scale": 1.2,
		"particles": {"kind": "snow", "color": Color(0.86, 0.9, 0.95, 0.75), "amount": 360, "size": 0.07, "speed": 0.35},
		"daylight": false,
	}


## Iron fences with stone pillars close every open edge the houses leave (the south / east edges
## of the zones, gaps between houses, the paths between the zones).
func border_style() -> Dictionary:
	return {
		"segments": {"gothic_railing": 1.0},
		"length": 6.0,
		"posts": {"gothic_pillar": 1.0},
		"post_every": 1,
		"offset": 0.3,
		"min_prop_height": 1.2,
		"prop_clearance": 1.3,
		"max_footprint": 0.8,
		"solid_prefixes": ["gothic_house", "gothic_terrace", "gothic_crypt", "gothic_cathedral", "gothic_clocktower",
			"gothic_bridge_tower", "gothic_undercroft", "gothic_arcade", "gothic_stall"],
		"skip_water": true,
	}


# ------------------------------------------------------------------ ground

func ground_color(x: float, z: float) -> Color:
	if zone == "hub":
		return _hub_ground_color(x, z)
	if _ccol.is_empty():
		return Color(0.02, 0.022, 0.026)
	# Vertices sit on cell corners: the mean of the four cells around, shaded by broad noise, snow
	# where the noise is high and the ground takes it.
	var i := clampi(roundi(x * 0.5), 1, _W - 1)
	var j := clampi(roundi(z * 0.5), 1, _H - 1)
	var k := j * _W + i
	var c: Color = (_ccol[k] + _ccol[k - 1] + _ccol[k - _W] + _ccol[k - _W - 1]) * 0.25
	var n := noise2(x, z, 0.021, 2)
	var s := smoothstep(0.62, 0.84, n) * c.a * 0.4
	var v := 0.84 + 0.32 * n
	return Color(lerpf(c.r * v, _snow_lin.r, s), lerpf(c.g * v, _snow_lin.g, s), lerpf(c.b * v, _snow_lin.b, s))


func ground_height(x: float, z: float) -> float:
	if zone == "hub" or _depth.is_empty():
		return 0.0
	var i := clampi(roundi(x * 0.5), 1, _W - 1)
	var j := clampi(roundi(z * 0.5), 1, _H - 1)
	var k := j * _W + i
	return (_depth[k] + _depth[k - 1] + _depth[k - _W] + _depth[k - _W - 1]) * 0.25


func _hub_ground_color(x: float, z: float) -> Color:
	var c := Vector2i(floori(x / TILE), floori(z / TILE))
	var n := fbm(x * 0.09, z * 0.09, 3)
	var fine := vnoise(x * 0.9, z * 0.9)
	var snow_amt := smoothstep(0.56, 0.8, n + fine * 0.12)
	var base: Color
	if _grass.has(c):
		base = Color(0.08, 0.1, 0.075).lerp(Color(0.13, 0.13, 0.1), smoothstep(0.35, 0.75, n))
		base = base.lerp(Color(0.11, 0.085, 0.065), smoothstep(0.55, 0.9, fine) * 0.7)
		return base.lerp(Color(0.34, 0.38, 0.43), snow_amt * 0.45)
	else:
		base = Color(0.1, 0.105, 0.115).lerp(Color(0.15, 0.15, 0.16), smoothstep(0.3, 0.8, n))
	return base.lerp(Color(0.4, 0.45, 0.52), snow_amt * 0.7)


# ------------------------------------------------------------------ zones

func generate_zone() -> void:
	if zone == "hub":
		_hub()
	else:
		_wilds()


func _hub() -> void:
	setup_grid(Vector2i(36, 40))
	ground_rect = Rect2(-44.0, -44.0, 72.0 + 88.0, 80.0 + 60.0)
	# The cathedral across the north end (front steps at z = 18.5).
	add_building("gothic_cathedral", Vector3(36.0, 0.0, 8.5), 0.0, Vector2(29.0, 19.0))
	_reserve_rect(Rect2i(10, 0, 16, 9), "landmark")
	add_light(Vector3(36.0, 2.4, 19.6), Color(1.0, 0.62, 0.3), 2.2, 9.0, true)
	# Plaza + a lane north past the cathedral's east end and the churchyard to the Old Ward (it
	# leaves the grid's north edge; the camera looks from the south-east, so the lane keeps the
	# cathedral on its west side).
	var plaza := Rect2i(8, 9, 20, 18)
	var road := Rect2i(28, 0, 3, 16)
	carve_rect(plaza)
	carve_rect(road)
	# The churchyard (north-east corner of the plaza): a crypt and graves behind a fence.
	var yard := Rect2i(23, 9, 5, 4)
	block_rect(yard)
	_reserve_rect(yard, "yard")
	add_prop("gothic_crypt", at(26.0, 11.2), -PI * 0.5, 1.0, {"cutout": true})
	for p in [at(23.6, 10.0), at(24.5, 11.6), at(23.5, 12.4), at(25.0, 9.6)]:
		add_prop("gothic_grave_a" if rng.randf() < 0.5 else "gothic_grave_b", p, rng.randf_range(-0.3, 0.3), 1.0)
	add_prop("gothic_dead_tree", at(27.4, 9.6), rng.randf() * TAU, 0.9, {"cutout": true})
	_fence_line(at(23.0, 13.0), at(28.0, 13.0), true)
	_fence_line(at(23.0, 9.0), at(23.0, 13.0), true)
	# Mark visibility (for the house rule) and tiles.
	_mark_visible_walkable()
	_hub_tiles(plaza, road)
	# Fountain in the middle, lamps around it.
	var centre := at(18.0, 18.0)
	add_obstacle("gothic_fountain", centre, PI / 8.0, 1.0, 2.3, {"cutout": false})
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		_lamp(centre + Vector3(cos(a), 0, sin(a)) * 6.4, a + PI * 0.5, true)
	for k2 in 4:
		var a2 := k2 * PI * 0.5
		var bp := centre + Vector3(cos(a2), 0, sin(a2)) * 4.3
		add_obstacle("gothic_bench", bp, atan2(-cos(a2), -sin(a2)), 1.0, 0.5, {"cutout": false})
	for q in [at(12.5, 13.0), at(23.5, 22.5), at(12.5, 22.5)]:
		add_obstacle("gothic_planter", q, 0.0, 1.0, 0.75, {"cutout": false})
	# Waystone (north-west, by the cathedral), merchant (west), stash (east).
	add_waystone(at(11.2, 11.6), PI * 0.5, "gothic_shrine", Vector2(2.6, 2.0))
	add_light(at(11.2, 11.6) + Vector3(0.0, 2.6, 0.0), Color(1.0, 0.7, 0.36), 1.6, 7.0, true)
	add_block("gothic_stall", at(9.2, 17.0), PI * 0.5, Vector2(3.4, 2.6), {"height": 2.6})
	add_vendor(at(10.7, 17.0), PI * 0.5)
	add_light(at(10.0, 17.0) + Vector3(0.0, 2.4, 0.0), Color(1.0, 0.66, 0.34), 1.6, 7.0, true)
	add_prop("gothic_coffin", at(9.0, 20.4), 1.3, 1.0)
	block_cell(Vector2i(9, 20), false, false)
	add_stash(at(26.4, 17.0), -PI * 0.5)
	# An abandoned carriage in the south-east of the plaza.
	add_block("gothic_carriage", at(25.2, 21.4), 0.35, Vector2(2.2, 4.8), {"height": 2.6})
	# Corner lamps (the north-east corner is the churchyard).
	_lamp(at(9.4, 9.8), 0.0, true)
	_lamp(at(9.4, 26.3), 0.0, true)
	_lamp(at(26.6, 26.3), 0.0, true)
	# The lane north through gate pillars, lamps along it; the Old Ward lies beyond.
	for z in [13.0, 16.0]:
		add_prop("gothic_pillar", at(28.0, z) + Vector3(-0.4, 0, -0.4 if z < 14.0 else 0.4), 0.0, 1.0)
		keep(at(28.0, z), 0.6)
	_lamp(at(31.35, 9.0), -PI * 0.5, false, Vector3(-1, 0, 0))
	_lamp(at(31.35, 2.5), -PI * 0.5, false, Vector3(-1, 0, 0))
	add_exit("wilds", at(29.5, 0.5), Vector2i(0, -1))
	start = at(18.0, 24.6)
	portal_spot = {"pos": at(21.5, 24.0), "yaw": 0.0}
	keep(start, 1.6)
	keep(portal_spot["pos"], 2.4)
	# Buildings around the plaza (east / west rows and behind them), gardens of graves south.
	_fill_city(Rect2i(0, 0, 36, 40), 6)
	_decorate_gardens(Rect2i(0, 0, 36, 40))
	_street_lamps()
	_ground_decals(9, 1)
	_outer_city(Rect2i(0, 0, 36, 40))
	reveal_all = true


# ------------------------------------------------------------------ hub helpers

func _hub_tiles(plaza: Rect2i, road: Rect2i) -> void:
	# Cobbled cross through the plaza, flagstones in the quadrants, cobbled road.
	var cob: Array = []
	var flag: Array = []
	for j in grid.size.y:
		for i in grid.size.x:
			var c := Vector2i(i, j)
			if not grid.is_walkable_cell(c):
				continue
			var cross := (i >= 16 and i <= 19) or (j >= 16 and j <= 19)
			if road.has_point(c) or (plaza.has_point(c) and cross):
				cob.append(c)
			else:
				flag.append(c)
	add_tiles(COBBLES, cob, COBBLE_TINT, COBBLE_TINTS)
	add_tiles(FLAGS, flag, FLAG_TINT, FLAG_TINTS)


## Rain puddles and a few blood stains on the tiled ground (decoration, no collision).
func _ground_decals(puddles: int, blood: int) -> void:
	var r := Rect2(0, 0, grid.size.x * TILE, grid.size.y * TILE)
	scatter(["gothic_puddle"], puddles, r, {"on": "walkable", "min_dist": 7.0, "scale": Vector2(0.55, 0.95), "shadows": false,
		"filter": func(p: Vector3) -> bool: return not _grass.has(world_to_cell(p))})
	scatter(["gothic_blood"], blood, r, {"on": "walkable", "min_dist": 12.0, "scale": Vector2(0.7, 1.1), "shadows": false,
		"filter": func(p: Vector3) -> bool: return not _grass.has(world_to_cell(p))})


## Lamps along street edges: inside the building / garden cell next to the street, ~10 m apart.
func _street_lamps() -> void:
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for j in range(1, grid.size.y - 1):
		for i in range(1, grid.size.x - 1):
			var c := Vector2i(i, j)
			if not grid.is_walkable_cell(c) or _grass.has(c):
				continue
			for d in dirs:
				var n: Vector2i = c + d
				var kind := String(_occ.get(n, ""))
				if kind != "house" and kind != "garden":
					continue
				var edge := cell_center(c) + Vector3(d.x, 0, d.y) * (TILE * 0.5)
				var pos := edge + Vector3(d.x, 0, d.y) * (0.3 if kind == "house" else 0.62)
				var ok := true
				for q in _lamps:
					if q.distance_to(pos) < 10.0:
						ok = false
						break
				if not ok or not is_clear(pos, 0.3):
					continue
				_lamp(pos, 0.0 if d.x == 0 else PI * 0.5, false, -Vector3(d.x, 0, d.y))


## A street lamp: prop (+ collision when standing on walkable ground), light, glow pool.
## `toward`: direction of the street (lights and glows shift that way).
func _lamp(pos: Vector3, yaw: float, on_walkable: bool, toward: Vector3 = Vector3.ZERO) -> void:
	if on_walkable:
		add_obstacle("gothic_lamp", pos, yaw, 1.0, 0.22, {"cutout": false})
	else:
		add_prop("gothic_lamp", pos, yaw, 1.0, {"shadows": true})
		keep(pos, 0.4)
	_lamps.append(pos)
	var lp := pos + toward * 0.6
	add_light(lp + Vector3(0.0, 2.75, 0.0), LAMP_LIGHT, 3.2, 10.5, true)
	add_glow(lp, 3.0, Color(1.0, 0.6, 0.28))


## Iron fence from a to b (axis-aligned, along cell edges), 2 m segments, pillars every 3rd joint.
func _fence_line(a: Vector3, b: Vector3, pillars: bool) -> void:
	var d := b - a
	var n := int(round(d.length() / TILE))
	if n <= 0:
		return
	var dir := d / float(n)
	var yaw := 0.0 if absf(d.x) > absf(d.z) else PI * 0.5
	for k in n:
		add_prop("gothic_fence", a + dir * (k + 0.5), yaw, 1.0)
		if pillars and k % 3 == 0:
			add_prop("gothic_pillar", a + dir * k, 0.0, 0.85)
	if pillars:
		add_prop("gothic_pillar", b, 0.0, 0.85)


## Iron railing from a to b (axis-aligned, along cell edges): 6 m pieces (2 m fence pieces for
## the rest), a pillar at every joint.
func _railing_line(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var n := int(round(d.length() / TILE))
	if n <= 0:
		return
	var dir := d / float(n)
	var yaw := 0.0 if absf(d.x) > absf(d.z) else PI * 0.5
	var k := 0
	while k < n:
		add_prop("gothic_pillar", a + dir * k, 0.0, 0.85)
		if n - k >= 3:
			add_prop("gothic_railing", a + dir * (k + 1.5), yaw, 1.0)
			k += 3
		else:
			add_prop("gothic_fence", a + dir * (k + 0.5), yaw, 1.0)
			k += 1
	add_prop("gothic_pillar", b, 0.0, 0.85)


func _reserve_rect(r: Rect2i, kind: String) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			_occ[Vector2i(i, j)] = kind


func _mark_visible_walkable() -> void:
	for j in grid.size.y:
		for i in grid.size.x:
			if grid.is_walkable_cell(Vector2i(i, j)):
				_visible[Vector2i(i, j)] = true


## Townhouses on free non-walkable blocks within max_dist cells of the streets. A block whose
## 4 rows to the north hold a visible cell (street, square, canal) stays a garden instead.
func _fill_city(area: Rect2i, max_dist: int) -> void:
	var dist := _street_distance()
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var c := Vector2i(i, j)
			if _occ.has(c) or grid.is_walkable_cell(c):
				continue
			var dc := int(dist.get(c, 99))
			if dc > max_dist:
				continue
			for shape in [Vector2i(3, 3), Vector2i(2, 3), Vector2i(3, 2)]:
				var sz: Vector2i = shape
				if not _block_free(c, sz, area):
					continue
				if _north_visible(c, sz):
					break
				var face := _facing(c, sz)
				if sz == Vector2i(2, 3) and absf(sin(face)) > 0.5:
					continue
				if sz == Vector2i(3, 2) and absf(sin(face)) < 0.5:
					continue
				var id: String = HOUSE_NARROW if sz != Vector2i(3, 3) else HOUSES_WIDE[rng.randi_range(0, HOUSES_WIDE.size() - 1)]
				var centre := at(c.x + sz.x * 0.5, c.y + sz.y * 0.5)
				add_prop(id, centre, face, 1.0, {"cutout": true, "shadows": true, "vary": 0.1})
				for jj in range(c.y, c.y + sz.y):
					for ii in range(c.x, c.x + sz.x):
						var cc := Vector2i(ii, jj)
						_occ[cc] = "house"
						grid.set_opaque(cc, true)
				break
	# Whatever is left right next to the streets becomes garden.
	for j2 in range(area.position.y, area.end.y):
		for i2 in range(area.position.x, area.end.x):
			var c2 := Vector2i(i2, j2)
			if _occ.has(c2) or grid.is_walkable_cell(c2):
				continue
			if grid.is_floor(c2):
				continue   # a blocked plaza / street cell (lamp, stall, carriage...), not a garden
			if int(dist.get(c2, 99)) <= 2:
				_occ[c2] = "garden"


## Iron fences on the edges between streets and gardens, graves / trees inside the gardens.
func _decorate_gardens(area: Rect2i) -> void:
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var c := Vector2i(i, j)
			if String(_occ.get(c, "")) != "garden":
				continue
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = c + d
				if not grid.is_walkable_cell(n):
					continue
				var edge := cell_center(c) + Vector3(d.x, 0, d.y) * (TILE * 0.5 - 0.22)
				add_prop("gothic_fence", edge, 0.0 if d.x == 0 else PI * 0.5, 1.0)
				if (i + j) % 3 == 0:
					var corner := edge + (Vector3(1, 0, 0) if d.x == 0 else Vector3(0, 0, 1)) * (TILE * 0.5)
					if is_clear(corner, 0.3):
						add_prop("gothic_pillar", corner, 0.0, 0.85)
						keep(corner, 0.35)
			if rng.randf() < 0.42:
				var p := cell_center(c) + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
				if is_clear(p, 0.6):
					var id := pick(GRAVE_IDS)
					var sc := rng.randf_range(0.85, 1.1)
					add_prop(id, p, rng.randf() * TAU if id == "gothic_dead_tree" else rng.randf_range(-0.4, 0.4), sc,
						{"cutout": id in ["gothic_dead_tree", "gothic_statue"]})
					keep(p, 0.5)


## Roofs beyond the playable area (only the overview really sees them): houses on a coarse
## lattice outside the grid and on far void blocks, some dead trees.
func _outer_city(area: Rect2i) -> void:
	var lo := ground_rect.position
	var hi := ground_rect.end
	var step := 6.6
	var z := lo.y + 3.0
	while z < hi.y - 3.0:
		var x := lo.x + 3.0
		while x < hi.x - 3.0:
			var c := world_to_cell(Vector3(x, 0, z))
			var inside := area.grow(-1).has_point(c)
			var band := area.grow(8).has_point(c)
			if (not inside and band) or (inside and not _occ.has(c) and not grid.is_walkable_cell(c) and _far_from_streets(c, 4)):
				var jit := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
				var ok := true
				if inside:
					for jj in range(c.y - 2, c.y + 2):
						for ii in range(c.x - 2, c.x + 2):
							var cc := Vector2i(ii, jj)
							if _occ.has(cc) or grid.is_walkable_cell(cc):
								ok = false
				if ok:
					var id: String = HOUSES_WIDE[rng.randi_range(0, HOUSES_WIDE.size() - 1)]
					add_prop(id, Vector3(x, 0, z) + jit, [0.0, PI * 0.5, PI, -PI * 0.5][rng.randi_range(0, 3)], rng.randf_range(0.95, 1.15), {"cutout": true, "shadows": false})
					if inside:
						for jj2 in range(c.y - 1, c.y + 2):
							for ii2 in range(c.x - 1, c.x + 2):
								if area.has_point(Vector2i(ii2, jj2)):
									_occ[Vector2i(ii2, jj2)] = "outer"
			x += step
		z += step


func _far_from_streets(c: Vector2i, r: int) -> bool:
	for j in range(c.y - r, c.y + r + 1):
		for i in range(c.x - r, c.x + r + 1):
			var cc := Vector2i(i, j)
			if grid.is_walkable_cell(cc) or _visible.has(cc):
				return false
	return true


func _block_free(c: Vector2i, sz: Vector2i, area: Rect2i) -> bool:
	for j in range(c.y, c.y + sz.y):
		for i in range(c.x, c.x + sz.x):
			var cc := Vector2i(i, j)
			if not area.has_point(cc) or _occ.has(cc) or grid.is_walkable_cell(cc):
				return false
	return true


func _north_visible(c: Vector2i, sz: Vector2i) -> bool:
	for j in range(c.y - 4, c.y):
		for i in range(c.x - 1, c.x + sz.x + 1):
			if _visible.has(Vector2i(i, j)):
				return true
	return false


## Facing (yaw) towards the nearest street side: south preferred, then east / west, else north.
func _facing(c: Vector2i, sz: Vector2i) -> float:
	var south := 0
	var east := 0
	var west := 0
	for k in range(1, 4):
		for i in range(c.x, c.x + sz.x):
			if grid.is_walkable_cell(Vector2i(i, c.y + sz.y - 1 + k)):
				south += 1
		for j in range(c.y, c.y + sz.y):
			if grid.is_walkable_cell(Vector2i(c.x + sz.x - 1 + k, j)):
				east += 1
			if grid.is_walkable_cell(Vector2i(c.x - k, j)):
				west += 1
	if south >= east and south >= west and south > 0:
		return 0.0
	if east >= west and east > 0:
		return PI * 0.5
	if west > 0:
		return -PI * 0.5
	return 0.0


## Chebyshev distance (cells) from every cell to the nearest walkable cell (up to 8).
func _street_distance() -> Dictionary:
	var out := {}
	var frontier: Array[Vector2i] = []
	for j in grid.size.y:
		for i in grid.size.x:
			var c := Vector2i(i, j)
			if grid.is_walkable_cell(c):
				out[c] = 0
				frontier.append(c)
	for step in range(1, 9):
		var nxt: Array[Vector2i] = []
		for c in frontier:
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var n := c + Vector2i(di, dj)
					if grid.in_bounds(n) and not out.has(n):
						out[n] = step
						nxt.append(n)
		frontier = nxt
	return out


# ------------------------------------------------------------------ the wilds (the act's layout)

func _wilds() -> void:
	use_layout()
	_W = grid.size.x
	_H = grid.size.y
	var n := _W * _H
	_kind.resize(n)
	_open.resize(n)
	_depth.resize(n)
	for k in n:
		if grid.walk[k] == 1:
			_kind[k] = K_STREET
	has_water = true
	water_level = WATER_Y
	_open_disc(_cell_pos(start), 5.0)
	_old_ward()
	_canal_quarter()
	_cemetery()
	_blackmoor_bridge()
	_abbey_grounds()
	_gateways()
	_edge_rows()
	_outer_roofs()
	_lay_tiles()
	_snowdrifts()
	_street_decals()
	_ground_setup()
	_prune_unreachable()
	_loot()
	_monsters()
	_zone_looks()


# ------------------------------------------------------------------ the Old Ward (outskirts)

func _old_ward() -> void:
	var id := "outskirts"
	set_region_pool(id, {"maddened_townsman": 4.0, "scourge_beast": 2.0, "belfry_archer": 2.0, "church_servant": 1.0})
	var ex := _exit_cell()
	var ln := _link_cell(id, "bridge")
	var lw := _link_cell(id, "canals")
	var fp := Vector2(200.0, 197.0)
	var arrive := Rect2i(ex.x - 12, ex.y - 25, 25, 21)
	var market := Rect2i(236, 188, 30, 30)
	var clock := Rect2i(221, 141, 30, 24)
	var gal := Vector2(151.0, 238.0)
	var chapel := Rect2i(131, 146, 32, 20)
	var yard := Rect2i(229, 236, 26, 20)
	# Boulevards (cobbles) between the squares and on to the paths out of the ward.
	var ways: Array = [
		[Vector2(ex.x + 0.5, arrive.position.y + 2.0), fp + Vector2(0.0, 12.0), 13.0],
		[fp - Vector2(0.0, 12.0), Vector2(ln.x + 0.5, ln.y + 1.0), 13.0],
		[fp - Vector2(12.0, 0.0), Vector2(lw.x + 1.0, lw.y + 0.5), 12.0],
		[fp + Vector2(12.0, 2.0), Vector2(market.position.x + 2.0, _rc(market).y), 11.0],
		[fp + Vector2(9.0, -10.0), Vector2(_rc(clock).x - 3.0, clock.end.y - 2.0), 10.0],
		[fp + Vector2(-9.0, 10.0), gal + Vector2(6.0, -6.0), 10.0],
		[Vector2(_rc(chapel).x, chapel.end.y - 2.0), Vector2(_rc(chapel).x + 1.0, lw.y + 0.5), 9.0],
		[Vector2(arrive.end.x - 2.0, _rc(arrive).y), Vector2(yard.position.x + 2.0, _rc(yard).y), 9.0],
	]
	for wv in ways:
		_paint_band(wv[0], wv[1], float(wv[2]), K_STREET, id)
	# Squares (flagstones), a cobbled cross through the arrival square, a cobbled ring round the
	# fountain.
	_paint_rect(arrive, K_PLAZA, id)
	_paint_disc(fp, 12.5, K_PLAZA, id)
	_paint_rect(market, K_PLAZA, id)
	_paint_rect(clock, K_PLAZA, id)
	_paint_disc(gal, 12.0, K_PLAZA, id)
	_paint_rect(chapel, K_PLAZA, id)
	_paint_rect(yard, K_PLAZA, id)
	_paint_band(Vector2(ex.x + 0.5, arrive.position.y), Vector2(ex.x + 0.5, ex.y + 1.0), 3.0, K_STREET, id)
	# The passage on to the grid's edge (the composer carves it) is cobbled too: the road to Cathedral
	# Square takes the paving found at the edge.
	for pj in range(ex.y + 1, _H):
		for pi in range(ex.x - 1, ex.x + 2):
			_kind[pj * _W + pi] = K_STREET
	_paint_band(Vector2(arrive.position.x, _rc(arrive).y), Vector2(arrive.end.x, _rc(arrive).y), 3.0, K_STREET, id)
	_ring(fp, 7.2, 8.4, K_STREET, id)
	_ring(fp, 11.5, 12.5, K_STREET, id)
	# Blocks of townhouses (some fenced gardens) between them.
	_fill_blocks(id, Vector2i(6, 5), Vector2i(14, 10), Vector2i(20, 13), 4, 0.12, 0.75)
	# The squares' landmarks and furniture.
	_fountain_plaza(fp, id)
	_market(market, id)
	_clock_square(clock, id)
	_gallows_square(gal, id)
	_chapel_square(chapel, id)
	_undertakers_yard(yard, id)
	_arrival_square(arrive, ex)
	for wv2 in ways:
		_lamps_along(wv2[0], wv2[1], float(wv2[2]) * 0.5 - 0.7, 16.0)
	# Abandoned carriages, coffins and crates along the boulevards.
	for wv3 in ways:
		var a3: Vector2 = wv3[0]
		var b3: Vector2 = wv3[1]
		var u3 := (b3 - a3).normalized()
		var t3 := Vector2(-u3.y, u3.x)
		for f in [0.3, 0.7]:
			var q3: Vector2 = a3.lerp(b3, float(f)) + t3 * (float(wv3[2]) * 0.5 - 2.2) * (1.0 if rng.randf() < 0.5 else -1.0)
			if rng.randf() < 0.5:
				_carriage(at(q3.x, q3.y), atan2(u3.x, u3.y) + rng.randf_range(-0.3, 0.3))
			else:
				_clutter(at(q3.x, q3.y))
	set_region_arrival(id, start)


func _fountain_plaza(c: Vector2, id: String) -> void:
	var p := at(c.x, c.y)
	add_obstacle("gothic_fountain", p, PI / 8.0, 1.6, 3.7, {"cutout": false})
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var q := p + Vector3(cos(a), 0.0, sin(a)) * 13.0
		add_obstacle("gothic_statue", q, _yaw_to(q, p), 1.1, 0.9)
	for k2 in 4:
		var a2 := k2 * PI * 0.5
		var bq := p + Vector3(cos(a2), 0.0, sin(a2)) * 6.8
		add_obstacle("gothic_bench", bq, _yaw_to(bq, p), 1.0, 0.5, {"cutout": false})
	_lamps_ring(p, 13.0, 4, 0.0)
	_lamps_ring(p, 21.0, 6, 0.5)
	for k3 in 4:
		var a3 := PI * 0.25 + k3 * PI * 0.5
		_planter(p + Vector3(cos(a3), 0.0, sin(a3)) * 17.5)
	_carriage(p + Vector3(-15.0, 0.0, 13.0), 0.9)
	_carriage(p + Vector3(18.0, 0.0, -7.0), -0.4)
	_clutter(p + Vector3(-19.0, 0.0, -8.0))
	_clutter(p + Vector3(12.0, 0.0, 18.0))
	_shrine_spot(id, p + Vector3(-14.0, 0.0, -14.0))
	_chest_spot(id, p + Vector3(15.0, 0.0, 15.0), -PI * 0.75)
	keep(p, 5.0)


func _market(r: Rect2i, id: String) -> void:
	add_obstacle("gothic_fountain", at(_rc(r).x, _rc(r).y), PI / 8.0, 0.85, 2.0, {"cutout": false})
	for row in 2:
		for col in 4:
			if row == 1 and (col == 1 or col == 2):
				continue
			var q := at(r.position.x + 5.0 + col * 7.0, r.position.y + 6.0 + row * 17.0)
			if not is_walkable_at(q) or not is_clear(q, 2.5):
				continue
			add_block("gothic_stall", q, 0.0, Vector2(3.4, 2.6), {"height": 2.6})
			add_light(q + Vector3(0.0, 2.4, 1.2), Color(1.0, 0.66, 0.34), 1.4, 6.5, true)
			add_glow(q + Vector3(0.0, 0.0, 1.8), 2.4, Color(1.0, 0.6, 0.3))
			_clutter(q + Vector3(rng.randf_range(-3.0, 3.0), 0.0, 3.2))
	_carriage(at(r.end.x - 4.0, r.position.y + 4.0), 1.4)
	_carriage(at(r.position.x + 3.5, r.end.y - 4.5), -0.3)
	_lamps_rect(r, 16.0)
	_dress_rect(r, id, 0, 4, 3)
	_chest_spot(id, at(r.end.x - 2.0, r.end.y - 2.0), -PI * 0.75)
	_chest_spot(id, at(r.position.x + 2.0, r.position.y + 2.0), PI * 0.25)


func _clock_square(r: Rect2i, id: String) -> void:
	var tower := at(_rc(r).x, r.position.y + 3.5)
	add_building("gothic_clocktower", tower, 0.0, Vector2(6.4, 6.4))
	add_light(tower + Vector3(0.0, 2.6, 4.2), LAMP_LIGHT, 2.0, 8.0, true)
	var c := at(_rc(r).x, _rc(r).y + 4.0)
	add_obstacle("gothic_statue", c, 0.0, 1.25, 1.0)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var bq := c + Vector3(cos(a), 0.0, sin(a)) * 5.0
		add_obstacle("gothic_bench", bq, _yaw_to(bq, c), 1.0, 0.5, {"cutout": false})
		_planter(c + Vector3(cos(a + PI * 0.25), 0.0, sin(a + PI * 0.25)) * 7.5)
	_lamps_rect(r, 14.0)
	_dress_rect(r, id, 0, 2, 2)
	_shrine_spot(id, at(r.position.x + 5.0, r.position.y + 5.0))
	_chest_spot(id, at(r.end.x - 3.0, r.position.y + 3.0), PI * 0.75)


func _gallows_square(c: Vector2, id: String) -> void:
	var p := at(c.x, c.y)
	add_block("gothic_gallows", p, 0.0, Vector2(4.8, 3.4), {"height": 3.0})
	for _k in 5:
		var a := rng.randf() * TAU
		add_prop("gothic_blood", p + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(3.2, 6.0), rng.randf() * TAU, rng.randf_range(0.7, 1.1), {"shadows": false})
	for k2 in 3:
		var a2 := PI * 0.3 + k2 * PI * 0.62
		var q := p + Vector3(cos(a2), 0.0, sin(a2)) * 7.5
		if is_clear(q, 1.2):
			add_obstacle("gothic_coffin", q, rng.randf() * TAU, 1.0, 0.8, {"cutout": false})
	_lamps_ring(p, 11.0, 5, 0.4)
	_dress_disc(c, 12.0, id, 2, 3)
	_carriage(p + Vector3(-15.0, 0.0, 6.0), 1.2)
	_chest_spot(id, p + Vector3(12.0, 0.0, 12.0), -PI * 0.75)


func _chapel_square(r: Rect2i, id: String) -> void:
	# The chapel's front steps on the square's north side.
	var cx := _rc(r).x
	add_building("gothic_cathedral", at(cx, r.position.y - 2.4), 0.0, Vector2(15.0, 9.9), {"scale": 0.52})
	add_light(at(cx, r.position.y + 0.8) + Vector3(0.0, 2.2, 0.0), Color(1.0, 0.62, 0.3), 1.8, 7.5, true)
	for sx in [-1.0, 1.0]:
		add_obstacle("gothic_statue", at(cx + sx * 5.5, r.position.y + 2.0), 0.0, 0.9, 0.8)
	var yard := Rect2i(int(cx) - 12, r.position.y - 13, 24, 7)
	if _block_fits(yard, id, 0):
		_garden_block(yard)
	_lamps_rect(r, 14.0)
	_dress_rect(r, id, 2, 4, 2)
	_chest_spot(id, at(r.end.x - 3.0, r.position.y + 3.0), -PI * 0.75)


func _undertakers_yard(r: Rect2i, id: String) -> void:
	add_block("gothic_crypt", at(_rc(r).x + 3.0, r.position.y + 2.8), 0.0, Vector2(4.2, 5.2), {"height": 4.0, "scale": 1.15})
	add_light(at(_rc(r).x + 3.0, r.position.y + 5.2) + Vector3(0.0, 2.0, 0.0), Color(1.0, 0.6, 0.3), 1.6, 7.0, true)
	_carriage(at(r.position.x + 5.0, r.position.y + 5.0), 0.2)
	_carriage(at(r.position.x + 12.0, r.position.y + 4.5), -0.15)
	_carriage(at(r.end.x - 5.0, r.end.y - 6.0), 1.5)
	for _k in 7:
		var q := at(rng.randf_range(r.position.x + 3.0, r.end.x - 3.0), rng.randf_range(r.position.y + 9.0, r.end.y - 2.0))
		if is_walkable_at(q) and is_clear(q, 1.4):
			add_obstacle("gothic_coffin", q, rng.randf() * TAU, 1.0, 0.8, {"cutout": false})
	_lamps_rect(r, 14.0)
	_dress_rect(r, id, 0, 2, 2)
	_chest_spot(id, at(r.end.x - 2.5, r.position.y + 2.5), PI * 0.75)
	_shrine_spot(id, at(r.position.x + 3.0, r.end.y - 3.0))


func _arrival_square(r: Rect2i, ex: Vector2i) -> void:
	for q in [Vector2(r.position.x + 1.6, r.position.y + 1.6), Vector2(r.end.x - 1.6, r.position.y + 1.6),
			Vector2(r.position.x + 1.6, r.end.y - 1.6), Vector2(r.end.x - 1.6, r.end.y - 1.6)]:
		_street_lamp(at(q.x, q.y), 6.0)
	for side in [-1.0, 1.0]:
		_planter(at(ex.x + 0.5 + side * 5.0, r.position.y + 6.0))
		_planter(at(ex.x + 0.5 + side * 5.0, r.end.y - 7.0))
	var cp := at(ex.x + 0.5 - 4.5, ex.y - 7.0)
	add_obstacle("gothic_statue", cp, 0.4, 1.2, 1.0)
	add_light(cp + Vector3(1.2, 2.0, 1.2), LAMP_LIGHT, 1.6, 7.0, true)
	_carriage(at(r.position.x + 4.0, _rc(r).y + 3.0), 0.25)
	_clutter(at(r.end.x - 3.0, r.position.y + 3.5))
	_clutter(at(r.position.x + 3.0, r.end.y - 3.0))
	_dress_rect(r, "outskirts", 2, 0, 1)


# ------------------------------------------------------------------ the Canal Quarter

func _canal_quarter() -> void:
	var id := "canals"
	set_region_pool(id, {"canal_drowned": 4.0, "maddened_townsman": 2.0, "belfry_archer": 1.5, "scourge_beast": 1.5})
	var le := _link_cell(id, "outskirts")
	var ln := _link_cell(id, "cemetery")
	var great := Rect2i(0, 160, 106, 5)
	var sluice := Rect2i(44, 165, 5, 92)
	var decks: Array = [Rect2i(68, 160, 6, 5), Rect2i(20, 160, 6, 5), Rect2i(44, 204, 5, 6)]
	var sq_e := Vector2(86.0, 194.0)
	var sq_se := Vector2(64.0, 185.0)
	var sq_sw := Vector2(25.0, 199.0)
	var sq_n := Vector2(55.0, 146.0)
	var ways: Array = [
		[Vector2(le.x, le.y + 0.5), sq_e, 11.0],
		[sq_e, Vector2(71.0, 168.0), 9.0],
		[Vector2(71.0, 158.0), sq_n, 9.0],
		[sq_n, Vector2(ln.x + 0.5, ln.y), 9.0],
		[sq_se, Vector2(51.0, 207.0), 8.0],
		[Vector2(42.0, 207.0), sq_sw, 8.0],
		[sq_sw, Vector2(23.0, 167.0), 8.0],
		[Vector2(23.0, 158.0), sq_n, 8.0],
		[sq_e, sq_se, 9.0],
	]
	for wv in ways:
		_paint_band(wv[0], wv[1], float(wv[2]), K_STREET, id)
	for sq in [sq_e, sq_se, sq_sw, sq_n]:
		_paint_disc(sq, 8.5, K_PLAZA, id)
	for d in decks:
		_paint_rect(d, K_DECK, id)
	# The canals: water between stone quays, the arched bridges over them, boats at the quays.
	_channel(great, decks, id)
	_channel(sluice, decks, id)
	for cr in [great, sluice]:
		_quays(cr, id)
		_balustrades(cr, K_WATER, -1)
		_boats(cr, decks)
		_quay_lamps(cr)
	for d2 in decks:
		var dr: Rect2i = d2
		var over_great := dr.intersects(great)
		add_prop("gothic_canal_bridge", at(_rc(dr).x, _rc(dr).y), 0.0 if over_great else PI * 0.5, 1.0, {"cutout": false})
	# Houses on the quays facing the water, then warehouse rows and townhouse blocks.
	_quay_blocks(id, great, sluice)
	_fill_blocks(id, Vector2i(6, 5), Vector2i(12, 9), Vector2i(16, 11), 4, 0.1, 0.85)
	# The squares.
	for sq2 in [sq_e, sq_se, sq_sw, sq_n]:
		_dress_disc(sq2, 8.5, id, 2, 2)
	var e := at(sq_e.x, sq_e.y)
	_lamps_ring(e, 13.0, 5, 0.2)
	for k in 3:
		_clutter(e + Vector3(-9.0 + k * 3.0, 0.0, 10.5))
	_carriage(e + Vector3(8.0, 0.0, -8.0), 1.1)
	var se := at(sq_se.x, sq_se.y)
	add_obstacle("gothic_fountain", se, PI / 8.0, 1.0, 2.4, {"cutout": false})
	_lamps_ring(se, 10.0, 4, 0.5)
	for k2 in 2:
		add_obstacle("gothic_bench", se + Vector3(-4.5 + k2 * 9.0, 0.0, 0.0), -PI * 0.5 + k2 * PI, 1.0, 0.5, {"cutout": false})
	_shrine_spot(id, se + Vector3(0.0, 0.0, -8.0))
	var sw := at(sq_sw.x, sq_sw.y)
	add_obstacle("gothic_statue", sw, 0.0, 1.1, 0.9)
	_lamps_ring(sw, 11.0, 4, 0.8)
	_chest_spot(id, sw + Vector3(8.0, 0.0, 9.0), -PI * 0.75)
	_clutter(sw + Vector3(-9.0, 0.0, 6.0))
	var nq := at(sq_n.x, sq_n.y)
	add_obstacle("gothic_statue", nq + Vector3(0.0, 0.0, 2.0), 0.0, 1.0, 0.9)
	_lamps_ring(nq, 11.0, 4, 0.0)
	_chest_spot(id, at(15.0, 151.0), PI * 0.5)
	_chest_spot(id, at(92.0, 176.0), -PI * 0.5)
	_shrine_spot(id, at(30.0, 226.0))
	for wv2 in ways:
		_lamps_along(wv2[0], wv2[1], float(wv2[2]) * 0.5 - 0.7, 16.0)
	set_region_arrival(id, at(88.5, 194.5))


## Blocks of houses right on the quays north of the Great Canal and west of the Sluice, their fronts
## to the water (the faces the camera sees across the canal).
func _quay_blocks(id: String, great: Rect2i, sluice: Rect2i) -> void:
	var y_end := great.position.y - 2
	var x := great.position.x + 1
	while x < great.end.x - 6:
		var done := false
		for w in [16, 13, 10, 8]:
			var r := Rect2i(x, y_end - 9, int(w), 9)
			if _fits_by_quay(r, id, Vector2i(0, 1)):
				_house_block(r, 0.85)
				x += int(w) + 5
				done = true
				break
		if not done:
			x += 2
	var x_end := sluice.position.x - 2
	var y := sluice.position.y + 2
	while y < sluice.end.y - 6:
		var done2 := false
		for h in [14, 11, 9]:
			var r2 := Rect2i(x_end - 10, y, 10, int(h))
			if _fits_by_quay(r2, id, Vector2i(1, 0)):
				_house_block(r2, 0.85)
				y += int(h) + 5
				done2 = true
				break
		if not done2:
			y += 2


## Like _block_fits, but the block may touch the quay on side `side`; the other sides keep 3 cells
## of street.
func _fits_by_quay(r: Rect2i, id: String, side: Vector2i) -> bool:
	var ri := _ri(id)
	var g := r.grow_individual(0 if side.x < 0 else 3, 0 if side.y < 0 else 3, 0 if side.x > 0 else 3, 0 if side.y > 0 else 3)
	if g.position.x < 0 or g.position.y < 0 or g.end.x > _W or g.end.y > _H:
		return false
	for j in range(g.position.y, g.end.y):
		for i in range(g.position.x, g.end.x):
			var k := j * _W + i
			if grid.walk[k] == 0 or region_map[k] != ri:
				return false
			if r.has_point(Vector2i(i, j)) and _open[k] == 1:
				return false
	return true


## Water in r (cells) except on the bridge decks: not walkable (a low box keeps walkers out,
## projectiles fly over), the ground dips under the water plane; the canal runs on under the town
## beyond the zone's edges.
func _channel(r: Rect2i, decks: Array, id: String) -> void:
	var ri := _ri(id)
	for j in range(maxi(r.position.y, 0), mini(r.end.y, _H)):
		for i in range(maxi(r.position.x, 0), mini(r.end.x, _W)):
			var c := Vector2i(i, j)
			var on_deck := false
			for d in decks:
				if (d as Rect2i).has_point(c):
					on_deck = true
					break
			if on_deck:
				continue
			var k := j * _W + i
			if grid.floor_cells[k] == 1:
				if region_map[k] != ri:
					continue
				grid.set_void(c)
				grid.set_opaque(c, false)
				soft[c] = true
			_kind[k] = K_WATER
			_depth[k] = CANAL_DEPTH
	# The water runs on past the grid's edge (the ground there repeats the edge cells).
	var wr := Rect2(r.position.x * TILE, r.position.y * TILE, r.size.x * TILE, r.size.y * TILE)
	if r.position.x <= 0:
		wr = wr.grow_individual(44.0, 0.0, 0.0, 0.0)
	if r.end.x >= _W:
		wr = wr.grow_individual(0.0, 0.0, 44.0, 0.0)
	if r.position.y <= 0:
		wr = wr.grow_individual(0.0, 44.0, 0.0, 0.0)
	if r.end.y >= _H:
		wr = wr.grow_individual(0.0, 0.0, 0.0, 44.0)
	water_rects.append(wr)
	_low_boxes(r, decks)


## Low collision boxes over a channel / the gorge (rect r, cells), split where the decks cross it.
func _low_boxes(r: Rect2i, decks: Array) -> void:
	var horiz := r.size.x >= r.size.y
	var cuts: Array = []
	for d in decks:
		var dr: Rect2i = d
		if dr.intersects(r):
			cuts.append([dr.position.x, dr.end.x] if horiz else [dr.position.y, dr.end.y])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var s := r.position.x if horiz else r.position.y
	var e := r.end.x if horiz else r.end.y
	var segs: Array = []
	for cu in cuts:
		if int(cu[0]) > s:
			segs.append([s, int(cu[0])])
		s = maxi(s, int(cu[1]))
	if e > s:
		segs.append([s, e])
	for sg in segs:
		var rr := Rect2i(int(sg[0]), r.position.y, int(sg[1]) - int(sg[0]), r.size.y) if horiz else Rect2i(r.position.x, int(sg[0]), r.size.x, int(sg[1]) - int(sg[0]))
		shapes.append({"type": "box", "pos": Vector3((rr.position.x + rr.size.x * 0.5) * TILE, 0.0, (rr.position.y + rr.size.y * 0.5) * TILE),
			"size": Vector3(rr.size.x * TILE, 0.9, rr.size.y * TILE), "yaw": 0.0})


## Flagstone quays two cells wide along a canal.
func _quays(r: Rect2i, id: String) -> void:
	var ri := _ri(id)
	var g := r.grow(2)
	for j in range(maxi(g.position.y, 0), mini(g.end.y, _H)):
		for i in range(maxi(g.position.x, 0), mini(g.end.x, _W)):
			var k := j * _W + i
			if grid.walk[k] == 1 and region_map[k] == ri and _kind[k] != K_DECK:
				_kind[k] = K_QUAY
				_open[k] = 1


## Stone balustrades on the land side of every edge between land and `kind` cells (water, the
## gorge) inside r, a pillar every few metres; land of kind `skip` gets none (the great bridge has
## its own parapets).
func _balustrades(r: Rect2i, kind: int, skip: int) -> void:
	for j in range(maxi(r.position.y, 0), mini(r.end.y, _H)):
		for i in range(maxi(r.position.x, 0), mini(r.end.x, _W)):
			if _kind[j * _W + i] != kind:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(i, j) + d
				if not _inb(q):
					continue
				var qk := q.y * _W + q.x
				if grid.floor_cells[qk] == 0 or int(_kind[qk]) == skip:
					continue
				var dv := Vector3(-d.x, 0.0, -d.y)
				var pos := Vector3((q.x + 0.5) * TILE, 0.0, (q.y + 0.5) * TILE) + dv * (TILE * 0.5 - 0.22)
				add_prop("gothic_balustrade", pos, 0.0 if d.x == 0 else PI * 0.5, 1.0)
				if (q.x * 7 + q.y * 3) % 4 == 0:
					var tv := Vector3(1.0, 0.0, 0.0) if d.x == 0 else Vector3(0.0, 0.0, 1.0)
					add_prop("gothic_pillar", pos + tv * (TILE * 0.5), 0.0, 0.6)


## Boats moored along a canal, alternating banks, clear of the bridges.
func _boats(r: Rect2i, decks: Array) -> void:
	var horiz := r.size.x >= r.size.y
	var along := r.size.x if horiz else r.size.y
	var k := 3
	var side := 1.0
	while k < along - 3:
		var c := Vector2i(r.position.x + k, r.position.y + r.size.y / 2) if horiz else Vector2i(r.position.x + r.size.x / 2, r.position.y + k)
		var near_deck := false
		for d in decks:
			if (d as Rect2i).grow(4).has_point(c):
				near_deck = true
		if not near_deck and _inb(c) and region_map[c.y * _W + c.x] > 0:
			var off := (r.size.y if horiz else r.size.x) * 0.5 * TILE - 2.4
			var mid := Vector3((r.position.x + (k + 0.5 if horiz else r.size.x * 0.5)) * TILE, WATER_Y - 0.04,
				(r.position.y + (r.size.y * 0.5 if horiz else k + 0.5)) * TILE)
			var pos := mid + (Vector3(0.0, 0.0, off * side) if horiz else Vector3(off * side, 0.0, 0.0))
			var yaw := (PI * 0.5 if horiz else 0.0) + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.08, 0.08)
			add_prop("gothic_boat", pos, yaw, rng.randf_range(0.92, 1.05), {"shadows": false})
			side = -side
		k += rng.randi_range(8, 13)


## Lamps along both quays of a canal.
func _quay_lamps(r: Rect2i) -> void:
	var horiz := r.size.x >= r.size.y
	var along := r.size.x if horiz else r.size.y
	for k in range(2, along - 2, 7):
		for side in [-1, 1]:
			var pos: Vector3
			if horiz:
				pos = at(r.position.x + k + 0.5, (r.position.y - 0.6) if side < 0 else (r.end.y + 0.6))
			else:
				pos = at((r.position.x - 0.6) if side < 0 else (r.end.x + 0.6), r.position.y + k + 0.5)
			_street_lamp(pos, 11.0)


# ------------------------------------------------------------------ Ashgrove Cemetery

func _cemetery() -> void:
	var id := "cemetery"
	set_region_pool(id, {"crypt_ghoul": 3.0, "shroud_widow": 2.0, "blood_acolyte": 1.5, "maddened_townsman": 1.0})
	for c in region_cells(id):
		var cc: Vector2i = c
		var k := cc.y * _W + cc.x
		if grid.walk[k] == 1:
			_kind[k] = K_GRASS
	var ls := _link_cell(id, "canals")
	var le := _link_cell(id, "bridge")
	var cross := Vector2(ls.x + 0.5, 62.0)
	var top := Vector2(ls.x + 0.5, 37.0)
	# Old flagstone paths: from the canal gate up to the mausoleum, across from the west wall to the
	# bridge gate, lanes round the plots.
	_paint_band(Vector2(ls.x + 0.5, ls.y + 1.0), top, 5.0, K_PATH, id)
	_paint_band(Vector2(8.0, cross.y), Vector2(le.x + 1.0, le.y + 0.5), 5.0, K_PATH, id)
	_paint_disc(cross, 7.5, K_PATH, id)
	_paint_disc(top, 6.0, K_PATH, id)
	for x in [21.5, 92.5]:
		_paint_band(Vector2(x, 34.0), Vector2(x, 96.0), 3.0, K_PATH, id)
	for y in [45.5, 80.5]:
		_paint_band(Vector2(6.0, y), Vector2(112.0, y), 3.0, K_PATH, id)
	# The Ashgrove Mausoleum at the head of the main path.
	add_building("gothic_crypt", at(top.x, top.y - 6.2), 0.0, Vector2(9.2, 11.4), {"scale": 2.2, "height": 6.0})
	add_light(at(top.x, top.y - 0.6) + Vector3(0.0, 2.0, 0.0), Color(0.8, 0.9, 1.0), 1.4, 7.0, true)
	# Mausoleums along the main path, facing it.
	var y0 := 44
	while y0 < 100:
		for side in [-1.0, 1.0]:
			var q := at(ls.x + 0.5 + side * 5.4, y0 + 0.5)
			if _cells_are(world_to_cell(q), 2, K_GRASS) and is_clear(q, 3.2):
				add_block("gothic_crypt", q, -PI * 0.5 * side, Vector2(4.2, 5.2), {"height": 4.0})
		y0 += 9
	# Plots between the paths: fenced family plots, groves, lawns with a statue; rows of graves over
	# the rest of the grass (a gap every few graves), dead trees here and there.
	var bb: Array = get_region(id)["bbox"]
	var py := int(bb[1]) + 2
	while py < int(bb[3]) - 6:
		var px := int(bb[0]) + 2
		while px < int(bb[2]) - 10:
			var pr := Rect2i(px, py, 12, 8)
			var roll := rng.randf()
			if roll < 0.5 and _plot_fits(pr, id):
				if roll < 0.24:
					_family_plot(pr, id)
				elif roll < 0.4:
					_grove(pr)
				else:
					_lawn(pr)
			px += 16
		py += 11
	var j0 := int(bb[1]) + 1
	while j0 <= int(bb[3]):
		for i0 in range(int(bb[0]), int(bb[2]) + 1):
			var c0 := Vector2i(i0, j0)
			if not _inb(c0) or (i0 + j0 * 3) % 5 == 0 or rng.randf() < 0.42:
				continue
			var k0 := j0 * _W + i0
			if _kind[k0] != K_GRASS or grid.walk[k0] == 0 or _open[k0] == 1:
				continue
			if _kind_of(c0 + Vector2i(1, 0)) == K_PATH or _kind_of(c0 - Vector2i(1, 0)) == K_PATH \
					or _kind_of(c0 + Vector2i(0, 1)) == K_PATH or _kind_of(c0 - Vector2i(0, 1)) == K_PATH:
				continue
			if not is_clear(cell_center(c0), 0.5):
				continue
			if rng.randf() < 0.06:
				add_obstacle("gothic_dead_tree", cell_center(c0), rng.randf() * TAU, rng.randf_range(0.8, 1.2), 0.45)
			else:
				_grave(c0)
		j0 += 3
	# The crossing: a statue, lamps; lamps along the main paths.
	var cp := at(cross.x, cross.y)
	add_obstacle("gothic_statue", cp, 0.0, 1.3, 1.1)
	_lamps_ring(cp, 8.0, 4, PI * 0.25)
	_lamps_along(Vector2(ls.x + 0.5, ls.y), top, 2.6, 22.0)
	_lamps_along(Vector2(8.0, cross.y), Vector2(le.x, le.y + 0.5), 2.6, 22.0)
	_shrine_spot(id, cp + Vector3(9.0, 0.0, 9.0))
	_chest_spot(id, at(top.x + 4.0, top.y + 1.0), -PI * 0.5)
	_chest_spot(id, at(10.0, cross.y + 0.5), PI * 0.5)
	set_region_arrival(id, at(ls.x + 0.5, ls.y - 20.0))


## True if every cell within r (Chebyshev) of c is walkable, of `kind` and not kept open.
func _cells_are(c: Vector2i, r: int, kind: int) -> bool:
	for j in range(c.y - r, c.y + r + 1):
		for i in range(c.x - r, c.x + r + 1):
			var q := Vector2i(i, j)
			if not _inb(q):
				return false
			var k := j * _W + i
			if grid.walk[k] == 0 or _kind[k] != kind or _open[k] == 1:
				return false
	return true


func _plot_fits(r: Rect2i, id: String) -> bool:
	var ri := _ri(id)
	var g := r.grow(1)
	for j in range(g.position.y, g.end.y):
		for i in range(g.position.x, g.end.x):
			if not _inb(Vector2i(i, j)):
				return false
			var k := j * _W + i
			if region_map[k] != ri or grid.walk[k] == 0 or _kind[k] != K_GRASS or _open[k] == 1:
				return false
	return true


## A grave on cell c (blocks it); now and then a candle glow.
func _grave(c: Vector2i) -> void:
	var p := cell_center(c) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.25, 0.1))
	add_prop("gothic_grave_a" if rng.randf() < 0.45 else "gothic_grave_b", p, rng.randf_range(-0.12, 0.12), rng.randf_range(0.9, 1.1))
	grid.walk[c.y * _W + c.x] = 0
	keep(p, 0.6)
	if rng.randf() < 0.12:
		add_glow(p + Vector3(0.0, 0.0, -0.3), 0.9, Color(1.0, 0.62, 0.3))


## A fenced family plot: iron fence round a crypt and a few graves (not walkable).
func _family_plot(r: Rect2i, id: String) -> void:
	var inner := Rect2i(r.position.x + 2, r.position.y + 1, r.size.x - 4, r.size.y - 2)
	_block_cells(inner, false, K_GRASS)
	_fence_rect(inner)
	var c := _rc(inner)
	add_prop("gothic_crypt", at(c.x, c.y - 0.3), 0.0, 1.0, {"cutout": true})
	for k in 4:
		var q := at(inner.position.x + 1.0 + (inner.size.x - 2.0) * (k % 2), inner.position.y + 1.2 + (inner.size.y - 2.4) * (k / 2))
		add_prop("gothic_grave_a" if rng.randf() < 0.5 else "gothic_grave_b", q, rng.randf_range(-0.15, 0.15), 0.95)
	_chest_spot(id, at(c.x + 3.0, inner.end.y + 1.0), 0.0)


## A grove: dead trees and a few leaning graves.
func _grove(r: Rect2i) -> void:
	for _k in rng.randi_range(4, 6):
		var c := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
		var p := cell_center(c) + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
		if is_clear(p, 1.6):
			add_obstacle("gothic_dead_tree", p, rng.randf() * TAU, rng.randf_range(0.85, 1.3), 0.45)
	for _k2 in 4:
		var c2 := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		if grid.walk[c2.y * _W + c2.x] == 1 and is_clear(cell_center(c2), 0.8):
			_grave(c2)


## A lawn with a hooded statue and a bench.
func _lawn(r: Rect2i) -> void:
	var c := _rc(r)
	var p := at(c.x, c.y)
	add_obstacle("gothic_statue", p, 0.0, 1.0, 0.9)
	add_obstacle("gothic_bench", p + Vector3(0.0, 0.0, 3.2), PI, 1.0, 0.5, {"cutout": false})
	_street_lamp(p + Vector3(3.5, 0.0, 2.0), 8.0)


# ------------------------------------------------------------------ Blackmoor Bridge

func _blackmoor_bridge() -> void:
	var id := "bridge"
	set_region_pool(id, {"bridge_sentinel": 3.0, "belfry_archer": 2.0, "scourge_beast": 2.0, "church_giant": 1.0})
	var ls := _link_cell(id, "outskirts")
	var lw := _link_cell(id, "cemetery")
	var la := _link_cell(id, "abbey")
	var g0 := 226
	var g1 := 246
	var deck := Rect2i(g0 - 4, 53, g1 - g0 + 8, 7)
	var head_w := Rect2i(199, 46, 22, 22)
	var head_e := Rect2i(g1 + 4, 47, 18, 20)
	var ways: Array = [
		[Vector2(ls.x + 0.5, ls.y), Vector2(ls.x + 2.0, head_w.end.y - 2.0), 11.0],
		[Vector2(lw.x, lw.y + 0.5), Vector2(head_w.position.x + 2.0, _rc(head_w).y), 10.0],
		[Vector2(head_e.end.x - 2.0, _rc(head_e).y), Vector2(la.x, la.y + 0.5), 11.0],
	]
	for wv in ways:
		_paint_band(wv[0], wv[1], float(wv[2]), K_STREET, id)
	_paint_rect(head_w, K_PLAZA, id)
	_paint_rect(head_e, K_PLAZA, id)
	_paint_rect(deck, K_DECK, id)
	# The gorge, the great bridge over it: statues and lamps on its parapets, towers at its ends.
	_gorge(g0, g1, deck, id)
	_balustrades(Rect2i(g0, 0, g1 - g0, _H), K_CHASM, -1)
	var bc := at((g0 + g1) * 0.5, _rc(deck).y)
	add_prop("gothic_great_bridge", bc, 0.0, 1.0, {"cutout": false})
	var half := deck.size.y * TILE * 0.5
	for xo in [-15.0, -5.0, 5.0, 15.0]:
		for side in [-1.0, 1.0]:
			var sp := Vector3(bc.x + float(xo), 0.0, bc.z + float(side) * (half + 0.9))
			add_prop("gothic_statue", sp, 0.0 if float(side) < 0.0 else PI, 0.8, {"cutout": true})
	for x2 in [-20.0, -10.0, 0.0, 10.0, 20.0]:
		for side2 in [-1.0, 1.0]:
			var lp := Vector3(bc.x + x2, 0.0, bc.z + side2 * (half + 0.8))
			add_prop("gothic_lamp", lp, PI * 0.5, 1.0, {"shadows": true})
			add_light(lp + Vector3(0.0, 2.75, -side2 * 0.6), LAMP_LIGHT, 3.2, 10.5, true)
			add_glow(Vector3(lp.x, 0.0, bc.z + side2 * (half - 2.4)), 2.4, Color(1.0, 0.6, 0.28))
	for tx in [g0 - 1.5, g1 + 1.5]:
		for ty in [deck.position.y - 1.6, deck.end.y + 1.6]:
			var tp := at(tx, ty)
			add_building("gothic_bridge_tower", tp, 0.0 if ty < deck.position.y else PI, Vector2(5.6, 5.6), {"height": 6.0})
			add_light(tp + Vector3(0.0, 4.2, 2.6 if ty < deck.position.y else -2.6), LAMP_LIGHT, 2.2, 9.0, true)
	for sk in 3:
		add_shaft(Vector3(bc.x + rng.randf_range(-12.0, 12.0), GORGE_DEPTH + 3.0, (18.0 + sk * 11.0) * TILE), 34.0, 7.0, Color(0.62, 0.74, 0.9), rng.randf() * TAU, 10.0)
	# Townhouse blocks (and ruined gardens) on both banks.
	_fill_blocks(id, Vector2i(6, 5), Vector2i(12, 9), Vector2i(17, 12), 4, 0.25, 0.75)
	# The squares at the bridge heads.
	var hw := at(_rc(head_w).x, _rc(head_w).y)
	add_obstacle("gothic_statue", hw, PI * 0.5, 1.5, 1.2)
	_lamps_rect(head_w, 14.0)
	_dress_rect(head_w, id, 2, 4, 2)
	_carriage(hw + Vector3(-12.0, 0.0, 12.0), 0.5)
	_clutter(hw + Vector3(-14.0, 0.0, -14.0))
	_shrine_spot(id, hw + Vector3(-9.0, 0.0, -12.0))
	_chest_spot(id, at(head_w.position.x + 2.0, head_w.end.y - 2.0), PI * 0.25)
	var he := at(_rc(head_e).x, _rc(head_e).y)
	add_obstacle("gothic_statue", he + Vector3(4.0, 0.0, 0.0), -PI * 0.5, 1.2, 1.0)
	_lamps_rect(head_e, 14.0)
	_dress_rect(head_e, id, 2, 2, 1)
	_chest_spot(id, at(head_e.end.x - 2.0, head_e.position.y + 2.0), -PI * 0.75)
	_chest_spot(id, at(170.0, 40.0), 0.0)
	for wv2 in ways:
		_lamps_along(wv2[0], wv2[1], float(wv2[2]) * 0.5 - 0.7, 16.0)
	set_region_arrival(id, at(ls.x + 0.5, ls.y - 18.0))


## The gorge: cells g0..g1 (x) through the zone and on north beyond it (not walkable, deep), closing
## south of the zone; the deck crosses it. Low boxes keep walkers off it.
func _gorge(g0: int, g1: int, deck: Rect2i, id: String) -> void:
	var ri := _ri(id)
	for j in _H:
		var fade := 1.0 - smoothstep(92.0, 118.0, float(j))
		if fade <= 0.0:
			break
		for i in range(maxi(g0 - 1, 0), mini(g1 + 1, _W)):
			var din := minf(i + 0.5 - g0, g1 - (i + 0.5))
			if din <= 0.0:
				continue
			var c := Vector2i(i, j)
			if deck.has_point(c):
				continue
			var k := j * _W + i
			if grid.floor_cells[k] == 1:
				if region_map[k] != ri:
					continue
				grid.set_void(c)
				grid.set_opaque(c, false)
				soft[c] = true
			_kind[k] = K_CHASM
			_depth[k] = GORGE_DEPTH * smoothstep(0.0, 3.5, din) * fade
	var bb: Array = get_region(id)["bbox"]
	_low_boxes(Rect2i(g0, int(bb[1]), g1 - g0, int(bb[3]) - int(bb[1]) + 1), [Rect2i(0, deck.position.y, _W, deck.size.y)])


# ------------------------------------------------------------------ the Abbey Grounds

func _abbey_grounds() -> void:
	var id := "abbey"
	set_region_pool(id, {"abbey_flagellant": 3.0, "church_servant": 2.0, "blood_acolyte": 2.0, "church_giant": 1.5})
	var lw := _link_cell(id, "bridge")
	var door := dungeon_door()
	var dc := world_to_cell(door["pos"])
	var dv: Vector2i = door["dir"]
	var fore := Rect2i(327, 31, 36, 19)
	var yard_c := Vector2(dc.x - 9.5, dc.y + 0.5)
	var garth := Rect2i(362, 17, 14, 12)
	var way_a := Vector2(lw.x, lw.y + 0.5)
	var way_b := Vector2(fore.position.x + 6.0, fore.end.y - 1.0)
	var way_c := Vector2(fore.end.x - 2.0, fore.end.y - 2.0)
	# The pilgrims' way from the bridge gate to the forecourt, on to the undercroft's yard.
	_paint_band(way_a, way_b, 9.0, K_PLAZA, id)
	_paint_rect(fore, K_PLAZA, id)
	_paint_band(way_c, yard_c, 8.0, K_PLAZA, id)
	_paint_disc(yard_c, 10.0, K_PLAZA, id)
	# Graveyards (grass).
	var gy: Array = [Rect2i(300, 69, 30, 29), Rect2i(347, 67, 36, 29), Rect2i(326, 8, 30, 10)]
	for g in gy:
		_paint_rect(g, K_GRASS, id, false)
	# The abbey church, its front steps onto the forecourt.
	add_building("gothic_cathedral", at(345.0, 24.6), 0.0, Vector2(28.0, 18.4))
	add_light(at(345.0, 30.6) + Vector3(0.0, 2.4, 0.0), Color(1.0, 0.5, 0.3), 2.2, 9.0, true)
	for sx in [-1.0, 1.0]:
		add_obstacle("gothic_statue", at(345.0 + sx * 7.5, fore.position.y + 1.8), 0.0, 1.1, 0.9)
	_dress_rect(fore, id, 2, 0, 0)
	for gx in [fore.position.x + 2, fore.end.x - 10]:
		var plot := Rect2i(gx, fore.position.y + 6, 8, 7)
		_block_cells(plot, false, K_GRASS)
		_railing_line(at(plot.position.x, plot.position.y), at(plot.end.x, plot.position.y))
		_railing_line(at(plot.position.x, plot.end.y), at(plot.end.x, plot.end.y))
		_railing_line(at(plot.position.x, plot.position.y + 1), at(plot.position.x, plot.end.y - 1))
		_railing_line(at(plot.end.x, plot.position.y + 1), at(plot.end.x, plot.end.y - 1))
		for gj in range(plot.position.y + 1, plot.end.y - 1, 2):
			for gi in range(plot.position.x + 1, plot.end.x - 1):
				if rng.randf() < 0.6:
					add_prop("gothic_grave_a" if rng.randf() < 0.5 else "gothic_grave_b", cell_center(Vector2i(gi, gj)), rng.randf_range(-0.15, 0.15), 0.95)
		add_prop("gothic_dead_tree", at(plot.position.x + 4.0, plot.position.y + 3.5), rng.randf() * TAU, 0.9, {"cutout": true})
	# The cloister east of it: arcades round a grass garth with a well, a gate in the south range.
	_cloister(garth, id)
	# Braziers along the way and round the forecourt and the yard.
	var dist := way_a.distance_to(way_b) * TILE
	var u := (way_b - way_a).normalized()
	var t := Vector2(-u.y, u.x)
	var s := 6.0
	while s < dist - 4.0:
		var m := way_a + u * (s / TILE)
		for side in [-1.0, 1.0]:
			var q: Vector2 = m + t * 5.2 * side
			_brazier(at(q.x, q.y))
		s += 14.0
	for q2 in [Vector2(fore.position.x + 1.5, fore.position.y + 1.5), Vector2(fore.end.x - 1.5, fore.position.y + 1.5),
			Vector2(fore.position.x + 1.5, fore.end.y - 1.5), Vector2(fore.end.x - 1.5, fore.end.y - 1.5)]:
		_brazier(at(q2.x, q2.y))
	var yc := at(yard_c.x, yard_c.y)
	for k in 4:
		var ya := PI * 0.62 + k * PI * 0.25
		_brazier(yc + Vector3(cos(ya), 0.0, sin(ya)) * 8.0)
	# The Abbey Undercroft (the act's dungeon) by the east wall, its portal turned south: the camera
	# looks north-west, so a door facing west (the way in) would only ever show its back. The
	# Undertaker waits before it.
	var dpos: Vector3 = door["pos"]
	var epos := dpos + Vector3(-5.0, 0.0, -4.5)
	var eyaw := 0.0
	add_dungeon_entrance(epos, eyaw, "gothic_undercroft", Vector2(8.0, 5.0))
	for sd in [-1.0, 1.0]:
		var sp := epos + Basis(Vector3.UP, eyaw) * Vector3(sd * 5.6, 0.0, 3.2)
		add_obstacle("gothic_statue", sp, eyaw, 1.0, 0.9)
		add_light(sp + Basis(Vector3.UP, eyaw) * Vector3(0.0, 2.2, 1.6), FIRE_LIGHT, 2.0, 8.0, true)
	add_zone_boss(dpos - Vector3(dv.x, 0.0, dv.y) * 20.0)
	add_chest(epos + Vector3(-6.4, 0.0, 4.0), PI * 0.25, 2)
	for _k2 in 6:
		var a2 := rng.randf() * TAU
		add_prop("gothic_blood", yc + Vector3(cos(a2), 0.0, sin(a2)) * rng.randf_range(2.0, 8.0), rng.randf() * TAU, rng.randf_range(0.8, 1.2), {"shadows": false})
	# Graveyards and a few monastery blocks.
	for g2 in gy:
		var gr: Rect2i = g2
		var j := gr.position.y + 1
		while j < gr.end.y - 1:
			var run := 0
			for i in range(gr.position.x + 1, gr.end.x - 1):
				run += 1
				if run % 5 == 0:
					continue
				var c := Vector2i(i, j)
				var k3 := j * _W + i
				if _inb(c) and grid.walk[k3] == 1 and _kind[k3] == K_GRASS and rng.randf() < 0.7 and is_clear(cell_center(c), 0.5):
					if rng.randf() < 0.1:
						add_obstacle("gothic_dead_tree", cell_center(c), rng.randf() * TAU, rng.randf_range(0.8, 1.15), 0.45)
					else:
						_grave(c)
			j += 3
	_chest_spot(id, at(302.0, 70.0), PI * 0.25)
	_chest_spot(id, at(383.0, 88.0), -PI * 0.75)
	_shrine_spot(id, at(_rc(fore).x - 6.0, fore.end.y - 2.5))
	_shrine_spot(id, at(way_a.x + 16.0, way_a.y + 3.5))
	_fill_blocks(id, Vector2i(6, 5), Vector2i(12, 9), Vector2i(16, 11), 4, 0.2, 0.85)
	_lamps_along(way_c, yard_c, 3.2, 12.0)
	set_region_arrival(id, at(lw.x + 11.0, lw.y + 0.5))


## The cloister: arcades (not walkable) round a grass garth, a gate in the south range, a well,
## graves and a chest in the garth.
func _cloister(garth: Rect2i, id: String) -> void:
	var ring := garth.grow(2)
	var gate := Rect2i(int(_rc(garth).x) - 2, garth.end.y, 4, 2)
	for j in range(ring.position.y, ring.end.y):
		for i in range(ring.position.x, ring.end.x):
			var c := Vector2i(i, j)
			var k := j * _W + i
			if garth.has_point(c):
				_kind[k] = K_GRASS
				_open[k] = 1
			elif gate.has_point(c):
				_kind[k] = K_PLAZA
				_open[k] = 1
			else:
				grid.walk[k] = 0
				grid.opaque[k] = 1
				_kind[k] = K_BLOCK
	# Arcade pieces (4 m) facing the garth.
	for x in range(garth.position.x + 1, garth.end.x, 2):
		add_prop("gothic_arcade", at(x, ring.position.y + 1.0), 0.0, 1.0, {"cutout": true})
		if not (x >= gate.position.x and x <= gate.end.x):
			add_prop("gothic_arcade", at(x, ring.end.y - 1.0), PI, 1.0, {"cutout": true})
	for y in range(garth.position.y + 1, garth.end.y, 2):
		add_prop("gothic_arcade", at(ring.position.x + 1.0, y), PI * 0.5, 1.0, {"cutout": true})
		add_prop("gothic_arcade", at(ring.end.x - 1.0, y), -PI * 0.5, 1.0, {"cutout": true})
	for cx in [ring.position.x + 1.0, ring.end.x - 1.0]:
		for cy in [ring.position.y + 1.0, ring.end.y - 1.0]:
			add_prop("gothic_pillar", at(cx, cy), 0.0, 1.5)
	for gx in [gate.position.x, gate.end.x]:
		add_prop("gothic_pillar", at(gx, gate.end.y), 0.0, 1.2)
	var gc := at(_rc(garth).x, _rc(garth).y)
	add_obstacle("gothic_fountain", gc, PI / 8.0, 0.75, 1.8, {"cutout": false})
	for _k2 in 5:
		var c2 := Vector2i(rng.randi_range(garth.position.x + 1, garth.end.x - 2), rng.randi_range(garth.position.y + 1, garth.end.y - 2))
		if cell_center(c2).distance_to(gc) > 3.5 and is_clear(cell_center(c2), 0.8):
			_grave(c2)
	add_chest(gc + Vector3(0.0, 0.0, -5.0), 0.0, 1)
	_street_lamp(gc + Vector3(5.0, 0.0, 4.0), 6.0)


# ------------------------------------------------------------------ gateways between the zones

## A gateway where each path crosses between two zones: gate pillars with an iron arch over the
## middle of the path (10 m), iron fences from them to the path's sides, lanterns.
func _gateways() -> void:
	for l in layout_data.get("links", []):
		var at_: Array = l["at"]
		var c := world_to_cell(Vector3((float(at_[0]) + 0.5) * TILE, 0.0, (float(at_[1]) + 0.5) * TILE))
		if not is_walkable_cell(c):
			continue
		var along := Vector2i(1, 0) if _run(c, Vector2i(1, 0)) > _run(c, Vector2i(0, 1)) else Vector2i(0, 1)
		var across := Vector2i(along.y, along.x)
		var lo := c
		while is_walkable_cell(lo - across) and (lo - c).length() < 30:
			lo -= across
		var hi := c
		while is_walkable_cell(hi + across) and (hi - c).length() < 30:
			hi += across
		var width := (hi.x - lo.x) + (hi.y - lo.y) + 1
		var mid := lo + across * (width / 2)
		var yaw := 0.0 if across.x != 0 else PI * 0.5
		var s_lo := (width / 2) - 2
		var s_hi := (width / 2) + 2
		for s in width:
			var cc := lo + across * s
			if s >= s_lo and s <= s_hi:
				_open[cc.y * _W + cc.x] = 1
				continue
			block_cell(cc, false, false)
			add_prop("gothic_fence", cell_center(cc), yaw, 1.0)
			if s == 0 or s == width - 1 or s % 3 == 0:
				add_prop("gothic_pillar", cell_center(cc) - Vector3(across.x, 0, across.y) * TILE * 0.5, 0.0, 0.9)
		var gp := cell_center(mid)
		add_prop("gothic_gate", gp, yaw, 1.0, {"cutout": true})
		add_light(gp + Vector3(0.0, 6.2, 0.0), LAMP_LIGHT, 3.0, 12.0, true)
		add_glow(gp, 4.0, Color(1.0, 0.6, 0.28))
		keep(gp, 5.2)
		for d in [-1, 1]:
			for s2 in range(1, 6):
				var oc: Vector2i = mid + along * (int(d) * s2)
				for w2 in range(-2, 3):
					var q: Vector2i = oc + across * w2
					if _inb(q):
						_open[q.y * _W + q.x] = 1


## Walkable cells in a row through c along dir (both ways, up to 40).
func _run(c: Vector2i, dir: Vector2i) -> int:
	var n := 1
	for sgn in [-1, 1]:
		var q := c
		for _s in 40:
			q += dir * int(sgn)
			if not is_walkable_cell(q):
				break
			n += 1
	return n


# ------------------------------------------------------------------ edges of the zones

## Rows of houses (walls of crypts in the cemetery) just outside the zones' north / west / side
## edges, facing in, a second row of tall terraces behind; the south-east edges, where a house
## would stand between the camera and the player, are left to the iron fences of border_style().
func _edge_rows() -> void:
	for r in regions:
		var id := String(r["id"])
		var style := "crypts" if id == "cemetery" else ("abbey" if id == "abbey" else "town")
		var cen := Vector2(float(r["centroid"][0]) + 0.5, float(r["centroid"][1]) + 0.5)
		var rim := _rim_cells(id)
		rim.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return atan2(a.y + 0.5 - cen.y, a.x + 0.5 - cen.x) < atan2(b.y + 0.5 - cen.y, b.x + 0.5 - cen.x))
		var piece := _pick_piece(style)
		for c in rim:
			var n := _outward(c)
			if n == Vector2.ZERO or n.dot(CAM_DIR) > -0.1:
				continue
			var res := _edge_piece(c, n, piece, style == "town")
			if res != 0:
				piece = _pick_piece(style)


## The town beyond the zones: blocks of roofs on a jittered lattice over the open ground well away
## from the zones (the overview and the far camera see them; the edge rows hide them up close).
func _outer_roofs() -> void:
	var lo := ground_rect.position
	var hi := ground_rect.end
	var z := lo.y + 9.0
	var row := 0
	while z < hi.y - 7.0:
		var x := lo.x + 13.0 + (13.0 if row % 2 == 1 else 0.0)
		while x < hi.x - 12.0:
			var p := Vector2(x + rng.randf_range(-3.0, 3.0), z + rng.randf_range(-2.0, 2.0))
			if _far_from_zones(p, 26.0):
				add_prop("gothic_roofs", Vector3(p.x, 0.0, p.y), 0.0 if rng.randf() < 0.5 else PI, rng.randf_range(0.95, 1.12),
					{"shadows": false, "vary": 0.12})
			x += 27.0
		z += 17.0
		row += 1


## True if no zone ground, water or gorge lies within r m of p (sampled on rings).
func _far_from_zones(p: Vector2, r: float) -> bool:
	for k in 12:
		var a := TAU * k / 12.0
		for rr in [0.0, r * 0.5, r]:
			var q: Vector2 = p + Vector2(cos(a), sin(a)) * float(rr)
			var c := Vector2i(floori(q.x / TILE), floori(q.y / TILE))
			if not _inb(c):
				continue
			var k2 := c.y * _W + c.x
			if grid.floor_cells[k2] == 1 or _kind[k2] != K_VOID:
				return false
	return true


## Land cells of a zone next to open ground outside all zones.
func _rim_cells(id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in region_cells(id):
		var cc: Vector2i = c
		if grid.floor_cells[cc.y * _W + cc.x] == 0:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = cc + d
			if not _inb(q):
				out.append(cc)
				break
			var qk := q.y * _W + q.x
			if grid.floor_cells[qk] == 0 and _kind[qk] == K_VOID and not soft.has(q):
				out.append(cc)
				break
	return out


## Unit vector from a rim cell out of the zone (towards the open ground around it).
func _outward(c: Vector2i) -> Vector2:
	var s := Vector2.ZERO
	for dj in range(-2, 3):
		for di in range(-2, 3):
			var q := Vector2i(c.x + di, c.y + dj)
			if not _inb(q):
				s += Vector2(di, dj)
				continue
			var k := q.y * _W + q.x
			if grid.floor_cells[k] == 0 and _kind[k] == K_VOID:
				s += Vector2(di, dj)
	return s.normalized() if s.length() > 0.5 else Vector2.ZERO


## [id, width, depth, setback from the edge, min scale, max scale].
func _pick_piece(style: String) -> Array:
	var r := rng.randf()
	match style:
		"crypts":
			if r < 0.6:
				return ["gothic_crypt", 4.4, 5.4, 1.7, 0.95, 1.2]
			return ["gothic_dead_tree", 3.0, 3.0, 2.2, 0.85, 1.25]
		"abbey":
			if r < 0.6:
				return [String(TERRACES[rng.randi_range(0, 1)]), 12.0, 6.0, 0.3, 1.0, 1.12]
			if r < 0.85:
				return ["gothic_crypt", 4.4, 5.4, 1.7, 1.0, 1.25]
			return ["gothic_dead_tree", 3.0, 3.0, 2.2, 0.9, 1.3]
	if r < 0.68:
		return [String(TERRACES[rng.randi_range(0, 1)]), 12.0, 6.0, 0.3, 1.0, 1.1]
	if r < 0.9:
		return [String(HOUSES_WIDE[rng.randi_range(0, 2)]), 5.8, 5.6, 0.3, 1.0, 1.1]
	return [HOUSE_NARROW, 3.9, 5.6, 0.3, 1.0, 1.1]


## Place `piece` outside rim cell c (facing in): 1 = placed, 0 = overlaps a placed one (try the
## same piece further on), 2 = does not fit here.
func _edge_piece(c: Vector2i, n: Vector2, piece: Array, backdrop: bool) -> int:
	var t := Vector2(-n.y, n.x)
	var sc := rng.randf_range(float(piece[4]), float(piece[5]))
	var w := float(piece[1]) * sc
	var d := float(piece[2]) * sc
	var edge := Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE) + n * (TILE * 0.5)
	var centre := edge + n * (float(piece[3]) + d * 0.5)
	if _bld_overlaps(centre, t, w):
		return 0
	if not _footprint_free(centre, t, n, w, d):
		return 2
	var id := String(piece[0])
	var yaw := atan2(-n.x, -n.y)
	if id != "gothic_dead_tree" and _occludes(Vector3(centre.x, 0.0, centre.y), yaw, w, d, OCCLUDE_M if id != "gothic_crypt" else 4.5):
		return 2
	if id == "gothic_dead_tree":
		add_prop(id, Vector3(centre.x, 0.0, centre.y), rng.randf() * TAU, sc, {"cutout": true})
	else:
		_building(id, Vector3(centre.x, 0.0, centre.y), yaw, sc)
	_bld_add(centre, t, w)
	if backdrop and w > 5.0 and rng.randf() < 0.55:
		var sc2 := rng.randf_range(1.05, 1.25)
		var w2 := 12.0 * sc2
		var d2 := 6.0 * sc2
		var c2 := centre + n * (d * 0.5 + 2.5 + d2 * 0.5) + t * rng.randf_range(-2.0, 2.0)
		if not _bld_overlaps(c2, t, w2) and _footprint_free(c2, t, n, w2, d2):
			add_prop(String(TERRACES[rng.randi_range(0, 1)]), Vector3(c2.x, 0.0, c2.y), yaw, sc2, {"cutout": true, "shadows": false, "vary": 0.12})
			_bld_add(c2, t, w2)
	return 1


## True if a w x d footprint (centre, along t / n) stays on open ground outside the zones.
func _footprint_free(centre: Vector2, t: Vector2, n: Vector2, w: float, d: float) -> bool:
	for su in [-0.5, 0.0, 0.5]:
		for sv in [-0.5, 0.0, 0.5]:
			var p: Vector2 = centre + t * (float(su) * (w - 1.2)) + n * (float(sv) * (d - 1.0))
			var q := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
			if not _inb(q):
				continue
			var k := q.y * _W + q.x
			if grid.floor_cells[k] == 1 or _kind[k] != K_VOID:
				return false
	return true


## A building's footprint as discs along its width (edge rows only).
func _bld_discs(centre: Vector2, t: Vector2, w: float) -> Array:
	var n := maxi(1, roundi(w / 6.0))
	var out: Array = []
	for k in n:
		out.append([centre + t * ((k - (n - 1) * 0.5) * (w / n)), w / n * 0.5])
	return out


func _bld_overlaps(centre: Vector2, t: Vector2, w: float) -> bool:
	for dsc in _bld_discs(centre, t, w):
		var p: Vector2 = dsc[0]
		var r := float(dsc[1])
		var b := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for e in _bld_hash.get(b + Vector2i(di, dj), []):
					if (e[0] as Vector2).distance_to(p) < (float(e[1]) + r) * 0.9:
						return true
	return false


func _bld_add(centre: Vector2, t: Vector2, w: float) -> void:
	for dsc in _bld_discs(centre, t, w):
		var p: Vector2 = dsc[0]
		var b := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		if not _bld_hash.has(b):
			_bld_hash[b] = []
		(_bld_hash[b] as Array).append(dsc)


# ------------------------------------------------------------------ blocks

## Blocks packed over zone `id`: candidate spots on a jittered grid (`step` cells) in a shuffled
## order, each trying a block of random size (smaller ones when it does not fit) that keeps
## `clear` cells of street to anything not walkable; townhouse blocks, a share of them gardens.
func _fill_blocks(id: String, step: Vector2i, size_lo: Vector2i, size_hi: Vector2i, clear: int, gardens: float, terraces: float) -> int:
	var bb: Array = get_region(id)["bbox"]
	var pts: Array[Vector2i] = []
	var y := int(bb[1])
	while y <= int(bb[3]):
		var x := int(bb[0])
		while x <= int(bb[2]):
			pts.append(Vector2i(x + rng.randi_range(0, step.x - 1), y + rng.randi_range(0, step.y - 1)))
			x += step.x
		y += step.y
	for k in range(pts.size() - 1, 0, -1):
		var r0 := rng.randi_range(0, k)
		var tmp := pts[k]
		pts[k] = pts[r0]
		pts[r0] = tmp
	var count := 0
	for p in pts:
		if not _inb(p) or grid.walk[p.y * _W + p.x] == 0 or _open[p.y * _W + p.x] == 1:
			continue
		var w := rng.randi_range(size_lo.x, size_hi.x)
		var h := rng.randi_range(size_lo.y, size_hi.y)
		var done := false
		for attempt in 3:
			var sw := w - attempt * 3
			var sh := h - attempt
			if sw < 6 or sh < 5:
				break
			for shift in [0, -3, 3]:
				var r := Rect2i(p.x - sw / 2 + int(shift), p.y - sh / 2, sw, sh)
				if _block_fits(r, id, clear):
					if rng.randf() < gardens:
						_garden_block(r)
					else:
						_house_block(r, terraces)
					count += 1
					done = true
					break
			if done:
				break
	return count


func _block_fits(r: Rect2i, id: String, clear: int) -> bool:
	var ri := _ri(id)
	var g := r.grow(clear)
	if g.position.x < 0 or g.position.y < 0 or g.end.x > _W or g.end.y > _H:
		return false
	for q in [g.position, Vector2i(g.end.x - 1, g.position.y), Vector2i(g.position.x, g.end.y - 1), g.end - Vector2i.ONE]:
		var qk: int = int(q.y) * _W + int(q.x)
		if grid.walk[qk] == 0 or region_map[qk] != ri:
			return false
	for j in range(g.position.y, g.end.y):
		for i in range(g.position.x, g.end.x):
			var k := j * _W + i
			if grid.walk[k] == 0 or region_map[k] != ri:
				return false
	var o := r.grow(1)
	for j2 in range(o.position.y, o.end.y):
		for i2 in range(o.position.x, o.end.x):
			if _open[j2 * _W + i2] == 1:
				return false
	return true


func _block_cells(r: Rect2i, opaque: bool, kind: int = K_BLOCK) -> void:
	for j in range(maxi(r.position.y, 0), mini(r.end.y, _H)):
		for i in range(maxi(r.position.x, 0), mini(r.end.x, _W)):
			var k := j * _W + i
			grid.walk[k] = 0
			if opaque:
				grid.opaque[k] = 1
			_kind[k] = kind


## A block of townhouses: a row along its south side (fronts south) and a column along its east
## side (fronts east) — the faces the camera sees — with a fenced yard in the north-west part. A
## house only stands where it hides no street from the camera (_occludes); where it would, the yard
## goes on instead. A flagstone kerb round the block, lamps and clutter at its corners.
func _house_block(r: Rect2i, terraces: float) -> void:
	_block_cells(r, false, K_GRASS)
	var taken := {}
	# The south row, from the east end westwards.
	var x := r.end.x
	var y_row := r.end.y - 3
	while x - r.position.x >= 2:
		var placed := false
		for piece in _row_pieces(x - r.position.x, terraces):
			var wc := int(piece[1])
			var centre := at(x - wc * 0.5, y_row + 1.5)
			if _occludes(centre, 0.0, wc * TILE - 0.4, 5.6, OCCLUDE_M):
				continue
			_building(String(piece[0]), centre, 0.0, rng.randf_range(1.0, 1.06))
			_mark_cells(Rect2i(x - wc, y_row, wc, 3), taken)
			x -= wc
			placed = true
			break
		if not placed:
			break
	var row_w := x
	# The east column, from above the row's corner house northwards.
	var y := r.end.y - 3
	if row_w < r.end.x:
		while y - r.position.y >= 2:
			var placed2 := false
			for piece2 in _row_pieces(y - r.position.y, terraces + 0.2):
				var hc := int(piece2[1])
				var centre2 := at(r.end.x - 1.5, y - hc * 0.5)
				if _occludes(centre2, PI * 0.5, hc * TILE - 0.4, 5.6, OCCLUDE_M):
					continue
				_building(String(piece2[0]), centre2, PI * 0.5, rng.randf_range(1.0, 1.06))
				_mark_cells(Rect2i(r.end.x - 3, y - hc, 3, hc), taken)
				y -= hc
				placed2 = true
				break
			if not placed2:
				break
	for c in taken:
		var cc: Vector2i = c
		grid.opaque[cc.y * _W + cc.x] = 1
		_kind[cc.y * _W + cc.x] = K_BLOCK
	# The yard: an iron fence along its open sides, dead trees, graves, a statue.
	_railing_line(at(r.position.x, r.position.y), at(r.end.x, r.position.y))
	_railing_line(at(r.position.x, r.position.y + 1), at(r.position.x, r.end.y))
	if row_w > r.position.x + 1:
		_railing_line(at(r.position.x + 1, r.end.y), at(row_w, r.end.y))
	if y > r.position.y + 1:
		_railing_line(at(r.end.x, r.position.y + 1), at(r.end.x, y))
	_yard(r, taken)
	_kerb(r)
	_block_corners(r)


## [[house id, cells along the row], ...] to try (in order) with `left` cells to go: the chosen
## piece, then smaller ones.
func _row_pieces(left: int, terraces: float) -> Array:
	var wide := [String(HOUSES_WIDE[rng.randi_range(0, 2)]), 3]
	var narrow := [HOUSE_NARROW, 2]
	if left >= 6 and rng.randf() < terraces:
		return [[String(TERRACES[rng.randi_range(0, 1)]), 6], wide, narrow]
	if left == 2 or left == 4 or left == 5 or (left >= 6 and rng.randf() < 0.15):
		return [narrow]
	return [wide, narrow]


## True if a building (footprint w x d m round centre, turned by yaw) would stand between the game
## camera and walkable ground within `reach` m of it (the camera looks north-west from ~13 m away
## and ~15 m up, so a house south-east of a street hides it).
func _occludes(centre: Vector3, yaw: float, w: float, d: float, reach: float) -> bool:
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	for su in [-0.5, -0.17, 0.17, 0.5]:
		for sv in [-0.5, 0.0, 0.5]:
			var q: Vector2 = Vector2(centre.x, centre.z) + ax * (float(su) * w) + az * (float(sv) * d)
			var t := 0.0
			while t <= reach:
				var p: Vector2 = q - CAM_DIR * t
				var c := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
				if _inb(c) and grid.walk[c.y * _W + c.x] == 1:
					return true
				t += 1.5
	return false


func _mark_cells(r: Rect2i, into: Dictionary) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			into[Vector2i(i, j)] = true


## A block's yard (its cells not under houses): dead trees, graves, now and then a statue or crypt.
func _yard(r: Rect2i, taken: Dictionary) -> void:
	var inner := r.grow(-1)
	var free: Array[Vector2i] = []
	for j in range(inner.position.y, inner.end.y):
		for i in range(inner.position.x, inner.end.x):
			var c := Vector2i(i, j)
			if not taken.has(c) and not taken.has(c + Vector2i(1, 0)) and not taken.has(c + Vector2i(0, 1)) \
					and not taken.has(c - Vector2i(1, 0)) and not taken.has(c - Vector2i(0, 1)):
				free.append(c)
	if free.is_empty():
		return
	# Low outbuildings (they hide nothing from the camera), then the garden things round them.
	var free_set := {}
	for c0 in free:
		free_set[c0] = true
	var sheds := 0
	for _t in 10:
		if sheds >= 2:
			break
		var o: Vector2i = free[rng.randi_range(0, free.size() - 1)]
		var sr := Rect2i(o.x, o.y, 3, 2)
		var ok := true
		for j in range(sr.position.y, sr.end.y):
			for i in range(sr.position.x, sr.end.x):
				if not free_set.has(Vector2i(i, j)):
					ok = false
		var sp := at(sr.position.x + 1.5, sr.position.y + 1.0)
		if not ok or not is_clear(sp, 2.2) or _occludes(sp, 0.0, 5.6, 3.8, 3.5):
			continue
		add_prop("gothic_shed", sp, 0.0, rng.randf_range(0.95, 1.05), {"cutout": true, "vary": 0.1})
		keep(sp, 2.6)
		for j2 in range(sr.position.y - 1, sr.end.y + 1):
			for i2 in range(sr.position.x - 1, sr.end.x + 1):
				free_set.erase(Vector2i(i2, j2))
		sheds += 1
	free = []
	for c1 in free_set:
		free.append(c1)
	if free.is_empty():
		return
	var mid: Vector2i = free[free.size() / 2]
	if free.size() > 24 and rng.randf() < 0.3:
		add_prop("gothic_crypt", cell_center(mid), 0.0, 0.85, {"cutout": true})
	elif free.size() > 8:
		add_prop("gothic_statue", cell_center(mid), 0.0, 0.9, {"cutout": true})
	for c2 in free:
		if c2.distance_to(mid) < 2.2:
			continue
		var roll := rng.randf()
		var p := cell_center(c2) + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		if roll < 0.12:
			add_prop("gothic_dead_tree", p, rng.randf() * TAU, rng.randf_range(0.7, 1.0), {"cutout": true})
		elif roll < 0.3:
			add_prop("gothic_grave_a" if rng.randf() < 0.5 else "gothic_grave_b", p, rng.randf_range(-0.3, 0.3), rng.randf_range(0.85, 1.05))


## A fenced garden: iron fence and pillars round it, dead trees, graves, a statue or a crypt
## inside (not walkable).
func _garden_block(r: Rect2i) -> void:
	_block_cells(r, false, K_GRASS)
	_fence_rect(r)
	var inner := r.grow(-1)
	var c := _rc(inner)
	if inner.size.x >= 4 and inner.size.y >= 3 and rng.randf() < 0.4:
		add_prop("gothic_crypt", at(c.x, c.y), 0.0, 0.9, {"cutout": true})
	else:
		add_prop("gothic_statue", at(c.x, c.y), 0.0, 1.0, {"cutout": true})
	for j in range(inner.position.y, inner.end.y):
		for i in range(inner.position.x, inner.end.x):
			var p := cell_center(Vector2i(i, j)) + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
			if p.distance_to(at(c.x, c.y)) < 3.2 or rng.randf() > 0.34:
				continue
			var gid := pick(GRAVE_IDS)
			add_prop(gid, p, rng.randf() * TAU if gid == "gothic_dead_tree" else rng.randf_range(-0.3, 0.3), rng.randf_range(0.85, 1.1),
				{"cutout": gid in ["gothic_dead_tree", "gothic_statue"]})
	_kerb(r)
	_block_corners(r)


## Iron fence with pillars along the outline of cell rect r.
func _fence_rect(r: Rect2i) -> void:
	var a := at(r.position.x, r.position.y)
	var b := at(r.end.x, r.position.y)
	var c := at(r.end.x, r.end.y)
	var d := at(r.position.x, r.end.y)
	_railing_line(a, b)
	_railing_line(b + Vector3(0, 0, TILE), c)
	_railing_line(d + Vector3(TILE, 0, 0), c)
	_railing_line(a + Vector3(0, 0, TILE), d)


## Flagstone kerb (one cell) round a block.
func _kerb(r: Rect2i) -> void:
	var g := r.grow(1)
	for j in range(maxi(g.position.y, 0), mini(g.end.y, _H)):
		for i in range(maxi(g.position.x, 0), mini(g.end.x, _W)):
			if r.has_point(Vector2i(i, j)):
				continue
			var k := j * _W + i
			if grid.walk[k] == 1 and _kind[k] == K_STREET:
				_kind[k] = K_PLAZA


## Lamps at a block's corners (always the southern two), clutter along a side now and then.
func _block_corners(r: Rect2i) -> void:
	var corners: Array = [Vector2(r.position.x - 0.8, r.end.y + 0.8), Vector2(r.end.x + 0.8, r.end.y + 0.8),
		Vector2(r.end.x + 0.8, r.position.y - 0.8), Vector2(r.position.x - 0.8, r.position.y - 0.8)]
	for k in corners.size():
		var q: Vector2 = corners[k]
		if k == 1 or rng.randf() < 0.3:
			_street_lamp(at(q.x, q.y), 12.0)
	if rng.randf() < 0.35 and r.size.x >= 8:
		var bx := rng.randf_range(r.position.x + 2.0, r.end.x - 2.0)
		var bp := at(bx, r.end.y + 0.6)
		if is_walkable_at(bp) and is_clear(bp, 1.2):
			add_obstacle("gothic_bench", bp, 0.0, 1.0, 0.5, {"cutout": false})
	if rng.randf() < 0.3:
		_planter(at(r.position.x - 0.7, r.end.y + 0.7))
	if rng.randf() < 0.45:
		var side := rng.randi_range(0, 3)
		var f := rng.randf_range(0.2, 0.8)
		var p: Vector2
		match side:
			0:
				p = Vector2(lerpf(r.position.x, r.end.x, f), r.end.y + 0.55)
			1:
				p = Vector2(r.end.x + 0.55, lerpf(r.position.y, r.end.y, f))
			2:
				p = Vector2(lerpf(r.position.x, r.end.x, f), r.position.y - 0.55)
			_:
				p = Vector2(r.position.x - 0.55, lerpf(r.position.y, r.end.y, f))
		_clutter(at(p.x, p.y))


# ------------------------------------------------------------------ furniture

func _building(id: String, pos: Vector3, yaw: float, sc: float) -> void:
	add_prop(id, pos, yaw, sc, {"cutout": true, "shadows": true, "vary": 0.1})


## A street lamp on walkable ground unless another stands within `spacing` m.
func _street_lamp(pos: Vector3, spacing: float = 10.0) -> bool:
	if not is_walkable_at(pos) or not is_clear(pos, 0.7):
		return false
	var b := Vector2i(floori(pos.x / 12.0), floori(pos.z / 12.0))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for q in _lamp_hash.get(b + Vector2i(di, dj), []):
				if (q as Vector3).distance_to(pos) < spacing:
					return false
	if not _lamp_hash.has(b):
		_lamp_hash[b] = []
	(_lamp_hash[b] as Array).append(pos)
	_lamp(pos, rng.randf_range(-0.2, 0.2) + (PI * 0.5 if rng.randf() < 0.5 else 0.0), true)
	return true


## Lamps along a street a -> b (cell units), alternating sides `off` cells from its middle.
func _lamps_along(a: Vector2, b: Vector2, off: float, every: float) -> void:
	var d := b - a
	var len_m := d.length() * TILE
	if len_m < 1.0:
		return
	var t := Vector2(-d.y, d.x) / d.length()
	var n := maxi(1, int(len_m / every))
	for k in n + 1:
		var q := a + d * (float(k) / n) + t * off * (1.0 if k % 2 == 0 else -1.0)
		_street_lamp(at(q.x, q.y))


func _lamps_ring(p: Vector3, radius: float, count: int, phase: float) -> void:
	for k in count:
		var a := phase + TAU * k / count
		_street_lamp(p + Vector3(cos(a), 0.0, sin(a)) * radius, 6.0)


## Lamps round the inside of a square (cell rect).
func _lamps_rect(r: Rect2i, every: float) -> void:
	var x0 := r.position.x + 1.2
	var x1 := r.end.x - 1.2
	var y0 := r.position.y + 1.2
	var y1 := r.end.y - 1.2
	for seg in [[Vector2(x0, y0), Vector2(x1, y0)], [Vector2(x1, y0), Vector2(x1, y1)], [Vector2(x1, y1), Vector2(x0, y1)], [Vector2(x0, y1), Vector2(x0, y0)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := maxi(1, int(a.distance_to(b) * TILE / every))
		for k in n:
			var q := a.lerp(b, float(k) / n)
			_street_lamp(at(q.x, q.y), every * 0.6)


## An iron brazier with a red fire (light and glow).
func _brazier(pos: Vector3) -> void:
	if not is_walkable_at(pos) or not is_clear(pos, 0.9):
		return
	add_obstacle("env_brazier", pos, rng.randf() * TAU, 1.0, 0.45, {"cutout": false, "emission_color": Color(1.0, 0.3, 0.14)})
	add_light(pos + Vector3(0.0, 1.5, 0.0), FIRE_LIGHT, 2.8, 10.0, true)
	add_glow(pos, 3.4, Color(1.0, 0.34, 0.16))


func _carriage(pos: Vector3, yaw: float) -> void:
	if is_walkable_at(pos) and is_clear(pos, 2.8):
		add_block("gothic_carriage", pos, yaw, Vector2(2.2, 4.8), {"height": 2.6})


func _planter(pos: Vector3) -> void:
	if is_walkable_at(pos) and is_clear(pos, 1.0):
		add_obstacle("gothic_planter", pos, 0.0, 1.0, 0.75, {"cutout": false})


## Dress a flagstone square (cell rect): a cobbled border, benches facing its middle, planters and
## some clutter along its sides.
func _dress_rect(r: Rect2i, id: String, benches: int, planters: int, clutter: int) -> void:
	var x0 := float(r.position.x)
	var x1 := float(r.end.x)
	var y0 := float(r.position.y)
	var y1 := float(r.end.y)
	for e in [[Vector2(x0, y0 + 0.5), Vector2(x1, y0 + 0.5)], [Vector2(x0, y1 - 0.5), Vector2(x1, y1 - 0.5)],
			[Vector2(x0 + 0.5, y0), Vector2(x0 + 0.5, y1)], [Vector2(x1 - 0.5, y0), Vector2(x1 - 0.5, y1)]]:
		_paint_band(e[0], e[1], 1.0, K_STREET, id)
	var mid := at(_rc(r).x, _rc(r).y)
	var sides: Array = [[Vector2(x0 + 2.6, y0 + 2.6), Vector2(x1 - 2.6, y0 + 2.6)], [Vector2(x1 - 2.6, y0 + 2.6), Vector2(x1 - 2.6, y1 - 2.6)],
		[Vector2(x1 - 2.6, y1 - 2.6), Vector2(x0 + 2.6, y1 - 2.6)], [Vector2(x0 + 2.6, y1 - 2.6), Vector2(x0 + 2.6, y0 + 2.6)]]
	for k in benches:
		var sd: Array = sides[(k * 2 + 1) % 4]
		var q: Vector2 = (sd[0] as Vector2).lerp(sd[1], 0.5)
		var bp := at(q.x, q.y)
		if is_walkable_at(bp) and is_clear(bp, 1.4):
			add_obstacle("gothic_bench", bp, _yaw_to(bp, mid), 1.0, 0.5, {"cutout": false})
	for k2 in planters:
		var sd2: Array = sides[k2 % 4]
		var q2: Vector2 = (sd2[0] as Vector2).lerp(sd2[1], 0.25 if k2 < 4 else 0.75)
		_planter(at(q2.x, q2.y))
	for _k3 in clutter:
		var sd3: Array = sides[rng.randi_range(0, 3)]
		var q3: Vector2 = (sd3[0] as Vector2).lerp(sd3[1], rng.randf_range(0.15, 0.85))
		_clutter(at(q3.x, q3.y))


## Dress a round square: a cobbled rim, benches facing its middle, planters.
func _dress_disc(c: Vector2, radius: float, id: String, benches: int, planters: int) -> void:
	_ring(c, radius - 1.0, radius, K_STREET, id)
	var p := at(c.x, c.y)
	for k in benches:
		var a := PI * 0.5 + TAU * k / maxf(benches, 1)
		var bp := p + Vector3(cos(a), 0.0, sin(a)) * radius * TILE * 0.55
		if is_walkable_at(bp) and is_clear(bp, 1.4):
			add_obstacle("gothic_bench", bp, _yaw_to(bp, p), 1.0, 0.5, {"cutout": false})
	for k2 in planters:
		var a2 := PI * 0.25 + TAU * k2 / maxf(planters, 1)
		_planter(p + Vector3(cos(a2), 0.0, sin(a2)) * radius * TILE * 0.78)


## A coffin, or a pile of crates and barrels.
func _clutter(pos: Vector3) -> void:
	if not is_walkable_at(pos) or not is_clear(pos, 1.3):
		return
	if rng.randf() < 0.4:
		add_obstacle("gothic_coffin", pos, rng.randf() * TAU, 1.0, 0.8, {"cutout": false})
		return
	for _k in rng.randi_range(2, 3):
		var q := pos + Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
		add_obstacle("env_crate" if rng.randf() < 0.5 else "env_barrel", q, rng.randf() * TAU, rng.randf_range(0.8, 0.95), 0.4,
			{"cutout": false, "tint": Color(0.55, 0.55, 0.62)})


func _chest_spot(id: String, pos: Vector3, yaw: float) -> void:
	if not _chest_spots.has(id):
		_chest_spots[id] = []
	(_chest_spots[id] as Array).append([pos, yaw])


func _shrine_spot(id: String, pos: Vector3) -> void:
	if not _shrine_spots.has(id):
		_shrine_spots[id] = []
	(_shrine_spots[id] as Array).append(pos)


# ------------------------------------------------------------------ paving, ground, loot, monsters

## Drifts of snow along house walls, yard railings and the zones' edges where the broad snow noise
## is high.
func _snowdrifts() -> void:
	var taken := {}
	var dirs: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for j in range(1, _H - 1):
		for i in range(1, _W - 1):
			var k := j * _W + i
			if grid.walk[k] == 0:
				continue
			var kd := _kind[k]
			if kd != K_STREET and kd != K_PLAZA and kd != K_QUAY and kd != K_PATH:
				continue
			var d := Vector2i.ZERO
			for dd in dirs:
				var nk := k + dd.x + dd.y * _W
				var nkd := _kind[nk]
				if (grid.floor_cells[nk] == 0 and nkd == K_VOID) or ((nkd == K_BLOCK or nkd == K_GRASS) and grid.walk[nk] == 0):
					d = dd
					break
			if d == Vector2i.ZERO:
				continue
			var x := (i + 0.5) * TILE
			var z := (j + 0.5) * TILE
			if noise2(x, z, 0.021, 2) < 0.5 or rng.randf() < 0.6:
				continue
			var p := Vector3(x + d.x * 0.5, 0.0, z + d.y * 0.5)
			var b := Vector2i(floori(p.x / 7.0), floori(p.z / 7.0))
			if taken.has(b) or taken.has(b + Vector2i(1, 0)) or taken.has(b - Vector2i(1, 0)) or taken.has(b + Vector2i(0, 1)) or taken.has(b - Vector2i(0, 1)):
				continue
			taken[b] = true
			var yaw := (0.0 if d.x == 0 else PI * 0.5) + rng.randf_range(-0.2, 0.2)
			add_prop("gothic_snowdrift", p, yaw, rng.randf_range(0.7, 1.2), {"shadows": false, "vary": 0.05})


## Paving by cell kind, tinted per zone (the canal quarter's wet blue-grey setts, the bridge's
## pale stone, the abbey's warmer flags).
func _lay_tiles() -> void:
	var groups := {}
	for k in _W * _H:
		var kd := int(_kind[k])
		if kd != K_STREET and kd != K_PLAZA and kd != K_QUAY and kd != K_PATH and kd != K_DECK:
			continue
		var key := kd * 16 + int(region_map[k])
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(Vector2i(k % _W, k / _W))
	var keys: Array = groups.keys()
	keys.sort()
	for key in keys:
		var kd2 := int(key) / 16
		var rv := int(key) % 16
		var rid := String(regions[rv - 1]["id"]) if rv > 0 and rv <= regions.size() else ""
		var tints: Array = ZONE_TINTS.get(rid, COBBLE_TINTS) if kd2 == K_STREET else ZONE_FLAG_TINTS.get(rid, FLAG_TINTS)
		match kd2:
			K_QUAY:
				tints = QUAY_TINTS
			K_PATH:
				tints = PATH_TINTS
			K_DECK:
				tints = DECK_TINTS
		add_tiles(WILDS_COBBLES if kd2 == K_STREET else FLAGS, groups[key], tints[0], tints)


## Rain puddles and blood on the paving.
func _street_decals() -> void:
	var r := Rect2(0.0, 0.0, _W * TILE, _H * TILE)
	var paved := func(p: Vector3) -> bool:
		var kd := _kind_of(world_to_cell(p))
		return kd == K_STREET or kd == K_PLAZA or kd == K_QUAY
	scatter(["gothic_puddle"], 170, r, {"on": "walkable", "min_dist": 8.0, "scale": Vector2(0.55, 1.0), "shadows": false, "filter": paved})
	scatter(["gothic_blood"], 34, r, {"on": "walkable", "min_dist": 16.0, "scale": Vector2(0.7, 1.1), "shadows": false, "filter": paved})


## Ground colour per cell (linear), the gorge darkening with depth.
func _ground_setup() -> void:
	var pal := PackedColorArray()
	for c in KIND_COLORS:
		var col: Color = c
		var lin := col.srgb_to_linear()
		lin.a = col.a
		pal.append(lin)
	_snow_lin = SNOW_SRGB.srgb_to_linear()
	var n := _W * _H
	_ccol.resize(n)
	for k in n:
		var kd := _kind[k]
		if kd == K_CHASM:
			var col2 := pal[kd]
			var f := 1.0 - 0.75 * clampf(_depth[k] / GORGE_DEPTH, 0.0, 1.0)
			_ccol[k] = Color(col2.r * f, col2.g * f, col2.b * f, col2.a)
		else:
			_ccol[k] = pal[kd]


## Walkable cells the start cannot reach are blocked now (nothing is placed there).
func _prune_unreachable() -> void:
	var reach := grid.flood_walkable(world_to_cell(start))
	for k in grid.walk.size():
		if grid.walk[k] == 1 and reach[k] == 0:
			grid.walk[k] = 0


## 2-4 chests and 1-2 shrines per zone from the painters' spots.
func _loot() -> void:
	for id in region_ids():
		var want := 4 if id == "outskirts" else 3
		var placed := 0
		for s in _chest_spots.get(id, []):
			if placed >= want:
				break
			var p: Vector3 = s[0]
			if region_at(p) != id or not is_walkable_at(p) or not is_clear(p, 1.1):
				continue
			add_chest(p, float(s[1]), 1 if placed == 0 and region_level(id) >= 1 else 0)
			placed += 1
		var sh := 0
		for p2 in _shrine_spots.get(id, []):
			if sh >= 2:
				break
			var q: Vector3 = p2
			if region_at(q) != id or not is_walkable_at(q) or not is_clear(q, 1.4):
				continue
			add_shrine(q)
			sh += 1


## Monster packs: about one per 4500 m2 of each zone, 2-3 rare packs.
func _monsters() -> void:
	refresh_open_field()
	for id in region_ids():
		var area := float(get_region(id).get("cells", 0)) * TILE * TILE
		var packs := maxi(4, roundi(area / 4500.0))
		var rares := 3 if area > 60000.0 else 2
		var got := auto_spawn_region(id, packs, rares, 15.0, 12.0)
		if got < 4:
			auto_spawn_region(id, 4 - got, 0, 9.0, 8.0)


## Each zone's night: the Canal Quarter's colder water fog, the cemetery's thick fog, the bridge's
## cold wind, the abbey's red glow.
func _zone_looks() -> void:
	set_region_theme("outskirts", {"ambient_energy": 0.45, "exposure": 1.15})
	set_region_theme("canals", {"fog": Color(0.09, 0.17, 0.23), "fog_density": 0.019, "ambient": Color(0.26, 0.4, 0.52),
		"ambient_energy": 0.48, "sun": Color(0.6, 0.76, 0.96), "exposure": 1.18})
	set_region_theme("cemetery", {"fog": Color(0.16, 0.22, 0.21), "fog_density": 0.028, "fog_height_density": 0.12,
		"ambient": Color(0.32, 0.42, 0.42), "ambient_energy": 0.55, "saturation": 0.74, "exposure": 1.28,
		"volumetric_fog": {"density": 0.045}})
	set_region_theme("bridge", {"fog": Color(0.1, 0.15, 0.25), "fog_density": 0.017, "ambient": Color(0.28, 0.38, 0.56),
		"ambient_energy": 0.46, "sun": Color(0.68, 0.82, 1.0), "sun_energy": 1.05, "saturation": 0.78, "contrast": 1.2})
	set_region_theme("abbey", {"fog": Color(0.2, 0.1, 0.1), "fog_density": 0.019, "ambient": Color(0.42, 0.31, 0.34),
		"sun": Color(0.9, 0.68, 0.66), "saturation": 0.9, "exposure": 1.14})


# ------------------------------------------------------------------ small helpers

func _ri(id: String) -> int:
	return int(_region_index.get(id, 0))


func _inb(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _W and c.y < _H


func _kind_of(c: Vector2i) -> int:
	return int(_kind[c.y * _W + c.x]) if _inb(c) else K_VOID


## The centre of a cell rect in cell units.
static func _rc(r: Rect2i) -> Vector2:
	return Vector2(r.position) + Vector2(r.size) * 0.5


## A world position in cell units (cell (i, j) spans [i, i + 1] x [j, j + 1]).
static func _cell_pos(p: Vector3) -> Vector2:
	return Vector2(p.x / TILE, p.z / TILE)


## Yaw that turns a model's front (+Z) from `from` towards `to`.
static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


func _exit_cell() -> Vector2i:
	var ex: Dictionary = layout_data.get("exit", {})
	return Vector2i(roundi(float(ex["cell"][0])), roundi(float(ex["cell"][1])))


## The cell where the path from zone a to zone b crosses between them.
func _link_cell(a: String, b: String) -> Vector2i:
	for l in region_links(a):
		if String(l["to"]) == b:
			return world_to_cell(l["pos"])
	return Vector2i(-1, -1)


## Cells of zone `id` (walkable) within width / 2 of the segment a-b (cell units) get `kind` (-1:
## unchanged) and, when `open`, stay free of blocks. id "" = any zone.
func _paint_band(a: Vector2, b: Vector2, width: float, kind: int, id: String, open: bool = true) -> void:
	var ri := _ri(id)
	var half := width * 0.5
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	var y0 := maxi(floori(minf(a.y, b.y) - half) - 1, 0)
	var y1 := mini(ceili(maxf(a.y, b.y) + half) + 1, _H)
	var x0 := maxi(floori(minf(a.x, b.x) - half) - 1, 0)
	var x1 := mini(ceili(maxf(a.x, b.x) + half) + 1, _W)
	for j in range(y0, y1):
		for i in range(x0, x1):
			var k := j * _W + i
			if grid.walk[k] == 0 or (ri > 0 and region_map[k] != ri):
				continue
			var p := Vector2(i + 0.5, j + 0.5)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			if p.distance_squared_to(a + ab * t) <= half * half:
				if kind >= 0:
					_kind[k] = kind
				if open:
					_open[k] = 1


func _paint_disc(c: Vector2, radius: float, kind: int, id: String, open: bool = true) -> void:
	_paint_band(c, c, radius * 2.0, kind, id, open)


func _paint_rect(r: Rect2i, kind: int, id: String, open: bool = true) -> void:
	var ri := _ri(id)
	for j in range(maxi(r.position.y, 0), mini(r.end.y, _H)):
		for i in range(maxi(r.position.x, 0), mini(r.end.x, _W)):
			var k := j * _W + i
			if grid.walk[k] == 1 and (ri == 0 or region_map[k] == ri):
				if kind >= 0:
					_kind[k] = kind
				if open:
					_open[k] = 1


## Cells whose centre lies r0..r1 cells from c get `kind`.
func _ring(c: Vector2, r0: float, r1: float, kind: int, id: String) -> void:
	var ri := _ri(id)
	for j in range(maxi(floori(c.y - r1) - 1, 0), mini(ceili(c.y + r1) + 1, _H)):
		for i in range(maxi(floori(c.x - r1) - 1, 0), mini(ceili(c.x + r1) + 1, _W)):
			var k := j * _W + i
			if grid.walk[k] == 0 or (ri > 0 and region_map[k] != ri):
				continue
			var d := Vector2(i + 0.5, j + 0.5).distance_to(c)
			if d >= r0 and d <= r1:
				_kind[k] = kind


## Keep cells within `radius` cells of c free of blocks.
func _open_disc(c: Vector2, radius: float) -> void:
	_paint_band(c, c, radius * 2.0, -1, "")

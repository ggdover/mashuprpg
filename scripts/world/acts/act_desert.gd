extends WorldActGen
## Act II — The Gilded Sands (desert). OWNER: acts-desert.
##
## Hub "Qadesh": a walled sandstone city square in the spirit of Qarth — crenellated walls and
## towers with dark stripe bands, a great striped gate in the north wall (the road to the river
## leaves through it), flat-roofed and domed houses, an arcade, a paved plaza with a pool, palm
## planters, the merchant's striped awning, an obelisk waystone; dunes outside.
## The outdoor zones north of the gate (data/layouts/act_desert.json, one big seamless map):
##   Banks of the Iteru (outskirts, +0): the great river winds through the zone from the north to
##     the east. On its far bank farmsteads, fields and ditches, shadufs, jetties and feluccas; the
##     Great Bridge carries the road north, a paved causeway and a reed ford cross further along.
##     The near bank is desert: an avenue of sphinxes before the city, a caravan halt, a pyramid
##     with its sphinx, dune ridges, rock outcrops and a ruined temple by the water.
##   The Oasis (+1): a spring-fed pool under palms, lotus and ferns, a caravan camp and a well.
##   Snake Isles (+2): papyrus islands between marsh channels, plank footbridges, serpent statues
##     and a serpent shrine.
##   Anubis Graveyard (+2): the jackal god's necropolis — streets of mastaba tombs, pyramid
##     chapels, fields of stelae, sarcophagi, jackal statues along a paved processional way.
##   Anubis Courtyard (+3): a paved temple court in the golden hour — colonnades, colossal
##     standing Anubis statues, obelisks, braziers and a sacred lake. The Anubis Temple stands along
##     its north side facing the court (and the camera): its hall, the pylon and the door down into
##     the act dungeon, with the zone's guardian before it.
## Each link between zones is marked by a gateway (columns, serpents, jackals, a pylon gate).
## Ground: per-cell fields baked once (water distance, relief, trails, fertility, a palette) keep
## ground_color() / ground_height() to a few microseconds per vertex.

const HUB_SIZE := Vector2i(36, 34)
## Hub interior (walkable) bounds in metres.
const HUB_X0 := 12.0
const HUB_X1 := 60.0
const HUB_Z0 := 12.0
const HUB_Z1 := 56.0
## The hub's exit cell (add_exit in _hub()): the composer puts the town beyond the wilds' exit.
const HUB_EXIT_CELL := Vector2i(18, 0)

# ------------------------------------------------------------------ wilds layout (metres)

## The Iteru: from the north (between the oasis and the necropolis) through the outskirts, out to
## the east. Points and half widths.
const RIVER: Array[Vector2] = [Vector2(232, -45), Vector2(228, 40), Vector2(236, 120), Vector2(250, 175), Vector2(272, 222),
	Vector2(312, 252), Vector2(362, 266), Vector2(412, 285), Vector2(452, 318), Vector2(492, 352), Vector2(560, 380),
	Vector2(650, 392), Vector2(740, 420), Vector2(840, 440)]
const RIVER_HW: Array[float] = [12.0, 12.0, 12.0, 11.5, 11.5, 11.5, 12.0, 12.0, 11.5, 12.0, 13.0, 14.0, 14.0, 14.0]
## The Snake Isles' marsh channels (points, half widths).
const CHANNELS := [
	[[Vector2(-40, 352), Vector2(10, 352), Vector2(40, 358), Vector2(62, 372), Vector2(78, 398), Vector2(88, 430), Vector2(92, 462),
		Vector2(72, 486), Vector2(20, 494), Vector2(-40, 494)], [7.0, 7.0, 6.5, 6.0, 6.0, 6.0, 6.0, 6.5, 7.0, 7.0]],
	[[Vector2(40, 358), Vector2(62, 340), Vector2(95, 330), Vector2(130, 322), Vector2(160, 316)], [6.0, 6.0, 6.0, 5.5, 5.0]],
	[[Vector2(78, 398), Vector2(105, 405), Vector2(130, 420), Vector2(170, 440)], [6.0, 6.0, 6.0, 6.0]],
	[[Vector2(-40, 440), Vector2(10, 432), Vector2(40, 420), Vector2(66, 396)], [6.0, 6.0, 6.0, 6.0]],
]
## The oasis pool: ellipses (centre, radii, rotation).
const POOLS := [[Vector2(92, 172), Vector2(26, 17), 0.35], [Vector2(64, 196), Vector2(12, 9), 0.2]]
## The sacred lake of the temple court (a rectangle).
const LAKE := Rect2(670, 34, 48, 28)
## The Anubis Temple's axis (x, m): it stands along the court's north side, facing south.
const TEMPLE_X := 631.0
## Crossings: [centre, axis (0 = the path runs N-S, 1 = E-W), width in cells, kind].
const CROSSINGS := [
	[Vector2(340, 260), 0, 2, "bridge"], [Vector2(441, 308), 0, 3, "causeway"], [Vector2(262, 200), 1, 3, "ford"],
	[Vector2(116, 325), 0, 2, "foot"], [Vector2(118, 413), 0, 2, "foot"], [Vector2(20, 354), 0, 2, "foot"],
	[Vector2(30, 424), 0, 2, "foot"], [Vector2(93, 456), 1, 2, "foot"], [Vector2(69, 384), 1, 2, "foot"],
]
## Mounds inside the zones: [centre, radii, rotation, height, kind] — dune ridges and rock outcrops
## (solid open ground with relief: soft cells with their own collision boxes, so no border ruins).
const MOUNDS := [
	[Vector2(385, 452), Vector2(16, 7), 0.2, 2.8, "dune"],
	[Vector2(190, 270), Vector2(12, 7), 1.2, 2.6, "dune"], [Vector2(262, 470), Vector2(12, 6), 0.1, 2.2, "dune"],
	[Vector2(412, 440), Vector2(9, 7), 0.4, 0.3, "rock"], [Vector2(468, 425), Vector2(8, 6), 0.9, 0.3, "rock"],
	[Vector2(236, 240), Vector2(8, 6), 0.5, 0.3, "rock"], [Vector2(60, 112), Vector2(14, 9), 0.3, 0.4, "rock"],
	[Vector2(300, 108), Vector2(12, 11), 0.0, 0.4, "rock"], [Vector2(462, 138), Vector2(13, 8), 0.2, 2.6, "dune"],
	[Vector2(180, 420), Vector2(8, 6), 0.3, 0.3, "rock"], [Vector2(236, 372), Vector2(13, 5.5), 0.4, 2.4, "dune"],
	[Vector2(345, 430), Vector2(7, 5), 1.0, 0.3, "rock"], [Vector2(482, 262), Vector2(7, 5), 0.2, 0.3, "rock"],
	[Vector2(300, 330), Vector2(12, 5), -0.3, 2.4, "dune"], [Vector2(272, 292), Vector2(11, 5), 0.6, 2.2, "dune"],
	[Vector2(365, 345), Vector2(6, 5), 0.8, 0.3, "rock"],
]
## Worn trails: [points, half width].
const TRAILS := [
	[[Vector2(299, 502), Vector2(299, 470), Vector2(304, 440), Vector2(316, 400), Vector2(330, 355), Vector2(338, 312),
		Vector2(340, 285), Vector2(340, 235), Vector2(345, 205), Vector2(352, 180), Vector2(352, 150)], 3.2],
	[[Vector2(304, 440), Vector2(270, 425), Vector2(230, 400), Vector2(190, 382), Vector2(151, 376), Vector2(128, 376)], 2.6],
	[[Vector2(316, 400), Vector2(285, 370), Vector2(255, 335), Vector2(235, 295), Vector2(222, 255), Vector2(205, 222),
		Vector2(182, 198), Vector2(160, 196), Vector2(138, 196)], 2.6],
	[[Vector2(215, 232), Vector2(245, 202), Vector2(280, 201), Vector2(315, 203), Vector2(345, 205)], 2.2],
	[[Vector2(340, 235), Vector2(375, 247), Vector2(420, 252), Vector2(441, 270), Vector2(441, 290), Vector2(441, 326),
		Vector2(425, 350), Vector2(395, 372), Vector2(360, 390), Vector2(322, 398)], 2.2],
	[[Vector2(88, 281), Vector2(96, 300), Vector2(116, 312), Vector2(116, 340), Vector2(128, 376)], 2.0],
	[[Vector2(352, 150), Vector2(352, 118), Vector2(360, 84), Vector2(400, 80), Vector2(530, 77)], 3.0],
]
## Irrigated fields (rectangles, m).
const FIELDS := [Rect2(300, 212, 34, 16), Rect2(360, 212, 40, 26), Rect2(404, 196, 42, 30), Rect2(350, 288, 42, 20), Rect2(392, 316, 32, 20)]

## Batching options per model family (kept constant so each model is one MultiMesh group).
const OPT_PALM := {"cutout": true, "sway": 0.45, "sway_base": 2.0}
const OPT_REEDS := {"shadows": false, "sway": 1.0, "sway_base": 0.5}
const OPT_LOW := {"shadows": false}
const OPT_TALL := {"cutout": true}

## Water edge: cells whose centre is nearer to open water than this (m) are not walkable.
const WATER_CUT := 0.8
## "No water near" (m) in the water-distance field (exact up to about 24 m from any water).
const FAR_WATER := 30.0
## Cell size (m) of the coarse field that raises dunes away from the walkable ground.
const AMP_CELL := 8.0
## South of this band (m) the wilds' dunes turn into the town's own (they meet beyond the road).
const SOUTH_BLEND := Vector2(466.0, 500.0)

## Smoothed walkability per grid cell (0..1) for soft path edges in ground_color() (hub).
var _walk_blur := PackedFloat32Array()
## Pyramid footprints (centre x, centre z, half size) for ground colours (hub).
var _pyramids: Array = []

## Wilds fields, per grid cell: r = signed distance to open water (m, < 0 in it), g = relief (m),
## b = trail (0..1), a = fertility (0..1).
var _fa := PackedColorArray()
## Per cell: the ground's base colour (linear) — the zones' palettes, the open sand.
var _pal := PackedColorArray()
var _gw := 0
var _gh := 0
var _umax := 0.0
var _vmax := 0.0
## Coarse dune amplitude (0..1) over the ground rect and the strip down to the town.
var _amp := PackedFloat32Array()
var _aw := 0
var _ah := 0
var _ax0 := -48.0
var _az0 := -48.0
var _dn: FastNoiseLite = null
var _cn: FastNoiseLite = null
var _bn: FastNoiseLite = null
## The town zone's origin in these coordinates (to match its dunes south of the road).
var _hub_off := Vector2.ZERO
## Cells kept walkable across water (bridges, fords).
var _crossing_cells := {}
## Palette (linear).
var _c_sand := Color()
var _c_mud := Color()
var _c_bed := Color()
var _c_green := Color()
var _c_green_b := Color()
var _c_silt := Color()
var _c_crest := Color()
var _c_trail := Color()
var _c_pale := Color()
var _c_gravel := Color()
var _c_dusk := Color()
var _c_damp := Color()
## Dev stats of the wilds' generation: milliseconds per phase, mound placement tallies.
var prof := {}
## ground_height() -> ground_color() cache (the World asks for both at every vertex).
var _cx := INF
var _cz := INF
var _cf := Color()
var _ch := 0.0


func generate_zone() -> void:
	if zone == "hub":
		_hub()
		_blur_walk()
	else:
		_wilds()


func theme() -> Dictionary:
	var th := {
		"sky_top": Color(0.24, 0.47, 0.8),
		"sky_horizon": Color(0.93, 0.82, 0.64),
		"ground_horizon": Color(0.86, 0.72, 0.52),
		"ground_bottom": Color(0.52, 0.42, 0.3),
		"sky_energy": 1.0,
		"ambient": Color(0.88, 0.8, 0.68),
		"ambient_energy": 0.44,
		"ambient_sky": 0.45,
		"sun": Color(1.0, 0.9, 0.74),
		"sun_energy": 1.65,
		"sun_rot": Vector3(-40.0, 38.0, 0.0),
		"fog": Color(0.93, 0.83, 0.66),
		"fog_density": 0.0035,
		"fog_sky_affect": 0.35,
		"exposure": 1.0,
		"contrast": 1.1,
		"saturation": 1.12,
		"light_color": Color(1.0, 0.68, 0.32),
		"light_energy": 1.6,
		"light_range": 7.0,
		"glow_color": Color(1.0, 0.66, 0.3),
		"glow_pool_strength": 0.22,
		"water_shallow": Color(0.3, 0.62, 0.62),
		"water_deep": Color(0.07, 0.3, 0.46),
		"water_foam": Color(0.92, 0.9, 0.8),
		"water_depth_scale": 1.1,
		"particles": {"kind": "dust", "color": Color(1.0, 0.9, 0.7, 0.45), "amount": 150, "size": 0.07, "speed": 0.7},
		"daylight": true,
	}
	return th


# ------------------------------------------------------------------ hub: Qadesh

func _hub() -> void:
	setup_grid(HUB_SIZE)
	ground_rect = Rect2(-60, -90, 196, 222)
	ground_step = 1.5
	carve_rect(Rect2i(int(HUB_X0 / TILE), int(HUB_Z0 / TILE), int((HUB_X1 - HUB_X0) / TILE), int((HUB_Z1 - HUB_Z0) / TILE)))
	start = Vector3(36, 0, 46.5)
	keep(start, 1.6)
	# --- city walls, towers and the great gate ---------------------------------------------
	var gate_x := 36.0
	add_prop("desert_gate", Vector3(gate_x, 0, 10.4), 0.0, 1.0, {"cutout": true})
	for x in [29.3, 42.7]:
		add_prop("desert_tower", Vector3(x, 0, 10.2), 0.0, 1.0, {"cutout": true})
	var xs := []
	var x := HUB_X0 + 2.0
	while x <= HUB_X1 - 2.0 + 0.01:
		xs.append(x)
		x += 4.0
	for wx in xs:
		if absf(wx - gate_x) > 6.5:
			add_prop("desert_wall", Vector3(wx, 0, 11.0), 0.0, 1.0, {"cutout": true})
		add_prop("desert_wall", Vector3(wx, 0, 57.0), PI, 1.0, {"cutout": true})
	var z := HUB_Z0 + 2.0
	while z <= HUB_Z1 - 2.0 + 0.01:
		add_prop("desert_wall", Vector3(11.0, 0, z), PI * 0.5, 1.0, {"cutout": true})
		add_prop("desert_wall", Vector3(61.0, 0, z), -PI * 0.5, 1.0, {"cutout": true})
		z += 4.0
	for t in [Vector3(10.6, 0, 10.6), Vector3(61.4, 0, 10.6), Vector3(10.6, 0, 57.4), Vector3(61.4, 0, 57.4),
			Vector3(10.4, 0, 34), Vector3(61.6, 0, 34), Vector3(24, 0, 57.6), Vector3(48, 0, 57.6)]:
		add_prop("desert_tower", t, 0.0, 1.0, {"cutout": true})
	# The domed landmark tower in the north-east corner.
	add_building("desert_tower_dome", Vector3(57.0, 0, 15.0), 0.0, Vector2(5.0, 5.0))
	# --- houses ---------------------------------------------------------------------------------
	add_building("desert_house_c", Vector3(15.0, 0, 15.0), PI * 0.5, Vector2(5.0, 5.0))
	add_building("desert_house_a", Vector3(16.0, 0, 27.0), PI * 0.5, Vector2(6.0, 6.0))
	add_building("desert_house_b", Vector3(15.5, 0, 40.0), PI * 0.5, Vector2(6.0, 5.0))
	add_building("desert_house_a", Vector3(16.0, 0, 51.0), PI * 0.5, Vector2(6.0, 6.0))
	add_building("desert_house_b", Vector3(56.5, 0, 28.0), -PI * 0.5, Vector2(6.0, 5.0))
	add_building("desert_house_a", Vector3(56.0, 0, 40.0), -PI * 0.5, Vector2(6.0, 6.0))
	add_building("desert_house_c", Vector3(56.5, 0, 51.0), -PI * 0.5, Vector2(5.0, 5.0))
	# --- arcades framing the plaza's north side ---------------------------------------------
	for cx in [25.0, 47.0]:
		add_block("desert_colonnade", Vector3(cx, 0, 24.0), 0.0, Vector2(6.0, 1.3), {"height": 5.0})
	# --- plaza: pool, market, stash, waystone, braziers ---------------------------------------
	add_block("desert_fountain", Vector3(36, 0, 35), 0.0, Vector2(4.8, 4.8), {"height": 1.2, "cutout": false})
	add_waystone(Vector3(27.5, 0, 17.0), 0.0, "desert_obelisk", Vector2(2.4, 2.4))
	add_block("desert_awning", Vector3(25.2, 0, 35.0), PI * 0.5, Vector2(3.8, 3.2), {"height": 2.6})
	add_vendor(Vector3(28.2, 0, 35.0), PI * 0.5)
	add_prop("desert_carpet", Vector3(29.6, 0, 35.0), PI * 0.5 + 0.05)
	add_stash(Vector3(47.2, 0, 35.0), -PI * 0.5)
	add_obstacle("desert_pots", Vector3(48.4, 0, 31.6), 0.6, 1.0, 0.7, {"cutout": false})
	add_obstacle("desert_pots", Vector3(23.4, 0, 39.4), 2.1, 0.9, 0.7, {"cutout": false})
	# The way out: through the open gate to the grid's north edge (the road to the river starts
	# there), and where a town portal's way back opens.
	carve_rect(Rect2i(17, 0, 2, 6))
	add_exit("wilds", Vector3(37, 0, 1), Vector2i(0, -1))
	portal_spot = {"pos": Vector3(44.5, 0, 18.5), "yaw": 0.0}
	keep(portal_spot["pos"], 2.4)
	for b in [Vector3(31.0, 0, 14.2), Vector3(41.0, 0, 14.2), Vector3(31.0, 0, 30.5), Vector3(41.0, 0, 30.5)]:
		add_obstacle("desert_brazier", b, 0.0, 1.0, 0.45, {"cutout": false})
		add_light(b + Vector3(0, 2.1, 0), Color(1.0, 0.66, 0.3), 1.5, 6.5, true)
		add_glow(b, 2.2, Color(1.0, 0.62, 0.28))
	# --- palm planters along the main street and in the plaza ----------------------------------
	for p in [Vector3(31.2, 0, 21.5), Vector3(40.8, 0, 21.5), Vector3(31.2, 0, 45.5), Vector3(40.8, 0, 45.5),
			Vector3(22.0, 0, 45.5), Vector3(50.0, 0, 45.5), Vector3(22.0, 0, 21.0), Vector3(50.2, 0, 22.0)]:
		add_obstacle("desert_planter", p, rng.randf() * TAU, 1.0, 0.85, {"cutout": false})
		add_prop("desert_palm_a" if rng.randf() < 0.6 else "desert_palm_b", p, rng.randf() * TAU, rng.randf_range(0.72, 0.88),
			{"cutout": true, "sway": 0.45, "sway_base": 2.0})
	# --- clutter: carpets, pots by the doors ---------------------------------------------------
	for c in [[Vector3(21.2, 0, 27.0), PI * 0.5], [Vector3(50.8, 0, 40.0), -PI * 0.5], [Vector3(36.0, 0, 41.5), 0.0]]:
		add_prop("desert_carpet", c[0], c[1] + rng.randf_range(-0.1, 0.1))
	for p in [Vector3(21.5, 0, 50.0), Vector3(50.3, 0, 27.6), Vector3(21.3, 0, 17.8), Vector3(50.6, 0, 50.0)]:
		add_obstacle("desert_pots", p, rng.randf() * TAU, rng.randf_range(0.8, 1.0), 0.6, {"cutout": false})
	# small garden shrubs by the house fronts
	for g in [Vector3(20.2, 0, 23.6), Vector3(20.2, 0, 30.6), Vector3(19.4, 0, 43.2), Vector3(20.2, 0, 47.4),
			Vector3(51.8, 0, 24.8), Vector3(51.8, 0, 36.6), Vector3(52.4, 0, 43.4), Vector3(52.0, 0, 47.6)]:
		add_prop("desert_shrub", g, rng.randf() * TAU, rng.randf_range(0.45, 0.6), {"shadows": false})
	# --- market stalls along the southern street ------------------------------------------------
	add_block("desert_awning", Vector3(26.6, 0, 50.5), PI * 0.5, Vector2(3.8, 3.2), {"height": 2.6})
	add_block("desert_awning", Vector3(45.4, 0, 50.5), -PI * 0.5, Vector2(3.8, 3.2), {"height": 2.6})
	add_prop("desert_carpet", Vector3(29.3, 0, 50.5), PI * 0.5 + 0.08)
	add_prop("desert_carpet", Vector3(42.7, 0, 50.5), -PI * 0.5 - 0.06)
	# --- paving: gate forecourt, main street and the plaza --------------------------------------
	var paved := {}
	for j in range(6, 28):
		for i in range(16, 20):
			paved[Vector2i(i, j)] = true
	for j in range(13, 21):
		for i in range(11, 25):
			paved[Vector2i(i, j)] = true
	for j in range(6, 9):
		for i in range(12, 24):
			paved[Vector2i(i, j)] = true
	for j in range(0, 6):
		for i in range(17, 19):
			paved[Vector2i(i, j)] = true
	var cells: Array = []
	for c in paved:
		if grid.is_floor(c):
			cells.append(c)
	add_tiles(["desert_tile_a", "desert_tile_b"], cells, Color(1, 1, 1), [Color(1, 1, 1), Color(0.97, 0.95, 0.92), Color(1.02, 1.0, 0.96)])
	# --- outside the walls: dunes, palms and the pyramids on the horizon -----------------------
	add_prop("desert_pyramid", Vector3(-8, 0, -44), 0.25, 1.0, {"shadows": true})
	add_prop("desert_pyramid", Vector3(58, 0, -62), 0.1, 0.8, {"shadows": true})
	add_prop("desert_pyramid", Vector3(104, 0, -30), 0.4, 0.55, {"shadows": true})
	_pyramids = [[-8.0, -44.0, 20.0], [58.0, -62.0, 16.0], [104.0, -30.0, 11.0]]
	scatter({"desert_palm_a": 3.0, "desert_palm_b": 2.0}, 40, Rect2(64, -10, 60, 90), {"min_dist": 4.5, "scale": Vector2(0.85, 1.15), "sway": 0.45, "sway_base": 2.0})
	scatter({"desert_palm_a": 1.0, "desert_palm_b": 1.0}, 14, Rect2(-40, 0, 44, 70), {"min_dist": 5.0, "sway": 0.45, "sway_base": 2.0})
	scatter(["desert_rock"], 18, Rect2(-50, -80, 190, 200), {"min_dist": 12.0, "margin": 6.0, "scale": Vector2(0.8, 1.5)})
	_ground_fx_hub()


# ------------------------------------------------------------------ wilds: the outdoor zones

func _wilds() -> void:
	var t0 := Time.get_ticks_usec()
	use_layout()
	has_water = true
	water_level = -0.35
	_init_fields()
	for t in TRAILS:
		_trail(t[0], float(t[1]))
	# Water (the river, the pool, the marsh channels, the sacred lake) and the ways across it.
	_water_line(RIVER, RIVER_HW, 2.4)
	for ch in CHANNELS:
		_water_line(ch[0], ch[1], 1.6)
	for pl in POOLS:
		_water_ellipse(pl[0], pl[1], float(pl[2]))
	_water_box(LAKE)
	_carve_water()
	var crossings: Array = []
	for cr in CROSSINGS:
		crossings.append({"rect": _carve_crossing(cr[0], int(cr[1]), int(cr[2])), "axis": int(cr[1]), "kind": String(cr[3]), "at": cr[0]})
	# Dune ridges and rock outcrops.
	var mounds: Array = []
	for m in MOUNDS:
		mounds.append(_mound(m[0], m[1], float(m[2]), float(m[3]), String(m[4])))
	_auto_mounds(mounds)
	_connect_all()
	prof["water_mounds"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	water_rects = []
	for wr in [_water_bounds(RIVER, RIVER_HW), Rect2(-40, 280, 222, 250), Rect2(20, 130, 130, 90)]:
		water_rects.append((wr as Rect2).intersection(ground_rect))
	# Relief, fertility, the palette.
	_bake_fields()
	prof["fields"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	# The zones.
	_paint_crossings(crossings)
	_paint_mounds(mounds)
	_paint_outskirts()
	_paint_oasis()
	_paint_isles()
	_paint_graveyard()
	_paint_courtyard()
	_paint_gateways()
	_paint_banks()
	_paint_offmap()
	prof["paint"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	# Monsters.
	refresh_open_field()
	_populate()
	prof["monsters"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_ground_fx_wilds()
	prof["ground_fx"] = (Time.get_ticks_usec() - t0) / 1000.0


# ------------------------------------------------------------------ fields

func _init_fields() -> void:
	_gw = grid.size.x
	_gh = grid.size.y
	_umax = _gw - 1.001
	_vmax = _gh - 1.001
	_fa = PackedColorArray()
	_fa.resize(_gw * _gh)
	_fa.fill(Color(FAR_WATER, 0.0, 0.0, 0.0))
	_dn = FastNoiseLite.new()
	_dn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dn.fractal_type = FastNoiseLite.FRACTAL_FBM
	_dn.fractal_octaves = 3
	_dn.frequency = 0.011
	_dn.seed = 71
	_cn = FastNoiseLite.new()
	_cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cn.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cn.fractal_octaves = 3
	_cn.frequency = 0.07
	_cn.seed = 97
	_bn = FastNoiseLite.new()
	_bn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_bn.fractal_type = FastNoiseLite.FRACTAL_FBM
	_bn.fractal_octaves = 2
	_bn.frequency = 0.014
	_bn.seed = 131
	# Where the composer puts the town: its exit cell faces ours across the road.
	var ex: Dictionary = exits.get("hub", {})
	var ec := world_to_cell(ex.get("pos", Vector3(_gw, 0, _gh * TILE)))
	_hub_off = Vector2((ec.x - HUB_EXIT_CELL.x) * TILE, (_gh + WorldActComposite.EXIT_GAP_CELLS - HUB_EXIT_CELL.y) * TILE)
	_c_sand = Color(0.91, 0.76, 0.53).srgb_to_linear()
	_c_mud = Color(0.69, 0.59, 0.45).srgb_to_linear()
	_c_damp = Color(0.55, 0.58, 0.36).srgb_to_linear()
	_c_pale = Color(1.1, 1.08, 1.06)
	_c_dusk = Color(0.9, 0.84, 0.8)
	_c_bed = Color(0.33, 0.31, 0.23).srgb_to_linear()
	_c_green = Color(0.43, 0.53, 0.22).srgb_to_linear()
	_c_green_b = Color(0.55, 0.61, 0.28).srgb_to_linear()
	_c_silt = Color(0.34, 0.28, 0.2).srgb_to_linear()
	_c_crest = Color(0.97, 0.85, 0.62).srgb_to_linear()
	_c_trail = Color(1.2, 1.14, 1.04)
	_c_gravel = Color(0.8, 0.74, 0.7)


## Open water along a polyline (half widths per point): the signed distance to its banks goes into
## the water field (banks wobble by up to `wobble` m).
func _water_line(pts: Array, hw: Array, wobble: float) -> void:
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ha := float(hw[k])
		var hb := float(hw[k + 1])
		var m := maxf(ha, hb) + 24.0
		var i0 := clampi(floori((minf(a.x, b.x) - m) / TILE), 0, _gw - 1)
		var i1 := clampi(floori((maxf(a.x, b.x) + m) / TILE), 0, _gw - 1)
		var j0 := clampi(floori((minf(a.y, b.y) - m) / TILE), 0, _gh - 1)
		var j1 := clampi(floori((maxf(a.y, b.y) + m) / TILE), 0, _gh - 1)
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.001)
		for j in range(j0, j1 + 1):
			var pz := (j + 0.5) * TILE
			for i in range(i0, i1 + 1):
				var p := Vector2((i + 0.5) * TILE, pz)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t) - lerpf(ha, hb, t)
				if d < 8.0:
					d -= _cn.get_noise_2d(p.x * 1.6, p.y * 1.6) * wobble
				var idx := j * _gw + i
				var c := _fa[idx]
				if d < c.r:
					c.r = d
					_fa[idx] = c


func _water_ellipse(cen: Vector2, rad: Vector2, rot: float) -> void:
	var m := maxf(rad.x, rad.y) + 24.0
	var cr := cos(rot)
	var sr := sin(rot)
	var rmin := minf(rad.x, rad.y)
	for j in range(clampi(floori((cen.y - m) / TILE), 0, _gh - 1), clampi(floori((cen.y + m) / TILE), 0, _gh - 1) + 1):
		for i in range(clampi(floori((cen.x - m) / TILE), 0, _gw - 1), clampi(floori((cen.x + m) / TILE), 0, _gw - 1) + 1):
			var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE) - cen
			var q := Vector2(p.x * cr + p.y * sr, -p.x * sr + p.y * cr)
			var d := (Vector2(q.x / rad.x, q.y / rad.y).length() - 1.0) * rmin - _cn.get_noise_2d(p.x * 1.9, p.y * 1.9) * 1.4
			var idx := j * _gw + i
			var c := _fa[idx]
			if d < c.r:
				c.r = d
				_fa[idx] = c


func _water_box(r: Rect2) -> void:
	var cen := r.get_center()
	var half := r.size * 0.5
	for j in range(clampi(floori((r.position.y - 24.0) / TILE), 0, _gh - 1), clampi(floori((r.end.y + 24.0) / TILE), 0, _gh - 1) + 1):
		for i in range(clampi(floori((r.position.x - 24.0) / TILE), 0, _gw - 1), clampi(floori((r.end.x + 24.0) / TILE), 0, _gw - 1) + 1):
			var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE) - cen
			var d := maxf(absf(p.x) - half.x, absf(p.y) - half.y)
			var idx := j * _gw + i
			var c := _fa[idx]
			if d < c.r:
				c.r = d
				_fa[idx] = c


func _water_bounds(pts: Array, hw: Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for k in pts.size():
		var h := float(hw[k]) + 6.0
		r = r.expand(pts[k] + Vector2(h, h)).expand(pts[k] - Vector2(h, h))
	return r


## Open water is not walkable ground (void, see-through).
func _carve_water() -> void:
	for k in _fa.size():
		if _fa[k].r < WATER_CUT and grid.floor_cells[k] == 1:
			var c := Vector2i(k % _gw, k / _gw)
			grid.set_void(c)
			grid.set_opaque(c, false)


## A walkable strip `w` cells wide across the water at `centre` (axis 0: the path runs N-S), as long
## as the water there. Returns the strip (m).
func _carve_crossing(centre: Vector2, axis: int, w: int) -> Rect2:
	var c0 := Vector2i(floori(centre.x / TILE), floori(centre.y / TILE))
	var first := roundi((centre.x if axis == 0 else centre.y) / TILE - w * 0.5)
	var ext := [0, 0]
	for side in 2:
		var dir := -1 if side == 0 else 1
		var s := 1
		while s < 45:
			var wet := false
			for n in w:
				var c := Vector2i(first + n, c0.y + dir * s) if axis == 0 else Vector2i(c0.x + dir * s, first + n)
				if in_bounds(c) and _fa[c.y * _gw + c.x].r < WATER_CUT:
					wet = true
			if not wet:
				break
			s += 1
		ext[side] = s
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in range(-int(ext[0]), int(ext[1]) + 1):
		for n in w:
			var c := Vector2i(first + n, c0.y + s) if axis == 0 else Vector2i(c0.x + s, first + n)
			if not in_bounds(c) or region_of_cell(c) == "":
				continue
			grid.set_floor(c, true)
			_crossing_cells[c] = true
			lo = lo.min(Vector2(c.x, c.y) * TILE)
			hi = hi.max(Vector2(c.x + 1, c.y + 1) * TILE)
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2(centre, Vector2.ZERO)


## A dune ridge or rock outcrop: its cells become solid open ground (soft: its own collision boxes,
## no border ruins around it) and the relief field rises over it. Returns its description.
func _mound(cen: Vector2, rad: Vector2, rot: float, height: float, kind: String) -> Dictionary:
	var cr := cos(rot)
	var sr := sin(rot)
	var cells := {}
	var m := maxf(rad.x, rad.y) + 4.0
	for j in range(clampi(floori((cen.y - m) / TILE), 0, _gh - 1), clampi(floori((cen.y + m) / TILE), 0, _gh - 1) + 1):
		for i in range(clampi(floori((cen.x - m) / TILE), 0, _gw - 1), clampi(floori((cen.x + m) / TILE), 0, _gw - 1) + 1):
			var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE) - cen
			var q := Vector2((p.x * cr + p.y * sr) / rad.x, (-p.x * sr + p.y * cr) / rad.y).length()
			q += _cn.get_noise_2d(p.x * 2.3 + cen.x, p.y * 2.3) * 0.12
			var c := Vector2i(i, j)
			var idx := j * _gw + i
			if q < 1.25:
				var f := _fa[idx]
				f.g += height * pow(maxf(0.0, 1.0 - q * q / 1.5625), 1.5)
				_fa[idx] = f
			if q < 1.0 and grid.floor_cells[idx] == 1 and not _crossing_cells.has(c):
				grid.set_void(c)
				grid.set_opaque(c, false)
				soft[c] = true
				cells[c] = true
	_add_cell_boxes(cells)
	return {"at": cen, "rad": rad, "rot": rot, "kind": kind, "cells": cells}


## More dune ridges and rock outcrops over the dry near bank of the Iteru, on a jittered grid:
## inside the outskirts, clear of the trails, the water, the fields, the landmarks and each other.
func _auto_mounds(mounds: Array) -> void:
	var avoid: Array = [[Vector2(205, 330), 30.0], [Vector2(448, 395), 22.0], [Vector2(338, 466), 18.0], [Vector2(392, 408), 14.0],
		[Vector2(262, 392), 14.0], [Vector2(299, 470), 20.0], [Vector2(236, 330), 14.0], [Vector2(300, 370), 16.0], [Vector2(222, 458), 18.0]]
	for m in mounds:
		avoid.append([m["at"], maxf((m["rad"] as Vector2).x, (m["rad"] as Vector2).y) + 8.0])
	var area := Rect2(176, 268, 300, 216)
	var step := 26.0
	var y := area.position.y
	var why := {}
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			var c := Vector2(x + rng.randf_range(0.0, step * 0.7), y + rng.randf_range(0.0, step * 0.7))
			x += step
			var rock := rng.randf() < 0.4
			var rad := Vector2(rng.randf_range(5.0, 8.0), rng.randf_range(4.0, 6.0)) if rock else Vector2(rng.randf_range(9.0, 14.0), rng.randf_range(4.5, 6.5))
			var rot := rng.randf() * PI
			var reach := maxf(rad.x, rad.y)
			var fail := ""
			for a in avoid:
				if c.distance_to(a[0]) < float(a[1]) + reach * 0.8:
					fail = "near"
					break
			if fail == "":
				for fr in FIELDS:
					if (fr as Rect2).grow(reach + 6.0).has_point(c):
						fail = "field"
			if fail == "":
				var m2 := reach + 3.0
				for j in range(floori((c.y - m2) / TILE), floori((c.y + m2) / TILE) + 1):
					for i in range(floori((c.x - m2) / TILE), floori((c.x + m2) / TILE) + 1):
						var cc := Vector2i(i, j)
						if Vector2((i + 0.5) * TILE, (j + 0.5) * TILE).distance_to(c) > m2:
							continue
						if not in_bounds(cc) or not grid.is_walkable_cell(cc) or region_of_cell(cc) != "outskirts":
							fail = "edge"
							break
						var f := _fa[j * _gw + i]
						if f.b > 0.1:
							fail = "trail"
							break
						if f.r < 16.0:
							fail = "water"
							break
					if fail != "":
						break
			if fail != "":
				why[fail] = int(why.get(fail, 0)) + 1
				continue
			mounds.append(_mound(c, rad, rot, 0.3 if rock else rng.randf_range(2.8, 4.0), "rock" if rock else "dune"))
			avoid.append([c, reach + 8.0])
			why["placed"] = int(why.get("placed", 0)) + 1
		y += step
	prof["auto_mounds"] = why


## Collision for a set of cells: greedy row-major rectangles.
func _add_cell_boxes(cells: Dictionary) -> void:
	var keys: Array = cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var used := {}
	for key in keys:
		var c: Vector2i = key
		if used.has(c):
			continue
		var rw := 1
		while cells.has(c + Vector2i(rw, 0)) and not used.has(c + Vector2i(rw, 0)):
			rw += 1
		var rh := 1
		var grow := true
		while grow:
			for x in rw:
				var q := c + Vector2i(x, rh)
				if not cells.has(q) or used.has(q):
					grow = false
					break
			if grow:
				rh += 1
		for y in rh:
			for x in rw:
				used[c + Vector2i(x, y)] = true
		shapes.append({"type": "box", "pos": Vector3((c.x + rw * 0.5) * TILE, 0.0, (c.y + rh * 0.5) * TILE),
			"size": Vector3(rw * TILE, 3.0, rh * TILE), "yaw": 0.0})


## Every walkable cell must be reachable from the start: slivers the water cut off become water,
## bigger pieces get a land bridge to the reachable ground.
func _connect_all() -> void:
	for attempt in 4:
		var reach := grid.flood_walkable(world_to_cell(start))
		var comps := _unreached(reach)
		if comps.is_empty():
			return
		var bridged := false
		for comp in comps:
			var cells: Array = comp
			if cells.size() < 40:
				for c in cells:
					grid.set_void(c)
					grid.set_opaque(c, false)
			else:
				push_warning("act_desert: %d cells cut off near %s; bridging" % [cells.size(), cell_center(cells[0])])
				_bridge_to(cells, reach)
				bridged = true
		if not bridged:
			return


func _unreached(reach: PackedByteArray) -> Array:
	var out: Array = []
	var seen := PackedByteArray()
	seen.resize(_gw * _gh)
	for k in _gw * _gh:
		if grid.walk[k] == 0 or reach[k] == 1 or seen[k] == 1:
			continue
		var comp: Array = []
		var stack: Array[Vector2i] = [Vector2i(k % _gw, k / _gw)]
		seen[k] = 1
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if in_bounds(n):
					var nk := n.y * _gw + n.x
					if seen[nk] == 0 and grid.walk[nk] == 1 and reach[nk] == 0:
						seen[nk] = 1
						stack.append(n)
		out.append(comp)
	return out


## Carve the shortest way (2 cells wide) from a cut-off piece to the reachable ground.
func _bridge_to(cells: Array, reach: PackedByteArray) -> void:
	var parent := {}
	var queue: Array[Vector2i] = []
	for c in cells:
		parent[c] = c
		queue.append(c)
	var head := 0
	var goal := Vector2i(-1, -1)
	while head < queue.size() and head < 60000:
		var c: Vector2i = queue[head]
		head += 1
		if reach[c.y * _gw + c.x] == 1:
			goal = c
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if in_bounds(n) and not parent.has(n):
				parent[n] = c
				queue.append(n)
	var c2 := goal
	while c2.x >= 0 and parent.has(c2) and parent[c2] != c2:
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = c2 + d
			if in_bounds(q) and region_of_cell(q) != "":
				grid.set_floor(q, true)
				_crossing_cells[q] = true
		c2 = parent[c2]


## Relief (dunes off the walkable ground), fertility near water and the per-cell palette (the
## zones' colours, soft where zones meet, with broad tones, wind streaks and gravel patches).
func _bake_fields() -> void:
	_bake_amp()
	var pal_region: Array = [_c_sand]
	for r in regions:
		pal_region.append(_region_base(String(r["id"])))
	_pal = PackedColorArray()
	_pal.resize(_gw * _gh)
	for k in _gw * _gh:
		_pal[k] = pal_region[int(region_map[k])]
	for l in layout_data.get("links", []):
		_blend_link(l)
	var fert_region := {"outskirts": 1.0, "oasis": 1.25, "isles": 1.15, "graveyard": 0.25, "courtyard": 0.0}
	var floor_region := {"oasis": 0.22, "isles": 0.3}
	var fert_by_index: Array = [0.8]
	var floor_by_index: Array = [0.0]
	for r in regions:
		fert_by_index.append(float(fert_region.get(String(r["id"]), 1.0)))
		floor_by_index.append(float(floor_region.get(String(r["id"]), 0.0)))
	var walk := grid.walk
	var fl := grid.floor_cells
	var court_i := int(_region_index.get("courtyard", -1))
	var fake := PackedFloat32Array()
	fake.resize(_gw * _gh)
	var drift := _edge_steps(10)
	for j in _gh:
		var z := (j + 0.5) * TILE
		var row := j * _gw
		for i in _gw:
			var k := row + i
			var x := (i + 0.5) * TILE
			var f := _fa[k]
			var ri := int(region_map[k])
			# the dune pattern (real relief off the walkable ground, painted shading on it)
			var dn := _dn.get_noise_2d(x, z)
			var rg := 1.0 - absf(sin(x * 0.041 + z * 0.017 + dn * 3.5))
			fake[k] = 2.6 * dn + 2.2 * rg * rg
			if walk[k] == 0 and fl[k] == 0:
				f.g += _dune_shape(1.4 + fake[k], x, z)
				# sand drifted up against the edge of the walkable ground (over the ruined walls)
				var ds := int(drift[k])
				if ds > 1 and f.r > 3.0:
					f.g += 1.9 * smoothstep(1.0, 4.0, ds - 1.0) * (1.0 - smoothstep(6.0, 11.0, ds - 1.0)) * (0.7 + 0.3 * _cn.get_noise_2d(x * 1.3, z * 1.3))
			if f.r < 20.0:
				f.a = maxf(f.a, (1.0 - smoothstep(2.0, 18.0, f.r)) * float(fert_by_index[ri]))
			var c := _vary(_pal[k], x, z, ri != court_i)
			if ri > 0 and walk[k] == 1:
				f.a = maxf(f.a, float(floor_by_index[ri]) * (0.55 + 0.9 * c.a))
			_fa[k] = f
			_pal[k] = c
	# Gentle dunes painted on the flat walkable sand: light on the slopes toward the sun (south-east),
	# shade on the lee side.
	for j2 in range(1, _gh - 1):
		for i2 in range(1, _gw - 1):
			var k2 := j2 * _gw + i2
			if walk[k2] == 0 or int(region_map[k2]) == court_i:
				continue
			var hx := (fake[k2 + 1] - fake[k2 - 1]) / (2.0 * TILE)
			var hz := (fake[k2 + _gw] - fake[k2 - _gw]) / (2.0 * TILE)
			var shade := clampf(1.0 + 1.2 * (0.47 * hx + 0.6 * hz), 0.8, 1.18)
			var pc := _pal[k2]
			_pal[k2] = Color(pc.r * shade, pc.g * shade, pc.b * shade, pc.a)


## Per cell: 1 on walkable (or solid floor) ground, else 1 + the steps (4-neighbour) out to it,
## up to `limit` (0 = farther away).
func _edge_steps(limit: int) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(_gw * _gh)
	var queue := PackedInt32Array()
	var fl := grid.floor_cells
	for j in _gh:
		for i in _gw:
			var k := j * _gw + i
			if fl[k] == 0 and not soft.has(Vector2i(i, j)):
				continue
			d[k] = 1
			if (i > 0 and fl[k - 1] == 0) or (i < _gw - 1 and fl[k + 1] == 0) or (j > 0 and fl[k - _gw] == 0) or (j < _gh - 1 and fl[k + _gw] == 0):
				queue.append(k)
	var head := 0
	while head < queue.size():
		var k2 := queue[head]
		head += 1
		var st := d[k2]
		if st > limit:
			continue
		var i2 := k2 % _gw
		for nk in [k2 - 1 if i2 > 0 else -1, k2 + 1 if i2 < _gw - 1 else -1, k2 - _gw, k2 + _gw]:
			if nk >= 0 and nk < d.size() and d[nk] == 0:
				d[nk] = st + 1
				queue.append(nk)
	return d


## The zones' ground palettes (sRGB picks -> linear).
func _region_base(id: String) -> Color:
	match id:
		"oasis":
			return Color(0.8, 0.7, 0.5).srgb_to_linear()
		"isles":
			return Color(0.67, 0.61, 0.45).srgb_to_linear()
		"graveyard":
			return Color(0.8, 0.67, 0.57).srgb_to_linear()
		"courtyard":
			return Color(0.88, 0.78, 0.6).srgb_to_linear()
	return Color(0.86, 0.73, 0.53).srgb_to_linear()


func _blend_link(l: Dictionary) -> void:
	var at_: Array = l["at"]
	var p := Vector2((float(at_[0]) + 0.5) * TILE, (float(at_[1]) + 0.5) * TILE)
	var ia := int(_region_index.get(String(l["a"]), 0))
	var ib := int(_region_index.get(String(l["b"]), 0))
	if ia == 0 or ib == 0:
		return
	# Which way the path runs: from region a to region b.
	var dir := Vector2.ZERO
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if region_at(Vector3(p.x, 0, p.y) + Vector3(d.x, 0, d.y) * 8.0) == String(l["b"]):
			dir = d
	if dir == Vector2.ZERO:
		return
	var ca := _region_base(String(l["a"]))
	var cb := _region_base(String(l["b"]))
	var half := float(l.get("width_cells", 10)) * TILE * 0.5 + 6.0
	for j in range(floori((p.y - 16.0) / TILE), floori((p.y + 16.0) / TILE) + 1):
		for i in range(floori((p.x - 16.0) / TILE), floori((p.x + 16.0) / TILE) + 1):
			var c := Vector2i(i, j)
			if not in_bounds(c):
				continue
			var q := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE) - p
			if absf(q.dot(Vector2(-dir.y, dir.x))) > half:
				continue
			var ri := int(region_map[j * _gw + i])
			if ri != ia and ri != ib:
				continue
			_pal[j * _gw + i] = ca.lerp(cb, smoothstep(-12.0, 12.0, q.dot(dir)))


## Coarse field: how far the ground lies from anywhere walkable (dunes rise away from the zones).
func _bake_amp() -> void:
	_ax0 = -48.0
	_az0 = -48.0
	_aw = int(ceil((_gw * TILE + 96.0) / AMP_CELL)) + 1
	_ah = int(ceil((_gh * TILE + 210.0) / AMP_CELL)) + 1
	var g := WorldGrid.new()
	g.setup(Vector2i(_aw, _ah))
	for k in g.walk.size():
		g.walk[k] = 1
	for k in grid.walk.size():
		if grid.walk[k] == 1 or (grid.floor_cells[k] == 1 and soft.has(Vector2i(k % _gw, k / _gw))):
			var ci := floori(((k % _gw + 0.5) * TILE - _ax0) / AMP_CELL)
			var cj := floori(((k / _gw + 0.5) * TILE - _az0) / AMP_CELL)
			g.walk[cj * _aw + ci] = 0
	var d := WorldActGen.distance_to_blocked(g)
	_amp = PackedFloat32Array()
	_amp.resize(d.size())
	for k in d.size():
		_amp[k] = smoothstep(0.0, 22.0, d[k] * (AMP_CELL / TILE))


func _amp_at(x: float, z: float) -> float:
	var u := clampf((x - _ax0) / AMP_CELL - 0.5, 0.0, _aw - 1.001)
	var v := clampf((z - _az0) / AMP_CELL - 0.5, 0.0, _ah - 1.001)
	var i := int(u)
	var j := int(v)
	var k := j * _aw + i
	return lerpf(lerpf(_amp[k], _amp[k + 1], u - i), lerpf(_amp[k + _aw], _amp[k + _aw + 1], u - i), v - j)


## Dunes (m) off the walkable ground: long wind ridges over swells, rising away from the zones;
## near the town they become the town's own dunes.
func _dune_height(x: float, z: float) -> float:
	var n := _dn.get_noise_2d(x, z)
	var ridge := 1.0 - absf(sin(x * 0.041 + z * 0.017 + n * 3.5))
	return _dune_shape(1.4 + 2.6 * n + 2.2 * ridge * ridge, x, z)


## Dune height from the raw dune pattern: scaled by the distance from the zones, turning into the
## town's dunes near it.
func _dune_shape(raw: float, x: float, z: float) -> float:
	var h := _amp_at(x, z) * maxf(0.0, raw)
	if z > SOUTH_BLEND.x:
		var tw := _town_weight(x, z)
		if tw > 0.0:
			h = lerpf(h, _dunes(x - _hub_off.x, z - _hub_off.y), tw)
	return h


## How much of the town zone's own ground (colours, dunes) shows at x, z: all of it along the town
## zone's ground south of the road (so the two meet without a seam), none far to its sides.
func _town_weight(x: float, z: float) -> float:
	var hx0 := _hub_off.x - 60.0
	var hx1 := _hub_off.x + 136.0
	var side := maxf(hx0 - x, x - hx1)
	return smoothstep(SOUTH_BLEND.x, SOUTH_BLEND.y, z) * (1.0 - smoothstep(0.0, 60.0, side))


## A worn trail along the polyline (half width in m) in the trail field.
func _trail(pts: Array, hw: float) -> void:
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var m := hw + 3.0
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.001)
		for j in range(clampi(floori((minf(a.y, b.y) - m) / TILE), 0, _gh - 1), clampi(floori((maxf(a.y, b.y) + m) / TILE), 0, _gh - 1) + 1):
			for i in range(clampi(floori((minf(a.x, b.x) - m) / TILE), 0, _gw - 1), clampi(floori((maxf(a.x, b.x) + m) / TILE), 0, _gw - 1) + 1):
				var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var w := hw + _cn.get_noise_2d(p.x * 2.1, p.y * 2.1) * 0.9
				var v := 1.0 - smoothstep(w - 1.0, w + 1.6, p.distance_to(a + ab * t))
				var idx := j * _gw + i
				var f := _fa[idx]
				if v > f.b:
					f.b = v
					_fa[idx] = f


## Field (fertility) over a rectangle, soft at its rim.
func _fertile(r: Rect2, v: float) -> void:
	for j in range(clampi(floori((r.position.y - 4.0) / TILE), 0, _gh - 1), clampi(floori((r.end.y + 4.0) / TILE), 0, _gh - 1) + 1):
		for i in range(clampi(floori((r.position.x - 4.0) / TILE), 0, _gw - 1), clampi(floori((r.end.x + 4.0) / TILE), 0, _gw - 1) + 1):
			var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE)
			var d := maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(r.position.y - p.y, p.y - r.end.y))
			var idx := j * _gw + i
			var f := _fa[idx]
			f.a = maxf(f.a, v * (1.0 - smoothstep(-1.0, 3.0, d)))
			_fa[idx] = f


# ------------------------------------------------------------------ field queries & placement

func _field_at(p: Vector3) -> Color:
	var c := world_to_cell(p)
	if not in_bounds(c):
		return Color(FAR_WATER, 0.0, 0.0, 0.0)
	return _fa[c.y * _gw + c.x]


func _water_at(p: Vector3) -> float:
	return _field_at(p).r


func _trail_at(p: Vector3) -> float:
	return _field_at(p).b


## Height of the finished ground at p (the World flattens relief next to walkable ground).
func _terrain_y(p: Vector3) -> float:
	var h := _wilds_height(p.x, p.z)
	if absf(h) < 0.01:
		return 0.0
	return h * smoothstep(1.2, 4.5, walk_distance(p))


## A walkable, clear spot of region `rid` near p (spiral search up to `reach` m), off the trails;
## Vector3.INF if none.
func _spot(p: Vector3, r: float, rid: String = "", reach: float = 8.0, max_trail: float = 0.35) -> Vector3:
	for ring in int(reach) + 1:
		var n := maxi(1, ring * 6)
		for k in n:
			var a := TAU * k / n + ring * 0.7
			var q := p + Vector3(cos(a), 0.0, sin(a)) * float(ring)
			var c := world_to_cell(q)
			if not is_walkable_cell(c):
				continue
			if rid != "" and region_of_cell(c) != rid:
				continue
			if _fa[c.y * _gw + c.x].b > max_trail:
				continue
			if not is_clear(q, r):
				continue
			return q
	return Vector3.INF


func _chest(p: Vector3, yaw: float, tier: int, rid: String) -> void:
	var q := _spot(p, 1.7, rid, 10.0)
	if q != Vector3.INF:
		add_chest(q, yaw, tier)


func _shrine(p: Vector3, rid: String, kind: String = "") -> void:
	var q := _spot(p, 2.2, rid, 10.0)
	if q != Vector3.INF:
		add_shrine(q, rng.randf() * TAU, kind)


## A solid round prop on walkable ground (collision), a plain prop set on the terrain elsewhere.
func _solid(id: String, p: Vector3, yaw: float, sc: float, radius: float, opts: Dictionary = {}) -> void:
	if is_walkable_at(p):
		add_obstacle(id, Vector3(p.x, 0.0, p.z), yaw, sc, radius * sc, opts)
	else:
		add_prop(id, Vector3(p.x, _terrain_y(p) - 0.1, p.z), yaw, sc, opts)


## A solid block prop where there is room for it (all its cells walkable or open, clear of
## keep-outs); returns whether it was placed.
func _block_if_free(id: String, p: Vector3, yaw: float, size: Vector2, opts: Dictionary = {}, max_trail: float = 0.3) -> bool:
	var r := size.length() * 0.5
	if not is_clear(p, r * 0.8):
		return false
	var basis := Basis(Vector3.UP, yaw)
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			var q := p + basis * Vector3(size.x * sx, 0.0, size.y * sz)
			var c := world_to_cell(q)
			if not in_bounds(c) or _crossing_cells.has(c) or _fa[c.y * _gw + c.x].r < 1.5 or _fa[c.y * _gw + c.x].b > max_trail:
				return false
	add_block(id, p, yaw, size, opts)
	return true


## Points every `step` m along a polyline.
func _along(pts: Array, step: float) -> Array:
	var out: Array = []
	var carry := 0.0
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ln := a.distance_to(b)
		var s := carry
		while s < ln:
			out.append({"p": a.lerp(b, s / ln), "dir": (b - a) / ln})
			s += step
		carry = s - ln
	return out


func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## Yaw that turns a model's front (+Z) toward `dir` (x, z).
static func _face(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


# ------------------------------------------------------------------ painting: crossings & mounds

func _paint_crossings(crossings: Array) -> void:
	for cr in crossings:
		var r: Rect2 = cr["rect"]
		if r.size.x <= 0.0:
			continue
		var axis := int(cr["axis"])
		var mid := r.get_center()
		var along := r.size.y if axis == 0 else r.size.x
		var yaw := 0.0 if axis == 0 else PI * 0.5
		var cells: Array = []
		for j in range(floori(r.position.y / TILE), floori(r.end.y / TILE)):
			for i in range(floori(r.position.x / TILE), floori(r.end.x / TILE)):
				var c := Vector2i(i, j)
				if _crossing_cells.has(c):
					cells.append(c)
		match String(cr["kind"]):
			"bridge":
				# The Great Bridge: the deck spans the water, obelisk finials mark both ends.
				add_prop("desert_bridge", _v3(mid), yaw, clampf(along / 30.0, 0.9, 1.25), OPT_TALL)
				keep(_v3(mid), 3.0)
			"causeway":
				add_tiles(["desert_tile_b", "desert_tile_a"], cells, Color(0.86, 0.8, 0.7), [Color(0.86, 0.8, 0.7), Color(0.78, 0.72, 0.62)])
				var side := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
				var dirv := Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
				var half := (r.size.x if axis == 0 else r.size.y) * 0.5
				for k in int(along / 3.2):
					var t := -along * 0.5 + 1.6 + k * 3.2
					for s: float in [-1.0, 1.0]:
						var p := _v3(mid) + dirv * t + side * s * (half + 0.9)
						if _water_at(p) < 0.5:
							add_prop("desert_rock", Vector3(p.x, -0.45, p.z), rng.randf() * TAU, rng.randf_range(0.35, 0.55), OPT_LOW)
			"ford":
				add_tiles(["desert_tile_b"], cells, Color(0.74, 0.7, 0.6), [Color(0.74, 0.7, 0.6), Color(0.66, 0.63, 0.55)])
				var side2 := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
				var dir2 := Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
				var half2 := (r.size.x if axis == 0 else r.size.y) * 0.5
				for k in int(along / 2.2):
					var t2 := -along * 0.5 + 1.1 + k * 2.2
					for s: float in [-1.0, 1.0]:
						var p2 := _v3(mid) + dir2 * t2 + side2 * s * (half2 + rng.randf_range(0.8, 2.2))
						if _water_at(p2) < 0.6:
							add_prop("desert_reeds", Vector3(p2.x, -0.55, p2.z), rng.randf() * TAU, rng.randf_range(0.8, 1.2), OPT_REEDS)
			_:
				add_prop("desert_footbridge", _v3(mid), yaw, clampf(along / 13.0, 0.8, 1.3))
				keep(_v3(mid), 2.0)


func _paint_mounds(mounds: Array) -> void:
	for m in mounds:
		var cen: Vector2 = m["at"]
		var rad: Vector2 = m["rad"]
		var rot := float(m["rot"])
		var cells: Dictionary = m["cells"]
		if cells.is_empty():
			continue
		keep(_v3(cen), minf(rad.x, rad.y))
		if String(m["kind"]) == "rock":
			var sc := minf(rad.x / 7.4, rad.y / 5.4) * 0.95
			add_prop("desert_mesa", _v3(cen), -rot, sc, OPT_TALL)
			for k in 7:
				var a := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
				var q := Vector2(cos(a) * rad.x * 1.02, sin(a) * rad.y * 1.02)
				var p := cen + Vector2(q.x * cos(rot) - q.y * sin(rot), q.x * sin(rot) + q.y * cos(rot))
				_solid("desert_rock", Vector3(p.x, 0.0, p.y), rng.randf() * TAU, rng.randf_range(0.5, 0.95), 1.2, OPT_TALL)
		else:
			# A dune: dry grass on its flanks, a half-buried ruin or bones now and then.
			for k in 9:
				var a2 := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
				var f := rng.randf_range(0.55, 1.05)
				var q2 := Vector2(cos(a2) * rad.x * f, sin(a2) * rad.y * f)
				var p2 := cen + Vector2(q2.x * cos(rot) - q2.y * sin(rot), q2.x * sin(rot) + q2.y * cos(rot))
				var y := _terrain_y(_v3(p2)) - 0.05
				add_prop("desert_grass", Vector3(p2.x, y, p2.y), rng.randf() * TAU, rng.randf_range(0.8, 1.3), OPT_LOW)


# ------------------------------------------------------------------ painting: Banks of the Iteru

func _paint_outskirts() -> void:
	var rid := "outskirts"
	# --- the avenue of ram sphinxes before the city gate, the caravan halt ---------------------
	for z: float in [446.0, 458.0, 470.0]:
		for s: float in [-1.0, 1.0]:
			var p := Vector3(299.0 + s * 9.5, 0, z)
			add_block("desert_sphinx_small", p, -s * PI * 0.5, Vector2(1.6, 3.6), {"height": 2.2})
	add_tiles(["desert_tile_b", "desert_tile_a"], _cells_along([Vector2(299, 500), Vector2(299, 440)], 2.6, 0.22),
		Color(0.93, 0.87, 0.78), [Color(0.93, 0.87, 0.78), Color(0.86, 0.8, 0.7)])
	var camp := Vector3(338, 0, 466)
	for t in [[Vector3(-8, 0, -3), 0.9], [Vector3(6, 0, -6), -0.5], [Vector3(10, 0, 5), -1.6]]:
		_block_if_free("desert_tent", camp + (t[0] as Vector3), float(t[1]), Vector2(4.6, 3.6), {"height": 2.4})
	add_prop("desert_carpet", camp + Vector3(0, 0, 1), 0.3)
	add_prop("desert_carpet", camp + Vector3(-3, 0, 4), 1.4)
	for c in [Vector3(-14, 0, 6), Vector3(-10, 0, 10)]:
		_solid("desert_camel", camp + c, rng.randf_range(-0.6, 0.6) + PI * 0.5, rng.randf_range(0.95, 1.05), 0.8, OPT_TALL)
	_solid("desert_pots", camp + Vector3(4, 0, 2), 0.4, 1.0, 0.6, {"cutout": false})
	_chest(camp + Vector3(1, 0, -3), 0.2, 0, rid)
	# --- the pyramid of the west bank and its sphinx -------------------------------------------
	add_block("desert_pyramid", Vector3(205, 0, 330), 0.0, Vector2(30, 30), {"height": 6.0, "opaque": true, "scale": 0.75})
	add_block("desert_sphinx", Vector3(236, 0, 330), PI * 0.5, Vector2(5.4, 12.6), {"height": 5.0, "opaque": true})
	add_block("desert_head", Vector3(224, 0, 356), 2.3, Vector2(4.4, 3.6), {"height": 3.0})
	add_block("desert_obelisk_fallen", Vector3(186, 0, 356), 0.5, Vector2(9.0, 2.2), {"height": 1.2, "cutout": false})
	# the two seated colossi on the near bank, looking toward the road and the river
	for cz in [362.0, 379.0]:
		add_block("desert_statue", Vector3(300, 0, cz), PI * 0.5, Vector2(4.2, 6.2), {"height": 6.0, "scale": 1.25})
	add_block("desert_pyramid", Vector3(222, 0, 458), 0.3, Vector2(16, 16), {"height": 5.0, "opaque": true, "scale": 0.4})
	add_block("desert_tomb", Vector3(246, 0, 446), -0.2, Vector2(8.0, 7.4), {"height": 4.0, "opaque": true})
	_chest(Vector3(228, 0, 344), PI * 0.5, 1, rid)
	_shrine(Vector3(246, 0, 316), rid)
	# --- the ruined temple by the river ---------------------------------------------------------
	var tc := Vector3(448, 0, 395)
	var floor_cells: Array = []
	for j in range(-4, 4):
		for i in range(-6, 6):
			var c := world_to_cell(tc) + Vector2i(i, j)
			if is_walkable_cell(c) and rng.randf() > 0.18:
				floor_cells.append(c)
	add_tiles(["desert_tile_b", "desert_tile_a"], floor_cells, Color(0.96, 0.93, 0.88), [Color(0.96, 0.93, 0.88), Color(0.88, 0.84, 0.78)])
	var cols := [Vector3(-9, 0, -5), Vector3(-3, 0, -5), Vector3(3, 0, -5), Vector3(9, 0, -5), Vector3(-9, 0, 5), Vector3(-3, 0, 5), Vector3(3, 0, 5), Vector3(9, 0, 5)]
	for k in cols.size():
		var cp: Vector3 = tc + (cols[k] as Vector3)
		if not is_walkable_at(cp):
			continue
		if k in [2, 4, 7]:
			add_obstacle("desert_column_broken", cp, rng.randf() * TAU, 1.0, 0.95, {"cutout": false})
		elif k != 5:
			add_obstacle("desert_column", cp, 0.0, 1.0, 0.95)
	add_block("desert_obelisk_fallen", tc + Vector3(0, 0, 0.5), 0.15, Vector2(9.0, 2.2), {"height": 1.2, "cutout": false})
	add_block("desert_statue", tc + Vector3(0, 0, -11), 0.0, Vector2(3.4, 5.0), {"height": 6.0})
	_chest(tc + Vector3(6, 0, 1), PI, 1, rid)
	add_obstacle("desert_brazier", tc + Vector3(-6, 0, 1), 0.0, 1.0, 0.45, {"cutout": false})
	add_light(tc + Vector3(-6, 2.1, 1), Color(1.0, 0.64, 0.3), 1.5, 6.5, true)
	add_glow(tc + Vector3(-6, 0, 1), 2.2, Color(1.0, 0.6, 0.26))
	# --- milestones along the trails --------------------------------------------------------------
	for t in TRAILS.slice(0, 5):
		var pts: Array = t[0]
		var hw := float(t[1])
		var n := 0
		for sp in _along(pts, 46.0):
			n += 1
			if n == 1:
				continue
			var side := Vector2(-(sp["dir"] as Vector2).y, (sp["dir"] as Vector2).x) * (1.0 if n % 2 == 0 else -1.0)
			var q4 := _v3((sp["p"] as Vector2) + side * (hw + 1.8))
			if is_walkable_at(q4) and is_clear(q4, 1.5) and _water_at(q4) > 6.0 and region_at(q4) == rid:
				add_obstacle("desert_stele", q4, _face(-side), 0.9, 0.45, OPT_TALL)
	# --- ruins, fallen columns and rocks on the dry west bank --------------------------------------
	for mo in [Vector3(392, 0, 408), Vector3(262, 0, 392)]:
		_mini_oasis(mo)
	for rp in [[Vector3(186, 0, 300), 0.4], [Vector3(362, 0, 436), 1.2], [Vector3(430, 0, 470), 0.2],
			[Vector3(212, 0, 402), 2.0], [Vector3(470, 0, 360), -1.1]]:
		_block_if_free("desert_ruin", rp[0], float(rp[1]), Vector2(6.2, 2.4), {"height": 3.0})
	for cp2 in [Vector3(196, 0, 320), Vector3(262, 0, 408), Vector3(350, 0, 445), Vector3(240, 0, 460), Vector3(418, 0, 470)]:
		var q := _spot(cp2, 2.0, rid, 5.0)
		if q != Vector3.INF:
			add_obstacle("desert_column_broken", q, rng.randf() * TAU, rng.randf_range(0.85, 1.1), 0.95, {"cutout": false})
	_block_if_free("desert_obelisk_fallen", Vector3(275, 0, 430), -0.6, Vector2(9.0, 2.2), {"height": 1.2, "cutout": false})
	var west := Rect2(172, 280, 290, 215)
	for k in 20:
		var cp3 := Vector3(rng.randf_range(west.position.x, west.end.x), 0, rng.randf_range(west.position.y, west.end.y))
		var q3 := _spot(cp3, 7.0, rid, 10.0, 0.05)
		if q3 != Vector3.INF and _field_at(q3).r > 18.0:
			_rock_cluster(q3)
	scatter(["desert_rock"], 80, west, {"on": "walkable", "region": rid, "collide": 1.0, "min_dist": 9.0, "scale": Vector2(0.55, 1.0),
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 16.0 and _field_at(p).b < 0.15 and p.distance_to(start) > 14.0})
	scatter(["desert_rock"], 90, west, {"on": "walkable", "region": rid, "min_dist": 6.0, "scale": Vector2(0.22, 0.4), "cutout": true,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 16.0 and _field_at(p).b < 0.3})
	# dead palms, lonely graves and bleached bones in the dry land
	scatter(["desert_palm_a"], 16, west, {"on": "walkable", "region": rid, "collide": 0.45, "min_dist": 20.0, "scale": Vector2(0.75, 0.95),
		"cutout": true, "sway": 0.45, "sway_base": 2.0, "tint": Color(0.78, 0.62, 0.42),
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 20.0 and _field_at(p).b < 0.15})
	scatter(["desert_sarcophagus", "desert_stele", "desert_column_broken"], 16, west, {"on": "walkable", "region": rid, "collide": 0.8, "min_dist": 24.0,
		"cutout": false, "filter": func(p: Vector3) -> bool: return _field_at(p).r > 16.0 and _field_at(p).b < 0.15})
	scatter(["env_bones"], 24, west, {"on": "walkable", "region": rid, "min_dist": 12.0, "scale": Vector2(0.9, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 16.0 and _field_at(p).b < 0.3})
	# --- the far (north-east) bank: farmsteads, fields, a well ------------------------------------
	for f in [[Vector3(300, 0, 192), 0.0, "desert_mudhouse", Vector2(8.4, 4.8)], [Vector3(372, 0, 196), 0.0, "desert_mudhouse_b", Vector2(7.0, 4.6)],
			[Vector3(462, 0, 214), -PI * 0.5, "desert_mudhouse", Vector2(8.4, 4.8)], [Vector3(404, 0, 304), -PI * 0.5, "desert_mudhouse", Vector2(8.4, 4.8)],
			[Vector3(446, 0, 346), PI, "desert_mudhouse_b", Vector2(7.0, 4.6)]]:
		if not _block_if_free(String(f[2]), f[0], float(f[1]), f[3], {"height": 3.2, "opaque": true}):
			print_verbose("act_desert: no room for %s at %s (skipped)" % [f[2], f[0]])
	_block_if_free("desert_well", Vector3(318, 0, 214), 0.3, Vector2(4.6, 2.6), {"height": 1.2})
	for fr in FIELDS:
		_field(fr)
	_chest(Vector3(470, 0, 250), -PI * 0.5, 0, rid)
	_shrine(Vector3(418, 0, 236), rid)
	# --- palms, shrubs and grass --------------------------------------------------------------------
	var all_r := region_rect(rid)
	scatter({"desert_palm_a": 3.0, "desert_palm_b": 2.0}, 60, all_r, {"on": "walkable", "region": rid, "collide": 0.45, "min_dist": 6.0,
		"scale": Vector2(0.8, 1.1), "cutout": true, "sway": 0.45, "sway_base": 2.0,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 2.5 and _field_at(p).r < 22.0 and _field_at(p).b < 0.3 and _cn.get_noise_2d(p.x * 0.4, p.z * 0.4) > -0.05 and p.distance_to(start) > 8.0})
	scatter(["desert_shrub"], 70, all_r, {"on": "walkable", "region": rid, "min_dist": 4.0, "scale": Vector2(0.6, 1.1), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).a > 0.25 and _field_at(p).b < 0.4})
	scatter(["desert_grass_green"], 130, all_r, {"on": "walkable", "region": rid, "min_dist": 3.0, "scale": Vector2(0.8, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).a > 0.35 and _field_at(p).b < 0.4})
	scatter(["desert_grass"], 170, all_r, {"on": "walkable", "region": rid, "min_dist": 4.5, "scale": Vector2(0.7, 1.2), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).a < 0.2 and _field_at(p).b < 0.4})
	scatter(["desert_pebbles"], 190, all_r, {"on": "walkable", "region": rid, "min_dist": 5.0, "scale": Vector2(0.8, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).a < 0.3})
	scatter(["desert_grass"], 260, all_r, {"on": "walkable", "region": rid, "min_dist": 3.5, "scale": Vector2(0.9, 1.6), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).a < 0.2 and _field_at(p).b < 0.2 and _cn.get_noise_2d(p.x * 0.5, p.z * 0.5) > 0.0})
	scatter(["desert_shrub"], 120, all_r, {"on": "walkable", "region": rid, "min_dist": 6.0, "scale": Vector2(0.55, 1.0), "shadows": false,
		"tint": Color(0.98, 0.82, 0.58), "filter": func(p: Vector3) -> bool: return _field_at(p).a < 0.15 and _field_at(p).b < 0.2})


## A well in the dry land with a ring of palms, grass and a water jar or two (a small landmark).
func _mini_oasis(p: Vector3) -> void:
	if not _block_if_free("desert_well", p, rng.randf() * TAU, Vector2(4.6, 2.6), {"height": 1.2}):
		return
	_fertile(Rect2(p.x - 9.0, p.z - 9.0, 18.0, 18.0), 0.45)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
		var q := p + Vector3(cos(a), 0, sin(a)) * rng.randf_range(5.0, 8.5)
		if is_walkable_at(q) and is_clear(q, 1.0):
			add_obstacle("desert_palm_a" if rng.randf() < 0.55 else "desert_palm_b", q, rng.randf() * TAU, rng.randf_range(0.8, 1.05), 0.45, OPT_PALM)
	for k2 in 8:
		var q2 := p + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		if is_walkable_at(q2) and is_clear(q2, 0.5):
			add_prop("desert_grass_green", q2, rng.randf() * TAU, rng.randf_range(0.8, 1.2), OPT_LOW)
	keep(p, 6.0)


## A few weathered rocks with pebbles and dry grass around them (a small landmark).
func _rock_cluster(p: Vector3) -> void:
	if rng.randf() < 0.6:
		var sc0 := rng.randf_range(0.32, 0.48)
		add_obstacle("desert_mesa", p, rng.randf() * TAU, sc0, 6.2 * sc0, OPT_TALL)
	var n := rng.randi_range(3, 5)
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.4, 0.4)
		var q := p + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.6, 5.4)
		if is_walkable_at(q) and is_clear(q, 0.8):
			var sc := rng.randf_range(0.55, 1.15)
			add_obstacle("desert_rock", q, rng.randf() * TAU, sc, 1.2 * sc, OPT_TALL)
	for k2 in 3:
		var q2 := p + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
		if is_walkable_at(q2):
			add_prop("desert_grass" if k2 < 2 else "desert_pebbles", q2, rng.randf() * TAU, rng.randf_range(0.8, 1.2), OPT_LOW)
	keep(p, 4.0)


## An irrigated field: rows of crop patches, a ditch along the side nearest the river with a
## shaduf at its end, some palms at the corners.
func _field(r: Rect2) -> void:
	_fertile(r, 1.0)
	var nx := int(r.size.x / 6.5)
	var nz := int(r.size.y / 4.5)
	var ox := r.position.x + (r.size.x - nx * 6.5) * 0.5 + 3.25
	var oz := r.position.y + (r.size.y - nz * 4.5) * 0.5 + 2.25
	for jz in nz:
		var id := "desert_crops_a" if (jz + int(r.position.x)) % 3 != 0 else "desert_crops_b"
		for ix in nx:
			var p := Vector3(ox + ix * 6.5, 0, oz + jz * 4.5)
			var ok := true
			for q in [Vector3(-3, 0, -2), Vector3(3, 0, -2), Vector3(-3, 0, 2), Vector3(3, 0, 2)]:
				var c := world_to_cell(p + (q as Vector3))
				if not is_walkable_cell(c) or _fa[c.y * _gw + c.x].b > 0.35:
					ok = false
			if ok and is_clear(p, 1.5):
				add_prop(id, p, 0.0 if rng.randf() < 0.5 else PI, 1.0, OPT_LOW)
				keep(p, 2.6)
	# The ditch: along the long side nearest the water.
	var sides := [[Vector2(r.position.x, r.position.y - 1.2), Vector2(r.end.x, r.position.y - 1.2)],
		[Vector2(r.position.x, r.end.y + 1.2), Vector2(r.end.x, r.end.y + 1.2)]]
	var best: Array = sides[0]
	if _water_at(_v3((sides[1][0] + sides[1][1]) * 0.5)) < _water_at(_v3((sides[0][0] + sides[0][1]) * 0.5)):
		best = sides[1]
	var a: Vector2 = best[0]
	var b: Vector2 = best[1]
	var n := int(a.distance_to(b) / 8.0)
	for k in n:
		var p2 := _v3(a.lerp(b, (k + 0.5) / n))
		if is_walkable_at(p2) and _trail_at(p2) < 0.4:
			add_prop("desert_canal", p2, PI * 0.5, 1.0, OPT_LOW)
	# A shaduf where the ditch meets the bank.
	var end := _v3(a) if _water_at(_v3(a)) < _water_at(_v3(b)) else _v3(b)
	var bank := _toward_water(end, 16.0)
	if bank != Vector3.INF:
		var wdir := _water_dir(bank)
		add_prop("desert_shaduf", bank, _face(Vector2(wdir.x, wdir.z)), 1.0, OPT_TALL)
		keep(bank, 2.0)
	for corner in [Vector3(r.position.x - 2, 0, r.position.y - 2), Vector3(r.end.x + 2, 0, r.end.y + 2)]:
		var q2 := _spot(corner, 1.5, "", 3.0)
		if q2 != Vector3.INF:
			add_obstacle("desert_palm_a" if rng.randf() < 0.6 else "desert_palm_b", q2, rng.randf() * TAU, rng.randf_range(0.85, 1.05), 0.45, OPT_PALM)


## The last walkable spot on the way from p toward the nearest water (within `reach` m).
func _toward_water(p: Vector3, reach: float) -> Vector3:
	var d := _water_dir(p)
	var last := Vector3.INF
	var q := p
	for k in int(reach * 2.0):
		q = p + d * (k * 0.5)
		if not is_walkable_at(q):
			break
		last = q
	return last


## Direction of steepest descent of the water distance (toward the water) at p.
func _water_dir(p: Vector3) -> Vector3:
	var gx := _water_at(p + Vector3(2, 0, 0)) - _water_at(p - Vector3(2, 0, 0))
	var gz := _water_at(p + Vector3(0, 0, 2)) - _water_at(p - Vector3(0, 0, 2))
	var v := Vector3(-gx, 0, -gz)
	return v.normalized() if v.length() > 0.001 else Vector3(0, 0, 1)


## Cells within `half` m of a polyline (Vector2 points), dropping a random share `gaps` (buried).
func _cells_along(pts: Array, half: float, gaps: float = 0.0) -> Array:
	var seen := {}
	var out: Array = []
	for s in _along(pts, 0.8):
		for c in cells_in_disc(_v3(s["p"]), half):
			if seen.has(c):
				continue
			seen[c] = true
			if is_walkable_cell(c) and rng.randf() >= gaps:
				out.append(c)
	return out


# ------------------------------------------------------------------ painting: The Oasis

func _paint_oasis() -> void:
	var rid := "oasis"
	var rr := region_rect(rid)
	# --- the caravan camp west of the pool ----------------------------------------------------------
	var camp := Vector3(44, 0, 150)
	for a: float in [3.4, 4.9, 0.5]:
		var tp := camp + Vector3(cos(a), 0, sin(a)) * 10.0
		_block_if_free("desert_tent", tp, _face(Vector2(camp.x - tp.x, camp.z - tp.z)), Vector2(4.6, 3.6), {"height": 2.4})
	_block_if_free("desert_awning", camp + Vector3(9, 0, -8), -2.3, Vector2(3.8, 3.2), {"height": 2.6})
	for k in 3:
		add_prop("desert_carpet", camp + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), rng.randf() * TAU)
	for c in [Vector3(14, 0, 8), Vector3(18, 0, 3), Vector3(-12, 0, 12)]:
		_solid("desert_camel", camp + c, rng.randf() * TAU, rng.randf_range(0.95, 1.05), 0.8, OPT_TALL)
	for c2 in [Vector3(6, 0, 4), Vector3(-6, 0, -5)]:
		_solid("desert_pots", camp + c2, rng.randf() * TAU, rng.randf_range(0.85, 1.0), 0.6, {"cutout": false})
	add_obstacle("desert_brazier", camp, 0.0, 1.0, 0.45, {"cutout": false})
	add_light(camp + Vector3(0, 2.1, 0), Color(1.0, 0.66, 0.3), 1.4, 6.5, true)
	add_glow(camp, 2.2, Color(1.0, 0.62, 0.28))
	_chest(camp + Vector3(-4, 0, 8), 0.4, 1, rid)
	# --- the well at the east entrance, the ruined shrine in the south ------------------------------
	_block_if_free("desert_well", Vector3(148, 0, 205), PI, Vector2(4.6, 2.6), {"height": 1.2})
	_block_if_free("desert_ruin", Vector3(130, 0, 244), 0.6, Vector2(6.2, 2.4), {"height": 3.0})
	var q := _spot(Vector3(122, 0, 236), 2.0, rid, 5.0)
	if q != Vector3.INF:
		add_obstacle("desert_column_broken", q, 0.7, 1.0, 0.95, {"cutout": false})
	_chest(Vector3(136, 0, 238), 0.0, 1, rid)
	_chest(Vector3(76, 0, 124), 0.0, 0, rid)
	_shrine(Vector3(112, 0, 206), rid, "swiftness")
	# --- lush growth around the water ------------------------------------------------------------------
	scatter({"desert_palm_a": 3.0, "desert_palm_b": 2.0}, 75, rr, {"on": "walkable", "region": rid, "collide": 0.45, "min_dist": 4.6,
		"scale": Vector2(0.8, 1.12), "cutout": true, "sway": 0.45, "sway_base": 2.0,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 2.0 and _field_at(p).r < 23.0 and _field_at(p).b < 0.35})
	scatter({"desert_palm_a": 1.0, "desert_palm_b": 1.0}, 20, rr, {"on": "walkable", "region": rid, "collide": 0.45, "min_dist": 9.0,
		"scale": Vector2(0.8, 1.05), "cutout": true, "sway": 0.45, "sway_base": 2.0,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.3})
	scatter(["desert_fern"], 55, rr, {"on": "walkable", "region": rid, "min_dist": 3.2, "scale": Vector2(0.7, 1.2), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < 20.0 and _field_at(p).b < 0.4})
	scatter(["desert_grass_green"], 120, rr, {"on": "walkable", "region": rid, "min_dist": 2.8, "scale": Vector2(0.8, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < 22.0 and _field_at(p).b < 0.4})
	scatter(["desert_shrub"], 30, rr, {"on": "walkable", "region": rid, "min_dist": 5.0, "scale": Vector2(0.6, 1.1), "shadows": false})
	scatter(["desert_reeds"], 45, rr, {"on": "walkable", "region": rid, "min_dist": 2.6, "scale": Vector2(0.7, 1.1), "shadows": false,
		"sway": 1.0, "sway_base": 0.5, "filter": func(p: Vector3) -> bool: return _field_at(p).r < 2.8 and _field_at(p).b < 0.3})
	scatter(["desert_reeds"], 40, Rect2(56, 146, 70, 64), {"on": "void", "min_dist": 2.4, "scale": Vector2(0.8, 1.3), "shadows": false,
		"sway": 1.0, "sway_base": 0.5, "filter": func(p: Vector3) -> bool: return _field_at(p).r > -2.5 and _field_at(p).r < 0.8})
	scatter(["desert_grass"], 40, rr, {"on": "walkable", "region": rid, "min_dist": 6.0, "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 24.0})
	# lotus on the pool
	scatter(["desert_lotus"], 12, Rect2(56, 146, 70, 64), {"on": "void", "min_dist": 5.0, "scale": Vector2(0.8, 1.2), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < -3.0})
	for d in props:
		var did := String(d["id"])
		var dp: Vector3 = d["pos"]
		if dp.y != 0.0 or region_at(dp) != rid or is_walkable_at(dp):
			continue
		if did == "desert_lotus":
			d["pos"] = Vector3(dp.x, water_level + 0.005, dp.z)
		elif did == "desert_reeds":
			d["pos"] = Vector3(dp.x, -0.55, dp.z)


# ------------------------------------------------------------------ painting: Snake Isles

func _paint_isles() -> void:
	var rid := "isles"
	var rr := region_rect(rid)
	# --- the serpent shrine on the western island -----------------------------------------------------
	var sc := Vector3(30, 0, 392)
	var shrine_cells: Array = []
	for j in range(-4, 5):
		for i in range(-5, 6):
			var c := world_to_cell(sc) + Vector2i(i, j)
			if is_walkable_cell(c) and Vector2(i, j * 1.2).length() < 5.2 and rng.randf() > 0.1:
				shrine_cells.append(c)
	add_tiles(["desert_tile_b", "desert_tile_a"], shrine_cells, Color(0.8, 0.84, 0.72), [Color(0.8, 0.84, 0.72), Color(0.72, 0.76, 0.64)])
	add_block("desert_serpent_statue", sc + Vector3(0, 0, -3), 0.0, Vector2(2.5, 2.5), {"height": 4.0})
	for s: float in [-1.0, 1.0]:
		var cp := sc + Vector3(s * 5.5, 0, -1)
		if is_walkable_at(cp):
			add_obstacle("desert_column", cp, 0.0, 0.85, 0.85)
		var bp := sc + Vector3(s * 3.2, 0, 3)
		if is_walkable_at(bp):
			add_obstacle("desert_brazier", bp, 0.0, 1.0, 0.45, {"cutout": false})
			add_glow(bp, 2.0, Color(0.6, 1.0, 0.55))
	add_light(sc + Vector3(0, 2.4, 2), Color(0.55, 1.0, 0.6), 1.3, 7.0, true)
	_chest(sc + Vector3(0, 0, 1.5), 0.0, 2, rid)
	# --- serpent statues on the islands ---------------------------------------------------------------
	for sp in [[Vector3(112, 0, 302), PI], [Vector3(128, 0, 446), -0.6], [Vector3(46, 0, 452), 0.4], [Vector3(96, 0, 360), 2.4]]:
		var q := _spot(sp[0], 2.2, rid, 6.0)
		if q != Vector3.INF:
			add_block("desert_serpent_statue", q, float(sp[1]), Vector2(2.5, 2.5), {"height": 4.0})
	_chest(Vector3(40, 0, 450), 0.0, 0, rid)
	_chest(Vector3(126, 0, 436), 0.0, 1, rid)
	_shrine(Vector3(120, 0, 356), rid)
	_shrine(Vector3(40, 0, 316), rid, "arcana")
	# --- a felucca in the main channel, reeds and papyrus, palms ------------------------------------
	add_prop("desert_boat", Vector3(22, water_level + 0.05, 353), PI * 0.5 + 0.1, 0.85, OPT_TALL)
	scatter(["desert_reeds"], 230, Rect2(-10, 280, 190, 230), {"on": "void", "min_dist": 2.2, "scale": Vector2(0.8, 1.35), "shadows": false,
		"sway": 1.0, "sway_base": 0.5, "filter": func(p: Vector3) -> bool: return _field_at(p).r > -2.8 and _field_at(p).r < 1.2 and region_at(p) == rid})
	scatter(["desert_reeds"], 70, rr, {"on": "walkable", "region": rid, "min_dist": 3.0, "scale": Vector2(0.7, 1.1), "shadows": false,
		"sway": 1.0, "sway_base": 0.5, "filter": func(p: Vector3) -> bool: return _field_at(p).r < 4.0 and _field_at(p).b < 0.3})
	scatter(["desert_lotus"], 26, Rect2(-10, 290, 190, 220), {"on": "void", "min_dist": 7.0, "scale": Vector2(0.7, 1.1), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < -2.5 and region_at(p) == rid})
	scatter({"desert_palm_a": 1.0, "desert_palm_b": 2.0}, 30, rr, {"on": "walkable", "region": rid, "collide": 0.45, "min_dist": 8.0,
		"scale": Vector2(0.75, 1.0), "cutout": true, "sway": 0.45, "sway_base": 2.0, "filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.3})
	scatter(["desert_shrub"], 50, rr, {"on": "walkable", "region": rid, "min_dist": 4.0, "scale": Vector2(0.6, 1.1), "shadows": false})
	scatter(["desert_grass_green"], 110, rr, {"on": "walkable", "region": rid, "min_dist": 3.0, "scale": Vector2(0.8, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.4})
	scatter(["desert_fern"], 25, rr, {"on": "walkable", "region": rid, "min_dist": 5.0, "scale": Vector2(0.7, 1.1), "shadows": false})
	for d in props:
		var did := String(d["id"])
		if (did == "desert_reeds" or did == "desert_lotus") and region_at(d["pos"]) == rid:
			var dp: Vector3 = d["pos"]
			if not is_walkable_at(dp):
				d["pos"] = Vector3(dp.x, water_level + 0.005 if did == "desert_lotus" else -0.55, dp.z)


# ------------------------------------------------------------------ painting: Anubis Graveyard

func _paint_graveyard() -> void:
	var rid := "graveyard"
	var rr := region_rect(rid)
	# --- the processional way: paving, jackals, braziers --------------------------------------------
	var way: Array = TRAILS[TRAILS.size() - 1][0]
	add_tiles(["desert_tile_b", "desert_tile_a"], _cells_along(way, 3.0, 0.3), Color(0.9, 0.8, 0.7), [Color(0.9, 0.8, 0.7), Color(0.8, 0.7, 0.6)])
	var n := 0
	for s in _along(way.slice(1), 22.0):
		var p: Vector2 = s["p"]
		var dir: Vector2 = s["dir"]
		var side := Vector2(-dir.y, dir.x)
		n += 1
		for sg: float in [-1.0, 1.0]:
			var q := _v3(p + side * sg * 7.0)
			if not is_walkable_at(q) or region_at(q) != rid:
				continue
			if n % 2 == 0:
				add_block("desert_jackal_statue", q, _face(dir), Vector2(1.9, 3.7), {"height": 3.0})
			else:
				add_obstacle("desert_brazier", q, 0.0, 1.0, 0.45, {"cutout": false})
				add_light(q + Vector3(0, 2.1, 0), Color(1.0, 0.6, 0.3), 1.5, 6.5, true)
				add_glow(q, 2.2, Color(1.0, 0.55, 0.26))
	# --- streets of mastaba tombs north and south of the way ------------------------------------------
	for x in range(378, 492, 20):
		for z: float in [36.0, 56.0]:
			_block_if_free("desert_tomb", Vector3(x + rng.randf_range(-1.5, 1.5), 0, z), 0.0, Vector2(8.0, 7.4), {"height": 4.0, "opaque": true})
		for z2: float in [106.0, 128.0]:
			_block_if_free("desert_tomb", Vector3(x + rng.randf_range(-1.5, 1.5), 0, z2), PI, Vector2(8.0, 7.4), {"height": 4.0, "opaque": true})
	# pyramid chapels in the old western cemetery and along the edges
	for tp in [Vector3(304, 0, 40), Vector3(326, 0, 58), Vector3(302, 0, 72), Vector3(322, 0, 132), Vector3(330, 0, 36),
			Vector3(340, 0, 108), Vector3(318, 0, 148), Vector3(498, 0, 60), Vector3(490, 0, 140), Vector3(370, 0, 150),
			Vector3(440, 0, 20), Vector3(350, 0, 22)]:
		_block_if_free("desert_tomb_pyr", tp, rng.randf_range(-0.25, 0.25), Vector2(4.6, 6.2), {"height": 4.0, "opaque": true})
	for rp in [[Vector3(352, 0, 60), 0.3], [Vector3(470, 0, 36), -0.2], [Vector3(455, 0, 118), 1.3], [Vector3(300, 0, 128), 0.7]]:
		_block_if_free("desert_ruin", rp[0], float(rp[1]), Vector2(6.2, 2.4), {"height": 3.0})
	# --- stelae fields, sarcophagi, fallen obelisks, bones ---------------------------------------------
	scatter(["desert_stele"], 180, rr, {"on": "walkable", "region": rid, "collide": 0.45, "min_dist": 2.8, "scale": Vector2(0.8, 1.15), "cutout": true,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.2 and _cn.get_noise_2d(p.x * 0.6, p.z * 0.6) > -0.05})
	scatter(["desert_sarcophagus"], 34, rr, {"on": "walkable", "region": rid, "collide": 0.9, "min_dist": 8.0, "scale": Vector2(0.9, 1.1), "cutout": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.2})
	scatter(["desert_rock"], 14, rr, {"on": "walkable", "region": rid, "collide": 1.0, "min_dist": 14.0, "scale": Vector2(0.5, 0.9), "cutout": true,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.2})
	for op in [[Vector3(300, 0, 148), 0.6], [Vector3(440, 0, 150), -0.4], [Vector3(476, 0, 90), 1.4]]:
		_block_if_free("desert_obelisk_fallen", op[0], float(op[1]), Vector2(9.0, 2.2), {"height": 1.2, "cutout": false})
	scatter(["desert_column_broken"], 12, rr, {"on": "walkable", "region": rid, "collide": 0.95, "min_dist": 14.0, "cutout": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.2})
	scatter(["env_bones"], 40, rr, {"on": "walkable", "region": rid, "min_dist": 7.0, "scale": Vector2(0.8, 1.2), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.5})
	scatter(["desert_grass"], 110, rr, {"on": "walkable", "region": rid, "min_dist": 5.0, "scale": Vector2(0.6, 1.0), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).b < 0.3})
	scatter(["desert_pebbles"], 80, rr, {"on": "walkable", "region": rid, "min_dist": 6.0, "scale": Vector2(0.8, 1.3), "shadows": false})
	_chest(Vector3(398, 0, 70), PI, 1, rid)
	_chest(Vector3(318, 0, 96), PI * 0.5, 0, rid)
	_chest(Vector3(486, 0, 116), -PI * 0.5, 1, rid)
	_shrine(Vector3(420, 0, 90), rid, "fortitude")
	_shrine(Vector3(330, 0, 150), rid)


# ------------------------------------------------------------------ painting: Anubis Courtyard

func _paint_courtyard() -> void:
	var rid := "courtyard"
	var rr := region_rect(rid)
	# --- the Anubis Temple along the court's north side: its hall, the pylon and the door down face
	# the court (and the game camera, which looks north-west from the south-east, so the player at
	# the door stays in view; nothing of it rises above the camera). Colossi flank the door, the
	# guardian waits before it. -------------------------------------------------------------------------
	var dx := TEMPLE_X
	var north := _edge_along(Vector2(dx, rr.get_center().y), Vector2(0, -1), rid)
	if north == INF:
		north = rr.position.y
	# The pylon's origin: its back (3.99 m behind it) meets the hall's front, the hall's back
	# (34.5 m further) the court's edge.
	var gate_z := north + 38.5
	add_prop("desert_temple_hall", Vector3(dx, 0, gate_z - 20.5), 0.0, 1.0, OPT_TALL)
	add_block("", Vector3(dx, 0, (north + gate_z - 3.5) * 0.5), 0.0, Vector2(35.0, gate_z - 3.5 - north), {"height": 8.0, "opaque": true})
	add_prop("desert_temple_gate", Vector3(dx, 0, gate_z), 0.0, 1.0, OPT_TALL)
	for s: float in [-1.0, 1.0]:
		add_block("", Vector3(dx + s * 12.0, 0, gate_z - 0.4), 0.0, Vector2(15.0, 7.0), {"height": 8.0, "opaque": true})
	add_block("", Vector3(dx, 0, gate_z - 0.6), 0.0, Vector2(9.4, 5.2), {"height": 8.0, "opaque": true})
	add_dungeon_entrance(Vector3(dx, 0, gate_z + 2.9), 0.0, "desert_temple_door", Vector2(6.4, 1.8))
	for s2: float in [-1.0, 1.0]:
		add_block("desert_anubis_statue", Vector3(dx + s2 * 12.5, 0, gate_z + 7.0), 0.0, Vector2(3.4, 3.4), {"height": 6.0})
		add_block("desert_obelisk", Vector3(dx + s2 * 7.5, 0, gate_z + 16.0), 0.0, Vector2(2.4, 2.4), {"height": 4.0})
	add_zone_boss(Vector3(dx, 0, gate_z + 26.0))
	_chest(Vector3(dx + 18.0, 0, gate_z + 11.0), -PI * 0.5, 2, rid)
	var south := _edge_along(Vector2(dx, rr.get_center().y), Vector2(0, 1), rid)
	if south == INF:
		south = rr.end.y
	# --- the paved court -----------------------------------------------------------------------------
	var axis_cells := {}
	for c in _cells_along([Vector2(528, 77), Vector2(dx, 77)], 4.2) + _cells_along([Vector2(dx, gate_z + 4.5), Vector2(dx, south - 1.0)], 4.2):
		axis_cells[c] = true
	var court: Array = []
	var axis: Array = []
	var inside := _inside_steps(rid, 5)
	for c2 in region_cells(rid):
		var cc: Vector2i = c2
		if not is_walkable_cell(cc):
			continue
		if axis_cells.has(cc):
			axis.append(cc)
		elif rng.randf() > 0.015 + 0.5 * (1.0 - smoothstep(1.0, 4.5, float(inside.get(cc, 9)))) * (0.5 + 0.5 * _cn.get_noise_2d(cc.x * 3.1, cc.y * 3.1)):
			# (sand has drifted over the paving along the court's edges)
			court.append(cc)
	add_tiles(["desert_tile_c"], court, Color(1, 1, 1), [Color(1, 1, 1), Color(0.96, 0.93, 0.88), Color(1.02, 1.0, 0.96)])
	add_tiles(["desert_tile_a", "desert_tile_b"], axis, Color(1.0, 0.95, 0.86), [Color(1.0, 0.95, 0.86), Color(0.95, 0.88, 0.76)])
	# --- colossi and braziers along the axis -----------------------------------------------------
	for x: float in [560.0, 588.0]:
		for s3: float in [-1.0, 1.0]:
			add_block("desert_anubis_statue", Vector3(x, 0, 77 + s3 * 11.0), 0.0 if s3 < 0 else PI, Vector2(3.4, 3.4), {"height": 6.0})
	for z: float in [104.0, 132.0, 160.0]:
		for s4: float in [-1.0, 1.0]:
			add_block("desert_anubis_statue", Vector3(dx + s4 * 11.0, 0, z), -s4 * PI * 0.5, Vector2(3.4, 3.4), {"height": 6.0})
	for bpos in [Vector3(574, 0, 70), Vector3(574, 0, 84), Vector3(604, 0, 70), Vector3(604, 0, 84),
			Vector3(dx - 7, 0, 90), Vector3(dx + 7, 0, 90), Vector3(dx - 7, 0, 118), Vector3(dx + 7, 0, 118)]:
		if is_walkable_at(bpos) and is_clear(bpos, 1.0):
			add_obstacle("desert_brazier", bpos, 0.0, 1.0, 0.45, {"cutout": false})
			add_light(bpos + Vector3(0, 2.1, 0), Color(1.0, 0.62, 0.28), 1.6, 7.0, true)
			add_glow(bpos, 2.4, Color(1.0, 0.58, 0.25))
	# recumbent jackals at the far (south) end of the way, looking up it to the temple
	for s6: float in [-1.0, 1.0]:
		var jp := _spot(Vector3(dx + s6 * 8.0, 0, south - 5.0), 2.2, rid, 4.0, 1.0)
		if jp != Vector3.INF:
			add_block("desert_jackal_statue", jp, PI, Vector2(1.9, 3.7), {"height": 3.0})
	# ram sphinxes along the way in from the gate
	for x2 in [546.0, 574.0, 602.0]:
		for s5 in [-1.0, 1.0]:
			var sp := Vector3(x2, 0, 77 + s5 * 6.5)
			if is_walkable_at(sp) and is_clear(sp, 1.6):
				add_block("desert_sphinx_small", sp, 0.0 if s5 < 0 else PI, Vector2(1.6, 3.6), {"height": 2.2})
	# kiosks: four columns round a brazier, in the open quarters of the court
	for kc: Vector3 in [Vector3(585, 0, 140), Vector3(690, 0, 150), Vector3(700, 0, 100), Vector3(590, 0, 30)]:
		if not (is_walkable_at(kc) and is_clear(kc, 6.0)):
			continue
		for a in 4:
			var cp := kc + Vector3(cos(a * PI * 0.5 + PI * 0.25), 0, sin(a * PI * 0.5 + PI * 0.25)) * 4.2
			if is_walkable_at(cp):
				add_obstacle("desert_column", cp, 0.0, 0.9, 0.85)
		add_obstacle("desert_brazier", kc, 0.0, 1.0, 0.45, {"cutout": false})
		add_light(kc + Vector3(0, 2.1, 0), Color(1.0, 0.62, 0.28), 1.5, 6.5, true)
		add_glow(kc, 2.4, Color(1.0, 0.58, 0.25))
	# a fallen colossus in the south-west quarter, a great sphinx guarding the south-east
	var fc := _spot(Vector3(596, 0, 170), 7.0, rid, 12.0, 1.0)
	if fc != Vector3.INF:
		add_block("desert_head", fc, 2.6, Vector2(4.4, 3.6), {"height": 3.0})
		add_block("desert_obelisk_fallen", fc + Vector3(-7, 0, -4), 0.7, Vector2(9.0, 2.2), {"height": 1.2, "cutout": false})
		for k in 2:
			var cq := fc + Vector3(4.5 + k * 3.0, 0, -5.0 + k * 3.5)
			if is_walkable_at(cq) and is_clear(cq, 1.2):
				add_obstacle("desert_column_broken", cq, rng.randf() * TAU, 1.0, 0.95, {"cutout": false})
	var gs := _spot(Vector3(712, 0, 168), 8.0, rid, 12.0, 1.0)
	if gs != Vector3.INF:
		add_block("desert_sphinx", gs, -PI * 0.5, Vector2(5.4, 12.6), {"height": 5.0, "opaque": true})
	# seated kings by the sacred lake
	for sx in [LAKE.position.x + 10.0, LAKE.end.x - 10.0]:
		var stp := Vector3(sx, 0, LAKE.end.y + 5.0)
		if is_walkable_at(stp) and is_clear(stp, 2.5):
			add_block("desert_statue", stp, PI, Vector2(3.4, 5.0), {"height": 6.0})
	# --- the sacred lake: jackals at its corners, lotus on the water -----------------------------
	for lc in [Vector3(LAKE.position.x - 3, 0, LAKE.position.y - 3), Vector3(LAKE.end.x + 3, 0, LAKE.position.y - 3),
			Vector3(LAKE.position.x - 3, 0, LAKE.end.y + 3), Vector3(LAKE.end.x + 3, 0, LAKE.end.y + 3)]:
		var q := _spot(lc, 2.2, rid, 4.0, 1.0)
		if q != Vector3.INF:
			add_block("desert_jackal_statue", q, _face(Vector2(LAKE.get_center().x - q.x, LAKE.get_center().y - q.z)), Vector2(1.9, 3.7), {"height": 3.0})
	scatter(["desert_lotus"], 8, LAKE.grow(-3.0), {"on": "void", "min_dist": 6.0, "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < -2.0})
	for d in props:
		if String(d["id"]) == "desert_lotus" and region_at(d["pos"]) == rid:
			var dp: Vector3 = d["pos"]
			d["pos"] = Vector3(dp.x, water_level + 0.005, dp.z)
	# --- colonnades along the court's sides -------------------------------------------------------
	_porticos(rid, dx)
	_chest(Vector3(LAKE.get_center().x, 0, LAKE.end.y + 6), 0.0, 1, rid)
	_chest(Vector3(724, 0, 150), -PI * 0.5, 0, rid)
	_chest(Vector3(566, 0, 150), PI * 0.5, 1, rid)
	_shrine(Vector3(690, 0, 110), rid, "fury")
	_shrine(Vector3(580, 0, 40), rid)
	scatter(["desert_pebbles"], 40, rr, {"on": "walkable", "region": rid, "min_dist": 8.0, "scale": Vector2(0.6, 0.9), "shadows": false,
		"filter": func(p: Vector3) -> bool: return not axis_cells.has(world_to_cell(p))})
	scatter(["desert_grass"], 40, rr, {"on": "walkable", "region": rid, "min_dist": 6.0, "scale": Vector2(0.6, 1.0), "shadows": false,
		"filter": func(p: Vector3) -> bool: return inside.has(world_to_cell(p))})
	scatter(["desert_stele", "desert_sarcophagus"], 12, rr, {"on": "walkable", "region": rid, "collide": 0.6, "min_dist": 18.0, "cutout": true,
		"filter": func(p: Vector3) -> bool: return not axis_cells.has(world_to_cell(p)) and p.distance_to(boss_pos) > 14.0 and inside.has(world_to_cell(p))})
	scatter(["desert_column_broken"], 5, rr, {"on": "walkable", "region": rid, "collide": 0.95, "min_dist": 20.0, "cutout": false,
		"filter": func(p: Vector3) -> bool: return not axis_cells.has(world_to_cell(p)) and p.distance_to(boss_pos) > 14.0})


## Walkable cells of a region within `limit` steps of its edge (or of anything solid): cell -> steps
## (1 = on the edge).
func _inside_steps(rid: String, limit: int) -> Dictionary:
	var out := {}
	var queue: Array[Vector2i] = []
	for c in region_cells(rid):
		var cc: Vector2i = c
		if not grid.is_walkable_cell(cc):
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not grid.is_walkable_cell(cc + d):
				out[cc] = 1
				queue.append(cc)
				break
	var head := 0
	while head < queue.size():
		var c2: Vector2i = queue[head]
		head += 1
		var st := int(out[c2])
		if st >= limit:
			continue
		for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c2 + d2
			if not out.has(n) and grid.is_walkable_cell(n) and is_region(n, rid):
				out[n] = st + 1
				queue.append(n)
	return out


## Colonnade sections along the straight stretches of the court's edges, facing in.
func _porticos(rid: String, dx: float) -> void:
	var rr := region_rect(rid)
	var lx := 12.4
	var cen := rr.get_center()
	# Each side: sections side by side, their backs on the innermost point of the wavy edge.
	for side in 4:
		var along := Vector2(1, 0) if side < 2 else Vector2(0, 1)
		var out := [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)][side] as Vector2
		var t := (rr.position.x if side < 2 else rr.position.y) + 10.0
		var t_end := (rr.end.x if side < 2 else rr.end.y) - 10.0
		while t < t_end:
			var mid := Vector2(t, cen.y) if side < 2 else Vector2(cen.x, t)
			t += lx + 0.6
			# keep clear of the temple (north), the end of its way (south) and the gate in from the necropolis
			if side < 2 and absf(mid.x - dx) < 26.0:
				continue
			if side == 3 and absf(mid.y - 77.0) < 22.0:
				continue
			# the innermost of three edge points (the wavy edge), measured along -out
			var sgn := out.x + out.y
			var inner := -INF
			var found := true
			for off in [-5.5, 0.0, 5.5]:
				var e := _edge_along(mid + along * float(off), out, rid)
				if e == INF:
					found = false
					break
				inner = maxf(inner, -e * sgn)
			if not found:
				continue
			# the section's back on that line, its centre 1.6 m in from it
			var edge := -inner * sgn
			var c := mid
			if side < 2:
				c.y = edge - sgn * 1.6
			else:
				c.x = edge - sgn * 1.6
			var p := _v3(c)
			var ok := true
			for off2 in [-5.5, 0.0, 5.5]:
				var q := p + _v3(along * float(off2)) - _v3(out) * 1.6
				if not is_walkable_at(q) or not is_region(world_to_cell(q), rid):
					ok = false
			if ok:
				_block_if_free("desert_portico", p, _face(-out), Vector2(lx, 2.9), {"height": 6.0, "opaque": true}, 1.0)


## The coordinate of the region's edge (the last walkable cell's outer side) from p going along dir.
func _edge_along(p: Vector2, dir: Vector2, rid: String) -> float:
	var c := world_to_cell(_v3(p))
	var d := Vector2i(int(dir.x), int(dir.y))
	var last := Vector2i(-1, -1)
	var inside := false
	for k in 200:
		if is_region(c, rid):
			inside = true
			if grid.is_floor(c):
				last = c
		elif inside:
			break
		c += d
	if last.x < 0:
		return INF
	if d.y != 0:
		return (last.y + (1 if d.y > 0 else 0)) * TILE
	return (last.x + (1 if d.x > 0 else 0)) * TILE


# ------------------------------------------------------------------ painting: gateways between zones

func _paint_gateways() -> void:
	for l in layout_data.get("links", []):
		var at_: Array = l["at"]
		var p := Vector2((float(at_[0]) + 0.5) * TILE, (float(at_[1]) + 0.5) * TILE)
		var a := String(l["a"])
		var b := String(l["b"])
		var dir := Vector2.ZERO
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if region_at(_v3(p + d * 8.0)) == b:
				dir = d
		if dir == Vector2.ZERO:
			continue
		var side := Vector2(-dir.y, dir.x)
		var half := float(l.get("width_cells", 10)) * TILE * 0.5
		var key := "%s|%s" % [a, b]
		match key:
			"graveyard|courtyard":
				add_prop("desert_gateway", _v3(p), _face(dir), 1.0, OPT_TALL)
				for s: float in [-1.0, 1.0]:
					add_block("", _v3(p + side * s * 9.3), _face(dir), Vector2(6.4, 4.6), {"height": 8.0, "opaque": true})
			"outskirts|graveyard":
				for s2: float in [-1.0, 1.0]:
					var q := _v3(p - dir * 4.0 + side * s2 * (half - 3.5))
					add_block("desert_jackal_statue", q, _face(-dir), Vector2(1.9, 3.7), {"height": 3.0})
					var st := _v3(p - dir * 9.0 + side * s2 * (half - 2.0))
					if is_walkable_at(st):
						add_obstacle("desert_stele", st, _face(-dir), 1.1, 0.5, OPT_TALL)
			"outskirts|oasis":
				for s3: float in [-1.0, 1.0]:
					var c := _v3(p + side * s3 * (half - 2.0))
					if is_walkable_at(c):
						add_obstacle("desert_column", c, 0.0, 1.0, 0.95)
					var pp := _v3(p + side * s3 * (half + 1.5) + dir * 3.0)
					_solid("desert_palm_a", pp, rng.randf() * TAU, 1.0, 0.45, OPT_PALM)
			_:
				# Into the Snake Isles: a pair of serpents.
				for s4: float in [-1.0, 1.0]:
					var sp := _v3(p - dir * 3.0 + side * s4 * (half - 3.0))
					if is_walkable_at(sp):
						add_block("desert_serpent_statue", sp, _face(-dir), Vector2(2.5, 2.5), {"height": 4.0})


# ------------------------------------------------------------------ painting: river banks & beyond

## The Iteru's banks: palm groves, reeds at the water, jetties, feluccas on the river.
func _paint_banks() -> void:
	var near := Rect2(150, 150, 370, 360)
	scatter({"desert_palm_a": 3.0, "desert_palm_b": 2.0}, 150, near, {"on": "void", "min_dist": 4.2, "scale": Vector2(0.8, 1.15),
		"cutout": true, "sway": 0.45, "sway_base": 2.0,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 1.5 and _field_at(p).r < 16.0 and _field_at(p).g < 1.6 and _cn.get_noise_2d(p.x * 0.35, p.z * 0.35) > -0.15})
	scatter({"desert_palm_a": 3.0, "desert_palm_b": 2.0}, 90, near, {"on": "walkable", "collide": 0.45, "min_dist": 5.0, "scale": Vector2(0.8, 1.15),
		"cutout": true, "sway": 0.45, "sway_base": 2.0,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 2.2 and _field_at(p).r < 18.0 and _field_at(p).b < 0.3 and _cn.get_noise_2d(p.x * 0.35, p.z * 0.35) > -0.05 and region_at(p) == "outskirts"})
	scatter(["desert_reeds"], 260, near, {"on": "void", "min_dist": 2.4, "scale": Vector2(0.8, 1.35), "shadows": false, "sway": 1.0, "sway_base": 0.5,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > -3.0 and _field_at(p).r < 1.0})
	scatter(["desert_reeds"], 150, near, {"on": "walkable", "min_dist": 2.6, "scale": Vector2(0.7, 1.15), "shadows": false, "sway": 1.0, "sway_base": 0.5,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < 2.8 and _field_at(p).b < 0.25 and not _crossing_cells.has(world_to_cell(p))})
	scatter(["desert_grass_green"], 120, near, {"on": "walkable", "min_dist": 2.4, "scale": Vector2(0.8, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < 5.0 and _field_at(p).b < 0.3})
	scatter(["desert_shrub"], 60, near, {"on": "void", "min_dist": 4.0, "scale": Vector2(0.7, 1.2), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 1.0 and _field_at(p).r < 10.0 and _field_at(p).g < 1.2})
	scatter(["desert_lotus"], 14, near, {"on": "void", "min_dist": 14.0, "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r < -5.0})
	# Everything set on the open banks sits on the terrain (in the water: in it).
	for d in props:
		var dp: Vector3 = d["pos"]
		if dp.y != 0.0 or not near.has_point(Vector2(dp.x, dp.z)) or is_walkable_at(dp):
			continue
		var id := String(d["id"])
		var wd := _water_at(dp)
		if id == "desert_lotus":
			d["pos"] = Vector3(dp.x, water_level + 0.005, dp.z)
		elif id == "desert_reeds" and wd < 0.3:
			d["pos"] = Vector3(dp.x, -0.55, dp.z)
		elif id.begins_with("desert_palm") or id == "desert_shrub" or id == "desert_reeds":
			d["pos"] = Vector3(dp.x, _terrain_y(dp) - 0.1, dp.z)
	# Jetties and feluccas.
	for j in [[Vector3(380, 0, 262), 0.0], [Vector3(300, 0, 258), PI], [Vector3(476, 0, 322), -0.8]]:
		var jp: Vector3 = j[0]
		add_prop("desert_jetty", jp, float(j[1]), 1.0)
		keep(jp, 3.0)
	for bt in [[Vector2(386, 272), 0.0], [Vector2(296, 244), 0.0], [Vector2(470, 336), 0.0], [Vector2(560, 381), 0.0], [Vector2(238, 110), 0.0],
			[Vector2(420, 290), 0.0]]:
		var bp: Vector2 = bt[0]
		var t := _river_dir(bp)
		add_prop("desert_boat", Vector3(bp.x, water_level + 0.05, bp.y), _face(t) + rng.randf_range(-0.2, 0.2), rng.randf_range(0.9, 1.05), OPT_TALL)


## The river's direction (downstream) near p.
func _river_dir(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(0, 1)
	for k in range(RIVER.size() - 1):
		var a: Vector2 = RIVER[k]
		var b: Vector2 = RIVER[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			dir = ab.normalized()
	return dir


## Beyond the zones: rock mesas and far pyramids, dry grass and rocks on the dunes.
func _paint_offmap() -> void:
	for pp in [[Vector3(95, 0, 36), 0.2, 1.0], [Vector3(300, 0, -24), 0.35, 0.8], [Vector3(612, 0, 250), 0.1, 1.1], [Vector3(700, 0, 300), 0.5, 0.8]]:
		var p: Vector3 = pp[0]
		add_prop("desert_pyramid", Vector3(p.x, _terrain_y(p) - 0.8, p.z), float(pp[1]), float(pp[2]))
	for mp in [Vector3(20, 0, 60), Vector3(160, 0, 60), Vector3(520, 0, 140), Vector3(560, 0, 220), Vector3(540, 0, 470), Vector3(660, 0, 470),
			Vector3(760, 0, 240), Vector3(10, 0, 250), Vector3(170, 0, 470), Vector3(420, 0, 10), Vector3(160, 0, 280)]:
		if walk_distance(mp) > 9.0:
			add_prop("desert_mesa", Vector3(mp.x, _terrain_y(mp) - 0.6, mp.z), rng.randf() * TAU, rng.randf_range(0.9, 1.5), OPT_TALL)
	var gr := Rect2(-40, -40, _gw * TILE + 80.0, _gh * TILE + 40.0)
	var placed := scatter(["desert_rock"], 70, gr, {"on": "void", "margin": 3.0, "min_dist": 14.0, "scale": Vector2(0.8, 1.7), "cutout": true,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 6.0 and walk_distance(p) < 12.0})
	placed.append_array(scatter(["desert_grass"], 160, gr, {"on": "void", "margin": 1.5, "min_dist": 5.0, "scale": Vector2(0.8, 1.3), "shadows": false,
		"filter": func(p: Vector3) -> bool: return _field_at(p).r > 4.0 and walk_distance(p) < 10.0}))
	for d in placed:
		var dp: Vector3 = d["pos"]
		d["pos"] = Vector3(dp.x, _terrain_y(dp) - 0.1, dp.z)


# ------------------------------------------------------------------ monsters, looks

func _populate() -> void:
	set_region_pool("outskirts", {"carrion_jackal": 3.0, "linen_dead": 3.0, "dune_archer": 2.5, "drowned_boatman": 3.0,
		"reed_stalker": 2.5, "tomb_guardian": 1.5})
	set_region_pool("oasis", {"caravan_raider": 4.0, "mirage_witch": 2.0, "dune_archer": 2.5, "carrion_jackal": 3.0,
		"sandstone_colossus": 1.0})
	set_region_pool("isles", {"serpent_guard": 4.0, "naga_priest": 3.0, "reed_stalker": 3.0, "drowned_boatman": 2.5})
	set_region_pool("graveyard", {"tomb_guardian": 4.0, "linen_dead": 4.0, "carrion_jackal": 2.5, "jackal_archer": 2.5,
		"embalmer": 2.0})
	set_region_pool("courtyard", {"anubite_warden": 4.0, "jackal_priest": 3.0, "jackal_archer": 3.0, "sandstone_colossus": 1.5,
		"sun_priest": 1.5})
	set_region_theme("oasis", {"ambient": Color(0.82, 0.86, 0.7), "saturation": 1.2, "fog": Color(0.86, 0.88, 0.72),
		"fog_density": 0.003, "sun": Color(1.0, 0.94, 0.8)})
	set_region_theme("isles", {"ambient": Color(0.7, 0.8, 0.72), "ambient_energy": 0.5, "fog": Color(0.66, 0.74, 0.62),
		"fog_density": 0.0085, "sun": Color(0.92, 0.95, 0.82), "sun_energy": 1.35, "sky_horizon": Color(0.78, 0.84, 0.7), "saturation": 1.05})
	set_region_theme("graveyard", {"ambient": Color(0.9, 0.7, 0.58), "ambient_energy": 0.42, "fog": Color(0.86, 0.6, 0.44),
		"fog_density": 0.0075, "sun": Color(1.0, 0.76, 0.56), "sun_energy": 1.45, "sky_top": Color(0.34, 0.42, 0.62),
		"sky_horizon": Color(0.95, 0.66, 0.45), "saturation": 1.0, "contrast": 1.12})
	set_region_theme("courtyard", {"ambient": Color(0.95, 0.76, 0.52), "ambient_energy": 0.46, "fog": Color(0.98, 0.72, 0.42),
		"fog_density": 0.005, "sun": Color(1.0, 0.72, 0.4), "sun_energy": 1.9, "sky_top": Color(0.3, 0.44, 0.72),
		"sky_horizon": Color(1.0, 0.7, 0.4), "saturation": 1.15, "contrast": 1.14, "exposure": 1.02})
	# About a pack per 4500 m2 of walkable ground, a few rares.
	var area := {}
	for k in grid.walk.size():
		if grid.walk[k] == 1:
			var ri := int(region_map[k])
			area[ri] = int(area.get(ri, 0)) + 1
	for r in regions:
		var id := String(r["id"])
		var m2 := float(area.get(int(_region_index[id]), 0)) * TILE * TILE
		var packs := maxi(4, roundi(m2 / 4500.0))
		var rares := 3 if m2 > 40000.0 else 2
		var got := auto_spawn_region(id, packs, rares, 15.0, 14.0)
		if got < packs + rares:
			got += auto_spawn_region(id, packs + rares - got, 0, 10.0, 10.0)
		if got < 5:
			push_warning("act_desert: only %d monster groups in %s" % [got, id])


# ------------------------------------------------------------------ ground

func ground_color(x: float, z: float) -> Color:
	if zone == "hub":
		return _hub_color(x, z)
	return _wilds_color(x, z)


## Ground shader layers (desert): r = pebbles, g = sandstone slabs, b = sand bricks, a = dried
## cracked mud (wet by the water). Uses the field sampled by ground_height / ground_color.
func ground_detail(x: float, z: float) -> Color:
	if zone == "hub":
		var wk := _walk_at(x, z)
		var nh := noise2(x + 5.0, z - 3.0, 0.1, 1)
		return Color(wk * (0.2 + 0.4 * nh), 0.0, wk * 0.45 * smoothstep(0.45, 0.7, noise2(x - 9.0, z + 2.0, 0.08, 1)), 0.0)
	if _fa.is_empty():
		return Color(0, 0, 0, 0)
	if x != _cx or z != _cz:
		_wilds_height(x, z)
	var f := _cf
	var ri := 0
	if x >= 0.0 and z >= 0.0 and x < _gw * TILE and z < _gh * TILE:
		ri = int(region_map[int(z * 0.5) * _gw + int(x * 0.5)])
	var look: Vector4 = _DET_LOOK.get(_region_ids_by_index[ri] if ri < _region_ids_by_index.size() else "", _DET_LOOK[""])
	var n := noise2(x + 17.0, z + 41.0, 0.06, 2)
	var n2 := noise2(x - 83.0, z + 12.0, 0.035, 2)
	var dry := smoothstep(0.8, 2.6, f.r)          # away from the water
	var fert := f.a * (1.0 - smoothstep(0.8, 2.6, f.g))
	var pebbles := (f.b * 0.55 + look.x * smoothstep(0.5, 0.75, n)) * dry * (1.0 - fert)
	var slabs := look.y * smoothstep(0.52, 0.72, n2) * dry * (1.0 - fert)
	var bricks := look.z * smoothstep(0.55, 0.75, noise2(x + 211.0, z - 57.0, 0.05, 2)) * dry * (1.0 - fert)
	var mud := (1.0 - smoothstep(-0.4, 4.5, f.r)) + fert * 0.35 + look.w * 0.5 * smoothstep(0.4, 0.7, n)
	return Color(clampf(pebbles, 0.0, 1.0), clampf(slabs, 0.0, 1.0), clampf(bricks, 0.0, 1.0), clampf(mud, 0.0, 1.0))


func ground_height(x: float, z: float) -> float:
	if zone != "hub":
		return _wilds_height(x, z)
	var inside := x > HUB_X0 - 4.0 and x < HUB_X1 + 4.0 and z > HUB_Z0 - 4.0 and z < HUB_Z1 + 4.0
	if inside:
		return 0.0
	var edge := maxf(maxf(HUB_X0 - 4.0 - x, x - HUB_X1 - 4.0), maxf(HUB_Z0 - 4.0 - z, z - HUB_Z1 - 4.0))
	return _dunes(x, z) * smoothstep(0.0, 14.0, edge)


## The town's ground: sand with wind ripples and dune shading, packed paths, pyramid rubble.
func _hub_color(x: float, z: float) -> Color:
	var n := fbm(x * 0.05, z * 0.05, 3)
	var n2 := vnoise(x * 0.35, z * 0.35)
	var sand := Color(0.88, 0.68, 0.42).lerp(Color(0.93, 0.76, 0.5), smoothstep(0.35, 0.75, n))
	sand = sand.lerp(Color(0.8, 0.55, 0.34), smoothstep(0.55, 0.9, fbm(x * 0.013 + 7.0, z * 0.013, 2)) * 0.5)
	var c := sand
	var h := _dunes(x, z)
	# wind ripples and pale crests / deeper troughs on the dunes
	var ripple := sin(x * 0.85 + z * 0.3 + fbm(x * 0.03, z * 0.03, 2) * 9.0)
	c *= 1.0 + 0.035 * ripple * smoothstep(0.3, 1.5, h)
	c = c.lerp(Color(0.96, 0.82, 0.58), smoothstep(1.8, 4.5, h) * 0.55)
	c = c.lerp(Color(0.76, 0.53, 0.33), (1.0 - smoothstep(0.2, 1.4, h)) * smoothstep(0.1, 0.5, h) * 0.3)
	# walkable ground: packed, a little darker and greyer
	var w := _walk_at(x, z)
	c = c.lerp(Color(0.74, 0.58, 0.41).lerp(Color(0.68, 0.55, 0.4), n2), w * 0.6)
	# pyramid bases: stone rubble colour
	for p in _pyramids:
		var d := maxf(absf(x - float(p[0])), absf(z - float(p[1]))) - float(p[2])
		if d < 3.0:
			c = c.lerp(Color(0.74, 0.62, 0.46), (1.0 - smoothstep(-0.5, 3.0, d)) * 0.7)
	# The ground shader takes vertex colours as linear: pick in sRGB, convert here.
	return (c * (0.96 + 0.08 * n2)).srgb_to_linear()


## Bilinear sample of the wilds fields at a world point (clamped at the grid's edges).
func _sample(x: float, z: float) -> Color:
	var u := clampf(x * 0.5 - 0.5, 0.0, _umax)
	var v := clampf(z * 0.5 - 0.5, 0.0, _vmax)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var k := j * _gw + i
	return _fa[k].lerp(_fa[k + 1], fu).lerp(_fa[k + _gw].lerp(_fa[k + _gw + 1], fu), v - j)


## Relief of the outdoor zones: dunes and mounds from the relief field (computed directly off the
## grid), river beds and banks from the water distance.
func _wilds_height(x: float, z: float) -> float:
	if _fa.is_empty():
		return 0.0
	var f: Color
	if x < 0.0 or z < 0.0 or x > _gw * TILE or z > _gh * TILE:
		f = Color(_water_dist_outside(x, z), _dune_height(x, z), 0.0, 0.0)
	else:
		f = _sample(x, z)
	var h := f.g
	var r := f.r
	if r < 6.0:
		# a dry bank just above the water, then (past ~3 m from the walkable cells, where the World no
		# longer eases the ground in) a drop to a deep bed: the shore follows the smooth water
		# distance, not the cells' staircase
		var bed := (-0.33 + (r + 1.4) * 0.035) if r >= -1.4 else (-0.33 - 3.0 * smoothstep(-1.4, -4.4, r))
		h = lerpf(bed, h, smoothstep(0.8, 6.0, r))
	_cx = x
	_cz = z
	_cf = f
	_ch = h
	return h


func _wilds_color(x: float, z: float) -> Color:
	if _fa.is_empty():
		return _c_sand
	var f: Color
	var h: float
	if x == _cx and z == _cz:
		f = _cf
		h = _ch
	else:
		h = _wilds_height(x, z)
		f = _cf
	var outside := x < 0.0 or z < 0.0 or x > _gw * TILE or z > _gh * TILE
	var c: Color
	var k := 0
	if outside:
		c = _sand_at(x, z)
	else:
		var u := x * 0.5 - 0.5
		var v := z * 0.5 - 0.5
		u = clampf(u, 0.0, _umax)
		v = clampf(v, 0.0, _vmax)
		var i := int(u)
		var j := int(v)
		var fu := u - i
		k = j * _gw + i
		c = _pal[k].lerp(_pal[k + 1], fu).lerp(_pal[k + _gw].lerp(_pal[k + _gw + 1], fu), v - j)
	var tone := c.a
	c.a = 1.0
	# fertile ground: green by the water and on the fields, dark silt under the crops
	var fert := f.a * (1.0 - smoothstep(0.8, 2.6, h))
	if fert > 0.01:
		c = c.lerp(_c_green.lerp(_c_green_b, tone), minf(fert * 1.1, 0.85))
		if fert > 0.6:
			c = c.lerp(_c_silt, (fert - 0.6) * 1.6)
	# worn trails: packed, paler
	if f.b > 0.01:
		c = c.lerp(c * _c_trail, minf(f.b * 1.1, 1.0))
	# the water's edge: wet mud, a dark bed under the water
	if f.r < 1.8:
		c = c.lerp(_c_mud.lerp(_c_damp, minf(f.a * 1.2, 1.0)), (1.0 - smoothstep(-1.6, 1.8, f.r)) * 0.5)
		if f.r < -1.5:
			c = c.lerp(_c_bed, smoothstep(-1.5, -2.8, f.r))
	# dunes: pale crests
	if h > 0.4:
		c = c.lerp(_c_crest, smoothstep(1.5, 5.0, h) * 0.45)
	# near the town the open sand turns into the town's own
	if z > SOUTH_BLEND.x and (outside or grid.walk[k] == 0):
		var tw := _town_weight(x, z)
		if tw > 0.0:
			c = c.lerp(_hub_color(x - _hub_off.x, z - _hub_off.y), tw)
	return c


## Signed distance to open water beyond the grid (the river's and the channels' ends run on
## past its edges).
func _water_dist_outside(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := FAR_WATER
	var lines: Array = [[RIVER, RIVER_HW]]
	lines.append_array(CHANNELS)
	for ln in lines:
		var pts: Array = ln[0]
		var hw: Array = ln[1]
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			if p.x < minf(a.x, b.x) - 40.0 or p.x > maxf(a.x, b.x) + 40.0 or p.y < minf(a.y, b.y) - 40.0 or p.y > maxf(a.y, b.y) + 40.0:
				continue
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t) - lerpf(float(hw[k]), float(hw[k + 1]), t))
	return best


## The open sand's colour (with the baked palette's variation) at a point beyond the grid.
func _sand_at(x: float, z: float) -> Color:
	return _vary(_c_sand, x, z, true)


## A ground colour with the palette's variation: broad tones, mottling, wind streaks, gravel
## patches and (on open sand) ripples; alpha = the mottling tone (0..1).
func _vary(base: Color, x: float, z: float, ripples: bool) -> Color:
	var tone := _cn.get_noise_2d(x, z)
	var nb := _bn.get_noise_2d(x, z)
	var c := base * (0.95 + 0.1 * tone)
	if nb > 0.0:
		c = c.lerp(c * _c_pale, minf(nb * 1.4, 1.0))
	else:
		c = c.lerp(c * _c_dusk, minf(-nb * 1.4, 1.0))
	var st := _bn.get_noise_2d(x * 3.2 + z * 1.1, z * 9.0)
	if st > 0.25:
		c = c.lerp(c * _c_pale, smoothstep(0.25, 0.6, st) * 0.55)
	var gv := _cn.get_noise_2d(x * 0.9 + 311.0, z * 0.9)
	if gv > 0.3:
		c = c.lerp(c * _c_gravel, smoothstep(0.3, 0.6, gv) * 0.5)
	elif ripples:
		c *= 1.0 + 0.045 * sin(x * 0.62 + z * 0.41 + nb * 6.0) * (1.0 - smoothstep(-0.2, 0.3, gv))
	c.a = 0.5 + 0.5 * tone
	return c


## Dune relief (m), >= 0: long wind-shaped ridges plus soft swells.
func _dunes(x: float, z: float) -> float:
	var warp := fbm(x * 0.012, z * 0.012, 2) * 6.0
	var ridge := 1.0 - absf(sin(x * 0.05 + z * 0.022 + warp))
	ridge = ridge * ridge
	var swell := fbm(x * 0.02 + 3.0, z * 0.02 - 5.0, 3)
	return maxf(0.0, swell * 3.6 + ridge * 1.6 - 0.9)


# ------------------------------------------------------------------ helpers

## Box-blurred walkability (two passes) for soft path edges.
func _blur_walk() -> void:
	var w := grid.size.x
	var h := grid.size.y
	var a := PackedFloat32Array()
	a.resize(w * h)
	for k in w * h:
		a[k] = 1.0 if grid.walk[k] == 1 or (grid.floor_cells[k] == 1 and soft.has(Vector2i(k % w, k / w))) else 0.0
	for _pass in 2:
		var b := PackedFloat32Array()
		b.resize(w * h)
		for j in h:
			for i in w:
				var s := 0.0
				var n := 0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := i + di
						var jj := j + dj
						if ii >= 0 and jj >= 0 and ii < w and jj < h:
							s += a[jj * w + ii]
							n += 1
				b[j * w + i] = s / n
		a = b
	_walk_blur = a


func _walk_at(x: float, z: float) -> float:
	if _walk_blur.is_empty():
		return 0.0
	var w := grid.size.x
	var h := grid.size.y
	var u := clampf(x / TILE - 0.5, 0.0, w - 1.001)
	var v := clampf(z / TILE - 0.5, 0.0, h - 1.001)
	if x < 0.0 or z < 0.0 or x > w * TILE or z > h * TILE:
		return 0.0
	var i0 := int(u)
	var j0 := int(v)
	var fu := u - i0
	var fv := v - j0
	var i1 := mini(i0 + 1, w - 1)
	var j1 := mini(j0 + 1, h - 1)
	var top := lerpf(_walk_blur[j0 * w + i0], _walk_blur[j0 * w + i1], fu)
	var bot := lerpf(_walk_blur[j1 * w + i0], _walk_blur[j1 * w + i1], fu)
	return smoothstep(0.2, 0.8, lerpf(top, bot, fv))


## Low ruined sandstone walls (with a pier now and then) line the edges of the walkable ground
## wherever nothing else (city walls, houses, monuments) marks them.
func border_style() -> Dictionary:
	return {
		"segments": {"desert_ruinwall_a": 3.0, "desert_ruinwall_b": 2.0, "desert_ruinwall_c": 2.0},
		"posts": {"desert_ruinwall_pier": 1.0},
		"post_every": 4,
		"length": 2.0,
		"offset": 0.5,
		"scale": Vector2(0.95, 1.05),
		"yaw_jitter": 0.04,
		"min_prop_height": 1.2,
		"prop_clearance": 0.9,
		"max_footprint": 0.8,
		"solid_prefixes": ["desert_wall", "desert_tower", "desert_gate", "desert_house", "desert_pyramid", "desert_pylon",
			"desert_tomb", "desert_colonnade", "desert_sphinx", "desert_statue", "desert_ruin", "desert_awning",
			"desert_obelisk_fallen", "desert_head", "desert_tent", "desert_fountain", "desert_temple", "desert_gateway",
			"desert_portico", "desert_mudhouse", "desert_mesa", "desert_anubis", "desert_jackal", "desert_serpent", "desert_well"],
	}


# ================================================================== ground detail (WorldGroundFx)

## Ground layer amounts per zone ("" = open land between the zones): x = pebble patches, y =
## sandstone slabs, z = buried brick patches, w = extra mud.
const _DET_LOOK := {
	"": Vector4(0.35, 0.25, 0.1, 0.0), "outskirts": Vector4(0.45, 0.3, 0.3, 0.0), "oasis": Vector4(0.2, 0.1, 0.05, 0.3),
	"isles": Vector4(0.1, 0.0, 0.05, 0.8), "graveyard": Vector4(0.6, 0.65, 0.6, 0.0), "courtyard": Vector4(0.3, 0.7, 0.8, 0.0),
}
## Region ids by region_map index (0 = none).
var _region_ids_by_index: Array = [""]
const DRY_GRASS := Color(0.5, 0.4, 0.17)
const GREEN_GRASS := Color(0.2, 0.34, 0.08)
const REED_GREEN := Color(0.24, 0.36, 0.1)
const SAND_DRIFT := Color(0.86, 0.68, 0.44)
const BRICK_TINT := Color(0.8, 0.58, 0.36)


## Details and grass of the outdoor zones: sand drifts and cracks on the paving, brick rubble by
## the ruins and tombs, pebbles, bones, fallen palm fronds; dry desert grass on the sand, green
## grass and reeds by the water, the oasis and the isles.
func _ground_fx_wilds() -> void:
	_region_ids_by_index = [""]
	for r in regions:
		_region_ids_by_index.append(String(r["id"]))
	var tiled := {}
	for tg in tiles:
		for c in tg.get("cells", []):
			tiled[c] = true
	var wk := grid.walk
	for j in range(1, _gh - 1):
		var z := (j + 0.5) * TILE
		for i in range(1, _gw - 1):
			var k := j * _gw + i
			var x := (i + 0.5) * TILE
			var c := Vector2i(i, j)
			var f: Color = _fa[k]
			var ri := int(region_map[k])
			var rid: String = _region_ids_by_index[ri] if ri < _region_ids_by_index.size() else ""
			var walk := wk[k] == 1
			var r := rng.randf()
			if f.r < 0.0:
				# reeds in the shallows next to walkable ground
				if f.r > -2.5 and _near_walk_d(i, j) and rng.randf() < 0.3:
					add_grass(Vector3(x + rng.randf_range(-0.9, 0.9), 0, z + rng.randf_range(-0.9, 0.9)), rng.randf_range(0.75, 1.1),
						REED_GREEN.lerp(DRY_GRASS, rng.randf() * 0.3), "reeds")
				continue
			if not walk:
				continue
			if tiled.has(c):
				# paving: drifted sand, cracks, a chip of stone
				if r < 0.09 + (0.06 if rid == "courtyard" else 0.0):
					add_detail("sand", _jit_d(x, z), rng.randf() * TAU, Vector2(rng.randf_range(1.4, 2.6), rng.randf_range(1.0, 1.8)), SAND_DRIFT)
				elif r < 0.15:
					add_detail("cracks", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.8, 1.6), Color(0.1, 0.07, 0.05))
				elif r < 0.17:
					add_detail("bricks", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 0.9), BRICK_TINT)
				continue
			var fert := f.a
			var near_water := f.r < 5.0
			# --- grass
			if fert > 0.25 or near_water:
				var gp := noise2(x + 300.0, z + 90.0, 0.14, 2)
				if gp > 0.5 - fert * 0.2:
					var dens := int(clampf((gp - 0.5 + fert * 0.2) * 40.0, 1.0, 7.0))
					for q in dens:
						var p := _jit_d(x, z)
						if is_clear(p, 0.3):
							add_grass(p, rng.randf_range(0.8, 1.2), GREEN_GRASS.lerp(DRY_GRASS, rng.randf() * 0.35) * rng.randf_range(0.85, 1.12))
			elif rid != "courtyard" and noise2(x - 140.0, z + 60.0, 0.09, 2) > 0.66 and rng.randf() < 0.45:
				for q in rng.randi_range(1, 3):
					var p2 := _jit_d(x, z)
					if is_clear(p2, 0.3):
						add_grass(p2, rng.randf_range(0.55, 0.9), DRY_GRASS * rng.randf_range(0.85, 1.15))
			# --- details
			if rid == "graveyard" or rid == "courtyard":
				if r < 0.05:
					add_detail("bricks", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.7, 1.1), BRICK_TINT * rng.randf_range(0.85, 1.1))
				elif r < 0.075:
					add_detail("bones", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 0.9), Color(0.86, 0.8, 0.68))
				elif r < 0.1:
					add_detail("pebbles", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 1.0), Color(0.78, 0.62, 0.44))
				elif r < 0.11 and rid == "courtyard":
					add_detail("stain", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(1.0, 1.8), Color(0.25, 0.12, 0.08))
				continue
			if r < 0.025:
				add_detail("pebbles", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 1.0), Color(0.74, 0.58, 0.4))
			elif r < 0.032 and not near_water:
				add_detail("bones", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 0.9), Color(0.86, 0.8, 0.68))
			elif r < 0.045 and (rid == "oasis" or fert > 0.4):
				add_detail("leaves", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(1.0, 1.6), Color(0.46, 0.4, 0.16))
			elif r < 0.05 and near_water:
				add_detail("puddle", _jit_d(x, z), rng.randf() * TAU, Vector2(rng.randf_range(1.0, 2.0), rng.randf_range(0.8, 1.4)), Color(0.3, 0.36, 0.36))
			elif r < 0.058 and rid == "outskirts":
				add_detail("bricks", _jit_d(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 1.0), BRICK_TINT)


func _jit_d(x: float, z: float) -> Vector3:
	return Vector3(x + rng.randf_range(-0.8, 0.8), 0, z + rng.randf_range(-0.8, 0.8))


func _near_walk_d(i: int, j: int) -> bool:
	var wk := grid.walk
	var k := j * _gw + i
	return wk[k - 1] == 1 or wk[k + 1] == 1 or wk[k - _gw] == 1 or wk[k + _gw] == 1


## The town: sand blown onto the plaza's paving, a few cracks, pebbles and straw by the market,
## dry grass tufts in the dunes by the walls.
func _ground_fx_hub() -> void:
	var tiled := {}
	for tg in tiles:
		for c in tg.get("cells", []):
			tiled[c] = true
	var on_tiles := func(p: Vector3) -> bool: return tiled.has(world_to_cell(p))
	scatter_details("sand", 26, Rect2(HUB_X0, HUB_Z0, HUB_X1 - HUB_X0, HUB_Z1 - HUB_Z0), {"filter": on_tiles, "size": Vector2(1.2, 2.4), "stretch": 1.6, "tint": SAND_DRIFT, "clear": 0.8})
	scatter_details("cracks", 14, Rect2(HUB_X0, HUB_Z0, HUB_X1 - HUB_X0, HUB_Z1 - HUB_Z0), {"filter": on_tiles, "size": Vector2(0.8, 1.4), "tint": Color(0.12, 0.08, 0.05)})
	scatter_details({"straw": 2.0, "pebbles": 1.0}, 16, Rect2(HUB_X0, HUB_Z0, HUB_X1 - HUB_X0, HUB_Z1 - HUB_Z0), {"size": Vector2(0.6, 1.0),
		"tints": [Color(0.7, 0.58, 0.32), Color(0.76, 0.62, 0.44)], "clear": 0.8})
	scatter_grass(20, 5, Rect2(-40, -60, 150, 180), {"on": "void", "radius": Vector2(0.8, 1.8), "scale": Vector2(0.55, 0.9), "tints": [DRY_GRASS, DRY_GRASS * 1.15]})

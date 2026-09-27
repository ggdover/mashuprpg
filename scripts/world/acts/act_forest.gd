extends WorldActGen
## Act I — The Whispering Pines (forest). OWNER: acts-forest.
##   hub   "Birkavik": a viking village on a lake shore — longhouses with thatch and turf roofs and
##         crossed gable boards, a fire pit yard, a jetty with a longship, drying racks, a rune
##         stone waystone, pine forest all around. Its north path leads into the wilds.
##   wilds the act's outdoor map (data/layouts/act_forest.json): five zones joined by trails and
##         wide forest paths, each crossing marked by a gateway (rune stones, a wooden gate,
##         standing stones, cairns):
##     outskirts "The Mattis Woods" (+0): open Swedish pine forest to roam — tall red-barked pines,
##         spruces and birches with room between them, groves, sunlit clearings, mossy boulders,
##         fallen logs, a woodcutters' camp and a brook from a waterfall to a pond, with log bridges.
##     tarn "Stillwater Tarn" (+1): a lake with reedy shores, water lilies and birches, islands
##         joined by stone causeways, a broken jetty, a fisher's hut and a witch's hut.
##     hollows "The Grey Dwarf Hollows" (+2): a misty maze of granite outcrops and mossy ravines,
##         dark spruce, ferns, a boulder field and the grey dwarves' burrows.
##     gap "Hell's Gap" (+2): the ruined Mattis fort split by a dark chasm, a log bridge across it,
##         rocky pine forest and old outworks around.
##     downs "The Barrow Downs" (+3): windswept heath with burial mounds, standing stones, rune
##         stones, a stone ship and the Old Barrow (the act dungeon) guarded by the Barrow Wight.
## Layout data only (see WorldActGen). The wilds' ground look comes from per-cell fields (_fine:
## open ground / trails / beds / rock, bilinear) and a coarse zone-look map (_look), sampled with
## noise2() — see _wilds_height() and _wilds_color(). Lakes, the brook, outcrops and the chasm are
## blocked floor cells (no border fences, relief shows); groves, tree stands and clumps block their
## cells softly with one collision cylinder each (collision shapes are the build's big cost); the
## zones' outer edges get the roundpole fences (border_style()).

const WATER_Y := -0.35

## Trail / path polylines (Array of PackedVector2Array, XZ) used for the ground colours (hub).
var _trails: Array = []
## Ponds (hub helpers; none): {"c": Vector2, "r": float, "depth": float}
var _ponds: Array = []
## Per-cell distance (m) from the nearest floor cell centre (hub, like World's relief mask).
var _field := PackedFloat32Array()
## Hub: shore line parameters.
var _shore_base := 51.5
## Trail segments bucketed by 8 m cells (fast _trail_dist): Vector2i -> Array of [Vector2, Vector2].
var _buckets := {}
var _buckets_ready := false
const BUCKET := 8.0
const TRAIL_REACH := 4.5
## Spatial hash of placed decoration (spacing checks): Vector2i -> Array of [Vector3, radius].
var _hash := {}
const HASH_CELL := 4.0


func generate_zone() -> void:
	_trails = []
	_buckets = {}
	_buckets_ready = false
	_ponds = []
	_hash = {}
	if zone == "hub":
		_hub()
	else:
		_wilds()


# ------------------------------------------------------------------ theme

func theme() -> Dictionary:
	return {
		"sky": true,
		"sky_top": Color(0.3, 0.52, 0.82),
		"sky_horizon": Color(0.78, 0.86, 0.86),
		"ground_horizon": Color(0.46, 0.54, 0.42),
		"ground_bottom": Color(0.16, 0.2, 0.13),
		"ambient": Color(0.56, 0.66, 0.56),
		"ambient_energy": 0.52,
		"ambient_sky": 0.5,
		"sun": Color(1.0, 0.91, 0.72),
		"sun_energy": 1.45,
		"sun_rot": Vector3(-50.0, 30.0, 0.0),
		"fog": Color(0.62, 0.74, 0.66),
		"fog_density": 0.0022,
		"fog_sky_affect": 0.25,
		# Height fog stays off here; the Hollows and Hell's Gap raise its density (mist, the chasm).
		"fog_height": 1.4,
		"fog_height_density": 0.0,
		"volumetric_fog": {},
		"exposure": 0.95,
		"contrast": 1.1,
		"saturation": 1.12,
		"glow_intensity": 0.6,
		"light_color": Color(1.0, 0.62, 0.3),
		"light_energy": 2.2,
		"light_range": 9.0,
		"glow_color": Color(1.0, 0.6, 0.28),
		"water_shallow": Color(0.3, 0.44, 0.42),
		"water_deep": Color(0.07, 0.15, 0.17),
		"water_foam": Color(0.82, 0.88, 0.84),
		"water_depth_scale": 1.1,
		"particles": {"kind": "motes", "color": Color(1.0, 0.95, 0.72, 0.75), "amount": 150, "size": 0.07, "speed": 0.22},
		"shaft_strength": 1.4,
		"daylight": true,
	}


# ------------------------------------------------------------------ ground

func ground_height(x: float, z: float) -> float:
	if zone == "hub":
		return _hub_height(x, z)
	return _wilds_height(x, z)


func ground_color(x: float, z: float) -> Color:
	if zone == "hub":
		return _hub_color(x, z)
	return _wilds_color(x, z)


## Ground shader layers (forest): r = gravel, g = mud / puddles, b = leaf litter, a = moss and
## needles. The wilds use the field sampled by ground_color (same point) and the zone weights.
func ground_detail(x: float, z: float) -> Color:
	if zone == "hub":
		return _hub_detail(x, z)
	if _fine.is_empty():
		return Color(0, 0, 0, 0)
	var f := _sample(x, z)
	_look(x, z)
	var n := noise2(x + 71.0, z - 33.0, 0.09, 1)
	var wt := _l_w.r
	var wh := _l_w.g
	var wg := _l_w.b
	var wd := _l_w.a
	var floor_ := 1.0 - f.r
	# trails: gravel, muddy stretches in the wet zones
	var wet_zone := 0.25 + 0.45 * wt + 0.35 * wh
	var gravel := f.g * (0.55 + 0.6 * n) * (1.0 - wet_zone * 0.6) + f.a * 0.45 + wg * 0.18
	var mud := f.g * (1.0 - n) * wet_zone
	# shores: mud right by the water
	if f.b < -0.005:
		mud = maxf(mud, (1.0 - smoothstep(0.05, 0.9, -f.b)) * 0.95)
	# peat bogs on the downs, wet dips in the tarn
	mud = maxf(mud, (wd * 0.6 + wt * 0.4) * smoothstep(0.72, 0.86, noise2(x - 5.0, z + 9.0, 0.05, 2)))
	# leaves under the birches (outskirts, tarn), fewer elsewhere; some on the open ground
	var birch := _l_w0 * 0.75 + wt * 1.0 + wh * 0.15 + wg * 0.2 + wd * 0.08
	var leaves := birch * (floor_ * 0.95 + f.r * 0.45 * smoothstep(0.35, 0.7, noise2(x + 3.0, z + 3.0, 0.07, 2)))
	# moss and needles under the conifers
	var conifer := _l_w0 * 0.55 + wt * 0.25 + wh * 1.0 + wg * 0.85 + wd * 0.3
	var moss := conifer * (floor_ * 0.9 + f.r * 0.3 * n) + f.a * 0.35 * (wh + 0.3)
	return Color(clampf(gravel, 0.0, 1.0), clampf(mud, 0.0, 1.0), clampf(leaves * (1.0 - f.g), 0.0, 1.0), clampf(moss * (1.0 - f.g * 0.8), 0.0, 1.0))


## The village: gravel and mud on the paths and the yard, a muddy shore, leaves at the forest edge.
func _hub_detail(x: float, z: float) -> Color:
	if _field.is_empty():
		return Color(0, 0, 0, 0)
	var td := _trail_dist(x, z) + (vnoise(x * 0.5, z * 0.5) - 0.5) * 1.2
	var path := 1.0 - smoothstep(1.0, 2.2, td)
	var yard := 1.0 - smoothstep(3.0, 6.5, Vector2(x, z).distance_to(Vector2(36, 31)))
	var n := noise2(x + 11.0, z + 4.0, 0.12, 1)
	var sz := _shore_z(x)
	var shore := smoothstep(sz - 4.0, sz - 1.5, z) * (1.0 - smoothstep(sz - 0.2, sz + 1.0, z))
	var d := _fd(x, z)
	var forest := smoothstep(1.5, 6.0, d)
	return Color(clampf((path + yard) * (0.5 + 0.5 * n), 0.0, 1.0), clampf(maxf((path + yard) * (1.0 - n) * 0.45, shore * 0.9), 0.0, 1.0),
		clampf(forest * 0.85 + (1.0 - forest) * 0.3 * n, 0.0, 1.0), clampf(forest * 0.6, 0.0, 1.0))


## Rolling forest hills (>= 0: dips would fill with water).
func _hills(x: float, z: float, amp: float) -> float:
	return maxf(0.0, fbm(x * 0.03 + 3.1, z * 0.03 - 1.7, 3) - 0.38) * amp


func _pond_depth(x: float, z: float) -> float:
	var d := 0.0
	for p in _ponds:
		var c: Vector2 = p["c"]
		var r: float = p["r"]
		var q := Vector2(x, z).distance_to(c) / r
		q += (vnoise(x * 0.35, z * 0.35) - 0.5) * 0.25
		if q < 1.0:
			d = minf(d, -float(p["depth"]) * (1.0 - q * q))
	return d


func _forest_floor(x: float, z: float) -> Color:
	var n := fbm(x * 0.07 - 11.0, z * 0.07 + 5.0, 2)
	var c := Color(0.17, 0.27, 0.1).lerp(Color(0.26, 0.37, 0.13), n)
	# needle-brown patches under the pines
	c = c.lerp(Color(0.34, 0.27, 0.17), smoothstep(0.55, 0.8, vnoise(x * 0.18 + 2.0, z * 0.18)) * 0.6)
	return c


## Distance (m) to the nearest trail centre line; 99 when farther than TRAIL_REACH.
func _trail_dist(x: float, z: float) -> float:
	if not _buckets_ready:
		_build_buckets()
	var p := Vector2(x, z)
	var best := 99.0
	for seg in _buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)), []):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ab := b - a
		var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * tt))
	return best if best <= TRAIL_REACH else 99.0


func _add_trail_line(pv: PackedVector2Array) -> void:
	_trails.append(pv)
	_buckets_ready = false


func _build_buckets() -> void:
	_buckets = {}
	for t in _trails:
		var pts: PackedVector2Array = t
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * TRAIL_REACH
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * TRAIL_REACH
			for bj in range(floori(lo.y / BUCKET), floori(hi.y / BUCKET) + 1):
				for bi in range(floori(lo.x / BUCKET), floori(hi.x / BUCKET) + 1):
					var key := Vector2i(bi, bj)
					if not _buckets.has(key):
						_buckets[key] = []
					(_buckets[key] as Array).append([a, b])
	_buckets_ready = true


# ------------------------------------------------------------------ distance field

## Floor-cell distance field (same idea as World's relief mask).
func _build_field() -> void:
	var w := grid.size.x
	var h := grid.size.y
	_field = PackedFloat32Array()
	_field.resize(w * h)
	for k in w * h:
		_field[k] = 0.0 if grid.floor_cells[k] == 1 else 1e6
	var diag := TILE * 1.4142
	for pass_i in 2:
		var s := -1 if pass_i == 0 else 1
		for jj in h:
			var j: int = jj if pass_i == 0 else h - 1 - jj
			for ii in w:
				var i: int = ii if pass_i == 0 else w - 1 - ii
				var k := j * w + i
				var best := _field[k]
				var i2 := i + s
				var j2 := j + s
				if i2 >= 0 and i2 < w:
					best = minf(best, _field[j * w + i2] + TILE)
				if j2 >= 0 and j2 < h:
					best = minf(best, _field[j2 * w + i] + TILE)
					if i2 >= 0 and i2 < w:
						best = minf(best, _field[j2 * w + i2] + diag)
					var i3 := i - s
					if i3 >= 0 and i3 < w:
						best = minf(best, _field[j2 * w + i3] + diag)
				_field[k] = best


## Distance (m) to the nearest floor cell centre at a point (bilinear; + distance outside the grid).
func _fd(x: float, z: float) -> float:
	var w := grid.size.x
	var h := grid.size.y
	var u := x / TILE - 0.5
	var v := z / TILE - 0.5
	var cu := clampf(u, 0.0, w - 1.0)
	var cv := clampf(v, 0.0, h - 1.0)
	var outside := Vector2(u - cu, v - cv).length() * TILE
	var i0 := mini(int(cu), w - 2)
	var j0 := mini(int(cv), h - 2)
	var fu := cu - i0
	var fv := cv - j0
	var a := lerpf(_field[j0 * w + i0], _field[j0 * w + i0 + 1], fu)
	var b := lerpf(_field[(j0 + 1) * w + i0], _field[(j0 + 1) * w + i0 + 1], fu)
	return lerpf(a, b, fv) + outside


## The ground height World will actually build at a point (relief masked near floor cells).
func _eff_height(x: float, z: float) -> float:
	var h := ground_height(x, z)
	if h == 0.0:
		return 0.0
	return h * smoothstep(1.2, 4.5, _fd(x, z))


# ------------------------------------------------------------------ decoration helpers

func _hash_ok(p: Vector3, r: float) -> bool:
	var key := Vector2i(floori(p.x / HASH_CELL), floori(p.z / HASH_CELL))
	for dj in range(-2, 3):
		for di in range(-2, 3):
			var arr: Array = _hash.get(key + Vector2i(di, dj), [])
			for e in arr:
				var q: Vector3 = e[0]
				var rr: float = e[1]
				if Vector2(q.x - p.x, q.z - p.z).length() < rr + r:
					return false
	return true


func _hash_add(p: Vector3, r: float) -> void:
	var key := Vector2i(floori(p.x / HASH_CELL), floori(p.z / HASH_CELL))
	if not _hash.has(key):
		_hash[key] = []
	(_hash[key] as Array).append([p, r])


## Plant decoration on the ground outside the walkable area. kinds: [[ids (Array or Dict),
## radius (spacing), count, dmin, dmax, opts]], placed in order; opts: "scale" Vector2, "sway",
## "sway_base", "cutout", "shadows", "keep_water" (allow near water), "filter" Callable.
func _plant(rect: Rect2, ids: Variant, r: float, count: int, dmin: float, dmax: float, opts: Dictionary = {}) -> int:
	var placed := 0
	var tries := count * 10
	var sc_range: Vector2 = opts.get("scale", Vector2(0.85, 1.2))
	var filt: Callable = opts.get("filter", Callable())
	for t in tries:
		if placed >= count:
			break
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
		var d := _fd(p.x, p.z)
		if d < dmin or d > dmax:
			continue
		# far from any trail, thin out (only the overview camera sees it)
		if d > 26.0 and rng.randf() < (d - 26.0) / 22.0:
			continue
		var eh := _eff_height(p.x, p.z)
		if eh < -0.12:
			continue
		if _pond_depth(p.x, p.z) < -0.05 and not bool(opts.get("keep_water", false)):
			continue
		if filt.is_valid() and not bool(filt.call(p)):
			continue
		if not _hash_ok(p, r) or not is_clear(p, r * 0.5):
			continue
		_hash_add(p, r)
		var id := pick(ids)
		var sc := rng.randf_range(sc_range.x, sc_range.y)
		var o := {"cutout": bool(opts.get("cutout", false)), "shadows": bool(opts.get("shadows", true)),
			"sway": float(opts.get("sway", 0.0)), "sway_base": float(opts.get("sway_base", 1.0)), "vary": 0.1}
		p.y = eh - 0.05
		add_prop(id, p, rng.randf() * TAU, sc, o)
		placed += 1
	return placed


## Forest trees: tall pines / spruces / birches.
func _plant_trees(rect: Rect2, count: int, spacing: float, filt: Callable = Callable()) -> void:
	var near := {"forest_pine_a": 4.0, "forest_pine_b": 3.0, "forest_birch": 2.2, "forest_spruce": 2.0}
	var deep := {"forest_pine_a": 3.0, "forest_pine_b": 2.5, "forest_spruce": 4.5, "forest_birch": 0.8}
	var tries := count * 8
	var placed := 0
	for t in tries:
		if placed >= count:
			break
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
		var d := _fd(p.x, p.z)
		if d < 1.7:
			continue
		if d > 28.0 and rng.randf() < (d - 28.0) / 20.0:
			continue
		var eh := _eff_height(p.x, p.z)
		if eh < -0.1 or _pond_depth(p.x, p.z) < -0.02:
			continue
		if filt.is_valid() and not bool(filt.call(p)):
			continue
		var sp := spacing * (0.8 if d > 8.0 else 1.0)
		# Trees just south of walkable ground stand between the camera and the player: fewer and
		# smaller there, so the crowns don't fill the view.
		var occ := d < 10.0 and _occluder(p)
		if occ and (d < 5.0 or rng.randf() < 0.5):
			continue
		if not _hash_ok(p, sp * 0.5) or not is_clear(p, 0.8):
			continue
		_hash_add(p, sp * 0.5)
		var id := pick(near if d < 6.0 else deep)
		var sc := rng.randf_range(0.85, 1.18)
		if occ:
			id = pick({"forest_spruce": 2.0, "forest_birch": 1.0, "forest_pine_b": 1.0})
			sc = rng.randf_range(0.55, 0.72)
		p.y = eh - 0.1
		add_prop(id, p, rng.randf() * TAU, sc, {"cutout": true, "shadows": true, "sway": _sway(id), "sway_base": _sway_base(id), "vary": 0.12})
		placed += 1


## Wind sway per tree model (sway_base is in model space, so it is the same for every instance —
## props are batched by their parameters).
func _sway(id: String) -> float:
	return 0.5 if id == "forest_birch" else 0.28


func _sway_base(id: String) -> float:
	match id:
		"forest_pine_a", "forest_stand_a":
			return 6.0
		"forest_pine_b":
			return 5.0
		"forest_birch", "forest_stand_b":
			return 3.0
	return 2.5


## True if floor lies a few metres beyond p as the camera looks (p would hide it). The default
## camera looks north-west (CameraRig.YAW_DEG).
func _occluder(p: Vector3) -> bool:
	var yaw := deg_to_rad(CameraRig.YAW_DEG)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	for d in [2.5, 5.0, 7.5, 10.0]:
		for o in [-7.0, -3.5, 0.0, 3.5, 7.0]:
			var q: Vector2 = Vector2(p.x, p.z) + fwd * float(d) + side * float(o)
			if _fd(q.x, q.y) < 0.6:
				return true
	return false


## A tree standing on walkable ground (collision).
func _tree_obstacle(pos: Vector3, id: String = "") -> void:
	var tid := id if id != "" else pick({"forest_pine_a": 3.0, "forest_pine_b": 2.0, "forest_birch": 2.0})
	var sc := rng.randf_range(0.9, 1.15)
	add_obstacle(tid, pos, rng.randf() * TAU, sc, 0.45, {"cutout": true, "sway": _sway(tid), "sway_base": _sway_base(tid)})
	_hash_add(pos, 1.6)


## Trail carving with a ragged edge; also records the trail for the ground colours.
func _trail(points: Array, width: float) -> void:
	var pv := PackedVector2Array()
	for p in points:
		pv.append(Vector2((p as Vector3).x, (p as Vector3).z))
	_add_trail_line(pv)
	for k in points.size() - 1:
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 1.2)))
		for s in n + 1:
			var p := a.lerp(b, float(s) / n)
			var wob := 0.8 + 0.45 * vnoise(p.x * 0.12 + 3.0, p.z * 0.12)
			carve_disc(p, width * 0.5 * wob)


# ================================================================== HUB: Birkavik

func _shore_z(x: float) -> float:
	return _shore_base + 2.5 * sin(x * 0.07 + 1.0) + 1.6 * (vnoise(x * 0.08, 3.0) - 0.5)


func _hub_height(x: float, z: float) -> float:
	var h := _hills(x, z, 5.0)
	var sz := _shore_z(x)
	if z > sz - 2.5:
		var t := clampf((z - (sz - 2.5)) / 7.0, 0.0, 1.0)
		h = lerpf(h, -2.4, smoothstep(0.0, 1.0, t))
	return h


func _hub_color(x: float, z: float) -> Color:
	var d := _fd(x, z)
	var sz := _shore_z(x)
	var c: Color
	if d > 6.0:
		c = _forest_floor(x, z)
	else:
		var n := fbm(x * 0.08, z * 0.08, 3)
		var meadow := Color(0.33, 0.49, 0.16).lerp(Color(0.46, 0.56, 0.2), smoothstep(0.35, 0.75, n))
		meadow = meadow.lerp(Color(0.55, 0.58, 0.26), smoothstep(0.78, 0.95, n) * 0.6)
		meadow = meadow.lerp(meadow.darkened(0.16), vnoise(x * 0.45, z * 0.45) * 0.7)
		c = meadow if d < 1.5 else meadow.lerp(_forest_floor(x, z), smoothstep(1.5, 6.0, d))
	# worn earth paths and the trampled yard
	var td := _trail_dist(x, z) + (vnoise(x * 0.5, z * 0.5) - 0.5) * 1.2
	var dirt := Color(0.45, 0.35, 0.22).lerp(Color(0.52, 0.42, 0.28), vnoise(x * 0.7, z * 0.7))
	c = c.lerp(dirt, (1.0 - smoothstep(1.0, 2.2, td)) * 0.9)
	var yard := Vector2(x, z).distance_to(Vector2(36, 31))
	c = c.lerp(dirt.darkened(0.05), (1.0 - smoothstep(3.0, 6.5, yard + (vnoise(x * 0.4, z * 0.4) - 0.5) * 2.0)) * 0.8)
	# stony beach, lake bed
	if z > sz - 5.0:
		var sand := Color(0.5, 0.48, 0.38).lerp(Color(0.42, 0.42, 0.35), vnoise(x * 0.6, z * 0.6))
		c = c.lerp(sand, smoothstep(sz - 5.0, sz - 2.0, z) * 0.85)
		c = c.lerp(Color(0.24, 0.26, 0.2), smoothstep(sz - 0.5, sz + 4.0, z))
	return c


func _hub() -> void:
	setup_grid(Vector2i(36, 30))
	ground_rect = Rect2(-24.0, -30.0, 120.0, 124.0)
	has_water = true
	water_level = WATER_Y
	reveal_all = true
	# Walkable village green (x 10..62, z 8..48) with a ragged edge, bays, and the north path.
	carve_rect(Rect2i(5, 4, 26, 20))
	for j in range(4, 24):
		for i in range(5, 31):
			var edge := mini(mini(i - 5, 30 - i), mini(j - 4, 23 - j))
			if edge == 0 and vnoise(i * 0.7, j * 0.7) > 0.62 and not (i >= 15 and i <= 19):
				grid.set_void(Vector2i(i, j))
				grid.set_opaque(Vector2i(i, j), false)
	carve_disc(Vector3(8, 0, 30), 4.5)
	carve_disc(Vector3(63, 0, 36), 3.5)
	_trail([Vector3(34, 0, 10), Vector3(34.5, 0, 5), Vector3(35.5, 0, 1.2)], 6.0)
	_build_field()
	# Paths for the ground colour (start -> yard -> hall / portal / stall / stash / jetty).
	_add_trail_line(PackedVector2Array([Vector2(36, 44), Vector2(36, 31), Vector2(33.5, 22), Vector2(34, 10), Vector2(35.5, -14)]))
	_add_trail_line(PackedVector2Array([Vector2(36, 31), Vector2(42, 24), Vector2(44.4, 19.5)]))
	_add_trail_line(PackedVector2Array([Vector2(36, 31), Vector2(28, 38), Vector2(22, 44.5)]))
	_add_trail_line(PackedVector2Array([Vector2(36, 31), Vector2(44, 38), Vector2(48, 41.5)]))
	_add_trail_line(PackedVector2Array([Vector2(36, 38), Vector2(42, 44), Vector2(44, 49)]))
	_add_trail_line(PackedVector2Array([Vector2(36, 31), Vector2(25, 31), Vector2(21.5, 30)]))
	_add_trail_line(PackedVector2Array([Vector2(36, 31), Vector2(48, 30), Vector2(53, 30)]))
	start = Vector3(36, 0, 42)
	keep(start, 2.0)
	portal_spot = {"pos": Vector3(42.5, 0, 42.5), "yaw": 0.0}
	keep(portal_spot["pos"], 2.6)
	# Buildings.
	add_building("forest_longhouse", Vector3(44, 0, 15), 0.0, Vector2(12.6, 6.6))
	add_building("forest_turfhouse", Vector3(21.5, 0, 14), 0.0, Vector2(7.6, 5.0))
	add_building("forest_longhouse", Vector3(16.5, 0, 32), PI * 0.5, Vector2(12.6, 6.6))
	add_building("forest_turfhouse", Vector3(56.5, 0, 30), -PI * 0.5, Vector2(7.6, 5.0))
	add_building("forest_hut", Vector3(56, 0, 15), -0.25, Vector2(3.2, 2.6))
	add_building("forest_hut", Vector3(27, 0, 45.5), 0.35, Vector2(3.2, 2.6))
	# The yard: fire pit, rune stone waystone, portal north.
	add_obstacle("forest_firepit", Vector3(36, 0, 31), 0.0, 1.0, 0.95, {"cutout": false})
	add_light(Vector3(36, 1.4, 31), Color(1.0, 0.6, 0.28), 2.4, 9.0, true)
	add_glow(Vector3(36, 0, 31), 3.2, Color(1.0, 0.55, 0.22))
	add_waystone(Vector3(29.5, 0, 23.5), 0.35, "forest_runestone", Vector2(2.4, 1.6))
	add_exit("wilds", Vector3(35, 0, 1), Vector2i(0, -1))
	# Merchant at the trader's stall, stash by the east house.
	add_block("forest_stall", Vector3(22, 0, 41.2), 0.0, Vector2(3.0, 2.0), {"height": 2.5})
	add_vendor(Vector3(22, 0, 40.5), 0.0)
	add_stash(Vector3(49.5, 0, 40.5), 0.0)
	# Shore: jetty + longship on the lake, a boat pulled up, drying racks.
	add_prop("forest_jetty", Vector3(44, -0.1, 47.6), 0.0, 1.0, {"shadows": true})
	add_prop("forest_longship", Vector3(48.2, WATER_Y + 0.1, 54.5), PI * 0.5 + 0.04, 1.0, {"shadows": true})
	add_prop("forest_boat", Vector3(24.5, _eff_height(24.5, 49.4) - 0.05, 49.4), 0.28, 1.0)
	add_block("forest_rack", Vector3(31, 0, 44.5), 0.15, Vector2(3.4, 1.2), {"cutout": false})
	add_block("forest_rack", Vector3(58, 0, 42.5), -0.5, Vector2(3.4, 1.2), {"cutout": false})
	# Wattle pen (west of the stall) and a fence by the hall.
	for f in [[Vector3(11, 0, 45), 0.0], [Vector3(13, 0, 45), 0.0], [Vector3(15, 0, 45), 0.0],
			[Vector3(16, 0, 44), PI * 0.5], [Vector3(10, 0, 44), PI * 0.5],
			[Vector3(51, 0, 22), 0.0], [Vector3(53, 0, 22), 0.0], [Vector3(55, 0, 22), 0.0]]:
		add_block("forest_fence", f[0], f[1], Vector2(2.0, 0.35), {"cutout": false, "height": 1.2})
	# Barrels, crates, a few birches and pines in the village.
	for b in [[Vector3(19.4, 0, 43.4), "env_barrel"], [Vector3(19.0, 0, 42.2), "env_crate"], [Vector3(51.3, 0, 19.3), "env_barrel"],
			[Vector3(50.4, 0, 20.2), "env_barrel"], [Vector3(38.8, 0, 19.4), "env_crate"], [Vector3(52.0, 0, 40.2), "env_crate"],
			[Vector3(60.5, 0, 25.5), "env_barrel"], [Vector3(24.8, 0, 18.2), "env_crate"]]:
		add_obstacle(b[1], b[0], rng.randf() * TAU, 0.95, 0.42, {"cutout": false})
	for t in [Vector3(26, 0, 34.5), Vector3(47.5, 0, 34.5), Vector3(12, 0, 22), Vector3(61, 0, 12), Vector3(12.5, 0, 10.5)]:
		_tree_obstacle(t, "forest_birch" if rng.randf() < 0.6 else "forest_pine_b")
	# Woodpiles by the houses, a cart, a storage hut in the north-west corner.
	for w in [[Vector3(39.8, 0, 19.7), 0.0], [Vector3(59.6, 0, 24.4), PI * 0.5], [Vector3(20.8, 0, 17.8), 0.0], [Vector3(21.9, 0, 26.2), PI * 0.5]]:
		add_block("forest_woodpile", w[0], w[1], Vector2(2.4, 1.0), {"cutout": false, "height": 1.4})
	add_obstacle("town_cart", Vector3(42.5, 0, 36.0), 0.7, 1.0, 1.4, {"cutout": false})
	add_building("forest_hut", Vector3(12.6, 0, 16.2), 0.45, Vector2(3.2, 2.6))
	# Grass tufts and flowers on the green, reeds along the shore.
	var green := func(p: Vector3) -> bool:
		return _trail_dist(p.x, p.z) > 2.4 and p.distance_to(Vector3(36, 0, 31)) > 6.5
	_plant(Rect2(10, 8, 52, 40), ["forest_grass"], 0.9, 170, -1.0, 0.1, {"shadows": false, "filter": green, "scale": Vector2(0.8, 1.3)})
	_plant(Rect2(-10, 44, 92, 18), ["forest_reeds"], 1.1, 60, 1.5, 12.0, {"shadows": false, "keep_water": true,
		"filter": func(p: Vector3) -> bool: return absf(p.z - (_shore_z(p.x) - 0.6)) < 1.3 and absf(p.x - 44.0) > 3.0,
		"scale": Vector2(0.8, 1.2)})
	# Meadow decoration on the walkable ground (no collision).
	_plant(Rect2(10, 8, 52, 40), ["forest_flowers"], 1.6, 40, -1.0, 0.1,
		{"shadows": false, "filter": func(p: Vector3) -> bool: return _trail_dist(p.x, p.z) > 2.6 and p.distance_to(Vector3(36, 0, 31)) > 6.0})
	_plant(Rect2(10, 8, 52, 40), ["forest_mushrooms", "forest_fern"], 1.2, 8, -1.0, 0.1,
		{"shadows": false, "filter": func(p: Vector3) -> bool: return _trail_dist(p.x, p.z) > 3.0 and _fd_walk_edge(p) < 3.0})
	# The forest around the village (not on the lake, not in front of the north path).
	var keep_path := func(p: Vector3) -> bool:
		return not (absf(p.x - 35.0) < 3.4 and p.z < 6.0) and p.z < _shore_z(p.x) - 4.0
	_plant_trees(ground_rect.grow(-2.0), 520, 3.3, keep_path)
	_plant(ground_rect, {"forest_shrub": 5.0, "forest_fern": 2.5, "forest_stump": 0.4, "forest_mushrooms": 0.4}, 1.2, 320, 1.4, 16.0,
		{"shadows": false, "filter": keep_path, "scale": Vector2(0.8, 1.25)})
	_plant(ground_rect, {"forest_boulder_a": 2.0, "forest_boulder_b": 1.5}, 2.4, 26, 2.0, 22.0,
		{"filter": keep_path, "scale": Vector2(0.7, 1.15)})
	_plant(ground_rect, {"forest_log": 1.0}, 3.0, 10, 2.5, 18.0, {"filter": keep_path})
	# Reeds / stones at the beach.
	_plant(Rect2(0, 44, 72, 14), {"forest_boulder_b": 1.0, "forest_shrub": 1.0}, 2.0, 10, 2.0, 9.0,
		{"filter": func(p: Vector3) -> bool: return p.z > _shore_z(p.x) - 5.0 and p.z < _shore_z(p.x) - 1.0, "scale": Vector2(0.5, 0.8)})
	# Sun shafts at the forest edge.
	for s in [Vector3(6, 0, 10), Vector3(66, 0, 8), Vector3(67, 0, 40), Vector3(4, 0, 40), Vector3(30, 0, 2)]:
		add_shaft(s, 15.0, 3.2, Color(1.0, 0.94, 0.72), 2.06, 26.0)
	_ground_fx_hub()


## Distance from a walkable point to the walkable area's edge (m), capped at 6.
func _fd_walk_edge(p: Vector3) -> float:
	var c0 := world_to_cell(p)
	var best := 6.0
	for j in range(c0.y - 3, c0.y + 4):
		for i in range(c0.x - 3, c0.x + 4):
			var c := Vector2i(i, j)
			if not grid.is_floor(c):
				best = minf(best, cell_center(c).distance_to(Vector3(p.x, 0, p.z)) - 1.0)
	return best



# ================================================================== WILDS: the act's outdoor zones

## Ground kinds of the wilds' cells (_kind). Features are blocked FLOOR cells: no border fences
## around them, but World shows their relief (the beds under the water, the chasm, rock); grove
## cells are soft (flat, a cylinder or two for collision).
const K_VOID := 0     # outside the zones: forest floor (fences along the zone edges)
const K_OPEN := 1     # walkable ground
const K_GROVE := 2    # a grove (trees and undergrowth)
const K_WATER := 3    # lake / brook (bed below the water)
const K_ROCK := 4     # granite outcrop (relief up)
const K_GORGE := 5    # Hell's Gap
const K_DECK := 6     # bridge / causeway (walkable)
## Open-ground amount (_fine.r) per kind.
const OPEN_BY_KIND := [0.0, 1.0, 0.3, 1.0, 0.0, 0.0, 1.0]

## Zone looks (LINEAR ground colours, like the hub's): open ground, its patches, the forest floor
## beyond the walkable ground, trails. Order = LOOK_IDS.
const LOOK_IDS: Array[String] = ["outskirts", "tarn", "hollows", "gap", "downs"]
const PAL_OPEN := [Color(0.075, 0.145, 0.03), Color(0.12, 0.21, 0.04), Color(0.055, 0.1, 0.03), Color(0.085, 0.125, 0.045), Color(0.21, 0.19, 0.07)]
const PAL_PATCH := [Color(0.04, 0.085, 0.018), Color(0.2, 0.24, 0.07), Color(0.12, 0.13, 0.1), Color(0.12, 0.115, 0.085), Color(0.17, 0.1, 0.065)]
const PAL_FOREST := [Color(0.035, 0.06, 0.018), Color(0.04, 0.068, 0.022), Color(0.026, 0.042, 0.018), Color(0.038, 0.05, 0.026), Color(0.065, 0.07, 0.03)]
const PAL_TRAIL := [Color(0.21, 0.13, 0.06), Color(0.2, 0.14, 0.07), Color(0.14, 0.13, 0.1), Color(0.17, 0.14, 0.09), Color(0.24, 0.19, 0.11)]
const C_LICHEN := Color(0.2, 0.25, 0.09)
const C_NEEDLES := Color(0.12, 0.07, 0.03)
const C_ROCK := Color(0.19, 0.19, 0.18)
const C_SAND := Color(0.25, 0.22, 0.14)
const C_BED := Color(0.06, 0.07, 0.04)
const C_GORGE := Color(0.008, 0.008, 0.008)
## Coarse zone-look map cell (m).
const LOOK_CELL := 8.0
## Spatial hash cell of small decoration (m).
const HASH_S := 2.0
## The Mattis fort in Hell's Gap (m).
const FORT := Rect2(348, 42, 80, 56)
const FORT_GATE_X := 410.0
const SUN_YAW := 2.06
const SUN_TILT := 26.0

var _kind := PackedByteArray()
## Per-cell ground field (bilinear): r = open ground (1) vs forest floor (0), g = trail,
## b = bed depth (m, <= 0: lake / brook beds, the chasm), a = rock.
var _fine := PackedColorArray()
var _fw := 0
var _fh := 0
## Trails: [PackedVector2Array (m), width]; named routes: name -> PackedVector2Array.
var _lines: Array = []
var _route := {}
## Zone edge cells (walkable, next to open land outside the zones): [Vector2i, Vector2 normal out].
var _edges: Array = []
## Small decoration spacing: Vector2i -> Array of [Vector2, r].
var _hash_s := {}
## Coarse zone-look map: weights of LOOK_IDS[1..4] (r, g, b, a) per cell, 1..5 where one look
## covers a cell and its neighbours (0 = mixed).
var _lorg := Vector2.ZERO
var _lw := 0
var _lh := 0
var _lwt := PackedColorArray()
var _lpure := PackedByteArray()
var _l_open := Color()
var _l_patch := Color()
var _l_forest := Color()
var _l_trail := Color()
## Zone weights of the last _look(): outskirts, and (r, g, b, a) = tarn, hollows, gap, downs.
var _l_w0 := 1.0
var _l_w := Color(0, 0, 0, 0)
## Last _sample() point and value (World asks for the height, then the colour, of each vertex).
var _sx := INF
var _sz := INF
var _sf := Color()
## Features: cell -> e (0 middle .. 1 rim).
var _brook := {}
var _lake_cells := {}
var _gorge_cells := {}
## The camera's side of the player (the default camera looks north-west).
var _cam_dir := Vector2(0.61, 0.79)


func _wilds() -> void:
	use_layout()
	has_water = true
	water_level = WATER_Y
	_fw = grid.size.x
	_fh = grid.size.y
	_kind = grid.floor_cells.duplicate()
	_fine = PackedColorArray()
	_fine.resize(_fw * _fh)
	_fine.fill(Color(0, 0, 0, 0))
	_hash_s = {}
	_lines = []
	_route = {}
	_sx = INF
	var yaw := deg_to_rad(CameraRig.YAW_DEG)
	_cam_dir = Vector2(sin(yaw), cos(yaw))
	_routes()
	_arrivals()
	_gateways()
	_paint_outskirts()
	_paint_tarn()
	_paint_hollows()
	_paint_gap()
	_paint_downs()
	_scan()
	_edge_forest()
	_build_looks()
	_zone_looks()
	_monsters()
	_ground_fx_wilds()


# ------------------------------------------------------------------ ground look

## Bilinear sample of the ground field (cached for the last point).
func _sample(x: float, z: float) -> Color:
	if x == _sx and z == _sz:
		return _sf
	var u := clampf(x * 0.5 - 0.5, 0.0, _fw - 1.001)
	var v := clampf(z * 0.5 - 0.5, 0.0, _fh - 1.001)
	var i0 := int(u)
	var j0 := int(v)
	var k := j0 * _fw + i0
	var fu := u - i0
	var a: Color = _fine[k].lerp(_fine[k + 1], fu)
	var b: Color = _fine[k + _fw].lerp(_fine[k + _fw + 1], fu)
	_sx = x
	_sz = z
	_sf = a.lerp(b, v - j0)
	return _sf


## The zone look at a point: sets _l_open, _l_patch, _l_forest, _l_trail.
func _look(x: float, z: float) -> void:
	var u := (x - _lorg.x) / LOOK_CELL - 0.5
	var v := (z - _lorg.y) / LOOK_CELL - 0.5
	var i0 := clampi(floori(u), 0, _lw - 2)
	var j0 := clampi(floori(v), 0, _lh - 2)
	var k := j0 * _lw + i0
	var p := _lpure[k]
	if p != 0 and p == _lpure[k + 1] and p == _lpure[k + _lw] and p == _lpure[k + _lw + 1]:
		_l_open = PAL_OPEN[p - 1]
		_l_patch = PAL_PATCH[p - 1]
		_l_forest = PAL_FOREST[p - 1]
		_l_trail = PAL_TRAIL[p - 1]
		_l_w0 = 1.0 if p == 1 else 0.0
		_l_w = Color(1.0 if p == 2 else 0.0, 1.0 if p == 3 else 0.0, 1.0 if p == 4 else 0.0, 1.0 if p == 5 else 0.0)
		return
	var fu := clampf(u - i0, 0.0, 1.0)
	var fv := clampf(v - j0, 0.0, 1.0)
	var w: Color = _lwt[k].lerp(_lwt[k + 1], fu).lerp(_lwt[k + _lw].lerp(_lwt[k + _lw + 1], fu), fv)
	var w0 := maxf(0.0, 1.0 - w.r - w.g - w.b - w.a)
	_l_w0 = w0
	_l_w = w
	_l_open = PAL_OPEN[0] * w0 + PAL_OPEN[1] * w.r + PAL_OPEN[2] * w.g + PAL_OPEN[3] * w.b + PAL_OPEN[4] * w.a
	_l_patch = PAL_PATCH[0] * w0 + PAL_PATCH[1] * w.r + PAL_PATCH[2] * w.g + PAL_PATCH[3] * w.b + PAL_PATCH[4] * w.a
	_l_forest = PAL_FOREST[0] * w0 + PAL_FOREST[1] * w.r + PAL_FOREST[2] * w.g + PAL_FOREST[3] * w.b + PAL_FOREST[4] * w.a
	_l_trail = PAL_TRAIL[0] * w0 + PAL_TRAIL[1] * w.r + PAL_TRAIL[2] * w.g + PAL_TRAIL[3] * w.b + PAL_TRAIL[4] * w.a


## Relief of the wilds: gentle forest hills off the walkable ground, granite outcrops, the beds of
## the lakes and the brook, the chasm (World flattens it on and next to walkable cells).
func _wilds_height(x: float, z: float) -> float:
	var f := _sample(x, z)
	var n := noise2(x - 40.0, z + 25.0, 0.035, 2)
	return f.b + f.a * 1.5 + maxf(0.0, n - 0.34) * (1.6 + f.a * 9.0)


func _wilds_color(x: float, z: float) -> Color:
	var f := _sample(x, z)
	_look(x, z)
	var n := noise2(x + 13.0, z - 7.0, 0.06, 2)
	var s := noise2(x, z, 0.45, 1)
	# open ground: the zone's ground with softly blended patches (blueberry scrub, sedge, heather,
	# stone), lichen spots and a little speckle
	var open := _l_open.lerp(_l_patch, smoothstep(0.42, 0.72, n))
	open = open.lerp(C_LICHEN, smoothstep(0.7, 0.9, s) * 0.35) * (0.88 + 0.24 * s)
	# forest floor: dark moss and needle-brown under the trees
	var forest := _l_forest.lerp(C_NEEDLES, smoothstep(0.45, 0.85, n) * 0.35) * (0.9 + 0.2 * s)
	var c := forest.lerp(open, f.r)
	if f.g > 0.004:
		c = c.lerp(_l_trail * (0.88 + 0.24 * s), f.g * 0.92)
	if f.a > 0.004:
		c = c.lerp(C_ROCK * (0.78 + 0.44 * s), f.a)
	if f.b < -0.02:
		var dp := -f.b
		if f.a > 0.5:
			c = c.lerp(C_GORGE, smoothstep(0.8, 6.0, dp))
		else:
			c = c.lerp(C_SAND * (0.9 + 0.2 * s), smoothstep(0.05, 0.5, dp) * 0.8)
			c = c.lerp(C_BED, smoothstep(0.7, 1.8, dp))
	return c


## Finish the ground field (open ground per kind) and find the zones' edge cells (walkable ground
## next to open land outside the zones) with their outward normals.
func _scan() -> void:
	_edges = []
	var fl := grid.floor_cells
	var wk := grid.walk
	for j in range(1, _fh - 1):
		var row := j * _fw
		for i in range(1, _fw - 1):
			var k := row + i
			var kd := _kind[k]
			if kd == K_VOID:
				continue
			var col := _fine[k]
			col.r = OPEN_BY_KIND[kd]
			_fine[k] = col
			if (kd != K_OPEN and kd != K_DECK) or wk[k] == 0:
				continue
			var nx := 0
			var nz := 0
			if fl[k - 1] == 0:
				nx -= 1
			if fl[k + 1] == 0:
				nx += 1
			if fl[k - _fw] == 0:
				nz -= 1
			if fl[k + _fw] == 0:
				nz += 1
			if nx != 0 or nz != 0:
				_edges.append([Vector2i(i, j), Vector2(nx, nz).normalized()])
	_sx = INF


## The coarse zone-look map: each cell takes the zone at its centre (open land between the zones:
## the nearest zone), then a 3x3 blur gives the blend weights.
func _build_looks() -> void:
	_lorg = ground_rect.position
	_lw = int(ceil(ground_rect.size.x / LOOK_CELL)) + 1
	_lh = int(ceil(ground_rect.size.y / LOOK_CELL)) + 1
	var n := _lw * _lh
	var lab := PackedByteArray()
	lab.resize(n)
	var q := PackedInt32Array()
	for cj in _lh:
		for ci in _lw:
			var p := _lorg + Vector2((ci + 0.5) * LOOK_CELL, (cj + 0.5) * LOOK_CELL)
			var rid := region_of_cell(Vector2i(floori(p.x / TILE), floori(p.y / TILE)))
			if rid != "":
				lab[cj * _lw + ci] = maxi(LOOK_IDS.find(rid), 0) + 1
				q.append(cj * _lw + ci)
	var head := 0
	while head < q.size():
		var k := q[head]
		head += 1
		var ci := k % _lw
		var cj := k / _lw
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = ci + d.x
			var nj: int = cj + d.y
			if ni < 0 or nj < 0 or ni >= _lw or nj >= _lh:
				continue
			var nk := nj * _lw + ni
			if lab[nk] == 0:
				lab[nk] = lab[k]
				q.append(nk)
	_lwt = PackedColorArray()
	_lwt.resize(n)
	_lpure = PackedByteArray()
	_lpure.resize(n)
	var cnt := PackedInt32Array()
	cnt.resize(6)
	for cj in _lh:
		for ci in _lw:
			cnt.fill(0)
			for dj in range(-1, 2):
				var jj := clampi(cj + dj, 0, _lh - 1)
				for di in range(-1, 2):
					var ii := clampi(ci + di, 0, _lw - 1)
					cnt[lab[jj * _lw + ii]] += 1
			var k2 := cj * _lw + ci
			_lwt[k2] = Color(cnt[2] / 9.0, cnt[3] / 9.0, cnt[4] / 9.0, cnt[5] / 9.0)
			var own := lab[k2]
			_lpure[k2] = own if own > 0 and cnt[own] == 9 else 0


# ------------------------------------------------------------------ cells & fields

func _ck(c: Vector2i) -> int:
	return c.y * _fw + c.x


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _fw and c.y < _fh


static func _v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## Turn a cell into a feature kind: walkable kinds become floor, the others blocked floor.
func _set_kind(c: Vector2i, kind: int) -> void:
	_kind[_ck(c)] = kind
	if kind == K_OPEN or kind == K_DECK:
		grid.set_floor(c, true)
	else:
		grid.set_walkable(c, false)


## Walkable again (islands, decks): no bed, no rock.
func _set_open(c: Vector2i, kind: int = K_OPEN) -> void:
	_set_kind(c, kind)
	var k := _ck(c)
	var col := _fine[k]
	col.b = 0.0
	col.a = 0.0
	_fine[k] = col
	_sx = INF


func _set_bed(c: Vector2i, depth: float) -> void:
	var k := _ck(c)
	var col := _fine[k]
	if depth < col.b:
		col.b = depth
		_fine[k] = col
		_sx = INF


func _set_rock(c: Vector2i, v: float) -> void:
	var k := _ck(c)
	var col := _fine[k]
	if v > col.a:
		col.a = v
		_fine[k] = col
		_sx = INF


## Walkable open ground (not a feature, not blocked by an obstacle) at a point.
func _free(p: Vector2) -> bool:
	var c := _cell_of(p)
	if not _in(c):
		return false
	var k := c.y * _fw + c.x
	return _kind[k] == K_OPEN and grid.walk[k] == 1


## Open land outside the zones (no bed) at p and at four points r metres around it.
func _void_ok(p: Vector2, r: float) -> bool:
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var c := _cell_of(p + o)
		if not _in(c):
			return false
		var k := c.y * _fw + c.x
		if _kind[k] != K_VOID or _fine[k].b < -0.1:
			return false
	return true


func _trail_at(p: Vector2) -> float:
	return _sample(p.x, p.y).g


## Open walkable ground with room around (radius r): off the trails, clear of keep-outs and of
## other decoration (the spacing hash).
func _spot_ok(p: Vector2, r: float) -> bool:
	if not _free(p) or _trail_at(p) > 0.01:
		return false
	var v := _v3(p)
	return _hash_ok(v, r) and is_clear(v, r * 0.6)


## A circle of radius r of open walkable ground of the region, off the trails, clear of keep-outs.
func _room(q: Vector2, r: float, region: String) -> bool:
	if not _free(q) or _trail_at(q) > 0.05 or region_of_cell(_cell_of(q)) != region:
		return false
	for k in 8:
		var a := TAU * k / 8.0
		var s := q + Vector2(cos(a), sin(a)) * r
		if not _free(s) or _trail_at(s) > 0.05:
			return false
	return is_clear(_v3(q), r)


## The nearest spot to p (spiral search) with room for a circle of radius r; Vector2.INF if none.
func _site(p: Vector2, r: float, region: String, reach: float = 16.0) -> Vector2:
	for ring in range(0, int(reach / 2.0) + 1):
		var n := maxi(1, ring * 6)
		for k in n:
			var a := TAU * k / n + ring * 0.7
			var q := p + Vector2(cos(a), sin(a)) * ring * 2.0
			if _room(q, r, region):
				return q
	return Vector2.INF


## The ground height World builds at a point (the relief flattened next to walkable cells).
func _ground_y(p: Vector2) -> float:
	var h := _wilds_height(p.x, p.y)
	if absf(h) < 0.001:
		return 0.0
	var c := _cell_of(p)
	var best := 99.0
	for j in range(c.y - 3, c.y + 4):
		for i in range(c.x - 3, c.x + 4):
			if i < 0 or j < 0 or i >= _fw or j >= _fh:
				continue
			var k := j * _fw + i
			if grid.walk[k] == 1 or (grid.floor_cells[k] == 1 and soft.has(Vector2i(i, j))):
				best = minf(best, Vector2((i + 0.5) * TILE, (j + 0.5) * TILE).distance_to(p))
	return h * smoothstep(1.2, 4.5, best)


func _rand_in(cells: Array) -> Vector2:
	var c: Vector2i = cells[rng.randi() % cells.size()]
	return Vector2((c.x + rng.randf()) * TILE, (c.y + rng.randf()) * TILE)


func _hash_s_ok(p: Vector2, r: float) -> bool:
	var key := Vector2i(floori(p.x / HASH_S), floori(p.y / HASH_S))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for e in _hash_s.get(key + Vector2i(di, dj), []):
				if (e[0] as Vector2).distance_to(p) < float(e[1]) + r:
					return false
	return true


func _hash_s_add(p: Vector2, r: float) -> void:
	var key := Vector2i(floori(p.x / HASH_S), floori(p.y / HASH_S))
	if not _hash_s.has(key):
		_hash_s[key] = []
	(_hash_s[key] as Array).append([p, r])


# ------------------------------------------------------------------ shapes

## A smooth curve through control points (Catmull-Rom, a point every `step` m), its inner points
## pushed sideways by noise (wob m).
func _curve(ctrl: Array, step: float = 3.0, wob: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for k in n - 1:
		var p0: Vector2 = ctrl[maxi(k - 1, 0)]
		var p1: Vector2 = ctrl[k]
		var p2: Vector2 = ctrl[k + 1]
		var p3: Vector2 = ctrl[mini(k + 2, n - 1)]
		var seg := maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for s in seg:
			var t := float(s) / seg
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	if wob > 0.0:
		for k in range(1, out.size() - 1):
			var dir := (out[k + 1] - out[k - 1]).normalized()
			out[k] += Vector2(-dir.y, dir.x) * (noise2(out[k].x * 1.3 + 17.0, out[k].y * 1.3, 0.035, 1) - 0.5) * 2.0 * wob
	return out


## Cells whose centre lies in a noisy ellipse: {Vector2i: e} (0 at the centre, < 1 inside).
func _blob(c: Vector2, r: Vector2, rot: float, wob: float) -> Dictionary:
	var out := {}
	var reach := maxf(r.x, r.y) * (1.0 + wob) + TILE
	var cs := cos(rot)
	var sn := sin(rot)
	for j in range(maxi(floori((c.y - reach) / TILE), 0), mini(floori((c.y + reach) / TILE), _fh - 1) + 1):
		for i in range(maxi(floori((c.x - reach) / TILE), 0), mini(floori((c.x + reach) / TILE), _fw - 1) + 1):
			var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE)
			var d := p - c
			var e := (Vector2(d.x * cs + d.y * sn, -d.x * sn + d.y * cs) / r).length()
			e += (noise2(p.x + 91.0, p.y - 37.0, 0.08, 2) - 0.5) * wob * 2.0
			if e < 1.0:
				out[Vector2i(i, j)] = maxf(e, 0.0)
	return out


## Cells whose centre lies within a band along a polyline, its width varying w0..w1 with noise:
## {Vector2i: e} (0 on the line .. 1 at the band's edge).
func _band(pts: PackedVector2Array, w0: float, w1: float) -> Dictionary:
	var out := {}
	var reach := maxf(w0, w1) * 0.5 + TILE
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.0001)
		for j in range(maxi(floori((minf(a.y, b.y) - reach) / TILE), 0), mini(floori((maxf(a.y, b.y) + reach) / TILE), _fh - 1) + 1):
			for i in range(maxi(floori((minf(a.x, b.x) - reach) / TILE), 0), mini(floori((maxf(a.x, b.x) + reach) / TILE), _fw - 1) + 1):
				var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var q := a + ab * t
				var half := lerpf(w0, w1, noise2(q.x + 7.0, q.y - 3.0, 0.05, 1)) * 0.5
				var e := p.distance_to(q) / half
				var cell := Vector2i(i, j)
				if e < 1.0 and e < float(out.get(cell, 2.0)):
					out[cell] = e
	return out


# ------------------------------------------------------------------ trails & terrain features

## A trail through control points: stamped into the ground field (g) and remembered (_lines).
func _path(ctrl: Array, width: float, wob: float = 2.5) -> PackedVector2Array:
	var pts := _curve(ctrl, 3.0, wob)
	_lines.append([pts, width])
	var reach := width * 0.5 + 1.4
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.0001)
		for j in range(maxi(floori((minf(a.y, b.y) - reach) / TILE), 0), mini(floori((maxf(a.y, b.y) + reach) / TILE), _fh - 1) + 1):
			for i in range(maxi(floori((minf(a.x, b.x) - reach) / TILE), 0), mini(floori((maxf(a.x, b.x) + reach) / TILE), _fw - 1) + 1):
				var p := Vector2((i + 0.5) * TILE, (j + 0.5) * TILE)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var q := a + ab * t
				var half := width * 0.5 * (0.82 + 0.36 * noise2(q.x, q.y, 0.09, 1))
				var val := 1.0 - smoothstep(half - 0.9, half + 1.4, p.distance_to(q))
				if val <= 0.0:
					continue
				var kk := j * _fw + i
				var col := _fine[kk]
				if val > col.g:
					col.g = val
					_fine[kk] = col
	_sx = INF
	return pts


## A stream bed along a polyline: water cells (blocked, the bed below the water) in `region`, the
## bed alone on the open land outside the zones; water planes along it. Returns the water cells.
func _water_band(pts: PackedVector2Array, w0: float, w1: float, depth: float, region: String) -> Dictionary:
	var cells := _band(pts, w0, w1)
	var out := {}
	for cell in cells:
		var c: Vector2i = cell
		var e: float = cells[cell]
		var rid := region_of_cell(c)
		var bed := -depth * (0.75 + 0.25 * (1.0 - e * e))
		if rid == region and _kind[_ck(c)] == K_OPEN:
			_set_kind(c, K_WATER)
			_set_bed(c, bed)
			out[c] = e
		elif rid == "" and _kind[_ck(c)] == K_VOID:
			_set_bed(c, bed)
	var k0 := 0
	while k0 < pts.size() - 1:
		var k1 := mini(k0 + 14, pts.size() - 1)
		var r := Rect2(pts[k0], Vector2.ZERO)
		for k in range(k0, k1 + 1):
			r = r.expand(pts[k])
		water_rects.append(r.grow(maxf(w0, w1) * 0.5 + 5.0))
		k0 = k1
	return out


## A lake: water cells of `region` inside a noisy ellipse, the bed deepening towards the middle.
func _lake(c: Vector2, r: Vector2, rot: float, wob: float, depth: float, region: String) -> Dictionary:
	var cells := _blob(c, r, rot, wob)
	var out := {}
	for cell in cells:
		var cc: Vector2i = cell
		if region_of_cell(cc) != region or _kind[_ck(cc)] != K_OPEN:
			continue
		var e: float = cells[cell]
		_set_kind(cc, K_WATER)
		_set_bed(cc, -(1.9 + depth * smoothstep(0.95, 0.3, e)))
		out[cc] = e
	var m := maxf(r.x, r.y) * (1.0 + wob) + 6.0
	water_rects.append(Rect2(c - Vector2(m, m), Vector2(m, m) * 2.0))
	return out


func _island(c: Vector2, r: Vector2, wob: float, region: String) -> Array:
	var cells := _blob(c, r, 0.0, wob)
	var out: Array = []
	for cell in cells:
		var cc: Vector2i = cell
		if region_of_cell(cc) == region and _kind[_ck(cc)] == K_WATER:
			_set_open(cc)
			out.append(cc)
	return out


## A stone causeway across the water along a polyline (walkable).
func _causeway(pts: PackedVector2Array, width: float, region: String) -> Array:
	var cells := _band(pts, width, width)
	var out: Array = []
	for cell in cells:
		var cc: Vector2i = cell
		if region_of_cell(cc) == region and _kind[_ck(cc)] == K_WATER:
			_set_open(cc, K_DECK)
			out.append(cc)
	return out


## Log bridges where the trails cross a stream: a walkable deck along the trail across the water
## and the bridge model over it.
func _bridges(water: Dictionary, region: String) -> void:
	for line in _lines:
		var pts: PackedVector2Array = line[0]
		var k := 0
		while k < pts.size():
			if not water.has(_cell_of(pts[k])):
				k += 1
				continue
			var k0 := k
			while k < pts.size() and water.has(_cell_of(pts[k])):
				k += 1
			var a := pts[maxi(k0 - 1, 0)]
			var b := pts[mini(k, pts.size() - 1)]
			if a.distance_to(b) > 22.0:
				continue
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			var cells := _band(PackedVector2Array([mid - dir * 7.0, mid + dir * 7.0]), 4.4, 4.4)
			for cell in cells:
				var cc: Vector2i = cell
				if region_of_cell(cc) == region and _kind[_ck(cc)] == K_WATER:
					_set_open(cc, K_DECK)
			add_prop("forest_log_bridge", _v3(mid), atan2(dir.x, dir.y), 1.0, {"cutout": false, "vary": 0.06})
			_hash_add(_v3(mid), 6.5)
			keep(_v3(mid), 5.5)


## Hell's Gap: chasm cells (blocked, deep, rock) of `region`; beyond the zone its dark bed goes on.
func _gorge(pts: PackedVector2Array, w0: float, w1: float, region: String) -> Dictionary:
	var cells := _band(pts, w0, w1)
	var out := {}
	for cell in cells:
		var cc: Vector2i = cell
		var e: float = cells[cell]
		var rid := region_of_cell(cc)
		if rid == region:
			if _kind[_ck(cc)] != K_OPEN and _kind[_ck(cc)] != K_GORGE:
				continue
			_set_kind(cc, K_GORGE)
		elif rid != "" or _kind[_ck(cc)] != K_VOID:
			continue
		_set_bed(cc, -(7.0 + 5.0 * (1.0 - e * e)))
		_set_rock(cc, 1.0)
		out[cc] = e
	return out


## A granite outcrop (blocked, rock relief) of `region`, off the trails. Returns its cells.
func _outcrop(c: Vector2, r: Vector2, rot: float, region: String) -> Array:
	var cells := _blob(c, r, rot, 0.25)
	var out: Array = []
	for cell in cells:
		var cc: Vector2i = cell
		var k := _ck(cc)
		if region_of_cell(cc) != region or _kind[k] != K_OPEN or _fine[k].g > 0.03 or grid.walk[k] == 0:
			continue
		_set_kind(cc, K_ROCK)
		_set_rock(cc, 1.0 if float(cells[cell]) < 0.8 else 0.7)
		out.append(cc)
	return out


## A grove on the open ground of `region`: a blob of blocked ground filled with a stand of trees,
## a few single trees and undergrowth. False if there is no room.
func _grove(region: String, c: Vector2, r: float, stands: Dictionary, singles: Dictionary, cover: Dictionary) -> bool:
	if not is_clear(_v3(c), r + 1.0) or not _hash_ok(_v3(c), r) or not _free(c):
		return false
	var cells := _blob(c, Vector2(r, r * rng.randf_range(0.7, 1.0)), rng.randf() * TAU, 0.3)
	var use: Array = []
	for cell in cells:
		var cc: Vector2i = cell
		var k := _ck(cc)
		if _kind[k] != K_OPEN or grid.walk[k] == 0 or _fine[k].g > 0.02 or region_of_cell(cc) != region:
			continue
		use.append(cc)
	if use.size() < 8:
		return false
	# soft blocked cells (no merged boxes, flat ground) and one or two cylinders for collision
	for cc in use:
		_kind[_ck(cc)] = K_GROVE
		block_cell(cc, false, true)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cc in use:
		lo = lo.min(Vector2(cc) * TILE)
		hi = hi.max((Vector2(cc) + Vector2.ONE) * TILE)
	var ext := hi - lo
	var mid := (lo + hi) * 0.5
	if ext.x > ext.y * 1.35 or ext.y > ext.x * 1.35:
		var ax := Vector2(1, 0) if ext.x > ext.y else Vector2(0, 1)
		var rr := minf(ext.x, ext.y) * 0.42
		var off := (maxf(ext.x, ext.y) * 0.5 - rr) * 0.8
		for s2 in [-1.0, 1.0]:
			shapes.append({"type": "cylinder", "pos": _v3(mid + ax * off * s2), "radius": rr, "height": 3.0})
	else:
		shapes.append({"type": "cylinder", "pos": _v3(mid), "radius": minf(ext.x, ext.y) * 0.42, "height": 3.0})
	if not stands.is_empty():
		var sid := pick(stands)
		add_prop(sid, _v3(c), rng.randf() * TAU, rng.randf_range(0.8, 1.05), {"cutout": true, "sway": 0.28, "sway_base": _sway_base(sid), "vary": 0.1})
	var n := int(use.size() / 7.0)
	for t in n:
		var cc: Vector2i = use[rng.randi() % use.size()]
		var p := Vector2((cc.x + rng.randf()) * TILE, (cc.y + rng.randf()) * TILE)
		if p.distance_to(c) < 3.5 and not stands.is_empty():
			continue
		if rng.randf() < 0.55 and not singles.is_empty():
			var tid := pick(singles)
			add_prop(tid, _v3(p, -0.05), rng.randf() * TAU, rng.randf_range(0.8, 1.15), {"cutout": true, "sway": _sway(tid), "sway_base": _sway_base(tid), "vary": 0.12})
		elif not cover.is_empty():
			add_prop(pick(cover), _v3(p), rng.randf() * TAU, rng.randf_range(0.8, 1.3), {"shadows": false, "vary": 0.14})
	_hash_add(_v3(c), r)
	return true


# ------------------------------------------------------------------ placing things

## A tree on walkable ground (collision, blocks its cell).
func _tree(p: Vector2, id: String, sc: float) -> void:
	add_obstacle(id, _v3(p, -0.05), rng.randf() * TAU, sc, 0.42 * sc, {"cutout": true, "sway": _sway(id), "sway_base": _sway_base(id), "vary": 0.12})


## Radius (m) of a rock-like obstacle at scale 1.
func _solid_r(id: String) -> float:
	match id:
		"forest_boulder_a":
			return 1.45
		"forest_boulder_b":
			return 1.75
		"forest_rock_slab":
			return 2.4
		"forest_stump":
			return 0.5
		"forest_snag":
			return 0.4
		"forest_juniper":
			return 0.45
		"forest_standing_stone":
			return 0.7
		"forest_runestone_old":
			return 0.75
		"forest_cairn":
			return 1.15
	return 0.5


func _solid(p: Vector2, id: String, sc: float, yaw: float = -1.0) -> void:
	var r := _solid_r(id) * sc
	var o := {"cutout": true, "vary": 0.1}
	if id == "forest_snag":
		o["sway"] = _sway(id)
		o["sway_base"] = _sway_base(id)
	add_obstacle(id, _v3(p), rng.randf() * TAU if yaw < 0.0 else yaw, sc, r, o)
	_hash_add(_v3(p), r + 0.6)


func _log(p: Vector2) -> void:
	add_block("forest_log", _v3(p), rng.randf() * TAU, Vector2(5.4, 0.9), {"cutout": false, "height": 1.0})
	_hash_add(_v3(p), 3.0)


## A stand of trees (forest_stand_*) on walkable ground: one collision cylinder round its trunks.
func _stand(p: Vector2, id: String, sc: float) -> void:
	var r := 3.1 * sc
	add_prop(id, _v3(p, -0.05), rng.randf() * TAU, sc, {"cutout": true, "sway": 0.28, "sway_base": _sway_base(id), "vary": 0.1})
	shapes.append({"type": "cylinder", "pos": _v3(p), "radius": r, "height": 3.0})
	for c in cells_in_disc(_v3(p), r + 0.2):
		if grid.is_walkable_cell(c):
			block_cell(c, false, true)
	keep(_v3(p), r + 0.4)


## Two or three trees close together on walkable ground (one collision cylinder).
func _clump_trees(p: Vector2, ids: Dictionary, sc: Vector2) -> void:
	var n := rng.randi_range(2, 3)
	var a0 := rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * k / n + rng.randf_range(-0.3, 0.3)
		var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(0.9, 1.7)
		var tid := pick(ids)
		add_prop(tid, _v3(q, -0.05), rng.randf() * TAU, rng.randf_range(sc.x, sc.y), {"cutout": true, "sway": _sway(tid), "sway_base": _sway_base(tid), "vary": 0.12})
	shapes.append({"type": "cylinder", "pos": _v3(p), "radius": 2.1, "height": 3.0})
	for c in cells_in_disc(_v3(p), 2.3):
		if grid.is_walkable_cell(c):
			block_cell(c, false, true)
	keep(_v3(p), 2.4)


## Trees over a region's open ground, denser where its density noise is high: stands (4-5 trees),
## clumps (2-3) and single trees, one collision cylinder each. spec: "stands" {id: w}, "n_stands",
## "trees" {id: w}, "n_clumps", "n_singles", "spacing" (m, singles), "scale" Vector2, "filter"
## Callable(Vector2) -> bool, "dens" (noise threshold).
func _woods(region: String, spec: Dictionary) -> void:
	var cells := region_cells(region)
	var filt: Callable = spec.get("filter", Callable())
	var dens := float(spec.get("dens", 0.3))
	var sc: Vector2 = spec.get("scale", Vector2(0.85, 1.2))
	var stands: Dictionary = spec.get("stands", {})
	var trees: Dictionary = spec.get("trees", {})
	var keys := ["n_stands", "n_clumps", "n_singles"]
	var radii := [5.2, 3.6, float(spec.get("spacing", 8.0)) * 0.5]
	for kind in 3:
		var want := int(spec.get(keys[kind], 0))
		if want <= 0 or (kind == 0 and stands.is_empty()) or (kind > 0 and trees.is_empty()):
			continue
		var r: float = radii[kind]
		var placed := 0
		for t in want * 14:
			if placed >= want:
				break
			var p := _rand_in(cells)
			if rng.randf() > smoothstep(dens, dens + 0.35, noise2(p.x + 300.0, p.y - 120.0, 0.017, 2)):
				continue
			if filt.is_valid() and not bool(filt.call(p)):
				continue
			if not _spot_ok(p, r):
				continue
			if kind == 0:
				if not _room(p, 3.4, region):
					continue
				_stand(p, pick(stands), rng.randf_range(0.85, 1.1))
			elif kind == 1:
				if not _room(p, 2.4, region):
					continue
				_clump_trees(p, trees, sc)
			else:
				_tree(p, pick(trees), rng.randf_range(sc.x, sc.y))
			_hash_add(_v3(p), r)
			placed += 1


## Rock-like obstacles (boulders, stumps, junipers, stones...) over a region's open ground.
func _scatter_solids(region: String, count: int, ids: Dictionary, sc: Vector2, filt: Callable = Callable(), gap: float = 1.2) -> int:
	var cells := region_cells(region)
	var placed := 0
	for t in count * 14:
		if placed >= count:
			break
		var p := _rand_in(cells)
		if filt.is_valid() and not bool(filt.call(p)):
			continue
		var id := pick(ids)
		var s := rng.randf_range(sc.x, sc.y)
		if not _spot_ok(p, _solid_r(id) * s + gap):
			continue
		_solid(p, id, s)
		placed += 1
	return placed


## Ground cover (no collision) on a region's open ground, clustered by noise. opts: "freq",
## "lo" (noise threshold), "seed", "filter" Callable(Vector2) -> bool, "trail" (allow on trails),
## "gap" (spacing, m).
func _cover(region: String, count: int, ids: Variant, sc: Vector2, opts: Dictionary = {}) -> int:
	var cells := region_cells(region)
	var freq := float(opts.get("freq", 0.06))
	var lo := float(opts.get("lo", 0.45))
	var off := float(opts.get("seed", 0.0))
	var gap := float(opts.get("gap", 0.7))
	var on_trail := bool(opts.get("trail", false))
	var filt: Callable = opts.get("filter", Callable())
	var placed := 0
	for t in count * 10:
		if placed >= count:
			break
		var p := _rand_in(cells)
		if lo > 0.0 and rng.randf() > smoothstep(lo, lo + 0.25, noise2(p.x + off, p.y - off, freq, 2)):
			continue
		var c := _cell_of(p)
		var k := _ck(c)
		if (_kind[k] != K_OPEN and _kind[k] != K_GROVE) or (grid.walk[k] == 0 and _kind[k] == K_OPEN):
			continue
		if not on_trail and _fine[k].g > 0.15:
			continue
		if filt.is_valid() and not bool(filt.call(p)):
			continue
		if not _hash_s_ok(p, gap) or not is_clear(_v3(p), 0.3):
			continue
		_hash_s_add(p, gap)
		add_prop(pick(ids), _v3(p), rng.randf() * TAU, rng.randf_range(sc.x, sc.y), {"shadows": false, "vary": 0.14})
		placed += 1
	return placed


func _shaft(p: Vector2) -> void:
	add_shaft(_v3(p), rng.randf_range(14.0, 18.0), rng.randf_range(2.6, 3.6), Color(1.0, 0.94, 0.72), SUN_YAW, SUN_TILT)


## A chest / shrine at the nearest free spot to p in `region` (skipped if there is none).
func _chest_at(p: Vector2, region: String, tier: int) -> void:
	var q := _site(p, 1.6, region)
	if q.x < INF:
		add_chest(_v3(q), rng.randf_range(-0.6, 0.6), tier)
		_hash_add(_v3(q), 1.4)


func _shrine_at(p: Vector2, region: String) -> void:
	var q := _site(p, 2.0, region)
	if q.x < INF:
		add_shrine(_v3(q), rng.randf() * TAU)
		_hash_add(_v3(q), 1.8)


## Reeds along the shore cells of a water body, lily pads and stones out on the water.
func _shore(water: Dictionary, reeds: float, lilies: int, stones: int) -> void:
	var list: Array = water.keys()
	for cell in list:
		var c: Vector2i = cell
		if _kind[_ck(c)] != K_WATER:
			continue
		var shore := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nk := _ck(c + d)
			if _kind[nk] == K_OPEN or _kind[nk] == K_DECK:
				shore = true
				break
		if not shore or rng.randf() > reeds:
			continue
		var p := Vector2((c.x + rng.randf()) * TILE, (c.y + rng.randf()) * TILE)
		add_prop("forest_reeds", _v3(p, maxf(_ground_y(p), WATER_Y - 0.25) - 0.05), rng.randf() * TAU, rng.randf_range(0.8, 1.25), {"shadows": false, "vary": 0.12})
	var n := 0
	for t in lilies * 12:
		if n >= lilies or list.is_empty():
			break
		var c2: Vector2i = list[rng.randi() % list.size()]
		if float(water[c2]) > 0.75 or _kind[_ck(c2)] != K_WATER:
			continue
		var p2 := Vector2((c2.x + rng.randf()) * TILE, (c2.y + rng.randf()) * TILE)
		if not _hash_s_ok(p2, 3.0):
			continue
		_hash_s_add(p2, 3.0)
		add_prop("forest_lilypads", _v3(p2, WATER_Y + 0.02), rng.randf() * TAU, rng.randf_range(0.8, 1.3), {"shadows": false, "vary": 0.1})
		n += 1
	n = 0
	for t in stones * 12:
		if n >= stones or list.is_empty():
			break
		var c3: Vector2i = list[rng.randi() % list.size()]
		var e3 := float(water[c3])
		if e3 < 0.55 or e3 > 0.9 or _kind[_ck(c3)] != K_WATER:
			continue
		var p3 := Vector2((c3.x + rng.randf()) * TILE, (c3.y + rng.randf()) * TILE)
		if not _hash_s_ok(p3, 2.5):
			continue
		_hash_s_add(p3, 2.5)
		add_prop("forest_boulder_a", _v3(p3, WATER_Y - 0.55), rng.randf() * TAU, rng.randf_range(0.5, 0.75), {"cutout": true, "vary": 0.1})
		n += 1


# ------------------------------------------------------------------ routes, arrivals, gateways

## The trails: from Birkavik north through the Mattis Woods to Hell's Gap, east to Stillwater Tarn,
## north-east to the Hollows, west from the Gap to the Barrow Downs; loops round the western woods
## and the tarn, across the tarn on its causeways, and into the deep Hollows.
func _routes() -> void:
	_route["main"] = _path([Vector2(397, 531), Vector2(400, 500), Vector2(390, 468), Vector2(383, 432), Vector2(393, 398),
		Vector2(403, 362), Vector2(395, 326), Vector2(388, 292), Vector2(396, 262), Vector2(397, 234), Vector2(396, 200),
		Vector2(396, 170), Vector2(399, 150), Vector2(405, 130), Vector2(410, 104)], 4.8)
	_route["tarn"] = _path([Vector2(393, 398), Vector2(430, 410), Vector2(470, 404), Vector2(510, 393), Vector2(550, 399),
		Vector2(585, 398), Vector2(612, 398), Vector2(636, 396), Vector2(652, 382), Vector2(672, 362), Vector2(698, 352),
		Vector2(716, 336), Vector2(720, 314), Vector2(720, 292), Vector2(720, 276), Vector2(721, 258), Vector2(716, 240),
		Vector2(706, 226)], 4.2)
	_route["hollows"] = _path([Vector2(395, 326), Vector2(428, 314), Vector2(466, 296), Vector2(502, 272), Vector2(538, 252),
		Vector2(566, 236), Vector2(586, 224), Vector2(612, 220), Vector2(640, 222), Vector2(664, 222), Vector2(686, 226),
		Vector2(706, 226)], 4.0)
	_route["downs"] = _path([Vector2(399, 150), Vector2(372, 138), Vector2(340, 132), Vector2(305, 122), Vector2(272, 110),
		Vector2(246, 104), Vector2(232, 104), Vector2(212, 106), Vector2(190, 114), Vector2(165, 128), Vector2(145, 150),
		Vector2(128, 176), Vector2(120, 196), Vector2(117, 205)], 4.2)
	_route["loop"] = _path([Vector2(390, 468), Vector2(352, 470), Vector2(318, 452), Vector2(294, 418), Vector2(284, 382),
		Vector2(292, 350), Vector2(305, 318), Vector2(332, 296), Vector2(362, 290), Vector2(388, 292)], 3.4)
	_route["shore"] = _path([Vector2(652, 382), Vector2(646, 420), Vector2(648, 452), Vector2(660, 488), Vector2(690, 510),
		Vector2(735, 514), Vector2(768, 488), Vector2(785, 452), Vector2(790, 415), Vector2(784, 380), Vector2(760, 356),
		Vector2(735, 348), Vector2(716, 336)], 3.4)
	_route["causeway"] = _path([Vector2(646, 422), Vector2(668, 424), Vector2(700, 420), Vector2(725, 437), Vector2(748, 455),
		Vector2(768, 458), Vector2(786, 452)], 3.6, 0.0)
	_route["deep"] = _path([Vector2(706, 226), Vector2(716, 204), Vector2(724, 180), Vector2(728, 158), Vector2(736, 130),
		Vector2(752, 112)], 3.4)
	# The stone ship and the king's mound on the downs.
	_route["mounds"] = _path([Vector2(165, 128), Vector2(140, 116), Vector2(118, 112), Vector2(106, 126)], 3.0)


## Where the player arrives in each zone: on its trail, a little inside from the way in.
func _arrivals() -> void:
	for a in [["tarn", Vector2(640, 394)], ["hollows", Vector2(618, 220)], ["gap", Vector2(399, 146)], ["downs", Vector2(206, 108)]]:
		var rid: String = a[0]
		var p: Vector2 = a[1]
		var c := _cell_of(p)
		if region_of_cell(c) == rid and grid.is_walkable_cell(c):
			set_region_arrival(rid, _v3(p))
			keep(_v3(p), 3.0)


## The trail's direction nearest to p.
func _trail_dir(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(0, -1)
	for line in _lines:
		var pts: PackedVector2Array = line[0]
		for k in pts.size() - 1:
			var d := pts[k].distance_squared_to(p)
			if d < best:
				best = d
				dir = (pts[k + 1] - pts[k]).normalized()
	return dir


## Landmarks where the trails cross from one zone into the next: a wooden gate in a roundpole
## fence (to the tarn), old rune stones (to Hell's Gap), standing stones and a cairn (to the
## downs), cairns (the hollows).
func _gateways() -> void:
	for l in layout_data.get("links", []):
		var pair := "%s|%s" % [String(l["a"]), String(l["b"])]
		var at_: Array = l["at"]
		var pos := Vector2((float(at_[0]) + 0.5) * TILE, (float(at_[1]) + 0.5) * TILE)
		var width := float(l.get("width_cells", 6)) * TILE
		var dir := _trail_dir(pos)
		var side := Vector2(-dir.y, dir.x)
		match pair:
			"outskirts|tarn":
				_gate_fence(pos, dir)
			"outskirts|gap":
				_stone_pair(pos, side, "forest_runestone_old", 5.2, 1.05)
				_solid(pos + side * 9.0 + dir * 3.0, "forest_cairn", 0.8)
			"gap|downs":
				_stone_pair(pos, side, "forest_standing_stone", 5.4, 1.0)
				_solid(pos - side * 9.5 - dir * 2.0, "forest_cairn", 0.9)
			_:
				_stone_pair(pos, side, "forest_cairn", 5.0, 0.95)
		keep(_v3(pos), width * 0.42)


func _stone_pair(pos: Vector2, side: Vector2, id: String, off: float, sc: float) -> void:
	for s in [-1.0, 1.0]:
		var p: Vector2 = pos + side * off * s
		# face the trail
		_solid(p, id, sc * rng.randf_range(0.95, 1.08), atan2(-side.x * s, -side.y * s))


## A wooden gate over the trail with roundpole fences from its posts out to the path's sides.
func _gate_fence(pos: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	add_prop("forest_gate", _v3(pos), atan2(dir.x, dir.y), 1.0, {"cutout": true, "vary": 0.05})
	for s in [-1.0, 1.0]:
		var post: Vector2 = pos + side * 2.5 * s
		shapes.append({"type": "cylinder", "pos": _v3(post), "radius": 0.4, "height": 4.0})
		block_cell(_cell_of(post), false, true)
		# fence runs out to the edge of the path
		for k in 12:
			var mid: Vector2 = pos + side * s * (3.6 + k * 2.0)
			var c := _cell_of(mid)
			if not _in(c) or grid.floor_cells[_ck(c)] == 0:
				break
			add_block(pick({"forest_gardsgard_a": 4.0, "forest_gardsgard_b": 1.0}), _v3(mid), atan2(-side.y, side.x), Vector2(2.0, 0.45),
				{"cutout": false, "height": 1.3})
	keep(_v3(pos), 3.2)
	keep(_v3(pos + dir * 4.0), 2.0)
	keep(_v3(pos - dir * 4.0), 2.0)


# ------------------------------------------------------------------ The Mattis Woods (outskirts)

func _paint_outskirts() -> void:
	var id := "outskirts"
	# The brook: from a waterfall at the west edge east through the woods to a forest pond.
	var brook := _curve([Vector2(222, 342), Vector2(246, 346), Vector2(264, 349), Vector2(290, 356), Vector2(318, 350),
		Vector2(345, 338), Vector2(372, 340), Vector2(402, 350), Vector2(428, 362), Vector2(455, 356), Vector2(480, 344),
		Vector2(505, 336), Vector2(532, 336)], 3.0, 2.5)
	_brook = _water_band(brook, 8.5, 11.0, 2.3, id)
	var pond := _lake(Vector2(548, 336), Vector2(16, 12), 0.2, 0.2, 1.0, id)
	for c in pond:
		_brook[c] = pond[c]
	_bridges(_brook, id)
	add_prop("forest_waterfall", Vector3(240, WATER_Y - 0.05, 345.5), PI * 0.5, 1.3, {"cutout": false})
	_hash_add(Vector3(240, 0, 345.5), 6.0)
	_shore(_brook, 0.3, 6, 3)
	# Sunlit clearings (no trees; anemones and grass).
	var clearings: Array = [Vector2(330, 456), Vector2(456, 470), Vector2(524, 440), Vector2(318, 302), Vector2(458, 262),
		Vector2(352, 392), Vector2(566, 302), Vector2(430, 222)]
	for c in clearings:
		var cp: Vector2 = c
		keep(_v3(cp), 10.0)
		_shaft(cp + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	# The woodcutters' camp near the road from Birkavik.
	var camp := _site(Vector2(438, 484), 7.0, id)
	if camp.x < INF:
		add_obstacle("forest_firepit", _v3(camp), 0.0, 1.0, 0.95, {"cutout": false})
		add_light(_v3(camp, 1.4), Color(1.0, 0.6, 0.28), 2.2, 9.0, true)
		add_glow(_v3(camp), 3.0, Color(1.0, 0.55, 0.22))
		add_building("forest_hut", _v3(camp + Vector2(6.5, -4.5)), 0.5, Vector2(3.2, 2.6))
		add_block("forest_woodpile", _v3(camp + Vector2(-5.0, -3.5)), 0.3, Vector2(2.4, 1.0), {"cutout": false, "height": 1.4})
		add_block("forest_woodpile", _v3(camp + Vector2(1.0, -6.5)), -0.15, Vector2(2.4, 1.0), {"cutout": false, "height": 1.4})
		add_block("forest_log", _v3(camp + Vector2(-2.5, 3.2)), 0.2, Vector2(5.4, 0.9), {"cutout": false, "height": 1.0})
		for k in 6:
			var a := TAU * k / 6.0 + 0.4
			var sp := camp + Vector2(cos(a), sin(a)) * rng.randf_range(9.0, 12.0)
			if _free(sp):
				add_prop("forest_stump", _v3(sp), rng.randf() * TAU, rng.randf_range(0.85, 1.1), {"shadows": false, "vary": 0.14})
		keep(_v3(camp), 9.0)
		_hash_add(_v3(camp), 9.0)
		_chest_at(camp + Vector2(3.5, 3.0), id, 0)
	# The troll stones: huge mossy boulders in a ring.
	var troll := _site(Vector2(496, 452), 8.0, id)
	if troll.x < INF:
		for k in 4:
			var a := TAU * k / 4.0 + rng.randf_range(-0.3, 0.3)
			var tp := troll + Vector2(cos(a), sin(a)) * rng.randf_range(4.5, 6.0)
			_solid(tp, "forest_boulder_a" if k % 2 == 0 else "forest_rock_slab", rng.randf_range(1.2, 1.6))
		_solid(troll, "forest_boulder_b", 1.7)
		keep(_v3(troll), 8.0)
	_chest_at(Vector2(268, 334), id, 1)
	_chest_at(Vector2(458, 256), id, 0)
	_shrine_at(Vector2(330, 448), id)
	_shrine_at(Vector2(318, 296), id)
	# Groves, stands of trees, clumps and single trees with room to walk between them: red-barked
	# pines, spruce in the north-west, birch in the south-east.
	var cells := region_cells(id)
	var nw := func(p: Vector2) -> bool: return p.x < 400.0 and p.y < 400.0
	var se := func(p: Vector2) -> bool: return p.x > 440.0 and p.y > 380.0
	var groves := 0
	for t in 300:
		if groves >= 24:
			break
		var gp := _rand_in(cells)
		var north := bool(nw.call(gp))
		if _grove(id, gp, rng.randf_range(6.0, 10.0), {"forest_stand_a": 3.0, "forest_stand_b": 2.0 if north else 1.0},
				{"forest_pine_a": 2.0, "forest_spruce": 2.0 if north else 0.7, "forest_birch": 1.0}, {"forest_patch_scrub": 2.0, "forest_patch_fern": 1.0}):
			groves += 1
	_woods(id, {"stands": {"forest_stand_a": 3.0, "forest_stand_b": 1.2}, "n_stands": 85,
		"trees": {"forest_pine_a": 5.0, "forest_pine_b": 3.0, "forest_spruce": 1.0, "forest_birch": 1.0}, "n_clumps": 62, "n_singles": 84})
	_woods(id, {"stands": {"forest_stand_c": 1.0, "forest_stand_b": 1.0}, "n_stands": 16, "trees": {"forest_spruce": 3.0, "forest_pine_b": 1.0},
		"n_clumps": 12, "n_singles": 16, "filter": nw})
	_woods(id, {"stands": {"forest_stand_b": 1.0}, "n_stands": 8, "trees": {"forest_birch": 4.0, "forest_pine_b": 1.0},
		"n_clumps": 18, "n_singles": 18, "filter": se, "dens": 0.2})
	# Mossy boulders, stumps and fallen logs.
	_scatter_solids(id, 40, {"forest_boulder_a": 2.0, "forest_boulder_b": 1.5}, Vector2(0.7, 1.25))
	_cover(id, 30, {"forest_stump": 1.0}, Vector2(0.8, 1.15), {"lo": 0.0, "gap": 3.0})
	var logs := 0
	for t in 200:
		if logs >= 18:
			break
		var lp := _rand_in(cells)
		if _spot_ok(lp, 3.2):
			_log(lp)
			logs += 1
	# Ground cover: blueberry and lingonberry scrub, moss, bracken by the brook and in the
	# north-west, anemone meadows in the clearings, fly agarics.
	var in_clearing := func(p: Vector2) -> bool:
		for c in clearings:
			if p.distance_to(c) < 11.0:
				return true
		return false
	var ferny := func(p: Vector2) -> bool: return absf(p.y - 346.0) < 24.0 or (p.x < 340.0 and p.y < 420.0)
	_cover(id, 430, {"forest_patch_scrub": 1.0}, Vector2(0.85, 1.25), {"freq": 0.045, "lo": 0.33, "seed": 11.0, "gap": 2.3})
	_cover(id, 140, {"forest_patch_moss": 1.0}, Vector2(0.85, 1.2), {"freq": 0.06, "lo": 0.45, "seed": 57.0, "gap": 2.3})
	_cover(id, 80, {"forest_patch_fern": 1.0}, Vector2(0.85, 1.2), {"lo": 0.0, "gap": 2.5, "filter": ferny})
	_cover(id, 45, {"forest_patch_meadow": 1.0}, Vector2(0.9, 1.2), {"lo": 0.0, "gap": 2.5, "filter": in_clearing})
	_cover(id, 30, {"forest_flowers": 1.0}, Vector2(0.8, 1.2), {"lo": 0.0, "gap": 1.4, "filter": in_clearing})
	_cover(id, 110, {"forest_shrub": 3.0, "forest_grass": 2.0, "forest_fern": 1.0}, Vector2(0.8, 1.3), {"freq": 0.08, "lo": 0.45, "seed": 37.0})
	_cover(id, 30, {"forest_mushrooms": 1.0}, Vector2(0.8, 1.2), {"freq": 0.11, "lo": 0.55, "seed": 71.0})
	for k in 8:
		var sp: Vector2 = _route["main"][rng.randi_range(8, maxi(9, (_route["main"] as PackedVector2Array).size() - 30))]
		_shaft(sp + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)))


# ------------------------------------------------------------------ Stillwater Tarn

func _paint_tarn() -> void:
	var id := "tarn"
	_lake_cells = _lake(Vector2(722, 432), Vector2(52, 58), 0.3, 0.12, 1.6, id)
	_island(Vector2(700, 420), Vector2(11, 9), 0.25, id)
	_island(Vector2(748, 455), Vector2(9, 8), 0.25, id)
	var deck := _causeway(_route["causeway"], 5.6, id)
	for cell in deck:
		_lake_cells.erase(cell)
	for cell in _lake_cells.keys():
		if _kind[_ck(cell)] != K_WATER:
			_lake_cells.erase(cell)
	# Stones lining the causeways.
	var cw: PackedVector2Array = _route["causeway"]
	for k in range(1, cw.size() - 1):
		var dir := (cw[k + 1] - cw[k - 1]).normalized()
		for s in [-1.0, 1.0]:
			if rng.randf() < 0.45:
				var sp: Vector2 = cw[k] + Vector2(-dir.y, dir.x) * s * rng.randf_range(3.4, 4.2)
				if _kind[_ck(_cell_of(sp))] == K_WATER:
					add_prop("forest_boulder_b", _v3(sp, _ground_y(sp) - 0.15), rng.randf() * TAU, rng.randf_range(0.35, 0.5), {"cutout": true, "vary": 0.1})
	_shore(_lake_cells, 0.42, 26, 7)
	# The broken jetty on the north shore, a fisher's hut with a boat pulled up.
	var jx := 734.0
	var jz := 380.0
	for z in range(340, 400, 2):
		if _kind[_ck(_cell_of(Vector2(jx, z)))] == K_WATER:
			jz = z - 1.5
			break
	add_prop("forest_jetty_old", Vector3(jx, -0.05, jz), 0.0, 1.0, {"shadows": true})
	keep(Vector3(jx, 0, jz - 4.0), 8.0)
	var hut := _site(Vector2(752, 364), 4.5, id)
	if hut.x < INF:
		add_building("forest_hut", _v3(hut), rng.randf_range(-0.4, 0.4), Vector2(3.2, 2.6))
		add_block("forest_rack", _v3(hut + Vector2(-5.0, 2.5)), 0.3, Vector2(3.4, 1.2), {"cutout": false})
		add_prop("forest_boat", _v3(hut + Vector2(-9.0, 7.0), -0.05), 0.4, 1.0)
		keep(_v3(hut), 6.0)
		_chest_at(hut + Vector2(3.5, 2.5), id, 0)
	# The witch's hut on the far shore: a green fire, bones, an old rune stone.
	var witch := _site(Vector2(700, 518), 6.0, id)
	if witch.x < INF:
		add_building("forest_hut", _v3(witch + Vector2(0, -3.5)), PI + rng.randf_range(-0.3, 0.3), Vector2(3.2, 2.6))
		add_obstacle("forest_firepit", _v3(witch + Vector2(0, 2.0)), 0.0, 1.0, 0.95, {"cutout": false, "tint": Color(0.7, 1.0, 0.8)})
		add_light(_v3(witch + Vector2(0, 2.0), 1.4), Color(0.45, 1.0, 0.6), 2.0, 8.0, true)
		add_glow(_v3(witch + Vector2(0, 2.0)), 3.0, Color(0.4, 1.0, 0.55))
		_solid(witch + Vector2(-5.0, 1.0), "forest_runestone_old", 0.9)
		add_block("forest_rack", _v3(witch + Vector2(4.5, -1.0)), 1.2, Vector2(3.4, 1.2), {"cutout": false})
		for k in 3:
			add_prop("env_bones", _v3(witch + Vector2(rng.randf_range(-4, 4), rng.randf_range(3, 6))), rng.randf() * TAU, 1.0, {"shadows": false})
		keep(_v3(witch), 7.0)
		_chest_at(witch + Vector2(4.0, 3.5), id, 1)
	_chest_at(Vector2(750, 457), id, 2)
	_shrine_at(Vector2(700, 418), id)
	# Birches along the shores, pines behind; a few groves; stones.
	var cells := region_cells(id)
	var groves := 0
	for t in 200:
		if groves >= 10:
			break
		if _grove(id, _rand_in(cells), rng.randf_range(5.0, 8.0), {"forest_stand_b": 2.0, "forest_stand_a": 1.0},
				{"forest_birch": 3.0, "forest_pine_b": 1.0}, {"forest_patch_meadow": 1.0, "forest_patch_fern": 1.0}):
			groves += 1
	_woods(id, {"stands": {"forest_stand_b": 2.0, "forest_stand_a": 1.0}, "n_stands": 26,
		"trees": {"forest_birch": 5.0, "forest_pine_b": 2.0, "forest_pine_a": 1.5, "forest_spruce": 1.0}, "n_clumps": 28, "n_singles": 40,
		"spacing": 7.0, "scale": Vector2(0.85, 1.15), "dens": 0.25})
	_scatter_solids(id, 14, {"forest_boulder_a": 1.0, "forest_boulder_b": 2.0}, Vector2(0.6, 1.1))
	# Lush meadows, scrub and ferns; reeds on the wet ground by the water.
	_cover(id, 220, {"forest_patch_meadow": 1.0}, Vector2(0.9, 1.35), {"freq": 0.06, "lo": 0.28, "seed": 5.0, "gap": 2.4})
	_cover(id, 60, {"forest_patch_scrub": 2.0, "forest_patch_fern": 1.0}, Vector2(0.85, 1.2), {"freq": 0.05, "lo": 0.48, "seed": 19.0, "gap": 2.4})
	_cover(id, 90, {"forest_grass": 3.0, "forest_flowers": 1.0}, Vector2(0.8, 1.4), {"freq": 0.07, "lo": 0.4, "seed": 43.0})
	_cover(id, 50, {"forest_reeds": 1.0}, Vector2(0.7, 1.0), {"lo": 0.0, "filter": func(p: Vector2) -> bool: return _near_kind(p, K_WATER, 2)})
	for k in 5:
		var sp: Vector2 = _route["shore"][rng.randi_range(4, (_route["shore"] as PackedVector2Array).size() - 5)]
		_shaft(sp)


## True if a cell of `kind` lies within r cells of p.
func _near_kind(p: Vector2, kind: int, r: int) -> bool:
	var c := _cell_of(p)
	for j in range(c.y - r, c.y + r + 1):
		for i in range(c.x - r, c.x + r + 1):
			if i >= 0 and j >= 0 and i < _fw and j < _fh and _kind[j * _fw + i] == kind:
				return true
	return false


# ------------------------------------------------------------------ The Grey Dwarf Hollows

func _paint_hollows() -> void:
	var id := "hollows"
	# Granite outcrops with mossy ravines between them; the grey dwarves' burrows in their flanks.
	var crops: Array = [[Vector2(682, 196), Vector2(20, 12), 0.3], [Vector2(754, 226), Vector2(15, 10), -0.2],
		[Vector2(700, 146), Vector2(18, 14), 0.5], [Vector2(770, 162), Vector2(12, 18), 0.0], [Vector2(744, 100), Vector2(14, 8), 0.2],
		[Vector2(664, 160), Vector2(8, 13), 0.0], [Vector2(620, 206), Vector2(9, 5), 0.2]]
	var holes := 0
	for o in crops:
		var oc: Vector2 = o[0]
		var orr: Vector2 = o[1]
		var cells := _outcrop(oc, orr, float(o[2]), id)
		if cells.is_empty():
			continue
		# crags and boulders on top
		var n := int(cells.size() / 9.0) + 1
		for k in n:
			var cc: Vector2i = cells[rng.randi() % cells.size()]
			var p := Vector2((cc.x + 0.5) * TILE, (cc.y + 0.5) * TILE)
			if not _hash_s_ok(p, 2.6):
				continue
			_hash_s_add(p, 2.6)
			var rid := pick({"forest_rock_slab": 2.0, "forest_boulder_a": 1.5, "forest_boulder_b": 1.0})
			add_prop(rid, _v3(p, _ground_y(p) - 0.4), rng.randf() * TAU, rng.randf_range(1.0, 1.7), {"cutout": true, "vary": 0.1})
		# a burrow on the rim, facing the open ground
		if holes < 5:
			for t in 40:
				var rc: Vector2i = cells[rng.randi() % cells.size()]
				var out := Vector2i.ZERO
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _kind[_ck(rc + d)] == K_OPEN and grid.walk[_ck(rc + d)] == 1:
						out = d
						break
				if out == Vector2i.ZERO:
					continue
				var hp := Vector2((rc.x + 0.5) * TILE, (rc.y + 0.5) * TILE) - Vector2(out) * 0.6
				add_prop("forest_dwarf_hole", _v3(hp, _ground_y(hp) - 0.1), atan2(float(out.x), float(out.y)), rng.randf_range(0.95, 1.15), {"cutout": true})
				keep(_v3(hp + Vector2(out) * 3.0), 2.5)
				holes += 1
				if holes == 2:
					_chest_at(hp + Vector2(out) * 4.0 + Vector2(-out.y, out.x) * 2.5, id, 1)
				break
	_chest_at(Vector2(776, 224), id, 0)
	_chest_at(Vector2(752, 110), id, 2)
	_shrine_at(Vector2(700, 176), id)
	# Dark spruce: groves, stands, clumps and single trees; a boulder field in the east; dead snags.
	var cells2 := region_cells(id)
	var groves := 0
	for t in 220:
		if groves >= 12:
			break
		if _grove(id, _rand_in(cells2), rng.randf_range(5.0, 8.0), {"forest_stand_c": 3.0, "forest_stand_b": 0.6},
				{"forest_spruce": 3.0, "forest_snag": 0.5}, {"forest_patch_fern": 2.0, "forest_patch_moss": 1.0}):
			groves += 1
	_woods(id, {"stands": {"forest_stand_c": 4.0, "forest_stand_b": 0.5}, "n_stands": 34,
		"trees": {"forest_spruce": 6.0, "forest_pine_b": 1.2, "forest_birch": 0.4}, "n_clumps": 20, "n_singles": 34,
		"spacing": 7.0, "scale": Vector2(0.8, 1.2), "dens": 0.25})
	_scatter_solids(id, 36, {"forest_boulder_a": 2.0, "forest_boulder_b": 1.5, "forest_rock_slab": 0.6}, Vector2(0.6, 1.2),
		func(p: Vector2) -> bool: return p.x > 735.0 or p.y < 125.0, 0.8)
	_scatter_solids(id, 12, {"forest_boulder_a": 2.0, "forest_boulder_b": 1.0}, Vector2(0.6, 1.1))
	_scatter_solids(id, 8, {"forest_snag": 1.0}, Vector2(0.85, 1.15))
	# Bracken and moss everywhere, fly agarics.
	_cover(id, 150, {"forest_patch_fern": 1.0}, Vector2(0.85, 1.3), {"freq": 0.06, "lo": 0.3, "seed": 3.0, "gap": 2.4})
	_cover(id, 120, {"forest_patch_moss": 1.0}, Vector2(0.85, 1.25), {"freq": 0.05, "lo": 0.36, "seed": 61.0, "gap": 2.3})
	_cover(id, 60, {"forest_fern": 2.0, "forest_mushrooms": 1.0}, Vector2(0.8, 1.3), {"freq": 0.1, "lo": 0.45, "seed": 23.0})


# ------------------------------------------------------------------ Hell's Gap

func _paint_gap() -> void:
	var id := "gap"
	# The chasm: from the north edge down through the fort, narrowing to a crack south of it.
	var g1 := _curve([Vector2(392, -8), Vector2(386, 24), Vector2(391, 50), Vector2(386, 76), Vector2(392, 102)], 3.0, 1.5)
	var g2 := _curve([Vector2(392, 100), Vector2(389, 114), Vector2(388, 126)], 3.0, 0.0)
	_gorge_cells = _gorge(g1, 10.5, 13.5, id)
	var tail := _gorge(g2, 4.5, 8.0, id)
	for c in tail:
		_gorge_cells[c] = tail[c]
	_fort(id)
	# Rocks along the rims (outside the fort's bridge).
	for pts in [g1, g2]:
		var pv: PackedVector2Array = pts
		for k in range(1, pv.size() - 1):
			if rng.randf() > 0.55:
				continue
			var dir := (pv[k + 1] - pv[k - 1]).normalized()
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			var rp: Vector2 = pv[k] + Vector2(-dir.y, dir.x) * s * rng.randf_range(4.5, 6.5)
			var rc := _cell_of(rp)
			if not _in(rc) or _kind[_ck(rc)] != K_GORGE or absf(rp.y - 70.0) < 7.0:
				continue
			if not _hash_s_ok(rp, 2.2):
				continue
			_hash_s_add(rp, 2.2)
			add_prop(pick({"forest_rock_slab": 1.0, "forest_boulder_a": 2.0}), _v3(rp, _ground_y(rp) - 0.3), rng.randf() * TAU,
				rng.randf_range(0.8, 1.3), {"cutout": true, "vary": 0.1})
	# Old outworks: broken walls and a fallen tower out in the forest.
	var outworks: Array = [Vector2(300, 62), Vector2(468, 58), Vector2(456, 118), Vector2(318, 104), Vector2(430, 18)]
	for ow in outworks:
		var p: Vector2 = _site(ow, 5.0, id, 12.0)
		if p.x == INF:
			continue
		var yaw := rng.randf() * PI
		if rng.randf() < 0.4:
			add_obstacle("forest_fort_tower", _v3(p), rng.randf() * TAU, rng.randf_range(0.75, 0.9), 2.3, {"cutout": true, "opaque": true, "height": 4.0})
		else:
			for k in 2:
				var wp := p + Vector2(cos(yaw), -sin(yaw)) * (k * 4.0 - 2.0)
				add_building("forest_fort_ruin", _v3(wp), yaw, Vector2(4.0, 1.5), {"height": 4.0})
		keep(_v3(p), 5.0)
		_hash_add(_v3(p), 5.0)
	_chest_at(Vector2(300, 70), id, 0)
	_shrine_at(Vector2(470, 100), id)
	# Rocky pine forest round the fort.
	var not_fort := func(p: Vector2) -> bool: return not FORT.grow(4.0).has_point(p)
	var cells := region_cells(id)
	var groves := 0
	for t in 240:
		if groves >= 12:
			break
		var gp := _rand_in(cells)
		if FORT.grow(10.0).has_point(gp):
			continue
		if _grove(id, gp, rng.randf_range(5.0, 8.0), {"forest_stand_a": 2.0, "forest_stand_c": 1.0}, {"forest_pine_b": 2.0, "forest_snag": 0.5},
				{"forest_patch_scrub": 1.0, "forest_patch_moss": 1.0}):
			groves += 1
	_woods(id, {"stands": {"forest_stand_a": 2.0, "forest_stand_c": 1.0}, "n_stands": 30,
		"trees": {"forest_pine_a": 3.0, "forest_pine_b": 3.0, "forest_spruce": 1.5}, "n_clumps": 20, "n_singles": 34, "filter": not_fort, "dens": 0.28})
	_scatter_solids(id, 36, {"forest_boulder_a": 2.0, "forest_boulder_b": 1.5, "forest_rock_slab": 0.8}, Vector2(0.6, 1.25), not_fort)
	_scatter_solids(id, 8, {"forest_snag": 1.0}, Vector2(0.85, 1.2), not_fort)
	_cover(id, 110, {"forest_patch_moss": 1.0, "forest_patch_scrub": 1.0}, Vector2(0.85, 1.2), {"freq": 0.06, "lo": 0.38, "seed": 13.0, "gap": 2.4})
	_cover(id, 90, {"forest_grass": 2.0, "forest_shrub": 1.0}, Vector2(0.8, 1.3), {"freq": 0.07, "lo": 0.4, "seed": 29.0})
	_cover(id, 30, {"forest_patch_fern": 1.0}, Vector2(0.85, 1.2), {"freq": 0.05, "lo": 0.55, "seed": 47.0, "gap": 2.5, "filter": not_fort})


## West and east rim (m) of the chasm on a row of the fort (x range of its cells).
func _gorge_span(z: float) -> Vector2:
	var j := floori(z / TILE)
	var lo := INF
	var hi := -INF
	for i in range(floori(360.0 / TILE), floori(420.0 / TILE)):
		if _kind[j * _fw + i] == K_GORGE:
			lo = minf(lo, i * TILE)
			hi = maxf(hi, (i + 1) * TILE)
	if lo == INF:
		return Vector2(386.0, 394.0)
	return Vector2(lo, hi)


## A run of fort wall pieces (4 m each, some broken) from a to b.
func _wall_run(a: Vector2, b: Vector2, ruin: float) -> void:
	var ln := a.distance_to(b)
	if ln < 2.5:
		return
	var n := maxi(1, roundi(ln / 4.0))
	var seg := ln / n
	var dir := (b - a) / ln
	var yaw := atan2(-dir.y, dir.x)
	for k in n:
		var p := a + dir * (seg * (k + 0.5))
		var broken := rng.randf() < ruin
		add_building("forest_fort_ruin" if broken else "forest_fort_wall", _v3(p), yaw, Vector2(seg, 1.5), {"height": 4.0, "scale": seg / 4.0})


## The ruined Mattis fort: walls and towers round a courtyard split by the chasm, the gatehouse to
## the south, a breach in the west wall, a log bridge across the chasm, a robbers' camp.
func _fort(id: String) -> void:
	var xw := FORT.position.x
	var xe := FORT.end.x
	var zn := FORT.position.y
	var zs := FORT.end.y
	var gx := FORT_GATE_X
	var rim_s := _gorge_span(zs)
	var rim_n := _gorge_span(zn)
	_wall_run(Vector2(xw + 2.0, zs), Vector2(rim_s.x - 3.0, zs), 0.45)
	_wall_run(Vector2(rim_s.y + 3.0, zs), Vector2(gx - 4.0, zs), 0.35)
	_wall_run(Vector2(gx + 4.0, zs), Vector2(xe - 2.0, zs), 0.35)
	_wall_run(Vector2(xw + 2.0, zn), Vector2(rim_n.x - 3.0, zn), 0.5)
	_wall_run(Vector2(rim_n.y + 3.0, zn), Vector2(xe - 2.0, zn), 0.5)
	_wall_run(Vector2(xw, zn + 2.0), Vector2(xw, 62.0), 0.4)
	_wall_run(Vector2(xw, 74.0), Vector2(xw, zs - 2.0), 0.4)
	_wall_run(Vector2(xe, zn + 2.0), Vector2(xe, zs - 2.0), 0.3)
	# the gatehouse (its passage: the two cell columns under the arch)
	add_prop("forest_fort_gate", Vector3(gx, 0, zs), 0.0, 1.0, {"cutout": true, "shadows": true})
	var pass0 := floori((gx - 1.0) / TILE)
	for s in [-1.0, 1.0]:
		var pier := Vector3(gx + s * 2.9, 0, zs)
		shapes.append({"type": "box", "pos": pier, "size": Vector3(2.2, 4.0, 2.0), "yaw": 0.0})
		for c in cells_in_disc(pier, 1.6):
			if c.x != pass0 and c.x != pass0 + 1:
				block_cell(c, true, true)
	keep(Vector3(gx, 0, zs), 3.0)
	keep(Vector3(gx, 0, zs + 4.0), 2.0)
	keep(Vector3(gx, 0, zs - 4.0), 2.0)
	# towers: the corners and either side of the chasm
	for t in [Vector2(xw, zn), Vector2(xe, zn), Vector2(xw, zs), Vector2(xe, zs), Vector2(rim_n.x - 3.0, zn),
			Vector2(rim_n.y + 3.0, zn), Vector2(rim_s.x - 3.0, zs), Vector2(rim_s.y + 3.0, zs)]:
		var tp: Vector2 = t
		add_obstacle("forest_fort_tower", _v3(tp), rng.randf() * TAU, 1.0, 2.8, {"cutout": true, "opaque": true, "height": 4.0})
		_hash_add(_v3(tp), 3.5)
	# the log bridge across the chasm, mid-courtyard
	var bz := 70.0
	var rim_b := _gorge_span(bz)
	var span := rim_b.y - rim_b.x
	var deck := _band(PackedVector2Array([Vector2(rim_b.x - 3.0, bz), Vector2(rim_b.y + 3.0, bz)]), 4.4, 4.4)
	for cell in deck:
		var cc: Vector2i = cell
		if _kind[_ck(cc)] == K_GORGE:
			_set_open(cc, K_DECK)
	add_prop("forest_log_bridge", Vector3((rim_b.x + rim_b.y) * 0.5, 0.0, bz), PI * 0.5, (span + 3.0) / 12.8, {"cutout": false})
	keep(Vector3(rim_b.x - 3.0, 0, bz), 3.0)
	keep(Vector3(rim_b.y + 3.0, 0, bz), 3.0)
	# old paving in the courtyard
	var paving: Array = []
	for cj in range(floori(zn / TILE) + 1, floori(zs / TILE) - 1):
		for ci in range(floori(xw / TILE) + 1, floori(xe / TILE) - 1):
			var c := Vector2i(ci, cj)
			if _kind[_ck(c)] != K_OPEN or not grid.is_walkable_cell(c):
				continue
			var cp := cell_center(c)
			if noise2(cp.x + 4.0, cp.z, 0.09, 2) > 0.52:
				paving.append(c)
	add_tiles(["env_floor_a", "env_floor_b", "env_floor_c"], paving, Color(0.62, 0.62, 0.6),
		[Color(0.62, 0.62, 0.6), Color(0.55, 0.57, 0.54), Color(0.66, 0.64, 0.6), Color(0.52, 0.58, 0.46)])
	# the robbers' camp in the east yard
	var camp := _site(Vector2(418, 58), 4.0, id, 10.0)
	if camp.x < INF:
		add_obstacle("forest_firepit", _v3(camp), 0.0, 1.0, 0.95, {"cutout": false})
		add_light(_v3(camp, 1.4), Color(1.0, 0.6, 0.28), 2.2, 9.0, true)
		add_glow(_v3(camp), 3.0, Color(1.0, 0.55, 0.22))
		add_block("forest_woodpile", _v3(camp + Vector2(4.0, -2.0)), 1.3, Vector2(2.4, 1.0), {"cutout": false, "height": 1.4})
		add_block("forest_rack", _v3(camp + Vector2(-4.0, -3.0)), 0.2, Vector2(3.4, 1.2), {"cutout": false})
		keep(_v3(camp), 5.0)
		_chest_at(camp + Vector2(3.0, 4.0), id, 1)
	_chest_at(Vector2(356, 50), id, 2)
	_shrine_at(Vector2(364, 86), id)
	# rubble, bones, grass along the walls
	for k in 16:
		var p := Vector2(rng.randf_range(xw + 3.0, xe - 3.0), rng.randf_range(zn + 3.0, zs - 3.0))
		if not _free(p) or _trail_at(p) > 0.2:
			continue
		var edge := minf(minf(p.x - xw, xe - p.x), minf(p.y - zn, zs - p.y))
		if edge < 4.5:
			add_prop("forest_grass" if rng.randf() < 0.6 else "forest_shrub", _v3(p), rng.randf() * TAU, rng.randf_range(0.8, 1.3), {"shadows": false})
		else:
			add_prop("env_rubble" if k % 3 else "env_bones", _v3(p), rng.randf() * TAU, rng.randf_range(0.9, 1.3), {"shadows": false})


# ------------------------------------------------------------------ The Barrow Downs

func _paint_downs() -> void:
	var id := "downs"
	# The Old Barrow (the act dungeon) on the south edge, its door to the north, and its guardian.
	var door := dungeon_door()
	if not door.is_empty():
		var dv: Vector2i = door["dir"]
		var dpos: Vector3 = door["pos"]
		var epos := dpos - Vector3(dv.x, 0, dv.y) * 3.0
		add_dungeon_entrance(epos, atan2(-dv.x, -dv.y), "forest_barrow", Vector2(9.0, 7.0))
		_hash_add(epos, 6.5)
		var front := Vector2(epos.x, epos.z) - Vector2(dv) * 20.0
		add_zone_boss(_v3(front))
		# a ring of standing stones round the barrow's forecourt
		var e2 := Vector2(epos.x, epos.z)
		var fwd := -Vector2(dv)
		for k in 7:
			var ang := atan2(fwd.y, fwd.x) + (k - 3) * 0.43
			var sp := e2 + Vector2(cos(ang), sin(ang)) * 17.0
			if _free(sp) and _trail_at(sp) < 0.05:
				_solid(sp, "forest_standing_stone", rng.randf_range(0.8, 1.05))
	# Burial mounds (the king's mound the biggest), a long barrow.
	var mounds: Array = [[Vector2(96, 140), 1.7, "forest_mound"], [Vector2(60, 70), 1.3, "forest_mound"], [Vector2(142, 52), 1.1, "forest_mound"],
		[Vector2(40, 146), 1.2, "forest_mound"], [Vector2(182, 164), 1.0, "forest_mound"], [Vector2(190, 62), 1.2, "forest_mound_b"],
		[Vector2(66, 188), 1.0, "forest_mound_b"], [Vector2(28, 100), 0.95, "forest_mound"], [Vector2(112, 40), 1.0, "forest_mound"],
		[Vector2(160, 200), 0.9, "forest_mound"], [Vector2(76, 42), 0.8, "forest_mound"], [Vector2(84, 104), 0.9, "forest_mound_b"],
		[Vector2(160, 176), 0.75, "forest_mound"], [Vector2(50, 176), 0.8, "forest_mound"]]
	var king := Vector2.INF
	for m in mounds:
		var sc: float = m[1]
		var mid: String = m[2]
		var sz := Vector2(8.4, 7.2) * sc if mid == "forest_mound" else Vector2(12.8, 5.6) * sc
		var mp := _site(m[0], maxf(sz.x, sz.y) * 0.55, id, 14.0)
		if mp.x == INF:
			continue
		var yaw := rng.randf() * TAU
		add_block(mid, _v3(mp), yaw, sz, {"height": 2.6 * sc, "cutout": false, "scale": sc})
		_hash_add(_v3(mp), maxf(sz.x, sz.y) * 0.6)
		if sc > 1.5:
			king = mp
	if king.x < INF:
		for k in 8:
			var a := TAU * k / 8.0
			var sp := king + Vector2(cos(a), sin(a)) * 12.5
			if _free(sp) and _trail_at(sp) < 0.05:
				_solid(sp, "forest_standing_stone", rng.randf_range(0.6, 0.8))
		_chest_at(king + Vector2(0, 10.5), id, 1)
	# The stone ship: standing stones in the shape of a ship, a chest amidships.
	var ship := _site(Vector2(150, 92), 13.0, id, 40.0)
	if ship.x < INF:
		var yaw2 := rng.randf_range(-0.25, 0.25)
		var ax := Vector2(cos(yaw2), sin(yaw2))
		var az := Vector2(-ax.y, ax.x)
		for k in 22:
			var u := TAU * k / 22.0
			var x := cos(u) * 16.0
			var z := sin(u) * 5.6 * (1.0 - 0.25 * cos(u) * cos(u))
			var sp := ship + ax * x + az * z
			var tall := k == 0 or k == 11
			if _free(sp):
				_solid(sp, "forest_standing_stone", rng.randf_range(0.85, 0.95) if tall else rng.randf_range(0.42, 0.55))
		keep(_v3(ship), 4.0)
		_chest_at(ship, id, 2)
	# Barrow cemeteries: small mounds in clusters.
	var cem := 0
	for t in 60:
		if cem >= 5:
			break
		var cp := _site(_rand_in(region_cells(id)), 9.0, id, 6.0)
		if cp.x == INF:
			continue
		cem += 1
		for k in rng.randi_range(3, 5):
			var a := rng.randf() * TAU
			var mp := cp + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 7.5)
			var sc := rng.randf_range(0.45, 0.7)
			if _free(mp) and _trail_at(mp) < 0.05 and _hash_ok(_v3(mp), 3.8 * sc):
				add_block("forest_mound", _v3(mp), rng.randf() * TAU, Vector2(8.4, 7.2) * sc, {"height": 2.6 * sc, "cutout": false, "scale": sc})
				_hash_add(_v3(mp), 4.2 * sc)
		keep(_v3(cp), 9.0)
	# Standing stones, old rune stones and cairns on the heath.
	_scatter_solids(id, 9, {"forest_standing_stone": 1.0}, Vector2(0.7, 1.05), Callable(), 3.0)
	_scatter_solids(id, 4, {"forest_runestone_old": 1.0}, Vector2(0.9, 1.05), Callable(), 3.0)
	_scatter_solids(id, 7, {"forest_cairn": 1.0}, Vector2(0.7, 1.0), Callable(), 3.0)
	_chest_at(Vector2(40, 60), id, 0)
	_shrine_at(Vector2(170, 190), id)
	_shrine_at(Vector2(52, 112), id)
	# Few trees: junipers, wind-bent pines, birches, a few small groves, dead snags.
	var cells := region_cells(id)
	var groves := 0
	for t in 80:
		if groves >= 4:
			break
		if _grove(id, _rand_in(cells), rng.randf_range(4.0, 6.0), {"forest_stand_a": 1.0, "forest_stand_b": 1.0}, {"forest_birch": 1.0},
				{"forest_patch_heath": 2.0, "forest_grass": 1.0}):
			groves += 1
	_scatter_solids(id, 50, {"forest_juniper": 1.0}, Vector2(0.75, 1.25), Callable(), 1.2)
	_woods(id, {"trees": {"forest_pine_b": 3.0, "forest_birch": 2.0}, "n_clumps": 10, "n_singles": 22, "spacing": 9.0,
		"scale": Vector2(0.7, 0.95), "dens": 0.35})
	_scatter_solids(id, 7, {"forest_snag": 1.0}, Vector2(0.8, 1.1))
	_scatter_solids(id, 12, {"forest_boulder_b": 2.0, "forest_boulder_a": 1.0}, Vector2(0.5, 0.9))
	# Heather, dry grass, a few flowers.
	_cover(id, 420, {"forest_patch_heath": 1.0}, Vector2(1.05, 1.65), {"freq": 0.05, "lo": 0.22, "seed": 7.0, "gap": 2.8})
	_cover(id, 200, {"forest_grass": 3.0, "forest_heather": 1.0}, Vector2(1.0, 1.7), {"freq": 0.08, "lo": 0.28, "seed": 17.0})
	_cover(id, 18, {"forest_flowers": 1.0}, Vector2(0.8, 1.1), {"freq": 0.1, "lo": 0.6, "seed": 31.0})


# ------------------------------------------------------------------ the forest round the zones

## Trees and stands on the open land beyond the walkable edges: single trees near the fences,
## stands farther out, undergrowth right behind the fences, now and then a boulder at the edge
## (the fence runs up to it). Beyond the camera side of an edge (south / east of the walkable
## ground) the trees stay farther back and lower, so they don't hide the player.
func _edge_forest() -> void:
	for e in _edges:
		var c: Vector2i = e[0]
		var nrm: Vector2 = e[1]
		var base := Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)
		var look := maxi(LOOK_IDS.find(region_of_cell(c)), 0)
		var cam_side := nrm.dot(_cam_dir) > 0.3
		var side := Vector2(-nrm.y, nrm.x)
		var sparse := look == 4
		if rng.randf() < 0.05:
			var bp := base + nrm * 2.4 + side * rng.randf_range(-0.6, 0.6)
			if _void_ok(bp, 1.0) and _hash_ok(_v3(bp), 1.6):
				add_prop(pick({"forest_boulder_a": 2.0, "forest_boulder_b": 1.0}), _v3(bp, -0.15), rng.randf() * TAU, rng.randf_range(0.7, 1.05), {"cutout": true, "vary": 0.1})
				_hash_add(_v3(bp), 1.8)
		if rng.randf() < (0.34 if sparse else 0.4):
			var d := rng.randf_range(6.0, 10.0) if cam_side else rng.randf_range(1.8, 5.5)
			var p := base + nrm * d + side * rng.randf_range(-1.2, 1.2)
			if _void_ok(p, 1.2) and _hash_ok(_v3(p), 1.8):
				var tid := pick(_edge_trees(look))
				var sc := rng.randf_range(0.55, 0.75) if cam_side and d < 9.0 else rng.randf_range(0.85, 1.2)
				var o := {"cutout": true, "vary": 0.12}
				if tid != "forest_juniper":
					o["sway"] = _sway(tid)
					o["sway_base"] = _sway_base(tid)
				add_prop(tid, _v3(p, _wilds_height(p.x, p.y) * smoothstep(1.2, 4.5, d) - 0.1), rng.randf() * TAU, sc, o)
				_hash_add(_v3(p), 1.8)
		# stands behind them: the forest wall
		if rng.randf() < (0.3 if sparse else 0.42):
			var d2 := rng.randf_range(11.0, 17.0) if cam_side else rng.randf_range(5.8, 13.0)
			var p2 := base + nrm * d2 + side * rng.randf_range(-1.5, 1.5)
			if _void_ok(p2, 4.0) and _hash_ok(_v3(p2), 3.8):
				var sid := pick(_edge_stands(look))
				add_prop(sid, _v3(p2, _wilds_height(p2.x, p2.y) * smoothstep(1.2, 4.5, d2 - 3.0) - 0.15), rng.randf() * TAU,
					rng.randf_range(0.85, 1.12) * (0.85 if cam_side else 1.0), {"cutout": true, "sway": 0.28, "sway_base": _sway_base(sid), "vary": 0.1})
				_hash_add(_v3(p2), 4.0)
		# and a few far out (the view from above)
		if rng.randf() < (0.06 if sparse else 0.12):
			var p4 := base + nrm * rng.randf_range(20.0, 34.0) + side * rng.randf_range(-3.0, 3.0)
			if _void_ok(p4, 4.5) and _hash_ok(_v3(p4), 4.5):
				var sid2 := pick(_edge_stands(look))
				add_prop(sid2, _v3(p4, _wilds_height(p4.x, p4.y) - 0.2), rng.randf() * TAU, rng.randf_range(0.9, 1.2),
					{"cutout": true, "sway": 0.28, "sway_base": _sway_base(sid2), "vary": 0.1})
				_hash_add(_v3(p4), 4.5)
		# undergrowth behind the fence
		if rng.randf() < 0.28:
			var p3 := base + nrm * rng.randf_range(1.6, 4.5) + side * rng.randf_range(-1.0, 1.0)
			if _void_ok(p3, 0.5):
				add_prop(pick(_edge_cover(look)), _v3(p3), rng.randf() * TAU, rng.randf_range(0.85, 1.25), {"shadows": false, "vary": 0.14})


func _edge_trees(look: int) -> Dictionary:
	match look:
		1:
			return {"forest_birch": 4.0, "forest_pine_b": 2.0, "forest_pine_a": 2.0, "forest_spruce": 1.0}
		2:
			return {"forest_spruce": 6.0, "forest_pine_b": 1.0, "forest_snag": 0.4}
		3:
			return {"forest_pine_b": 3.0, "forest_pine_a": 3.0, "forest_spruce": 2.0, "forest_snag": 0.6}
		4:
			return {"forest_juniper": 3.0, "forest_pine_b": 2.0, "forest_birch": 2.0, "forest_snag": 0.4}
	return {"forest_pine_a": 4.0, "forest_pine_b": 3.0, "forest_spruce": 2.0, "forest_birch": 1.5}


func _edge_stands(look: int) -> Dictionary:
	match look:
		1:
			return {"forest_stand_b": 3.0, "forest_stand_a": 1.0}
		2:
			return {"forest_stand_c": 4.0, "forest_stand_b": 1.0}
		3:
			return {"forest_stand_a": 2.0, "forest_stand_c": 2.0}
		4:
			return {"forest_stand_a": 1.0, "forest_stand_b": 1.0}
	return {"forest_stand_a": 3.0, "forest_stand_b": 2.0}


func _edge_cover(look: int) -> Dictionary:
	match look:
		1:
			return {"forest_patch_meadow": 1.0, "forest_patch_fern": 1.0, "forest_patch_scrub": 1.0}
		2:
			return {"forest_patch_fern": 3.0, "forest_patch_moss": 2.0}
		3:
			return {"forest_patch_scrub": 2.0, "forest_patch_moss": 1.0, "forest_stump": 0.3}
		4:
			return {"forest_patch_heath": 3.0, "forest_grass": 1.0}
	return {"forest_patch_scrub": 3.0, "forest_patch_fern": 1.5, "forest_patch_moss": 1.0, "forest_stump": 0.3}


# ------------------------------------------------------------------ zone looks & monsters

func _zone_looks() -> void:
	set_region_theme("tarn", {"fog": Color(0.66, 0.76, 0.78), "fog_density": 0.0035, "ambient": Color(0.56, 0.66, 0.68),
		"sky_horizon": Color(0.8, 0.88, 0.9), "saturation": 1.08})
	set_region_theme("hollows", {"fog": Color(0.5, 0.56, 0.54), "fog_density": 0.009, "fog_height_density": 0.1,
		"ambient": Color(0.46, 0.53, 0.5), "ambient_energy": 0.46, "sun": Color(0.9, 0.92, 0.88), "sun_energy": 1.05,
		"exposure": 0.9, "saturation": 0.9, "contrast": 1.14, "sky_top": Color(0.4, 0.48, 0.58), "sky_horizon": Color(0.64, 0.68, 0.68)})
	set_region_theme("gap", {"fog": Color(0.5, 0.52, 0.52), "fog_density": 0.006, "fog_height_density": 0.05,
		"ambient": Color(0.5, 0.52, 0.54), "sun_energy": 1.15, "exposure": 0.9, "saturation": 0.92, "contrast": 1.14,
		"sky_top": Color(0.36, 0.46, 0.62), "sky_horizon": Color(0.7, 0.74, 0.76)})
	set_region_theme("downs", {"fog": Color(0.7, 0.75, 0.8), "fog_density": 0.004, "ambient": Color(0.6, 0.64, 0.7),
		"sun": Color(0.98, 0.95, 0.88), "sun_energy": 1.35, "saturation": 0.98, "brightness": 1.02,
		"sky_top": Color(0.36, 0.5, 0.72), "sky_horizon": Color(0.82, 0.86, 0.9)})


## Monster pools per zone (act monsters + the zone variants of monsters_forest.gd) and packs:
## about one per 4500 m2, two or three rare packs each.
func _monsters() -> void:
	set_region_pool("outskirts", {"draugr": 4.0, "rumphob": 3.0, "grey_dwarf": 2.0, "barrow_archer": 2.0, "wild_harpy": 1.0})
	set_region_pool("tarn", {"bog_dead": 5.0, "draugr": 2.0, "rime_witch": 2.0, "wild_harpy": 2.0, "barrow_archer": 1.0})
	set_region_pool("hollows", {"grey_dwarf": 6.0, "grey_dwarf_elder": 2.0, "rumphob": 2.0, "forest_troll": 2.0})
	set_region_pool("gap", {"wild_harpy": 5.0, "forest_troll": 2.0, "barrow_archer": 2.0, "draugr": 2.0, "rime_witch": 1.0})
	set_region_pool("downs", {"draugr": 4.0, "barrow_guard": 4.0, "barrow_archer": 3.0, "rime_witch": 1.5, "cairn_seer": 1.0})
	refresh_open_field()
	for r in regions:
		var rid := String(r["id"])
		var area := float(r.get("area_m2", float(r.get("cells", 0)) * TILE * TILE))
		var packs := maxi(4, roundi(area / 4500.0))
		var rares := 3 if area > 60000.0 or rid == "downs" else 2
		var n := auto_spawn_region(rid, packs, rares, 18.0, 14.0)
		if n < packs + rares:
			auto_spawn_region(rid, packs + rares - n, 0, 11.0, 10.0)


## Swedish roundpole fences (gärdsgård) line the edges of the walkable ground wherever nothing
## else (houses, the fort, boulders, tree trunks) marks them.
func border_style() -> Dictionary:
	return {
		"segments": {"forest_gardsgard_c": 4.0, "forest_gardsgard_d": 1.0},
		"length": 4.0,
		"offset": 0.4,
		"scale": Vector2(0.95, 1.08),
		"yaw_jitter": 0.03,
		"min_prop_height": 1.0,
		"prop_clearance": 0.6,
		"max_footprint": 0.5,
		"solid_prefixes": ["forest_longhouse", "forest_turfhouse", "forest_hut", "forest_fort", "forest_boulder",
			"forest_stall", "forest_log", "forest_rack", "forest_fence", "forest_jetty", "forest_longship",
			"forest_waterfall", "forest_barrow", "forest_woodpile", "forest_rock_slab", "forest_mound", "forest_gate"],
	}


# ================================================================== ground detail (WorldGroundFx)

## Time the ground detail placement took (ms; the preview prints it).
var ground_fx_ms := 0.0
## Grass colours (linear-ish tints for the grass shader): meadow, lush, shade, dry, heather.
const GRASS_MEADOW := Color(0.2, 0.34, 0.07)
const GRASS_LUSH := Color(0.16, 0.36, 0.06)
const GRASS_SHADE := Color(0.09, 0.2, 0.05)
const GRASS_DRY := Color(0.36, 0.34, 0.12)
const GRASS_HEATHER := Color(0.26, 0.13, 0.2)
const LEAF_TINTS := [Color(0.62, 0.42, 0.08), Color(0.58, 0.22, 0.06), Color(0.3, 0.17, 0.07), Color(0.48, 0.1, 0.05)]


## The wilds: grass patches on the open ground (by zone), reeds on the shores, and details —
## twigs and pine cones under the trees, pebble clusters on the trails and by the rocks, leaf heaps,
## puddles on the wet trails, moss on rocky ground, bones on the barrow downs.
func _ground_fx_wilds() -> void:
	var t0 := Time.get_ticks_usec()
	var wk := grid.walk
	for j in range(1, _fh - 1):
		var z := (j + 0.5) * TILE
		for i in range(1, _fw - 1):
			var k := j * _fw + i
			var kd := _kind[k]
			if kd == K_VOID or kd == K_GORGE:
				continue
			var x := (i + 0.5) * TILE
			var c := Vector2i(i, j)
			var f: Color = _fine[k]
			if kd == K_WATER:
				# reeds and sedge in the shallows next to walkable ground
				if f.b > -0.6 and _near_walk(i, j) and rng.randf() < 0.35:
					add_grass(Vector3(x + rng.randf_range(-0.8, 0.8), 0, z + rng.randf_range(-0.8, 0.8)), rng.randf_range(0.8, 1.15),
						GRASS_LUSH.lerp(GRASS_DRY, rng.randf() * 0.35), "reeds")
				continue
			if wk[k] == 0 and kd != K_GROVE:
				continue
			_look(x, z)
			var wt := _l_w.r
			var wh := _l_w.g
			var wg := _l_w.b
			var wd := _l_w.a
			var trail := f.g
			# --- grass patches (open walkable ground, off the trails)
			if kd == K_OPEN and trail < 0.25:
				var gp := noise2(x + 400.0, z - 170.0, 0.13, 2)
				var thr := 0.56 - 0.08 * wt - 0.06 * wd + 0.1 * wh
				if gp > thr:
					# patches: dense in the middle, a few tufts at the rim
					var dens := int(clampf((gp - thr) * 60.0, 1.0, 8.0))
					var tint := GRASS_MEADOW * _l_w0 + GRASS_LUSH * wt + GRASS_SHADE * wh + GRASS_DRY * wg + GRASS_DRY.lerp(GRASS_HEATHER, 0.55) * wd
					for q in dens:
						var p := Vector3(x + rng.randf_range(-1.0, 1.0), 0, z + rng.randf_range(-1.0, 1.0))
						if not is_clear(p, 0.3):
							continue
						var v := rng.randf_range(0.82, 1.15)
						var tt := Color(tint.r * v, tint.g * v * rng.randf_range(0.92, 1.08), tint.b * v)
						if wd > 0.5 and rng.randf() < 0.45:
							tt = GRASS_HEATHER * v
						add_grass(p, rng.randf_range(0.75, 1.2) * (0.8 if wd > 0.5 else 1.0), tt)
			# --- details
			var r := rng.randf()
			if trail > 0.3:
				if r < 0.07:
					add_detail("pebbles", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.5, 0.9), Color(0.5, 0.47, 0.42))
				elif r < 0.09 + 0.05 * (wt + wh):
					add_detail("puddle", _jit(x, z), rng.randf() * TAU, Vector2(rng.randf_range(1.0, 2.2), rng.randf_range(0.8, 1.6)), Color(0.2, 0.24, 0.26))
				elif r < 0.12:
					add_detail("twigs", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 1.0), Color(0.2, 0.13, 0.08))
				continue
			var edge := _near_void(i, j)
			if kd == K_GROVE or edge:
				if r < 0.08:
					add_detail("twigs", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.7, 1.2), Color(0.2, 0.13, 0.08))
				elif r < 0.16 + 0.08 * wt:
					add_detail("leaves", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.8, 1.4), LEAF_TINTS[rng.randi() % LEAF_TINTS.size()])
				elif r < 0.2 + 0.08 * (wh + wg):
					add_detail("needles", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.7, 1.2), Color(0.36, 0.2, 0.09))
				elif r < 0.22 + 0.06 * wh:
					add_detail("moss", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.8, 1.6), Color(0.12, 0.2, 0.05))
				continue
			if r < 0.035 * (_l_w0 + wt):
				add_detail("leaves", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.7, 1.2), LEAF_TINTS[rng.randi() % LEAF_TINTS.size()])
			elif r < 0.05 and f.a > 0.05:
				add_detail("pebbles", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 1.0), Color(0.46, 0.46, 0.44))
			elif r < 0.058 and wd > 0.5:
				add_detail("bones", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.6, 0.9), Color(0.78, 0.74, 0.64))
			elif r < 0.07 and wd > 0.3:
				add_detail("moss", _jit(x, z), rng.randf() * TAU, Vector2.ONE * rng.randf_range(0.8, 1.5), Color(0.2, 0.18, 0.06))
	ground_fx_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The village: grass on the green (bends as people walk through), reeds along the shore, straw
## and wood chips in the yard, pebbles on the paths, puddles by the jetty.
func _ground_fx_hub() -> void:
	var green := func(p: Vector3) -> bool:
		return _trail_dist(p.x, p.z) > 2.2 and p.distance_to(Vector3(36, 0, 31)) > 6.5 and p.z < _shore_z(p.x) - 3.0
	scatter_grass(46, 22, Rect2(10, 8, 52, 40), {"filter": green, "radius": Vector2(1.2, 2.6), "tints": [GRASS_MEADOW, GRASS_LUSH, GRASS_MEADOW.lerp(GRASS_DRY, 0.3)]})
	scatter_grass(22, 10, Rect2(-10, 44, 92, 18), {"on": "any", "kind": "reeds", "radius": Vector2(0.8, 1.8), "scale": Vector2(0.7, 1.0),
		"tints": [GRASS_LUSH, GRASS_LUSH.lerp(GRASS_DRY, 0.4)],
		"filter": func(p: Vector3) -> bool: return absf(p.z - (_shore_z(p.x) - 0.3)) < 1.2 and absf(p.x - 44.0) > 3.0})
	var on_path := func(p: Vector3) -> bool: return _trail_dist(p.x, p.z) < 1.8
	scatter_details("pebbles", 40, Rect2(10, -6, 52, 54), {"filter": on_path, "size": Vector2(0.5, 0.9), "tint": Color(0.5, 0.47, 0.42)})
	scatter_details({"straw": 3.0, "splinters": 1.0}, 30, Rect2(28, 24, 16, 14), {"size": Vector2(0.6, 1.1),
		"tints": [Color(0.5, 0.42, 0.22), Color(0.45, 0.34, 0.2)]})
	scatter_details({"splinters": 1.0}, 10, Rect2(18, 14, 44, 14), {"size": Vector2(0.6, 1.0), "tint": Color(0.62, 0.46, 0.28),
		"filter": func(p: Vector3) -> bool: return _trail_dist(p.x, p.z) < 3.0})
	scatter_details({"leaves": 2.0, "twigs": 1.0}, 40, Rect2(6, 4, 60, 48), {"size": Vector2(0.7, 1.2), "tints": LEAF_TINTS,
		"filter": func(p: Vector3) -> bool: return _fd_walk_edge(p) < 2.5})
	scatter_details("puddle", 5, Rect2(30, 36, 20, 12), {"size": Vector2(1.0, 1.8), "stretch": 1.5, "tint": Color(0.22, 0.26, 0.28),
		"filter": on_path})


func _jit(x: float, z: float) -> Vector3:
	return Vector3(x + rng.randf_range(-0.8, 0.8), 0, z + rng.randf_range(-0.8, 0.8))


## A walkable 4-neighbour?
func _near_walk(i: int, j: int) -> bool:
	var wk := grid.walk
	var k := j * _fw + i
	return wk[k - 1] == 1 or wk[k + 1] == 1 or wk[k - _fw] == 1 or wk[k + _fw] == 1


## A non-walkable 8-neighbour (the edge of the walkable ground)?
func _near_void(i: int, j: int) -> bool:
	var wk := grid.walk
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if wk[(j + dj) * _fw + i + di] == 0:
				return true
	return false

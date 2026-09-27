class_name WorldActComposite
extends WorldActGen
## A whole act as ONE seamless map (see WorldActGen, "Seamless acts"). The act's generator lays out
## the hub and the wilds separately (one generator instance per zone, each in its own
## coordinates); this composer
##   1. finds each zone's exit (add_exit(), else derived from its old portal / start: the nearest
##      grid edge), turns the wilds in quarter turns so the two exits face each other and places
##      them EXIT_GAP_CELLS apart, then shifts both so the merged grid starts at cell (0, 0),
##   2. merges the grids, carves the road between the exits (and a passage from a derived exit's
##      portal to its grid edge), marks each cell's region: the town ("hub") up to the road's
##      midline, beyond it the wilds' own regions (its layout's outskirts and further zones),
##   3. transforms every output (props, collision shapes, lights, tiles, water, interactables,
##      spawn groups...) and drops what a zone laid out beyond the midline, the old hub <-> wilds
##      portals, and props standing on the road,
##   4. blends the zones' ground colours / heights across the midline (the road gets the zones'
##      path colour) and lines the walkable edges with the act's border pieces (border_style()).
## Output: the usual layout keys plus "regions" ([{"id", "name", "level" (offset), "safe", "pool"}],
## the town first), "region_map" (per cell: 1-based region index), "arrivals" (per region id, plus
## "wilds" = the outskirts, "town_portal", "dungeon_exit"), "region_themes" (full theme per region),
## "road", "split" and "water_areas". Spawn groups carry "region", "level_offset" and "pool".
## OWNER: acts framework.

const EXIT_GAP_CELLS := 6
const ROAD_WIDTH_CELLS := 3
## Metres over which the two zones' ground colours / heights blend around the midline.
const BLEND_M := 6.0
const ZONES: Array[String] = ["hub", "wilds"]

## zone -> {"zone", "gen": WorldActGen, "layout": Dictionary, "rot": int (quarter turns),
##  "norm": Vector2 (m, added after turning), "off": Vector2i (cells in the merged grid),
##  "size": Vector2i (turned grid size), "exit": {"cell", "dir", "from", "carve"} (local)}
var parts: Dictionary = {}
## Connection axis (0 = x, 1 = z), the midline's coordinate (m), and the hub's side (+1 = the hub
## lies where that coordinate is larger than the midline).
var axis := 1
var split := 0.0
var hub_side := 1.0
## The road (merged cells, inclusive) and its direction (from the hub towards the wilds).
var road_from := Vector2i.ZERO
var road_to := Vector2i.ZERO
var road_dir := Vector2i(0, -1)
## (inherited) regions / region_map / region_themes: the merged act's regions, the town first.
var arrivals: Dictionary = {}
var water_areas: Array = []

var _road_colors := {}      # zone -> Color (ground colour at the zone's exit)
var _road_cells: Array = [] # merged cells of the road between the zones
var _passages: Array = []   # [[Vector3 a, Vector3 b]] carved bands (m), for prop clearing
var _model_info := {}       # id -> {"height": float, "box": Rect2 (xz, model space)}
var _hub_rect_w := Rect2()  # the town zone's ground rect in merged coordinates
## The town's (finer) ground vertex spacing, used on ground tiles near the town.
var fine_step := 1.0
var _road_box := Rect2()    # the road's bounding box (+ margin), merged coordinates


## Milliseconds per composing phase (zones, merge, borders...).
var profile: Dictionary = {}


## Build the whole act. Returns the merged layout.
func compose(p_act: String, p_seed: int, p_level: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	act_id = p_act
	zone = "act"
	level = maxi(1, p_level)
	seed_value = p_seed
	rng.seed = hash("%s|compose|%d" % [act_id, seed_value])
	for z in ZONES:
		var gen := ActDefs.make_generator(act_id)
		var lay := gen.generate(act_id, z, p_seed, p_level)
		parts[z] = {"zone": z, "gen": gen, "layout": lay, "rot": 0, "norm": Vector2.ZERO, "off": Vector2i.ZERO,
			"gsize": (lay["grid"] as WorldGrid).size}
		profile["zone_" + z] = (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
	_place_parts()
	_merge_grids()
	_merge_outputs()
	_carve_roads()
	_mark_regions()
	finalize()
	var wa: Vector3 = arrivals.get("wilds", start)
	var reach := grid.flood_walkable(grid.nearest_walkable_cell(world_to_cell(start)))
	var wc := grid.nearest_walkable_cell(world_to_cell(wa))
	if wc.x < 0 or reach[grid.idx(wc)] == 0:
		push_warning("WorldActComposite(%s): the wilds are not reachable from the hub" % act_id)
	profile["merge"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_add_borders((parts["hub"]["gen"] as WorldActGen).border_style())
	_region_looks()
	profile["borders"] = (Time.get_ticks_usec() - t0) / 1000.0
	var lay := {
		"grid": grid, "start": start, "ground_rect": ground_rect, "ground_step": ground_step,
		"has_water": not water_areas.is_empty(), "water_level": water_level, "water_areas": water_areas,
		"water_rects": [], "tiles": tiles, "props": props, "shapes": shapes, "soft": soft, "lights": lights,
		"glows": glows, "shafts": shafts, "interactables": interactables, "spawn_groups": spawn_groups,
		"portal_spot": portal_spot, "boss_pos": boss_pos, "reveal_all": false, "act": act_id, "zone": "act",
		"exits": {}, "dungeon_entrance": dungeon_entrance, "regions": regions, "region_map": region_map,
		"arrivals": arrivals, "region_themes": region_themes,
		"road": {"from": cell_center(road_from), "to": cell_center(road_to)},
		"split": {"axis": axis, "value": split, "hub_side": hub_side},
		"profile": profile,
		"fine_step": fine_step, "fine_rect": _hub_rect_w,
		"details": details, "grass": grass, "ground_style": ground_style(),
	}
	return lay


# ------------------------------------------------------------------ transforms

static func rot_v(v: Vector2, k: int) -> Vector2:
	match posmod(k, 4):
		1:
			return Vector2(v.y, -v.x)
		2:
			return Vector2(-v.x, -v.y)
		3:
			return Vector2(-v.y, v.x)
	return v


static func rot_dir(d: Vector2i, k: int) -> Vector2i:
	var v := rot_v(Vector2(d), k)
	return Vector2i(roundi(v.x), roundi(v.y))


## A zone's local point -> merged world point.
func to_world(part: Dictionary, p: Vector3) -> Vector3:
	var r := rot_v(Vector2(p.x, p.z), int(part["rot"])) + (part["norm"] as Vector2) + Vector2(part["off"]) * TILE
	return Vector3(r.x, p.y, r.y)


## A merged world point -> the zone's local point (x, z).
func to_local(part: Dictionary, x: float, z: float) -> Vector2:
	var v := Vector2(x, z) - (part["norm"] as Vector2) - Vector2(part["off"]) * TILE
	return rot_v(v, 4 - int(part["rot"]))


## A zone's local cell -> merged cell (exact integer maths: quarter turns + offset).
func cell_to_world_cell(part: Dictionary, c: Vector2i) -> Vector2i:
	var off: Vector2i = part["off"]
	var gs: Vector2i = part["gsize"]
	match int(part["rot"]) % 4:
		1:
			return Vector2i(c.y, gs.x - 1 - c.x) + off
		2:
			return Vector2i(gs.x - 1 - c.x, gs.y - 1 - c.y) + off
		3:
			return Vector2i(gs.y - 1 - c.y, c.x) + off
	return c + off


func yaw_to_world(part: Dictionary, yaw: float) -> float:
	return yaw + float(part["rot"]) * PI * 0.5


func _rect_to_world(part: Dictionary, r: Rect2) -> Rect2:
	var a := to_world(part, Vector3(r.position.x, 0, r.position.y))
	var b := to_world(part, Vector3(r.end.x, 0, r.end.y))
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	return Rect2(lo, hi - lo)


## True if a merged world point lies on the zone's side of the midline.
func on_side(zone_id: String, x: float, z: float) -> bool:
	var c := x if axis == 0 else z
	var hub := (c - split) * hub_side >= 0.0
	return hub if zone_id == "hub" else not hub


## Signed distance (m) from the midline, positive on the hub's side.
func side_distance(x: float, z: float) -> float:
	return ((x if axis == 0 else z) - split) * hub_side


# ------------------------------------------------------------------ placement

## The zone's exit towards `to_zone`: {"cell": Vector2i on the grid edge, "dir", "from": Vector3
## (where a passage to the edge starts), "carve": bool}. Declared (add_exit) or derived.
func _exit_of(lay: Dictionary, to_zone: String) -> Dictionary:
	var g: WorldGrid = lay["grid"]
	var ex: Dictionary = (lay.get("exits", {}) as Dictionary).get(to_zone, {})
	var from: Vector3 = lay.get("start", Vector3.ZERO)
	var dir := Vector2i.ZERO
	var declared := not ex.is_empty()
	if declared:
		from = ex["pos"]
		dir = ex["dir"]
	else:
		for it in lay.get("interactables", []):
			if String(it.get("kind", "")) == "portal" and String(it.get("zone", "")) == to_zone:
				from = it["pos"]
		# The nearest grid edge.
		var gw := g.size.x * TILE
		var gh := g.size.y * TILE
		var d := [from.z, gh - from.z, from.x, gw - from.x]
		var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		var best := 0
		for k in 4:
			if float(d[k]) < float(d[best]):
				best = k
		dir = dirs[best]
	var c := Vector2i(clampi(floori(from.x / TILE), 0, g.size.x - 1), clampi(floori(from.z / TILE), 0, g.size.y - 1))
	var edge := c
	if dir.x < 0:
		edge.x = 0
	elif dir.x > 0:
		edge.x = g.size.x - 1
	elif dir.y < 0:
		edge.y = 0
	else:
		edge.y = g.size.y - 1
	return {"cell": edge, "dir": dir, "from": Vector3((c.x + 0.5) * TILE, 0, (c.y + 0.5) * TILE), "carve": (not declared) or edge != c}


func _place_parts() -> void:
	var hub: Dictionary = parts["hub"]
	var wilds: Dictionary = parts["wilds"]
	hub["exit"] = _exit_of(hub["layout"], "wilds")
	wilds["exit"] = _exit_of(wilds["layout"], "hub")
	var hd: Vector2i = hub["exit"]["dir"]
	var wd: Vector2i = wilds["exit"]["dir"]
	# Turn the wilds so their exit faces the hub's.
	var k := 0
	for t in 4:
		if rot_dir(wd, t) == -hd:
			k = t
			break
	wilds["rot"] = k
	for z in ZONES:
		var p: Dictionary = parts[z]
		var g: WorldGrid = p["layout"]["grid"]
		var size := g.size if int(p["rot"]) % 2 == 0 else Vector2i(g.size.y, g.size.x)
		p["size"] = size
		# Normalise: the turned grid rectangle's min corner at (0, 0).
		p["norm"] = Vector2.ZERO
		p["off"] = Vector2i.ZERO
		var r := _rect_to_world(p, Rect2(0, 0, g.size.x * TILE, g.size.y * TILE))
		p["norm"] = -r.position
	# Exit cells in each zone's normalised frame.
	var eh := cell_to_world_cell(hub, hub["exit"]["cell"])
	var ew := cell_to_world_cell(wilds, wilds["exit"]["cell"])
	road_dir = hd
	var woff: Vector2i = eh + hd * (EXIT_GAP_CELLS + 1) - ew
	# Shift both so the merged grid starts at (0, 0).
	var hsize: Vector2i = hub["size"]
	var wsize: Vector2i = wilds["size"]
	var lo := Vector2i(mini(0, woff.x), mini(0, woff.y))
	hub["off"] = -lo
	wilds["off"] = woff - lo
	var hi := Vector2i(maxi(hsize.x, woff.x + wsize.x), maxi(hsize.y, woff.y + wsize.y)) - lo
	setup_grid(hi)
	road_from = eh - lo
	road_to = eh + hd * (EXIT_GAP_CELLS + 1) - lo
	axis = 0 if hd.x != 0 else 1
	var a := cell_center(road_from)
	var b := cell_center(road_to)
	split = ((a.x + b.x) * 0.5) if axis == 0 else ((a.z + b.z) * 0.5)
	var ac := a.x if axis == 0 else a.z
	hub_side = 1.0 if ac > split else -1.0


# ------------------------------------------------------------------ merging

func _merge_grids() -> void:
	for z in ZONES:
		var p: Dictionary = parts[z]
		var lay: Dictionary = p["layout"]
		var g: WorldGrid = lay["grid"]
		for j in g.size.y:
			for i in g.size.x:
				var k := j * g.size.x + i
				var u := cell_to_world_cell(p, Vector2i(i, j))
				if not grid.in_bounds(u):
					continue
				var uk := grid.idx(u)
				grid.floor_cells[uk] = g.floor_cells[k]
				grid.walk[uk] = g.walk[k]
				grid.opaque[uk] = g.opaque[k]
		for c in (lay["soft"] as Dictionary):
			soft[cell_to_world_cell(p, c)] = true


func _merge_outputs() -> void:
	props = []
	shapes = []
	lights = []
	glows = []
	shafts = []
	tiles = []
	details = []
	grass = []
	interactables = []
	spawn_groups = []
	water_areas = []
	var rects: Array = []
	var steps: Array = []
	for z in ZONES:
		var p: Dictionary = parts[z]
		var lay: Dictionary = p["layout"]
		var gen: WorldActGen = p["gen"]
		var yaw0 := yaw_to_world(p, 0.0)
		for dd in lay.get("details", []):
			var wd := to_world(p, Vector3(float(dd[1]), 0.0, float(dd[2])))
			if not on_side(z, wd.x, wd.z):
				continue
			var nd2: Array = (dd as Array).duplicate()
			nd2[1] = wd.x
			nd2[2] = wd.z
			nd2[3] = float(dd[3]) + yaw0
			details.append(nd2)
		for g in lay.get("grass", []):
			var wg := to_world(p, Vector3(float(g[0]), 0.0, float(g[1])))
			if not on_side(z, wg.x, wg.z):
				continue
			var ng: Array = (g as Array).duplicate()
			ng[0] = wg.x
			ng[1] = wg.z
			ng[2] = float(g[2]) + yaw0
			grass.append(ng)
		for d in lay["props"]:
			var w := to_world(p, d["pos"])
			if not on_side(z, w.x, w.z):
				continue
			var nd: Dictionary = (d as Dictionary).duplicate()
			nd["pos"] = w
			nd["yaw"] = yaw_to_world(p, float(d.get("yaw", 0.0)))
			props.append(nd)
		for s in lay["shapes"]:
			var ws := to_world(p, s["pos"])
			if not on_side(z, ws.x, ws.z):
				continue
			var ns: Dictionary = (s as Dictionary).duplicate()
			ns["pos"] = ws
			if ns.has("yaw"):
				ns["yaw"] = yaw_to_world(p, float(s["yaw"]))
			shapes.append(ns)
		for key in ["lights", "glows", "shafts"]:
			var dst: Array = get(key)
			for l in lay[key]:
				var wl := to_world(p, l["pos"])
				if not on_side(z, wl.x, wl.z):
					continue
				var nl: Dictionary = (l as Dictionary).duplicate()
				nl["pos"] = wl
				if nl.has("yaw"):
					nl["yaw"] = yaw_to_world(p, float(l["yaw"]))
				dst.append(nl)
		for tg in lay["tiles"]:
			var cells: Array = []
			for c in tg.get("cells", []):
				cells.append(cell_to_world_cell(p, c))
			var nt: Dictionary = (tg as Dictionary).duplicate()
			nt["cells"] = cells
			tiles.append(nt)
		for it in lay["interactables"]:
			if String(it.get("kind", "")) == "portal" and String(it.get("zone", "")) in ZONES and String(it.get("act", act_id)) == act_id:
				continue
			var ni: Dictionary = (it as Dictionary).duplicate()
			ni["pos"] = to_world(p, it["pos"])
			ni["yaw"] = yaw_to_world(p, float(it.get("yaw", 0.0)))
			interactables.append(ni)
		var reg_info := {}
		for r in lay.get("regions", []):
			reg_info[String(r["id"])] = r
		for g in lay["spawn_groups"]:
			var ng: Dictionary = (g as Dictionary).duplicate()
			ng["position"] = to_world(p, g["position"])
			var ri: Dictionary = reg_info.get(String(g.get("region", "")), {})
			if not ri.is_empty():
				ng["level_offset"] = int(ri.get("level", 0))
				if not (ri.get("pool", {}) as Dictionary).is_empty() and not ng.has("pool"):
					ng["pool"] = ri["pool"]
			spawn_groups.append(ng)
		if bool(lay.get("has_water", false)):
			var wr: Array = lay.get("water_rects", [])
			if wr.is_empty():
				wr = [lay["ground_rect"]]
			for r in wr:
				var clipped := _clip_to_side(z, _rect_to_world(p, r))
				if clipped.size.x > 0.5 and clipped.size.y > 0.5:
					water_areas.append({"rect": clipped, "level": float(lay.get("water_level", -0.35))})
		rects.append(_rect_to_world(p, lay["ground_rect"]))
		steps.append(float(lay.get("ground_step", 1.0)))
		# Arrivals and special spots.
		arrivals[z] = to_world(p, lay["start"])
		if z == "wilds":
			var ra: Dictionary = lay.get("region_arrivals", {})
			for rid in ra:
				arrivals[rid] = to_world(p, ra[rid])
		if z == "hub":
			start = arrivals["hub"]
			var ps: Dictionary = lay.get("portal_spot", {})
			if not ps.is_empty():
				portal_spot = {"pos": to_world(p, ps["pos"]), "yaw": yaw_to_world(p, float(ps.get("yaw", 0.0)))}
				arrivals["town_portal"] = portal_spot["pos"]
			water_level = float(lay.get("water_level", water_level))
		else:
			boss_pos = to_world(p, lay.get("boss_pos", lay["start"]))
		var de: Dictionary = lay.get("dungeon_entrance", {})
		if not de.is_empty():
			var dpos := to_world(p, de["pos"])
			var dyaw := yaw_to_world(p, float(de.get("yaw", 0.0)))
			dungeon_entrance = {"pos": dpos, "yaw": dyaw, "model": de.get("model", ""), "size": de.get("size", Vector2(4, 4)), "zone": z}
			if not (lay.get("region_arrivals", {}) as Dictionary).has("dungeon_exit"):
				arrivals["dungeon_exit"] = dpos + Basis(Vector3.UP, dyaw) * Vector3(0, 0, maxf((de.get("size", Vector2(4, 4)) as Vector2).y * 0.5, 1.0) + 2.0)
		_road_colors[z] = gen.ground_color((p["exit"]["cell"].x + 0.5) * TILE, (p["exit"]["cell"].y + 0.5) * TILE)
	if not arrivals.has("town_portal"):
		arrivals["town_portal"] = arrivals["hub"]
	_hub_rect_w = rects[0]
	# Ground: the union of both zones' ground rectangles.
	var gr: Rect2 = rects[0]
	for r in rects:
		gr = gr.merge(r)
	ground_rect = gr
	# The wilds' (coarser) step everywhere, the town's finer one around the town.
	ground_step = float(steps[1])
	fine_step = minf(float(steps[0]), float(steps[1]))


func _clip_to_side(zone_id: String, r: Rect2) -> Rect2:
	var lo := r.position
	var hi := r.end
	var hub_hi := hub_side > 0.0   # the hub lies at larger coordinates
	var keep_hi := hub_hi if zone_id == "hub" else not hub_hi
	if axis == 0:
		if keep_hi:
			lo.x = maxf(lo.x, split)
		else:
			hi.x = minf(hi.x, split)
	else:
		if keep_hi:
			lo.y = maxf(lo.y, split)
		else:
			hi.y = minf(hi.y, split)
	return Rect2(lo, (hi - lo).max(Vector2.ZERO))


## Carve the road between the exits (and the passages from derived exits to their grid edge), and
## clear props off them.
func _carve_roads() -> void:
	var half := ROAD_WIDTH_CELLS / 2
	var side := Vector2i(absi(road_dir.y), absi(road_dir.x))
	_road_cells = _carve_band(road_from, road_to, side, half)
	var ra := cell_center(road_from)
	var rb := cell_center(road_to)
	_road_box = Rect2(Vector2(minf(ra.x, rb.x), minf(ra.z, rb.z)), Vector2(absf(ra.x - rb.x), absf(ra.z - rb.z))).grow(ROAD_WIDTH_CELLS * TILE + 3.0)
	_pave_road()
	_passages.append([cell_center(road_from), cell_center(road_to)])
	for z in ZONES:
		var p: Dictionary = parts[z]
		var ex: Dictionary = p["exit"]
		if not bool(ex["carve"]):
			continue
		var a := cell_to_world_cell(p, world_to_cell(ex["from"]))
		var b := cell_to_world_cell(p, ex["cell"])
		_carve_band(a, b, side, half)
		_passages.append([cell_center(a), cell_center(b)])
	# Props and collision shapes whose footprint reaches onto the carved bands.
	var band := (half + 0.5) * TILE
	var keep_props: Array = []
	for d in props:
		var info := _model_info_for(String(d["id"]))
		var sc := float(d.get("scale", 1.0))
		var box: Rect2 = info["box"]
		if not _footprint_on_passage(d["pos"], float(d.get("yaw", 0.0)), Rect2(box.position * sc, box.size * sc), band + 0.6):
			keep_props.append(d)
	props = keep_props
	var keep_shapes: Array = []
	for sh in shapes:
		var fp: Rect2
		if String(sh.get("type", "")) == "cylinder":
			var r := float(sh.get("radius", 0.5))
			fp = Rect2(-r, -r, r * 2.0, r * 2.0)
		else:
			var sz: Vector3 = sh.get("size", Vector3.ONE)
			fp = Rect2(-sz.x * 0.5, -sz.z * 0.5, sz.x, sz.z)
		if not _footprint_on_passage(sh["pos"], float(sh.get("yaw", 0.0)), fp, band):
			keep_shapes.append(sh)
	shapes = keep_shapes


## True if a footprint (rect in the item's local XZ, turned by yaw, at pos) comes within `reach`
## metres of any carved passage's centre line.
func _footprint_on_passage(pos: Vector3, yaw: float, fp: Rect2, reach: float) -> bool:
	var rad := maxf(fp.position.length(), fp.end.length())
	rad = maxf(rad, maxf(Vector2(fp.position.x, fp.end.y).length(), Vector2(fp.end.x, fp.position.y).length()))
	var inv := Basis(Vector3.UP, yaw).inverse()
	for seg in _passages:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		if _dist_to_segment(pos, a, b) > reach + rad:
			continue
		# Sample the centre line; a sample within `reach` of the footprint rectangle hits.
		var n := maxi(2, ceili(a.distance_to(b) / 0.75))
		for k in n + 1:
			var p: Vector3 = a.lerp(b, float(k) / n)
			var q: Vector3 = inv * (p - Vector3(pos.x, 0.0, pos.z))
			var cx := clampf(q.x, fp.position.x, fp.end.x)
			var cz := clampf(q.z, fp.position.y, fp.end.y)
			if Vector2(q.x - cx, q.z - cz).length() < reach:
				return true
	return false


func _carve_band(a: Vector2i, b: Vector2i, side: Vector2i, half: int) -> Array:
	var out: Array = []
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for s in n + 1:
		var t := float(s) / maxf(n, 1)
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		for o in range(-half, half + 1):
			var cc := c + side * o
			if grid.in_bounds(cc):
				grid.set_floor(cc, true)
				soft.erase(cc)
				if not cc in out:
					out.append(cc)
	return out


## The street paving (tile group) at a zone's exit continues onto its half of the road.
func _pave_road() -> void:
	for z in ZONES:
		var p: Dictionary = parts[z]
		var exit_cell := cell_to_world_cell(p, p["exit"]["cell"])
		var group: Dictionary = {}
		for tg in tiles:
			if exit_cell in (tg["cells"] as Array):
				group = tg
				break
		if group.is_empty():
			continue
		var cells: Array = group["cells"]
		for c in _road_cells:
			var cc: Vector2i = c
			var w := cell_center(cc)
			if on_side(z, w.x, w.z) and not cc in cells:
				cells.append(cc)


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func _mark_regions() -> void:
	var wl: Dictionary = parts["wilds"]["layout"]
	var wregs: Array = wl.get("regions", [])
	regions = [{"id": "hub", "name": ActDefs.zone_name(act_id, "hub"), "level": 0, "safe": true, "pool": {}}]
	if wregs.is_empty():
		regions.append({"id": "wilds", "name": ActDefs.zone_name(act_id, "wilds"), "level": 0, "safe": false, "pool": {}})
	else:
		for r in wregs:
			var nr: Dictionary = (r as Dictionary).duplicate()
			nr["safe"] = false
			regions.append(nr)
	_region_index = {}
	_region_cells = {}
	for k in regions.size():
		_region_index[String(regions[k]["id"])] = k + 1
	region_map = PackedByteArray()
	region_map.resize(grid.size.x * grid.size.y)
	# The town up to the midline, the outskirts (the first wilds region) beyond it...
	var w := grid.size.x
	for j in grid.size.y:
		for i in w:
			var hub := false
			if axis == 1:
				hub = ((j + 0.5) * TILE - split) * hub_side >= 0.0
			else:
				hub = ((i + 0.5) * TILE - split) * hub_side >= 0.0
			region_map[j * w + i] = 1 if hub else 2
	# ... and the wilds' own regions where its layout has them.
	var wmap: PackedByteArray = wl.get("region_map", PackedByteArray())
	if wmap.is_empty():
		return
	var wp: Dictionary = parts["wilds"]
	var wg: WorldGrid = wl["grid"]
	for k in wmap.size():
		var v := int(wmap[k])
		if v == 0:
			continue
		var u := cell_to_world_cell(wp, Vector2i(k % wg.size.x, k / wg.size.x))
		if grid.in_bounds(u):
			var cc := cell_center(u)
			if not on_side("hub", cc.x, cc.z):
				region_map[u.y * grid.size.x + u.x] = v + 1


## Every region's full theme: the town's, the wilds' theme() with each region's overrides.
func _region_looks() -> void:
	region_themes = {}
	region_themes["hub"] = (parts["hub"]["gen"] as WorldActGen).full_theme()
	var wgen: WorldActGen = parts["wilds"]["gen"]
	var base := wgen.full_theme()
	region_themes["wilds"] = base
	for r in regions:
		var id := String(r["id"])
		if id == "hub":
			continue
		var th := base.duplicate()
		var over: Dictionary = wgen.region_themes.get(id, {})
		for key in over:
			# Nested looks ("volumetric_fog") merge key by key.
			if th.get(key) is Dictionary and over[key] is Dictionary:
				var sub: Dictionary = (th[key] as Dictionary).duplicate()
				sub.merge(over[key], true)
				th[key] = sub
			else:
				th[key] = over[key]
		region_themes[id] = th
	if not arrivals.has("wilds") or regions.size() > 1:
		arrivals["wilds"] = arrivals.get(String(regions[1]["id"]), arrivals.get("wilds", start)) if regions.size() > 1 else start


# ------------------------------------------------------------------ ground & look

## The town's zone on its side of the midline within its own ground rect, else the wilds' (the town
## zone knows nothing about ground far to its sides).
func _part_at(x: float, z: float) -> Dictionary:
	return parts["hub"] if on_side("hub", x, z) and _hub_rect_w.has_point(Vector2(x, z)) else parts["wilds"]


func ground_color(x: float, z: float) -> Color:
	var sd := side_distance(x, z)
	var c: Color
	if absf(sd) >= BLEND_M or not _hub_rect_w.has_point(Vector2(x, z)):
		var p := _part_at(x, z)
		var l := to_local(p, x, z)
		c = (p["gen"] as WorldActGen).ground_color(l.x, l.y)
	else:
		var lh := to_local(parts["hub"], x, z)
		var lw := to_local(parts["wilds"], x, z)
		var ch := (parts["hub"]["gen"] as WorldActGen).ground_color(lh.x, lh.y)
		var cw := (parts["wilds"]["gen"] as WorldActGen).ground_color(lw.x, lw.y)
		c = cw.lerp(ch, smoothstep(-BLEND_M, BLEND_M, sd))
	# The road between the zones takes their path colour.
	if not _road_box.has_point(Vector2(x, z)):
		return c
	var d := _dist_to_segment(Vector3(x, 0, z), cell_center(road_from), cell_center(road_to))
	var half_w := ROAD_WIDTH_CELLS * TILE * 0.5
	if d < half_w + 1.5:
		var rc: Color = (_road_colors.get("wilds", c) as Color).lerp(_road_colors.get("hub", c), smoothstep(-BLEND_M, BLEND_M, sd))
		var n := WorldActGen.vnoise(x * 0.6, z * 0.6)
		rc = rc * (0.94 + 0.1 * n)
		c = c.lerp(rc, 1.0 - smoothstep(half_w - 0.8, half_w + 1.5, d))
	return c


func ground_style() -> String:
	if parts.has("wilds"):
		return (parts["wilds"]["gen"] as WorldActGen).ground_style()
	return super.ground_style()


## The zones' material weights, blended across the midline like the colours; the road between
## the zones is gravel / packed ground (the style's first layer).
func ground_detail(x: float, z: float) -> Color:
	var sd := side_distance(x, z)
	var c: Color
	if absf(sd) >= BLEND_M or not _hub_rect_w.has_point(Vector2(x, z)):
		var p := _part_at(x, z)
		var l := to_local(p, x, z)
		c = (p["gen"] as WorldActGen).ground_detail(l.x, l.y)
	else:
		var lh := to_local(parts["hub"], x, z)
		var lw := to_local(parts["wilds"], x, z)
		var ch := (parts["hub"]["gen"] as WorldActGen).ground_detail(lh.x, lh.y)
		var cw := (parts["wilds"]["gen"] as WorldActGen).ground_detail(lw.x, lw.y)
		c = cw.lerp(ch, smoothstep(-BLEND_M, BLEND_M, sd))
	if not _road_box.has_point(Vector2(x, z)):
		return c
	var d := _dist_to_segment(Vector3(x, 0, z), cell_center(road_from), cell_center(road_to))
	var half_w := ROAD_WIDTH_CELLS * TILE * 0.5
	if d < half_w + 1.5:
		c.r = maxf(c.r, 0.7 * (1.0 - smoothstep(half_w - 0.8, half_w + 1.5, d)))
	return c


func ground_height(x: float, z: float) -> float:
	var sd := side_distance(x, z)
	if absf(sd) >= BLEND_M or not _hub_rect_w.has_point(Vector2(x, z)):
		var p := _part_at(x, z)
		var l := to_local(p, x, z)
		return (p["gen"] as WorldActGen).ground_height(l.x, l.y)
	var lh := to_local(parts["hub"], x, z)
	var lw := to_local(parts["wilds"], x, z)
	var hh := (parts["hub"]["gen"] as WorldActGen).ground_height(lh.x, lh.y)
	var hw := (parts["wilds"]["gen"] as WorldActGen).ground_height(lw.x, lw.y)
	return lerpf(hw, hh, smoothstep(-BLEND_M, BLEND_M, sd))


func theme() -> Dictionary:
	if parts.has("hub"):
		return (parts["hub"]["gen"] as WorldActGen).theme()
	return {}


## Each zone decorates under a node carrying its transform (local coordinates keep working).
func decorate(world: Node3D, parent: Node3D) -> void:
	for z in ZONES:
		var p: Dictionary = parts[z]
		var n := Node3D.new()
		n.name = "Decor_%s" % z
		var t := to_world(p, Vector3.ZERO)
		n.transform = Transform3D(Basis(Vector3.UP, float(p["rot"]) * PI * 0.5), t)
		parent.add_child(n)
		(p["gen"] as WorldActGen).decorate(world, n)


# ------------------------------------------------------------------ borders

## Line the walkable edges that face open ground with the act's border pieces.
func _add_borders(style: Dictionary) -> void:
	if style.is_empty() or (style.get("segments", {}) as Dictionary).is_empty():
		return
	var min_h := float(style.get("min_prop_height", 0.9))
	var clearance := float(style.get("prop_clearance", 1.0))
	var max_fp := float(style.get("max_footprint", 0.8))
	var solid: Array = style.get("solid_prefixes", [])
	var skip_water := bool(style.get("skip_water", true))
	# Tall props, bucketed (8 m).
	var buckets := {}
	for d in props:
		var info := _model_info_for(String(d["id"]))
		var sc := float(d.get("scale", 1.0))
		if float(info["height"]) * sc < min_h:
			continue
		var full := false
		for pre in solid:
			if String(d["id"]).begins_with(String(pre)):
				full = true
		var pos: Vector3 = d["pos"]
		var key := Vector2i(floori(pos.x / 8.0), floori(pos.z / 8.0))
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append({"pos": pos, "yaw": float(d.get("yaw", 0.0)), "scale": sc, "box": info["box"], "full": full})
	# Candidate edges between walkable cells and open ground (direct array access: this runs over
	# every cell of a big act).
	var edges := {}   # "a|b" corner keys -> {"a": Vector2i, "b": Vector2i, "n": Vector2}
	var w := grid.size.x
	var h := grid.size.y
	var walk := grid.walk
	var fl := grid.floor_cells
	for j in h:
		for i in w:
			var k := j * w + i
			if walk[k] == 0:
				continue
			for dir in 4:
				var ni := i + (1 if dir == 0 else (-1 if dir == 1 else 0))
				var nj := j + (1 if dir == 2 else (-1 if dir == 3 else 0))
				if ni >= 0 and nj >= 0 and ni < w and nj < h:
					var nk := nj * w + ni
					if fl[nk] == 1 or soft.has(Vector2i(ni, nj)):
						continue
				var a: Vector2i
				var b: Vector2i
				var d := Vector2i(ni - i, nj - j)
				if d.x == 1:
					a = Vector2i(i + 1, j)
					b = Vector2i(i + 1, j + 1)
				elif d.x == -1:
					a = Vector2i(i, j)
					b = Vector2i(i, j + 1)
				elif d.y == 1:
					a = Vector2i(i, j + 1)
					b = Vector2i(i + 1, j + 1)
				else:
					a = Vector2i(i, j)
					b = Vector2i(i + 1, j)
				var mid := Vector3((a.x + b.x) * 0.5 * TILE, 0.0, (a.y + b.y) * 0.5 * TILE)
				if skip_water and _water_beyond(mid, Vector2(d)):
					continue
				if _marked_by_prop(mid, buckets, clearance, max_fp):
					continue
				edges["%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]] = {"a": a, "b": b, "n": Vector2(d)}
	for chain in _chain_edges(edges):
		_place_border_chain(chain, style)


func _water_beyond(mid: Vector3, n: Vector2) -> bool:
	var any_area := false
	for wa in water_areas:
		if (wa["rect"] as Rect2).grow(5.0).has_point(Vector2(mid.x, mid.z)):
			any_area = true
			break
	if not any_area:
		return false
	for dist in [1.0, 2.5, 4.0]:
		var q: Vector3 = mid + Vector3(n.x, 0, n.y) * float(dist)
		var lay: Dictionary = _part_at(q.x, q.z)["layout"]
		if not bool(lay.get("has_water", false)):
			continue
		if ground_height(q.x, q.z) < float(lay.get("water_level", -0.35)) + 0.15:
			return true
	return false


func _marked_by_prop(p: Vector3, buckets: Dictionary, clearance: float, max_fp: float) -> bool:
	var key := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dj in range(-2, 3):
		for di in range(-2, 3):
			for e in buckets.get(key + Vector2i(di, dj), []):
				var q: Vector3 = Basis(Vector3.UP, float(e["yaw"])).inverse() * (p - (e["pos"] as Vector3))
				var sc := float(e["scale"])
				var box: Rect2 = e["box"]
				var lo := box.position * sc
				var hi := box.end * sc
				if not bool(e["full"]):
					lo = lo.max(Vector2(-max_fp, -max_fp))
					hi = hi.min(Vector2(max_fp, max_fp))
				var cx := clampf(q.x, lo.x, hi.x)
				var cz := clampf(q.z, lo.y, hi.y)
				if Vector2(q.x - cx, q.z - cz).length() < clearance:
					return true
	return false


func _model_info_for(id: String) -> Dictionary:
	if _model_info.has(id):
		return _model_info[id]
	var info := {"height": 0.0, "box": Rect2(-0.3, -0.3, 0.6, 0.6)}
	if Assets.has_model(id):
		var m := Assets.mesh(id)
		if m != null:
			var bb := m.get_aabb()
			info = {"height": bb.end.y, "box": Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z)}
	_model_info[id] = info
	return info


## Chain edges sharing corners into polylines: [{"pts": [Vector2 corner...], "n": [Vector2 per
## point], "closed": bool}].
func _chain_edges(edges: Dictionary) -> Array:
	var at := {}   # corner -> [edge keys]
	for k in edges:
		for end in ["a", "b"]:
			var c: Vector2i = edges[k][end]
			if not at.has(c):
				at[c] = []
			(at[c] as Array).append(k)
	var used := {}
	var out: Array = []
	for k0 in edges:
		if used.has(k0):
			continue
		used[k0] = true
		var e0: Dictionary = edges[k0]
		var pts: Array = [e0["a"], e0["b"]]
		var ns: Array = [e0["n"], e0["n"]]
		# Grow at the tail, then at the head.
		for dir in [1, -1]:
			while true:
				var end_c: Vector2i = pts[pts.size() - 1] if dir == 1 else pts[0]
				var nxt := ""
				var links: Array = at.get(end_c, [])
				if links.size() != 2:
					break
				for kk in links:
					if not used.has(kk):
						nxt = kk
				if nxt == "":
					break
				used[nxt] = true
				var e: Dictionary = edges[nxt]
				var other: Vector2i = e["b"] if e["a"] == end_c else e["a"]
				if dir == 1:
					ns[ns.size() - 1] = ((ns[ns.size() - 1] as Vector2) + (e["n"] as Vector2)).normalized()
					pts.append(other)
					ns.append(e["n"])
				else:
					ns[0] = ((ns[0] as Vector2) + (e["n"] as Vector2)).normalized()
					pts.push_front(other)
					ns.push_front(e["n"])
		var closed: bool = pts.size() > 3 and pts[0] == pts[pts.size() - 1]
		out.append({"pts": pts, "n": ns, "closed": closed})
	return out


func _place_border_chain(chain: Dictionary, style: Dictionary) -> void:
	var offset := float(style.get("offset", 0.35))
	var L := maxf(float(style.get("length", 2.0)), 0.5)
	var pts: Array = []
	var cpts: Array = chain["pts"]
	var ns: Array = chain["n"]
	for k in cpts.size():
		var c: Vector2i = cpts[k]
		var n: Vector2 = ns[k]
		pts.append(Vector2(c) * TILE + n * offset)
	var closed := bool(chain["closed"])
	if closed:
		pts.remove_at(pts.size() - 1)
	# Chaikin smoothing (2 passes), keeping open ends in place.
	for pass_i in 2:
		if pts.size() < 3:
			break
		var sm: Array = []
		var n_pts := pts.size()
		if not closed:
			sm.append(pts[0])
		var last := n_pts if closed else n_pts - 1
		for k in last:
			var p0: Vector2 = pts[k]
			var p1: Vector2 = pts[(k + 1) % n_pts]
			sm.append(p0.lerp(p1, 0.25))
			sm.append(p0.lerp(p1, 0.75))
		if not closed:
			sm.append(pts[n_pts - 1])
		pts = sm
	if closed and pts.size() > 0:
		pts.append(pts[0])
	# Arc length.
	var total := 0.0
	for k in range(1, pts.size()):
		total += (pts[k] as Vector2).distance_to(pts[k - 1])
	# Tiny islands of non-walkable ground inside open areas get no ring of border pieces.
	if total < L * 0.55 or (closed and total < 14.0):
		return
	var count := maxi(1, roundi(total / L))
	var spacing := total / count
	var sc_rng: Vector2 = style.get("scale", Vector2(1, 1))
	var tint: Color = style.get("tint", Color.WHITE)
	var jitter := float(style.get("yaw_jitter", 0.0))
	var opts := {"cutout": bool(style.get("cutout", false)), "shadows": bool(style.get("shadows", true)), "tint": tint}
	var post_ids: Dictionary = style.get("posts", {})
	var post_every := maxi(1, int(style.get("post_every", 1)))
	# One walk along the polyline (a cursor, linear in the edge length); each piece faces the side
	# with walkable ground (probed on the grid), else keeps the previous piece's facing.
	var cur := {"k": 1, "acc": 0.0}
	var a: Vector2 = pts[0]
	var last_inward := Vector2.ZERO
	for s in count:
		var b := _advance(pts, cur, spacing * (s + 1))
		var mid := (a + b) * 0.5
		var t := (b - a).normalized()
		var yaw := atan2(-t.y, t.x)
		var side := Vector2(-t.y, t.x)
		var inward := last_inward
		if is_walkable_at(Vector3(mid.x + side.x * 1.6, 0.0, mid.y + side.y * 1.6)):
			inward = side
		elif is_walkable_at(Vector3(mid.x - side.x * 1.6, 0.0, mid.y - side.y * 1.6)):
			inward = -side
		if inward == Vector2.ZERO:
			inward = -_normal_near(chain, mid)
		last_inward = inward
		if Vector2(sin(yaw), cos(yaw)).dot(inward) < 0.0:
			yaw += PI
		var sc := rng.randf_range(sc_rng.x, sc_rng.y) * spacing / L
		add_prop(pick(style["segments"]), Vector3(mid.x, 0, mid.y), yaw + rng.randf_range(-jitter, jitter), sc, opts)
		if not post_ids.is_empty() and s % post_every == 0:
			add_prop(pick(post_ids), Vector3(a.x, 0, a.y), yaw, rng.randf_range(sc_rng.x, sc_rng.y), opts)
		a = b
	if not post_ids.is_empty() and not closed:
		var e: Vector2 = pts[pts.size() - 1]
		add_prop(pick(post_ids), Vector3(e.x, 0, e.y), 0.0, rng.randf_range(sc_rng.x, sc_rng.y), opts)


## Move the cursor {"k": point index, "acc": length up to point k-1} along pts to arc length s.
static func _advance(pts: Array, cur: Dictionary, s: float) -> Vector2:
	var k := int(cur["k"])
	var acc := float(cur["acc"])
	while k < pts.size():
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		var l := a.distance_to(b)
		if acc + l >= s:
			cur["k"] = k
			cur["acc"] = acc
			return a.lerp(b, (s - acc) / maxf(l, 0.0001))
		acc += l
		k += 1
	cur["k"] = k
	cur["acc"] = acc
	return pts[pts.size() - 1]


## The outward normal of the chain's corner nearest to a point.
func _normal_near(chain: Dictionary, p: Vector2) -> Vector2:
	var best := Vector2(0, -1)
	var bd := INF
	var cpts: Array = chain["pts"]
	for k in cpts.size():
		var d := (Vector2(cpts[k]) * TILE).distance_squared_to(p)
		if d < bd:
			bd = d
			best = chain["n"][k]
	return best

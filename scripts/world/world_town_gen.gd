class_name WorldTownGen
extends RefCounted
## Layout of Emberfall, the town hub (docs/ARCHITECTURE.md §13): a ~40 x 40 m walkable square
## (cells 2..21 of a 24 x 24 grid) fenced in by forest, with a paved plaza and well in the centre,
## dirt paths, the Dungeon Gate in the north, the Merchant (west), the Stash (east), houses in
## the corners, lamp posts, trees and clutter. Pure data (no nodes). Deterministic. OWNER: world.

const SIZE := 24
const TILE := 2.0
## Walkable interior: cells [INNER_MIN, INNER_MAX] on both axes.
const INNER_MIN := 2
const INNER_MAX := 21
const PATH_DIRT := 1
const PATH_PLAZA := 2

var grid: WorldGrid = null
## Per cell: 0 grass, PATH_DIRT, PATH_PLAZA.
var paths := PackedByteArray()
## Cells whose collision comes from an explicit shape (not a merged box).
var soft := {}
## {"type": "cylinder", "pos": Vector3, "radius": float, "height": float} or
## {"type": "box", "pos": Vector3, "size": Vector3, "yaw": float}
var shapes: Array = []
var houses: Array = []     # {"id", "pos", "yaw"}
var trees: Array = []      # {"id", "pos", "yaw", "scale"}
var lamps: Array = []      # {"pos", "yaw"}
var fences: Array = []     # {"pos", "yaw"}
var props: Array = []      # {"id", "pos", "yaw", "scale", "r" (footprint radius)}
## Footprints of everything solid or reserved (landmarks, lamps, trees in town, clutter, the
## return-portal spot): circles {"id", "pos", "r"} and house rectangles {"id", "rect": Rect2 (XZ)}.
## Decorative bushes / rocks are only placed clear of these.
var keepouts: Array = []
var well := {}
var gate := {}
var merchant := {}
var stall := {}
var stash := {}
var portal_spot := {}
var start := Vector3.ZERO
var rng := RandomNumberGenerator.new()


func generate() -> Dictionary:
	rng.seed = 7741
	grid = WorldGrid.new()
	grid.setup(Vector2i(SIZE, SIZE))
	paths = PackedByteArray()
	paths.resize(SIZE * SIZE)
	for j in SIZE:
		for i in SIZE:
			var c := Vector2i(i, j)
			if i >= INNER_MIN and i <= INNER_MAX and j >= INNER_MIN and j <= INNER_MAX:
				grid.set_floor(c, true)
			else:
				grid.set_void(c)
				# Outside the fence is open land: it hides nothing.
				grid.set_opaque(c, false)
	_paint_paths()
	_place_landmarks()
	_place_houses()
	_place_lamps()
	_place_trees()
	_place_fences()
	_place_clutter()
	grid.rebuild_astar()
	return {
		"grid": grid, "paths": paths, "soft": soft, "shapes": shapes, "houses": houses,
		"trees": trees, "lamps": lamps, "fences": fences, "props": props, "well": well,
		"gate": gate, "merchant": merchant, "stall": stall, "stash": stash,
		"portal_spot": portal_spot, "start": start, "keepouts": keepouts,
	}


func _cell_pos(i: float, j: float) -> Vector3:
	return Vector3(i * TILE, 0.0, j * TILE)


func _solid(c: Vector2i, opaque: bool = false, is_soft: bool = false) -> void:
	grid.set_walkable(c, false)
	if opaque:
		grid.set_opaque(c, true)
	if is_soft:
		soft[c] = true


func _solid_rect(r: Rect2i, opaque: bool = false, is_soft: bool = false) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			_solid(Vector2i(i, j), opaque, is_soft)


func _paint(r: Rect2i, kind: int) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			if i >= 0 and j >= 0 and i < SIZE and j < SIZE:
				var k := j * SIZE + i
				paths[k] = maxi(paths[k], kind)


func _paint_paths() -> void:
	_paint(Rect2i(11, 3, 2, 21), PATH_DIRT)    # north gate -> south road
	_paint(Rect2i(3, 11, 17, 2), PATH_DIRT)    # merchant (west) -> stash (east)
	_paint(Rect2i(8, 8, 8, 8), PATH_PLAZA)     # paved plaza around the well
	_paint(Rect2i(10, 4, 4, 2), PATH_DIRT)     # clearing in front of the gate
	_paint(Rect2i(6, 6, 2, 5), PATH_DIRT)      # spur to the NW house
	_paint(Rect2i(16, 6, 2, 5), PATH_DIRT)     # spur to the NE house
	_paint(Rect2i(6, 13, 2, 5), PATH_DIRT)     # spur to the SW house
	_paint(Rect2i(16, 13, 2, 5), PATH_DIRT)    # spur to the SE house


func _place_landmarks() -> void:
	# Player start: south of the well, looking north at the plaza and the gate.
	start = _cell_pos(12.0, 17.0)
	# Well in the middle of the plaza (2 x 2 cells).
	well = {"pos": _cell_pos(12.0, 12.0), "yaw": 0.0}
	_solid_rect(Rect2i(11, 11, 2, 2), false, true)
	shapes.append({"type": "cylinder", "pos": _cell_pos(12.0, 12.0), "radius": 1.35, "height": 2.0})
	# Dungeon Gate at the north end of the road, facing the town (+Z).
	gate = {"pos": _cell_pos(12.0, 2.5), "yaw": 0.0}
	_solid_rect(Rect2i(11, 2, 2, 2), true, true)
	shapes.append({"type": "box", "pos": _cell_pos(12.0, 2.5), "size": Vector3(4.2, 3.0, 4.2), "yaw": 0.0})
	# Merchant in front of the market stall at the west end of the road.
	stall = {"pos": _cell_pos(6.0, 12.0), "yaw": PI * 0.5}
	_solid_rect(Rect2i(5, 11, 2, 2), false, true)
	shapes.append({"type": "box", "pos": _cell_pos(6.0, 12.0), "size": Vector3(2.2, 2.0, 2.8), "yaw": 0.0})
	merchant = {"pos": _cell_pos(7.5, 12.0), "yaw": PI * 0.5}
	_solid_rect(Rect2i(7, 11, 1, 2), false, true)
	shapes.append({"type": "cylinder", "pos": _cell_pos(7.5, 12.0), "radius": 0.45, "height": 2.0})
	# Stash chest at the east end of the road.
	stash = {"pos": _cell_pos(17.6, 12.0), "yaw": -PI * 0.5}
	_solid_rect(Rect2i(17, 11, 1, 2), false, true)
	shapes.append({"type": "box", "pos": _cell_pos(17.6, 12.0), "size": Vector3(1.0, 1.4, 1.6), "yaw": 0.0})
	# Where the "Return to Depth N" portal opens (east of the road, below the gate).
	portal_spot = {"pos": _cell_pos(15.0, 6.5), "yaw": 0.0}
	_keep("start", start, 1.0)
	_keep("town_well", well["pos"], 1.3)
	_keep("env_waypoint", gate["pos"], 3.2)
	_keep("town_stall", stall["pos"], 1.9)
	_keep("char_merchant", merchant["pos"], 0.6)
	_keep("town_stash", stash["pos"], 0.85)
	_keep("portal", portal_spot["pos"], 1.9)


func _keep(id: String, pos: Vector3, r: float) -> void:
	keepouts.append({"id": id, "pos": pos, "r": r})


## True if a round footprint (pos, r) stays clear of every keep-out (and of `others`: circles
## {"pos", "r"} that may touch a little).
func is_clear(pos: Vector3, r: float, others: Array = []) -> bool:
	for k in keepouts:
		if k.has("rect"):
			var rect: Rect2 = k["rect"]
			var q := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.z, rect.position.y, rect.end.y))
			if q.distance_to(Vector2(pos.x, pos.z)) < r:
				return false
		elif (k["pos"] as Vector3).distance_to(pos) < float(k["r"]) + r:
			return false
	for o in others:
		if (o["pos"] as Vector3).distance_to(pos) < (float(o["r"]) + r) * 0.8:
			return false
	return true


func _place_houses() -> void:
	var defs := [
		["town_house_a", Rect2i(3, 3, 3, 3), 0.0],
		["town_house_b", Rect2i(18, 3, 3, 3), 0.0],
		["town_house_c", Rect2i(3, 17, 3, 3), PI * 0.5],
		["town_house_a", Rect2i(18, 17, 3, 3), -PI * 0.5],
	]
	for d in defs:
		var r: Rect2i = d[1]
		houses.append({"id": d[0], "pos": _cell_pos(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5), "yaw": d[2]})
		_solid_rect(r, true)
		keepouts.append({"id": d[0], "rect": Rect2(r.position.x * TILE - 0.1, r.position.y * TILE - 0.1, r.size.x * TILE + 0.2, r.size.y * TILE + 0.2)})


func _place_lamps() -> void:
	for c in [Vector2i(9, 7), Vector2i(14, 7), Vector2i(9, 16), Vector2i(14, 16), Vector2i(9, 3), Vector2i(14, 3), Vector2i(4, 10), Vector2i(19, 13)]:
		var cell: Vector2i = c
		lamps.append({"pos": _cell_pos(cell.x + 0.5, cell.y + 0.5), "yaw": 0.0})
		_keep("town_lamp", _cell_pos(cell.x + 0.5, cell.y + 0.5), 0.35)
		_solid(cell, false, true)
		shapes.append({"type": "cylinder", "pos": _cell_pos(cell.x + 0.5, cell.y + 0.5), "radius": 0.25, "height": 3.0})


func _place_trees() -> void:
	# Inside the town (solid).
	for c in [Vector2i(7, 2), Vector2i(16, 2), Vector2i(2, 8), Vector2i(21, 9), Vector2i(2, 14), Vector2i(21, 15), Vector2i(9, 20), Vector2i(14, 21), Vector2i(8, 17)]:
		var cell: Vector2i = c
		trees.append({"id": "town_tree_a" if rng.randf() < 0.5 else "town_tree_b", "pos": _cell_pos(cell.x + 0.5, cell.y + 0.5), "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.9, 1.15)})
		_keep("town_tree", _cell_pos(cell.x + 0.5, cell.y + 0.5), 1.3)
		_solid(cell, false, true)
		shapes.append({"type": "cylinder", "pos": _cell_pos(cell.x + 0.5, cell.y + 0.5), "radius": 0.45, "height": 3.0})
	# The forest around the town (outside the fence, decoration only).
	var placed: Array[Vector3] = []
	var lo := -18.0
	var hi := SIZE * TILE + 18.0
	for t in 700:
		var p := Vector3(rng.randf_range(lo, hi), 0.0, rng.randf_range(lo, hi))
		var inside_x := p.x > INNER_MIN * TILE - 1.0 and p.x < (INNER_MAX + 1) * TILE + 1.0
		var inside_z := p.z > INNER_MIN * TILE - 1.0 and p.z < (INNER_MAX + 1) * TILE + 1.0
		if inside_x and inside_z:
			continue
		# Keep the road south and the gate north readable.
		if absf(p.x - 24.0) < 3.0 and p.z > 44.0 and p.z < 56.0:
			continue
		var ok := true
		for q in placed:
			if q.distance_squared_to(p) < 6.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		trees.append({"id": "town_tree_a" if rng.randf() < 0.55 else "town_tree_b", "pos": p, "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.85, 1.35)})
		if placed.size() >= 150:
			break


func _place_fences() -> void:
	var lo := INNER_MIN * TILE - 0.35
	var hi := (INNER_MAX + 1) * TILE + 0.35
	for i in range(INNER_MIN, INNER_MAX + 1):
		var x := (i + 0.5) * TILE
		# North side: open behind the gate.
		if i < 10 or i > 13:
			fences.append({"pos": Vector3(x, 0, lo), "yaw": 0.0})
		# South side: open where the road leaves town.
		if i < 11 or i > 12:
			fences.append({"pos": Vector3(x, 0, hi), "yaw": 0.0})
	for j in range(INNER_MIN, INNER_MAX + 1):
		var z := (j + 0.5) * TILE
		fences.append({"pos": Vector3(lo, 0, z), "yaw": PI * 0.5})
		fences.append({"pos": Vector3(hi, 0, z), "yaw": PI * 0.5})


func _place_clutter() -> void:
	# Market: a cart south of the stall, barrels and crates stored north of it.
	props.append({"id": "town_cart", "pos": _cell_pos(4.5, 15.0), "yaw": PI * 0.5 + 0.2, "scale": 1.0, "r": 1.6})
	_keep("town_cart", _cell_pos(4.5, 15.0), 1.6)
	_solid_rect(Rect2i(3, 14, 3, 2), false, true)
	shapes.append({"type": "box", "pos": _cell_pos(4.5, 15.0), "size": Vector3(1.6, 1.3, 2.9), "yaw": PI * 0.5 + 0.2})
	# Barrels and crates block their cell (none on a path) and get a small collision cylinder.
	for p in [[_cell_pos(5.2, 9.6), "env_barrel"], [_cell_pos(4.6, 8.7), "env_crate"], [_cell_pos(5.5, 8.5), "env_crate"],
			[_cell_pos(19.3, 10.4), "env_barrel"], [_cell_pos(20.4, 13.9), "env_crate"], [_cell_pos(9.2, 5.0), "env_barrel"],
			[_cell_pos(15.4, 17.6), "env_crate"], [_cell_pos(15.0, 18.3), "env_barrel"]]:
		var pos: Vector3 = p[0]
		var id: String = p[1]
		var r := 0.55 if id == "env_crate" else 0.34
		props.append({"id": id, "pos": pos, "yaw": rng.randf() * TAU, "scale": 0.95, "r": r})
		_keep(id, pos, r)
		_solid(grid.world_to_cell(pos), false, true)
		shapes.append({"type": "cylinder", "pos": pos, "radius": 0.42 if id == "env_crate" else 0.34, "height": 1.0})
	# Bushes and rocks along the fence and between houses: decoration only (no collision), kept
	# off the paths and clear of the gate, lamps, stall, stash, houses, trees, clutter and each other.
	var deco: Array = []
	for t in 34:
		var edge := rng.randi_range(0, 3)
		var along := rng.randf_range(INNER_MIN * TILE + 1.0, (INNER_MAX + 1) * TILE - 1.0)
		var inset := rng.randf_range(0.8, 1.4)
		var p2 := Vector3.ZERO
		match edge:
			0:
				p2 = Vector3(along, 0, INNER_MIN * TILE + inset)
			1:
				p2 = Vector3(along, 0, (INNER_MAX + 1) * TILE - inset)
			2:
				p2 = Vector3(INNER_MIN * TILE + inset, 0, along)
			3:
				p2 = Vector3((INNER_MAX + 1) * TILE - inset, 0, along)
		var id := "town_bush" if rng.randf() < 0.75 else "town_rock"
		var yaw := rng.randf() * TAU
		var sc := rng.randf_range(0.8, 1.1)
		var c := grid.world_to_cell(p2)
		if paths[c.y * SIZE + c.x] != 0 or not grid.is_walkable_cell(c):
			continue
		var r2 := 0.75 * sc
		if not is_clear(p2, r2, deco):
			continue
		deco.append({"pos": p2, "r": r2})
		props.append({"id": id, "pos": p2, "yaw": yaw, "scale": sc, "r": r2})
	for p3 in [_cell_pos(6.8, 5.2), _cell_pos(17.2, 5.4), _cell_pos(2.8, 16.0), _cell_pos(21.2, 16.4), _cell_pos(10.5, 18.8), _cell_pos(13.8, 19.6)]:
		var yaw3 := rng.randf() * TAU
		var sc3 := rng.randf_range(0.9, 1.2)
		var r3 := 0.75 * sc3
		if not is_clear(p3, r3, deco):
			continue
		deco.append({"pos": p3, "r": r3})
		props.append({"id": "town_bush", "pos": p3, "yaw": yaw3, "scale": sc3, "r": r3})

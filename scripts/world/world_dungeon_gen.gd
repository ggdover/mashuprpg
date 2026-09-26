class_name WorldDungeonGen
extends RefCounted
## Seeded dungeon layout generator (docs/ARCHITECTURE.md §13). Produces pure data (no nodes):
## the WorldGrid plus rooms, start / boss room, spawn groups, chests, pillars, lava, torches,
## lights and debris. Same (depth, seed, theme) -> identical layout. OWNER: world.
##
## Algorithm: rooms (5-12 cells) jittered in a 4x4 sector grid -> minimum spanning tree + a few
## loops of 2-3 cell wide L corridors -> "cave" rooms are elliptic, corridors wobble and a
## cellular automaton roughens the edges -> flood fill keeps one connected region -> start room
## by a double sweep (farthest from a random room), boss room = farthest by A* path distance ->
## blocking props (pillars / rocks / lava / chests / shrine; each keeps connectivity locally) ->
## spawn groups, light sources and debris.

const CELL_VOID := 0
const CELL_FLOOR := 1
const CELL_LAVA := 2
const TILE := 2.0

## Spawn rules (§13).
const MIN_SPAWN_DIST_FROM_START := 12.0
const MAX_MONSTERS := 70
## OmniLight3Ds created by build(). 3 are left for the two exit portals and one town portal
## (World.spawn_exit_portals / spawn_town_portal), so the total stays <= World.MAX_LIGHTS (20).
const MAX_BUILD_LIGHTS := 17

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var rng := RandomNumberGenerator.new()
var size := 44
var depth := 1
var theme := "crypt"
var grid: WorldGrid = null
## CELL_* per cell.
var cells := PackedByteArray()
## {"rect": Rect2i, "center": Vector2i (walkable anchor cell), "kind": "start"|"boss"|"room"}
var rooms: Array = []
var start_room := 0
var boss_room := 0
var start_cell := Vector2i.ZERO
var portal_cell := Vector2i.ZERO
var pillars: Array = []      # {"cell": Vector2i, "kind": "pillar"|"rock"}
var lava_pools: Array = []   # {"rect": Rect2i}
var chests: Array = []       # {"cell": Vector2i, "facing": Vector2i, "tier": int}
var shrine: Dictionary = {}  # {"cell": Vector2i, "kind": String}
var spawn_groups: Array = []
var torches: Array = []      # {"cell": Vector2i (wall), "dir": Vector2i (towards floor)}
var crystals: Array = []     # {"pos": Vector3, "yaw": float, "scale": float}
var braziers: Array = []     # {"pos": Vector3}
## Light sources (torches, crystals, braziers, lava): {"pos", "color", "energy", "range", "flicker"}.
## The World lights the light_pool_size ones nearest the camera focus (moving pool).
var light_candidates: Array = []
var light_pool_size := 0
var glows: Array = []        # {"pos": Vector3, "radius": float, "color": Color}
var debris: Array = []       # {"id": String, "pos": Vector3, "yaw": float, "scale": float}
var wall_rocks: Array = []   # {"id": String, "pos": Vector3, "yaw": float, "scale": float}
var _occupied := {}          # Vector2i -> true (cells reserved by props / portal)


## Grid size for a depth: 44x44 at depth 1 growing to 64x64 at depth 10.
static func dungeon_size(p_depth: int) -> int:
	var d := clampi(p_depth, 1, 10)
	return 44 + roundi(float(d - 1) * 20.0 / 9.0)


func generate(p_depth: int, p_seed: int, p_theme: String) -> Dictionary:
	depth = maxi(p_depth, 1)
	theme = p_theme
	rng.seed = p_seed
	size = dungeon_size(depth)
	cells = PackedByteArray()
	cells.resize(size * size)
	_place_rooms()
	for r in rooms:
		_carve_room(r["rect"])
	_connect_rooms()
	if theme == "cave":
		_roughen_cave()
	_clear_border()
	_build_grid()
	_keep_main_region()
	_pick_start_and_boss()
	_grow_boss_room()
	_place_blocking_props()
	_finalize_start_and_boss()
	_place_spawn_groups()
	_place_lighting()
	_place_debris()
	return to_layout()


func to_layout() -> Dictionary:
	var room_out: Array = []
	for r in rooms:
		room_out.append({"rect": r["rect"], "center": grid.cell_center(r["center"]), "kind": r["kind"]})
	return {
		"size": Vector2i(size, size), "grid": grid, "cells": cells, "rooms": room_out,
		"start_room": start_room, "boss_room": boss_room,
		"start": grid.cell_center(start_cell), "start_cell": start_cell,
		"portal_cell": portal_cell, "pillars": pillars, "lava": lava_pools, "chests": chests,
		"shrine": shrine, "spawn_groups": spawn_groups, "torches": torches, "crystals": crystals,
		"braziers": braziers, "light_candidates": light_candidates,
		"light_pool_size": light_pool_size, "glows": glows, "debris": debris,
		"wall_rocks": wall_rocks,
	}


# ------------------------------------------------------------------ helpers

func _k(c: Vector2i) -> int:
	return c.y * size + c.x


func _inside(c: Vector2i) -> bool:
	return c.x >= 1 and c.y >= 1 and c.x < size - 1 and c.y < size - 1


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _carve(c: Vector2i) -> void:
	if _inside(c):
		cells[_k(c)] = CELL_FLOOR


func _walk(c: Vector2i) -> bool:
	return grid.is_walkable_cell(c)


func _room_at(c: Vector2i) -> int:
	for i in rooms.size():
		if (rooms[i]["rect"] as Rect2i).has_point(c):
			return i
	return -1


# ------------------------------------------------------------------ rooms & corridors

func _place_rooms() -> void:
	rooms.clear()
	var cols := 4
	var rows := 4
	var t := clampf(float(size - 44) / 20.0, 0.0, 1.0)
	var total := clampi(rng.randi_range(10, 12) + roundi(t * 4.0), 10, cols * rows)
	var sectors: Array = []
	for r in rows:
		for c in cols:
			sectors.append(Vector2i(c, r))
	_shuffle(sectors)
	var interior := size - 2
	for n in total:
		var s: Vector2i = sectors[n]
		var sx0 := 1 + s.x * interior / cols
		var sx1 := 1 + (s.x + 1) * interior / cols
		var sy0 := 1 + s.y * interior / rows
		var sy1 := 1 + (s.y + 1) * interior / rows
		var max_w := mini(12, sx1 - sx0 - 2)
		var max_h := mini(12, sy1 - sy0 - 2)
		var w := rng.randi_range(5, maxi(5, max_w))
		var h := rng.randi_range(5, maxi(5, max_h))
		# Occasionally a long hall.
		if rng.randf() < 0.2:
			if rng.randf() < 0.5:
				w = maxi(5, max_w)
				h = 5
			else:
				h = maxi(5, max_h)
				w = 5
		var x := rng.randi_range(sx0 + 1, maxi(sx0 + 1, sx1 - 1 - w))
		var y := rng.randi_range(sy0 + 1, maxi(sy0 + 1, sy1 - 1 - h))
		var rect := Rect2i(x, y, w, h)
		rooms.append({"rect": rect, "center": rect.get_center(), "kind": "room", "sector": s})


func _carve_room(rect: Rect2i) -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	var rx := rect.size.x * 0.5
	var ry := rect.size.y * 0.5
	for j in range(rect.position.y, rect.end.y):
		for i in range(rect.position.x, rect.end.x):
			if theme == "cave":
				var dx := (i + 0.5 - cx) / rx
				var dy := (j + 0.5 - cy) / ry
				var limit := 1.0 + rng.randf_range(-0.12, 0.2)
				# Keep the centre cross carved so corridors always meet the room.
				if dx * dx + dy * dy > limit and i != int(cx) and j != int(cy):
					continue
			_carve(Vector2i(i, j))


func _connect_rooms() -> void:
	var n := rooms.size()
	var centers: Array[Vector2] = []
	for r in rooms:
		centers.append(Vector2(r["center"]))
	var in_tree: Array[int] = [0]
	var edges := {}
	while in_tree.size() < n:
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in in_tree:
			for b in n:
				if b in in_tree:
					continue
				var d := centers[a].distance_squared_to(centers[b])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		in_tree.append(best_b)
		edges[Vector2i(mini(best_a, best_b), maxi(best_a, best_b))] = true
	# A few loops: connect some rooms to one of their two nearest neighbours.
	for a in n:
		var order: Array = []
		for b in n:
			if b != a:
				order.append([centers[a].distance_squared_to(centers[b]), b])
		order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for k in mini(2, order.size()):
			var b2: int = order[k][1]
			var key := Vector2i(mini(a, b2), maxi(a, b2))
			if not edges.has(key) and rng.randf() < 0.22:
				edges[key] = true
	var keys := edges.keys()
	keys.sort()
	for e in keys:
		var ev: Vector2i = e
		var width := 3 if rng.randf() < 0.3 else 2
		_carve_corridor(rooms[ev.x]["center"], rooms[ev.y]["center"], width)


func _carve_corridor(a: Vector2i, b: Vector2i, width: int) -> void:
	var corner := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	_carve_line(a, corner, width)
	_carve_line(corner, b, width)


func _carve_line(p: Vector2i, q: Vector2i, width: int) -> void:
	var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
	var c := p
	var wobble := 0
	var guard := 0
	while guard < 400:
		guard += 1
		var w := width
		if theme == "cave":
			if rng.randf() < 0.25:
				wobble = clampi(wobble + (1 if rng.randf() < 0.5 else -1), -1, 1)
			w = 2 if rng.randf() < 0.5 else 3
		var lo := -(w - 1) / 2 + wobble
		for a in range(lo, lo + w):
			for b in range(-(w - 1) / 2, -(w - 1) / 2 + w):
				_carve(c + Vector2i(a, b))
		if c == q:
			break
		c += step


func _roughen_cave() -> void:
	var fixed := cells.duplicate()
	var band := PackedByteArray()
	band.resize(size * size)
	for j in range(1, size - 1):
		for i in range(1, size - 1):
			if fixed[j * size + i] == CELL_FLOOR:
				continue
			var near := false
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var c := Vector2i(i + di, j + dj)
					if _inside(c) and fixed[_k(c)] == CELL_FLOOR:
						near = true
			if near:
				band[j * size + i] = 1
				if rng.randf() < 0.5:
					cells[j * size + i] = CELL_FLOOR
	for it in 3:
		var nxt := cells.duplicate()
		for j in range(1, size - 1):
			for i in range(1, size - 1):
				var k := j * size + i
				if fixed[k] == CELL_FLOOR or band[k] == 0:
					continue
				var cnt := 0
				for d in DIRS8:
					if cells[_k(Vector2i(i, j) + d)] == CELL_FLOOR:
						cnt += 1
				if cells[k] == CELL_FLOOR:
					nxt[k] = CELL_FLOOR if cnt >= 4 else CELL_VOID
				else:
					nxt[k] = CELL_FLOOR if cnt >= 5 else CELL_VOID
		cells = nxt


func _clear_border() -> void:
	for i in size:
		cells[_k(Vector2i(i, 0))] = CELL_VOID
		cells[_k(Vector2i(i, size - 1))] = CELL_VOID
		cells[_k(Vector2i(0, i))] = CELL_VOID
		cells[_k(Vector2i(size - 1, i))] = CELL_VOID


func _build_grid() -> void:
	grid = WorldGrid.new()
	grid.setup(Vector2i(size, size))
	for j in size:
		for i in size:
			var c := Vector2i(i, j)
			if cells[_k(c)] == CELL_FLOOR:
				grid.set_floor(c, true)
			else:
				grid.set_void(c)


## Flood fill from the first room; everything unreachable becomes void (cave noise islands).
func _keep_main_region() -> void:
	var seen := grid.flood_walkable(rooms[0]["center"])
	for k in cells.size():
		if cells[k] == CELL_FLOOR and seen[k] == 0:
			cells[k] = CELL_VOID
			grid.set_void(Vector2i(k % size, k / size))
	for r in rooms:
		r["center"] = grid.nearest_walkable_cell(r["center"])
	grid.rebuild_astar()


func _room_distances(from_cell: Vector2i) -> Array[float]:
	var out: Array[float] = []
	for r in rooms:
		out.append(grid.cell_path_length(from_cell, r["center"]))
	return out


func _argmax(values: Array[float], exclude: int) -> int:
	var best := -1
	var best_v := -1.0
	for i in values.size():
		if i == exclude or is_inf(values[i]):
			continue
		if values[i] > best_v:
			best_v = values[i]
			best = i
	return best


func _pick_start_and_boss() -> void:
	var r0 := rng.randi_range(0, rooms.size() - 1)
	start_room = _argmax(_room_distances(rooms[r0]["center"]), -1)
	if start_room < 0:
		start_room = r0
	boss_room = _argmax(_room_distances(rooms[start_room]["center"]), start_room)
	if boss_room < 0:
		boss_room = (start_room + 1) % rooms.size()


## Bosses need space: widen a small boss room (without touching other rooms).
func _grow_boss_room() -> void:
	var rect: Rect2i = rooms[boss_room]["rect"]
	var target := 9
	var changed := false
	for it in 8:
		var grew := false
		for side in 4:
			if (side < 2 and rect.size.x >= target) or (side >= 2 and rect.size.y >= target):
				continue
			var cand := rect
			match side:
				0:
					cand = Rect2i(rect.position.x - 1, rect.position.y, rect.size.x + 1, rect.size.y)
				1:
					cand = Rect2i(rect.position.x, rect.position.y, rect.size.x + 1, rect.size.y)
				2:
					cand = Rect2i(rect.position.x, rect.position.y - 1, rect.size.x, rect.size.y + 1)
				3:
					cand = Rect2i(rect.position.x, rect.position.y, rect.size.x, rect.size.y + 1)
			if cand.position.x < 1 or cand.position.y < 1 or cand.end.x > size - 1 or cand.end.y > size - 1:
				continue
			var blocked := false
			for i in rooms.size():
				if i != boss_room and (rooms[i]["rect"] as Rect2i).grow(1).intersects(cand):
					blocked = true
					break
			if blocked:
				continue
			rect = cand
			grew = true
			changed = true
		if not grew:
			break
	if not changed:
		return
	rooms[boss_room]["rect"] = rect
	for j in range(rect.position.y, rect.end.y):
		for i in range(rect.position.x, rect.end.x):
			var c := Vector2i(i, j)
			if cells[_k(c)] != CELL_FLOOR:
				cells[_k(c)] = CELL_FLOOR
				grid.set_floor(c, true)
	rooms[boss_room]["center"] = grid.nearest_walkable_cell(rect.get_center())
	grid.rebuild_astar()


# ------------------------------------------------------------------ blocking props

## A cell can hold a solid prop without breaking connectivity if all 8 neighbours are walkable
## (they form a 4-connected ring around it).
func _ring_walkable(c: Vector2i) -> bool:
	if not _walk(c):
		return false
	for d in DIRS8:
		if not _walk(c + d):
			return false
	return true


func _block(c: Vector2i) -> void:
	grid.set_walkable(c, false)
	_occupied[c] = true


func _place_blocking_props() -> void:
	_occupied.clear()
	var sc: Vector2i = rooms[start_room]["center"]
	# Keep the start area free.
	for dj in range(-2, 3):
		for di in range(-2, 3):
			_occupied[sc + Vector2i(di, dj)] = true
	# Lava first (inferno), so pillars fit around the pools.
	if theme == "inferno":
		for ri in rooms.size():
			var lrect: Rect2i = rooms[ri]["rect"]
			if ri != start_room and ri != boss_room and lrect.size.x >= 8 and lrect.size.y >= 8 and rng.randf() < 0.8:
				_place_lava_pool(lrect)
	for ri in rooms.size():
		if ri == start_room:
			continue
		var rect: Rect2i = rooms[ri]["rect"]
		if theme == "cave":
			_place_cave_rocks(ri, rect)
		elif rect.size.x >= 8 and rect.size.y >= 8:
			var inset_x := 3 if rect.size.x >= 11 else 2
			var inset_y := 3 if rect.size.y >= 11 else 2
			var pts: Array[Vector2i] = [
				Vector2i(rect.position.x + inset_x, rect.position.y + inset_y),
				Vector2i(rect.end.x - 1 - inset_x, rect.position.y + inset_y),
				Vector2i(rect.position.x + inset_x, rect.end.y - 1 - inset_y),
				Vector2i(rect.end.x - 1 - inset_x, rect.end.y - 1 - inset_y),
			]
			for p in pts:
				if not _occupied.has(p) and _ring_walkable(p):
					_block(p)
					pillars.append({"cell": p, "kind": "pillar"})
	_place_chests()
	_place_shrine()
	grid.rebuild_astar()


func _place_cave_rocks(_ri: int, rect: Rect2i) -> void:
	var area := rect.size.x * rect.size.y
	if area < 40:
		return
	var n := rng.randi_range(1, 2 + area / 60)
	for t in n * 4:
		if n <= 0:
			break
		var p := Vector2i(rng.randi_range(rect.position.x + 2, rect.end.x - 3), rng.randi_range(rect.position.y + 2, rect.end.y - 3))
		if _occupied.has(p) or not _ring_walkable(p):
			continue
		_block(p)
		pillars.append({"cell": p, "kind": "rock"})
		n -= 1


func _place_lava_pool(rect: Rect2i) -> void:
	var pw := rng.randi_range(2, maxi(2, mini(4, rect.size.x - 6)))
	var ph := rng.randi_range(2, maxi(2, mini(3, rect.size.y - 6)))
	if rect.size.x - pw < 6 or rect.size.y - ph < 6:
		return
	var x0 := rng.randi_range(rect.position.x + 3, rect.end.x - 3 - pw)
	var y0 := rng.randi_range(rect.position.y + 3, rect.end.y - 3 - ph)
	var pool := Rect2i(x0, y0, pw, ph)
	# The ring around the pool (and the pool itself) must be free walkable floor.
	for j in range(pool.position.y - 1, pool.end.y + 1):
		for i in range(pool.position.x - 1, pool.end.x + 1):
			var c := Vector2i(i, j)
			if not _walk(c) or _occupied.has(c):
				return
	for j in range(pool.position.y, pool.end.y):
		for i in range(pool.position.x, pool.end.x):
			var c2 := Vector2i(i, j)
			cells[_k(c2)] = CELL_LAVA
			grid.floor_cells[grid.idx(c2)] = 0
			grid.walk[grid.idx(c2)] = 0
			grid.opaque[grid.idx(c2)] = 0
			_occupied[c2] = true
	for j in range(pool.position.y - 1, pool.end.y + 1):
		for i in range(pool.position.x - 1, pool.end.x + 1):
			_occupied[Vector2i(i, j)] = true
	lava_pools.append({"rect": pool})


## Chest spot: floor cell against a wall (back), free cells left/right and the three in front.
func _chest_spot_ok(c: Vector2i, back: Vector2i) -> bool:
	if not _walk(c) or _occupied.has(c) or _walk(c + back):
		return false
	if cells[_k(c + back)] != CELL_VOID:
		return false
	var front := -back
	var side := Vector2i(back.y, back.x)
	for p in [c + side, c - side, c + front, c + front + side, c + front - side]:
		if not _walk(p) or _occupied.has(p):
			return false
	return true


func _place_chests() -> void:
	var want := rng.randi_range(2, 4)
	var order: Array = []
	for i in rooms.size():
		if i != start_room and i != boss_room:
			order.append(i)
	_shuffle(order)
	var start_pos := grid.cell_center(rooms[start_room]["center"])
	var tries := 0
	while chests.size() < want and tries < order.size() * 2:
		var ri: int = order[tries % order.size()]
		tries += 1
		var rect: Rect2i = rooms[ri]["rect"]
		var spots: Array = []
		for j in range(rect.position.y, rect.end.y):
			for i in range(rect.position.x, rect.end.x):
				var c := Vector2i(i, j)
				if grid.cell_center(c).distance_to(start_pos) < 10.0:
					continue
				for back in DIRS4:
					if _chest_spot_ok(c, back):
						spots.append([c, back])
		if spots.is_empty():
			continue
		var pick: Array = spots[rng.randi_range(0, spots.size() - 1)]
		var cell: Vector2i = pick[0]
		var back_dir: Vector2i = pick[1]
		_block(cell)
		for d in DIRS8:
			_occupied[cell + d] = true
		var tier := 1 if rng.randf() < 0.2 + 0.01 * depth else 0
		chests.append({"cell": cell, "facing": -back_dir, "tier": tier})


func _place_shrine() -> void:
	if rng.randf() >= 0.55:
		return
	var order: Array = []
	for i in rooms.size():
		if i != start_room and i != boss_room:
			order.append(i)
	_shuffle(order)
	var kinds := ["fury", "swiftness", "fortitude", "arcana"]
	for ri in order:
		var rect: Rect2i = rooms[ri]["rect"]
		var c: Vector2i = rooms[ri]["center"]
		var cands: Array[Vector2i] = [c, c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]
		for p in cands:
			if rect.has_point(p) and not _occupied.has(p) and _ring_walkable(p):
				_block(p)
				for d in DIRS8:
					_occupied[p + d] = true
				shrine = {"cell": p, "kind": kinds[rng.randi_range(0, kinds.size() - 1)]}
				return


## Recompute path distances on the final grid: boss room = farthest room from the start.
func _finalize_start_and_boss() -> void:
	# Props may sit on a room centre: re-anchor every room on its nearest walkable cell.
	for r in rooms:
		r["center"] = grid.nearest_walkable_cell(r["center"])
	start_cell = rooms[start_room]["center"]
	var dists := _room_distances(start_cell)
	var b := _argmax(dists, start_room)
	if b >= 0:
		boss_room = b
	for i in rooms.size():
		rooms[i]["kind"] = "room"
	rooms[start_room]["kind"] = "start"
	rooms[boss_room]["kind"] = "boss"
	# Portal back to town: 2 cells north of the start (towards the top of the screen).
	portal_cell = start_cell
	for off in [Vector2i(0, -2), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(0, -1), Vector2i(1, -1)]:
		var p: Vector2i = start_cell + off
		if _walk(p):
			portal_cell = p
			break
	_occupied[portal_cell] = true
	_occupied[start_cell] = true


# ------------------------------------------------------------------ spawns

func _pick_spot(cands: Array, start_pos: Vector3, radius: float, min_sep: float) -> Variant:
	var ok: Array = []
	for c in cands:
		var p := grid.cell_center(c)
		if p.distance_to(start_pos) < MIN_SPAWN_DIST_FROM_START + radius:
			continue
		var clear := true
		for g in spawn_groups:
			if (g["position"] as Vector3).distance_to(p) < min_sep:
				clear = false
				break
		if clear:
			ok.append(p)
	if ok.is_empty():
		return null
	var pos: Vector3 = ok[rng.randi_range(0, ok.size() - 1)]
	# Jitter inside the cell.
	pos += Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
	return pos


func _room_cells(ri: int) -> Array:
	var rect: Rect2i = rooms[ri]["rect"]
	var out: Array = []
	for j in range(rect.position.y + 1, rect.end.y - 1):
		for i in range(rect.position.x + 1, rect.end.x - 1):
			var c := Vector2i(i, j)
			if _walk(c):
				out.append(c)
	return out


func _corridor_cells() -> Array:
	var out: Array = []
	for j in range(1, size - 1):
		for i in range(1, size - 1):
			var c := Vector2i(i, j)
			if not _walk(c) or _room_at(c) >= 0:
				continue
			var open := true
			for d in DIRS4:
				if not _walk(c + d):
					open = false
					break
			if open:
				out.append(c)
	return out


func _add_group(kind: String, pos: Vector3, count: int, room: int) -> void:
	var radius := 1.0
	if kind == "pack":
		radius = 2.0 + 0.25 * count
	elif kind == "rare_pack":
		radius = 3.5
	spawn_groups.append({"position": pos, "radius": radius, "kind": kind, "count": count, "room": room})


func _place_spawn_groups() -> void:
	spawn_groups.clear()
	var start_pos := grid.cell_center(start_cell)
	# Boss first (the boss room is never shared).
	_add_group("boss", grid.cell_center(rooms[boss_room]["center"]), 1, boss_room)
	var eligible: Array = []
	for i in rooms.size():
		if i != start_room and i != boss_room:
			eligible.append(i)
	_shuffle(eligible)
	var n_packs := clampi(roundi(eligible.size() * 1.2), 8, 12)
	# Rare packs prefer rooms far from the start.
	var by_dist := eligible.duplicate()
	var dists := _room_distances(start_cell)
	by_dist.sort_custom(func(a: int, b: int) -> bool: return dists[a] > dists[b])
	var n_rares := rng.randi_range(2, 4)
	var rare_rooms: Array = []
	var far_half := by_dist.slice(0, maxi(n_rares, (by_dist.size() + 1) / 2))
	_shuffle(far_half)
	for ri in far_half:
		if rare_rooms.size() >= n_rares:
			break
		var pos: Variant = _pick_spot(_room_cells(ri), start_pos, 3.5, 7.0)
		if pos != null:
			_add_group("rare_pack", pos, 1 + rng.randi_range(3, 4), ri)
			rare_rooms.append(ri)
	# Packs: one per room first (rooms without a rare pack first), then extras in big rooms and
	# corridors.
	var order: Array = []
	for ri in eligible:
		if not ri in rare_rooms:
			order.append(ri)
	for ri in eligible:
		if ri in rare_rooms:
			order.append(ri)
	var packs := 0
	for ri in order:
		if packs >= n_packs:
			break
		var cnt := rng.randi_range(3, 6)
		var pos2: Variant = _pick_spot(_room_cells(ri), start_pos, 2.0 + 0.25 * cnt, 7.0)
		if pos2 != null:
			_add_group("pack", pos2, cnt, ri)
			packs += 1
	var corridor := _corridor_cells()
	var extra_tries := 0
	while packs < n_packs and extra_tries < 30:
		extra_tries += 1
		var cnt2 := rng.randi_range(3, 6)
		var use_corridor := rng.randf() < 0.4 and not corridor.is_empty()
		var pos3: Variant = null
		var room_idx := -1
		if use_corridor:
			pos3 = _pick_spot(corridor, start_pos, 2.0 + 0.25 * cnt2, 8.0)
		else:
			room_idx = eligible[rng.randi_range(0, eligible.size() - 1)] if not eligible.is_empty() else -1
			if room_idx >= 0:
				var rc := _room_cells(room_idx)
				if rc.size() >= 20:
					pos3 = _pick_spot(rc, start_pos, 2.0 + 0.25 * cnt2, 7.0)
		if pos3 == null and extra_tries > 20:
			pos3 = _pick_spot(corridor, start_pos, 2.0, 5.0)
			room_idx = -1
		if pos3 != null:
			_add_group("pack", pos3, cnt2, room_idx)
			packs += 1
	_cap_monsters()


func _cap_monsters() -> void:
	var total := 0
	for g in spawn_groups:
		total += int(g["count"])
	while total > MAX_MONSTERS:
		var best := -1
		for i in spawn_groups.size():
			var g: Dictionary = spawn_groups[i]
			if g["kind"] == "pack" and int(g["count"]) > 3 and (best < 0 or int(g["count"]) > int(spawn_groups[best]["count"])):
				best = i
		if best < 0:
			break
		spawn_groups[best]["count"] = int(spawn_groups[best]["count"]) - 1
		spawn_groups[best]["radius"] = 2.0 + 0.25 * int(spawn_groups[best]["count"])
		total -= 1


# ------------------------------------------------------------------ light sources

## Wall faces a torch can hang on: wall cell + direction to the floor cell in front. Only faces
## visible to the camera (floor towards +Z or sideways) on straight wall runs.
func _torch_faces() -> Array:
	var out: Array = []
	for j in range(1, size - 1):
		for i in range(1, size - 1):
			var w := Vector2i(i, j)
			if cells[_k(w)] != CELL_VOID:
				continue
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var f: Vector2i = w + d
				if not _walk(f) or _occupied.has(f):
					continue
				var side := Vector2i(d.y, d.x)
				if cells[_k(w + side)] != CELL_VOID or cells[_k(w - side)] != CELL_VOID:
					continue
				if not _walk(f + side) or not _walk(f - side):
					continue
				out.append([w, d])
	return out


func _place_lighting() -> void:
	var th := WorldThemes.get_theme(theme)
	var col: Color = th["light_color"]
	var energy: float = th["light_energy"]
	var lrange: float = th["light_range"]
	# OmniLight3Ds form a pool that the World moves to the sources nearest the camera focus;
	# the start portal and the shrine keep their own light.
	light_pool_size = MAX_BUILD_LIGHTS - 1 - (0 if shrine.is_empty() else 1)
	# Lava pools glow.
	for pool in lava_pools:
		var r: Rect2i = pool["rect"]
		var centre := Vector3((r.position.x + r.size.x * 0.5) * TILE, 0.0, (r.position.y + r.size.y * 0.5) * TILE)
		glows.append({"pos": centre, "radius": maxf(r.size.x, r.size.y) * TILE * 0.8 + 1.2, "color": Color(1.0, 0.32, 0.06)})
		light_candidates.append({"pos": centre + Vector3(0, 1.4, 0), "color": Color(1.0, 0.42, 0.12), "energy": 2.4, "range": 10.0, "flicker": true})
	# Boss room: braziers (crypt / inferno) or big crystals (cave) at the corners.
	var brect: Rect2i = rooms[boss_room]["rect"]
	var corners := [
		Vector2i(brect.position.x + 1, brect.position.y + 1), Vector2i(brect.end.x - 2, brect.position.y + 1),
		Vector2i(brect.position.x + 1, brect.end.y - 2), Vector2i(brect.end.x - 2, brect.end.y - 2)]
	for c in corners:
		if not _walk(c) or _occupied.has(c):
			continue
		var p := grid.cell_center(c)
		if theme == "cave":
			crystals.append({"pos": p, "yaw": rng.randf() * TAU, "scale": 1.5})
		else:
			braziers.append({"pos": p})
		light_candidates.append({"pos": p + Vector3(0, 1.8, 0), "color": col, "energy": energy, "range": lrange, "flicker": theme != "cave"})
		_occupied[c] = true
	if theme == "cave":
		_place_crystals(col, energy, lrange)
	else:
		_place_torches(col, energy, lrange)


func _place_torches(col: Color, energy: float, lrange: float) -> void:
	var faces := _torch_faces()
	_shuffle(faces)
	var chosen: Array = []
	for f in faces:
		var w: Vector2i = f[0]
		var ok := true
		for o in chosen:
			if Vector2(o[0] - w).length() < 5.0:
				ok = false
				break
		if ok:
			chosen.append(f)
	for f2 in chosen:
		torches.append({"cell": f2[0], "dir": f2[1]})
		light_candidates.append({"pos": _torch_light_pos(f2[0], f2[1]), "color": col, "energy": energy, "range": lrange, "flicker": true})


## Point just in front of the torch flame.
func _torch_light_pos(w: Vector2i, d: Vector2i) -> Vector3:
	var face := grid.cell_center(w) + Vector3(d.x, 0, d.y) * (TILE * 0.5)
	return face + Vector3(d.x, 0, d.y) * 0.6 + Vector3(0, 1.9, 0)


func _place_crystals(col: Color, energy: float, lrange: float) -> void:
	# Crystal clusters grow on floor cells next to walls.
	var cands: Array = []
	for j in range(1, size - 1):
		for i in range(1, size - 1):
			var c := Vector2i(i, j)
			if not _walk(c) or _occupied.has(c):
				continue
			var wall_dir := Vector2i.ZERO
			for d in DIRS4:
				if cells[_k(c + d)] == CELL_VOID:
					wall_dir = d
					break
			if wall_dir != Vector2i.ZERO:
				cands.append([c, wall_dir])
	_shuffle(cands)
	var chosen: Array = []
	for cd in cands:
		var c2: Vector2i = cd[0]
		var ok := true
		for o in chosen:
			if Vector2(o[0] - c2).length() < 5.5:
				ok = false
				break
		if ok:
			chosen.append(cd)
	for cd in chosen:
		var cc: Vector2i = cd[0]
		var wd: Vector2i = cd[1]
		var pos := grid.cell_center(cc) + Vector3(wd.x, 0, wd.y) * 0.55
		crystals.append({"pos": pos, "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.9, 1.3)})
		light_candidates.append({"pos": pos + Vector3(0, 1.3, 0), "color": col, "energy": energy, "range": lrange, "flicker": false})


# ------------------------------------------------------------------ debris

func _weighted(table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var r := rng.randf() * total
	for k in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return table.keys()[0]


func _place_debris() -> void:
	var th := WorldThemes.get_theme(theme)
	var floor_table: Dictionary = th["debris"]
	var wall_table: Dictionary = th["wall_debris"]
	for j in range(1, size - 1):
		for i in range(1, size - 1):
			var c := Vector2i(i, j)
			if cells[_k(c)] == CELL_VOID:
				# Cave walls get big rocks leaning out of them.
				if theme == "cave":
					var touch := Vector2i.ZERO
					for d in DIRS4:
						if cells[_k(c + d)] == CELL_FLOOR:
							touch = d
							break
					if touch != Vector2i.ZERO and rng.randf() < 0.3:
						var rid := "env_rock_a" if rng.randf() < 0.5 else "env_rock_b"
						var rp := grid.cell_center(c) + Vector3(touch.x, 0, touch.y) * rng.randf_range(0.2, 0.4)
						# Sticks out of the wall face by at most ~0.45 m.
						wall_rocks.append({"id": rid, "pos": rp, "yaw": rng.randf() * TAU, "scale": 3.0, "fit": rng.randf_range(1.05, 1.3)})
				continue
			if not _walk(c) or _occupied.has(c):
				continue
			var wall_dir := Vector2i.ZERO
			for d in DIRS4:
				if cells[_k(c + d)] == CELL_VOID:
					wall_dir = d
					break
			var centre := grid.cell_center(c)
			if wall_dir != Vector2i.ZERO and not wall_table.is_empty() and rng.randf() < 0.1:
				var side := Vector3(wall_dir.y, 0, wall_dir.x) * rng.randf_range(-0.5, 0.5)
				var p := centre + Vector3(wall_dir.x, 0, wall_dir.y) * 0.55 + side
				debris.append({"id": _weighted(wall_table), "pos": p, "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.85, 1.1)})
			elif not floor_table.is_empty() and rng.randf() < 0.075:
				var p2 := centre + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
				debris.append({"id": _weighted(floor_table), "pos": p2, "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.7, 1.05)})

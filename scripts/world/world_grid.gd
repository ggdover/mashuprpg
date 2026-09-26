class_name WorldGrid
extends RefCounted
## Cell grid of a World: floor / walkability / sight-blocking per cell, A* pathfinding
## (AStarGrid2D, diagonals only without corner cutting), grid line of sight, nearest-walkable
## queries, flood fills and the explored mask for the minimap. OWNER: world.
##
## Cell (i, j) spans x in [origin.x + 2i, origin.x + 2i + 2], z in [origin.z + 2j, origin.z + 2j + 2].
## origin is Vector3.ZERO for towns and dungeons (docs/ARCHITECTURE.md §13); the test arena is
## centred on the world origin instead.

const TILE := 2.0
## Clearance used when smoothing paths (roughly an actor radius).
const PATH_CLEARANCE := 0.38

var size := Vector2i.ZERO
var origin := Vector3.ZERO
## 1 = the cell shows floor (minimap floor), 0 = void / wall.
var floor_cells := PackedByteArray()
## 1 = actors may stand here (floor without a pillar / prop / house).
var walk := PackedByteArray()
## 1 = blocks grid line of sight (walls, void, houses).
var opaque := PackedByteArray()
## 1 = revealed on the minimap.
var explored := PackedByteArray()
## Bumped whenever `explored` changes (lets the minimap redraw only when needed).
var explored_version := 0
var astar := AStarGrid2D.new()


func setup(p_size: Vector2i, p_origin: Vector3 = Vector3.ZERO) -> void:
	size = p_size
	origin = p_origin
	var n := size.x * size.y
	floor_cells = PackedByteArray()
	floor_cells.resize(n)
	walk = PackedByteArray()
	walk.resize(n)
	opaque = PackedByteArray()
	opaque.resize(n)
	opaque.fill(1)
	explored = PackedByteArray()
	explored.resize(n)
	explored_version = 0


# ------------------------------------------------------------------ cells

func idx(c: Vector2i) -> int:
	return c.y * size.x + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - origin.x) / TILE), floori((pos.z - origin.z) / TILE))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * TILE, 0.0, origin.z + (c.y + 0.5) * TILE)


## Cell type setters used by the generators. A floor cell is walkable and transparent; a solid
## floor cell (pillar, prop) keeps its floor but blocks walking; void blocks everything.
func set_floor(c: Vector2i, walkable: bool = true) -> void:
	var k := idx(c)
	floor_cells[k] = 1
	walk[k] = 1 if walkable else 0
	opaque[k] = 0


func set_void(c: Vector2i) -> void:
	var k := idx(c)
	floor_cells[k] = 0
	walk[k] = 0
	opaque[k] = 1


func set_walkable(c: Vector2i, walkable: bool) -> void:
	if in_bounds(c):
		walk[idx(c)] = 1 if walkable else 0


func set_opaque(c: Vector2i, on: bool) -> void:
	if in_bounds(c):
		opaque[idx(c)] = 1 if on else 0


func is_floor(c: Vector2i) -> bool:
	return in_bounds(c) and floor_cells[idx(c)] == 1


func is_walkable_cell(c: Vector2i) -> bool:
	return in_bounds(c) and walk[idx(c)] == 1


func is_opaque_cell(c: Vector2i) -> bool:
	return not in_bounds(c) or opaque[idx(c)] == 1


func walkable_count() -> int:
	return walk.count(1)


# ------------------------------------------------------------------ A*

## Rebuild the A* grid from `walk` (call after changing walkability).
func rebuild_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(origin.x + TILE * 0.5, origin.z + TILE * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.jumping_enabled = false
	astar.update()
	for j in size.y:
		for i in size.x:
			if walk[j * size.x + i] == 0:
				astar.set_point_solid(Vector2i(i, j), true)


## Keep the A* grid in sync after a single-cell walkability change.
func update_astar_cell(c: Vector2i) -> void:
	if in_bounds(c) and astar.is_in_boundsv(c):
		astar.set_point_solid(c, not is_walkable_cell(c))


## Length in cells of the shortest grid path between two walkable cells (INF if none).
func cell_path_length(a: Vector2i, b: Vector2i) -> float:
	if not is_walkable_cell(a) or not is_walkable_cell(b):
		return INF
	if a == b:
		return 0.0
	var ids := astar.get_id_path(a, b)
	if ids.is_empty():
		return INF
	var total := 0.0
	for k in range(1, ids.size()):
		total += Vector2(ids[k] - ids[k - 1]).length()
	return total


## Grid path as world positions at y = 0 (start cell excluded, `to` included, snapped to the
## nearest walkable cell), smoothed by string pulling. Empty if unreachable.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if size.x == 0:
		return out
	var fc := nearest_walkable_cell(world_to_cell(from))
	var goal := to
	goal.y = 0.0
	var tc := world_to_cell(goal)
	if not is_walkable_cell(tc):
		tc = nearest_walkable_cell(tc)
		if tc.x < 0:
			return out
		goal = _closest_point_in_cell(tc, goal)
	if fc.x < 0:
		return out
	var start := Vector3(from.x, 0.0, from.z)
	if not is_walkable_cell(world_to_cell(start)):
		start = cell_center(fc)
	if fc == tc or _segment_walkable(start, goal, PATH_CLEARANCE):
		out.append(goal)
		return out
	var ids := astar.get_id_path(fc, tc)
	if ids.is_empty():
		return out
	# Raw points: cell centres after the start cell, then the exact goal.
	var pts: Array[Vector3] = []
	for k in range(1, ids.size() - 1):
		pts.append(cell_center(ids[k]))
	pts.append(goal)
	# String pulling (greedy): from the current anchor, advance while the straight line with
	# clearance stays on walkable cells.
	var anchor := start
	var k2 := 0
	while k2 < pts.size():
		var best := k2
		while best + 1 < pts.size() and _segment_walkable(anchor, pts[best + 1], PATH_CLEARANCE):
			best += 1
		out.append(pts[best])
		anchor = pts[best]
		k2 = best + 1
	return out


## True if a straight walk from a to b (world XZ) stays on walkable cells with `clearance` metres
## of room on both sides.
func _segment_walkable(a: Vector3, b: Vector3, clearance: float) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var length := d.length()
	if length < 0.001:
		return is_walkable_cell(world_to_cell(a))
	var perp := Vector2(-d.y, d.x) / length * clearance
	var off := Vector3(perp.x, 0.0, perp.y)
	# Centre line plus both edges of the corridor the actor sweeps (grid traversal).
	return line_clear(a, b, walk, true) and line_clear(a + off, b + off, walk, true) and line_clear(a - off, b - off, walk, true)


# ------------------------------------------------------------------ nearest / random

## Nearest walkable cell to c (c itself if walkable), (-1, -1) if the grid has none.
func nearest_walkable_cell(c: Vector2i) -> Vector2i:
	if is_walkable_cell(c):
		return c
	var cc := Vector2i(clampi(c.x, 0, size.x - 1), clampi(c.y, 0, size.y - 1))
	var best := Vector2i(-1, -1)
	var best_d := INF
	var max_r := maxi(size.x, size.y) + absi(c.x - cc.x) + absi(c.y - cc.y)
	for r in range(0, max_r + 1):
		# Every cell of ring r is at least r - 1 cells away: stop once that can't beat the best.
		if best.x >= 0 and float(r - 1) > best_d:
			break
		for dy in range(-r, r + 1):
			var row := cc.y + dy
			if row < 0 or row >= size.y:
				continue
			var ring_x: Array[int] = []
			if absi(dy) == r:
				for dx in range(-r, r + 1):
					ring_x.append(cc.x + dx)
			else:
				ring_x.append(cc.x - r)
				ring_x.append(cc.x + r)
			for col in ring_x:
				if col < 0 or col >= size.x:
					continue
				if walk[row * size.x + col] == 1:
					var dd := Vector2(col - c.x, row - c.y).length()
					if dd < best_d:
						best_d = dd
						best = Vector2i(col, row)
	return best


## Nearest walkable world position (pos itself if walkable): the closest point of the nearest
## walkable cell, kept a little away from its edges.
func nearest_walkable(pos: Vector3) -> Vector3:
	var c := world_to_cell(pos)
	if is_walkable_cell(c):
		return pos
	var n := nearest_walkable_cell(c)
	if n.x < 0:
		return pos
	return _closest_point_in_cell(n, pos)


func _closest_point_in_cell(c: Vector2i, pos: Vector3) -> Vector3:
	var margin := 0.45
	var x0 := origin.x + c.x * TILE
	var z0 := origin.z + c.y * TILE
	# Only keep the margin on sides that border a non-walkable cell.
	var lo_x := x0 + (margin if not is_walkable_cell(c + Vector2i(-1, 0)) else 0.05)
	var hi_x := x0 + TILE - (margin if not is_walkable_cell(c + Vector2i(1, 0)) else 0.05)
	var lo_z := z0 + (margin if not is_walkable_cell(c + Vector2i(0, -1)) else 0.05)
	var hi_z := z0 + TILE - (margin if not is_walkable_cell(c + Vector2i(0, 1)) else 0.05)
	return Vector3(clampf(pos.x, lo_x, hi_x), 0.0, clampf(pos.z, lo_z, hi_z))


## Random walkable point within radius of center that can see center (grid LOS).
func random_walkable_near(center: Vector3, radius: float, rng: RandomNumberGenerator = null) -> Vector3:
	var base := nearest_walkable(center)
	base.y = 0.0
	if radius <= 0.01:
		return base
	for attempt in 16:
		var ang := (rng.randf() if rng else randf()) * TAU
		var dist := sqrt(rng.randf() if rng else randf()) * radius
		var p := base + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		if is_walkable_cell(world_to_cell(p)) and line_clear(base, p, walk, true):
			return p
	return base


# ------------------------------------------------------------------ line of sight

## True if no cell crossed by the segment a -> b (XZ) is opaque (walls, void, houses).
func has_line_of_sight(a: Vector3, b: Vector3) -> bool:
	return line_clear(a, b, opaque, false)


## Grid traversal (Amanatides-Woo). mask[k] == blocking_value... interpreted as: when
## `mask_is_walk` is false, cells with mask == 1 block; when true, cells with mask == 0 block.
## Passing exactly through a corner checks both side cells (conservative).
func line_clear(a: Vector3, b: Vector3, mask: PackedByteArray, mask_is_walk: bool) -> bool:
	var p0 := Vector2((a.x - origin.x) / TILE, (a.z - origin.z) / TILE)
	var p1 := Vector2((b.x - origin.x) / TILE, (b.z - origin.z) / TILE)
	var cx := floori(p0.x)
	var cy := floori(p0.y)
	var ex := floori(p1.x)
	var ey := floori(p1.y)
	var dx := p1.x - p0.x
	var dy := p1.y - p0.y
	var step_x := 1 if dx > 0.0 else -1
	var step_y := 1 if dy > 0.0 else -1
	var t_max_x := INF
	var t_max_y := INF
	var t_dx := INF
	var t_dy := INF
	if absf(dx) > 1e-9:
		t_max_x = ((cx + (1 if dx > 0.0 else 0)) - p0.x) / dx
		t_dx = absf(1.0 / dx)
	if absf(dy) > 1e-9:
		t_max_y = ((cy + (1 if dy > 0.0 else 0)) - p0.y) / dy
		t_dy = absf(1.0 / dy)
	var guard := absi(ex - cx) + absi(ey - cy) + 4
	while true:
		if _blocks(Vector2i(cx, cy), mask, mask_is_walk):
			return false
		if cx == ex and cy == ey:
			return true
		guard -= 1
		if guard < 0 or minf(t_max_x, t_max_y) > 1.0:
			return true
		if absf(t_max_x - t_max_y) < 1e-7:
			# Exactly through a corner: both side cells must be clear.
			if _blocks(Vector2i(cx + step_x, cy), mask, mask_is_walk) or _blocks(Vector2i(cx, cy + step_y), mask, mask_is_walk):
				return false
			cx += step_x
			cy += step_y
			t_max_x += t_dx
			t_max_y += t_dy
		elif t_max_x < t_max_y:
			if t_max_x > 1.0:
				return true
			cx += step_x
			t_max_x += t_dx
		else:
			if t_max_y > 1.0:
				return true
			cy += step_y
			t_max_y += t_dy
	return true


func _blocks(c: Vector2i, mask: PackedByteArray, mask_is_walk: bool) -> bool:
	if not in_bounds(c):
		return true
	var v := mask[c.y * size.x + c.x]
	return v == 0 if mask_is_walk else v == 1


# ------------------------------------------------------------------ flood fill

## 4-connected flood fill over walkable cells from `start`. Returns a byte mask (1 = reached).
## (4-connectivity equals A* connectivity, since diagonals need both side cells free.)
func flood_walkable(start: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(size.x * size.y)
	if not is_walkable_cell(start):
		return seen
	var stack: Array[Vector2i] = [start]
	seen[idx(start)] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if in_bounds(n):
				var k := idx(n)
				if seen[k] == 0 and walk[k] == 1:
					seen[k] = 1
					stack.append(n)
	return seen


## True if every walkable cell is reachable from every other.
func is_fully_connected() -> bool:
	var first := walk.find(1)
	if first < 0:
		return true
	var seen := flood_walkable(Vector2i(first % size.x, first / size.x))
	return seen.count(1) == walk.count(1)


# ------------------------------------------------------------------ explored

func mark_explored(pos: Vector3, radius: float) -> void:
	if size.x == 0:
		return
	var c := world_to_cell(pos)
	var r := int(ceil(radius / TILE))
	var r2 := (radius / TILE + 0.5) * (radius / TILE + 0.5)
	var changed := false
	for j in range(maxi(c.y - r, 0), mini(c.y + r, size.y - 1) + 1):
		for i in range(maxi(c.x - r, 0), mini(c.x + r, size.x - 1) + 1):
			var dd := float((i - c.x) * (i - c.x) + (j - c.y) * (j - c.y))
			if dd <= r2:
				var k := j * size.x + i
				if explored[k] == 0:
					explored[k] = 1
					changed = true
	if changed:
		explored_version += 1

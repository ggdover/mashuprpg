extends TestCase
## Passive tree layout (§10): node spacing, links never passing through other nodes or crossing
## (both as straight lines and with orbit links drawn as arcs), radii, arcs, hit-testing.

const MIN_SPACING := 60.0
const LINK_MARGIN := 10.0
const ARC_SEGMENTS := 10


func _pos(id: int) -> Vector2:
	return TreeDB.get_node_position(id)


## Polyline of a link: straight, or the arc from TreeDB.get_link_arc when `arcs` is true.
func _shape(link: Vector2i, arcs: bool) -> PackedVector2Array:
	var a := _pos(link.x)
	var b := _pos(link.y)
	if arcs:
		var arc := TreeDB.get_link_arc(link.x, link.y)
		if not arc.is_empty():
			var pts := PackedVector2Array([a])
			var c: Vector2 = arc["centre"]
			var r: float = arc["radius"]
			for i in range(1, ARC_SEGMENTS):
				var t := lerpf(arc["start_angle"], arc["end_angle"], float(i) / ARC_SEGMENTS)
				pts.append(c + Vector2(cos(t), sin(t)) * r)
			pts.append(b)
			return pts
	return PackedVector2Array([a, b])


func _bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (d - c).cross(a - c)
	var d2 := (d - c).cross(b - c)
	var d3 := (b - a).cross(c - a)
	var d4 := (b - a).cross(d - a)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


func _polylines_cross(p: PackedVector2Array, q: PackedVector2Array) -> bool:
	for i in p.size() - 1:
		for j in q.size() - 1:
			if _segments_cross(p[i], p[i + 1], q[j], q[j + 1]):
				return true
	return false


func test_node_spacing() -> void:
	var ids: Array = TreeDB.get_all_ids()
	var min_d := INF
	var bad := 0
	for i in ids.size():
		var pi := _pos(ids[i])
		for j in range(i + 1, ids.size()):
			var d := pi.distance_to(_pos(ids[j]))
			min_d = minf(min_d, d)
			if d < MIN_SPACING:
				bad += 1
				if bad <= 5:
					fail("nodes %d and %d only %.1f apart" % [ids[i], ids[j], d])
	assert_true(min_d >= MIN_SPACING, "min spacing %.1f" % min_d)


func test_links_never_pass_through_nodes() -> void:
	var ids: Array = TreeDB.get_all_ids()
	for arcs in [false, true]:
		var bad := 0
		for link in TreeDB.get_links():
			var shape := _shape(link, arcs)
			var box := _bbox(shape).grow(TreeDB.NODE_RADIUS["start"] + LINK_MARGIN)
			for c in ids:
				if c == link.x or c == link.y:
					continue
				var pc := _pos(c)
				if not box.has_point(pc):
					continue
				var clear := TreeDB.get_node_radius(c) + LINK_MARGIN
				for i in shape.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(pc, shape[i], shape[i + 1])
					if q.distance_to(pc) < clear:
						bad += 1
						if bad <= 5:
							fail("%s link %d-%d passes through node %d" % ["arc" if arcs else "straight", link.x, link.y, c])
						break
		assert_eq(bad, 0, "links through nodes (arcs=%s)" % arcs)


func test_links_never_cross() -> void:
	var links := TreeDB.get_links()
	for arcs in [false, true]:
		var shapes: Array[PackedVector2Array] = []
		var boxes: Array[Rect2] = []
		for link in links:
			var s := _shape(link, arcs)
			shapes.append(s)
			boxes.append(_bbox(s))
		var crossings := 0
		for i in links.size():
			for j in range(i + 1, links.size()):
				var a := links[i]
				var b := links[j]
				if a.x == b.x or a.x == b.y or a.y == b.x or a.y == b.y:
					continue
				if not boxes[i].grow(1.0).intersects(boxes[j].grow(1.0)):
					continue
				if _polylines_cross(shapes[i], shapes[j]):
					crossings += 1
					if crossings <= 5:
						fail("links %s and %s cross (arcs=%s)" % [a, b, arcs])
		assert_eq(crossings, 0, "crossings (arcs=%s)" % arcs)


func test_layout_radii() -> void:
	var max_r := 0.0
	var bounds := TreeDB.get_bounds()
	for id in TreeDB.get_all_ids():
		var p := _pos(id)
		max_r = maxf(max_r, p.length())
		assert_true(bounds.grow(0.01).has_point(p), "bounds contain node %d" % id)
		var t := TreeDB.get_node_type(id)
		if t == "keystone":
			assert_true(p.length() > 1800.0, "keystone %d outside the outer ring (r=%.0f)" % [id, p.length()])
		if t == "start":
			assert_between(p.length(), 330.0, 370.0, "start radius")
	assert_between(max_r, 1900.0, 2300.0, "overall radius (~2200)")
	assert_between(bounds.size.x, 3800.0, 4600.0, "bounds width")
	assert_between(bounds.size.y, 3800.0, 4600.0, "bounds height")
	assert_true(bounds.has_point(Vector2.ZERO), "centred on the origin")


func test_regions_follow_angles() -> void:
	# Region centres (deg, y down): Int -90, Dex/Int -30, Dex 30, Str/Dex 90, Str 150, Int/Str 210.
	var centres := {"int": -90.0, "dex_int": -30.0, "dex": 30.0, "str_dex": 90.0, "str": 150.0, "int_str": 210.0}
	for id in TreeDB.get_all_ids():
		var r := TreeDB.get_region(id)
		if not centres.has(r):
			continue
		var p := _pos(id)
		if p.length() < 800.0:
			continue
		var d := absf(wrapf(rad_to_deg(p.angle()) - float(centres[r]), -180.0, 180.0))
		assert_true(d <= 36.0, "node %d (%s) lies in its region (off by %.0f deg)" % [id, r, d])


func test_link_arcs() -> void:
	var arcs := 0
	for link in TreeDB.get_links():
		var arc := TreeDB.get_link_arc(link.x, link.y)
		if arc.is_empty():
			continue
		arcs += 1
		var c: Vector2 = arc["centre"]
		var r: float = arc["radius"]
		var a := _pos(link.x)
		var b := _pos(link.y)
		assert_near(a.distance_to(c), r, 0.5, "arc start on circle")
		assert_near(b.distance_to(c), r, 0.5, "arc end on circle")
		var sweep: float = arc["end_angle"] - arc["start_angle"]
		assert_true(absf(sweep) < PI * 0.75 and absf(sweep) > 0.0, "minor arc")
		var end: Vector2 = c + Vector2(cos(arc["end_angle"]), sin(arc["end_angle"])) * r
		assert_true(end.distance_to(b) < 0.5, "arc ends at b")
		var back := TreeDB.get_link_arc(link.y, link.x)
		assert_near(absf(back["end_angle"] - back["start_angle"]), absf(sweep), 0.001, "symmetric arc")
	assert_true(arcs > 100, "rings and wheels use arcs (%d)" % arcs)
	assert_true(TreeDB.get_links().is_read_only(), "get_links is read-only")
	var links := TreeDB.get_links()
	for i in range(1, links.size()):
		assert_true(links[i - 1].x < links[i].x or (links[i - 1].x == links[i].x and links[i - 1].y < links[i].y), "links sorted")
	for link in links:
		assert_true(link.x < link.y, "a < b")
	# Start exits are straight.
	var s := TreeDB.get_start_node("warrior")
	for nb in TreeDB.get_neighbors(s):
		assert_eq(TreeDB.get_link_arc(s, nb), {}, "straight exit")
	assert_eq(TreeDB.get_link_arc(-1, s), {}, "unknown node")


func test_find_node_at_and_rect() -> void:
	for id in TreeDB.get_all_ids():
		var p := _pos(id)
		assert_eq(TreeDB.find_node_at(p), id, "hit node %d at its centre" % id)
		assert_eq(TreeDB.find_node_at(p + Vector2(TreeDB.get_node_radius(id) * 0.7, 0)), id, "hit inside radius %d" % id)
	assert_eq(TreeDB.find_node_at(Vector2(5000, 5000)), -1, "empty space")
	assert_eq(TreeDB.find_node_at(Vector2(0, 170)), -1, "between nodes")
	var all := TreeDB.get_nodes_in_rect(TreeDB.get_bounds())
	assert_eq(all.size(), TreeDB.nodes.size(), "rect over bounds returns every node")
	var some := TreeDB.get_nodes_in_rect(Rect2(-100, -100, 200, 200), 0.0)
	assert_true(some.size() >= 1 and some.size() < 10, "small rect around the centre (%d)" % some.size())

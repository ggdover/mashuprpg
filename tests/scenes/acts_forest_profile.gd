extends Node
## Forest act stats, headless: composes the whole act (hub + wilds) and prints the generator
## timings, prop counts per model, collision shapes (explicit + the merged boxes World builds over
## blocked cells), spawn groups per zone, and the time a StaticBody3D takes to take all shapes.
##   tools/gtest.sh acts-forest res://tests/scenes/acts_forest_profile.tscn
## OWNER: acts-forest.

func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	var comp := WorldActComposite.new()
	var lay := comp.compose("forest", 1, 12)
	var t1 := Time.get_ticks_usec()
	print("[stats] compose %.0f ms  profile %s" % [(t1 - t0) / 1000.0, str(lay.get("profile", {}))])
	var props: Array = lay["props"]
	var by_id := {}
	for d in props:
		by_id[d["id"]] = int(by_id.get(d["id"], 0)) + 1
	var ids := by_id.keys()
	ids.sort_custom(func(a, b): return by_id[a] > by_id[b])
	var line := ""
	for id in ids:
		line += "%s=%d " % [id, by_id[id]]
	print("[stats] props %d: %s" % [props.size(), line])
	var grid: WorldGrid = lay["grid"]
	var soft: Dictionary = lay["soft"]
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
	var boxes := 0
	var boxes_floor := 0
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
			boxes += 1
			if grid.floor_cells[k] == 1:
				boxes_floor += 1
	var shapes: Array = lay["shapes"]
	print("[stats] shapes: explicit %d, merged boxes %d (%d starting on floor cells), total %d" % [shapes.size(), boxes, boxes_floor, shapes.size() + boxes])
	var per := {}
	for g in lay["spawn_groups"]:
		var key := "%s/%s" % [String(g.get("region", "?")), String(g["kind"])]
		per[key] = int(per.get(key, 0)) + 1
	print("[stats] spawn groups %d: %s" % [(lay["spawn_groups"] as Array).size(), str(per)])
	print("[stats] interactables %d, lights %d, shafts %d, water areas %d, walkable %d" % [(lay["interactables"] as Array).size(),
		(lay["lights"] as Array).size(), (lay["shafts"] as Array).size(), (lay["water_areas"] as Array).size(), grid.walkable_count()])
	# How long a body in the tree takes to get that many shapes (World adds them one by one).
	for n in [1000, 2000, 3000]:
		var body := StaticBody3D.new()
		add_child(body)
		var t2 := Time.get_ticks_usec()
		for k in n:
			var cs := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = Vector3(2, 3, 2)
			cs.shape = b
			cs.position = Vector3(k % 100 * 3.0, 1.5, k / 100 * 3.0)
			body.add_child(cs)
		var t3 := Time.get_ticks_usec()
		print("[stats] %d shapes on one body: %.0f ms" % [n, (t3 - t2) / 1000.0])
		body.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)

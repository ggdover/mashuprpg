extends Node
## Desert act build stats (dev tool): composes the act's layout and prints prop counts per model,
## collision shapes, tiles, lights, monster groups / chests / shrines per zone and timings (the
## generator's own phases too). OWNER: acts-desert.
##   tools/gtest.sh acts-desert res://tests/scenes/acts_desert_stats.tscn [-- --seed=N]


func _ready() -> void:
	var seed_value := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.split("=")[1])
	var t0 := Time.get_ticks_usec()
	var comp := WorldActComposite.new()
	var lay := comp.compose("desert", seed_value, 10)
	print("[desert_stats] compose %.0f ms, profile %s" % [(Time.get_ticks_usec() - t0) / 1000.0, str(lay.get("profile", {}))])
	var gen: Variant = (comp.parts["wilds"] as Dictionary)["gen"]
	if "prof" in gen:
		print("[desert_stats] wilds phases (ms) %s" % str(gen.prof))
	var by_id := {}
	for d in lay["props"]:
		by_id[d["id"]] = int(by_id.get(d["id"], 0)) + 1
	var ids: Array = by_id.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(by_id[a]) > int(by_id[b]))
	var border := 0
	for id in ids:
		if String(id).begins_with("desert_ruinwall"):
			border += int(by_id[id])
	print("[desert_stats] props %d (border %d), shapes %d, lights %d, glows %d" % [(lay["props"] as Array).size(), border,
		(lay["shapes"] as Array).size(), (lay["lights"] as Array).size(), (lay["glows"] as Array).size()])
	for id in ids:
		print("    %-26s %5d" % [id, int(by_id[id])])
	var tiles := 0
	for tg in lay["tiles"]:
		tiles += (tg["cells"] as Array).size()
	print("[desert_stats] tile cells %d in %d groups" % [tiles, (lay["tiles"] as Array).size()])
	var per := {}
	for g in lay["spawn_groups"]:
		var rid := comp.region_at(g["position"])
		var e: Dictionary = per.get(rid, {})
		e[String(g["kind"])] = int(e.get(String(g["kind"]), 0)) + 1
		per[rid] = e
	for it in lay["interactables"]:
		var rid2 := comp.region_at(it["pos"])
		var e2: Dictionary = per.get(rid2, {})
		e2[String(it["kind"])] = int(e2.get(String(it["kind"]), 0)) + 1
		per[rid2] = e2
	var walk := {}
	var g2: WorldGrid = lay["grid"]
	for k in g2.walk.size():
		if g2.walk[k] == 1:
			var ri := int(lay["region_map"][k])
			walk[ri] = int(walk.get(ri, 0)) + 1
	for k2 in (lay["regions"] as Array).size():
		var r: Dictionary = lay["regions"][k2]
		print("[desert_stats] %-10s walkable %6.0f m2  %s" % [r["id"], float(walk.get(k2 + 1, 0)) * 4.0, str(per.get(String(r["id"]), {}))])
	print("[desert_stats] fully connected: %s" % g2.is_fully_connected())
	get_tree().quit(0)

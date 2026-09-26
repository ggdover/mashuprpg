extends TestCase
## TreeDB allocation rules (§10): can_allocate, can_refund (connectivity), find_path (shortest
## through unallocated nodes), get_mods aggregation, helpers and robustness.

const CLASSES: Array[String] = ["warrior", "ranger", "sorcerer"]


func _id_by_name(node_name: String) -> int:
	for id in TreeDB.nodes:
		if TreeDB.nodes[id]["name"] == node_name:
			return id
	fail("no node named %s" % node_name)
	return -1


## Independent BFS distance from the start (through non-start nodes) for checking find_path.
func _dist_from(sources: Array, blocked: Dictionary) -> Dictionary:
	var dist := {}
	var queue: Array = []
	for s in sources:
		dist[s] = 0
		queue.append(s)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in TreeDB.nodes[cur]["links"]:
			if dist.has(nb) or blocked.has(nb) or TreeDB.nodes[nb]["type"] == "start":
				continue
			dist[nb] = int(dist[cur]) + 1
			queue.append(nb)
	return dist


## Allocate the shortest path to `target` on top of `allocated`, checking can_allocate each step.
func _allocate_to(allocated: Array, target: int, cls: String) -> Array[int]:
	var out: Array[int] = []
	out.assign(allocated)
	for id in TreeDB.find_path(out, target, cls):
		assert_true(TreeDB.can_allocate(out, id, cls), "path step %d allocatable" % id)
		out.append(id)
	return out


func test_can_allocate_basics() -> void:
	for cls in CLASSES:
		var s := TreeDB.get_start_node(cls)
		var neighbours := TreeDB.get_neighbors(s)
		assert_eq(neighbours.size(), 3, "%s start has three exits" % cls)
		for nb in neighbours:
			assert_true(TreeDB.can_allocate([], nb, cls), "start neighbour allocatable")
			assert_false(TreeDB.can_allocate([nb], nb, cls), "already allocated")
			for nb2 in TreeDB.get_neighbors(nb):
				if nb2 != s:
					assert_false(TreeDB.can_allocate([], nb2, cls), "two steps away not allocatable")
					assert_true(TreeDB.can_allocate([nb], nb2, cls), "adjacent to allocated")
		assert_false(TreeDB.can_allocate([], s, cls), "own start")
		for other in CLASSES:
			if other != cls:
				var os := TreeDB.get_start_node(other)
				for onb in TreeDB.get_neighbors(os):
					assert_false(TreeDB.can_allocate([onb], os, cls), "other class start never allocatable")
	assert_false(TreeDB.can_allocate([], 999999, "warrior"), "unknown id")
	var any: int = TreeDB.get_neighbors(TreeDB.get_start_node("warrior"))[0]
	assert_false(TreeDB.can_allocate([], any, "necromancer"), "unknown class")
	# Ids may come in as floats (e.g. straight from JSON).
	var nb0: int = TreeDB.get_neighbors(TreeDB.get_start_node("ranger"))[0]
	var nb1 := -1
	for x in TreeDB.get_neighbors(nb0):
		if not TreeDB.is_start(x):
			nb1 = x
	assert_true(TreeDB.can_allocate([float(nb0)], nb1, "ranger"), "float ids tolerated")


func test_refund_blocked_when_it_disconnects() -> void:
	var cls := "warrior"
	var target := _id_by_name("Resolute Technique")
	var alloc := _allocate_to([], target, cls)
	assert_true(alloc.size() >= 10, "long path to a keystone (%d)" % alloc.size())
	assert_eq(alloc[-1], target, "path ends at the target")
	# Only the end of a chain can be refunded.
	for i in alloc.size():
		var ok := TreeDB.can_refund(alloc, alloc[i], cls)
		if i == alloc.size() - 1:
			assert_true(ok, "refund the keystone at the end")
		else:
			assert_false(ok, "refund of %d would disconnect the rest" % alloc[i])
	assert_false(TreeDB.can_refund(alloc, TreeDB.get_start_node(cls), cls), "start can't be refunded")
	assert_false(TreeDB.can_refund(alloc, _id_by_name("Blood Magic"), cls), "unallocated node")
	assert_false(TreeDB.can_refund([alloc[0]], alloc[0], "necromancer"), "unknown class")
	# Refunding the last node leaves the rest connected; then the new end is refundable.
	var shorter := alloc.duplicate()
	shorter.pop_back()
	assert_true(TreeDB.can_refund(shorter, shorter[-1], cls), "new end refundable")


func test_refund_allowed_around_a_loop() -> void:
	# "Heart of the Oak" is a loop cluster: two ways round the rim to the notable.
	var cls := "warrior"
	var notable := _id_by_name("Heart of the Oak")
	var group: String = TreeDB.nodes[notable]["group"]
	var alloc := _allocate_to([], notable, cls)
	var rim: Array[int] = []
	for id in TreeDB.nodes:
		if TreeDB.nodes[id]["group"] == group:
			rim.append(id)
	assert_eq(rim.size(), 6, "loop of 5 smalls + notable")
	for id in rim:
		if not alloc.has(id):
			alloc = _allocate_to(alloc, id, cls)
	for id in rim:
		assert_true(alloc.has(id), "whole loop allocated")
	var entry := -1
	for id in rim:
		for nb in TreeDB.get_neighbors(id):
			if TreeDB.nodes[nb]["group"] != group:
				entry = id
	assert_true(entry >= 0, "loop entry found")
	for id in rim:
		if id == entry:
			assert_false(TreeDB.can_refund(alloc, id, cls), "entry holds the loop")
		else:
			assert_true(TreeDB.can_refund(alloc, id, cls), "rim node %d refundable (other way round)" % id)


func test_refund_ignores_already_disconnected_nodes() -> void:
	var cls := "sorcerer"
	var a: int = TreeDB.get_neighbors(TreeDB.get_start_node(cls))[0]
	var far := _id_by_name("Iron Reflexes")
	var alloc: Array = [a, far, 424242]
	assert_true(TreeDB.can_refund(alloc, far, cls), "stray node can be cleaned up")
	assert_true(TreeDB.can_refund(alloc, 424242, cls), "unknown id can be cleaned up")
	assert_true(TreeDB.can_refund(alloc, a, cls), "a leaf next to the start")
	var clean := TreeDB.sanitize_allocation([a, a, far, 424242, TreeDB.get_start_node(cls)], cls)
	assert_eq(Array(clean), [a], "sanitize keeps only connected, known, unique nodes")
	assert_eq(Array(TreeDB.get_connected(alloc, cls)), [a], "get_connected")


func test_find_path_is_shortest() -> void:
	var targets: Array[int] = TreeDB.get_ids_by_type("keystone")
	targets.append_array(TreeDB.get_ids_by_type("notable"))
	for cls in CLASSES:
		var s := TreeDB.get_start_node(cls)
		var dist := _dist_from([s], {})
		for t in targets:
			var path := TreeDB.find_path([], t, cls)
			assert_true(path.size() > 0, "%s reaches %d" % [cls, t])
			if path.is_empty():
				continue
			assert_eq(path[-1], t, "ends at target")
			assert_eq(path.size(), int(dist[t]), "shortest (%s -> %s)" % [cls, TreeDB.nodes[t]["name"]])
			assert_true(TreeDB.get_neighbors(s).has(path[0]), "starts next to the class start")
			for i in range(1, path.size()):
				assert_true(TreeDB.get_neighbors(path[i - 1]).has(path[i]), "consecutive nodes linked")
			for id in path:
				assert_false(TreeDB.is_start(id), "never through a start")


func test_find_path_from_allocation() -> void:
	var cls := "ranger"
	var alloc := _allocate_to([], _id_by_name("Deadeye"), cls)
	var target := _id_by_name("Point Blank")
	var path := TreeDB.find_path(alloc, target, cls)
	var fresh := TreeDB.find_path([], target, cls)
	assert_true(path.size() > 0 and path.size() <= fresh.size(), "an allocation never makes a path longer")
	var sources: Array = [TreeDB.get_start_node(cls)]
	for id in alloc:
		sources.append(id)
	assert_eq(path.size(), int(_dist_from(sources, {})[target]), "shortest from the allocated set")
	for id in path:
		assert_false(alloc.has(id), "only unallocated nodes in the path")
	assert_true(TreeDB.can_allocate(alloc, path[0], cls), "first step allocatable")
	assert_eq(TreeDB.find_path(alloc, alloc[0], cls), [], "already allocated -> []")
	assert_eq(TreeDB.find_path([], TreeDB.get_start_node(cls), cls), [], "start -> []")
	assert_eq(TreeDB.find_path([], TreeDB.get_start_node("warrior"), cls), [], "other start -> []")
	assert_eq(TreeDB.find_path([], 999999, cls), [], "unknown id -> []")
	assert_eq(TreeDB.find_path([], target, "necromancer"), [], "unknown class -> []")
	# The cached answer is a copy.
	var p1 := TreeDB.find_path(alloc, target, cls)
	p1.clear()
	assert_eq(TreeDB.find_path(alloc, target, cls), path, "cache returns copies")


func test_get_mods_aggregation() -> void:
	var cls := "warrior"
	assert_eq(TreeDB.get_mods([], cls), [], "start mods are empty")
	var s := TreeDB.get_start_node(cls)
	var alloc: Array[int] = []
	for nb in TreeDB.get_neighbors(s):
		alloc.append(nb)
	var expected := 0
	for id in alloc:
		expected += (TreeDB.nodes[id]["mods"] as Array).size()
	var mods := TreeDB.get_mods(alloc, cls)
	assert_eq(mods.size(), expected, "one entry per node mod")
	var b := StatBlock.new()
	b.add_mods(mods)
	assert_near(b.flat("strength"), 30.0, 0.001, "three +10 Strength exits")
	# Duplicates and unknown ids are ignored; the class argument is optional.
	var with_junk: Array = alloc.duplicate()
	with_junk.append(alloc[0])
	with_junk.append(777777)
	with_junk.append(s)
	assert_eq(TreeDB.get_mods(with_junk, cls).size(), expected, "duplicates/unknown/start ignored")
	assert_eq(TreeDB.get_mods(alloc).size(), expected, "class optional")
	# A notable + keystone path adds up in a StatBlock.
	var path := _allocate_to([], _id_by_name("Unwavering Stance"), cls)
	var sb := StatBlock.new()
	sb.add_mods(TreeDB.get_mods(path, cls))
	assert_true(sb.has_flag("cannot_evade"), "keystone flag")
	assert_near(sb.more("armour"), 1.3, 0.001, "keystone more armour")
	var armour_inc := 0.0
	for id in path:
		for m in TreeDB.nodes[id]["mods"]:
			if m["stat"] == "armour" and m["op"] == "inc":
				armour_inc += m["value"]
	assert_near(sb.inc("armour"), armour_inc, 0.001, "inc armour sums")
	# Returned mods are copies.
	var m0: Dictionary = TreeDB.get_mods(alloc, cls)[0]
	m0["value"] = 9999.0
	assert_ne(TreeDB.get_mods(alloc, cls)[0]["value"], 9999.0, "mods are copies")
	var lines := TreeDB.get_allocated_lines(alloc, cls)
	assert_eq(lines.size(), 1, "merged summary")
	assert_eq(lines[0], "+30 to Strength", "summary text")


func test_node_lines() -> void:
	var rt := _id_by_name("Resolute Technique")
	var lines := TreeDB.get_node_lines(rt)
	assert_eq(lines.size(), 2, "keystone lines")
	assert_eq(lines[0], "Your Hits can't be Critical Strikes", "flag text")
	assert_eq(lines[1], "30% more Attack Damage", "more text")
	var bf := _id_by_name("Brute Force")
	assert_eq(TreeDB.get_node_lines(bf)[0], "25% increased Melee Damage", "notable text")
	assert_eq(TreeDB.get_node_lines(-5).size(), 0, "unknown id")


func test_allocatable_frontier() -> void:
	var cls := "sorcerer"
	var s := TreeDB.get_start_node(cls)
	var frontier := TreeDB.get_allocatable([], cls)
	var expected: Array[int] = []
	for nb in TreeDB.get_neighbors(s):
		expected.append(nb)
	expected.sort()
	assert_eq(frontier, expected, "frontier of an empty allocation = start neighbours")
	var alloc := _allocate_to([], _id_by_name("Arcane Potency"), cls)
	for id in TreeDB.get_allocatable(alloc, cls):
		assert_true(TreeDB.can_allocate(alloc, id, cls), "frontier node %d allocatable" % id)
	var count := 0
	for id in TreeDB.nodes:
		if TreeDB.can_allocate(alloc, id, cls):
			count += 1
	assert_eq(TreeDB.get_allocatable(alloc, cls).size(), count, "frontier complete")


func test_search() -> void:
	var hits := TreeDB.search("resolute")
	assert_has(hits, _id_by_name("Resolute Technique"), "name match")
	assert_eq(TreeDB.search("   ").size(), 0, "empty query")
	var fire := TreeDB.search("fire damage")
	assert_true(fire.size() >= 5, "matches tooltip lines (%d)" % fire.size())
	assert_eq(TreeDB.search("zzqqxx").size(), 0, "no match")


func test_queries_are_fast() -> void:
	var cls := "warrior"
	var alloc := _allocate_to([], _id_by_name("Troll's Blood"), cls)
	alloc = _allocate_to(alloc, _id_by_name("Titan's Grip"), cls)
	var targets: Array[int] = TreeDB.get_ids_by_type("notable")
	var t0 := Time.get_ticks_usec()
	for t in targets:
		TreeDB.find_path(alloc, t, cls)
		TreeDB.can_refund(alloc, alloc[-1], cls)
		TreeDB.find_node_at(TreeDB.get_node_position(t))
	var per := float(Time.get_ticks_usec() - t0) / targets.size()
	print("[tree] find_path + can_refund + find_node_at: %.0f us per target" % per)
	assert_true(per < 5000.0, "fast enough for per-frame hover (%.0f us)" % per)


func test_missing_or_bad_file_is_safe() -> void:
	var db: Node = load("res://scripts/autoload/tree_db.gd").new()
	add_child(db)
	assert_false(db.load_tree("res://data/does_not_exist.json"), "missing file")
	assert_false(db.is_loaded(), "empty")
	assert_eq(db.get_start_node("warrior"), -1, "no start")
	assert_eq(db.find_path([], 5, "warrior"), [], "no path")
	assert_false(db.can_allocate([], 5, "warrior"), "nothing allocatable")
	assert_eq(db.get_mods([5], "warrior"), [], "no mods")
	assert_eq(db.get_bounds(), Rect2(), "empty bounds")
	var path := "user://tree_bad.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"nodes\": [{\"id\": 0, \"type\": \"start\", \"class\": \"warrior\", \"links\": [1, 7]}, {\"id\": 1.0, \"name\": \"A\", \"links\": [0.0], \"mods\": [{\"stat\": \"strength\", \"op\": \"flat\", \"value\": 10}]}, \"junk\"]}")
	f.close()
	assert_true(db.load_tree(path), "partially valid file loads")
	assert_eq(db.get_start_node("warrior"), 0, "start found")
	assert_true(db.can_allocate([], 1, "warrior"), "float ids converted")
	assert_eq(db.get_neighbors(0), [1], "unknown link target dropped")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	assert_false(db.load_tree(path), "garbage file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	db.queue_free()

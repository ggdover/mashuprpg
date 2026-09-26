extends TestCase
## TreeDB consistency (§10 polish): only allocated nodes CONNECTED to the start extend the
## frontier (can_allocate == get_allocatable == 1-step find_path), get_refundable (articulation
## points, cached) == can_refund == a brute-force check, stable ids through tools/tree/id_map.json,
## and every themed cluster (incl. the three spurs) has >= 4 small nodes.

const CLASSES: Array[String] = ["warrior", "ranger", "sorcerer"]
const ID_MAP_PATH := "res://tools/tree/id_map.json"
## Ids that saves may reference: starts, notables and keystones (wave-1 numbering, frozen).
const PINNED_IDS := {
	"Warrior": 0, "Ranger": 1, "Sorcerer": 2, "Arcane Potency": 116, "Wellspring of Mana": 120,
	"Crystalline Aegis": 129, "Prismatic Barrier": 130, "Quickened Incantations": 134,
	"Mental Discipline": 137, "Elemental Conduit": 141, "Glacial Heart": 144,
	"Archmage's Insight": 147, "Keen Perception": 156, "Winter's Embrace": 160, "Serpent's Kiss": 168,
	"Stormcaller": 172, "Forked Lightning": 175, "Shadow Veil": 181, "Blightweaver": 185,
	"Assassin's Mark": 190, "Twin Fangs": 193, "Toxic Bloom": 197, "Deadeye": 203, "Fleet Footed": 210,
	"Treasure Hunter": 211, "Farshot": 218, "Sharpshooter": 219, "Hunter's Rhythm": 225,
	"Heavy Bolts": 229, "Crank and Load": 232, "Hail of Arrows": 237, "Blood Drinker": 244,
	"Hemorrhage": 248, "Titan's Grip": 256, "Ironwood Hide": 262, "Warlord's Command": 266,
	"Executioner": 269, "Butcher's Art": 275, "Vampiric Frenzy": 279, "Rending Wounds": 284,
	"Brute Force": 290, "Heart of the Oak": 294, "Blade Dancer": 300, "Headsman": 303,
	"Iron Skin": 310, "Unbreakable": 311, "Shield Wall": 315, "Sword and Board": 318,
	"Skullcrusher": 321, "Troll's Blood": 324, "Elemental Warding": 331, "Pyromancer": 335,
	"Cataclysm": 343, "Everburning Flame": 349, "Sacred Bastion": 355, "Deep Meditation": 359,
	"Staff Adept": 362, "Heart of Flame": 367, "Crimson Covenant": 371, "Mind over Matter": 374,
	"Pain Attunement": 377, "Glass Cannon": 380, "Acrobatics": 383, "Point Blank": 386,
	"Iron Reflexes": 389, "Resolute Technique": 392, "Unwavering Stance": 395, "Blood Magic": 398,
	"Convergence": 399,
}
## md5 of "<id>=<key>\n" for ids 0..405 (the 403 wave-1 nodes + the 3 spur smalls): any
## renumbering of an existing node changes it.
const ID_KEY_FINGERPRINT := "c2fd274e42be08883c602453a5700003"
const SPUR_GROUPS: Array[String] = ["toxic_bloom", "vampiric_frenzy", "crimson_covenant"]


func _id_by_name(node_name: String) -> int:
	for id in TreeDB.nodes:
		if TreeDB.nodes[id]["name"] == node_name:
			return id
	fail("no node named %s" % node_name)
	return -1


func _key(key: String) -> int:
	var id := TreeDB.get_id_by_key(key)
	if id < 0:
		fail("no node with key %s" % key)
	return id


func _allocate_to(allocated: Array, target: int, cls: String) -> Array[int]:
	var out: Array[int] = []
	out.assign(allocated)
	out.append_array(TreeDB.find_path(out, target, cls))
	return out


## Independent reference: start + allocated nodes reachable through allocated non-start nodes.
func _reach(alloc: Dictionary, start: int) -> Dictionary:
	var seen := {start: true}
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nb in TreeDB.nodes[cur]["links"]:
			if not seen.has(nb) and alloc.has(nb) and not TreeDB.is_start(nb):
				seen[nb] = true
				queue.append(nb)
	return seen


## Brute-force refundable set: removing the node keeps every other connected node connected;
## entries not connected to the start (strays) are always refundable.
func _brute_refundable(allocated: Array, cls: String) -> Array[int]:
	var start := TreeDB.get_start_node(cls)
	var alloc := {}
	for v in allocated:
		alloc[int(v)] = true
	var before := _reach(alloc, start)
	var out: Array[int] = []
	for id in alloc:
		var ok := true
		if before.has(id) and id != start:
			var without := alloc.duplicate()
			without.erase(id)
			var after := _reach(without, start)
			for n in before:
				if n != id and not after.has(n):
					ok = false
					break
		if ok:
			out.append(id)
	out.sort()
	return out


## Deterministic random allocations grown from the frontier (so they contain cycles through
## rings, wheels and loops), plus strays.
func _sample_allocations(cls: String, rng: RandomNumberGenerator, count: int) -> Array:
	var out: Array = [[]]
	for i in count:
		var alloc: Array[int] = []
		var size := rng.randi_range(3, 140)
		while alloc.size() < size:
			var frontier := TreeDB.get_allocatable(alloc, cls)
			if frontier.is_empty():
				break
			alloc.append(frontier[rng.randi_range(0, frontier.size() - 1)])
		out.append(alloc)
	return out


func _with_strays(alloc: Array, cls: String) -> Array:
	var out: Array = alloc.duplicate()
	var connected := {}
	for id in TreeDB.get_connected(alloc, cls):
		connected[id] = true
	# A far keystone + its spur neighbour (disconnected unless the allocation reaches them),
	# an unknown id, a duplicate and another class's start.
	for name in ["Iron Reflexes", "Glass Cannon", "Blood Magic"]:
		var k := _id_by_name(name)
		if not connected.has(k) and not out.has(k):
			out.append(k)
			for nb in TreeDB.get_neighbors(k):
				if not connected.has(nb) and not out.has(nb):
					out.append(nb)
			break
	out.append(987654)
	if not alloc.is_empty():
		out.append(alloc[0])
	for other in CLASSES:
		if other != cls:
			out.append(TreeDB.get_start_node(other))
			break
	return out


# ------------------------------------------------------------------------------------------------
# 1. can_allocate / get_allocatable / find_path agree (connected set only)
# ------------------------------------------------------------------------------------------------

func test_disconnected_nodes_do_not_extend_the_frontier() -> void:
	var cls := "sorcerer"
	var start := TreeDB.get_start_node(cls)
	var far := _id_by_name("Iron Reflexes")
	var spur: int = TreeDB.get_neighbors(far)[0]
	var alloc: Array = [TreeDB.get_neighbors(start)[0], far]
	assert_false(TreeDB.can_allocate(alloc, spur, cls), "next to a stray keystone only: not allocatable")
	assert_false(TreeDB.get_allocatable(alloc, cls).has(spur), "not in the frontier")
	assert_true(TreeDB.find_path(alloc, spur, cls).size() > 1, "find_path needs a real route")
	assert_false(TreeDB.can_allocate(alloc, far, cls), "allocated (even stray) nodes can't be allocated again")
	assert_eq(TreeDB.find_path(alloc, far, cls), [], "nor pathed to")
	# Once the allocation actually reaches the spur, the stray becomes part of it.
	var reach := _allocate_to([TreeDB.get_neighbors(start)[0]], spur, cls)
	reach.pop_back()
	reach.append(far)
	assert_true(TreeDB.can_allocate(reach, spur, cls), "connected neighbour -> allocatable")
	assert_true(TreeDB.get_allocatable(reach, cls).has(spur), "in the frontier")
	assert_eq(TreeDB.find_path(reach, spur, cls), [spur], "1-step path")
	reach.append(spur)
	assert_has(TreeDB.get_connected(reach, cls), far, "keystone joined the allocation")


func test_other_class_start_is_never_passed() -> void:
	# Warrior walks along the inner ring to the ranger's 70-degree exit chain, up to the node next
	# to the ranger start. A corrupt allocation also holds the ranger start and the first node of
	# the ranger's -10-degree exit: they must not join (nothing is passed through a start).
	var cls := "warrior"
	var rs := TreeDB.get_start_node("ranger")
	var near_exit := _key("path[start:ranger>ring_inner:8]:0")
	var far_exit := _key("path[start:ranger>ring_inner:4]:0")
	var behind := _key("path[start:ranger>ring_inner:4]:1")
	var alloc := _allocate_to([], near_exit, cls)
	assert_eq(alloc[-1], near_exit, "path to the ranger exit")
	assert_false(alloc.has(_key("ring_inner:4")), "the path stays away from the far exit")
	var corrupt: Array = alloc.duplicate()
	corrupt.append(rs)
	corrupt.append(far_exit)
	var connected := TreeDB.get_connected(corrupt, cls)
	assert_false(connected.has(rs), "other start not connected")
	assert_false(connected.has(far_exit), "nothing behind the other start")
	assert_eq(Array(TreeDB.sanitize_allocation(corrupt, cls)), Array(alloc), "sanitize drops both")
	assert_false(TreeDB.can_allocate(corrupt, behind, cls), "no frontier behind the other start")
	assert_false(TreeDB.get_allocatable(corrupt, cls).has(behind), "not in the frontier")
	assert_ne(TreeDB.find_path(corrupt, behind, cls).size(), 1, "no 1-step path")
	assert_true(TreeDB.can_refund(corrupt, rs, cls), "stray start entry can be cleaned up")
	assert_true(TreeDB.can_refund(corrupt, far_exit, cls), "stray behind it too")
	assert_false(TreeDB.can_refund(corrupt, alloc[-2], cls), "the real chain still holds its end")


func test_allocation_queries_agree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var checked := 0
	for cls in CLASSES:
		for alloc in _sample_allocations(cls, rng, 4):
			for variant in [alloc, _with_strays(alloc, cls)]:
				var frontier := TreeDB.get_allocatable(variant, cls)
				var fset := {}
				for id in frontier:
					fset[id] = true
				for id in TreeDB.nodes:
					var can := TreeDB.can_allocate(variant, id, cls)
					var one_step := TreeDB.find_path(variant, id, cls).size() == 1
					if can != fset.has(id) or can != one_step:
						fail("%s node %d: can_allocate %s, frontier %s, 1-step path %s (alloc %d)" % [
							cls, id, can, fset.has(id), one_step, (variant as Array).size()])
						return
					checked += 1
	print("    [info] %d (allocation, node) pairs agree" % checked)
	assert_true(checked > 10000, "enough cases")


# ------------------------------------------------------------------------------------------------
# 2. get_refundable
# ------------------------------------------------------------------------------------------------

func test_refundable_matches_brute_force() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var cases := 0
	for cls in CLASSES:
		for alloc in _sample_allocations(cls, rng, 12):
			for variant in [alloc, _with_strays(alloc, cls)]:
				var want := _brute_refundable(variant, cls)
				var got := TreeDB.get_refundable(variant, cls)
				assert_eq(Array(got), Array(want), "%s refundable set (%d allocated)" % [cls, (variant as Array).size()])
				for v in variant:
					assert_eq(TreeDB.can_refund(variant, int(v), cls), want.has(int(v)), "can_refund %d agrees" % int(v))
				cases += 1
	assert_eq(cases, 78, "cases")


func test_refundable_on_cycles() -> void:
	# Loop cluster fully allocated: everything but the entry (and the path to it) is refundable.
	var cls := "warrior"
	var notable := _id_by_name("Heart of the Oak")
	var group: String = TreeDB.nodes[notable]["group"]
	var alloc := _allocate_to([], notable, cls)
	var path_len := alloc.size()
	for id in TreeDB.nodes:
		if TreeDB.nodes[id]["group"] == group and not alloc.has(id):
			alloc = _allocate_to(alloc, id, cls)
	var refundable := TreeDB.get_refundable(alloc, cls)
	for i in path_len - 1:
		if TreeDB.nodes[alloc[i]]["group"] != group:
			assert_false(refundable.has(alloc[i]), "path node %d before the loop holds it" % alloc[i])
	var rim := 0
	for id in alloc:
		if TreeDB.nodes[id]["group"] == group and refundable.has(id):
			rim += 1
	assert_eq(rim, 5, "5 of the 6 loop nodes (all but the entry) are refundable")
	assert_eq(Array(refundable), Array(_brute_refundable(alloc, cls)), "loop: brute force agrees")
	# A cycle through the start: the -40 and 0 degree exits joined along the inner ring.
	var cyc: Array[int] = []
	for key in ["path[start:warrior>ring_inner:10]:0", "path[start:warrior>ring_inner:10]:1", "ring_inner:10",
			"ring_inner:11", "ring_inner:12", "path[start:warrior>ring_inner:12]:1"]:
		var id := _key(key)
		assert_true(TreeDB.can_allocate(cyc, id, cls), "%s allocatable in order" % key)
		cyc.append(id)
	assert_eq(Array(TreeDB.get_refundable(cyc, cls)), [cyc[-1]] as Array, "open chain: only its end")
	var closing := _key("path[start:warrior>ring_inner:12]:0")
	assert_true(TreeDB.can_allocate(cyc, closing, cls), "closing node next to the start")
	cyc.append(closing)
	var sorted_cyc := cyc.duplicate()
	sorted_cyc.sort()
	assert_eq(Array(TreeDB.get_refundable(cyc, cls)), Array(sorted_cyc), "closed cycle: every node refundable")
	# A branch hanging off the cycle makes its attachment point a cut vertex.
	cyc.append(_key("ring_inner:13"))
	var with_branch := TreeDB.get_refundable(cyc, cls)
	assert_false(with_branch.has(_key("ring_inner:12")), "attachment point of the branch holds it")
	assert_eq(with_branch.size(), cyc.size() - 1, "everything else stays refundable")
	assert_eq(Array(with_branch), Array(_brute_refundable(cyc, cls)), "brute force agrees")
	for id in cyc:
		assert_eq(TreeDB.can_refund(cyc, id, cls), with_branch.has(id), "can_refund %d agrees" % id)


func test_refundable_edge_cases() -> void:
	assert_eq(TreeDB.get_refundable([], "warrior").size(), 0, "empty allocation")
	assert_eq(TreeDB.get_refundable([5, 6], "necromancer").size(), 0, "unknown class")
	var cls := "ranger"
	var alloc := _allocate_to([], _id_by_name("Deadeye"), cls)
	var r := TreeDB.get_refundable(alloc, cls)
	assert_eq(Array(r), [alloc[-1]] as Array, "a single chain: only its end")
	assert_true(r.is_typed(), "Array[int]")
	# Floats (JSON) and duplicates are tolerated.
	var floats: Array = []
	for id in alloc:
		floats.append(float(id))
	floats.append(float(alloc[0]))
	assert_eq(Array(TreeDB.get_refundable(floats, cls)), [alloc[-1]] as Array, "float ids")
	# Returned arrays are copies; the caller's array may change between calls.
	r.clear()
	assert_eq(TreeDB.get_refundable(alloc, cls).size(), 1, "cache returns copies")
	var f := TreeDB.get_allocatable(alloc, cls)
	var n0 := f.size()
	f.clear()
	assert_eq(TreeDB.get_allocatable(alloc, cls).size(), n0, "frontier copies too")
	var last: int = alloc.pop_back()
	assert_eq(Array(TreeDB.get_refundable(alloc, cls)), [alloc[-1]] as Array, "in-place change seen")
	alloc.append(last)
	var other_exit := -1
	for nb in TreeDB.get_neighbors(TreeDB.get_start_node(cls)):
		if not alloc.has(nb):
			other_exit = nb
			break
	alloc[alloc.size() - 1] = other_exit  # in place: same size, different content
	var branch := TreeDB.get_refundable(alloc, cls)
	assert_eq(Array(branch), Array(_brute_refundable(alloc, cls)), "in-place replacement seen")
	assert_eq(branch.size(), 2, "chain end + a second exit are both leaves (%s)" % [branch])


func test_refund_queries_are_fast() -> void:
	var cls := "sorcerer"
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var allocs := _sample_allocations(cls, rng, 20)
	# Uncached: each distinct allocation analysed once (clear the cache by loading).
	TreeDB.load_tree()
	var t0 := Time.get_ticks_usec()
	var total := 0
	for alloc in allocs:
		total += TreeDB.get_refundable(alloc, cls).size()
	var uncached := float(Time.get_ticks_usec() - t0) / allocs.size()
	# Cached: the same allocation every frame, with the other per-frame queries.
	var big: Array = allocs[0]
	for alloc in allocs:
		if (alloc as Array).size() > big.size():
			big = alloc
	TreeDB.get_refundable(big, cls)
	t0 = Time.get_ticks_usec()
	for i in 500:
		TreeDB.get_refundable(big, cls)
		TreeDB.can_refund(big, int(big[i % big.size()]), cls)
		TreeDB.get_allocatable(big, cls)
	var cached := float(Time.get_ticks_usec() - t0) / 500.0
	# can_allocate for every node with one allocation (a UI highlighting the frontier by hand).
	t0 = Time.get_ticks_usec()
	var allocatable := 0
	for id in TreeDB.nodes:
		if TreeDB.can_allocate(big, id, cls):
			allocatable += 1
	var per_node := float(Time.get_ticks_usec() - t0) / TreeDB.nodes.size()
	print("    [info] can_allocate: %.1f us per node over the whole tree (%d allocated, %d allocatable)" % [per_node, big.size(), allocatable])
	assert_true(per_node < 60.0, "can_allocate cheap (%.1f us)" % per_node)
	print("    [info] get_refundable: %.0f us uncached (avg over %d allocations, %d refundable), %.1f us cached + can_refund + frontier (%d allocated)" % [
		uncached, allocs.size(), total, cached, big.size()])
	assert_true(uncached < 4000.0, "analysis fast (%.0f us)" % uncached)
	assert_true(cached < 400.0, "cached per-frame queries fast (%.1f us)" % cached)


# ------------------------------------------------------------------------------------------------
# 3. Stable ids
# ------------------------------------------------------------------------------------------------

func test_ids_match_the_checked_in_id_map() -> void:
	assert_true(FileAccess.file_exists(ID_MAP_PATH), "id map exists")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ID_MAP_PATH))
	assert_true(data is Dictionary and (data as Dictionary).get("ids") is Dictionary, "id map format")
	if not (data is Dictionary):
		return
	var ids: Dictionary = data["ids"]
	var max_id := -1
	var used := {}
	for key in ids:
		var v := int(ids[key])
		assert_false(used.has(v), "id %d used once in the map" % v)
		used[v] = true
		max_id = maxi(max_id, v)
	assert_true(int(data["next_id"]) > max_id, "next_id beyond every id")
	for id in TreeDB.nodes:
		var key := TreeDB.get_node_key(id)
		assert_ne(key, "", "node %d has a key" % id)
		assert_eq(int(ids.get(key, -1)), id, "map id of %s" % key)
		assert_eq(TreeDB.get_id_by_key(key), id, "get_id_by_key(%s)" % key)
	assert_eq(TreeDB.get_id_by_key("no:such:key"), -1, "unknown key")
	assert_eq(TreeDB.get_node_key(-3), "", "unknown id")


func test_existing_ids_never_change() -> void:
	for node_name in PINNED_IDS:
		var id: int = PINNED_IDS[node_name]
		assert_eq(TreeDB.get_passive(id).get("name", ""), node_name, "id %d is still %s" % [id, node_name])
	var lines := ""
	for id in 406:
		assert_true(TreeDB.nodes.has(id), "id %d exists" % id)
		lines += "%d=%s\n" % [id, TreeDB.get_node_key(id)]
	assert_eq(lines.md5_text(), ID_KEY_FINGERPRINT, "ids 0..405 keep their keys (regenerate with the checked-in tools/tree/id_map.json)")
	assert_eq(TreeDB.get_id_by_key("start:warrior"), 0, "start ids")
	assert_eq(TreeDB.get_id_by_key("keystone:resolute_technique"), 392, "keystone id")


# ------------------------------------------------------------------------------------------------
# 4. Cluster sizes (the three spurs got a 4th small node, appended with new ids)
# ------------------------------------------------------------------------------------------------

func test_spur_clusters_have_four_smalls() -> void:
	var appended := {"toxic_bloom": 403, "vampiric_frenzy": 404, "crimson_covenant": 405}
	for group in SPUR_GROUPS:
		var smalls: Array[String] = []
		var notable := -1
		for id in TreeDB.nodes:
			var n: Dictionary = TreeDB.nodes[id]
			if n["group"] != group:
				continue
			if n["type"] == "notable":
				notable = id
			else:
				smalls.append(TreeDB.get_node_key(id))
		smalls.sort()
		assert_eq(Array(smalls), ["%s:spur:0" % group, "%s:spur:1" % group, "%s:spur:2" % group, "%s:spur:3" % group], group)
		var fourth := TreeDB.get_id_by_key("%s:spur:3" % group)
		assert_eq(fourth, appended[group], "new node got an appended id")
		assert_eq(TreeDB.get_neighbors(notable), [fourth], "the notable ends the spur")
		assert_eq(TreeDB.get_region(fourth), TreeDB.get_region(notable), "same region")
		assert_eq(TreeDB.get_node_type(fourth), "small", "a themed small node")
	# Every themed cluster (a group with a notable, except the centre nexus) has >= 4 smalls.
	var smalls_per_group := {}
	var has_notable := {}
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		if n["type"] == "notable":
			has_notable[n["group"]] = true
		elif n["type"] in ["small", "attribute"]:
			smalls_per_group[n["group"]] = int(smalls_per_group.get(n["group"], 0)) + 1
	for group in has_notable:
		if group == "convergence":
			continue
		assert_true(int(smalls_per_group.get(group, 0)) >= 4, "cluster %s has %d smalls" % [group, smalls_per_group.get(group, 0)])
	assert_true(has_notable.size() >= 40, "clusters found (%d)" % has_notable.size())

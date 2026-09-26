extends TestCase
## Passive tree data (data/passive_tree.json through TreeDB): counts per type, schema, stats valid
## in StatDefs, value rules, keystones, starts, attribute rules, connectivity. §10.

const MAIN_ATTR := {"warrior": "strength", "ranger": "dexterity", "sorcerer": "intelligence"}
const START_ANGLE := {"sorcerer": -90.0, "warrior": 150.0, "ranger": 30.0}
## Stats allowed as "flat" on the tree: attributes, crit multiplier, resistances (§10) plus stats
## that only exist as flat values (block, evade, ailment chances, leech, regen %, pierce, ...).
const FLAT_OK: Array[String] = [
	"strength", "dexterity", "intelligence", "all_attributes", "crit_multiplier",
	"fire_resistance", "cold_resistance", "lightning_resistance", "chaos_resistance", "elemental_resistance",
	"block_chance", "evade_chance", "physical_damage_reduction", "life_leech", "mana_leech",
	"life_regen_percent", "life_on_kill", "mana_on_kill", "life_on_hit",
	"ignite_chance", "freeze_chance", "shock_chance", "bleed_chance", "poison_chance",
	"pierce", "chain", "additional_projectiles",
]
const KEYSTONES := {
	"Blood Magic": [["blood_magic", "flag", 0], ["max_mana", "more", -100]],
	"Iron Reflexes": [["iron_reflexes", "flag", 0]],
	"Mind over Matter": [["mind_over_matter", "flag", 0]],
	"Resolute Technique": [["no_crit", "flag", 0], ["attack_damage", "more", 30]],
	"Point Blank": [["point_blank", "flag", 0]],
	"Pain Attunement": [["pain_attunement", "flag", 0]],
	"Unwavering Stance": [["cannot_evade", "flag", 0], ["armour", "more", 30], ["physical_damage_reduction", "flat", 10]],
	"Glass Cannon": [["damage", "more", 50], ["max_life", "more", -40]],
	"Acrobatics": [["evade_chance", "flat", 30], ["armour", "more", -50], ["max_energy_shield", "more", -50]],
}


func _count_types() -> Dictionary:
	var c := {"start": 0, "small": 0, "attribute": 0, "notable": 0, "keystone": 0}
	for id in TreeDB.nodes:
		var t: String = TreeDB.nodes[id]["type"]
		c[t] = int(c.get(t, 0)) + 1
	return c


## BFS order from a start; never passes through other class starts.
func _bfs_order(start: int) -> Array[int]:
	var order: Array[int] = [start]
	var seen := {start: true}
	var head := 0
	while head < order.size():
		var cur := order[head]
		head += 1
		var links: Array = TreeDB.nodes[cur]["links"].duplicate()
		links.sort()
		for nb in links:
			if seen.has(nb) or TreeDB.nodes[nb]["type"] == "start":
				continue
			seen[nb] = true
			order.append(nb)
	return order


func test_loaded_with_int_ids() -> void:
	assert_true(TreeDB.is_loaded(), "tree loaded")
	for id in TreeDB.nodes:
		assert_eq(typeof(id), TYPE_INT, "node key type")
		var n: Dictionary = TreeDB.nodes[id]
		assert_eq(typeof(n["id"]), TYPE_INT, "id type")
		assert_eq(n["id"], id, "id matches key")
		for l in n["links"]:
			assert_eq(typeof(l), TYPE_INT, "link type on %d" % id)
	assert_eq(TreeDB.get_all_ids().size(), TreeDB.nodes.size(), "get_all_ids")
	assert_eq(TreeDB.get_passive(-12345), {}, "unknown id")


func test_counts_per_type() -> void:
	var c := _count_types()
	var total := TreeDB.nodes.size()
	assert_eq(c["start"], 3, "starts")
	assert_eq(c["keystone"], 9, "keystones")
	assert_between(c["notable"], 50, 60, "notables (~55)")
	assert_true(c["attribute"] >= 60, "attribute nodes >= 60 (got %d)" % c["attribute"])
	assert_between(c["small"] + c["attribute"], 290, 350, "small + attribute (~300)")
	assert_between(total, 380, 430, "total (~400)")
	assert_eq(c["start"] + c["small"] + c["attribute"] + c["notable"] + c["keystone"], total, "only known types")
	assert_eq(TreeDB.get_ids_by_type("keystone").size(), 9, "get_ids_by_type")


func test_start_nodes() -> void:
	for cls in MAIN_ATTR:
		var s := TreeDB.get_start_node(cls)
		assert_true(s >= 0, "start for %s" % cls)
		var n: Dictionary = TreeDB.get_passive(s)
		assert_eq(n.get("type"), "start", "type")
		assert_eq(n.get("class"), cls, "class")
		assert_eq((n["mods"] as Array).size(), 0, "start mods empty")
		assert_eq(TreeDB.get_node_lines(s).size(), 0, "start has no lines")
		assert_true(TreeDB.is_start(s), "is_start")
		assert_eq(TreeDB.get_start_class(s), cls, "get_start_class")
		var p := TreeDB.get_node_position(s)
		assert_between(p.length(), 330.0, 370.0, "start radius %s" % cls)
		var ang := rad_to_deg(p.angle())
		assert_near(wrapf(ang - float(START_ANGLE[cls]), -180.0, 180.0), 0.0, 2.0, "start angle %s" % cls)
	assert_eq(TreeDB.get_start_node("necromancer"), -1, "unknown class")
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		if n["type"] != "start":
			assert_false(n.has("class"), "class only on starts (%d)" % id)


func test_schema_and_links() -> void:
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		assert_true(str(n["name"]) != "", "name on %d" % id)
		assert_has(TreeDB.REGIONS, n["region"], "region of %d" % id)
		var links: Array = n["links"]
		assert_true(links.size() > 0, "node %d isolated" % id)
		var seen := {}
		for l in links:
			assert_true(TreeDB.nodes.has(l), "link %d->%d target exists" % [id, l])
			assert_ne(l, id, "self link")
			assert_false(seen.has(l), "duplicate link %d->%d" % [id, l])
			seen[l] = true
			if TreeDB.nodes.has(l):
				assert_has(TreeDB.nodes[l]["links"], id, "link %d-%d symmetric" % [id, l])
		if n["type"] != "start":
			assert_true((n["mods"] as Array).size() > 0, "mods on %d" % id)
			assert_true(TreeDB.get_node_lines(id).size() > 0, "lines on %d" % id)
		if n["type"] == "notable":
			assert_between((n["mods"] as Array).size(), 2, 3, "notable %s mods" % n["name"])
	# Neighbours API mirrors links.
	var s := TreeDB.get_start_node("warrior")
	assert_eq(TreeDB.get_neighbors(s).size(), (TreeDB.nodes[s]["links"] as Array).size(), "get_neighbors")
	assert_eq(TreeDB.get_neighbors(-1).size(), 0, "neighbours of unknown")


func test_all_stats_valid() -> void:
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		for m in n["mods"]:
			var stat: String = m.get("stat", "")
			var op: String = m.get("op", "")
			assert_true(StatDefs.STATS.has(stat), "unknown stat '%s' on %s" % [stat, n["name"]])
			assert_false(StatDefs.is_local(stat), "local stat %s on the tree" % stat)
			assert_has(["flat", "inc", "more", "flag"], op, "op on %s" % n["name"])
			assert_eq(typeof(m.get("value")), TYPE_FLOAT, "value type on %s" % n["name"])
			if op == "flat":
				assert_has(FLAT_OK, stat, "flat %s on %s" % [stat, n["name"]])
			if op == "more" or op == "flag":
				assert_eq(n["type"], "keystone", "%s %s only on keystones (%s)" % [op, stat, n["name"]])
			if op == "flag":
				assert_true(StatDefs.get_info(stat).has("flag"), "flag stat %s has flag text" % stat)


func test_small_node_values() -> void:
	# §10 value bands for single-mod small nodes.
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		if n["type"] != "small" or (n["mods"] as Array).size() != 1:
			continue
		var m: Dictionary = n["mods"][0]
		var stat: String = m["stat"]
		var v: float = m["value"]
		var label := "%s (%s %s %s)" % [n["name"], stat, m["op"], v]
		if stat == "max_life":
			assert_between(v, 5, 8, label)
		elif stat in ["max_mana", "max_energy_shield"]:
			assert_between(v, 8, 12, label)
		elif stat in ["armour", "evasion"]:
			assert_between(v, 12, 18, label)
		elif stat in ["attack_speed", "cast_speed", "movement_speed"]:
			assert_between(v, 3, 5, label)
		elif stat == "crit_multiplier":
			assert_between(v, 10, 15, label)
		elif stat.ends_with("_resistance"):
			assert_between(v, 6, 8, label)
		elif stat == "damage" or stat.ends_with("_damage"):
			assert_between(v, 8, 12, label)
			assert_eq(m["op"], "inc", label)


func test_attribute_nodes() -> void:
	var count := 0
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		if n["type"] != "attribute":
			continue
		count += 1
		var mods: Array = n["mods"]
		assert_eq(mods.size(), 1, "attribute node %d has one mod" % id)
		assert_has(["strength", "dexterity", "intelligence"], mods[0]["stat"], "attribute stat")
		assert_eq(mods[0]["op"], "flat", "attribute op")
		assert_eq(mods[0]["value"], 10.0, "+10")
		assert_eq(n["name"], StatDefs.get_stat_name(mods[0]["stat"]), "named after its attribute")
	assert_true(count >= 60, ">= 60 attribute nodes (got %d)" % count)


func test_first_twelve_nodes_give_main_attribute() -> void:
	for cls in MAIN_ATTR:
		var order := _bfs_order(TreeDB.get_start_node(cls))
		var hits := 0
		for i in range(1, mini(13, order.size())):
			for m in TreeDB.nodes[order[i]]["mods"]:
				if m["stat"] == MAIN_ATTR[cls]:
					hits += 1
		assert_true(hits >= 3, "%s: %d main-attribute nodes in the first 12" % [cls, hits])


func test_every_node_reachable_from_every_start() -> void:
	for cls in MAIN_ATTR:
		var order := _bfs_order(TreeDB.get_start_node(cls))
		var reached := {}
		for id in order:
			reached[id] = true
		var missing := 0
		for id in TreeDB.nodes:
			if TreeDB.nodes[id]["type"] != "start" and not reached.has(id):
				missing += 1
		assert_eq(missing, 0, "%s unreachable nodes" % cls)


func test_keystones_match_spec() -> void:
	var found := {}
	for id in TreeDB.get_ids_by_type("keystone"):
		var n: Dictionary = TreeDB.nodes[id]
		assert_true(KEYSTONES.has(n["name"]), "unexpected keystone %s" % n["name"])
		if not KEYSTONES.has(n["name"]):
			continue
		found[n["name"]] = true
		var want: Array = KEYSTONES[n["name"]]
		var mods: Array = n["mods"]
		assert_eq(mods.size(), want.size(), "%s mod count" % n["name"])
		for i in mini(mods.size(), want.size()):
			assert_eq(mods[i]["stat"], want[i][0], "%s stat %d" % [n["name"], i])
			assert_eq(mods[i]["op"], want[i][1], "%s op %d" % [n["name"], i])
			if want[i][1] != "flag":
				assert_near(mods[i]["value"], want[i][2], 0.001, "%s value %d" % [n["name"], i])
	assert_eq(found.size(), 9, "all 9 keystones")


func test_unique_names_and_regions() -> void:
	var names := {}
	var per_region := {}
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		if n["type"] in ["notable", "keystone"]:
			assert_false(names.has(n["name"]), "duplicate name %s" % n["name"])
			names[n["name"]] = true
			per_region[n["region"]] = int(per_region.get(n["region"], 0)) + 1
	for r in ["str", "dex", "int", "str_dex", "dex_int", "int_str"]:
		assert_true(int(per_region.get(r, 0)) >= 8, "region %s has >= 8 notables/keystones (%d)" % [r, per_region.get(r, 0)])


func test_class_directions_exist() -> void:
	# Each class has its advertised build directions somewhere on the tree.
	var want := {
		"two_handed_damage": 2, "block_chance": 3, "bleed_chance": 4,       # warrior
		"bow_damage": 2, "crossbow_damage": 2, "pierce": 1, "poison_chance": 3,  # ranger
		"fire_damage": 3, "cold_damage": 2, "lightning_damage": 2, "max_energy_shield": 4,  # sorcerer
	}
	var have := {}
	for id in TreeDB.get_ids_by_type("notable"):
		for m in TreeDB.nodes[id]["mods"]:
			have[m["stat"]] = int(have.get(m["stat"], 0)) + 1
	for stat in want:
		assert_true(int(have.get(stat, 0)) >= int(want[stat]), "notables with %s: %d" % [stat, have.get(stat, 0)])

extends TestCase
## Drop tables (§9.5), loot spawning and GroundItem behaviour (§9.6).


## Deterministic character double (independent of the kernel's CharacterData implementation).
class FakeChar extends CharacterData:
	var received: Array = []
	var full := false
	var gold_added := 0

	func add_to_inventory(it: Item) -> bool:
		if full:
			return false
		received.append(it)
		return true

	func add_gold(amount: int) -> void:
		gold_added += amount
		gold += amount


func _items(drops: Array) -> Array:
	var out: Array = []
	for d: Dictionary in drops:
		if d["type"] == "item":
			out.append(d["item"])
	return out


func _gold(drops: Array) -> Array:
	var out: Array = []
	for d: Dictionary in drops:
		if d["type"] == "gold":
			out.append(int(d["amount"]))
	return out


func test_drop_format() -> void:
	seed(10)
	for i in 50:
		for d: Variant in LootSystem.roll_monster_drops(12, 3):
			assert_true(d is Dictionary, "drop is a dict")
			assert_has(["item", "gold"], d["type"], "drop type")
			if d["type"] == "item":
				assert_true(d["item"] is Item, "item drop has an Item")
				assert_eq((d["item"] as Item).item_level, 12, "item level = monster level")
			else:
				assert_true(d["amount"] is int and d["amount"] >= 1, "gold amount int >= 1")


func test_normal_and_magic_monster_rates() -> void:
	seed(11)
	for r in [0, 1]:
		var n := 5000
		var items := 0
		var gold_piles := 0
		for i in n:
			var drops := LootSystem.roll_monster_drops(10, r)
			items += _items(drops).size()
			gold_piles += _gold(drops).size()
		var exp_item: float = [0.14, 0.35][r]
		var exp_gold: float = [0.20, 0.40][r]
		assert_between(float(items) / n, exp_item - 0.025, exp_item + 0.025, "rarity %d item rate %.3f" % [r, float(items) / n])
		assert_between(float(gold_piles) / n, exp_gold - 0.025, exp_gold + 0.025, "rarity %d gold rate" % r)


func test_rare_monster_drops() -> void:
	seed(12)
	var total := 0
	var n := 1500
	var threes := 0
	for i in n:
		var drops := LootSystem.roll_monster_drops(20, 2)
		var k := _items(drops).size()
		assert_between(k, 1, 3, "rare monster drops 1-3 items")
		assert_eq(_gold(drops).size(), 2, "rare monster: 2 gold piles")
		total += k
		if k == 3:
			threes += 1
	assert_between(float(total) / n, 1.85, 2.15, "rare monster mean items (1.5 + 0.5)")
	assert_between(float(threes) / n, 0.2, 0.3, "3rd item 50% of the time (x 1/2 for 2 base)")


func test_boss_drops() -> void:
	seed(13)
	var n := 400
	var uniques := 0
	for i in n:
		var drops := LootSystem.roll_monster_drops(30, 3)
		var items := _items(drops)
		assert_between(items.size(), 4, 6, "boss drops 4-6 items")
		assert_eq(_gold(drops).size(), 5, "boss: 5 gold piles")
		var has_rare := false
		for it: Item in items:
			if it.rarity >= Item.Rarity.RARE:
				has_rare = true
			if it.rarity == Item.Rarity.UNIQUE:
				uniques += 1
		assert_true(has_rare, "boss drops >= 1 rare")
	assert_between(float(uniques) / n, 0.2, 0.42, "boss unique chance ~25%% (+ rolled uniques): %.2f" % (float(uniques) / n))


func test_quantity_rarity_and_gold_bonus() -> void:
	seed(14)
	var n := 5000
	var items := 0
	for i in n:
		items += _items(LootSystem.roll_monster_drops(10, 0, 0.0, 100.0)).size()
	assert_between(float(items) / n, 0.25, 0.31, "+100% quantity doubles the chance")
	var boss_items := 0
	for i in 200:
		boss_items += _items(LootSystem.roll_monster_drops(10, 3, 0.0, 50.0)).size()
	assert_between(float(boss_items) / 200.0, 6.9, 8.1, "+50% quantity: boss 5 × 1.5 items")
	# Rarity bonus shifts rarity.
	var plain := 0
	var lucky := 0
	for i in 3000:
		for it: Item in _items(LootSystem.roll_monster_drops(10, 1, 0.0)):
			if it.rarity >= Item.Rarity.MAGIC:
				plain += 1
		for it: Item in _items(LootSystem.roll_monster_drops(10, 1, 200.0)):
			if it.rarity >= Item.Rarity.MAGIC:
				lucky += 1
	assert_true(lucky > plain * 1.3, "rarity bonus gives more magic+ items (%d vs %d)" % [lucky, plain])
	# Gold find.
	var g0 := 0.0
	var g1 := 0.0
	for i in 3000:
		g0 += LootSystem.roll_gold(20)
		g1 += LootSystem.roll_gold(20, 100.0)
	assert_between(g1 / g0, 1.85, 2.15, "+100% gold find doubles gold")
	assert_between(g0 / 3000.0, Balance.gold_drop(20) * 0.95, Balance.gold_drop(20) * 1.05, "average pile = Balance.gold_drop")


func test_chest_drops() -> void:
	seed(15)
	var spec := [[1, 2, Item.Rarity.NORMAL], [2, 4, Item.Rarity.MAGIC], [3, 5, Item.Rarity.RARE]]
	for tier in 3:
		for i in 200:
			var drops := LootSystem.roll_chest_drops(14, tier)
			var items := _items(drops)
			assert_between(items.size(), spec[tier][0], spec[tier][1], "chest tier %d item count" % tier)
			assert_true(_gold(drops).size() >= 1, "chest has gold")
			var best := 0
			for it: Item in items:
				best = maxi(best, it.rarity)
				assert_eq(it.item_level, 14, "chest item level")
			assert_true(best >= spec[tier][2], "chest tier %d minimum rarity" % tier)


func test_spawn_drops_into_world() -> void:
	seed(16)
	var w := await make_world()
	var spawned: Array = []
	var cb := func(n: Node) -> void: spawned.append(n)
	Events.loot_spawned.connect(cb)
	var drops := LootSystem.roll_monster_drops(10, 3)
	var center := Vector3(4, 0, 6)
	LootSystem.spawn_drops(drops, center)
	Events.loot_spawned.disconnect(cb)
	assert_eq(spawned.size(), drops.size(), "loot_spawned per drop")
	for n: Node in spawned:
		assert_true(n is GroundItem, "GroundItem spawned")
		assert_eq(n.get_parent(), w.dynamic_root, "added through add_dynamic")
		assert_true(n.is_in_group("loot") and n.is_in_group("interactable"), "groups")
		assert_eq((n as GroundItem).collision_layer, 8, "loot layer")
		var p := (n as Node3D).global_position
		assert_near(p.y, 0.0, 0.001, "on the floor")
		assert_true(Vector2(p.x - center.x, p.z - center.z).length() < 6.0, "scattered near the drop point")
	# Pop arc: in the air first, then landed.
	assert_false((spawned[0] as GroundItem).is_landed(), "pop arc running")
	for i in 40:
		await get_tree().physics_frame
	var min_gap := 99.0
	for i in spawned.size():
		assert_true((spawned[i] as GroundItem).is_landed(), "landed after the pop")
		for j in range(i + 1, spawned.size()):
			min_gap = minf(min_gap, (spawned[i] as Node3D).global_position.distance_to((spawned[j] as Node3D).global_position))
	assert_true(min_gap > 0.5, "drops don't stack (min gap %.2f)" % min_gap)
	# Items vs gold.
	var n_gold := 0
	for n: GroundItem in spawned:
		if n.is_gold():
			n_gold += 1
			assert_true(n.get_hover_name().ends_with(" Gold"), "gold name")
			assert_eq(n.get_hover_color(), UIStyle.COLOR_GOLD, "gold colour")
		else:
			assert_eq(n.get_hover_name(), n.item.get_display_name(), "item name")
			assert_eq(n.get_hover_color(), n.item.get_rarity_color(), "item colour")
	assert_eq(n_gold, 5, "5 gold piles")


## Spawn drops at center and return where each GroundItem landed (the items are freed again).
func _spawn_and_collect(drops: Array, center: Vector3) -> Array[Vector3]:
	var got: Array = []
	var cb := func(n: Node) -> void: got.append(n)
	Events.loot_spawned.connect(cb)
	LootSystem.spawn_drops(drops, center)
	Events.loot_spawned.disconnect(cb)
	var out: Array[Vector3] = []
	for n: Node3D in got:
		out.append(n.global_position)
		n.queue_free()
	return out


## Independent check: walkable landing spot with a clear walk-line on the grid from the drop point.
func _reachable_in_line(w: World, from: Vector3, to: Vector3) -> bool:
	var g: WorldGrid = w.grid
	var s := w.get_nearest_walkable(from)
	return w.is_walkable(to) and w.has_line_of_sight(from, to) and g.line_clear(Vector3(s.x, 0, s.z), Vector3(to.x, 0, to.z), g.walk, true)


func test_scatter_never_crosses_walls() -> void:
	seed(31)
	# Arena 16 = 18×18 cells from (-18, 0, -18). A one-cell wall at cell column 9 (world x 0..2)
	# splits it into two rooms.
	var w := await make_world()
	for j in w.grid.size.y:
		w.grid.set_void(Vector2i(9, j))
	w.grid.rebuild_astar()
	assert_false(LootSystem.is_clear_landing(Vector3(-0.4, 0, 0), Vector3(2.6, 0, 0)), "no landing behind the wall")
	assert_false(LootSystem.is_clear_landing(Vector3(-0.4, 0, 0), Vector3(1.0, 0, 0)), "no landing inside the wall")
	assert_true(LootSystem.is_clear_landing(Vector3(-0.4, 0, 0), Vector3(-2.5, 0, 1.5)), "same room is fine")
	var n := 0
	for rep in 25:
		var center := Vector3(-0.35, 0, randf_range(-6.0, 6.0))
		for p in _spawn_and_collect(LootSystem.roll_monster_drops(20, 3), center):
			n += 1
			assert_true(p.x < 0.0, "stays on the kill side of the wall (x = %.2f)" % p.x)
			assert_true(_reachable_in_line(w, center, p), "clear line from the kill position to %s" % p)
			assert_true(Vector2(p.x - center.x, p.z - center.z).length() < 7.0, "lands near the kill")
		await get_tree().process_frame
	assert_true(n > 150, "many boss drops checked (%d)" % n)
	# Corner between the dividing wall and the arena edge: most of the ring is blocked, the
	# fallback (random reachable floor) still finds room, spread out.
	var corner := Vector3(-0.4, 0, -15.6)
	var spots := _spawn_and_collect(LootSystem.roll_monster_drops(20, 3), corner)
	var min_gap := 99.0
	for i in spots.size():
		assert_true(spots[i].x < 0.0 and spots[i].z > -16.0, "corner drop stays in the room")
		assert_true(_reachable_in_line(w, corner, spots[i]), "corner drop reachable")
		for j in range(i + 1, spots.size()):
			min_gap = minf(min_gap, spots[i].distance_to(spots[j]))
	assert_true(min_gap > 0.3, "corner drops still spread (min gap %.2f)" % min_gap)
	await get_tree().process_frame
	# Kill position inside a solid (pillar) cell: drops land on the floor around it.
	var pillar := Vector2i(4, 8)
	w.grid.set_floor(pillar, false)
	var pc := w.grid.cell_center(pillar)
	for p in _spawn_and_collect(LootSystem.roll_monster_drops(20, 3), pc):
		assert_true(w.is_walkable(p), "not on the pillar")
		assert_true(p.distance_to(pc) < 7.0, "near the pillar")
	# Single drops (inventory drops) next to the wall too.
	for rep in 20:
		var gi := LootSystem.spawn_item(ItemDB.create_item("ring_1"), Vector3(-0.3, 0, 3.0))
		assert_true(gi.global_position.x < 0.0, "dropped item stays in the player's room")
		gi.queue_free()


func test_scatter_in_dungeon_near_thin_walls() -> void:
	seed(5)
	var w := await make_world({"id": "dungeon", "depth": 4, "level": 4, "seed": 424242, "theme": World.theme_for_depth(4), "name": "test"})
	var g: WorldGrid = w.grid
	# Kill positions next to one-cell walls/solid cells with floor behind them.
	var spots: Array[Vector3] = []
	for j in g.size.y:
		for i in g.size.x:
			var c := Vector2i(i, j)
			if not g.is_walkable_cell(c):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not g.is_walkable_cell(c + d) and g.is_walkable_cell(c + d * 2):
					spots.append(g.cell_center(c) + Vector3(d.x, 0, d.y) * 0.6)
	assert_true(spots.size() >= 10, "dungeon has thin walls (%d spots)" % spots.size())
	spots.shuffle()
	var n := 0
	for center in spots.slice(0, 30):
		for p in _spawn_and_collect(LootSystem.roll_monster_drops(20, 3), center):
			n += 1
			assert_true(_reachable_in_line(w, center, p), "drop at %s from %s has a clear line" % [p, center])
			assert_true(Vector2(p.x - center.x, p.z - center.z).length() < 7.5, "lands near the kill")
		await get_tree().process_frame
	assert_true(n > 200, "drops checked (%d)" % n)


func test_spawn_item_without_world_uses_fallback() -> void:
	LootSystem.fallback_parent = self
	var gi := LootSystem.spawn_item(ItemDB.create_item("ring_1"), Vector3(1, 0, 1))
	assert_not_null(gi, "spawned")
	assert_eq(gi.get_parent(), self, "into the fallback parent")
	assert_true(gi.global_position.distance_to(Vector3(1, 0, 1)) < 3.0, "near the drop point")
	assert_null_safe(LootSystem.spawn_item(null, Vector3.ZERO))
	assert_true(LootSystem.spawn_gold(0, Vector3.ZERO) == null, "no empty gold piles")
	var g := LootSystem.spawn_gold(40, Vector3.ZERO)
	LootSystem.fallback_parent = null
	assert_true(g != null and g.is_gold() and g.gold == 40, "gold pile")
	assert_eq(g.get_parent(), self, "gold into the fallback parent")


func assert_null_safe(v: Variant) -> void:
	assert_true(v == null, "null item -> null (warning only)")


func test_label_visibility_rules() -> void:
	var normal := _ground(ItemDB.create_item("sword_2"))
	var magic := _ground(ItemDB.create_item("sword_2", Item.Rarity.MAGIC, 10))
	var rare := _ground(ItemDB.create_item("sword_2", Item.Rarity.RARE, 10))
	var gold := GroundItem.new()
	gold.setup_gold(12)
	add_child(gold)
	await get_tree().process_frame
	assert_false(normal.is_label_visible(), "normal label hidden")
	assert_true(magic.is_label_visible(), "magic label shown")
	assert_true(rare.is_label_visible(), "rare label shown")
	assert_true(gold.is_label_visible(), "gold label shown")
	normal.set_hovered(true)
	assert_true(normal.is_label_visible(), "hovered normal shows label")
	normal.set_hovered(false)
	assert_false(normal.is_label_visible(), "unhovered hides it again")
	normal.set_label_visible(true)
	assert_true(normal.is_label_visible(), "forced on")
	normal.set_label_visible(false)
	assert_false(normal.is_label_visible(), "forced off again")
	Input.action_press("highlight_items")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(normal.is_label_visible(), "Alt shows normal labels")
	Input.action_release("highlight_items")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(normal.is_label_visible(), "Alt released")
	# Effects: beam only for rare/unique.
	assert_true(rare.find_child("Beam", true, false) != null, "rare beam")
	assert_true(magic.find_child("Beam", true, false) == null, "no beam for magic")
	assert_true(normal.find_child("Glow", true, false) == null, "no glow for normal")
	assert_true(rare.find_child("Border", true, false) != null, "rare label border")
	# Two pick shapes; the label one is disabled while hidden.
	var shapes := normal.find_children("*", "CollisionShape3D", false, false)
	assert_eq(shapes.size(), 2, "model + label pick shapes")
	var label_cs := normal.get_node("LabelShape") as CollisionShape3D
	assert_true(label_cs.disabled, "hidden label is not clickable")
	assert_false((magic.get_node("LabelShape") as CollisionShape3D).disabled, "visible label clickable")


func _ground(it: Item, pos: Vector3 = Vector3.ZERO) -> GroundItem:
	var gi := GroundItem.new()
	gi.setup_item(it)
	gi.position = pos
	add_child(gi)
	return gi


func test_pickup_item_and_inventory_full() -> void:
	var fc := FakeChar.new()
	GameState.character = fc
	var picked: Array = []
	var fulls: Array = []
	var cb_pick := func(it: RefCounted) -> void: picked.append(it)
	var cb_full := func() -> void: fulls.append(true)
	Events.item_picked_up.connect(cb_pick)
	Events.inventory_full.connect(cb_full)
	var it := ItemDB.create_item("ring_3", Item.Rarity.MAGIC, 20)
	var gi := _ground(it)
	fc.full = true
	gi.interact(null)
	assert_eq(fulls.size(), 1, "inventory_full emitted")
	assert_true(picked.is_empty(), "not picked while full")
	assert_false(gi.is_queued_for_deletion(), "stays on the ground")
	assert_true(gi.can_interact(null), "still interactable")
	fc.full = false
	gi.interact(null)
	assert_eq(picked, [it], "item_picked_up emitted with the item")
	assert_eq(fc.received, [it], "added to the inventory")
	assert_true(gi.is_queued_for_deletion(), "freed after pickup")
	assert_false(gi.can_interact(null), "not interactable after pickup")
	gi.interact(null)
	assert_eq(fc.received.size(), 1, "no double pickup")
	Events.item_picked_up.disconnect(cb_pick)
	Events.inventory_full.disconnect(cb_full)


func test_pickup_prefers_player_character() -> void:
	var global_char := FakeChar.new()
	var player_char := FakeChar.new()
	GameState.character = global_char
	var fake_player := _PlayerLike.new()
	fake_player.character = player_char
	add_child(fake_player)
	var gi := _ground(ItemDB.create_item("amulet_1"))
	gi.interact(fake_player)
	assert_eq(player_char.received.size(), 1, "goes to player.character")
	assert_eq(global_char.received.size(), 0, "not to GameState.character")


class _PlayerLike extends Node3D:
	var character: CharacterData = null


func test_gold_pickup_manual_and_auto() -> void:
	var fc := FakeChar.new()
	GameState.character = fc
	var amounts: Array = []
	var cb := func(a: int) -> void: amounts.append(a)
	Events.gold_picked_up.connect(cb)
	var g := GroundItem.new()
	g.setup_gold(33)
	add_child(g)
	g.interact(null)
	assert_eq(fc.gold_added, 33, "gold added")
	assert_eq(amounts, [33], "gold_picked_up emitted")
	# Auto pickup: needs GameState.player within 1.2 m (re-read every frame).
	await make_world()
	var p := spawn_player(Vector3(6, 0, 0))
	var auto := GroundItem.new()
	auto.setup_gold(50)
	auto.position = Vector3(0, 0, 0)
	GameState.world.add_dynamic(auto)
	for i in 5:
		await get_tree().physics_frame
	assert_false(auto.is_queued_for_deletion(), "not picked from 6 m")
	p.global_position = Vector3(1.0, 0, 0.3)
	for i in 3:
		await get_tree().physics_frame
	assert_true(not is_instance_valid(auto) or auto.is_queued_for_deletion(), "auto-picked within 1.2 m")
	assert_eq(fc.gold_added, 83, "auto pickup went to the player's character")
	# No player -> no crash, no pickup.
	GameState.player = null
	var lonely := GroundItem.new()
	lonely.setup_gold(7)
	GameState.world.add_dynamic(lonely)
	for i in 3:
		await get_tree().physics_frame
	assert_false(lonely.is_queued_for_deletion(), "no player, no pickup")
	Events.gold_picked_up.disconnect(cb)


func test_gold_waits_for_landing() -> void:
	var fc := FakeChar.new()
	GameState.character = fc
	await make_world()
	spawn_player(Vector3(0.5, 0, 0))
	var g := GroundItem.new()
	g.setup_gold(20)
	g.pop_from(Vector3(0, 1, 0))
	GameState.world.add_dynamic(g)
	await get_tree().physics_frame
	assert_false(g.is_landed(), "in the air")
	assert_eq(fc.gold_added, 0, "not picked mid-air")
	for i in 40:
		await get_tree().physics_frame
	assert_eq(fc.gold_added, 20, "picked after landing")


func test_ground_model_sizes() -> void:
	for bid in ["sword_2", "greataxe_3", "body_str_1", "ring_1", "shield_dex_2", "quiver_1", "boots_int_3"]:
		var gi := _ground(ItemDB.create_item(bid))
		var aabb := GroundItem._local_aabb(gi.get_node("Visual/Spin") as Node3D)
		var spin := gi.get_node("Visual/Spin") as Node3D
		var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		assert_between(longest, 0.3, 0.95, "%s ground model size %.2f" % [bid, longest])
		var bottom := spin.position.y + aabb.position.y
		assert_between(bottom, -0.02, 0.08, "%s rests on the floor (%.3f)" % [bid, bottom])
		if ItemDB.get_base(bid)["slot_type"] == "weapon":
			assert_true(aabb.size.y < longest * 0.5, bid + " lies flat")

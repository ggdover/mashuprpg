class_name LootSystem
extends RefCounted
## Drop tables and spawning of ground loot. OWNER: items (wave 1). See docs/ARCHITECTURE.md §9.5.
##
## A drop is {"type": "item", "item": Item} or {"type": "gold", "amount": int}.
##
##   LootSystem.spawn_drops(LootSystem.roll_monster_drops(level, rarity, p_rarity, p_quantity, p_gold), pos)
##   LootSystem.spawn_item(item, player.global_position)     # item dropped from the inventory
##
## Spawned GroundItems go into GameState.world.add_dynamic(); without a world (demos) into
## LootSystem.fallback_parent, else the current scene.

## Item drop chance (%) for normal / magic monsters.
const ITEM_CHANCE: Array[float] = [14.0, 35.0]
## Chance (%) of one gold pile for normal / magic monsters; rare and boss drop fixed piles.
const GOLD_CHANCE: Array[float] = [20.0, 40.0]
const GOLD_PILES: Array[int] = [0, 0, 2, 5]
const RARE_THIRD_ITEM_CHANCE := 0.5
const BOSS_UNIQUE_CHANCE := 0.25
## Chest tiers: [min items, max items, minimum rarity, rarity bonus (like a monster rarity), gold piles].
const CHEST_TABLE := [
	{"min": 1, "max": 2, "min_rarity": Item.Rarity.NORMAL, "monster_rarity": 0, "gold": 1},
	{"min": 2, "max": 4, "min_rarity": Item.Rarity.MAGIC, "monster_rarity": 1, "gold": 2},
	{"min": 3, "max": 5, "min_rarity": Item.Rarity.RARE, "monster_rarity": 2, "gold": 3},
]
## Scatter ring for several drops (outer radius grows by SCATTER_PER_DROP per drop) and minimum
## distance between loot on the floor.
const SCATTER_MIN := 0.8
const SCATTER_MAX := 1.4
const SCATTER_PER_DROP := 0.14
const SINGLE_SCATTER := Vector2(0.35, 0.9)
const MIN_SPACING := 0.8
## Height above the ground the pop arc starts at.
const POP_ORIGIN_HEIGHT := 0.9

## Parent for loot when there is no GameState.world (demos). Falls back to the current scene.
static var fallback_parent: Node = null


## Drops for a killed monster. monster_rarity 0..3 (3 = boss). Bonuses are the player's
## item_rarity / item_quantity / gold_find stats in percent. Item level = monster level.
static func roll_monster_drops(monster_level: int, monster_rarity: int, rarity_bonus: float = 0.0, quantity_bonus: float = 0.0, gold_bonus: float = 0.0) -> Array:
	var lvl := maxi(1, monster_level)
	var r := clampi(monster_rarity, 0, 3)
	var q := maxf(0.0, 1.0 + quantity_bonus / 100.0)
	var n := 0
	match r:
		0, 1:
			n = _chance_count(ITEM_CHANCE[r] / 100.0 * q)
		2:
			n = _chance_count(float(randi_range(1, 2) + (1 if randf() < RARE_THIRD_ITEM_CHANCE else 0)) * q)
		3:
			n = maxi(1, _chance_count(float(randi_range(4, 6)) * q))
	var items: Array = []
	for i in n:
		items.append(ItemDB.generate_random_item(lvl, ItemDB.roll_rarity(rarity_bonus, r)))
	if r == 3:
		_ensure_min_rarity(items, Item.Rarity.RARE, lvl)
		if randf() < BOSS_UNIQUE_CHANCE and _count_rarity(items, Item.Rarity.UNIQUE) == 0:
			_replace_lowest(items, ItemDB.generate_random_item(lvl, Item.Rarity.UNIQUE))
	var drops: Array = []
	for it: Item in items:
		drops.append({"type": "item", "item": it})
	var piles := GOLD_PILES[r]
	if r <= 1 and randf() * 100.0 < GOLD_CHANCE[r]:
		piles = 1
	for i in piles:
		drops.append({"type": "gold", "amount": roll_gold(lvl, gold_bonus)})
	return drops


## Drops for an opened chest (chest_tier 0 = normal, 1 = rare chest, 2 = boss chest):
## tier 0: 1-2 items + gold; tier 1: 2-4 with >= 1 magic; tier 2: 3-5 with >= 1 rare.
static func roll_chest_drops(area_level: int, chest_tier: int = 0) -> Array:
	var lvl := maxi(1, area_level)
	var row: Dictionary = CHEST_TABLE[clampi(chest_tier, 0, CHEST_TABLE.size() - 1)]
	var items: Array = []
	for i in randi_range(row["min"], row["max"]):
		items.append(ItemDB.generate_random_item(lvl, ItemDB.roll_rarity(0.0, row["monster_rarity"])))
	_ensure_min_rarity(items, row["min_rarity"], lvl)
	var drops: Array = []
	for it: Item in items:
		drops.append({"type": "item", "item": it})
	for i in int(row["gold"]):
		drops.append({"type": "gold", "amount": roll_gold(lvl, 0.0, 1.0 + 0.5 * chest_tier)})
	return drops


## One gold pile: Balance.gold_drop(level) × 0.5..1.5 × (1 + gold_find/100) × mult, at least 1.
static func roll_gold(level: int, gold_bonus: float = 0.0, mult: float = 1.0) -> int:
	var amount := float(Balance.gold_drop(maxi(1, level))) * randf_range(0.5, 1.5) * maxf(0.0, 1.0 + gold_bonus / 100.0) * mult
	return maxi(1, int(roundf(amount)))


## Scatter drops around `position` (spread on a small circle, snapped to walkable floor, never
## behind a wall: every landing spot has a clear line from `position`, see is_clear_landing) as
## GroundItems added through GameState.world.add_dynamic(). Emits Events.loot_spawned per item.
static func spawn_drops(drops: Array, position: Vector3) -> void:
	if drops.is_empty():
		return
	var placed: Array[Vector3] = []
	var base_angle := randf() * TAU
	var any_item := false
	var origin := Vector3(position.x, POP_ORIGIN_HEIGHT, position.z)
	for i in drops.size():
		var d: Variant = drops[i]
		if not (d is Dictionary):
			push_warning("LootSystem.spawn_drops: bad drop %s" % [d])
			continue
		var target := _scatter_target(position, i, drops.size(), base_angle, placed)
		placed.append(target)
		match String(d.get("type", "")):
			"item":
				if d.get("item") is Item:
					_spawn(_make_item(d["item"]), origin, target)
					any_item = true
				else:
					push_warning("LootSystem.spawn_drops: item drop without an Item")
			"gold":
				if int(d.get("amount", 0)) > 0:
					_spawn(_make_gold(int(d["amount"])), origin, target)
			_:
				push_warning("LootSystem.spawn_drops: unknown drop type in %s" % [d])
	if any_item:
		Sfx.play("drop_item", position)


static func spawn_item(item: Item, position: Vector3) -> GroundItem:
	if item == null:
		push_warning("LootSystem.spawn_item: null item")
		return null
	var target := _scatter_target(position, 0, 1, randf() * TAU, [])
	var gi := _spawn(_make_item(item), Vector3(position.x, POP_ORIGIN_HEIGHT, position.z), target)
	if gi != null:
		Sfx.play("drop_item", position)
	return gi


static func spawn_gold(amount: int, position: Vector3) -> GroundItem:
	if amount <= 0:
		return null
	var target := _scatter_target(position, 0, 1, randf() * TAU, [])
	return _spawn(_make_gold(amount), Vector3(position.x, POP_ORIGIN_HEIGHT, position.z), target)


# ------------------------------------------------------------------ helpers

static func _chance_count(expected: float) -> int:
	var e := maxf(0.0, expected)
	var n := int(floorf(e))
	if randf() < e - float(n):
		n += 1
	return n


static func _count_rarity(items: Array, min_rarity: int) -> int:
	var n := 0
	for it: Item in items:
		if it.rarity >= min_rarity:
			n += 1
	return n


## Guarantee at least one item of min_rarity or better (replaces the lowest item, or adds one).
static func _ensure_min_rarity(items: Array, min_rarity: int, lvl: int) -> void:
	if min_rarity <= Item.Rarity.NORMAL or _count_rarity(items, min_rarity) > 0:
		return
	_replace_lowest(items, ItemDB.generate_random_item(lvl, min_rarity))


static func _replace_lowest(items: Array, new_item: Item) -> void:
	var idx := -1
	for i in items.size():
		var it: Item = items[i]
		if it.rarity < new_item.rarity and (idx < 0 or it.rarity < (items[idx] as Item).rarity):
			idx = i
	if idx >= 0:
		items[idx] = new_item
	else:
		items.append(new_item)


static func _make_item(item: Item) -> GroundItem:
	var gi := GroundItem.new()
	gi.setup_item(item)
	return gi


static func _make_gold(amount: int) -> GroundItem:
	var gi := GroundItem.new()
	gi.setup_gold(amount)
	return gi


static func _world() -> World:
	var w: Variant = GameState.world
	if is_instance_valid(w) and (w as Node).is_inside_tree():
		return w
	return null


static func _parent() -> Node:
	if _world() != null:
		return _world()
	if is_instance_valid(fallback_parent) and fallback_parent.is_inside_tree():
		return fallback_parent
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return null


static func _spawn(gi: GroundItem, origin: Vector3, target: Vector3) -> GroundItem:
	var parent := _parent()
	if parent == null:
		push_warning("LootSystem: no world or scene to spawn %s into" % gi.get_hover_name())
		gi.free()
		return null
	gi.pop_from(origin)
	if parent is World:
		var dyn: Node3D = (parent as World).dynamic_root
		gi.position = dyn.to_local(target) if dyn != null and dyn.is_inside_tree() else target
		(parent as World).add_dynamic(gi)
	else:
		gi.position = (parent as Node3D).to_local(target) if parent is Node3D else target
		parent.add_child(gi)
	Events.loot_spawned.emit(gi)
	return gi


## True if loot dropped at `from` (the kill / drop position) may land at `to`: `to` is walkable and
## the straight line from -> to crosses neither walls nor solid cells (grid walk-line from the
## nearest walkable point of `from`, plus grid line of sight from `from` itself), so the pop arc
## never passes through a wall into another room. Always true without a World.
static func is_clear_landing(from: Vector3, to: Vector3) -> bool:
	var w := _world()
	if w == null:
		return true
	if not w.is_walkable(to):
		return false
	if not w.has_line_of_sight(from, to):
		return false
	var g: WorldGrid = w.grid
	if g == null:
		return true
	var start := w.get_nearest_walkable(from)
	return g.line_clear(Vector3(start.x, 0.0, start.z), Vector3(to.x, 0.0, to.z), g.walk, true)


## A landing spot for drop i of n around center: on a ring (one drop: close by), snapped to
## walkable floor, with a clear line from center (is_clear_landing) and at least MIN_SPACING from
## other loot where possible. Ring spots behind walls are rejected; if none fits, random walkable
## spots near center (world.random_walkable_near) are tried, and as a last resort the nearest
## walkable point of center itself.
static func _scatter_target(center: Vector3, i: int, n: int, base_angle: float, placed: Array) -> Vector3:
	var w := _world()
	var home := Vector3(center.x, 0.0, center.z)
	if w != null:
		home = w.get_nearest_walkable(home)
		home.y = 0.0
	var best := home
	var best_gap := -1.0
	var others := _existing_loot_positions()
	others.append_array(placed)
	var outer := SINGLE_SCATTER.y if n <= 1 else SCATTER_MAX + SCATTER_PER_DROP * n
	for attempt in 10:
		var ang := base_angle + TAU * (float(i) + randf_range(-0.3, 0.3)) / float(maxi(n, 1)) + float(attempt) * 2.39996
		var radius: float
		if n <= 1:
			radius = randf_range(SINGLE_SCATTER.x, SINGLE_SCATTER.y) + attempt * 0.2
		else:
			radius = randf_range(SCATTER_MIN, outer) + attempt * 0.25
		var p := _snap_walkable(center + Vector3(cos(ang), 0.0, sin(ang)) * radius)
		if not is_clear_landing(center, p):
			continue
		var gap := _gap_to(p, others)
		if gap >= MIN_SPACING:
			return p
		if gap > best_gap:
			best_gap = gap
			best = p
	if w != null:
		# Near walls most of the ring may be blocked: fall back to random reachable floor.
		for attempt in 8:
			var p := w.random_walkable_near(home, outer + attempt * 0.3)
			p.y = 0.0
			if not is_clear_landing(center, p):
				continue
			var gap := _gap_to(p, others)
			if gap >= MIN_SPACING:
				return p
			if gap > best_gap:
				best_gap = gap
				best = p
	return best


static func _gap_to(p: Vector3, others: Array) -> float:
	var gap := 999.0
	for o: Vector3 in others:
		gap = minf(gap, Vector2(o.x - p.x, o.z - p.z).length())
	return gap


static func _snap_walkable(p: Vector3) -> Vector3:
	p.y = 0.0
	var w := _world()
	if w != null and not w.is_walkable(p):
		p = w.get_nearest_walkable(p)
		p.y = 0.0
	return p


static func _existing_loot_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("loot"):
		if n is Node3D and (n as Node3D).is_inside_tree() and not (n as Node).is_queued_for_deletion():
			out.append((n as Node3D).global_position)
	return out

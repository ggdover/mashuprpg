class_name CharacterData
extends RefCounted
## Persistent state of one character: progression, gear, inventory, stash, passives, skill bar.
## Pure data + rules; no nodes. The live Player node reads from it. EVERY mutator emits the matching
## Events signal (gold_changed, inventory_changed, stash_changed, equipment_changed, potions_changed,
## passives_changed, skill_bar_changed, xp_changed/level_up). UI code must use these mutators and
## never write the arrays directly.
## Typed arrays (skill_bar, allocated_passives, cleared_depths) are only filled with .assign(),
## never "=" from untyped arrays. from_dict() converts every JSON number with int().
## OWNER: kernel (wave 1). Keep every public member/signature. See docs/ARCHITECTURE.md §9.1, §11.
##
## Equip rules (§9.1): slot types per SLOT_ACCEPTS; level + attribute requirements (can_equip);
## a two-handed weapon empties off_hand except a quiver kept with a bow/crossbow; a one-handed
## (non-bow/crossbow) weapon displaces an equipped quiver; shields and foci need a one-handed weapon
## or an empty main hand, quivers a bow/crossbow or an empty main hand (can_equip refuses otherwise).

## Equipment slot -> accepted Item.get_slot_type().
const SLOT_ACCEPTS := {
	"main_hand": "weapon",
	"off_hand": "offhand",
	"helmet": "helmet",
	"body": "body",
	"gloves": "gloves",
	"boots": "boots",
	"amulet": "amulet",
	"ring_1": "ring",
	"ring_2": "ring",
	"belt": "belt",
}
const EQUIP_SLOTS: Array[String] = ["main_hand", "off_hand", "helmet", "body", "gloves", "boots", "amulet", "ring_1", "ring_2", "belt"]
const SKILL_BAR_SIZE := 6
## Display names of the equipment slots (UI messages).
const SLOT_NAMES := {
	"main_hand": "Main Hand", "off_hand": "Off Hand", "helmet": "Helmet", "body": "Body Armour",
	"gloves": "Gloves", "boots": "Boots", "amulet": "Amulet", "ring_1": "Ring", "ring_2": "Ring",
	"belt": "Belt",
}
const RANGED_WEAPON_TYPES: Array[String] = ["bow", "crossbow"]
const _EPS := 0.0001

var char_name: String = "Hero"
var class_id: String = "warrior"
## Chosen player look (ClassDefs "looks": "f", "m1", "m2"; "" = the class default). See get_look().
var appearance: String = ""
var level: int = 1
## XP progress inside the current level (resets to 0 on level up).
var xp: int = 0
var gold: int = 0
## slot -> Item (missing key or null = empty)
var equipment: Dictionary = {}
## Balance.INVENTORY_COLUMNS * INVENTORY_ROWS entries; each is an Item or null. Index = row*cols+col.
var inventory: Array = []
## Balance.STASH_SIZE entries, Item or null.
var stash: Array = []
## Allocated passive node ids (int). The class start node is implicit and NOT in this list.
var allocated_passives: Array[int] = []
## Extra passive points (first-time boss kills).
var bonus_passive_points: int = 0
## Skill ids per bar slot ("" = empty). Size SKILL_BAR_SIZE.
var skill_bar: Array[String] = ["", "", "", "", "", ""]
var life_potion_charges: float = 3.0
var mana_potion_charges: float = 3.0
## Deepest dungeon depth unlocked in the waypoint (1 at start).
var max_depth: int = 1
## Depths whose boss has been killed at least once.
var cleared_depths: Array[int] = []
## Seconds played (informational; GameState advances it while a player is live).
var play_time: float = 0.0
## XP lost by the last lose_xp_fraction() call (death screen).
var last_xp_loss: int = 0


func _init() -> void:
	inventory.resize(Balance.INVENTORY_COLUMNS * Balance.INVENTORY_ROWS)
	stash.resize(Balance.STASH_SIZE)


# ------------------------------------------------------------------ progression

## The player model look to show (ClassDefs.get_look of the class and the chosen appearance).
func get_look() -> String:
	return ClassDefs.get_look(class_id, appearance)


func xp_to_next() -> int:
	return Balance.xp_to_next(level)


func is_max_level() -> bool:
	return level >= Balance.MAX_LEVEL


## Adds XP, handling multiple level ups. Emits Events.xp_changed and Events.level_up (once per
## level gained, after the whole amount has been applied). At the level cap XP stays 0.
## Returns the number of levels gained.
func add_xp(amount: int) -> int:
	if amount <= 0 or is_max_level():
		return 0
	xp += amount
	var start_level := level
	while level < Balance.MAX_LEVEL and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
	if is_max_level():
		xp = 0
	var gained := level - start_level
	for l in range(start_level + 1, level + 1):
		Events.level_up.emit(l)
	Events.xp_changed.emit(xp, xp_to_next(), level)
	return gained


## Death penalty: lose `fraction` of the XP needed for this level (never below 0 / de-level).
func lose_xp_fraction(fraction: float) -> void:
	var loss := int(roundf(float(xp_to_next()) * clampf(fraction, 0.0, 1.0)))
	last_xp_loss = mini(loss, xp)
	xp -= last_xp_loss
	Events.xp_changed.emit(xp, xp_to_next(), level)


## Emits Events.gold_changed. Gold never goes below 0.
func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	Events.gold_changed.emit(gold)


## False (and no change) if not enough gold. Emits Events.gold_changed.
func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	if amount == 0:
		return true
	gold -= amount
	Events.gold_changed.emit(gold)
	return true


func passive_points_total() -> int:
	return level - 1 + bonus_passive_points


func passive_points_unspent() -> int:
	return passive_points_total() - allocated_passives.size()


## Emits Events.passives_changed.
func add_bonus_passive_points(n: int) -> void:
	if n == 0:
		return
	bonus_passive_points = maxi(0, bonus_passive_points + n)
	Events.passives_changed.emit()


## Allocate one node (must be adjacent per TreeDB.can_allocate). Emits Events.passives_changed.
func allocate_passive(node_id: int) -> bool:
	if passive_points_unspent() <= 0 or allocated_passives.has(node_id):
		return false
	if not TreeDB.can_allocate(allocated_passives, node_id, class_id):
		return false
	allocated_passives.append(node_id)
	Events.passives_changed.emit()
	return true


## Allocate several nodes in order (e.g. TreeDB.find_path()); stops at the first failure.
## Returns how many were allocated.
func allocate_passives(node_ids: Array) -> int:
	var n := 0
	for id in node_ids:
		if not allocate_passive(int(id)):
			break
		n += 1
	return n


## Gold cost of one refund at the current level.
func refund_cost() -> int:
	return Balance.passive_refund_cost(level)


## Refund one node (TreeDB.can_refund; costs Balance.passive_refund_cost gold).
func refund_passive(node_id: int) -> bool:
	if not allocated_passives.has(node_id):
		return false
	if not TreeDB.can_refund(allocated_passives, node_id, class_id):
		return false
	var cost := refund_cost()
	if gold < cost:
		return false
	allocated_passives.erase(node_id)
	spend_gold(cost)
	Events.passives_changed.emit()
	return true


## Mods of the allocated passives (TreeDB.get_mods, start node included).
func get_passive_mods() -> Array:
	return TreeDB.get_mods(allocated_passives, class_id)


## Mark a depth's boss as killed. Returns true on the first clear.
func mark_depth_cleared(depth: int) -> bool:
	if cleared_depths.has(depth):
		return false
	cleared_depths.append(depth)
	return true


# ------------------------------------------------------------------ attributes

## Attribute totals from class + equipment + passives (§5.2, no buffs):
## {"strength": float, "dexterity": float, "intelligence": float}. Used by can_equip() when no
## attributes are passed; the live Player's Actor.attributes also include buffs.
func compute_attributes() -> Dictionary:
	var sb := StatBlock.new()
	sb.add_mods(ClassDefs.get_attribute_mods(class_id))
	sb.add_mods(get_equipment_mods())
	sb.add_mods(get_passive_mods())
	var out := {}
	var all_flat := sb.flat("all_attributes")
	var all_inc := sb.inc("all_attributes")
	var all_more := sb.more("all_attributes")
	for a in ClassDefs.ATTRIBUTES:
		out[a] = maxf(0.0, (sb.flat(a) + all_flat) * (1.0 + (sb.inc(a) + all_inc) / 100.0) * sb.more(a) * all_more)
	return out


# ------------------------------------------------------------------ items

func get_equipped(slot: String) -> Item:
	return equipment.get(slot, null)


## Slot the item is equipped in, or "".
func find_equipped_slot(item: Item) -> String:
	if item == null:
		return ""
	for slot in EQUIP_SLOTS:
		if equipment.get(slot, null) == item:
			return slot
	return ""


## Whether `item` can go into `slot` (slot type, level/attribute requirements given `attributes`
## {"strength":..}, and two-handed/off-hand rules). Returns {"ok": bool, "reason": String}.
## attributes {} = the character's own (compute_attributes()).
func can_equip(item: Item, slot: String, attributes: Dictionary = {}) -> Dictionary:
	if item == null:
		return _no("No item")
	if not SLOT_ACCEPTS.has(slot):
		return _no("Unknown slot")
	if item.get_slot_type() != SLOT_ACCEPTS[slot]:
		return _no("Can't be equipped in the %s slot" % SLOT_NAMES.get(slot, slot))
	var rule := _offhand_rule(item, slot)
	if rule != "":
		return _no(rule)
	var req := item.get_requirements()
	if level < int(req.get("level", 1)):
		return _no("Requires Level %d" % int(req.get("level", 1)))
	var need_attrs := false
	for a in ClassDefs.ATTRIBUTES:
		if int(req.get(a, 0)) > 0:
			need_attrs = true
	if need_attrs:
		var attrs := attributes if not attributes.is_empty() else compute_attributes()
		for a in ClassDefs.ATTRIBUTES:
			var need := int(req.get(a, 0))
			if need > 0 and float(attrs.get(a, 0.0)) + _EPS < float(need):
				return _no("Requires %d %s" % [need, a.capitalize()])
	return {"ok": true, "reason": ""}


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## "" if the item may go into `slot` next to the current main hand, else the reason.
func _offhand_rule(item: Item, slot: String) -> String:
	if slot != "off_hand":
		return ""
	var main := get_equipped("main_hand")
	if main == null:
		return ""
	if item.get_weapon_type() == "quiver":
		if not RANGED_WEAPON_TYPES.has(main.get_weapon_type()):
			return "Quivers can only be used with a Bow or Crossbow"
		return ""
	if main.is_two_handed():
		return "Requires a one-handed weapon"
	return ""


## Other slots that equipping `item` into `slot` would empty (e.g. ["off_hand"] for a two-hander).
## The UI can check inventory space with it before equipping.
func get_equip_conflicts(item: Item, slot: String) -> Array[String]:
	var out: Array[String] = []
	if item == null or slot != "main_hand":
		return out
	var off := get_equipped("off_hand")
	if off == null:
		return out
	var ranged := RANGED_WEAPON_TYPES.has(item.get_weapon_type())
	if off.get_weapon_type() == "quiver":
		if not ranged:
			out.append("off_hand")
	elif item.is_two_handed():
		out.append("off_hand")
	return out


## Best slot for an item (first empty matching slot, else the first matching slot). "" if none.
func get_default_slot_for(item: Item) -> String:
	if item == null:
		return ""
	var st := item.get_slot_type()
	var first := ""
	for slot in EQUIP_SLOTS:
		if SLOT_ACCEPTS[slot] != st:
			continue
		if first == "":
			first = slot
		if get_equipped(slot) == null:
			return slot
	return first


## Put item into slot; returns the Array of Items displaced (previous item, or the off-hand
## displaced by a two-hander). Caller decides where displaced items go. Emits
## Events.equipment_changed(slot) for every slot that changed.
## Structural rules only (slot type, off-hand rules): requirements are checked by can_equip().
## If the item can't go into the slot at all, nothing changes and [item] is returned (so the
## caller puts it back). Moving an equipped item to another slot of the same type (ring_1 ->
## ring_2) swaps the two.
func equip(item: Item, slot: String) -> Array:
	if item == null:
		return []
	if not SLOT_ACCEPTS.has(slot) or item.get_slot_type() != SLOT_ACCEPTS[slot]:
		push_warning("CharacterData.equip: %s can't go into slot '%s'" % [item.get_display_name(), slot])
		return [item]
	if _offhand_rule(item, slot) != "":
		push_warning("CharacterData.equip: %s" % _offhand_rule(item, slot))
		return [item]
	var prev: Item = get_equipped(slot)
	if prev == item:
		return []
	var changed: Array[String] = [slot]
	var displaced: Array = []
	var from_slot := find_equipped_slot(item)
	if from_slot != "":
		equipment.erase(from_slot)
		changed.append(from_slot)
		if prev != null and SLOT_ACCEPTS[from_slot] == prev.get_slot_type():
			equipment[from_slot] = prev
			prev = null
	for s in get_equip_conflicts(item, slot):
		var other: Item = get_equipped(s)
		if other != null:
			displaced.append(other)
			equipment.erase(s)
			if not changed.has(s):
				changed.append(s)
	if prev != null:
		displaced.push_front(prev)
	equipment[slot] = item
	for s in changed:
		Events.equipment_changed.emit(s)
	return displaced


func unequip(slot: String) -> Item:
	var prev: Item = get_equipped(slot)
	if prev == null:
		equipment.erase(slot)
		return null
	equipment.erase(slot)
	Events.equipment_changed.emit(slot)
	return prev


## Equip the inventory item at `index` in one step (slot "" = get_default_slot_for): checks
## can_equip() (attributes {} = own) and that every displaced item fits in the inventory (the
## freed cell is reused first). Emits the usual signals, and Events.inventory_full when the
## displaced items don't fit. Returns {"ok": bool, "reason": String}.
func equip_from_inventory(index: int, slot: String = "", attributes: Dictionary = {}) -> Dictionary:
	if not _valid_index(inventory, index) or inventory[index] == null:
		return _no("No item")
	var it: Item = inventory[index]
	var target := slot if slot != "" else get_default_slot_for(it)
	var check := can_equip(it, target, attributes)
	if not check.get("ok", false):
		return check
	var outgoing := get_equip_conflicts(it, target).size()
	if get_equipped(target) != null:
		outgoing += 1
	if outgoing > inventory_free_count() + 1:
		Events.inventory_full.emit()
		return _no("Inventory full")
	take_from_inventory(index)
	var displaced := equip(it, target)
	for d in displaced:
		if inventory[index] == null:
			put_in_inventory(index, d)
		else:
			add_to_inventory(d)
	return {"ok": true, "reason": ""}


## Move an equipped item into the first free inventory cell. False (and Events.inventory_full)
## when the inventory is full; false when the slot is empty.
func unequip_to_inventory(slot: String) -> bool:
	if get_equipped(slot) == null:
		return false
	if first_free_inventory_index() < 0:
		Events.inventory_full.emit()
		return false
	return add_to_inventory(unequip(slot))


## Mods from all equipped items (Item.get_global_mods()).
func get_equipment_mods() -> Array:
	var mods: Array = []
	for slot in EQUIP_SLOTS:
		var it: Item = equipment.get(slot, null)
		if it != null:
			mods.append_array(it.get_global_mods())
	return mods


## First free inventory index, or -1.
func first_free_inventory_index() -> int:
	return inventory.find(null)


func inventory_free_count() -> int:
	return inventory.count(null)


## Index of the item in the inventory, or -1.
func find_inventory_index(item: Item) -> int:
	return -1 if item == null else inventory.find(item)


## Adds to the first free cell. Emits Events.inventory_changed. False if full.
func add_to_inventory(item: Item) -> bool:
	if item == null:
		return false
	if inventory.has(item):
		push_warning("CharacterData.add_to_inventory: item already in the inventory")
		return false
	var idx := first_free_inventory_index()
	if idx < 0:
		return false
	inventory[idx] = item
	Events.inventory_changed.emit()
	return true


## Remove and return the item at index (null if empty). Emits Events.inventory_changed.
func take_from_inventory(index: int) -> Item:
	if index < 0 or index >= inventory.size():
		return null
	var it: Item = inventory[index]
	if it == null:
		return null
	inventory[index] = null
	Events.inventory_changed.emit()
	return it


## Remove a specific item from the inventory. Emits Events.inventory_changed.
func remove_from_inventory(item: Item) -> bool:
	var idx := find_inventory_index(item)
	if idx < 0:
		return false
	take_from_inventory(idx)
	return true


## Swap/move between two inventory cells. Emits Events.inventory_changed.
func move_inventory(from_index: int, to_index: int) -> void:
	if from_index == to_index or not _valid_index(inventory, from_index) or not _valid_index(inventory, to_index):
		return
	var tmp: Variant = inventory[to_index]
	inventory[to_index] = inventory[from_index]
	inventory[from_index] = tmp
	Events.inventory_changed.emit()


## Put item into a specific cell (item may be null to clear it); returns the item previously there
## (or null). Emits Events.inventory_changed. An invalid index changes nothing and returns `item`.
func put_in_inventory(index: int, item: Item) -> Item:
	if not _valid_index(inventory, index):
		push_warning("CharacterData.put_in_inventory: bad index %d" % index)
		return item
	var prev: Item = inventory[index]
	inventory[index] = item
	Events.inventory_changed.emit()
	return prev


func first_free_stash_index() -> int:
	return stash.find(null)


## First free cell. Emits Events.stash_changed. False if full.
func add_to_stash(item: Item) -> bool:
	if item == null:
		return false
	if stash.has(item):
		push_warning("CharacterData.add_to_stash: item already in the stash")
		return false
	var idx := first_free_stash_index()
	if idx < 0:
		return false
	stash[idx] = item
	Events.stash_changed.emit()
	return true


## Emits Events.stash_changed.
func take_from_stash(index: int) -> Item:
	if not _valid_index(stash, index):
		return null
	var it: Item = stash[index]
	if it == null:
		return null
	stash[index] = null
	Events.stash_changed.emit()
	return it


## Like put_in_inventory, for the stash. Emits Events.stash_changed.
func put_in_stash(index: int, item: Item) -> Item:
	if not _valid_index(stash, index):
		push_warning("CharacterData.put_in_stash: bad index %d" % index)
		return item
	var prev: Item = stash[index]
	stash[index] = item
	Events.stash_changed.emit()
	return prev


## Emits Events.stash_changed.
func move_stash(from_index: int, to_index: int) -> void:
	if from_index == to_index or not _valid_index(stash, from_index) or not _valid_index(stash, to_index):
		return
	var tmp: Variant = stash[to_index]
	stash[to_index] = stash[from_index]
	stash[from_index] = tmp
	Events.stash_changed.emit()


func _valid_index(arr: Array, index: int) -> bool:
	return index >= 0 and index < arr.size()


# ------------------------------------------------------------------ skills & potions

func get_skill_in_slot(slot: int) -> String:
	if slot < 0 or slot >= skill_bar.size():
		return ""
	return skill_bar[slot]


## Assign a skill id to a bar slot 0..5 ("" clears). If the skill is already in another slot, the
## two slots swap. Emits Events.skill_bar_changed.
func set_skill_in_slot(slot: int, skill_id: String) -> void:
	if slot < 0 or slot >= SKILL_BAR_SIZE:
		push_warning("CharacterData.set_skill_in_slot: bad slot %d" % slot)
		return
	while skill_bar.size() < SKILL_BAR_SIZE:
		skill_bar.append("")
	if skill_id != "":
		var other := skill_bar.find(skill_id)
		if other >= 0 and other != slot:
			skill_bar[other] = skill_bar[slot]
	skill_bar[slot] = skill_id
	Events.skill_bar_changed.emit()


## Adds charges to both potions (clamped to Balance.POTION_MAX_CHARGES).
## Emits Events.potions_changed.
func add_potion_charges(amount: float) -> void:
	if amount <= 0.0:
		return
	life_potion_charges = minf(Balance.POTION_MAX_CHARGES, life_potion_charges + amount)
	mana_potion_charges = minf(Balance.POTION_MAX_CHARGES, mana_potion_charges + amount)
	Events.potions_changed.emit()


## Charges of kind "life" | "mana".
func get_potion_charges(kind: String) -> float:
	return life_potion_charges if kind == "life" else (mana_potion_charges if kind == "mana" else 0.0)


## Uses one charge of kind "life" | "mana" if >= 1 available. Emits Events.potions_changed.
func consume_potion_charge(kind: String) -> bool:
	match kind:
		"life":
			if life_potion_charges + _EPS < 1.0:
				return false
			life_potion_charges = maxf(0.0, life_potion_charges - 1.0)
		"mana":
			if mana_potion_charges + _EPS < 1.0:
				return false
			mana_potion_charges = maxf(0.0, mana_potion_charges - 1.0)
		_:
			push_warning("CharacterData.consume_potion_charge: unknown kind '%s'" % kind)
			return false
	Events.potions_changed.emit()
	return true


## Both potions to max. Emits Events.potions_changed.
func refill_potions() -> void:
	life_potion_charges = Balance.POTION_MAX_CHARGES
	mana_potion_charges = Balance.POTION_MAX_CHARGES
	Events.potions_changed.emit()


# ------------------------------------------------------------------ persistence

## JSON-native dictionary (items via Item.to_dict(); inventory/stash stored sparsely as
## [{"index": int, "item": dict}]).
func to_dict() -> Dictionary:
	var eq := {}
	for slot in EQUIP_SLOTS:
		var it: Item = equipment.get(slot, null)
		if it != null:
			eq[slot] = it.to_dict()
	return {
		"char_name": char_name,
		"class_id": class_id,
		"appearance": appearance,
		"level": level,
		"xp": xp,
		"gold": gold,
		"equipment": eq,
		"inventory": _cells_to_list(inventory),
		"stash": _cells_to_list(stash),
		"allocated_passives": Array(allocated_passives),
		"bonus_passive_points": bonus_passive_points,
		"skill_bar": Array(skill_bar),
		"life_potion_charges": life_potion_charges,
		"mana_potion_charges": mana_potion_charges,
		"max_depth": max_depth,
		"cleared_depths": Array(cleared_depths),
		"play_time": play_time,
	}


static func _cells_to_list(cells: Array) -> Array:
	var out: Array = []
	for i in cells.size():
		var it: Item = cells[i]
		if it != null:
			out.append({"index": i, "item": it.to_dict()})
	return out


static func from_dict(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.char_name = String(d.get("char_name", "Hero"))
	var cid := String(d.get("class_id", ClassDefs.DEFAULT_CLASS))
	if not ClassDefs.has_class(cid):
		push_warning("CharacterData.from_dict: unknown class '%s'" % cid)
		cid = ClassDefs.DEFAULT_CLASS
	c.class_id = cid
	c.appearance = String(d.get("appearance", ""))
	if c.appearance != "" and not ClassDefs.get_looks(cid).has(c.appearance):
		c.appearance = ""
	c.level = clampi(int(d.get("level", 1)), 1, Balance.MAX_LEVEL)
	c.xp = maxi(0, int(d.get("xp", 0)))
	if c.is_max_level():
		c.xp = 0
	c.gold = maxi(0, int(d.get("gold", 0)))
	var eq: Variant = d.get("equipment", {})
	if eq is Dictionary:
		for slot in eq:
			var s := String(slot)
			if not SLOT_ACCEPTS.has(s):
				push_warning("CharacterData.from_dict: unknown equipment slot '%s'" % s)
				continue
			var it := _item_from(eq[slot])
			if it != null:
				c.equipment[s] = it
	var overflow: Array = []
	_list_to_cells(d.get("inventory", []), c.inventory, overflow)
	_list_to_cells(d.get("stash", []), c.stash, overflow)
	for it in overflow:
		if not c.add_to_inventory(it) and not c.add_to_stash(it):
			push_warning("CharacterData.from_dict: no room for %s" % (it as Item).get_display_name())
	var passives: Array[int] = []
	for v in _as_array(d.get("allocated_passives", [])):
		var id := int(v)
		if not passives.has(id):
			passives.append(id)
	c.allocated_passives.assign(passives)
	c.bonus_passive_points = maxi(0, int(d.get("bonus_passive_points", 0)))
	var bar: Array[String] = []
	for v in _as_array(d.get("skill_bar", [])):
		bar.append(String(v) if v != null else "")
	while bar.size() < SKILL_BAR_SIZE:
		bar.append("")
	bar.resize(SKILL_BAR_SIZE)
	c.skill_bar.assign(bar)
	c.life_potion_charges = clampf(float(d.get("life_potion_charges", Balance.POTION_MAX_CHARGES)), 0.0, Balance.POTION_MAX_CHARGES)
	c.mana_potion_charges = clampf(float(d.get("mana_potion_charges", Balance.POTION_MAX_CHARGES)), 0.0, Balance.POTION_MAX_CHARGES)
	c.max_depth = clampi(int(d.get("max_depth", 1)), 1, Balance.MAX_DEPTH)
	var cleared: Array[int] = []
	for v in _as_array(d.get("cleared_depths", [])):
		if not cleared.has(int(v)):
			cleared.append(int(v))
	c.cleared_depths.assign(cleared)
	c.play_time = maxf(0.0, float(d.get("play_time", 0.0)))
	return c


static func _as_array(v: Variant) -> Array:
	if v is Array:
		return v
	return []


static func _item_from(v: Variant) -> Item:
	if not (v is Dictionary) or (v as Dictionary).is_empty():
		return null
	var it := Item.from_dict(v)
	if it == null:
		return null
	if it.base_id == "" or it.get_base().is_empty():
		push_warning("CharacterData.from_dict: dropping item with unknown base '%s'" % it.base_id)
		return null
	return it


## Accepts the sparse format [{"index", "item"}] and a dense one [item dict | null, ...].
static func _list_to_cells(list: Variant, cells: Array, overflow: Array) -> void:
	var arr := _as_array(list)
	for i in arr.size():
		var e: Variant = arr[i]
		if not (e is Dictionary):
			continue
		var idx := i
		var item_d: Variant = e
		if (e as Dictionary).has("item"):
			idx = int(e.get("index", -1))
			item_d = e["item"]
		var it := _item_from(item_d)
		if it == null:
			continue
		if idx >= 0 and idx < cells.size() and cells[idx] == null:
			cells[idx] = it
		else:
			overflow.append(it)

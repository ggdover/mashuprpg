extends Node
## Autoload "ItemDB": item base types, affixes, uniques and item generation.
## OWNER: items (wave 1). See docs/ARCHITECTURE.md §9.
##
## Data lives in scripts/items/item_{base,affix,unique,name}_data.gd and is expanded once in
## _init() (so it is usable before _ready and from other autoloads):
##   - 43 base categories × 6 tiers (levels 1/8/16/26/38/50) = 258 bases, ids "<category>_<tier>"
##   - ~64 affixes (prefix/suffix, 6 tiers each), 15 uniques.
##
## Quick reference:
##   ItemDB.create_item("sword_3", Item.Rarity.RARE, 20)      # specific base
##   ItemDB.generate_random_item(12)                           # drop: rolls rarity/slot/tier
##   ItemDB.generate_random_item(12, Item.Rarity.MAGIC, "boots")
##   ItemDB.create_unique("gorebinder")
##   ItemDB.reroll_affixes(item) / upgrade_rarity(item) + reroll_cost / upgrade_cost
##
## Base, affix and unique dictionaries (and their nested arrays/dicts) are shared and read-only
## (writes raise an engine error); duplicate() them for a writable copy.

const BaseData := preload("res://scripts/items/item_base_data.gd")
const AffixData := preload("res://scripts/items/item_affix_data.gd")
const UniqueData := preload("res://scripts/items/item_unique_data.gd")
const NameData := preload("res://scripts/items/item_name_data.gd")

## §9.5 slot type weights for random drops.
const SLOT_WEIGHTS := {"weapon": 18, "offhand": 8, "helmet": 10, "body": 10, "gloves": 10, "boots": 10, "ring": 14, "amulet": 10, "belt": 10}
## §9.5 rarity weights (index = Item.Rarity) and the rarity bonus a monster rarity adds.
const RARITY_WEIGHTS: Array[float] = [72.0, 22.0, 5.5, 0.5]
const MONSTER_RARITY_BONUS: Array[float] = [0.0, 50.0, 150.0, 400.0]
## Number of explicit affixes: magic 1-2, rare 3-6.
const MAGIC_AFFIX_COUNTS := {1: 45, 2: 55}
const RARE_AFFIX_COUNTS := {3: 30, 4: 35, 5: 22, 6: 13}
const MAX_PREFIXES := {Item.Rarity.MAGIC: 1, Item.Rarity.RARE: 3}
const MAX_SUFFIXES := {Item.Rarity.MAGIC: 1, Item.Rarity.RARE: 3}
## Affix tier choice among the tiers allowed by item level: index 0 = best allowed tier.
const AFFIX_TIER_WEIGHTS: Array[float] = [30.0, 30.0, 20.0, 10.0, 6.0, 4.0]
## §9.5 base tier choice: highest allowed tier / next lower / any lower.
const TIER_CHANCE_TOP := 0.70
const TIER_CHANCE_NEXT := 0.25
## Vendor rarity weights (normal, magic, rare) — vendors never sell uniques.
const VENDOR_RARITY_WEIGHTS: Array[float] = [45.0, 45.0, 10.0]
const MELEE_CATEGORIES: Array[String] = ["sword", "greatsword", "axe", "greataxe", "mace", "maul", "dagger"]
const RANGED_CATEGORIES: Array[String] = ["bow", "crossbow"]
const CASTER_CATEGORIES: Array[String] = ["wand", "staff"]

var _bases: Dictionary = {}              # id -> base dict
var _base_order: Array[String] = []      # display order (slot, category, tier)
var _categories_by_slot: Dictionary = {} # slot -> Array[String]
var _category_bases: Dictionary = {}     # category -> Array[String] of ids, tier 1..6
var _affixes: Dictionary = {}            # id -> affix dict
var _uniques: Dictionary = {}            # id -> unique dict (with "id" and "level")
var _pool_cache: Dictionary = {}         # "base_id|kind" -> Array[String] affix ids
## Returned for unknown ids (read-only like every other lookup result).
const _EMPTY := {}


func _init() -> void:
	_bases = BaseData.build_bases()
	for slot: String in BaseData.SLOT_CATEGORIES:
		var cats: Array[String] = []
		for cat: String in BaseData.SLOT_CATEGORIES[slot]:
			cats.append(cat)
			var ids: Array[String] = []
			for t in range(1, 7):
				var id := "%s_%d" % [cat, t]
				if _bases.has(id):
					ids.append(id)
					_base_order.append(id)
			_category_bases[cat] = ids
		_categories_by_slot[slot] = cats
	_affixes = AffixData.build_affixes()
	for uid: String in UniqueData.UNIQUES:
		var u: Dictionary = (UniqueData.UNIQUES[uid] as Dictionary).duplicate(true)
		u["id"] = uid
		var base := get_base(u.get("base", ""))
		if base.is_empty():
			push_warning("ItemDB: unique '%s' has unknown base '%s'" % [uid, u.get("base", "")])
			continue
		u["level"] = int(base.get("level", 1))
		_uniques[uid] = u
	# Everything handed out by the lookups below is shared: make it (deeply) read-only so an
	# accidental write fails loudly instead of silently changing every item of that base.
	for d: Dictionary in [_bases, _affixes, _uniques, _category_bases, _categories_by_slot]:
		deep_make_read_only(d)
	_base_order.make_read_only()


# ------------------------------------------------------------------ lookups

## Base definition. Keys: "id", "name", "category", "tier", "item_class", "slot_type",
## "weapon_type", "two_handed", "level" (drop level), "req" {"strength","dexterity","intelligence"},
## "model", "tint", "tags", "implicits" (Array of mod templates), weapon: "template_min",
## "template_max", "phys_min", "phys_max" (at the base level), "attack_speed", "crit_chance",
## "range"; armour-like: "defence_types", "defence_factor", "armour", "evasion", "energy_shield",
## "block". Returns {} for unknown ids. The returned dictionary (and everything nested in it) is
## shared and READ-ONLY: duplicate() it to get a writable copy.
func get_base(base_id: String) -> Dictionary:
	return _bases.get(base_id, _EMPTY)


func has_base(base_id: String) -> bool:
	return _bases.has(base_id)


## Every base dict, ordered by slot type, category and tier.
func get_all_bases() -> Array:
	var out: Array = []
	for id in _base_order:
		out.append(_bases[id])
	return out


func get_base_ids() -> Array[String]:
	return _base_order.duplicate()


## Base dicts of one slot type (Item.SLOT_TYPES), ordered by category and tier.
func get_bases_for_slot(slot_type: String) -> Array:
	var out: Array = []
	for cat: String in _categories_by_slot.get(slot_type, []):
		for id: String in _category_bases[cat]:
			out.append(_bases[id])
	return out


## Category ids ("sword", "body_str_dex", "ring", ...) of a slot type, or all when slot_type == "".
func get_categories(slot_type: String = "") -> Array[String]:
	var out: Array[String] = []
	for slot: String in _categories_by_slot:
		if slot_type == "" or slot == slot_type:
			out.append_array(_categories_by_slot[slot])
	return out


## Base ids of a category, tier 1..6.
func get_category_bases(category: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_category_bases.get(category, []))
	return ids


## Base id of a category for an area/item level: the highest tier whose level <= level.
func get_base_for_level(category: String, level: int) -> String:
	var ids: Array = _category_bases.get(category, [])
	if ids.is_empty():
		return ""
	var best: String = ids[0]
	for id: String in ids:
		if int(_bases[id]["level"]) <= level:
			best = id
	return best


## Tier (1..6) of the highest base tier available at this level.
func tier_for_level(level: int) -> int:
	var tier := 1
	for i in BaseData.TIER_LEVELS.size():
		if BaseData.TIER_LEVELS[i] <= level:
			tier = i + 1
	return tier


func get_affix(affix_id: String) -> Dictionary:
	return _affixes.get(affix_id, _EMPTY)


func get_all_affixes() -> Array:
	return _affixes.values()


## Affix ids that may roll on a base (kind "prefix"/"suffix"/"" = both).
func get_affixes_for_base(base_id: String, kind: String = "") -> Array[String]:
	var out: Array[String] = []
	for k in (["prefix", "suffix"] if kind == "" else [kind]):
		out.append_array(_affix_pool(base_id, k))
	return out


## Whether an affix may roll on a base (slot type and tag filters).
func affix_allowed_on_base(affix: Dictionary, base: Dictionary) -> bool:
	if not (base.get("slot_type", "") in affix.get("slot_types", [])):
		return false
	var tags: Array = affix.get("tags", [])
	if tags.is_empty():
		return true
	var base_tags: Array = base.get("tags", [])
	for t in tags:
		if t in base_tags:
			return true
	return false


## Unique definition: {"id", "name", "base", "level", "tint", "mods", "flavour"} or {}.
func get_unique(unique_id: String) -> Dictionary:
	return _uniques.get(unique_id, _EMPTY)


func get_all_uniques() -> Array:
	return _uniques.values()


func get_unique_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_uniques.keys())
	return out


# ------------------------------------------------------------------ creation

## Create an item of a specific base. item_level -1 = the base's level. Rolls implicits, and
## affixes for magic/rare (and a generated name for rares). Rarity UNIQUE picks a unique of that
## base if one exists, else the item becomes rare.
func create_item(base_id: String, rarity: int = Item.Rarity.NORMAL, item_level: int = -1) -> Item:
	var base := get_base(base_id)
	if base.is_empty():
		push_warning("ItemDB.create_item: unknown base '%s'" % base_id)
	var it := Item.new()
	it.base_id = base_id
	it.item_level = item_level if item_level > 0 else int(base.get("level", 1))
	it.rarity = clampi(rarity, Item.Rarity.NORMAL, Item.Rarity.UNIQUE)
	if it.rarity == Item.Rarity.UNIQUE:
		var uids := get_uniques_for_base(base_id)
		if not uids.is_empty():
			return create_unique(uids[randi() % uids.size()], it.item_level)
		it.rarity = Item.Rarity.RARE
	it.implicit_mods = _roll_templates(base.get("implicits", []), 1.0)
	match it.rarity:
		Item.Rarity.MAGIC:
			_add_affixes(it, _weighted_key(MAGIC_AFFIX_COUNTS))
		Item.Rarity.RARE:
			_add_affixes(it, _weighted_key(RARE_AFFIX_COUNTS))
			it.name = NameData.random_rare_name(base)
	return it


## Create a unique. item_level -1 = the unique's (base) level.
func create_unique(unique_id: String, item_level: int = -1) -> Item:
	var u := get_unique(unique_id)
	if u.is_empty():
		push_warning("ItemDB.create_unique: unknown unique '%s'" % unique_id)
		return create_item("ring_1", Item.Rarity.RARE, item_level)
	var base := get_base(u["base"])
	var it := Item.new()
	it.base_id = u["base"]
	it.unique_id = unique_id
	it.name = u["name"]
	it.rarity = Item.Rarity.UNIQUE
	it.item_level = maxi(item_level, int(u["level"])) if item_level > 0 else int(u["level"])
	it.implicit_mods = _roll_templates(base.get("implicits", []), 1.0)
	it.affixes = [{"id": unique_id, "kind": "unique", "tier": 0, "name": u["name"], "mods": _roll_templates(u.get("mods", []), 1.0)}]
	return it


## Unique ids whose base is base_id.
func get_uniques_for_base(base_id: String) -> Array[String]:
	var out: Array[String] = []
	for uid: String in _uniques:
		if _uniques[uid]["base"] == base_id:
			out.append(uid)
	return out


## Random item for a drop. rarity -1 = roll it (roll_rarity). slot_type "" = any slot (weighted per
## §9.5); a category id ("bow", "body_str") is accepted too. Uniques need a unique with level <=
## item_level (and the slot, if given), else the item becomes rare.
func generate_random_item(item_level: int, rarity: int = -1, slot_type: String = "", rarity_bonus: float = 0.0) -> Item:
	var ilvl := maxi(1, item_level)
	if rarity < 0:
		rarity = roll_rarity(rarity_bonus)
	rarity = clampi(rarity, Item.Rarity.NORMAL, Item.Rarity.UNIQUE)
	if rarity == Item.Rarity.UNIQUE:
		var uid := _pick_unique(ilvl, slot_type)
		if uid != "":
			return create_unique(uid, ilvl)
		rarity = Item.Rarity.RARE
	var category := ""
	if _category_bases.has(slot_type):
		category = slot_type
	else:
		var slot := slot_type
		if not _categories_by_slot.has(slot):
			if slot != "":
				push_warning("ItemDB.generate_random_item: unknown slot type '%s'" % slot)
			slot = pick_slot_type()
		var cats: Array = _categories_by_slot[slot]
		category = cats[randi() % cats.size()]
	return create_item(pick_tier_base(category, ilvl), rarity, ilvl)


## Slot type by the §9.5 weights.
func pick_slot_type() -> String:
	return _weighted_key(SLOT_WEIGHTS)


## Base id of a category for a drop at ilvl: highest allowed tier 70%, next lower 25%, any lower 5%.
func pick_tier_base(category: String, item_level: int) -> String:
	var ids: Array = _category_bases.get(category, [])
	if ids.is_empty():
		push_warning("ItemDB.pick_tier_base: unknown category '%s'" % category)
		return ""
	var top := 0
	for i in ids.size():
		if int(_bases[ids[i]]["level"]) <= item_level:
			top = i
	var r := randf()
	var idx := top
	if r >= TIER_CHANCE_TOP and top >= 1:
		if r < TIER_CHANCE_TOP + TIER_CHANCE_NEXT or top < 2:
			idx = top - 1
		else:
			idx = randi_range(0, top - 2)
	return ids[idx]


## Roll a rarity. rarity_bonus is the item_rarity stat (percent), monster_rarity 0..3.
## Weights normal 72, magic 22, rare 5.5, unique 0.5; non-normal × (1 + bonus/100) where the
## monster rarity adds +50 / +150 / +400.
func roll_rarity(rarity_bonus: float = 0.0, monster_rarity: int = 0) -> int:
	var w := get_rarity_weights(rarity_bonus, monster_rarity)
	var total := 0.0
	for v in w:
		total += v
	var r := randf() * total
	for i in w.size():
		r -= w[i]
		if r < 0.0:
			return i
	return Item.Rarity.NORMAL


## The weights roll_rarity uses (index = Item.Rarity).
func get_rarity_weights(rarity_bonus: float = 0.0, monster_rarity: int = 0) -> Array[float]:
	var bonus := rarity_bonus + MONSTER_RARITY_BONUS[clampi(monster_rarity, 0, 3)]
	var mult := maxf(0.0, 1.0 + bonus / 100.0)
	var w: Array[float] = [RARITY_WEIGHTS[0]]
	for i in range(1, 4):
		w.append(RARITY_WEIGHTS[i] * mult)
	return w


# ------------------------------------------------------------------ crafting

## Vendor crafting: reroll every explicit affix (keeps rarity; rares get a new name).
## Returns false for normal/unique items.
func reroll_affixes(item: Item) -> bool:
	if item == null or not (item.rarity in [Item.Rarity.MAGIC, Item.Rarity.RARE]):
		return false
	item.affixes = []
	if item.rarity == Item.Rarity.MAGIC:
		_add_affixes(item, _weighted_key(MAGIC_AFFIX_COUNTS))
	else:
		_add_affixes(item, _weighted_key(RARE_AFFIX_COUNTS))
		item.name = NameData.random_rare_name(item.get_base())
	return not item.affixes.is_empty()


## Vendor crafting: normal -> magic (1-2 affixes) -> rare (keeps the affixes, adds up to 3-6 and
## gets a name). Returns false at rare/unique.
func upgrade_rarity(item: Item) -> bool:
	if item == null:
		return false
	match item.rarity:
		Item.Rarity.NORMAL:
			item.rarity = Item.Rarity.MAGIC
			item.affixes = []
			item.name = ""
			_add_affixes(item, _weighted_key(MAGIC_AFFIX_COUNTS))
			return true
		Item.Rarity.MAGIC:
			item.rarity = Item.Rarity.RARE
			var target := maxi(_weighted_key(RARE_AFFIX_COUNTS), item.affixes.size() + 1)
			_add_affixes(item, target - item.affixes.size())
			item.name = NameData.random_rare_name(item.get_base())
			return true
	return false


## Gold cost for the crafting services (0 = not available for this item).
func reroll_cost(item: Item) -> int:
	if item == null:
		return 0
	match item.rarity:
		Item.Rarity.MAGIC:
			return 20 + 6 * item.item_level
		Item.Rarity.RARE:
			return 60 + 15 * item.item_level
	return 0


func upgrade_cost(item: Item) -> int:
	if item == null:
		return 0
	match item.rarity:
		Item.Rarity.NORMAL:
			return 30 + 5 * item.item_level
		Item.Rarity.MAGIC:
			return 150 + 20 * item.item_level
	return 0


# ------------------------------------------------------------------ vendor

## Items the vendor sells in town for this area level (item level = area level). Always includes a
## melee weapon, a bow or crossbow and a wand or staff at the current tier; the rest are random
## (normal/magic, sometimes rare; never unique). Sorted by slot type.
func generate_vendor_stock(area_level: int, count: int = 12) -> Array:
	var lvl := maxi(1, area_level)
	var stock: Array = []
	for cats: Array[String] in [MELEE_CATEGORIES, RANGED_CATEGORIES, CASTER_CATEGORIES]:
		var cat: String = cats[randi() % cats.size()]
		stock.append(create_item(get_base_for_level(cat, lvl), _vendor_rarity(), lvl))
	while stock.size() < maxi(count, 3):
		stock.append(generate_random_item(lvl, _vendor_rarity()))
	stock.sort_custom(_vendor_sort)
	return stock


func _vendor_rarity() -> int:
	var total := 0.0
	for w in VENDOR_RARITY_WEIGHTS:
		total += w
	var r := randf() * total
	for i in VENDOR_RARITY_WEIGHTS.size():
		r -= VENDOR_RARITY_WEIGHTS[i]
		if r < 0.0:
			return i
	return Item.Rarity.NORMAL


func _vendor_sort(a: Item, b: Item) -> bool:
	var sa := Item.SLOT_TYPES.find(a.get_slot_type())
	var sb := Item.SLOT_TYPES.find(b.get_slot_type())
	if sa != sb:
		return sa < sb
	return a.base_id < b.base_id


# ------------------------------------------------------------------ rolling helpers

## Roll one mod template ({"stat","op","min","max"[,"min2","max2"][,"decimals"]} or with a fixed
## "value") into a mod {"stat","op","value"[,"value2"]}. `mult` scales min/max (two-handers).
func roll_mod(t: Dictionary, mult: float = 1.0) -> Dictionary:
	var m := {"stat": String(t.get("stat", "")), "op": String(t.get("op", "flat"))}
	var dec := int(t.get("decimals", 0))
	if t.has("value"):
		m["value"] = float(t["value"])
		return m
	var lo := _scaled(float(t.get("min", 0.0)), mult, dec)
	var hi := maxf(lo, _scaled(float(t.get("max", t.get("min", 0.0))), mult, dec))
	m["value"] = _roll_value(lo, hi, dec)
	if t.has("min2"):
		var lo2 := maxf(hi, _scaled(float(t["min2"]), mult, dec))
		var hi2 := maxf(lo2, _scaled(float(t.get("max2", t["min2"])), mult, dec))
		m["value2"] = maxf(float(m["value"]), _roll_value(lo2, hi2, dec))
	return m


func _roll_templates(templates: Array, mult: float) -> Array:
	var out: Array = []
	for t: Dictionary in templates:
		out.append(roll_mod(t, mult))
	return out


func _scaled(v: float, mult: float, dec: int) -> float:
	var p := pow(10.0, dec)
	return roundf(v * mult * p) / p


func _roll_value(lo: float, hi: float, dec: int) -> float:
	var p := pow(10.0, dec)
	var a := int(roundf(lo * p))
	var b := int(roundf(hi * p))
	return float(randi_range(mini(a, b), maxi(a, b))) / p


## Affix ids of `kind` allowed on this base (cached).
func _affix_pool(base_id: String, kind: String) -> Array:
	var key := base_id + "|" + kind
	if _pool_cache.has(key):
		return _pool_cache[key]
	var base := get_base(base_id)
	var pool: Array[String] = []
	if not base.is_empty():
		for id: String in _affixes:
			var a: Dictionary = _affixes[id]
			if a["kind"] == kind and affix_allowed_on_base(a, base):
				pool.append(id)
	pool.make_read_only()
	_pool_cache[key] = pool
	return pool


## Add up to `count` explicit affixes respecting the rarity's prefix/suffix limits and groups.
func _add_affixes(item: Item, count: int) -> void:
	var max_p: int = MAX_PREFIXES.get(item.rarity, 0)
	var max_s: int = MAX_SUFFIXES.get(item.rarity, 0)
	var base := item.get_base()
	var mult: float = 1.0
	for i in count:
		var groups := {}
		var n_p := 0
		var n_s := 0
		for a: Dictionary in item.affixes:
			groups[_group_of(a.get("id", ""))] = true
			if a.get("kind", "") == "prefix":
				n_p += 1
			elif a.get("kind", "") == "suffix":
				n_s += 1
		var kinds: Array[String] = []
		if n_p < max_p and not _available(item.base_id, "prefix", groups, item.item_level).is_empty():
			kinds.append("prefix")
		if n_s < max_s and not _available(item.base_id, "suffix", groups, item.item_level).is_empty():
			kinds.append("suffix")
		if kinds.is_empty():
			return
		var kind: String = kinds[randi() % kinds.size()]
		var choices := _available(item.base_id, kind, groups, item.item_level)
		var weights := {}
		for id: String in choices:
			weights[id] = float(_affixes[id].get("weight", 100))
		var affix: Dictionary = _affixes[_weighted_key(weights)]
		var tier: Dictionary = _pick_affix_tier(affix, item.item_level)
		mult = float(affix.get("two_handed_mult", 1.0)) if bool(base.get("two_handed", false)) else 1.0
		item.affixes.append({
			"id": affix["id"], "kind": kind, "tier": int(tier["tier"]), "name": tier["name"],
			"mods": _roll_templates(tier["mods"], mult),
		})


func _group_of(affix_id: String) -> String:
	return String(_affixes.get(affix_id, {}).get("group", affix_id))


func _available(base_id: String, kind: String, groups: Dictionary, ilvl: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in _affix_pool(base_id, kind):
		var a: Dictionary = _affixes[id]
		if groups.has(a["group"]):
			continue
		if int(a["tiers"][0]["ilvl"]) <= ilvl:
			out.append(id)
	return out


## Tier dict for an item level: among tiers with ilvl <= item_level, weighted toward the best.
func _pick_affix_tier(affix: Dictionary, ilvl: int) -> Dictionary:
	var allowed: Array = []
	for t: Dictionary in affix["tiers"]:
		if int(t["ilvl"]) <= ilvl:
			allowed.append(t)
	if allowed.is_empty():
		return affix["tiers"][0]
	var weights := {}
	for i in allowed.size():
		var from_top := allowed.size() - 1 - i
		weights[i] = AFFIX_TIER_WEIGHTS[mini(from_top, AFFIX_TIER_WEIGHTS.size() - 1)]
	return allowed[_weighted_key(weights)]


func _pick_unique(ilvl: int, slot_type: String) -> String:
	var ids: Array[String] = []
	for uid: String in _uniques:
		var u: Dictionary = _uniques[uid]
		if int(u["level"]) > ilvl:
			continue
		if slot_type != "":
			var base := get_base(u["base"])
			if base.get("slot_type", "") != slot_type and base.get("category", "") != slot_type:
				continue
		ids.append(uid)
	if ids.is_empty():
		return ""
	return ids[randi() % ids.size()]


## Make an Array/Dictionary and everything nested in it read-only (make_read_only is shallow).
## Returns `v` for chaining. Other values are returned unchanged.
static func deep_make_read_only(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d:
			deep_make_read_only(d[k])
		d.make_read_only()
	elif v is Array:
		var a: Array = v
		for e: Variant in a:
			deep_make_read_only(e)
		a.make_read_only()
	return v


## Weighted random key of {key: weight}.
func _weighted_key(weights: Dictionary) -> Variant:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := randf() * total
	var last: Variant = null
	for k in weights:
		last = k
		r -= float(weights[k])
		if r < 0.0:
			return k
	return last

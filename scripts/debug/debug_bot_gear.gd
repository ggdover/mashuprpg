extends RefCounted
## Gear decisions of the autoplay bot: upgrades (a whole-character power score from
## DebugBotEval, so weapons, armour, jewellery, requirements and two-handed / off-hand rules are
## all judged the same way), what to pick up, sell, stash and buy. Weapon and off-hand types are
## limited per class so each class keeps its playstyle. OWNER: flow (wave 2).

const DebugBotEval := preload("res://scripts/debug/debug_bot_eval.gd")
const DebugBotBuild := preload("res://scripts/debug/debug_bot_build.gd")

## weapon_type values the class wields.
const CLASS_WEAPONS := {
	"warrior": ["sword", "axe", "mace"],
	"ranger": ["bow", "crossbow"],
	"sorcerer": ["wand", "staff"],
}
## Off-hand weapon_type values ("shield", "quiver", "focus").
const CLASS_OFFHANDS := {
	"warrior": ["shield"],
	"ranger": ["quiver"],
	"sorcerer": ["focus", "shield"],
}
## Item categories used to equip a boosted (--depth) character.
const CLASS_WEAPON_CATEGORIES := {
	"warrior": ["sword", "axe", "mace", "greatsword", "greataxe", "maul"],
	"ranger": ["bow"],
	"sorcerer": ["wand"],
}
## An item must raise the power score by this factor to count as an upgrade.
const UPGRADE_MARGIN := 1.02
const BUY_MARGIN := 1.06

var eval: DebugBotEval = null
var class_id := "warrior"
## The class's player skill ids: offence() filters them by level and weapon.
var skill_ids: Array = []

var _base_key := ""
var _base_score := 1.0


func _init(p_class_id: String) -> void:
	class_id = p_class_id if CLASS_WEAPONS.has(p_class_id) else "warrior"
	eval = DebugBotEval.new()
	skill_ids = DebugBotBuild.class_skills(class_id)


## Free the evaluation actor (a Node) when the bot is done.
func dispose() -> void:
	if eval != null and is_instance_valid(eval):
		eval.free()
	eval = null


## Weapons / off-hands of other playstyles are never equipped.
func allowed(item: Item) -> bool:
	if item == null:
		return false
	match item.get_slot_type():
		"weapon":
			return item.get_weapon_type() in CLASS_WEAPONS[class_id]
		"offhand":
			return item.get_weapon_type() in CLASS_OFFHANDS[class_id]
	return true


## Equipment slots that accept the item.
static func candidate_slots(item: Item) -> Array[String]:
	var out: Array[String] = []
	if item == null:
		return out
	var st := item.get_slot_type()
	for slot in CharacterData.EQUIP_SLOTS:
		if CharacterData.SLOT_ACCEPTS[slot] == st:
			out.append(slot)
	return out


## Power score of the character wearing `equipment`.
func score_with(c: CharacterData, equipment: Dictionary) -> float:
	eval.configure(c, equipment)
	return eval.power_score(skill_ids)


## Score of the current equipment (cached per character state).
func base_score(c: CharacterData) -> float:
	var key := "%d|%d|%d|%s" % [c.level, c.allocated_passives.size(), c.allocated_passives.hash(), _equip_key(c.equipment)]
	if key != _base_key:
		_base_key = key
		_base_score = maxf(0.0001, score_with(c, c.equipment))
	return _base_score


## c.equipment with `item` put into `slot` (conflicting slots emptied, its old slot freed).
static func equipment_with(c: CharacterData, item: Item, slot: String) -> Dictionary:
	var eq := c.equipment.duplicate()
	var from := c.find_equipped_slot(item)
	if from != "":
		eq.erase(from)
	for s in c.get_equip_conflicts(item, slot):
		eq.erase(s)
	eq[slot] = item
	return eq


## Best score ratio (new / current) of equipping `item` in any slot it fits, requirements
## checked. 0 when it can't be equipped (or isn't for this class).
func item_gain(c: CharacterData, item: Item) -> Dictionary:
	var best := {"gain": 0.0, "slot": ""}
	if not allowed(item):
		return best
	var base := base_score(c)
	for slot in candidate_slots(item):
		if not c.can_equip(item, slot).get("ok", false):
			continue
		var g := score_with(c, equipment_with(c, item, slot)) / base
		if g > float(best["gain"]):
			best = {"gain": g, "slot": slot}
	return best


## The best upgrade in the inventory: {"index", "slot", "gain", "item"}, or {} if none.
func best_upgrade(c: CharacterData) -> Dictionary:
	var best := {}
	var best_gain := UPGRADE_MARGIN
	for i in c.inventory.size():
		var it: Item = c.inventory[i]
		if it == null:
			continue
		var r := item_gain(c, it)
		if float(r["gain"]) > best_gain:
			best_gain = float(r["gain"])
			best = {"index": i, "slot": r["slot"], "gain": best_gain, "item": it}
	return best


func should_pick_up(c: CharacterData, item: Item) -> bool:
	if item == null or c.inventory_free_count() <= 0:
		return false
	if item.rarity >= Item.Rarity.RARE:
		return true
	if item.rarity == Item.Rarity.MAGIC:
		return c.inventory_free_count() > 8 or float(item_gain(c, item)["gain"]) > UPGRADE_MARGIN
	return float(item_gain(c, item)["gain"]) > UPGRADE_MARGIN


## Not an upgrade and not worth keeping (uniques and good rares go to the stash).
func should_sell(c: CharacterData, item: Item) -> bool:
	if item == null or item.rarity == Item.Rarity.UNIQUE:
		return false
	if item.rarity == Item.Rarity.RARE and _stash_worthy(c, item):
		return false
	return float(item_gain(c, item)["gain"]) <= UPGRADE_MARGIN


## Uniques, and rares of the character's item level range that are no upgrade right now (spares
## for later), while the stash has room.
func should_stash(c: CharacterData, item: Item) -> bool:
	if item == null or c.first_free_stash_index() < 0:
		return false
	if float(item_gain(c, item)["gain"]) > UPGRADE_MARGIN:
		return false
	return item.rarity == Item.Rarity.UNIQUE or (item.rarity == Item.Rarity.RARE and _stash_worthy(c, item))


func _stash_worthy(c: CharacterData, item: Item) -> bool:
	return c.first_free_stash_index() >= 0 and item.item_level >= c.level - 3 and allowed(item)


## Index into GameState.vendor_stock worth buying (affordable upgrade), or -1.
func best_purchase(c: CharacterData) -> int:
	var best := -1
	var best_gain := BUY_MARGIN
	for i in GameState.vendor_stock.size():
		var it: Item = GameState.vendor_stock[i]
		if it == null or it.get_buy_value() > c.gold or not allowed(it):
			continue
		var g := float(item_gain(c, it)["gain"])
		if g > best_gain:
			best_gain = g
			best = i
	return best


## Items to hand a boosted character (--depth=N): a few rolls per slot at item level `ilvl`.
func boost_items(ilvl: int) -> Array:
	var out: Array = []
	var cats: Array = CLASS_WEAPON_CATEGORIES[class_id]
	for k in 3:
		out.append(ItemDB.generate_random_item(ilvl, Item.Rarity.RARE, String(cats[k % cats.size()])))
	for st in ["helmet", "body", "gloves", "boots", "ring", "ring", "amulet", "belt", "offhand", "offhand"]:
		var it: Item = ItemDB.generate_random_item(ilvl, Item.Rarity.MAGIC if randf() < 0.5 else Item.Rarity.RARE, st)
		if it != null:
			out.append(it)
	return out.filter(func(x: Variant) -> bool: return x != null)


static func _equip_key(eq: Dictionary) -> String:
	var parts: PackedStringArray = []
	for slot in CharacterData.EQUIP_SLOTS:
		var it: Item = eq.get(slot, null)
		parts.append(str(it.uid) if it != null else "-")
	return ",".join(parts)

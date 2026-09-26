class_name InvActions
extends RefCounted
## Item moves shared by the item panels (inventory grid, paper doll, stash, vendor): drag & drop
## between containers, quick actions (right-click equip/unequip, shift+click stash), selling,
## buying and dropping on the ground. Every change goes through CharacterData mutators, so the
## usual Events signals fire. Failures return {"ok": false, "reason": ...} and show the reason as
## a notification (Events.notify). OWNER: ui-items. See docs/ARCHITECTURE.md §9.1, §9.7, §16.
##
## Drag payload (§16): {"type": "item", "item": Item, "from": "inventory"|"equipment"|"stash"|
## "vendor", "index": int, "slot": String}. Vendor payloads also carry "price": int and
## "buyback": bool.

const MAX_BUYBACK := 10
## Containers an item can be dragged out of into the character's own storage.
const OWN_SOURCES: Array[String] = ["inventory", "equipment", "stash"]

## The open VendorPanel / StashPanel, registered by the panels in on_opened() and cleared in
## on_closed(). Lets the inventory route Ctrl+click (sell) and Shift+click (stash) without UIRoot.
static var vendor_panel: Control = null
static var stash_panel: Control = null
## Items sold during this town visit, newest first (bought back at their sell value). Cleared
## when GameState.vendor_stock is replaced (new town visit) or another character is loaded or
## created (the list belongs to the character who sold the items).
static var buyback: Array = []
static var _buyback_stock: Variant = null
## Instance id of the character the buyback list belongs to (an id, so the old character isn't
## kept alive).
static var _buyback_char_id: int = 0


# ------------------------------------------------------------------ context

static func character() -> CharacterData:
	return GameState.character


static func is_vendor_open() -> bool:
	return vendor_panel != null and is_instance_valid(vendor_panel) and vendor_panel.is_visible_in_tree()


static func is_stash_open() -> bool:
	return stash_panel != null and is_instance_valid(stash_panel) and stash_panel.is_visible_in_tree()


static func has_live_player() -> bool:
	return GameState.player != null and is_instance_valid(GameState.player) and GameState.player.is_inside_tree()


## Attributes for requirement checks: the live Player's (buffs included) when there is one, else
## CharacterData.compute_attributes(). Includes "level" (the character's level).
static func get_attributes() -> Dictionary:
	var c := character()
	var attrs := {}
	var p: Node = GameState.player
	if p != null and is_instance_valid(p) and p.has_method("get_attributes"):
		var a: Variant = p.call("get_attributes")
		if a is Dictionary:
			attrs = (a as Dictionary).duplicate()
	if attrs.is_empty() and c != null:
		attrs = c.compute_attributes()
	if c != null:
		attrs["level"] = c.level
	return attrs


## The equipped item `item` would replace (its default slot), or null (nothing there, or the item
## is equipped itself).
static func comparison_item(item: Item) -> Item:
	var c := character()
	if c == null or item == null or c.find_equipped_slot(item) != "":
		return null
	var slot := c.get_default_slot_for(item)
	if slot == "":
		return null
	var eq: Item = c.get_equipped(slot)
	return eq if eq != item else null


static func make_payload(item: Item, from: String, index: int = -1, slot: String = "") -> Dictionary:
	return {"type": "item", "item": item, "from": from, "index": index, "slot": slot}


static func is_item_payload(data: Variant) -> bool:
	return data is Dictionary and String((data as Dictionary).get("type", "")) == "item" and (data as Dictionary).get("item") is Item


## Whether the payload's item is still where the payload says (drags can go stale).
static func source_has(p: Dictionary) -> bool:
	var c := character()
	if c == null or not is_item_payload(p):
		return false
	var item: Item = p["item"]
	var i := int(p.get("index", -1))
	match String(p.get("from", "")):
		"inventory":
			return i >= 0 and i < c.inventory.size() and c.inventory[i] == item
		"equipment":
			return c.get_equipped(String(p.get("slot", ""))) == item
		"stash":
			return i >= 0 and i < c.stash.size() and c.stash[i] == item
		"vendor":
			if bool(p.get("buyback", false)):
				return buyback.has(item)
			return GameState.vendor_stock.has(item)
	return false


## Where an owned item currently is: {"from", "index", "slot"} or {} if the character doesn't
## own it (anymore).
static func locate(item: Item) -> Dictionary:
	var c := character()
	if c == null or item == null:
		return {}
	var i := c.find_inventory_index(item)
	if i >= 0:
		return {"from": "inventory", "index": i, "slot": ""}
	var s := c.find_equipped_slot(item)
	if s != "":
		return {"from": "equipment", "index": -1, "slot": s}
	var k := c.stash.find(item)
	if k >= 0:
		return {"from": "stash", "index": k, "slot": ""}
	return {}


## Payload for an owned item wherever it is ({} if not owned).
static func payload_for(item: Item) -> Dictionary:
	var loc := locate(item)
	if loc.is_empty():
		return {}
	return make_payload(item, loc["from"], loc["index"], loc["slot"])


## Remove the payload's item from its source container (inventory/equipment/stash) and return it,
## or null if it isn't there anymore.
static func take_from_source(p: Dictionary) -> Item:
	var c := character()
	if not source_has(p):
		return null
	var i := int(p.get("index", -1))
	match String(p.get("from", "")):
		"inventory":
			return c.take_from_inventory(i)
		"equipment":
			return c.unequip(String(p.get("slot", "")))
		"stash":
			return c.take_from_stash(i)
	return null


# ------------------------------------------------------------------ drag & drop

## Whether a drop of `p` onto a destination cell is allowed at all (slot type for equipment).
## Requirements are checked on drop (with a message).
static func can_move(p: Dictionary, dest_kind: String, dest_index: int = -1, dest_slot: String = "") -> bool:
	if character() == null or not is_item_payload(p):
		return false
	var from := String(p.get("from", ""))
	if not OWN_SOURCES.has(from):
		return false
	var item: Item = p["item"]
	match dest_kind:
		"inventory", "stash":
			return dest_index >= 0
		"equipment":
			return CharacterData.SLOT_ACCEPTS.has(dest_slot) and item.get_slot_type() == CharacterData.SLOT_ACCEPTS[dest_slot]
	return false


## Highlight state of an equipment slot for a dragged payload: 0 = not accepted, 1 = can equip,
## 2 = right slot type but refused (requirements / off-hand rules).
static func equip_drop_state(p: Dictionary, dest_slot: String) -> int:
	if not can_move(p, "equipment", -1, dest_slot):
		return 0
	var c := character()
	var item: Item = p["item"]
	if c.find_equipped_slot(item) == dest_slot:
		return 0
	return 1 if bool(c.can_equip(item, dest_slot, get_attributes()).get("ok", false)) else 2


## Perform a drop of `p` onto a destination cell: "inventory" / "stash" (dest_index) or
## "equipment" (dest_slot). Swaps when the target cell is occupied.
static func move(p: Dictionary, dest_kind: String, dest_index: int = -1, dest_slot: String = "") -> Dictionary:
	var c := character()
	if c == null:
		return _no("No character", false)
	if not can_move(p, dest_kind, dest_index, dest_slot):
		return _no("Can't put that there")
	if not source_has(p):
		return _no("", false)
	var from := String(p.get("from", ""))
	var si := int(p.get("index", -1))
	var ss := String(p.get("slot", ""))
	var item: Item = p["item"]
	var attrs := get_attributes()
	match dest_kind:
		"inventory":
			if dest_index >= c.inventory.size():
				return _no("", false)
			match from:
				"inventory":
					if si != dest_index:
						c.move_inventory(si, dest_index)
						Sfx.play_ui("ui_click")
					return _ok()
				"equipment":
					var target: Item = c.inventory[dest_index]
					if target == null:
						c.put_in_inventory(dest_index, c.unequip(ss))
						Sfx.play_ui("equip")
						return _ok()
					if target.get_slot_type() == CharacterData.SLOT_ACCEPTS.get(ss, ""):
						return _equip_result(c.equip_from_inventory(dest_index, ss, attrs))
					if c.unequip_to_inventory(ss):
						Sfx.play_ui("equip")
						return _ok()
					return _no("Inventory full", false)
				"stash":
					var it := c.take_from_stash(si)
					var prev := c.put_in_inventory(dest_index, it)
					if prev != null:
						c.put_in_stash(si, prev)
					Sfx.play_ui("ui_click")
					return _ok()
		"stash":
			if dest_index >= c.stash.size():
				return _no("", false)
			match from:
				"stash":
					if si != dest_index:
						c.move_stash(si, dest_index)
						Sfx.play_ui("ui_click")
					return _ok()
				"inventory":
					var it := c.take_from_inventory(si)
					var prev := c.put_in_stash(dest_index, it)
					if prev != null:
						c.put_in_inventory(si, prev)
					Sfx.play_ui("ui_click")
					return _ok()
				"equipment":
					var target: Item = c.stash[dest_index]
					if target == null:
						c.put_in_stash(dest_index, c.unequip(ss))
						Sfx.play_ui("equip")
						return _ok()
					if target.get_slot_type() == CharacterData.SLOT_ACCEPTS.get(ss, ""):
						return _equip_from_stash(dest_index, ss, attrs)
					if c.first_free_stash_index() < 0:
						return _no("Stash full")
					c.add_to_stash(c.unequip(ss))
					Sfx.play_ui("equip")
					return _ok()
		"equipment":
			match from:
				"inventory":
					return _equip_result(c.equip_from_inventory(si, dest_slot, attrs))
				"equipment":
					if ss == dest_slot:
						return _ok()
					var chk := c.can_equip(item, dest_slot, attrs)
					if not bool(chk.get("ok", false)):
						return _no(String(chk.get("reason", "")))
					for d: Item in c.equip(item, dest_slot):
						if not c.add_to_inventory(d) and not c.add_to_stash(d):
							push_warning("InvActions: no room for displaced %s" % d.get_display_name())
					Sfx.play_ui("equip")
					return _ok()
				"stash":
					return _equip_from_stash(si, dest_slot, attrs)
	return _no("Can't put that there")


## Equip stash[index] into `slot`; displaced items go to the freed stash cell first, then the
## inventory (then the stash).
static func _equip_from_stash(index: int, slot: String, attrs: Dictionary) -> Dictionary:
	var c := character()
	var item: Item = c.stash[index]
	if item == null:
		return _no("", false)
	var chk := c.can_equip(item, slot, attrs)
	if not bool(chk.get("ok", false)):
		return _no(String(chk.get("reason", "")))
	var outgoing := c.get_equip_conflicts(item, slot).size() + (1 if c.get_equipped(slot) != null else 0)
	if outgoing - 1 > c.inventory_free_count() + maxi(0, c.stash.count(null)):
		Events.inventory_full.emit()
		return _no("Inventory full", false)
	c.take_from_stash(index)
	for d: Item in c.equip(item, slot):
		if c.stash[index] == null:
			c.put_in_stash(index, d)
		elif not c.add_to_inventory(d) and not c.add_to_stash(d):
			push_warning("InvActions: no room for displaced %s" % d.get_display_name())
	Sfx.play_ui("equip")
	return _ok()


static func _equip_result(r: Dictionary) -> Dictionary:
	if bool(r.get("ok", false)):
		Sfx.play_ui("equip")
		return _ok()
	var reason := String(r.get("reason", ""))
	# equip_from_inventory already emitted inventory_full (UIRoot shows it).
	return _no(reason, reason != "Inventory full")


# ------------------------------------------------------------------ quick actions

## Right-click in the inventory: equip into the default slot.
static func equip_inventory_item(index: int) -> Dictionary:
	var c := character()
	if c == null or index < 0 or index >= c.inventory.size() or c.inventory[index] == null:
		return _no("", false)
	return _equip_result(c.equip_from_inventory(index, "", get_attributes()))


## Right-click on the paper doll: move the item into the inventory.
static func unequip_slot(slot: String) -> Dictionary:
	var c := character()
	if c == null or c.get_equipped(slot) == null:
		return _no("", false)
	if c.unequip_to_inventory(slot):
		Sfx.play_ui("equip")
		return _ok()
	return _no("Inventory full", false)


## Shift+click in the inventory while the stash is open.
static func inventory_to_stash(index: int) -> Dictionary:
	var c := character()
	if c == null or index < 0 or index >= c.inventory.size() or c.inventory[index] == null:
		return _no("", false)
	if c.first_free_stash_index() < 0:
		return _no("Stash full")
	c.add_to_stash(c.take_from_inventory(index))
	Sfx.play_ui("ui_click")
	return _ok()


## Shift+click (or right-click) in the stash.
static func stash_to_inventory(index: int) -> Dictionary:
	var c := character()
	if c == null or index < 0 or index >= c.stash.size() or c.stash[index] == null:
		return _no("", false)
	if c.first_free_inventory_index() < 0:
		Events.inventory_full.emit()
		return _no("Inventory full", false)
	c.add_to_inventory(c.take_from_stash(index))
	Sfx.play_ui("ui_click")
	return _ok()


## Shift+click on the paper doll while the stash is open.
static func equipment_to_stash(slot: String) -> Dictionary:
	var c := character()
	if c == null or c.get_equipped(slot) == null:
		return _no("", false)
	if c.first_free_stash_index() < 0:
		return _no("Stash full")
	c.add_to_stash(c.unequip(slot))
	Sfx.play_ui("equip")
	return _ok()


## Drop an owned item on the floor at the live player's feet (drag released outside the UI).
static func drop_to_ground(p: Dictionary) -> bool:
	if not has_live_player() or not OWN_SOURCES.has(String(p.get("from", ""))):
		return false
	var it := take_from_source(p)
	if it == null:
		return false
	var pos: Vector3 = GameState.player.global_position
	LootSystem.spawn_item(it, pos)
	Sfx.play("drop_item", pos)
	return true


# ------------------------------------------------------------------ vendor

## Sell value of an item (0 for null).
static func sell_value(item: Item) -> int:
	return item.get_sell_value() if item != null else 0


## Price of a vendor payload (stock: buy value, buyback: sell value).
static func price_of(p: Dictionary) -> int:
	var item: Item = p.get("item")
	if item == null:
		return 0
	return item.get_sell_value() if bool(p.get("buyback", false)) else item.get_buy_value()


## Sell an owned item (no confirmation here: the vendor panel asks first for rare/unique).
## Returns the gold received (0 if nothing was sold).
static func sell(p: Dictionary) -> int:
	var c := character()
	if c == null or not OWN_SOURCES.has(String(p.get("from", ""))):
		return 0
	sync_buyback()
	var it := take_from_source(p)
	if it == null:
		return 0
	var value := it.get_sell_value()
	buyback.push_front(it)
	while buyback.size() > MAX_BUYBACK:
		buyback.pop_back()
	c.add_gold(value)
	Sfx.play_ui("pickup_gold")
	return value


## Buy a vendor payload (stock or buyback) into inventory cell dest_index (or the first free cell
## if -1 / occupied). Checks gold and space.
static func buy(p: Dictionary, dest_index: int = -1) -> Dictionary:
	var c := character()
	if c == null or not is_item_payload(p) or String(p.get("from", "")) != "vendor":
		return _no("", false)
	sync_buyback()
	if not source_has(p):
		return _no("That item is no longer for sale")
	var item: Item = p["item"]
	var price := price_of(p)
	if c.gold < price:
		return _no("Not enough gold")
	var idx := dest_index
	if idx < 0 or idx >= c.inventory.size() or c.inventory[idx] != null:
		idx = c.first_free_inventory_index()
	if idx < 0:
		Events.inventory_full.emit()
		return _no("Inventory full", false)
	if bool(p.get("buyback", false)):
		buyback.erase(item)
	else:
		GameState.vendor_stock.erase(item)
	c.spend_gold(price)
	c.put_in_inventory(idx, item)
	Sfx.play_ui("pickup_item")
	return _ok()


## Clear the buyback list when the vendor stock was replaced (new town visit) or the character
## changed (load / new game).
static func sync_buyback() -> void:
	var cid := GameState.character.get_instance_id() if GameState.character != null else 0
	if _buyback_stock == null or not is_same(_buyback_stock, GameState.vendor_stock) or cid != _buyback_char_id:
		buyback.clear()
		_buyback_stock = GameState.vendor_stock
		_buyback_char_id = cid


## Re-emit the change signal of the container holding `item` after it was modified in place
## (crafting), so the player recalculates stats and panels refresh.
static func notify_item_changed(item: Item) -> void:
	var c := character()
	var loc := locate(item)
	if c == null or loc.is_empty():
		return
	match String(loc["from"]):
		"inventory":
			c.put_in_inventory(int(loc["index"]), item)
		"stash":
			c.put_in_stash(int(loc["index"]), item)
		"equipment":
			var slot := String(loc["slot"])
			c.unequip(slot)
			var back := c.equip(item, slot)
			for d: Item in back:
				if d == item:
					# Refused (shouldn't happen for an item that was equipped): keep it.
					if not c.add_to_inventory(d):
						c.add_to_stash(d)
				elif not c.add_to_inventory(d):
					c.add_to_stash(d)


# ------------------------------------------------------------------ helpers

static func _ok() -> Dictionary:
	return {"ok": true, "reason": ""}


## A failure; shows the reason as a notification unless silent / empty.
static func _no(reason: String, show: bool = true) -> Dictionary:
	if show and reason != "":
		Events.notify.emit(reason, UIStyle.COLOR_BAD)
	return {"ok": false, "reason": reason}

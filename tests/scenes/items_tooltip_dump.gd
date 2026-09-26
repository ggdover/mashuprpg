extends Node
## Prints item tooltips as plain text (wording check) and some generation statistics, then quits.
##   tools/gtest.sh items res://tests/scenes/items_tooltip_dump.tscn [-- --count=N --ilvl=L --seed=S]
## OWNER: items.


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	var count := 6
	var ilvl := 30
	var rng_seed := 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--count="):
			count = int(a.substr(8))
		elif a.begins_with("--ilvl="):
			ilvl = int(a.substr(7))
		elif a.begins_with("--seed="):
			rng_seed = int(a.substr(7))
	seed(rng_seed)
	var attrs := {"strength": 30, "dexterity": 20, "intelligence": 15, "level": 20}
	var equipped := ItemDB.create_item("sword_3", Item.Rarity.MAGIC, 20)
	var samples: Array = [
		ItemDB.create_item("sword_1"),
		ItemDB.create_item("greataxe_4", Item.Rarity.MAGIC, 30),
		ItemDB.create_item("bow_5", Item.Rarity.RARE, 45),
		ItemDB.create_item("body_str_dex_3", Item.Rarity.RARE, 24),
		ItemDB.create_item("shield_str_2", Item.Rarity.MAGIC, 12),
		ItemDB.create_item("ring_4", Item.Rarity.RARE, 40),
		ItemDB.create_unique("gorebinder"),
		ItemDB.create_unique("glasswork_amulet"),
		ItemDB.create_unique("bloodbond_plate"),
	]
	for i in count:
		samples.append(ItemDB.generate_random_item(ilvl))
	for it: Item in samples:
		var cmp: Item = equipped if it.is_weapon() else null
		print_item(it, attrs, cmp)
	print("bases=%d affixes=%d uniques=%d" % [ItemDB.get_all_bases().size(), ItemDB.get_all_affixes().size(), ItemDB.get_all_uniques().size()])
	get_tree().quit()


static func print_item(it: Item, attrs: Dictionary = {}, cmp: Item = null) -> void:
	print("+------------------------------------------------------------")
	for l: Dictionary in it.get_tooltip_lines(attrs, cmp):
		if l.get("separator", false):
			print("|  ----")
			continue
		var tag := ""
		var c: Color = l["color"]
		if c == UIStyle.COLOR_BAD:
			tag = " {red}"
		elif c == UIStyle.COLOR_GOOD:
			tag = " {green}"
		elif c == UIStyle.COLOR_MOD:
			tag = " {mod}"
		var pre := "## " if l.get("size", "") == "title" else "|  "
		print(pre + String(l["text"]) + tag + ("   <" + String(l["hint"]) + ">" if l.has("hint") else ""))
	print("|  sell %d / buy %d   model %s   tint %s" % [it.get_sell_value(), it.get_buy_value(), it.get_model_id(), it.get_tint().to_html(false)])

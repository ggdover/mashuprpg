extends Node
## Skills balance report: single-target DPS of every player skill (SkillDB.estimate_dps, real
## DamageCalc) for a naked character of each class with the best normal weapon of its level
## (ItemDB bases, implicits included), as a ratio to basic_attack with the same weapon, plus
## seconds to kill a normal monster of that level and mana use per second vs mana regen.
## With -- --tooltips it prints every skill tooltip for level-12 characters instead.
##
##   tools/gtest.sh skills res://tests/scenes/skills_balance_report.tscn
## OWNER: skills.

const LEVELS: Array[int] = [1, 6, 12, 20, 30, 45]
## [label, class, weapon category]
const KITS := [
	["sword", "warrior", "sword"],
	["greataxe", "warrior", "greataxe"],
	["bow", "ranger", "bow"],
	["crossbow", "ranger", "crossbow"],
	["wand", "sorcerer", "wand"],
	["staff", "sorcerer", "staff"],
]


class Probe extends TestDummy:
	var item_mods: Array = []

	func get_all_mods() -> Array:
		var m := get_base_mods()
		m.append_array(item_mods)
		return m


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	print("")
	print("==================== SKILLS BALANCE REPORT ====================")
	if OS.get_cmdline_user_args().has("--tooltips"):
		_tooltips()
		get_tree().quit()
		return
	for lvl in LEVELS:
		_level(lvl)
	print("")
	print("ratio = skill DPS / basic_attack DPS with the same weapon (target for attacks 1.3-1.8);")
	print("ttk = seconds to kill one normal monster of the level (life only, no armour);")
	print("mana/s = cost per second while spamming; regen = mana regen/s of the naked character.")
	print("===============================================================")
	get_tree().quit()


func _probe(class_id: String, category: String, lvl: int) -> Probe:
	var p := Probe.new()
	p.team = Actor.Team.PLAYER
	p.level = lvl
	p.base_life = Balance.player_base_life(lvl)
	p.base_mana = Balance.player_base_mana(lvl)
	p.extra_mods = ClassDefs.get_attribute_mods(class_id)
	var base_id := ItemDB.get_base_for_level(category, lvl)
	var item := ItemDB.create_item(base_id, Item.Rarity.NORMAL, lvl)
	p.weapon_override = item.get_weapon_stats()
	p.item_mods = item.get_global_mods()
	add_child(p)
	p.recalculate_stats()
	return p


func _level(lvl: int) -> void:
	var mlife := Balance.monster_life(lvl)
	print("")
	print("--- Level %d (normal monster life %.0f) ---" % [lvl, mlife])
	for kit in KITS:
		var p := _probe(kit[1], kit[2], lvl)
		var basic := SkillDB.estimate_dps("basic_attack", p)
		var w: Dictionary = p.get_weapon()
		print("  [%s L%d] %s %.0f-%.0f @%.2f/s | basic %.1f dps | mana %.0f regen %.1f/s" % [kit[0], lvl, w["weapon_type"], w["phys_min"], w["phys_max"], w["attack_speed"], basic, p.max_mana, p.mana_regen])
		for s in SkillDB.get_player_skills():
			var id := String(s["id"])
			if id == "basic_attack" or int(s["unlock_level"]) > lvl + 4:
				continue
			if not SkillDB.is_weapon_compatible(id, String(w["weapon_type"])):
				continue
			var tags: PackedStringArray = s["tags"]
			if tags.has("spell") and not kit[1] == "sorcerer":
				continue
			var dps := SkillDB.estimate_dps(id, p)
			if dps <= 0.0:
				continue
			var r := SkillDB.get_resolved(id, p)
			var t := maxf(DamageCalc.get_use_time(p, r), DamageCalc.get_cooldown(p, r))
			var cost := DamageCalc.get_cost(p, r)
			if String(r["delivery"]) == "channel_aoe":
				cost = DamageCalc.scale_cost(p, float(r["params"].get("cost_per_tick", 0.0)))
			var mps := cost / maxf(0.05, t)
			print("    %-16s dps %7.1f  ratio %4.2f  ttk %5.2fs  mana/s %5.1f" % [id, dps, dps / maxf(0.01, basic), mlife / maxf(0.01, dps), mps])
		p.queue_free()


func _tooltips() -> void:
	var kits := {"sword": ["warrior", "sword"], "bow": ["ranger", "bow"], "crossbow": ["ranger", "crossbow"], "wand": ["sorcerer", "wand"]}
	for s in SkillDB.get_player_skills():
		var id := String(s["id"])
		var kit: Array = kits["wand"]
		var types: Array = s["weapon_types"]
		if types.has("bow"):
			kit = kits["bow"]
		elif types.has("crossbow"):
			kit = kits["crossbow"]
		elif not types.is_empty() or (s["tags"] as PackedStringArray).has("warcry"):
			kit = kits["sword"]
		var p := _probe(kit[0], kit[1], 12)
		print("")
		for l in SkillDB.get_tooltip_lines(id, p):
			if l.get("separator", false):
				print("  ----")
			else:
				print("  [%s] %s" % [l["size"], l["text"]])
		p.queue_free()

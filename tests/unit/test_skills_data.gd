extends "res://tests/unit/test_skills_util.gd"
## SkillDB data validity (§8.1, §8.4, §8.5), weapon compatibility and resolution, tooltips and
## the DPS parity targets (§8.4: attack skills 1.3-1.8x basic_attack single target).

const PLAYER_IDS := ["basic_attack", "heavy_strike", "cleave", "ground_slam", "leap_slam", "whirlwind",
	"infernal_blow", "war_cry", "power_shot", "split_arrow", "rain_of_arrows", "explosive_bolt", "scatter_shot",
	"rapid_fire", "ice_shot", "venom_arrow", "fireball", "ice_spear", "frost_nova", "chain_lightning", "teleport",
	"spark", "meteor", "blood_rite"]
const MONSTER_IDS := ["m_melee", "m_bite", "m_arrow", "m_firebolt", "m_frostbolt", "m_slam", "m_summon", "m_leap",
	"m_boss_nova", "m_boss_volley", "m_boss_charge", "m_boss_meteors", "m_boss_slam", "m_boss_spikes"]
const ANIMS := ["attack_slash", "attack_slam", "attack_stab", "shoot_bow", "shoot_crossbow", "cast", "cast_area", "channel"]
const REQUIRED := ["id", "name", "description", "tags", "weapon_types", "unlock_level", "monster_only", "mana_cost",
	"cooldown", "cast_time", "attack_time_mult", "base_damage", "damage_effectiveness", "more_damage", "monster_damage",
	"damage_mult", "conversion", "crit_chance", "ailments", "delivery", "params", "anim", "hit_frame", "move_mult", "vfx", "sfx"]
const SFX_IDS := ["swing", "hit_flesh", "hit_crit", "bow_shoot", "crossbow_shoot", "spell_cast", "fireball_cast", "explosion",
	"frost_nova", "ice_shatter", "lightning", "meteor_impact", "warcry", "leap_land", "teleport", "whirlwind", "boss_roar"]


func test_frozen_ids_present() -> void:
	for id in PLAYER_IDS:
		assert_true(SkillDB.has_skill(id), "player skill %s" % id)
		assert_false(bool(SkillDB.get_skill(id)["monster_only"]), "%s not monster only" % id)
	for id in MONSTER_IDS:
		assert_true(SkillDB.has_skill(id), "monster skill %s" % id)
	assert_eq(SkillDB.get_player_skills().size(), PLAYER_IDS.size(), "player skill count")
	assert_eq(SkillDB.get_all_ids().size(), PLAYER_IDS.size() + MONSTER_IDS.size(), "total skill count")
	assert_false(SkillDB.has_skill("nope"), "unknown")
	assert_true(SkillDB.get_skill("nope").is_empty(), "unknown -> {}")


func test_player_skills_sorted() -> void:
	var list := SkillDB.get_player_skills()
	for i in range(1, list.size()):
		var a: Dictionary = list[i - 1]
		var b: Dictionary = list[i]
		var ok := int(a["unlock_level"]) < int(b["unlock_level"]) or (int(a["unlock_level"]) == int(b["unlock_level"]) and String(a["name"]) <= String(b["name"]))
		assert_true(ok, "sorted: %s before %s" % [a["id"], b["id"]])
	list.clear()
	assert_eq(SkillDB.get_player_skills().size(), PLAYER_IDS.size(), "returned array is a copy")


func test_schema() -> void:
	for id in SkillDB.get_all_ids():
		var s := SkillDB.get_skill(id)
		for k in REQUIRED:
			assert_has(s, k, "%s has %s" % [id, k])
		assert_eq(String(s["id"]), String(id), "%s id field" % id)
		assert_true(String(s["name"]) != "" and String(s["description"]) != "", "%s name/description" % id)
		assert_true(s["tags"] is PackedStringArray, "%s tags packed" % id)
		assert_true(SkillDB.DELIVERIES.has(String(s["delivery"])), "%s delivery %s known" % [id, s["delivery"]])
		assert_true(ANIMS.has(String(s["anim"])), "%s anim %s known" % [id, s["anim"]])
		assert_between(float(s["hit_frame"]), 0.0, 1.0, "%s hit frame" % id)
		assert_between(float(s["move_mult"]), 0.0, 1.0, "%s move mult" % id)
		var tags: PackedStringArray = s["tags"]
		assert_true(tags.has("attack") or tags.has("spell") or tags.has("warcry"), "%s is an attack, spell or warcry" % id)
		for t in s["base_damage"]:
			assert_true(StatDefs.DAMAGE_TYPES.has(t), "%s base damage type %s" % [id, t])
			var r := DamageCalc.to_range(s["base_damage"][t])
			assert_true(r.x > 0.0 and r.y >= r.x, "%s base damage range" % id)
		for t in s["monster_damage"]:
			assert_true(StatDefs.DAMAGE_TYPES.has(t), "%s monster damage type %s" % [id, t])
		for from_t in s["conversion"]:
			assert_true(StatDefs.DAMAGE_TYPES.has(from_t), "%s conversion from" % id)
			for to_t in s["conversion"][from_t]:
				assert_true(StatDefs.DAMAGE_TYPES.has(to_t), "%s conversion to" % id)
		for k in s["ailments"]:
			assert_true(DamageCalc.HIT_AILMENTS.has(k), "%s ailment %s" % [id, k])
		for m in s["params"].get("mods", []):
			assert_true(StatDefs.has_stat(String(m["stat"])), "%s buff stat %s exists" % [id, m["stat"]])
		for k in ["use", "release", "hit", "impact"]:
			var sid := String(s["sfx"].get(k, ""))
			if sid != "":
				assert_true(SFX_IDS.has(sid), "%s sfx %s is a §17 id" % [id, sid])
		var model := String(s["vfx"].get("model", ""))
		if model != "":
			assert_true(model.begins_with("proj_"), "%s projectile model id" % id)
		var damaging := not (String(s["delivery"]) in ["buff", "blink", "summon"])
		if damaging and not bool(s["monster_only"]):
			if tags.has("attack"):
				assert_true(float(s["damage_effectiveness"]) > 0.0, "%s effectiveness" % id)
			else:
				assert_false((s["base_damage"] as Dictionary).is_empty(), "%s spell has base damage" % id)
		if damaging and bool(s["monster_only"]):
			assert_false((s["monster_damage"] as Dictionary).is_empty(), "%s monster damage" % id)


func test_monster_skills_rules() -> void:
	for id in MONSTER_IDS:
		var s := SkillDB.get_skill(id)
		assert_true(bool(s["monster_only"]), "%s monster only" % id)
		assert_eq(float(s["mana_cost"]), 0.0, "%s costs 0" % id)
		assert_eq((s["weapon_types"] as Array).size(), 0, "%s any weapon" % id)
	assert_eq(String(SkillDB.get_skill("m_summon")["params"]["enemy_id"]), "skeleton_warrior", "summon id")
	assert_eq(int(SkillDB.get_skill("m_summon")["params"]["count"]), 2, "summon count")
	assert_eq(int(SkillDB.get_skill("m_boss_volley")["params"]["count"]), 7, "volley count")
	assert_true(float(SkillDB.get_skill("m_slam")["params"]["windup"]) > 0.0, "slam windup")
	assert_true(float(SkillDB.get_skill("m_boss_slam")["params"]["windup"]) > 0.0, "boss slam windup")
	assert_true(float(SkillDB.get_skill("m_boss_nova")["params"]["windup"]) > 0.0, "boss nova windup")
	assert_eq(String(SkillDB.get_skill("m_boss_spikes")["params"]["pattern"]), "line", "spikes line")
	assert_near(float(SkillDB.get_skill("m_boss_spikes")["params"]["impact_radius"]), 1.2, 0.001, "spike radius")


func test_player_skill_rules() -> void:
	for id in PLAYER_IDS:
		var s := SkillDB.get_skill(id)
		var tags: PackedStringArray = s["tags"]
		if id != "basic_attack":
			assert_true(float(s["mana_cost"]) > 0.0 or float(s["params"].get("cost_per_tick", 0.0)) > 0.0, "%s costs mana" % id)
		if tags.has("spell") or tags.has("warcry"):
			assert_eq((s["weapon_types"] as Array).size(), 0, "%s spells/warcries accept any weapon" % id)
		assert_true(ResourceLoader.exists("res://assets/icons/skills/%s.png" % id), "%s has an icon" % id)
	assert_eq(int(SkillDB.get_skill("meteor")["unlock_level"]), 14, "meteor unlock")
	assert_eq(String(SkillDB.get_skill("whirlwind")["delivery"]), "channel_aoe", "whirlwind channel")
	assert_true(float(SkillDB.get_skill("whirlwind")["move_mult"]) > 0.0, "whirlwind moves")
	assert_true(bool(SkillDB.get_skill("scatter_shot")["params"]["shotgun"]), "scatter shotgun")
	assert_eq(int(SkillDB.get_skill("power_shot")["params"]["pierce"]), 99, "power shot pierce all")


func test_weapon_compatibility() -> void:
	for wt in StatDefs.MELEE_WEAPON_TYPES:
		assert_true(SkillDB.is_weapon_compatible("cleave", wt), "cleave with %s" % wt)
	for wt in ["bow", "crossbow", "wand"]:
		assert_false(SkillDB.is_weapon_compatible("cleave", wt), "no cleave with %s" % wt)
	assert_true(SkillDB.is_weapon_compatible("power_shot", "bow"), "power shot bow")
	assert_false(SkillDB.is_weapon_compatible("power_shot", "crossbow"), "power shot not crossbow")
	assert_true(SkillDB.is_weapon_compatible("ice_shot", "crossbow"), "ice shot crossbow")
	assert_true(SkillDB.is_weapon_compatible("explosive_bolt", "crossbow"), "bolt crossbow")
	assert_false(SkillDB.is_weapon_compatible("explosive_bolt", "bow"), "bolt not bow")
	for wt in StatDefs.WEAPON_TYPES:
		assert_true(SkillDB.is_weapon_compatible("fireball", wt), "fireball with %s" % wt)
		assert_true(SkillDB.is_weapon_compatible("war_cry", wt), "war cry with %s" % wt)
		assert_true(SkillDB.is_weapon_compatible("basic_attack", wt), "basic attack with %s" % wt)
	assert_false(SkillDB.is_weapon_compatible("nope", "sword"), "unknown")
	assert_eq(SkillDB.get_weapon_requirement_text("ice_shot"), "Requires a Bow or Crossbow", "text")
	assert_eq(SkillDB.get_weapon_requirement_text("cleave"), "Requires a Melee Weapon", "melee text")
	assert_eq(SkillDB.get_weapon_requirement_text("explosive_bolt"), "Requires a Crossbow", "crossbow text")
	assert_eq(SkillDB.get_weapon_requirement_text("fireball"), "", "no requirement")


func test_resolve_basic_attack() -> void:
	var b := SkillDB.get_skill("basic_attack")
	for wt in ["sword", "axe", "mace", "staff", "dagger", "unarmed", "monster"]:
		var r := SkillDB.resolve_for_weapon(b, wt)
		assert_eq(String(r["delivery"]), "melee_arc", "%s melee" % wt)
		assert_true((r["tags"] as PackedStringArray).has("melee"), "%s melee tag" % wt)
		assert_false((r["tags"] as PackedStringArray).has("projectile"), "%s no projectile tag" % wt)
		assert_near(float(r["params"]["angle"]), 80.0, 0.001, "%s angle 80" % wt)
	assert_eq(String(SkillDB.resolve_for_weapon(b, "sword")["anim"]), "attack_slash", "sword anim")
	assert_eq(String(SkillDB.resolve_for_weapon(b, "dagger")["anim"]), "attack_stab", "dagger anim")
	var bow := SkillDB.resolve_for_weapon(b, "bow")
	assert_eq(String(bow["delivery"]), "projectile", "bow projectile")
	assert_eq(String(bow["params"]["model"]), "proj_arrow", "bow arrow")
	assert_near(float(bow["params"]["speed"]), 28.0, 0.001, "bow speed")
	assert_eq(String(bow["anim"]), "shoot_bow", "bow anim")
	assert_true((bow["tags"] as PackedStringArray).has("projectile"), "bow tag")
	var xb := SkillDB.resolve_for_weapon(b, "crossbow")
	assert_eq(String(xb["params"]["model"]), "proj_bolt", "bolt")
	assert_near(float(xb["params"]["speed"]), 34.0, 0.001, "bolt speed")
	assert_eq(int(xb["params"]["pierce"]), 1, "bolt pierce")
	assert_eq(String(xb["anim"]), "shoot_crossbow", "crossbow anim")
	var wand := SkillDB.resolve_for_weapon(b, "wand")
	assert_eq(String(wand["delivery"]), "projectile", "wand projectile")
	assert_true(bool(wand["params"]["orb"]), "wand orb")
	assert_near(float(wand["params"]["speed"]), 22.0, 0.001, "wand speed")
	assert_false((b["tags"] as PackedStringArray).has("melee"), "original untouched")
	var fb := SkillDB.get_skill("fireball")
	assert_true(is_same(SkillDB.resolve_for_weapon(fb, "bow"), fb), "other skills unchanged")


func test_get_resolved_uses_actor_weapon() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("bow"))
	assert_eq(String(SkillDB.get_resolved("basic_attack", c)["delivery"]), "projectile", "bow resolved")
	c.weapon_override = weapon("sword")
	assert_eq(String(SkillDB.get_resolved("basic_attack", c)["delivery"]), "melee_arc", "sword resolved")
	assert_true(SkillDB.get_resolved("nope", c).is_empty(), "unknown")
	assert_eq(String(SkillDB.get_resolved("basic_attack", null)["delivery"]), "weapon_default", "no actor")


func test_tooltip_lines() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0), 5)
	for id in PLAYER_IDS:
		var lines := SkillDB.get_tooltip_lines(id, c)
		assert_true(lines.size() >= 4, "%s lines" % id)
		var first: Dictionary = lines[0]
		assert_eq(String(first["text"]), String(SkillDB.get_skill(id)["name"]), "%s title" % id)
		assert_eq(String(first["size"]), "title", "%s title size" % id)
		for l in lines:
			assert_true(l.has("text") and l.has("color") and l.has("size"), "%s line format" % id)
			assert_true(l["color"] is Color, "%s colour" % id)
		var plain := SkillDB.get_tooltip_lines(id)
		assert_true(plain.size() >= 4, "%s lines without actor" % id)
	var text := _joined(SkillDB.get_tooltip_lines("fireball", c))
	for needle in ["Cost:", "Cast Time:", "Fire Damage:", "Critical Strike Chance:", "Estimated DPS"]:
		assert_true(text.contains(needle), "fireball tooltip has %s" % needle)
	var hs := _joined(SkillDB.get_tooltip_lines("heavy_strike", c))
	for needle in ["Requires a Melee Weapon", "Attack Time:", "Physical Damage:", "Damage Effectiveness"]:
		assert_true(hs.contains(needle), "heavy strike tooltip has %s" % needle)
	var locked := SkillDB.get_tooltip_lines("meteor", c)
	var found := false
	for l in locked:
		if String(l["text"]) == "Requires Level 14":
			found = true
			assert_eq(l["color"], UIStyle.COLOR_BAD, "unmet level in red")
	assert_true(found, "meteor level line")
	var wc := _joined(SkillDB.get_tooltip_lines("war_cry", c))
	assert_true(wc.contains("Cooldown:") and wc.contains("increased Damage"), "war cry buff lines")
	assert_true(SkillDB.get_tooltip_lines("nope", c).is_empty(), "unknown -> []")


func test_attack_skill_parity() -> void:
	# §8.4: single-target throughput of attack skills 1.3-1.8x basic_attack per second.
	var kits := {"sword": weapon("sword", 12.0, 1.45, 5.0), "bow": weapon("bow", 15.0, 1.4, 5.0), "crossbow": weapon("crossbow", 23.0, 1.0, 6.0)}
	for wt in kits:
		var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, kits[wt], 20, [], true)
		var basic := SkillDB.estimate_dps("basic_attack", c)
		assert_true(basic > 0.0, "%s basic dps" % wt)
		for id in PLAYER_IDS:
			var s := SkillDB.get_skill(id)
			if id == "basic_attack" or not (s["tags"] as PackedStringArray).has("attack") or not SkillDB.is_weapon_compatible(id, wt):
				continue
			var ratio := SkillDB.estimate_dps(id, c) / basic
			assert_between(ratio, 1.28, 1.82, "%s with %s ratio" % [id, wt])
		c.queue_free()


func test_spells_comparable_to_attacks() -> void:
	# A level-12 wand user's spells vs a level-12 sword user's attack skills (normal gear).
	var sword := ItemDB.create_item(ItemDB.get_base_for_level("sword", 12), Item.Rarity.NORMAL, 12)
	var wand := ItemDB.create_item(ItemDB.get_base_for_level("wand", 12), Item.Rarity.NORMAL, 12)
	var warrior := make_caster(Actor.Team.PLAYER, Vector3.ZERO, sword.get_weapon_stats(), 12, ClassDefs.get_attribute_mods("warrior"), true)
	var mods := ClassDefs.get_attribute_mods("sorcerer")
	mods.append_array(wand.get_global_mods())
	var sorc := make_caster(Actor.Team.PLAYER, Vector3.ZERO, wand.get_weapon_stats(), 12, mods, true)
	var hs := SkillDB.estimate_dps("heavy_strike", warrior)
	for id in ["fireball", "ice_spear", "chain_lightning", "spark"]:
		var r := SkillDB.estimate_dps(id, sorc) / hs
		assert_between(r, 0.75, 1.4, "%s vs heavy strike" % id)


func test_skill_ranges() -> void:
	var c := make_caster(Actor.Team.PLAYER, Vector3.ZERO, weapon("sword", 10.0, 1.0, 0.0, 2.2))
	assert_near(SkillDB.get_skill_range("basic_attack", c), 2.45, 0.01, "basic reach")
	assert_true(SkillDB.get_skill_range("ground_slam", c) > 6.0, "slam reach")
	assert_near(SkillDB.get_skill_range("fireball", c), 20.0, 0.01, "fireball range")
	assert_near(SkillDB.get_skill_range("teleport", c), 12.0, 0.01, "teleport range")


func _joined(lines: Array) -> String:
	var parts: PackedStringArray = []
	for l in lines:
		parts.append(String(l.get("text", "")))
	return "\n".join(parts)

extends "res://tests/unit/test_kernel_util.gd"
## DamageCalc.build_hit and the derived skill numbers (§6.2, §6.3).

const NO_CRIT := {"force_crit": false}


func test_scaling_stats() -> void:
	var s := DamageCalc.get_scaling_stats("fire", PackedStringArray(["spell", "projectile"]), "")
	assert_eq(s, ["damage", "fire_damage", "elemental_damage", "spell_damage", "projectile_damage"] as Array[String], "doc example")
	var a := DamageCalc.get_scaling_stats("physical", PackedStringArray(["attack", "melee", "area"]), "axe", true)
	assert_eq(a, ["damage", "physical_damage", "attack_damage", "melee_damage", "area_damage", "axe_damage", "two_handed_damage"] as Array[String], "2h axe")
	var b := DamageCalc.get_scaling_stats("cold", PackedStringArray(["attack", "projectile"]), "bow", true)
	assert_has(b, "bow_damage", "bow")
	assert_has(b, "elemental_damage", "cold is elemental")
	var u := DamageCalc.get_scaling_stats("physical", PackedStringArray(["attack", "melee"]), "unarmed")
	assert_false(u.has("unarmed_damage") or u.has("one_handed_damage"), "unarmed: no weapon stats")
	var m := DamageCalc.get_scaling_stats("chaos", PackedStringArray(["attack"]), "monster")
	assert_eq(m, ["damage", "chaos_damage", "attack_damage"] as Array[String], "monster: no weapon stats")
	var sp := DamageCalc.get_scaling_stats("physical", PackedStringArray(["spell"]), "sword")
	assert_false(sp.has("sword_damage"), "weapon stats only for attacks")


func test_attack_base_damage() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0))
	var h := DamageCalc.build_hit(d, attack_skill({"damage_effectiveness": 1.5}), NO_CRIT)
	assert_near(h.get_amount("physical"), 15.0, 0.001, "weapon × effectiveness")
	assert_eq(h.damage.size(), 1, "only physical")
	assert_true(h.can_evade, "attacks can be evaded")
	assert_true(h.can_block, "attacks can be blocked")
	assert_eq(h.source, d, "source")
	assert_eq(h.source_team, Actor.Team.PLAYER, "team")
	assert_eq(h.skill_id, "t_attack", "skill id")
	assert_eq(h.weapon_type, "sword", "weapon type")
	assert_false(h.is_crit, "no crit")


func test_attack_added_damage() -> void:
	var w := weapon(10.0, 1.0, 0.0, "sword", false, {"cold": Vector2(4, 4)})
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("added_fire_attack", "flat", 5, 5), mod("added_lightning_spell", "flat", 100, 100)], w)
	var h := DamageCalc.build_hit(d, attack_skill({"damage_effectiveness": 1.5}), NO_CRIT)
	assert_near(h.get_amount("physical"), 15.0, 0.001, "phys")
	assert_near(h.get_amount("cold"), 6.0, 0.001, "weapon added cold × eff")
	assert_near(h.get_amount("fire"), 7.5, 0.001, "added fire attack × eff")
	assert_eq(h.get_amount("lightning"), 0.0, "spell added damage not on attacks")
	# Ranges roll inside [min, max].
	var w2 := weapon(10.0)
	w2["phys_min"] = 5.0
	w2["phys_max"] = 9.0
	var d2 := dummy(Actor.Team.PLAYER, 100.0, [mod("added_fire_attack", "flat", 1, 3)], w2)
	var r := DamageCalc.get_damage_range(d2, attack_skill())
	assert_eq(r["physical"], Vector2(5, 9), "phys range")
	assert_eq(r["fire"], Vector2(1, 3), "fire range")
	for i in 50:
		var hh := DamageCalc.build_hit(d2, attack_skill(), NO_CRIT)
		assert_between(hh.get_amount("physical"), 5.0, 9.0, "rolled phys")
		assert_between(hh.get_amount("fire"), 1.0, 3.0, "rolled fire")


func test_attack_scaling_one_and_two_handed() -> void:
	var mods := [
		mod("damage", "inc", 10), mod("physical_damage", "inc", 20), mod("attack_damage", "inc", 30),
		mod("melee_damage", "inc", 40), mod("sword_damage", "inc", 50), mod("one_handed_damage", "inc", 60),
		mod("two_handed_damage", "inc", 1000), mod("spell_damage", "inc", 1000), mod("fire_damage", "inc", 1000),
		mod("projectile_damage", "inc", 1000), mod("damage", "more", 20),
	]
	var d := dummy(Actor.Team.PLAYER, 100.0, mods, weapon(10.0))
	var h := DamageCalc.build_hit(d, attack_skill(), NO_CRIT)
	assert_near(h.get_amount("physical"), 10.0 * 3.1 * 1.2, 0.001, "one-handed sword scaling")
	var mods2 := mods.duplicate()
	mods2[5] = mod("one_handed_damage", "inc", 1000)
	mods2[6] = mod("two_handed_damage", "inc", 60)
	var d2 := dummy(Actor.Team.PLAYER, 100.0, mods2, weapon(10.0, 1.0, 0.0, "sword", true))
	var h2 := DamageCalc.build_hit(d2, attack_skill(), NO_CRIT)
	assert_near(h2.get_amount("physical"), 10.0 * 3.1 * 1.2, 0.001, "two-handed scaling")


func test_unarmed() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("one_handed_damage", "inc", 1000)])
	var r := DamageCalc.get_damage_range(d, attack_skill())
	assert_eq(r["physical"], Vector2(2, 5), "unarmed range, no weapon stats")
	assert_near(DamageCalc.get_attack_speed(d), 1.3, 0.001, "unarmed speed")


func test_monster_damage_skill() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [mod("damage", "more", 50), mod("physical_damage", "inc", 100)])
	d.level = 10
	var skill := {"id": "m_test", "tags": ["attack", "melee"], "monster_only": true, "monster_damage": {"physical": 0.6, "fire": 0.4}, "damage_mult": 1.5, "damage_effectiveness": 3.0}
	# avg = monster_damage(10) × 1.5 = 37.5; phys 22.5 × [0.8, 1.2]; fire 15 × [0.8, 1.2]
	var r := DamageCalc.get_damage_range(d, skill)
	var phys: Vector2 = r["physical"]
	var fire: Vector2 = r["fire"]
	assert_near(phys.x, 18.0 * 1.5 * 2.0, 0.001, "phys min (more 50, inc 100)")
	assert_near(phys.y, 27.0 * 1.5 * 2.0, 0.001, "phys max")
	assert_near(fire.x, 12.0 * 1.5, 0.001, "fire min")
	assert_near(fire.y, 18.0 * 1.5, 0.001, "fire max")
	var h := DamageCalc.build_hit(d, skill, NO_CRIT)
	assert_between(h.get_amount("physical"), phys.x, phys.y, "rolled")
	assert_eq(h.source_level, 10, "source level")
	assert_eq(DamageCalc.get_cost(d, skill), 0.0, "monster skills are free")
	# Monster spells use the same path (no evade).
	var spell := {"id": "m_bolt", "tags": ["spell", "projectile", "fire"], "monster_only": true, "monster_damage": {"fire": 1.0}}
	var hs := DamageCalc.build_hit(d, spell, NO_CRIT)
	assert_false(hs.can_evade, "spells can't be evaded")
	assert_true(hs.can_block, "projectiles can be blocked")
	var rs := DamageCalc.get_damage_range(d, spell)
	assert_near((rs["fire"] as Vector2).x, 25.0 * 0.8 * 1.5, 0.001, "monster spell")


func test_spell_damage() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [
		mod("added_fire_spell", "flat", 10, 10), mod("added_fire_attack", "flat", 100, 100),
		mod("spell_damage", "inc", 50), mod("fire_damage", "inc", 25), mod("elemental_damage", "inc", 25),
		mod("attack_damage", "inc", 1000),
	])
	d.level = 11
	var skill := spell_skill({"fire": [10, 20]}, {"damage_effectiveness": 0.5})
	var r := DamageCalc.get_damage_range(d, skill)
	# base × 2.95 = [29.5, 59] + added 10 × 0.5 = [34.5, 64]; × (1 + 100%)
	assert_near((r["fire"] as Vector2).x, 69.0, 0.001, "spell min")
	assert_near((r["fire"] as Vector2).y, 128.0, 0.001, "spell max")
	var h := DamageCalc.build_hit(d, skill, NO_CRIT)
	assert_between(h.get_amount("fire"), 69.0, 128.0, "rolled")
	assert_false(h.can_evade, "spell not evadable")
	assert_false(h.can_block, "non-projectile spell not blockable")
	assert_eq(h.weapon_type, "", "no weapon")


func test_conversion() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("physical_damage", "inc", 100), mod("fire_damage", "inc", 200)], weapon(10.0))
	var h := DamageCalc.build_hit(d, attack_skill({"conversion": {"physical": {"fire": 0.5}}}), NO_CRIT)
	assert_near(h.get_amount("physical"), 5.0 * 2.0, 0.001, "phys part scales as phys")
	assert_near(h.get_amount("fire"), 5.0 * 3.0, 0.001, "converted part scales only as fire")
	var h2 := DamageCalc.build_hit(d, attack_skill({"conversion": {"physical": {"fire": 0.8, "cold": 0.8}}}), NO_CRIT)
	assert_false(h2.damage.has("physical"), "fully converted")
	assert_near(h2.get_amount("fire"), 5.0 * 3.0, 0.001, "normalised fire")
	assert_near(h2.get_amount("cold"), 5.0, 0.001, "normalised cold")
	var full := DamageCalc.build_hit(d, attack_skill({"conversion": {"physical": {"cold": 1.0}}}), NO_CRIT)
	assert_eq(full.dominant_type(), "cold", "ice shot style")
	var base := DamageCalc.get_base_damage_range(d, attack_skill({"conversion": {"physical": {"fire": 0.5}}}))
	assert_eq(base["fire"], Vector2(5, 5), "base range after conversion")


func test_hit_multipliers() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0))
	var h := DamageCalc.build_hit(d, attack_skill({"more_damage": 50.0}), {"force_crit": false, "effectiveness": 0.5, "more": 20.0})
	assert_near(h.get_amount("physical"), 10.0 * 1.5 * 0.5 * 1.2, 0.001, "more_damage × effectiveness × opts.more")
	var d2 := dummy(Actor.Team.PLAYER, 100.0, [mod("damage", "inc", -200)], weapon(10.0))
	assert_eq(DamageCalc.build_hit(d2, attack_skill(), NO_CRIT).get_amount("physical"), 0.0, "never negative")


func test_crit() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("crit_multiplier", "flat", 50)], weapon(10.0))
	var h := DamageCalc.build_hit(d, attack_skill(), {"force_crit": true})
	assert_true(h.is_crit, "forced crit")
	assert_near(h.get_amount("physical"), 20.0, 0.001, "crit × (150 + 50)%")
	assert_near(DamageCalc.get_crit_multiplier(d), 200.0, 0.001, "multiplier")
	var nc := dummy(Actor.Team.PLAYER, 100.0, [mod("no_crit", "flag"), mod("base_crit_chance", "flat", 50)], weapon(10.0, 1.0, 50.0))
	var hn := DamageCalc.build_hit(nc, attack_skill(), {"force_crit": true})
	assert_false(hn.is_crit, "no_crit wins")
	assert_eq(DamageCalc.get_crit_chance(nc, attack_skill()), 0.0, "no_crit chance 0")


func test_crit_chance_formula() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("base_crit_chance", "flat", 2), mod("crit_chance", "inc", 100), mod("crit_chance", "more", 50)], weapon(10.0, 1.0, 5.0))
	assert_near(DamageCalc.get_crit_chance(d, attack_skill()), (5.0 + 2.0) * 2.0 * 1.5, 0.001, "attack uses weapon crit")
	assert_near(DamageCalc.get_crit_chance(d, spell_skill({"fire": [1, 1]}, {"crit_chance": 8.0})), (8.0 + 2.0) * 3.0, 0.001, "spell crit")
	var s := spell_skill({"fire": [1, 1]})
	s.erase("crit_chance")
	assert_near(DamageCalc.get_crit_chance(d, s), 7.0 * 3.0, 0.001, "spell default 5")
	var big := dummy(Actor.Team.PLAYER, 100.0, [mod("base_crit_chance", "flat", 500)], weapon(10.0))
	assert_eq(DamageCalc.get_crit_chance(big, attack_skill()), 95.0, "cap 95")


func test_crit_rate_statistical() -> void:
	seed(1234)
	var d := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0, 1.0, 40.0))
	var crits := 0
	for i in 2000:
		if DamageCalc.build_hit(d, attack_skill()).is_crit:
			crits += 1
	assert_between(crits / 2000.0, 0.36, 0.44, "crit rate ~40%")


func test_pain_attunement() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("pain_attunement", "flag")], weapon(10.0))
	var skill := spell_skill({"cold": [10, 10]})
	assert_near(DamageCalc.build_hit(d, skill, NO_CRIT).get_amount("cold"), 10.0, 0.001, "full life")
	d.life = 35.0
	assert_near(DamageCalc.build_hit(d, skill, NO_CRIT).get_amount("cold"), 13.0, 0.001, "low life ×1.3")
	assert_near(DamageCalc.build_hit(d, attack_skill(), NO_CRIT).get_amount("physical"), 10.0, 0.001, "attacks unaffected")


func test_point_blank() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("point_blank", "flag")], weapon(10.0, 1.0, 0.0, "bow", true))
	var skill := attack_skill({"tags": ["attack", "projectile"]})
	var near := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(1, 0, 0))
	var mid := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(0, 0, 7))
	var far := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(20, 0, 0))
	assert_near(DamageCalc.build_hit(d, skill, {"force_crit": false, "target": near}).get_amount("physical"), 15.0, 0.001, "≤ 2 m ×1.5")
	assert_near(DamageCalc.build_hit(d, skill, {"force_crit": false, "target": mid}).get_amount("physical"), 11.0, 0.001, "7 m ×1.1")
	assert_near(DamageCalc.build_hit(d, skill, {"force_crit": false, "target": far}).get_amount("physical"), 7.0, 0.001, "≥ 12 m ×0.7")
	assert_near(DamageCalc.build_hit(d, skill, {"force_crit": false, "target_pos": Vector3(12, 0, 0), "fire_origin": Vector3(10, 0, 0)}).get_amount("physical"), 15.0, 0.001, "fire origin")
	assert_near(DamageCalc.build_hit(d, skill, NO_CRIT).get_amount("physical"), 10.0, 0.001, "no target: no modifier")
	assert_near(DamageCalc.build_hit(d, attack_skill(), {"force_crit": false, "target": near}).get_amount("physical"), 10.0, 0.001, "melee unaffected")
	var plain := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0, 1.0, 0.0, "bow", true))
	assert_near(DamageCalc.build_hit(plain, skill, {"force_crit": false, "target": far}).get_amount("physical"), 10.0, 0.001, "no keystone")
	assert_near(DamageCalc.point_blank_mult(2.0), 1.5, 0.0001, "pb 2")
	assert_near(DamageCalc.point_blank_mult(12.0), 0.7, 0.0001, "pb 12")


func test_ailment_rolls() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("damage_over_time", "inc", 50), mod("skill_duration", "inc", 50)], weapon(10.0))
	var fire := DamageCalc.build_hit(d, spell_skill({"fire": [20, 20]}, {"ailments": {"ignite": 100}}), NO_CRIT)
	assert_near(float(fire.ailments["ignite"]["dps"]), 0.5 * 20.0 * 1.5, 0.001, "ignite dps")
	assert_near(float(fire.ailments["ignite"]["duration"]), 4.0 * 1.5, 0.001, "ignite duration × duration mult")
	var bleed := DamageCalc.build_hit(d, attack_skill({"ailments": {"bleed": 100}}), NO_CRIT)
	assert_near(float(bleed.ailments["bleed"]["dps"]), 0.5 * 10.0 * 1.5, 0.001, "bleed dps")
	var spell_phys := DamageCalc.build_hit(d, spell_skill({"physical": [10, 10]}, {"ailments": {"bleed": 100}}), NO_CRIT)
	assert_false(spell_phys.ailments.has("bleed"), "bleed needs an attack")
	var poison := DamageCalc.build_hit(d, spell_skill({"physical": [10, 10], "chaos": [10, 10]}, {"ailments": {"poison": 100}}), NO_CRIT)
	assert_near(float(poison.ailments["poison"]["dps"]), 0.2 * 20.0 * 1.5, 0.001, "poison dps")
	assert_near(float(poison.ailments["poison"]["duration"]), 3.0, 0.001, "poison duration")
	var shock := DamageCalc.build_hit(d, spell_skill({"lightning": [10, 10]}, {"ailments": {"shock": 100}}), NO_CRIT)
	assert_near(float(shock.ailments["shock"]["effect"]), 0.2, 0.001, "shock effect")
	assert_near(float(shock.ailments["shock"]["duration"]), 6.0, 0.001, "shock duration")
	var freeze := DamageCalc.build_hit(d, spell_skill({"cold": [10, 10]}, {"ailments": {"freeze": 100}}), NO_CRIT)
	assert_near(float(freeze.ailments["freeze"]["duration"]), 1.2, 0.001, "freeze duration")
	var none := DamageCalc.build_hit(d, spell_skill({"cold": [10, 10]}, {"ailments": {"ignite": 100, "shock": 100}}), NO_CRIT)
	assert_true(none.ailments.is_empty(), "ailments need their damage type")
	var zero := DamageCalc.build_hit(d, spell_skill({"fire": [10, 10]}), NO_CRIT)
	assert_true(zero.ailments.is_empty(), "no chance, no ailment")
	var skip := DamageCalc.build_hit(d, spell_skill({"fire": [10, 10]}, {"ailments": {"ignite": 100}}), {"force_crit": false, "no_ailments": true})
	assert_true(skip.ailments.is_empty(), "no_ailments opt")


func test_ailment_chance_from_stats() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("ignite_chance", "flat", 60), mod("freeze_chance", "flat", 100)], weapon(10.0))
	var skill := spell_skill({"fire": [10, 10], "cold": [10, 10]}, {"ailments": {"ignite": 40}})
	assert_near(DamageCalc.get_ailment_chance(d, skill, "ignite"), 100.0, 0.001, "chance sum")
	var h := DamageCalc.build_hit(d, skill, NO_CRIT)
	assert_true(h.ailments.has("ignite"), "ignite from skill + stat")
	assert_true(h.ailments.has("freeze"), "freeze from stat")
	seed(99)
	var hits := 0
	var d2 := dummy(Actor.Team.PLAYER, 100.0, [mod("shock_chance", "flat", 30)], weapon(10.0))
	for i in 1000:
		if DamageCalc.build_hit(d2, spell_skill({"lightning": [5, 5]}), NO_CRIT).ailments.has("shock"):
			hits += 1
	assert_between(hits / 1000.0, 0.25, 0.35, "shock rate ~30%")


func test_crit_scales_ailments() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0))
	var h := DamageCalc.build_hit(d, spell_skill({"fire": [10, 10]}, {"ailments": {"ignite": 100}}), {"force_crit": true})
	assert_near(float(h.ailments["ignite"]["dps"]), 0.5 * 15.0, 0.001, "ignite from the post-crit hit")


func test_use_time() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("attack_speed", "inc", 25), mod("cast_speed", "inc", 50)], weapon(10.0, 1.0))
	assert_near(DamageCalc.get_attack_speed(d), 1.25, 0.001, "attack speed")
	assert_near(DamageCalc.get_use_time(d, attack_skill({"attack_time_mult": 1.25})), 1.0, 0.001, "attack time")
	assert_near(DamageCalc.get_use_time(d, spell_skill({}, {"cast_time": 0.75})), 0.5, 0.001, "cast time")
	assert_near(DamageCalc.get_use_time(d, {"id": "war_cry", "tags": ["warcry"], "cast_time": 0.6}), 0.6, 0.001, "non-spell ignores cast speed")
	var fast := dummy(Actor.Team.PLAYER, 100.0, [mod("attack_speed", "inc", 10000)], weapon(10.0, 1.0))
	assert_eq(DamageCalc.get_use_time(fast, attack_skill()), 0.1, "minimum 0.1")


func test_cost_cooldown_and_helpers() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [
		mod("mana_cost", "inc", -20), mod("cooldown_recovery", "inc", 100), mod("area_of_effect", "inc", 44),
		mod("additional_projectiles", "flat", 2), mod("pierce", "flat", 1), mod("chain", "flat", 2),
		mod("projectile_speed", "inc", 30), mod("skill_duration", "inc", 50),
	], weapon(10.0))
	d.level = 11
	assert_near(DamageCalc.get_cost(d, {"id": "x", "mana_cost": 10.0}), 10.0 * 1.3 * 0.8, 0.001, "cost")
	assert_eq(DamageCalc.get_cost(d, {"id": "x"}), 0.0, "no cost")
	assert_near(DamageCalc.scale_cost(d, 3.0), 3.0 * 1.3 * 0.8, 0.001, "per-tick cost scaling")
	assert_near(DamageCalc.get_cooldown(d, {"id": "x", "cooldown": 4.0}), 2.0, 0.001, "cooldown recovery")
	assert_eq(DamageCalc.get_cooldown(d, {"id": "x"}), 0.0, "no cooldown")
	assert_near(DamageCalc.get_area_mult(d, {}), 1.2, 0.001, "area sqrt")
	var proj := {"id": "split", "tags": ["attack", "projectile"], "params": {"count": 5, "pierce": 2}}
	assert_eq(DamageCalc.get_projectile_count(d, proj), 7, "projectiles")
	assert_eq(DamageCalc.get_projectile_count(d, {"id": "slam", "tags": ["attack", "melee"]}), 1, "not a projectile skill")
	assert_eq(DamageCalc.get_pierce(d, proj), 3, "pierce")
	assert_eq(DamageCalc.get_chain(d, {"id": "cl", "tags": ["spell", "chain"], "params": {"chain": 4}}), 6, "chain")
	assert_eq(DamageCalc.get_chain(d, proj), 0, "non-chaining skill")
	assert_near(DamageCalc.get_projectile_speed_mult(d, proj), 1.3, 0.001, "proj speed")
	assert_near(DamageCalc.get_duration_mult(d, proj), 1.5, 0.001, "duration")
	var shrink := dummy(Actor.Team.PLAYER, 100.0, [mod("area_of_effect", "inc", -500)])
	assert_near(DamageCalc.get_area_mult(shrink, {}), sqrt(0.1), 0.001, "area floor")


func test_estimate_dps() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0, 2.0, 0.0))
	assert_near(DamageCalc.estimate_dps(d, attack_skill()), 20.0, 0.001, "10 dmg × 2/s")
	var c := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0, 1.0, 50.0))
	assert_near(DamageCalc.estimate_dps(c, attack_skill()), 12.5, 0.001, "crit factor 1.25")
	assert_near(DamageCalc.estimate_dps(d, attack_skill({"cooldown": 2.0})), 5.0, 0.001, "cooldown bound")
	var seq := attack_skill({"tags": ["attack", "projectile"], "params": {"repeat": 5}})
	assert_near(DamageCalc.estimate_dps(d, seq), 100.0, 0.001, "sequence repeats")
	var boom := attack_skill({"tags": ["attack", "projectile"], "params": {"explode_radius": 2.0, "explode_effectiveness": 0.6}})
	assert_near(DamageCalc.estimate_dps(d, boom), 12.0, 0.001, "explosion effectiveness")
	assert_eq(DamageCalc.estimate_dps(d, {"id": "war_cry", "tags": ["warcry"]}), 0.0, "no damage")
	assert_near(DamageCalc.get_average_hit(d, attack_skill()), 10.0, 0.001, "average hit")


func test_null_attacker() -> void:
	var h := DamageCalc.build_hit(null, spell_skill({"fire": [10, 10]}), NO_CRIT)
	assert_near(h.get_amount("fire"), 10.0, 0.001, "level 1 spell")
	assert_eq(h.source, null, "no source")
	assert_eq(h.source_level, 1, "level 1")
	var a := DamageCalc.build_hit(null, attack_skill(), NO_CRIT)
	assert_between(a.get_amount("physical"), 2.0, 5.0, "unarmed")
	assert_near(DamageCalc.get_use_time(null, attack_skill()), 1.0 / 1.3, 0.001, "unarmed speed")


func test_use_id_and_origin() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [], weapon(10.0), Vector3(3, 0, 4))
	var id := DamageCalc.next_use_id()
	assert_true(id > 0, "positive id")
	assert_ne(DamageCalc.next_use_id(), id, "unique ids")
	var h := DamageCalc.build_hit(d, attack_skill(), {"use_id": id, "knockback": 4.0})
	assert_eq(h.use_id, id, "use id")
	assert_eq(h.origin, Vector3(3, 0, 4), "origin = attacker")
	assert_eq(h.knockback, 4.0, "knockback")
	var h2 := DamageCalc.build_hit(d, attack_skill(), {"origin": Vector3(9, 0, 9)})
	assert_eq(h2.origin, Vector3(9, 0, 9), "origin opt")
	var copy := h.duplicate_hit()
	assert_eq(copy.use_id, id, "duplicate keeps use id")
	var half := h.scaled(0.5)
	assert_near(half.total(), h.total() * 0.5, 0.001, "scaled")


func test_to_range() -> void:
	assert_eq(DamageCalc.to_range([3, 7]), Vector2(3, 7), "array")
	assert_eq(DamageCalc.to_range(Vector2(1, 2)), Vector2(1, 2), "vector")
	assert_eq(DamageCalc.to_range({"min": 2, "max": 4}), Vector2(2, 4), "dict")
	assert_eq(DamageCalc.to_range(5), Vector2(5, 5), "number")
	assert_eq(DamageCalc.to_range(null), Vector2.ZERO, "null")

extends "res://tests/unit/test_kernel_util.gd"
## Actor.recalculate_stats(): attributes, attribute bonuses, pools, regen, defences, resistances,
## movement speed, pool ratios (§5).


func test_fresh_actor_is_full() -> void:
	var d := dummy(Actor.Team.ENEMY, 500.0, [mod("max_energy_shield", "flat", 40)])
	assert_eq(d.max_life, 500.0, "max life")
	assert_eq(d.life, 500.0, "full life")
	assert_eq(d.mana, d.max_mana, "full mana")
	assert_eq(d.es, 40.0, "full es")
	assert_true(d.is_in_group("actors"), "group actors")
	assert_true(d.is_in_group("team_1"), "team group")


func test_actor_ready_recalculates() -> void:
	# A bare Actor (no subclass recalc) must still have valid pools after _ready.
	var a := Actor.new()
	add_child(a)
	assert_eq(a.max_life, 1.0, "min life 1")
	assert_eq(a.life, 1.0, "full")
	assert_eq(a.base_move_speed, 5.0, "default speed")
	assert_eq(a.motion_mode, CharacterBody3D.MOTION_MODE_FLOATING, "floating")


func test_attributes_and_bonuses() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [
		mod("strength", "flat", 20), mod("dexterity", "flat", 30), mod("intelligence", "flat", 40),
		mod("all_attributes", "flat", 10), mod("strength", "inc", 50),
	])
	# str = (20 + 10) * 1.5 = 45; dex = 40; int = 50
	assert_near(d.get_attribute("strength"), 45.0, 0.001, "str")
	assert_near(d.get_attribute("dexterity"), 40.0, 0.001, "dex")
	assert_near(d.get_attribute("intelligence"), 50.0, 0.001, "int")
	assert_near(float(d.attributes["strength"]), 45.0, 0.001, "attributes dict")
	# Strength: +1 life per 2, +1% melee per 5.
	assert_near(d.max_life, 100.0 + 22.0, 0.001, "life from str")
	assert_near(d.stats.inc("melee_damage"), 9.0, 0.001, "melee from str")
	# Dexterity: +1% evasion per 5, +1% attack speed per 10, +1% projectile damage per 10.
	assert_near(d.stats.inc("evasion"), 8.0, 0.001, "evasion from dex")
	assert_near(d.stats.inc("attack_speed"), 4.0, 0.001, "aspd from dex")
	assert_near(d.stats.inc("projectile_damage"), 4.0, 0.001, "proj from dex")
	# Intelligence: +1 mana per 2, +1% ES per 5, +1% spell damage per 10.
	assert_near(d.max_mana, 100.0 + 25.0, 0.001, "mana from int")
	assert_near(d.stats.inc("max_energy_shield"), 10.0, 0.001, "es from int")
	assert_near(d.stats.inc("spell_damage"), 5.0, 0.001, "spell from int")


func test_attribute_inc_all_attributes() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [mod("strength", "flat", 10), mod("all_attributes", "inc", 20), mod("strength", "inc", 30)])
	# (10 + 0) * (1 + (30 + 20)/100) = 15
	assert_near(d.get_attribute("strength"), 15.0, 0.001, "inc stacking")
	assert_near(d.get_attribute("dexterity"), 0.0, 0.001, "no dex")


func test_pools_regen() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [
		mod("max_life", "inc", 50), mod("life_regen", "flat", 5), mod("life_regen_percent", "flat", 2),
		mod("max_mana", "flat", 25), mod("mana_regen", "inc", 50),
		mod("max_energy_shield", "flat", 100), mod("max_energy_shield", "inc", 20), mod("energy_shield_recharge", "inc", 100),
	])
	assert_near(d.max_life, 150.0, 0.001, "life inc")
	assert_near(d.life_regen, 5.0 + 150.0 * 0.02, 0.001, "life regen")
	assert_near(d.max_mana, 125.0, 0.001, "mana")
	assert_near(d.mana_regen, (2.0 + 0.03 * 125.0) * 1.5, 0.001, "mana regen formula")
	assert_near(d.max_es, 120.0, 0.001, "es")
	assert_near(d.es_recharge_rate, 0.25 * 120.0 * 2.0, 0.001, "es recharge rate")
	# Regen ticks.
	d.life = 50.0
	d.mana = 0.0
	tick(d, 1.0)
	assert_near(d.life, 58.0, 0.01, "regenerated life")
	assert_near(d.mana, 8.625, 0.01, "regenerated mana")
	tick(d, 100.0, 0.5)
	assert_eq(d.life, d.max_life, "life capped")
	assert_eq(d.mana, d.max_mana, "mana capped")


func test_es_recharge_delay() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [mod("max_energy_shield", "flat", 100)])
	d.take_damage(60.0, "fire")
	assert_near(d.es, 40.0, 0.001, "es absorbed")
	assert_eq(d.life, 100.0, "life untouched")
	assert_eq(d.time_since_damaged, 0.0, "timer reset")
	tick(d, 1.9, 0.1)
	assert_near(d.es, 40.0, 0.001, "no recharge before 2 s")
	tick(d, 0.1, 0.1)
	tick(d, 1.0, 0.1)
	# Recharge starts at 2.0 s: at 25 ES/s, ~1 s of recharge.
	assert_between(d.es, 60.0, 70.0, "recharging")
	tick(d, 10.0, 0.5)
	assert_eq(d.es, 100.0, "full es")


func test_no_mana_regen_without_mana_and_blood_magic() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("blood_magic", "flag"), mod("mana_regen", "inc", 100)])
	assert_eq(d.max_mana, 0.0, "blood magic: no mana")
	assert_eq(d.mana_regen, 0.0, "no mana regen")
	assert_eq(d.mana, 0.0, "mana 0")


func test_armour_evasion_iron_reflexes() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [mod("armour", "flat", 100), mod("armour", "more", 20), mod("evasion", "flat", 200), mod("evasion", "inc", 50)])
	assert_near(d.armour, 120.0, 0.001, "armour")
	assert_near(d.evasion, 300.0, 0.001, "evasion")
	d.extra_mods.append(mod("iron_reflexes", "flag"))
	d.recalculate_stats()
	# armour = compute(armour) + evasion * more(armour) = 120 + 300 * 1.2
	assert_near(d.armour, 120.0 + 300.0 * 1.2, 0.001, "iron reflexes armour")
	assert_eq(d.evasion, 0.0, "iron reflexes evasion")


func test_block_and_resistances() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [
		mod("block_chance", "flat", 80),
		mod("fire_resistance", "flat", 50), mod("elemental_resistance", "flat", 40),
		mod("cold_resistance", "flat", -200),
		mod("chaos_resistance", "flat", 30),
		mod("physical_damage_reduction", "flat", 90),
	])
	assert_eq(d.block_chance, 75.0, "block cap")
	assert_eq(d.resistances["fire"], 75.0, "fire capped")
	assert_eq(d.resistances_uncapped["fire"], 90.0, "fire uncapped")
	assert_eq(d.resistances["lightning"], 40.0, "lightning from elemental")
	assert_eq(d.resistances["cold"], -100.0, "cold floor")
	assert_eq(d.resistances["chaos"], 30.0, "chaos without elemental")
	assert_eq(d.resistances["physical"], 75.0, "phys reduction cap")
	var d2 := dummy(Actor.Team.ENEMY, 100.0, [mod("physical_damage_reduction", "flat", -20)])
	assert_eq(d2.resistances["physical"], 0.0, "phys reduction floor 0")


func test_move_speed() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [mod("movement_speed", "inc", 20), mod("movement_speed", "more", 10)])
	d.base_move_speed = 5.0
	assert_near(d.get_move_speed(), 5.0 * 1.2 * 1.1, 0.001, "mods")
	d.apply_ailment("chill", {"effect": 0.3, "duration": 2.0})
	assert_near(d.get_move_speed(), 5.0 * 1.2 * 1.1 * 0.7, 0.001, "chilled")
	assert_near(d.get_action_speed_mult(), 0.7, 0.001, "chill action speed")
	d.apply_ailment("freeze", {"duration": 1.0})
	assert_eq(d.get_move_speed(), 0.0, "frozen")
	assert_false(d.can_act(), "frozen can't act")


func test_ratio_preserved_on_recalc() -> void:
	var d := dummy(Actor.Team.ENEMY, 100.0, [mod("max_energy_shield", "flat", 50)])
	d.life = 50.0
	d.mana = 25.0
	d.es = 10.0
	d.extra_mods.append(mod("max_life", "flat", 100))
	d.extra_mods.append(mod("max_mana", "flat", 100))
	d.extra_mods.append(mod("max_energy_shield", "flat", 50))
	d.recalculate_stats()
	assert_near(d.max_life, 200.0, 0.001, "new max life")
	assert_near(d.life, 100.0, 0.001, "life ratio kept")
	assert_near(d.mana, 50.0, 0.001, "mana ratio kept")
	assert_near(d.es, 20.0, 0.001, "es ratio kept")
	var r := d.get_pool_ratios()
	assert_near(float(r["life"]), 0.5, 0.001, "ratios")
	d.set_pool_ratios({"life": 0.25, "mana": 1.0, "es": 0.0})
	assert_near(d.life, 50.0, 0.001, "set life ratio")
	assert_near(d.mana, d.max_mana, 0.001, "set mana ratio")
	assert_eq(d.es, 0.0, "set es ratio")
	d.set_pool_ratios({"life": 0.0})
	assert_eq(d.life, 1.0, "life at least 1")


func test_stats_recalculated_signal_and_low_life() -> void:
	var d := dummy()
	var count := [0]
	d.stats_recalculated.connect(func() -> void: count[0] += 1)
	d.recalculate_stats()
	assert_eq(count[0], 1, "signal")
	d.life = d.max_life * 0.35
	assert_true(d.is_low_life(), "35% is low life")
	d.life = d.max_life * 0.36
	assert_false(d.is_low_life(), "36% is not")
	d.refill_pools()
	assert_eq(d.life, d.max_life, "refill")


func test_face_towards() -> void:
	var d := dummy()
	d.face_towards(Vector3(1, 0, 0))
	assert_near(d.rotation.y, PI / 2.0, 0.001, "face +X")
	assert_true(d.get_forward().distance_to(Vector3(1, 0, 0)) < 0.01, "forward +X")


func test_pool_from_zero_does_not_refill_live_actor() -> void:
	# Before the actor is live (spawn / setup / starting gear) a pool growing from 0 starts full.
	var d := dummy(Actor.Team.PLAYER, 1000.0)
	assert_eq(d.max_es, 0.0, "no es yet")
	var es_mod := mod("max_energy_shield", "flat", 200)
	d.extra_mods.append(es_mod)
	d.recalculate_stats()
	assert_eq(d.es, 200.0, "setup before going live: full es")
	# Live actor: removing and re-adding the only ES source must not refill ES.
	d.take_damage(190.0, "fire")
	assert_near(d.es, 10.0, 0.001, "es 10/200")
	tick(d, 0.5, 0.1)
	d.extra_mods.erase(es_mod)
	d.recalculate_stats()
	assert_eq(d.max_es, 0.0, "es source removed")
	assert_eq(d.es, 0.0, "es 0/0")
	d.extra_mods.append(es_mod)
	d.recalculate_stats()
	assert_eq(d.max_es, 200.0, "es source back")
	assert_eq(d.es, 0.0, "no instant refill")
	assert_near(d.time_since_damaged, 0.5, 0.001, "recharge delay not reset")
	tick(d, 1.4, 0.1)
	assert_eq(d.es, 0.0, "no recharge before 2 s after the hit")
	tick(d, 1.0, 0.1)
	assert_between(d.es, 20.0, 60.0, "normal recharge afterwards")
	tick(d, 10.0, 0.5)
	assert_eq(d.es, 200.0, "recharged to full")
	# Blood magic toggled off on a live actor: mana starts at 0 and regenerates.
	var bm := mod("blood_magic", "flag")
	d.extra_mods.append(bm)
	d.recalculate_stats()
	assert_eq(d.max_mana, 0.0, "blood magic")
	d.extra_mods.erase(bm)
	d.recalculate_stats()
	assert_true(d.max_mana > 0.0, "mana back")
	assert_eq(d.mana, 0.0, "mana not refilled")
	tick(d, 1.0, 0.1)
	assert_near(d.mana, d.mana_regen * 1.0, 0.01, "mana regenerates")
	d.refill_pools()
	assert_eq(d.es, d.max_es, "explicit refill still works")
	assert_eq(d.mana, d.max_mana, "explicit mana refill")

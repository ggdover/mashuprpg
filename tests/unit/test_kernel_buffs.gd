extends "res://tests/unit/test_kernel_util.gd"
## Buffs, heals, costs (Blood Magic), and a tick performance smoke test (§6.6).


func test_buff_add_expire_refresh() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0)
	var changed := [0]
	d.buffs_changed.connect(func() -> void: changed[0] += 1)
	d.life = 50.0
	d.add_buff("war_cry", {"name": "War Cry", "mods": [mod("max_life", "inc", 100), mod("damage", "inc", 30)], "duration": 6.0, "icon": "war_cry"})
	assert_true(d.has_buff("war_cry"), "has buff")
	assert_eq(changed[0], 1, "buffs_changed")
	assert_near(d.max_life, 200.0, 0.001, "buff mods in stats")
	assert_near(d.life, 100.0, 0.001, "ratio kept")
	assert_near(d.stats.inc("damage"), 30.0, 0.001, "damage inc")
	var b: Dictionary = d.buffs["war_cry"]
	assert_eq(b["name"], "War Cry", "name")
	assert_eq(b["icon"], "war_cry", "icon")
	assert_near(float(b["time_left"]), 6.0, 0.001, "time left")
	tick(d, 3.0, 0.5)
	assert_near(float(d.buffs["war_cry"]["time_left"]), 3.0, 0.001, "counting down")
	d.add_buff("war_cry", {"name": "War Cry", "mods": [mod("damage", "inc", 40)], "duration": 6.0, "icon": "war_cry"})
	assert_near(float(d.buffs["war_cry"]["time_left"]), 6.0, 0.001, "refreshed")
	assert_near(d.stats.inc("damage"), 40.0, 0.001, "mods replaced, not stacked")
	assert_near(d.max_life, 100.0, 0.001, "old mods gone")
	tick(d, 6.1, 0.5)
	assert_false(d.has_buff("war_cry"), "expired")
	assert_eq(d.stats.inc("damage"), 0.0, "mods removed")
	assert_eq(changed[0], 3, "changed on add, refresh, expire")


func test_permanent_and_remove() -> void:
	var d := dummy()
	d.add_buff("aura", {"name": "Aura", "mods": [mod("fire_resistance", "flat", 30)], "duration": 0.0, "icon": ""})
	tick(d, 100.0, 1.0)
	assert_true(d.has_buff("aura"), "permanent")
	assert_eq(d.resistances["fire"], 30.0, "buff resist")
	d.remove_buff("aura")
	assert_false(d.has_buff("aura"), "removed")
	assert_eq(d.resistances["fire"], 0.0, "resist gone")
	d.remove_buff("nothing")


func test_buffs_survive_external_recalc() -> void:
	var d := dummy()
	d.add_buff("b", {"name": "B", "mods": [mod("armour", "flat", 50)], "duration": 5.0, "icon": ""})
	d.extra_mods.append(mod("armour", "flat", 25))
	d.recalculate_stats()
	assert_near(d.armour, 75.0, 0.001, "gear + buff")


func test_heal_and_numbers() -> void:
	capture_numbers()
	var d := dummy(Actor.Team.PLAYER, 1000.0)
	d.life = 500.0
	assert_near(d.heal(100.0), 100.0, 0.001, "healed")
	assert_near(d.heal(1000.0), 400.0, 0.001, "capped")
	assert_eq(d.heal(10.0), 0.0, "full")
	assert_eq(numbers.size(), 0, "batched")
	tick(d, 0.5, 0.05)
	assert_eq(numbers_of("heal").size(), 1, "one heal number")
	assert_near(float(numbers_of("heal")[0]["amount"]), 500.0, 0.001, "summed heal")
	numbers.clear()
	d.life = 900.0
	d.heal(5.0)
	tick(d, 0.6, 0.05)
	assert_eq(numbers_of("heal").size(), 0, "insignificant heal: no number")
	d.mana = 0.0
	assert_near(d.restore_mana(50.0), 50.0, 0.001, "mana restored")
	tick(d, 0.6, 0.05)
	assert_eq(numbers_of("mana").size(), 1, "mana number")
	d.die(null)
	assert_eq(d.heal(100.0), 0.0, "no heal when dead")


func test_costs_mana() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0)
	d.mana = 10.0
	assert_true(d.can_pay_cost(10.0), "exact")
	assert_false(d.can_pay_cost(10.5), "too much")
	assert_true(d.pay_cost(4.0), "paid")
	assert_near(d.mana, 6.0, 0.001, "mana spent")
	assert_false(d.pay_cost(7.0), "can't pay")
	assert_near(d.mana, 6.0, 0.001, "unchanged")
	assert_true(d.pay_cost(0.0), "free")


func test_costs_blood_magic() -> void:
	var d := dummy(Actor.Team.PLAYER, 100.0, [mod("blood_magic", "flag")])
	assert_eq(d.max_mana, 0.0, "no mana")
	assert_true(d.can_pay_cost(99.0), "life stays at 1")
	assert_false(d.can_pay_cost(99.5), "would drop below 1")
	assert_true(d.pay_cost(30.0), "paid with life")
	assert_near(d.life, 70.0, 0.001, "life spent")
	assert_false(d.pay_cost(70.0), "can't die from costs")
	assert_near(d.life, 70.0, 0.001, "unchanged")


func test_enemies_never_pay() -> void:
	var e := dummy(Actor.Team.ENEMY, 100.0)
	e.mana = 0.0
	assert_true(e.can_pay_cost(50.0), "enemy can always pay")
	assert_true(e.pay_cost(50.0), "enemy pays nothing")
	assert_eq(e.mana, 0.0, "no mana used")


func test_tick_performance_70_actors() -> void:
	var actors: Array = []
	for i in 70:
		var d := dummy(Actor.Team.ENEMY, 1e7, [mod("life_regen", "flat", 1), mod("max_energy_shield", "flat", 50)])
		d.apply_ailment("ignite", {"dps": 10.0, "duration": 100.0})
		d.apply_ailment("poison", {"dps": 5.0, "duration": 100.0})
		d.apply_ailment("poison", {"dps": 5.0, "duration": 100.0})
		d.apply_ailment("chill", {"effect": 0.2, "duration": 100.0})
		d.add_buff("b", {"name": "B", "mods": [], "duration": 100.0, "icon": ""})
		actors.append(d)
	var start := Time.get_ticks_usec()
	for frame in 60:
		for d in actors:
			(d as Actor)._tick_actor(1.0 / 60.0)
	var per_frame_ms := (Time.get_ticks_usec() - start) / 1000.0 / 60.0
	print("    [perf] 70 actors with 4 ailments + buff: %.3f ms per frame" % per_frame_ms)
	assert_true(per_frame_ms < 3.0, "tick budget (%.3f ms)" % per_frame_ms)

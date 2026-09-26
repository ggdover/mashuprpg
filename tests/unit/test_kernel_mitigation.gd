extends "res://tests/unit/test_kernel_util.gd"
## Actor.take_hit (§6.5): evade, block, armour, resistances, damage taken, shock, MoM, ES,
## floating numbers, leech / life on hit budget, death and kill callbacks.


func test_plain_hit_and_numbers() -> void:
	capture_numbers()
	var t := dummy(Actor.Team.ENEMY, 1000.0)
	var got := [0.0, false, null]
	t.damaged.connect(func(amount: float, crit: bool, src: Node) -> void:
		got[0] = amount
		got[1] = crit
		got[2] = src)
	var src := dummy(Actor.Team.PLAYER, 100.0)
	var h := make_hit({"physical": 60.0, "fire": 40.0}, ["spell"], src)
	h.is_crit = true
	var dealt := t.take_hit(h)
	assert_near(dealt, 100.0, 0.001, "dealt")
	assert_near(t.life, 900.0, 0.001, "life")
	assert_near(float(got[0]), 100.0, 0.001, "damaged amount")
	assert_true(got[1], "damaged crit")
	assert_eq(got[2], src, "damaged source")
	assert_eq(numbers.size(), 1, "one number")
	assert_eq(numbers[0]["kind"], "physical", "dominant type")
	assert_true(numbers[0]["crit"], "crit number")
	assert_near(float(numbers[0]["amount"]), 100.0, 0.001, "number amount")


func test_player_hurt_kind() -> void:
	capture_numbers()
	var p := dummy(Actor.Team.PLAYER, 1000.0)
	p.take_hit(make_hit({"fire": 10.0}))
	assert_eq(numbers[0]["kind"], "player_hurt", "player hurt kind")


func test_armour_and_physical_reduction() -> void:
	var t := dummy(Actor.Team.ENEMY, 10000.0, [mod("armour", "flat", 1000), mod("physical_damage_reduction", "flat", 20)])
	# reduction = 1000 / (1000 + 10 × 100) = 0.5; then × 0.8
	assert_near(t.take_hit(make_hit({"physical": 100.0})), 40.0, 0.001, "armour + phys reduction")
	# Bigger hits are reduced less: 1000 / (1000 + 10000) ≈ 0.0909
	assert_near(t.take_hit(make_hit({"physical": 1000.0})), 1000.0 * (1.0 - 1000.0 / 11000.0) * 0.8, 0.01, "big hit")
	assert_near(DamageCalc.armour_reduction(1e9, 1.0), 0.9, 0.0001, "cap 90%")
	assert_eq(DamageCalc.armour_reduction(0.0, 100.0), 0.0, "no armour")
	# Armour doesn't touch elemental damage.
	assert_near(t.take_hit(make_hit({"fire": 100.0})), 100.0, 0.001, "armour only vs physical")


func test_resistances() -> void:
	var t := dummy(Actor.Team.ENEMY, 10000.0, [mod("fire_resistance", "flat", 50), mod("cold_resistance", "flat", -50), mod("chaos_resistance", "flat", 90)])
	assert_near(t.take_hit(make_hit({"fire": 100.0})), 50.0, 0.001, "fire 50%")
	assert_near(t.take_hit(make_hit({"cold": 100.0})), 150.0, 0.001, "negative cold res")
	assert_near(t.take_hit(make_hit({"chaos": 100.0})), 25.0, 0.001, "chaos capped 75")
	assert_near(t.take_hit(make_hit({"lightning": 100.0})), 100.0, 0.001, "no res")
	var m := DamageCalc.mitigate(t, make_hit({"fire": 100.0, "physical": 50.0}))
	assert_near(float(m["total"]), 100.0, 0.001, "preview total")
	assert_near(float(m["by_type"]["fire"]), 50.0, 0.001, "preview by type")
	assert_near(t.life, 10000.0 - 325.0, 0.001, "preview has no side effects")


func test_damage_taken_and_shock() -> void:
	var t := dummy(Actor.Team.ENEMY, 10000.0, [mod("damage_taken", "inc", 20), mod("damage_taken", "more", 10)])
	assert_near(t.take_hit(make_hit({"fire": 100.0})), 132.0, 0.001, "damage taken")
	t.apply_ailment("shock", {"effect": 0.2, "duration": 4.0})
	assert_near(t.take_hit(make_hit({"fire": 100.0})), 132.0 * 1.2, 0.001, "shocked hit")
	assert_near(t.take_damage(100.0, "fire", true), 132.0 * 1.2, 0.001, "shocked dot")
	assert_near(DamageCalc.damage_taken_mult(t), 1.32 * 1.2, 0.001, "mult helper")


func test_es_before_life() -> void:
	var t := dummy(Actor.Team.ENEMY, 100.0, [mod("max_energy_shield", "flat", 50)])
	tick(t, 0.5)
	t.take_hit(make_hit({"fire": 30.0}))
	assert_near(t.es, 20.0, 0.001, "es absorbs")
	assert_near(t.life, 100.0, 0.001, "life intact")
	assert_eq(t.time_since_damaged, 0.0, "recharge delay reset")
	t.take_hit(make_hit({"fire": 30.0}))
	assert_eq(t.es, 0.0, "es empty")
	assert_near(t.life, 90.0, 0.001, "overflow to life")


func test_mind_over_matter() -> void:
	var t := dummy(Actor.Team.PLAYER, 1000.0, [mod("mind_over_matter", "flag"), mod("max_energy_shield", "flat", 20)])
	t.base_mana = 100.0
	t.recalculate_stats()
	t.refill_pools()
	t.take_hit(make_hit({"physical": 100.0}))
	assert_near(t.mana, 70.0, 0.001, "30% from mana")
	assert_near(t.es, 0.0, 0.001, "then ES")
	assert_near(t.life, 950.0, 0.001, "then life")
	t.mana = 10.0
	t.take_hit(make_hit({"physical": 100.0}))
	assert_near(t.mana, 0.0, 0.001, "as much mana as available")
	assert_near(t.life, 860.0, 0.001, "rest from life")


func test_invulnerable_god_dead() -> void:
	var t := dummy(Actor.Team.PLAYER, 100.0)
	t.invulnerable_time = 0.3
	assert_eq(t.take_hit(make_hit({"physical": 50.0})), 0.0, "invulnerable")
	assert_eq(t.take_damage(50.0, "fire"), 0.0, "invulnerable vs environment")
	assert_true(t.take_damage(5.0, "fire", true) > 0.0, "DoTs still tick through i-frames")
	tick(t, 0.31)
	assert_eq(t.invulnerable_time, 0.0, "counts down")
	t.god_mode = true
	assert_eq(t.take_hit(make_hit({"physical": 50.0})), 0.0, "god mode")
	assert_eq(t.take_damage(50.0, "fire", true), 0.0, "god mode dot")
	t.god_mode = false
	t.die(null)
	assert_eq(t.take_hit(make_hit({"physical": 50.0})), 0.0, "dead")


func test_evade_formula_and_rolls() -> void:
	var t := dummy(Actor.Team.PLAYER, 10000.0, [mod("evasion", "flat", 400), mod("evade_chance", "flat", 10)])
	# 100 × 400 / (400 + 200 + 40 × 5) + 10 = 60
	assert_near(DamageCalc.evade_chance(t, 5), 60.0, 0.001, "evade formula")
	var capped := dummy(Actor.Team.PLAYER, 10000.0, [mod("evade_chance", "flat", 1000)])
	assert_eq(DamageCalc.evade_chance(capped, 1), 75.0, "cap 75")
	seed(7)
	capture_numbers()
	var evaded := 0
	for i in 1000:
		if capped.take_hit(make_hit({"physical": 1.0}, ["attack"])) == 0.0:
			evaded += 1
	assert_between(evaded / 1000.0, 0.70, 0.80, "evade rate ~75%")
	assert_eq(numbers_of("evade").size(), evaded, "evade numbers")
	assert_eq(float(numbers_of("evade")[0]["amount"]), 0.0, "evade amount 0")
	var spells_evaded := 0
	for i in 200:
		if capped.take_hit(make_hit({"fire": 1.0}, ["spell"])) == 0.0:
			spells_evaded += 1
	assert_eq(spells_evaded, 0, "spells are never evaded")
	var unwavering := dummy(Actor.Team.PLAYER, 10000.0, [mod("evade_chance", "flat", 1000), mod("cannot_evade", "flag")])
	assert_eq(DamageCalc.evade_chance(unwavering, 1), 0.0, "cannot_evade chance")
	for i in 100:
		assert_true(unwavering.take_hit(make_hit({"physical": 1.0}, ["attack"])) > 0.0, "cannot evade")


func test_evade_uses_source_level() -> void:
	var t := dummy(Actor.Team.PLAYER, 10000.0, [mod("evasion", "flat", 400)])
	var low := DamageCalc.evade_chance(t, 1)
	var high := DamageCalc.evade_chance(t, 50)
	assert_true(low > high, "higher level attackers are evaded less")
	assert_near(high, 100.0 * 400.0 / (400.0 + 200.0 + 2000.0), 0.001, "level 50")


func test_block() -> void:
	seed(11)
	capture_numbers()
	var t := dummy(Actor.Team.PLAYER, 10000.0, [mod("block_chance", "flat", 50)])
	var blocked := 0
	for i in 1000:
		if t.take_hit(make_hit({"physical": 1.0}, ["attack", "melee"])) == 0.0:
			blocked += 1
	assert_between(blocked / 1000.0, 0.45, 0.55, "block ~50%")
	assert_eq(numbers_of("block").size(), blocked, "block numbers")
	var proj := 0
	for i in 400:
		if t.take_hit(make_hit({"fire": 1.0}, ["spell", "projectile"])) == 0.0:
			proj += 1
	assert_between(proj / 400.0, 0.4, 0.6, "projectile spells can be blocked")
	for i in 100:
		assert_true(t.take_hit(make_hit({"fire": 1.0}, ["spell", "area"])) > 0.0, "area spells can't be blocked")


func test_death_and_kill_callbacks() -> void:
	var killer := dummy(Actor.Team.PLAYER, 100.0, [mod("life_on_kill", "flat", 7), mod("mana_on_kill", "flat", 5)])
	killer.life = 50.0
	killer.mana = 10.0
	var t := dummy(Actor.Team.ENEMY, 100.0)
	t.collision_layer = 4
	t.apply_ailment("ignite", {"dps": 5.0, "duration": 4.0})
	var died := [null, null]
	t.died.connect(func(a: Actor, k: Node) -> void:
		died[0] = a
		died[1] = k)
	watch_ailments(t)
	var dealt := t.take_hit(make_hit({"physical": 150.0}, ["spell"], killer))
	assert_near(dealt, 150.0, 0.001, "overkill dealt")
	assert_true(t.dead, "dead")
	assert_eq(t.life, 0.0, "life 0")
	assert_eq(t.collision_layer, 0, "collision cleared")
	assert_eq(died[0], t, "died actor")
	assert_eq(died[1], killer, "died killer")
	assert_near(killer.life, 57.0, 0.001, "life on kill")
	assert_near(killer.mana, 15.0, 0.001, "mana on kill")
	assert_true(t.ailments.is_empty(), "ailments cleared")
	assert_has(ailment_events, "ignite:false", "ailment off emitted")
	assert_false(t.can_act(), "dead can't act")
	assert_eq(t.get_move_speed(), 0.0, "dead doesn't move")
	t.die(killer)
	assert_near(killer.life, 57.0, 0.001, "die twice is a no-op")


func test_leech_and_cap() -> void:
	var a := dummy(Actor.Team.PLAYER, 1000.0, [mod("life_leech", "flat", 10), mod("mana_leech", "flat", 10)])
	a.base_mana = 100.0
	a.recalculate_stats()
	a.life = 100.0
	a.mana = 0.0
	var t := dummy(Actor.Team.ENEMY, 1e9)
	t.take_hit(make_hit({"physical": 100.0}, ["attack"], a))
	assert_near(a.life, 110.0, 0.001, "10% leech")
	assert_near(a.mana, 10.0, 0.001, "10% mana leech")
	t.take_hit(make_hit({"physical": 5000.0}, ["attack"], a))
	assert_near(a.life, 300.0, 0.001, "capped at 20% of max life per second")
	assert_near(a.mana, 20.0, 0.001, "mana capped at 20% of max mana")
	t.take_hit(make_hit({"physical": 5000.0}, ["attack"], a))
	assert_near(a.life, 300.0, 0.001, "budget used up")
	tick(a, 1.1, 0.1)
	var before := a.life
	t.take_hit(make_hit({"physical": 100.0}, ["attack"], a))
	assert_near(a.life - before, 10.0, 0.001, "budget recovers after a second")


func test_life_on_hit_targets_per_use() -> void:
	var a := dummy(Actor.Team.PLAYER, 1000.0, [mod("life_on_hit", "flat", 10)])
	a.life = 100.0
	var id := DamageCalc.next_use_id()
	for i in 7:
		var t := dummy(Actor.Team.ENEMY, 1000.0)
		var h := make_hit({"physical": 10.0}, ["attack"], a)
		h.use_id = id
		t.take_hit(h)
	assert_near(a.life, 150.0, 0.001, "5 targets per use")
	var h2 := make_hit({"physical": 10.0}, ["attack"], a)
	h2.use_id = DamageCalc.next_use_id()
	dummy(Actor.Team.ENEMY, 1000.0).take_hit(h2)
	assert_near(a.life, 160.0, 0.001, "new use counts again")
	# Without a use id: same skill in the same physics frame = one use.
	for i in 7:
		var h3 := make_hit({"physical": 10.0}, ["attack"], a)
		h3.skill_id = "cleave"
		dummy(Actor.Team.ENEMY, 1000.0).take_hit(h3)
	assert_near(a.life, 210.0, 0.001, "5 per tick without use id")
	for i in 10:
		var h4 := make_hit({"physical": 10.0}, ["attack"], a)
		h4.use_id = DamageCalc.next_use_id()
		dummy(Actor.Team.ENEMY, 1000.0).take_hit(h4)
	assert_near(a.life, 300.0, 0.001, "life on hit shares the 20%/s cap")


func test_zero_damage_hit() -> void:
	capture_numbers()
	var t := dummy(Actor.Team.ENEMY, 100.0, [mod("damage_taken", "more", -100)])
	assert_eq(t.take_hit(make_hit({"fire": 10.0})), 0.0, "no damage")
	assert_eq(numbers_of("immune").size(), 1, "immune number")
	assert_eq(t.life, 100.0, "life intact")


func test_knockback() -> void:
	var t := dummy(Actor.Team.ENEMY, 1000.0, [], {}, Vector3(2, 0, 0))
	var h := make_hit({"physical": 1.0})
	h.origin = Vector3.ZERO
	h.knockback = 6.0
	t.take_hit(h)
	assert_near(t.knockback_velocity.x, 6.0, 0.001, "pushed away from origin")
	tick(t, 1.0)
	assert_eq(t.knockback_velocity, Vector3.ZERO, "decays")
	t.is_boss_actor = true
	t.take_hit(h)
	assert_eq(t.knockback_velocity, Vector3.ZERO, "bosses ignore knockback")


func test_environment_damage() -> void:
	capture_numbers()
	var t := dummy(Actor.Team.ENEMY, 1000.0, [mod("fire_resistance", "flat", 50)])
	var src := dummy(Actor.Team.PLAYER, 100.0)
	var got := [0.0]
	t.damaged.connect(func(amount: float, _c: bool, _s: Node) -> void: got[0] = amount)
	assert_near(t.take_damage_from(src, 100.0, "fire"), 50.0, 0.001, "resisted")
	assert_near(float(got[0]), 50.0, 0.001, "damaged emitted")
	assert_eq(numbers_of("fire").size(), 1, "immediate number")
	t.take_damage(100.0, "cold")
	assert_true(t.has_ailment("chill"), "cold environment damage chills")

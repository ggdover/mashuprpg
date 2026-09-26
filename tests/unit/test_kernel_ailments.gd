extends "res://tests/unit/test_kernel_util.gd"
## Ailments on the target (§6.4): DoT tick math, stacking/replacement rules, chill, freeze
## threshold and immunity, boss durations, batched DoT numbers, ailment_changed.


func test_ignite_ticks_with_resistance() -> void:
	var t := dummy(Actor.Team.ENEMY, 1000.0, [mod("fire_resistance", "flat", 50)])
	watch_ailments(t)
	t.apply_ailment("ignite", {"dps": 20.0, "duration": 4.0})
	assert_true(t.has_ailment("ignite"), "ignited")
	assert_eq(ailment_events, ["ignite:true"], "changed true")
	var st: Dictionary = t.ailments["ignite"]
	assert_eq(float(st["duration"]), 4.0, "duration")
	assert_eq(float(st["time_left"]), 4.0, "time left")
	tick(t, 1.0)
	assert_near(t.life, 990.0, 0.01, "20 dps × 50% res for 1 s")
	tick(t, 3.0)
	assert_near(t.life, 960.0, 0.001, "exactly dps × duration")
	assert_false(t.has_ailment("ignite"), "expired")
	assert_eq(ailment_events, ["ignite:true", "ignite:false"], "changed false")


func test_ignite_replace_and_refresh() -> void:
	var t := dummy()
	t.apply_ailment("ignite", {"dps": 10.0, "duration": 4.0})
	tick(t, 2.0, 0.5)
	t.apply_ailment("ignite", {"dps": 5.0, "duration": 4.0})
	assert_eq(float(t.ailments["ignite"]["dps"]), 10.0, "weaker doesn't replace")
	assert_near(float(t.ailments["ignite"]["time_left"]), 4.0, 0.001, "weaker refreshes duration")
	t.apply_ailment("ignite", {"dps": 30.0, "duration": 3.0})
	assert_eq(float(t.ailments["ignite"]["dps"]), 30.0, "stronger replaces")
	assert_near(float(t.ailments["ignite"]["time_left"]), 3.0, 0.001, "with its duration")


func test_bleed_ignores_armour() -> void:
	var t := dummy(Actor.Team.ENEMY, 1000.0, [mod("armour", "flat", 100000), mod("physical_damage_reduction", "flat", 50)])
	t.apply_ailment("bleed", {"dps": 40.0, "duration": 4.0})
	tick(t, 1.0)
	assert_near(t.life, 980.0, 0.01, "only physical damage reduction applies")


func test_poison_stacks() -> void:
	var t := dummy(Actor.Team.ENEMY, 1000.0, [mod("chaos_resistance", "flat", 20)])
	watch_ailments(t)
	t.apply_ailment("poison", {"dps": 5.0, "duration": 1.0})
	t.apply_ailment("poison", {"dps": 5.0, "duration": 3.0})
	t.apply_ailment("poison", {"dps": 5.0, "duration": 3.0})
	var p: Dictionary = t.ailments["poison"]
	assert_eq((p["stacks"] as Array).size(), 3, "3 stacks")
	assert_near(float(p["dps"]), 15.0, 0.001, "total dps")
	assert_near(float(p["time_left"]), 3.0, 0.001, "longest stack")
	assert_eq(ailment_events, ["poison:true"], "one changed event")
	tick(t, 1.0, 0.05)
	assert_near(t.life, 1000.0 - 12.0, 0.1, "15 dps × 80% for 1 s")
	assert_eq((t.ailments["poison"]["stacks"] as Array).size(), 2, "short stack expired")
	assert_near(float(t.ailments["poison"]["dps"]), 10.0, 0.001, "total updated")
	tick(t, 2.1, 0.05)
	assert_false(t.has_ailment("poison"), "all expired")
	assert_eq(ailment_events, ["poison:true", "poison:false"], "off")


func test_poison_max_stacks() -> void:
	var t := dummy(Actor.Team.ENEMY, 1e6)
	for i in 25:
		t.apply_ailment("poison", {"dps": 1.0 + i, "duration": 2.0})
	var stacks: Array = t.ailments["poison"]["stacks"]
	assert_eq(stacks.size(), Actor.MAX_POISON_STACKS, "max 20")
	assert_near(float(t.ailments["poison"]["dps"]), float(range(6, 26).reduce(func(a, b): return a + b, 0)), 0.001, "weakest dropped")


func test_shock_and_chill_keep_stronger() -> void:
	var t := dummy()
	t.apply_ailment("shock", {"effect": 0.1, "duration": 4.0})
	t.apply_ailment("shock", {"effect": 0.3, "duration": 2.0})
	assert_near(t.get_shock_effect(), 0.3, 0.001, "stronger shock")
	t.apply_ailment("shock", {"effect": 0.1, "duration": 10.0})
	assert_near(t.get_shock_effect(), 0.3, 0.001, "weaker ignored")
	assert_near(float(t.ailments["shock"]["time_left"]), 2.0, 0.001, "weaker doesn't refresh")
	tick(t, 2.1, 0.1)
	assert_false(t.has_ailment("shock"), "shock expired")
	assert_eq(t.get_shock_effect(), 0.0, "no shock")
	t.apply_ailment("chill", {"effect": 0.9, "duration": 1.0})
	assert_near(t.get_chill_effect(), Actor.AILMENT_EFFECT_CAP, 0.001, "effect cap")


func test_chill_from_cold_hits() -> void:
	var t := dummy(Actor.Team.ENEMY, 1000.0)
	t.take_hit(make_hit({"cold": 100.0}))
	assert_near(t.get_chill_effect(), 0.2, 0.001, "100 / 1000 × 2")
	assert_near(float(t.ailments["chill"]["duration"]), 2.0, 0.001, "2 s")
	var t2 := dummy(Actor.Team.ENEMY, 1000.0)
	t2.take_hit(make_hit({"cold": 1.0}))
	assert_near(t2.get_chill_effect(), 0.1, 0.001, "min 10%")
	t2.take_hit(make_hit({"cold": 800.0}))
	assert_near(t2.get_chill_effect(), 0.3, 0.001, "max 30%, stronger kept")
	var t3 := dummy(Actor.Team.ENEMY, 1000.0, [mod("cold_resistance", "flat", 75)])
	t3.take_hit(make_hit({"cold": 200.0}))
	assert_near(t3.get_chill_effect(), 0.1, 0.001, "uses cold damage after mitigation")
	var t4 := dummy(Actor.Team.ENEMY, 1000.0)
	t4.take_hit(make_hit({"fire": 500.0}))
	assert_false(t4.has_ailment("chill"), "no chill without cold")


func test_freeze_threshold() -> void:
	var t := dummy(Actor.Team.ENEMY, 1000.0)
	var h := make_hit({"cold": 40.0})
	h.ailments = {"freeze": {"duration": 0.8}}
	t.take_hit(h)
	assert_false(t.is_frozen(), "4% of max life: no freeze")
	var h2 := make_hit({"cold": 60.0})
	h2.ailments = {"freeze": {"duration": 0.8}}
	t.take_hit(h2)
	assert_true(t.is_frozen(), "6%: frozen")
	assert_false(t.can_act(), "can't act")
	assert_near(float(t.ailments["freeze"]["duration"]), 0.8, 0.001, "duration")
	var r := dummy(Actor.Team.ENEMY, 1000.0, [mod("cold_resistance", "flat", 50)])
	var h3 := make_hit({"cold": 80.0})
	h3.ailments = {"freeze": {"duration": 0.8}}
	r.take_hit(h3)
	assert_false(r.is_frozen(), "threshold uses mitigated cold (40)")


func test_freeze_immunity() -> void:
	var t := dummy(Actor.Team.PLAYER, 1000.0)
	t.apply_ailment("freeze", {"duration": 0.5})
	assert_true(t.is_frozen(), "frozen")
	tick(t, 0.6, 0.1)
	assert_false(t.is_frozen(), "thawed")
	assert_near(t.freeze_immune_time, 2.0 - 0.1, 0.11, "2 s immunity")
	t.apply_ailment("freeze", {"duration": 0.5})
	assert_false(t.is_frozen(), "immune")
	tick(t, 2.0, 0.1)
	assert_eq(t.freeze_immune_time, 0.0, "immunity over")
	t.apply_ailment("freeze", {"duration": 0.5})
	assert_true(t.is_frozen(), "can be frozen again")
	t.remove_ailment("freeze")
	assert_near(t.freeze_immune_time, 2.0, 0.001, "removal also grants immunity")


func test_boss_rules() -> void:
	var b := dummy(Actor.Team.ENEMY, 1000.0)
	b.is_boss_actor = true
	var h := make_hit({"cold": 60.0})
	h.ailments = {"freeze": {"duration": 0.8}}
	b.take_hit(h)
	assert_false(b.is_frozen(), "boss threshold 10%")
	var h2 := make_hit({"cold": 120.0})
	h2.ailments = {"freeze": {"duration": 0.8}}
	b.take_hit(h2)
	assert_true(b.is_frozen(), "boss frozen at 12%")
	assert_near(float(b.ailments["freeze"]["duration"]), 0.24, 0.001, "freeze ×0.3")
	assert_near(float(b.ailments["chill"]["duration"]), 1.0, 0.001, "chill ×0.5")
	tick(b, 0.3, 0.05)
	assert_near(b.freeze_immune_time, 6.0, 0.1, "boss immunity 6 s")
	b.apply_ailment("ignite", {"dps": 10.0, "duration": 4.0})
	assert_near(float(b.ailments["ignite"]["duration"]), 2.0, 0.001, "ignite ×0.5")
	b.apply_ailment("poison", {"dps": 10.0, "duration": 2.0})
	assert_near(float(b.ailments["poison"]["time_left"]), 1.0, 0.001, "poison ×0.5")
	b.apply_ailment("shock", {"effect": 0.2, "duration": 4.0})
	assert_near(float(b.ailments["shock"]["duration"]), 2.0, 0.001, "shock ×0.5")


func test_dot_numbers_batched() -> void:
	capture_numbers()
	var t := dummy(Actor.Team.ENEMY, 1000.0)
	t.apply_ailment("ignite", {"dps": 10.0, "duration": 4.0})
	t.apply_ailment("poison", {"dps": 4.0, "duration": 4.0})
	tick(t, 0.45, 0.05)
	assert_eq(numbers.size(), 0, "nothing before 0.5 s")
	tick(t, 0.1, 0.05)
	assert_eq(numbers.size(), 2, "one number per type")
	assert_near(float(numbers_of("fire")[0]["amount"]), 5.0, 0.01, "summed fire")
	assert_near(float(numbers_of("chaos")[0]["amount"]), 2.0, 0.01, "summed chaos")
	assert_false(numbers[0]["crit"], "never crit")
	var p := dummy(Actor.Team.PLAYER, 1000.0)
	numbers.clear()
	p.apply_ailment("bleed", {"dps": 10.0, "duration": 4.0})
	tick(p, 0.55, 0.05)
	assert_eq(numbers_of("player_hurt").size(), 1, "player DoT numbers use player_hurt")


func test_dot_es_mom_and_kill_credit() -> void:
	var t := dummy(Actor.Team.ENEMY, 100.0, [mod("max_energy_shield", "flat", 10)])
	var killer := dummy(Actor.Team.PLAYER, 100.0, [mod("life_on_kill", "flat", 5)])
	killer.life = 50.0
	var died := [null]
	t.died.connect(func(_a: Actor, k: Node) -> void: died[0] = k)
	t.apply_ailment("ignite", {"dps": 20.0, "duration": 10.0, "source": killer})
	tick(t, 0.5, 0.05)
	assert_eq(t.es, 0.0, "ES absorbs DoT first")
	assert_near(t.life, 100.0, 0.5, "then life")
	tick(t, 6.0, 0.05)
	assert_true(t.dead, "DoT kills")
	assert_eq(died[0], killer, "kill credited to the ailment source")
	assert_near(killer.life, 55.0, 0.001, "on_kill called")
	var m := dummy(Actor.Team.PLAYER, 1000.0, [mod("mind_over_matter", "flag")])
	m.mana_regen = 0.0
	m.apply_ailment("poison", {"dps": 100.0, "duration": 1.0})
	tick(m, 0.5, 0.05)
	assert_near(m.mana, 100.0 - 15.0, 0.01, "MoM applies to DoTs")


func test_no_ailments_when_dead_and_clear() -> void:
	var t := dummy()
	watch_ailments(t)
	t.apply_ailment("shock", {"effect": 0.2, "duration": 4.0})
	t.apply_ailment("chill", {"effect": 0.2, "duration": 4.0})
	t.clear_ailments()
	assert_true(t.ailments.is_empty(), "cleared")
	assert_has(ailment_events, "shock:false", "shock off")
	assert_has(ailment_events, "chill:false", "chill off")
	t.die(null)
	t.apply_ailment("ignite", {"dps": 10.0, "duration": 4.0})
	assert_false(t.has_ailment("ignite"), "dead actors get no ailments")
	var u := dummy()
	u.apply_ailment("ignite", {"dps": 0.0, "duration": 4.0})
	u.apply_ailment("shock", {"effect": 0.2, "duration": 0.0})
	assert_true(u.ailments.is_empty(), "zero dps / duration ignored")


func test_hit_applies_rolled_ailments() -> void:
	var src := dummy(Actor.Team.PLAYER, 100.0)
	var t := dummy(Actor.Team.ENEMY, 1000.0)
	var h := DamageCalc.build_hit(src, spell_skill({"fire": [10, 10], "lightning": [10, 10]}, {"ailments": {"ignite": 100, "shock": 100}}), {"force_crit": false})
	t.take_hit(h)
	assert_true(t.has_ailment("ignite"), "ignite applied")
	assert_true(t.has_ailment("shock"), "shock applied")
	assert_eq(t.ailments["ignite"]["source"], src, "source stored")
	assert_near(float(t.ailments["ignite"]["dps"]), 5.0, 0.001, "dps from hit")


func test_freed_sources_are_safe() -> void:
	var src := dummy(Actor.Team.PLAYER, 100.0)
	var t := dummy(Actor.Team.ENEMY, 10.0)
	var h := DamageCalc.build_hit(src, spell_skill({"fire": [5, 5]}, {"ailments": {"ignite": 100}}), {"force_crit": false})
	t.take_hit(h)
	var target := dummy(Actor.Team.ENEMY, 100.0, [], {}, Vector3(5, 0, 0))
	var pb := dummy(Actor.Team.PLAYER, 100.0, [mod("point_blank", "flag")])
	src.free()
	target.free()
	var died := [false]
	t.died.connect(func(_a: Actor, k: Node) -> void: died[0] = (k == null))
	tick(t, 30.0, 0.1)
	assert_true(t.dead, "DoT from a freed source still kills")
	assert_true(died[0], "killer is null")
	var t2 := dummy(Actor.Team.ENEMY, 100.0)
	assert_true(t2.take_hit(h) > 0.0, "hit whose source was freed still lands")
	var pbh := DamageCalc.build_hit(pb, attack_skill({"tags": ["attack", "projectile"]}), {"force_crit": false, "target": target})
	assert_true(pbh.total() > 0.0, "freed point-blank target ignored")


func test_freed_source_copy_scale_and_environment() -> void:
	# A hit that outlives its attacker (projectile, delayed impact) can still be copied / scaled.
	var src := dummy(Actor.Team.PLAYER, 100.0)
	src.level = 7
	var h := DamageCalc.build_hit(src, spell_skill({"fire": [10, 10]}, {"ailments": {"ignite": 100}}), {"force_crit": false})
	var fire := h.get_amount("fire")
	var ignite_dps := float(h.ailments["ignite"]["dps"])
	var caster := dummy(Actor.Team.PLAYER, 100.0)
	src.free()
	var copy := h.duplicate_hit()
	assert_not_null(copy, "duplicate_hit with a freed source")
	assert_true(copy.source == null, "freed source -> null")
	assert_eq(copy.source_team, Actor.Team.PLAYER, "team kept")
	assert_eq(copy.source_level, 7, "level kept")
	assert_near(copy.get_amount("fire"), fire, 0.001, "damage copied")
	var half := h.scaled(0.5)
	assert_not_null(half, "scaled with a freed source")
	assert_near(half.get_amount("fire"), fire * 0.5, 0.001, "damage scaled")
	assert_near(float(half.ailments["ignite"]["dps"]), ignite_dps * 0.5, 0.001, "ailment dps scaled")
	assert_near(float(h.ailments["ignite"]["dps"]), ignite_dps, 0.001, "original untouched")
	var t := dummy(Actor.Team.ENEMY, 1000.0)
	assert_true(t.take_hit(half) > 0.0, "scaled copy lands")
	# A stored caster freed since: HitData.create / take_damage_from treat it as no source.
	caster.free()
	var env := HitData.create({"cold": 20.0}, caster, PackedStringArray(["spell"]))
	assert_true(env.source == null, "create with a freed source")
	assert_near(env.get_amount("cold"), 20.0, 0.001, "create damage")
	var killer := ["unset"]
	var weak := dummy(Actor.Team.ENEMY, 10.0)
	weak.died.connect(func(_a: Actor, k: Node) -> void: killer[0] = k)
	assert_near(weak.take_damage_from(caster, 5.0, "fire"), 5.0, 0.001, "freed caster, direct damage")
	weak.take_damage_from(caster, 100.0, "fire", true)
	assert_true(weak.dead, "DoT from a freed caster kills")
	assert_true(killer[0] == null, "no kill credit")
	var t2 := dummy(Actor.Team.ENEMY, 1000.0)
	var not_a_node: Variant = RefCounted.new()
	assert_near(t2.take_damage_from(not_a_node, 10.0, "physical"), 10.0, 0.001, "non-node source ignored")

extends Node
## Balance report for the balance pass: expected time-to-kill and survivability at levels
## 1 / 10 / 30 / 50, computed with the real kernel code (Actor stats, DamageCalc.build_hit with
## sampled rolls and crits, DamageCalc.mitigate with armour/resistances, evade/block chances).
## OWNER: kernel.
##
##   tools/gtest.sh kernel res://tests/scenes/kernel_balance_report.tscn
##
## Assumptions (edit the constants below to explore):
##   - Weapons/defences follow §9.2 templates at the best tier for the level (eff = min(L, tier + 12)).
##   - "naked": class attributes + base life/mana + the weapon, no passives, no other gear.
##   - "typical": passives spent as TYPICAL_* per point, gear defences on 4 armour pieces with
##     ~30% local increases, flat life and resistances from affixes.
##   - Monsters: normal archetype (life/damage mult 1), armour 8L, attack 0.85/s plus the AI pause
##     (0.3-0.8 s) = MONSTER_HITS_PER_SEC. Resist penalty applies to the player (§5.3).

const LEVELS: Array[int] = [1, 10, 30, 50]
const TIER_LEVELS: Array[int] = [1, 8, 16, 26, 38, 50]
const SAMPLES := 600
const MONSTER_ATTACK_SPEED := 0.85
const MONSTER_HITS_PER_SEC := 1.0 / (1.0 / MONSTER_ATTACK_SPEED + 0.55)
const PACK_SIZE := 4
const BOSS_LIFE_MULT := 25.0

## Per allocated passive point.
const TYPICAL_DAMAGE_INC_PER_POINT := 4.5
const TYPICAL_LIFE_INC_PER_POINT := 1.8
const TYPICAL_ATTR_PER_POINT := 1.5
## Per level, from gear affixes.
const TYPICAL_FLAT_LIFE_PER_LEVEL := 2.0
const TYPICAL_RES_BASE := 12.0
const TYPICAL_RES_PER_LEVEL := 1.1
const TYPICAL_LOCAL_DEFENCE_INC := 30.0
## Body 100% + helmet 45% + gloves 35% + boots 35%.
const ARMOUR_PIECES_MULT := 2.15

const WEAPONS := {
	"sword": {"weapon_type": "sword", "phys": Vector2(7, 15), "aps": 1.45, "crit": 5.0, "two_handed": false},
	"bow": {"weapon_type": "bow", "phys": Vector2(9, 21), "aps": 1.40, "crit": 5.0, "two_handed": true},
	"wand": {"weapon_type": "wand", "phys": Vector2(4, 9), "aps": 1.40, "crit": 7.0, "two_handed": false},
}

const BUILDS := [
	{"name": "warrior", "class": "warrior", "weapon": "sword", "defence": "armour",
		"skill": {"id": "heavy_strike", "tags": ["attack", "melee"], "damage_effectiveness": 1.75, "attack_time_mult": 1.25}},
	{"name": "ranger", "class": "ranger", "weapon": "bow", "defence": "evasion",
		"skill": {"id": "power_shot", "tags": ["attack", "projectile"], "damage_effectiveness": 1.9, "attack_time_mult": 1.0}},
	{"name": "sorcerer", "class": "sorcerer", "weapon": "wand", "defence": "energy_shield",
		"skill": {"id": "fireball", "tags": ["spell", "projectile", "area", "fire"], "base_damage": {"fire": [9, 14]}, "cast_time": 0.75, "crit_chance": 6.0}},
]

const MONSTER_MELEE := {"id": "m_melee", "tags": ["attack", "melee"], "monster_only": true, "monster_damage": {"physical": 1.0}}
const MONSTER_BOLT := {"id": "m_firebolt", "tags": ["spell", "projectile", "fire"], "monster_only": true, "monster_damage": {"fire": 1.0}}
const BASIC_ATTACK := {"id": "basic_attack", "tags": ["attack"], "damage_effectiveness": 1.0, "attack_time_mult": 1.0}


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	seed(20260925)
	print("")
	print("==================== KERNEL BALANCE REPORT ====================")
	print("monster hits/s (0.85 aps + 0.55 s AI pause): %.2f; pack size %d; boss life x%d, damage x2" % [MONSTER_HITS_PER_SEC, PACK_SIZE, int(BOSS_LIFE_MULT)])
	for lvl in LEVELS:
		_report_level(lvl)
	print("")
	print("Columns: dps vs a normal monster of the same level (armour applied, crits sampled);")
	print("TTK = seconds to kill; hit% = one normal melee hit (after armour/evade/block) as % of life+ES;")
	print("pack TTD = seconds to die to %d normals hitting continuously; rare/boss TTD likewise vs one." % PACK_SIZE)
	print("================================================================")
	get_tree().quit()


func _report_level(lvl: int) -> void:
	var life_n := Balance.monster_life(lvl)
	var hit := Balance.monster_damage(lvl)
	var kills := float(Balance.xp_to_next(lvl)) / Balance.monster_xp(lvl)
	print("")
	print("--- Level %d: monster life %.0f (magic %.0f, rare %.0f, boss %.0f), avg hit %.1f, armour %.0f; %.0f normal kills per level; resist penalty %d" % [
		lvl, life_n, life_n * 2.2, life_n * 5.0, life_n * BOSS_LIFE_MULT, hit, Balance.monster_armour(lvl), kills, int(Balance.resist_penalty(lvl))])
	print("%-9s %-7s | %8s %8s | %7s %7s %7s | %7s %6s %6s %5s | %8s %8s %8s" % [
		"build", "gear", "dps basic", "dps main", "TTK N", "TTK R", "TTK B", "life+ES", "hit%", "fire%", "evade", "pack TTD", "rare TTD", "boss TTD"])
	var monster := _monster(lvl, 0)
	for b in BUILDS:
		for gear in ["naked", "typical"]:
			var p := _player(b, lvl, gear == "typical")
			var main_dps := _dps(p, b["skill"], monster)
			var basic_dps := _dps(p, BASIC_ATTACK, monster)
			var dps := maxf(main_dps, 0.001)
			var ehp := p.max_life + p.max_es
			var melee := _expected_taken(p, _monster(lvl, 0), MONSTER_MELEE)
			var melee_rare := _expected_taken(p, _monster(lvl, 2), MONSTER_MELEE)
			var melee_boss := _expected_taken(p, _monster(lvl, 3), MONSTER_MELEE)
			var fire := _expected_taken(p, _monster(lvl, 0), MONSTER_BOLT)
			print("%-9s %-7s | %8.1f %8.1f | %7.2f %7.2f %7.1f | %7.0f %5.1f%% %5.1f%% %4.0f%% | %8.1f %8.1f %8.1f" % [
				b["name"], gear, basic_dps, main_dps,
				life_n / dps, life_n * 5.0 / dps, life_n * BOSS_LIFE_MULT / dps,
				ehp, 100.0 * melee / ehp, 100.0 * fire / ehp, DamageCalc.evade_chance(p, lvl),
				ehp / maxf(0.001, melee * MONSTER_HITS_PER_SEC * PACK_SIZE),
				ehp / maxf(0.001, melee_rare * MONSTER_HITS_PER_SEC),
				ehp / maxf(0.001, melee_boss * MONSTER_HITS_PER_SEC)])
			p.queue_free()
	monster.queue_free()


## Best weapon tier for the level, scaled per §9.2.
func _weapon(kind: String, lvl: int) -> Dictionary:
	var w: Dictionary = WEAPONS[kind]
	var eff := _eff_level(lvl)
	var scale := Balance.weapon_damage_scale(eff)
	var phys: Vector2 = w["phys"] * scale
	return {"weapon_type": w["weapon_type"], "phys_min": phys.x, "phys_max": phys.y, "added": {},
		"attack_speed": w["aps"], "crit_chance": w["crit"], "range": 2.2, "two_handed": w["two_handed"]}


func _eff_level(lvl: int) -> int:
	var tier_level := 1
	for t in TIER_LEVELS:
		if t <= lvl:
			tier_level = t
	return mini(lvl, tier_level + 12)


func _player(b: Dictionary, lvl: int, typical: bool) -> TestDummy:
	var d := TestDummy.new()
	d.team = Actor.Team.PLAYER
	d.level = lvl
	d.base_life = Balance.player_base_life(lvl)
	d.base_mana = Balance.player_base_mana(lvl)
	d.weapon_override = _weapon(b["weapon"], lvl)
	var mods: Array = ClassDefs.get_attribute_mods(b["class"])
	mods.append(StatBlock.mod("evasion", "flat", Balance.PLAYER_BASE_EVASION))
	var pen := Balance.resist_penalty(lvl)
	mods.append(StatBlock.mod("elemental_resistance", "flat", pen))
	mods.append(StatBlock.mod("chaos_resistance", "flat", pen))
	if typical:
		var pts := float(lvl - 1)
		mods.append(StatBlock.mod("damage", "inc", pts * TYPICAL_DAMAGE_INC_PER_POINT))
		mods.append(StatBlock.mod("max_life", "inc", pts * TYPICAL_LIFE_INC_PER_POINT))
		mods.append(StatBlock.mod(ClassDefs.get_main_attribute(b["class"]), "flat", pts * TYPICAL_ATTR_PER_POINT))
		mods.append(StatBlock.mod("max_life", "flat", TYPICAL_FLAT_LIFE_PER_LEVEL * lvl))
		mods.append(StatBlock.mod("elemental_resistance", "flat", minf(75.0, TYPICAL_RES_BASE + TYPICAL_RES_PER_LEVEL * lvl)))
		var eff := float(_eff_level(lvl))
		var local := (1.0 + TYPICAL_LOCAL_DEFENCE_INC / 100.0) * ARMOUR_PIECES_MULT
		match String(b["defence"]):
			"armour":
				mods.append(StatBlock.mod("armour", "flat", (15.0 + 7.5 * (eff - 1.0)) * local))
			"evasion":
				mods.append(StatBlock.mod("evasion", "flat", (50.0 + 9.0 * (eff - 1.0)) * local))
			"energy_shield":
				mods.append(StatBlock.mod("max_energy_shield", "flat", (12.0 + 3.2 * (eff - 1.0)) * local))
	d.extra_mods = mods
	add_child(d)
	d.set_physics_process(false)
	return d


func _monster(lvl: int, rarity: int) -> TestDummy:
	var d := TestDummy.new()
	d.team = Actor.Team.ENEMY
	d.level = lvl
	var r := Balance.monster_rarity(rarity)
	var life_mult: float = BOSS_LIFE_MULT if rarity == 3 else float(r["life"])
	d.base_life = Balance.monster_life(lvl) * life_mult
	d.base_mana = 0.0
	d.weapon_override = {"weapon_type": "monster", "phys_min": 0.0, "phys_max": 0.0, "added": {}, "attack_speed": MONSTER_ATTACK_SPEED, "crit_chance": 5.0, "range": 2.0, "two_handed": false}
	d.extra_mods = [
		StatBlock.mod("armour", "flat", Balance.monster_armour(lvl)),
		StatBlock.mod("damage", "more", (float(r["damage"]) - 1.0) * 100.0),
	]
	add_child(d)
	d.set_physics_process(false)
	return d


## Average damage per second of `skill` against `target` (armour/resistances applied).
func _dps(attacker: Actor, skill: Dictionary, target: Actor) -> float:
	var total := 0.0
	for i in SAMPLES:
		var h := DamageCalc.build_hit(attacker, skill, {"no_ailments": true})
		total += float(DamageCalc.mitigate(target, h)["total"])
	var avg := total / SAMPLES
	return avg / DamageCalc.get_use_time(attacker, skill)


## Expected damage the defender takes per monster skill use (evade/block chances included).
func _expected_taken(defender: Actor, attacker: Actor, skill: Dictionary) -> float:
	var total := 0.0
	for i in SAMPLES:
		var h := DamageCalc.build_hit(attacker, skill, {"no_ailments": true})
		total += float(DamageCalc.mitigate(defender, h)["total"])
	var avg := total / SAMPLES
	var tags := PackedStringArray(skill["tags"])
	if tags.has("attack"):
		avg *= 1.0 - DamageCalc.evade_chance(defender, attacker.level) / 100.0
	if tags.has("attack") or tags.has("projectile"):
		avg *= 1.0 - defender.block_chance / 100.0
	attacker.queue_free()
	return avg

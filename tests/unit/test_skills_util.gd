extends TestCase
## Shared helpers for the skills tests (no test_* methods here). Skills test files extend this
## script: extends "res://tests/unit/test_skills_util.gd".


## A TestDummy that records the SkillRunner's animation calls and owns a SkillRunner.
class Caster extends TestDummy:
	var anims: Array = []
	var stops := 0

	func play_action_animation(anim: String, duration: float) -> void:
		anims.append([anim, duration])

	func stop_action_animation() -> void:
		stops += 1


## A weapon dict with fixed damage (min == max) and no crit.
func weapon(wtype: String = "sword", phys: float = 10.0, aps: float = 1.0, crit: float = 0.0, reach: float = 2.2, two_handed: bool = false) -> Dictionary:
	return {"weapon_type": wtype, "phys_min": phys, "phys_max": phys, "added": {}, "attack_speed": aps, "crit_chance": crit,
		"range": reach if not (wtype in ["bow", "crossbow"]) else 20.0, "two_handed": two_handed or wtype in ["bow", "crossbow", "staff"]}


## A caster Actor (team, level, weapon, extra mods) with a SkillRunner child, inside the World
## when there is one. no_crit by default so damage checks are deterministic.
func make_caster(team: int = Actor.Team.PLAYER, pos: Vector3 = Vector3.ZERO, w: Dictionary = {}, lvl: int = 20, mods: Array = [], crit: bool = false) -> Caster:
	var c := Caster.new()
	c.team = team
	c.level = lvl
	c.base_life = 1000.0
	c.base_mana = 500.0
	c.weapon_override = w
	var m: Array = mods.duplicate()
	if not crit:
		m.append(StatBlock.mod("no_crit", "flag", 1.0))
	c.extra_mods = m
	c.position = pos
	var r := SkillRunner.new()
	r.name = "SkillRunner"
	r.setup(c)
	c.skill_runner = r
	c.add_child(r)
	if GameState.world != null:
		GameState.world.add_child(c)
	else:
		add_child(c)
	return c


## A target dummy (no armour / resistances, no evasion so attacks always land).
func target(pos: Vector3, life_value: float = 100000.0, team: int = Actor.Team.ENEMY) -> TestDummy:
	var d := spawn_dummy(team, pos, life_value)
	d.set_meta("start_life", d.max_life)
	return d


func lost(d: Actor) -> float:
	if not is_instance_valid(d):
		return 0.0
	return d.max_life - d.life


## Wait `seconds` of game time (physics frames).
func wait_time(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0 / maxf(0.01, Engine.time_scale))
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame


## Wait until cond() is true or `timeout` seconds of game time passed. Returns cond().
func wait_until(cond: Callable, timeout: float = 3.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0 / maxf(0.01, Engine.time_scale))
	while not bool(cond.call()) and Time.get_ticks_msec() < end:
		await get_tree().physics_frame
	return bool(cond.call())


## Use a skill with the caster's runner and wait for it to finish (and `extra` seconds more).
func use_and_wait(c: Actor, id: String, aim: Vector3, extra: float = 0.3, tgt: Actor = null) -> bool:
	var ok := c.skill_runner.try_use(id, aim, tgt)
	if not ok:
		return false
	var r := c.skill_runner
	await wait_until(func() -> bool: return not is_instance_valid(r) or not r.is_busy(), 6.0)
	if extra > 0.0:
		await wait_time(extra)
	return true


## Count live nodes of a script class under the current World's dynamic root (or this test).
func count_nodes(type_name: String) -> int:
	var root: Node = GameState.world.dynamic_root if GameState.world != null else self
	var n := 0
	for c in root.get_children():
		if c.get_script() != null and (c.get_script() as Script).get_global_name() == type_name:
			n += 1
	return n

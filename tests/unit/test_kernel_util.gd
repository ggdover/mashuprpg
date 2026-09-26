extends TestCase
## Shared helpers for the kernel tests (no test_* methods here). Kernel test files extend this
## script: extends "res://tests/unit/test_kernel_util.gd".

## Captured Events.damage_number emissions: [{"pos", "amount", "kind", "crit"}].
var numbers: Array = []
## Captured ailment_changed emissions: ["ignite:true", ...].
var ailment_events: Array = []


## A TestDummy with extra mods (and optional weapon) inside the tree, full pools, no physics
## processing (tests tick it by hand with d._tick_actor()).
func dummy(team: int = Actor.Team.ENEMY, life_value: float = 1000.0, mods: Array = [], weapon: Dictionary = {}, pos: Vector3 = Vector3.ZERO) -> TestDummy:
	var d := TestDummy.new()
	d.team = team
	d.base_life = life_value
	d.extra_mods = mods
	d.weapon_override = weapon
	d.position = pos
	add_child(d)
	d.set_physics_process(false)
	return d


## A weapon dict with fixed damage (min == max) and no crit.
func weapon(phys: float, aps: float = 1.0, crit: float = 0.0, wtype: String = "sword", two_handed: bool = false, added: Dictionary = {}) -> Dictionary:
	return {"weapon_type": wtype, "phys_min": phys, "phys_max": phys, "added": added, "attack_speed": aps, "crit_chance": crit, "range": 2.2, "two_handed": two_handed}


func attack_skill(extra: Dictionary = {}) -> Dictionary:
	var s := {"id": "t_attack", "tags": ["attack", "melee"], "damage_effectiveness": 1.0, "attack_time_mult": 1.0, "mana_cost": 0.0}
	s.merge(extra, true)
	return s


func spell_skill(base: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var s := {"id": "t_spell", "tags": ["spell"], "base_damage": base, "cast_time": 1.0, "crit_chance": 0.0, "mana_cost": 0.0}
	s.merge(extra, true)
	return s


func mod(stat: String, op: String, value: float = 0.0, value2: Variant = null) -> Dictionary:
	return StatBlock.mod(stat, op, value, value2)


## A hit with fixed damage (no rolls): tags decide evade/block.
func make_hit(damage: Dictionary, tags: Array = ["spell"], source: Actor = null) -> HitData:
	return HitData.create(damage, source, PackedStringArray(tags))


func capture_numbers() -> void:
	numbers.clear()
	if not Events.damage_number.is_connected(_on_number):
		Events.damage_number.connect(_on_number)


func stop_capture() -> void:
	if Events.damage_number.is_connected(_on_number):
		Events.damage_number.disconnect(_on_number)


func _on_number(pos: Vector3, amount: float, kind: String, crit: bool) -> void:
	numbers.append({"pos": pos, "amount": amount, "kind": kind, "crit": crit})


func numbers_of(kind: String) -> Array:
	return numbers.filter(func(n: Dictionary) -> bool: return n["kind"] == kind)


func watch_ailments(a: Actor) -> void:
	a.ailment_changed.connect(func(kind: String, active: bool) -> void: ailment_events.append("%s:%s" % [kind, active]))


## Tick an actor by hand in steps.
func tick(a: Actor, seconds: float, step: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds - 0.00001:
		var dt := minf(step, seconds - t)
		a._tick_actor(dt)
		t += dt


func _exit_tree() -> void:
	stop_capture()

class_name TestCase
extends Node
## Base class for unit tests. Put test files in res://tests/unit/test_<module>_<topic>.gd,
## extend TestCase, and write methods named test_*. Each test method runs on a FRESH instance that
## is added to the scene tree (so autoloads, get_tree() and node creation all work). Tests may use
## `await` (e.g. await get_tree().physics_frame). A test fails on any failed assertion, on any
## engine/script error logged while it runs (push_error, SCRIPT ERROR), or after 20 s.
## Use push_warning() (not push_error) for tolerated, expected problems.
##
## Fixtures (await the async ones):
##   var w := await make_world()            # open "arena" World (16x16 cells), GameState.world = w
##   var c := make_character("ranger")      # GameState.new_character(...), sets GameState.character
##   var p := spawn_player(Vector3.ZERO)    # real Player bound to GameState.character (+ world)
##   var d := spawn_dummy(Actor.Team.ENEMY, Vector3(3, 0, 0), 500.0)   # TestDummy actor
## The runner resets GameState.player/world/character/current_area after every test.
## Wave-2 tests may only depend on wave-0/1 code and your own module; use dummies for the rest.
## OWNER: orchestrator.

var failures: Array[String] = []
var current_test: String = ""


func fail(msg: String) -> void:
	failures.append(msg)


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("%s: expected %s (%s), got %s (%s)" % [msg, expected, type_string(typeof(expected)), actual, type_string(typeof(actual))])
	elif actual != expected:
		fail("%s: expected %s, got %s" % [msg, expected, actual])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if actual == unexpected:
		fail("%s: did not expect %s" % [msg, unexpected])


func assert_near(actual: float, expected: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s: expected %s ± %s, got %s" % [msg, expected, eps, actual])


func assert_between(actual: float, lo: float, hi: float, msg: String = "") -> void:
	if actual < lo or actual > hi:
		fail("%s: expected in [%s, %s], got %s" % [msg, lo, hi, actual])


func assert_not_null(v: Variant, msg: String = "expected non-null") -> void:
	if v == null:
		fail(msg)


func assert_has(container: Variant, key: Variant, msg: String = "") -> void:
	var ok := false
	if container is Dictionary:
		ok = (container as Dictionary).has(key)
	elif container is Array or container is PackedStringArray or container is PackedInt32Array:
		ok = key in container
	if not ok:
		fail("%s: %s not found" % [msg, key])


# ------------------------------------------------------------------ fixtures

## Build an open arena World (or any World.build() info), parented to this test, and make it
## GameState.world. Awaits two physics frames so physics shapes are live.
func make_world(info: Dictionary = {"id": "arena", "name": "Arena", "level": 1, "size": 16}) -> World:
	var w := World.new()
	add_child(w)
	GameState.world = w
	GameState.current_area = info
	w.build(info)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return w


## Fresh character via GameState.new_character (sets GameState.character).
func make_character(class_id: String = "warrior") -> CharacterData:
	return GameState.new_character("Tester", class_id)


## A real Player bound to GameState.character (created if missing), added to GameState.world if
## set, else to this test node. Sets GameState.player.
func spawn_player(pos: Vector3 = Vector3.ZERO) -> Player:
	if GameState.character == null:
		make_character()
	var p := Player.new()
	p.setup(GameState.character)
	p.position = pos
	if GameState.world != null:
		GameState.world.add_child(p)
	else:
		add_child(p)
	GameState.player = p
	return p


## A TestDummy actor (capsule, configurable life) on the given team.
func spawn_dummy(team: int = Actor.Team.ENEMY, pos: Vector3 = Vector3(3, 0, 0), max_life: float = 1000.0) -> TestDummy:
	var d := TestDummy.new()
	d.team = team
	d.base_life = max_life
	d.position = pos
	if GameState.world != null:
		GameState.world.add_child(d)
	else:
		add_child(d)
	return d


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

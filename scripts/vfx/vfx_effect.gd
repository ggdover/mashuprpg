class_name VfxEffect
extends Node3D
## A self-freeing visual effect node: ages every frame, calls `updater.call(t, age)` with
## t = age / life (0..1), optionally follows a Node3D, and frees itself when age >= life.
## `keep_while` (optional Callable returning bool) holds the effect at `hold_t` until it returns
## false (buff auras, clouds), then the remaining life plays out as the fade.
## Built by VfxSpawn; everything visual in the skills module goes through it. OWNER: skills.

var life := 1.0
var age := 0.0
var updater: Callable = Callable()
var follow: Variant = null
var follow_offset := Vector3.ZERO
var keep_while: Callable = Callable()
var hold_t := 0.5
var _holding := false


func _process(delta: float) -> void:
	if keep_while.is_valid():
		if bool(keep_while.call()):
			if age < hold_t * life:
				age = minf(age + delta, hold_t * life)
			_holding = true
		else:
			keep_while = Callable()
			_holding = false
			age = maxf(age, hold_t * life)
	else:
		age += delta
	if follow != null:
		if is_instance_valid(follow) and (follow as Node3D).is_inside_tree():
			global_position = (follow as Node3D).global_position + follow_offset
		elif not keep_while.is_valid():
			pass
	var t := clampf(age / maxf(life, 0.001), 0.0, 1.0)
	if updater.is_valid():
		updater.call(t, age)
	if age >= life and not _holding:
		queue_free()


## Jump to the fade-out part (used when the owner ends early).
func end_now(fade_fraction: float = 0.25) -> void:
	keep_while = Callable()
	_holding = false
	age = maxf(age, life * (1.0 - fade_fraction))


## Abort the effect: it shrinks (XZ) to nothing over `time` seconds and frees itself (cancelled
## telegraphs, interrupted casts).
func cancel(time: float = 0.15) -> void:
	keep_while = Callable()
	_holding = false
	follow = null
	var start_scale := scale
	var t0 := age
	var dur := maxf(0.02, time)
	life = age + dur
	updater = func(_t: float, a: float) -> void:
		var k := clampf((a - t0) / dur, 0.0, 1.0)
		scale = Vector3(start_scale.x * (1.0 - k), start_scale.y, start_scale.z * (1.0 - k)) + Vector3(0.001, 0.0, 0.001)

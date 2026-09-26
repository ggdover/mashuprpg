extends SkillRunner
## A scripted SkillRunner for the player tests (no test_* methods: the runner skips this file).
## Inject it before the Player enters the tree:
##   var p := Player.new(); p.setup(c); p.skill_runner = FakeRunner.new(); world.add_child(p)
## A use keeps the runner busy for `fk_use_time` seconds (channel ids until release()), plays
## `fk_anim` through actor.play_action_animation() and records every call.

## Seconds one use keeps the runner busy.
var fk_use_time := 0.3
## movement_multiplier() while busy.
var fk_move_mult := 0.0
var fk_anim := "attack_slash"
## Skill ids that behave like channels (busy until release / cancel).
var fk_channel_ids: Array[String] = []
## Skill ids whose try_use fails (like "Not enough mana").
var fk_fail_ids: Array[String] = []

## [{"id": String, "pos": Vector3, "target": Actor}] per successful try_use.
var fk_uses: Array = []
## Every try_use call (successful or not): ids.
var fk_attempts: Array[String] = []
var fk_releases: Array[String] = []
var fk_updates := 0
var fk_last_update_pos := Vector3.ZERO
var fk_cancels := 0

var _fk_current := ""
var _fk_left := 0.0


func can_use(skill_id: String) -> Dictionary:
	if skill_id in fk_fail_ids:
		return {"ok": false, "reason": "Not enough mana", "code": "cost"}
	return {"ok": true, "reason": "", "code": "ok"}


func try_use(skill_id: String, target_pos: Vector3, target: Actor = null) -> bool:
	fk_attempts.append(skill_id)
	if actor == null or not actor.can_act() or _fk_current != "" or skill_id in fk_fail_ids:
		return false
	fk_uses.append({"id": skill_id, "pos": target_pos, "target": target})
	actor.face_towards(target_pos)
	_fk_current = skill_id
	if skill_id in fk_channel_ids:
		_fk_left = INF
		actor.play_action_animation("channel", 0.0)
	else:
		_fk_left = fk_use_time
		actor.play_action_animation(fk_anim, fk_use_time)
	skill_started.emit(skill_id, fk_anim, fk_use_time)
	return true


func update_target(target_pos: Vector3, _target: Actor = null) -> void:
	fk_updates += 1
	fk_last_update_pos = target_pos


func release(skill_id: String) -> void:
	fk_releases.append(skill_id)
	if _fk_current == skill_id and skill_id in fk_channel_ids:
		_fk_finish()
		if actor != null and is_instance_valid(actor):
			actor.stop_action_animation()


func is_busy() -> bool:
	return _fk_current != ""


func get_current_skill() -> String:
	return _fk_current


func movement_multiplier() -> float:
	return fk_move_mult if _fk_current != "" else 1.0


func get_cooldown_remaining(_skill_id: String) -> float:
	return 0.0


func get_cooldown_ratio(_skill_id: String) -> float:
	return 0.0


func cancel() -> void:
	fk_cancels += 1
	if _fk_current != "":
		_fk_current = ""
		_fk_left = 0.0
		if actor != null and is_instance_valid(actor):
			actor.stop_action_animation()


func fk_use_count(skill_id: String) -> int:
	var n := 0
	for u in fk_uses:
		if u["id"] == skill_id:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if _fk_current == "" or _fk_left == INF:
		return
	_fk_left -= delta
	if _fk_left <= 0.0:
		_fk_finish()


func _fk_finish() -> void:
	var id := _fk_current
	_fk_current = ""
	_fk_left = 0.0
	skill_finished.emit(id)

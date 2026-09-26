extends Node3D
## The player's look: the char_player model, its AnimationPlayer (idle / run by speed, time-scaled
## action one-shots, looping channel with model spin, hit reaction, death), gear visuals (weapon,
## shield / focus, quiver, helmet attached to bones; armour tints on body parts) and the hit flash.
## Child "Visuals" of the Player. OWNER: player (wave 2).
## Internal helper of Player: `const PlayerVisuals := preload("res://scripts/entities/player/player_visuals.gd")`.

## Planted-foot speed of char_player's run cycle (m/s): run speed_scale = speed / RUN_REF_SPEED.
const RUN_REF_SPEED := 5.2
## Below this horizontal speed (m/s) the model idles.
const RUN_MIN_SPEED := 0.4
## Model spin while the action animation is "channel" (turns per second).
const CHANNEL_SPIN := 2.0
const LOCO_BLEND := 0.15
const ACTION_BLEND := 0.06
const RETURN_BLEND := 0.18
## Colours for body parts whose slot is empty.
const NO_BODY_TINT := Color(0.72, 0.64, 0.52)      # plain linen tunic
const EMPTY_GLOVES_TINT := Color(0.5, 0.38, 0.26)  # bare leather
const EMPTY_BOOTS_TINT := Color(0.46, 0.34, 0.22)
const HIT_FLASH_COLOR := Color(1.0, 0.32, 0.26)
## Flash amount lost per second.
const FLASH_DECAY := 3.5
## Animations used when a requested one is missing on the model.
const ANIM_FALLBACKS := {
	"attack_stab": "attack_slash", "attack_slam": "attack_slash", "shoot_crossbow": "shoot_bow",
	"shoot_bow": "attack_slash", "cast_area": "cast", "roar": "cast_area", "channel": "cast",
	"dodge": "run", "hit": "idle",
}

var model: Node3D = null
var anim: AnimationPlayer = null
## Current action animation ("" = locomotion). One of the §14.3 names, or "die".
var action_anim := ""
## Seconds left of the current action (INF while looping / dead).
var action_left := 0.0
## Current locomotion animation ("idle" / "run").
var loco_anim := ""
## bone -> Node3D attached for the current equipment ("grip_r", "grip_l", "chest", "head").
var attachments: Dictionary = {}
var dead := false

var _reaction := false
var _flash := 0.0
var _hair: MeshInstance3D = null


func build() -> void:
	model = Assets.model("char_player")
	model.name = "Model"
	add_child(model)
	anim = Assets.prepare_animations(model)
	_hair = Assets.find_part(model, "Hair")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if anim != null:
		anim.playback_default_blend_time = 0.0
		_play_loco("idle", 0.0)


# ------------------------------------------------------------------ per-frame update

## speed: horizontal speed in m/s; frozen pauses the animation.
func update(delta: float, speed: float, frozen: bool) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - FLASH_DECAY * delta)
		Assets.set_flash(model, _flash, HIT_FLASH_COLOR)
	if dead:
		if anim != null:
			anim.speed_scale = 1.0
		return
	if action_anim != "":
		if action_anim == "channel" and model != null:
			model.rotation.y = wrapf(model.rotation.y + TAU * CHANNEL_SPIN * delta * (0.0 if frozen else 1.0), -PI, PI)
		if action_left != INF:
			action_left -= delta
			if action_left <= 0.0:
				_end_action()
	if anim == null:
		return
	if frozen:
		anim.speed_scale = 0.0
		return
	if action_anim != "":
		anim.speed_scale = 1.0
		return
	if speed > RUN_MIN_SPEED:
		_play_loco("run", LOCO_BLEND)
		anim.speed_scale = clampf(speed / RUN_REF_SPEED, 0.45, 2.6)
	else:
		_play_loco("idle", LOCO_BLEND)
		anim.speed_scale = 1.0


func _play_loco(name_: String, blend: float) -> void:
	if anim == null or not anim.has_animation(name_):
		loco_anim = name_
		return
	if loco_anim == name_ and anim.current_animation == name_:
		return
	loco_anim = name_
	anim.play(name_, blend)


func _end_action() -> void:
	action_anim = ""
	action_left = 0.0
	_reaction = false
	if model != null:
		model.rotation.y = 0.0
	loco_anim = ""   # force the locomotion animation to restart with a blend
	if anim != null:
		anim.speed_scale = 1.0
		_play_loco("idle", RETURN_BLEND)


# ------------------------------------------------------------------ actions

## Name actually available on the model for `wanted` ("" if nothing fits).
func resolve_anim(wanted: String) -> String:
	if anim == null:
		return wanted
	var n := wanted
	for i in 4:
		if anim.has_animation(n):
			return n
		if not ANIM_FALLBACKS.has(n):
			break
		n = ANIM_FALLBACKS[n]
	return "cast" if anim.has_animation("cast") else ""


## One-shot time-scaled to last `duration` s; duration <= 0 loops it (channel) until stop_action().
func play_action(wanted: String, duration: float) -> void:
	if dead:
		return
	var n := resolve_anim(wanted)
	if model != null and wanted != "channel":
		model.rotation.y = 0.0
	action_anim = wanted if n != "" else ""
	_reaction = false
	if action_anim == "":
		return
	action_left = INF if duration <= 0.0 else duration
	if anim == null:
		return
	anim.speed_scale = 1.0
	var restart := anim.current_animation == n
	if duration <= 0.0:
		anim.play(n, ACTION_BLEND, 1.0)
	else:
		var length := anim.get_animation(n).length
		anim.play(n, ACTION_BLEND, maxf(0.05, length / duration))
	if restart:
		anim.seek(0.0, true)


## Back to idle / run immediately.
func stop_action() -> void:
	if dead or action_anim == "":
		return
	_end_action()


## Low-priority one-shot (hit flinch): only when no other action is playing.
func play_reaction(wanted: String, duration: float) -> void:
	if dead or action_anim != "":
		return
	play_action(wanted, duration)
	_reaction = action_anim != ""


func is_reacting() -> bool:
	return _reaction


## Fall down and stay down.
func play_death() -> void:
	if dead:
		return
	var n := resolve_anim("die")
	action_anim = "die"
	action_left = INF
	_reaction = false
	dead = true
	if model != null:
		model.rotation.y = 0.0
	if anim != null and n != "":
		anim.speed_scale = 1.0
		anim.play(n, 0.08, 1.0)


func flash(amount: float) -> void:
	if model == null:
		return
	_flash = clampf(maxf(_flash, amount), 0.0, 1.0)
	Assets.set_flash(model, _flash, HIT_FLASH_COLOR)


# ------------------------------------------------------------------ equipment

## Rebuild weapon / off-hand / helmet attachments and body tints from the character's equipment.
func apply_equipment(character: CharacterData) -> void:
	if model == null:
		return
	for bone in attachments:
		var old: Node3D = attachments[bone]
		if is_instance_valid(old):
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.queue_free()
	attachments.clear()
	var main: Item = character.get_equipped("main_hand") if character != null else null
	var off: Item = character.get_equipped("off_hand") if character != null else null
	var helm: Item = character.get_equipped("helmet") if character != null else null
	var body: Item = character.get_equipped("body") if character != null else null
	var gloves: Item = character.get_equipped("gloves") if character != null else null
	var boots: Item = character.get_equipped("boots") if character != null else null
	if main != null:
		_attach("grip_r", main)
	if off != null:
		_attach("chest" if off.get_weapon_type() == "quiver" else "grip_l", off)
	if helm != null:
		_attach("head", helm)
	if _hair != null:
		_hair.visible = helm == null
	var body_tint := body.get_tint() if body != null else NO_BODY_TINT
	var gloves_tint := gloves.get_tint() if gloves != null else EMPTY_GLOVES_TINT
	var boots_tint := boots.get_tint() if boots != null else EMPTY_BOOTS_TINT
	Assets.tint(model, body_tint, PackedStringArray(["Torso", "Arms"]))
	Assets.tint(model, gloves_tint, PackedStringArray(["Hands"]))
	Assets.tint(model, boots_tint, PackedStringArray(["Feet"]))
	# Knee guards follow the boots so the legs match the footwear.
	Assets.tint(model, boots_tint, PackedStringArray(["Legs"]))
	if _flash > 0.0:
		Assets.set_flash(model, _flash, HIT_FLASH_COLOR)


func _attach(bone: String, item: Item) -> void:
	var id := item.get_model_id()
	if id == "":
		push_warning("PlayerVisuals: item %s has no model" % item.base_id)
		return
	var node := Assets.model(id)
	node.name = "Gear_" + bone
	Assets.tint(node, item.get_tint())
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Assets.attach_to_bone(model, bone, node)
	attachments[bone] = node


## The attached model for a bone ("grip_r", "grip_l", "chest", "head") or null.
func get_attachment(bone: String) -> Node3D:
	var n: Variant = attachments.get(bone)
	return n if is_instance_valid(n) else null

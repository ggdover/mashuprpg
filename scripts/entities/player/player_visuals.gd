extends Node3D
## The player's look: the character's player model (char_player_<look>: "f", "m1", "m2", see
## ClassDefs "looks"), its AnimationPlayer (idle / walk / run by speed, time-scaled action one-shots,
## looping channel with model spin, hit reaction, death), a leg layer (PlayerLegs: walking / backing
## off / side-stepping legs under an action while the player moves during a skill, blended by the
## direction of movement), swinging cape and hair (SpringBoneSimulator3D on the cape_* / hair_*
## bones, pushed back by the movement), gear visuals and the hit flash.
## Gear: weapons, shields / foci on the grip bones and quivers on the chest (BoneAttachment3D); armour
## (helmet, body, gloves, boots) shows the model's own gear piece for the item (PlayerGear: family and
## tier -> "Helm_str_2"...), hides the base parts the piece covers (hair under helmets, the default
## outfit under body armour...) and tints the piece's tint_* surfaces with the item's tint.
## Child "Visuals" of the Player. OWNER: player (wave 2).
## Internal helper of Player: `const PlayerVisuals := preload("res://scripts/entities/player/player_visuals.gd")`.

const PlayerLegs := preload("res://scripts/entities/player/player_legs.gd")
const PlayerGear := preload("res://scripts/entities/player/player_gear.gd")

## Planted-foot speed of char_player's run cycle (m/s): run speed_scale = speed / RUN_REF_SPEED.
const RUN_REF_SPEED := 5.2
## Planted-foot speed of the walk cycle (m/s): walk speed_scale = speed / WALK_REF_SPEED (the pace
## while using a skill, SkillRunner.PLAYER_SKILL_MOVE_MULT × the base move speed).
const WALK_REF_SPEED := 1.82
## Locomotion switches to the walk below WALK_BELOW and back to the run above RUN_ABOVE (m/s).
const WALK_BELOW := 2.8
const RUN_ABOVE := 3.2
## Actions whose legs stay their own (no walking legs under them).
const OWN_LEGS: Array[String] = ["dodge", "die", "channel", "hit"]
## How fast the walking legs blend in / out under an action (per second).
const LEGS_BLEND_RATE := 12.0
## How fast the leg layer turns toward a new movement direction (1/s, exponential).
const LEGS_TURN_RATE := 14.0
## Below this horizontal speed (m/s) the model idles.
const RUN_MIN_SPEED := 0.4
## Model spin while the action animation is "channel" (turns per second).
const CHANNEL_SPIN := 2.0
const LOCO_BLEND := 0.15
const ACTION_BLEND := 0.06
const RETURN_BLEND := 0.18
## Swinging chains: [root bone, end bone, end length (m), stiffness, drag, gravity, joint radius].
const SPRING_CHAINS := [
	["cape_1", "cape_3", 0.28, 2.0, 0.5, 1.2, 0.03],
	["hair_1", "hair_2", 0.2, 3.0, 0.55, 0.8, 0.025],
]
## Body colliders the chains stay out of: [bone, radius, height, offset along the bone].
const SPRING_COLLIDERS := [
	["spine", 0.1, 0.5, 0.05],
	["upper_leg_l", 0.075, 0.44, 0.2],
	["upper_leg_r", 0.075, 0.44, 0.2],
]
## Air drag on cape and hair while moving: external force = -velocity × SPRING_WIND.
const SPRING_WIND := 0.14
const HIT_FLASH_COLOR := Color(1.0, 0.32, 0.26)
## Flash amount lost per second.
const FLASH_DECAY := 3.5
## Animations used when a requested one is missing on the model.
const ANIM_FALLBACKS := {
	"attack_stab": "attack_slash", "attack_slam": "attack_slash", "shoot_crossbow": "shoot_bow",
	"shoot_bow": "attack_slash", "cast_area": "cast", "roar": "cast_area", "channel": "cast",
	"dodge": "run", "hit": "idle", "parry": "attack_stab", "parry_hold": "parry",
}

var model: Node3D = null
var anim: AnimationPlayer = null
## Current action animation ("" = locomotion). One of the §14.3 names, or "die".
var action_anim := ""
## Seconds left of the current action (INF while looping / dead).
var action_left := 0.0
## Current locomotion animation ("idle" / "run").
var loco_anim := ""
## bone -> Node3D attached for the current equipment ("grip_r", "grip_l", "chest").
var attachments: Dictionary = {}
var dead := false
## The model's look ("f", "m1", "m2") and its mesh parts by name (base parts + gear pieces).
var look := ""
var parts: Dictionary = {}
## Gear piece shown per equipment slot ("helmet" -> "Helm_str_2"; missing = none).
var gear_pieces: Dictionary = {}
## Cape / hair simulation (null without such bones).
var springs: SkeletonModifier3D = null

var _reaction := false
var _flash := 0.0
## The leg layer (null for placeholder models or models without a walk).
var legs: PlayerLegs = null


## Model id of a look ("char_player_f"); char_player (the default look) when that model is missing.
static func model_id_for(p_look: String) -> String:
	var id := "char_player_" + p_look
	return id if p_look != "" and Assets.has_model(id) else "char_player"


## Load the model of `p_look` ("" = the default look), its animations, leg layer and springs.
func build(p_look: String = "") -> void:
	look = p_look
	model = Assets.model(model_id_for(p_look))
	model.name = "Model"
	add_child(model)
	anim = Assets.prepare_animations(model)
	parts.clear()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parts[String(mi.name)] = mi
	if anim != null:
		anim.playback_default_blend_time = 0.0
		_play_loco("idle", 0.0)
		_build_legs()
	_build_springs()
	_show_gear({})


func _build_legs() -> void:
	if anim == null or not anim.has_animation("walk"):
		return
	var sk := Assets.find_skeleton(model)
	if sk == null:
		return
	var l := PlayerLegs.new()
	l.name = "WalkLegs"
	if not l.setup(anim, sk):
		l.free()
		return
	l.influence = 0.0
	l.active = false
	sk.add_child(l)
	legs = l


## Cape and hair chains (SpringBoneSimulator3D, after the animation and the leg layer).
func _build_springs() -> void:
	var sk := Assets.find_skeleton(model)
	if sk == null:
		return
	var chains: Array = []
	for c in SPRING_CHAINS:
		if sk.find_bone(String(c[0])) >= 0 and sk.find_bone(String(c[1])) >= 0:
			chains.append(c)
	if chains.is_empty():
		return
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Springs"
	sim.setting_count = chains.size()
	for i in chains.size():
		var c: Array = chains[i]
		sim.set_root_bone_name(i, String(c[0]))
		sim.set_end_bone_name(i, String(c[1]))
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, float(c[2]))
		sim.set_stiffness(i, float(c[3]))
		sim.set_drag(i, float(c[4]))
		sim.set_gravity(i, float(c[5]))
		sim.set_radius(i, float(c[6]))
		sim.set_enable_all_child_collisions(i, true)
	for c in SPRING_COLLIDERS:
		if sk.find_bone(String(c[0])) < 0:
			continue
		var col := SpringBoneCollisionCapsule3D.new()
		col.name = "Collider_" + String(c[0])
		col.bone_name = String(c[0])
		col.radius = float(c[1])
		col.height = float(c[2])
		col.position_offset = Vector3(0.0, float(c[3]), 0.0)
		sim.add_child(col)
	sk.add_child(sim)
	springs = sim


# ------------------------------------------------------------------ per-frame update

## speed: horizontal speed in m/s; frozen pauses the animation. local_velocity: the velocity in the
## model's frame (x = toward its right, y = forward; zero = straight ahead) — the leg layer under an
## action walks, backs off or side-steps by its direction.
func update(delta: float, speed: float, frozen: bool, local_velocity: Vector2 = Vector2.ZERO) -> void:
	_update_legs(delta, speed, frozen, local_velocity)
	if springs != null and is_instance_valid(springs):
		var body := get_parent() as CharacterBody3D
		var v := body.velocity if body != null else Vector3.ZERO
		(springs as SpringBoneSimulator3D).external_force = Vector3(-v.x, 0.0, -v.z) * SPRING_WIND
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
		var walking := anim.has_animation("walk") and (speed < WALK_BELOW or (loco_anim == "walk" and speed < RUN_ABOVE))
		if walking:
			_play_loco("walk", LOCO_BLEND)
			anim.speed_scale = clampf(speed / WALK_REF_SPEED, 0.5, 1.9)
		else:
			_play_loco("run", LOCO_BLEND)
			anim.speed_scale = clampf(speed / RUN_REF_SPEED, 0.45, 2.6)
	else:
		_play_loco("idle", LOCO_BLEND)
		anim.speed_scale = 1.0


## The walking legs under an action: blended in while moving (by speed), turned toward the direction
## of movement relative to the facing (forward walk, side-steps, backing off), stepping in time with
## the ground speed; blended out when standing or between actions.
func _update_legs(delta: float, speed: float, frozen: bool, local_velocity: Vector2) -> void:
	if legs == null or not is_instance_valid(legs):
		return
	var want := 0.0
	if not dead and not frozen and action_anim != "" and not OWN_LEGS.has(action_anim):
		want = clampf((speed - 0.25) / 0.6, 0.0, 1.0)
	var was_active := legs.active
	legs.influence = move_toward(legs.influence, want, LEGS_BLEND_RATE * delta)
	legs.active = legs.influence > 0.001
	if not legs.active or frozen:
		return
	if local_velocity.length_squared() > 0.01:
		var target := atan2(local_velocity.x, local_velocity.y)
		# Snap when the layer just came in; turn smoothly while it plays.
		legs.direction = target if not was_active else lerp_angle(legs.direction, target, 1.0 - exp(-LEGS_TURN_RATE * delta))
	legs.phase = fposmod(legs.phase + delta * speed / legs.cycle_distance(), 1.0)


## Weight of the walking legs under the current action (0 = the action's own legs).
func get_legs_weight() -> float:
	return legs.influence if legs != null and is_instance_valid(legs) and legs.active else 0.0


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

## Rebuild weapon / off-hand attachments and the armour pieces from the character's equipment.
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
	if main != null:
		_attach("grip_r", main)
	if off != null:
		_attach("chest" if off.get_weapon_type() == "quiver" else "grip_l", off)
	var worn := {}
	if character != null:
		for slot in PlayerGear.SLOT_PIECES:
			var it: Item = character.get_equipped(String(slot))
			if it != null:
				worn[String(slot)] = it
	_show_gear(worn)
	if _flash > 0.0:
		Assets.set_flash(model, _flash, HIT_FLASH_COLOR)


## Show the pieces for `worn` (equipment slot -> Item), hide every other piece and the base parts
## the shown pieces cover, tint the shown pieces.
func _show_gear(worn: Dictionary) -> void:
	gear_pieces.clear()
	var hidden := {}
	for slot in worn:
		var piece := PlayerGear.piece_for(String(slot), worn[slot])
		if piece == "" or not parts.has(piece):
			continue
		gear_pieces[slot] = piece
		for h in PlayerGear.hides_of(piece):
			hidden[String(h)] = true
	var shown := {}
	for slot in gear_pieces:
		shown[gear_pieces[slot]] = slot
	for n in parts:
		var mi: MeshInstance3D = parts[n]
		if not is_instance_valid(mi):
			continue
		mi.visible = shown.has(n) if PlayerGear.is_piece(n) else not hidden.has(n)
	for slot in gear_pieces:
		Assets.tint(model, (worn[slot] as Item).get_tint(), PackedStringArray([gear_pieces[slot]]))


## The visible mesh part names (tests / previews).
func get_visible_parts() -> Array[String]:
	var out: Array[String] = []
	for n in parts:
		var mi: MeshInstance3D = parts[n]
		if is_instance_valid(mi) and mi.visible:
			out.append(String(n))
	out.sort()
	return out


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


## The attached model for a bone ("grip_r", "grip_l", "chest") or null.
func get_attachment(bone: String) -> Node3D:
	var n: Variant = attachments.get(bone)
	return n if is_instance_valid(n) else null

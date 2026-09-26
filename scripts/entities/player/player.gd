class_name Player
extends Actor
## The player character: input (WASD move, mouse aim, 6 skill slots, dodge, potions, click to
## pick up / interact), stats from CharacterData, animated model with gear visuals.
## Group "player". Collision layer 2. OWNER: player (wave 2).
## CONTRACT — keep every public member/signature. See docs/ARCHITECTURE.md §11.
##
## Behaviour (§11.3):
##   Input      keyboard actions start in _unhandled_input (never _input); mouse-bound skills only
##              start from a press received there while not UI.is_mouse_over_ui(); a pressed slot
##              counts as held while Input.is_action_pressed(action). Polled movement / skill keys
##              are skipped while a LineEdit has focus. While ai_control is true real input is
##              ignored and the ai_* methods drive the same code paths (calling ai_move / ai_aim /
##              ai_hold_skill / ai_interact / ai_dodge / ai_town_portal turns ai_control on).
##   Move       WASD in screen space (screen-up = world -Z): dir × get_move_speed() ×
##              skill_runner.movement_multiplier() + knockback_velocity; faces the movement
##              direction (smoothly) unless a skill is in use.
##   Aim/hover  camera_rig.get_mouse_ground_position(); hovering a hostile actor targets it (the
##              skill aims at its position). Hover changes call set_hovered() on Interactables (and
##              on any hovered node with that method, e.g. Enemy) and emit
##              Events.hovered_target_changed.
##   Skills     holding a slot calls skill_runner.try_use(slot skill, aim, target) whenever the
##              runner is not busy (repeat while held), update_target() while held and busy with
##              it, release() on key up. A tap (press + release before the next physics tick) or a
##              press while busy is buffered for INPUT_BUFFER_TIME. LMB on a hovered GroundItem /
##              Interactable auto-walks there (world.find_path) and calls interact(self); WASD or
##              another skill cancels the walk.
##   Dodge      6 m over 0.35 s toward the move dir (or the aim), 0.3 s i-frames, 1.2 s cooldown,
##              passes through enemies, cancels skills / portal cast / auto-walk, anim "dodge".
##   Potions    life 40% of max life, mana 50% of max mana over 1.5 s (× potion_effect); one charge
##              each; not while the same potion is active; charges from Events.enemy_killed.
##   Portal     T in a dungeon: 1 s rooted "cast" (cancelled by dodge, freeze, death) ->
##              Events.town_portal_requested. Ignored in town. A press while a skill finishes is
##              retried for INPUT_BUFFER_TIME.
##   Stats      get_base_mods / get_all_mods per §5 + dungeon resist penalty; recalculated on
##              equipment_changed / passives_changed / level_up; every recalculation emits
##              Events.player_stats_changed. Level up: full heal, ring VFX, sound, notification.
##   Death      Events.player_died, anim "die", input off.
##   Visuals    PlayerVisuals (model, animations, gear, flash) under the child "Visuals", drawn
##              interpolated between physics ticks (get_visual_position(); the camera follows it).
##
## Extra API for the HUD / flow / bot (beyond the contract): get_aim_position, get_aim_target,
## is_auto_walking, get_auto_walk_target, cancel_auto_walk, is_slot_held, get_resist_penalty,
## is_potion_active, get_potion_active_ratio, get_dodge_cooldown_ratio, can_dodge,
## start_town_portal, request_town_portal, cancel_town_portal, is_casting_portal,
## get_portal_cast_ratio, is_in_dungeon, get_visual_position, ai_town_portal, ai_release_all,
## ai_stop, ai_release_control.

const PlayerVisuals := preload("res://scripts/entities/player/player_visuals.gd")
const PlayerFx := preload("res://scripts/entities/player/player_fx.gd")

const COLLISION_LAYER := 2
const COLLISION_MASK := 5
## While dodging the player only collides with the world (rolls through monsters).
const DODGE_COLLISION_MASK := 1
const CAPSULE_RADIUS := 0.4
const CAPSULE_HEIGHT := 1.8

const DODGE_DISTANCE := 6.0
const DODGE_TIME := 0.35
const DODGE_IFRAMES := 0.3
const DODGE_COOLDOWN := 1.2

const POTION_DURATION := 1.5
const LIFE_POTION_FRACTION := 0.4
const MANA_POTION_FRACTION := 0.5
## Potion charges gained per kill by monster rarity (normal, magic, rare, boss).
const POTION_CHARGES_PER_KILL: Array[float] = [0.25, 0.5, 1.0, 3.0]

const PORTAL_CAST_TIME := 1.0

const EXPLORE_INTERVAL := 0.25
const EXPLORE_RADIUS := 14.0
## Hits >= this fraction of max life play the "hit" flinch (when not busy).
const HIT_ANIM_THRESHOLD := 0.10
## Hits > this fraction of max life shake the camera.
const SHAKE_THRESHOLD := 0.15
## Facing smoothing toward the movement direction (1/s, exponential).
const TURN_RATE := 18.0
## A skill press that could not start yet (busy, dodging, tapped between physics ticks) is retried
## for this long.
const INPUT_BUFFER_TIME := 0.3
const WALK_REPATH_TIME := 0.6
const WALK_WAYPOINT_REACHED := 0.35
## Auto-walk gives up after this long without getting closer.
const WALK_STUCK_TIME := 1.5
## Visual interpolation between physics ticks is skipped for jumps longer than this (teleports).
const INTERP_MAX_STEP := 1.5
const MESSAGE_THROTTLE := 1.0
const LIGHT_COLOR := Color(1.0, 0.8, 0.55)
const LIGHT_ENERGY := 1.2
const LIGHT_ENERGY_TOWN := 0.55
const LIGHT_RANGE := 10.0

var character: CharacterData = null
## Set by the game flow right after spawning.
var camera_rig: CameraRig = null
## True while a dodge roll is in progress.
var dodging: bool = false
## Programmatic control (autoplay bot, tests, demos). While true, keyboard/mouse input is ignored
## and the ai_* methods drive the player through the same code paths as input.
var ai_control: bool = false

## Visual helper (model, animations, gear). See player_visuals.gd.
var visuals: PlayerVisuals = null
## The char_player model instance and its AnimationPlayer (null for placeholders).
var model: Node3D = null
var anim_player: AnimationPlayer = null
## Warm shadowless light above the player.
var light: OmniLight3D = null

var _move_input := Vector3.ZERO
var _ai_move := Vector3.ZERO
var _ai_aim_pos := Vector3.ZERO
var _ai_aim_target: Variant = null
var _has_ai_aim := false
var _aim_pos := Vector3.ZERO
var _aim_target: Actor = null
var _hovered: Node = null
## Instance id of _hovered (0 = none). Survives the node being freed, so the change is reported.
var _hovered_id := 0

var _held: Array[bool] = [false, false, false, false, false, false]
var _held_by_ai: Array[bool] = [false, false, false, false, false, false]
## Seconds left during which a press is retried even if the key is no longer held (0 = none).
var _pending: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## Pressed slots, most recent last.
var _press_order: Array[int] = []

var _dodge_left := 0.0
var _dodge_dir := Vector3.FORWARD
var _dodge_cooldown := 0.0

## kind -> {"left": float, "duration": float, "rate": float}
var _potions: Dictionary = {}

var _portal_left := 0.0
var _portal_fx: Node3D = null
## A T press that could not start the cast yet (busy) is retried for INPUT_BUFFER_TIME.
var _portal_request := 0.0

var _walk_target: Interactable = null
var _walk_path := PackedVector3Array()
var _walk_index := 0
var _walk_repath := 0.0
var _walk_stuck := 0.0

var _explore_timer := 0.0
var _hurt_sound_cd := 0.0
var _anim_speed := 0.0
var _messages: Dictionary = {}
## Positions at the last two physics ticks (visual interpolation on high refresh rate screens).
var _phys_prev := Vector3.ZERO
var _phys_cur := Vector3.ZERO
var _interp_ready := false


func _init() -> void:
	team = Team.PLAYER
	base_move_speed = Balance.PLAYER_BASE_MOVE_SPEED
	collision_layer = COLLISION_LAYER
	collision_mask = COLLISION_MASK
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	add_child(cs)


## Bind to character data (sets level = data.level, team). Call before adding to the tree.
## camera_rig is null during _ready (the game flow sets it right after).
func setup(data: CharacterData) -> void:
	character = data
	team = Team.PLAYER
	if data != null:
		level = data.level
		display_name = data.char_name


func _ready() -> void:
	if character == null:
		if GameState.character != null:
			push_warning("Player: setup() was not called; using GameState.character")
			setup(GameState.character)
		else:
			push_warning("Player: no character data; using a fresh warrior")
			setup(CharacterData.new())
	super._ready()
	add_to_group("player")
	if skill_runner == null:
		skill_runner = SkillRunner.new()
	if skill_runner.actor != self:
		skill_runner.setup(self)
	if skill_runner.get_parent() == null:
		skill_runner.name = "SkillRunner"
		add_child(skill_runner)
	visuals = PlayerVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	visuals.build()
	model = visuals.model
	anim_player = visuals.anim
	refresh_equipment_visuals()
	_build_light()
	StatusVisuals.attach(self)
	stats_recalculated.connect(_on_stats_recalculated)
	damaged.connect(_on_damaged)
	ailment_changed.connect(_on_ailment_changed)
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.passives_changed.connect(_on_passives_changed)
	Events.level_up.connect(_on_level_up)
	Events.enemy_killed.connect(_on_enemy_killed)
	# The resist penalty depends on the World we were added to.
	recalculate_stats()
	_aim_pos = global_position + get_forward() * 4.0


func _exit_tree() -> void:
	if _hovered_id != 0 and is_instance_valid(_hovered) and _hovered.has_method("set_hovered"):
		_hovered.call("set_hovered", false)
	_hovered = null
	_hovered_id = 0


func _process(delta: float) -> void:
	if visuals != null:
		visuals.update(delta, _anim_speed, is_frozen())
		_interpolate_visuals()


## Where the player is drawn this frame: the physics position interpolated between the last two
## physics ticks (smooth motion when the screen refreshes faster than the 60 Hz physics). The
## camera follows this point. Independent of the _process order of the player and the camera.
func get_visual_position() -> Vector3:
	if not is_inside_tree():
		return position
	if get_tree().physics_interpolation:
		return get_global_transform_interpolated().origin
	return global_position + _interp_offset()


## World-space XZ offset from the physics position to the interpolated draw position.
func _interp_offset() -> Vector3:
	if not _interp_ready or dead or get_tree().physics_interpolation:
		return Vector3.ZERO
	var gp := global_position
	# Moved outside the physics step (teleport, respawn placement) or a long jump: no smoothing.
	if gp.distance_squared_to(_phys_cur) > 0.0001 or _phys_prev.distance_squared_to(_phys_cur) > INTERP_MAX_STEP * INTERP_MAX_STEP:
		return Vector3.ZERO
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var p := _phys_prev.lerp(_phys_cur, f)
	return Vector3(p.x - gp.x, 0.0, p.z - gp.z)


## Offset the Visuals node (XZ only: the Y offset belongs to leap arcs, see SkillMover) so the
## model is drawn at get_visual_position(). Disabled when the engine's own physics interpolation
## is on (it would double up).
func _interpolate_visuals() -> void:
	if not is_inside_tree():
		return
	var off := global_transform.basis.inverse() * _interp_offset()
	visuals.position.x = off.x
	visuals.position.z = off.z


func _record_physics_position() -> void:
	var gp := global_position
	if not _interp_ready:
		_phys_prev = gp
		_interp_ready = true
	else:
		_phys_prev = _phys_cur
	_phys_cur = gp


# ------------------------------------------------------------------ public API (contract)

## Skill id in bar slot 0..5 ("" if empty).
func get_skill_in_slot(slot: int) -> String:
	if character == null or slot < 0 or slot >= character.skill_bar.size():
		return ""
	return character.skill_bar[slot]


## kind "life" | "mana". Returns false if no charge / already full.
## Also false (with a message) while the same potion's heal-over-time is still running.
func use_potion(kind: String) -> bool:
	if dead or character == null or not (kind == "life" or kind == "mana"):
		return false
	if _potions.has(kind):
		_message("Potion already active")
		return false
	var pool := max_life if kind == "life" else max_mana
	var current := life if kind == "life" else mana
	if pool <= 0.0 or current >= pool - 0.001:
		_message("Life is already full" if kind == "life" else "Mana is already full", UIStyle.COLOR_TEXT_DIM)
		return false
	if not character.consume_potion_charge(kind):
		_message("No %s potion charges" % kind)
		return false
	var fraction := LIFE_POTION_FRACTION if kind == "life" else MANA_POTION_FRACTION
	var total := pool * fraction * maxf(0.0, 1.0 + stats.inc("potion_effect") / 100.0) * stats.more("potion_effect")
	_potions[kind] = {"left": POTION_DURATION, "duration": POTION_DURATION, "rate": total / POTION_DURATION}
	Sfx.play("potion", _gpos())
	if is_inside_tree():
		PlayerFx.potion(self, kind)
	return true


## Re-apply equipment visuals (weapon in hand, helmet, armour tints).
func refresh_equipment_visuals() -> void:
	if visuals != null:
		visuals.apply_equipment(character)


## Current mouse-over target (Enemy / Interactable) or null.
func get_hovered() -> Node:
	if _hovered_id != 0 and is_instance_valid(_hovered):
		return _hovered
	return null


## Current attribute totals {"strength": x, "dexterity": y, "intelligence": z} (for item
## requirement checks in UI).
func get_attributes() -> Dictionary:
	return {
		"strength": float(attributes.get("strength", 0.0)),
		"dexterity": float(attributes.get("dexterity", 0.0)),
		"intelligence": float(attributes.get("intelligence", 0.0)),
	}


# ------------------------------------------------------------------ programmatic control

## Move in world XZ direction (length <= 1); Vector3.ZERO stops.
func ai_move(dir: Vector3) -> void:
	ai_control = true
	var d := Vector3(dir.x, 0.0, dir.z)
	_ai_move = d.limit_length(1.0)


## Aim at a world position (and optional target actor) instead of the mouse.
## The target may also be an Interactable (it gets hovered like under the mouse).
func ai_aim(pos: Vector3, target: Node = null) -> void:
	ai_control = true
	_ai_aim_pos = Vector3(pos.x, 0.0, pos.z)
	_ai_aim_target = target
	_has_ai_aim = true


## Same path as holding / releasing the skill key of bar slot 0..5.
func ai_hold_skill(slot: int, held: bool) -> void:
	ai_control = true
	if slot < 0 or slot >= _held.size():
		return
	if held:
		_press_slot(slot, true)
	else:
		_release_slot(slot)


## Walk to the interactable (world.find_path) and interact() when in range.
func ai_interact(target: Interactable) -> void:
	ai_control = true
	_start_auto_walk(target)


func ai_dodge(dir: Vector3) -> void:
	ai_control = true
	_try_dodge(dir)


func ai_use_potion(kind: String) -> bool:
	return use_potion(kind)


## Same path as pressing T. True if the cast started now (a press while busy is retried briefly).
func ai_town_portal() -> bool:
	ai_control = true
	return request_town_portal()


## Release every held skill slot.
func ai_release_all() -> void:
	for i in _held.size():
		_release_slot(i)
		_pending[i] = 0.0


## Stop moving, release every skill and cancel the auto-walk.
func ai_stop() -> void:
	_ai_move = Vector3.ZERO
	ai_release_all()
	_cancel_auto_walk()


## Hand control back to the keyboard / mouse (stops everything the ai_* calls started).
func ai_release_control() -> void:
	ai_stop()
	_has_ai_aim = false
	_ai_aim_target = null
	ai_control = false


# ------------------------------------------------------------------ extra public API

## Where skills are aimed right now (hovered enemy's position or the mouse / ai ground point).
func get_aim_position() -> Vector3:
	return _aim_pos


## Hovered hostile actor that skills target (null if none).
func get_aim_target() -> Actor:
	return _aim_target if _aim_target != null and is_instance_valid(_aim_target) else null


## True while walking to a clicked GroundItem / Interactable.
func is_auto_walking() -> bool:
	return _walk_target != null and is_instance_valid(_walk_target)


func get_auto_walk_target() -> Interactable:
	return _walk_target if is_auto_walking() else null


## Stop an auto-walk (WASD does this).
func cancel_auto_walk() -> void:
	_cancel_auto_walk()


func is_slot_held(slot: int) -> bool:
	return slot >= 0 and slot < _held.size() and _held[slot]


## Resistance penalty applied right now (negative, 0 outside dungeons) — character sheet.
func get_resist_penalty() -> float:
	var info := _area_info()
	if String(info.get("id", "")) != "dungeon":
		return 0.0
	var lvl := int(info.get("level", Balance.area_level_for_depth(int(info.get("depth", 1)))))
	return Balance.resist_penalty(lvl)


## True while a potion of this kind is healing.
func is_potion_active(kind: String) -> bool:
	return _potions.has(kind)


## Remaining fraction (1 → 0) of the running potion of this kind, 0 when none (HUD sweep).
func get_potion_active_ratio(kind: String) -> float:
	if not _potions.has(kind):
		return 0.0
	var p: Dictionary = _potions[kind]
	return clampf(float(p["left"]) / maxf(0.001, float(p["duration"])), 0.0, 1.0)


## 0 = dodge ready, 1 = just used.
func get_dodge_cooldown_ratio() -> float:
	return clampf(_dodge_cooldown / DODGE_COOLDOWN, 0.0, 1.0)


func can_dodge() -> bool:
	return not dead and can_act() and not dodging and _dodge_cooldown <= 0.0


## Start the Town Portal cast (T). False when not in a dungeon, dead, frozen, busy or dodging.
func start_town_portal() -> bool:
	if dead or not can_act() or dodging or is_casting_portal():
		return false
	if not is_in_dungeon():
		return false
	if skill_runner != null and is_instance_valid(skill_runner) and skill_runner.is_busy():
		return false
	_cancel_auto_walk()
	_portal_left = PORTAL_CAST_TIME
	play_action_animation("cast", PORTAL_CAST_TIME)
	Sfx.play("spell_cast", _gpos())
	if is_inside_tree():
		_portal_fx = PlayerFx.portal_cast(self, PORTAL_CAST_TIME)
	return true


## The T key: start the cast, or retry it for INPUT_BUFFER_TIME while a skill is finishing.
## Returns true if the cast started right away.
func request_town_portal() -> bool:
	if start_town_portal():
		_portal_request = 0.0
		return true
	if not dead and is_in_dungeon() and not is_casting_portal():
		_portal_request = INPUT_BUFFER_TIME
	return false


func cancel_town_portal() -> void:
	_portal_request = 0.0
	if _portal_left <= 0.0:
		return
	_portal_left = 0.0
	if _portal_fx != null and is_instance_valid(_portal_fx):
		_portal_fx.queue_free()
	_portal_fx = null
	if visuals != null and visuals.action_anim == "cast":
		stop_action_animation()


func is_casting_portal() -> bool:
	return _portal_left > 0.0


## 0..1 progress of the Town Portal cast (0 when not casting).
func get_portal_cast_ratio() -> float:
	return 1.0 - _portal_left / PORTAL_CAST_TIME if _portal_left > 0.0 else 0.0


## True in a dungeon area (Town Portal allowed, resist penalty applies).
func is_in_dungeon() -> bool:
	return String(_area_info().get("id", "")) == "dungeon"


# ------------------------------------------------------------------ Actor overrides

func get_base_mods() -> Array:
	var mods: Array = [
		StatBlock.mod("max_life", "flat", Balance.player_base_life(level)),
		StatBlock.mod("max_mana", "flat", Balance.player_base_mana(level)),
		StatBlock.mod("evasion", "flat", Balance.PLAYER_BASE_EVASION),
	]
	if character != null:
		mods.append_array(ClassDefs.get_attribute_mods(character.class_id))
	return mods


func get_all_mods() -> Array:
	var mods := get_base_mods()
	if character != null:
		mods.append_array(character.get_equipment_mods())
		mods.append_array(TreeDB.get_mods(character.allocated_passives, character.class_id))
	var pen := get_resist_penalty()
	if pen != 0.0:
		mods.append(StatBlock.mod("elemental_resistance", "flat", pen))
		mods.append(StatBlock.mod("chaos_resistance", "flat", pen))
	return mods


func get_weapon() -> Dictionary:
	if character != null:
		var main: Item = character.get_equipped("main_hand")
		if main != null:
			var w := main.get_weapon_stats()
			if not w.is_empty():
				return w
	return DamageCalc.UNARMED.duplicate(true)


func play_action_animation(anim: String, duration: float) -> void:
	if dead or visuals == null:
		return
	visuals.play_action(anim, duration)


func stop_action_animation() -> void:
	if dead or visuals == null:
		return
	visuals.stop_action()


func _on_death(_killer: Node) -> void:
	if dodging:
		_end_dodge()
	cancel_town_portal()
	_cancel_auto_walk()
	for i in _held.size():
		_held[i] = false
		_pending[i] = 0.0
	_press_order.clear()
	_potions.clear()
	_set_hovered(null)
	_aim_target = null
	velocity = Vector3.ZERO
	_anim_speed = 0.0
	if visuals != null:
		visuals.play_death()
	Sfx.play("player_die", _gpos())
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.shake(0.35, 0.4)
	Events.player_died.emit()


# ------------------------------------------------------------------ physics

func _actor_physics(delta: float) -> void:
	if dead:
		velocity = Vector3.ZERO
		_anim_speed = 0.0
		_record_physics_position()
		return
	if _dodge_cooldown > 0.0:
		_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	if _hurt_sound_cd > 0.0:
		_hurt_sound_cd -= delta
	for i in _pending.size():
		if _pending[i] > 0.0:
			_pending[i] = maxf(0.0, _pending[i] - delta)
	_update_potions(delta)
	if dead:
		return
	if not ai_control:
		_poll_input()
	_update_hover_and_aim()
	if _portal_request > 0.0:
		_portal_request = maxf(0.0, _portal_request - delta)
		if start_town_portal():
			_portal_request = 0.0
	_update_portal(delta)
	_update_movement(delta)
	_record_physics_position()
	if dead or not is_inside_tree():
		return
	_update_skills()
	_update_explore(delta)


func _poll_input() -> void:
	var typing := false
	var vp := get_viewport()
	if vp != null:
		typing = vp.gui_get_focus_owner() is LineEdit
	if typing:
		_move_input = Vector3.ZERO
	else:
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		_move_input = Vector3(v.x, 0.0, v.y)
	for i in _held.size():
		if not _held[i] or _held_by_ai[i]:
			continue
		var action: String = Controls.SKILL_ACTIONS[i]
		var still := Input.is_action_pressed(action)
		if typing and not _is_mouse_action(action):
			still = false
		if not still:
			_release_slot(i)


func _unhandled_input(event: InputEvent) -> void:
	if ai_control or dead or not is_inside_tree():
		return
	if event is InputEventKey and (event as InputEventKey).is_echo():
		return
	if not event.is_pressed():
		return
	var is_mouse := event is InputEventMouseButton
	if is_mouse and UI.is_mouse_over_ui():
		return
	for i in Controls.SKILL_ACTIONS.size():
		if event.is_action_pressed(Controls.SKILL_ACTIONS[i]):
			if i == 0 and is_mouse and _click_interact():
				get_viewport().set_input_as_handled()
				return
			_press_slot(i, false)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("dodge"):
		var dir := _move_input if _move_input.length_squared() > 0.0001 else Vector3.ZERO
		_try_dodge(dir)
	elif event.is_action_pressed("potion_life"):
		use_potion("life")
	elif event.is_action_pressed("potion_mana"):
		use_potion("mana")
	elif event.is_action_pressed("town_portal"):
		request_town_portal()
	else:
		return
	get_viewport().set_input_as_handled()


func _is_mouse_action(action: String) -> bool:
	var b: Array = Controls.BINDINGS.get(action, [])
	return not b.is_empty() and int(b[0]) < 16


## LMB on a hovered GroundItem / Interactable: walk there instead of using skill 1.
func _click_interact() -> bool:
	var h := get_hovered()
	if h is Interactable and (h as Interactable).can_interact(self):
		_start_auto_walk(h as Interactable)
		return true
	return false


func _update_hover_and_aim() -> void:
	var ground := _aim_pos
	var hover: Node = null
	if ai_control:
		if _has_ai_aim:
			ground = _ai_aim_pos
			if _ai_aim_target != null and is_instance_valid(_ai_aim_target) and _ai_aim_target is Node:
				hover = _ai_aim_target as Node
	elif camera_rig != null and is_instance_valid(camera_rig) and camera_rig.is_inside_tree():
		ground = camera_rig.get_mouse_ground_position(0.0)
		hover = camera_rig.get_hover_target()
	if hover is Actor and ((hover as Actor).dead or not (hover as Node).is_inside_tree()):
		hover = null
	if hover is Interactable and not (hover as Interactable).enabled:
		hover = null
	_set_hovered(hover)
	if hover is Actor and CombatQuery.is_hostile(self, hover):
		_aim_target = hover as Actor
		var tp := _aim_target.global_position
		_aim_pos = Vector3(tp.x, 0.0, tp.z)
	else:
		_aim_target = null
		_aim_pos = Vector3(ground.x, 0.0, ground.z)


func _set_hovered(n: Node) -> void:
	var new_id := n.get_instance_id() if n != null and is_instance_valid(n) else 0
	if new_id == _hovered_id:
		return
	# The previous node may have been freed since (loot picked up, corpse removed).
	var old: Node = _hovered if _hovered_id != 0 and is_instance_valid(_hovered) else null
	_hovered = n if new_id != 0 else null
	_hovered_id = new_id
	# Interactables highlight themselves; enemies may offer the same hook (rim highlight).
	if old != null and old.has_method("set_hovered"):
		old.call("set_hovered", false)
	if _hovered != null and _hovered.has_method("set_hovered"):
		_hovered.call("set_hovered", true)
	Events.hovered_target_changed.emit(_hovered)


func _update_movement(delta: float) -> void:
	var v := Vector3.ZERO
	var runner_ok := skill_runner != null and is_instance_valid(skill_runner)
	if dodging:
		var dt := minf(delta, _dodge_left)
		var mid := 1.0 - (_dodge_left - dt * 0.5) / DODGE_TIME   # progress at the step's midpoint
		var speed := DODGE_DISTANCE / DODGE_TIME * (1.5 - mid)
		v = _dodge_dir * speed * (dt / maxf(delta, 0.00001))
		_dodge_left -= delta
		if _dodge_left <= 0.00001:
			_end_dodge()
	elif not can_act():
		v = Vector3.ZERO
	elif is_casting_portal():
		v = knockback_velocity
	else:
		var dir := _ai_move if ai_control else _move_input
		if dir.length_squared() > 0.0001:
			if is_auto_walking():
				_cancel_auto_walk()
		elif is_auto_walking():
			dir = _auto_walk_dir(delta)
			if dead or not is_inside_tree():
				return
		dir = dir.limit_length(1.0)
		var mult := skill_runner.movement_multiplier() if runner_ok else 1.0
		v = dir * get_move_speed() * mult
		var busy := runner_ok and skill_runner.is_busy()
		if dir.length_squared() > 0.0001 and not busy and mult > 0.0:
			var want := atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_RATE * delta))
		v += knockback_velocity
	velocity = Vector3(v.x, 0.0, v.z)
	move_and_slide()
	if absf(position.y) > 0.0001:
		position.y = 0.0
	var rv := get_real_velocity()
	_anim_speed = Vector2(rv.x, rv.z).length() if not dodging else 0.0


func _update_explore(delta: float) -> void:
	_explore_timer -= delta
	if _explore_timer > 0.0:
		return
	_explore_timer = EXPLORE_INTERVAL
	var w := _get_world()
	if w != null:
		w.mark_explored(global_position, EXPLORE_RADIUS)


# ------------------------------------------------------------------ skills

func _press_slot(slot: int, by_ai: bool) -> void:
	if dead:
		return
	_held[slot] = true
	_held_by_ai[slot] = by_ai
	_pending[slot] = INPUT_BUFFER_TIME
	_press_order.erase(slot)
	_press_order.append(slot)
	if is_auto_walking():
		_cancel_auto_walk()


func _release_slot(slot: int) -> void:
	if not _held[slot]:
		return
	_held[slot] = false
	_held_by_ai[slot] = false
	if _pending[slot] <= 0.0:
		_press_order.erase(slot)
	var id := get_skill_in_slot(slot)
	if id != "" and skill_runner != null and is_instance_valid(skill_runner):
		skill_runner.release(id)


## Most recently pressed slot that is held or still has a buffered press (-1 if none).
func _active_slot() -> int:
	var i := _press_order.size() - 1
	while i >= 0:
		var s := _press_order[i]
		if _held[s] or _pending[s] > 0.0:
			return s
		_press_order.remove_at(i)
		i -= 1
	return -1


func _update_skills() -> void:
	if skill_runner == null or not is_instance_valid(skill_runner):
		return
	if not can_act() or dodging or is_casting_portal():
		return
	var slot := _active_slot()
	if slot < 0:
		return
	var id := get_skill_in_slot(slot)
	if id == "":
		_pending[slot] = 0.0
		return
	if skill_runner.is_busy():
		if _held[slot] and skill_runner.get_current_skill() == id:
			skill_runner.update_target(_aim_pos, get_aim_target())
		return
	var started := skill_runner.try_use(id, _aim_pos, get_aim_target())
	_pending[slot] = 0.0
	if not _held[slot]:
		_press_order.erase(slot)
		if started:
			# A tap: one use; stop channels right away.
			skill_runner.release(id)


# ------------------------------------------------------------------ dodge

func _try_dodge(dir: Vector3) -> bool:
	if not can_dodge():
		return false
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		d = _aim_pos - global_position
		d.y = 0.0
	if d.length_squared() < 0.0001:
		d = get_forward()
		d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3.BACK
	d = d.normalized()
	if skill_runner != null and is_instance_valid(skill_runner):
		skill_runner.cancel()
	cancel_town_portal()
	_cancel_auto_walk()
	dodging = true
	_dodge_left = DODGE_TIME
	_dodge_dir = d
	_dodge_cooldown = DODGE_COOLDOWN
	invulnerable_time = maxf(invulnerable_time, DODGE_IFRAMES)
	collision_mask = DODGE_COLLISION_MASK
	rotation.y = atan2(d.x, d.z)
	play_action_animation("dodge", DODGE_TIME)
	Sfx.play("swing", _gpos(), -4.0)
	if is_inside_tree():
		PlayerFx.dodge_dust(get_parent(), global_position, d)
	return true


func _end_dodge() -> void:
	dodging = false
	_dodge_left = 0.0
	if not dead:
		collision_mask = COLLISION_MASK
	if visuals != null and visuals.action_anim == "dodge":
		stop_action_animation()


# ------------------------------------------------------------------ potions

func _update_potions(delta: float) -> void:
	if _potions.is_empty():
		return
	for kind in _potions.keys():
		var p: Dictionary = _potions[kind]
		var dt := minf(delta, float(p["left"]))
		var amount := float(p["rate"]) * dt
		if kind == "life":
			heal(amount)
		else:
			restore_mana(amount)
		p["left"] = float(p["left"]) - delta
		if float(p["left"]) <= 0.00001:
			_potions.erase(kind)


func _on_enemy_killed(enemy: Node) -> void:
	if dead or character == null or not is_inside_tree():
		return
	if GameState.player != null and is_instance_valid(GameState.player) and GameState.player != self:
		return
	var r := 0
	if enemy != null and is_instance_valid(enemy):
		var rv: Variant = enemy.get("rarity")
		if rv is int or rv is float:
			r = int(rv)
		if enemy.get("is_boss") == true or enemy.is_in_group("boss"):
			r = 3
	character.add_potion_charges(POTION_CHARGES_PER_KILL[clampi(r, 0, POTION_CHARGES_PER_KILL.size() - 1)])


# ------------------------------------------------------------------ town portal

func _update_portal(delta: float) -> void:
	if _portal_left <= 0.0:
		return
	_portal_left -= delta
	if _portal_left > 0.00001:
		return
	_portal_left = 0.0
	PlayerFx.portal_burst(_portal_fx)
	_portal_fx = null
	if visuals != null and visuals.action_anim == "cast":
		stop_action_animation()
	Sfx.play("portal", _gpos())
	Events.town_portal_requested.emit()


# ------------------------------------------------------------------ auto-walk

func _start_auto_walk(target: Interactable) -> void:
	if dead or target == null or not is_instance_valid(target):
		return
	if is_casting_portal():
		return
	_walk_target = target
	_walk_path = PackedVector3Array()
	_walk_index = 0
	_walk_repath = 0.0
	_walk_stuck = 0.0


func _cancel_auto_walk() -> void:
	_walk_target = null
	_walk_path = PackedVector3Array()
	_walk_index = 0


## Direction to walk this frame (may interact and stop).
func _auto_walk_dir(delta: float) -> Vector3:
	var t := _walk_target
	if t == null or not is_instance_valid(t) or not t.is_inside_tree() or not t.can_interact(self):
		_cancel_auto_walk()
		return Vector3.ZERO
	var goal := t.get_interact_position()
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	if dist <= t.get_interact_range():
		_cancel_auto_walk()
		if dist > 0.05:
			face_towards(goal)
		t.interact(self)
		return Vector3.ZERO
	# Give up when blocked for a while (unreachable target, pushed against a wall). Time rooted by
	# a skill does not count.
	var rooted := skill_runner != null and is_instance_valid(skill_runner) and skill_runner.movement_multiplier() <= 0.01
	var rv := get_real_velocity()
	if rooted or Vector2(rv.x, rv.z).length() > get_move_speed() * 0.25:
		_walk_stuck = 0.0
	else:
		_walk_stuck += delta
		if _walk_stuck > WALK_STUCK_TIME:
			_cancel_auto_walk()
			return Vector3.ZERO
	var w := _get_world()
	if w == null:
		return to_goal / dist
	# find_path returns just [goal] when the straight line is walkable (with clearance), else
	# string-pulled waypoints around walls and pillars. Re-path now and then (things move).
	_walk_repath -= delta
	if _walk_path.is_empty() or _walk_repath <= 0.0:
		_walk_path = w.find_path(global_position, goal)
		_walk_index = 0
		_walk_repath = WALK_REPATH_TIME
	while _walk_index < _walk_path.size():
		var wp := _walk_path[_walk_index] - global_position
		wp.y = 0.0
		# The last waypoint is the (snapped) goal: head for it until in interact range.
		if wp.length() > WALK_WAYPOINT_REACHED or _walk_index == _walk_path.size() - 1:
			if wp.length() > 0.05:
				return wp.normalized()
		_walk_index += 1
	return to_goal / dist


# ------------------------------------------------------------------ reactions

func _on_stats_recalculated() -> void:
	Events.player_stats_changed.emit()


func _on_equipment_changed(_slot: String) -> void:
	recalculate_stats()
	refresh_equipment_visuals()


func _on_passives_changed() -> void:
	recalculate_stats()


func _on_level_up(new_level: int) -> void:
	if character == null:
		return
	level = character.level
	recalculate_stats()
	# add_xp() emits once per level gained, after the whole amount was applied: celebrate once.
	if new_level != character.level or dead:
		return
	refill_pools()
	if GameState.player != null and is_instance_valid(GameState.player) and GameState.player != self:
		return
	if is_inside_tree():
		PlayerFx.level_up(self)
	Sfx.play("level_up", _gpos())
	Events.notify.emit("Level %d" % new_level, UIStyle.COLOR_GOLD)


func _on_damaged(amount: float, _is_crit: bool, _source: Node) -> void:
	if dead or max_life <= 0.0:
		if visuals != null:
			visuals.flash(0.6)
		return
	var ratio := amount / max_life
	if visuals != null:
		visuals.flash(clampf(0.35 + ratio * 2.0, 0.35, 0.8))
		if ratio >= HIT_ANIM_THRESHOLD and not _is_busy_for_flinch():
			visuals.play_reaction("hit", 0.3)
	if ratio > SHAKE_THRESHOLD and camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.shake(clampf(0.1 + ratio * 0.6, 0.15, 0.45), 0.28)
	if _hurt_sound_cd <= 0.0 and ratio >= 0.03:
		_hurt_sound_cd = 0.35
		Sfx.play("player_hurt", _gpos())


func _is_busy_for_flinch() -> bool:
	if dodging or is_casting_portal() or _anim_speed > 0.5:
		return true
	if skill_runner != null and is_instance_valid(skill_runner) and skill_runner.is_busy():
		return true
	return visuals != null and visuals.action_anim != ""


func _on_ailment_changed(kind: String, active: bool) -> void:
	if kind == "freeze" and active:
		cancel_town_portal()
		_cancel_auto_walk()


# ------------------------------------------------------------------ helpers

func _build_light() -> void:
	light = OmniLight3D.new()
	light.name = "PlayerLight"
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY_TOWN if String(_area_info().get("id", "")) == "town" else LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.omni_attenuation = 1.1
	light.shadow_enabled = false
	light.light_specular = 0.25
	light.position = Vector3(0, 3.0, 0)
	add_child(light)


## The World this player is in (ancestor), else GameState.world.
func _get_world() -> World:
	var n := get_parent()
	while n != null:
		if n is World:
			return n as World
		n = n.get_parent()
	var w := GameState.world
	if w != null and is_instance_valid(w):
		return w
	return null


func _area_info() -> Dictionary:
	var w := _get_world()
	if w != null and not w.area_info.is_empty():
		return w.area_info
	return GameState.current_area


func _message(text: String, color: Color = UIStyle.COLOR_BAD) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_messages.get(text, -100.0)) < MESSAGE_THROTTLE:
		return
	_messages[text] = now
	Events.notify.emit(text, color)

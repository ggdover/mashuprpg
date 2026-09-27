class_name Enemy
extends Actor
## A monster: model + animations, AI (idle -> aggro -> chase/kite -> attack), rarity & monster
## mods, death (XP, loot, corpse fade). Group "enemies". Collision layer 3.
## OWNER: enemies (wave 2). CONTRACT STUB — keep every public member/signature.
## See docs/ARCHITECTURE.md §12.
##
## Stats (§6.2, §7, §12): max_life = Balance.monster_life(level) × def.life_mult × rarity life;
## damage more-mod = (def.damage_mult × rarity damage − 1) × 100; armour = Balance.monster_armour ×
## def.armour_mult; def resistances; monster mods (EnemyDB.get_mod_stats). The weapon is
## {"weapon_type": "monster", phys = Balance.monster_damage(level) × [0.8, 1.2], ...}.
##
## AI (every THINK_INTERVAL, staggered): targets are the living team-0 actors (the player side),
## re-acquired every tick (never cached across ticks). Idle enemies aggro on a target within
## aggro_radius with grid line of sight, or when damaged (hits and DoTs); an aggroing enemy alerts
## every idle enemy within 8 m and its whole pack. In combat: melee enemies chase (world.find_path,
## re-path every 0.5 s, direct steering on a clear straight line, separation from other monsters,
## un-sticking) into reach; ranged / caster / summoner enemies first back off from a target closer
## than half their preferred_range (limited time), keep preferred_range and strafe a little.
## Skills are picked by range, weight, the def's AI cooldown, line of sight and
## skill_runner.can_use(); windups/telegraphs are the skills' job. Bosses rotate through their
## special abilities. A random 0.3-0.8 s pause follows every skill use (started on the frame the
## skill ends). Hits >= 20% of max life stagger non-bosses (cancel + "hit", then 1.5 s immunity).
## Leash: no target within LEASH_RADIUS for LEASH_TIMEOUT -> walk home; on arrival full life, no
## ailments, a boss's enrage ends and its next aggro roars + announces again. Bosses roar on first
## aggro (Events.boss_spawned), re-announce (no roar) when they fight on after their kept dungeon
## was re-attached (town portal), and enrage at half life (buff + red rim + embers). EnemyDB puts
## enemies far from the player to sleep (set_sleeping; 40 m, 60 m while fighting), makes every
## fighter leave combat when the player dies and resets bosses on Events.respawn_requested.
## Summoned minions rise from the ground, give half XP and drop no loot. The life bar shows on
## any damage (hits and DoTs); rare / boss bars always show.
##
## Public helpers (flow / tests / other modules): aggro(), leave_combat(), reset_boss(),
## is_in_combat(), get_target(), set_sleeping(), set_hovered(), mark_as_summon(),
## get_minion_count(), get_height(), home_position, pack_id, is_summon, summoner_id, sleeping,
## state, archetype_name, enraged, visuals.

const EnemyVisuals := preload("res://scripts/entities/enemies/enemy_visuals.gd")

enum State { IDLE, COMBAT, RETURN, DEAD }
enum Move { NONE, CHASE, KITE, STRAFE, HOME }

const THINK_INTERVAL := 0.2
const REPATH_INTERVAL := 0.5
const PACK_AGGRO_RADIUS := 8.0
## In combat, targets farther than this are ignored; without any for LEASH_TIMEOUT s -> go home.
const LEASH_RADIUS := 36.0
const LEASH_TIMEOUT := 4.0
## Idle enemies that take damage without a known source aggro on the nearest hostile this close.
const DAMAGE_AGGRO_RADIUS := 40.0
const STAGGER_THRESHOLD := 0.2
const STAGGER_IMMUNITY := 1.5
const HIT_ANIM_TIME := 0.3
const SKILL_PAUSE_MIN := 0.3
const SKILL_PAUSE_MAX := 0.8
## Reaction delay after aggroing before the first skill.
const REACTION_TIME := Vector2(0.1, 0.45)
const CORPSE_TIME := 4.0
const FADE_TIME := 1.4
const TURN_SPEED := 10.0
const SEPARATION_GAP := 0.3
const SEPARATION_WEIGHT := 0.9
const MAGIC_SIZE := 1.04
const RARE_SIZE := 1.12
const ROAR_TIME := 1.2
const ENRAGE_ROAR_TIME := 0.9
## Summoned monsters give this fraction of XP and drop no loot.
const SUMMON_XP_MULT := 0.5
const WAYPOINT_REACHED := 0.45
const KITE_MAX_TIME := 1.6
const HOME_REACHED := 1.0
const STUCK_CHECK := 1.0
## Summoned monsters climb out of the ground for this long before they act.
const RISE_TIME := 0.7

var enemy_id: String = ""
var def: Dictionary = {}
## Item.Rarity value; 3 = unique boss.
var rarity: int = 0
## Monster mod ids ("hasted", "fiery", ...).
var monster_mods: Array = []
var is_boss: bool = false

## Where the enemy spawned; it walks back here after losing its target.
var home_position: Vector3 = Vector3.ZERO
## Spawn group index from EnemyDB.populate_area (-1 = spawned on its own).
var pack_id: int = -1
## Raised by a summoner (a necromancer's or the lich's skeletons): less XP, no loot.
var is_summon: bool = false
## instance_id of the summoner (0 = none).
var summoner_id: int = 0
## True while put to sleep by EnemyDB (far from the player): no physics, hidden.
var sleeping: bool = false
var state: int = State.IDLE
## Archetype name ("Skeleton Warrior"), also for magic/rare monsters.
var archetype_name: String = ""
## Bosses: true after the half-life enrage.
var enraged: bool = false
## The visual node (model, animations, life bar). Null before _ready.
var visuals: EnemyVisuals = null

var _target: Actor = null
var _ai_clock := 0.0
var _think_timer := 0.0
var _move_mode: int = Move.NONE
var _path := PackedVector3Array()
var _path_index := 0
var _repath_timer := 0.0
var _direct := false
var _separation := Vector3.ZERO
var _no_target_time := 0.0
var _pause := 0.0
var _was_busy := false
var _stagger := 0.0
var _stagger_immune := 0.0
var _roar := 0.0
var _boss_announced := false
var _skill_ready_at: Dictionary = {}
## skill id -> Vector2(min range, max range) the AI uses it at (centre to target edge).
var _skill_ranges: Dictionary = {}
var _rotation := 0
var _kite_time := 0.0
var _strafe_dir := 1.0
var _strafe_time := 0.0
var _corpse_time := 0.0
var _last_life := -1.0
var _stuck_timer := 0.0
var _stuck_pos := Vector3.ZERO
var _unstick_time := 0.0
var _unstick_dir := Vector3.ZERO
var _idle_turn_timer := 0.0
var _idle_yaw := 0.0
var _idle_turning := false
var _collision: CollisionShape3D = null
var _radius := 0.4
var _height := 1.8
var _start_in_combat := false
var _home_set := false
var _hovered := false
## Seconds left of the summon rise (no moving / acting).
var _rise := 0.0
var _weapon: Dictionary = {}
var _weapon_level := -1
## Horizontal speed actually moved this frame (drives idle / run).
var _speed := 0.0


## Configure before adding to the tree.
func setup(p_def: Dictionary, p_level: int, p_rarity: int, p_mods: Array) -> void:
	def = p_def
	enemy_id = p_def.get("id", "")
	level = p_level
	rarity = p_rarity
	monster_mods = p_mods
	team = Team.ENEMY
	is_boss = bool(def.get("boss", false))
	if is_boss:
		rarity = 3
	is_boss_actor = is_boss
	base_move_speed = float(def.get("move_speed", 3.5))
	archetype_name = String(def.get("name", enemy_id.capitalize()))
	_radius = float(def.get("radius", 0.4)) * float(def.get("scale", 1.0)) * _size_mult()
	_height = float(def.get("height", 1.8)) * float(def.get("scale", 1.0)) * _size_mult()
	display_name = _make_display_name()


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 2)
	_build_collision()
	super._ready()
	add_to_group("enemies")
	if is_boss:
		add_to_group("boss")
	if not _home_set:
		home_position = global_position
		_home_set = true
	if skill_runner == null:
		skill_runner = SkillRunner.new()
	if skill_runner.actor == null:
		skill_runner.setup(self)
	if skill_runner.get_parent() == null:
		skill_runner.name = "SkillRunner"
		add_child(skill_runner)
	skill_runner.skill_started.connect(_on_skill_started)
	_build_visuals()
	StatusVisuals.attach(self)
	damaged.connect(_on_damaged)
	_last_life = life
	_think_timer = randf() * THINK_INTERVAL
	_repath_timer = randf() * REPATH_INTERVAL
	_idle_turn_timer = randf_range(2.0, 7.0)
	_idle_yaw = rotation.y
	_compute_skill_ranges()
	if _start_in_combat:
		state = State.COMBAT
		_pause = randf_range(REACTION_TIME.x, REACTION_TIME.y)
	if is_summon:
		_rise = RISE_TIME
		visuals.play_rise(RISE_TIME)


## For the HUD hover card: {"name": String, "subtitle": String (archetype name for magic/rare, else
## ""), "rarity": int, "mods": PackedStringArray (display names, e.g. "Hasted"), "level": int,
## "life_ratio": float, "is_boss": bool}
func get_nameplate_info() -> Dictionary:
	var mods := PackedStringArray()
	for m in monster_mods:
		mods.append(EnemyDB.get_mod_name(String(m)))
	var subtitle := archetype_name if (rarity == 1 or rarity == 2) and not is_boss else ""
	return {"name": display_name, "subtitle": subtitle, "rarity": rarity, "mods": mods, "level": level,
		"life_ratio": life_ratio(), "is_boss": is_boss}


func _notification(what: int) -> void:
	# Leaving the tree (a dungeon kept for a town portal): the HUD hides the boss bar on the next
	# area_entered, so a living boss announces itself again when it fights on after coming back.
	if what == NOTIFICATION_EXIT_TREE and is_boss and not dead:
		_boss_announced = false


# ------------------------------------------------------------------ stats

func get_base_mods() -> Array:
	var r := Balance.monster_rarity(rarity)
	var mods: Array = []
	var life_value := Balance.monster_life(level) * float(def.get("life_mult", 1.0)) * float(r["life"])
	mods.append(StatBlock.mod("max_life", "flat", life_value))
	var dmg_more := (float(def.get("damage_mult", 1.0)) * float(r["damage"]) - 1.0) * 100.0
	if absf(dmg_more) > 0.0001:
		mods.append(StatBlock.mod("damage", "more", dmg_more))
	var arm := Balance.monster_armour(level) * float(def.get("armour_mult", 1.0))
	if arm > 0.0:
		mods.append(StatBlock.mod("armour", "flat", arm))
	var res: Dictionary = def.get("resist", {})
	for t in res:
		var stat := "physical_damage_reduction" if String(t) == "physical" else "%s_resistance" % t
		mods.append(StatBlock.mod(stat, "flat", float(res[t])))
	for m in monster_mods:
		mods.append_array(EnemyDB.get_mod_stats(String(m), level))
	return mods


## §6.2 monster weapon (the archetype/rarity multiplier is the "damage" more-mod, not in here).
## Cached per level (SkillRunner / DamageCalc ask for it several times per skill use); treat the
## returned dictionary as read-only.
func get_weapon() -> Dictionary:
	if _weapon.is_empty() or _weapon_level != level:
		var avg := Balance.monster_damage(level)
		_weapon_level = level
		_weapon = {
			"weapon_type": "monster",
			"phys_min": avg * 0.8,
			"phys_max": avg * 1.2,
			"added": {},
			"attack_speed": float(def.get("attack_speed", 0.85)),
			"crit_chance": 5.0,
			"range": float(def.get("melee_range", 1.8)),
			"two_handed": false,
		}
	return _weapon


func get_collision_radius() -> float:
	return _radius


func get_aim_point() -> Vector3:
	return _gpos() + Vector3(0, clampf(_height * 0.55, 0.9, 1.9), 0)


## Model height in metres (after scale).
func get_height() -> float:
	return _height


# ------------------------------------------------------------------ animation hooks

func play_action_animation(anim: String, duration: float) -> void:
	if visuals != null:
		visuals.play_action(anim, duration)


func stop_action_animation() -> void:
	if visuals != null:
		visuals.stop_action()


# ------------------------------------------------------------------ public AI API

## Enter combat against `target` (or the nearest hostile). alert: also wake the pack / idle
## enemies within 8 m. Bosses roar and emit Events.boss_spawned the first time.
func aggro(target: Node = null, alert: bool = true) -> void:
	if dead or state == State.COMBAT:
		return
	if sleeping:
		set_sleeping(false)
	var t: Actor = target as Actor if is_instance_valid(target) else null
	if t == null or t.dead:
		t = CombatQuery.nearest_hostile(team, global_position, DAMAGE_AGGRO_RADIUS)
	state = State.COMBAT
	_no_target_time = 0.0
	_move_mode = Move.NONE
	_path = PackedVector3Array()
	_target = t
	_pause = maxf(_pause, randf_range(REACTION_TIME.x, REACTION_TIME.y))
	if t != null:
		face_towards(t.global_position)
	if is_boss and not _boss_announced:
		_boss_announced = true
		_start_roar(ROAR_TIME)
		Events.boss_spawned.emit(self)
	if alert:
		_alert_pack(t)


## Stop fighting and walk home (heals up on arrival).
func leave_combat() -> void:
	if dead:
		return
	if skill_runner != null:
		skill_runner.cancel()
	state = State.RETURN
	_move_mode = Move.HOME
	_target = null
	_no_target_time = 0.0
	_path = PackedVector3Array()
	_repath_timer = 0.0


## Bosses (and any enemy): full life, ailments/buffs cleared, out of combat, back at home at once.
## The next aggro roars and emits Events.boss_spawned again. The game flow calls this (via
## EnemyDB.reset_bosses) when the player respawns after dying.
func reset_boss() -> void:
	if dead:
		return
	if skill_runner != null:
		skill_runner.cancel()
	clear_ailments()
	_clear_enrage()
	for id in buffs.keys():
		remove_buff(id)
	refill_pools()
	if is_inside_tree():
		global_position = home_position
	else:
		position = home_position
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	state = State.IDLE
	_move_mode = Move.NONE
	_target = null
	_boss_announced = false
	_roar = 0.0
	_stagger = 0.0
	_pause = 0.0
	_rotation = 0
	_skill_ready_at.clear()
	_path = PackedVector3Array()
	_last_life = life
	if visuals != null:
		visuals.stop_action()


func is_in_combat() -> bool:
	return state == State.COMBAT


## Current target (valid, alive) or null.
func get_target() -> Actor:
	if is_instance_valid(_target) and not _target.dead:
		return _target
	return null


## Put to sleep (far from the player): physics off, hidden, animations paused.
func set_sleeping(on: bool) -> void:
	if dead or sleeping == on:
		return
	sleeping = on
	set_physics_process(not on)
	visible = not on
	if on:
		velocity = Vector3.ZERO
	if visuals != null:
		visuals.set_active(not on)


## Mouse-over highlight (a bright rim). The player may call this like Interactable.set_hovered.
func set_hovered(on: bool) -> void:
	_hovered = on
	if visuals != null:
		visuals.set_highlight(on)


## Make this enemy a minion of `caster` (called by EnemyDB for monsters spawned by a summon).
func mark_as_summon(caster: Node) -> void:
	is_summon = true
	summoner_id = caster.get_instance_id() if caster != null else 0
	var c := caster as Enemy
	if c != null:
		pack_id = c.pack_id
		if c.state == State.COMBAT:
			_start_in_combat = true


## Living minions raised by this enemy.
func get_minion_count() -> int:
	var n := 0
	var my_id := get_instance_id()
	for e in EnemyDB.get_live_enemies():
		if not e.dead and e.summoner_id == my_id:
			n += 1
	return n


# ------------------------------------------------------------------ frame update

func _actor_physics(delta: float) -> void:
	if dead:
		_tick_corpse(delta)
		return
	_ai_clock += delta
	# The 0.3-0.8 s pause starts on the frame a skill ends (not at the next think tick), and the
	# AI thinks at once when it runs out, so the gaps between skill uses match the contract.
	var busy := _is_busy()
	if _was_busy and not busy:
		_pause = maxf(_pause, randf_range(SKILL_PAUSE_MIN, SKILL_PAUSE_MAX))
	_was_busy = busy
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0 and state == State.COMBAT:
			_think_timer = 0.0
	if _stagger > 0.0:
		_stagger -= delta
	if _stagger_immune > 0.0:
		_stagger_immune -= delta
	if _roar > 0.0:
		_roar -= delta
	if _rise > 0.0:
		_rise -= delta
	if _strafe_time > 0.0:
		_strafe_time -= delta
	if _unstick_time > 0.0:
		_unstick_time -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer += THINK_INTERVAL
		if _think_timer <= 0.0:
			_think_timer = THINK_INTERVAL
		_think()
	_update_movement(delta)
	if visuals != null:
		visuals.tick(delta, _speed, life_ratio(), is_frozen())


func _think() -> void:
	# Damage without a `damaged` signal (DoTs) also shows the life bar and wakes the enemy up.
	if _last_life >= 0.0 and life < _last_life - 0.001:
		if visuals != null:
			visuals.show_bar()
		if state != State.COMBAT:
			aggro(null)
	_last_life = life
	if state == State.COMBAT or state == State.RETURN:
		_separation = _compute_separation()
	else:
		_separation = Vector3.ZERO
	var target := _acquire_target()
	_target = target
	match state:
		State.IDLE:
			if target != null:
				aggro(target)
			else:
				_idle_think()
		State.RETURN:
			if target != null:
				aggro(target)
			elif CombatQuery.distance_xz(global_position, home_position) <= HOME_REACHED:
				_arrive_home()
			else:
				_move_mode = Move.HOME
				_check_stuck(true)
		State.COMBAT:
			if target == null:
				_move_mode = Move.NONE
				_no_target_time += THINK_INTERVAL
				if _no_target_time >= LEASH_TIMEOUT:
					leave_combat()
			else:
				_no_target_time = 0.0
				_combat_think(target)


func _combat_think(target: Actor) -> void:
	# A boss still fighting when its kept dungeon is re-attached (town portal round trip) shows
	# its HUD bar again (no roar).
	if is_boss and not _boss_announced:
		_boss_announced = true
		Events.boss_spawned.emit(self)
	var pos := global_position
	var tpos := target.global_position
	var dist := CombatQuery.distance_to_actor(pos, target)
	var los := _has_los(tpos)
	if _roar > 0.0 or _stagger > 0.0 or _rise > 0.0 or not can_act():
		_move_mode = Move.NONE
		return
	if is_boss:
		_check_enrage()
		if _roar > 0.0:
			return
	if _is_busy():
		_move_mode = Move.NONE
		return
	var ai := String(def.get("ai", "melee"))
	var pref := float(def.get("preferred_range", 0.0))
	var ranged := not (ai == "melee" or (ai == "boss" and pref <= 0.0))
	if ranged:
		if dist >= pref * 0.7:
			_kite_time = 0.0
		# Ranged monsters first back off from a target that got too close (a limited time per
		# approach, so cornered archers still shoot). Bosses fight back with their skills first.
		if not is_boss and los and dist < pref * 0.5 and _kite_time < KITE_MAX_TIME \
				and _kite_dir(tpos) != Vector3.ZERO:
			_move_mode = Move.KITE
			_kite_time += THINK_INTERVAL
			_check_stuck(false)
			return
	if _pause <= 0.0:
		var sid := _choose_skill(dist, los)
		if sid != "":
			if skill_runner.try_use(sid, tpos, target):
				var entry := _skill_entry(sid)
				_skill_ready_at[sid] = _ai_clock + float(entry.get("cooldown", 0.0))
				_was_busy = true
				_move_mode = Move.NONE
				if is_boss:
					_rotation = _skill_index(sid) + 1
				return
			# Could not start (e.g. SkillRunner cooldown): try again a bit later.
			_skill_ready_at[sid] = _ai_clock + 0.4
	if not ranged:
		if dist > _engage_range() or not los:
			_move_mode = Move.CHASE
			_direct = los and _direct_clear(tpos)
		else:
			_move_mode = Move.NONE
		_check_stuck(_move_mode == Move.CHASE)
		return
	# Ranged / caster / summoner (and ranged bosses): keep the preferred range.
	if not los or dist > pref + 1.0:
		_move_mode = Move.CHASE
		_direct = los and _direct_clear(tpos)
	elif is_boss and dist < pref * 0.5 and _kite_time < KITE_MAX_TIME:
		_move_mode = Move.KITE
		_kite_time += THINK_INTERVAL
	else:
		if _strafe_time <= 0.0 and randf() < 0.12 and not is_boss:
			_strafe_time = randf_range(0.5, 1.0)
			_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_move_mode = Move.STRAFE if _strafe_time > 0.0 else Move.NONE
	_check_stuck(_move_mode == Move.CHASE)


func _idle_think() -> void:
	_move_mode = Move.NONE
	_idle_turn_timer -= THINK_INTERVAL
	if _idle_turn_timer <= 0.0:
		_idle_turn_timer = randf_range(3.0, 8.0)
		_idle_yaw = rotation.y + randf_range(-1.3, 1.3)
		_idle_turning = true


func _update_movement(delta: float) -> void:
	if state == State.IDLE and not _idle_turning and knockback_velocity == Vector3.ZERO:
		velocity = Vector3.ZERO
		_speed = 0.0
		return
	var dir := Vector3.ZERO
	var t := get_target()
	var busy := _is_busy()
	var frozen := _roar > 0.0 or _stagger > 0.0 or _rise > 0.0 or not can_act()
	if not frozen:
		if busy:
			var mm := skill_runner.movement_multiplier()
			if mm > 0.0 and t != null:
				dir = _flat_dir(t.global_position) * mm
		elif _unstick_time > 0.0 and _move_mode in [Move.CHASE, Move.HOME]:
			dir = _unstick_dir
		else:
			match _move_mode:
				Move.CHASE:
					if t != null:
						dir = _chase_dir(t.global_position, delta)
				Move.KITE:
					if t != null:
						dir = _kite_dir(t.global_position)
				Move.STRAFE:
					if t != null:
						dir = _strafe_vec(t.global_position)
				Move.HOME:
					dir = _chase_dir(home_position, delta, true)
		if not busy and dir != Vector3.ZERO:
			dir += _separation * SEPARATION_WEIGHT
		elif not busy and _separation.length_squared() > 0.04:
			dir = _separation * 0.5
	dir.y = 0.0
	# Monsters never step into an act's safe hub.
	if dir != Vector3.ZERO:
		var w := _world()
		if w != null and w.is_safe_at(global_position + dir.normalized() * (_radius + 0.6)):
			dir = Vector3.ZERO
	velocity = dir.limit_length(1.0) * get_move_speed() + knockback_velocity
	velocity.y = 0.0
	# Standing still: skip the physics sweep entirely.
	if velocity.length_squared() > 0.0001:
		move_and_slide()
		var rv := get_real_velocity()
		_speed = Vector2(rv.x, rv.z).length()
	else:
		_speed = 0.0
	# Facing.
	if frozen or busy:
		return
	var moving := dir.length_squared() > 0.01
	if moving and _move_mode != Move.STRAFE:
		_turn_towards(dir, delta)
	elif t != null and state == State.COMBAT:
		_turn_towards(t.global_position - global_position, delta)
	elif _idle_turning and state == State.IDLE:
		rotation.y = lerp_angle(rotation.y, _idle_yaw, clampf(2.5 * delta, 0.0, 1.0))
		if absf(angle_difference(rotation.y, _idle_yaw)) < 0.02:
			_idle_turning = false


# ------------------------------------------------------------------ AI helpers

func _acquire_target() -> Actor:
	var pos := global_position
	var combat := state == State.COMBAT
	var radius := LEASH_RADIUS if combat else float(def.get("aggro_radius", 10.0))
	var best: Actor = null
	var best_d := INF
	var w := _world()
	for a in _hostiles():
		var d := CombatQuery.distance_xz(pos, a.global_position)
		if d > radius or d >= best_d:
			continue
		# Nobody is hunted inside an act's safe hub.
		if w != null and w.is_safe_at(a.global_position):
			continue
		if not combat and not _has_los(a.global_position):
			continue
		best = a
		best_d = d
	return best


## Living hostile actors (the other team's group: usually just the player and its summons).
func _hostiles() -> Array[Actor]:
	var out: Array[Actor] = []
	if not is_inside_tree():
		return out
	var group := "team_%d" % (Team.PLAYER if team != Team.PLAYER else Team.ENEMY)
	for n in get_tree().get_nodes_in_group(group):
		var a := n as Actor
		if a != null and not a.dead and a.team != team and a.is_inside_tree():
			out.append(a)
	return out


func _alert_pack(target: Actor) -> void:
	if not is_inside_tree():
		return
	var pos := global_position
	for e in EnemyDB.get_live_enemies():
		if e == self or e.dead or e.state == State.COMBAT:
			continue
		var near := CombatQuery.distance_xz(pos, e.global_position) <= PACK_AGGRO_RADIUS
		if near or (pack_id >= 0 and e.pack_id == pack_id):
			e.aggro(target, false)


func _choose_skill(dist: float, los: bool) -> String:
	var skills: Array = def.get("skills", [])
	var cands: Array = []
	var total := 0.0
	var best_special := ""
	var best_order := 1 << 20
	for i in skills.size():
		var s: Dictionary = skills[i]
		var id := String(s.get("id", ""))
		var rng: Vector2 = _skill_ranges.get(id, Vector2(0.0, 2.0))
		if dist > rng.y or dist < rng.x:
			continue
		if _ai_clock < float(_skill_ready_at.get(id, 0.0)):
			continue
		# Never attack or cast through walls (point-blank excepted).
		if not los and dist > 0.5:
			continue
		if id == "m_summon" and get_minion_count() >= int(def.get("summon_cap", 4)):
			continue
		var cu: Dictionary = skill_runner.can_use(id)
		if not bool(cu.get("ok", false)):
			continue
		if is_boss and float(s.get("cooldown", 0.0)) > 0.0:
			var order := posmod(i - _rotation, skills.size())
			if order < best_order:
				best_order = order
				best_special = id
		var w := maxf(0.0, float(s.get("weight", 1.0)))
		cands.append([id, w])
		total += w
	if best_special != "":
		return best_special
	if cands.is_empty():
		return ""
	var r := randf() * total
	for c in cands:
		r -= float(c[1])
		if r <= 0.0:
			return String(c[0])
	return String(cands[cands.size() - 1][0])


## Distance (centre to target edge) a melee enemy walks into before it stops chasing.
func _engage_range() -> float:
	var best := INF
	for id in _skill_ranges:
		var rng: Vector2 = _skill_ranges[id]
		if rng.x <= 0.01:
			best = minf(best, rng.y)
	if best == INF:
		best = float(def.get("melee_range", 1.8))
	return maxf(0.6, best * 0.8)


func _compute_skill_ranges() -> void:
	_skill_ranges.clear()
	var melee := float(def.get("melee_range", 1.8))
	for s in def.get("skills", []):
		var id := String((s as Dictionary).get("id", ""))
		var mx := float(s.get("range", 0.0))
		var mn := float(s.get("min_range", 0.0))
		var sk := SkillDB.get_skill(id)
		var params: Dictionary = sk.get("params", {}) if not sk.is_empty() else {}
		if mx <= 0.0:
			mx = melee + float(params.get("range_add", 0.0))
		if params.has("max_range") and float(params["max_range"]) > 0.0:
			mx = minf(mx, float(params["max_range"]))
		_skill_ranges[id] = Vector2(mn, maxf(mx, mn + 0.5))


func _skill_entry(id: String) -> Dictionary:
	for s in def.get("skills", []):
		if String(s.get("id", "")) == id:
			return s
	return {}


func _skill_index(id: String) -> int:
	var skills: Array = def.get("skills", [])
	for i in skills.size():
		if String(skills[i].get("id", "")) == id:
			return i
	return 0


func _check_enrage() -> void:
	if enraged or dead or _is_busy():
		return
	var at := float(def.get("enrage_at", 0.0))
	if at <= 0.0 or life_ratio() > at:
		return
	enraged = true
	add_buff("boss_enrage", {"name": "Enraged", "duration": 0.0, "icon": "", "mods": [
		StatBlock.mod("attack_speed", "inc", 25.0), StatBlock.mod("cast_speed", "inc", 25.0),
		StatBlock.mod("movement_speed", "inc", 15.0), StatBlock.mod("damage", "inc", 15.0)]})
	_start_roar(ENRAGE_ROAR_TIME)
	if visuals != null:
		visuals.set_enraged(true)


func _start_roar(seconds: float) -> void:
	if skill_runner != null:
		skill_runner.cancel()
	_roar = seconds
	velocity = Vector3.ZERO
	play_action_animation("roar", seconds)
	Sfx.play("boss_roar", global_position if is_inside_tree() else position)


## Back home after leaving combat: a fresh start (full life, no ailments, a boss calms down and
## may enrage again, and announces itself again on its next aggro).
func _arrive_home() -> void:
	state = State.IDLE
	_move_mode = Move.NONE
	_path = PackedVector3Array()
	clear_ailments()
	_clear_enrage()
	refill_pools()
	_last_life = life
	if is_boss:
		_boss_announced = false


## Ends a boss enrage: the buff, the flag and the red look (back to the rarity rim).
func _clear_enrage() -> void:
	if enraged or has_buff("boss_enrage"):
		remove_buff("boss_enrage")
	enraged = false
	if visuals != null and visuals.is_enraged_look():
		visuals.set_enraged(false, _rarity_rim())


func _is_busy() -> bool:
	return skill_runner != null and skill_runner.is_busy()


func _world() -> World:
	var w: Variant = GameState.world
	if is_instance_valid(w) and (w as World).is_inside_tree():
		return w
	return null


## Grid line of sight (walls, void) inside a World, physics line of sight otherwise.
func _has_los(to: Vector3) -> bool:
	var w := _world()
	if w != null and w.grid != null:
		return w.has_line_of_sight(global_position, to)
	return CombatQuery.has_line_of_sight(global_position, to)


## True if a straight walk to `goal` stays on walkable cells with room for this body.
func _direct_clear(goal: Vector3) -> bool:
	var w := _world()
	if w == null or w.grid == null:
		return true
	var g := w.grid
	var a := global_position
	a.y = 0.0
	var b := Vector3(goal.x, 0.0, goal.z)
	if not g.line_clear(a, b, g.walk, true):
		return false
	var d := Vector2(b.x - a.x, b.z - a.z)
	var length := d.length()
	if length < 0.01:
		return true
	var perp := Vector2(-d.y, d.x) / length * clampf(_radius * 0.9, 0.3, 0.8)
	var off := Vector3(perp.x, 0.0, perp.y)
	return g.line_clear(a + off, b + off, g.walk, true) and g.line_clear(a - off, b - off, g.walk, true)


func _walkable(p: Vector3) -> bool:
	var w := _world()
	if w == null:
		return true
	return w.is_walkable(p)


func _flat_dir(to: Vector3) -> Vector3:
	var d := to - global_position
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO


func _chase_dir(goal: Vector3, delta: float, home: bool = false) -> Vector3:
	var direct := _direct if not home else _direct_clear(goal)
	if direct:
		_path = PackedVector3Array()
		var d := goal - global_position
		d.y = 0.0
		if home and d.length() < HOME_REACHED * 0.5:
			return Vector3.ZERO
		return d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO
	_repath_timer -= delta
	if _path.is_empty() or _repath_timer <= 0.0:
		_repath(goal)
	var pos := global_position
	while _path_index < _path.size() and CombatQuery.distance_xz(pos, _path[_path_index]) < WAYPOINT_REACHED:
		_path_index += 1
	if _path_index >= _path.size():
		var d2 := goal - pos
		d2.y = 0.0
		return d2.normalized() if d2.length() > 0.3 else Vector3.ZERO
	var d3 := _path[_path_index] - pos
	d3.y = 0.0
	return d3.normalized() if d3.length_squared() > 0.0001 else Vector3.ZERO


func _repath(goal: Vector3) -> void:
	_repath_timer = REPATH_INTERVAL
	_path_index = 0
	var w := _world()
	if w == null:
		_path = PackedVector3Array([Vector3(goal.x, 0.0, goal.z)])
		return
	_path = w.find_path(global_position, goal)


func _kite_dir(tpos: Vector3) -> Vector3:
	var away := -_flat_dir(tpos)
	if away == Vector3.ZERO:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	for ang in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var d := away.rotated(Vector3.UP, ang)
		if _walkable(global_position + d * 1.6):
			return d
	return Vector3.ZERO


func _strafe_vec(tpos: Vector3) -> Vector3:
	var to := _flat_dir(tpos)
	var side := to.cross(Vector3.UP) * _strafe_dir
	if not _walkable(global_position + side * 1.2):
		_strafe_dir = -_strafe_dir
		side = -side
		if not _walkable(global_position + side * 1.2):
			return Vector3.ZERO
	return side * 0.6


func _compute_separation() -> Vector3:
	var sep := Vector3.ZERO
	var pos := global_position
	var list := EnemyDB.get_live_enemies()
	var positions := EnemyDB.get_live_positions()
	var radii := EnemyDB.get_live_radii()
	for i in positions.size():
		if list[i] == self:
			continue
		var q := positions[i]
		var dx := pos.x - q.x
		var dz := pos.z - q.z
		var min_d := _radius + radii[i] + SEPARATION_GAP
		var l2 := dx * dx + dz * dz
		if l2 >= min_d * min_d:
			continue
		var l := sqrt(l2)
		if l < 0.001:
			sep += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 0.5
		else:
			sep += Vector3(dx, 0.0, dz) / l * (1.0 - l / min_d)
	return sep.limit_length(1.0)


## Chasing without making progress for a second: re-path and side-step briefly.
func _check_stuck(wants_to_move: bool) -> void:
	if not wants_to_move:
		_stuck_timer = 0.0
		_stuck_pos = global_position
		return
	_stuck_timer += THINK_INTERVAL
	if _stuck_timer < STUCK_CHECK:
		return
	var moved := CombatQuery.distance_xz(global_position, _stuck_pos)
	_stuck_timer = 0.0
	_stuck_pos = global_position
	if moved < 0.25 * base_move_speed * STUCK_CHECK * 0.3:
		_repath_timer = 0.0
		_path = PackedVector3Array()
		_direct = false
		var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if _walkable(global_position + side * 1.2):
			_unstick_dir = side
			_unstick_time = 0.4


func _turn_towards(dir: Vector3, delta: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), clampf(TURN_SPEED * delta, 0.0, 1.0))


# ------------------------------------------------------------------ events

func _on_damaged(amount: float, is_crit: bool, source: Node) -> void:
	if dead:
		return
	if visuals != null:
		visuals.flash(1.0 if is_crit else 0.8, Color(1.0, 0.92, 0.75) if is_crit else Color.WHITE)
		visuals.show_bar()
	if state != State.COMBAT:
		aggro(source if CombatQuery.is_hostile(self, source) else null)
	_last_life = life
	# §6.7 hit stagger (bosses never flinch).
	if is_boss or life <= 0.0 or _stagger_immune > 0.0:
		return
	if amount >= STAGGER_THRESHOLD * max_life:
		_stagger_immune = STAGGER_IMMUNITY
		_stagger = HIT_ANIM_TIME
		if skill_runner != null:
			skill_runner.cancel()
		play_action_animation("hit", HIT_ANIM_TIME)
		_pause = maxf(_pause, 0.1)


func _on_skill_started(skill_id: String, _anim: String, duration: float) -> void:
	if skill_id == "m_summon":
		EnemyDB.register_summon_cast(self, maxf(duration, 0.5) + 0.5)


## Rewards, events, death animation; the corpse fades out CORPSE_TIME s later.
func _on_death(_killer: Node) -> void:
	# Killed while asleep (a far hit): wake up so the corpse animates, fades and frees itself.
	if sleeping:
		sleeping = false
		set_physics_process(true)
		visible = true
		if visuals != null:
			visuals.set_active(true)
	state = State.DEAD
	_move_mode = Move.NONE
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if _collision != null:
		_collision.set_deferred("disabled", true)
	remove_from_group("enemies")
	EnemyDB.unregister_summon_cast(self)
	var pos := _gpos()
	if visuals != null:
		visuals.play_die()
	Sfx.play("enemy_die", pos)
	var xp_mult := float(def.get("xp_mult", 1.0)) * float(Balance.monster_rarity(rarity)["xp"])
	if is_summon:
		xp_mult *= SUMMON_XP_MULT
	GameState.award_kill_xp(level, xp_mult)
	if not is_summon:
		_drop_loot(pos)
	Events.enemy_killed.emit(self)
	if is_boss:
		Events.boss_killed.emit(self)
	_corpse_time = CORPSE_TIME


func _drop_loot(pos: Vector3) -> void:
	var ir := 0.0
	var iq := 0.0
	var gf := 0.0
	var p: Variant = GameState.player
	if is_instance_valid(p):
		var st: StatBlock = (p as Actor).stats
		ir = st.compute("item_rarity")
		iq = st.compute("item_quantity")
		gf = st.compute("gold_find")
	LootSystem.spawn_drops(LootSystem.roll_monster_drops(level, rarity, ir, iq, gf), pos)


func _tick_corpse(delta: float) -> void:
	velocity = Vector3.ZERO
	if visuals != null:
		visuals.tick(delta, 0.0, 0.0)
	_corpse_time -= delta
	if _corpse_time > 0.0:
		return
	var t := clampf(-_corpse_time / FADE_TIME, 0.0, 1.0)
	if visuals != null:
		visuals.set_fade(t)
	if t >= 1.0:
		queue_free()


# ------------------------------------------------------------------ construction

func _size_mult() -> float:
	match rarity:
		1:
			return MAGIC_SIZE
		2:
			return RARE_SIZE
	return 1.0


func _make_display_name() -> String:
	if is_boss:
		return archetype_name
	match rarity:
		1:
			if not monster_mods.is_empty():
				return "%s %s" % [EnemyDB.get_mod_name(String(monster_mods[0])), archetype_name]
			return archetype_name
		2:
			return EnemyDB.generate_rare_name()
	return archetype_name


func _rarity_rim() -> Color:
	if visuals == null:
		return Color(0, 0, 0, 0)
	match rarity:
		1:
			return EnemyVisuals.MAGIC_RIM
		2:
			return EnemyVisuals.RARE_RIM
		3:
			return EnemyVisuals.BOSS_RIM
	return Color(0, 0, 0, 0)


func _build_collision() -> void:
	if _collision != null:
		return
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = _radius
	cap.height = maxf(_radius * 2.0 + 0.2, _height * 0.9)
	_collision.shape = cap
	_collision.position = Vector3(0, cap.height * 0.5, 0)
	add_child(_collision)


func _build_visuals() -> void:
	visuals = EnemyVisuals.new()
	var aura := Color(0, 0, 0, 0)
	for m in monster_mods:
		var c := EnemyDB.get_mod_color(String(m))
		if c.a > 0.0:
			aura = c
			break
	var bar_width := 1.0
	match rarity:
		1:
			bar_width = 1.1
		2:
			bar_width = 1.35
		3:
			bar_width = 2.3
	var show_name := rarity >= 1
	add_child(visuals)
	visuals.build(def, {
		"rarity": rarity, "size": _size_mult(), "name": display_name if show_name else "",
		"name_color": UIStyle.rarity_color(rarity), "always_bar": rarity >= 2, "aura_color": aura,
		"bar_width": bar_width,
	})

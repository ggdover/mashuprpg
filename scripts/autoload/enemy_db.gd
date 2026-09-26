extends Node
## Autoload "EnemyDB": monster archetypes, monster modifiers, rare-name generation, and spawning
## (packs, rares, bosses) into a World. OWNER: enemies (wave 2).
## CONTRACT STUB — keep every public signature. See docs/ARCHITECTURE.md §12.
##
## Data lives in scripts/entities/enemies/enemy_defs.gd. Besides the contract API this autoload:
##   - rolls monster mods (roll_mods) and builds their stat mods per level (get_mod_stats),
##   - picks archetypes per depth / theme (get_pool_for_depth, pick_archetype, get_boss_for_depth),
##   - puts enemies far from the player to sleep (> 40 m, see Enemy.set_sleeping) every 0.25 s,
##   - lets summoned monsters know who raised them (register_summon_cast, used by Enemy),
##   - ends every fight when the player dies (Events.player_died) and resets living bosses on
##     Events.respawn_requested, also in a kept dungeon (reset_bosses / leave_combat_all are
##     public too, idempotent),
##   - highlights the enemy under the mouse (Events.hovered_target_changed -> Enemy.set_hovered),
##   - keeps a per-frame list of live enemies + positions for the AI (get_live_enemies).
## Packs: 1-2 archetypes (a primary plus maybe one companion from its "companions" list), 15%
## magic packs sharing one rolled mod, rare packs = 1 rare + normal escorts, the depth's boss.

const EnemyDefs := preload("res://scripts/entities/enemies/enemy_defs.gd")

## Maximum monsters populate_area() spawns from packs and rare packs (the boss comes on top).
const MAX_AREA_MONSTERS := 70
## Chance that a normal pack is a magic pack (every member magic).
const MAGIC_PACK_CHANCE := 0.15
## Chance that a pack mixes in a companion archetype.
const MIXED_PACK_CHANCE := 0.45
## Minimum distance between two members of one pack.
const MEMBER_SPACING := 1.05
## Enemies beyond this distance (m) from the player sleep; in combat they sleep only beyond
## SLEEP_DISTANCE_COMBAT. WAKE_MARGIN adds hysteresis.
const SLEEP_DISTANCE := 40.0
const SLEEP_DISTANCE_COMBAT := 60.0
const WAKE_MARGIN := 2.0
const SLEEP_CHECK_INTERVAL := 0.25
## A summon cast "claims" monsters spawned within this radius of the caster while it is casting.
const SUMMON_CLAIM_RADIUS := 14.0

var _defs: Dictionary = {}
var _sleep_timer := 0.0
## The enemy under the mouse (highlighted), tracked from Events.hovered_target_changed.
var _hovered: WeakRef = null
## Per-physics-frame cache of the living enemies in the tree (see get_live_enemies).
var _live: Array[Enemy] = []
var _live_pos := PackedVector3Array()
var _live_radius := PackedFloat32Array()
var _live_key := Vector2i(-1, -1)
## instance_id -> {"until": msec}: casters currently summoning (see register_summon_cast).
var _summon_casts: Dictionary = {}


func _ready() -> void:
	for id in EnemyDefs.ARCHETYPES:
		var d: Dictionary = (EnemyDefs.ARCHETYPES[id] as Dictionary).duplicate(true)
		d["id"] = id
		_defs[id] = d
	for id in EnemyDefs.BOSSES:
		var b: Dictionary = (EnemyDefs.BOSSES[id] as Dictionary).duplicate(true)
		b["id"] = id
		_defs[id] = b
	Events.player_died.connect(_on_player_died)
	Events.respawn_requested.connect(_on_respawn_requested)
	Events.hovered_target_changed.connect(_on_hovered_target_changed)


# ------------------------------------------------------------------ definitions

## Deep copy of a monster definition (§12 schema, plus "radius", "height", "attach", ...), {} if
## unknown.
func get_def(enemy_id: String) -> Dictionary:
	if not _defs.has(enemy_id):
		return {}
	return (_defs[enemy_id] as Dictionary).duplicate(true)


func has_def(enemy_id: String) -> bool:
	return _defs.has(enemy_id)


## Every archetype and boss id.
func get_all_ids() -> Array:
	return _defs.keys()


## Archetype (non-boss) ids.
func get_archetype_ids() -> Array:
	return EnemyDefs.ARCHETYPES.keys()


func get_boss_ids() -> Array:
	return EnemyDefs.BOSSES.keys()


## The depth's boss: the Lich on odd depths, the Gravebreaker on even depths.
func get_boss_for_depth(depth: int) -> String:
	return "boss_lich" if maxi(depth, 1) % 2 == 1 else "boss_gravebreaker"


## {archetype id: weight} allowed at this depth (min_depth <= depth), weighted by the theme.
func get_pool_for_depth(depth: int, theme: String = "") -> Dictionary:
	var th := theme if EnemyDefs.THEME_WEIGHTS.has(theme) else World.theme_for_depth(depth)
	var weights: Dictionary = EnemyDefs.THEME_WEIGHTS[th]
	var out := {}
	for id in EnemyDefs.ARCHETYPES:
		var d: Dictionary = EnemyDefs.ARCHETYPES[id]
		if int(d.get("min_depth", 1)) <= maxi(depth, 1):
			out[id] = float(weights.get(id, 1.0))
	return out


## Weighted random archetype from a pool ({id: weight}). rng may be null (global RNG).
func pick_archetype(pool: Dictionary, rng: RandomNumberGenerator = null) -> String:
	var total := 0.0
	for id in pool:
		total += float(pool[id])
	if total <= 0.0:
		return "skeleton_warrior"
	var r := _randf(rng) * total
	for id in pool:
		r -= float(pool[id])
		if r <= 0.0:
			return id
	return pool.keys()[pool.size() - 1]


# ------------------------------------------------------------------ monster mods

func get_mod_ids() -> Array:
	return EnemyDefs.MONSTER_MODS.keys()


## Display name of a monster mod ("Hasted"); the id itself if unknown.
func get_mod_name(mod_id: String) -> String:
	var m: Dictionary = EnemyDefs.MONSTER_MODS.get(mod_id, {})
	return String(m.get("name", mod_id.capitalize()))


## One-line description of a monster mod ("+30% movement, attack and cast speed").
func get_mod_description(mod_id: String) -> String:
	var m: Dictionary = EnemyDefs.MONSTER_MODS.get(mod_id, {})
	return String(m.get("desc", ""))


## Exclusion group of a monster mod (fiery / frigid / shocking share "element").
func get_mod_group(mod_id: String) -> String:
	var m: Dictionary = EnemyDefs.MONSTER_MODS.get(mod_id, {})
	return String(m.get("group", mod_id))


## Aura colour of elemental mods (fiery / frigid / shocking), else Color(0, 0, 0, 0).
func get_mod_color(mod_id: String) -> Color:
	var m: Dictionary = EnemyDefs.MONSTER_MODS.get(mod_id, {})
	return m.get("color", Color(0, 0, 0, 0))


## Stat mods (StatBlock.mod dicts) a monster mod gives a monster of this level.
func get_mod_stats(mod_id: String, level: int) -> Array:
	var avg := Balance.monster_damage(maxi(level, 1))
	var added := Vector2(avg * 0.2, avg * 0.34)
	match mod_id:
		"hasted":
			return [StatBlock.mod("movement_speed", "inc", 30.0), StatBlock.mod("attack_speed", "inc", 30.0),
				StatBlock.mod("cast_speed", "inc", 30.0)]
		"armoured":
			return [StatBlock.mod("armour", "inc", 100.0), StatBlock.mod("physical_damage_reduction", "flat", 20.0)]
		"fiery":
			return [StatBlock.mod("added_fire_attack", "flat", added.x, added.y),
				StatBlock.mod("added_fire_spell", "flat", added.x, added.y), StatBlock.mod("fire_resistance", "flat", 40.0),
				StatBlock.mod("ignite_chance", "flat", 10.0)]
		"frigid":
			return [StatBlock.mod("added_cold_attack", "flat", added.x, added.y),
				StatBlock.mod("added_cold_spell", "flat", added.x, added.y), StatBlock.mod("cold_resistance", "flat", 40.0)]
		"shocking":
			return [StatBlock.mod("added_lightning_attack", "flat", added.x * 0.5, added.y * 1.5),
				StatBlock.mod("added_lightning_spell", "flat", added.x * 0.5, added.y * 1.5),
				StatBlock.mod("lightning_resistance", "flat", 40.0), StatBlock.mod("shock_chance", "flat", 10.0)]
		"regenerating":
			return [StatBlock.mod("life_regen_percent", "flat", 2.0)]
		"vampiric":
			return [StatBlock.mod("life_leech", "flat", 8.0)]
		"berserker":
			return [StatBlock.mod("damage", "inc", 40.0)]
		"resilient":
			return [StatBlock.mod("elemental_resistance", "flat", 30.0)]
		"extra_life":
			return [StatBlock.mod("max_life", "inc", 60.0)]
	push_warning("EnemyDB.get_mod_stats: unknown monster mod '%s'" % mod_id)
	return []


## Random distinct monster mods for a rarity at a depth (Balance.monster_mod_count); at most one
## mod per group (so a monster is never both fiery and frigid).
func roll_mods(rarity: int, depth: int, rng: RandomNumberGenerator = null) -> Array:
	var n_range := Balance.monster_mod_count(rarity, depth)
	var n := n_range.x
	if n_range.y > n_range.x:
		n = n_range.x + int(_randf(rng) * float(n_range.y - n_range.x + 1))
	n = mini(n, n_range.y)
	var pool: Array = EnemyDefs.MONSTER_MODS.keys()
	var out: Array = []
	var groups := {}
	while out.size() < n and not pool.is_empty():
		var k := int(_randf(rng) * pool.size()) % pool.size()
		var id: String = pool[k]
		pool.remove_at(k)
		var g := String((EnemyDefs.MONSTER_MODS[id] as Dictionary).get("group", id))
		if groups.has(g):
			continue
		groups[g] = true
		out.append(id)
	return out


## "Grim Howl" style name for a rare monster.
func generate_rare_name(rng: RandomNumberGenerator = null) -> String:
	var p: Array[String] = EnemyDefs.RARE_PREFIXES
	var s: Array[String] = EnemyDefs.RARE_SUFFIXES
	var a := p[int(_randf(rng) * p.size()) % p.size()]
	var b := s[int(_randf(rng) * s.size()) % s.size()]
	return "%s %s" % [a, b]


## Reference run speed of a model's run cycle (m/s, §19).
func get_model_run_speed(model_id: String) -> float:
	return float(EnemyDefs.MODEL_RUN_SPEED.get(model_id, 5.0))


# ------------------------------------------------------------------ spawning

## Spawn one enemy. rarity uses Item.Rarity values. mods: monster mod ids ([] = roll per rarity).
## Snaps position with world.get_nearest_walkable(), adds the enemy via world.add_enemy() (world
## defaults to GameState.world) and returns it already inside the tree. Callers never re-parent it.
## Boss defs always spawn as rarity 3. Without any World (demos) the enemy goes into the current
## scene. Monsters spawned next to a monster that is casting a summon become its minions.
func spawn_enemy(enemy_id: String, position: Vector3, level: int, rarity: int = 0, mods: Array = [], world: World = null) -> Enemy:
	var def := get_def(enemy_id)
	if def.is_empty():
		push_warning("EnemyDB.spawn_enemy: unknown enemy id '%s'" % enemy_id)
		return null
	var w: World = world
	if w == null and is_instance_valid(GameState.world):
		w = GameState.world
	var r := clampi(rarity, 0, 3)
	if bool(def.get("boss", false)):
		r = 3
	var m := mods.duplicate()
	if m.is_empty() and (r == 1 or r == 2):
		var depth := level
		if w != null:
			depth = int(w.area_info.get("depth", level))
		m = roll_mods(r, depth)
	var pos := Vector3(position.x, 0.0, position.z)
	if w != null:
		pos = w.get_nearest_walkable(pos)
		pos.y = 0.0
	var e := Enemy.new()
	e.setup(def, maxi(1, level), r, m)
	e.position = pos
	e.home_position = pos
	e.rotation.y = randf() * TAU
	_claim_summon(e, pos)
	_live_key = Vector2i(-1, -1)
	if w != null:
		w.add_enemy(e)
	else:
		var tree := get_tree()
		var parent: Node = tree.current_scene if tree != null else null
		if parent == null:
			push_warning("EnemyDB.spawn_enemy: no World and no current scene for '%s'" % enemy_id)
			e.free()
			return null
		parent.add_child(e)
	return e


## Fill a dungeon World from world.get_spawn_groups() (packs, rare packs, the boss).
## pack -> `count` monsters of 1-2 archetypes allowed at the depth (15% magic packs);
## rare_pack -> 1 rare + (count - 1) normal escorts; boss -> the depth's boss.
## At most MAX_AREA_MONSTERS monsters plus the boss. Returns nothing (see get_enemies()).
func populate_area(world: World) -> void:
	if world == null or not is_instance_valid(world):
		push_warning("EnemyDB.populate_area: no world")
		return
	var info := world.area_info
	var depth := maxi(1, int(info.get("depth", 1)))
	var level := int(info.get("level", Balance.area_level_for_depth(depth)))
	var theme := world.theme
	var pool := get_pool_for_depth(depth, theme)
	var total := 0
	var pack_id := 0
	var boss_done := false
	for g in world.get_spawn_groups():
		var kind := String(g.get("kind", "pack"))
		var center: Vector3 = g.get("position", Vector3.ZERO)
		var radius := float(g.get("radius", 2.5))
		var count := maxi(1, int(g.get("count", 3)))
		match kind:
			"boss":
				if boss_done:
					continue
				var boss := spawn_enemy(get_boss_for_depth(depth), center, level, 3, [], world)
				if boss != null:
					boss_done = true
					boss.pack_id = pack_id
					_face_start(boss, world)
			"rare_pack":
				if total >= MAX_AREA_MONSTERS:
					continue
				var n := mini(count, MAX_AREA_MONSTERS - total)
				var arche := pick_archetype(pool)
				var members := _pack_members(arche, n - 1, pool, true)
				members.push_front(arche)
				var positions := _member_positions(world, center, maxf(radius, 2.5), members.size())
				for i in members.size():
					var e := spawn_enemy(members[i], positions[i], level, 2 if i == 0 else 0, [], world)
					if e != null:
						e.pack_id = pack_id
						total += 1
			_:
				if total >= MAX_AREA_MONSTERS:
					continue
				var n2 := mini(count, MAX_AREA_MONSTERS - total)
				var arche2 := pick_archetype(pool)
				var members2 := _pack_members(arche2, n2, pool, false)
				var magic := randf() < MAGIC_PACK_CHANCE
				# A magic pack shares one rolled mod ("a pack of Hasted ghouls").
				var pack_mods: Array = roll_mods(1, depth) if magic else []
				var positions2 := _member_positions(world, center, radius, members2.size())
				for i in members2.size():
					var e2 := spawn_enemy(members2[i], positions2[i], level, 1 if magic else 0, pack_mods, world)
					if e2 != null:
						e2.pack_id = pack_id
						total += 1
		pack_id += 1


## Living enemies in the tree (group "enemies"), cached once per physics frame: the AI's cheap
## neighbour list (separation, pack alerts, minion counts). Treat as read-only.
func get_live_enemies() -> Array[Enemy]:
	_refresh_live()
	return _live


## Positions (and collision radii) of get_live_enemies(), same order, same frame cache.
func get_live_positions() -> PackedVector3Array:
	_refresh_live()
	return _live_pos


func get_live_radii() -> PackedFloat32Array:
	_refresh_live()
	return _live_radius


func _refresh_live() -> void:
	var key := Vector2i(Engine.get_physics_frames(), Engine.get_process_frames())
	if key == _live_key:
		return
	_live_key = key
	_live.clear()
	_live_pos.clear()
	_live_radius.clear()
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and not e.dead:
			_live.append(e)
			_live_pos.append(e.global_position)
			_live_radius.append(e.get_collision_radius())


## Living enemies of a World (all worlds in the tree when null).
func get_enemies(world: World = null) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if world != null:
		if not is_instance_valid(world) or world.enemies_root == null:
			return out
		for n in world.enemies_root.get_children():
			var e := n as Enemy
			if e != null and not e.dead:
				out.append(e)
		return out
	for n in get_tree().get_nodes_in_group("enemies"):
		var e2 := n as Enemy
		if e2 != null and not e2.dead:
			out.append(e2)
	return out


## Every living boss of the world (or GameState.world) resets: full life, out of combat, back
## home. Called automatically on Events.respawn_requested (also for a kept, detached dungeon); the
## game flow may call it too (idempotent).
func reset_bosses(world: World = null) -> void:
	var w: Variant = world if world != null else GameState.world
	if not is_instance_valid(w):
		return
	for e in get_enemies(w as World):
		if e.is_boss:
			e.reset_boss()


## Every living enemy of the world (or GameState.world) stops fighting and walks home.
func leave_combat_all(world: World = null) -> void:
	var w: Variant = world if world != null else GameState.world
	if not is_instance_valid(w):
		return
	for e in get_enemies(w as World):
		e.leave_combat()


# ------------------------------------------------------------------ summons

## Called by an Enemy when it starts a summon skill: monsters spawned near it within `seconds`
## become its minions (Enemy.summoner).
func register_summon_cast(caster: Node, seconds: float) -> void:
	if caster == null:
		return
	_summon_casts[caster.get_instance_id()] = {"until": Time.get_ticks_msec() + int(seconds * 1000.0) + 400}


func unregister_summon_cast(caster: Node) -> void:
	if caster != null:
		_summon_casts.erase(caster.get_instance_id())


func _claim_summon(e: Enemy, pos: Vector3) -> void:
	if _summon_casts.is_empty():
		return
	var now := Time.get_ticks_msec()
	var best: Enemy = null
	var best_d := INF
	for id in _summon_casts.keys():
		var entry: Dictionary = _summon_casts[id]
		var caster := instance_from_id(id) as Enemy
		if caster == null or not is_instance_valid(caster) or caster.dead or now > int(entry["until"]):
			_summon_casts.erase(id)
			continue
		if not caster.is_inside_tree():
			continue
		var d := CombatQuery.distance_xz(caster.global_position, pos)
		if d <= SUMMON_CLAIM_RADIUS and d < best_d:
			best_d = d
			best = caster
	if best != null:
		e.mark_as_summon(best)


# ------------------------------------------------------------------ sleeping

func _physics_process(delta: float) -> void:
	_sleep_timer += delta
	if _sleep_timer < SLEEP_CHECK_INTERVAL:
		return
	_sleep_timer = 0.0
	update_sleep()


## Put enemies far from the player to sleep / wake them (runs every 0.25 s by itself). Without a
## live player nothing changes.
func update_sleep() -> void:
	var pv: Variant = GameState.player
	if not is_instance_valid(pv):
		return
	var p := pv as Node3D
	if p == null or not p.is_inside_tree():
		return
	apply_sleep(p.global_position)


## Sleep / wake every enemy in the tree by its distance to `focus` (SLEEP_DISTANCE, or
## SLEEP_DISTANCE_COMBAT while fighting; WAKE_MARGIN hysteresis). Tests and the flow may call it.
func apply_sleep(focus: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.dead:
			continue
		var d := CombatQuery.distance_xz(focus, e.global_position)
		var limit := SLEEP_DISTANCE_COMBAT if e.is_in_combat() else SLEEP_DISTANCE
		if e.sleeping:
			if d < limit - WAKE_MARGIN:
				e.set_sleeping(false)
		elif d > limit:
			e.set_sleeping(true)


## Wake every enemy of the world (or all in the tree).
func wake_all(world: World = null) -> void:
	for e in get_enemies(world):
		if e.sleeping:
			e.set_sleeping(false)


# ------------------------------------------------------------------ event hooks

## The player died: every fighting enemy of the current world stops and walks home (healing up
## on arrival), so a returning player finds the level calm.
func _on_player_died() -> void:
	var w: Variant = GameState.world
	if not is_instance_valid(w):
		return
	for e in get_enemies(w as World):
		if e.is_in_combat():
			e.leave_combat()


## Respawn after a death (§15): living bosses reset to full life and leave combat, wherever the
## kept dungeon is (still current, or already detached into town_portal_state).
func _on_respawn_requested() -> void:
	for w in _known_worlds():
		reset_bosses(w)


func _on_hovered_target_changed(target: Node) -> void:
	var old: Enemy = _hovered.get_ref() as Enemy if _hovered != null else null
	if old != null and old != target and is_instance_valid(old):
		old.set_hovered(false)
	_hovered = null
	var e := target as Enemy if is_instance_valid(target) else null
	if e != null and not e.dead:
		e.set_hovered(true)
		_hovered = weakref(e)


func _known_worlds() -> Array[World]:
	var out: Array[World] = []
	var w: Variant = GameState.world
	if is_instance_valid(w) and w is World:
		out.append(w as World)
	var kept: Variant = GameState.town_portal_state.get("world", null)
	if is_instance_valid(kept) and kept is World and not out.has(kept):
		out.append(kept as World)
	return out


# ------------------------------------------------------------------ internals

## Archetypes of one pack: `n` members of at most two archetypes, `primary` (respecting its
## max_per_pack) plus sometimes one companion (always when the primary's cap is below n).
## is_escort: the rare leader is a `primary` too, so escorts leave room for it under the cap.
func _pack_members(primary: String, n: int, pool: Dictionary, is_escort: bool) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var pdef: Dictionary = _defs.get(primary, {})
	var cap := int(pdef.get("max_per_pack", 6))
	if is_escort:
		cap = maxi(0, cap - 1)
	var comps: Array = []
	for c in pdef.get("companions", []):
		if pool.has(c) and c != primary:
			comps.append(c)
	var companion := ""
	if not comps.is_empty() and (cap < n or (n >= 2 and randf() < MIXED_PACK_CHANCE)):
		companion = String(comps[randi() % comps.size()])
	elif cap < n:
		# No companion allowed here: any other pool archetype with room fills the pack.
		var others := pool.duplicate()
		others.erase(primary)
		for id in others.keys():
			if int((_defs.get(id, {}) as Dictionary).get("max_per_pack", 6)) < n - cap:
				others.erase(id)
		if not others.is_empty():
			companion = pick_archetype(others)
	var n_comp := 0
	if companion != "":
		var ccap := int((_defs.get(companion, {}) as Dictionary).get("max_per_pack", 6))
		if cap < n:
			n_comp = n - cap
		else:
			n_comp = randi_range(1, maxi(1, n / 2))
		n_comp = clampi(n_comp, 0, mini(ccap, n))
	var n_primary := mini(n - n_comp, cap)
	for i in n_primary:
		out.append(primary)
	for i in n_comp:
		out.append(companion)
	return out


## Spread positions for `n` members around center (walkable, >= MEMBER_SPACING apart).
func _member_positions(world: World, center: Vector3, radius: float, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var base := world.get_nearest_walkable(center)
	for i in n:
		var best := base
		var best_score := -INF
		for attempt in 8:
			var p := world.random_walkable_near(base, maxf(radius, 1.2))
			var min_d := INF
			for q in out:
				min_d = minf(min_d, CombatQuery.distance_xz(p, q))
			if min_d >= MEMBER_SPACING:
				best = p
				best_score = INF
				break
			if min_d > best_score:
				best_score = min_d
				best = p
		out.append(best)
	return out


## Bosses face the way the player will come from (the player start).
func _face_start(boss: Enemy, world: World) -> void:
	var d := world.get_player_start() - boss.position
	d.y = 0.0
	if d.length_squared() > 0.01:
		boss.rotation.y = atan2(d.x, d.z)


func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()

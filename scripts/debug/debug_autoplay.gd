extends Node
## Autoplay bot (§15): `-- --autoplay=SECONDS [--class=warrior|ranger|sorcerer] [--depth=N]
## [--seed=N]`. Main creates it instead of showing the menu. It creates a character through the
## real flow (Main.start_new_game), walks to the Dungeon Gate and takes the waypoint, and plays
## through the Player.ai_* API — the same code paths as keyboard and mouse:
##   combat    nearest enemy with line of sight; the best usable skill on the bar by estimated
##             DPS (area skills weighted by the enemies around the target), buffs when engaged,
##             leap / teleport to close in or escape; melee closes in, ranged keeps its distance
##             and backs off when hurt; potions below 55% life / 25% mana; dodge away and cast
##             Town Portal when in trouble
##   loot      gold always; items the gear logic wants (DebugBotGear); chests and shrines
##   build     equips upgrades (whole-character power score), allocates passives along the best
##             path (DebugBotBuild), rebuilds the skill bar on level up / weapon change
##   progress  explores toward the nearest remaining monster, kills the boss, then descends or
##             takes the Town portal (inventory filling up / every 2 clears); in town it sells
##             junk and buys upgrades at the Merchant, stashes uniques, and goes back through the
##             return portal or the waypoint (one depth lower after repeated deaths)
##   death     waits for the death screen and respawns
## Logs a status line every 15 s, notable events as they happen and a summary at the end. Exit
## code: 0 healthy; 1 script/engine errors were logged; 2 the player got stuck (no progress for
## 50 s, three times, or never recovered); 3 no kills at all. OWNER: flow (wave 2).
##
##   GTEST_FULL=1 GTEST_TIMEOUT=260 tools/gtest.sh flow-bot res://scenes/main.tscn -- --autoplay=180 --class=ranger

const DebugErrorLog := preload("res://scripts/debug/debug_error_log.gd")
const DebugBotGear := preload("res://scripts/debug/debug_bot_gear.gd")
const DebugBotBuild := preload("res://scripts/debug/debug_bot_build.gd")

const SAVE_DIR := "user://autoplay_saves/"
const THINK_INTERVAL := 0.1
const MAINTAIN_INTERVAL := 1.0
const LOG_INTERVAL := 15.0
const ENGAGE_RADIUS := 15.0
const LOOT_RADIUS := 22.0
const INTERACT_RADIUS := 30.0
## Game seconds without progress (kills, loot, damage dealt, area changes, walking 6 m) before a
## stuck event is logged and a recovery is tried.
const PROGRESS_TIMEOUT := 50.0
const MAX_STUCK_EVENTS := 3
const REPATH_TIME := 0.7
const WAYPOINT_REACHED := 0.55
const TOWN_TASK_TIMEOUT := 35.0
const AUTO_WALK_TIMEOUT := 12.0
const BLACKLIST_TIME := 45.0
## A target we keep attacking (in range) without hurting it is dropped after this long, and one
## we chase without ever hurting it after TARGET_CHASE_TIME.
const TARGET_NO_DAMAGE_TIME := 9.0
const TARGET_CHASE_TIME := 30.0

enum Mode { NONE, PATH, AUTO, DIRECT }

## Set by Main before _ready.
var main: Node = null
var config: Dictionary = {}

var class_id := ""
var duration := 120.0
var gear: DebugBotGear = null
var build: DebugBotBuild = null
var err_log: DebugErrorLog = null
var stats := {
	"kills": 0, "kills_by_rarity": [0, 0, 0, 0], "bosses": 0, "deaths": 0,
	"items": [0, 0, 0, 0], "gold": 0, "equips": 0, "sold": 0, "bought": 0, "stashed": 0,
	"passives": 0, "town_visits": 0, "area_changes": 0, "stuck": 0, "potions": 0, "dodges": 0,
	"portals_cast": 0, "max_depth": 0, "cleared": [], "skills": {}, "chests": 0, "shrines": 0,
}

var _started := false
var _finished := false
var _time := 0.0
var _wall_start := 0
var _think_timer := 0.0
var _maint_timer := 0.0
var _log_timer := LOG_INTERVAL
var _gear_dirty := true
var _bar_dirty := true
var _boosted := false

# Movement.
var _mode := Mode.NONE
var _goal := Vector3.ZERO
var _goal_node: Node = null
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _dir := Vector3.ZERO
var _direct_left := 0.0
var _auto_target: Node = null
var _auto_since := 0.0
var _auto_retries := 0
var _auto_timeout := AUTO_WALK_TIMEOUT

# Combat.
var _target: Enemy = null
var _target_since := 0.0
## Seconds spent attacking the current target (skill held in range) since it last lost life.
var _target_attack_time := 0.0
var _target_life := 0.0
var _held_slot := -1
var _held_id := ""
var _dps_cache: Dictionary = {}
var _status := "starting"

# Bookkeeping.
var _blacklist: Dictionary = {}      # instance id -> game time until
var _loot_ok: Dictionary = {}        # ground item instance id -> bool
var _cleared_worlds: Dictionary = {} # World instance id -> true
var _deaths_at: Dictionary = {}      # depth -> deaths
var _clears_since_town := 0
var _town_tasks: Array[String] = []
var _task_since := 0.0
var _dead_since := -1.0
var _last_progress := 0.0
var _progress_anchor := Vector3.INF
var _hooked_runner: SkillRunner = null


func _ready() -> void:
	_wall_start = Time.get_ticks_msec()
	duration = maxf(5.0, float(config.get("autoplay", 120.0)))
	_boot.call_deferred()


func _exit_tree() -> void:
	if err_log != null:
		OS.remove_logger(err_log)
	if gear != null:
		gear.dispose()


func _boot() -> void:
	GameState.save_dir = SAVE_DIR
	err_log = DebugErrorLog.new()
	OS.add_logger(err_log)
	if config.has("seed"):
		seed(int(config["seed"]))
	class_id = String(config.get("class", ""))
	if not ClassDefs.has_class(class_id):
		var ids := ClassDefs.get_class_ids()
		class_id = String(ids[randi() % ids.size()])
	gear = DebugBotGear.new(class_id)
	build = DebugBotBuild.new(gear.eval, class_id)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.item_picked_up.connect(_on_item_picked_up)
	Events.gold_picked_up.connect(_on_gold_picked_up)
	Events.level_up.connect(_on_level_up)
	Events.player_died.connect(_on_player_died)
	Events.player_spawned.connect(_on_player_spawned)
	Events.inventory_changed.connect(func() -> void: _loot_ok.clear())
	Events.equipment_changed.connect(func(_s: String) -> void: _bar_dirty = true)
	main.connect("area_change_finished", _on_area_entered)
	main.connect("boss_cleared", _on_boss_cleared)
	_say("start: class=%s duration=%ds depth=%d seed=%s" % [class_id, int(duration), int(config.get("depth", 1)), str(config.get("seed", "random"))])
	var ok: bool = main.call("start_new_game", "Bot %s" % ClassDefs.get_display_name(class_id), class_id)
	if not ok:
		_say("ERROR: could not start a new game")
		_finish()
		return
	_last_progress = 0.0
	_started = true


# ------------------------------------------------------------------ frame loop

func _physics_process(delta: float) -> void:
	if not _started or _finished:
		return
	_time += delta
	var wall := (Time.get_ticks_msec() - _wall_start) / 1000.0
	if _time >= duration or wall > duration * 3.0 + 120.0:
		_finish()
		return
	_log_timer -= delta
	if _log_timer <= 0.0:
		_log_timer = LOG_INTERVAL
		_log_status()
	if bool(main.call("is_changing")):
		_last_progress = _time
		return
	var p := _player()
	if p == null:
		return
	_check_progress(p)
	_steer(p, delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_dps_cache.clear()
		_think(p)


func _player() -> Player:
	var p: Variant = GameState.player
	if p != null and is_instance_valid(p) and (p as Node).is_inside_tree():
		return p as Player
	return null


func _think(p: Player) -> void:
	if p.dead:
		_think_dead(p)
		return
	_dead_since = -1.0
	_maintain(p)
	if GameState.is_in_town():
		_think_town(p)
	else:
		_think_dungeon(p)


# ------------------------------------------------------------------ build upkeep

func _maintain(p: Player) -> void:
	_maint_timer -= THINK_INTERVAL
	if _maint_timer > 0.0:
		return
	_maint_timer = MAINTAIN_INTERVAL
	var c := GameState.character
	if c == null:
		return
	var n := 0
	while c.passive_points_unspent() > 0 and n < 8:
		var id := build.next_passive(c)
		if id < 0:
			break
		if not c.allocate_passive(id):
			build.reset_target()
			break
		stats["passives"] += 1
		n += 1
		var node := TreeDB.get_passive(id)
		if String(node.get("type", "")) == "notable":
			_say("passive notable: %s" % String(node.get("name", id)))
	if _gear_dirty:
		_gear_dirty = false
		_equip_upgrades()
	if _bar_dirty:
		_bar_dirty = false
		if build.apply_bar(c, p):
			_say("skill bar: %s" % ", ".join(PackedStringArray(Array(c.skill_bar).filter(func(s: String) -> bool: return s != ""))))


func _equip_upgrades() -> void:
	var c := GameState.character
	for k in 4:
		var up := gear.best_upgrade(c)
		if up.is_empty():
			return
		var it: Item = up["item"]
		var r := c.equip_from_inventory(int(up["index"]), String(up["slot"]))
		if not r.get("ok", false):
			return
		stats["equips"] += 1
		_bar_dirty = true
		_say("equipped %s [%s] in %s (+%d%% power)" % [it.get_display_name(), UIStyle.RARITY_NAMES[it.rarity], up["slot"], int(round((float(up["gain"]) - 1.0) * 100.0))])


# ------------------------------------------------------------------ dungeon

func _think_dungeon(p: Player) -> void:
	var w := GameState.world
	if w == null or not is_instance_valid(w):
		return
	_use_potions(p)
	if p.is_casting_portal():
		_stop(p)
		_status = "casting town portal"
		return
	var enemies := _visible_enemies(p, w)
	if _emergency(p, w, enemies):
		return
	if not enemies.is_empty():
		_fight(p, w, enemies)
		return
	_release(p)
	_target = null
	if _loot(p):
		return
	if _visit_interactables(p, w):
		return
	if _take_exit(p, w):
		return
	_explore(p, w)


func _use_potions(p: Player) -> void:
	var c := GameState.character
	if p.life_ratio() < 0.55 and not p.is_potion_active("life") and c.get_potion_charges("life") >= 1.0:
		if p.use_potion("life"):
			stats["potions"] += 1
	if p.max_mana > 0.0 and p.mana < p.max_mana * 0.25 and not p.is_potion_active("mana") and c.get_potion_charges("mana") >= 1.0:
		if p.use_potion("mana"):
			stats["potions"] += 1


## Living, awake, not blacklisted enemies within ENGAGE_RADIUS (further if they are fighting)
## with line of sight, nearest first.
func _visible_enemies(p: Player, w: World) -> Array:
	var pos := p.global_position
	var out: Array = []
	for e in EnemyDB.get_enemies(w):
		if e.dead or e.sleeping or _is_blacklisted(e):
			continue
		var d := CombatQuery.distance_xz(pos, e.global_position)
		var limit := ENGAGE_RADIUS * (1.4 if e.is_in_combat() else 1.0)
		if d > limit or not w.has_line_of_sight(pos, e.global_position):
			continue
		out.append([d, e])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out.map(func(x: Array) -> Enemy: return x[1])


func _emergency(p: Player, w: World, enemies: Array) -> bool:
	if p.life_ratio() >= 0.3 or enemies.is_empty():
		return false
	var pos := p.global_position
	var nearest: Enemy = enemies[0]
	var d := CombatQuery.distance_xz(pos, nearest.global_position)
	if d < 4.0 and p.can_dodge():
		var away := _away_dir(w, pos, _centroid(enemies, pos, 8.0))
		_release(p)
		_stop(p)
		p.ai_dodge(away)
		if p.dodging:
			stats["dodges"] += 1
			_status = "dodging away"
			return true
	var c := GameState.character
	if c.get_potion_charges("life") < 1.0 and not p.is_potion_active("life"):
		_release(p)
		# Get some room first: the cast roots the player for a second.
		if d < 3.5:
			_kite(p, w, _centroid(enemies, pos, 8.0))
			_direct_left = 0.8
			_status = "running away to cast Town Portal"
			return true
		_stop(p)
		if p.ai_town_portal():
			stats["portals_cast"] += 1
			_say("low life (%d%%), no potions: casting Town Portal" % int(p.life_ratio() * 100.0))
			_status = "fleeing to town"
			return true
	return false


func _fight(p: Player, w: World, enemies: Array) -> void:
	var pos := p.global_position
	var tgt := _pick_target(p, enemies)
	var tpos := tgt.global_position
	var dist := maxf(0.0, CombatQuery.distance_xz(pos, tpos) - tgt.get_collision_radius())
	var near_me := 0
	var near_tgt := 0
	for e: Enemy in enemies:
		if CombatQuery.distance_xz(pos, e.global_position) < 4.0:
			near_me += 1
		if CombatQuery.distance_xz(tpos, e.global_position) < 3.5:
			near_tgt += 1
	var ch := _choose_skill(p, w, tgt, dist, near_me, near_tgt, enemies)
	if ch.is_empty():
		_release(p)
		if dist < 2.5:
			_kite(p, w, tpos)
		else:
			_stop(p)
		_status = "no usable skill vs %s" % tgt.display_name
		return
	var kind := String(ch["kind"])
	var reach := float(ch["reach"])
	_status = "fighting %s %.1fm [%s]" % [tgt.display_name, dist, ch["id"]]
	# Projectiles stop at walls: the grid line of sight can pass where a wall corner still blocks.
	var clear := not bool(ch["ranged"]) or CombatQuery.has_line_of_sight(pos, tpos)
	if kind in ["buff", "blink", "nova"] or (dist <= reach and clear):
		if bool(ch["ranged"]) and near_me > 0 and p.life_ratio() < 0.55 and dist < 2.5 and randf() < 0.35:
			_release(p)
			_kite(p, w, tpos)
			return
		var aim: Vector3 = ch.get("aim", tpos)
		p.ai_aim(aim, null if kind == "blink" else tgt)
		_hold(p, int(ch["slot"]), String(ch["id"]))
		if not (kind in ["buff", "blink"]):
			_target_attack_time += THINK_INTERVAL
		if kind == "channel" and dist > 1.2:
			_move_to(tpos, tgt)
		else:
			_stop(p)
	else:
		_release(p)
		_move_to(tpos, tgt)


func _pick_target(p: Player, enemies: Array) -> Enemy:
	var keep := _target != null and is_instance_valid(_target) and not _target.dead and enemies.has(_target)
	var nearest: Enemy = enemies[0]
	if keep:
		# Switch when something much closer shows up.
		var dk := CombatQuery.distance_xz(p.global_position, _target.global_position)
		var dn := CombatQuery.distance_xz(p.global_position, nearest.global_position)
		if dn + 3.0 < dk:
			keep = false
	if not keep:
		_target = nearest
		_target_since = _time
		_target_attack_time = 0.0
		_target_life = nearest.life
	if _target.life < _target_life - 0.01:
		_target_life = _target.life
		_target_attack_time = 0.0
		_target_since = _time
		_progress()
	elif _target_attack_time > TARGET_NO_DAMAGE_TIME or _time - _target_since > TARGET_CHASE_TIME:
		_say("can't hurt %s (attacked %.0fs, chased %.0fs without damage): ignoring it for a while" % [_target.display_name, _target_attack_time, _time - _target_since])
		_blacklist_node(_target, BLACKLIST_TIME)
		var other: Enemy = nearest if nearest != _target else (enemies[1] if enemies.size() > 1 else nearest)
		_target = other
		_target_since = _time
		_target_attack_time = 0.0
		_target_life = other.life
	return _target


func _choose_skill(p: Player, w: World, tgt: Enemy, dist: float, near_me: int, near_tgt: int, enemies: Array) -> Dictionary:
	var best := {}
	var best_score := 0.0
	var runner := p.skill_runner
	if runner == null or not is_instance_valid(runner):
		return best
	var pos := p.global_position
	var tpos := tgt.global_position
	var low_mana := p.max_mana > 0.0 and p.mana < p.max_mana * 0.25
	for slot in 6:
		var id := p.get_skill_in_slot(slot)
		if id == "" or not bool(runner.can_use(id).get("ok", false)):
			continue
		var s := SkillDB.get_resolved(id, p)
		var params: Dictionary = s.get("params", {})
		var delivery := String(s.get("delivery", ""))
		var kind := DebugBotBuild.classify(s)
		var reach := SkillDB.get_skill_range(id, p)
		var entry := {"slot": slot, "id": id, "reach": reach * 0.85, "kind": kind, "ranged": false, "aim": tpos}
		var score := 0.0
		match kind:
			"buff":
				if p.has_buff(String(params.get("buff_id", id))):
					continue
				if near_me >= 2 or tgt.rarity >= 2 or tgt.is_boss or dist < 5.0:
					score = 1.0e6
				else:
					continue
			"move":
				if delivery == "blink":
					if p.life_ratio() < 0.5 and near_me >= 1:
						entry["aim"] = w.get_nearest_walkable(pos + _away_dir(w, pos, _centroid(enemies, pos, 8.0)) * minf(reach, 9.0))
						entry["kind"] = "blink"
						score = 5.0e5
					else:
						continue
				else:
					if dist > 4.5 and dist <= reach * 0.9 and w.has_line_of_sight(pos, tpos):
						entry["kind"] = "leap"
						score = 2.0e5
					else:
						continue
			_:
				var dps := _dps(id, p)
				if dps <= 0.0:
					continue
				var mult := 1.0
				var ranged := delivery in ["projectile", "sequence", "aoe_target", "rain", "chain"]
				if kind == "nova":
					if near_me == 0:
						continue
					mult += 0.45 * float(near_me - 1)
				elif kind in ["aoe", "channel"]:
					mult += 0.45 * float(maxi(0, near_tgt - 1))
				if low_mana and DamageCalc.get_cost(p, s) > 0.0:
					mult *= 0.3
				score = dps * mult
				entry["ranged"] = ranged
				if ranged:
					entry["reach"] = minf(reach * 0.9, 13.0)
		if score > best_score:
			best_score = score
			best = entry
	return best


func _dps(id: String, p: Player) -> float:
	if not _dps_cache.has(id):
		_dps_cache[id] = SkillDB.estimate_dps(id, p)
	return float(_dps_cache[id])


func _loot(p: Player) -> bool:
	var c := GameState.character
	var pos := p.global_position
	var best: GroundItem = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("loot"):
		var gi := n as GroundItem
		if gi == null or not is_instance_valid(gi) or not gi.is_inside_tree() or not gi.enabled or _is_blacklisted(gi):
			continue
		var d := CombatQuery.distance_xz(pos, gi.global_position)
		if d > LOOT_RADIUS or d >= bd:
			continue
		if not gi.is_gold():
			var key := gi.get_instance_id()
			if not _loot_ok.has(key):
				_loot_ok[key] = gi.item != null and gear.should_pick_up(c, gi.item)
			if not bool(_loot_ok[key]):
				continue
		best = gi
		bd = d
	if best == null:
		return false
	_status = "looting %s" % best.get_hover_name()
	_walk_interact(p, best)
	return true


func _visit_interactables(p: Player, w: World) -> bool:
	var pos := p.global_position
	var best: Interactable = null
	var bd := INF
	for n in w.get_interactables():
		var it := n as Interactable
		if it == null or not it.enabled or _is_blacklisted(it):
			continue
		var want := false
		if it is WorldChest:
			want = not (it as WorldChest).opened
		elif it is WorldShrine:
			want = not (it as WorldShrine).used
		if not want or not it.can_interact(p):
			continue
		var d := CombatQuery.distance_xz(pos, it.global_position)
		if d < INTERACT_RADIUS and d < bd:
			best = it
			bd = d
	if best == null:
		return false
	_status = "opening %s" % best.get_hover_name()
	_walk_interact(p, best)
	return true


## After the boss: the exit portals ("Descend" or "Town").
func _take_exit(p: Player, w: World) -> bool:
	if not _cleared_worlds.has(w.get_instance_id()):
		return false
	var c := GameState.character
	var depth := int(w.area_info.get("depth", 1))
	var go_town := c.inventory_free_count() < 16 or _clears_since_town >= 2 or c.level + 1 < depth
	var portal := _find_portal(w, "town" if go_town else "next")
	if portal == null:
		portal = _find_portal(w, "next" if go_town else "town")
	if portal == null:
		return false
	_status = "taking the %s portal" % portal.destination
	_walk_interact(p, portal)
	return true


## Head for the nearest remaining monster (asleep ones included); nothing left -> Town Portal.
func _explore(p: Player, w: World) -> void:
	var pos := p.global_position
	var best: Enemy = null
	var bd := INF
	for e in EnemyDB.get_enemies(w):
		if e.dead or _is_blacklisted(e):
			continue
		var d := CombatQuery.distance_xz(pos, e.global_position)
		if d < bd:
			bd = d
			best = e
	if best != null:
		_status = "exploring toward %s (%dm)" % [best.display_name, int(bd)]
		_move_to(best.global_position, best)
		return
	_stop(p)
	_status = "area empty: town portal"
	if not p.is_casting_portal() and p.ai_town_portal():
		stats["portals_cast"] += 1
		_say("nothing left to fight here: casting Town Portal")


# ------------------------------------------------------------------ town

func _plan_town() -> void:
	var c := GameState.character
	_town_tasks.clear()
	_gear_dirty = true
	var junk := 0
	for it in c.inventory:
		if it != null and (it as Item).rarity != Item.Rarity.UNIQUE:
			junk += 1
	if junk > 0 or c.gold >= 60:
		_town_tasks.append("vendor")
	var stashable := 0
	for it in c.inventory:
		if it != null and gear.should_stash(c, it):
			stashable += 1
	if stashable > 0:
		_town_tasks.append("stash")
	_town_tasks.append("leave")
	_task_since = _time


func _next_task() -> void:
	if not _town_tasks.is_empty():
		_town_tasks.pop_front()
	_task_since = _time
	_mode = Mode.NONE


func _think_town(p: Player) -> void:
	if _town_tasks.is_empty():
		_plan_town()
	var task: String = _town_tasks[0]
	if _time - _task_since > TOWN_TASK_TIMEOUT:
		_say("town task '%s' timed out" % task)
		UI.close_all_panels()
		_next_task()
		return
	var w := GameState.world
	match task:
		"vendor":
			_status = "visiting the merchant"
			if UI.is_panel_open("vendor"):
				_do_vendor(p)
				UI.close_all_panels()
				_next_task()
			else:
				_walk_interact(p, _find_interactable(w, "WorldVendorNpc"))
		"stash":
			_status = "visiting the stash"
			if UI.is_panel_open("stash"):
				_do_stash()
				UI.close_all_panels()
				_next_task()
			else:
				_walk_interact(p, _find_interactable(w, "WorldStashChest"))
		"leave":
			_leave_town(p, w)


func _leave_town(p: Player, w: World) -> void:
	var c := GameState.character
	var kept: World = main.call("get_kept_world")
	if kept != null and not _cleared_worlds.has(kept.get_instance_id()):
		var rp := _find_portal(w, "return")
		if rp != null:
			_status = "returning to depth %d" % int(kept.area_info.get("depth", 1))
			_walk_interact(p, rp)
			return
	if UI.is_panel_open("waypoint"):
		var depth := c.max_depth
		if int(_deaths_at.get(depth, 0)) >= 2 and depth > 1:
			depth -= 1
		var wp := UI.get_panel("waypoint")
		_say("waypoint -> depth %d (level %d, max depth %d)" % [depth, c.level, c.max_depth])
		var ok := false
		if wp != null and wp.has_method("travel_to"):
			ok = bool(wp.call("travel_to", depth))
		if not ok:
			UI.close_all_panels()
			Events.area_change_requested.emit("dungeon", {"depth": depth})
		return
	_status = "walking to the Dungeon Gate"
	_walk_interact(p, _find_interactable(w, "WorldWaypointGate"))


func _do_vendor(p: Player) -> void:
	var c := GameState.character
	var gold0 := c.gold
	var sold := 0
	for i in c.inventory.size():
		var it: Item = c.inventory[i]
		if it != null and gear.should_sell(c, it):
			c.take_from_inventory(i)
			c.add_gold(maxi(1, it.get_sell_value()))
			sold += 1
	stats["sold"] += sold
	var bought := 0
	var vp := UI.get_panel("vendor")
	for k in 3:
		var idx := gear.best_purchase(c)
		if idx < 0:
			break
		var it: Item = GameState.vendor_stock[idx]
		var ok := false
		if vp != null and vp.has_method("buy_stock"):
			ok = bool((vp.call("buy_stock", idx) as Dictionary).get("ok", false))
		elif c.spend_gold(it.get_buy_value()):
			GameState.vendor_stock.remove_at(idx)
			ok = c.add_to_inventory(it)
		if not ok:
			break
		bought += 1
		_say("bought %s for %d gold" % [it.get_display_name(), it.get_buy_value()])
		_equip_upgrades()
	stats["bought"] += bought
	_say("merchant: sold %d items, bought %d (gold %d -> %d)" % [sold, bought, gold0, c.gold])


func _do_stash() -> void:
	var c := GameState.character
	var n := 0
	for i in c.inventory.size():
		var it: Item = c.inventory[i]
		if it == null or c.first_free_stash_index() < 0:
			continue
		if gear.should_stash(c, it):
			c.take_from_inventory(i)
			c.add_to_stash(it)
			n += 1
	stats["stashed"] += n
	_say("stash: deposited %d items" % n)


# ------------------------------------------------------------------ death

func _think_dead(p: Player) -> void:
	_release(p)
	_stop(p)
	_status = "dead"
	if _dead_since < 0.0:
		_dead_since = _time
	var waited := _time - _dead_since
	if UI.is_panel_open("death") and waited > 2.4:
		var d := UI.get_panel("death")
		if d != null and d.has_method("respawn"):
			d.call("respawn")
		else:
			Events.respawn_requested.emit()
		_dead_since = _time + 5.0
	elif waited > 8.0:
		_say("death screen missing: requesting respawn")
		Events.respawn_requested.emit()
		_dead_since = _time


# ------------------------------------------------------------------ movement

func _move_to(goal: Vector3, node: Node = null) -> void:
	if _mode != Mode.PATH or _goal.distance_to(goal) > 1.5:
		_mode = Mode.PATH
		_path = PackedVector3Array()
		_path_i = 0
		_repath = 0.0
	_goal = goal
	_goal_node = node


func _stop(p: Player) -> void:
	if _mode == Mode.AUTO:
		p.cancel_auto_walk()
	_mode = Mode.NONE
	p.ai_move(Vector3.ZERO)


func _kite(p: Player, w: World, from: Vector3) -> void:
	var pos := p.global_position
	_dir = _away_dir(w, pos, from)
	_mode = Mode.DIRECT
	_direct_left = 0.45
	_status = "backing off"


## Walk to an interactable and use it, like a click (Player.ai_interact). If the player's
## auto-walk gives up twice, the bot steers there itself and interacts once in range.
func _walk_interact(p: Player, target: Node) -> void:
	if target == null or not is_instance_valid(target) or not (target is Interactable):
		return
	var it := target as Interactable
	var goal := it.get_interact_position()
	var d := CombatQuery.distance_xz(p.global_position, goal)
	if (_mode == Mode.AUTO or _mode == Mode.PATH) and _auto_target == target:
		if _time - _auto_since > _auto_timeout:
			_say("could not reach %s: skipping it (%s)" % [it.get_hover_name(), _diag(p, it)])
			_blacklist_node(target, BLACKLIST_TIME)
			_stop(p)
			_auto_target = null
			return
		if _auto_retries >= 2:
			# Fallback: our own path, then interact in range (what the auto-walk does).
			if d <= it.get_interact_range() - 0.15:
				_stop(p)
				it.interact(p)
				_auto_target = null
				return
			_move_to(goal, target)
			return
		if _mode == Mode.AUTO and p.is_auto_walking():
			return
		_auto_retries += 1
		if _auto_retries >= 2:
			return
	else:
		_auto_since = _time
		_auto_retries = 0
		# Generous for long walks: path length at walking speed, plus slack.
		var pd := GameState.world.get_path_distance(p.global_position, goal) if is_instance_valid(GameState.world) else d
		_auto_timeout = AUTO_WALK_TIMEOUT + (pd if pd < INF else d) / maxf(1.0, p.get_move_speed()) * 1.5
	_release(p)
	_mode = Mode.AUTO
	_auto_target = target
	p.ai_move(Vector3.ZERO)
	p.ai_interact(it)


func _diag(p: Player, it: Interactable) -> String:
	var rv := p.get_real_velocity()
	var busy := p.skill_runner != null and is_instance_valid(p.skill_runner) and p.skill_runner.is_busy()
	var near := 0
	for n in get_tree().get_nodes_in_group("enemies"):
		if CombatQuery.distance_xz((n as Node3D).global_position, p.global_position) < 3.0:
			near += 1
	return "player %s -> %s, %.1f m, speed %.1f, busy %s, can act %s, auto-walk %s, retries %d, path %d pts, enemies within 3 m %d" % [
		_v(p.global_position), _v(it.get_interact_position()), CombatQuery.distance_xz(p.global_position, it.get_interact_position()),
		Vector2(rv.x, rv.z).length(), str(busy), str(p.can_act()), str(p.is_auto_walking()), _auto_retries,
		GameState.world.find_path(p.global_position, it.get_interact_position()).size(), near]


func _steer(p: Player, delta: float) -> void:
	match _mode:
		Mode.PATH:
			var pos := p.global_position
			_repath -= delta
			if _path.is_empty() or _repath <= 0.0:
				_path = GameState.world.find_path(pos, _goal) if is_instance_valid(GameState.world) else PackedVector3Array()
				_path_i = 0
				_repath = REPATH_TIME
				if _path.is_empty():
					if _goal_node != null and is_instance_valid(_goal_node):
						_blacklist_node(_goal_node, BLACKLIST_TIME)
					_mode = Mode.NONE
					p.ai_move(Vector3.ZERO)
					return
			while _path_i < _path.size() and CombatQuery.distance_xz(pos, _path[_path_i]) < WAYPOINT_REACHED:
				_path_i += 1
			if _path_i >= _path.size():
				_mode = Mode.NONE
				p.ai_move(Vector3.ZERO)
				return
			var d := _path[_path_i] - pos
			d.y = 0.0
			p.ai_move(d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO)
		Mode.DIRECT:
			p.ai_move(_dir)
			_direct_left -= delta
			if _direct_left <= 0.0:
				_mode = Mode.NONE
				p.ai_move(Vector3.ZERO)
		Mode.AUTO:
			if not p.is_auto_walking() and (_auto_target == null or not is_instance_valid(_auto_target)):
				_mode = Mode.NONE


func _hold(p: Player, slot: int, id: String) -> void:
	if _held_slot == slot and _held_id == id and p.is_slot_held(slot):
		return
	_release(p)
	p.ai_hold_skill(slot, true)
	_held_slot = slot
	_held_id = id


func _release(p: Player) -> void:
	if _held_slot >= 0:
		p.ai_hold_skill(_held_slot, false)
	_held_slot = -1
	_held_id = ""


# ------------------------------------------------------------------ progress / stuck

func _progress() -> void:
	_last_progress = _time


func _check_progress(p: Player) -> void:
	var pos := p.global_position
	if _progress_anchor == Vector3.INF or pos.distance_to(_progress_anchor) > 6.0:
		_progress_anchor = pos
		_progress()
	if _time - _last_progress < PROGRESS_TIMEOUT:
		return
	stats["stuck"] += 1
	_last_progress = _time
	_say("STUCK #%d: no progress for %ds at %s in %s (status: %s, mode %d, goal %s, path %d/%d)" % [
		stats["stuck"], int(PROGRESS_TIMEOUT), _v(pos), String(GameState.current_area.get("name", "?")),
		_status, _mode, _v(_goal), _path_i, _path.size()])
	# Recover: forget the goal, drop everything, leave the area.
	if _goal_node != null and is_instance_valid(_goal_node):
		_blacklist_node(_goal_node, 120.0)
	if _auto_target != null and is_instance_valid(_auto_target):
		_blacklist_node(_auto_target, 120.0)
	_release(p)
	_stop(p)
	UI.close_all_panels()
	if GameState.is_in_town():
		_town_tasks.clear()
	elif not p.dead:
		if p.ai_town_portal():
			stats["portals_cast"] += 1
	if int(stats["stuck"]) >= MAX_STUCK_EVENTS:
		_say("giving up after %d stuck events" % stats["stuck"])
		_finish()


# ------------------------------------------------------------------ events

func _on_area_entered(info: Dictionary) -> void:
	stats["area_changes"] += 1
	_progress()
	_mode = Mode.NONE
	_path = PackedVector3Array()
	_auto_target = null
	_target = null
	_held_slot = -1
	_held_id = ""
	_blacklist.clear()
	_loot_ok.clear()
	var c := GameState.character
	if String(info.get("id", "")) == "town":
		stats["town_visits"] += 1
		_clears_since_town = 0
		if not _boosted:
			_boosted = true
			_boost()
		_plan_town()
		_say("entered %s (level %d, gold %d, max depth %d)" % [String(info.get("name", "town")), c.level, c.gold, c.max_depth])
	else:
		var depth := int(info.get("depth", 1))
		stats["max_depth"] = maxi(int(stats["max_depth"]), depth)
		_say("entered %s (level %d, %d monsters)" % [String(info.get("name", "?")), c.level, EnemyDB.get_enemies(GameState.world).size()])


func _on_player_spawned(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	var r := p.skill_runner
	if r != null and r != _hooked_runner:
		_hooked_runner = r
		r.skill_started.connect(func(id: String, _anim: String, _d: float) -> void:
			var sk: Dictionary = stats["skills"]
			sk[id] = int(sk.get(id, 0)) + 1)


func _on_boss_cleared(depth: int) -> void:
	stats["bosses"] += 1
	(stats["cleared"] as Array).append(depth)
	_clears_since_town += 1
	if is_instance_valid(GameState.world):
		_cleared_worlds[GameState.world.get_instance_id()] = true
	_progress()
	_say("BOSS of depth %d killed (level %d)" % [depth, GameState.character.level])


func _on_enemy_killed(enemy: Node) -> void:
	stats["kills"] += 1
	var r := 0
	var e := enemy as Enemy
	if e != null:
		r = clampi(3 if e.is_boss else e.rarity, 0, 3)
	(stats["kills_by_rarity"] as Array)[r] += 1
	_progress()


func _on_item_picked_up(item: RefCounted) -> void:
	var it := item as Item
	if it == null:
		return
	(stats["items"] as Array)[clampi(it.rarity, 0, 3)] += 1
	_gear_dirty = true
	_progress()
	if it.rarity >= Item.Rarity.RARE:
		_say("picked up %s [%s, ilvl %d]" % [it.get_display_name(), UIStyle.RARITY_NAMES[it.rarity], it.item_level])


func _on_gold_picked_up(amount: int) -> void:
	stats["gold"] += amount
	_progress()


func _on_level_up(new_level: int) -> void:
	_bar_dirty = true
	_gear_dirty = true
	_progress()
	_say("LEVEL %d" % new_level)


func _on_player_died() -> void:
	stats["deaths"] += 1
	var depth := int(GameState.current_area.get("depth", 0))
	_deaths_at[depth] = int(_deaths_at.get(depth, 0)) + 1
	_say("DIED in %s (level %d, death #%d)" % [String(GameState.current_area.get("name", "?")), GameState.character.level, stats["deaths"]])


# ------------------------------------------------------------------ boost (--depth)

func _boost() -> void:
	var depth := int(config.get("depth", 1))
	if depth <= 1:
		return
	var c := GameState.character
	depth = mini(depth, Balance.MAX_DEPTH)
	c.max_depth = maxi(c.max_depth, depth)
	var target := clampi(depth + 1, 1, Balance.MAX_LEVEL)
	while c.level < target and not c.is_max_level():
		c.add_xp(maxi(1, c.xp_to_next() - c.xp))
	c.add_gold(150 * depth)
	for it in gear.boost_items(depth):
		c.add_to_inventory(it)
	_gear_dirty = true
	_bar_dirty = true
	_say("boosted for depth %d: level %d, %d gold, gear to choose from" % [depth, c.level, c.gold])


# ------------------------------------------------------------------ helpers

## The nearest enabled, not blacklisted portal to `destination` (a dungeon has two "town"
## portals: the start room's and the boss exit).
func _find_portal(w: World, destination: String) -> WorldPortal:
	if w == null:
		return null
	var best: WorldPortal = null
	var bd := INF
	var from := Vector3.ZERO
	var p := _player()
	if p != null:
		from = p.global_position
	for n in w.get_interactables():
		if n is WorldPortal and (n as WorldPortal).destination == destination and (n as WorldPortal).enabled and not _is_blacklisted(n):
			var d := CombatQuery.distance_xz(from, (n as Node3D).global_position)
			if d < bd:
				bd = d
				best = n
	return best


func _find_interactable(w: World, cls: String) -> Interactable:
	if w == null:
		return null
	for n in w.get_interactables():
		var s: Script = (n as Node).get_script()
		if s != null and s.get_global_name() == cls:
			return n
	return null


func _blacklist_node(n: Node, seconds: float) -> void:
	if n != null and is_instance_valid(n):
		_blacklist[n.get_instance_id()] = _time + seconds


func _is_blacklisted(n: Node) -> bool:
	var id := n.get_instance_id()
	if not _blacklist.has(id):
		return false
	if _time > float(_blacklist[id]):
		_blacklist.erase(id)
		return false
	return true


## Average position of the enemies within `radius` of `pos` (pos itself when none).
func _centroid(enemies: Array, pos: Vector3, radius: float) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for e: Enemy in enemies:
		if is_instance_valid(e) and CombatQuery.distance_xz(pos, e.global_position) <= radius:
			sum += e.global_position
			n += 1
	return sum / float(n) if n > 0 else pos


## A walkable direction away from `from` (tries the straight line, then +-45 and +-90 degrees).
func _away_dir(w: World, pos: Vector3, from: Vector3) -> Vector3:
	var d := pos - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	d = d.normalized()
	for a in [0.0, 0.785, -0.785, 1.571, -1.571, 2.356, -2.356]:
		var r := d.rotated(Vector3.UP, a)
		if w.is_walkable(pos + r * 2.5) and w.is_walkable(pos + r * 5.0):
			return r
	return d


func _say(msg: String) -> void:
	print("[autoplay %5.1fs] %s" % [_time, msg])


static func _v(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]


func _log_status() -> void:
	var c := GameState.character
	var p := _player()
	if c == null:
		return
	var life := "-"
	if p != null:
		life = "life %d/%d mana %d/%d es %d" % [int(p.life), int(p.max_life), int(p.mana), int(p.max_mana), int(p.es)]
	var kr: Array = stats["kills_by_rarity"]
	var it: Array = stats["items"]
	_say("STATUS %s | L%d %d/%dxp | %s | kills %d (magic %d, rare %d, boss %d) | deaths %d | items %d/%d/%d/%d | gold %d | pts %d | %s | errors %d warnings %d" % [
		String(GameState.current_area.get("name", "?")), c.level, c.xp, c.xp_to_next(), life,
		stats["kills"], kr[1], kr[2], kr[3], stats["deaths"], it[0], it[1], it[2], it[3], c.gold,
		c.passive_points_unspent(), _status, err_log.get_error_count(), err_log.get_warning_count()])


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var p := _player()
	if p != null:
		_release(p)
		_stop(p)
	var c := GameState.character
	var errors := err_log.get_error_count() if err_log != null else 0
	var warnings := err_log.get_warning_count() if err_log != null else 0
	var kr: Array = stats["kills_by_rarity"]
	var it: Array = stats["items"]
	print("")
	_say("================ AUTOPLAY SUMMARY ================")
	_say("class %s, %.0f s of game time (%.0f s wall)" % [class_id, _time, (Time.get_ticks_msec() - _wall_start) / 1000.0])
	if c != null:
		_say("level %d (%d/%d xp), gold %d, max depth %d, depths cleared %s" % [c.level, c.xp, c.xp_to_next(), c.gold, c.max_depth, str(stats["cleared"])])
		_say("passives %d allocated (%d unspent), skill bar: %s" % [c.allocated_passives.size(), c.passive_points_unspent(), ", ".join(PackedStringArray(Array(c.skill_bar)))])
		var eq: PackedStringArray = []
		for slot in CharacterData.EQUIP_SLOTS:
			var e: Item = c.get_equipped(slot)
			if e != null:
				eq.append("%s=%s" % [slot, e.get_display_name()])
		_say("equipment: %s" % ", ".join(eq))
	_say("kills %d (normal %d, magic %d, rare %d, boss %d), deaths %d" % [stats["kills"], kr[0], kr[1], kr[2], kr[3], stats["deaths"]])
	_say("items picked up: normal %d, magic %d, rare %d, unique %d; gold picked up %d" % [it[0], it[1], it[2], it[3], stats["gold"]])
	_say("equipped %d upgrades, sold %d, bought %d, stashed %d; potions %d, dodges %d, town portals %d" % [stats["equips"], stats["sold"], stats["bought"], stats["stashed"], stats["potions"], stats["dodges"], stats["portals_cast"]])
	_say("area changes %d, town visits %d, deepest depth entered %d, stuck events %d" % [stats["area_changes"], stats["town_visits"], stats["max_depth"], stats["stuck"]])
	_say("skills used: %s" % str(stats["skills"]))
	_say("engine/script errors %d, warnings %d" % [errors, warnings])
	if err_log != null:
		for e in err_log.get_errors():
			_say("  ERROR " + e)
		var ws := err_log.get_warnings()
		for i in mini(ws.size(), 12):
			_say("  warning " + ws[i])
	var code := 0
	if errors > 0:
		code = 1
	elif int(stats["stuck"]) > 0:
		code = 2
	elif int(stats["kills"]) == 0:
		code = 3
	_say("RESULT: %s (exit code %d)" % ["HEALTHY" if code == 0 else "UNHEALTHY", code])
	if c != null:
		GameState.save_game()
	get_tree().quit(code)

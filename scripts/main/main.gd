extends Node
## Main scene script: boots into the main menu and runs the game loop (area changes, spawning the
## player / camera / enemies, death and respawn, autosave, debug keys, autoplay and screenshot
## tour command-line modes). OWNER: game flow (wave 2). CONTRACT STUB.
## See docs/ARCHITECTURE.md §15.
##
## Boot: UI.show_main_menu() (after a short fade from black). Command line (after `--`):
##   --autoplay=SECONDS [--class=warrior|ranger|sorcerer] [--depth=N] [--seed=N]
##        skip the menu, play with the autoplay bot (scripts/debug/debug_autoplay.gd), quit with
##        0 when healthy (non-zero when stuck / errors / no progress)
##   --shots=DIR   screenshot tour (scripts/debug/debug_shot_tour.gd); needs a real window
##
## Area change (§15), handled for Events.area_change_requested / town_portal_requested /
## respawn_requested and the new game / load requests. Requests while a change is running (or
## while the player lies dead, except the respawn) are ignored. The change itself runs deferred
## (after a short fade to black, see FlowFade), synchronously:
##   1. close panels; remember the player's pool ratios; free the player and the camera rig
##   2. keep the old dungeon (town with keep_dungeon, or a death respawn) detached in
##      GameState.town_portal_state = {"world", "position"}, else free it; a fresh dungeon
##      discards a kept one
##   3. new World (in the tree before build) or, for "dungeon_return", the kept World re-attached
##   4. world.build(info)
##   5. Player at the start (return: where the portal was cast), pool ratios (town: full)
##   6. CameraRig, snap, world.snap_light_pool()
##   7. fresh dungeons: EnemyDB.populate_area(); return: world.spawn_town_portal(position)
##   8. town entry: refill potions, rebuild GameState.vendor_stock
##   9. Events.player_spawned, Events.area_entered; autosave; fade in (+ optional title card)
## Boss kill: depth cleared (bonus passive point on the first clear up to depth 20), max_depth,
## exit portals, Events.area_cleared, notifications, autosave.
## Death: 1.5 s -> death panel -> Events.respawn_requested -> lose 10% of the level's XP -> town at
## full life, dungeon kept (portal at its start; living bosses reset via EnemyDB.reset_bosses).
## Autosave: area change, level up, boss kill, return to menu, quit (and window close).
## Debug builds: F9 level up, F10 spawn 6 items, F11 god mode, F12 screenshot (FlowDebugKeys).
##
## Public API (bot, tour, tests): start_new_game, load_game, request_area_change, respawn,
## return_to_menu, quit_game, is_changing, is_awaiting_respawn, get_player, get_kept_world,
## show_main_menu, parse_args; signals area_change_started / area_change_finished /
## boss_cleared / death_screen_shown / returned_to_menu.

const FlowFade := preload("res://scripts/main/flow_fade.gd")
const FlowAreas := preload("res://scripts/main/flow_areas.gd")
const FlowDebugKeys := preload("res://scripts/main/flow_debug_keys.gd")
const AUTOPLAY_SCRIPT := "res://scripts/debug/debug_autoplay.gd"
const SHOT_TOUR_SCRIPT := "res://scripts/debug/debug_shot_tour.gd"

signal area_change_started(area_id: String, params: Dictionary)
signal area_change_finished(area_info: Dictionary)
signal boss_cleared(depth: int)
signal death_screen_shown()
signal returned_to_menu()

const DEATH_PANEL_DELAY := 1.5
const FADE_OUT_TIME := 0.22
const FADE_IN_TIME := 0.5
const BOOT_FADE_IN := 0.8

## false: _ready() neither shows the main menu nor reads the command line (tests, tools).
var auto_boot := true
## false: area changes run right away in a deferred call, no fade (tests).
var use_fade := true
## Area title card (FlowFade.show_title) after each change. Off by default: the HUD shows its own
## area banner (HudAreaBanner) on Events.area_entered. Enable for builds without that HUD.
var show_titles := false
var autosave_enabled := true
var debug_keys_enabled := OS.is_debug_build()
var death_panel_delay := DEATH_PANEL_DELAY

## The live camera rig (child of the current World), or null.
var camera_rig: CameraRig = null
var fade: FlowFade = null
## Parsed command line, see parse_args().
var args: Dictionary = {}
## The autoplay bot / screenshot tour node when running in those modes.
var bot: Node = null
var tour: Node = null
## Completed area changes (tests / bot statistics).
var changes_done := 0

var _changing := false
var _change_id := ""
var _death_timer := -1.0
var _awaiting_respawn := false
var _save_queued := false
var _menu_queued := false
## God mode survives area changes (F11 is a debug toggle for the session).
var _god_mode := false
## Mirror of GameState.town_portal_state.world (freed with Main if still detached).
var _kept_world: World = null


func _ready() -> void:
	fade = FlowFade.new()
	add_child(fade)
	Events.new_game_requested.connect(_on_new_game_requested)
	Events.load_game_requested.connect(_on_load_game_requested)
	Events.area_change_requested.connect(_on_area_change_requested)
	Events.town_portal_requested.connect(_on_town_portal_requested)
	Events.boss_killed.connect(_on_boss_killed)
	Events.player_died.connect(_on_player_died)
	Events.respawn_requested.connect(_on_respawn_requested)
	Events.return_to_menu_requested.connect(_on_return_to_menu_requested)
	Events.quit_requested.connect(_on_quit_requested)
	Events.level_up.connect(_on_level_up)
	if not auto_boot:
		return
	args = parse_args(OS.get_cmdline_user_args())
	if args.has("autoplay"):
		_start_mode(AUTOPLAY_SCRIPT, "bot")
	elif args.has("shots"):
		_start_mode(SHOT_TOUR_SCRIPT, "tour")
	else:
		show_main_menu()


func _exit_tree() -> void:
	var kw := get_kept_world()
	if kw != null and not kw.is_inside_tree():
		kw.queue_free()
	if _kept_world != null and is_instance_valid(_kept_world) and not _kept_world.is_inside_tree():
		_kept_world.queue_free()
	_kept_world = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _in_game():
			_apply_pending_death_penalty()
			_save_now()


func _process(delta: float) -> void:
	if _death_timer > 0.0:
		_death_timer -= delta
		if _death_timer <= 0.0:
			_death_timer = -1.0
			_show_death_screen()


func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys_enabled:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if event.is_action_pressed("debug_screenshot"):
		FlowDebugKeys.screenshot(get_viewport())
		get_viewport().set_input_as_handled()
		return
	if not _in_game() or _changing or UI.is_modal_open():
		return
	if event.is_action_pressed("debug_level_up"):
		FlowDebugKeys.level_up()
	elif event.is_action_pressed("debug_spawn_loot"):
		FlowDebugKeys.spawn_loot()
	elif event.is_action_pressed("debug_god_mode"):
		_god_mode = FlowDebugKeys.toggle_god_mode()
	else:
		return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ public API

## Parse `-- --key=value` user args: autoplay (float s, default 120), class, depth (int), seed
## (int), shots (dir); other --key[=value] pairs are kept as strings.
static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		var key := kv[0]
		var val := kv[1] if kv.size() > 1 else ""
		match key:
			"autoplay":
				out["autoplay"] = float(val) if val.is_valid_float() else 120.0
			"depth", "seed":
				if val.is_valid_int():
					out[key] = int(val)
			_:
				out[key] = val
	return out


## Title screen (fades in from black on boot). Without a main menu panel the most recent save is
## loaded (or a new warrior created) so the game stays playable.
func show_main_menu() -> void:
	UI.show_main_menu()
	if use_fade and fade != null:
		fade.set_black()
		fade.fade_in(BOOT_FADE_IN)
	if not UI.is_panel_open("main_menu"):
		push_warning("Main: no main menu panel; starting the game directly")
		var saves := GameState.list_saves()
		if not saves.is_empty() and load_game(String(saves[0]["save_id"])):
			return
		start_new_game("Hero", ClassDefs.DEFAULT_CLASS)


## Create a character, save it and enter the town. False while a change is running.
func start_new_game(char_name: String, class_id: String) -> bool:
	if _changing:
		return false
	if _in_game():
		push_warning("Main: new game requested while playing; ignored")
		return false
	_discard_kept_world()
	GameState.new_character(char_name, class_id)
	_save_now()
	return _begin_change("town", {"reason": "new_game"})


## Load a save and enter the town. False (with a notification) when the save can't be read.
func load_game(p_save_id: String) -> bool:
	if _changing:
		return false
	if _in_game():
		push_warning("Main: load requested while playing; ignored")
		return false
	if not GameState.load_game(p_save_id):
		Events.notify.emit("Could not load this character", UIStyle.COLOR_BAD)
		return false
	_discard_kept_world()
	_sanitize_character(GameState.character)
	return _begin_change("town", {"reason": "load"})


## Validate and start an area change (see Events.area_change_requested for ids/params; params may
## also carry "seed" for dungeons). Returns false when the request is ignored.
func request_area_change(area_id: String, params: Dictionary = {}) -> bool:
	if _changing:
		return false
	if GameState.character == null:
		push_warning("Main: area change '%s' without a character; ignored" % area_id)
		return false
	var p := get_player()
	if p != null and p.dead:
		return false
	if _awaiting_respawn:
		return false
	match area_id:
		"town":
			if GameState.is_in_town() and is_instance_valid(GameState.world) and not params.has("reason"):
				return false
		"dungeon":
			pass
		"dungeon_return":
			if get_kept_world() == null:
				push_warning("Main: dungeon_return without a kept dungeon; ignored")
				return false
		_:
			push_warning("Main: unknown area id '%s'" % area_id)
			return false
	return _begin_change(area_id, params)


## Respawn in town after a death (applies the XP penalty). False when not dead / busy.
func respawn() -> bool:
	if _changing or GameState.character == null:
		return false
	var p := get_player()
	var dead := p != null and p.dead
	if not _awaiting_respawn and not dead:
		return false
	_awaiting_respawn = false
	_death_timer = -1.0
	GameState.character.lose_xp_fraction(Balance.DEATH_XP_PENALTY)
	return _begin_change("town", {"respawn": true})


## Save, tear the game down and show the title screen (fades). Queued if a change is running.
func return_to_menu() -> bool:
	if _changing:
		_menu_queued = true
		return true
	if not _in_game():
		UI.show_main_menu()
		return false
	_changing = true
	_change_id = "menu"
	_menu_queued = false
	_death_timer = -1.0
	var p := get_player()
	if p != null:
		p.god_mode = true
	if use_fade and fade != null and is_inside_tree():
		fade.fade_out(FADE_OUT_TIME, _do_return_to_menu)
	else:
		_do_return_to_menu.call_deferred()
	return true


## Save (when playing) and quit.
func quit_game() -> void:
	if _in_game():
		_apply_pending_death_penalty()
		_save_now()
	get_tree().quit()


func is_changing() -> bool:
	return _changing


func is_awaiting_respawn() -> bool:
	return _awaiting_respawn


## The live player (dead or alive) or null.
func get_player() -> Player:
	var p: Variant = GameState.player
	if p != null and is_instance_valid(p):
		return p as Player
	return null


## The dungeon kept for a town portal / death (detached), or null.
func get_kept_world() -> World:
	var w: Variant = GameState.town_portal_state.get("world", null)
	if w != null and is_instance_valid(w) and w is World:
		return w as World
	return null


# ------------------------------------------------------------------ event handlers

func _on_new_game_requested(char_name: String, class_id: String) -> void:
	start_new_game(char_name, class_id)


func _on_load_game_requested(p_save_id: String) -> void:
	load_game(p_save_id)


func _on_area_change_requested(area_id: String, params: Dictionary) -> void:
	request_area_change(area_id, params)


func _on_town_portal_requested() -> void:
	request_area_change("town", {"keep_dungeon": true})


func _on_respawn_requested() -> void:
	respawn()


func _on_return_to_menu_requested() -> void:
	return_to_menu()


func _on_quit_requested() -> void:
	quit_game()


func _on_level_up(_new_level: int) -> void:
	_queue_save()


func _on_player_died() -> void:
	if _changing or GameState.character == null:
		return
	var p := get_player()
	if p == null or not p.dead:
		return
	_awaiting_respawn = true
	_death_timer = maxf(death_panel_delay, 0.001)


func _show_death_screen() -> void:
	if not _awaiting_respawn or _changing:
		return
	UI.close_all_panels()
	UI.open_panel("death", {})
	death_screen_shown.emit()
	if not UI.is_panel_open("death"):
		# No death screen available: respawn anyway rather than leave the player lying there.
		push_warning("Main: no death screen panel; respawning directly")
		respawn.call_deferred()


func _on_boss_killed(boss: Node) -> void:
	var w: Variant = GameState.world
	if not is_instance_valid(w) or not (w as World).is_dungeon():
		return
	if not is_instance_valid(boss) or not (w as World).is_ancestor_of(boss):
		return
	_handle_boss_kill.call_deferred(w, (boss as Node3D).global_position)


func _handle_boss_kill(w: World, pos: Vector3) -> void:
	if not is_instance_valid(w) or w != GameState.world:
		return
	var c := GameState.character
	if c == null:
		return
	var depth := int(w.area_info.get("depth", 1))
	var first := c.mark_depth_cleared(depth)
	var bonus := first and depth <= Balance.BONUS_POINT_MAX_DEPTH
	if bonus:
		c.add_bonus_passive_points(1)
	var old_max := c.max_depth
	c.max_depth = mini(Balance.MAX_DEPTH, maxi(c.max_depth, depth + 1))
	w.spawn_exit_portals(pos)
	Events.area_cleared.emit(w.area_info)
	Events.notify.emit("Depth %d cleared!" % depth, UIStyle.COLOR_GOLD)
	if bonus:
		Events.notify.emit("+1 Passive Skill Point", UIStyle.COLOR_GOOD)
	if c.max_depth > old_max:
		Events.notify.emit("Depth %d unlocked" % c.max_depth, UIStyle.COLOR_TEXT)
	_save_now()
	boss_cleared.emit(depth)


# ------------------------------------------------------------------ area change

func _begin_change(area_id: String, params: Dictionary) -> bool:
	_changing = true
	_change_id = area_id
	_death_timer = -1.0
	var p := get_player()
	if p != null:
		# Nothing may kill the player while the screen fades out.
		p.god_mode = true
	area_change_started.emit(area_id, params)
	if use_fade and fade != null and is_inside_tree():
		fade.fade_out(FADE_OUT_TIME, _change_area.bind(area_id, params))
	else:
		_change_area.call_deferred(area_id, params)
	return true


func _change_area(area_id: String, params: Dictionary) -> void:
	var c := GameState.character
	if c == null:
		push_warning("Main: area change without a character; back to the menu")
		_changing = false
		_teardown()
		UI.show_main_menu()
		if fade != null:
			fade.fade_in(FADE_IN_TIME if use_fade else 0.0)
		return
	var respawning := bool(params.get("respawn", false))
	var old_world: World = GameState.world if is_instance_valid(GameState.world) else null
	var old_player := get_player()
	var kept := get_kept_world()
	var id := area_id
	if id == "dungeon_return" and kept == null:
		push_warning("Main: the kept dungeon is gone; opening a fresh one")
		id = "dungeon"
		params = {"depth": c.max_depth}
	var info: Dictionary
	match id:
		"town":
			info = FlowAreas.town_info()
		"dungeon":
			info = FlowAreas.dungeon_info(int(params.get("depth", c.max_depth)), int(params.get("seed", -1)))
		_:
			info = kept.area_info

	# 1. Panels, the old player and camera.
	UI.close_all_panels()
	var ratios := {}
	var old_pos := Vector3.ZERO
	if old_player != null:
		old_pos = old_player.global_position if old_player.is_inside_tree() else old_player.position
		if not old_player.dead:
			ratios = old_player.get_pool_ratios()
	GameState.player = null
	if old_player != null:
		_free_node(old_player)
	if camera_rig != null and is_instance_valid(camera_rig):
		_free_node(camera_rig)
	camera_rig = null

	# 2. The old world: kept (town portal / death) or freed. A fresh dungeon discards a kept one.
	if id == "dungeon":
		_discard_kept_world()
	if old_world != null:
		var keep := id == "town" and old_world.is_dungeon() and (respawning or bool(params.get("keep_dungeon", false)))
		if keep:
			_discard_kept_world()
			var pos := old_world.get_player_start() if respawning else Vector3(old_pos.x, 0.0, old_pos.z)
			if old_world.get_parent() != null:
				old_world.get_parent().remove_child(old_world)
			GameState.town_portal_state = {"world": old_world, "position": pos}
			_kept_world = old_world
			if respawning:
				EnemyDB.reset_bosses(old_world)
		else:
			_free_node(old_world)
	GameState.world = null

	# 3-4. The new world (in the tree before build), or the kept dungeon re-attached.
	var w: World
	var return_pos := Vector3.ZERO
	if id == "dungeon_return":
		w = kept
		return_pos = GameState.town_portal_state.get("position", kept.get_player_start())
		GameState.town_portal_state = {}
		_kept_world = null
		GameState.world = w
		GameState.current_area = info
		add_child(w)
	else:
		w = World.new()
		w.name = "World"
		GameState.world = w
		GameState.current_area = info
		add_child(w)
		w.build(info)

	# 5. The player.
	var start := w.get_player_start()
	if id == "dungeon_return":
		start = w.get_nearest_walkable(return_pos)
	var p := Player.new()
	p.setup(c)
	p.position = start
	GameState.player = p
	w.add_child(p)
	if id != "town" and not ratios.is_empty():
		p.set_pool_ratios(ratios)
	else:
		p.refill_pools()
	p.god_mode = _god_mode

	# 6. Camera.
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	rig.target = p
	w.add_child(rig)
	p.camera_rig = rig
	rig.snap_to_target()
	camera_rig = rig
	w.snap_light_pool()

	# 7. Monsters (fresh dungeons) / the portal home (kept dungeon).
	if id == "dungeon":
		EnemyDB.populate_area(w)
		EnemyDB.apply_sleep(p.global_position)
	elif id == "dungeon_return":
		w.spawn_town_portal(return_pos)
		EnemyDB.apply_sleep(p.global_position)

	# 8. Town services.
	if id == "town":
		c.refill_potions()
		GameState.vendor_stock = ItemDB.generate_vendor_stock(maxi(c.level, Balance.area_level_for_depth(c.max_depth)))

	# 9. Announce, save, show.
	_changing = false
	changes_done += 1
	Events.player_spawned.emit(p)
	Events.area_entered.emit(info)
	_save_now()
	area_change_finished.emit(info)
	if fade != null:
		fade.fade_in(FADE_IN_TIME if use_fade else 0.0)
		if show_titles:
			var t := FlowAreas.title_for(info)
			fade.show_title(t[0], t[1], t[2])
	if _menu_queued:
		_menu_queued = false
		return_to_menu.call_deferred()


func _do_return_to_menu() -> void:
	_apply_pending_death_penalty()
	_save_now()
	UI.close_all_panels()
	_teardown()
	GameState.character = null
	GameState.save_id = ""
	GameState.vendor_stock = []
	if get_tree() != null:
		get_tree().paused = false
	_changing = false
	if fade != null:
		fade.hide_title()
	if use_fade:
		show_main_menu()
	else:
		UI.show_main_menu()
		if fade != null:
			fade.clear()
	returned_to_menu.emit()


## Free the player, camera, current world and any kept dungeon; clear GameState's live refs.
func _teardown() -> void:
	var p := get_player()
	GameState.player = null
	if p != null:
		_free_node(p)
	if camera_rig != null and is_instance_valid(camera_rig):
		_free_node(camera_rig)
	camera_rig = null
	var w: Variant = GameState.world
	GameState.world = null
	if w != null and is_instance_valid(w):
		_free_node(w as Node)
	_discard_kept_world()
	GameState.current_area = {}
	_awaiting_respawn = false
	_death_timer = -1.0


func _discard_kept_world() -> void:
	var kw := get_kept_world()
	GameState.town_portal_state = {}
	if kw != null and kw != GameState.world:
		_free_node(kw)
	if _kept_world != null and is_instance_valid(_kept_world) and _kept_world != GameState.world:
		_free_node(_kept_world)
	_kept_world = null


## Remove from the tree right away (so groups like "enemies"/"actors" forget it this frame) and
## free at the end of the frame.
static func _free_node(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.queue_free()


# ------------------------------------------------------------------ helpers

func _in_game() -> bool:
	return GameState.character != null and (is_instance_valid(GameState.world) or get_player() != null)


## The respawn's XP penalty when leaving the game while dead (it can't be dodged by quitting).
func _apply_pending_death_penalty() -> void:
	if not _awaiting_respawn or GameState.character == null:
		return
	_awaiting_respawn = false
	_death_timer = -1.0
	GameState.character.lose_xp_fraction(Balance.DEATH_XP_PENALTY)


## Clean up a loaded character: passives not connected to the class start (tree changed), more
## allocated passives than points, unknown skill ids on the bar.
func _sanitize_character(c: CharacterData) -> void:
	if c == null:
		return
	var clean := TreeDB.sanitize_allocation(c.allocated_passives, c.class_id)
	var guard := 0
	while clean.size() > c.passive_points_total() and not clean.is_empty() and guard < 1000:
		clean.pop_back()
		clean = TreeDB.sanitize_allocation(clean, c.class_id)
		guard += 1
	if clean != c.allocated_passives:
		push_warning("Main: cleaned the passive allocation of '%s' (%d -> %d nodes)" % [c.char_name, c.allocated_passives.size(), clean.size()])
		c.allocated_passives.assign(clean)
	for i in c.skill_bar.size():
		var sid := c.skill_bar[i]
		if sid != "" and not SkillDB.has_skill(sid):
			push_warning("Main: unknown skill '%s' removed from the bar" % sid)
			c.set_skill_in_slot(i, "")


func _save_now() -> void:
	_save_queued = false
	if not autosave_enabled or GameState.character == null:
		return
	GameState.save_game()


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	if _save_queued:
		_save_now()


func _start_mode(script_path: String, what: String) -> void:
	var script := load(script_path) as GDScript
	if script == null:
		push_warning("Main: %s script missing (%s); showing the menu" % [what, script_path])
		show_main_menu()
		return
	var n: Node = script.new()
	n.name = "Autoplay" if what == "bot" else "ShotTour"
	n.set("main", self)
	n.set("config", args)
	if what == "bot":
		bot = n
	else:
		tour = n
	add_child(n)

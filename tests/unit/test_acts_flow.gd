extends TestCase
## Acts through the real Main node. One seamless World per act: Emberfall -> Act II's town
## (services, waystone) -> walk into the outskirts and on into a higher-level zone (no area change,
## Events.zone_entered, the zone's level, monsters spawning as the player comes near) -> town
## portal (a portal pair in the same World) -> back through it -> walk into town (refill) -> the
## act's dungeon (fade; the act World kept) and back out -> down again to the act boss (portals
## back out and on to the next act) -> Act III -> Emberfall. Monsters off; death in the outskirts
## (town, same World) and in the act dungeon (town, dungeon kept, return portal).
## OWNER: acts framework.

const Main := preload("res://scripts/main/main.gd")
const SAVE_DIR := "user://test_saves_acts/"

var main: Main = null
var _old_options: Dictionary = {}
var _zones: Array = []


func _make_main() -> Main:
	GameState.save_dir = SAVE_DIR
	_old_options = GameState.act_options.duplicate()
	var m: Main = Main.new()
	m.auto_boot = false
	m.use_fade = false
	m.show_titles = false
	m.death_panel_delay = 0.1
	add_child(m)
	main = m
	Events.zone_entered.connect(_on_zone)
	return m


func _on_zone(info: Dictionary) -> void:
	_zones.append(String(info.get("zone", "")))


func _exit_tree() -> void:
	if Events.zone_entered.is_connected(_on_zone):
		Events.zone_entered.disconnect(_on_zone)
	UI.close_all_panels()
	UI.show_hud(false)
	GameState.save_dir = GameState.SAVE_DIR
	if not _old_options.is_empty():
		GameState.act_options = _old_options


func _await_change(m: Main) -> Dictionary:
	if not m.is_changing():
		return GameState.current_area
	var info: Dictionary = await m.area_change_finished
	await get_tree().physics_frame
	return info


## Put the player somewhere and let the World notice the region (debounced).
func _walk_to(pos: Vector3) -> void:
	var p := GameState.player
	var w := GameState.world
	p.global_position = w.get_nearest_walkable(pos)
	for i in 30:
		await get_tree().physics_frame


func _first(w: World, cls: Variant) -> Node:
	for n in w.get_interactables():
		if is_instance_of(n, cls):
			return n
	return null


func _named(w: World, n_name: String) -> Node:
	for n in w.get_interactables():
		if String((n as Node).name) == n_name:
			return n
	return null


func _boss_of(w: World) -> Enemy:
	for e in EnemyDB.get_enemies(w):
		if e.is_boss and not e.dead:
			return e
	return null


func test_act_journey() -> void:
	var m := _make_main()
	GameState.act_options = {"level_mode": "custom", "level": 4, "monsters": true}
	assert_true(m.start_new_game("Act Tester", "ranger"), "new game")
	await _await_change(m)
	assert_true(GameState.world.is_town(), "starts in Emberfall")

	# Emberfall -> Act II (the desert), arriving in its town.
	Events.area_change_requested.emit("act", {"act": "desert", "zone": "hub", "seed": 11})
	var info := await _await_change(m)
	var w := GameState.world
	assert_true(w.is_act() and w.is_act_hub(), "in the desert act, in town")
	assert_eq(String(info["name"]), ActDefs.zone_name("desert", "hub"), "town name")
	assert_true(GameState.vendor_stock.size() > 0, "vendor stocked")
	var total_groups := w.get_spawn_groups().size()
	assert_true(total_groups > 30, "the act has many monster groups (%d)" % total_groups)
	assert_true(w.pending_spawn_count() > total_groups / 2, "most of them wait until the player comes near")
	for e in EnemyDB.get_enemies(w):
		assert_false(w.is_safe_at(e.global_position), "no monsters in town")
	assert_false(GameState.player.is_in_dungeon(), "no town portal in town")

	# The waystone opens the Act Explorer.
	var stone := _first(w, WorldActWaystone) as WorldActWaystone
	assert_not_null(stone, "waystone")
	stone.interact(GameState.player)
	await get_tree().process_frame
	assert_true(UI.is_panel_open("acts"), "Act Explorer opened")
	UI.close_panel("acts")

	# Walk out into the outskirts: no area change, the zone is announced, monsters spawn around.
	var changes := m.changes_done
	_zones.clear()
	await _walk_to(w.get_region_arrival("outskirts"))
	assert_eq(m.changes_done, changes, "no area change when walking between zones")
	assert_eq(GameState.world, w, "same World")
	assert_eq(_zones, ["outskirts"], "zone_entered(outskirts) once")
	assert_eq(String(GameState.current_area.get("zone", "")), "outskirts", "current area follows the zone")
	assert_eq(String(GameState.current_area.get("name", "")), "Banks of the Iteru", "zone name")
	assert_eq(int(GameState.current_area.get("level", 0)), 4, "outskirts level")
	assert_true(GameState.player.is_in_dungeon(), "town portal allowed outside town")
	# ... walk on into a higher-level zone: its name and level.
	var pending := w.pending_spawn_count()
	await _walk_to(w.get_region_arrival("oasis"))
	for i in 10:
		await get_tree().process_frame
	assert_eq(String(GameState.current_area.get("zone", "")), "oasis", "in the oasis")
	assert_eq(int(GameState.current_area.get("level", 0)), 4 + ActDefs.zone_level_offset("desert", "oasis"), "the oasis is higher level")
	assert_true(w.pending_spawn_count() < pending, "packs spawned as the player came near")
	var near := 0
	for e in EnemyDB.get_enemies(w):
		if CombatQuery.distance_xz(e.global_position, GameState.player.global_position) < World.LAZY_RADIUS + 12.0:
			near += 1
			if w.region_at(e.global_position) == "oasis" and not e.is_boss:
				assert_eq(e.level, 4 + ActDefs.zone_level_offset("desert", "oasis"), "oasis monsters have its level")
	assert_true(near > 0, "monsters around the player")

	# Town portal: a portal pair in the same World; the player is in town.
	var cast := GameState.player.global_position
	Events.town_portal_requested.emit()
	await _await_change(m)
	assert_eq(GameState.world, w, "town portal keeps the act World")
	assert_true(w.is_act_hub(), "arrived in town")
	assert_eq(w.get_town_portal_pair().size(), 2, "two portals (field + town)")
	var home := _named(w, "TownPortalHome") as WorldPortal
	assert_not_null(home, "town side of the town portal")
	home.interact(GameState.player)
	await _await_change(m)
	assert_true(CombatQuery.distance_xz(GameState.player.global_position, cast) < 5.0, "back where the portal was cast")
	assert_eq(w.get_town_portal_pair().size(), 0, "using the town side closes the pair")

	# Walking back into town refills potions.
	GameState.character.consume_potion_charge("life")
	assert_true(GameState.character.get_potion_charges("life") < Balance.POTION_MAX_CHARGES, "a potion used")
	await _walk_to(w.get_region_arrival("hub"))
	assert_true(w.is_act_hub(), "walked back into town")
	assert_near(GameState.character.get_potion_charges("life"), Balance.POTION_MAX_CHARGES, 0.001, "potions refilled in town")

	# The act's dungeon: a full (faded) change; the act World is kept and comes back.
	var door := _first(w, WorldDungeonEntrance) as WorldDungeonEntrance
	assert_not_null(door, "dungeon entrance")
	assert_eq(w.region_at(door.get_interact_position()), "courtyard", "the temple door is in the Anubis Courtyard")
	door.interact(GameState.player)
	info = await _await_change(m)
	var dw := GameState.world
	assert_true(dw.is_dungeon() and String(dw.area_info.get("act", "")) == "desert", "in the act's dungeon")
	assert_eq(String(info["name"]), "The Anubis Temple", "dungeon name")
	assert_false(w.is_inside_tree(), "act World detached, kept")
	assert_true(is_instance_valid(w), "act World alive")
	var out := _named(dw, "StartPortal") as WorldPortal
	assert_not_null(out, "the way out")
	assert_eq(out.destination, "overworld", "the start portal leads back into the act")
	out.interact(GameState.player)
	await _await_change(m)
	assert_eq(GameState.world, w, "back in the same act World")
	assert_true(CombatQuery.distance_xz(GameState.player.global_position, w.get_region_arrival("dungeon_exit")) < 3.0, "in front of the dungeon entrance")
	await get_tree().process_frame
	assert_false(is_instance_valid(dw), "dungeon freed")

	# Down again: the act boss waits at the bottom; it falls -> portals out and on to Act III.
	door = _first(w, WorldDungeonEntrance) as WorldDungeonEntrance
	door.interact(GameState.player)
	await _await_change(m)
	dw = GameState.world
	var boss := _boss_of(dw)
	assert_not_null(boss, "act boss in the dungeon")
	if boss == null:
		return
	assert_eq(String(boss.def.get("id", "")), "boss_pharaoh", "the desert's act boss")
	boss.die(GameState.player)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_not_null(_named(dw, "PortalOut"), "portal back out")
	var onward := _named(dw, "PortalActNext") as WorldPortal
	assert_not_null(onward, "portal onward")
	if onward == null:
		return
	assert_eq(onward.act_target, "gothic", "onward to Act III")
	onward.interact(GameState.player)
	await _await_change(m)
	assert_true(GameState.world.is_act() and GameState.world.is_act_hub(), "in Act III's town")
	assert_eq(String(GameState.world.area_info.get("act", "")), "gothic", "Act III")
	await get_tree().process_frame
	assert_false(is_instance_valid(w), "Act II's World freed")
	assert_false(is_instance_valid(dw), "its dungeon freed")

	# Back to Emberfall.
	Events.area_change_requested.emit("town", {})
	await _await_change(m)
	assert_true(GameState.world.is_town(), "back in Emberfall")


func test_monsters_off_and_death() -> void:
	var m := _make_main()
	GameState.act_options = {"level_mode": "custom", "level": 3, "monsters": false}
	assert_true(m.start_new_game("Act Tester 2", "warrior"), "new game")
	await _await_change(m)
	Events.area_change_requested.emit("act", {"act": "gothic", "zone": "wilds", "seed": 5})
	await _await_change(m)
	var w := GameState.world
	assert_true(w.is_act_wilds(), "arrived in the gothic outskirts")
	assert_eq(String(GameState.current_area.get("zone", "")), "outskirts", "wilds = the outskirts")
	assert_eq(EnemyDB.get_enemies(w).size(), 0, "monsters off: none spawned")
	assert_eq(w.pending_spawn_count(), 0, "monsters off: none waiting either")
	assert_false(w.is_daylit(), "the gothic act is dark")
	# Death in the wilds: back in the hub of the same World, full life.
	var p := GameState.player
	p.take_damage(p.max_life * 10.0 + p.max_es * 10.0 + 1000.0, "physical")
	assert_true(p.dead, "died")
	await m.death_screen_shown
	Events.respawn_requested.emit()
	await _await_change(m)
	assert_eq(GameState.world, w, "same act World")
	assert_true(w.is_act_hub(), "respawned in the hub")
	assert_near(GameState.player.life_ratio(), 1.0, 0.001, "full life")
	# Death in the act's dungeon: the hub, the dungeon kept, a return portal.
	GameState.act_options["monsters"] = true
	Events.area_change_requested.emit("act_dungeon", {"act": "gothic"})
	await _await_change(m)
	var dw := GameState.world
	assert_true(dw.is_dungeon() and dw.area_info.has("act"), "in the undercroft")
	p = GameState.player
	p.take_damage(p.max_life * 10.0 + p.max_es * 10.0 + 1000.0, "physical")
	await m.death_screen_shown
	Events.respawn_requested.emit()
	await _await_change(m)
	assert_eq(GameState.world, w, "back in the same act World")
	assert_true(w.is_act_hub(), "in the hub")
	assert_eq(m.get_kept_world(), dw, "the dungeon is kept")
	var ret := _named(w, "ReturnPortal") as WorldPortal
	assert_not_null(ret, "return portal to the dungeon")
	if ret != null:
		ret.interact(GameState.player)
		await _await_change(m)
		assert_eq(GameState.world, dw, "back in the same dungeon")

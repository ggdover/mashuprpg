extends Node
## ui-menus demo: opens every screen of the module through the real UIRoot (UI autoload) with
## demo data and saves screenshots to docs/screenshots/ui-menus/ (windowed runs only); headless
## it just walks through every screen as a smoke test.
##
##   GTEST_WINDOWED=1 tools/gtest.sh ui-menus-demo res://tests/scenes/ui_menus_demo.tscn
##   ... -- --only=tree_mid,skills     (subset; names below)

const SHOTS: Array[String] = ["main_menu", "new_character", "delete_confirm", "tree_fresh", "tree_mid", "tree_search", "tree_zoomed_out", "tree_closeup", "skills", "skills_locked", "waypoint", "pause", "death"]
const SAVE_DIR := "user://demo_saves_ui_menus/"

var _dir := ""
var _windowed := false


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	_windowed = DisplayServer.get_name() != "headless"
	var repo := OS.get_environment("GTEST_REPO")
	if repo == "":
		repo = ProjectSettings.globalize_path("res://")
	_dir = repo.path_join("docs/screenshots/ui-menus")
	DirAccess.make_dir_recursive_absolute(_dir)
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",", false)
	RenderingServer.set_default_clear_color(Color(0.05, 0.05, 0.06))
	_make_demo_saves()
	for shot in SHOTS:
		if not only.is_empty() and not only.has(shot):
			continue
		await call("_shot_" + shot)
		await _settle(6)
		_capture(shot)
		if shot.begins_with("tree"):
			UI.get_panel("passives").call("set_search", "")
		if shot.begins_with("skills"):
			UI.get_panel("skills").call("set_filter", "all")
		UI.close_all_panels()
		UI.hide_tooltip()
		await _settle(2)
	print("[ui_menus_demo] done")
	get_tree().quit()


## Wait for rendered frames (windowed) or processed frames (headless: the dummy renderer never
## emits frame_post_draw).
func _settle(frames: int) -> void:
	for i in frames:
		if _windowed:
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame


func _capture(shot: String) -> void:
	if not _windowed:
		print("[ui_menus_demo] %s ok (headless: no screenshot)" % shot)
		return
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%s.png" % shot)
	img.save_png(path)
	print("[ui_menus_demo] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


# ------------------------------------------------------------------ data

func _make_demo_saves() -> void:
	GameState.save_dir = SAVE_DIR
	for s in GameState.list_saves():
		GameState.delete_save(String(s["save_id"]))
	var demo := [["Kaelen", "warrior", 23, 9], ["Syl", "ranger", 12, 4], ["Morwen", "sorcerer", 38, 16]]
	for d in demo:
		var c := GameState.new_character(String(d[0]), String(d[1]))
		c.level = int(d[2])
		c.max_depth = int(d[3])
		GameState.save_game()
	GameState.character = null


# ------------------------------------------------------------------ shots

func _shot_main_menu() -> void:
	UI.show_main_menu()
	await _settle(30)


func _shot_new_character() -> void:
	UI.show_main_menu()
	var m: Control = UI.get_panel("main_menu")
	m.call("show_create_view")
	m.call("set_character_name", "Aeris")
	m.call("select_class", "ranger")
	await _settle(20)


func _shot_delete_confirm() -> void:
	UI.show_main_menu()
	var m: Control = UI.get_panel("main_menu")
	m.call("request_delete_selected")
	await _settle(10)


# ------------------------------------------------------------------ passive tree

## A node id by display name (first match), -1 if none.
func _node_named(node_name: String) -> int:
	for id in TreeDB.get_all_ids():
		if String(TreeDB.get_passive(int(id)).get("name", "")) == node_name:
			return int(id)
	return -1


## Allocate the shortest paths to the named nodes (as far as points allow).
func _allocate_towards(c: CharacterData, names: Array) -> void:
	for n in names:
		var id := _node_named(String(n))
		if id < 0:
			push_warning("demo: no passive named %s" % n)
			continue
		c.allocate_passives(TreeDB.find_path(c.allocated_passives, id, c.class_id))


func _tree_character(level: int, names: Array, gold: int) -> CharacterData:
	var c := GameState.new_character("Kaelen", "warrior")
	c.level = level
	c.bonus_passive_points = 3
	c.gold = gold
	_allocate_towards(c, names)
	return c


func _shot_tree_fresh() -> void:
	var c := GameState.new_character("Kaelen", "warrior")
	c.level = 3
	UI.open_panel("passives", {})
	await _settle(30)


func _shot_tree_mid() -> void:
	var c := _tree_character(26, ["Brute Force", "Heart of the Oak", "Iron Skin"], 1450)
	c.bonus_passive_points += 2 - c.passive_points_unspent()
	var target := _node_named("Resolute Technique")
	UI.open_panel("passives", {})
	var p: Control = UI.get_panel("passives")
	await _settle(4)
	p.call("set_view", TreeDB.get_node_position(target) + Vector2(260, -240), 0.62)
	await _settle(4)
	p.call("hover_node", target)
	print("[ui_menus_demo] tree_mid: %d allocated, %d unspent, preview %d nodes" % [c.allocated_passives.size(), c.passive_points_unspent(), (p.call("get_preview_path") as Array).size()])
	await _settle(40)


func _shot_tree_search() -> void:
	_tree_character(18, ["Brute Force", "Heart of the Oak"], 300)
	UI.open_panel("passives", {})
	var p: Control = UI.get_panel("passives")
	p.call("set_search", "fire")
	p.call("set_view", Vector2(-700, -250), 0.5)
	await _settle(30)


func _shot_tree_zoomed_out() -> void:
	_tree_character(40, ["Brute Force", "Heart of the Oak", "Iron Skin", "Warlord's Command", "Resolute Technique", "Unwavering Stance"], 5000)
	UI.open_panel("passives", {})
	var p: Control = UI.get_panel("passives")
	p.call("set_view", Vector2(440, 60), 0.25)   # the whole tree, left of the Passive Bonuses panel
	await _settle(30)
	await _report_perf(p)


func _shot_tree_closeup() -> void:
	_tree_character(40, ["Brute Force", "Heart of the Oak", "Iron Skin", "Resolute Technique"], 5000)
	UI.open_panel("passives", {})
	var p: Control = UI.get_panel("passives")
	p.call("set_view", TreeDB.get_node_position(_node_named("Iron Skin")) + Vector2(-60, 40), 1.6)
	await _settle(30)
	await _report_perf(p)


func _report_perf(p: Control) -> void:
	var canvas: Control = p.call("get_tree_canvas")
	var total := 0
	for i in 30:
		await _settle(1)
		total += int(canvas.get("last_draw_usec"))
	print("[ui_menus_demo] tree draw: %.2f ms CPU per frame (avg of 30), static layer recorded in %.2f ms (%d records), %d fps, zoom %.2f" % [
		total / 30000.0, int(canvas.get("last_static_usec")) / 1000.0, int(canvas.get("static_records")), Engine.get_frames_per_second(), float(p.call("get_zoom"))])


# ------------------------------------------------------------------ in-game panels

var _world: World = null
var _cam: Camera3D = null


## A game view behind the in-game panels: a built area and a camera at the gameplay angle.
func _ensure_world(info: Dictionary) -> void:
	if _world != null and String(_world.area_info.get("id", "")) == String(info.get("id", "")) and int(_world.area_info.get("depth", 0)) == int(info.get("depth", 0)):
		return
	if _world != null:
		_world.queue_free()
	_world = World.new()
	add_child(_world)
	GameState.world = _world
	GameState.current_area = info
	_world.build(info)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_cam.far = 400.0
		add_child(_cam)
	var target := _world.get_player_start()
	_cam.position = target + Vector3(0, sin(deg_to_rad(56.0)), cos(deg_to_rad(56.0))) * 18.0
	_cam.look_at(target)
	_cam.make_current()
	if _world.has_method("snap_light_pool"):
		_world.call("snap_light_pool")


func _town() -> void:
	_ensure_world({"id": "town", "name": "Emberfall", "level": 1, "theme": "town"})


func _dungeon(depth: int) -> void:
	var theme := World.theme_for_depth(depth)
	_ensure_world({"id": "dungeon", "depth": depth, "level": Balance.area_level_for_depth(depth), "seed": 777,
		"theme": theme, "name": "Depth %d — %s" % [depth, World.theme_display_name(theme)]})


func _shot_skills() -> void:
	_town()
	var c := GameState.new_character("Syl", "ranger")
	c.level = 9
	c.set_skill_in_slot(2, "power_shot")
	c.set_skill_in_slot(3, "rain_of_arrows")
	UI.open_panel("skills", {})
	var p: Control = UI.get_panel("skills")
	p.call("set_filter", "ranged")
	await _settle(4)
	if p.has_method("preview_tooltip"):
		p.call("preview_tooltip", "split_arrow")
	await _settle(20)


func _shot_skills_locked() -> void:
	_town()
	var c := GameState.new_character("Morwen", "sorcerer")
	c.level = 4
	c.set_skill_in_slot(2, "frost_nova")
	c.set_skill_in_slot(3, "ice_spear")
	UI.open_panel("skills", {})
	var p: Control = UI.get_panel("skills")
	p.call("set_filter", "spells")
	await _settle(4)
	if p.has_method("preview_tooltip"):
		p.call("preview_tooltip", "chain_lightning")
	await _settle(20)


func _shot_waypoint() -> void:
	_town()
	var c := GameState.new_character("Morwen", "sorcerer")
	c.level = 17
	c.max_depth = 9
	for d in range(1, 9):
		c.mark_depth_cleared(d)
	UI.open_panel("waypoint", {"max_depth": c.max_depth})
	await _settle(6)
	UI.get_panel("waypoint").call("preview_tooltip", 9)
	await _settle(14)


func _shot_pause() -> void:
	_dungeon(4)
	var c := GameState.new_character("Kaelen", "warrior")
	c.level = 23
	c.play_time = 3 * 3600 + 17 * 60
	UI.open_panel("pause", {})
	await _settle(20)


func _shot_death() -> void:
	_dungeon(7)
	var c := GameState.new_character("Kaelen", "warrior")
	c.level = 23
	c.xp = int(c.xp_to_next() * 0.62)
	UI.open_panel("death", {})
	await _settle(110)

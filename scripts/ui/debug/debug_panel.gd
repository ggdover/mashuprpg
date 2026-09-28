class_name DebugPanel
extends Control
## In-game debug menu (F1, or the pause menu, or F1 / "Debug Menu" on the title screen): one list
## to jump anywhere and test things.
##   ZONES     every zone of the game: Emberfall, each act's hub and wilds, dungeon depths (three
##             theme shortcuts + any depth with − / +). Click = travel.
##   TELEPORT  points of interest in the current zone: start, boss, merchant, stash, waystone /
##             gate, portals, chests, shrine, the next monster pack.
##   CHEATS    god mode, monsters on/off (next zone), act monster level, level up, loot, gold, heal,
##             reveal map, kill boss, remove monsters, far camera, camera view preset, fog of war;
##             wardrobe: wear a full armour set of any family (STR / DEX / INT) and gear look tier
##             (I common, II rare, III unique), or take the armour off.
## Three tabs (Zones / Teleport / Cheats; the last one used is remembered). Docked on the left (not
## modal, the game keeps running). Options live in GameState.act_options.
## OWNER: acts framework. Standalone: `var p := DebugPanel.new(); add_child(p); p.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuFrame := preload("res://scripts/ui/menus/menu_frame.gd")
const FlowAreas := preload("res://scripts/main/flow_areas.gd")
const FlowDebugKeys := preload("res://scripts/main/flow_debug_keys.gd")

const PANEL_NAME := "debug"
const WIDTH := 430
## Dungeon theme shortcuts: [depth, label].
const DUNGEON_SHORTCUTS := [[1, "The Crypts"], [4, "Echoing Caves"], [7, "Infernal Depths"]]
const FAR_CAMERA_DISTANCE := 42.0

var close_button: Button
## Zone key ("town", "act:desert:hub", "dungeon:4", ...) -> Button.
var zone_buttons: Dictionary = {}
## Teleport buttons of the current zone, in list order: [{"label": String, "button": Button}].
var teleport_entries: Array = []

## The tab shown: "zones", "teleport" or "cheats" (kept between openings).
var tab := "zones"
var tab_buttons: Dictionary = {}

var _built := false
var _travelled := false
var _pages: Dictionary = {}
var _zone_label: Label
var _zones_box: VBoxContainer
var _tp_box: VBoxContainer
var _depth := 0
var _depth_label: Label
var _level_label: Label
var _god_button: Button
var _monsters_button: Button
var _level_mode_button: Button
var _far_button: Button
var _fog_button: Button
var _cam_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuStyle.get_theme()


func _ready() -> void:
	_ensure_built()


## Called by UIRoot after the panel becomes visible.
func on_opened(_context: Dictionary) -> void:
	_ensure_built()
	_travelled = false
	var c := GameState.character
	if _depth < 1:
		_depth = maxi(1, c.max_depth if c != null else 1)
	_rebuild_zones()
	_rebuild_teleports()
	_refresh_cheats()
	show_tab(tab)


## Show one tab: "zones", "teleport" or "cheats".
func show_tab(which: String) -> void:
	if not _pages.has(which):
		return
	tab = which
	for k in _pages:
		(_pages[k] as Control).visible = k == which
		MenuStyle.style_key_button(tab_buttons[k] as Button, k == which)


func on_closed() -> void:
	pass


func close() -> void:
	if UI.is_panel_open(PANEL_NAME) and UI.get_panel(PANEL_NAME) == self:
		UI.close_panel(PANEL_NAME)
	else:
		visible = false
		on_closed()


# ------------------------------------------------------------------ travel

## Travel to a zone: "town", "act" (act + zone) or "dungeon" (depth). False while travelling.
func travel(kind: String, a: Variant = null, b: Variant = null) -> bool:
	if _travelled:
		return false
	var params := {}
	match kind:
		"town":
			if GameState.is_in_town():
				Events.notify.emit("Already in Emberfall", UIStyle.COLOR_TEXT_DIM)
				return false
		"act":
			params = {"act": String(a), "zone": String(b)}
		"act_dungeon":
			params = {"act": String(a)}
		"dungeon":
			params = {"depth": clampi(int(a), 1, Balance.MAX_DEPTH)}
		_:
			return false
	_travelled = true
	Sfx.play_ui("ui_click")
	Events.area_change_requested.emit(kind, params)
	close()
	return true


# ------------------------------------------------------------------ teleport

## Teleport the player next to a world position (snapped to walkable ground).
func teleport_to(pos: Vector3) -> bool:
	var w := GameState.world
	var p := GameState.player
	if w == null or not is_instance_valid(w) or p == null or not is_instance_valid(p) or p.dead:
		return false
	var spot := w.get_nearest_walkable(Vector3(pos.x, 0.0, pos.z))
	p.cancel_auto_walk()
	p.velocity = Vector3.ZERO
	p.global_position = spot
	if p.camera_rig != null and is_instance_valid(p.camera_rig):
		p.camera_rig.snap_to_target()
	w.snap_light_pool()
	w.mark_explored(spot, 14.0)
	EnemyDB.apply_sleep(spot)
	return true


## Points of interest of the current zone: [{"label", "pos"}].
func get_teleport_points() -> Array:
	var out: Array = []
	var w := GameState.world
	if w == null or not is_instance_valid(w):
		return out
	out.append({"label": "Start", "pos": w.get_player_start()})
	# Act worlds: each region's arrival spot (the town, the way into the wilds).
	for r in w.get_regions():
		var rtag := "town" if bool(r.get("safe", false)) else "lvl %d" % w.region_level(String(r["id"]))
		out.append({"label": "%s (%s)" % [String(r["name"]), rtag], "pos": w.get_region_arrival(String(r["id"]))})
	var boss := _boss()
	if boss != null:
		out.append({"label": "Boss: %s" % String(boss.def.get("name", "Boss")), "pos": boss.global_position + Vector3(0, 0, 7.0)})
	elif w.is_act() and not w.pending_groups().filter(func(g: Dictionary) -> bool: return String(g.get("kind", "")) == "boss").is_empty():
		var bg: Dictionary = w.pending_groups().filter(func(g: Dictionary) -> bool: return String(g.get("kind", "")) == "boss")[0]
		var bdef: Dictionary = EnemyDB.get_def(String(bg.get("enemy", "")))
		out.append({"label": "Boss: %s" % String(bdef.get("name", "Zone boss")), "pos": (bg["position"] as Vector3) + Vector3(0, 0, 7.0)})
	elif w.is_act() and w.layout.has("boss_pos"):
		out.append({"label": "Boss arena", "pos": (w.layout["boss_pos"] as Vector3) + Vector3(0, 0, 7.0)})
	elif w.is_dungeon():
		out.append({"label": "Boss room", "pos": w.get_boss_room_center()})
	var counts := {}
	for n in w.get_interactables():
		var node := n as Node3D
		var label := String(n.get("display_name")) if n.get("display_name") != null else String(node.name)
		if n is WorldPortal:
			label = "Portal to %s" % label.trim_prefix("Return to ")
			if (n as WorldPortal).destination == "return":
				label = "Portal: %s" % String(n.get("display_name"))
		counts[label] = int(counts.get(label, 0)) + 1
		if int(counts[label]) > 1:
			label += " #%d" % int(counts[label])
		var pos: Vector3 = n.call("get_interact_position") if n.has_method("get_interact_position") else node.global_position
		out.append({"label": label, "pos": pos})
	return out


## Teleport next to the nearest living monster pack at least 12 m away. False if none.
func teleport_to_next_pack() -> bool:
	var w := GameState.world
	var p := GameState.player
	if w == null or p == null or not is_instance_valid(p):
		return false
	# Living packs and (big acts) the packs that have not spawned yet.
	var best := Vector3.INF
	var best_d := INF
	for e in EnemyDB.get_enemies(w):
		if e.is_boss:
			continue
		var d := CombatQuery.distance_xz(p.global_position, e.global_position)
		if d > 12.0 and d < best_d:
			best_d = d
			best = e.global_position
	for g in w.pending_groups():
		if String(g.get("kind", "")) == "boss":
			continue
		var gp: Vector3 = g["position"]
		var d2 := CombatQuery.distance_xz(p.global_position, gp)
		if d2 > 12.0 and d2 < best_d:
			best_d = d2
			best = gp
	if best == Vector3.INF:
		Events.notify.emit("No monster packs left here", UIStyle.COLOR_TEXT_DIM)
		return false
	return teleport_to(best + Vector3(0, 0, 7.0))


# ------------------------------------------------------------------ cheats

func set_god_mode(on: bool) -> void:
	GameState.act_options["god_mode"] = on
	var p := GameState.player
	if p != null and is_instance_valid(p):
		p.god_mode = on
	_refresh_cheats()


func set_monsters(on: bool) -> void:
	GameState.act_options["monsters"] = on
	Events.notify.emit("Monsters %s in the next zone you enter" % ("ON" if on else "OFF"), UIStyle.COLOR_TEXT_DIM)
	_refresh_cheats()


## Cycle the act monster level: act default -> my level -> custom.
func cycle_level_mode() -> void:
	var modes := ["act", "character", "custom"]
	var i := modes.find(String(GameState.act_options.get("level_mode", "act")))
	GameState.act_options["level_mode"] = modes[(i + 1) % modes.size()]
	_refresh_cheats()
	_rebuild_zones()


func add_custom_level(delta: int) -> void:
	GameState.act_options["level"] = clampi(int(GameState.act_options.get("level", 10)) + delta, 1, 100)
	GameState.act_options["level_mode"] = "custom"
	_refresh_cheats()
	_rebuild_zones()


func level_up(times: int) -> void:
	for k in times:
		FlowDebugKeys.level_up()
	_refresh_cheats()


func spawn_loot() -> void:
	FlowDebugKeys.spawn_loot()


func add_gold(amount: int) -> void:
	if GameState.character != null:
		GameState.character.add_gold(amount)
		Events.notify.emit("+%d gold" % amount, UIStyle.COLOR_GOLD)


func full_heal() -> void:
	var p := GameState.player
	if p != null and is_instance_valid(p) and not p.dead:
		p.refill_pools()
	if GameState.character != null:
		GameState.character.refill_potions()
	Events.notify.emit("Life, mana and potions refilled", UIStyle.COLOR_GOOD)


## Wear a full armour set (helmet, body, gloves, boots) of `family` ("str", "dex", "int") at gear look
## `tier` 1..3 (base tiers 1 / 3 / 5). The armour worn before is dropped (debug).
func equip_armour_set(family: String, tier: int) -> void:
	var c := GameState.character
	if c == null:
		return
	var base_tier: int = [1, 3, 5][clampi(tier, 1, 3) - 1]
	for slot in ["helmet", "body", "gloves", "boots"]:
		var it := ItemDB.create_item("%s_%s_%d" % [slot, family, base_tier], Item.Rarity.NORMAL, 1)
		if it != null and not it.get_base().is_empty():
			c.equip(it, slot)
	Events.notify.emit("Wearing %s armour, tier %d" % [family.to_upper(), tier], UIStyle.COLOR_GOOD)


## Take off helmet, body armour, gloves and boots (dropped; debug).
func remove_armour() -> void:
	var c := GameState.character
	if c == null:
		return
	for slot in ["helmet", "body", "gloves", "boots"]:
		c.unequip(slot)


func reveal_map() -> void:
	var w := GameState.world
	if w != null and is_instance_valid(w) and w.grid != null:
		w.grid.explored.fill(1)
		w.grid.explored_version += 1
		Events.notify.emit("Map revealed", UIStyle.COLOR_TEXT_DIM)


## Kill the zone's boss (opens the exit portals like a real kill).
func kill_boss() -> bool:
	var boss := _boss()
	if boss == null:
		Events.notify.emit("No living boss here", UIStyle.COLOR_TEXT_DIM)
		return false
	boss.die(GameState.player)
	return true


## Remove every monster of the zone (no loot, no XP).
func remove_monsters() -> int:
	var w := GameState.world
	if w == null or not is_instance_valid(w):
		return 0
	var n := 0
	w.stop_lazy_spawns()
	for e in EnemyDB.get_enemies(w):
		if e.get_parent() != null:
			e.get_parent().remove_child(e)
		e.queue_free()
		n += 1
	Events.notify.emit("Removed %d monsters" % n, UIStyle.COLOR_TEXT_DIM)
	return n


## Switch the default camera view (diagonal <-> straight) and apply it now.
func cycle_camera_preset() -> void:
	var ids: Array = CameraRig.PRESETS.keys()
	var i := ids.find(CameraRig.preset)
	CameraRig.set_preset(String(ids[(i + 1) % ids.size()]))
	var p := GameState.player
	if p != null and is_instance_valid(p) and p.camera_rig != null:
		p.camera_rig.reset_view()
	_refresh_cheats()


## Fog of war on / off (now and in the next zones).
func set_fog_of_war(on: bool) -> void:
	var w := GameState.world
	if w != null and is_instance_valid(w):
		w.set_fog_enabled(on)
	else:
		World.fog_of_war_enabled = on
	_refresh_cheats()


## Toggle a far camera (to see whole landmarks); the mouse wheel returns to the normal range.
func toggle_far_camera() -> void:
	var p := GameState.player
	if p == null or not is_instance_valid(p) or p.camera_rig == null:
		return
	var rig := p.camera_rig
	rig.zoom_target = CameraRig.DEFAULT_DISTANCE if rig.zoom_target > CameraRig.MAX_DISTANCE else FAR_CAMERA_DISTANCE
	_refresh_cheats()


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BORDER, 14)
	frame.set("accent", Color(MenuStyle.EMBER, 0.7))
	frame.position = Vector2(18, 18)
	frame.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(frame)
	var v := MenuStyle.vbox(8)
	frame.add_child(v)
	var head := MenuStyle.hbox(8)
	var tv := MenuStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(MenuStyle.title_label("DEBUG MENU", 24, UIStyle.COLOR_TITLE))
	_zone_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	tv.add_child(_zone_label)
	head.add_child(tv)
	close_button = MenuStyle.make_button("Close (F1)", UIStyle.FONT_SMALL)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	var tabs := MenuStyle.hbox(6)
	for t in [["zones", "Zones"], ["teleport", "Teleport"], ["cheats", "Cheats"]]:
		var tb := MenuStyle.make_button(t[1], UIStyle.FONT_NORMAL)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(show_tab.bind(t[0]))
		tabs.add_child(tb)
		tab_buttons[t[0]] = tb
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(WIDTH, 660)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(scroll)
	var body := MenuStyle.vbox(6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var zones_page := MenuStyle.vbox(3)
	zones_page.add_child(_header("Click a zone to travel there"))
	_zones_box = MenuStyle.vbox(3)
	zones_page.add_child(_zones_box)
	body.add_child(zones_page)
	_pages["zones"] = zones_page
	var tp_page := MenuStyle.vbox(3)
	tp_page.add_child(_header("Click to teleport in this zone"))
	_tp_box = MenuStyle.vbox(3)
	tp_page.add_child(_tp_box)
	body.add_child(tp_page)
	_pages["teleport"] = tp_page
	var cheats_page := MenuStyle.vbox(6)
	body.add_child(cheats_page)
	_pages["cheats"] = cheats_page
	cheats_page.add_child(_header("Cheats"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	cheats_page.add_child(grid)
	_god_button = _cheat(grid, "", func() -> void: set_god_mode(not _god_on()))
	_monsters_button = _cheat(grid, "", func() -> void: set_monsters(not bool(GameState.act_options.get("monsters", true))))
	_cheat(grid, "Level up +1", func() -> void: level_up(1))
	_cheat(grid, "Level up +5", func() -> void: level_up(5))
	_cheat(grid, "Spawn loot", spawn_loot)
	_cheat(grid, "+10,000 gold", func() -> void: add_gold(10000))
	_cheat(grid, "Full heal + potions", full_heal)
	_cheat(grid, "Reveal map", reveal_map)
	_cheat(grid, "Kill boss", func() -> void: kill_boss())
	_cheat(grid, "Remove monsters", func() -> void: remove_monsters())
	_far_button = _cheat(grid, "", toggle_far_camera)
	_level_mode_button = _cheat(grid, "", cycle_level_mode)
	_cam_button = _cheat(grid, "", cycle_camera_preset)
	_fog_button = _cheat(grid, "", func() -> void: set_fog_of_war(not World.fog_of_war_enabled))
	var lv := MenuStyle.hbox(6)
	lv.add_child(MenuStyle.label("Act monster level", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT))
	lv.add_child(MenuStyle.spacer())
	for d in [-5, -1]:
		lv.add_child(_small_button("%d" % d, add_custom_level.bind(d)))
	_level_label = MenuStyle.label("", UIStyle.FONT_NORMAL, MenuStyle.GOLD)
	_level_label.custom_minimum_size = Vector2(40, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_level_label)
	for d in [1, 5]:
		lv.add_child(_small_button("+%d" % d, add_custom_level.bind(d)))
	cheats_page.add_child(lv)
	var note := MenuStyle.label("Monsters on/off and the act level apply to the next zone you enter. The mouse wheel ends the far camera.", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(WIDTH - 10, 0)
	cheats_page.add_child(note)
	cheats_page.add_child(_header("Wardrobe"))
	var wg := GridContainer.new()
	wg.columns = 3
	wg.add_theme_constant_override("h_separation", 6)
	wg.add_theme_constant_override("v_separation", 4)
	cheats_page.add_child(wg)
	for fam in ["str", "dex", "int"]:
		for t in [1, 2, 3]:
			var b := MenuStyle.make_button("%s %s" % [fam.to_upper(), ["I", "II", "III"][t - 1]], UIStyle.FONT_SMALL)
			b.custom_minimum_size = Vector2((WIDTH - 18) / 3.0, 0)
			b.pressed.connect(equip_armour_set.bind(fam, t))
			wg.add_child(b)
	_cheat(cheats_page, "Remove armour", remove_armour)
	show_tab(tab)


func _rebuild_zones() -> void:
	if _zones_box == null:
		return
	for ch in _zones_box.get_children():
		_zones_box.remove_child(ch)
		ch.queue_free()
	zone_buttons.clear()
	var info: Dictionary = GameState.current_area
	var here := _zone_key(info)
	_zone_label.text = "Here: %s  ·  Monster level %d" % [String(info.get("name", "—")), int(info.get("level", 1))] if not info.is_empty() else "Not in a zone"
	_add_zone_row("town", "Emberfall", "town", Color(0.98, 0.82, 0.5), func() -> void: travel("town"), here)
	for act in ActDefs.ACT_ORDER:
		var accent := ActDefs.accent(act)
		_zones_box.add_child(MenuStyle.label("%s — %s" % [ActDefs.act_label(act), ActDefs.get_act(act)["title"]], UIStyle.FONT_SMALL, accent))
		for r in ActDefs.regions(act):
			var zone := String(r["id"])
			var tag := "town" if zone == "hub" else "lvl %d" % (FlowAreas.act_level(act) + int(r["level"]))
			_add_zone_row("act:%s:%s" % [act, zone], String(r["name"]), tag, accent, travel.bind("act", act, zone), here)
		var dd := ActDefs.dungeon(act)
		if not dd.is_empty():
			var dtag := "dungeon · lvl %d" % (FlowAreas.act_level(act) + int(dd.get("level_offset", ActDefs.DUNGEON_LEVEL_OFFSET)))
			_add_zone_row("act_dungeon:%s" % act, String(dd.get("name", "Dungeon")), dtag, accent, travel.bind("act_dungeon", act), here)
	_zones_box.add_child(MenuStyle.label("Dungeons", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT))
	for sc in DUNGEON_SHORTCUTS:
		var d: int = sc[0]
		_add_zone_row("dungeon:%d" % d, sc[1], "depth %d" % d, MenuStyle.theme_color(World.theme_for_depth(d)), travel.bind("dungeon", d), here)
	var row := MenuStyle.hbox(6)
	row.add_child(MenuStyle.label("Any depth", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT))
	row.add_child(MenuStyle.spacer())
	row.add_child(_small_button("-5", func() -> void: _set_depth(_depth - 5)))
	row.add_child(_small_button("-1", func() -> void: _set_depth(_depth - 1)))
	_depth_label = MenuStyle.label("", UIStyle.FONT_NORMAL, MenuStyle.GOLD)
	_depth_label.custom_minimum_size = Vector2(40, 0)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_depth_label)
	row.add_child(_small_button("+1", func() -> void: _set_depth(_depth + 1)))
	row.add_child(_small_button("+5", func() -> void: _set_depth(_depth + 5)))
	var go := MenuStyle.make_button("Go", UIStyle.FONT_SMALL, true)
	go.pressed.connect(func() -> void: travel("dungeon", _depth))
	row.add_child(go)
	_zones_box.add_child(row)
	zone_buttons["dungeon:any"] = go
	_set_depth(_depth)


func _rebuild_teleports() -> void:
	if _tp_box == null:
		return
	for ch in _tp_box.get_children():
		_tp_box.remove_child(ch)
		ch.queue_free()
	teleport_entries.clear()
	var pts := get_teleport_points()
	if pts.is_empty():
		_tp_box.add_child(MenuStyle.label("Not in a zone", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM))
		return
	var w := GameState.world
	if w != null and is_instance_valid(w) and (not EnemyDB.get_enemies(w).is_empty() or w.pending_spawn_count() > 0):
		pts.insert(1, {"label": "Next monster pack", "pos": null})
	for pt in pts:
		var b := MenuStyle.make_button(String(pt["label"]), UIStyle.FONT_SMALL)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		if pt["pos"] == null:
			b.pressed.connect(func() -> void: teleport_to_next_pack())
		else:
			var pos: Vector3 = pt["pos"]
			b.pressed.connect(func() -> void: teleport_to(pos))
		_tp_box.add_child(b)
		teleport_entries.append({"label": String(pt["label"]), "button": b})


func _refresh_cheats() -> void:
	if not _built:
		return
	_god_button.text = "God mode: %s" % ("ON" if _god_on() else "off")
	MenuStyle.style_key_button(_god_button, _god_on())
	var mon := bool(GameState.act_options.get("monsters", true))
	_monsters_button.text = "Monsters: %s" % ("ON" if mon else "OFF")
	MenuStyle.style_key_button(_monsters_button, mon)
	var mode := String(GameState.act_options.get("level_mode", "act"))
	_level_mode_button.text = "Act level: %s" % {"act": "act default", "character": "my level", "custom": "custom"}.get(mode, mode)
	_level_label.text = str(int(GameState.act_options.get("level", 10)))
	_level_label.modulate.a = 1.0 if mode == "custom" else 0.45
	var far := false
	var p := GameState.player
	if p != null and is_instance_valid(p) and p.camera_rig != null:
		far = p.camera_rig.zoom_target > CameraRig.MAX_DISTANCE
	_far_button.text = "Far camera: %s" % ("ON" if far else "off")
	_cam_button.text = "View: %s" % String(CameraRig.PRESETS[CameraRig.preset]["label"]).get_slice(" (", 0)
	MenuStyle.style_key_button(_far_button, far)
	_fog_button.text = "Fog of war: %s" % ("ON" if World.fog_of_war_enabled else "off")
	MenuStyle.style_key_button(_fog_button, World.fog_of_war_enabled)


func _add_zone_row(key: String, text: String, tag: String, accent: Color, cb: Callable, here: String) -> void:
	var b := MenuStyle.make_button(text, UIStyle.FONT_NORMAL)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var t := MenuStyle.label(tag, UIStyle.FONT_SMALL, accent.lerp(UIStyle.COLOR_TEXT_DIM, 0.35))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	t.offset_left = -170
	t.offset_right = -10
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(t)
	if key == here:
		MenuStyle.style_key_button(b, true)
		t.text = "you are here"
		t.add_theme_color_override("font_color", UIStyle.COLOR_GOOD)
	_zones_box.add_child(b)
	zone_buttons[key] = b


func _set_depth(d: int) -> void:
	_depth = clampi(d, 1, Balance.MAX_DEPTH)
	if _depth_label != null:
		_depth_label.text = str(_depth)


static func _zone_key(info: Dictionary) -> String:
	match String(info.get("id", "")):
		"town":
			return "town"
		"act":
			return "act:%s:%s" % [info.get("act", ""), info.get("zone", "")]
		"dungeon":
			if info.has("act"):
				return "act_dungeon:%s" % String(info["act"])
			return "dungeon:%d" % int(info.get("depth", 0))
	return ""


func _boss() -> Enemy:
	var w := GameState.world
	if w == null or not is_instance_valid(w):
		return null
	for e in EnemyDB.get_enemies(w):
		if e.is_boss and not e.dead:
			return e
	return null


func _god_on() -> bool:
	var p := GameState.player
	if p != null and is_instance_valid(p):
		return bool(p.god_mode)
	return bool(GameState.act_options.get("god_mode", false))


func _header(text: String) -> Control:
	var l := MenuStyle.label(text.to_upper(), UIStyle.FONT_SMALL, UIStyle.COLOR_TITLE)
	l.custom_minimum_size = Vector2(0, 26)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _cheat(parent: Control, text: String, cb: Callable) -> Button:
	var b := MenuStyle.make_button(text, UIStyle.FONT_SMALL)
	b.custom_minimum_size = Vector2((WIDTH - 12) / 2.0, 0)
	b.pressed.connect(func() -> void:
		cb.call()
		_refresh_cheats())
	parent.add_child(b)
	return b


func _small_button(text: String, cb: Callable) -> Button:
	var b := MenuStyle.make_button(text, UIStyle.FONT_SMALL)
	b.custom_minimum_size = Vector2(38, 0)
	b.pressed.connect(cb)
	return b

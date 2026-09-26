class_name HUD
extends Control
## In-game HUD: life/mana globes (+ES ring), XP bar, 6-slot skill bar with key labels, cooldown
## sweeps and unusable tint (drop target for skill drags), potion slots with charges and active-
## potion sweep, buff/ailment icons, area name, minimap (Tab = large, handled here in
## _unhandled_input), boss bar, hovered-enemy nameplate, floating damage numbers, passive-points
## indicator. Notifications are NOT here (UIRoot). Ground item labels are NOT here (GroundItem).
## Binds to the player on Events.player_spawned; GameState.player may be null at any time.
## OWNER: UI HUD module (wave 2).
## CONTRACT STUB — keep every public member/signature. See docs/ARCHITECTURE.md §16.
##
## Layout (base 1920×1080, positions follow the HUD size): globes in the bottom corners, a bronze
## plate in the bottom centre with [life potion][LMB][RMB] | [Q][E][R][F][mana potion][dodge],
## the XP bar along the bottom edge between the globes, "+N Passive Points" above the XP bar on
## the left, buffs/ailments top left, boss bar + hovered-enemy card top centre, minimap + area name
## top right, a fading area title on area entry, damage numbers and a low-life vignette under
## everything. Only the globes, slots, potions, dodge, XP bar, buff icons and the passive button
## take the mouse (MOUSE_FILTER_STOP); everything else is IGNORE.
##
## Works standalone (tests / demos): `var h := HUD.new(); some_canvas_layer.add_child(h)`; it binds
## to GameState.player on _ready and on every Events.player_spawned, and re-binds by itself when
## GameState.player changes. Children are built in code from the Hud* scripts in this folder.
##
## Extra public API (beyond the contract): bind_player, get_player, get_character,
## assign_skill, open_skill_book, open_passive_tree, use_potion, toggle_minimap, set_minimap_large,
## is_minimap_large, set_area, spawn_damage_number, show_tooltip_for, hide_tooltip_for and the
## widget references below (life_globe, mana_globe, skill_slots, ...).

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")
const HudGlobe := preload("res://scripts/ui/hud/hud_globe.gd")
const HudSkillSlot := preload("res://scripts/ui/hud/hud_skill_slot.gd")
const HudPotionSlot := preload("res://scripts/ui/hud/hud_potion_slot.gd")
const HudDodgeSlot := preload("res://scripts/ui/hud/hud_dodge_slot.gd")
const HudXpBar := preload("res://scripts/ui/hud/hud_xp_bar.gd")
const HudStatusBar := preload("res://scripts/ui/hud/hud_status_bar.gd")
const HudMinimap := preload("res://scripts/ui/hud/hud_minimap.gd")
const HudBossBar := preload("res://scripts/ui/hud/hud_boss_bar.gd")
const HudNameplate := preload("res://scripts/ui/hud/hud_nameplate.gd")
const HudDamageNumbers := preload("res://scripts/ui/hud/hud_damage_numbers.gd")
const HudVignette := preload("res://scripts/ui/hud/hud_vignette.gd")
const HudAreaLabel := preload("res://scripts/ui/hud/hud_area_label.gd")
const HudAreaBanner := preload("res://scripts/ui/hud/hud_area_banner.gd")
const HudPassiveButton := preload("res://scripts/ui/hud/hud_passive_button.gd")
const HudCastBar := preload("res://scripts/ui/hud/hud_cast_bar.gd")
const HudPlate := preload("res://scripts/ui/hud/hud_plate.gd")
const HudTooltip := preload("res://scripts/ui/hud/hud_tooltip.gd")

const SKILL_SLOTS := 6
## One skill slot's can_use() (red tint) is re-checked this often, in turn (each slot every
## 6 × USABLE_STEP seconds).
const USABLE_STEP := 0.03
const SLOT_GAP := 6.0
const GROUP_GAP := 18.0
const CLUSTER_GAP := 14.0
const PLATE_PAD := Vector2(14, 10)
const EDGE := 14.0
## Hits of at least this fraction of max life flash the screen edges.
const HIT_FLASH_FRACTION := 0.08

var life_globe: Control = null
var mana_globe: Control = null
## HudSkillSlot per bar slot (0..5).
var skill_slots: Array[Control] = []
var life_potion: Control = null
var mana_potion: Control = null
var dodge_slot: Control = null
var xp_bar: Control = null
var status_bar: Control = null
var minimap: Control = null
var minimap_large: Control = null
var boss_bar: Control = null
var nameplate: Control = null
var damage_numbers: Control = null
var vignette: Control = null
var area_label: Control = null
var area_banner: Control = null
var passive_button: Control = null
var cast_bar: Control = null
var plate: Control = null
var tooltip: Control = null

## Smoothed CPU time of the HUD's own per-frame update (microseconds; profiling / demos).
var frame_cost_usec: float = 0.0

var _player: Actor = null
var _player_id := 0
var _character: CharacterData = null
var _usable_timer := 0.0
var _usable_next := 0
var _usable_full := true
var _large_map := false
var _interactive: Array[Control] = []
var _last_points := -1


func _init() -> void:
	name = "HUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	Events.player_spawned.connect(_on_player_spawned)
	Events.area_entered.connect(_on_area_entered)
	Events.area_cleared.connect(_on_area_cleared)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_killed.connect(_on_boss_killed)
	Events.damage_number.connect(_on_damage_number)
	Events.hovered_target_changed.connect(_on_hovered_target_changed)
	Events.level_up.connect(_on_level_up)
	Events.skill_bar_changed.connect(_refresh_skill_ids)
	Events.xp_changed.connect(_on_xp_changed)
	# Same FULL_RECT anchors UIRoot gives us, with zero offsets (also right when used standalone).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	# UIRoot creates the HUD while Events.area_entered is being emitted (too late for our own
	# connection), so the current area's title plays from here.
	if not GameState.current_area.is_empty():
		set_area(GameState.current_area, true)
	var p: Variant = GameState.player
	if p != null and is_instance_valid(p):
		bind_player(p)
	elif GameState.character != null:
		_character = GameState.character
		_refresh_skill_ids()


# ------------------------------------------------------------------ contract

## True if the screen point is over an interactive HUD element (skill bar, globes, buttons).
func is_point_over_hud(_screen_pos: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	for c in _interactive:
		if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if c == status_bar and r.size.x <= 0.0:
			continue
		if not r.has_point(_screen_pos):
			continue
		if c.has_method("_has_point"):
			var local := c.get_global_transform().affine_inverse() * _screen_pos
			if not bool(c.call("_has_point", local)):
				continue
		return true
	return false


# ------------------------------------------------------------------ binding

## Bind to a player (Events.player_spawned does this). null unbinds.
func bind_player(p: Node) -> void:
	if p != null and is_instance_valid(p) and p == _player:
		_character = _character_of(_player)
		_refresh_skill_ids()
		return
	_unbind()
	if p == null or not is_instance_valid(p) or not (p is Actor) or p.is_queued_for_deletion():
		return
	_player = p as Actor
	_player_id = p.get_instance_id()
	var c := _character_of(_player)
	if c != _character:
		# Another character (loaded / new game): no level-up or refill flashes for the switch.
		(xp_bar as HudXpBar).reset()
		(life_potion as HudPotionSlot).reset()
		(mana_potion as HudPotionSlot).reset()
		_last_points = -1
	_character = c
	if not _player.damaged.is_connected(_on_player_damaged):
		_player.damaged.connect(_on_player_damaged)
	_refresh_skill_ids()
	_update(0.0)
	(life_globe as HudGlobe).snap()
	(mana_globe as HudGlobe).snap()


## The bound, live player (null when there is none / it was freed).
func get_player() -> Actor:
	if _player == null:
		return null
	if not is_instance_valid(_player) or _player.is_queued_for_deletion():
		return null
	return _player


## The bound character (the player's CharacterData, else GameState.character).
func get_character() -> CharacterData:
	var p := get_player()
	if p != null:
		var c: Variant = p.get("character")
		if c is CharacterData:
			return c
	if _character != null:
		return _character
	return GameState.character


func _character_of(p: Actor) -> CharacterData:
	var c: Variant = p.get("character") if p != null else null
	if c is CharacterData:
		return c
	return GameState.character


func _unbind() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.damaged.is_connected(_on_player_damaged):
			_player.damaged.disconnect(_on_player_damaged)
	_player = null
	_player_id = 0


## Re-bind when the player changed or vanished without an event.
func _check_player() -> void:
	var gp: Variant = GameState.player
	var gp_ok: bool = gp != null and is_instance_valid(gp) and not (gp as Node).is_queued_for_deletion()
	if _player != null and (not is_instance_valid(_player) or _player.is_queued_for_deletion()):
		_unbind()
	if gp_ok and gp != _player:
		bind_player(gp)


# ------------------------------------------------------------------ actions (used by the widgets)

## Put a skill into a bar slot through CharacterData.set_skill_in_slot ("" clears; an id already
## on the bar swaps places).
func assign_skill(slot: int, skill_id: String) -> void:
	var c := get_character()
	if c == null or slot < 0 or slot >= SKILL_SLOTS:
		return
	c.set_skill_in_slot(slot, skill_id)
	_refresh_skill_ids()
	Sfx.play_ui("ui_click")


func open_skill_book(slot: int = -1) -> void:
	if get_player() == null and get_character() == null:
		return
	Sfx.play_ui("ui_click")
	Events.panel_open_requested.emit("skills", {"slot": slot})


func open_passive_tree() -> void:
	Sfx.play_ui("ui_click")
	Events.panel_open_requested.emit("passives", {})


func use_potion(kind: String) -> void:
	var p := get_player()
	if p != null and p.has_method("use_potion"):
		p.call("use_potion", kind)


func toggle_minimap() -> void:
	set_minimap_large(not _large_map)


func set_minimap_large(on: bool) -> void:
	_large_map = on
	minimap_large.visible = on
	minimap.visible = not on
	var w: Variant = GameState.world
	if on and w != null and is_instance_valid(w):
		(minimap_large as HudMinimap).refresh_data(w, true)


func is_minimap_large() -> bool:
	return _large_map


## Area name / level (and the fading title when `banner`).
func set_area(info: Dictionary, banner: bool = true) -> void:
	(area_label as HudAreaLabel).set_area(info)
	if banner and not info.is_empty():
		var al := area_label as HudAreaLabel
		(area_banner as HudAreaBanner).play(al.area_name, al.sub_text, al.accent)


## Same as Events.damage_number (demos / tests).
func spawn_damage_number(pos: Vector3, amount: float, kind: String, is_crit: bool) -> void:
	(damage_numbers as HudDamageNumbers).spawn(pos, amount, kind, is_crit)


func show_tooltip_for(source: Control, lines: Array, below: bool = false) -> void:
	(tooltip as HudTooltip).show_for(source, lines, below)


func hide_tooltip_for(source: Control) -> void:
	(tooltip as HudTooltip).hide_for(source)


# ------------------------------------------------------------------ build & layout

func _build() -> void:
	vignette = HudVignette.new()
	add_child(vignette)
	damage_numbers = HudDamageNumbers.new()
	add_child(damage_numbers)
	minimap_large = HudMinimap.new(true)
	minimap_large.visible = false
	add_child(minimap_large)

	status_bar = HudStatusBar.new(true, 40.0)
	status_bar.name = "PlayerStatus"
	add_child(status_bar)
	boss_bar = HudBossBar.new()
	add_child(boss_bar)
	nameplate = HudNameplate.new()
	add_child(nameplate)
	minimap = HudMinimap.new(false)
	add_child(minimap)
	area_label = HudAreaLabel.new()
	add_child(area_label)

	plate = HudPlate.new()
	add_child(plate)
	life_potion = HudPotionSlot.new("life")
	add_child(life_potion)
	for i in SKILL_SLOTS:
		var s := HudSkillSlot.new(i)
		add_child(s)
		skill_slots.append(s)
	mana_potion = HudPotionSlot.new("mana")
	add_child(mana_potion)
	dodge_slot = HudDodgeSlot.new()
	add_child(dodge_slot)
	xp_bar = HudXpBar.new()
	add_child(xp_bar)
	life_globe = HudGlobe.new("life")
	add_child(life_globe)
	mana_globe = HudGlobe.new("mana")
	add_child(mana_globe)
	passive_button = HudPassiveButton.new()
	add_child(passive_button)
	cast_bar = HudCastBar.new()
	add_child(cast_bar)
	area_banner = HudAreaBanner.new()
	add_child(area_banner)
	tooltip = HudTooltip.new()
	add_child(tooltip)

	# Full-screen layers follow the HUD rect through their anchors.
	for full: Control in [vignette, damage_numbers, minimap_large, tooltip]:
		full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for c: Control in [life_potion, mana_potion, dodge_slot, xp_bar, status_bar, passive_button]:
		c.set("hud", self)
	for s in skill_slots:
		s.set("hud", self)
	for c2: Control in [boss_bar, nameplate, minimap, minimap_large]:
		c2.set("hud", self)
	_interactive.assign([life_globe, mana_globe, life_potion, mana_potion, dodge_slot, xp_bar, status_bar, passive_button])
	_interactive.append_array(skill_slots)


func _layout() -> void:
	var W := size.x
	var H := size.y
	if W <= 0.0 or H <= 0.0:
		var vs := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
		W = vs.x
		H = vs.y
	var gs := life_globe.size
	life_globe.position = Vector2(EDGE, H - gs.y - 6.0)
	mana_globe.position = Vector2(W - EDGE - gs.x, H - gs.y - 6.0)

	# Bottom-centre cluster.
	var slot := HudSkillSlot.SLOT_SIZE
	var pot := Vector2(HudPotionSlot.SLOT_W, HudPotionSlot.SLOT_H)
	var dodge_w := HudDodgeSlot.SLOT_SIZE
	var skills_w := slot * 6.0 + SLOT_GAP * 4.0 + GROUP_GAP
	var cluster_w := pot.x + CLUSTER_GAP + skills_w + CLUSTER_GAP + pot.x + CLUSTER_GAP + dodge_w
	var plate_h := pot.y + PLATE_PAD.y * 2.0
	var plate_w := cluster_w + PLATE_PAD.x * 2.0
	var plate_bottom := H - 34.0
	var plate_pos := Vector2(roundf(W * 0.5 - plate_w * 0.5), plate_bottom - plate_h)
	plate.position = plate_pos
	plate.size = Vector2(plate_w, plate_h)
	var x := plate_pos.x + PLATE_PAD.x
	var mid_y := plate_pos.y + plate_h * 0.5
	life_potion.position = Vector2(x, mid_y - pot.y * 0.5)
	x += pot.x + CLUSTER_GAP
	var dividers := PackedFloat32Array()
	for i in SKILL_SLOTS:
		skill_slots[i].position = Vector2(x, mid_y - slot * 0.5)
		x += slot
		if i == 1:
			dividers.append(x + GROUP_GAP * 0.5 - plate_pos.x)
			x += GROUP_GAP
		elif i < SKILL_SLOTS - 1:
			x += SLOT_GAP
	x += CLUSTER_GAP
	mana_potion.position = Vector2(x, mid_y - pot.y * 0.5)
	x += pot.x + CLUSTER_GAP
	dodge_slot.position = Vector2(x, mid_y - dodge_slot.size.y * 0.5 + 6.0)
	(plate as HudPlate).dividers = dividers
	plate.queue_redraw()

	# XP bar between the globes.
	var xp_x0 := life_globe.position.x + gs.x + 8.0
	var xp_x1 := mana_globe.position.x - 8.0
	xp_bar.position = Vector2(xp_x0, H - 16.0 - xp_bar.custom_minimum_size.y * 0.5)
	xp_bar.size = Vector2(maxf(40.0, xp_x1 - xp_x0), xp_bar.custom_minimum_size.y)

	passive_button.position = Vector2(xp_x0 + 18.0, H - 86.0)
	cast_bar.position = Vector2(roundf(W * 0.5 - cast_bar.size.x * 0.5), plate_pos.y - cast_bar.size.y - 14.0)

	# Top row.
	status_bar.position = Vector2(18, 18)
	minimap.position = Vector2(W - 18.0 - minimap.size.x - 6.0, 22.0)
	area_label.position = Vector2(W - 24.0 - area_label.size.x, minimap.position.y + minimap.size.y + 12.0)
	boss_bar.position = Vector2(roundf(W * 0.5 - boss_bar.size.x * 0.5), 10.0)
	_place_nameplate()
	area_banner.position = Vector2(roundf(W * 0.5 - area_banner.size.x * 0.5), roundf(H * 0.3))


func _place_nameplate() -> void:
	var y := 16.0
	var bb := boss_bar as HudBossBar
	var np := nameplate as HudNameplate
	np.compact = bb.is_showing()
	if bb.is_showing():
		y = boss_bar.position.y + bb.get_content_bottom() + 8.0
	nameplate.position = Vector2(roundf(size.x * 0.5 - nameplate.size.x * 0.5), y)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var t0 := Time.get_ticks_usec()
	_check_player()
	_update(delta)
	frame_cost_usec = lerpf(frame_cost_usec, float(Time.get_ticks_usec() - t0), 0.1)


func _update(delta: float) -> void:
	var p := get_player()
	var c := get_character()
	# Globes.
	var lg := life_globe as HudGlobe
	var mg := mana_globe as HudGlobe
	if p != null:
		lg.set_values(p.life, p.max_life, p.es, p.max_es, p.life_regen, delta)
		mg.set_values(p.mana, p.max_mana, 0.0, 0.0, p.mana_regen, delta)
		lg.set_low(not p.dead and p.is_low_life())
		if p.has_ailment("freeze"):
			lg.set_tint(Color(0.6, 0.88, 1.0), 1.0)
		elif p.has_ailment("poison"):
			lg.set_tint(Color(0.35, 0.95, 0.15), 1.0)
		else:
			lg.set_tint(lg.get_tint_color(), 0.0)
	else:
		lg.set_values(lg.value, lg.max_value, lg.es, lg.max_es, 0.0, delta)
		mg.set_values(mg.value, mg.max_value, 0.0, 0.0, 0.0, delta)
		lg.set_low(false)
	# Skill bar.
	_update_skill_slots(p, c, delta)
	# Potions, dodge, cast bar (Player extras; other actors show no activity).
	var pl := p as Player
	var life_active := 0.0
	var mana_active := 0.0
	if pl != null:
		life_active = pl.get_potion_active_ratio("life")
		mana_active = pl.get_potion_active_ratio("mana")
	if c != null:
		(life_potion as HudPotionSlot).set_state(c.life_potion_charges, Balance.POTION_MAX_CHARGES, life_active)
		(mana_potion as HudPotionSlot).set_state(c.mana_potion_charges, Balance.POTION_MAX_CHARGES, mana_active)
	if pl != null:
		(dodge_slot as HudDodgeSlot).set_state(pl.get_dodge_cooldown_ratio(), not pl.dead and pl.can_act())
	var casting := pl != null and pl.is_casting_portal()
	(cast_bar as HudCastBar).step(casting, pl.get_portal_cast_ratio() if casting else 0.0, delta)
	# XP + passive points.
	if c != null:
		(xp_bar as HudXpBar).set_xp(c.xp, c.xp_to_next(), c.level, c.is_max_level())
		var pts := c.passive_points_unspent()
		if pts != _last_points:
			(passive_button as HudPassiveButton).set_points(pts, _last_points >= 0)
			_last_points = pts
	(xp_bar as HudXpBar).step(delta)
	(passive_button as HudPassiveButton).step(delta)
	# Status icons.
	(status_bar as HudStatusBar).update_from(p, delta)
	# Top widgets.
	(boss_bar as HudBossBar).step(delta)
	var np := nameplate as HudNameplate
	var bb := boss_bar as HudBossBar
	var hidden_by_boss := bb.is_showing() and np.get_target() != null and np.get_target() == bb.get_boss()
	np.step(delta, hidden_by_boss)
	_place_nameplate()
	var world: Variant = GameState.world
	var w: Node = world if world != null and is_instance_valid(world) else null
	if _large_map:
		(minimap_large as HudMinimap).step(delta, w, p)
	else:
		(minimap as HudMinimap).step(delta, w, p)
	(vignette as HudVignette).step(p.life_ratio() if p != null else 1.0, p != null and not p.dead, delta)
	(area_banner as HudAreaBanner).step(delta)


func _update_skill_slots(p: Actor, c: CharacterData, delta: float) -> void:
	var runner: SkillRunner = null
	if p != null and p.skill_runner != null and is_instance_valid(p.skill_runner):
		runner = p.skill_runner
	# can_use() resolves the skill and its cost (tens of microseconds): after a bar change every
	# slot is checked at once, otherwise one slot per USABLE_STEP in turn.
	var check_all := _usable_full
	_usable_full = false
	var check_slot := -1
	_usable_timer -= delta
	if not check_all and _usable_timer <= 0.0:
		_usable_timer = USABLE_STEP
		check_slot = _usable_next
		_usable_next = (_usable_next + 1) % SKILL_SLOTS
	var pl := p as Player
	var current := runner.get_current_skill() if runner != null else ""
	for i in SKILL_SLOTS:
		var s := skill_slots[i] as HudSkillSlot
		var id := c.get_skill_in_slot(i) if c != null else ""
		s.set_skill(id)
		var check := check_all or i == check_slot
		if id == "" or runner == null:
			s.set_state(0.0, 0.0, false)
			if check:
				s.set_usable("", "")
			continue
		var held := pl != null and pl.is_slot_held(i)
		var ratio := runner.get_cooldown_ratio(id)
		s.set_state(ratio, runner.get_cooldown_remaining(id) if ratio > 0.0 else 0.0, held or current == id)
		if check:
			var r: Dictionary = runner.can_use(id)
			s.set_usable(String(r.get("code", "ok")), String(r.get("reason", "")))


func _refresh_skill_ids() -> void:
	var c := get_character()
	for i in skill_slots.size():
		(skill_slots[i] as HudSkillSlot).set_skill(c.get_skill_in_slot(i) if c != null else "")
	_usable_full = true


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.is_action_pressed("toggle_minimap") and not event.is_echo():
		if get_viewport().gui_get_focus_owner() is LineEdit or UI.is_modal_open():
			return
		toggle_minimap()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ events

func _on_player_spawned(p: Node) -> void:
	bind_player(p)


func _on_area_entered(info: Dictionary) -> void:
	(boss_bar as HudBossBar).hide_boss(true)
	(nameplate as HudNameplate).clear()
	(minimap as HudMinimap).reset()
	(minimap_large as HudMinimap).reset()
	(damage_numbers as HudDamageNumbers).clear()
	(tooltip as HudTooltip).hide_tooltip()
	set_area(info, true)


func _on_area_cleared(_info: Dictionary) -> void:
	(area_label as HudAreaLabel).set_cleared(true)


func _on_boss_spawned(b: Node) -> void:
	(boss_bar as HudBossBar).show_boss(b)
	_place_nameplate()


func _on_boss_killed(b: Node) -> void:
	var bb := boss_bar as HudBossBar
	var cur := bb.get_boss()
	if cur == null or cur == b or (b != null and bb.get_boss_instance_id() == b.get_instance_id()):
		bb.hide_boss()


func _on_damage_number(pos: Vector3, amount: float, kind: String, is_crit: bool) -> void:
	if not is_visible_in_tree():
		return
	(damage_numbers as HudDamageNumbers).spawn(pos, amount, kind, is_crit)


func _on_hovered_target_changed(target: Node) -> void:
	var np := nameplate as HudNameplate
	if target == null or not is_instance_valid(target) or not (target is Actor):
		np.clear()
		return
	var a := target as Actor
	var p := get_player()
	var hostile := CombatQuery.is_hostile(p, a) if p != null else a.team != Actor.Team.PLAYER
	if hostile and not a.dead:
		np.set_target(a)
	else:
		np.clear()


func _on_level_up(_new_level: int) -> void:
	(life_globe as HudGlobe).flash(0.9)
	(mana_globe as HudGlobe).flash(0.9)


func _on_xp_changed(_xp: int, _needed: int, _level: int) -> void:
	var c := get_character()
	if c != null:
		(xp_bar as HudXpBar).set_xp(c.xp, c.xp_to_next(), c.level, c.is_max_level())


func _on_player_damaged(amount: float, _is_crit: bool, _source: Node) -> void:
	var p := get_player()
	if p == null or p.max_life <= 0.0:
		return
	var frac := amount / p.max_life
	if frac >= HIT_FLASH_FRACTION:
		(vignette as HudVignette).flash_hit(clampf(frac * 2.5, 0.3, 1.0))

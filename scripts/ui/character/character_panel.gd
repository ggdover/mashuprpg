class_name CharacterPanel
extends Control
## Character sheet: attributes, life/mana/ES, defences, resistances, offence of the skill in slot 1 (damage, speed, crit, DPS).
## OWNER: UI items module (wave 2). CONTRACT STUB — keep every public member/signature.
## See docs/ARCHITECTURE.md §16.
##
## Docked on the left edge, or just right of the vendor / stash frame while one of those is open
## (they dock on the left edge too). Sections:
##   header      name, level, class, XP bar
##   attributes  Strength / Dexterity / Intelligence (hover: their bonuses, §5.2)
##   pools       life, mana, energy shield with regeneration / recharge
##   defence     armour (+ physical reduction against an average hit of the reference monster
##               level), evasion (+ evade chance), block
##   resistances fire / cold / lightning / chaos / physical; the dungeon penalty (§5.3) is shown
##   offence     one row per skill on the skill bar: damage range per type, uses per second, crit,
##               cost and DPS (SkillDB.get_resolved + DamageCalc); falls back to a plain weapon
##               attack when SkillDB knows none of them
##   other       movement speed, crit multiplier, item rarity / quantity, gold found, leech, ...
## Stats come from the live Player (buffs included) when there is one, else from an off-tree
## stand-in computed from GameState.character. Refreshes on player_stats_changed and the other
## character signals. Every row has a hover tooltip explaining the number.

const SheetActor := preload("res://scripts/ui/character/inv_sheet_actor.gd")
const PANEL_ID := "character"
const WIDTH := 520.0
const ATTR_COLORS := {
	"strength": Color(0.9, 0.42, 0.34),
	"dexterity": Color(0.48, 0.85, 0.42),
	"intelligence": Color(0.46, 0.62, 1.0),
}
const RESIST_ORDER: Array[String] = ["fire", "cold", "lightning", "chaos", "physical"]
## Gap between the sheet and a vendor / stash frame it docks beside.
const DOCK_GAP := 8.0
const NO_DAMAGE_DELIVERIES: Array[String] = ["buff", "blink", "summon"]

var _built := false
var _frame: PanelContainer = null
var _name_label: Label = null
var _class_label: Label = null
var _xp_bar: XpBar = null
var _attr_boxes: Dictionary = {}       # attr -> AttrBox
var _rows: Dictionary = {}             # key -> StatRow
var _resist_chips: Dictionary = {}     # type -> ResistChip
var _penalty_label: Label = null
var _skill_box: VBoxContainer = null
var _skill_rows: Array = []            # SkillRow
var _other_grid: GridContainer = null
var _keystone_label: Label = null
var _sheet: SheetActor = null
var _refresh_queued := false
var _dock_x := -1.0
## Last computed values (tests / debugging): key -> float.
var _values: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	Events.player_stats_changed.connect(_queue_refresh)
	Events.equipment_changed.connect(_on_any_str)
	Events.passives_changed.connect(_queue_refresh)
	Events.level_up.connect(_on_any_int)
	Events.xp_changed.connect(_on_xp_changed)
	Events.skill_bar_changed.connect(_queue_refresh)
	Events.area_entered.connect(_on_any_dict)
	Events.player_spawned.connect(_on_any_node)
	visibility_changed.connect(_on_visibility_changed)


func _exit_tree() -> void:
	if _sheet != null:
		_sheet.free()
		_sheet = null


## Called by UIRoot after the panel becomes visible.
func on_opened(_context: Dictionary) -> void:
	_build()
	update_dock()
	refresh()


func _process(_delta: float) -> void:
	# The vendor / stash can open or close while the sheet is open.
	if is_visible_in_tree():
		update_dock()


## Dock the frame just right of an open vendor / stash frame (both dock on the left edge), else on
## the left edge.
func update_dock() -> void:
	if _frame == null:
		return
	var x := InvStyle.SCREEN_MARGIN
	for p: Control in [InvActions.vendor_panel, InvActions.stash_panel]:
		if p == null or not is_instance_valid(p) or not p.is_visible_in_tree() or not p.has_method("get_frame"):
			continue
		var f: Control = p.call("get_frame")
		if f == null or not f.is_visible_in_tree():
			continue
		x = maxf(x, f.get_global_rect().end.x - get_global_rect().position.x + DOCK_GAP)
	if not is_equal_approx(x, _dock_x):
		_dock_x = x
		InvStyle.dock_left(_frame, InvStyle.PANEL_TOP, x)
		UI.hide_tooltip()


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	UI.hide_tooltip()


func get_frame() -> Control:
	return _frame


## Computed values of the last refresh, e.g. "max_life", "armour", "fire_res", "dps_0".
func get_values() -> Dictionary:
	return _values


## The stat row for a key ("life", "mana", "es", "armour", "evasion", "block", "move_speed", ...).
func get_row(key: String) -> Control:
	_build()
	return _rows.get(key, null)


## The skill rows currently shown (one per skill on the bar, or the weapon fallback).
func get_skill_rows() -> Array:
	return _skill_rows


## The actor the sheet reads: the live Player when valid, else the off-tree stand-in.
func get_stat_actor() -> Actor:
	var p: Variant = GameState.player
	if p != null and is_instance_valid(p) and (p as Node).is_inside_tree() and p is Actor and (p as Actor).get("character") == GameState.character:
		return p
	var c := GameState.character
	if c == null:
		return null
	if _sheet == null:
		_sheet = SheetActor.new()
		_sheet.setup(c)
	elif _sheet.character != c:
		_sheet.setup(c)
	else:
		_sheet.refresh()
	return _sheet


## Monster level used for the armour / evasion estimates: the current dungeon's level, else the
## level of the deepest unlocked depth.
static func reference_level() -> int:
	var info: Dictionary = GameState.current_area
	if String(info.get("id", "")) == "dungeon" or (String(info.get("id", "")) == "act" and not bool(info.get("safe", false))):
		return maxi(1, int(info.get("level", 1)))
	var c := GameState.character
	return Balance.area_level_for_depth(c.max_depth if c != null else 1)


## Recompute and redraw everything.
func refresh() -> void:
	_build()
	_refresh_queued = false
	_values.clear()
	var c := GameState.character
	var a := get_stat_actor()
	if c == null or a == null:
		_name_label.text = "No character"
		_class_label.text = ""
		return
	_refresh_header(c)
	_refresh_attributes(a)
	_refresh_pools(a)
	_refresh_defence(a)
	_refresh_resists(a)
	_refresh_offence(c, a)
	_refresh_other(a)


# ------------------------------------------------------------------ sections

func _refresh_header(c: CharacterData) -> void:
	_name_label.text = c.char_name
	_class_label.text = "Level %d %s" % [c.level, ClassDefs.get_display_name(c.class_id)]
	_class_label.add_theme_color_override("font_color", ClassDefs.get_color(c.class_id).lerp(UIStyle.COLOR_TEXT, 0.35))
	if c.is_max_level():
		_xp_bar.set_progress(1.0, "Maximum level")
	else:
		var need := maxi(1, c.xp_to_next())
		_xp_bar.set_progress(float(c.xp) / float(need), "%s / %s XP  (%d%%)" % [InvStyle.format_int(c.xp), InvStyle.format_int(need), int(floorf(100.0 * c.xp / need))])
	_xp_bar.tip = [
		InvStyle.line("Experience", UIStyle.COLOR_TITLE, "title"),
		InvStyle.line("%s XP to level %d" % [InvStyle.format_int(maxi(0, c.xp_to_next() - c.xp)), c.level + 1], UIStyle.COLOR_TEXT, "normal"),
		InvStyle.line("Passive points: %d unspent of %d" % [c.passive_points_unspent(), c.passive_points_total()], UIStyle.COLOR_TEXT_DIM),
	]


func _refresh_attributes(a: Actor) -> void:
	var s := float(a.attributes.get("strength", 0.0))
	var d := float(a.attributes.get("dexterity", 0.0))
	var i := float(a.attributes.get("intelligence", 0.0))
	var bonus := {
		"strength": ["+%d maximum Life" % int(floorf(s / 2.0)), "%d%% increased Melee Damage" % int(floorf(s / 5.0))],
		"dexterity": ["%d%% increased Evasion Rating" % int(floorf(d / 5.0)), "%d%% increased Attack Speed" % int(floorf(d / 10.0)), "%d%% increased Projectile Damage" % int(floorf(d / 10.0))],
		"intelligence": ["+%d maximum Mana" % int(floorf(i / 2.0)), "%d%% increased maximum Energy Shield" % int(floorf(i / 5.0)), "%d%% increased Spell Damage" % int(floorf(i / 10.0))],
	}
	var every := {"strength": "Every 2 Strength: +1 Life. Every 5: +1% Melee Damage.", "dexterity": "Every 5 Dexterity: +1% Evasion. Every 10: +1% Attack Speed and Projectile Damage.", "intelligence": "Every 2 Intelligence: +1 Mana. Every 5: +1% Energy Shield. Every 10: +1% Spell Damage."}
	for attr: String in _attr_boxes:
		var v := float(a.attributes.get(attr, 0.0))
		_values[attr] = v
		var box: AttrBox = _attr_boxes[attr]
		box.value = str(int(floorf(v)))
		var tip: Array = [InvStyle.line(attr.capitalize(), ATTR_COLORS[attr], "title"), InvStyle.line("%d" % int(floorf(v)), UIStyle.COLOR_TEXT, "normal"), InvStyle.separator()]
		for b: String in bonus[attr]:
			tip.append(InvStyle.line(b, UIStyle.COLOR_MOD, "normal"))
		tip.append(InvStyle.separator())
		tip.append(InvStyle.line(String(every[attr]), UIStyle.COLOR_TEXT_DIM))
		box.tip = tip
		box.queue_redraw()


func _refresh_pools(a: Actor) -> void:
	_values["max_life"] = a.max_life
	_values["max_mana"] = a.max_mana
	_values["max_es"] = a.max_es
	_set_row("life", InvStyle.format_int(roundi(a.max_life)), UIStyle.COLOR_LIFE.lightened(0.35),
		"Regenerates %s / s" % _num(a.life_regen, 1) if a.life_regen > 0.0 else "No regeneration",
		[InvStyle.line("Maximum Life", UIStyle.COLOR_LIFE.lightened(0.35), "title"), InvStyle.line("%s Life" % InvStyle.format_int(roundi(a.max_life)), UIStyle.COLOR_TEXT, "normal"),
		InvStyle.line("Regeneration: %s / s" % _num(a.life_regen, 1), UIStyle.COLOR_TEXT_DIM), InvStyle.separator(),
		InvStyle.line("When your Life reaches zero you die. Strength and gear raise it.", UIStyle.COLOR_TEXT_DIM)])
	var blood := a.stats.has_flag("blood_magic")
	_set_row("mana", "Blood Magic" if blood else InvStyle.format_int(roundi(a.max_mana)), UIStyle.COLOR_MANA.lightened(0.45),
		"Skills cost Life instead" if blood else "Regenerates %s / s" % _num(a.mana_regen, 1),
		[InvStyle.line("Maximum Mana", UIStyle.COLOR_MANA.lightened(0.45), "title"), InvStyle.line("%s Mana" % InvStyle.format_int(roundi(a.max_mana)), UIStyle.COLOR_TEXT, "normal"),
		InvStyle.line("Regeneration: %s / s" % _num(a.mana_regen, 1), UIStyle.COLOR_TEXT_DIM), InvStyle.separator(),
		InvStyle.line("Skills cost Mana. Regeneration: (2 + 3% of maximum Mana) per second.", UIStyle.COLOR_TEXT_DIM)])
	_set_row("es", InvStyle.format_int(roundi(a.max_es)), UIStyle.COLOR_ES,
		("Recharges %s / s" % _num(a.es_recharge_rate, 1)) if a.max_es > 0.0 else "None",
		[InvStyle.line("Energy Shield", UIStyle.COLOR_ES, "title"), InvStyle.line("%s Energy Shield" % InvStyle.format_int(roundi(a.max_es)), UIStyle.COLOR_TEXT, "normal"), InvStyle.separator(),
		InvStyle.line("Absorbs damage before your Life. Starts recharging 2 seconds after you were last hit.", UIStyle.COLOR_TEXT_DIM)])


func _refresh_defence(a: Actor) -> void:
	var lvl := reference_level()
	var raw := Balance.monster_damage(lvl)
	var ar := DamageCalc.armour_reduction(a.armour, raw)
	var phys := float(a.resistances.get("physical", 0.0)) / 100.0
	var total := 1.0 - (1.0 - ar) * (1.0 - phys)
	_values["armour"] = a.armour
	_values["phys_reduction"] = total * 100.0
	_set_row("armour", InvStyle.format_int(roundi(a.armour)), UIStyle.COLOR_TEXT,
		"Reduces level %d hits by %d%%" % [lvl, roundi(total * 100.0)],
		[InvStyle.line("Armour", UIStyle.COLOR_TITLE, "title"), InvStyle.line("%s Armour" % InvStyle.format_int(roundi(a.armour)), UIStyle.COLOR_TEXT, "normal"), InvStyle.separator(),
		InvStyle.line("Reduces physical damage taken from hits: armour / (armour + 10 x hit).", UIStyle.COLOR_TEXT_DIM),
		InvStyle.line("Against an average level %d monster hit (%d damage): %d%%" % [lvl, roundi(raw), roundi(ar * 100.0)], UIStyle.COLOR_TEXT),
		InvStyle.line("Additional physical damage reduction: %d%%" % roundi(phys * 100.0), UIStyle.COLOR_TEXT),
		InvStyle.line("Bigger hits are reduced less.", UIStyle.COLOR_TEXT_DIM)])
	var ev := DamageCalc.evade_chance(a, lvl)
	_values["evasion"] = a.evasion
	_values["evade_chance"] = ev
	var ev_sub := "Evades %d%% of level %d attacks" % [roundi(ev), lvl]
	if a.stats.has_flag("cannot_evade"):
		ev_sub = "Cannot evade (Unwavering)"
	elif a.stats.has_flag("iron_reflexes"):
		ev_sub = "Converted to Armour"
	_set_row("evasion", InvStyle.format_int(roundi(a.evasion)), UIStyle.COLOR_TEXT, ev_sub,
		[InvStyle.line("Evasion Rating", UIStyle.COLOR_TITLE, "title"), InvStyle.line("%s Evasion" % InvStyle.format_int(roundi(a.evasion)), UIStyle.COLOR_TEXT, "normal"), InvStyle.separator(),
		InvStyle.line("Gives a chance to avoid attack hits entirely (spells can't be evaded).", UIStyle.COLOR_TEXT_DIM),
		InvStyle.line("Against level %d monsters: %.1f%% (maximum 75%%)" % [lvl, ev], UIStyle.COLOR_TEXT)])
	_values["block"] = a.block_chance
	_set_row("block", "%d%%" % roundi(a.block_chance), UIStyle.COLOR_TEXT,
		"Attacks and projectiles" if a.block_chance > 0.0 else "Needs a shield or staff",
		[InvStyle.line("Chance to Block", UIStyle.COLOR_TITLE, "title"), InvStyle.line("%d%%" % roundi(a.block_chance), UIStyle.COLOR_TEXT, "normal"), InvStyle.separator(),
		InvStyle.line("A blocked attack or projectile deals no damage. Maximum 75%.", UIStyle.COLOR_TEXT_DIM)])


func _refresh_resists(a: Actor) -> void:
	var pen := _current_penalty()
	var c := GameState.character
	for t: String in RESIST_ORDER:
		var chip: ResistChip = _resist_chips[t]
		var v := float(a.resistances.get(t, 0.0))
		var raw := float(a.resistances_uncapped.get(t, v))
		_values[t + "_res"] = v
		chip.value = v
		chip.capped = t != "physical" and raw > StatDefs.RESIST_CAP
		var name := "Physical Damage Reduction" if t == "physical" else "%s Resistance" % t.capitalize()
		var tip: Array = [InvStyle.line(name, UIStyle.damage_color(t), "title"), InvStyle.line("%d%%" % roundi(v), UIStyle.COLOR_TEXT, "normal")]
		if t != "physical":
			tip.append(InvStyle.line("Uncapped: %d%%   (maximum %d%%)" % [roundi(raw), roundi(StatDefs.RESIST_CAP)], UIStyle.COLOR_TEXT_DIM))
			if pen != 0.0:
				tip.append(InvStyle.line("Includes the dungeon penalty of %d%%" % roundi(pen), UIStyle.COLOR_BAD))
			tip.append(InvStyle.separator())
			tip.append(InvStyle.line("Reduces %s damage taken from hits and damage over time." % t, UIStyle.COLOR_TEXT_DIM))
		else:
			tip.append(InvStyle.separator())
			tip.append(InvStyle.line("Reduces all physical damage taken, after armour. Maximum 75%.", UIStyle.COLOR_TEXT_DIM))
		chip.tip = tip
		chip.queue_redraw()
	if pen != 0.0:
		var depth := int(GameState.current_area.get("depth", 0))
		var where := "Depth %d" % depth
		if String(GameState.current_area.get("id", "")) == "act":
			where = String(GameState.current_area.get("name", "Here"))
		_penalty_label.text = "%s: %d%% to elemental and chaos resistances (applied)" % [where, roundi(pen)]
		_penalty_label.add_theme_color_override("font_color", UIStyle.COLOR_BAD.lerp(UIStyle.COLOR_TEXT, 0.25))
	else:
		var d := c.max_depth if c != null else 1
		var future := Balance.resist_penalty(Balance.area_level_for_depth(d))
		_penalty_label.text = "In Depth %d: %d%% to elemental and chaos resistances" % [d, roundi(future)]
		_penalty_label.add_theme_color_override("font_color", UIStyle.COLOR_TEXT_DIM)
	_values["resist_penalty"] = pen


func _refresh_offence(c: CharacterData, a: Actor) -> void:
	var entries: Array = []
	var seen := {}
	for i in c.skill_bar.size():
		var id := c.get_skill_in_slot(i)
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		var sk := SkillDB.get_resolved(id, a)
		if sk.is_empty():
			continue
		entries.append({"id": id, "skill": sk, "slot": i})
	if entries.is_empty():
		entries.append({"id": "basic_attack", "skill": _fallback_attack(a), "slot": -1})
	while _skill_rows.size() < entries.size():
		var r := SkillRow.new()
		r.frame = _frame
		_skill_box.add_child(r)
		_skill_rows.append(r)
	while _skill_rows.size() > entries.size():
		var r: SkillRow = _skill_rows.pop_back()
		r.queue_free()
	for k in entries.size():
		var e: Dictionary = entries[k]
		var row: SkillRow = _skill_rows[k]
		_fill_skill_row(row, c, a, e)
		_values["dps_%d" % k] = row.dps
		_values["skill_%d" % k] = String(e["id"])


func _fill_skill_row(row: SkillRow, c: CharacterData, a: Actor, e: Dictionary) -> void:
	var id: String = e["id"]
	var sk: Dictionary = e["skill"]
	var slot: int = e["slot"]
	row.skill_id = id
	row.icon = Assets.skill_icon(id)
	row.title = String(sk.get("name", id.capitalize()))
	row.key = Controls.skill_slot_label(slot) if slot >= 0 else ""
	var tags := PackedStringArray(sk.get("tags", PackedStringArray()))
	var is_attack := tags.has("attack")
	var deals := not NO_DAMAGE_DELIVERIES.has(String(sk.get("delivery", "")))
	row.damage_parts = []
	row.dps = 0.0
	row.problem = ""
	var unlock := int(sk.get("unlock_level", 1))
	if unlock > c.level:
		row.problem = "Requires Level %d" % unlock
	elif SkillDB.has_skill(id):
		var wt := String(a.get_weapon().get("weapon_type", "unarmed"))
		if not SkillDB.is_weapon_compatible(id, wt):
			var req := SkillDB.get_weapon_requirement_text(id)
			row.problem = req if req != "" else "Can't be used with this weapon"
	var bits: PackedStringArray = []
	var use_time := DamageCalc.get_use_time(a, sk)
	if deals:
		var ranges := DamageCalc.get_damage_range(a, sk)
		for t: String in StatDefs.DAMAGE_TYPES:
			if ranges.has(t):
				var r: Vector2 = ranges[t]
				if r.y >= 0.5:
					row.damage_parts.append({"text": "%d-%d" % [roundi(r.x), roundi(r.y)], "type": t})
		var dps := 0.0
		if SkillDB.has_method("estimate_dps") and SkillDB.has_skill(id):
			dps = float(SkillDB.call("estimate_dps", id, a))
		else:
			dps = DamageCalc.estimate_dps(a, sk)
		row.dps = dps
		bits.append("%.2f/s" % (1.0 / use_time))
		bits.append("%.1f%% crit" % DamageCalc.get_crit_chance(a, sk))
	else:
		bits.append("%.2f s" % use_time)
	var cd := DamageCalc.get_cooldown(a, sk)
	if cd > 0.0:
		bits.append("%.1fs cd" % cd)
	var cost := DamageCalc.get_cost(a, sk)
	if String(sk.get("delivery", "")) == "channel_aoe":
		cost = DamageCalc.scale_cost(a, float((sk.get("params", {}) as Dictionary).get("cost_per_tick", 0.0)))
	if cost > 0.0:
		bits.append("%s %s" % [_num(cost, 1), "life" if a.stats.has_flag("blood_magic") else "mana"])
	row.detail = "  ·  ".join(bits)
	if not deals:
		row.damage_parts = [{"text": _utility_text(sk), "type": ""}]
	var tip: Array = []
	if SkillDB.has_skill(id):
		tip = SkillDB.get_tooltip_lines(id, a)
	if tip.is_empty():
		tip = [InvStyle.line(row.title, UIStyle.COLOR_TITLE, "title"), InvStyle.line("Your weapon's basic attack", UIStyle.COLOR_TEXT_DIM)]
		if row.dps > 0.0:
			tip.append(InvStyle.line("Estimated DPS: %.1f" % row.dps, UIStyle.COLOR_TEXT))
	row.tip = tip
	row.queue_redraw()


func _utility_text(sk: Dictionary) -> String:
	match String(sk.get("delivery", "")):
		"buff":
			var dur := float((sk.get("params", {}) as Dictionary).get("duration", 0.0))
			return "Buff" + (" for %s s" % _num(dur, 0) if dur > 0.0 else "")
		"blink":
			return "Movement"
		"summon":
			return "Summon"
	return "Utility"


## A plain weapon attack used when SkillDB knows none of the bar skills (e.g. before the skill
## data exists): melee or projectile by weapon type.
func _fallback_attack(a: Actor) -> Dictionary:
	var wt := String(a.get_weapon().get("weapon_type", "unarmed"))
	var ranged := wt in ["bow", "crossbow", "wand"]
	return {"id": "basic_attack", "name": "Attack", "tags": PackedStringArray(["attack", "projectile" if ranged else "melee"]),
		"damage_effectiveness": 1.0, "attack_time_mult": 1.0, "delivery": "weapon_default", "params": {}, "unlock_level": 1}


func _refresh_other(a: Actor) -> void:
	var st := a.stats
	var mult := a.get_move_speed_mult()
	var ms := a.base_move_speed * mult
	_values["move_speed"] = ms
	var ms_pct := roundi((mult - 1.0) * 100.0)
	_set_row("move_speed", "%s m/s" % _num(ms, 1), UIStyle.COLOR_TEXT if ms_pct == 0 else UIStyle.COLOR_MOD, "" if ms_pct == 0 else "%+d%%" % ms_pct,
		[InvStyle.line("Movement Speed", UIStyle.COLOR_TITLE, "title"), InvStyle.line("%s metres per second" % _num(ms, 2), UIStyle.COLOR_TEXT, "normal"), InvStyle.line("Base %s m/s, %+d%% from modifiers" % [_num(a.base_move_speed, 1), roundi((mult - 1.0) * 100.0)], UIStyle.COLOR_TEXT_DIM)])
	var cm := DamageCalc.get_crit_multiplier(a)
	_values["crit_multiplier"] = cm
	_set_row("crit_multi", "%d%%" % roundi(cm), UIStyle.COLOR_TEXT, "",
		[InvStyle.line("Critical Strike Multiplier", UIStyle.COLOR_TITLE, "title"), InvStyle.line("Critical strikes deal %d%% of the hit's damage." % roundi(cm), UIStyle.COLOR_TEXT_DIM)])
	for pair: Array in [["rarity", "item_rarity", "Rarity of Items found", "Raises the chance that dropped items are Magic, Rare or Unique."],
			["quantity", "item_quantity", "Quantity of Items found", "More items drop from monsters."],
			["gold", "gold_find", "Gold found", "Gold piles are bigger."]]:
		var v := st.flat(pair[1]) + st.inc(pair[1])
		_values[pair[0]] = v
		_set_row(pair[0], "%+d%%" % roundi(v), UIStyle.COLOR_TEXT if v == 0.0 else UIStyle.COLOR_MOD, "",
			[InvStyle.line(pair[2], UIStyle.COLOR_TITLE, "title"), InvStyle.line("%+d%%" % roundi(v), UIStyle.COLOR_TEXT, "normal"), InvStyle.line(pair[3], UIStyle.COLOR_TEXT_DIM)])
	var leech := st.flat("life_leech")
	_values["life_leech"] = leech
	_set_row("leech", "%s%%" % _num(leech, 1), UIStyle.COLOR_TEXT if leech == 0.0 else UIStyle.COLOR_MOD, "",
		[InvStyle.line("Life Leech", UIStyle.COLOR_TITLE, "title"), InvStyle.line("%s%% of hit damage leeched as Life" % _num(leech, 1), UIStyle.COLOR_TEXT, "normal"),
		InvStyle.line("Mana leech: %s%%   ·   Life on hit: %s   ·   Life on kill: %s" % [_num(st.flat("mana_leech"), 1), _num(st.flat("life_on_hit"), 0), _num(st.flat("life_on_kill"), 0)], UIStyle.COLOR_TEXT_DIM),
		InvStyle.line("Leech and life on hit restore at most 20% of maximum Life per second.", UIStyle.COLOR_TEXT_DIM)])
	var ks: PackedStringArray = []
	for stat: String in StatDefs.STATS:
		var info: Dictionary = StatDefs.STATS[stat]
		if info.has("flag") and st.has_flag(stat):
			ks.append(String(info.get("name", stat)))
	_keystone_label.visible = not ks.is_empty()
	_keystone_label.text = "Keystones: " + ", ".join(ks)


func _set_row(key: String, value: String, color: Color, sub: String, tip: Array) -> void:
	var row: StatRow = _rows.get(key)
	if row == null:
		return
	row.value = value
	row.value_color = color
	row.sub = sub
	row.tip = tip
	row.queue_redraw()


func _current_penalty() -> float:
	var a := get_stat_actor()
	if a != null and a.has_method("get_resist_penalty"):
		return float(a.call("get_resist_penalty"))
	return SheetActor.get_resist_penalty()


static func _num(v: float, decimals: int) -> String:
	if decimals <= 0:
		return InvStyle.format_int(roundi(v))
	return ("%." + str(decimals) + "f") % v


func _queue_refresh(_a: Variant = null) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	if not _refresh_queued:
		return
	if is_visible_in_tree():
		refresh()
	else:
		_refresh_queued = false


func _on_any_str(_s: String) -> void:
	_queue_refresh()


func _on_any_int(_i: int) -> void:
	_queue_refresh()


func _on_any_dict(_d: Dictionary) -> void:
	_queue_refresh()


func _on_any_node(_n: Node) -> void:
	_queue_refresh()


func _on_xp_changed(_xp: int, _need: int, _lvl: int) -> void:
	_queue_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_queue_refresh()


func _request_close() -> void:
	Events.panel_close_requested.emit(PANEL_ID)
	if visible:
		visible = false
		on_closed()


# ------------------------------------------------------------------ build

func _build() -> void:
	if _built:
		return
	_built = true
	var f := InvStyle.make_frame("Character", _request_close, WIDTH)
	_frame = f["frame"]
	_frame.name = "Frame"
	add_child(_frame)
	InvStyle.dock_left(_frame)
	_dock_x = InvStyle.SCREEN_MARGIN
	var body: VBoxContainer = f["body"]
	body.add_theme_constant_override("separation", 8)
	# Header.
	var head := VBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 2)
	body.add_child(head)
	_name_label = UIStyle.make_label("", 28, UIStyle.COLOR_TITLE)
	_name_label.add_theme_font_override("font", InvStyle.title_font())
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("outline_size", 4)
	head.add_child(_name_label)
	_class_label = UIStyle.make_label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT)
	_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_class_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_xp_bar = XpBar.new()
	_xp_bar.name = "XpBar"
	_xp_bar.custom_minimum_size = Vector2(0, 20)
	head.add_child(_xp_bar)
	# Attributes.
	var attrs := HBoxContainer.new()
	attrs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attrs.add_theme_constant_override("separation", 8)
	body.add_child(attrs)
	for attr: String in ["strength", "dexterity", "intelligence"]:
		var b := AttrBox.new()
		b.name = "Attr_" + attr
		b.label = attr.capitalize()
		b.color = ATTR_COLORS[attr]
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		attrs.add_child(b)
		_attr_boxes[attr] = b
	# Pools + defence side by side.
	var cols := HBoxContainer.new()
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_theme_constant_override("separation", 14)
	body.add_child(cols)
	var left := _column(cols)
	left.add_child(InvStyle.section_header("Life & Mana"))
	_add_row(left, "life", "Life")
	_add_row(left, "mana", "Mana")
	_add_row(left, "es", "Energy Shield")
	var right := _column(cols)
	right.add_child(InvStyle.section_header("Defence"))
	_add_row(right, "armour", "Armour")
	_add_row(right, "evasion", "Evasion")
	_add_row(right, "block", "Block")
	# Resistances.
	body.add_child(InvStyle.section_header("Resistances"))
	var res := HBoxContainer.new()
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res.add_theme_constant_override("separation", 6)
	body.add_child(res)
	for t: String in RESIST_ORDER:
		var chip := ResistChip.new()
		chip.name = "Resist_" + t
		chip.type = t
		chip.label = "Physical" if t == "physical" else t.capitalize()
		chip.custom_minimum_size = Vector2(0, 50)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		res.add_child(chip)
		_resist_chips[t] = chip
	_penalty_label = UIStyle.make_label("", 13, UIStyle.COLOR_TEXT_DIM)
	_penalty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_penalty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_penalty_label)
	# Offence.
	body.add_child(InvStyle.section_header("Offence"))
	_skill_box = VBoxContainer.new()
	_skill_box.name = "Skills"
	_skill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_box.add_theme_constant_override("separation", 3)
	body.add_child(_skill_box)
	# Other.
	body.add_child(InvStyle.section_header("Other"))
	_other_grid = GridContainer.new()
	_other_grid.columns = 2
	_other_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_other_grid.add_theme_constant_override("h_separation", 14)
	_other_grid.add_theme_constant_override("v_separation", 0)
	body.add_child(_other_grid)
	for pair: Array in [["move_speed", "Movement"], ["crit_multi", "Crit Multiplier"], ["rarity", "Item Rarity"], ["quantity", "Item Quantity"], ["gold", "Gold Found"], ["leech", "Life Leech"]]:
		var r := _add_row(_other_grid, pair[0], pair[1])
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.compact = true
	_keystone_label = UIStyle.make_label("", 14, UIStyle.COLOR_TITLE.darkened(0.1))
	_keystone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keystone_label.visible = false
	body.add_child(_keystone_label)
	_assign_frame(_frame)


func _assign_frame(n: Node) -> void:
	for ch in n.get_children():
		if ch is TipControl:
			(ch as TipControl).frame = _frame
		_assign_frame(ch)


func _column(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	parent.add_child(v)
	return v


func _add_row(parent: Control, key: String, label: String) -> StatRow:
	var r := StatRow.new()
	r.name = "Row_" + key
	r.key = label
	parent.add_child(r)
	_rows[key] = r
	return r


# ------------------------------------------------------------------ widgets

## Base for the sheet's hover-able widgets: shows `tip` (tooltip lines) while hovered.
class TipControl:
	extends Control
	var tip: Array = []
	## The panel frame: tooltips open beside it (InvStyle.frame_anchor) instead of over the sheet.
	var frame: Control = null
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER:
				_hover = true
				queue_redraw()
				if not tip.is_empty() and is_inside_tree():
					UI.show_tooltip(tip, InvStyle.frame_anchor(frame, self))
			NOTIFICATION_MOUSE_EXIT:
				_hover = false
				queue_redraw()
				UI.hide_tooltip()

	func is_hovered() -> bool:
		return _hover

	func _hover_bg() -> void:
		if _hover:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.5, 0.05))


## "Key ........ value" with an optional small line under it.
class StatRow:
	extends TipControl
	var key := ""
	var value := ""
	var value_color := UIStyle.COLOR_TEXT
	var sub := "":
		set(v):
			sub = v
			update_minimum_size()
	## Compact rows (the "Other" grid) never show the sub line under the key.
	var compact := false

	func _get_minimum_size() -> Vector2:
		return Vector2(120, 24 if (compact or sub == "") else 40)

	func _draw() -> void:
		_hover_bg()
		var font := get_theme_default_font()
		var fs := 15
		var base := 17.0
		draw_string(font, Vector2(2, base), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.COLOR_TEXT_DIM)
		var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(size.x - vw - 2.0, base), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, value_color)
		if compact and sub != "":
			var kw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(kw + 8.0, base), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIStyle.COLOR_TEXT_DIM.darkened(0.1))
		elif sub != "":
			draw_string(font, Vector2(2, base + 17.0), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - 4.0, 13, Color(0.66, 0.62, 0.55))
		# Dotted leader between key and value.
		var y := base + 3.0
		draw_line(Vector2(2, y + 1.0), Vector2(size.x - 2.0, y + 1.0), Color(1, 1, 1, 0.04), 1.0)


## One attribute: coloured name + big number.
class AttrBox:
	extends TipControl
	var label := ""
	var value := "0"
	var color := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bg := Color(color.r, color.g, color.b, 0.10 if not _hover else 0.18)
		draw_rect(r, Color(0.045, 0.04, 0.036, 0.9))
		draw_rect(r, bg)
		draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, 2)), Color(color.r, color.g, color.b, 0.8))
		draw_rect(r, Color(color.r, color.g, color.b, 0.35), false, 1.0)
		var font := get_theme_default_font()
		var tf := InvStyle.title_font()
		var vs := 24
		var vw := tf.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x
		draw_string(tf, Vector2((size.x - vw) * 0.5, 28), value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs, UIStyle.COLOR_TEXT.lerp(Color.WHITE, 0.3))
		var t := label.to_upper()
		var ls := 12
		var lw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
		draw_string(font, Vector2((size.x - lw) * 0.5, 46), t, HORIZONTAL_ALIGNMENT_LEFT, -1, ls, color.lerp(UIStyle.COLOR_TEXT, 0.25))


## One resistance: coloured orb, value and name.
class ResistChip:
	extends TipControl
	var type := "fire"
	var label := ""
	var value := 0.0
	var capped := false

	func _draw() -> void:
		var col := UIStyle.damage_color(type)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.045, 0.04, 0.036, 0.9))
		if _hover:
			draw_rect(r, Color(col.r, col.g, col.b, 0.1))
		draw_rect(r, Color(col.r, col.g, col.b, 0.3), false, 1.0)
		var font := get_theme_default_font()
		var c := Vector2(14, size.y * 0.5 - 6.0)
		draw_circle(c, 6.5, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4))
		draw_circle(c, 5.0, col)
		draw_circle(c + Vector2(-1.5, -1.5), 1.8, Color(1, 1, 1, 0.55))
		var txt := "%d%%" % roundi(value)
		var vc := UIStyle.COLOR_TEXT
		if value < 0.0:
			vc = UIStyle.COLOR_BAD
		elif type != "physical" and value >= StatDefs.RESIST_CAP:
			vc = UIStyle.COLOR_GOOD
		draw_string(font, Vector2(26, size.y * 0.5 - 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, vc)
		if capped:
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(font, Vector2(28 + tw, size.y * 0.5 - 1.0), "max", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIStyle.COLOR_GOOD.darkened(0.2))
		draw_string(font, Vector2(7, size.y - 9.0), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 10.0, 12, col.lerp(UIStyle.COLOR_TEXT_DIM, 0.35))


## One skill of the bar: icon, name + key, damage per type, speed / crit / cost and DPS.
class SkillRow:
	extends TipControl
	const HEIGHT := 46.0
	var skill_id := ""
	var icon: Texture2D = null
	var title := ""
	var key := ""
	var damage_parts: Array = []      # [{"text", "type"}]
	var detail := ""
	var dps := 0.0
	var problem := ""

	func _get_minimum_size() -> Vector2:
		return Vector2(200, HEIGHT)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bc := InvStyle.FRAME_BORDER
		draw_rect(r, Color(0.045, 0.04, 0.036, 0.9))
		if _hover:
			draw_rect(r, Color(1, 0.85, 0.5, 0.06))
		draw_rect(r, Color(bc.r, bc.g, bc.b, 0.3), false, 1.0)
		var font := get_theme_default_font()
		var isz := size.y - 10.0
		var ir := Rect2(Vector2(5, 5), Vector2(isz, isz))
		if icon != null:
			draw_texture_rect(icon, ir, false, Color(1, 1, 1, 0.45) if problem != "" else Color.WHITE)
		draw_rect(ir, Color(bc.r, bc.g, bc.b, 0.7), false, 1.0)
		var x := ir.end.x + 9.0
		var right := size.x - 10.0
		# Line 1: name + key chip.
		draw_string(font, Vector2(x, 19), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIStyle.COLOR_TITLE)
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if key != "":
			var kw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var kr := Rect2(Vector2(x + tw + 7.0, 6), Vector2(kw + 8.0, 15))
			draw_rect(kr, Color(0, 0, 0, 0.4))
			draw_rect(kr, Color(bc.r, bc.g, bc.b, 0.8), false, 1.0)
			draw_string(font, Vector2(kr.position.x + 4.0, kr.position.y + 11.5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIStyle.COLOR_TEXT)
		# DPS (right column).
		var dps_w := 0.0
		if dps > 0.0:
			var dtxt := StatDefs.fmt(snappedf(dps, 0.1)) if dps < 100.0 else InvStyle.format_int(roundi(dps))
			var tf := InvStyle.title_font()
			dps_w = tf.get_string_size(dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(tf, Vector2(right - dps_w, 23), dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.93, 0.78))
			var lw := font.get_string_size("DPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, Vector2(right - lw, 37), "DPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIStyle.COLOR_TEXT_DIM)
		# Line 2: damage per type, then speed / crit / cost.
		var limit := right - maxf(dps_w, 30.0) - 12.0
		var dx := x
		var y2 := 37.0
		if problem != "":
			draw_string(font, Vector2(dx, y2), problem, HORIZONTAL_ALIGNMENT_LEFT, limit - dx, 13, UIStyle.COLOR_BAD)
			return
		for i in damage_parts.size():
			var p: Dictionary = damage_parts[i]
			var t := String(p["text"])
			var col := UIStyle.damage_color(String(p["type"])) if String(p["type"]) != "" else UIStyle.COLOR_TEXT
			if i > 0:
				draw_string(font, Vector2(dx, y2), " + ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIStyle.COLOR_TEXT_DIM)
				dx += font.get_string_size(" + ", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(dx, y2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			dx += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if detail != "" and limit - dx > 40.0:
			var d := ("   ·   " if not damage_parts.is_empty() else "") + detail
			draw_string(font, Vector2(dx, y2), d, HORIZONTAL_ALIGNMENT_LEFT, limit - dx, 12, UIStyle.COLOR_TEXT_DIM)


## Experience progress bar with centred text.
class XpBar:
	extends TipControl
	var ratio := 0.0
	var text := ""

	func set_progress(r: float, t: String) -> void:
		ratio = clampf(r, 0.0, 1.0)
		text = t
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.025, 0.02, 0.95))
		var fill := Rect2(Vector2(1, 1), Vector2((size.x - 2.0) * ratio, size.y - 2.0))
		var c := UIStyle.COLOR_XP
		draw_rect(fill, Color(c.r * 0.55, c.g * 0.5, c.b * 0.3))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.45)), Color(c.r, c.g, c.b, 0.35))
		draw_rect(r, Color(InvStyle.FRAME_BORDER.r, InvStyle.FRAME_BORDER.g, InvStyle.FRAME_BORDER.b, 0.9), false, 1.0)
		var font := get_theme_default_font()
		var fs := 13
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2((size.x - tw) * 0.5, size.y * 0.5 + font.get_ascent(fs) * 0.5 - 1.0)
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.COLOR_TEXT)

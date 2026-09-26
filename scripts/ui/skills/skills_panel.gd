class_name SkillsPanel
extends Control
## Skill book: every player skill with unlock level, tags, weapon requirement, tooltip; assign to skill-bar slots.
## OWNER: UI tree/skills/menus module (wave 2). See docs/ARCHITECTURE.md §8.4, §16.
##
## A window on the left of the screen (the panel root stays MOUSE_FILTER_IGNORE; the frame, rows,
## slots and buttons STOP). Top: the current skill bar (six slots with key labels: drop a skill on
## a slot to assign it, drag between slots to swap, right-click to clear). Below: filter tabs
## (All / Melee / Bow & Crossbow / Spells) and the skills from SkillDB.get_player_skills(), grouped
## by category. Each row shows the icon, name, unlock level (locked skills are greyed with a
## padlock), tag chips, weapon requirement (red when the equipped weapon can't use it), cost and
## cooldown, and six slot buttons that assign it (CharacterData.set_skill_in_slot; clicking the gold
## button of an assigned slot clears it). Hover: SkillDB.get_tooltip_lines(id, player). Rows are drag
## sources with the payload {"type": "skill", "skill_id": id} for the HUD skill bar.
## The character is GameState.character, or context {"character": CharacterData}.
## Standalone: `var p := SkillsPanel.new(); add_child(p); p.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuFrame := preload("res://scripts/ui/menus/menu_frame.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")
const SkillRow := preload("res://scripts/ui/skills/skill_book_row.gd")
const SkillSlot := preload("res://scripts/ui/skills/skill_book_slot.gd")

const PANEL_NAME := "skills"
const FILTERS: Array[String] = ["all", "melee", "ranged", "spells"]
const FILTER_NAMES := {"all": "All", "melee": "Melee", "ranged": "Bow & Crossbow", "spells": "Spells"}
const CATEGORY_ORDER: Array[String] = ["general", "melee", "ranged", "spells"]
const CATEGORY_NAMES := {"general": "Basic", "melee": "Melee", "ranged": "Bow & Crossbow", "spells": "Spells"}
const CATEGORY_COLORS := {
	"general": Color(0.85, 0.8, 0.7), "melee": Color(0.95, 0.45, 0.32), "ranged": Color(0.5, 0.85, 0.42),
	"spells": Color(0.55, 0.62, 1.0),
}
const RANGED_TYPES: Array[String] = ["bow", "crossbow"]

## Remembered between openings.
static var current_filter: String = "all"

var close_button: Button
var filter_buttons: Dictionary = {}    # filter -> Button
var bar_slots: Array = []              # SkillSlot per bar slot

var _built := false
var _context_character: CharacterData = null
var _frame: Control
var _subtitle: Label
var _count_label: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _rows: Dictionary = {}             # skill id -> row
var _sections: Dictionary = {}         # category -> header control
var _empty_label: Label               # only while the list is empty (a child of _list)
var _skills: Array = []
var _filter_group := ButtonGroup.new()
var _tooltip_owner := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuStyle.get_theme()


func _ready() -> void:
	_ensure_built()
	Events.skill_bar_changed.connect(_on_changed)
	Events.level_up.connect(func(_l: int) -> void: _on_changed())
	Events.equipment_changed.connect(func(_s: String) -> void: _on_changed())
	Events.player_spawned.connect(func(_p: Node) -> void: _on_changed())


## Called by UIRoot after the panel becomes visible.
func on_opened(context: Dictionary) -> void:
	_ensure_built()
	var c: Variant = context.get("character")
	_context_character = c as CharacterData if c is CharacterData else null
	_rebuild_rows()
	set_filter(current_filter)
	refresh()
	_scroll.scroll_vertical = 0


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	_hide_tooltip()


# ------------------------------------------------------------------ public API

func get_character() -> CharacterData:
	if _context_character != null:
		return _context_character
	return GameState.character


## The live player (for tooltips with real numbers), or null.
func get_actor() -> Actor:
	var p: Variant = GameState.player
	if p != null and is_instance_valid(p) and (p as Actor) != null:
		var pl := p as Player
		if pl != null and pl.character == get_character():
			return pl
	return null


## Weapon type of the equipped main hand ("unarmed" without one).
func get_weapon_type() -> String:
	var a := get_actor()
	if a != null:
		return String(a.get_weapon().get("weapon_type", "unarmed"))
	var c := get_character()
	if c != null:
		var it := c.get_equipped("main_hand")
		if it != null and it.is_weapon():
			return String(it.get_weapon_stats().get("weapon_type", "unarmed"))
	return "unarmed"


## Rows by skill id (row: skill_id, locked, slot_buttons...).
func get_rows() -> Dictionary:
	return _rows


## Skill ids currently listed under the active filter.
func get_visible_skill_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _rows:
		if (_rows[id] as Control).visible:
			out.append(id)
	return out


## Filter: "all", "melee", "ranged", "spells".
func set_filter(filter: String) -> void:
	if not FILTERS.has(filter):
		filter = "all"
	current_filter = filter
	for f: String in filter_buttons:
		(filter_buttons[f] as Button).set_pressed_no_signal(f == filter)
	for id: String in _rows:
		var cat := skill_category(_skill_by_id(id))
		(_rows[id] as Control).visible = filter == "all" or cat == filter or cat == "general"
	for cat: String in _sections:
		var any := false
		for id: String in _rows:
			if (_rows[id] as Control).visible and skill_category(_skill_by_id(id)) == cat:
				any = true
				break
		(_sections[cat] as Control).visible = any


func get_filter() -> String:
	return current_filter


## Put a skill in a bar slot (0..5). Refuses unknown and locked skills (with a notification).
func assign_skill(skill_id: String, slot: int) -> bool:
	var c := get_character()
	if c == null or slot < 0 or slot >= CharacterData.SKILL_BAR_SIZE:
		return false
	var s := _skill_by_id(skill_id)
	if s.is_empty():
		return false
	if c.level < int(s.get("unlock_level", 1)):
		Events.notify.emit("%s unlocks at level %d" % [String(s.get("name", skill_id)), int(s["unlock_level"])], UIStyle.COLOR_BAD)
		return false
	c.set_skill_in_slot(slot, skill_id)
	refresh()
	return true


func clear_slot(slot: int) -> void:
	var c := get_character()
	if c == null or slot < 0 or slot >= CharacterData.SKILL_BAR_SIZE:
		return
	c.set_skill_in_slot(slot, "")
	refresh()


## Refresh every row and the bar from the character.
func refresh() -> void:
	if not _built:
		return
	var c := get_character()
	var level := c.level if c != null else 1
	var bar: Array = c.skill_bar.duplicate() if c != null else ["", "", "", "", "", ""]
	var wt := get_weapon_type()
	var actor := get_actor()
	var unlocked := 0
	for id: String in _rows:
		var row: Control = _rows[id]
		row.call("refresh", level, wt, bar, actor)
		if not bool(row.get("locked")):
			unlocked += 1
	for i in bar_slots.size():
		(bar_slots[i] as Control).call("set_skill", String(bar[i]) if i < bar.size() else "")
	_count_label.text = "%d / %d unlocked" % [unlocked, _rows.size()] if not _rows.is_empty() else ""
	if c == null:
		_subtitle.text = "No character"
	else:
		var weapon_name := String(WEAPON_DISPLAY_NAMES.get(wt, wt.capitalize()))
		_subtitle.text = "%s  ·  Level %d %s  ·  Wielding: %s" % [c.char_name, c.level, ClassDefs.get_display_name(c.class_id), weapon_name]


## Skill category: "general" (basic attack), "melee", "ranged" (bow/crossbow), "spells".
static func skill_category(s: Dictionary) -> String:
	var tags: Array = s.get("tags", [])
	var types: Array = s.get("weapon_types", [])
	if tags.has("spell"):
		return "spells"
	for t in types:
		if RANGED_TYPES.has(String(t)):
			return "ranged"
	if types.is_empty() and not tags.has("melee") and not tags.has("warcry"):
		return "general"
	return "melee"


const WEAPON_DISPLAY_NAMES := {
	"melee": "Melee Weapon", "sword": "Sword", "axe": "Axe", "mace": "Mace", "dagger": "Dagger",
	"wand": "Wand", "staff": "Staff", "bow": "Bow", "crossbow": "Crossbow", "unarmed": "Nothing",
}


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BORDER, 20)
	frame.set("accent", Color(MenuStyle.GOLD, 0.7))
	frame.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	frame.offset_left = 40
	frame.offset_right = 40 + 860
	frame.offset_top = 70
	frame.offset_bottom = -190
	add_child(frame)
	_frame = frame
	var v := MenuStyle.vbox(10)
	frame.add_child(v)
	# Title.
	var head := MenuStyle.hbox(10)
	var tv := MenuStyle.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(MenuStyle.title_label("SKILL BOOK", 32, UIStyle.COLOR_TITLE))
	_subtitle = MenuStyle.label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM)
	tv.add_child(_subtitle)
	head.add_child(tv)
	close_button = MenuStyle.make_button("Close", UIStyle.FONT_NORMAL)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	# Skill bar.
	var bar_frame := PanelContainer.new()
	bar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	bsb.set_corner_radius_all(6)
	bsb.set_border_width_all(1)
	bsb.border_color = Color(UIStyle.COLOR_BORDER, 0.5)
	bsb.set_content_margin_all(10)
	bar_frame.add_theme_stylebox_override("panel", bsb)
	var bh := MenuStyle.hbox(6)
	bar_frame.add_child(bh)
	var bl := MenuStyle.vbox(2)
	bl.custom_minimum_size = Vector2(250, 0)
	bl.alignment = BoxContainer.ALIGNMENT_CENTER
	bl.add_child(MenuStyle.title_label("Skill Bar", 22, UIStyle.COLOR_TITLE))
	var bhint := MenuStyle.label("Click a key on a skill, or drag skills onto these slots or your hotbar. Right-click a slot to clear it.", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	bhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bhint.custom_minimum_size = Vector2(240, 0)
	bl.add_child(bhint)
	bh.add_child(bl)
	bh.add_child(MenuStyle.spacer())
	for i in CharacterData.SKILL_BAR_SIZE:
		var s: Control = SkillSlot.new(i)
		s.connect("dropped", func(slot: int, id: String) -> void:
			if assign_skill(id, slot):
				Sfx.play_ui("ui_click"))
		s.connect("clear_requested", func(slot: int) -> void:
			clear_slot(slot)
			_hide_tooltip())
		s.connect("hovered", _on_slot_hovered)
		s.connect("unhovered", func(_slot: int) -> void: _hide_tooltip())
		bh.add_child(s)
		bar_slots.append(s)
	v.add_child(bar_frame)
	# Filters.
	var fh := MenuStyle.hbox(6)
	for f in FILTERS:
		var b := MenuStyle.make_button(String(FILTER_NAMES[f]), UIStyle.FONT_NORMAL)
		b.toggle_mode = true
		b.button_group = _filter_group
		for st in ["pressed", "hover_pressed"]:
			var sb := MenuStyle.row_style("selected")
			sb.content_margin_left = 18
			sb.content_margin_right = 18
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_pressed_color", MenuStyle.GOLD_BRIGHT)
		var filter := f
		b.toggled.connect(func(on: bool) -> void:
			if on:
				set_filter(filter))
		fh.add_child(b)
		filter_buttons[f] = b
	fh.add_child(MenuStyle.spacer())
	_count_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(_count_label)
	v.add_child(fh)
	# List.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_scroll)
	_list = MenuStyle.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func _rebuild_rows() -> void:
	var skills := SkillDB.get_player_skills()
	var ids: Array[String] = []
	for s in skills:
		if s is Dictionary and not bool((s as Dictionary).get("monster_only", false)) and String((s as Dictionary).get("id", "")) != "":
			ids.append(String((s as Dictionary)["id"]))
	var have: Array[String] = []
	for id: String in _rows:
		have.append(id)
	if ids == have and _list.get_child_count() > 0:
		return
	_hide_tooltip()
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	_rows.clear()
	_sections.clear()
	_empty_label = null
	_skills = []
	for s in skills:
		if s is Dictionary and ids.has(String((s as Dictionary).get("id", ""))):
			_skills.append(s)
	if _skills.is_empty():
		# Created on demand as a child of the list, so it is freed with the other rows (never orphaned).
		_empty_label = MenuStyle.label("No skills known yet.", UIStyle.FONT_LARGE, UIStyle.COLOR_TEXT_DIM)
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_empty_label.custom_minimum_size = Vector2(0, 200)
		_list.add_child(_empty_label)
		return
	for cat in CATEGORY_ORDER:
		var in_cat: Array = _skills.filter(func(s: Dictionary) -> bool: return skill_category(s) == cat)
		if in_cat.is_empty():
			continue
		var header := _section_header(cat)
		_list.add_child(header)
		_sections[cat] = header
		for s: Dictionary in in_cat:
			var row: Control = SkillRow.new(s)
			row.connect("assign_requested", _on_row_assign)
			row.connect("hovered", _on_row_hovered)
			row.connect("unhovered", func(id: String) -> void:
				if _tooltip_owner == id:
					_hide_tooltip())
			_list.add_child(row)
			_rows[String(s["id"])] = row


func _section_header(cat: String) -> Control:
	var col: Color = CATEGORY_COLORS.get(cat, UIStyle.COLOR_TITLE)
	var h := MenuStyle.hbox(12)
	h.custom_minimum_size = Vector2(0, 34)
	var l := MenuStyle.title_label(String(CATEGORY_NAMES.get(cat, cat)).to_upper(), 18, col)
	l.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(l)
	var line := MenuCanvas.new(func(ci: Control) -> void:
		var y := ci.size.y - 9.0
		ci.draw_polyline_colors(PackedVector2Array([Vector2(0, y), Vector2(ci.size.x, y)]), PackedColorArray([Color(col, 0.7), Color(col, 0.0)]), 1.5, true), Vector2(0, 30))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(line)
	return h


func _skill_by_id(id: String) -> Dictionary:
	for s: Dictionary in _skills:
		if String(s.get("id", "")) == id:
			return s
	return SkillDB.get_skill(id)


# ------------------------------------------------------------------ events

func _on_row_assign(skill_id: String, slot: int) -> void:
	var c := get_character()
	if c == null:
		return
	if c.get_skill_in_slot(slot) == skill_id:
		clear_slot(slot)
	else:
		assign_skill(skill_id, slot)


func _on_row_hovered(skill_id: String, row: Control) -> void:
	_tooltip_owner = skill_id
	UI.show_tooltip(SkillDB.get_tooltip_lines(skill_id, get_actor()), row.get_global_rect())


func _on_slot_hovered(slot: int, ctrl: Control) -> void:
	var c := get_character()
	var id := c.get_skill_in_slot(slot) if c != null else ""
	if id == "":
		return
	_tooltip_owner = "slot:%d" % slot
	UI.show_tooltip(SkillDB.get_tooltip_lines(id, get_actor()), ctrl.get_global_rect())


## Show the tooltip of a listed skill as if its row were hovered (demos / tests).
## Scrolls the row into view first (a coroutine: the tooltip appears two frames later).
func preview_tooltip(skill_id: String) -> void:
	if not _rows.has(skill_id):
		return
	_scroll.ensure_control_visible(_rows[skill_id])
	await get_tree().process_frame
	await get_tree().process_frame
	if _rows.has(skill_id) and is_visible_in_tree():
		_on_row_hovered(skill_id, _rows[skill_id])


func _hide_tooltip() -> void:
	if _tooltip_owner != "":
		_tooltip_owner = ""
		UI.hide_tooltip()


func _on_changed() -> void:
	if is_visible_in_tree():
		refresh()


## Close the panel (through UIRoot when it manages it, else hide).
func close() -> void:
	if UI.is_panel_open(PANEL_NAME) and UI.get_panel(PANEL_NAME) == self:
		UI.close_panel(PANEL_NAME)
	else:
		visible = false
		on_closed()

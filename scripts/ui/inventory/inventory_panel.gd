class_name InventoryPanel
extends Control
## Inventory grid (10x6) + equipment paper doll + gold. Drag & drop, right-click to equip/unequip, Ctrl+click to sell while the vendor is open, shift+click to move to stash while the stash is open, tooltips with comparison.
## OWNER: UI items module (wave 2). CONTRACT STUB — keep every public member/signature.
## See docs/ARCHITECTURE.md §16.
##
## Docked on the right edge of the screen. All item changes go through InvActions ->
## CharacterData mutators; the panel refreshes itself on Events.inventory_changed,
## equipment_changed, gold_changed, stash_changed, player_stats_changed and level_up.
## Dragging an item out of the UI drops it on the ground at the player's feet.

const COLS := Balance.INVENTORY_COLUMNS
const ROWS := Balance.INVENTORY_ROWS
const CELL := 50.0
const GAP := 2.0
## Paper doll unit (px) and slot rects in units (x, y, w, h), laid out on a 10 x 6.9 unit board.
const DOLL_UNIT := 50.0
const DOLL_LAYOUT := {
	"main_hand": Rect2(0.5, 0.6, 2, 4),
	"off_hand": Rect2(7.5, 0.6, 2, 4),
	"helmet": Rect2(4, 0, 2, 2),
	"amulet": Rect2(6.25, 1.0, 1, 1),
	"body": Rect2(4, 2.2, 2, 3),
	"ring_1": Rect2(2.75, 3.2, 1, 1),
	"ring_2": Rect2(6.25, 3.2, 1, 1),
	"gloves": Rect2(0.5, 4.9, 2, 2),
	"boots": Rect2(7.5, 4.9, 2, 2),
	"belt": Rect2(4, 5.4, 2, 1),
}
## Silhouette icon per empty slot.
const PLACEHOLDER_ICONS := {
	"main_hand": "weapon_sword", "off_hand": "offhand_shield", "helmet": "armor_helmet_str",
	"amulet": "jewel_amulet", "body": "armor_body", "ring_1": "jewel_ring", "ring_2": "jewel_ring",
	"gloves": "armor_gloves", "boots": "armor_boots", "belt": "jewel_belt",
}
const PANEL_ID := "inventory"

var _built := false
var _frame: PanelContainer = null
var _grid_slots: Array[InvSlot] = []
var _equip_slots: Dictionary = {}          # slot id -> InvSlot
var _gold_label: Label = null
var _count_label: Label = null
var _hint_label: Label = null
var _name_label: Label = null
var _refresh_queued := false
var _known_uids: Dictionary = {}           # uid -> true (items seen at the last refresh)
var _has_refreshed := false
var _context_state := -1                   # vendor open (1) + stash open (2), for the hint


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	Events.inventory_changed.connect(_queue_refresh)
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.gold_changed.connect(_on_gold_changed)
	Events.stash_changed.connect(_queue_refresh)
	Events.player_stats_changed.connect(_queue_refresh)
	Events.level_up.connect(_on_level_up)
	Events.panel_open_requested.connect(_on_panel_event)
	Events.panel_close_requested.connect(_on_panel_close_event)
	visibility_changed.connect(_on_visibility_changed)


## Called by UIRoot after the panel becomes visible.
func on_opened(_context: Dictionary) -> void:
	_build()
	refresh()


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	UI.hide_tooltip()


## The frame (for layout by other panels / tests).
func get_frame() -> Control:
	return _frame


## The grid cell for an inventory index.
func get_grid_slot(index: int) -> InvSlot:
	_build()
	return _grid_slots[index] if index >= 0 and index < _grid_slots.size() else null


## The paper-doll slot for an equipment slot id.
func get_equip_slot(slot: String) -> InvSlot:
	_build()
	return _equip_slots.get(slot, null)


## Rebuild every cell from GameState.character.
func refresh() -> void:
	_build()
	_refresh_queued = false
	var c := GameState.character
	var attrs := InvActions.get_attributes() if c != null else {}
	var seen := {}
	for i in _grid_slots.size():
		var s: InvSlot = _grid_slots[i]
		var it: Item = null
		if c != null and i < c.inventory.size():
			it = c.inventory[i]
		_set_slot_item(s, it, attrs)
		if it != null:
			seen[it.uid] = true
			if _has_refreshed and not _known_uids.has(it.uid) and is_visible_in_tree():
				s.flash()
	for slot: String in _equip_slots:
		var s: InvSlot = _equip_slots[slot]
		var it: Item = c.get_equipped(slot) if c != null else null
		_set_slot_item(s, it, attrs)
		if it != null:
			seen[it.uid] = true
	# A two-handed melee weapon / staff also fills the off-hand slot (shown faded).
	var off: InvSlot = _equip_slots.get("off_hand")
	var main: Item = c.get_equipped("main_hand") if c != null else null
	var blocks := off != null and off.item == null and main != null and main.is_two_handed() and not CharacterData.RANGED_WEAPON_TYPES.has(main.get_weapon_type())
	if off != null:
		off.ghost_texture = Assets.item_icon(main.get_model_id()) if blocks else null
		off.empty_note = "Used by your two-handed weapon" if blocks else "Empty"
	if c != null:
		for it: Variant in c.stash:
			if it != null:
				seen[(it as Item).uid] = true
	_known_uids = seen
	_has_refreshed = c != null
	if _gold_label != null:
		_gold_label.text = InvStyle.format_int(c.gold if c != null else 0)
	if _count_label != null:
		var used := 0
		if c != null:
			used = c.inventory.size() - c.inventory_free_count()
		_count_label.text = "%d / %d" % [used, COLS * ROWS]
		_count_label.add_theme_color_override("font_color", UIStyle.COLOR_BAD if used >= COLS * ROWS else UIStyle.COLOR_TEXT_DIM)
	if _name_label != null:
		_name_label.text = ("%s  ·  Level %d %s" % [c.char_name, c.level, ClassDefs.get_display_name(c.class_id)]) if c != null else ""
	_update_hint()


func _set_slot_item(s: InvSlot, it: Item, attrs: Dictionary) -> void:
	var changed := s.item != it
	s.item = it
	s.unmet = it != null and not attrs.is_empty() and not it.meets_requirements(attrs)
	if changed:
		s.refresh_tooltip()
	else:
		s.queue_redraw()


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


func _on_equipment_changed(_slot: String) -> void:
	_queue_refresh()


func _on_gold_changed(_gold: int) -> void:
	_queue_refresh()


func _on_level_up(_level: int) -> void:
	_queue_refresh()


func _on_panel_event(_panel: String, _ctx: Dictionary) -> void:
	_update_hint.call_deferred()


func _on_panel_close_event(_panel: String) -> void:
	_update_hint.call_deferred()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_queue_refresh()


func _process(_delta: float) -> void:
	# Keeps the context hint and hovered tooltip current when the vendor / stash opens or closes.
	if not is_visible_in_tree():
		return
	if _context() != _context_state:
		_update_hint()
		for s: InvSlot in _grid_slots:
			if s.is_hovered():
				s.refresh_tooltip()
		for s: InvSlot in _equip_slots.values():
			if s.is_hovered():
				s.refresh_tooltip()


## 1 when the vendor is open, + 2 when the stash is open.
func _context() -> int:
	return (1 if InvActions.is_vendor_open() else 0) + (2 if InvActions.is_stash_open() else 0)


func _update_hint() -> void:
	_context_state = _context()
	if _hint_label == null:
		return
	var parts: PackedStringArray = ["Right-click: equip / unequip"]
	if InvActions.is_vendor_open():
		parts.append("Ctrl+Click: sell")
		parts.append("Shift+Click: craft")
	elif InvActions.is_stash_open():
		parts.append("Shift+Click: stash")
	else:
		parts.append("Drag outside to drop")
		parts.append("Hold Alt: affix tiers")
	var t := "   ·   ".join(parts)
	if _hint_label.text != t:
		_hint_label.text = t


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
	var f := InvStyle.make_frame("Inventory", _request_close)
	_frame = f["frame"]
	_frame.name = "Frame"
	add_child(_frame)
	InvStyle.dock_right(_frame)
	var body: VBoxContainer = f["body"]
	_name_label = UIStyle.make_label("", 14, UIStyle.COLOR_TEXT_DIM)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_name_label)
	# Paper doll.
	var doll_box := InvStyle.inset(6)
	body.add_child(doll_box)
	var doll := InvDollBoard.new()
	doll.name = "PaperDoll"
	doll.custom_minimum_size = Vector2(COLS * (CELL + GAP) - GAP, 6.9 * DOLL_UNIT)
	doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doll_box.add_child(doll)
	var x0 := (doll.custom_minimum_size.x - 10.0 * DOLL_UNIT) * 0.5
	for slot: String in CharacterData.EQUIP_SLOTS:
		var r: Rect2 = DOLL_LAYOUT.get(slot, Rect2(0, 0, 1, 1))
		var s := InvSlot.new()
		s.name = "Equip_" + slot
		s.kind = "equipment"
		s.equip_slot = slot
		s.handler = self
		s.highlight_drops = true
		s.placeholder = Assets.item_icon(PLACEHOLDER_ICONS.get(slot, "jewel_ring"))
		s.empty_tooltip = String(CharacterData.SLOT_NAMES.get(slot, slot.capitalize()))
		s.position = Vector2(x0 + r.position.x * DOLL_UNIT, r.position.y * DOLL_UNIT)
		s.size = r.size * DOLL_UNIT - Vector2(2, 2)
		s.custom_minimum_size = s.size
		doll.add_child(s)
		_equip_slots[slot] = s
	doll.slots = _equip_slots
	# Grid.
	var grid_box := InvStyle.inset(6)
	body.add_child(grid_box)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP))
	grid_box.add_child(grid)
	for i in COLS * ROWS:
		var s := InvSlot.new()
		s.name = "Cell_%d" % i
		s.kind = "inventory"
		s.index = i
		s.handler = self
		s.custom_minimum_size = Vector2(CELL, CELL)
		grid.add_child(s)
		_grid_slots.append(s)
	# Footer: gold + used cells.
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(footer)
	var gr := InvStyle.gold_row(0, UIStyle.FONT_NORMAL, 22.0)
	_gold_label = gr[1]
	(gr[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gr[0])
	_count_label = UIStyle.make_label("0 / 60", 14, UIStyle.COLOR_TEXT_DIM)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_count_label)
	_hint_label = InvStyle.hint_label("")
	body.add_child(_hint_label)


# ------------------------------------------------------------------ slot handler

func slot_clicked(slot: InvSlot, button: int, ctrl: bool, shift: bool) -> void:
	var c := GameState.character
	if c == null or slot.item == null:
		return
	var payload := InvActions.make_payload(slot.item, slot.kind, slot.index, slot.equip_slot)
	if ctrl and button == MOUSE_BUTTON_LEFT:
		if InvActions.is_vendor_open() and InvActions.vendor_panel.has_method("request_sell"):
			InvActions.vendor_panel.call("request_sell", payload)
		return
	if shift and button == MOUSE_BUTTON_LEFT:
		if InvActions.is_stash_open():
			if slot.kind == "inventory":
				InvActions.inventory_to_stash(slot.index)
			else:
				InvActions.equipment_to_stash(slot.equip_slot)
		elif InvActions.is_vendor_open() and InvActions.vendor_panel.has_method("select_for_craft"):
			InvActions.vendor_panel.call("select_for_craft", slot.item)
		return
	if button == MOUSE_BUTTON_RIGHT:
		if slot.kind == "inventory":
			InvActions.equip_inventory_item(slot.index)
		elif slot.kind == "equipment":
			InvActions.unequip_slot(slot.equip_slot)
	# Show the result right away (the deferred refresh keeps everything else in sync).
	refresh()


func slot_can_drop(slot: InvSlot, data: Dictionary) -> bool:
	if String(data.get("from", "")) == "vendor":
		return slot.kind == "inventory" and InvActions.source_has(data)
	return InvActions.can_move(data, slot.kind, slot.index, slot.equip_slot)


func slot_drop(slot: InvSlot, data: Dictionary) -> void:
	if String(data.get("from", "")) == "vendor":
		InvActions.buy(data, slot.index)
	else:
		InvActions.move(data, slot.kind, slot.index, slot.equip_slot)
	refresh()


func slot_drop_state(slot: InvSlot, data: Dictionary) -> int:
	if slot.kind != "equipment" or String(data.get("from", "")) == "vendor":
		return 0
	return InvActions.equip_drop_state(data, slot.equip_slot)


func slot_dropped_outside(_slot: InvSlot, data: Dictionary) -> void:
	if InvActions.drop_to_ground(data):
		refresh()


func slot_tooltip_anchor(slot: InvSlot) -> Rect2:
	return InvStyle.frame_anchor(_frame, slot)


func slot_tooltip_extra(slot: InvSlot) -> Array:
	if slot.item == null:
		return []
	var out: Array = [InvStyle.separator()]
	if InvActions.is_vendor_open():
		var v := slot.item.get_sell_value()
		out.append({"text": "Sell value: %s gold" % InvStyle.format_int(v), "color": UIStyle.COLOR_GOLD, "size": "small",
			"parts": [{"text": "Sell value: ", "color": UIStyle.COLOR_TEXT_DIM}, {"text": "%s gold" % InvStyle.format_int(v), "color": UIStyle.COLOR_GOLD}]})
		out.append(InvStyle.line("Ctrl+Click to sell  ·  Shift+Click to craft", UIStyle.COLOR_TEXT_DIM))
	elif InvActions.is_stash_open():
		out.append(InvStyle.line("Shift+Click to move to the stash", UIStyle.COLOR_TEXT_DIM))
	if slot.kind == "equipment":
		out.append(InvStyle.line("Right-click to unequip", UIStyle.COLOR_TEXT_DIM))
	else:
		out.append(InvStyle.line("Right-click to equip", UIStyle.COLOR_TEXT_DIM))
	return out


# ------------------------------------------------------------------ paper doll board

## Background of the paper doll: a soft vignette and faint connecting lines between the slots.
class InvDollBoard:
	extends Control
	var slots: Dictionary = {}

	func _draw() -> void:
		var c := size * 0.5
		# Radial-ish glow behind the body slot.
		for i in 6:
			var rr := (1.0 - float(i) / 6.0)
			draw_circle(c + Vector2(0, 10), 150.0 * rr, Color(0.55, 0.42, 0.25, 0.018))
		var line_c := Color(0.52, 0.41, 0.24, 0.22)
		for pair: Array in [["helmet", "body"], ["body", "belt"], ["ring_1", "body"], ["body", "ring_2"], ["helmet", "amulet"]]:
			var a: Control = slots.get(pair[0])
			var b: Control = slots.get(pair[1])
			if a == null or b == null:
				continue
			draw_line(a.position + a.size * 0.5, b.position + b.size * 0.5, line_c, 1.0)

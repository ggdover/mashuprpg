class_name StashPanel
extends Control
## Stash grid (120 cells). Opened by the town stash chest together with the inventory.
## OWNER: UI items module (wave 2). CONTRACT STUB — keep every public member/signature.
## See docs/ARCHITECTURE.md §16.
##
## Docked on the left edge (the inventory docks on the right). 12 x 10 cells. Drag & drop between
## stash cells, the inventory and the paper doll (swaps when the target is occupied); Shift+click
## or right-click a stash item to move it into the inventory (Shift+click in the inventory moves
## the other way while this panel is open); "Sort" orders the stash by slot, rarity and level;
## "Deposit All" moves the whole inventory in. Every change goes through CharacterData mutators
## (InvActions); the panel refreshes on Events.stash_changed / inventory_changed.

const COLS := 12
const ROWS := 10
const CELL := 50.0
const GAP := 2.0
const PANEL_ID := "stash"

var _built := false
var _frame: PanelContainer = null
var _slots: Array[InvSlot] = []
var _count_label: Label = null
var _gold_label: Label = null
var _refresh_queued := false
var _known_uids: Dictionary = {}
var _has_refreshed := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	Events.stash_changed.connect(_queue_refresh)
	Events.inventory_changed.connect(_queue_refresh)
	Events.gold_changed.connect(_on_gold_changed)
	Events.player_stats_changed.connect(_queue_refresh)
	visibility_changed.connect(_on_visibility_changed)


## Called by UIRoot after the panel becomes visible.
func on_opened(_context: Dictionary) -> void:
	_build()
	InvActions.stash_panel = self
	refresh()


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	if InvActions.stash_panel == self:
		InvActions.stash_panel = null
	UI.hide_tooltip()


func _exit_tree() -> void:
	if InvActions.stash_panel == self:
		InvActions.stash_panel = null


func get_frame() -> Control:
	return _frame


## The cell for a stash index.
func get_slot(index: int) -> InvSlot:
	_build()
	return _slots[index] if index >= 0 and index < _slots.size() else null


func get_slot_count() -> int:
	_build()
	return _slots.size()


## Rebuild every cell from GameState.character.stash.
func refresh() -> void:
	_build()
	_refresh_queued = false
	var c := GameState.character
	var attrs := InvActions.get_attributes() if c != null else {}
	var seen := {}
	for i in _slots.size():
		var s: InvSlot = _slots[i]
		var it: Item = null
		if c != null and i < c.stash.size():
			it = c.stash[i]
		var changed := s.item != it
		s.item = it
		s.unmet = it != null and not attrs.is_empty() and not it.meets_requirements(attrs)
		if changed:
			s.refresh_tooltip()
		if it != null:
			seen[it.uid] = true
			if _has_refreshed and not _known_uids.has(it.uid) and is_visible_in_tree():
				s.flash()
	_known_uids = seen
	_has_refreshed = c != null
	var used := seen.size()
	if _count_label != null:
		_count_label.text = "%d / %d" % [used, COLS * ROWS]
		_count_label.add_theme_color_override("font_color", UIStyle.COLOR_BAD if used >= COLS * ROWS else UIStyle.COLOR_TEXT_DIM)
	if _gold_label != null:
		_gold_label.text = InvStyle.format_int(c.gold if c != null else 0)


## Sort the stash: weapons first (slot order), then rarity (unique first), item level, name.
func sort_stash() -> void:
	var c := GameState.character
	if c == null:
		return
	var items: Array = []
	for it: Variant in c.stash:
		if it != null:
			items.append(it)
	items.sort_custom(_sort_less)
	var n := c.stash.size()
	var changed := false
	for i in n:
		var want: Item = items[i] if i < items.size() else null
		if c.stash[i] != want:
			changed = true
			break
	if not changed:
		return
	for i in n:
		var want: Item = items[i] if i < items.size() else null
		if c.stash[i] != want:
			c.put_in_stash(i, want)
	Sfx.play_ui("ui_click")


## Move every inventory item into the stash (until it is full). Returns how many moved.
func deposit_all() -> int:
	var c := GameState.character
	if c == null:
		return 0
	var moved := 0
	for i in c.inventory.size():
		if c.inventory[i] == null:
			continue
		if c.first_free_stash_index() < 0:
			Events.notify.emit("Stash full", UIStyle.COLOR_BAD)
			break
		c.add_to_stash(c.take_from_inventory(i))
		moved += 1
	if moved > 0:
		Sfx.play_ui("ui_click")
	return moved


static func _sort_less(a: Item, b: Item) -> bool:
	var sa := Item.SLOT_TYPES.find(a.get_slot_type())
	var sb := Item.SLOT_TYPES.find(b.get_slot_type())
	if sa != sb:
		return sa < sb
	if a.rarity != b.rarity:
		return a.rarity > b.rarity
	if a.get_item_class() != b.get_item_class():
		return a.get_item_class() < b.get_item_class()
	if a.item_level != b.item_level:
		return a.item_level > b.item_level
	return a.get_display_name() < b.get_display_name()


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


func _on_gold_changed(_g: int) -> void:
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
	var f := InvStyle.make_frame("Stash", _request_close)
	_frame = f["frame"]
	_frame.name = "Frame"
	add_child(_frame)
	InvStyle.dock_left(_frame)
	var body: VBoxContainer = f["body"]
	var sub := UIStyle.make_label("Items kept here are safe between your delves.", 14, UIStyle.COLOR_TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)
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
		s.kind = "stash"
		s.index = i
		s.handler = self
		s.custom_minimum_size = Vector2(CELL, CELL)
		grid.add_child(s)
		_slots.append(s)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override("separation", 10)
	body.add_child(footer)
	var sort := InvStyle.make_action_button("Sort")
	sort.name = "SortButton"
	sort.pressed.connect(sort_stash)
	footer.add_child(sort)
	var dep := InvStyle.make_action_button("Deposit All")
	dep.name = "DepositButton"
	dep.pressed.connect(func() -> void: deposit_all())
	footer.add_child(dep)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var gr := InvStyle.gold_row(0, UIStyle.FONT_NORMAL, 22.0)
	_gold_label = gr[1]
	footer.add_child(gr[0])
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(12, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(sep)
	_count_label = UIStyle.make_label("0 / %d" % (COLS * ROWS), 14, UIStyle.COLOR_TEXT_DIM)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_count_label)
	body.add_child(InvStyle.hint_label("Shift+Click or Right-click: to inventory   ·   Drag to move"))


# ------------------------------------------------------------------ slot handler

func slot_clicked(slot: InvSlot, button: int, _ctrl: bool, shift: bool) -> void:
	if slot.item == null:
		return
	if button == MOUSE_BUTTON_RIGHT or (shift and button == MOUSE_BUTTON_LEFT):
		InvActions.stash_to_inventory(slot.index)
	refresh()


func slot_can_drop(slot: InvSlot, data: Dictionary) -> bool:
	return InvActions.can_move(data, "stash", slot.index)


func slot_drop(slot: InvSlot, data: Dictionary) -> void:
	InvActions.move(data, "stash", slot.index)
	refresh()


func slot_dropped_outside(_slot: InvSlot, data: Dictionary) -> void:
	if InvActions.drop_to_ground(data):
		refresh()


func slot_tooltip_anchor(slot: InvSlot) -> Rect2:
	return InvStyle.frame_anchor(_frame, slot)


func slot_tooltip_extra(slot: InvSlot) -> Array:
	if slot.item == null:
		return []
	return [InvStyle.separator(), InvStyle.line("Shift+Click to move to the inventory", UIStyle.COLOR_TEXT_DIM)]

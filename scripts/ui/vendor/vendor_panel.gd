class_name VendorPanel
extends Control
## Vendor: buy items from GameState.vendor_stock, sell (drop or Ctrl+click from inventory), crafting services (reroll affixes, upgrade rarity).
## OWNER: UI items module (wave 2). CONTRACT STUB — keep every public member/signature.
## See docs/ARCHITECTURE.md §16.
##
## Docked on the left edge (the inventory opens on the right). Two tabs:
##   Trade  the stock grid with prices (right-click or drag into the inventory to buy; bought
##          items are removed from GameState.vendor_stock, which is never regenerated here), a
##          buyback row (items sold this town visit, at their sell value) and a sell zone (drop
##          an item on it or on the grids; Ctrl+click in the inventory). Rare and unique items ask
##          for confirmation before they are sold.
##   Craft  a bench slot (drag an owned item onto it, or Shift+click it in the inventory; the item
##          stays where it is), the two services with their ItemDB costs (Reroll Affixes, Upgrade
##          Rarity), what the result will be, and after a craft a Before / After comparison.
##          The preview sits in a scroll area sized to the room left on screen, so the frame never
##          grows past the bottom edge (rares with 6 affixes, uniques, Before / After pairs).
## The character's gold sits next to the tabs, so it is always visible.
## All gold and item changes go through CharacterData mutators (InvActions).

const PANEL_ID := "vendor"
const STOCK_COLS := 8
const STOCK_ROWS_MIN := 2
const STOCK_CELL := 64.0
const BUYBACK_CELL := 52.0
const GAP := 2.0
const CONTENT_WIDTH := 540.0
## Width of both tab pages (the buyback row plus its inset margins), so the frame never resizes.
const PAGE_WIDTH := 552.0
const BENCH_SIZE := 104.0
const MERCHANT_NAME := "Odric the Trader"
const GREETING := "\"Steel, leather and trinkets. Everything a delver needs.\""
## Rarity at or above which selling asks for confirmation.
const CONFIRM_RARITY := Item.Rarity.RARE
const SERVICE_REROLL := "reroll"
const SERVICE_UPGRADE := "upgrade"
## The crafting preview never shrinks below this height (it scrolls instead).
const PREVIEW_MIN_HEIGHT := 160.0
const PREVIEW_GAP := 8.0
const HINT_TRADE := "Right-click: buy   ·   Ctrl+Click inventory items: sell   ·   Shift+Click: craft"

var _built := false
var _frame: PanelContainer = null
var _tab_trade: Button = null
var _tab_craft: Button = null
var _page_trade: VBoxContainer = null
var _page_craft: VBoxContainer = null
var _stock_grid: GridContainer = null
var _stock_slots: Array[InvSlot] = []
var _stock_empty: Label = null
var _buyback_slots: Array[InvSlot] = []
var _sell_zone: Control = null
var _gold_label: Label = null
var _confirm: InvConfirm = null
var _refresh_queued := false
var _tab := "trade"

# Crafting bench.
var _bench_item: Item = null
var _bench_slot: InvSlot = null
var _bench_name: Label = null
var _bench_info: Label = null
var _services: Dictionary = {}          # service -> {"button", "cost", "note", "result"}
var _preview_scroll: InvPreviewScroll = null
var _preview_row: HBoxContainer = null
var _preview_before: TooltipBox = null
var _preview_after: TooltipBox = null
var _greeting: Label = null
var _craft_before: Item = null          # snapshot of the item before the last craft (display)
var _craft_after: Item = null           # the item that was crafted last
var _hint: Label = null
var _fitting := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	Events.inventory_changed.connect(_queue_refresh)
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.stash_changed.connect(_queue_refresh)
	Events.gold_changed.connect(_on_gold_changed)
	Events.player_stats_changed.connect(_queue_refresh)
	visibility_changed.connect(_on_visibility_changed)


## Called by UIRoot after the panel becomes visible. context {"tab": "craft"} opens the bench.
func on_opened(context: Dictionary) -> void:
	_build()
	InvActions.vendor_panel = self
	InvActions.sync_buyback()
	if String(context.get("tab", "")) in ["trade", "craft"]:
		set_tab(String(context["tab"]))
	refresh()


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	if InvActions.vendor_panel == self:
		InvActions.vendor_panel = null
	if _confirm != null:
		_confirm.cancel()
	UI.hide_tooltip()


func _exit_tree() -> void:
	if InvActions.vendor_panel == self:
		InvActions.vendor_panel = null


# ------------------------------------------------------------------ public API

func get_frame() -> Control:
	return _frame


## "trade" or "craft".
func get_tab() -> String:
	return _tab


func set_tab(tab: String) -> void:
	_build()
	_tab = "craft" if tab == "craft" else "trade"
	_page_trade.visible = _tab == "trade"
	_page_craft.visible = _tab == "craft"
	_tab_trade.set_pressed_no_signal(_tab == "trade")
	_tab_craft.set_pressed_no_signal(_tab == "craft")
	# The Craft tab shows its instructions on the bench itself; the room goes to the preview.
	_hint.text = HINT_TRADE
	_hint.visible = _tab == "trade"
	_greeting.visible = _tab == "trade"
	UI.hide_tooltip()
	_fit_preview()


## The stock cell for vendor_stock[index] (null past the grid).
func get_stock_slot(index: int) -> InvSlot:
	_build()
	return _stock_slots[index] if index >= 0 and index < _stock_slots.size() else null


func get_buyback_slot(index: int) -> InvSlot:
	_build()
	return _buyback_slots[index] if index >= 0 and index < _buyback_slots.size() else null


func get_bench_slot() -> InvSlot:
	_build()
	return _bench_slot


func get_sell_zone() -> Control:
	_build()
	return _sell_zone


func get_confirm() -> InvConfirm:
	_build()
	return _confirm


## The item on the crafting bench (an item the character owns), or null.
func get_bench_item() -> Item:
	return _bench_item


## The service button ("reroll" / "upgrade").
func get_service_button(service: String) -> Button:
	_build()
	return (_services.get(service, {}) as Dictionary).get("button", null)


## The scroll area holding the crafting preview (the bench item, or Before / After).
func get_preview_scroll() -> ScrollContainer:
	_build()
	return _preview_scroll


## Height of the area the panel lays out in: its own rect (full screen under UIRoot), else the
## viewport's visible rect.
func get_screen_height() -> float:
	if size.y > 1.0:
		return size.y
	return get_viewport_rect().size.y if is_inside_tree() else 1080.0


## Buy vendor_stock[index] into the first free inventory cell.
func buy_stock(index: int) -> Dictionary:
	if index < 0 or index >= GameState.vendor_stock.size():
		return {"ok": false, "reason": ""}
	var it: Item = GameState.vendor_stock[index]
	var r := InvActions.buy(_vendor_payload(it, index, false))
	refresh()
	return r


## Buy back InvActions.buyback[index].
func buy_back(index: int) -> Dictionary:
	if index < 0 or index >= InvActions.buyback.size():
		return {"ok": false, "reason": ""}
	var r := InvActions.buy(_vendor_payload(InvActions.buyback[index], index, true))
	refresh()
	return r


## Sell an owned item payload (inventory / equipment / stash). Rare and unique items open a
## confirmation first. Returns true if the item was sold right away.
func request_sell(payload: Dictionary) -> bool:
	if not InvActions.is_item_payload(payload) or not InvActions.OWN_SOURCES.has(String(payload.get("from", ""))):
		return false
	if not InvActions.source_has(payload):
		return false
	var it: Item = payload["item"]
	if it.rarity >= CONFIRM_RARITY:
		_build()
		var col := it.get_rarity_color().to_html(false)
		var text := "Sell [color=#%s]%s[/color] for [color=#%s]%s gold[/color]?" % [col, it.get_display_name(), UIStyle.COLOR_GOLD.to_html(false), InvStyle.format_int(it.get_sell_value())]
		if it.rarity == Item.Rarity.UNIQUE:
			text += "\n[color=#%s][font_size=14]Unique items are hard to find again.[/font_size][/color]" % UIStyle.COLOR_TEXT_DIM.to_html(false)
		_confirm.ask("Sell Item", text, "Sell", _do_sell.bind(payload))
		return false
	return _do_sell(payload)


## Put an owned item on the crafting bench (it stays where it is) and show the Craft tab.
func select_for_craft(item: Item) -> void:
	if item == null or InvActions.locate(item).is_empty():
		return
	_bench_item = item
	_craft_before = null
	_craft_after = null
	set_tab("craft")
	_preview_scroll.scroll_vertical = 0
	_refresh_bench()
	if _bench_slot != null:
		_bench_slot.flash()
	Sfx.play_ui("ui_click")


func clear_bench() -> void:
	_bench_item = null
	_craft_before = null
	_craft_after = null
	_refresh_bench()


## Run a crafting service ("reroll" / "upgrade") on the bench item. Pays the ItemDB cost.
func craft(service: String) -> Dictionary:
	var c := GameState.character
	var it := _bench_item
	if c == null or it == null or InvActions.locate(it).is_empty():
		return InvActions._no("Place an item on the bench first")
	var cost := _service_cost(service, it)
	if cost <= 0:
		return InvActions._no(_service_block_reason(service, it))
	if c.gold < cost:
		return InvActions._no("Not enough gold")
	var before := it.clone()
	before.uid = it.uid
	var ok := false
	if service == SERVICE_REROLL:
		ok = ItemDB.reroll_affixes(it)
	elif service == SERVICE_UPGRADE:
		ok = ItemDB.upgrade_rarity(it)
	if not ok:
		return InvActions._no("That doesn't work on this item")
	c.spend_gold(cost)
	InvActions.notify_item_changed(it)
	_craft_before = before
	_craft_after = it
	Sfx.play_ui("hit_block")
	Sfx.play_ui("pickup_gold")
	if _preview_scroll != null:
		_preview_scroll.scroll_vertical = 0
	_refresh_bench()
	if _bench_slot != null:
		_bench_slot.flash()
	return InvActions._ok()


## Rebuild the grids, buyback row, gold and bench from the game state.
func refresh() -> void:
	_build()
	_refresh_queued = false
	InvActions.sync_buyback()
	var c := GameState.character
	var gold := c.gold if c != null else 0
	var attrs := InvActions.get_attributes() if c != null else {}
	var stock: Array = GameState.vendor_stock
	var cells := maxi(STOCK_COLS * STOCK_ROWS_MIN, ceili(float(stock.size()) / STOCK_COLS) * STOCK_COLS)
	_ensure_stock_cells(cells)
	for i in _stock_slots.size():
		var s := _stock_slots[i]
		var it: Item = stock[i] if i < stock.size() else null
		_set_offer(s, it, it.get_buy_value() if it != null else -1, gold, attrs)
	_stock_empty.visible = stock.is_empty()
	for i in _buyback_slots.size():
		var s := _buyback_slots[i]
		var it: Item = InvActions.buyback[i] if i < InvActions.buyback.size() else null
		_set_offer(s, it, it.get_sell_value() if it != null else -1, gold, attrs)
	_gold_label.text = InvStyle.format_int(gold)
	_refresh_bench()


# ------------------------------------------------------------------ internals

func _set_offer(s: InvSlot, it: Item, price: int, gold: int, attrs: Dictionary) -> void:
	var changed := s.item != it
	s.item = it
	s.price = price if it != null else -1
	s.price_ok = price <= gold
	s.unmet = it != null and not attrs.is_empty() and not it.meets_requirements(attrs)
	if changed:
		s.refresh_tooltip()


func _vendor_payload(it: Item, index: int, is_buyback: bool) -> Dictionary:
	var p := InvActions.make_payload(it, "vendor", index)
	p["buyback"] = is_buyback
	p["price"] = it.get_sell_value() if is_buyback else it.get_buy_value()
	return p


func _do_sell(payload: Dictionary) -> bool:
	var it: Item = payload.get("item")
	var gold := InvActions.sell(payload)
	if gold <= 0:
		return false
	if it == _bench_item:
		clear_bench()
	Events.notify.emit("Sold %s for %s gold" % [it.get_display_name(), InvStyle.format_int(gold)], UIStyle.COLOR_GOLD)
	refresh()
	return true


func _service_cost(service: String, it: Item) -> int:
	if it == null:
		return 0
	if service == SERVICE_REROLL:
		return ItemDB.reroll_cost(it)
	return ItemDB.upgrade_cost(it)


func _service_block_reason(service: String, it: Item) -> String:
	if it == null:
		return "Place an item on the bench"
	if it.rarity == Item.Rarity.UNIQUE:
		return "Unique items can't be altered"
	if service == SERVICE_REROLL and it.rarity == Item.Rarity.NORMAL:
		return "Only Magic and Rare items have affixes to reroll"
	if service == SERVICE_UPGRADE and it.rarity == Item.Rarity.RARE:
		return "Already Rare: reroll it instead"
	return ""


## What the service will produce, for the preview line.
func _service_result_text(service: String, it: Item) -> String:
	if it == null:
		return ""
	match service:
		SERVICE_REROLL:
			if it.rarity == Item.Rarity.MAGIC:
				return "Result: Magic, 1-2 new random affixes"
			if it.rarity == Item.Rarity.RARE:
				return "Result: Rare with 3-6 new affixes and a new name"
		SERVICE_UPGRADE:
			if it.rarity == Item.Rarity.NORMAL:
				return "Result: Magic, gains 1-2 random affixes"
			if it.rarity == Item.Rarity.MAGIC:
				return "Result: Rare, keeps its %d affix%s, gains more (up to 6)" % [it.affixes.size(), "" if it.affixes.size() == 1 else "es"]
	return ""


func _refresh_bench() -> void:
	if not _built:
		return
	var c := GameState.character
	if _bench_item != null and InvActions.locate(_bench_item).is_empty():
		_bench_item = null
		_craft_before = null
		_craft_after = null
	var it := _bench_item
	var gold := c.gold if c != null else 0
	var changed := _bench_slot.item != it
	_bench_slot.item = it
	var attrs := InvActions.get_attributes() if c != null else {}
	_bench_slot.unmet = it != null and not attrs.is_empty() and not it.meets_requirements(attrs)
	if changed:
		_bench_slot.refresh_tooltip()
	else:
		_bench_slot.queue_redraw()
	if it == null:
		_bench_name.text = "Crafting Bench"
		_bench_name.add_theme_color_override("font_color", UIStyle.COLOR_TITLE)
		_bench_info.text = "Drag an item here, or Shift+Click one in your inventory."
	else:
		_bench_name.text = it.get_display_name()
		_bench_name.add_theme_color_override("font_color", it.get_rarity_color())
		var where := InvActions.locate(it)
		var loc := "in your inventory"
		match String(where.get("from", "")):
			"equipment":
				loc = "equipped (%s)" % String(CharacterData.SLOT_NAMES.get(String(where["slot"]), ""))
			"stash":
				loc = "in your stash"
		_bench_info.text = "%s %s · Item Level %d\nThe item stays %s." % [UIStyle.RARITY_NAMES[clampi(it.rarity, 0, 3)], it.get_item_class(), it.item_level, loc]
	for service: String in _services:
		var d: Dictionary = _services[service]
		var btn: Button = d["button"]
		var cost_l: Label = d["cost"]
		var note: Label = d["note"]
		var cost := _service_cost(service, it)
		btn.disabled = it == null or cost <= 0 or gold < cost
		(d["cost_row"] as Control).visible = cost > 0
		(d["na"] as Control).visible = cost <= 0
		if it == null:
			note.text = String(d["desc"])
			note.add_theme_color_override("font_color", UIStyle.COLOR_TEXT_DIM)
		elif cost <= 0:
			note.text = _service_block_reason(service, it)
			note.add_theme_color_override("font_color", UIStyle.COLOR_BAD.lerp(UIStyle.COLOR_TEXT_DIM, 0.35))
		else:
			cost_l.text = InvStyle.format_int(cost)
			cost_l.add_theme_color_override("font_color", UIStyle.COLOR_GOLD if gold >= cost else UIStyle.COLOR_BAD)
			note.text = _service_result_text(service, it) + ("" if gold >= cost else "   (not enough gold)")
			note.add_theme_color_override("font_color", UIStyle.COLOR_TEXT if gold >= cost else UIStyle.COLOR_BAD)
	_refresh_preview()


func _refresh_preview() -> void:
	var it := _bench_item
	if it == null:
		_preview_scroll.visible = false
		_preview_scroll.custom_minimum_size.y = 0.0
		return
	_preview_scroll.visible = true
	var attrs := InvActions.get_attributes()
	var inner := _preview_inner_width()
	if _craft_before != null and _craft_after == it:
		_preview_before.visible = true
		var half := floorf((inner - PREVIEW_GAP) * 0.5)
		_preview_before.max_width = half
		_preview_after.max_width = half
		_preview_before.dim = 0.5
		_preview_before.modulate.a = 0.85
		_preview_before.set_lines(_craft_before.get_tooltip_lines(attrs), "Before")
		_preview_after.set_lines(it.get_tooltip_lines(attrs), "After")
	else:
		_preview_before.visible = false
		_preview_after.max_width = inner
		_preview_after.set_lines(it.get_tooltip_lines(attrs), "")
	_preview_before.queue_redraw()
	_preview_after.queue_redraw()
	_fit_preview()


## Width available to the preview boxes: the page minus the scrollbar's reserved lane.
func _preview_inner_width() -> float:
	var bar := _preview_scroll.get_v_scroll_bar()
	return PAGE_WIDTH - (bar.get_combined_minimum_size().x if bar != null else 0.0) - 4.0


## Size the preview's scroll area so the frame ends above the bottom of the screen
## (InvStyle.SCREEN_MARGIN): the whole preview when it fits, else the room that is left (at least
## PREVIEW_MIN_HEIGHT) with a scrollbar. Called whenever the preview, the tab, the frame's
## minimum size (wrapping labels) or the screen size changes.
func _fit_preview() -> void:
	if not _built or _fitting or _preview_scroll == null:
		return
	if not _page_craft.visible or not _preview_scroll.visible:
		return
	_fitting = true
	var content := ceilf(_preview_row.get_combined_minimum_size().y)
	var others := _frame.get_combined_minimum_size().y - _preview_scroll.get_combined_minimum_size().y
	var top := _frame.anchor_top * get_screen_height() + _frame.offset_top
	var avail := floorf(get_screen_height() - InvStyle.SCREEN_MARGIN - top - others)
	var h := content if content <= avail else maxf(PREVIEW_MIN_HEIGHT, avail)
	if not is_equal_approx(_preview_scroll.custom_minimum_size.y, h):
		_preview_scroll.custom_minimum_size.y = h
	_fitting = false
	_preview_scroll.queue_fade_update()


func _on_frame_min_size_changed() -> void:
	_fit_preview()


func _ensure_stock_cells(n: int) -> void:
	while _stock_slots.size() < n:
		var s := InvSlot.new()
		s.name = "Stock_%d" % _stock_slots.size()
		s.kind = "vendor"
		s.index = _stock_slots.size()
		s.handler = self
		s.custom_minimum_size = Vector2(STOCK_CELL, STOCK_CELL + InvSlot.PRICE_HEIGHT)
		_stock_grid.add_child(s)
		_stock_slots.append(s)
	while _stock_slots.size() > n:
		var s: InvSlot = _stock_slots.pop_back()
		s.queue_free()


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
	var f := InvStyle.make_frame(MERCHANT_NAME, _request_close)
	_frame = f["frame"]
	_frame.name = "Frame"
	add_child(_frame)
	InvStyle.dock_left(_frame)
	var body: VBoxContainer = f["body"]
	# Merchant greeting (Trade tab only: the Craft tab needs the room for its preview).
	_greeting = UIStyle.make_label(GREETING, 14, UIStyle.COLOR_TEXT_DIM)
	_greeting.name = "Greeting"
	_greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_greeting)
	# Tabs (left) and the character's gold (right): always visible, whatever the page's height.
	var tabs := HBoxContainer.new()
	tabs.name = "TabRow"
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	_tab_trade = InvStyle.make_tab("Trade")
	_tab_trade.name = "TabTrade"
	_tab_trade.pressed.connect(func() -> void: set_tab("trade"))
	tabs.add_child(_tab_trade)
	_tab_craft = InvStyle.make_tab("Craft")
	_tab_craft.name = "TabCraft"
	_tab_craft.pressed.connect(func() -> void: set_tab("craft"))
	tabs.add_child(_tab_craft)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var gl := UIStyle.make_label("Your gold", 14, UIStyle.COLOR_TEXT_DIM)
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tabs.add_child(gl)
	var gr := InvStyle.gold_row(0, UIStyle.FONT_NORMAL, 22.0)
	gr[0].name = "Gold"
	_gold_label = gr[1]
	tabs.add_child(gr[0])
	_build_trade(body)
	_build_craft(body)
	_hint = InvStyle.hint_label(HINT_TRADE)
	_hint.name = "Hint"
	body.add_child(_hint)
	# Confirmation overlay (covers the whole screen while open).
	_confirm = InvConfirm.new()
	_confirm.name = "Confirm"
	add_child(_confirm)
	# Keep the crafting preview inside the screen when anything changes the frame's height
	# (wrapping labels, the preview itself) or the screen size.
	_frame.minimum_size_changed.connect(_on_frame_min_size_changed)
	resized.connect(_on_frame_min_size_changed)
	set_tab("trade")


func _build_trade(body: VBoxContainer) -> void:
	_page_trade = VBoxContainer.new()
	_page_trade.name = "TradePage"
	_page_trade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_trade.add_theme_constant_override("separation", 6)
	_page_trade.custom_minimum_size.x = PAGE_WIDTH
	body.add_child(_page_trade)
	_page_trade.add_child(InvStyle.section_header("For Sale"))
	var stock_box := InvStyle.inset(6)
	_page_trade.add_child(stock_box)
	_stock_grid = GridContainer.new()
	_stock_grid.name = "StockGrid"
	_stock_grid.columns = STOCK_COLS
	_stock_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stock_grid.add_theme_constant_override("h_separation", int(GAP))
	_stock_grid.add_theme_constant_override("v_separation", int(GAP) + 2)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_box.add_child(vb)
	vb.add_child(_stock_grid)
	_stock_empty = UIStyle.make_label("Sold out. Come back after your next delve.", 14, UIStyle.COLOR_TEXT_DIM)
	_stock_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stock_empty.visible = false
	vb.add_child(_stock_empty)
	_ensure_stock_cells(STOCK_COLS * STOCK_ROWS_MIN)
	_page_trade.add_child(InvStyle.section_header("Buyback"))
	var bb_box := InvStyle.inset(6)
	_page_trade.add_child(bb_box)
	var bb := GridContainer.new()
	bb.name = "BuybackGrid"
	bb.columns = InvActions.MAX_BUYBACK
	bb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bb.add_theme_constant_override("h_separation", int(GAP))
	bb_box.add_child(bb)
	for i in InvActions.MAX_BUYBACK:
		var s := InvSlot.new()
		s.name = "Buyback_%d" % i
		s.kind = "buyback"
		s.index = i
		s.handler = self
		s.custom_minimum_size = Vector2(BUYBACK_CELL, BUYBACK_CELL + InvSlot.PRICE_HEIGHT)
		bb.add_child(s)
		_buyback_slots.append(s)
	var zone := InvSellZone.new()
	zone.name = "SellZone"
	zone.panel = self
	zone.custom_minimum_size = Vector2(PAGE_WIDTH, 58)
	_page_trade.add_child(zone)
	_sell_zone = zone


func _build_craft(body: VBoxContainer) -> void:
	_page_craft = VBoxContainer.new()
	_page_craft.name = "CraftPage"
	_page_craft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_craft.add_theme_constant_override("separation", 8)
	_page_craft.custom_minimum_size.x = PAGE_WIDTH
	body.add_child(_page_craft)
	# The bench's big title reads "Crafting Bench" while it is empty (no section header: the
	# room goes to the preview).
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 12)
	_page_craft.add_child(top)
	_bench_slot = InvSlot.new()
	_bench_slot.name = "BenchSlot"
	_bench_slot.kind = "craft"
	_bench_slot.handler = self
	_bench_slot.draggable = false
	_bench_slot.highlight_drops = true
	_bench_slot.empty_tooltip = "Crafting Bench"
	_bench_slot.placeholder = Assets.item_icon("weapon_mace")
	_bench_slot.custom_minimum_size = Vector2(BENCH_SIZE, BENCH_SIZE)
	top.add_child(_bench_slot)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(info)
	_bench_name = UIStyle.make_label("Crafting Bench", UIStyle.FONT_LARGE, UIStyle.COLOR_TITLE)
	_bench_name.add_theme_font_override("font", InvStyle.title_font())
	_bench_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_bench_name)
	_bench_info = UIStyle.make_label("", 14, UIStyle.COLOR_TEXT_DIM)
	_bench_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_bench_info)
	var clear := InvStyle.make_action_button("Clear", false, 14)
	clear.name = "ClearBench"
	clear.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	clear.pressed.connect(clear_bench)
	info.add_child(clear)
	_add_service(SERVICE_REROLL, "Reroll Affixes", "Replaces every affix of a Magic or Rare item with new random ones.")
	_add_service(SERVICE_UPGRADE, "Upgrade Rarity", "Normal becomes Magic, Magic becomes Rare. Existing affixes are kept.")
	_preview_scroll = InvPreviewScroll.new()
	_preview_scroll.name = "PreviewScroll"
	_page_craft.add_child(_preview_scroll)
	_preview_row = HBoxContainer.new()
	_preview_row.name = "Preview"
	_preview_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_row.add_theme_constant_override("separation", int(PREVIEW_GAP))
	_preview_scroll.add_child(_preview_row)
	_preview_before = TooltipBox.new()
	_preview_before.name = "Before"
	_preview_before.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_row.add_child(_preview_before)
	_preview_after = TooltipBox.new()
	_preview_after.name = "After"
	_preview_after.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_row.add_child(_preview_after)


func _add_service(service: String, title: String, desc: String) -> void:
	var box := InvStyle.inset(8)
	_page_craft.add_child(box)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	box.add_child(hb)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var t := UIStyle.make_label(title, UIStyle.FONT_NORMAL, UIStyle.COLOR_TITLE)
	vb.add_child(t)
	var note := UIStyle.make_label(desc, 14, UIStyle.COLOR_TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 330
	vb.add_child(note)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(right)
	var gr := InvStyle.gold_row(0, UIStyle.FONT_NORMAL, 18.0)
	(gr[0] as HBoxContainer).alignment = BoxContainer.ALIGNMENT_END
	right.add_child(gr[0])
	var na := UIStyle.make_label("unavailable", 13, UIStyle.COLOR_TEXT_DIM)
	na.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(na)
	var btn := InvStyle.make_action_button(title.split(" ")[0], true)
	btn.name = "Service_" + service
	btn.custom_minimum_size.x = 110
	btn.pressed.connect(func() -> void: craft(service))
	right.add_child(btn)
	_services[service] = {"button": btn, "cost": gr[1], "cost_row": gr[0], "na": na, "note": note, "desc": desc}


# ------------------------------------------------------------------ slot handler

func slot_clicked(slot: InvSlot, button: int, ctrl: bool, _shift: bool) -> void:
	if slot.item == null:
		return
	match slot.kind:
		"vendor":
			if button == MOUSE_BUTTON_RIGHT or ctrl:
				buy_stock(slot.index)
		"buyback":
			if button == MOUSE_BUTTON_RIGHT or ctrl:
				buy_back(slot.index)
		"craft":
			if button == MOUSE_BUTTON_RIGHT:
				clear_bench()


func slot_drag_payload(slot: InvSlot) -> Dictionary:
	if slot.item == null:
		return {}
	match slot.kind:
		"vendor":
			return _vendor_payload(slot.item, slot.index, false)
		"buyback":
			return _vendor_payload(slot.item, slot.index, true)
	return {}


func slot_can_drop(slot: InvSlot, data: Dictionary) -> bool:
	var own := InvActions.OWN_SOURCES.has(String(data.get("from", ""))) and InvActions.source_has(data)
	if slot.kind == "craft":
		return own
	return own


func slot_drop(slot: InvSlot, data: Dictionary) -> void:
	if slot.kind == "craft":
		select_for_craft(data.get("item"))
		return
	request_sell(data)


func slot_drop_state(slot: InvSlot, data: Dictionary) -> int:
	if slot.kind != "craft" or not InvActions.OWN_SOURCES.has(String(data.get("from", ""))):
		return 0
	var it: Item = data.get("item")
	if it == null:
		return 0
	return 1 if ItemDB.reroll_cost(it) > 0 or ItemDB.upgrade_cost(it) > 0 else 2


func slot_tooltip_anchor(slot: InvSlot) -> Rect2:
	return InvStyle.frame_anchor(_frame, slot)


func slot_tooltip_extra(slot: InvSlot) -> Array:
	if slot.item == null:
		return []
	var c := GameState.character
	var gold := c.gold if c != null else 0
	var out: Array = [InvStyle.separator()]
	match slot.kind:
		"vendor", "buyback":
			var price := slot.item.get_sell_value() if slot.kind == "buyback" else slot.item.get_buy_value()
			var col := UIStyle.COLOR_GOLD if gold >= price else UIStyle.COLOR_BAD
			var label := "Buy back for: " if slot.kind == "buyback" else "Price: "
			out.append({"text": "%s%s gold" % [label, InvStyle.format_int(price)], "color": col, "size": "normal",
				"parts": [{"text": label, "color": UIStyle.COLOR_TEXT_DIM}, {"text": "%s gold" % InvStyle.format_int(price), "color": col}]})
			if gold < price:
				out.append(InvStyle.line("Not enough gold", UIStyle.COLOR_BAD))
			else:
				out.append(InvStyle.line("Right-click to buy  ·  Drag into your inventory", UIStyle.COLOR_TEXT_DIM))
		"craft":
			out.append(InvStyle.line("Right-click to take it off the bench", UIStyle.COLOR_TEXT_DIM))
	return out


## Drop target on the Trade page: dropping an owned item here sells it.
class InvSellZone:
	extends Control
	var panel: VendorPanel = null
	var _hot := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok := InvActions.is_item_payload(data) and InvActions.OWN_SOURCES.has(String((data as Dictionary).get("from", ""))) and InvActions.source_has(data)
		if ok != _hot:
			_hot = ok
			queue_redraw()
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_hot = false
		queue_redraw()
		if panel != null:
			panel.request_sell(data)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			if _hot:
				_hot = false
				queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var c := UIStyle.COLOR_GOLD if _hot else Color(InvStyle.FRAME_BORDER.r, InvStyle.FRAME_BORDER.g, InvStyle.FRAME_BORDER.b, 0.75)
		draw_rect(r, Color(0.2, 0.15, 0.05, 0.35) if _hot else Color(0, 0, 0, 0.25))
		# Dashed border.
		var dash := 8.0
		var gap := 5.0
		for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end], [r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 0.001)
			var t := 0.0
			while t < len:
				draw_line(a + dir * t, a + dir * minf(t + dash, len), c, 1.0)
				t += dash + gap
		var font := get_theme_default_font()
		var coin := Assets.item_icon("loot_gold")
		var text := "Drop items here to sell them"
		var fs := 16
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cs := 26.0
		var total := cs + 8.0 + tw
		var x := (size.x - total) * 0.5
		if coin != null:
			draw_texture_rect(coin, Rect2(Vector2(x, (size.y - cs) * 0.5), Vector2(cs, cs)), false)
		draw_string(font, Vector2(x + cs + 8.0, size.y * 0.5 + font.get_ascent(fs) * 0.5 - 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIStyle.COLOR_TITLE if _hot else UIStyle.COLOR_TEXT_DIM)


## Scroll area of the crafting preview: vertical only, a thin bronze scrollbar in a reserved lane
## (so the frame never changes width) and a fade along the bottom edge while more is below.
## Takes the mouse (PASS) only to scroll with the wheel; never takes focus.
class InvPreviewScroll:
	extends ScrollContainer
	const FADE_HEIGHT := 44.0
	var _fade: Control = null
	var _fade_queued := false

	func _init() -> void:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
		mouse_filter = Control.MOUSE_FILTER_PASS
		focus_mode = Control.FOCUS_NONE
		follow_focus = false
		var bar := get_v_scroll_bar()
		bar.focus_mode = Control.FOCUS_NONE
		get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.3)
		track.set_corner_radius_all(3)
		track.content_margin_left = 4
		track.content_margin_right = 4
		track.content_margin_top = 2
		track.content_margin_bottom = 2
		bar.add_theme_stylebox_override("scroll", track)
		bar.add_theme_stylebox_override("scroll_focus", track)
		for st: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var g := StyleBoxFlat.new()
			var c := InvStyle.FRAME_BORDER if st == "grabber" else UIStyle.COLOR_BORDER_BRIGHT
			g.bg_color = Color(c.r, c.g, c.b, 0.85)
			g.set_corner_radius_all(3)
			g.content_margin_left = 4
			g.content_margin_right = 4
			bar.add_theme_stylebox_override(st, g)
		bar.value_changed.connect(func(_v: float) -> void: queue_fade_update())
		bar.changed.connect(queue_fade_update)
		bar.visibility_changed.connect(queue_fade_update)
		resized.connect(queue_fade_update)
		_fade = Control.new()
		_fade.name = "Fade"
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.visible = false
		_fade.draw.connect(_draw_fade)
		add_child(_fade, false, Node.INTERNAL_MODE_BACK)

	func _ready() -> void:
		# Scrollbars never take focus (§16); set again here in case the container resets them.
		for bar: ScrollBar in [get_v_scroll_bar(), get_h_scroll_bar()]:
			bar.focus_mode = Control.FOCUS_NONE

	## True when part of the preview is scrolled out of view below.
	func has_more_below() -> bool:
		var bar := get_v_scroll_bar()
		return bar.visible and bar.value + bar.page < bar.max_value - 1.0

	func queue_fade_update() -> void:
		if _fade_queued:
			return
		_fade_queued = true
		_update_fade.call_deferred()

	func _update_fade() -> void:
		_fade_queued = false
		if not is_instance_valid(_fade):
			return
		var bar := get_v_scroll_bar()
		var lane := bar.get_combined_minimum_size().x
		_fade.position = Vector2(0, maxf(0.0, size.y - FADE_HEIGHT))
		_fade.size = Vector2(maxf(0.0, size.x - lane), minf(FADE_HEIGHT, size.y))
		_fade.visible = has_more_below()
		_fade.queue_redraw()

	func _draw_fade() -> void:
		var s := _fade.size
		var c := InvStyle.FRAME_BG
		var c0 := Color(c.r, c.g, c.b, 0.0)
		var mid := Vector2(0, s.y * 0.45)
		_fade.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, mid.y), mid]), PackedColorArray([c0, c0, Color(c.r, c.g, c.b, 0.75), Color(c.r, c.g, c.b, 0.75)]))
		_fade.draw_rect(Rect2(mid, Vector2(s.x, s.y - mid.y)), Color(c.r, c.g, c.b, 0.75))
		# "More below": a small bronze pill with a chevron.
		var pill := Rect2(Vector2(s.x * 0.5 - 20.0, s.y - 17.0), Vector2(40, 14))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.08, 0.06, 0.95)
		sb.border_color = InvStyle.FRAME_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(7)
		_fade.draw_style_box(sb, pill)
		var m := pill.get_center() + Vector2(0, 2.5)
		_fade.draw_polyline(PackedVector2Array([m + Vector2(-6, -5), m, m + Vector2(6, -5)]), UIStyle.COLOR_TITLE, 1.5, true)

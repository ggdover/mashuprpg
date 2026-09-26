class_name InvSlot
extends Control
## One item cell of the item panels: an inventory/stash grid cell, a paper-doll equipment slot, a
## vendor offer (with its price), a buyback offer or the crafting bench slot. Draws the item icon
## (never tinted) inside a rarity-coloured frame, red background when the requirements are not
## met, shows the item tooltip (with the equipped comparison) on hover, and forwards clicks and
## drag & drop to its `handler` (the owning panel). OWNER: ui-items. See docs/ARCHITECTURE.md §16.
##
## Handler methods (all optional, duck-typed):
##   slot_clicked(slot: InvSlot, button: int, ctrl: bool, shift: bool) -> void   (RMB, Ctrl/Shift+LMB)
##   slot_can_drop(slot: InvSlot, data: Dictionary) -> bool
##   slot_drop(slot: InvSlot, data: Dictionary) -> void
##   slot_drop_state(slot: InvSlot, data: Dictionary) -> int   (0 none, 1 ok glow, 2 refused glow)
##   slot_drag_payload(slot: InvSlot) -> Dictionary             ({} = not draggable)
##   slot_dropped_outside(slot: InvSlot, data: Dictionary) -> void
##   slot_tooltip_extra(slot: InvSlot) -> Array                 (lines appended to the tooltip)
##   slot_tooltip_anchor(slot: InvSlot) -> Rect2                (screen rect to place the tooltip by)

## Height reserved under the icon for the price (vendor / buyback cells).
const PRICE_HEIGHT := 18.0
const ICON_PAD := 4.0
const PREVIEW_SIZE := 58.0
const NORMAL_FRAME := Color(0.5, 0.48, 0.44)
const UNMET_BG := Color(0.55, 0.06, 0.05, 0.42)

## "inventory" | "equipment" | "stash" | "vendor" | "buyback" | "craft" | "preview"
var kind: String = "inventory"
## Cell index (inventory / stash / vendor stock / buyback).
var index: int = -1
## Equipment slot id (CharacterData.EQUIP_SLOTS) for paper-doll slots.
var equip_slot: String = ""
var item: Item = null:
	set(v):
		if item == v:
			return
		item = v
		queue_redraw()
## Price shown under the icon (-1 = none).
var price: int = -1:
	set(v):
		price = v
		queue_redraw()
## Price colour: gold when affordable, red otherwise.
var price_ok: bool = true:
	set(v):
		price_ok = v
		queue_redraw()
## Requirements of the item are not met (red background).
var unmet: bool = false:
	set(v):
		if unmet == v:
			return
		unmet = v
		queue_redraw()
## Faint silhouette drawn in empty equipment slots.
var placeholder: Texture2D = null
## Tooltip shown when hovering the empty slot ("Helmet").
var empty_tooltip: String = ""
## Second line of the empty-slot tooltip.
var empty_note: String = "Empty"
## Faded icon drawn in the empty slot instead of the placeholder (the off-hand slot shows the
## two-handed weapon that occupies it).
var ghost_texture: Texture2D = null:
	set(v):
		ghost_texture = v
		queue_redraw()
var handler: Object = null
var draggable: bool = true
## Glow while a compatible item is being dragged (asks handler.slot_drop_state).
var highlight_drops: bool = false
## Dim the item (e.g. while it sits in the crafting bench as a reference).
var ghost: bool = false:
	set(v):
		ghost = v
		queue_redraw()

var _hover := false
var _drag_source := false
var _drag_payload: Dictionary = {}
var _drop_state := 0
var _flash := 0.0
var _flash_tween: Tween = null
var _bg: StyleBoxFlat = null

## The slot that currently owns the shared tooltip (so exiting another slot doesn't hide it).
static var _tooltip_owner: Object = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = false


func is_hovered() -> bool:
	return _hover


## True while this slot is the source of an ongoing drag.
func is_drag_source() -> bool:
	return _drag_source


## Brief golden flash (new item, craft result).
func flash() -> void:
	if not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_flash(v: float) -> void:
	_flash = v
	queue_redraw()


## Rect of the icon area (the whole slot minus the price strip).
func get_icon_rect() -> Rect2:
	var r := Rect2(Vector2.ZERO, size)
	if price >= 0:
		r.size.y = maxf(8.0, r.size.y - PRICE_HEIGHT)
	return r


# ------------------------------------------------------------------ tooltip

## Show this slot's tooltip now (hover does this automatically).
func show_tooltip() -> void:
	if not is_inside_tree():
		return
	var lines: Array = []
	var cmp_lines: Array = []
	if item == null:
		if empty_tooltip == "":
			return
		lines = [InvStyle.line(empty_tooltip, UIStyle.COLOR_TITLE, "normal"), InvStyle.line(empty_note, UIStyle.COLOR_TEXT_DIM, "small")]
	else:
		var attrs := InvActions.get_attributes()
		var compare: Item = null
		if kind in ["inventory", "stash", "vendor", "buyback"]:
			compare = InvActions.comparison_item(item)
		lines = item.get_tooltip_lines(attrs, compare)
		if compare != null:
			cmp_lines = compare.get_tooltip_lines(attrs)
	if handler != null and is_instance_valid(handler) and handler.has_method("slot_tooltip_extra"):
		var extra: Variant = handler.call("slot_tooltip_extra", self)
		if extra is Array and not (extra as Array).is_empty():
			lines = lines.duplicate()
			lines.append_array(extra)
	UI.show_tooltip(lines, get_tooltip_anchor(), cmp_lines)
	_tooltip_owner = self


## Screen rect the tooltip is placed beside: the handler's slot_tooltip_anchor() (e.g. the
## panel frame's width at this slot's height, so the tooltip never covers the grid), else the
## slot's own rect.
func get_tooltip_anchor() -> Rect2:
	var r := get_global_rect()
	if handler != null and is_instance_valid(handler) and handler.has_method("slot_tooltip_anchor"):
		var a: Variant = handler.call("slot_tooltip_anchor", self)
		if a is Rect2 and (a as Rect2).size != Vector2.ZERO:
			r = a
	return r


func _hide_tooltip() -> void:
	if _tooltip_owner == self:
		_tooltip_owner = null
		UI.hide_tooltip()


## Re-show the tooltip if the mouse is over this slot (after its item changed).
func refresh_tooltip() -> void:
	if _hover and is_visible_in_tree() and not _is_dragging():
		if item == null and empty_tooltip == "":
			_hide_tooltip()
		else:
			show_tooltip()


func _is_dragging() -> bool:
	return is_inside_tree() and get_viewport().gui_is_dragging()


# ------------------------------------------------------------------ input

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
			if not _is_dragging():
				show_tooltip()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
			_hide_tooltip()
		NOTIFICATION_DRAG_BEGIN:
			_update_drop_state()
		NOTIFICATION_DRAG_END:
			_on_drag_end()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				_hover = false
				_hide_tooltip()
		NOTIFICATION_EXIT_TREE:
			if _tooltip_owner == self:
				_tooltip_owner = null


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var special := mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and (mb.ctrl_pressed or mb.shift_pressed or mb.meta_pressed))
	if not special:
		return
	accept_event()
	if handler != null and is_instance_valid(handler) and handler.has_method("slot_clicked"):
		handler.call("slot_clicked", self, int(mb.button_index), mb.ctrl_pressed or mb.meta_pressed, mb.shift_pressed)
	refresh_tooltip()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null or not draggable:
		return null
	var payload: Dictionary = {}
	if handler != null and is_instance_valid(handler) and handler.has_method("slot_drag_payload"):
		payload = handler.call("slot_drag_payload", self)
	else:
		payload = InvActions.make_payload(item, kind, index, equip_slot)
	if payload.is_empty():
		return null
	_drag_source = true
	_drag_payload = payload
	_hide_tooltip()
	set_drag_preview(make_drag_preview(item))
	queue_redraw()
	return payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not InvActions.is_item_payload(data) or handler == null or not is_instance_valid(handler):
		return false
	if not handler.has_method("slot_can_drop"):
		return false
	return bool(handler.call("slot_can_drop", self, data))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if handler != null and is_instance_valid(handler) and handler.has_method("slot_drop"):
		handler.call("slot_drop", self, data)
	refresh_tooltip()


func _update_drop_state() -> void:
	var old := _drop_state
	_drop_state = 0
	if highlight_drops and is_inside_tree() and handler != null and is_instance_valid(handler) and handler.has_method("slot_drop_state"):
		var d: Variant = get_viewport().gui_get_drag_data()
		if InvActions.is_item_payload(d):
			_drop_state = int(handler.call("slot_drop_state", self, d))
	if old != _drop_state:
		queue_redraw()


func _on_drag_end() -> void:
	if _drag_source:
		_drag_source = false
		var payload := _drag_payload
		_drag_payload = {}
		var ok := get_viewport().gui_is_drag_successful()
		if not ok and not UI.is_mouse_over_ui() and handler != null and is_instance_valid(handler) and handler.has_method("slot_dropped_outside"):
			handler.call("slot_dropped_outside", self, payload)
	_drop_state = 0
	queue_redraw()


## The control shown under the cursor while dragging `it`.
static func make_drag_preview(it: Item) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := InvSlot.new()
	p.kind = "preview"
	p.item = it
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	p.position = -p.size * 0.5
	p.modulate = Color(1, 1, 1, 0.92)
	wrap.add_child(p)
	return wrap


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var r := get_icon_rect()
	if _bg == null:
		_bg = StyleBoxFlat.new()
		_bg.set_corner_radius_all(3)
		_bg.anti_aliasing = true
	var rc: Color = UIStyle.rarity_color(item.rarity) if item != null else NORMAL_FRAME
	var is_normal := item == null or item.rarity == Item.Rarity.NORMAL
	# Background: dark slot, faint rarity tint for magic+ items, red when unusable.
	var bg := UIStyle.COLOR_SLOT
	if item != null and not is_normal:
		bg = bg.lerp(rc, 0.10)
	if _hover and kind != "preview":
		bg = bg.lerp(UIStyle.COLOR_SLOT_HOVER, 0.7)
	_bg.bg_color = bg
	var border := UIStyle.COLOR_BORDER.darkened(0.35)
	var bw := 1
	if item != null:
		border = Color(NORMAL_FRAME.r, NORMAL_FRAME.g, NORMAL_FRAME.b, 0.8) if is_normal else Color(rc.r, rc.g, rc.b, 0.85)
	if _hover and kind != "preview":
		border = border.lightened(0.35) if item != null else UIStyle.COLOR_BORDER_BRIGHT
		bw = 2
	match _drop_state:
		1:
			border = UIStyle.COLOR_GOOD
			bw = 2
		2:
			border = UIStyle.COLOR_BAD
			bw = 2
	_bg.border_color = border
	_bg.set_border_width_all(bw)
	draw_style_box(_bg, r)
	var inner := r.grow(-float(bw))
	# Soft inner shading: darker bottom half.
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.55), Vector2(inner.size.x, inner.size.y * 0.45)), Color(0, 0, 0, 0.14))
	if item != null and not is_normal:
		# Rarity glow in the lower part of the cell.
		var g := Color(rc.r, rc.g, rc.b, 0.16)
		var g0 := Color(rc.r, rc.g, rc.b, 0.0)
		var top_y := inner.position.y + inner.size.y * 0.35
		var bot_y := inner.end.y
		draw_polygon(PackedVector2Array([Vector2(inner.position.x, top_y), Vector2(inner.end.x, top_y), Vector2(inner.end.x, bot_y), Vector2(inner.position.x, bot_y)]), PackedColorArray([g0, g0, g, g]))
	if item != null and unmet:
		draw_rect(inner, UNMET_BG)
	if _drop_state == 1:
		draw_rect(inner, Color(UIStyle.COLOR_GOOD.r, UIStyle.COLOR_GOOD.g, UIStyle.COLOR_GOOD.b, 0.10))
	# Icon or placeholder silhouette.
	var side := minf(r.size.x, r.size.y) - ICON_PAD * 2.0
	if item != null:
		var tex: Texture2D = Assets.item_icon(item.get_model_id())
		if side > 4.0 and tex != null:
			var ir := Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
			var a := 0.35 if (_drag_source or ghost) else 1.0
			draw_texture_rect(tex, ir, false, Color(1, 1, 1, a))
	elif ghost_texture != null and side > 4.0:
		var gr := Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
		draw_texture_rect(ghost_texture, gr, false, Color(1, 1, 1, 0.22))
	elif placeholder != null and side > 4.0:
		var pr := Rect2(r.get_center() - Vector2(side, side) * 0.4, Vector2(side, side) * 0.8)
		draw_texture_rect(placeholder, pr, false, Color(0.78, 0.68, 0.52, 0.16))
	if _flash > 0.0:
		draw_rect(inner, Color(1.0, 0.88, 0.55, 0.38 * _flash))
	# Price strip.
	if price >= 0:
		var font := get_theme_default_font()
		var fs := 13
		var text := InvStyle.format_int(price)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var coin := Assets.item_icon("loot_gold")
		var cs := 13.0
		var total := tw + cs + 3.0
		var x := roundf((size.x - total) * 0.5)
		var y := r.end.y + 2.0
		if coin != null:
			draw_texture_rect(coin, Rect2(Vector2(x, y + 1.0), Vector2(cs, cs)), false)
		var col := UIStyle.COLOR_GOLD if price_ok else UIStyle.COLOR_BAD
		draw_string(font, Vector2(x + cs + 3.0, y + font.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

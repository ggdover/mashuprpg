class_name UIRoot
extends CanvasLayer
## Autoload "UI": the root of all 2D interface. Owns the HUD, every panel, the shared tooltip and
## notifications. OWNER: orchestrator (implemented in wave 0 because every module depends on it).
## Panel implementations are owned by the UI modules. See docs/ARCHITECTURE.md §16.
##
## Panels are created lazily from PANELS the first time they are opened/requested. Each panel script
## extends Control and may implement:
##   func on_opened(context: Dictionary) -> void
##   func on_closed() -> void
## UIRoot adds every panel (and the HUD) with FULL_RECT anchors. The panel ROOT gets
## MOUSE_FILTER_IGNORE (so empty screen areas never swallow gameplay clicks) unless the panel is
## full-screen (FULLSCREEN_PANELS), which get MOUSE_FILTER_STOP. Inside a panel, only the visible
## frames/slots/buttons use MOUSE_FILTER_STOP. Do not change your panel root's anchors/mouse_filter.
##
## Input: only in _unhandled_input (never _input), so typing in a LineEdit never toggles panels.
## Toggle keys and Esc are ignored while a MODAL panel is open or there is no live player.
## Esc closes the most recently opened panel; with none open it opens the pause menu.
##
## Notifications: Events.notify, Events.skill_use_failed (throttled) and Events.inventory_full are
## shown here as fading centre-screen text. The HUD does not handle them.

## Panel name -> script. "inventory" also opens automatically next to "vendor" and "stash".
const PANELS := {
	"inventory": "res://scripts/ui/inventory/inventory_panel.gd",
	"character": "res://scripts/ui/character/character_panel.gd",
	"stash": "res://scripts/ui/stash/stash_panel.gd",
	"vendor": "res://scripts/ui/vendor/vendor_panel.gd",
	"passives": "res://scripts/ui/passive_tree/passive_tree_panel.gd",
	"skills": "res://scripts/ui/skills/skills_panel.gd",
	"waypoint": "res://scripts/ui/waypoint/waypoint_panel.gd",
	"acts": "res://scripts/ui/acts/acts_panel.gd",
	"debug": "res://scripts/ui/debug/debug_panel.gd",
	"pause": "res://scripts/ui/menus/pause_menu.gd",
	"death": "res://scripts/ui/menus/death_screen.gd",
	"main_menu": "res://scripts/ui/menus/main_menu.gd",
}
const HUD_SCRIPT := "res://scripts/ui/hud/hud.gd"
const TOOLTIP_SCRIPT := "res://scripts/ui/tooltip/tooltip_panel.gd"

## Panels whose root covers the whole screen and blocks the mouse.
const FULLSCREEN_PANELS: Array[String] = ["passives", "pause", "death", "main_menu"]
## While one of these is open, Esc and the toggle keys do nothing (close via their own buttons).
const MODAL_PANELS: Array[String] = ["main_menu", "death"]
## Toggle action -> panel.
const TOGGLE_ACTIONS := {
	"toggle_inventory": "inventory",
	"toggle_character": "character",
	"toggle_passives": "passives",
	"toggle_skills": "skills",
	"toggle_acts": "acts",
	"toggle_debug": "debug",
}

var _root: Control
## The "F1: debug menu" hint is shown once per session.
var _debug_hint_shown := false
var _hud_layer: Control
var _panel_layer: Control
var _top_layer: Control
var _notify_box: VBoxContainer
var _hud: Control = null
var _tooltip: Control = null
var _panels: Dictionary = {}          # name -> Control
var _open_stack: Array[String] = []   # open panels, most recent last
var _inventory_auto_opened := false
var _last_notify: Dictionary = {}     # text -> msec (throttle)


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "UIRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIStyle.make_theme()
	add_child(_root)
	for layer_name in ["HudLayer", "PanelLayer", "TopLayer"]:
		var c := Control.new()
		c.name = layer_name
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(c)
	_hud_layer = _root.get_node("HudLayer")
	_panel_layer = _root.get_node("PanelLayer")
	_top_layer = _root.get_node("TopLayer")

	_notify_box = VBoxContainer.new()
	_notify_box.name = "Notifications"
	_notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notify_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notify_box.position = Vector2(-400, 150)
	_notify_box.custom_minimum_size = Vector2(800, 0)
	_notify_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top_layer.add_child(_notify_box)

	Events.panel_toggle_requested.connect(toggle_panel)
	Events.panel_open_requested.connect(open_panel)
	Events.panel_close_requested.connect(close_panel)
	Events.notify.connect(notify)
	Events.skill_use_failed.connect(_on_skill_use_failed)
	Events.inventory_full.connect(_on_inventory_full)
	Events.area_entered.connect(_on_area_entered)


# ------------------------------------------------------------------ panels

func open_panel(panel: String, context: Dictionary = {}) -> void:
	var p := get_panel(panel)
	if p == null:
		return
	if panel in ["vendor", "stash"] and not is_panel_open("inventory"):
		open_panel("inventory", {})
		_inventory_auto_opened = true
	var was_open := p.visible
	p.visible = true
	_panel_layer.move_child(p, -1)
	_open_stack.erase(panel)
	_open_stack.append(panel)
	if panel == "pause":
		get_tree().paused = true
	if p.has_method("on_opened"):
		p.call("on_opened", context)
	if not was_open:
		Sfx.play_ui("ui_open")


func close_panel(panel: String) -> void:
	if not _panels.has(panel):
		return
	var p: Control = _panels[panel]
	if not p.visible:
		return
	p.visible = false
	_open_stack.erase(panel)
	if panel == "pause":
		get_tree().paused = false
	if p.has_method("on_closed"):
		p.call("on_closed")
	hide_tooltip()
	get_viewport().gui_release_focus()
	Sfx.play_ui("ui_close")
	if panel in ["vendor", "stash"] and _inventory_auto_opened and not is_panel_open("vendor") and not is_panel_open("stash"):
		_inventory_auto_opened = false
		close_panel("inventory")
	if panel == "inventory":
		_inventory_auto_opened = false
		for other in ["vendor", "stash"]:
			if is_panel_open(other):
				close_panel(other)


func toggle_panel(panel: String) -> void:
	if is_panel_open(panel):
		close_panel(panel)
	else:
		open_panel(panel, {})


func close_all_panels() -> void:
	for panel in _open_stack.duplicate():
		close_panel(panel)
	hide_tooltip()


func is_panel_open(panel: String) -> bool:
	return _panels.has(panel) and (_panels[panel] as Control).visible


func any_panel_open() -> bool:
	return not _open_stack.is_empty()


func is_modal_open() -> bool:
	for m in MODAL_PANELS:
		if is_panel_open(m):
			return true
	return false


## The live panel instance (creating it if needed), e.g. to call panel-specific methods.
func get_panel(panel: String) -> Control:
	if _panels.has(panel):
		return _panels[panel]
	if not PANELS.has(panel):
		push_warning("UI: unknown panel '%s'" % panel)
		return null
	var script := load(PANELS[panel]) as GDScript
	if script == null:
		push_warning("UI: panel script missing for '%s'" % panel)
		return null
	var p: Control = script.new()
	p.name = panel.capitalize().replace(" ", "") + "Panel"
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP if panel in FULLSCREEN_PANELS else Control.MOUSE_FILTER_IGNORE
	p.visible = false
	_panel_layer.add_child(p)
	_panels[panel] = p
	return p


## True if the mouse is over any UI control that takes mouse input (panels' frames, slots, HUD
## globes/skill bar...). Gameplay must not act on clicks while this is true.
func is_mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


# ------------------------------------------------------------------ tooltip

## Show the shared tooltip near `anchor` (screen rect of the hovered control). Lines use the
## Item.get_tooltip_lines() format. compare_lines, if given, are shown in a second box beside it.
func show_tooltip(lines: Array, anchor: Rect2, compare_lines: Array = []) -> void:
	if _tooltip == null:
		var script := load(TOOLTIP_SCRIPT) as GDScript
		if script == null:
			return
		_tooltip = script.new()
		_tooltip.name = "Tooltip"
		_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top_layer.add_child(_tooltip)
	if _tooltip.has_method("show_lines"):
		_tooltip.call("show_lines", lines, anchor, compare_lines)
		_tooltip.visible = true


func hide_tooltip() -> void:
	if _tooltip != null:
		if _tooltip.has_method("hide_tooltip"):
			_tooltip.call("hide_tooltip")
		_tooltip.visible = false


# ------------------------------------------------------------------ HUD / menus

func show_hud(on: bool) -> void:
	if on and _hud == null:
		var script := load(HUD_SCRIPT) as GDScript
		if script != null:
			_hud = script.new()
			_hud.name = "HUD"
			_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
			_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hud_layer.add_child(_hud)
	if _hud != null:
		_hud.visible = on


func get_hud() -> Control:
	return _hud


## Close everything, hide the HUD and show the title screen. Called by the game flow only.
func show_main_menu() -> void:
	close_all_panels()
	show_hud(false)
	open_panel("main_menu", {})


# ------------------------------------------------------------------ notifications

func notify(text: String, color: Color = UIStyle.COLOR_TEXT) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_notify.get(text, -100000)) < 700:
		return
	_last_notify[text] = now
	var l := UIStyle.make_label(text, UIStyle.FONT_LARGE, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	_notify_box.add_child(l)
	while _notify_box.get_child_count() > 4:
		_notify_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _on_skill_use_failed(reason: String) -> void:
	notify(reason, UIStyle.COLOR_BAD)


func _on_inventory_full() -> void:
	notify("Inventory full", UIStyle.COLOR_BAD)


func _on_area_entered(_info: Dictionary) -> void:
	close_all_panels()
	show_hud(true)
	# "Explore the Acts" / "Debug Menu" from the title screen: open that panel on arrival
	# (open_on_enter = a panel name, or true for the Act Explorer).
	var want: Variant = GameState.act_options.get("open_on_enter", false)
	if want is String or bool(want):
		GameState.act_options.erase("open_on_enter")
		open_panel.call_deferred(String(want) if want is String else "acts", {})
	elif not _debug_hint_shown:
		_debug_hint_shown = true
		notify("F1: debug menu (travel anywhere, teleport, cheats)", UIStyle.COLOR_TEXT_DIM)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if is_modal_open():
		return
	if event.is_action_pressed("pause_menu"):
		if GameState.player == null:
			return
		if not _open_stack.is_empty():
			close_panel(_open_stack.back())
		else:
			open_panel("pause", {})
		get_viewport().set_input_as_handled()
		return
	if GameState.player == null or is_panel_open("pause"):
		return
	for action: String in TOGGLE_ACTIONS:
		if event.is_action_pressed(action):
			toggle_panel(TOGGLE_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return

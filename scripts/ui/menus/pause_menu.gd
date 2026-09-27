class_name PauseMenu
extends Control
## Pause menu (pauses the tree): Resume, Save, Save & Quit to Menu, Quit Game.
## OWNER: UI tree/skills/menus module (wave 2). See docs/ARCHITECTURE.md §15, §16.
##
## Full screen (UIRoot gives the root MOUSE_FILTER_STOP and pauses/unpauses the tree when it
## opens/closes "pause"; the UI keeps processing). A dimmed, vignetted game view with a centred
## frame: "PAUSED", the character and area, play time, and the buttons:
##   Resume              -> closes the panel (Esc does the same through UIRoot)
##   Act Explorer        -> closes the panel and opens the Act Explorer ("acts", demo travel menu)
##   Debug Menu          -> closes the panel and opens the debug menu ("debug": zones, teleports, cheats)
##   Save Game           -> GameState.save_game() + notification
##   Save & Quit to Menu -> save, then Events.return_to_menu_requested
##   Quit Game           -> save, then Events.quit_requested
## Standalone: `var p := PauseMenu.new(); add_child(p); p.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuFrame := preload("res://scripts/ui/menus/menu_frame.gd")
const MenuTitle := preload("res://scripts/ui/menus/menu_title.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")

const PANEL_NAME := "pause"

var resume_button: Button
var acts_button: Button
var debug_button: Button
var save_button: Button
var save_quit_button: Button
var quit_button: Button

var _built := false
var _char_label: Label
var _area_label: Label
var _status_label: Label
var _busy := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MenuStyle.get_theme()


func _ready() -> void:
	_ensure_built()


## Called by UIRoot after the panel becomes visible.
func on_opened(_context: Dictionary) -> void:
	_ensure_built()
	_busy = false
	_status_label.text = ""
	_update_info()
	_set_buttons_enabled(true)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	modulate.a = 1.0


# ------------------------------------------------------------------ actions

func resume() -> void:
	if UI.is_panel_open(PANEL_NAME) and UI.get_panel(PANEL_NAME) == self:
		UI.close_panel(PANEL_NAME)
	else:
		visible = false
		on_closed()


## Close the pause menu and open the Act Explorer.
func open_act_explorer() -> void:
	if _busy:
		return
	resume()
	UI.open_panel("acts", {})


## Close the pause menu and open the debug menu.
func open_debug_menu() -> void:
	if _busy:
		return
	resume()
	UI.open_panel("debug", {})


## Save the character. Returns true on success (notifies either way).
func save() -> bool:
	if GameState.character == null:
		_status("Nothing to save", UIStyle.COLOR_TEXT_DIM)
		return false
	var ok := GameState.save_game()
	if ok:
		_status("Game saved", UIStyle.COLOR_GOOD)
		Events.notify.emit("Game saved", UIStyle.COLOR_GOOD)
	else:
		_status("Save failed", UIStyle.COLOR_BAD)
		Events.notify.emit("Save failed", UIStyle.COLOR_BAD)
	return ok


func save_and_quit_to_menu() -> void:
	if _busy:
		return
	_busy = true
	if GameState.character != null:
		GameState.save_game()
	_set_buttons_enabled(false)
	_status("Returning to the title screen...", MenuStyle.GOLD)
	Events.return_to_menu_requested.emit()


func quit_game() -> void:
	if _busy:
		return
	_busy = true
	if GameState.character != null:
		GameState.save_game()
	_set_buttons_enabled(false)
	_status("Farewell...", MenuStyle.GOLD)
	Events.quit_requested.emit()


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var dim := MenuCanvas.new(_paint_backdrop)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BORDER, 30)
	frame.set("accent", Color(MenuStyle.GOLD, 0.8))
	frame.custom_minimum_size = Vector2(500, 0)
	center.add_child(frame)
	var v := MenuStyle.vbox(10)
	frame.add_child(v)
	var title: Control = MenuTitle.new("PAUSED", 64, MenuStyle.GOLD, Color(MenuStyle.EMBER, 0.8))
	v.add_child(title)
	_char_label = MenuStyle.label("", UIStyle.FONT_LARGE, UIStyle.COLOR_TEXT)
	_char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_char_label)
	_area_label = MenuStyle.label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM)
	_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_area_label)
	v.add_child(MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(20, ci.size.y * 0.5), Vector2(ci.size.x - 20, ci.size.y * 0.5), UIStyle.COLOR_BORDER_BRIGHT), Vector2(0, 22)))
	var bv := MenuStyle.vbox(12)
	resume_button = _button(bv, "Resume", true, resume)
	acts_button = _button(bv, "Act Explorer", false, open_act_explorer)
	debug_button = _button(bv, "Debug Menu  (F1)", false, open_debug_menu)
	save_button = _button(bv, "Save Game", false, func() -> void: save())
	save_quit_button = _button(bv, "Save & Quit to Menu", false, save_and_quit_to_menu)
	quit_button = _button(bv, "Quit Game", false, quit_game)
	quit_button.add_theme_color_override("font_hover_color", Color(1.0, 0.6, 0.5))
	var bc := CenterContainer.new()
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(bv)
	v.add_child(bc)
	_status_label = MenuStyle.label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_GOOD)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(0, 24)
	v.add_child(_status_label)
	var hint := MenuStyle.label("Esc  —  Resume", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _button(parent: Control, text: String, primary: bool, cb: Callable) -> Button:
	var b := MenuStyle.make_button(text, UIStyle.FONT_LARGE, primary)
	b.custom_minimum_size = Vector2(340, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _set_buttons_enabled(on: bool) -> void:
	for b in [resume_button, acts_button, debug_button, save_button, save_quit_button, quit_button]:
		(b as Button).disabled = not on


func _status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _update_info() -> void:
	var c := GameState.character
	if c == null:
		_char_label.text = ""
		_area_label.text = ""
		return
	_char_label.text = "%s  ·  Level %d %s" % [c.char_name, c.level, ClassDefs.get_display_name(c.class_id)]
	_char_label.add_theme_color_override("font_color", ClassDefs.get_color(c.class_id).lightened(0.35))
	var area := String(GameState.current_area.get("name", ""))
	var secs := int(c.play_time)
	var played := "%dh %02dm played" % [secs / 3600, (secs / 60) % 60]
	_area_label.text = ("%s  ·  %s" % [area, played]) if area != "" else played


func _paint_backdrop(ci: Control) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0.01, 0.008, 0.012, 0.62))
	ci.draw_texture_rect(MenuStyle.vignette_texture(), Rect2(-ci.size * 0.05, ci.size * 1.1), false, Color(1, 1, 1, 0.9))
	MenuStyle.draw_glow(ci, ci.size * 0.5, ci.size.x * 0.35, Color(MenuStyle.EMBER, 0.06), true)

class_name MainMenu
extends Control
## Title screen: character list (continue / delete), New Character (name + class select with descriptions), Quit.
## OWNER: UI tree/skills/menus module (wave 2). See docs/ARCHITECTURE.md §15, §16.
##
## Full screen (UIRoot gives the root MOUSE_FILTER_STOP; modal: Esc/toggles are blocked).
## Views:
##   list    — saves from GameState.list_saves() (newest first). Continue (or double-click / Enter)
##             emits Events.load_game_requested(save_id); Delete asks for confirmation and then
##             calls GameState.delete_save(); New Character opens the create view; Quit Game emits
##             Events.quit_requested.
##   create  — name LineEdit (Enter = begin, dice = random name) + three class cards with
##             ClassDefs descriptions, colours, attributes, starting gear and skills, and an
##             Appearance row for classes with several looks (ClassDefs "looks"; the warrior picks
##             one of two male exiles). Begin Adventure emits
##             Events.new_game_requested(name, class_id, appearance).
## The create view opens by itself when there are no saves. After a request is emitted the buttons
## are disabled until the menu is opened again (or for a few seconds, in case the flow refused).
## Standalone: `var m := MainMenu.new(); add_child(m); m.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuFrame := preload("res://scripts/ui/menus/menu_frame.gd")
const MenuTitle := preload("res://scripts/ui/menus/menu_title.gd")
const MenuBackdrop := preload("res://scripts/ui/menus/menu_backdrop.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")
const MenuSaveRow := preload("res://scripts/ui/menus/menu_save_row.gd")
const MenuClassCard := preload("res://scripts/ui/menus/menu_class_card.gd")

const PANEL_NAME := "main_menu"
const NAME_MAX_LENGTH := 20
const BUSY_TIMEOUT := 4.0
const VERSION_TEXT := "Mashup RPG  ·  Godot 4.6"
const NAME_START: PackedStringArray = ["Ae", "Bra", "Cor", "Dra", "El", "Fen", "Gar", "Hal", "Ith", "Jor", "Kae", "Lor", "Mor", "Nyx", "Or", "Pyr", "Quel", "Ras", "Syl", "Tor", "Ul", "Vae", "Wren", "Xan", "Yr", "Zed"]
const NAME_END: PackedStringArray = ["dric", "lyn", "wen", "mir", "gar", "thas", "ric", "vyn", "ra", "dor", "iel", "ros", "na", "ven", "mar", "eth", "a", "is", "on", "wyn"]

var continue_button: Button
var new_button: Button
var delete_button: Button
var quit_button: Button
## "Debug Menu (F1)": loads (or creates) the demo character and opens the debug menu.
var explore_button: Button
var explore_create_button: Button
var begin_button: Button
var back_button: Button
var random_name_button: Button
var name_edit: LineEdit
var confirm_yes_button: Button
var confirm_no_button: Button

var _built := false
var _backdrop: Control
var _title: Control
var _subtitle: Label
var _list_view: Control
var _create_view: Control
var _confirm: Control
var _confirm_text: Label
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _empty_box: Control
var _count_label: Label
var _status_label: Label
var _save_group := ButtonGroup.new()
var _class_group := ButtonGroup.new()
var _look_group := ButtonGroup.new()
## The Appearance row (hidden when the selected class has a single look) and its buttons.
var look_row: HBoxContainer
var _look_buttons: Dictionary = {}  # look -> Button
var _selected_look := ""
var _rows: Dictionary = {}          # save_id -> row
var _cards: Dictionary = {}         # class_id -> card
var _saves: Array = []
var _selected_save := ""
var _selected_class := ClassDefs.DEFAULT_CLASS
var _busy_time := 0.0


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
	_set_busy(false)
	_confirm.visible = false
	refresh_saves()
	if _saves.is_empty():
		show_create_view()
	else:
		show_list_view()


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	if _confirm != null:
		_confirm.visible = false


# ------------------------------------------------------------------ public API (tests, flow)

## Re-read GameState.list_saves() and rebuild the list (keeps the selection if it still exists).
func refresh_saves() -> void:
	_ensure_built()
	_saves = GameState.list_saves()
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	for info: Dictionary in _saves:
		var row: Button = MenuSaveRow.new(info)
		row.button_group = _save_group
		var sid := String(info["save_id"])
		row.toggled.connect(func(on: bool) -> void:
			if on:
				_select(sid))
		row.activated.connect(func(id: String) -> void:
			_select(id)
			continue_selected())
		_rows_box.add_child(row)
		_rows[sid] = row
	_empty_box.visible = _saves.is_empty()
	_count_label.text = "" if _saves.is_empty() else ("%d hero%s" % [_saves.size(), "" if _saves.size() == 1 else "es"])
	if not _rows.has(_selected_save):
		_selected_save = String(_saves[0]["save_id"]) if not _saves.is_empty() else ""
	if _selected_save != "":
		(_rows[_selected_save] as Button).set_pressed_no_signal(true)
	_update_buttons()


func get_save_ids() -> Array:
	var out: Array = []
	for info: Dictionary in _saves:
		out.append(String(info["save_id"]))
	return out


func select_save(save_id: String) -> void:
	if _rows.has(save_id):
		(_rows[save_id] as Button).button_pressed = true
		_select(save_id)


func get_selected_save() -> String:
	return _selected_save


## Emit Events.load_game_requested for the selected save.
func continue_selected() -> void:
	if _selected_save == "" or _is_busy():
		return
	_set_busy(true, "Entering the world...")
	Events.load_game_requested.emit(_selected_save)


## Open the delete confirmation for the selected save.
func request_delete_selected() -> void:
	if _selected_save == "" or _is_busy():
		return
	var info := _info_for(_selected_save)
	_confirm_text.text = "%s, Level %d %s, will be lost forever." % [
		String(info.get("char_name", "Hero")), int(info.get("level", 1)), ClassDefs.get_display_name(String(info.get("class_id", "")))]
	_confirm.visible = true


func confirm_delete() -> void:
	_confirm.visible = false
	if _selected_save == "":
		return
	GameState.delete_save(_selected_save)
	Sfx.play_ui("ui_close")
	Events.notify.emit("Character deleted", UIStyle.COLOR_TEXT_DIM)
	_selected_save = ""
	refresh_saves()
	if _saves.is_empty():
		show_create_view()


func cancel_delete() -> void:
	_confirm.visible = false


func show_list_view() -> void:
	_ensure_built()
	_list_view.visible = true
	_create_view.visible = false
	_title.set("font_size", 118)
	_subtitle.visible = true
	back_button.visible = true
	if is_inside_tree():
		get_viewport().gui_release_focus()
	_update_buttons()


func show_create_view() -> void:
	_ensure_built()
	_list_view.visible = false
	_create_view.visible = true
	_title.set("font_size", 76)
	_subtitle.visible = false
	back_button.visible = not _saves.is_empty()
	if name_edit.text.strip_edges() == "":
		name_edit.text = random_name()
	select_class(_selected_class)
	_update_buttons()


func is_create_view() -> bool:
	return _create_view != null and _create_view.visible


func select_class(class_id: String) -> void:
	if not _cards.has(class_id):
		return
	_selected_class = class_id
	(_cards[class_id] as Button).button_pressed = true
	_refresh_looks()


## Pick one of the selected class's looks (ignored when the class can't pick it).
func select_look(look: String) -> void:
	if not ClassDefs.get_looks(_selected_class).has(look):
		return
	_selected_look = look
	if _look_buttons.has(look):
		(_look_buttons[look] as Button).set_pressed_no_signal(true)


## The look the new hero will have (the class default until another is picked).
func get_selected_look() -> String:
	return ClassDefs.get_look(_selected_class, _selected_look)


func get_selected_class() -> String:
	return _selected_class


func set_character_name(text: String) -> void:
	name_edit.text = text.left(NAME_MAX_LENGTH)
	_update_buttons()


## Emit Events.new_game_requested(name, class) (needs a non-empty name).
func begin_new_game() -> void:
	var n := name_edit.text.strip_edges()
	if n == "" or _is_busy():
		return
	_set_busy(true, "Your journey begins...")
	Events.new_game_requested.emit(n, _selected_class, get_selected_look())


func quit_game() -> void:
	Events.quit_requested.emit()


const EXPLORER_NAME := "Act Explorer"

## Demo: load the "Act Explorer" character (created as a ranger the first time) and open the Act
## Explorer panel on arrival.
func explore_acts() -> void:
	_start_demo("acts")


## Debug: load the "Act Explorer" character (created as a ranger the first time) and open the
## debug menu on arrival (also F1 on the title screen).
func open_debug_menu() -> void:
	_start_demo("debug")


func _start_demo(panel: String) -> void:
	if _is_busy():
		return
	GameState.act_options["open_on_enter"] = panel
	var sid := ""
	for info: Dictionary in GameState.list_saves():
		if String(info.get("char_name", "")) == EXPLORER_NAME:
			sid = String(info["save_id"])
			break
	_set_busy(true, "Opening the debug menu..." if panel == "debug" else "Opening the Act Explorer...")
	if sid != "":
		Events.load_game_requested.emit(sid)
	else:
		Events.new_game_requested.emit(EXPLORER_NAME, "ranger", "")


## A random fantasy name ("Kaeris", "Wrendor"...).
static func random_name() -> String:
	return NAME_START[randi() % NAME_START.size()] + NAME_END[randi() % NAME_END.size()]


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	var root := MenuStyle.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_top = 48
	root.offset_bottom = -26
	root.offset_left = 40
	root.offset_right = -40
	add_child(root)
	_title = MenuTitle.new("MASHUP RPG", 118, MenuStyle.GOLD, Color(MenuStyle.EMBER, 0.95))
	_title.set("pulse", 0.6)
	root.add_child(_title)
	_subtitle = MenuStyle.title_label("DELVE  ·  LOOT  ·  GROW STRONGER", 22, Color(0.85, 0.78, 0.66, 0.85))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_subtitle)
	root.add_child(MenuStyle.spacer(Vector2(0, 26), false))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var views := MenuStyle.vbox(0)
	center.add_child(views)
	_list_view = _build_list_view()
	views.add_child(_list_view)
	_create_view = _build_create_view()
	views.add_child(_create_view)
	var footer := MenuStyle.hbox(12)
	_status_label = MenuStyle.label("", UIStyle.FONT_NORMAL, MenuStyle.GOLD, 3)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_label)
	var ver := MenuStyle.label(VERSION_TEXT, UIStyle.FONT_SMALL, Color(UIStyle.COLOR_TEXT_DIM, 0.8), 3)
	footer.add_child(ver)
	root.add_child(footer)
	_confirm = _build_confirm()
	add_child(_confirm)
	_create_view.visible = false


func _build_list_view() -> Control:
	var frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BORDER, 22)
	frame.set("accent", Color(MenuStyle.GOLD, 0.8))
	frame.custom_minimum_size = Vector2(760, 0)
	var v := MenuStyle.vbox(12)
	frame.add_child(v)
	var head := MenuStyle.hbox(8)
	head.add_child(MenuStyle.title_label("Choose Your Hero", 30, UIStyle.COLOR_TITLE))
	head.add_child(MenuStyle.spacer())
	_count_label = MenuStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_count_label)
	v.add_child(head)
	v.add_child(_divider())
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 420)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_scroll)
	var inner := MenuStyle.vbox(0)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(inner)
	_rows_box = MenuStyle.vbox(8)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_rows_box)
	var empty := MenuStyle.vbox(10)
	empty.custom_minimum_size = Vector2(0, 380)
	empty.alignment = BoxContainer.ALIGNMENT_CENTER
	var e1 := MenuStyle.title_label("No heroes yet", 26, UIStyle.COLOR_TEXT_DIM)
	e1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(e1)
	var e2 := MenuStyle.label("Create a character to begin your journey into the depths.", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT_DIM)
	e2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(e2)
	inner.add_child(empty)
	_empty_box = empty
	v.add_child(_divider())
	var buttons := MenuStyle.hbox(12)
	quit_button = MenuStyle.make_button("Quit Game", UIStyle.FONT_NORMAL)
	quit_button.pressed.connect(quit_game)
	buttons.add_child(quit_button)
	explore_button = MenuStyle.make_button("Debug Menu (F1)", UIStyle.FONT_NORMAL)
	explore_button.add_theme_color_override("font_color", MenuStyle.GOLD)
	explore_button.pressed.connect(open_debug_menu)
	buttons.add_child(explore_button)
	buttons.add_child(MenuStyle.spacer())
	delete_button = MenuStyle.make_button("Delete", UIStyle.FONT_NORMAL)
	delete_button.add_theme_color_override("font_hover_color", UIStyle.COLOR_BAD)
	delete_button.pressed.connect(request_delete_selected)
	buttons.add_child(delete_button)
	new_button = MenuStyle.make_button("New Character", UIStyle.FONT_NORMAL)
	new_button.pressed.connect(show_create_view)
	buttons.add_child(new_button)
	continue_button = MenuStyle.make_button("Continue", UIStyle.FONT_LARGE, true)
	continue_button.custom_minimum_size = Vector2(190, 0)
	continue_button.pressed.connect(continue_selected)
	buttons.add_child(continue_button)
	v.add_child(buttons)
	return frame


func _build_create_view() -> Control:
	var v := MenuStyle.vbox(18)
	# Name row.
	var name_frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BORDER, 16)
	name_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var nh := MenuStyle.hbox(14)
	name_frame.add_child(nh)
	var nl := MenuStyle.title_label("Create a New Hero", 28, UIStyle.COLOR_TITLE)
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nh.add_child(nl)
	nh.add_child(MenuStyle.spacer(Vector2(24, 0), false))
	var nm := MenuStyle.label("Name", UIStyle.FONT_LARGE, UIStyle.COLOR_TEXT_DIM)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nh.add_child(nm)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(340, 44)
	name_edit.max_length = NAME_MAX_LENGTH
	name_edit.placeholder_text = "Enter a name"
	name_edit.add_theme_font_size_override("font_size", UIStyle.FONT_LARGE)
	name_edit.add_theme_font_override("font", MenuStyle.heading_font())
	name_edit.text_changed.connect(func(_t: String) -> void: _update_buttons())
	name_edit.text_submitted.connect(func(_t: String) -> void: begin_new_game())
	nh.add_child(name_edit)
	random_name_button = MenuStyle.make_button("Random", UIStyle.FONT_NORMAL)
	random_name_button.tooltip_text = ""
	random_name_button.pressed.connect(func() -> void: set_character_name(random_name()))
	nh.add_child(random_name_button)
	v.add_child(name_frame)
	# Class cards.
	var cards := MenuStyle.hbox(28)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for cid in ["warrior", "ranger", "sorcerer"]:
		if not ClassDefs.has_class(cid):
			continue
		var card: Button = MenuClassCard.new(cid)
		card.button_group = _class_group
		card.toggled.connect(func(on: bool) -> void:
			if on:
				_selected_class = cid
				_refresh_looks()
				_update_buttons())
		card.chosen.connect(func(_id: String) -> void: begin_new_game())
		cards.add_child(card)
		_cards[cid] = card
	v.add_child(cards)
	# Appearance (classes with several looks).
	look_row = MenuStyle.hbox(12)
	look_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(look_row)
	# Buttons.
	var buttons := MenuStyle.hbox(12)
	back_button = MenuStyle.make_button("Back", UIStyle.FONT_NORMAL)
	back_button.custom_minimum_size = Vector2(140, 0)
	back_button.pressed.connect(show_list_view)
	buttons.add_child(back_button)
	explore_create_button = MenuStyle.make_button("Debug Menu (F1)", UIStyle.FONT_NORMAL)
	explore_create_button.add_theme_color_override("font_color", MenuStyle.GOLD)
	explore_create_button.pressed.connect(open_debug_menu)
	buttons.add_child(explore_create_button)
	buttons.add_child(MenuStyle.spacer())
	begin_button = MenuStyle.make_button("Begin Adventure", UIStyle.FONT_LARGE, true)
	begin_button.custom_minimum_size = Vector2(260, 0)
	begin_button.pressed.connect(begin_new_game)
	buttons.add_child(begin_button)
	v.add_child(buttons)
	return v


## Rebuild the Appearance row for the selected class (hidden with a single look).
func _refresh_looks() -> void:
	if look_row == null:
		return
	for c in look_row.get_children():
		look_row.remove_child(c)
		c.queue_free()
	_look_buttons.clear()
	var looks := ClassDefs.get_looks(_selected_class)
	if not looks.has(_selected_look):
		_selected_look = looks[0]
	look_row.visible = looks.size() > 1
	if looks.size() <= 1:
		return
	var l := MenuStyle.label("Appearance", UIStyle.FONT_LARGE, UIStyle.COLOR_TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	look_row.add_child(l)
	look_row.add_child(MenuStyle.spacer(Vector2(8, 0), false))
	for look in looks:
		var b := MenuStyle.make_button(String(ClassDefs.LOOK_NAMES.get(look, look)), UIStyle.FONT_NORMAL)
		b.toggle_mode = true
		b.button_group = _look_group
		b.custom_minimum_size = Vector2(190, 0)
		b.button_pressed = look == _selected_look
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_selected_look = look)
		look_row.add_child(b)
		_look_buttons[look] = b


func _build_confirm() -> Control:
	var dim := ColorRect.new()
	dim.color = MenuStyle.OVERLAY
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var frame: PanelContainer = MenuFrame.new(MenuStyle.FRAME_BG, UIStyle.COLOR_BAD.darkened(0.3), 26)
	frame.set("accent", Color(UIStyle.COLOR_BAD, 0.8))
	frame.custom_minimum_size = Vector2(560, 0)
	center.add_child(frame)
	var v := MenuStyle.vbox(16)
	frame.add_child(v)
	var t := MenuStyle.title_label("Delete Character?", 30, UIStyle.COLOR_BAD.lightened(0.15))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_confirm_text = MenuStyle.label("", UIStyle.FONT_NORMAL, UIStyle.COLOR_TEXT)
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_confirm_text)
	var warn := MenuStyle.label("This cannot be undone.", UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT_DIM)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(warn)
	var b := MenuStyle.hbox(16)
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_no_button = MenuStyle.make_button("Cancel", UIStyle.FONT_NORMAL)
	confirm_no_button.custom_minimum_size = Vector2(150, 0)
	confirm_no_button.pressed.connect(cancel_delete)
	b.add_child(confirm_no_button)
	confirm_yes_button = MenuStyle.make_button("Delete Forever", UIStyle.FONT_NORMAL)
	confirm_yes_button.custom_minimum_size = Vector2(190, 0)
	confirm_yes_button.add_theme_color_override("font_color", UIStyle.COLOR_BAD.lightened(0.2))
	confirm_yes_button.add_theme_color_override("font_hover_color", Color(1, 0.6, 0.55))
	confirm_yes_button.pressed.connect(confirm_delete)
	b.add_child(confirm_yes_button)
	v.add_child(b)
	dim.visible = false
	return dim


func _divider() -> Control:
	return MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(0, ci.size.y * 0.5), Vector2(ci.size.x, ci.size.y * 0.5), UIStyle.COLOR_BORDER_BRIGHT), Vector2(0, 12))


# ------------------------------------------------------------------ state

func _select(save_id: String) -> void:
	if _selected_save != save_id:
		Sfx.play_ui("ui_click")
	_selected_save = save_id
	_update_buttons()


func _info_for(save_id: String) -> Dictionary:
	for info: Dictionary in _saves:
		if String(info["save_id"]) == save_id:
			return info
	return {}


func _is_busy() -> bool:
	return _busy_time > 0.0


func _set_busy(on: bool, text: String = "") -> void:
	_busy_time = BUSY_TIMEOUT if on else 0.0
	if _status_label != null:
		_status_label.text = text
	_update_buttons()


func _update_buttons() -> void:
	if not _built:
		return
	var busy := _is_busy()
	continue_button.disabled = busy or _selected_save == ""
	delete_button.disabled = busy or _selected_save == ""
	new_button.disabled = busy
	if explore_button != null:
		explore_button.disabled = busy
	if explore_create_button != null:
		explore_create_button.disabled = busy
	begin_button.disabled = busy or name_edit.text.strip_edges() == ""
	back_button.disabled = busy


func _process(delta: float) -> void:
	if _busy_time > 0.0:
		_busy_time -= delta
		if _busy_time <= 0.0:
			_set_busy(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	if k == null:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit and k.keycode != KEY_ESCAPE:
		return
	var handled := true
	if k.keycode == KEY_F1 and not _confirm.visible:
		open_debug_menu()
	elif _confirm.visible:
		match k.keycode:
			KEY_ESCAPE:
				cancel_delete()
			KEY_ENTER, KEY_KP_ENTER:
				confirm_delete()
			_:
				handled = false
	elif is_create_view():
		match k.keycode:
			KEY_ESCAPE:
				if not _saves.is_empty():
					show_list_view()
			KEY_ENTER, KEY_KP_ENTER:
				begin_new_game()
			KEY_LEFT, KEY_RIGHT:
				var ids := _cards.keys()
				var i := ids.find(_selected_class)
				select_class(ids[posmod(i + (1 if k.keycode == KEY_RIGHT else -1), ids.size())])
			_:
				handled = false
	else:
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				continue_selected()
			KEY_DELETE:
				request_delete_selected()
			KEY_UP, KEY_DOWN:
				var ids := get_save_ids()
				if not ids.is_empty():
					var i := ids.find(_selected_save)
					var ni := clampi(i + (1 if k.keycode == KEY_DOWN else -1), 0, ids.size() - 1)
					select_save(ids[ni])
					_scroll.ensure_control_visible(_rows[ids[ni]])
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()

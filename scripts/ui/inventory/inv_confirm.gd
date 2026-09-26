class_name InvConfirm
extends Control
## Small modal confirmation box used by the item panels (e.g. "Sell Doom Grasp for 240 gold?").
## Covers its parent (FULL_RECT) with a dim backdrop that takes the mouse while it is shown, so
## nothing else can be clicked; Esc / the Cancel button cancel, Enter / the confirm button accept.
## Hidden (and mouse-transparent) otherwise. OWNER: ui-items.

signal confirmed()
signal cancelled()

var _frame: PanelContainer = null
var _title: Label = null
var _text: RichTextLabel = null
var _ok: Button = null
var _cancel: Button = null
var _on_confirm: Callable = Callable()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var f := InvStyle.make_frame("Confirm", Callable(), 420.0)
	_frame = f["frame"]
	_title = f["title"]
	center.add_child(_frame)
	var body: VBoxContainer = f["body"]
	body.add_theme_constant_override("separation", 14)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(390, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", UIStyle.FONT_NORMAL)
	_text.add_theme_color_override("default_color", UIStyle.COLOR_TEXT)
	body.add_child(_text)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	_cancel = InvStyle.make_action_button("Cancel")
	_cancel.custom_minimum_size.x = 120
	_cancel.pressed.connect(cancel)
	row.add_child(_cancel)
	_ok = InvStyle.make_action_button("Confirm", true)
	_ok.custom_minimum_size.x = 120
	_ok.pressed.connect(confirm)
	row.add_child(_ok)


## Show the box. `bbcode` is the message (BBCode), `on_confirm` runs when accepted.
func ask(title: String, bbcode: String, confirm_text: String, on_confirm: Callable) -> void:
	_title.text = title
	_text.text = "[center]%s[/center]" % bbcode
	_ok.text = confirm_text
	_on_confirm = on_confirm
	visible = true
	if is_inside_tree():
		Sfx.play_ui("ui_open")


func is_open() -> bool:
	return visible


func confirm() -> void:
	if not visible:
		return
	visible = false
	var cb := _on_confirm
	_on_confirm = Callable()
	if cb.is_valid():
		cb.call()
	confirmed.emit()


func cancel() -> void:
	if not visible:
		return
	visible = false
	_on_confirm = Callable()
	cancelled.emit()


## The confirm button (tests).
func get_confirm_button() -> Button:
	return _ok


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE or event.is_action_pressed("pause_menu"):
		cancel()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		confirm()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# Clicking the dim backdrop does nothing but swallows the click (modal).
	if event is InputEventMouseButton:
		accept_event()

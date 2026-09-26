class_name DeathScreen
extends Control
## 'You have died' overlay with XP-loss note and a Respawn in Town button (emits Events.respawn_requested).
## OWNER: UI tree/skills/menus module (wave 2). See docs/ARCHITECTURE.md §15, §16.
##
## Full screen and modal (UIRoot: root MOUSE_FILTER_STOP, Esc/toggles blocked). Fades in over the
## game view: a blood-red vignette with drifting ash, a skull, "YOU HAVE DIED", where it happened
## (GameState.current_area.name), the experience penalty with an XP bar showing the lost part, a
## reminder that the dungeon is kept, and "Respawn in Town" (Events.respawn_requested, once per
## opening; Enter/Space also respawn).
## Experience: context {"xp_lost": int} when the flow already applied the penalty; otherwise the
## penalty the respawn will apply (CharacterData.lose_xp_fraction(Balance.DEATH_XP_PENALTY):
## min(round(xp_to_next * 0.1), xp)); after respawning, character.last_xp_loss holds the amount.
## Standalone: `var d := DeathScreen.new(); add_child(d); d.on_opened({})`.

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")
const MenuTitle := preload("res://scripts/ui/menus/menu_title.gd")
const MenuCanvas := preload("res://scripts/ui/menus/menu_canvas.gd")

const BLOOD := Color(0.86, 0.12, 0.09)
const ASH_COUNT := 60

var respawn_button: Button

var _built := false
var _done := false
var _xp_lost := 0
var _xp_before := 0
var _xp_needed := 1
var _area_label: Label
var _xp_label: Label
var _xp_bar: Control
var _content: Control
var _t := 0.0
var _ash: Array = []           # [Vector2 (fractions), speed, size, phase]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MenuStyle.get_theme()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6660
	for i in ASH_COUNT:
		_ash.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.015, 0.05), rng.randf_range(1.0, 2.6), rng.randf() * TAU])


func _ready() -> void:
	_ensure_built()


## Called by UIRoot after the panel becomes visible.
func on_opened(context: Dictionary) -> void:
	_ensure_built()
	_done = false
	respawn_button.disabled = false
	respawn_button.text = "Respawn in Town"
	var c := GameState.character
	if c != null:
		_xp_needed = maxi(1, c.xp_to_next())
		if context.has("xp_lost"):
			_xp_lost = maxi(0, int(context["xp_lost"]))
			_xp_before = c.xp + _xp_lost
		else:
			_xp_lost = get_pending_xp_loss()
			_xp_before = c.xp
	else:
		_xp_lost = 0
		_xp_before = 0
		_xp_needed = 1
	var area := String(GameState.current_area.get("name", ""))
	_area_label.text = ("Slain in %s" % area) if area != "" else "Your journey ends here... for now."
	if c == null:
		_xp_label.text = ""
	elif c.is_max_level() or _xp_lost <= 0:
		_xp_label.text = "No experience lost"
	else:
		_xp_label.text = "Death costs %s experience (%d%% of this level)" % [MenuStyle.thousands(_xp_lost), int(roundf(Balance.DEATH_XP_PENALTY * 100.0))]
	_xp_bar.visible = c != null and not c.is_max_level()
	_t = 0.0
	modulate.a = 0.0
	_content.modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_content, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


## Called by UIRoot after the panel is hidden.
func on_closed() -> void:
	modulate.a = 1.0
	_content.modulate.a = 1.0


## The experience the respawn will take: min(round(xp_to_next * DEATH_XP_PENALTY), xp).
func get_pending_xp_loss() -> int:
	var c := GameState.character
	if c == null or c.is_max_level():
		return 0
	return mini(int(roundf(float(c.xp_to_next()) * Balance.DEATH_XP_PENALTY)), c.xp)


## The amount shown on the screen.
func get_shown_xp_loss() -> int:
	return _xp_lost


## Emit Events.respawn_requested (once per opening).
func respawn() -> void:
	if _done:
		return
	_done = true
	respawn_button.disabled = true
	respawn_button.text = "Respawning..."
	Events.respawn_requested.emit()


# ------------------------------------------------------------------ build

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var bg := MenuCanvas.new(_paint_backdrop, Vector2.ZERO, true)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := MenuStyle.vbox(12)
	v.custom_minimum_size = Vector2(760, 0)
	center.add_child(v)
	_content = v
	var skull := MenuCanvas.new(_paint_skull, Vector2(0, 130), true)
	v.add_child(skull)
	var title: Control = MenuTitle.new("YOU HAVE DIED", 96, BLOOD, Color(0.9, 0.05, 0.02, 0.95))
	title.set("pulse", 0.5)
	v.add_child(title)
	_area_label = MenuStyle.label("", UIStyle.FONT_LARGE, Color(0.9, 0.8, 0.72), 4)
	_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_area_label)
	v.add_child(MenuCanvas.new(func(ci: Control) -> void:
		MenuStyle.draw_divider(ci, Vector2(80, ci.size.y * 0.5), Vector2(ci.size.x - 80, ci.size.y * 0.5), Color(BLOOD, 0.8)), Vector2(0, 26)))
	_xp_label = MenuStyle.label("", UIStyle.FONT_NORMAL + 1, Color(0.95, 0.72, 0.6), 4)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_xp_label)
	_xp_bar = MenuCanvas.new(_paint_xp_bar, Vector2(0, 26))
	v.add_child(_xp_bar)
	var note := MenuStyle.label("Your dungeon remains: return through the portal in town to try again.", UIStyle.FONT_NORMAL, Color(0.78, 0.72, 0.66), 3)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	v.add_child(MenuStyle.spacer(Vector2(0, 16), false))
	var bc := CenterContainer.new()
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_button = MenuStyle.make_button("Respawn in Town", UIStyle.FONT_LARGE, true)
	respawn_button.custom_minimum_size = Vector2(320, 58)
	respawn_button.pressed.connect(respawn)
	bc.add_child(respawn_button)
	v.add_child(bc)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	if k != null and k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _content.modulate.a > 0.5:
		respawn()
		get_viewport().set_input_as_handled()


func _paint_backdrop(ci: Control) -> void:
	var s := ci.size
	ci.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.0, 0.0, 0.66))
	var pulse := 0.5 + 0.5 * sin(_t * 1.3)
	MenuStyle.draw_glow(ci, s * 0.5, s.x * 0.42, Color(0.55, 0.02, 0.0, 0.18 + 0.06 * pulse), true)
	ci.draw_texture_rect(MenuStyle.vignette_texture(), Rect2(-s * 0.1, s * 1.2), false, Color(0.35, 0.0, 0.0, 1.0))
	ci.draw_texture_rect(MenuStyle.vignette_texture(), Rect2(Vector2.ZERO, s), false, Color(0, 0, 0, 0.8))
	for a: Array in _ash:
		var p: Vector2 = a[0]
		var y := fposmod(p.y + _t * float(a[1]), 1.0)
		var x := p.x + 0.012 * sin(_t * 0.8 + float(a[3]))
		var fade := sin(y * PI)
		ci.draw_circle(Vector2(x * s.x, y * s.y), float(a[2]), Color(0.55, 0.45, 0.42, 0.35 * fade), true, -1.0, true)


func _paint_skull(ci: Control) -> void:
	var c := Vector2(ci.size.x * 0.5, ci.size.y * 0.55)
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	MenuStyle.draw_glow(ci, c, 120.0, Color(BLOOD, 0.3 + 0.12 * pulse))
	MenuStyle.draw_skull(ci, c, 96.0, Color(0.86, 0.8, 0.72, 0.95))


func _paint_xp_bar(ci: Control) -> void:
	var w := 460.0
	var r := Rect2(Vector2((ci.size.x - w) * 0.5, 6), Vector2(w, 12))
	ci.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.7))
	ci.draw_rect(r, Color(0.08, 0.06, 0.04))
	var before := clampf(float(_xp_before) / float(_xp_needed), 0.0, 1.0)
	var after := clampf(float(_xp_before - _xp_lost) / float(_xp_needed), 0.0, 1.0)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * after, r.size.y)), UIStyle.COLOR_XP)
	if before > after:
		var lost := Rect2(r.position + Vector2(r.size.x * after, 0), Vector2(r.size.x * (before - after), r.size.y))
		var pulse := 0.6 + 0.4 * sin(_t * 4.0)
		ci.draw_rect(lost, Color(BLOOD, 0.6 + 0.35 * pulse))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color(1, 1, 1, 0.1))
	ci.draw_rect(r.grow(2.0), Color(UIStyle.COLOR_BORDER, 0.8), false, 1.0)

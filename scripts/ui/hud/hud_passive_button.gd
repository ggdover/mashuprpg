extends Control
## "+N Passive Points (P)" indicator: a pulsing gold button shown while the character has unspent
## passive points; clicking it opens the passive tree (Events.panel_toggle_requested).
## Internal: preload("res://scripts/ui/hud/hud_passive_button.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

var hud: Control = null
var points: int = 0

var _hover := false
var _time := 0.0
var _pop := 0.0


func _init() -> void:
	name = "PassivePoints"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	size = Vector2(250, 40)
	visible = false
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func set_points(n: int, animate: bool = true) -> void:
	if n > points and animate:
		_pop = 1.0
	points = n
	visible = n > 0
	var f := HudStyle.bold_font()
	var key_w := HudStyle.text_width(f, Controls.label_for("toggle_passives"), 13) + 10.0
	var w := 40.0 + HudStyle.text_width(f, get_text(), 17) + 14.0 + key_w + 10.0
	size = Vector2(maxf(160.0, w), 40.0)
	queue_redraw()


func get_text() -> String:
	return "+%d Passive Point%s" % [points, "" if points == 1 else "s"]


func step(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_pop = maxf(0.0, _pop - delta * 2.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if hud != null and hud.has_method("open_passive_tree"):
			hud.call("open_passive_tree")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var pulse := 0.5 + 0.5 * sin(_time * 3.2)
	var glow := Color(HudStyle.GOLD, 0.18 + 0.22 * pulse + 0.4 * _pop)
	draw_style_box(HudStyle.box(Color(0, 0, 0, 0), glow, 4, 12), r.grow(4.0 + 3.0 * pulse))
	draw_style_box(HudStyle.box(Color(0.1, 0.075, 0.03, 0.94) if not _hover else Color(0.18, 0.13, 0.05, 0.96), HudStyle.GOLD.lerp(HudStyle.GOLD_BRIGHT, pulse * 0.6), 2, 10, 4), r)
	# Plus medallion.
	var c := Vector2(20.0, size.y * 0.5)
	draw_circle(c, 12.0, HudStyle.BRONZE_DARK)
	draw_circle(c, 10.0, HudStyle.GOLD.lerp(HudStyle.GOLD_BRIGHT, pulse))
	draw_rect(Rect2(c - Vector2(6, 1.5), Vector2(12, 3)), Color(0.25, 0.14, 0.02))
	draw_rect(Rect2(c - Vector2(1.5, 6), Vector2(3, 12)), Color(0.25, 0.14, 0.02))
	var f := HudStyle.bold_font()
	HudStyle.text(self, f, Vector2(40.0, size.y * 0.5 + 6.0), get_text(), 17, HudStyle.GOLD_BRIGHT, 4)
	var key := Controls.label_for("toggle_passives")
	var kw := HudStyle.text_width(f, key, 13) + 10.0
	var tag := Rect2(Vector2(size.x - kw - 8.0, size.y * 0.5 - 9.0), Vector2(kw, 18.0))
	draw_style_box(HudStyle.box(Color(0.02, 0.018, 0.016, 0.92), HudStyle.BRONZE, 1, 3), tag)
	HudStyle.text_centered(self, f, tag.get_center().x, tag.end.y - 4.0, key, 13, HudStyle.GOLD, 0)

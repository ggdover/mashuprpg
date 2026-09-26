extends Control
## Tiny custom-drawn control: `painter.call(self)` draws it (attribute bars, dividers, emblems...).
## Layout-only by default (MOUSE_FILTER_IGNORE). `animated` redraws every frame.
## Internal: preload("res://scripts/ui/menus/menu_canvas.gd").

var painter: Callable
var animated: bool = false:
	set(v):
		animated = v
		set_process(v)


func _init(p_painter: Callable = Callable(), min_size: Vector2 = Vector2.ZERO, p_animated: bool = false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	painter = p_painter
	custom_minimum_size = min_size
	animated = p_animated


func _ready() -> void:
	set_process(animated)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

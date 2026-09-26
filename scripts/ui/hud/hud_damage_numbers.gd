extends Control
## Floating combat text for Events.damage_number: a pool of Labels (created once, reused; the
## oldest is recycled when the pool is exhausted) projected from their 3D anchor every frame.
## Colours by kind (UIStyle.DAMAGE_COLORS; damage to the player red), crits larger with a pop,
## evade / block / immune as words, heal / mana / xp with a "+". New numbers near young ones are
## pushed up so they don't overlap; everything drifts up, slows and fades. Frozen while paused.
## Display only (MOUSE_FILTER_IGNORE).
## Internal: preload("res://scripts/ui/hud/hud_damage_numbers.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const POOL_START := 48
const POOL_MAX := 160
## Numbers smaller than this are not shown (DoT dust).
const MIN_AMOUNT := 0.5
## Screen-space rise speed (px/s) and its decay rate.
const RISE_SPEED := 95.0
const RISE_DAMP := 3.2
## Young numbers checked for overlap when a new one spawns.
const OVERLAP_SCAN := 40

class Num:
	var label: Label
	var pos3: Vector3
	var offset: Vector2
	var vel: Vector2
	var age: float = 0.0
	var life: float = 1.0
	var pop: float = 1.0
	var base_scale: float = 1.0
	var crit: bool = false
	var kind: String = ""
	var active: bool = false
	var screen: Vector2
	var half: Vector2

## Every Num ever created (the pool), active or not.
var pool: Array = []
## Active numbers, oldest first.
var active: Array = []
## Total numbers spawned (tests / stats).
var spawned_total: int = 0
## Smoothed CPU time of the per-frame update (microseconds; profiling / demos).
var frame_cost_usec: float = 0.0

var _settings: Dictionary = {}
var _camera_override: Camera3D = null


func _init() -> void:
	name = "DamageNumbers"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	for i in POOL_START:
		_create()


## Camera used for projection (default: the viewport's current camera).
func set_camera(cam: Camera3D) -> void:
	_camera_override = cam


func _camera() -> Camera3D:
	if _camera_override != null and is_instance_valid(_camera_override) and _camera_override.is_inside_tree():
		return _camera_override
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _create() -> Num:
	var n := Num.new()
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(l)
	n.label = l
	pool.append(n)
	return n


func get_active_count() -> int:
	return active.size()


func get_label_count() -> int:
	return pool.size()


## Show a number. kind: damage type, "player_hurt", "heal", "mana", "xp", "evade", "block",
## "immune". Returns false when it was skipped (tiny amount).
func spawn(pos: Vector3, amount: float, kind: String, is_crit: bool) -> bool:
	var word := ""
	match kind:
		"evade":
			word = "Evade"
		"block":
			word = "Block"
		"immune":
			word = "Immune"
	if word == "" and amount < MIN_AMOUNT:
		return false
	var n := _acquire()
	n.kind = kind
	n.crit = is_crit and word == ""
	n.pos3 = pos
	n.age = 0.0
	var txt := word
	if word == "":
		txt = HudStyle.compact(amount)
		match kind:
			"heal", "mana":
				txt = "+" + txt
			"xp":
				txt = "+%s XP" % txt
	if n.crit:
		txt += "!"
	var l := n.label
	l.text = txt
	l.label_settings = _label_settings(kind, n.crit)
	l.reset_size()
	l.size = l.get_minimum_size()
	l.pivot_offset = l.size * 0.5
	n.half = l.size * 0.5
	n.life = 0.95
	n.base_scale = 1.0
	n.pop = 1.35
	var rise := RISE_SPEED
	match kind:
		"xp":
			n.life = 1.5
			n.pop = 1.1
			rise = 55.0
		"heal", "mana":
			n.life = 1.1
			n.pop = 1.15
			rise = 70.0
		"evade", "block", "immune":
			n.life = 0.8
			n.pop = 1.2
			rise = 60.0
		"player_hurt":
			n.life = 0.9
			n.pop = 1.3
	if n.crit:
		n.life = 1.25
		n.pop = 2.1
		n.base_scale = 1.0
	n.vel = Vector2(randf_range(-22.0, 22.0), -rise)
	n.offset = Vector2(randf_range(-16.0, 16.0), -10.0)
	if kind == "player_hurt":
		n.offset.x += randf_range(-28.0, -8.0)
		n.vel.x = randf_range(-30.0, -10.0)
	var cam := _camera()
	n.screen = cam.unproject_position(pos) if cam != null else Vector2.ZERO
	_avoid_overlap(n)
	n.active = true
	l.visible = cam != null
	active.append(n)
	spawned_total += 1
	_place(n, cam)
	return true


func clear() -> void:
	for n in active:
		(n as Num).active = false
		(n as Num).label.visible = false
	active.clear()


func _acquire() -> Num:
	for n in pool:
		if not (n as Num).active:
			return n
	if pool.size() < POOL_MAX:
		return _create()
	# Pool exhausted: recycle the oldest active number.
	var oldest: Num = active.pop_front()
	oldest.active = false
	return oldest


## Push the new number above young numbers it would overlap (screen space, at spawn). Only the
## most recent OVERLAP_SCAN numbers are considered (the young ones are at the end of `active`).
func _avoid_overlap(n: Num) -> void:
	var last := active.size() - 1
	var first := maxi(0, active.size() - OVERLAP_SCAN)
	for _pass in 6:
		var moved := false
		var my := n.screen + n.offset
		for idx in range(last, first - 1, -1):
			var other: Num = active[idx]
			if other.age > 0.45:
				break
			var op := other.screen + other.offset
			var dx := absf(op.x - my.x)
			var dy := op.y - my.y
			var wlim := (other.half.x + n.half.x) * 0.9
			var hlim := (other.half.y + n.half.y) * 0.85
			if dx < wlim and absf(dy) < hlim:
				n.offset.y = op.y - n.screen.y - hlim - 1.0
				moved = true
				my = n.screen + n.offset
		if not moved:
			break


func _label_settings(kind: String, crit: bool) -> LabelSettings:
	var key := kind + ("|c" if crit else "")
	if _settings.has(key):
		return _settings[key]
	var ls := LabelSettings.new()
	ls.font = HudStyle.number_font()
	var col := UIStyle.damage_color(kind)
	var fs := 24
	var outline := 5
	match kind:
		"player_hurt":
			fs = 22
		"xp":
			fs = 18
			ls.font = HudStyle.bold_font()
		"heal", "mana":
			fs = 21
		"evade", "block", "immune":
			fs = 19
			ls.font = HudStyle.bold_font()
			col = Color(0.82, 0.84, 0.88)
	if crit:
		fs = int(fs * 1.4)
		outline = 7
		if kind == "physical":
			col = Color(1.0, 0.86, 0.32)
		else:
			col = col.lerp(Color(1, 1, 0.9), 0.25)
	ls.font_size = fs
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = Color(0.05, 0.02, 0.01, 0.95) if not crit else Color(0.25, 0.05, 0.0, 0.95)
	ls.shadow_size = 0
	_settings[key] = ls
	return ls


func _process(delta: float) -> void:
	if active.is_empty():
		return
	if get_tree().paused:
		return
	var t0 := Time.get_ticks_usec()
	_advance(delta)
	frame_cost_usec = lerpf(frame_cost_usec, float(Time.get_ticks_usec() - t0), 0.1)


func _advance(delta: float) -> void:
	var cam := _camera()
	var i := 0
	while i < active.size():
		var n: Num = active[i]
		n.age += delta
		if n.age >= n.life:
			n.active = false
			n.label.visible = false
			active.remove_at(i)
			continue
		n.offset += n.vel * delta
		n.vel *= exp(-RISE_DAMP * delta)
		_place(n, cam)
		i += 1


func _place(n: Num, cam: Camera3D) -> void:
	var l := n.label
	if cam == null or cam.is_position_behind(n.pos3):
		l.visible = false
		return
	n.screen = cam.unproject_position(n.pos3)
	var t := n.age
	var pop_t := 0.12 if not n.crit else 0.18
	var s := n.base_scale
	if t < pop_t:
		s *= lerpf(n.pop, 1.0, _ease_out(t / pop_t))
	var fade_start := n.life - 0.3
	var a := 1.0
	if t > fade_start:
		a = clampf(1.0 - (t - fade_start) / 0.3, 0.0, 1.0)
		s *= lerpf(0.85, 1.0, a)
	l.visible = true
	l.scale = Vector2(s, s)
	l.modulate.a = a
	l.position = n.screen + n.offset - n.half


func _ease_out(x: float) -> float:
	var y := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - y) * (1.0 - y)

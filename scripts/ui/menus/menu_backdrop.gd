extends Control
## Animated, atmospheric title-screen backdrop drawn entirely in code: night-sky gradient, a
## tiled starfield with twinkling stars, a haloed moon behind drifting clouds, three layers of
## moon-rimmed mountains (vertex-coloured meshes) with mouse parallax, a ruined castle with
## flickering windows, drifting ground fog, rising embers from a warm glow, the odd distant
## lightning flash, and a vignette. Layout-only (MOUSE_FILTER_IGNORE).
## Internal: preload("res://scripts/ui/menus/menu_backdrop.gd").

const MenuStyle := preload("res://scripts/ui/menus/menu_style.gd")

const SKY_TOP := Color(0.012, 0.016, 0.045)
const SKY_MID := Color(0.07, 0.05, 0.1)
const SKY_HORIZON := Color(0.3, 0.12, 0.1)
const MOON := Color(0.96, 0.93, 0.84)
const EMBER_COUNT := 80
const PROFILE_POINTS := 160
const MARGIN := 70.0

## Intensity of the warm glow and embers (0..1). The death screen reuses the backdrop dimmer.
var warmth: float = 1.0
## Animate (turn off for static screenshots in tests).
var animate: bool = true

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _embers: Array = []          # [pos, vel, life, max_life, size, phase]
var _profiles: Array = []        # 3 PackedFloat32Array (y as a fraction of height)
var _meshes: Array = []          # 3 ArrayMesh (rebuilt on resize)
var _mesh_size := Vector2.ZERO
var _twinkles: Array = []        # [Vector2 (fractions), phase, size]
var _windows: Array = []         # [Rect2 relative to castle base, phase]
var _par := Vector2.ZERO
var _flash := 0.0
var _next_flash := 6.0
var _flash_x := 0.3


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_rng.seed = 424242
	_profiles = [
		_make_profile(0.555, 0.15, 3.0, 11),
		_make_profile(0.665, 0.095, 5.0, 23),
		_make_profile(0.8, 0.05, 7.0, 37),
	]
	# The castle hill on the near layer.
	var near: PackedFloat32Array = _profiles[2]
	for i in near.size():
		var x := float(i) / float(near.size() - 1)
		near[i] -= 0.085 * exp(-pow((x - 0.2) / 0.075, 2.0))
	_profiles[2] = near
	for i in 34:
		_twinkles.append([Vector2(_rng.randf(), _rng.randf_range(0.02, 0.5)), _rng.randf() * TAU, _rng.randf_range(0.6, 1.4)])
	for i in 9:
		_windows.append([_rng.randi_range(0, 8), _rng.randf() * TAU])
	for i in EMBER_COUNT:
		_embers.append(_new_ember(true))
	_next_flash = _rng.randf_range(5.0, 9.0)


func _process(delta: float) -> void:
	if not animate or not is_visible_in_tree():
		return
	_t += delta
	var target := Vector2.ZERO
	if size.x > 0.0 and size.y > 0.0:
		target = ((get_local_mouse_position() / size) - Vector2(0.5, 0.5)) * 2.0
		target = target.clamp(Vector2(-1, -1), Vector2(1, 1))
	_par = _par.lerp(target, 1.0 - exp(-delta * 2.5))
	for e: Array in _embers:
		e[2] = float(e[2]) + delta
		var p: Vector2 = e[0]
		var v: Vector2 = e[1]
		p += (v + Vector2(sin(_t * 1.3 + float(e[5])) * 14.0, 0.0)) * delta
		e[0] = p
		if float(e[2]) >= float(e[3]) or p.y < -0.05:
			var fresh := _new_ember(false)
			for k in fresh.size():
				e[k] = fresh[k]
	_flash = maxf(0.0, _flash - delta * 2.4)
	_next_flash -= delta
	if _next_flash <= 0.0:
		_flash = 1.0
		_flash_x = _rng.randf_range(0.1, 0.9)
		_next_flash = _rng.randf_range(7.0, 14.0)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# ------------------------------------------------------------------ generation

func _make_profile(base: float, amp: float, freq: float, seed_add: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + seed_add
	var phases: Array[float] = []
	for k in 5:
		phases.append(r.randf() * TAU)
	var out := PackedFloat32Array()
	for i in PROFILE_POINTS:
		var x := float(i) / float(PROFILE_POINTS - 1)
		var h := 0.0
		h += 0.55 * (1.0 - absf(sin(x * PI * freq * 0.5 + phases[0])))
		h += 0.25 * (1.0 - absf(sin(x * PI * freq * 1.3 + phases[1])))
		h += 0.12 * sin(x * TAU * freq * 2.1 + phases[2])
		h += 0.06 * sin(x * TAU * freq * 5.3 + phases[3])
		h += 0.03 * r.randf_range(-1.0, 1.0)
		out.append(base - amp * h)
	return out


func _new_ember(anywhere: bool) -> Array:
	var x := _rng.randf_range(0.0, 1.0)
	var y := _rng.randf_range(0.35, 1.05) if anywhere else _rng.randf_range(1.0, 1.08)
	var sz := size if size.x > 0.0 else Vector2(1920, 1080)
	var life := _rng.randf_range(5.0, 11.0)
	return [Vector2(x * sz.x, y * sz.y), Vector2(_rng.randf_range(-12.0, 12.0), -_rng.randf_range(28.0, 75.0)),
		_rng.randf_range(0.0, life * 0.6) if anywhere else 0.0, life, _rng.randf_range(0.6, 1.5), _rng.randf() * TAU]


func _profile_at(layer: int, x_frac: float) -> float:
	var p: PackedFloat32Array = _profiles[layer]
	var f := clampf(x_frac, 0.0, 1.0) * float(p.size() - 1)
	var i := mini(int(f), p.size() - 2)
	return lerpf(p[i], p[i + 1], f - float(i))


func _rebuild_meshes() -> void:
	_mesh_size = size
	_meshes.clear()
	var rims := [Color(0.2, 0.17, 0.24), Color(0.13, 0.1, 0.13), Color(0.07, 0.05, 0.055)]
	var bodies := [Color(0.075, 0.06, 0.09), Color(0.045, 0.035, 0.045), Color(0.018, 0.013, 0.015)]
	for layer in 3:
		_meshes.append(_build_layer(_profiles[layer], rims[layer], bodies[layer]))


func _build_layer(profile: PackedFloat32Array, rim: Color, body: Color) -> ArrayMesh:
	var w := size.x + MARGIN * 2.0
	var bottom := size.y + MARGIN
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := profile.size()
	var deep := body.darkened(0.35)
	for i in n - 1:
		var x0 := -MARGIN + w * float(i) / float(n - 1)
		var x1 := -MARGIN + w * float(i + 1) / float(n - 1)
		var y0 := profile[i] * size.y
		var y1 := profile[i + 1] * size.y
		var m0 := y0 + 46.0
		var m1 := y1 + 46.0
		# Rim band (ridge -> 46 px below).
		verts.append_array([Vector2(x0, y0), Vector2(x1, y1), Vector2(x1, m1), Vector2(x0, y0), Vector2(x1, m1), Vector2(x0, m0)])
		cols.append_array([rim, rim, body, rim, body, body])
		# Body down to the bottom.
		verts.append_array([Vector2(x0, m0), Vector2(x1, m1), Vector2(x1, bottom), Vector2(x0, m0), Vector2(x1, bottom), Vector2(x0, bottom)])
		cols.append_array([body, body, deep, body, deep, deep])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if _mesh_size != size or _meshes.size() != 3:
		_rebuild_meshes()
	var w := size.x
	var h := size.y
	# Sky gradient.
	var hz := h * 0.62
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.38), Vector2(0, h * 0.38)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_MID, SKY_MID]))
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.38), Vector2(w, h * 0.38), Vector2(w, hz), Vector2(0, hz)]),
		PackedColorArray([SKY_MID, SKY_MID, SKY_HORIZON, SKY_HORIZON]))
	draw_rect(Rect2(0, hz, w, h - hz), SKY_HORIZON.darkened(0.5))
	# Stars (slight parallax).
	var star_off := _par * -4.0
	draw_texture_rect(MenuStyle.stars_texture(), Rect2(Vector2(-16, -16) + star_off, Vector2(w + 32, h * 0.66)), true, Color(1, 1, 1, 0.85))
	for tw: Array in _twinkles:
		var tp: Vector2 = tw[0]
		var a := 0.35 + 0.65 * pow(0.5 + 0.5 * sin(_t * 1.7 * float(tw[2]) + float(tw[1])), 3.0)
		var sp := Vector2(tp.x * w, tp.y * h) + star_off
		MenuStyle.draw_glow(self, sp, 7.0 * float(tw[2]), Color(0.85, 0.9, 1.0, 0.55 * a))
		draw_rect(Rect2(sp - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, a))
	# Moon with halo.
	var moon_c := Vector2(w * 0.8, h * 0.2) + _par * -8.0
	MenuStyle.draw_glow(self, moon_c, 520.0, Color(0.55, 0.5, 0.62, 0.16), true)
	MenuStyle.draw_glow(self, moon_c, 170.0, Color(0.95, 0.9, 0.8, 0.28))
	draw_circle(moon_c, 62.0, MOON, true, -1.0, true)
	draw_circle(moon_c + Vector2(-17, -12), 12.0, Color(0.78, 0.74, 0.68, 0.45), true, -1.0, true)
	draw_circle(moon_c + Vector2(20, 14), 17.0, Color(0.8, 0.76, 0.7, 0.38), true, -1.0, true)
	draw_circle(moon_c + Vector2(6, -30), 7.0, Color(0.78, 0.74, 0.68, 0.4), true, -1.0, true)
	draw_circle(moon_c + Vector2(-26, 22), 8.0, Color(0.8, 0.76, 0.7, 0.35), true, -1.0, true)
	# Lightning flash lights the sky behind the mountains.
	if _flash > 0.0:
		var fa := _flash * _flash
		MenuStyle.draw_glow(self, Vector2(_flash_x * w, h * 0.42), 700.0, Color(0.65, 0.7, 1.0, 0.22 * fa), true)
	# High clouds drifting across the moon.
	for i in 5:
		var speed := 9.0 + 4.0 * i
		var cw := 760.0 + 140.0 * (i % 3)
		var cx := fposmod(_t * speed + i * 530.0, w + cw * 2.0) - cw
		var cy := h * (0.12 + 0.07 * i)
		draw_texture_rect(MenuStyle.soft_texture(), Rect2(cx, cy, cw, 90.0 + 20.0 * (i % 2)), false, Color(0.03, 0.028, 0.045, 0.75))
		draw_texture_rect(MenuStyle.soft_texture(), Rect2(cx + cw * 0.2, cy - 8.0, cw * 0.6, 40.0), false, Color(0.35, 0.3, 0.4, 0.08))
	# Far and mid mountains.
	draw_mesh(_meshes[0], null, Transform2D(0.0, _par * -7.0))
	_draw_fog_band(h * 0.55, 0.05, 11.0, Color(0.45, 0.32, 0.4))
	draw_mesh(_meshes[1], null, Transform2D(0.0, _par * -14.0))
	_draw_fog_band(h * 0.66, 0.07, 17.0, Color(0.5, 0.3, 0.28))
	# Near hill with the castle.
	var near_off := _par * -24.0
	_draw_castle(Vector2(w * 0.2, _profile_at(2, (w * 0.2 + MARGIN) / (w + MARGIN * 2.0)) * h + 6.0) + near_off)
	draw_mesh(_meshes[2], null, Transform2D(0.0, near_off))
	_draw_fog_band(h * 0.82, 0.09, 24.0, Color(0.55, 0.32, 0.24))
	# Warm glow and embers.
	var pulse := 0.85 + 0.15 * sin(_t * 1.6) + 0.05 * sin(_t * 4.3)
	MenuStyle.draw_glow(self, Vector2(w * 0.5, h * 1.08), w * 0.55, Color(1.0, 0.35, 0.1, 0.2 * warmth * pulse), true)
	for e: Array in _embers:
		var life_t := float(e[2]) / float(e[3])
		var fade := sin(clampf(life_t, 0.0, 1.0) * PI)
		var flick := 0.7 + 0.3 * sin(_t * 9.0 + float(e[5]))
		var col := MenuStyle.EMBER.lerp(Color(1.0, 0.85, 0.4), 0.5 + 0.5 * sin(float(e[5])))
		var ep: Vector2 = e[0]
		ep += _par * -30.0 * float(e[4])
		MenuStyle.draw_glow(self, ep, 9.0 * float(e[4]), Color(col, 0.55 * fade * flick * warmth))
		draw_circle(ep, 1.3 * float(e[4]), Color(1.0, 0.9, 0.7, 0.9 * fade * warmth))
	# Vignette.
	draw_texture_rect(MenuStyle.vignette_texture(), Rect2(Vector2.ZERO, size), false)


func _draw_fog_band(y: float, alpha: float, speed: float, col: Color) -> void:
	var w := size.x
	for i in 4:
		var bw := w * 0.75
		var x := fposmod(_t * speed * (1.0 + 0.25 * i) + i * w * 0.37, w + bw) - bw * 0.5
		draw_texture_rect(MenuStyle.soft_texture(), Rect2(x - bw * 0.5, y - 60.0 + 18.0 * (i % 2), bw, 150.0), false, Color(col, alpha))


func _draw_castle(base: Vector2) -> void:
	var c := Color(0.022, 0.016, 0.02)
	var rim := Color(0.09, 0.07, 0.09)
	var s := size.y / 1080.0
	# Main keep, two towers, a broken wall and a spire.
	var parts := [
		Rect2(-60, -150, 120, 150), Rect2(-120, -110, 60, 110), Rect2(60, -128, 48, 128),
		Rect2(-190, -58, 70, 58), Rect2(108, -46, 82, 46), Rect2(-22, -200, 44, 52),
	]
	for r: Rect2 in parts:
		var rr := Rect2(base + r.position * s, r.size * s)
		draw_rect(rr, c)
		draw_line(rr.position, Vector2(rr.end.x, rr.position.y), rim, maxf(1.0, 2.0 * s))
	# Battlements.
	for tower: Rect2 in [parts[0], parts[1], parts[2], parts[3]]:
		var x := tower.position.x
		while x + 10.0 <= tower.end.x:
			draw_rect(Rect2(base + Vector2(x, tower.position.y - 12.0) * s, Vector2(10, 12) * s), c)
			x += 20.0
	# Spire and a broken tower tip.
	draw_colored_polygon(PackedVector2Array([base + Vector2(-26, -198) * s, base + Vector2(0, -262) * s, base + Vector2(26, -198) * s]), c)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-124, -108) * s, base + Vector2(-92, -150) * s, base + Vector2(-72, -122) * s, base + Vector2(-56, -108) * s]), c)
	# Windows with flickering light.
	var slots := [Vector2(-38, -120), Vector2(-8, -120), Vector2(22, -120), Vector2(-38, -80), Vector2(22, -80),
		Vector2(-98, -84), Vector2(76, -100), Vector2(-6, -178), Vector2(80, -60)]
	for i in slots.size():
		var ph: float = _windows[i % _windows.size()][1]
		var lit := 0.55 + 0.45 * sin(_t * (1.3 + 0.37 * i) + ph) * sin(_t * 3.1 + ph * 2.0)
		if i % 4 == 3:
			lit *= 0.35
		var wp: Vector2 = base + slots[i] * s
		var wc := Color(1.0, 0.62, 0.25, clampf(lit, 0.08, 1.0) * warmth)
		MenuStyle.draw_glow(self, wp + Vector2(3, 7) * s, 20.0 * s, Color(1.0, 0.5, 0.15, 0.35 * lit * warmth))
		draw_rect(Rect2(wp, Vector2(7, 14) * s), wc)

extends Control
## Minimap. Two modes: the round corner map (large = false) and the full-screen translucent
## overlay (large = true, Tab). Explored floor comes from World.get_minimap_data(): the cell and
## explored arrays are uploaded as R8 textures (no per-cell loops) and only re-uploaded when the
## world or its "version" changes; a canvas shader draws floor fill + wall outlines around the
## player (smooth scrolling). On top: markers (portal, waypoint, vendor, stash, chest), nearby
## enemies as rarity-coloured dots, a skull for a living boss and the player arrow.
## Indexing (World contract): cells[j * size.x + i] for cell (i, j), i along +X, j along +Z,
## origin = world position of the min corner of cell (0, 0) (the arena is centred on the world
## origin, so its origin is negative).
## Internal: preload("res://scripts/ui/hud/hud_minimap.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

const CORNER_RADIUS := 108.0
const CORNER_PPC := 7.0
const OVERLAY_PPC := 11.0
const OVERLAY_MAX_PPC := 24.0
## Seconds between get_minimap_data() polls (markers, version).
const POLL_INTERVAL := 0.2
## Enemies further than this from the player are not drawn (metres).
const ENEMY_RANGE := 42.0
## Enemies closer than this show even on unexplored ground (metres).
const NEAR_RANGE := 12.0

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D cells_tex : filter_nearest;
uniform sampler2D explored_tex : filter_nearest;
uniform vec2 grid_size = vec2(1.0);
uniform vec2 center_cell = vec2(0.0);
uniform float ppc = 6.0;
uniform vec2 rect_size = vec2(200.0);
uniform float circle = 1.0;
// The camera's yaw (radians): the map turns so screen-up matches the view.
uniform float map_rot = 0.0;
uniform vec4 floor_color : source_color = vec4(0.5, 0.45, 0.38, 0.4);
uniform vec4 edge_color : source_color = vec4(0.95, 0.85, 0.6, 0.9);
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);
uniform float edge_px = 1.6;

float is_floor(vec2 c) {
	if (c.x < 0.0 || c.y < 0.0 || c.x >= grid_size.x || c.y >= grid_size.y) return 0.0;
	return step(0.5 / 255.0, texelFetch(cells_tex, ivec2(c), 0).r);
}

float is_explored(vec2 c) {
	if (c.x < 0.0 || c.y < 0.0 || c.x >= grid_size.x || c.y >= grid_size.y) return 0.0;
	return step(0.5 / 255.0, texelFetch(explored_tex, ivec2(c), 0).r);
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 sd = (px - rect_size * 0.5) / ppc;
	float cr = cos(map_rot);
	float sr = sin(map_rot);
	vec2 cf = center_cell + vec2(sd.x * cr + sd.y * sr, -sd.x * sr + sd.y * cr);
	vec2 c = floor(cf);
	vec2 local = (cf - c) * ppc;
	vec4 col = bg_color;
	if (is_floor(c) * is_explored(c) > 0.5) {
		col = floor_color;
		float lo = edge_px;
		float hi = ppc - edge_px;
		float e = 0.0;
		if (is_floor(c + vec2(-1.0, 0.0)) < 0.5 && local.x < lo) e = 1.0;
		if (is_floor(c + vec2(1.0, 0.0)) < 0.5 && local.x > hi) e = 1.0;
		if (is_floor(c + vec2(0.0, -1.0)) < 0.5 && local.y < lo) e = 1.0;
		if (is_floor(c + vec2(0.0, 1.0)) < 0.5 && local.y > hi) e = 1.0;
		if (is_floor(c + vec2(-1.0, -1.0)) < 0.5 && local.x < lo && local.y < lo) e = 1.0;
		if (is_floor(c + vec2(1.0, -1.0)) < 0.5 && local.x > hi && local.y < lo) e = 1.0;
		if (is_floor(c + vec2(-1.0, 1.0)) < 0.5 && local.x < lo && local.y > hi) e = 1.0;
		if (is_floor(c + vec2(1.0, 1.0)) < 0.5 && local.x > hi && local.y > hi) e = 1.0;
		col = mix(col, edge_color, e);
	}
	float a = col.a;
	vec3 rgb = col.rgb;
	if (circle > 0.5) {
		float r = length(UV - vec2(0.5)) * 2.0;
		float aa = max(fwidth(r), 0.002);
		a *= 1.0 - smoothstep(1.0 - aa * 2.0, 1.0, r);
		rgb *= 1.0 - smoothstep(0.72, 1.0, r) * 0.4;
	}
	COLOR = vec4(rgb, a);
}
"""

static var _shader: Shader = null

var hud: Control = null
## Full-screen overlay mode.
var large: bool = false
## Pixels per grid cell.
var ppc: float = CORNER_PPC
## Last World.get_minimap_data() (may be {}).
var data: Dictionary = {}
## Texture (re)builds so far: +1 per explored upload (tests check it only grows on version change).
var rebuild_count: int = 0
## Player position in cell units (float).
var center_cell: Vector2 = Vector2.ZERO
var player_facing: Vector2 = Vector2(0, 1)
## The map's turn (radians, = the camera's yaw), so screen-up on the map is screen-up in the game.
var map_rot: float = 0.0

var _map: ColorRect
var _marks: Control
var _mat: ShaderMaterial
var _cells_tex: ImageTexture = null
var _explored_tex: ImageTexture = null
var _world_id := 0
var _version := -1
var _grid := Vector2i.ZERO
var _origin := Vector3.ZERO
var _tile := 2.0
var _poll := 0.0
var _player_pos := Vector3.ZERO
var _has_player := false
var _time := 0.0
var _is_town := false
var _last_center := Vector2(INF, INF)
var _last_ppc := -1.0


func _init(p_large: bool = false) -> void:
	large = p_large
	name = "MinimapOverlay" if large else "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	ppc = OVERLAY_PPC if large else CORNER_PPC
	if not large:
		size = Vector2.ONE * CORNER_RADIUS * 2.0
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("circle", 0.0 if large else 1.0)
	_mat.set_shader_parameter("edge_px", 2.2 if large else 1.5)
	if large:
		_mat.set_shader_parameter("floor_color", Color(0.62, 0.56, 0.45, 0.2))
		_mat.set_shader_parameter("edge_color", Color(0.98, 0.88, 0.62, 0.75))
		_mat.set_shader_parameter("bg_color", Color(0, 0, 0, 0))
	else:
		_mat.set_shader_parameter("floor_color", Color(0.55, 0.5, 0.42, 0.42))
		_mat.set_shader_parameter("edge_color", Color(0.98, 0.88, 0.62, 0.95))
		_mat.set_shader_parameter("bg_color", Color(0.02, 0.02, 0.025, 0.62))
	_map = ColorRect.new()
	_map.name = "Map"
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.material = _mat
	_map.visible = false
	add_child(_map)
	_marks = Control.new()
	_marks.name = "Marks"
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if _map == null:
		return
	_map.position = Vector2.ZERO
	_map.size = size
	_marks.position = Vector2.ZERO
	_marks.size = size
	_mat.set_shader_parameter("rect_size", size)


## Forget the current world (area change): the next step() rebuilds everything.
func reset() -> void:
	_world_id = 0
	_version = -1
	data = {}
	_map.visible = false
	_poll = 0.0


## Read the world's minimap data and upload what changed: the cell texture when the world (or
## its size) changed, the explored texture when "version" changed (or when forced).
func refresh_data(world: Node, force: bool = false) -> void:
	if world == null or not is_instance_valid(world) or not world.has_method("get_minimap_data"):
		if _world_id != 0:
			reset()
		return
	var d: Dictionary = world.call("get_minimap_data")
	if d.is_empty() or not d.has("size"):
		return
	data = d
	var wid := world.get_instance_id()
	var sz: Vector2i = d["size"]
	var ver := int(d.get("version", -2))
	_origin = d.get("origin", Vector3.ZERO)
	_tile = float(d.get("tile_size", 2.0))
	_is_town = world.has_method("is_town") and bool(world.call("is_town"))
	if wid != _world_id or sz != _grid or _cells_tex == null:
		_world_id = wid
		_grid = sz
		_version = -1
		var cells: PackedByteArray = d.get("cells", PackedByteArray())
		if cells.size() != sz.x * sz.y or sz.x <= 0 or sz.y <= 0:
			push_warning("HUD minimap: bad cell data (%d bytes for %s)" % [cells.size(), sz])
			_map.visible = false
			return
		_cells_tex = ImageTexture.create_from_image(Image.create_from_data(sz.x, sz.y, false, Image.FORMAT_R8, cells))
		_explored_tex = null
		_mat.set_shader_parameter("cells_tex", _cells_tex)
		_mat.set_shader_parameter("grid_size", Vector2(sz))
	if ver != _version or _explored_tex == null or force:
		_version = ver
		var explored: PackedByteArray = d.get("explored", PackedByteArray())
		if explored.size() != sz.x * sz.y:
			explored = PackedByteArray()
			explored.resize(sz.x * sz.y)
		var img := Image.create_from_data(sz.x, sz.y, false, Image.FORMAT_R8, explored)
		if _explored_tex == null:
			_explored_tex = ImageTexture.create_from_image(img)
			_mat.set_shader_parameter("explored_tex", _explored_tex)
		else:
			_explored_tex.update(img)
		rebuild_count += 1
	_map.visible = true


## Per-frame update: poll (throttled), follow the player.
func step(delta: float, world: Node, player: Node3D) -> void:
	_time += delta
	_poll -= delta
	if _poll <= 0.0 or world == null or not is_instance_valid(world) or world.get_instance_id() != _world_id:
		_poll = POLL_INTERVAL
		refresh_data(world)
	_has_player = player != null and is_instance_valid(player)
	if _has_player:
		_player_pos = player.call("get_visual_position") if player.has_method("get_visual_position") else player.global_position
		center_cell = world_to_map(_player_pos)
		var yaw := player.rotation.y
		player_facing = Vector2(sin(yaw), cos(yaw))
		var rig: Variant = player.get("camera_rig")
		var mr := deg_to_rad(float(rig.yaw_deg)) if rig != null and is_instance_valid(rig) else 0.0
		if mr != map_rot:
			map_rot = mr
			_mat.set_shader_parameter("map_rot", map_rot)
	if large and _grid.x > 0 and _grid.y > 0:
		# The overlay scales so small maps (town) fill a good part of the screen.
		var want := clampf(minf(size.x, size.y) * 0.8 / float(maxi(_grid.x, _grid.y)), OVERLAY_PPC, OVERLAY_MAX_PPC)
		if want != ppc:
			ppc = want
			_mat.set_shader_parameter("edge_px", clampf(ppc * 0.16, 2.0, 3.5))
	if center_cell != _last_center or ppc != _last_ppc:
		_last_center = center_cell
		_last_ppc = ppc
		_mat.set_shader_parameter("center_cell", center_cell)
		_mat.set_shader_parameter("ppc", ppc)
	_marks.queue_redraw()


# ------------------------------------------------------------------ indexing helpers

## World position -> map position in (float) cell units.
func world_to_map(pos: Vector3) -> Vector2:
	return Vector2((pos.x - _origin.x) / _tile, (pos.z - _origin.z) / _tile)


## World position -> grid cell (i, j).
func world_to_cell(pos: Vector3) -> Vector2i:
	var m := world_to_map(pos)
	return Vector2i(floori(m.x), floori(m.y))


## Index into data.cells / data.explored for a cell (-1 when outside).
func cell_index(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid.x or cell.y >= _grid.y:
		return -1
	return cell.y * _grid.x + cell.x


func is_floor_at(pos: Vector3) -> bool:
	var i := cell_index(world_to_cell(pos))
	var cells: PackedByteArray = data.get("cells", PackedByteArray())
	return i >= 0 and i < cells.size() and cells[i] != 0


func is_explored_at(pos: Vector3) -> bool:
	var i := cell_index(world_to_cell(pos))
	var ex: PackedByteArray = data.get("explored", PackedByteArray())
	return i >= 0 and i < ex.size() and ex[i] != 0


## Screen position (local to this control) of a world position (the map turns with the camera).
func world_to_screen(pos: Vector3) -> Vector2:
	return size * 0.5 + (world_to_map(pos) - center_cell).rotated(map_rot) * ppc


func get_grid_size() -> Vector2i:
	return _grid


func get_origin() -> Vector3:
	return _origin


func get_version() -> int:
	return _version


# ------------------------------------------------------------------ drawing

func _in_view(p: Vector2, margin: float) -> bool:
	if large:
		return Rect2(Vector2.ZERO, size).grow(-margin).has_point(p)
	return p.distance_to(size * 0.5) <= CORNER_RADIUS - margin


func _draw() -> void:
	if large:
		# Soft darkening behind the overlay so the lines read over bright floors.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.22))
		return
	var c := size * 0.5
	draw_circle(c + Vector2(0, 4), CORNER_RADIUS + 9.0, Color(0, 0, 0, 0.45))
	draw_circle(c, CORNER_RADIUS + 1.0, Color(0.02, 0.02, 0.025, 0.55))


func _draw_marks() -> void:
	var ci := _marks
	if not _map.visible:
		if not large:
			_draw_ring(ci)
		return
	var s := 1.4 if large else 1.0
	# Markers (only where explored, except in town). Portals / waypoints outside the round map
	# are pinned to its rim so the way back is always visible.
	for m in data.get("markers", []):
		var pos: Vector3 = m.get("position", Vector3.ZERO)
		var kind := String(m.get("kind", ""))
		if not _is_town and not is_explored_at(pos):
			continue
		var p := world_to_screen(pos)
		if _in_view(p, 6.0):
			HudStyle.draw_marker(ci, kind, p, 5.5 * s)
		elif not large and (kind == "portal" or kind == "waypoint"):
			var c := size * 0.5
			var edge := c + (p - c).normalized() * (CORNER_RADIUS - 11.0)
			HudStyle.draw_marker(ci, kind, edge, 4.2)
	# Enemies (awake, near, on explored ground) and bosses.
	if _has_player and is_inside_tree():
		for n in get_tree().get_nodes_in_group("team_1"):
			var a := n as Actor
			if a == null or a.dead or not a.is_visible_in_tree():
				continue
			var gp := a.global_position
			var dist := Vector2(gp.x - _player_pos.x, gp.z - _player_pos.z).length()
			var boss := a.is_boss_actor or a.is_in_group("boss")
			if dist > ENEMY_RANGE and not (boss and large):
				continue
			if dist > NEAR_RANGE and not is_explored_at(gp):
				continue
			var p2 := world_to_screen(gp)
			if not _in_view(p2, 4.0):
				continue
			if boss:
				HudStyle.draw_skull(ci, p2, 7.5 * s, Color(1.0, 0.45, 0.2))
				continue
			var rar := int(a.get("rarity")) if a.get("rarity") != null else 0
			var col := Color(0.95, 0.2, 0.15)
			var r := 3.2
			if rar == 1:
				col = Color(0.45, 0.6, 1.0)
				r = 3.8
			elif rar >= 2:
				col = Color(1.0, 0.88, 0.3)
				r = 4.8
			ci.draw_circle(p2, (r + 1.2) * s, Color(0, 0, 0, 0.75))
			ci.draw_circle(p2, r * s, col)
	# Player arrow.
	if _has_player:
		var pc := world_to_screen(_player_pos)
		var d := player_facing.rotated(map_rot).normalized() if player_facing.length() > 0.01 else Vector2(0, 1).rotated(map_rot)
		var side := Vector2(-d.y, d.x)
		var L := 9.0 * s
		var tri := PackedVector2Array([pc + d * L, pc - d * L * 0.6 + side * L * 0.65, pc - d * L * 0.25, pc - d * L * 0.6 - side * L * 0.65])
		var shadow := PackedVector2Array()
		for p3 in tri:
			shadow.append(p3 + (p3 - pc).normalized() * 1.6)
		ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.85))
		ci.draw_colored_polygon(tri, Color(1.0, 0.95, 0.8))
		ci.draw_circle(pc, 2.2 * s, HudStyle.GOLD)
	if not large:
		_draw_ring(ci)


func _draw_ring(ci: Control) -> void:
	var c := size * 0.5
	ci.draw_arc(c, CORNER_RADIUS + 3.0, 0.0, TAU, 96, HudStyle.BRONZE_DARK, 8.0, true)
	ci.draw_arc(c, CORNER_RADIUS + 3.0, 0.0, TAU, 96, HudStyle.BRONZE, 4.0, true)
	ci.draw_arc(c, CORNER_RADIUS + 1.5, PI * 1.05, PI * 1.75, 32, Color(HudStyle.BRONZE_LIGHT, 0.7), 1.3, true)
	ci.draw_arc(c, CORNER_RADIUS - 0.5, 0.0, TAU, 96, Color(0, 0, 0, 0.8), 1.5, true)
	# Rivets on the diagonals (kept off the axes so rim-pinned markers stay readable).
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var p := c + Vector2(cos(a), sin(a)) * (CORNER_RADIUS + 3.0)
		ci.draw_circle(p, 4.2, HudStyle.BRONZE_DARK)
		ci.draw_circle(p - Vector2(0.7, 0.7), 2.4, HudStyle.BRONZE_LIGHT)

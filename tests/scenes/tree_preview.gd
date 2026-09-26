extends Node2D
## Visual check of the passive tree (docs/ARCHITECTURE.md §10 / §18). Draws the whole tree fitted
## to the window: links (orbit links as arcs), nodes coloured by region (attributes neutral),
## notables/keystones/starts larger with names, plus a demo allocation per class (gold), the
## nodes TreeDB.get_refundable marks as refundable (red dot) and a find_path preview (light) to a
## keystone. Prints summary stats. With a real window
## (GTEST_WINDOWED=1) it saves screenshots of the full tree and zoomed regions to
## docs/screenshots/tree/ and quits; headless it prints the summary and quits.
##
##   tools/gtest.sh tree res://tests/scenes/tree_preview.tscn
##   GTEST_WINDOWED=1 tools/gtest.sh tree-shots res://tests/scenes/tree_preview.tscn

const BG := Color(0.045, 0.04, 0.035)
const LINK := Color(0.36, 0.32, 0.25)
const LINK_ALLOC := Color(0.96, 0.8, 0.32)
const LINK_PREVIEW := Color(0.75, 0.9, 1.0, 0.8)
const ATTR_FILL := Color(0.6, 0.57, 0.5)
const RING_NOTABLE := Color(0.95, 0.78, 0.4)
const REFUNDABLE := Color(0.95, 0.32, 0.26)
const TEXT := Color(0.93, 0.88, 0.76)
## Demo builds: class -> [allocated targets..., preview target] (node names or stable keys).
## The warrior's extra keys close a cycle through the start (all of it refundable except the
## nodes that hold branches).
const DEMO := {
	"warrior": ["Brute Force", "path[start:warrior>ring_inner:12]:1", "path[start:warrior>ring_inner:12]:0",
		"Heart of the Oak", "Iron Skin", "Resolute Technique"],
	"ranger": ["Deadeye", "Farshot", "Hunter's Rhythm", "Point Blank"],
	"sorcerer": ["Arcane Potency", "Elemental Warding", "Crystalline Aegis", "Mind over Matter"],
}
## Views: name -> [centre (tree units), a group id (centred on that cluster) or null = fit,
## tree units visible vertically]
const VIEWS := [
	["full", null, 0.0],
	["centre", Vector2(0, 0), 1700.0],
	["int", Vector2(0, -1350), 1500.0],
	["dex_int", Vector2(1150, -700), 1500.0],
	["dex", Vector2(1200, 650), 1500.0],
	["str_dex", Vector2(0, 1400), 1500.0],
	["str", Vector2(-1200, 650), 1500.0],
	["int_str", Vector2(-1150, -700), 1500.0],
	["spur_toxic_bloom", "toxic_bloom", 700.0],
	["spur_vampiric_frenzy", "vampiric_frenzy", 700.0],
	["spur_crimson_covenant", "crimson_covenant", 700.0],
]

var _centre := Vector2.ZERO
var _scale := 0.2
var _view_name := "full"
var _allocated := {}      # id -> true
var _alloc_links := {}    # Vector2i -> true
var _preview := {}        # id -> true
var _refundable := {}     # id -> true
var _preview_links := {}  # Vector2i -> true
var _font: Font


func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(get_tree().quit)
	_font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(BG)
	if not TreeDB.is_loaded():
		push_warning("tree_preview: TreeDB has no data")
		get_tree().quit(1)
		return
	_build_demo()
	_print_summary()
	_set_view(VIEWS[0])
	if DisplayServer.get_name() == "headless":
		print("[tree_preview] headless: no screenshots (run with GTEST_WINDOWED=1)")
		get_tree().quit()
		return
	_capture_all()


func _capture_all() -> void:
	var dir := OS.get_environment("GTEST_REPO")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://")
	dir = dir.path_join("docs/screenshots/tree")
	DirAccess.make_dir_recursive_absolute(dir)
	for v in VIEWS:
		_set_view(v)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := dir.path_join("tree_%s.png" % v[0])
		img.save_png(path)
		print("[tree_preview] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	get_tree().quit()


func _set_view(v: Array) -> void:
	_view_name = v[0]
	var size := get_viewport_rect().size
	if v[1] == null:
		var b := TreeDB.get_bounds().grow(90.0)
		_centre = b.get_center()
		_scale = minf(size.x / b.size.x, size.y / b.size.y)
	elif v[1] is String:
		var sum := Vector2.ZERO
		var count := 0
		for id in TreeDB.nodes:
			if TreeDB.nodes[id]["group"] == v[1]:
				sum += TreeDB.get_node_position(id)
				count += 1
		_centre = sum / maxi(1, count)
		_scale = size.y / float(v[2])
	else:
		_centre = v[1]
		_scale = size.y / float(v[2])
	queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return (p - _centre) * _scale + get_viewport_rect().size * 0.5


func _id_by_name(node_name: String) -> int:
	var by_key := TreeDB.get_id_by_key(node_name)
	if by_key >= 0:
		return by_key
	for id in TreeDB.nodes:
		if TreeDB.nodes[id]["name"] == node_name:
			return id
	push_warning("tree_preview: no node named %s" % node_name)
	return -1


func _build_demo() -> void:
	for cls in DEMO:
		var names: Array = DEMO[cls]
		var alloc: Array[int] = []
		for i in names.size() - 1:
			var t := _id_by_name(names[i])
			if t >= 0:
				alloc.append_array(TreeDB.find_path(alloc, t, cls))
		for id in alloc:
			_allocated[id] = true
		var refundable := TreeDB.get_refundable(alloc, cls)
		for id in refundable:
			_refundable[id] = true
		var start := TreeDB.get_start_node(cls)
		_allocated[start] = true
		var preview := TreeDB.find_path(alloc, _id_by_name(names[-1]), cls)
		for id in preview:
			_preview[id] = true
		var refund_names: PackedStringArray = []
		for id in refundable:
			refund_names.append(TreeDB.get_passive(id).get("name", "?"))
		print("[tree_preview] %s demo: %d points allocated, %d more to %s; refundable now (%d): %s" % [
			cls, alloc.size(), preview.size(), names[-1], refundable.size(), ", ".join(refund_names)])
	for link in TreeDB.get_links():
		if _allocated.has(link.x) and _allocated.has(link.y):
			_alloc_links[link] = true
		elif (_preview.has(link.x) or _allocated.has(link.x)) and (_preview.has(link.y) or _allocated.has(link.y)):
			_preview_links[link] = true


func _print_summary() -> void:
	var by_type := {}
	var by_region := {}
	var stat_nodes := {}
	var stat_total := {}
	for id in TreeDB.nodes:
		var n: Dictionary = TreeDB.nodes[id]
		by_type[n["type"]] = int(by_type.get(n["type"], 0)) + 1
		by_region[n["region"]] = int(by_region.get(n["region"], 0)) + 1
		for m in n["mods"]:
			var key := "%s %s" % [m["stat"], m["op"]]
			stat_nodes[key] = int(stat_nodes.get(key, 0)) + 1
			stat_total[key] = float(stat_total.get(key, 0.0)) + float(m["value"])
	print("[tree_preview] nodes %d, links %d" % [TreeDB.nodes.size(), TreeDB.get_links().size()])
	var t_parts: PackedStringArray = []
	for t in TreeDB.NODE_TYPES:
		t_parts.append("%s %d" % [t, by_type.get(t, 0)])
	print("[tree_preview] by type: ", ", ".join(t_parts))
	var r_parts: PackedStringArray = []
	for r in TreeDB.REGIONS:
		r_parts.append("%s %d" % [r, by_region.get(r, 0)])
	print("[tree_preview] by region: ", ", ".join(r_parts))
	var keys: Array = stat_nodes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return stat_nodes[a] > stat_nodes[b] or (stat_nodes[a] == stat_nodes[b] and a < b))
	var s_parts: PackedStringArray = []
	for i in mini(18, keys.size()):
		s_parts.append("%s x%d (sum %s)" % [keys[i], stat_nodes[keys[i]], StatDefs.fmt(stat_total[keys[i]])])
	print("[tree_preview] top stats (%d distinct): %s" % [keys.size(), "; ".join(s_parts)])
	for r in TreeDB.REGIONS:
		var names: PackedStringArray = []
		for id in TreeDB.nodes:
			var n: Dictionary = TreeDB.nodes[id]
			if n["region"] == r and n["type"] in ["notable", "keystone"]:
				names.append(("[%s]" % n["name"]) if n["type"] == "keystone" else n["name"])
		print("[tree_preview]   %-8s %s" % [r, ", ".join(names)])
	for cls in ["warrior", "ranger", "sorcerer"]:
		var parts: PackedStringArray = []
		for k in TreeDB.get_ids_by_type("keystone"):
			parts.append("%s %d" % [TreeDB.nodes[k]["name"], TreeDB.find_path([], k, cls).size()])
		print("[tree_preview] %s -> keystones: %s" % [cls, ", ".join(parts)])


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var view := Rect2(_centre - size * 0.5 / _scale, size / _scale)
	var w := maxf(1.0, 5.0 * _scale)
	# Links first.
	for link in TreeDB.get_links():
		var col := LINK
		var width := w
		if _alloc_links.has(link):
			col = LINK_ALLOC
			width = w * 1.8
		elif _preview_links.has(link):
			col = LINK_PREVIEW
			width = w * 1.4
		_draw_link(link, col, width)
	# Nodes.
	var visible := TreeDB.get_nodes_in_rect(view, 80.0)
	for id in visible:
		_draw_node(id)
	# Labels on top.
	var fs := clampi(int(26.0 * _scale), 9, 20)
	for id in visible:
		var n: Dictionary = TreeDB.nodes[id]
		if n["type"] in ["notable", "keystone", "start"]:
			var p := _to_screen(Vector2(n["x"], n["y"]))
			var r := TreeDB.get_node_radius(id) * _scale
			var size_mult := 1.15 if n["type"] != "notable" else 1.0
			_label(n["name"], p + Vector2(0, r + 3.0 + fs), int(fs * size_mult), TEXT)
	_draw_legend(size)


func _draw_link(link: Vector2i, col: Color, width: float) -> void:
	var arc := TreeDB.get_link_arc(link.x, link.y)
	if arc.is_empty():
		draw_line(_to_screen(TreeDB.get_node_position(link.x)), _to_screen(TreeDB.get_node_position(link.y)), col, width, true)
		return
	var r: float = arc["radius"] * _scale
	var sweep: float = absf(arc["end_angle"] - arc["start_angle"])
	var points := clampi(int(sweep * r / 4.0), 6, 96)
	draw_arc(_to_screen(arc["centre"]), r, arc["start_angle"], arc["end_angle"], points, col, width, true)


func _draw_node(id: int) -> void:
	var n: Dictionary = TreeDB.nodes[id]
	var t: String = n["type"]
	var p := _to_screen(Vector2(n["x"], n["y"]))
	var r := TreeDB.get_node_radius(id) * _scale
	var region_col: Color = TreeDB.REGION_COLORS.get(n["region"], TEXT)
	var alloc := _allocated.has(id)
	var fill := region_col.darkened(0.12)
	if t == "attribute":
		fill = ATTR_FILL.darkened(0.2)
	elif t == "start":
		fill = ClassDefs.get_class_def(n.get("class", "")).get("color", TEXT)
	if alloc:
		fill = fill.lightened(0.35)
	var ring_w := maxf(1.0, 4.0 * _scale)
	match t:
		"keystone":
			draw_circle(p, r + ring_w * 2.0, RING_NOTABLE.darkened(0.3))
			draw_circle(p, r + ring_w * 0.5, BG)
			draw_circle(p, r - ring_w * 0.5, fill)
			draw_arc(p, r * 0.55, 0, TAU, 24, RING_NOTABLE, ring_w, true)
		"notable":
			draw_circle(p, r + ring_w, RING_NOTABLE if alloc else RING_NOTABLE.darkened(0.35))
			draw_circle(p, r - ring_w * 0.3, fill)
		"start":
			draw_circle(p, r + ring_w * 1.5, RING_NOTABLE)
			draw_circle(p, r, fill)
			draw_circle(p, r * 0.45, BG.lightened(0.1))
		_:
			if alloc:
				draw_circle(p, r + ring_w, LINK_ALLOC)
			elif _preview.has(id):
				draw_circle(p, r + ring_w, LINK_PREVIEW)
			draw_circle(p, r, fill)
	if _refundable.has(id):
		draw_circle(p, maxf(2.0, r * 0.38), REFUNDABLE)


func _label(text: String, pos: Vector2, fs: int, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := pos - Vector2(sz.x * 0.5, 0)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, BG)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_legend(size: Vector2) -> void:
	var x := 16.0
	var y := 26.0
	if _view_name != "full":
		_legend_text("Passive tree — view: %s   (%d nodes)" % [_view_name, TreeDB.nodes.size()], Vector2(x, y), 18)
		return
	draw_rect(Rect2(6, 6, 300, 252), Color(BG, 0.85))
	draw_rect(Rect2(6, 6, 300, 252), LINK, false, 1.0)
	_legend_text("Passive tree — view: %s   (%d nodes)" % [_view_name, TreeDB.nodes.size()], Vector2(x, y), 18)
	y += 26.0
	for r in TreeDB.REGIONS:
		draw_circle(Vector2(x + 7, y - 6), 7, TreeDB.REGION_COLORS[r])
		_legend_text(TreeDB.REGION_NAMES[r], Vector2(x + 20, y), 14)
		y += 20.0
	draw_circle(Vector2(x + 7, y - 6), 6, ATTR_FILL)
	_legend_text("+10 attribute", Vector2(x + 20, y), 14)
	y += 20.0
	draw_line(Vector2(x, y - 6), Vector2(x + 14, y - 6), LINK_ALLOC, 3)
	_legend_text("demo allocation", Vector2(x + 20, y), 14)
	y += 20.0
	draw_line(Vector2(x, y - 6), Vector2(x + 14, y - 6), LINK_PREVIEW, 3)
	_legend_text("find_path preview", Vector2(x + 20, y), 14)
	y += 20.0
	draw_circle(Vector2(x + 7, y - 6), 4, REFUNDABLE)
	_legend_text("refundable (get_refundable)", Vector2(x + 20, y), 14)


func _legend_text(text: String, pos: Vector2, fs: int) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, BG)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)

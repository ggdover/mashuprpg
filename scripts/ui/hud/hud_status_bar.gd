extends Control
## A row of status icons for an actor: buffs (skill icon, gold border) then ailments (procedural
## glyph, red border) with a remaining-time bar (+ seconds for the player row), poison stacks,
## blinking in the last 2 seconds. The player row (interactive = true) shows a tooltip for the
## hovered icon; compact rows (nameplate / boss bar) are display only.
## Internal: preload("res://scripts/ui/hud/hud_status_bar.gd").

const HudStyle := preload("res://scripts/ui/hud/hud_style.gd")

var hud: Control = null
var icon_size: float = 40.0
var gap: float = 6.0
## Show the seconds under each icon and take the mouse for tooltips.
var interactive: bool = true
## Maximum icons shown.
var max_icons: int = 14

## Entries (rebuilt by update_from): {"key", "kind": "buff"|"ailment", "id", "name", "icon",
## "time_left", "duration", "stacks", "color", "mods", "data"}.
var entries: Array = []

var _hover_index := -1
var _time := 0.0
var _signature := ""
var _had_entries := false


func _init(p_interactive: bool = true, p_icon_size: float = 40.0) -> void:
	interactive = p_interactive
	icon_size = p_icon_size
	gap = 6.0 if p_icon_size >= 32.0 else 4.0
	name = "StatusBar"
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2.ZERO
	mouse_exited.connect(func() -> void:
		_hover_index = -1
		if hud != null and hud.has_method("hide_tooltip_for"):
			hud.call("hide_tooltip_for", self))


## Refresh from the actor's buffs and ailments (every frame). The entry list is only rebuilt
## when the set of buffs / ailments changes; otherwise timers and stacks update in place.
func update_from(actor: Actor, delta: float) -> void:
	_time += delta
	var alive := actor != null and is_instance_valid(actor) and not actor.dead
	var sig := ""
	if alive:
		for id in actor.buffs:
			sig += "b:" + String(id) + ","
		for kind in HudStyle.AILMENT_ORDER:
			if actor.ailments.has(kind):
				sig += kind + ","
	if sig != _signature:
		_signature = sig
		_rebuild(actor if alive else null)
		_hover_index = -1
		if interactive and hud != null and hud.has_method("hide_tooltip_for"):
			hud.call("hide_tooltip_for", self)
	elif alive:
		for e in entries:
			var src: Dictionary = actor.buffs.get(e["id"], {}) if e["kind"] == "buff" else actor.ailments.get(e["id"], {})
			e["time_left"] = float(src.get("time_left", INF if e["kind"] == "buff" else 0.0))
			e["duration"] = float(src.get("duration", 0.0))
			if e["id"] == "poison":
				e["stacks"] = (src.get("stacks", []) as Array).size()
			if e["kind"] == "ailment":
				e["data"] = src
			else:
				e["mods"] = src.get("mods", [])
	var n := entries.size()
	if n > 0 or _had_entries:
		queue_redraw()
	_had_entries = n > 0
	if interactive and _hover_index >= 0 and _hover_index < entries.size() and int(_time * 4.0) != int((_time - delta) * 4.0):
		_show_tooltip(_hover_index)


func _rebuild(actor: Actor) -> void:
	var list: Array = []
	if actor != null:
		for id in actor.buffs:
			var b: Dictionary = actor.buffs[id]
			var icon_id := String(b.get("icon", ""))
			list.append({"key": "b:" + String(id), "kind": "buff", "id": String(id), "name": String(b.get("name", id)),
				"icon": Assets.skill_icon(icon_id) if icon_id != "" else null,
				"time_left": float(b.get("time_left", INF)), "duration": float(b.get("duration", 0.0)),
				"stacks": 0, "color": HudStyle.BUFF_BORDER, "mods": b.get("mods", []), "data": {}, "desc": String(b.get("desc", ""))})
		for kind in HudStyle.AILMENT_ORDER:
			if not actor.ailments.has(kind):
				continue
			var a: Dictionary = actor.ailments[kind]
			var info: Dictionary = HudStyle.AILMENTS[kind]
			var stacks := 0
			if kind == "poison":
				stacks = (a.get("stacks", []) as Array).size()
			list.append({"key": "a:" + kind, "kind": "ailment", "id": kind, "name": String(info["name"]), "icon": null,
				"time_left": float(a.get("time_left", 0.0)), "duration": float(a.get("duration", 0.0)),
				"stacks": stacks, "color": info["color"], "mods": [], "data": a})
	if list.size() > max_icons:
		list.resize(max_icons)
	entries = list
	var n := entries.size()
	var new_size := Vector2(n * icon_size + maxi(0, n - 1) * gap, icon_size + (19.0 if interactive else 2.0)) if n > 0 else Vector2.ZERO
	if new_size != size:
		size = new_size


func get_entry_count() -> int:
	return entries.size()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	var idx := int(mm.position.x / (icon_size + gap))
	if mm.position.x < 0.0 or idx < 0 or idx >= entries.size() or fmod(mm.position.x, icon_size + gap) > icon_size:
		idx = -1
	if idx != _hover_index:
		_hover_index = idx
		if idx < 0:
			if hud != null and hud.has_method("hide_tooltip_for"):
				hud.call("hide_tooltip_for", self)
		else:
			_show_tooltip(idx)


func _show_tooltip(idx: int) -> void:
	if hud == null or not hud.has_method("show_tooltip_for"):
		return
	hud.call("show_tooltip_for", self, get_entry_tooltip(idx), true)


## Tooltip lines for entry `idx`.
func get_entry_tooltip(idx: int) -> Array:
	if idx < 0 or idx >= entries.size():
		return []
	var e: Dictionary = entries[idx]
	var is_buff := String(e["kind"]) == "buff"
	var lines: Array = [{"text": String(e["name"]), "color": UIStyle.COLOR_TITLE if is_buff else (e["color"] as Color), "size": "title"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true}]
	if is_buff:
		for m in StatDefs.describe_mods(e["mods"]):
			lines.append({"text": m, "color": UIStyle.COLOR_MOD, "size": "normal"})
		if String(e.get("desc", "")) != "":
			lines.append({"text": String(e["desc"]), "color": UIStyle.COLOR_TEXT, "size": "normal"})
	else:
		var d: Dictionary = e["data"]
		var tpl := String(HudStyle.AILMENTS[e["id"]]["desc"])
		var txt := tpl
		match String(e["id"]):
			"ignite", "bleed", "poison":
				txt = tpl % StatDefs.fmt(float(d.get("dps", 0.0)))
			"shock":
				txt = tpl % StatDefs.fmt(float(d.get("effect", 0.0)) * 100.0)
			"chill":
				txt = tpl % StatDefs.fmt(float(d.get("effect", 0.0)) * 100.0)
		lines.append({"text": txt, "color": UIStyle.COLOR_TEXT, "size": "normal"})
		if int(e["stacks"]) > 1:
			lines.append({"text": "%d stacks" % int(e["stacks"]), "color": UIStyle.COLOR_TEXT_DIM, "size": "small"})
	var tl := float(e["time_left"])
	if tl != INF and tl > 0.0:
		lines.append({"text": "%.1f seconds remaining" % tl, "color": UIStyle.COLOR_TEXT_DIM, "size": "small"})
	return lines


func _draw() -> void:
	var f := HudStyle.bold_font()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var r := Rect2(Vector2(i * (icon_size + gap), 0.0), Vector2(icon_size, icon_size))
		var col: Color = e["color"]
		var is_buff := String(e["kind"]) == "buff"
		var tl := float(e["time_left"])
		var dur := float(e["duration"])
		var alpha := 1.0
		if tl != INF and tl < 2.0:
			alpha = 0.55 + 0.45 * absf(cos(_time * 6.0))
		draw_style_box(HudStyle.box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 0, 6), r.grow(2.0))
		var bg := Color(0.04, 0.035, 0.03, 0.95) if is_buff else Color(col.darkened(0.8), 0.95)
		draw_style_box(HudStyle.box(bg, Color(0, 0, 0, 0), 0, 5), r)
		if is_buff and e["icon"] != null:
			draw_texture_rect(e["icon"], r.grow(-2.0), false, Color(1, 1, 1, alpha))
		elif is_buff:
			HudStyle.draw_buff_glyph(self, r.get_center(), icon_size * 0.34, Color(col, alpha))
		else:
			HudStyle.draw_ailment_glyph(self, String(e["id"]), r.get_center(), icon_size * 0.36, Color(col, alpha))
		# Remaining time: the elapsed part darkens clockwise from 12 o'clock.
		if tl != INF and dur > 0.0:
			var elapsed := clampf(1.0 - tl / dur, 0.0, 1.0)
			var poly := HudStyle.elapsed_polygon(r.grow(-1.0), elapsed)
			if poly.size() >= 3:
				draw_colored_polygon(poly, Color(0, 0, 0, 0.55))
			if interactive:
				HudStyle.text_centered(self, f, r.get_center().x, r.end.y + 16.0, HudStyle.seconds(tl), 14, HudStyle.TEXT, 4)
		var border := HudStyle.BUFF_BORDER if is_buff else HudStyle.DEBUFF_BORDER
		draw_style_box(HudStyle.box(Color(0, 0, 0, 0), border, 2 if icon_size >= 32.0 else 1, 5), r)
		if int(e["stacks"]) > 1:
			var st := str(int(e["stacks"]))
			HudStyle.text_right(self, f, r.end.x - 2.0, r.position.y + (14.0 if icon_size >= 32.0 else 11.0), st, 13 if icon_size >= 32.0 else 11, Color(1, 1, 1), 3)
		if interactive and i == _hover_index:
			draw_style_box(HudStyle.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.6), 1, 5), r)

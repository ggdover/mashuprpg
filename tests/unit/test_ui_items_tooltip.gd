extends TestCase
## ui-items: TooltipPanel / TooltipBox rendering from real items, parts / hints / italic lines,
## wrapping, the comparison box and screen clamping.


func _make_panel() -> TooltipPanel:
	var t := TooltipPanel.new()
	add_child(t)
	return t


func _screen() -> Rect2:
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)


func test_renders_real_item_lines() -> void:
	var t := _make_panel()
	var it := ItemDB.create_item("sword_3", Item.Rarity.RARE, 20)
	t.show_lines(it.get_tooltip_lines({}), Rect2(200, 200, 50, 50))
	assert_true(t.visible, "tooltip visible")
	var box := t.get_main_box()
	var rows := box.get_row_texts()
	assert_true(rows.size() > 6, "several rows (%d)" % rows.size())
	assert_eq(rows[0], it.get_display_name(), "title row")
	assert_has(rows, "---", "separators drawn")
	assert_true(box.size.x >= TooltipBox.MIN_WIDTH and box.size.y > 100.0, "box sized %s" % box.size)
	assert_eq(box.get_accent(), UIStyle.rarity_color(Item.Rarity.RARE), "frame accent = rarity colour")
	assert_false(t.has_comparison(), "no comparison box")
	t.hide_tooltip()
	assert_false(t.visible, "hidden")


func test_unique_flavour_is_italic_and_parts_join() -> void:
	var t := _make_panel()
	var it := ItemDB.create_unique("stormcrown")
	var lines := it.get_tooltip_lines({"strength": 0, "dexterity": 0, "intelligence": 0, "level": 1})
	var has_italic := false
	var req_line: Dictionary = {}
	for l: Dictionary in lines:
		if bool(l.get("italic", false)):
			has_italic = true
		if l.has("parts"):
			req_line = l
	assert_true(has_italic, "unique has an italic flavour line")
	assert_false(req_line.is_empty(), "requirement line has parts")
	t.show_lines(lines, Rect2(300, 300, 40, 40))
	var rows := t.get_main_box().get_row_texts()
	assert_has(rows, String(req_line["text"]), "parts rendered as one row with the same text")
	# Unmet requirement parts are red.
	var red := false
	for p: Dictionary in req_line["parts"]:
		if p["color"] == UIStyle.COLOR_BAD:
			red = true
	assert_true(red, "unmet requirement coloured red")


func test_hints_only_when_requested() -> void:
	var box := TooltipBox.new()
	add_child(box)
	var lines := [{"text": "Title", "color": UIStyle.COLOR_TITLE, "size": "title"}, {"text": "+10 to Strength", "color": UIStyle.COLOR_MOD, "size": "normal", "hint": "Suffix \"of the Ox\" (tier 1 of 6)"}]
	box.set_lines(lines, "", false)
	var n := box.get_text_row_count()
	box.set_lines(lines, "", true)
	assert_eq(box.get_text_row_count(), n + 1, "hint adds a row")
	assert_has(box.get_row_texts(), "Suffix \"of the Ox\" (tier 1 of 6)", "hint text")


func test_wrap_keeps_run_spacing() -> void:
	var box := TooltipBox.new()
	add_child(box)
	box.max_width = 150.0
	var line := {"text": "Requires Level 16, 21 Str, 21 Dex", "color": UIStyle.COLOR_TEXT, "size": "small", "parts": [
		{"text": "Requires ", "color": UIStyle.COLOR_TEXT_DIM}, {"text": "Level 16", "color": UIStyle.COLOR_TEXT},
		{"text": ", ", "color": UIStyle.COLOR_TEXT_DIM}, {"text": "21 Str", "color": UIStyle.COLOR_BAD},
		{"text": ", ", "color": UIStyle.COLOR_TEXT_DIM}, {"text": "21 Dex", "color": UIStyle.COLOR_TEXT}]}
	box.set_lines([line])
	var rows := box.get_row_texts()
	assert_true(rows.size() >= 2, "wrapped into several rows (%d)" % rows.size())
	assert_eq(" ".join(rows), "Requires Level 16, 21 Str, 21 Dex", "spacing kept across runs")
	assert_true(box.size.x <= 150.0 + 0.5, "box respects max width")


func test_comparison_box_side_by_side() -> void:
	var t := _make_panel()
	var a := ItemDB.create_item("body_str_3", Item.Rarity.RARE, 20)
	var b := ItemDB.create_item("body_str_2", Item.Rarity.MAGIC, 12)
	var scr := _screen()
	var anchor := Rect2(scr.size.x - 300.0, 120.0, 50.0, 50.0)
	t.show_lines(a.get_tooltip_lines({}, b), anchor, b.get_tooltip_lines({}))
	assert_true(t.has_comparison(), "comparison shown")
	assert_eq(t.get_compare_box().get_row_texts()[0], TooltipPanel.COMPARE_CAPTION, "caption on top")
	var m := t.get_main_rect()
	var c := t.get_compare_rect()
	assert_false(m.intersects(c), "boxes don't overlap")
	assert_false(m.intersects(anchor), "main box beside the anchor")
	assert_eq(m.position.y, c.position.y, "boxes share their top edge")
	assert_true(scr.encloses(m) and scr.encloses(c), "both inside the screen")


func test_clamped_inside_screen() -> void:
	var t := _make_panel()
	var it := ItemDB.create_unique("stormcrown")
	var scr := _screen()
	for anchor: Rect2 in [Rect2(scr.size - Vector2(20, 20), Vector2(10, 10)), Rect2(Vector2(-40, -40), Vector2(10, 10)), Rect2(scr.size * 0.5, Vector2(10, 10))]:
		t.show_lines(it.get_tooltip_lines({}, ItemDB.create_item("helmet_str_3", Item.Rarity.RARE, 20)), anchor, it.get_tooltip_lines({}))
		assert_true(scr.encloses(t.get_main_rect()), "main inside for %s: %s" % [anchor, t.get_main_rect()])
		assert_true(scr.encloses(t.get_compare_rect()), "compare inside for %s" % anchor)


func test_never_takes_mouse() -> void:
	var t := _make_panel()
	t.show_lines([{"text": "x", "color": UIStyle.COLOR_TEXT, "size": "normal"}], Rect2(10, 10, 5, 5), [{"text": "y", "color": UIStyle.COLOR_TEXT, "size": "normal"}])
	assert_eq(t.mouse_filter, Control.MOUSE_FILTER_IGNORE, "panel ignores mouse")
	assert_eq(t.get_main_box().mouse_filter, Control.MOUSE_FILTER_IGNORE, "main box ignores mouse")
	assert_eq(t.get_compare_box().mouse_filter, Control.MOUSE_FILTER_IGNORE, "compare ignores mouse")


func test_ui_show_tooltip_uses_tooltip_panel() -> void:
	var it := ItemDB.create_item("ring_2", Item.Rarity.MAGIC, 10)
	UI.show_tooltip(it.get_tooltip_lines({}), Rect2(400, 400, 40, 40))
	var tp: Variant = UI.get("_tooltip")
	assert_true(tp is TooltipPanel, "UIRoot created a TooltipPanel")
	if tp is TooltipPanel:
		assert_true((tp as TooltipPanel).visible, "visible")
		assert_eq((tp as TooltipPanel).get_main_box().get_row_texts()[0], it.get_display_name(), "shows the item")
	UI.hide_tooltip()
	if tp is TooltipPanel:
		assert_false((tp as TooltipPanel).visible, "hidden")


func test_skill_style_lines_render() -> void:
	# Skill tooltips use the same format (SkillDB.get_tooltip_lines); render a hand-made one.
	var box := TooltipBox.new()
	add_child(box)
	box.set_lines([
		{"text": "Fireball", "color": UIStyle.COLOR_TITLE, "size": "title"},
		{"text": "Spell, Projectile, Area, Fire", "color": UIStyle.COLOR_TEXT_DIM, "size": "small"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
		{"text": "Fire Damage: 9-14", "color": UIStyle.damage_color("fire"), "size": "normal"},
		{"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true},
	])
	var rows := box.get_row_texts()
	assert_eq(rows, PackedStringArray(["Fireball", "Spell, Projectile, Area, Fire", "---", "Fire Damage: 9-14"]), "rows (trailing separator dropped)")

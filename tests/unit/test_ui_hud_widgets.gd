extends TestCase
## HUD widgets: pooled damage numbers, boss bar lifecycle, minimap indexing (arena origin),
## hovered-enemy nameplate, status icons. OWNER: ui-hud.

const HudDamageNumbers := preload("res://scripts/ui/hud/hud_damage_numbers.gd")


class FakeRare extends TestDummy:
	func get_nameplate_info() -> Dictionary:
		return {"name": "Grim Howl", "subtitle": "Skeleton", "rarity": 2,
			"mods": PackedStringArray(["Hasted", "Fiery"]), "level": 7, "life_ratio": life_ratio(),
			"is_boss": false}


class FakeBoss extends TestDummy:
	var fighting := true
	func is_in_combat() -> bool:
		return fighting


func _make_hud() -> HUD:
	var layer := CanvasLayer.new()
	add_child(layer)
	var h := HUD.new()
	layer.add_child(h)
	return h


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 15, 10)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	return cam


func test_damage_numbers_are_pooled() -> void:
	await make_world()
	spawn_player()
	_camera()
	var hud := _make_hud()
	var dn: Variant = hud.damage_numbers
	var start_labels: int = dn.get_label_count()
	assert_true(start_labels > 0, "pool pre-created")
	for i in 300:
		var kind: String = ["physical", "fire", "cold", "player_hurt", "heal"][i % 5]
		Events.damage_number.emit(Vector3(randf_range(-4, 4), 1.2, randf_range(-4, 4)), 10.0 + i, kind, i % 7 == 0)
	assert_eq(dn.spawned_total, 300, "every number spawned")
	assert_true(dn.get_label_count() <= HudDamageNumbers.POOL_MAX, "pool never exceeds its cap")
	assert_true(dn.get_active_count() <= HudDamageNumbers.POOL_MAX, "active within the cap")
	var labels_after: int = dn.get_label_count()
	assert_eq(labels_after, dn.get_child_count(), "labels are the layer's only children")
	# Tiny DoT dust is skipped; words work with 0.
	assert_false(dn.spawn(Vector3.ZERO, 0.1, "fire", false), "tiny amount skipped")
	assert_true(dn.spawn(Vector3.ZERO, 0.0, "evade", false), "evade shows a word")
	await get_tree().create_timer(1.7).timeout
	assert_eq(dn.get_active_count(), 0, "all numbers expired")
	for i in 20:
		dn.spawn(Vector3(0, 1, 0), 50.0, "physical", false)
	assert_eq(dn.get_label_count(), labels_after, "reused, no new labels")


func test_damage_number_styles_and_stacking() -> void:
	await make_world()
	_camera()
	var hud := _make_hud()
	await _frames(1)
	var dn: Variant = hud.damage_numbers
	dn.spawn(Vector3(0, 1, 0), 100.0, "fire", false)
	dn.spawn(Vector3(0, 1, 0), 100.0, "fire", true)
	dn.spawn(Vector3(0, 1, 0), 100.0, "player_hurt", false)
	var a: Variant = dn.active[0]
	var b: Variant = dn.active[1]
	var c: Variant = dn.active[2]
	assert_true(b.label.label_settings.font_size > a.label.label_settings.font_size, "crits are bigger")
	assert_true(String(b.label.text).ends_with("!"), "crit marker")
	assert_eq(a.label.label_settings.font_color, UIStyle.damage_color("fire"), "coloured by type")
	assert_eq(c.label.label_settings.font_color, UIStyle.damage_color("player_hurt"), "player damage red")
	# Numbers at the same spot don't overlap at spawn.
	var ra := Rect2(a.screen + a.offset - a.half, a.half * 2.0)
	var rb := Rect2(b.screen + b.offset - b.half, b.half * 2.0)
	assert_false(ra.grow(-3.0).intersects(rb.grow(-3.0)), "stacked, not overlapping")


func test_damage_numbers_frame_cost() -> void:
	await make_world()
	_camera()
	var hud := _make_hud()
	await _frames(1)
	var dn: Variant = hud.damage_numbers
	for i in 150:
		dn.spawn(Vector3(randf_range(-6, 6), 1.2, randf_range(-6, 6)), 25.0 + i, "physical", i % 5 == 0)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		dn._advance(0.016)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 10000.0
	assert_true(per_frame_ms < 4.0, "150 numbers update in < 4 ms per frame (got %.2f ms)" % per_frame_ms)


func test_boss_bar_lifecycle() -> void:
	await make_world()
	spawn_player()
	var hud := _make_hud()
	var boss := spawn_dummy(Actor.Team.ENEMY, Vector3(6, 0, 0), 1000.0)
	boss.is_boss_actor = true
	boss.display_name = "Test Tyrant"
	await _frames(1)
	var bb: Variant = hud.boss_bar
	assert_false(bb.is_showing(), "hidden at start")
	Events.boss_spawned.emit(boss)
	assert_true(bb.is_showing(), "shown on boss_spawned")
	assert_true(bb.visible, "visible")
	assert_eq(bb.boss_name, "Test Tyrant", "boss name")
	boss.take_damage(400.0, "physical")
	await _frames(30)
	assert_near(bb.display_ratio, boss.life_ratio(), 0.05, "bar follows boss life")
	assert_true(bb.trail_ratio >= bb.display_ratio, "trail at or above the fill")
	boss.die(null)
	await _frames(1)
	assert_false(bb.is_showing(), "hidden when the boss dies")
	await get_tree().create_timer(0.8).timeout
	assert_false(bb.visible, "faded out")
	# boss_killed and area_entered also hide it.
	var boss2 := spawn_dummy(Actor.Team.ENEMY, Vector3(-6, 0, 0), 1000.0)
	boss2.is_boss_actor = true
	Events.boss_spawned.emit(boss2)
	assert_true(bb.is_showing(), "second boss shown")
	Events.boss_killed.emit(boss2)
	assert_false(bb.is_showing(), "hidden on boss_killed")
	Events.boss_spawned.emit(boss2)
	Events.area_entered.emit({"id": "town", "name": "Emberfall", "level": 1, "theme": "town"})
	assert_false(bb.is_showing(), "hidden on area_entered")
	assert_false(bb.visible, "immediately")
	# A freed boss hides the bar too.
	Events.boss_spawned.emit(boss2)
	boss2.queue_free()
	await _frames(3)
	assert_false(bb.is_showing(), "freed boss -> hidden")


func test_minimap_indexing_arena_origin() -> void:
	var w := await make_world()
	var p := spawn_player(Vector3(0, 0, 0))
	var hud := _make_hud()
	var mm: Variant = hud.minimap
	mm.refresh_data(w, true)
	var data := w.get_minimap_data()
	var sz: Vector2i = data["size"]
	assert_eq(mm.get_grid_size(), sz, "grid size")
	assert_eq(mm.get_origin(), data["origin"], "origin from the data")
	assert_true((data["origin"] as Vector3).x < 0.0, "the arena is centred on the world origin")
	for pos in [Vector3.ZERO, Vector3(5.3, 0, -7.1), Vector3(-15.9, 0, 15.9), Vector3(3.99, 0, 4.01)]:
		assert_eq(mm.world_to_cell(pos), w.world_to_cell(pos), "cell of %s matches the World" % pos)
	var cell: Vector2i = mm.world_to_cell(Vector3.ZERO)
	assert_eq(mm.cell_index(cell), cell.y * sz.x + cell.x, "row-major index j * size.x + i")
	assert_eq(mm.cell_index(Vector2i(-1, 0)), -1, "outside -> -1")
	assert_true(mm.is_floor_at(Vector3.ZERO), "centre is floor")
	var edge := Vector3((data["origin"] as Vector3).x + 0.5, 0, 0)
	assert_false(mm.is_floor_at(edge), "the border ring is not floor")
	# The player is drawn at the centre of the corner map.
	await _frames(2)
	var sp: Vector2 = mm.world_to_screen(p.global_position)
	assert_true(sp.distance_to(mm.size * 0.5) < 1.0, "player at the map centre")
	# Textures are only re-uploaded when the explored version changes.
	var rc: int = mm.rebuild_count
	mm.refresh_data(w)
	mm.refresh_data(w)
	assert_eq(mm.rebuild_count, rc, "no change -> no rebuild")
	w.grid.explored_version += 1
	mm.refresh_data(w)
	assert_eq(mm.rebuild_count, rc + 1, "version change -> one rebuild")


func test_minimap_in_dungeon_markers() -> void:
	var w := await make_world({"id": "dungeon", "depth": 2, "level": 2, "seed": 99, "theme": "crypt", "name": "Depth 2"})
	var p := spawn_player(w.get_player_start())
	var hud := _make_hud()
	await get_tree().create_timer(0.4).timeout
	var mm: Variant = hud.minimap
	mm.refresh_data(w, true)
	var data: Dictionary = mm.data
	assert_false(data.is_empty(), "polled the world")
	assert_eq(mm.get_origin(), Vector3.ZERO, "dungeon origin")
	assert_true(mm.is_explored_at(p.global_position), "explored around the player (Player.mark_explored)")
	assert_false(mm.is_explored_at(w.get_boss_room_center()), "boss room still unexplored")
	var kinds: Array = []
	for m in data.get("markers", []):
		kinds.append(String(m.get("kind", "")))
	assert_has(kinds, "portal", "start portal marker")


func test_nameplate_for_hovered_enemy() -> void:
	await make_world()
	spawn_player()
	var hud := _make_hud()
	var np: Variant = hud.nameplate
	var d := spawn_dummy(Actor.Team.ENEMY, Vector3(3, 0, 0), 500.0)
	d.display_name = "Grumpy Dummy"
	await _frames(1)
	Events.hovered_target_changed.emit(d)
	assert_true(np.is_active(), "card for a hostile actor")
	assert_eq(String(np.info.get("name")), "Grumpy Dummy", "name")
	assert_eq(int(np.info.get("rarity")), 0, "normal rarity")
	await _frames(12)
	assert_true(np.visible, "visible")
	d.take_damage(250.0, "fire")
	await _frames(30)
	assert_near(np.display_ratio, d.life_ratio(), 0.05, "life bar follows")
	# An Enemy-like target with nameplate info.
	var rare := FakeRare.new()
	rare.team = Actor.Team.ENEMY
	rare.position = Vector3(-3, 0, 0)
	GameState.world.add_child(rare)
	Events.hovered_target_changed.emit(rare)
	assert_eq(String(np.info.get("name")), "Grim Howl", "nameplate info name")
	assert_eq(int(np.info.get("rarity")), 2, "rare")
	assert_eq(String(np.info.get("subtitle")), "Skeleton", "subtitle")
	assert_eq(PackedStringArray(np.info.get("mods")).size(), 2, "mods")
	# Allies and null clear it.
	var ally := spawn_dummy(Actor.Team.PLAYER, Vector3(0, 0, 3), 100.0)
	Events.hovered_target_changed.emit(ally)
	assert_false(np.is_active(), "no card for allies")
	Events.hovered_target_changed.emit(rare)
	assert_true(np.is_active(), "rare again")
	Events.hovered_target_changed.emit(null)
	assert_false(np.is_active(), "cleared on null")
	# A target that dies clears itself.
	Events.hovered_target_changed.emit(rare)
	rare.die(null)
	await _frames(2)
	assert_false(np.is_active(), "dead target clears")


func test_status_icons_for_buffs_and_ailments() -> void:
	await make_world()
	var p := spawn_player()
	var hud := _make_hud()
	p.add_buff("war_cry", {"name": "War Cry", "duration": 6.0, "icon": "war_cry", "mods": [StatBlock.mod("damage", "inc", 30.0)]})
	p.apply_ailment("ignite", {"dps": 2.0, "duration": 4.0})
	p.apply_ailment("poison", {"dps": 1.0, "duration": 3.0})
	p.apply_ailment("poison", {"dps": 1.0, "duration": 3.0})
	await _frames(2)
	var sb: Variant = hud.status_bar
	assert_eq(sb.get_entry_count(), 3, "buff + 2 ailments")
	assert_eq(String(sb.entries[0]["kind"]), "buff", "buffs first")
	var kinds: Array = []
	for e in sb.entries:
		kinds.append(String(e["id"]))
	assert_has(kinds, "ignite", "ignite icon")
	assert_has(kinds, "poison", "poison icon")
	for e in sb.entries:
		if e["id"] == "poison":
			assert_eq(int(e["stacks"]), 2, "poison stacks")
	var tip: Array = sb.get_entry_tooltip(0)
	assert_eq(String(tip[0]["text"]), "War Cry", "buff tooltip title")
	assert_true(sb.size.x > 0.0, "row has a size (hoverable)")
	p.remove_buff("war_cry")
	p.clear_ailments()
	await _frames(2)
	assert_eq(sb.get_entry_count(), 0, "cleared")
	assert_eq(sb.size, Vector2.ZERO, "empty row takes no mouse")


func test_boss_bar_hides_when_the_boss_leaves_combat() -> void:
	await make_world()
	spawn_player()
	var hud := _make_hud()
	var boss := FakeBoss.new()
	boss.team = Actor.Team.ENEMY
	boss.is_boss_actor = true
	boss.display_name = "Leash Lord"
	boss.position = Vector3(5, 0, 0)
	GameState.world.add_child(boss)
	await _frames(1)
	var bb: Variant = hud.boss_bar
	Events.boss_spawned.emit(boss)
	await get_tree().create_timer(0.4).timeout
	assert_true(bb.is_showing(), "fighting boss keeps its bar")
	boss.fighting = false
	await get_tree().create_timer(0.5).timeout
	assert_true(bb.is_showing(), "short grace period")
	await get_tree().create_timer(1.3).timeout
	assert_false(bb.is_showing(), "hidden once the boss left combat")
	# It announces itself again on its next aggro.
	boss.fighting = true
	Events.boss_spawned.emit(boss)
	assert_true(bb.is_showing(), "re-announced")

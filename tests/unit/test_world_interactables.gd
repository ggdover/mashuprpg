extends TestCase
## World interactables: chest opening, shrine buff data, portal hover/labels, vendor facing,
## stash lid, destinations.


func _physics_wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func test_chest_opens_once() -> void:
	var w := await make_world()
	var chest := WorldChest.new().setup(1, 7)
	chest.position = Vector3(2, 0, -4)
	w.interactables_root.add_child(chest)
	assert_eq(chest.get_hover_name(), "Ornate Chest", "tier 1 name")
	assert_eq(chest.get_minimap_kind(), "chest", "marker while closed")
	assert_not_null(chest.lid, "real or fallback chest has a Lid")
	chest.set_hovered(true)
	assert_true(chest.label.visible, "label on hover")
	chest.interact(null)
	assert_true(chest.opened, "opened")
	assert_false(chest.enabled, "disabled")
	assert_false(chest.hovered, "hover cleared")
	assert_eq(chest.collision_layer, 0, "no longer pickable")
	assert_eq(chest.get_minimap_kind(), "", "marker removed")
	await _physics_wait(40)
	if chest.lid != null:
		assert_near(chest.lid.rotation.x, -deg_to_rad(110.0), 0.05, "lid opened")
	# With a loot system that produces drops, they land in the world in front of the chest.
	if not LootSystem.roll_chest_drops(7, 1).is_empty():
		var items := w.dynamic_root.find_children("*", "GroundItem", true, false)
		assert_true(items.size() > 0, "chest dropped loot")
		for it in items:
			assert_true(w.is_walkable((it as Node3D).global_position), "loot on walkable floor")
	chest.interact(null)   # second click does nothing
	assert_true(chest.opened, "still opened")


func test_chest_without_lid_is_tolerated() -> void:
	var w := await make_world()
	var chest := WorldChest.new().setup(0, 1)
	w.interactables_root.add_child(chest)
	if chest.lid != null:
		chest.lid.free()
		chest.lid = null
	chest.interact(null)
	await _physics_wait(25)
	assert_true(chest.opened, "opened without a lid")


func test_shrine_buff() -> void:
	var w := await make_world()
	for kind in WorldShrine.KINDS:
		var s := WorldShrine.new().setup(kind)
		w.interactables_root.add_child(s)
		var data := s.get_buff_data()
		assert_eq(data["duration"], 30.0, "30 s")
		assert_true(data.has("name") and data.has("icon") and data.has("mods"), "buff keys")
		for m in data["mods"]:
			assert_true(StatDefs.STATS.has(m["stat"]), "stat %s exists" % m["stat"])
	var shrine := WorldShrine.new().setup("fury")
	w.interactables_root.add_child(shrine)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(1, 0, 0), 100.0)
	var notes: Array = []
	var cb := func(text: String, _c: Color) -> void: notes.append(text)
	Events.notify.connect(cb)
	shrine.interact(d)
	Events.notify.disconnect(cb)
	assert_true(shrine.used, "used")
	assert_false(shrine.enabled, "disabled after use")
	assert_eq(notes.size(), 1, "notification")
	shrine.interact(d)
	assert_eq(notes.size(), 1, "only once")


func test_portal_hover_and_label() -> void:
	var w := await make_world()
	var p := WorldPortal.new().setup("next", 4)
	p.position = Vector3(0, 0, -6)
	w.interactables_root.add_child(p)
	assert_eq(p.get_hover_name(), "Descend to Depth 4", "label text")
	assert_true(p.label.visible, "portal labels are always visible")
	assert_not_null(p.swirl, "swirl")
	assert_not_null(p.light, "light")
	p.set_hovered(true)
	var meshes := p.model.find_children("*", "MeshInstance3D", true, false)
	assert_true(meshes.size() > 0, "model meshes")
	if meshes.size() > 0:
		assert_not_null((meshes[0] as MeshInstance3D).material_overlay, "hover flash")
	p.set_hovered(false)
	if meshes.size() > 0:
		assert_true((meshes[0] as MeshInstance3D).material_overlay == null, "flash removed")
	var town := WorldPortal.new().setup("town")
	w.interactables_root.add_child(town)
	assert_eq(town.get_hover_name(), "Town", "town portal name")
	var ret := WorldPortal.new().setup("return", 9)
	w.interactables_root.add_child(ret)
	assert_eq(ret.get_hover_name(), "Return to Depth 9", "return portal name")


func test_portal_double_click_guard() -> void:
	var w := await make_world()
	var p := WorldPortal.new().setup("town")
	w.interactables_root.add_child(p)
	var got: Array = []
	var cb := func(id: String, _params: Dictionary) -> void: got.append(id)
	Events.area_change_requested.connect(cb)
	p.interact(null)
	p.interact(null)
	Events.area_change_requested.disconnect(cb)
	assert_eq(got, ["town"], "one request per click burst")


func test_vendor_faces_player_and_returns() -> void:
	var w := await make_world()
	var v := WorldVendorNpc.new()
	v.position = Vector3(0, 0, 0)
	v.rotation.y = 0.0
	w.interactables_root.add_child(v)
	var d := spawn_dummy(Actor.Team.PLAYER, Vector3(3, 0, 0), 100.0)
	v.interact(d)
	await _physics_wait(50)
	assert_near(wrapf(v.rotation.y, -PI, PI), atan2(3.0, 0.0), 0.1, "turned to the player")
	# GameState.player is not set (no Player node): the merchant goes back to its post.
	await _physics_wait(150)
	assert_near(wrapf(v.rotation.y, -PI, PI), 0.0, 0.1, "back to its post")


func test_stash_lid_opens() -> void:
	var w := await make_world()
	var s := WorldStashChest.new()
	w.interactables_root.add_child(s)
	s.interact(null)
	if s.lid != null:
		await _physics_wait(40)
		assert_near(s.lid.rotation.x, WorldStashChest.LID_OPEN, 0.05, "lid open")
		# No player: the lid closes again after a moment.
		await _physics_wait(120)
		assert_near(s.lid.rotation.x, 0.0, 0.05, "closed again without a player nearby")


func test_vendor_plays_idle() -> void:
	var w := await make_world()
	var v := WorldVendorNpc.new()
	if not Assets.has_model("char_merchant") and Assets.has_model("char_player"):
		v.model_id = "char_player"   # stand-in rig until char_merchant exists
	w.interactables_root.add_child(v)
	await _physics_wait(2)
	if v.anim != null:
		assert_true(v.anim.is_playing(), "animation playing")
		assert_eq(String(v.anim.current_animation), "idle", "idle")
		assert_true(v.anim.get_animation("idle").loop_mode != Animation.LOOP_NONE, "idle loops")
	var box := WorldInteractable.model_aabb(v.model)
	assert_between(box.size.y, 1.2, 2.6, "human-sized model")

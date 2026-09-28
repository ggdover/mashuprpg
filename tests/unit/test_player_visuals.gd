extends TestCase
## Player visuals: the look's model (char_player_<look>) + AnimationPlayer, weapon / off-hand
## attachments per bone (main hand, shield / focus, quiver), armour as the model's gear pieces
## (family + tier, hides the covered base parts, item tints), looks per class, time-scaled
## one-shots, looping channel, animation fallbacks, hit flash / flinch, death pose, player light.

const PlayerVisuals := preload("res://scripts/entities/player/player_visuals.gd")
const PlayerGear := preload("res://scripts/entities/player/player_gear.gd")


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _procs(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Albedo of the first tint_* surface of a body part (override if tinted), or null.
func _part_tint_ratio(p: Player, part: String) -> Variant:
	var mi := Assets.find_part(p.model, part)
	if mi == null or mi.mesh == null:
		return null
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		if src != null and src.resource_name.begins_with("tint") and src is BaseMaterial3D:
			var ov := mi.get_surface_override_material(i)
			if ov == null or not (ov is BaseMaterial3D):
				return Color.WHITE
			var a := (src as BaseMaterial3D).albedo_color
			var b := (ov as BaseMaterial3D).albedo_color
			return Color(b.r / maxf(a.r, 0.001), b.g / maxf(a.g, 0.001), b.b / maxf(a.b, 0.001))
	return null


func _color_near(a: Variant, b: Color, eps: float = 0.02) -> bool:
	if not (a is Color):
		return false
	var c: Color = a
	return absf(c.r - b.r) < eps and absf(c.g - b.g) < eps and absf(c.b - b.b) < eps


func test_model_and_warrior_gear() -> void:
	await make_world()
	var c := make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	assert_not_null(p.model, "model")
	assert_not_null(p.visuals, "visuals helper")
	var real: bool = p.model != null and not p.model.get_meta("placeholder", false)
	assert_true(real, "player model loaded")
	if not real:
		return
	assert_eq(p.visuals.look, "m1", "warrior default look")
	assert_not_null(p.anim_player, "AnimationPlayer")
	for part in ["Head", "HairTop", "Body", "Hands", "Outfit_Top", "Outfit_Legs", "Outfit_Feet"]:
		assert_not_null(Assets.find_part(p.model, part), "part " + part)
	# A new hero wears only the default outfit: every gear piece hidden.
	assert_eq(c.get_equipped("body"), null, "no starting body armour")
	var vis := p.visuals.get_visible_parts()
	for n in vis:
		assert_false(PlayerGear.is_piece(n), "no gear piece shown at start (%s)" % n)
	assert_true(vis.has("HairTop") and vis.has("Outfit_Top") and vis.has("Hands"), "default look shown")
	# Sword on the right grip, via a BoneAttachment3D.
	var sword := p.visuals.get_attachment("grip_r")
	assert_not_null(sword, "main hand attached")
	if sword != null:
		var ba := sword.get_parent() as BoneAttachment3D
		assert_not_null(ba, "BoneAttachment3D parent")
		if ba != null:
			assert_eq(String(ba.bone_name), "grip_r", "grip_r bone")
		assert_true(sword.find_children("*", "MeshInstance3D", true, false).size() > 0, "weapon mesh")
	# Helmet, body armour, gloves, boots: the model's pieces replace the covered base parts.
	var helm := ItemDB.create_item("helmet_str_1", Item.Rarity.NORMAL, 1)
	var body := ItemDB.create_item("body_str_int_1", Item.Rarity.NORMAL, 1)
	var gloves := ItemDB.create_item("gloves_dex_1", Item.Rarity.NORMAL, 1)
	var boots := ItemDB.create_item("boots_int_1", Item.Rarity.NORMAL, 1)
	var shield := ItemDB.create_item("shield_str_1", Item.Rarity.NORMAL, 1)
	c.equip(helm, "helmet")
	c.equip(body, "body")
	c.equip(gloves, "gloves")
	c.equip(boots, "boots")
	c.equip(shield, "off_hand")
	vis = p.visuals.get_visible_parts()
	for piece in ["Helm_str_1", "Chest_str_1", "Gloves_dex_1", "Boots_int_1"]:
		if Assets.find_part(p.model, piece) == null:
			continue
		assert_true(vis.has(piece), "%s shown" % piece)
	assert_false(vis.has("HairTop"), "hair top hidden under the helmet")
	assert_false(vis.has("Outfit_Top"), "outfit hidden under the body armour")
	assert_false(vis.has("Hands"), "bare hands hidden under gloves")
	assert_false(vis.has("Outfit_Feet"), "shoes hidden under boots")
	assert_true(vis.has("Outfit_Legs") and vis.has("Head") and vis.has("Body"), "trousers, head, body stay")
	assert_eq(p.visuals.gear_pieces.get("helmet"), "Helm_str_1", "helmet piece")
	assert_true(_color_near(_part_tint_ratio(p, "Helm_str_1"), helm.get_tint()), "helmet tinted")
	assert_true(_color_near(_part_tint_ratio(p, "Chest_str_1"), body.get_tint()), "body armour tinted")
	assert_true(_color_near(_part_tint_ratio(p, "Gloves_dex_1"), gloves.get_tint()), "gloves tinted")
	assert_true(_color_near(_part_tint_ratio(p, "Boots_int_1"), boots.get_tint()), "boots tinted")
	assert_not_null(p.visuals.get_attachment("grip_l"), "shield on the left grip")
	assert_eq(p.model.find_children("Gear_head", "", true, false).size(), 0, "helmets are model pieces, not attachments")
	# Unequipping removes attachments and restores the default outfit.
	c.unequip("helmet")
	c.unequip("body")
	c.unequip("off_hand")
	c.unequip("main_hand")
	await get_tree().process_frame
	assert_eq(p.visuals.get_attachment("grip_l"), null, "shield removed")
	assert_eq(p.visuals.get_attachment("grip_r"), null, "weapon removed")
	assert_eq(p.model.find_children("Gear_*", "", true, false).size(), 0, "no leftover gear nodes")
	vis = p.visuals.get_visible_parts()
	assert_true(vis.has("HairTop") and vis.has("Outfit_Top"), "hair and outfit back")
	assert_false(vis.has("Helm_str_1") or vis.has("Chest_str_1"), "pieces hidden again")
	assert_true(vis.has("Gloves_dex_1") or Assets.find_part(p.model, "Gloves_dex_1") == null, "gloves still worn")


func test_gear_families_and_tiers() -> void:
	var it := func(base: String, rarity: int = Item.Rarity.NORMAL) -> Item:
		var x := ItemDB.create_item(base, Item.Rarity.NORMAL, 1)
		x.rarity = rarity
		return x
	assert_eq(PlayerGear.family_of(it.call("helmet_str_1")), "str", "str helmet")
	assert_eq(PlayerGear.family_of(it.call("body_str_dex_2")), "str", "str_dex -> str")
	assert_eq(PlayerGear.family_of(it.call("body_str_int_2")), "str", "str_int -> str")
	assert_eq(PlayerGear.family_of(it.call("gloves_dex_int_1")), "dex", "dex_int -> dex")
	assert_eq(PlayerGear.family_of(it.call("boots_int_4")), "int", "int boots")
	assert_eq(PlayerGear.family_of(it.call("sword_1")), "", "weapons have no piece")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_1")), 1, "base tier 1 -> 1")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_2")), 1, "base tier 2 -> 1")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_3")), 2, "base tier 3 -> 2")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_4")), 2, "base tier 4 -> 2")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_5")), 3, "base tier 5 -> 3")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_6")), 3, "base tier 6 -> 3")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_1", Item.Rarity.UNIQUE)), 2, "uniques one tier up")
	assert_eq(PlayerGear.tier_of(it.call("helmet_str_6", Item.Rarity.UNIQUE)), 3, "max tier 3")
	assert_eq(PlayerGear.piece_for("helmet", it.call("helmet_dex_int_5")), "Helm_dex_3", "piece name")
	assert_eq(PlayerGear.piece_for("body", it.call("body_int_3")), "Chest_int_2", "chest piece")
	assert_eq(PlayerGear.piece_for("main_hand", it.call("sword_1")), "", "no piece for weapons")
	# Every piece lists the base parts it hides.
	var pieces := PlayerGear.pieces()
	assert_eq(pieces.size(), 36, "3 families x 4 slots x 3 tiers")
	for n in pieces:
		assert_true((pieces[n] as Dictionary).get("hides") is Array, "%s hides" % n)


func test_looks_per_class() -> void:
	await make_world()
	make_character("ranger")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	assert_eq(p.visuals.look, "f", "ranger is the female exile")
	if Assets.has_model("char_player_f"):
		assert_not_null(Assets.find_part(p.model, "HairBack"), "long hair")
	p.queue_free()
	await _wait(1)
	var c := GameState.new_character("Second", "warrior", "m2")
	assert_eq(c.get_look(), "m2", "warrior picked the second look")
	var p2 := spawn_player(Vector3(3, 0, 0))
	await _wait(2)
	assert_eq(p2.visuals.look, "m2", "second male look")
	var c3 := GameState.new_character("Third", "sorcerer", "m2")
	assert_eq(c3.get_look(), "f", "sorcerers can't pick a male look")
	# Cape and hair swing on spring bones.
	if Assets.find_skeleton(p2.model) != null and Assets.find_skeleton(p2.model).find_bone("cape_1") >= 0:
		assert_not_null(p2.visuals.springs, "spring bones")


func test_ranger_quiver_and_sorcerer_focus() -> void:
	await make_world()
	var c := make_character("ranger")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var bow := p.visuals.get_attachment("grip_r")
	assert_not_null(bow, "bow in the right hand")
	var quiver := ItemDB.create_item("quiver_1", Item.Rarity.NORMAL, 1)
	c.equip(quiver, "off_hand")
	var q := p.visuals.get_attachment("chest")
	assert_not_null(q, "quiver on the chest bone")
	assert_eq(p.visuals.get_attachment("grip_l"), null, "quiver is not held")
	p.queue_free()
	await _wait(1)
	var c2 := make_character("sorcerer")
	var p2 := spawn_player(Vector3.ZERO)
	await _wait(2)
	var focus := ItemDB.create_item("focus_1", Item.Rarity.NORMAL, 1)
	if focus != null and not focus.get_base().is_empty():
		c2.equip(focus, "off_hand")
		assert_not_null(p2.visuals.get_attachment("grip_l"), "focus in the left hand")
	var wand := p2.visuals.get_attachment("grip_r")
	assert_not_null(wand, "wand in the right hand")


func test_action_animations() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var ap := p.anim_player
	assert_not_null(ap, "animation player")
	if ap == null:
		return
	assert_eq(String(ap.current_animation), "idle", "idle at rest")
	# One-shots are time-scaled to the requested duration.
	p.play_action_animation("attack_slash", 0.3)
	assert_eq(p.visuals.action_anim, "attack_slash", "action set")
	assert_eq(String(ap.current_animation), "attack_slash", "playing")
	assert_near(ap.get_playing_speed(), ap.get_animation("attack_slash").length / 0.3, 0.01, "speed = length / duration")
	await _procs(3)
	assert_near(ap.get_playing_speed(), 2.0, 0.01, "still 2x")
	await _wait(22)
	await _procs(1)
	assert_eq(p.visuals.action_anim, "", "one-shot over after its duration")
	assert_eq(String(ap.current_animation), "idle", "back to idle")
	# duration <= 0 loops (channel) until stop_action_animation.
	p.play_action_animation("channel", 0.0)
	await _wait(80)
	assert_eq(String(ap.current_animation), "channel", "channel keeps looping")
	p.stop_action_animation()
	assert_eq(p.visuals.action_anim, "", "stopped")
	assert_eq(String(ap.current_animation), "idle", "idle after stop")
	# Missing animations fall back (char_player has no "roar").
	p.play_action_animation("roar", 1.0)
	assert_true(String(ap.current_animation) in ["cast_area", "cast"], "fallback for roar (%s)" % ap.current_animation)
	p.stop_action_animation()
	# Re-triggering the same one-shot restarts it.
	p.play_action_animation("cast", 0.6)
	await _wait(15)
	p.play_action_animation("cast", 0.6)
	assert_true(ap.current_animation_position < 0.05, "restarted from the start")


func test_hit_flash_flinch_and_death_pose() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(2)
	var torso := Assets.find_part(p.model, "Body")
	# Small hit: flash, no flinch.
	p.take_damage(p.max_life * 0.05, "physical")
	await _procs(1)
	if torso != null:
		assert_not_null(torso.material_overlay, "hit flash")
	assert_ne(p.visuals.action_anim, "hit", "no flinch for small hits")
	await _wait(30)
	await _procs(1)
	if torso != null:
		assert_true(torso.material_overlay == null, "flash faded")
	# Big hit while idle: flinch.
	p.take_damage(p.max_life * 0.2, "physical")
	assert_eq(p.visuals.action_anim, "hit", "flinch on a big hit")
	assert_true(p.visuals.is_reacting(), "reaction flag")
	# A skill animation replaces the flinch; a flinch never interrupts an action.
	p.play_action_animation("attack_slam", 0.8)
	p.take_damage(p.max_life * 0.2, "physical")
	assert_eq(p.visuals.action_anim, "attack_slam", "no flinch while attacking")
	# Death pose.
	var died := [0]
	var cb := func() -> void: died[0] += 1
	Events.player_died.connect(cb)
	p.take_damage(p.max_life * 5.0, "physical")
	Events.player_died.disconnect(cb)
	assert_true(p.dead, "dead")
	assert_eq(died[0], 1, "player_died once")
	assert_eq(p.visuals.action_anim, "die", "die animation")
	assert_eq(String(p.anim_player.current_animation), "die", "playing die")
	p.play_action_animation("attack_slash", 0.5)
	assert_eq(p.visuals.action_anim, "die", "no actions after death")
	await _wait(90)
	assert_eq(p.visuals.action_anim, "die", "stays down")


func test_player_light() -> void:
	await make_world()
	make_character("warrior")
	var p := spawn_player(Vector3.ZERO)
	await _wait(1)
	assert_not_null(p.light, "player light")
	assert_false(p.light.shadow_enabled, "shadowless")
	assert_between(p.light.omni_range, 8.0, 12.0, "range ~10")
	assert_true(p.light.light_color.r > p.light.light_color.b, "warm colour")
	assert_true(p.light.position.y > 2.0, "above the player")

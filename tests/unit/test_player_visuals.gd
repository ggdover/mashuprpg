extends TestCase
## Player visuals: char_player model + AnimationPlayer, gear attachments per bone (main hand,
## shield / focus, quiver, helmet), Hair hidden under a helmet, body-part tints (and the leather
## colour of empty glove / boot slots), time-scaled one-shots, looping channel, animation
## fallbacks, hit flash / flinch, death pose, player light.

const PlayerVisuals := preload("res://scripts/entities/player/player_visuals.gd")


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
	assert_true(real, "char_player.glb loaded")
	if not real:
		return
	assert_not_null(p.anim_player, "AnimationPlayer")
	for part in ["Head", "Torso", "Arms", "Hands", "Legs", "Feet"]:
		assert_not_null(Assets.find_part(p.model, part), "part " + part)
	# Sword on the right grip, via a BoneAttachment3D.
	var sword := p.visuals.get_attachment("grip_r")
	assert_not_null(sword, "main hand attached")
	if sword != null:
		var ba := sword.get_parent() as BoneAttachment3D
		assert_not_null(ba, "BoneAttachment3D parent")
		if ba != null:
			assert_eq(String(ba.bone_name), "grip_r", "grip_r bone")
		assert_true(sword.find_children("*", "MeshInstance3D", true, false).size() > 0, "weapon mesh")
	assert_eq(p.visuals.get_attachment("head"), null, "no helmet")
	var hair := Assets.find_part(p.model, "Hair")
	if hair != null:
		assert_true(hair.visible, "hair visible without a helmet")
	# Body armour tints Torso + Arms; empty gloves / boots are leather.
	var body: Item = c.get_equipped("body")
	assert_true(_color_near(_part_tint_ratio(p, "Torso"), body.get_tint()), "Torso tinted with the body armour")
	assert_true(_color_near(_part_tint_ratio(p, "Arms"), body.get_tint()), "Arms tinted with the body armour")
	assert_true(_color_near(_part_tint_ratio(p, "Hands"), PlayerVisuals.EMPTY_GLOVES_TINT), "bare hands leather")
	assert_true(_color_near(_part_tint_ratio(p, "Feet"), PlayerVisuals.EMPTY_BOOTS_TINT), "plain boots leather")
	# Helmet, gloves, boots, shield.
	var helm := ItemDB.create_item("helmet_str_1", Item.Rarity.NORMAL, 1)
	var gloves := ItemDB.create_item("gloves_dex_1", Item.Rarity.NORMAL, 1)
	var boots := ItemDB.create_item("boots_int_1", Item.Rarity.NORMAL, 1)
	var shield := ItemDB.create_item("shield_str_1", Item.Rarity.NORMAL, 1)
	c.equip(helm, "helmet")
	c.equip(gloves, "gloves")
	c.equip(boots, "boots")
	c.equip(shield, "off_hand")
	var h := p.visuals.get_attachment("head")
	assert_not_null(h, "helmet attached")
	if h != null:
		assert_eq(String((h.get_parent() as BoneAttachment3D).bone_name), "head", "on the head bone")
	if hair != null:
		assert_false(hair.visible, "hair hidden under the helmet")
	assert_not_null(p.visuals.get_attachment("grip_l"), "shield on the left grip")
	assert_true(_color_near(_part_tint_ratio(p, "Hands"), gloves.get_tint()), "gloves tint the hands")
	assert_true(_color_near(_part_tint_ratio(p, "Feet"), boots.get_tint()), "boots tint the feet")
	# Unequipping removes attachments and restores the hair.
	c.unequip("helmet")
	c.unequip("off_hand")
	c.unequip("main_hand")
	await get_tree().process_frame
	assert_eq(p.visuals.get_attachment("head"), null, "helmet removed")
	assert_eq(p.visuals.get_attachment("grip_l"), null, "shield removed")
	assert_eq(p.visuals.get_attachment("grip_r"), null, "weapon removed")
	assert_eq(p.model.find_children("Gear_*", "", true, false).size(), 0, "no leftover gear nodes")
	if hair != null:
		assert_true(hair.visible, "hair back")
	c.unequip("body")
	assert_true(_color_near(_part_tint_ratio(p, "Torso"), PlayerVisuals.NO_BODY_TINT), "linen tunic without body armour")


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
	var torso := Assets.find_part(p.model, "Torso")
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

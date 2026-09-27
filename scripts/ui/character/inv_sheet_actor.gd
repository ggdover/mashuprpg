extends Actor
## Off-tree stand-in for the Player, used by the character sheet when there is no live Player
## (main menu, demos, tests): computes the same stats the Player would from CharacterData —
## Player.get_base_mods() / get_all_mods() per §5 / §11.3 (base life/mana, class attributes, base
## evasion, equipment, passives, and the dungeon resistance penalty of GameState.current_area).
## Never added to the tree; the owner frees it. OWNER: ui-items (internal, preloaded).

var character: CharacterData = null


## Bind to character data and recalculate.
func setup(data: CharacterData) -> void:
	character = data
	team = Team.PLAYER
	display_name = data.char_name if data != null else ""
	base_move_speed = Balance.PLAYER_BASE_MOVE_SPEED
	refresh()


## Re-read the character and rebuild every stat.
func refresh() -> void:
	level = character.level if character != null else 1
	recalculate_stats()


func get_base_mods() -> Array:
	var mods: Array = [
		StatBlock.mod("max_life", "flat", Balance.player_base_life(level)),
		StatBlock.mod("max_mana", "flat", Balance.player_base_mana(level)),
		StatBlock.mod("evasion", "flat", Balance.PLAYER_BASE_EVASION),
	]
	if character != null:
		mods.append_array(ClassDefs.get_attribute_mods(character.class_id))
	return mods


func get_all_mods() -> Array:
	var mods := get_base_mods()
	if character != null:
		mods.append_array(character.get_equipment_mods())
		mods.append_array(TreeDB.get_mods(character.allocated_passives, character.class_id))
	var pen := get_resist_penalty()
	if pen != 0.0:
		mods.append(StatBlock.mod("elemental_resistance", "flat", pen))
		mods.append(StatBlock.mod("chaos_resistance", "flat", pen))
	return mods


func get_weapon() -> Dictionary:
	if character != null:
		var main: Item = character.get_equipped("main_hand")
		if main != null:
			var w := main.get_weapon_stats()
			if not w.is_empty():
				return w
	return DamageCalc.UNARMED.duplicate(true)


## Balance.resist_penalty of the current area when it is a dungeon, else 0.
static func get_resist_penalty() -> float:
	var info: Dictionary = GameState.current_area
	if String(info.get("id", "")) != "dungeon" and not (String(info.get("id", "")) == "act" and not bool(info.get("safe", false))):
		return 0.0
	var lvl := int(info.get("level", Balance.area_level_for_depth(int(info.get("depth", 1)))))
	return Balance.resist_penalty(lvl)


func get_attributes() -> Dictionary:
	return {
		"strength": float(attributes.get("strength", 0.0)),
		"dexterity": float(attributes.get("dexterity", 0.0)),
		"intelligence": float(attributes.get("intelligence", 0.0)),
	}

extends Actor
## Off-tree stand-in actor the autoplay bot uses to score gear, skills and passives: it computes
## the stats a character WOULD have with a given equipment set (base + class + gear + passives,
## like Player.get_all_mods() without buffs or the dungeon penalty), then rates offence
## (best single-target DPS over the usable skills, SkillDB.estimate_dps) and defence (a simple
## effective-HP figure). Never added to the tree. OWNER: flow (wave 2).
##
##   var ev := DebugBotEval.new()
##   ev.configure(character, character.equipment)
##   var score := ev.power_score(skill_ids)
##   ev.free()   # when done (it is a Node)

var eval_mods: Array = []
var eval_weapon: Dictionary = {}
var class_id := "warrior"


func _init() -> void:
	super._init()
	team = Team.PLAYER
	base_move_speed = Balance.PLAYER_BASE_MOVE_SPEED


## Recompute the stats for `c` wearing `equipment` (slot -> Item; may differ from c.equipment).
## `allocated` overrides the passive allocation when not null.
func configure(c: CharacterData, equipment: Dictionary, allocated: Variant = null) -> void:
	class_id = c.class_id
	level = c.level
	var mods: Array = [
		StatBlock.mod("max_life", "flat", Balance.player_base_life(level)),
		StatBlock.mod("max_mana", "flat", Balance.player_base_mana(level)),
		StatBlock.mod("evasion", "flat", Balance.PLAYER_BASE_EVASION),
	]
	mods.append_array(ClassDefs.get_attribute_mods(c.class_id))
	for slot in CharacterData.EQUIP_SLOTS:
		var it: Item = equipment.get(slot, null)
		if it != null:
			mods.append_array(it.get_global_mods())
	var alloc: Array = c.allocated_passives if allocated == null else allocated
	mods.append_array(TreeDB.get_mods(alloc, c.class_id))
	eval_mods = mods
	var main: Item = equipment.get("main_hand", null)
	eval_weapon = main.get_weapon_stats() if main != null else {}
	buffs.clear()
	recalculate_stats()


func get_all_mods() -> Array:
	return eval_mods


func get_weapon() -> Dictionary:
	if eval_weapon.is_empty():
		return DamageCalc.UNARMED.duplicate(true)
	return eval_weapon


## Best estimated single-target DPS among `skill_ids` usable with the current weapon (0 if none).
func offence(skill_ids: Array) -> float:
	var wt := String(get_weapon().get("weapon_type", "unarmed"))
	var best := 0.0
	for id in skill_ids:
		var sid := String(id)
		if sid == "" or not SkillDB.has_skill(sid):
			continue
		var s := SkillDB.get_skill(sid)
		if int(s.get("unlock_level", 1)) > level or not SkillDB.is_weapon_compatible(sid, wt):
			continue
		best = maxf(best, SkillDB.estimate_dps(sid, self))
	return best


## Effective hit points: life + ES, scaled by elemental resistances, armour, evasion and block.
func defence() -> float:
	var pool := max_life + max_es
	var res := 0.0
	for t in StatDefs.ELEMENTAL_TYPES:
		res += clampf(float(resistances.get(t, 0.0)), -60.0, 75.0)
	res /= 3.0
	var res_f := 1.0 / maxf(0.25, 1.0 - res / 100.0 * 0.55)
	var arm_f := 1.0 + armour / (armour + 60.0 + 25.0 * level)
	var ev_f := 1.0 + evasion / (evasion + 120.0 + 40.0 * level) * 0.9
	var blk_f := 1.0 / maxf(0.25, 1.0 - block_chance / 100.0 * 0.6)
	return pool * res_f * arm_f * ev_f * blk_f


## One number to compare setups: offence^0.6 × defence^0.4 (+ a little for movement speed,
## mana for spell users and item rarity).
func power_score(skill_ids: Array) -> float:
	var off := maxf(0.5, offence(skill_ids))
	var def := maxf(1.0, defence())
	var extra := 1.0 + maxf(0.0, stats.inc("movement_speed")) / 100.0 * 0.6
	extra *= 1.0 + maxf(0.0, stats.compute("item_rarity")) / 100.0 * 0.05
	if class_id == "sorcerer":
		extra *= 1.0 + minf(max_mana, 400.0) / 4000.0
	return pow(off, 0.6) * pow(def, 0.4) * extra

extends RefCounted
## Character build decisions of the autoplay bot:
##   passives  — picks a target (a notable, or a frontier node) by the power gain per point of the
##               whole path to it (DebugBotEval with the allocation overridden), then allocates
##               along TreeDB.find_path one point at a time; keystones are never taken
##   skill bar — the best unlocked skills for the current weapon: main damage skill, area skill,
##               buff, movement, a third damage skill, and Attack as a free fallback
## OWNER: flow (wave 2).

const DebugBotEval := preload("res://scripts/debug/debug_bot_eval.gd")

const MAX_PATH := 9
## Skill tags a class plays with (basic_attack is always allowed): warriors and rangers use
## attacks and warcries, sorcerers spells.
const CLASS_SKILL_TAGS := {
	"warrior": ["attack", "warcry"],
	"ranger": ["attack", "warcry"],
	"sorcerer": ["spell"],
}

var eval: DebugBotEval = null
var skill_ids: Array = []

var _target := -1


func _init(p_eval: DebugBotEval, class_id: String) -> void:
	eval = p_eval
	skill_ids = class_skills(class_id)


## Player skill ids that fit the class's playstyle (see CLASS_SKILL_TAGS).
static func class_skills(class_id: String) -> Array:
	var tags: Array = CLASS_SKILL_TAGS.get(class_id, ["attack", "spell", "warcry"])
	var out: Array = []
	for id in SkillDB.PLAYER_SKILL_IDS:
		if id == "basic_attack":
			out.append(id)
			continue
		for t in SkillDB.get_skill(id).get("tags", []):
			if t in tags:
				out.append(id)
				break
	return out


# ------------------------------------------------------------------ passives

## Next node to allocate (-1 when there are no points or nothing worth taking).
func next_passive(c: CharacterData) -> int:
	if c.passive_points_unspent() <= 0:
		return -1
	if _target >= 0 and not c.allocated_passives.has(_target):
		var path := TreeDB.find_path(c.allocated_passives, _target, c.class_id)
		if not path.is_empty():
			return int(path[0])
	_target = choose_target(c)
	if _target < 0:
		return -1
	var p2 := TreeDB.find_path(c.allocated_passives, _target, c.class_id)
	return int(p2[0]) if not p2.is_empty() else -1


func reset_target() -> void:
	_target = -1


## The node whose path gives the most power per point (notables within MAX_PATH, or any node on
## the frontier).
func choose_target(c: CharacterData) -> int:
	var alloc: Array = Array(c.allocated_passives)
	eval.configure(c, c.equipment, alloc)
	var base := maxf(0.0001, eval.power_score(skill_ids))
	var candidates: Array = []
	candidates.append_array(TreeDB.get_ids_by_type("notable"))
	candidates.append_array(TreeDB.get_allocatable(alloc, c.class_id))
	var best := -1
	var best_eff := -INF
	var seen := {}
	for raw in candidates:
		var id := int(raw)
		if seen.has(id) or alloc.has(id) or TreeDB.get_node_type(id) == "keystone":
			continue
		seen[id] = true
		var path := TreeDB.find_path(alloc, id, c.class_id)
		if path.is_empty() or path.size() > MAX_PATH:
			continue
		var skip := false
		for n in path:
			if TreeDB.get_node_type(int(n)) == "keystone":
				skip = true
		if skip:
			continue
		var trial := alloc.duplicate()
		trial.append_array(path)
		eval.configure(c, c.equipment, trial)
		var gain := eval.power_score(skill_ids) / base - 1.0
		gain += 0.002 * _mod_count(path)
		var eff := gain / float(path.size())
		if TreeDB.get_node_type(id) == "notable":
			eff *= 1.1
		if eff > best_eff:
			best_eff = eff
			best = id
	return best


static func _mod_count(path: Array) -> int:
	var n := 0
	for id in path:
		n += (TreeDB.get_passive(int(id)).get("mods", []) as Array).size()
	return n


# ------------------------------------------------------------------ skill bar

## "buff" | "move" | "channel" | "nova" | "aoe" | "single" for a resolved skill.
static func classify(s: Dictionary) -> String:
	var d := String(s.get("delivery", ""))
	var tags: Array = s.get("tags", [])
	match d:
		"buff":
			return "buff"
		"leap", "blink":
			return "move"
		"channel_aoe":
			return "channel"
		"nova":
			return "nova"
	if "area" in tags or d in ["rain", "aoe_target", "chain"]:
		return "aoe"
	return "single"


## Desired bar for the actor's weapon and the character's level.
func choose_bar(c: CharacterData, actor: Actor) -> Array[String]:
	var wt := String(actor.get_weapon().get("weapon_type", "unarmed"))
	var dmg: Array = []     # [dps, id, kind]
	var buffs: Array = []
	var moves: Array = []
	for sd in SkillDB.get_player_skills():
		var id := String((sd as Dictionary).get("id", ""))
		if id == "" or not skill_ids.has(id) or int((sd as Dictionary).get("unlock_level", 1)) > c.level or not SkillDB.is_weapon_compatible(id, wt):
			continue
		var s := SkillDB.get_resolved(id, actor)
		var kind := classify(s)
		match kind:
			"buff":
				buffs.append(id)
			"move":
				moves.append(id)
			_:
				var dps := SkillDB.estimate_dps(id, actor)
				if dps > 0.0:
					dmg.append([dps, id, kind])
	dmg.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var bar: Array[String] = ["", "", "", "", "", ""]
	var used := {}
	# LMB: the best damage skill.
	if not dmg.is_empty():
		bar[0] = dmg[0][1]
		used[bar[0]] = true
	# Slot 2: the best area skill (weighted), else the next damage skill.
	var best_aoe := ""
	var best_aoe_v := -1.0
	for e in dmg:
		if used.has(e[1]) or not (String(e[2]) in ["aoe", "channel", "nova"]):
			continue
		if float(e[0]) * 1.5 > best_aoe_v:
			best_aoe_v = float(e[0]) * 1.5
			best_aoe = e[1]
	if best_aoe == "":
		best_aoe = _next_unused(dmg, used)
	if best_aoe != "":
		bar[1] = best_aoe
		used[best_aoe] = true
	# Q: buff; E: movement.
	if not buffs.is_empty():
		bar[2] = buffs[0]
		used[bar[2]] = true
	if not moves.is_empty():
		bar[3] = moves[0]
		used[bar[3]] = true
	# R: another damage skill; F: Attack (free) unless already there, else a fourth skill.
	var third := _next_unused(dmg, used)
	if third != "":
		bar[4] = third
		used[third] = true
	if not used.has("basic_attack"):
		bar[5] = "basic_attack"
	else:
		bar[5] = _next_unused(dmg, used)
	# No gaps: skills move left over empty slots (Attack stays last).
	var compact: Array[String] = []
	for id in bar:
		if id != "":
			compact.append(id)
	while compact.size() < bar.size():
		compact.append("")
	return compact


## Apply choose_bar() (only slots that change). Returns true if anything changed.
func apply_bar(c: CharacterData, actor: Actor) -> bool:
	var bar := choose_bar(c, actor)
	var changed := false
	for i in bar.size():
		if c.get_skill_in_slot(i) != bar[i]:
			c.set_skill_in_slot(i, bar[i])
			changed = true
	return changed


static func _next_unused(dmg: Array, used: Dictionary) -> String:
	for e in dmg:
		if not used.has(e[1]):
			return String(e[1])
	return ""

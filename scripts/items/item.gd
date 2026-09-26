class_name Item
extends RefCounted
## One item instance (equipment). Created by ItemDB; serialised with to_dict()/from_dict().
## OWNER: items (wave 1). See docs/ARCHITECTURE.md §9.
##
## Numbers are derived from the base + rolled mods on demand (nothing cached), so an item loaded
## from a save always reflects the current base tables:
##   - weapon numbers = category template × Balance.weapon_damage_scale(eff), then local mods
##   - defences = body formula(eff) × slot/hybrid factor, then local flat and inc mods
##   - eff = clamp(item_level, base.level, base.level + 12)

const BaseData := preload("res://scripts/items/item_base_data.gd")

## Also used for monster rarity (0 normal .. 3 unique/boss).
enum Rarity { NORMAL, MAGIC, RARE, UNIQUE }

## Values of get_slot_type().
const SLOT_TYPES: Array[String] = ["weapon", "offhand", "helmet", "body", "gloves", "boots", "ring", "amulet", "belt"]

## Sell value multiplier per rarity (§9.7): sell ≈ 2 × item_level × mult; buy = 4 × sell.
const SELL_RARITY_MULT: Array[float] = [1.0, 3.0, 8.0, 15.0]
const BUY_MULT := 4
const DAMAGE_TYPES_ADDED: Array[String] = ["fire", "cold", "lightning", "chaos"]
## Stats where a lower value is better (tooltip comparison colours).
const LOWER_IS_BETTER: Array[String] = ["damage_taken", "mana_cost"]

static var _next_uid: int = 1
## When true, tooltips append affix tier hints ("T4") to explicit mod lines (debug / advanced UI).
static var tooltip_show_tiers: bool = false

## Unique per item instance (kept across save/load).
var uid: int = 0
## Key into ItemDB bases, e.g. "sword_3", "body_str_2".
var base_id: String = ""
## Key into ItemDB uniques ("" unless rarity == UNIQUE).
var unique_id: String = ""
## Generated name for rare/unique items ("Doom Grasp"); magic/normal names are derived.
var name: String = ""
var rarity: int = Rarity.NORMAL
var item_level: int = 1
## Mods that come with the base type (rolled values).
var implicit_mods: Array = []
## Rolled affixes: [{"id": String, "kind": "prefix"|"suffix"|"unique", "tier": int,
## "name": String, "mods": Array[mod dict]}]. Uniques store their fixed mods as one entry of kind
## "unique".
var affixes: Array = []


func _init() -> void:
	uid = _next_uid
	_next_uid += 1


func get_base() -> Dictionary:
	return ItemDB.get_base(base_id)


## One of SLOT_TYPES.
func get_slot_type() -> String:
	return get_base().get("slot_type", "")


## StatDefs.WEAPON_TYPES entry for weapons, "shield"/"quiver"/"focus" for off-hands, else "".
func get_weapon_type() -> String:
	return get_base().get("weapon_type", "")


func is_weapon() -> bool:
	return get_slot_type() == "weapon"


func is_two_handed() -> bool:
	return get_base().get("two_handed", false)


## Display class of the base: "One Handed Sword", "Body Armour", "Ring"...
func get_item_class() -> String:
	return get_base().get("item_class", get_slot_type().capitalize())


## Tier of the base (1..6).
func get_tier() -> int:
	return int(get_base().get("tier", 1))


## Name shown in UI: unique/rare name, "Prefix Base of Suffix" for magic, base name for normal.
func get_display_name() -> String:
	if name != "":
		return name
	if rarity == Rarity.MAGIC:
		var prefix := ""
		var suffix := ""
		for a: Dictionary in affixes:
			if a.get("kind", "") == "prefix" and prefix == "":
				prefix = String(a.get("name", ""))
			elif a.get("kind", "") == "suffix" and suffix == "":
				suffix = String(a.get("name", ""))
		var out := get_base_name()
		if prefix != "":
			out = prefix + " " + out
		if suffix != "":
			out = out + " " + suffix
		return out
	return get_base_name()


func get_base_name() -> String:
	return get_base().get("name", base_id)


func get_rarity_color() -> Color:
	return UIStyle.rarity_color(rarity)


## {"level": int, "strength": int, "dexterity": int, "intelligence": int}
func get_requirements() -> Dictionary:
	var b := get_base()
	var req: Dictionary = b.get("req", {})
	return {"level": int(b.get("level", 1)), "strength": int(req.get("strength", 0)), "dexterity": int(req.get("dexterity", 0)), "intelligence": int(req.get("intelligence", 0))}


## Requirement keys ("level", "strength", ...) not met by `attributes` ({"strength": ..,
## optional "level": ..}). Level is checked only when `attributes` has "level" or `level` >= 0.
func get_unmet_requirements(attributes: Dictionary, level: int = -1) -> Array[String]:
	var out: Array[String] = []
	var req := get_requirements()
	var have_level := int(attributes.get("level", level))
	if have_level >= 0 and have_level < int(req["level"]):
		out.append("level")
	for k in ["strength", "dexterity", "intelligence"]:
		if int(req[k]) > 0 and float(attributes.get(k, 0.0)) < float(req[k]):
			out.append(k)
	return out


func meets_requirements(attributes: Dictionary, level: int = -1) -> bool:
	return get_unmet_requirements(attributes, level).is_empty()


# ------------------------------------------------------------------ mods

## Every mod on the item (implicit + explicit), local ones included. For tooltips.
func get_all_mods() -> Array:
	var out: Array = []
	for m: Dictionary in implicit_mods:
		out.append(m.duplicate())
	out.append_array(get_explicit_mods())
	return out


## Mods of the rolled affixes / unique mods only.
func get_explicit_mods() -> Array:
	var out: Array = []
	for a: Dictionary in affixes:
		for m: Dictionary in a.get("mods", []):
			out.append(m.duplicate())
	return out


## Local mods only (folded into get_weapon_stats / get_defence_stats).
func get_local_mods() -> Array:
	var out: Array = []
	for m: Dictionary in get_all_mods():
		if StatDefs.is_local(m.get("stat", "")):
			out.append(m)
	return out


## Mods to add to the wearer's StatBlock: all non-local mods PLUS the item's final defences as
## flat mods (armour, evasion, max_energy_shield, block_chance). Weapon damage is NOT included
## (DamageCalc reads get_weapon_stats()).
func get_global_mods() -> Array:
	var out := _non_local_mods()
	var d := get_defence_stats()
	if d["armour"] > 0.0:
		out.append(StatBlock.mod("armour", "flat", d["armour"]))
	if d["evasion"] > 0.0:
		out.append(StatBlock.mod("evasion", "flat", d["evasion"]))
	if d["energy_shield"] > 0.0:
		out.append(StatBlock.mod("max_energy_shield", "flat", d["energy_shield"]))
	if d["block"] > 0.0:
		out.append(StatBlock.mod("block_chance", "flat", d["block"]))
	return out


func _non_local_mods() -> Array:
	var out: Array = []
	for m: Dictionary in get_all_mods():
		if not StatDefs.is_local(m.get("stat", "")):
			out.append(m)
	return out


## Sum of local mod values for stat/op. Range stats return Vector2(min, max) via _local_range.
func _local_sum(stat: String, op: String) -> float:
	var total := 0.0
	for m: Dictionary in implicit_mods:
		if m.get("stat", "") == stat and m.get("op", "") == op:
			total += float(m.get("value", 0.0))
	for a: Dictionary in affixes:
		for m: Dictionary in a.get("mods", []):
			if m.get("stat", "") == stat and m.get("op", "") == op:
				total += float(m.get("value", 0.0))
	return total


func _local_range(stat: String) -> Vector2:
	var r := Vector2.ZERO
	for m: Dictionary in get_all_mods():
		if m.get("stat", "") == stat and m.get("op", "flat") == "flat":
			var v := float(m.get("value", 0.0))
			r += Vector2(v, float(m.get("value2", v)))
	return r


## Level used for weapon/defence numbers: clamp(item_level, base.level, base.level + 12).
func get_effective_level() -> int:
	var lvl := int(get_base().get("level", 1))
	return clampi(item_level, lvl, lvl + BaseData.TIER_GROWTH)


# ------------------------------------------------------------------ derived numbers

## Weapon dict (schema in DamageCalc.UNARMED) with local mods applied. {} for non-weapons.
## Extra keys: "base_phys_min"/"base_phys_max" (before local mods).
func get_weapon_stats() -> Dictionary:
	if not is_weapon():
		return {}
	var b := get_base()
	var scale := Balance.weapon_damage_scale(get_effective_level())
	var base_min := roundf(float(b.get("template_min", b.get("phys_min", 1.0))) * scale)
	var base_max := roundf(float(b.get("template_max", b.get("phys_max", 2.0))) * scale)
	var add := _local_range("local_added_physical")
	var inc := _local_sum("local_physical_damage", "inc")
	var pmin := roundf((base_min + add.x) * (1.0 + inc / 100.0))
	var pmax := maxf(pmin, roundf((base_max + add.y) * (1.0 + inc / 100.0)))
	var added := {}
	for t in DAMAGE_TYPES_ADDED:
		var r := _local_range("local_added_" + t)
		if r.y > 0.0:
			added[t] = r
	var aps := snappedf(float(b.get("attack_speed", 1.0)) * maxf(0.1, 1.0 + _local_sum("local_attack_speed", "inc") / 100.0), 0.01)
	var crit := snappedf(float(b.get("crit_chance", 5.0)) * maxf(0.0, 1.0 + _local_sum("local_crit_chance", "inc") / 100.0), 0.01)
	return {
		"weapon_type": b.get("weapon_type", "unarmed"),
		"phys_min": maxf(0.0, pmin),
		"phys_max": maxf(0.0, pmax),
		"added": added,
		"attack_speed": aps,
		"crit_chance": crit,
		"range": float(b.get("range", 2.2)),
		"two_handed": bool(b.get("two_handed", false)),
		"base_phys_min": base_min,
		"base_phys_max": base_max,
	}


## Final local defences: {"armour": float, "evasion": float, "energy_shield": float, "block": float}
func get_defence_stats() -> Dictionary:
	var out := {"armour": 0.0, "evasion": 0.0, "energy_shield": 0.0, "block": 0.0}
	var b := get_base()
	if b.is_empty():
		return out
	var types: Array = b.get("defence_types", [])
	var factor := float(b.get("defence_factor", 0.0))
	var eff := get_effective_level()
	for k: String in ["armour", "evasion", "energy_shield"]:
		var base_v := roundf(BaseData.body_defence(k, eff) * factor) if k in types else 0.0
		var flat := _local_sum("local_" + k, "flat")
		var inc := _local_sum("local_" + k, "inc")
		if base_v + flat > 0.0:
			out[k] = maxf(0.0, roundf((base_v + flat) * (1.0 + inc / 100.0)))
	var block := float(b.get("block", 0.0)) + _local_sum("local_block", "flat")
	out["block"] = maxf(0.0, block)
	return out


## Average damage per second of the weapon itself (all types), before character stats.
func get_weapon_dps() -> Dictionary:
	var w := get_weapon_stats()
	if w.is_empty():
		return {"physical": 0.0, "elemental": 0.0, "chaos": 0.0, "total": 0.0}
	var aps: float = w["attack_speed"]
	var phys := (float(w["phys_min"]) + float(w["phys_max"])) * 0.5 * aps
	var ele := 0.0
	var chaos := 0.0
	for t: String in w["added"]:
		var r: Vector2 = w["added"][t]
		if t == "chaos":
			chaos += (r.x + r.y) * 0.5 * aps
		else:
			ele += (r.x + r.y) * 0.5 * aps
	return {"physical": phys, "elemental": ele, "chaos": chaos, "total": phys + ele + chaos}


# ------------------------------------------------------------------ tooltip

## Tooltip content, top to bottom. Each line: {"text": String, "color": Color,
## "size": "title"|"normal"|"small", "separator": bool (optional: draw a divider instead)}.
## Optional extra keys: "parts": [{"text", "color"}] (same text split into coloured runs, e.g.
## requirements), "hint": String (affix name/tier, for a hover hint), "italic": bool (flavour).
## `attributes` ({"strength":.., optional "level"}) colours unmet requirements red (the level is
## taken from GameState.character when missing); `compare_to` adds comparison lines against the
## currently equipped item.
func get_tooltip_lines(attributes: Dictionary = {}, compare_to: Item = null) -> Array:
	var lines: Array = []
	var rc := get_rarity_color()
	lines.append(_line(get_display_name(), rc, "title"))
	if rarity >= Rarity.RARE and name != "":
		lines.append(_line(get_base_name(), rc, "normal"))
	var type_text := get_item_class()
	if rarity != Rarity.NORMAL:
		type_text = "%s %s" % [UIStyle.RARITY_NAMES[clampi(rarity, 0, 3)], type_text]
	lines.append(_line(type_text, UIStyle.COLOR_TEXT_DIM, "small"))
	# ---- properties
	var props := _property_lines()
	if not props.is_empty():
		lines.append(_separator())
		lines.append_array(props)
	# ---- requirements + item level
	lines.append(_separator())
	var req_line := _requirement_line(attributes)
	if not req_line.is_empty():
		lines.append(req_line)
	lines.append(_line("Item Level: %d" % item_level, UIStyle.COLOR_TEXT_DIM, "small"))
	# ---- implicits
	if not implicit_mods.is_empty():
		lines.append(_separator())
		for m: Dictionary in implicit_mods:
			lines.append(_line(_describe(m), UIStyle.COLOR_IMPLICIT, "normal"))
	# ---- explicit mods
	var explicit := _explicit_lines()
	if not explicit.is_empty():
		lines.append(_separator())
		lines.append_array(explicit)
	if rarity == Rarity.UNIQUE:
		var flavour := String(ItemDB.get_unique(unique_id).get("flavour", ""))
		if flavour != "":
			lines.append(_separator())
			var fl := _line(flavour, UIStyle.COLOR_UNIQUE_FLAVOR, "small")
			fl["italic"] = true
			lines.append(fl)
	# ---- comparison
	if compare_to != null and compare_to != self:
		lines.append(_separator())
		lines.append_array(get_comparison_lines(compare_to))
	return lines


## Lines describing what changes when this item replaces `other` (green = better, red = worse).
func get_comparison_lines(other: Item) -> Array:
	var lines: Array = []
	if other == null:
		return lines
	lines.append(_line("Compared to %s:" % other.get_display_name(), UIStyle.COLOR_TEXT_DIM, "small"))
	var n := lines.size()
	if is_weapon() and other.is_weapon():
		var a := get_weapon_dps()
		var b := other.get_weapon_dps()
		_diff_line(lines, a["total"] - b["total"], "%s Damage per Second", 1)
		var wa := get_weapon_stats()
		var wb := other.get_weapon_stats()
		_diff_line(lines, float(wa["attack_speed"]) - float(wb["attack_speed"]), "%s Attacks per Second", 2)
		_diff_line(lines, float(wa["crit_chance"]) - float(wb["crit_chance"]), "%s%% Critical Strike Chance", 1)
	elif is_weapon() != other.is_weapon():
		var mine := get_weapon_dps()["total"] as float
		var theirs := other.get_weapon_dps()["total"] as float
		_diff_line(lines, mine - theirs, "%s Weapon Damage per Second", 1)
	var da := get_defence_stats()
	var db := other.get_defence_stats()
	_diff_line(lines, da["armour"] - db["armour"], "%s Armour", 0)
	_diff_line(lines, da["evasion"] - db["evasion"], "%s Evasion Rating", 0)
	_diff_line(lines, da["energy_shield"] - db["energy_shield"], "%s Energy Shield", 0)
	_diff_line(lines, da["block"] - db["block"], "%s%% Chance to Block", 0)
	# Global mods (defences handled above).
	var sa := _mod_totals(_non_local_mods())
	var sb := _mod_totals(other._non_local_mods())
	var keys: Array = sa.keys()
	for k in sb.keys():
		if not k in keys:
			keys.append(k)
	for k: String in keys:
		var ma: Dictionary = sa.get(k, {})
		var mb: Dictionary = sb.get(k, {})
		var src: Dictionary = ma if not ma.is_empty() else mb
		var stat: String = src["stat"]
		var op: String = src["op"]
		if op == "flag":
			if ma.is_empty() != mb.is_empty():
				var gain := not ma.is_empty()
				lines.append(_line(("Gain: " if gain else "Lose: ") + StatDefs.describe(src), UIStyle.COLOR_GOOD if gain else UIStyle.COLOR_BAD, "small"))
			continue
		var dv := float(ma.get("value", 0.0)) - float(mb.get("value", 0.0))
		var dv2 := float(ma.get("value2", ma.get("value", 0.0))) - float(mb.get("value2", mb.get("value", 0.0)))
		if absf(dv) < 0.001 and absf(dv2) < 0.001:
			continue
		var m := {"stat": stat, "op": op, "value": dv}
		if StatDefs.is_range(stat):
			m["value2"] = dv2
		var better := (dv + dv2) > 0.0
		if stat in LOWER_IS_BETTER:
			better = not better
		lines.append(_line(_describe_diff(m), UIStyle.COLOR_GOOD if better else UIStyle.COLOR_BAD, "small"))
	if lines.size() == n:
		lines.append(_line("No stat changes", UIStyle.COLOR_TEXT_DIM, "small"))
	return lines


func _mod_totals(mods: Array) -> Dictionary:
	var out := {}
	for m: Dictionary in mods:
		var op: String = m.get("op", "flat")
		var key := "%s|%s" % [m.get("stat", ""), op]
		if op == "more":
			# more mods multiply: combine as one equivalent percentage
			var cur: Dictionary = out.get(key, {"stat": m["stat"], "op": op, "value": 0.0})
			cur["value"] = ((1.0 + float(cur["value"]) / 100.0) * (1.0 + float(m.get("value", 0.0)) / 100.0) - 1.0) * 100.0
			out[key] = cur
			continue
		if not out.has(key):
			out[key] = {"stat": m["stat"], "op": op, "value": 0.0}
		var t: Dictionary = out[key]
		t["value"] = float(t["value"]) + float(m.get("value", 0.0))
		if m.has("value2"):
			t["value2"] = float(t.get("value2", 0.0)) + float(m["value2"])
	return out


func _diff_line(lines: Array, diff: float, fmt: String, decimals: int) -> void:
	var eps := 0.5 * pow(10.0, -decimals)
	if absf(diff) < eps:
		return
	var num := ("%." + str(decimals) + "f") % absf(diff)
	var text := fmt % (("+" if diff > 0.0 else "-") + num)
	lines.append(_line(text, UIStyle.COLOR_GOOD if diff > 0.0 else UIStyle.COLOR_BAD, "small"))


func _property_lines() -> Array:
	var out: Array = []
	if is_weapon():
		var w := get_weapon_stats()
		var phys_mod := not is_equal_approx(float(w["phys_min"]), float(w["base_phys_min"])) or not is_equal_approx(float(w["phys_max"]), float(w["base_phys_max"]))
		out.append(_line("Physical Damage: %d-%d" % [int(w["phys_min"]), int(w["phys_max"])], UIStyle.COLOR_MOD if phys_mod else UIStyle.COLOR_TEXT, "normal"))
		for t: String in w["added"]:
			var r: Vector2 = w["added"][t]
			out.append(_line("%s Damage: %d-%d" % [t.capitalize(), int(r.x), int(r.y)], UIStyle.damage_color(t), "normal"))
		var b := get_base()
		var crit_mod := not is_equal_approx(float(w["crit_chance"]), float(b.get("crit_chance", 5.0)))
		out.append(_line("Critical Strike Chance: %.1f%%" % float(w["crit_chance"]), UIStyle.COLOR_MOD if crit_mod else UIStyle.COLOR_TEXT, "normal"))
		var aps_mod := not is_equal_approx(float(w["attack_speed"]), float(b.get("attack_speed", 1.0)))
		out.append(_line("Attacks per Second: %.2f" % float(w["attack_speed"]), UIStyle.COLOR_MOD if aps_mod else UIStyle.COLOR_TEXT, "normal"))
		if float(w["range"]) < 10.0:
			out.append(_line("Weapon Range: %.1f m" % float(w["range"]), UIStyle.COLOR_TEXT, "normal"))
		var dps := get_weapon_dps()
		var dps_text := "DPS: %.1f" % float(dps["total"])
		if float(dps["elemental"]) + float(dps["chaos"]) > 0.0:
			dps_text += "  (Physical %.1f, Elemental %.1f" % [float(dps["physical"]), float(dps["elemental"])]
			if float(dps["chaos"]) > 0.0:
				dps_text += ", Chaos %.1f" % float(dps["chaos"])
			dps_text += ")"
		out.append(_line(dps_text, UIStyle.COLOR_TEXT_DIM, "small"))
		return out
	var d := get_defence_stats()
	var base := get_base()
	var eff := get_effective_level()
	var labels := {"armour": "Armour", "evasion": "Evasion Rating", "energy_shield": "Energy Shield"}
	for k: String in ["armour", "evasion", "energy_shield"]:
		if d[k] <= 0.0:
			continue
		var unmodified := roundf(BaseData.body_defence(k, eff) * float(base.get("defence_factor", 0.0))) if k in base.get("defence_types", []) else 0.0
		var modified := not is_equal_approx(float(d[k]), unmodified)
		out.append(_line("%s: %d" % [labels[k], int(d[k])], UIStyle.COLOR_MOD if modified else UIStyle.COLOR_TEXT, "normal"))
	if d["block"] > 0.0:
		var block_mod := not is_equal_approx(float(d["block"]), float(base.get("block", 0.0)))
		out.append(_line("Chance to Block: %d%%" % int(d["block"]), UIStyle.COLOR_MOD if block_mod else UIStyle.COLOR_TEXT, "normal"))
	return out


func _requirement_line(attributes: Dictionary) -> Dictionary:
	var req := get_requirements()
	var check := not attributes.is_empty()
	var level := -1
	if check:
		level = int(attributes.get("level", -1))
		if level < 0 and GameState.character != null:
			level = GameState.character.level
	var unmet: Array[String] = []
	if check:
		unmet = get_unmet_requirements(attributes, level)
	var parts: Array = []
	var texts: PackedStringArray = []
	if int(req["level"]) > 1:
		var lt := "Level %d" % int(req["level"])
		texts.append(lt)
		parts.append({"text": lt, "color": UIStyle.COLOR_BAD if "level" in unmet else UIStyle.COLOR_TEXT})
	for k: String in ["strength", "dexterity", "intelligence"]:
		if int(req[k]) > 0:
			var at := "%d %s" % [int(req[k]), k.substr(0, 3).capitalize()]
			texts.append(at)
			parts.append({"text": at, "color": UIStyle.COLOR_BAD if k in unmet else UIStyle.COLOR_TEXT})
	if texts.is_empty():
		return {}
	var run: Array = [{"text": "Requires ", "color": UIStyle.COLOR_TEXT_DIM}]
	for i in parts.size():
		if i > 0:
			run.append({"text": ", ", "color": UIStyle.COLOR_TEXT_DIM})
		run.append(parts[i])
	var line := _line("Requires " + ", ".join(texts), UIStyle.COLOR_BAD if not unmet.is_empty() else UIStyle.COLOR_TEXT_DIM, "small")
	line["parts"] = run
	return line


func _explicit_lines() -> Array:
	var out: Array = []
	var ordered: Array = []
	for kind in ["unique", "prefix", "suffix"]:
		for a: Dictionary in affixes:
			if a.get("kind", "") == kind:
				ordered.append(a)
	for a: Dictionary in affixes:
		if not a in ordered:
			ordered.append(a)
	for a: Dictionary in ordered:
		var kind: String = a.get("kind", "")
		var hint := ""
		if kind == "prefix" or kind == "suffix":
			var def := ItemDB.get_affix(String(a.get("id", "")))
			var n_tiers: int = (def.get("tiers", []) as Array).size()
			hint = "%s \"%s\" (tier %d of %d)" % [kind.capitalize(), a.get("name", ""), int(a.get("tier", 1)), n_tiers]
		for m: Dictionary in a.get("mods", []):
			var text := _describe(m)
			if tooltip_show_tiers and hint != "":
				text += "  [T%d]" % int(a.get("tier", 1))
			var l := _line(text, UIStyle.COLOR_MOD, "normal")
			if hint != "":
				l["hint"] = hint
			out.append(l)
	return out


static func _describe(m: Dictionary) -> String:
	return StatDefs.describe(m).replace("+-", "-")


## Like _describe, for a stat DIFFERENCE (comparison lines): every flat number carries its sign,
## also in templates without one ("Regenerate +3 Life per second", "Adds +2 to +5 Fire Damage"),
## matching how negative differences read ("Regenerate -3 Life per second").
static func _describe_diff(m: Dictionary) -> String:
	var info := StatDefs.get_info(String(m.get("stat", "")))
	var tpl := String(info.get("flat", ""))
	if String(m.get("op", "flat")) != "flat" or tpl == "":
		return _describe(m)
	var v := float(m.get("value", 0.0))
	var v2 := float(m.get("value2", v))
	tpl = tpl.replace("+{v2}", "{v2}").replace("+{v}", "{v}")
	var stat_name := String(info.get("name", String(m.get("stat", "")).capitalize()))
	return tpl.replace("{v2}", _signed(v2)).replace("{v}", _signed(v)).replace("{name}", stat_name)


## StatDefs.fmt with a leading "+" for positive numbers ("-" comes from the number itself).
static func _signed(v: float) -> String:
	var s := StatDefs.fmt(v)
	if s == "-0":
		s = "0"
	return ("+" + s) if v > 0.0 and s != "0" else s


static func _line(text: String, color: Color, size: String = "normal") -> Dictionary:
	return {"text": text, "color": color, "size": size}


static func _separator() -> Dictionary:
	return {"text": "", "color": UIStyle.COLOR_BORDER, "size": "small", "separator": true}


# ------------------------------------------------------------------ economy & visuals

func get_sell_value() -> int:
	return maxi(1, int(roundf(2.0 * item_level * SELL_RARITY_MULT[clampi(rarity, 0, 3)])))


func get_buy_value() -> int:
	return get_sell_value() * BUY_MULT


## Model/icon id (docs §14): e.g. "weapon_sword", "armor_helmet_str", "jewel_ring".
func get_model_id() -> String:
	return get_base().get("model", "")


## Tint used on the ground model and on the player's body parts when worn (uniques may override
## their base tint).
func get_tint() -> Color:
	if unique_id != "":
		var u := ItemDB.get_unique(unique_id)
		if u.has("tint"):
			return u["tint"]
	return get_base().get("tint", Color.WHITE)


## A copy with a new uid (same base, rolls and name).
func clone() -> Item:
	var d := to_dict()
	var it := Item.new()
	var new_uid := it.uid
	it = from_dict(d)
	it.uid = new_uid
	return it


# ------------------------------------------------------------------ persistence

## JSON-native values only (no Color/Vector2): base stats, tint and weapon numbers are recomputed
## from base_id. Rolled mod values are stored.
func to_dict() -> Dictionary:
	var aff: Array = []
	for a: Dictionary in affixes:
		aff.append({"id": String(a.get("id", "")), "kind": String(a.get("kind", "")), "tier": int(a.get("tier", 0)), "name": String(a.get("name", "")), "mods": _clean_mods(a.get("mods", []))})
	return {"uid": uid, "base_id": base_id, "unique_id": unique_id, "name": name, "rarity": rarity, "item_level": item_level, "implicit_mods": _clean_mods(implicit_mods), "affixes": aff}


## Restores uid and bumps _next_uid past it; converts JSON floats with int().
static func from_dict(d: Dictionary) -> Item:
	var it := Item.new()
	it.uid = int(d.get("uid", it.uid))
	_next_uid = maxi(_next_uid, it.uid + 1)
	it.base_id = String(d.get("base_id", ""))
	it.unique_id = String(d.get("unique_id", ""))
	it.name = String(d.get("name", ""))
	it.rarity = clampi(int(d.get("rarity", 0)), Rarity.NORMAL, Rarity.UNIQUE)
	it.item_level = maxi(1, int(d.get("item_level", 1)))
	it.implicit_mods = _clean_mods(d.get("implicit_mods", []))
	var aff: Array = []
	var src: Variant = d.get("affixes", [])
	if src is Array:
		for a: Variant in src:
			if a is Dictionary:
				aff.append({"id": String(a.get("id", "")), "kind": String(a.get("kind", "")), "tier": int(a.get("tier", 0)), "name": String(a.get("name", "")), "mods": _clean_mods(a.get("mods", []))})
	it.affixes = aff
	if not ItemDB.has_base(it.base_id):
		push_warning("Item.from_dict: unknown base '%s'" % it.base_id)
	return it


static func _clean_mods(mods: Variant) -> Array:
	var out: Array = []
	if not (mods is Array):
		return out
	for m: Variant in mods:
		if not (m is Dictionary) or not (m as Dictionary).has("stat"):
			continue
		var c := {"stat": String(m["stat"]), "op": String(m.get("op", "flat")), "value": float(m.get("value", 0.0))}
		if (m as Dictionary).has("value2"):
			c["value2"] = float(m["value2"])
		out.append(c)
	return out

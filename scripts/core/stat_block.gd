class_name StatBlock
extends RefCounted
## Aggregates stat modifiers ("mods"). OWNER: orchestrator (the kernel may extend it, but must not
## change existing behaviour). See docs/ARCHITECTURE.md §5.
##
## A mod is a plain Dictionary:
##   {"stat": String, "op": String, "value": float}                    # most mods
##   {"stat": String, "op": "flat", "value": float, "value2": float}   # min-max range (added damage)
##
## op:
##   "flat" - added to the base value. With "value2" it is a min..max range.
##   "inc"  - percent increased; negative means reduced. All inc mods on a stat are SUMMED.
##   "more" - percent more; negative means less. Each more mod MULTIPLIES separately.
##   "flag" - boolean switch (keystones, unique effects). value is ignored.
##
## final = (base + flat) * (1 + sum(inc)/100) * product(1 + more_i/100)

const OP_FLAT := "flat"
const OP_INC := "inc"
const OP_MORE := "more"
const OP_FLAG := "flag"

var _flat: Dictionary = {}   # stat -> float (min side for ranges)
var _flat2: Dictionary = {}  # stat -> float (max side for ranges; same as _flat for non-ranges)
var _inc: Dictionary = {}    # stat -> float (percent points)
var _more: Dictionary = {}   # stat -> float (multiplier, 1.0 = no change)
var _flags: Dictionary = {}  # flag -> int (count of sources)


## Build a mod dictionary. Pass value2 only for min-max ranges.
static func mod(stat: String, op: String, value: float = 0.0, value2: Variant = null) -> Dictionary:
	var m := {"stat": stat, "op": op, "value": value}
	if value2 != null:
		m["value2"] = float(value2)
	return m


func clear() -> void:
	_flat.clear()
	_flat2.clear()
	_inc.clear()
	_more.clear()
	_flags.clear()


func add_mod(m: Dictionary) -> void:
	var stat: String = m.get("stat", "")
	if stat == "":
		push_warning("StatBlock.add_mod: mod without stat: %s" % [m])
		return
	var value: float = float(m.get("value", 0.0))
	match m.get("op", OP_FLAT):
		OP_FLAT:
			_flat[stat] = _flat.get(stat, 0.0) + value
			_flat2[stat] = _flat2.get(stat, 0.0) + float(m.get("value2", value))
		OP_INC:
			_inc[stat] = _inc.get(stat, 0.0) + value
		OP_MORE:
			_more[stat] = _more.get(stat, 1.0) * maxf(0.0, 1.0 + value / 100.0)
		OP_FLAG:
			_flags[stat] = _flags.get(stat, 0) + 1
		var other:
			push_warning("StatBlock.add_mod: unknown op '%s' for %s" % [other, stat])


func add_mods(mods: Array) -> void:
	for m in mods:
		add_mod(m)


## Sum of flat mods (for range stats this is the MIN side; use flat_range()).
func flat(stat: String) -> float:
	return _flat.get(stat, 0.0)


## (min, max) of flat mods. Non-range flats return (v, v).
func flat_range(stat: String) -> Vector2:
	return Vector2(_flat.get(stat, 0.0), _flat2.get(stat, 0.0))


## Sum of inc mods, in percent points (25 means 25% increased).
func inc(stat: String) -> float:
	return _inc.get(stat, 0.0)


## Product of more mods as a multiplier (1.0 = none, 1.2 = 20% more).
func more(stat: String) -> float:
	return _more.get(stat, 1.0)


## Sum of inc over several stats, e.g. ["damage", "fire_damage", "spell_damage"].
func sum_inc(stats: Array) -> float:
	var total := 0.0
	for s in stats:
		total += _inc.get(s, 0.0)
	return total


## Product of more over several stats.
func product_more(stats: Array) -> float:
	var total := 1.0
	for s in stats:
		total *= _more.get(s, 1.0)
	return total


func has_flag(flag: String) -> bool:
	return _flags.get(flag, 0) > 0


## (base + flat) * (1 + inc/100) * more. Result is clamped at >= 0 only if the caller does so.
func compute(stat: String, base: float = 0.0) -> float:
	return (base + flat(stat)) * (1.0 + inc(stat) / 100.0) * more(stat)


## True if any mod at all touches this stat.
func has_stat(stat: String) -> bool:
	return _flat.has(stat) or _inc.has(stat) or _more.has(stat) or _flags.has(stat)


func duplicate_block() -> StatBlock:
	var b := StatBlock.new()
	b._flat = _flat.duplicate()
	b._flat2 = _flat2.duplicate()
	b._inc = _inc.duplicate()
	b._more = _more.duplicate()
	b._flags = _flags.duplicate()
	return b


func to_debug_string() -> String:
	var lines: PackedStringArray = []
	var keys := {}
	for d in [_flat, _inc, _more, _flags]:
		for k in d:
			keys[k] = true
	var sorted := keys.keys()
	sorted.sort()
	for k in sorted:
		var parts: PackedStringArray = []
		if _flat.has(k):
			if not is_equal_approx(_flat[k], _flat2[k]):
				parts.append("flat=%s-%s" % [_flat[k], _flat2[k]])
			else:
				parts.append("flat=%s" % _flat[k])
		if _inc.has(k):
			parts.append("inc=%s%%" % _inc[k])
		if _more.has(k):
			parts.append("more=x%.3f" % _more[k])
		if _flags.has(k):
			parts.append("FLAG")
		lines.append("%s: %s" % [k, ", ".join(parts)])
	return "\n".join(lines)

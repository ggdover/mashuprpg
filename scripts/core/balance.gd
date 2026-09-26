class_name Balance
extends RefCounted
## Every tunable progression curve lives here, so balancing is one file. OWNER: kernel (wave 1);
## tuned later by the balance pass. Keep every public signature.
## Formulas: docs/ARCHITECTURE.md §7 (the report scene tests/scenes/kernel_balance_report.tscn
## prints time-to-kill / survivability tables built from these curves).

const MAX_LEVEL := 60
const PLAYER_BASE_MOVE_SPEED := 5.2
## Flat evasion every player has (Player.get_base_mods).
const PLAYER_BASE_EVASION := 15.0
const INVENTORY_COLUMNS := 10
const INVENTORY_ROWS := 6
const STASH_SIZE := 120
const POTION_MAX_CHARGES := 3.0
## Deepest dungeon depth (its boss only opens a town portal).
const MAX_DEPTH := 60
## First clears of depths up to this grant a bonus passive point.
const BONUS_POINT_MAX_DEPTH := 20
## Fraction of the current level's XP requirement lost on death.
const DEATH_XP_PENALTY := 0.1
## Rares roll one more monster mod from this depth on (2-3 -> 3-4).
const RARE_EXTRA_MOD_DEPTH := 10

## Monster rarity multipliers, index = rarity (0 normal, 1 magic, 2 rare, 3 boss). Boss life comes
## from its def's life_mult; "mods" = Vector2i(min, max) number of monster mods
## (rares: see monster_mod_count() for the depth bonus).
const MONSTER_RARITY := [
	{"life": 1.0, "damage": 1.0, "xp": 1.0, "mods": Vector2i(0, 0)},
	{"life": 2.2, "damage": 1.25, "xp": 2.5, "mods": Vector2i(1, 1)},
	{"life": 5.0, "damage": 1.5, "xp": 8.0, "mods": Vector2i(2, 3)},
	{"life": 1.0, "damage": 2.0, "xp": 40.0, "mods": Vector2i(0, 0)},
]


## XP needed to go from `level` to level + 1: round(80 × L^1.9 + 60).
static func xp_to_next(level: int) -> int:
	var l := maxi(1, level)
	return int(roundf(80.0 * pow(float(l), 1.9) + 60.0))


## Total XP needed to reach `level` from level 1 (informational / balance report).
static func total_xp_for_level(level: int) -> int:
	var total := 0
	for l in range(1, clampi(level, 1, MAX_LEVEL)):
		total += xp_to_next(l)
	return total


## Base XP for killing a normal monster of this level (before rarity multiplier and penalty):
## 8 + 2.9 × L^1.45.
static func monster_xp(monster_level: int) -> float:
	return 8.0 + 2.9 * pow(float(maxi(1, monster_level)), 1.45)


## Multiplier (0.05..1) for killing monsters far below/above the player's level.
## safe = 3 + p/16; 1 within the safe range, else max(0.05, 1 − 0.12 × (|p − m| − safe)).
static func xp_penalty(player_level: int, monster_level: int) -> float:
	var safe := 3.0 + float(player_level) / 16.0
	var diff := absf(float(player_level - monster_level))
	if diff <= safe:
		return 1.0
	return maxf(0.05, 1.0 - 0.12 * (diff - safe))


## Final XP of one kill (what GameState.award_kill_xp adds, before rounding).
## xp_mult = def.xp_mult × MONSTER_RARITY[rarity].xp.
static func kill_xp(monster_level: int, xp_mult: float, player_level: int) -> float:
	return monster_xp(monster_level) * maxf(0.0, xp_mult) * xp_penalty(player_level, monster_level)


## Normal-monster life: 12 + 6L + 0.25L² (× def.life_mult × rarity life).
static func monster_life(level: int) -> float:
	var l := float(level)
	return 12.0 + 6.0 * l + 0.25 * l * l


## Average damage of one normal-monster hit at this level (before the damage more-mod):
## 4 + 1.8L + 0.03L².
static func monster_damage(level: int) -> float:
	var l := float(level)
	return 4.0 + 1.8 * l + 0.03 * l * l


## Monster armour: 8L (× def.armour_mult).
static func monster_armour(level: int) -> float:
	return 8.0 * level


## Multiplier applied to skill base_damage for spells, by caster level:
## 1 + 0.16(L−1) + 0.0035(L−1)².
static func spell_damage_scale(level: int) -> float:
	var l := float(maxi(1, level) - 1)
	return 1.0 + 0.16 * l + 0.0035 * l * l


## Weapon base damage multiplier for an effective item level (same curve as spells).
static func weapon_damage_scale(level: int) -> float:
	return spell_damage_scale(level)


## Mana cost multiplier by character level: 1 + 0.03(L−1).
static func mana_cost_scale(level: int) -> float:
	return 1.0 + 0.03 * (maxi(1, level) - 1)


## Resistance penalty (negative) applied to the player in dungeons of this area level:
## −min(40, round(0.8 × area_level)).
static func resist_penalty(area_level: int) -> float:
	return -minf(40.0, roundf(0.8 * area_level))


## Player base life (flat, before Strength and modifiers): 40 + 10L.
static func player_base_life(level: int) -> float:
	return 40.0 + 10.0 * level


## Player base mana (flat, before Intelligence and modifiers): 40 + 6L.
static func player_base_mana(level: int) -> float:
	return 40.0 + 6.0 * level


## Average gold in one gold drop at this area level: 4 + 2L
## (the loot system rolls × 0.5..1.5 × (1 + gold_find/100)).
static func gold_drop(level: int) -> int:
	return 4 + 2 * level


## Monster level for a dungeon depth (depth 1 = level 1).
static func area_level_for_depth(depth: int) -> int:
	return clampi(depth, 1, MAX_DEPTH)


## Gold cost to refund one passive point at this character level: 20 + 8L.
static func passive_refund_cost(level: int) -> int:
	return 20 + 8 * level


## MONSTER_RARITY entry for a rarity (clamped to 0..3).
static func monster_rarity(rarity: int) -> Dictionary:
	return MONSTER_RARITY[clampi(rarity, 0, MONSTER_RARITY.size() - 1)]


## Number of monster mods (min, max) for a rarity at a depth: rares get 3-4 from depth 10.
static func monster_mod_count(rarity: int, depth: int) -> Vector2i:
	var r: Vector2i = monster_rarity(rarity)["mods"]
	if rarity == 2 and depth >= RARE_EXTRA_MOD_DEPTH:
		r += Vector2i(1, 1)
	return r

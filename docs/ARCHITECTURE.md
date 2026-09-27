# Mashup RPG — Architecture & Module Contract (v2)

A 3D action RPG (Diablo / Path of Exile style) in **Godot 4.6.1** (GDScript), with low-poly assets made in
**Blender 5.2** via Python. This document is the contract between modules that are built in parallel. The
*signatures* live in the contract stubs (the `.gd` files marked `CONTRACT STUB`); this document gives the
*semantics*, formulas, data schemas, the asset catalogue and the ownership rules.

> **Golden rules for every module owner**
> 1. **Only edit files you own** (§3, `tools/owners/<module>.txt`). Shared orchestrator files (`events.gd`,
>    `stat_defs.gd`, `ui_style.gd`, `assets.gd`, `controls.gd`, `ui_root.gd`, test framework) are FROZEN
>    during waves. Need a change elsewhere? Put it in your final report (file, line, fix). Work around it
>    in your own files meanwhile.
> 2. Keep every public member, signal and signature of your stubs. Adding more is fine. If a signature
>    *must* change, report it prominently.
> 3. Build node trees in code. The only `.tscn` files are minimal "root node + script" scenes.
> 4. Run Godot **only** through `tools/gtest.sh <your-module>[-suffix] …` — a private copy built from the
>    frozen wave baseline plus *your* files, with its own `.godot/` and `user://`. Its summary splits
>    errors into YOUR files vs OTHER modules'; yours must be zero. Never run Godot directly on the repo.
> 5. **Your files must parse at all times**: write a file in one go, then immediately run the parse check
>    (§18) and fix it before moving on. Never leave a file half-edited while a long job runs.
>    Generated files (glb, png, json) are written atomically (`.tmp` then rename, §14.1).
> 6. Never crash on missing data or assets: `push_warning`, fall back, continue. (`push_error` fails tests.)
> 7. Never keep a Node reference (Player, Actor, target, projectile owner) across frames without
>    `is_instance_valid()`. Re-read `GameState.player` each time. Inside a World, time things with
>    `_physics_process` counters, node-owned `Timer`s or `create_tween()` — never
>    `await get_tree().create_timer()` (a World kept for a town portal leaves the tree).
> 8. New `class_name`s use your module prefix (§4). Prefer `const X := preload("…")` for internal classes.

---------------------------------------------------------------------------------------------------------

## 1. The game

**Loop:** create a character (Warrior / Ranger / Sorcerer) → town hub → waypoint to dungeon depth N →
fight packs of monsters, loot items and gold, gain XP → kill the depth boss → portals to the next depth
or town → sell/craft/stash in town, spend passive points, pick skills → go deeper (up to depth 60).
Monster level = depth. Death returns you to town (10% of the level's XP lost) with the dungeon kept, so
you can go back through the portal and retry.

**Systems:** stats built from modifiers (base + gear + passives + buffs); 5 damage types
(physical, fire, cold, lightning, chaos) and 6 ailments (ignite, chill, freeze, shock, bleed, poison);
24 player skills (melee, bow, crossbow, spells, warcry, movement); gear in 10 slots with rarities
normal/magic/rare/unique, random affixes and local/global mods; a ~400-node passive tree with notables
and keystones; procedural dungeons; vendor with crafting; stash; save/load.

**Controls** (registered in code by `Controls`):

| Action | Key | Action | Key |
|---|---|---|---|
| move | WASD / arrows | skill slots 1–6 | LMB, MMB, Q, E, R, F |
| dodge roll | Space | parry | Shift |
| life / mana potion | 1 / 2 | orbit camera | hold RMB |
| inventory | I | character sheet | C |
| passive tree | P | skill book | K |
| town portal | T | show all loot labels | hold Alt |
| minimap size | Tab | pause / close panel | Esc |
| zoom | mouse wheel | debug (debug builds) | F9 level, F10 loot, F11 god, F12 screenshot |

LMB on a hovered loot item/label or interactable walks there and picks up / interacts instead of using
skill 1. Holding a skill key repeats the skill. The character always aims at the mouse.

---------------------------------------------------------------------------------------------------------

## 2. Engine conventions

- **Godot 4.6.1**, GDScript only, tabs, static typing where practical. Binary:
  `/opt/godot/Godot_v4.6.1-stable_linux.x86_64`. Blender: `blender` (5.2, on PATH). Physics: **Jolt**.
- **Units** metres, **Y up**, floor at **y = 0**. Actors move on the XZ plane: no gravity,
  `velocity.y = 0`, no floor collision, `motion_mode = MOTION_MODE_FLOATING` (set in `Actor._init`).
  Mouse aiming intersects the plane y = 0 mathematically.
- **Facing:** models face **+Z** in Godot (they face −Y in Blender). An actor faces direction `d` with
  `rotation.y = atan2(d.x, d.z)` (`Actor.face_towards`). Forward = `global_transform.basis.z`. Don't call
  `look_at()` on actors (it points −Z) unless you pass `use_model_front = true`. A character facing +Z
  has its right hand on −X.
- **Physics layers** (named in project.godot):

  | Layer | Value | Name | Used by | Mask |
  |---|---|---|---|---|
  | 1 | 1 | world | walls, pillars, large props (StaticBody3D) | – |
  | 2 | 2 | player | Player (CharacterBody3D) | 1 + 4 = **5** (world, enemies) |
  | 3 | 4 | enemies | Enemy (CharacterBody3D) | 1 + 2 + 4 = **7** |
  | 4 | 8 | loot | GroundItem (Area3D, pick shapes only) | 0 |
  | 5 | 16 | interactables | Interactable (Area3D) | 0 |

  Mouse hover ray: `collision_mask = 4 | 8 | 16` (= 28), areas and bodies. Skills don't use physics bodies
  for hits: they use `CombatQuery` (distance tests over group `actors`) and `CombatQuery.raycast_world`.
- **Groups:** `actors`, `team_0` (player side), `team_1` (enemies), `player`, `enemies`, `boss`,
  `interactable`, `loot`, `world`.
- **Signals:** cross-module notifications go through `Events`. Signals have no default arguments —
  always emit every parameter.
- **Randomness:** dungeon layout is seeded (`RandomNumberGenerator` with `area_info.seed`). Combat and loot
  may use the global RNG.
- **Pausing:** only the pause menu pauses the tree. `UI` and `Sfx` use `PROCESS_MODE_ALWAYS`.
- **Performance budget** (Intel Arc iGPU, 1080p, 60 fps): floors/walls via `MultiMeshInstance3D`;
  ≤ 20 shadowless `OmniLight3D` per area plus the player light; small `GPUParticles3D` amounts; ≤ 70
  spawned enemies per dungeon (+ summons); enemies > 40 m from the player sleep; merged wall collision.
- **Shared resources:** meshes, materials and animations from `Assets` (and any imported glb) are shared by
  every instance. Never mutate them: use `Assets.tint/set_flash/set_fade` or per-instance overrides, and
  `duplicate()` a Mesh before changing its surface materials.
- **Scenes:** `scenes/main.tscn` (main), `tests/test_runner.tscn`, `tools/godot/*.tscn` (checks/probes)
  and small demo scenes under `tests/scenes/`. Everything else is built in code. Materials are created
  in code (no `.tres`).

---------------------------------------------------------------------------------------------------------

## 3. Directory layout & ownership

```
project.godot  icon.svg
docs/ARCHITECTURE.md  docs/screenshots/<module>/
tools/gtest.sh  tools/gtest_classify.py  tools/owners/<module>.txt  tools/godot/  tools/blender/<module>/  tools/tree/  tools/audio/
assets/models/<id>.glb  assets/icons/items/<model_id>.png  assets/icons/skills/<skill_id>.png  assets/audio/<id>.wav
data/passive_tree.json
scenes/main.tscn
scripts/autoload/  scripts/core/  scripts/items/  scripts/skills/  scripts/vfx/  scripts/world/
scripts/entities/player/  scripts/entities/enemies/  scripts/ui/<panel>/  scripts/main/  scripts/debug/
tests/test_runner.tscn  tests/unit/test_<module>_*.gd  tests/scenes/<module>_*.{tscn,gd}
```

The exact globs per module are in `tools/owners/<module>.txt` (used by gtest isolation):

| Module | Wave | Owns |
|---|---|---|
| orchestrator | 0 | `project.godot`, docs, `tools/gtest*`, `tools/owners/`, `tools/godot/parse_check.*`, `scripts/autoload/{controls,events,assets,sfx}.gd`, `scripts/core/{stat_block,stat_defs}.gd`, `scripts/world/interactable.gd`, `scripts/ui/{ui_style,ui_root}.gd`, test framework (`tests/test_*.gd`, `tests/error_logger.gd`, `tests/unit/test_core_*`) |
| **kernel** | 1 | `scripts/core/{actor,hit_data,damage_calc,combat_query,balance,class_defs,character_data}.gd`, `scripts/core/kernel_*`, `scripts/autoload/game_state.gd`, `tests/unit/test_kernel_*`, `tests/scenes/kernel_*` |
| **items** | 1 | `scripts/items/**`, `scripts/autoload/item_db.gd`, `tests/unit/test_items_*`, `tests/scenes/items_*` |
| **tree** | 1 | `tools/tree/**`, `data/passive_tree.json`, `scripts/autoload/tree_db.gd`, `tests/unit/test_tree_*`, `tests/scenes/tree_*` |
| **world** | 1 | `scripts/world/**` except `interactable.gd`, `tests/unit/test_world_*`, `tests/scenes/world_*` |
| **assets-characters** | 1 | `tools/blender/characters/**`, models `char_*`, `weapon_*`, `offhand_*`, `armor_*`, `jewel_*`, `loot_*`, `assets/icons/items/**`, `tools/godot/probe_characters.*`, `tests/scenes/assets_characters_*` |
| **assets-environment** | 1 | `tools/blender/environment/**`, models `env_*`, `town_*`, `proj_*`, `assets/icons/skills/**`, `tools/godot/probe_environment.*`, `tests/scenes/assets_environment_*` |
| **skills** | 2 | `scripts/autoload/skill_db.gd`, `scripts/skills/**`, `scripts/vfx/**`, `tests/unit/test_skills_*`, `tests/scenes/skills_*` |
| **player** | 2 | `scripts/entities/player/**`, `tests/unit/test_player_*`, `tests/scenes/player_*` |
| **enemies** | 2 | `scripts/autoload/enemy_db.gd`, `scripts/entities/enemies/**`, `tests/unit/test_enemies_*`, `tests/scenes/enemies_*` |
| **ui-hud** | 2 | `scripts/ui/hud/**`, `tests/unit/test_ui_hud_*`, `tests/scenes/ui_hud_*` |
| **ui-items** | 2 | `scripts/ui/{inventory,character,stash,vendor,tooltip}/**`, `tests/unit/test_ui_items_*`, `tests/scenes/ui_items_*` |
| **ui-menus** | 2 | `scripts/ui/{passive_tree,skills,waypoint,menus}/**`, `tests/unit/test_ui_menus_*`, `tests/scenes/ui_menus_*` |
| **flow** | 2 | `scenes/main.tscn`, `scripts/main/**`, `scripts/debug/**`, `tests/unit/test_flow_*`, `tests/scenes/flow_*` |
| audio | 3 | `assets/audio/**`, `tools/audio/**` |

`scripts/autoload/game_state.gd` belongs to kernel in wave 1; in wave 2 the flow module may extend it
with area-transition helpers (kernel is done by then).

---------------------------------------------------------------------------------------------------------

## 4. Autoloads & class names

| Name | Script | Purpose |
|---|---|---|
| `Controls` | `scripts/autoload/controls.gd` | builds the InputMap; `label_for(action)`, `skill_slot_label(i)` |
| `Events` | `scripts/autoload/events.gd` | signal bus |
| `Assets` | `scripts/autoload/assets.gd` | `model/mesh/item_icon/skill_icon` + model helpers (`prepare_animations`, `find_skeleton`, `find_part`, `attach_to_bone`, `tint`, `set_flash`, `set_fade`) |
| `Sfx` | `scripts/autoload/sfx.gd` | `play(id, pos)`, `play_ui(id)`; missing files ignored |
| `ItemDB` | `scripts/autoload/item_db.gd` | bases, affixes, uniques, generation, crafting |
| `SkillDB` | `scripts/autoload/skill_db.gd` | skill definitions, `get_resolved(id, actor)` |
| `TreeDB` | `scripts/autoload/tree_db.gd` | passive tree data + allocation rules |
| `EnemyDB` | `scripts/autoload/enemy_db.gd` | monster archetypes, mods, spawning |
| `GameState` | `scripts/autoload/game_state.gd` | character, save/load, XP awards, live `player`/`world`, `vendor_stock` |
| `UI` | `scripts/ui/ui_root.gd` (`class_name UIRoot`) | HUD, panels, tooltip, notifications |

**Autoload rule:** `_ready()` may only load data and create hidden nodes. UIRoot starts with the HUD hidden
and no panel open; only `main.gd` calls `UI.show_main_menu()`. The HUD binds to a player on
`Events.player_spawned`. `GameState` loads no save by itself. `GameState.player/world` may be null.

**Global classes:** `StatBlock`, `StatDefs`, `HitData`, `DamageCalc`, `CombatQuery`, `Balance`,
`ClassDefs`, `CharacterData`, `Actor`, `Player`, `CameraRig`, `Enemy`, `Item`, `LootSystem`, `GroundItem`,
`Interactable`, `World`, `SkillRunner`, `StatusVisuals`, `UIRoot`, `UIStyle`, `HUD`, `TooltipPanel`, the
panel classes, `TestCase`, `TestDummy`. **New class names** must start with the module prefix:
`Kernel*` (kernel), `Item*`/`Loot*` (items), `Tree*` (tree), `World*` (world), `Skill*`/`Vfx*` (skills),
`Player*` (player), `Enemy*` (enemies), `Hud*` (ui-hud), `Inv*`/`Tooltip*` (ui-items),
`Menu*`/`TreePanel*` (ui-menus), `Flow*`/`Debug*` (flow). A test fails on duplicate class names.

---------------------------------------------------------------------------------------------------------

## 5. Stats and modifiers

### 5.1 Mods
A mod is `{"stat", "op", "value"[, "value2"]}`; ops `flat` / `inc` / `more` / `flag`. `StatBlock` sums them:
`final = (base + flat) × (1 + Σinc/100) × Π(1 + more/100)`. `value2` makes a flat mod a min–max range
(added damage). Build mods with `StatBlock.mod(stat, op, value, value2)`. The vocabulary and tooltip text
are in `StatDefs.STATS`; every stat referenced by items, passives, skills, buffs or monsters must exist
there (tests check). `local_*` stats only exist on items and are folded into that item's own numbers (§9.3).

### 5.2 Attributes
`attr = (flat(attr) + flat(all_attributes)) × (1 + (inc(attr) + inc(all_attributes))/100)`.
Bonuses, injected as extra mods during `recalculate_stats()`:
- **Strength**: +1 max_life per 2; +1% inc melee_damage per 5.
- **Dexterity**: +1% inc evasion per 5; +1% inc attack_speed per 10; +1% inc projectile_damage per 10.
- **Intelligence**: +1 max_mana per 2; +1% inc max_energy_shield per 5; +1% inc spell_damage per 10.

### 5.3 Derived values (`Actor.recalculate_stats`)
Order: attributes → attribute bonus mods → everything else. Keep current life/mana/ES *ratios* when maxima
change (a fresh actor starts full).
- `max_life = max(1, compute("max_life"))`; the base comes from `get_base_mods()` as flat mods.
- `max_mana = compute("max_mana")`; **blood_magic** → 0. `max_es = compute("max_energy_shield")`.
- `life_regen/s = flat(life_regen) + max_life × flat(life_regen_percent)/100`.
- `mana_regen/s = (2 + 0.03 × max_mana) × (1 + inc(mana_regen)/100)` (0 without mana).
- ES recharge: once `time_since_damaged ≥ 2.0` s, +25% of max ES per second × (1 + inc(energy_shield_recharge)/100).
- `armour = compute("armour")`, `evasion = compute("evasion")`; **iron_reflexes** →
  `armour = compute("armour") + evasion × stats.more("armour")`, `evasion = 0`.
- `block_chance = min(75, flat(block_chance))`.
- `resistances[t] = clamp(flat(t_resistance) + flat(elemental_resistance) [elemental only], -100, 75)`; chaos
  without the elemental term; `resistances.physical = clamp(flat(physical_damage_reduction), 0, 75)`.
  In dungeons the Player adds `Balance.resist_penalty(area_level)` as flat mods to
  `elemental_resistance` and `chaos_resistance` (shown on the character sheet).
- Move speed = `base_move_speed × (1 + inc(movement_speed)/100) × more(movement_speed) × (1 − chill)`;
  0 while frozen.

---------------------------------------------------------------------------------------------------------

## 6. Combat

### 6.1 Damage types & tags
Types: `physical fire cold lightning chaos`; elemental = fire/cold/lightning. Scaling tags:
`attack spell melee projectile area` (+ damage-type tags, `channel`, `movement`, `warcry`, `duration`,
`chain`, `nova` for display/filtering).

### 6.2 Weapon dictionary
`Actor.get_weapon()` and `Item.get_weapon_stats()` return
`{"weapon_type", "phys_min", "phys_max", "added": {type: Vector2}, "attack_speed", "crit_chance", "range", "two_handed"}`.
Player: main-hand item or `DamageCalc.UNARMED`. Monsters: `weapon_type = "monster"`, phys =
`Balance.monster_damage(level) × [0.8, 1.2]` (no multipliers), `attack_speed = def.attack_speed`,
crit 5, `range = def.melee_range`. The monster's archetype and rarity multiplier is a stat mod added by
`Enemy.get_base_mods()`: `StatBlock.mod("damage", "more", (def.damage_mult × Balance.MONSTER_RARITY[rarity].damage − 1) × 100)`,
so it scales monster attacks and monster spells alike. DamageCalc never reads `Enemy.def`.

### 6.3 `DamageCalc.build_hit(attacker, skill, opts)` (skill = resolved dict)
1. **Base ranges per type**
   - Monster skills with `skill.monster_damage` (e.g. `{"physical": 0.6, "fire": 0.4}`):
     `Balance.monster_damage(level) × fraction × skill.damage_mult` → range ×0.8..×1.2.
   - Attacks (`"attack"` in tags): weapon phys range + weapon `added` + `stats.flat_range("added_<t>_attack")`
     per type, all × `skill.damage_effectiveness` (default 1).
   - Spells: `skill.base_damage[t] × Balance.spell_damage_scale(level)` +
     `stats.flat_range("added_<t>_spell") × skill.damage_effectiveness`.
2. **Conversion** `skill.conversion = {"physical": {"fire": 0.5}}` moves that fraction of the range to the
   new type before scaling; converted damage scales only as its new type.
3. **Roll** each type uniformly in [min, max].
4. **Scale**: `inc = stats.sum_inc(S)`, `more = stats.product_more(S)`, `S = get_scaling_stats(type, tags,
   weapon_type, two_handed)` = `damage, <type>_damage, [elemental_damage], [attack_damage], [spell_damage],
   [melee_damage], [projectile_damage], [area_damage]`, plus for attacks with a real weapon
   (not unarmed/monster) `<weapon_type>_damage` and `two_handed_damage`|`one_handed_damage`. Multiply by
   `(1 + inc/100) × more × (1 + skill.more_damage/100) × (1 + opts.more/100) × opts.effectiveness` and
   keystone conditionals: **pain_attunement** (spell, attacker ≤ 35% life) ×1.3; **point_blank**
   (projectile; d = distance origin→target): ×1.5 at d ≤ 2 m, lerp to ×0.7 at d ≥ 12 m.
5. **Crit**: chance = `(base + flat(base_crit_chance)) × (1 + inc(crit_chance)/100) × more(crit_chance)`,
   cap 95; base = weapon crit (attacks) or `skill.crit_chance` (spells, default 5). **no_crit** → 0.
   Multiplier `150 + flat(crit_multiplier)` %.
6. **Ailments** (chance % = `skill.ailments[k] + flat(<k>_chance)`, rolled per hit, needs the damage type;
   `dot = 1 + inc(damage_over_time)/100`; durations × `get_duration_mult`):
   - ignite (fire > 0): `{"dps": 0.5 × fire × dot, "duration": 4}`
   - bleed (attack, physical > 0): `{"dps": 0.5 × phys × dot, "duration": 4}`
   - poison (physical or chaos > 0): `{"dps": 0.2 × (phys + chaos) × dot, "duration": 2}` (stacks)
   - shock (lightning > 0): `{"effect": 0.2, "duration": 4}`
   - freeze (cold > 0): `{"duration": 0.8}` (subject to the threshold in §6.4)
7. `can_evade = "attack" in tags`; `can_block = "attack" or "projectile" in tags`; `source_level = attacker.level`.

### 6.4 Ailments on the target (`Actor`)
- **chill**: whenever cold damage is taken (after mitigation): effect =
  `clamp(cold_taken / max_life × 2, 0.1, 0.3)` for 2 s; keep the stronger. Slows movement and action speed.
- **freeze**: only if the hit's mitigated cold damage ≥ 5% of max life (bosses 10%) and
  `freeze_immune_time <= 0`. Can't move or act. Bosses (`is_boss_actor`) take ×0.3 duration. When a freeze
  ends: `freeze_immune_time = 2` (bosses 6). Players too.
- **shock**: +`effect` damage taken (hits and DoTs); keep the stronger.
- **ignite / bleed**: one instance; a new one replaces the old if its dps is higher (else refresh duration).
- **poison**: stacks `{"stacks": [{"dps", "time_left"}], "dps": total, ...}`, max 20.
- **stun**: not rolled from hits; applied by the player's parry counter (`apply_ailment("stun",
  {"duration"})`). Like freeze it stops moving and acting (`can_act()` false, cancels the current skill;
  `is_stunned()`), without ice or an immunity afterwards. Stars circle over the head (StatusVisuals);
  monsters flinch when stunned.
- Bosses: all ailment durations ×0.5 (freeze ×0.3).
- DoTs tick every physics frame via `take_damage(dps × delta, type, true)`: resistance of its type applies
  (bleed: only physical_damage_reduction), shock applies, ES absorbs, MoM applies, never evaded/blocked.
  `take_damage(is_dot = true)` never emits a number per call: the Actor accumulates DoT damage and emits
  one `Events.damage_number(get_aim_point(), sum, type, false)` per type every 0.5 s.
- State dicts always include `"time_left"` and `"duration"`. Emit `ailment_changed(kind, true/false)`.

### 6.5 `Actor.take_hit(hit)`
1. Dead, `god_mode`, or `invulnerable_time > 0` → return 0.
2. Evade (if `hit.can_evade` and not `cannot_evade`): chance = `DamageCalc.evade_chance(self, hit.source_level)` =
   `100 × evasion / (evasion + 200 + 40 × attacker_level) + flat(evade_chance)`, cap 75 → emit
   `Events.damage_number(pos, 0, "evade", false)`, return 0.
3. Block (if `hit.can_block`): roll `block_chance` → `"block"`, return 0.
4. Mitigate per type: physical × `(1 − armour_reduction(armour, raw))` × `(1 − resist.physical/100)`,
   `armour_reduction = min(0.9, armour / (armour + 10 × raw))`; others × `(1 − resist/100)`.
   Then × `(1 + inc(damage_taken)/100) × more(damage_taken) × (1 + shock)`.
5. **mind_over_matter**: 30% of the total comes from mana first (as much as available). **ES** absorbs the
   rest before life. `time_since_damaged = 0`.
6. Apply `hit.ailments` (freeze threshold/immunity) and chill.
7. Emit `damaged(total, is_crit, source)` and `Events.damage_number(get_aim_point(), total, kind, crit)` with
   kind = `"player_hurt"` for the player's team, else `hit.dominant_type()`.
8. `source.on_hit_dealt(self, hit, total)` if valid → life/mana leech (instant) and life_on_hit. Leech +
   life_on_hit together restore at most 20% of max life per rolling second (mana leech 20% of max mana);
   life_on_hit counts at most 5 targets per skill use/tick.
9. `life ≤ 0` → `die(source)`: `dead = true`, collision layers cleared, `died` emitted, `killer.on_kill(self)`
   (life_on_kill / mana_on_kill), then `_on_death(killer)`.

### 6.6 Buffs & costs
- `add_buff(id, {"name","mods","duration","icon"})` stores `time_left`; buff mods are part of `stats`
  (recalc on add/expire); emits `buffs_changed`. `"icon"` is a skill id (HUD uses `Assets.skill_icon`).
- `pay_cost(amount)`: mana, or life under **blood_magic** (only if life stays > amount).
  Enemies never pay costs.

### 6.7 Hit recovery
Player: never interrupted by hits (only freeze and dodge cancel skills); plays `hit` only when not busy
and the hit ≥ 10% of max life. Enemies (not bosses): a single hit ≥ 20% of max life (after mitigation)
calls `skill_runner.cancel()` (windups included) and plays `hit`, then 1.5 s stagger immunity. Bosses never
flinch.

---------------------------------------------------------------------------------------------------------

## 7. Balance (starting curves in `Balance`; the balance pass tunes them)

| Function | Formula |
|---|---|
| `xp_to_next(L)` | `round(80 × L^1.9 + 60)` |
| `monster_xp(L)` | `8 + 2.9 × L^1.45` |
| `xp_penalty(p, m)` | safe = 3 + p/16; `1` if abs(p−m) ≤ safe else `max(0.05, 1 − 0.12 × (abs(p−m) − safe))` |
| `monster_life(L)` | `12 + 6L + 0.25L²` (normal; × def.life_mult × rarity life) |
| `monster_damage(L)` | `4 + 1.8L + 0.03L²` (average hit, before the damage more-mod) |
| `monster_armour(L)` | `8L` (× def.armour_mult) |
| `spell_damage_scale(L)` | `1 + 0.16(L−1) + 0.0035(L−1)²` |
| `weapon_damage_scale(L)` | = `spell_damage_scale(L)` |
| `mana_cost_scale(L)` | `1 + 0.03(L−1)` |
| `resist_penalty(area_level)` | `−min(40, round(0.8 × area_level))` |
| `player_base_life(L)` | `40 + 10L` |
| `player_base_mana(L)` | `40 + 6L` |
| `gold_drop(L)` | `4 + 2L` (× 0.5..1.5 × (1 + gold_find/100)) |
| `area_level_for_depth(d)` | `d` (depths 1..`MAX_DEPTH` = 60) |
| `passive_refund_cost(L)` | `20 + 8L` |

`Balance.MONSTER_RARITY` holds rarity multipliers (life, damage, xp, number of mods): normal 1/1/1/0,
magic 2.2/1.25/2.5/1, rare 5/1.5/8/2–3 (3–4 from depth 10), boss 1(def life_mult 25)/2/40/0.
Monster attack speed 0.7–1.0 (m_bite ≈ 1.4); AI waits a random 0.3–0.8 s between skill uses.
Player base: `base_move_speed = Balance.PLAYER_BASE_MOVE_SPEED` (5.2 m/s), 15 flat evasion.

### 7.1 Levels glossary
- `Actor.level`: Player = `character.level` (set in `Player.setup` and on `Events.level_up`, before
  `recalculate_stats`); Enemy = `area_info.level`; summons use the summoner's level.
- `area_info.level`: town 1; dungeon `Balance.area_level_for_depth(depth)`.
- `Item.item_level` = level of the monster, chest or vendor that created it. Base `level` = minimum item
  level for the base to drop and its requirement level. Skill `unlock_level` is compared to `character.level`.

---------------------------------------------------------------------------------------------------------

## 8. Skills

### 8.1 Definition schema (`SkillDB.get_skill(id)`)
```
{
  "id": "fireball", "name": "Fireball", "description": "…",
  "tags": ["spell", "projectile", "area", "fire"],
  "weapon_types": [],                 # [] = any; else weapon types or the alias "melee"
  "unlock_level": 1, "monster_only": false,
  "mana_cost": 6.0, "cooldown": 0.0,  # cost × Balance.mana_cost_scale(level) × modifiers
  "cast_time": 0.75,                  # spells
  "attack_time_mult": 1.0,            # attacks: seconds = attack_time_mult / attack_speed
  "base_damage": {"fire": [9, 14]},   # spells, level-1 values (× Balance.spell_damage_scale)
  "damage_effectiveness": 1.0, "more_damage": 0.0,
  "monster_damage": {"physical": 1.0}, "damage_mult": 1.0,   # monster skills
  "conversion": {"physical": {"fire": 0.5}},
  "crit_chance": 6.0, "ailments": {"ignite": 25},
  "delivery": "projectile", "params": {…},
  "anim": "cast", "hit_frame": 0.45, "move_mult": 0.0,
  "vfx": {"color": Color(…), "model": "proj_arrow"}, "sfx": {"use": "fireball_cast", "hit": "explosion"}
}
```
Monster skills: `monster_only: true`, `weapon_types: []`, `mana_cost: 0`. **Skill ids in §8.4/§8.5 are
frozen** (icons, class defs and enemy defs reference them); numbers may change.
Everything outside SkillRunner (character sheet, tooltips, HUD, bot) uses `SkillDB.get_resolved(id, actor)`
before calling `DamageCalc`.

### 8.2 SkillRunner timeline
`can_use(id)` → `{"ok", "reason", "code"}` with code `ok|unknown|cannot_act|level|weapon|cost|cooldown`
(never "busy"). `try_use(id, target_pos, target)`: validate (exists, `actor.can_act()`, not busy, unlocked
for players, weapon compatible via `SkillDB.is_weapon_compatible(id, weapon_type)`, off cooldown, cost for
players), failures for the player emit `Events.skill_use_failed(reason)` (throttled ≥ 1 s per reason).
Then: resolve (`SkillDB.resolve_for_weapon`), pay the cost, face the target,
`duration = DamageCalc.get_use_time(actor, skill) / (1 − chill)`, `actor.play_action_animation(anim, duration)`,
emit `skill_started`; at `hit_frame × duration` run the delivery (`skill_effect`); at `duration` finish.
Cooldowns start on use. Freeze or dodge cancels (`cancel()` → `actor.stop_action_animation()`). Channel
skills: `play_action_animation("channel", 0)` (loops), tick every `get_use_time` while held (cost per tick),
end on release/out of mana → `stop_action_animation()`. `movement_multiplier()` = `move_mult` while busy;
for the player at least `PLAYER_SKILL_MOVE_MULT` (0.35: skills slow the player instead of rooting), except
movement-tagged skills (leap, teleport). `is_recovering()` / `end_recovery()`: once the effect has happened,
its travel is over and nothing it spawned still runs, the rest of the use can be cut (the player moves
off with the key released).

**Parry empowerment** (`SkillEmpower`, `scripts/skills/skill_empower.gd`): `try_use` asks the actor
`consume_empower()` (Player: a parry charge) for damaging skills (`can_empower`: not buff / blink /
summon) and marks the `SkillUse` (`empowered`, `more_damage` +50% on every hit, `extra_projectiles` +2 for
projectile / sequence deliveries, `extra_chains` +2, `area_mult` ×1.4 for area deliveries and explosions,
`echo` for attack melee / projectile deliveries). An echo repeats the delivery once `ECHO_DELAY` (0.22 s)
after the effect, from where the caster stands, with a quick replay of the attack animation.

### 8.3 Deliveries (`params`)
| delivery | params | notes |
|---|---|---|
| `weapon_default` | – | basic attack: melee weapon → `melee_arc` (angle 80); bow → `projectile` (`proj_arrow`, speed 28); crossbow → `projectile` (`proj_bolt`, speed 34, pierce 1); wand → `projectile` (glowing orb, speed 22); tags get `melee` or `projectile` |
| `melee_arc` | `range_add` (+weapon range), `angle`, `max_targets` (0 = all) | cone test at hit frame; swing VFX |
| `projectile` | `speed`, `count`, `spread` (deg total), `pierce`, `chain`, `radius`, `range`, `explode_radius`, `explode_effectiveness`, `model`, `shotgun` | flies at y ≈ 1.1; stops at walls (`raycast_world`) |
| `aoe_target` | `radius`, `max_range`, `delay`, `telegraph` | meteor-style |
| `rain` | `radius`, `impacts`, `impact_radius`, `duration`, `max_range` | random impact points |
| `nova` | `radius`, `expand_time` | centred on caster |
| `chain` | `range`, `chain`, `chain_range` | instant beam segments |
| `channel_aoe` | `radius`, `cost_per_tick`, `effectiveness` | tick = `DamageCalc.get_use_time` (attack_time_mult / attack speed) |
| `leap` | `max_range`, `duration`, `radius` | arc movement, AoE on landing |
| `blink` | `max_range` | teleport to `world.get_nearest_walkable(target)` |
| `buff` | `duration`, `mods`, `radius` | warcry / self buff + visual |
| `sequence` | `repeat`, `interval` + projectile params | rapid fire |
| `ground_dot` | `radius`, `duration`, `tick`, `effectiveness` | poison cloud; ticks `take_damage(…, true)` |
| `summon` | `enemy_id`, `count`, `radius` | monsters: `EnemyDB.spawn_enemy` (adds them itself) |
| `charge` | `max_range`, `speed`, `radius` | monsters/bosses: dash then hit |

Rules: **Explosions** — a projectile with `explode_radius` has no separate direct hit: on impact (actor or
wall) or at max range it explodes, damaging every hostile in the radius (the impacted one included) at
`explode_effectiveness`. Secondary explosions of melee skills exclude actors already hit by that use.
**Multiple projectiles** from one use hit each target at most once (all projectiles of a use share a
hit set), except `shotgun: true` (scatter_shot only), where each extra projectile on the same target
deals 50% less. **Windup**: any delivery may have `windup` (s) — a red ground telegraph (disc/cone/line)
fills up before the effect. Everything spawned goes through `GameState.world.add_dynamic()` (summons via
`EnemyDB.spawn_enemy`) and frees itself.

### 8.4 Player skills (ids frozen; starting numbers — skills owns final values)
| id | name | tags | weapon | lvl | delivery / key params | cost |
|---|---|---|---|---|---|---|
| basic_attack | Attack | attack (+melee/projectile) | any | 1 | weapon_default, eff 1.0 | 0 |
| heavy_strike | Heavy Strike | attack melee | melee | 1 | melee_arc angle 50, eff 1.75, time ×1.25 | 4 |
| cleave | Cleave | attack melee area | melee | 1 | melee_arc angle 160, range_add 0.8, eff 1.0 | 4 |
| ground_slam | Ground Slam | attack melee area | melee | 4 | melee_arc cone range_add 4 (≈6 m), angle 50, eff 1.3; shockwave VFX | 7 |
| leap_slam | Leap Slam | attack melee area movement | melee | 6 | leap max 10, radius 2.5, eff 1.2 | 10 |
| whirlwind | Whirlwind | attack melee area channel | melee | 8 | channel_aoe radius 2.6, attack_time_mult 0.45, eff 0.55, move ×0.6 | 3/tick |
| infernal_blow | Infernal Blow | attack melee area fire | melee | 10 | melee_arc + explosion r 2.5 (60%), 50% phys→fire | 7 |
| war_cry | War Cry | warcry area | any | 3 | buff 6 s: +30% inc damage, +10% inc attack speed; cd 10 | 8 |
| power_shot | Power Shot | attack projectile | bow | 1 | projectile pierce 99, speed 32, eff 1.9 | 5 |
| split_arrow | Split Arrow | attack projectile | bow | 1 | projectile count 5, spread 50, eff 0.8 | 5 |
| rain_of_arrows | Rain of Arrows | attack projectile area | bow | 8 | rain radius 3.5, impacts 8, eff 0.55 | 10 |
| explosive_bolt | Explosive Bolt | attack projectile area fire | crossbow | 1 | projectile explode 2.5, 40% phys→fire, eff 1.3 | 6 |
| scatter_shot | Scatter Shot | attack projectile | crossbow | 4 | projectile count 7, spread 40, range 11, eff 0.6, shotgun | 7 |
| rapid_fire | Rapid Fire | attack projectile | crossbow | 8 | sequence 5 × 0.1 s, eff 0.7, attack_time_mult 2.2 | 8 |
| ice_shot | Ice Shot | attack projectile cold | bow, crossbow | 6 | 100% phys→cold, pierce 2, freeze 10% | 6 |
| venom_arrow | Venom Arrow | attack projectile area chaos duration | bow, crossbow | 12 | projectile → ground_dot 3 s r 2.5; 100% poison | 8 |
| fireball | Fireball | spell projectile area fire | – | 1 | speed 18, explode 2.2, base 9–14 fire, ignite 25%, cast 0.75 | 5 |
| ice_spear | Ice Spear | spell projectile cold | – | 3 | speed 32, pierce 3, base 12–18 cold, crit 8, cast 0.7 | 6 |
| frost_nova | Frost Nova | spell area cold nova | – | 4 | radius 4.5, base 10–15 cold, freeze 25%, cd 3 | 10 |
| chain_lightning | Chain Lightning | spell lightning chain | – | 5 | chain range 14, chain 4, base 3–26 lightning, shock 20% | 7 |
| teleport | Teleport | spell movement | – | 6 | blink 12 m, cd 3 | 8 |
| spark | Spark | spell projectile lightning | – | 10 | 5 wandering projectiles, 1.5 s, base 2–18 | 7 |
| meteor | Meteor | spell area fire | – | 14 | aoe_target delay 1.0, r 3.5, base 40–60 fire, cd 4 | 20 |
| blood_rite | Blood Rite | spell duration | – | 16 | buff 8 s: 30% more spell_damage, 20% inc damage_taken; cd 12 | 8 |

Target single-target throughput for attack skills: 1.3–1.8× `basic_attack` per second.

### 8.5 Monster skills (ids frozen)
`m_melee` (weapon swing, melee_arc angle 70), `m_bite` (fast, attack_time_mult 0.7), `m_arrow` (projectile
speed 22), `m_firebolt` (fire projectile, explode 1.5), `m_frostbolt` (cold projectile), `m_slam` (windup 0.9,
cone r 3.5), `m_summon` (`{"enemy_id": "skeleton_warrior", "count": 2}`), `m_leap` (ghoul leap),
`m_boss_nova` (expanding fire ring, windup 1.0), `m_boss_volley` (7 firebolts fan), `m_boss_charge`,
`m_boss_meteors` (3 telegraphed impacts near the target), `m_boss_slam` (big cone, windup 1.2),
`m_boss_spikes` (rain: 5–6 telegraphed spike impacts along the line to the target, impact_radius 1.2,
windup 0.8, `monster_damage {"physical": 1.0}`).

### 8.6 VFX
Colour by damage type (`UIStyle.DAMAGE_COLORS`), unshaded additive emissive materials, short-lived
`OmniLight3D` only for fireballs/explosions, small `GPUParticles3D`. Melee: swing arc ribbon. Hits: spark
burst. `StatusVisuals.attach(actor)` shows ailments (Player and Enemy call it in `_ready`). Telegraphs:
translucent red discs/cones on the ground that fill up over the windup.

---------------------------------------------------------------------------------------------------------

## 9. Items

### 9.1 Slots
Equipment slots → accepted slot type: `main_hand→weapon, off_hand→offhand, helmet, body, gloves, boots,
amulet, ring_1→ring, ring_2→ring, belt`. A two-handed weapon empties `off_hand` **except** quivers,
which are allowed only with a bow or crossbow. Shields and foci need a one-handed weapon (or an empty main
hand). Requirements (level + attributes) must be met to equip. Inventory: 60 cells (10×6), one item per
cell. Stash: 120 cells.

### 9.2 Bases (`ItemDB.get_base`)
Ids `<category>_<tier>`, tiers 1–6 at base levels 1, 8, 16, 26, 38, 50. **Required ids** (the ItemDB stub
already has them): `sword_1`, `greataxe_1`, `bow_1`, `crossbow_1`, `wand_1`, `shield_str_1`, `quiver_1`,
`body_str_1`, `body_dex_1`, `body_int_1`, `ring_1`.
- Weapon categories (`weapon_type`): `sword`, `greatsword` [sword, 2h], `axe`, `greataxe` [axe, 2h], `mace`,
  `maul` [mace, 2h], `dagger`, `wand`, `staff` [2h], `bow` [2h], `crossbow` [2h].
- **Weapon numbers** = category template × `Balance.weapon_damage_scale(eff)` where
  `eff = min(item_level, base.level + 12)` (tiers cap growth, so higher tiers matter). Templates
  (level-1 phys, attacks/s, crit %): sword 7–15/1.45/5, axe 8–18/1.30/5, mace 9–17/1.25/5, dagger
  5–13/1.60/8, wand 4–9/1.40/7, greatsword 13–25/1.20/5, greataxe 14–30/1.10/5, maul 17–31/1.00/5, staff
  11–21/1.15/6, bow 9–21/1.40/5, crossbow 16–30/1.00/6. Range: dagger 1.8, 1h 2.2, 2h 2.7, staff 2.6,
  ranged 20. Implicits: wand inc spell_damage; staff inc spell_damage + block; dagger crit; mace area_damage;
  axe bleed chance; sword attack_speed; crossbow +1 pierce.
- Off-hands: `shield_str` (armour + block), `shield_dex` (evasion + block), `shield_int` (ES + block),
  `focus` (ES, implicit spell_damage), `quiver` (implicit added_physical_attack or projectile speed).
- Armour: `helmet_*`, `body_*`, `gloves_*`, `boots_*` with suffix `str` (armour), `dex` (evasion), `int`
  (ES), `str_dex`, `str_int`, `dex_int`. **Defence numbers** (body, at `eff` as above): armour
  `15 + 7.5(eff−1)`, evasion `50 + 9(eff−1)`, ES `12 + 3.2(eff−1)`; helmet 45%, gloves/boots 35%,
  shield 60% of body; hybrids 60% of each type.
- Jewellery: `ring` (implicits vary: +life, +mana, +res, +added phys…), `amulet` (+attribute), `belt`
  (+life / +armour / +ES). No requirements.
- **Requirements:** level = base.level. Pure bases: its attribute = `round(8 + 1.6 × base.level)`; hybrids
  `round(5 + 1.0 × base.level)` each. Weapons: sword str+dex, axe/mace/maul/greataxe/greatsword str,
  dagger dex+int, wand int, staff str+int, bow dex, crossbow dex+str (hybrid formula for two).
- Every base has `model` (§14 id) and `tint`: str steel grey, dex leather brown/green, int cloth violet/blue,
  hybrids blend; weapon tints brighten per tier (iron → steel → gold/runic).

### 9.3 Affixes
Schema: `{"id", "kind": "prefix"|"suffix", "group", "slot_types": [...], "weight", "tiers": [{"tier", "ilvl",
"name", "mods": [{"stat", "op", "min", "max"[, "min2", "max2"]}]}]}`. Tier 1 = lowest ilvl (1/8/16/26/38/50).
One affix per group. Magic: 1–2 affixes (≤ 1 prefix, ≤ 1 suffix). Rare: 3–6 (≤ 3 prefixes, ≤ 3 suffixes).
Values roll uniformly, ints (except small percents like leech: one decimal). Reference values by tier:
+max_life 10–19/20–29/30–44/45–59/60–79/80–99; one resistance 6–11/12–17/18–23/24–29/30–35/36–42;
amulets +10–40 to one attribute.
- **Local** on weapons: `local_added_<t>`, `local_physical_damage` (inc), `local_attack_speed`,
  `local_crit_chance`. On armour: `local_armour|evasion|energy_shield` (flat & inc), `local_block`.
- **Global** elsewhere: added_<t>_attack (rings, amulets, gloves, quivers), added_<t>_spell and spell_damage /
  cast_speed (wands, staves, foci, amulets), elemental/fire/cold/lightning_damage (rings, amulets, wands,
  staves), movement_speed (boots), item_rarity (rings, amulets, helmets, boots).
- Suffixes: attributes, resistances, attack speed (gloves, quivers, rings), cast speed, crit chance and
  multiplier, life regen, life/mana leech, life/mana on kill, mana regen, projectile speed, area of effect
  (amulets), ailment chances (weapons, gloves), all_attributes (amulets).
- `Item.get_global_mods()` returns non-local mods **plus** the item's final defences as flat mods
  (`armour`, `evasion`, `max_energy_shield`, `block_chance`).

### 9.4 Uniques (~12–15, fixed mods + flavour text)
*Gorebinder* (axe: phys, bleed, leech), *Emberheart* (staff: fire spell, +1 projectile, ignite), *Windshear*
(bow: attack speed, +2 projectiles, movement speed), *Frostbite Grips* (gloves: added cold, freeze chance),
*Stormcrown* (helmet: lightning damage, shock, ES), *Wanderer's Steps* (boots: 30% move speed, evasion),
*Bulwark of the Fallen* (shield: block, armour, life regen), *Bloodbond Plate* (body: life, blood_magic,
regen), *Voidheart Ring* (chaos damage, poison, chaos res), *Glasswork Amulet* (30% more damage, 25% less
max life), *The Arbalest* (crossbow: +3 pierce, projectile damage), *Seraph's Cord* (belt: life, ES, res).

### 9.5 Rarity, item choice & drops
`roll_rarity(bonus, monster_rarity)`: weights normal 72, magic 22, rare 5.5, unique 0.5; non-normal weights
× (1 + bonus/100); monster rarity adds bonus: magic +50, rare +150, boss +400.
`generate_random_item(ilvl, …)`: slot type by weight {weapon 18, offhand 8, helmet 10, body 10, gloves 10,
boots 10, ring 14, amulet 10, belt 10}, then category uniformly, then tier: the highest tier with
`level ≤ ilvl` 70%, the next lower 25%, any lower 5%.
`roll_monster_drops(level, rarity, rarity_bonus, quantity_bonus, gold_bonus)`: item chance normal 14%,
magic 35%; rare 1–2 items (+50% for a 3rd); boss 4–6 with ≥ 1 rare and 25% a unique. Gold: normal 20%,
magic 40%, rare 2 piles, boss 5 piles. `item_quantity` multiplies counts/chances. Item level = monster
level. Chests: tier 0 1–2 items + gold; tier 1 2–4 with ≥ 1 magic; tier 2 3–5 with ≥ 1 rare.

### 9.6 Ground loot (`GroundItem`)
Model `Assets.model(item.get_model_id())` scaled to ~0.6 m longest side, lying flat, random yaw, tinted
(`Assets.tint`). Own `Label3D` (billboard, `no_depth_test`, outline 8) in rarity colour at y ≈ 0.6; normal
items show it only when hovered or while Alt is held (GroundItem polls `highlight_items` itself); magic+
always. Two pick shapes: the model and a box over the label, so clicking label text picks it up.
Rare/unique: tall translucent light beam in rarity colour. Spawn with a short pop arc. Gold auto-picks up
within 1.2 m of the player. Pick up: `add_to_inventory` → emit `item_picked_up`, `Sfx.play("pickup_item")`,
free; full → emit `Events.inventory_full` (UIRoot shows the message) and stay.

### 9.7 Vendor & crafting
Sell ≈ normal 2 × ilvl, magic ×3, rare ×8, unique ×15 (min 1). Buy ≈ 4 × sell. Stock =
`GameState.vendor_stock`, rebuilt by the flow on every town entry via
`ItemDB.generate_vendor_stock(max(character.level, Balance.area_level_for_depth(character.max_depth)))`,
which always includes ≥ 1 melee weapon, 1 bow or crossbow and 1 wand or staff at the current tier. The
vendor panel removes bought items from the array and never regenerates it. Crafting: `reroll_affixes`
(magic 20 + 6 × ilvl gold, rare 60 + 15 × ilvl); `upgrade_rarity` (normal→magic 30 + 5 × ilvl, magic→rare
150 + 20 × ilvl). Potions refill for free on town entry (flow).

---------------------------------------------------------------------------------------------------------

## 10. Passive tree

- File `data/passive_tree.json` = `{"version": 1, "nodes": [node, …]}`, node =
  `{"id": int, "name", "type": "start"|"small"|"attribute"|"notable"|"keystone", "x", "y", "mods": [mod],
  "links": [int], "class": "warrior"|"ranger"|"sorcerer" (start only), "group": String}`. Links are
  undirected (listed on both ends). **Start nodes have `"mods": []`** (class attributes come from ClassDefs).
- Generated deterministically by `tools/tree/gen_passive_tree.py` (python3, stdlib only), written
  atomically (`.tmp` + `os.replace`). Target **~400 nodes**: 3 starts, ~300 small/attribute (≥ 60
  attribute nodes of +10), ~55 notables, 9 keystones.
- **TreeDB** converts `id` and every `links` entry with `int()` on load (JSON numbers are floats) and keys
  `nodes` by int; every API takes/returns int ids.
- **Layout** (tree units ≈ px at zoom 1, y down): centre (0, 0); class starts at radius ~350 — sorcerer at
  −90° (top), warrior at 150° (lower left), ranger at 30° (lower right). Overall radius ~2200. Node centres
  ≥ 60 apart; links never pass through other nodes. Clusters (4–8 small nodes + a notable) hang off an inner
  ring (~700), middle ring (~1250) and outer ring (~1750); keystones sit outside the outer ring at the end
  of short spurs. Every node reachable from every start. Within the first 12 nodes of each start, ≥ 3 give
  its main attribute.
- **Regions:** Str (≈150°): life, armour, melee, physical, axes/maces/swords, shields/block, life regen.
  Dex (≈30°): evasion, attack speed, bows, crossbows, projectiles, movement, crit. Int (≈−90°): ES, mana,
  spell damage, cast speed, elements. Str/Dex (90°, bottom): bleed, attack damage, two-handed, armour +
  evasion, leech. Dex/Int (−30°): crit, poison, chaos, cold/lightning, evasion + ES. Int/Str (−150°): fire,
  ignite, area, armour + ES, mana regen, resistances.
- **Values:** flat only for attributes (+10), crit multiplier (+10–15) and resistances (+6–8%). Pools and
  defences use inc (max_life 5–8%, max_mana/max_energy_shield 8–12%, armour/evasion 12–18%); damage 8–12%
  inc; speeds 3–5%. Notables: 2–3 mods (e.g. +25% inc melee damage and 8% inc max life). Keystones:
  Blood Magic (`blood_magic`, 100% less max_mana), Iron Reflexes (`iron_reflexes`), Mind over Matter
  (`mind_over_matter`), Resolute Technique (`no_crit` + 30% more attack_damage), Point Blank (`point_blank`),
  Pain Attunement (`pain_attunement`), Unwavering Stance (`cannot_evade`, 30% more armour, +10
  physical_damage_reduction), Glass Cannon (50% more damage, 40% less max_life), Acrobatics (+30
  evade_chance, 50% less armour, 50% less max_energy_shield).
- **Rules:** start node always allocated (not stored); allocate if adjacent to start or an allocated node;
  refund only if the rest stays connected; 1 point per level after 1 + bonus points; refunds cost
  `Balance.passive_refund_cost(level)` gold.

---------------------------------------------------------------------------------------------------------

## 11. Character, classes, player

### 11.1 Classes (`ClassDefs`)
warrior 20/12/10, ranger 12/20/10, sorcerer 10/12/20 (str/dex/int), starting items and skill bar per
`ClassDefs.CLASSES`, tree start = start node with the same `class`. New characters: level 1, 0 gold, 3/3
potion charges, `max_depth` 1, start items equipped (normal). Attributes are not stored on the character.

### 11.2 `CharacterData` / `GameState`
See stubs. Every mutator emits its Events signal; UI code never writes the arrays directly. `add_xp`
handles multi-level-ups (cap `Balance.MAX_LEVEL`). Saves: `GameState.save_dir + <save_id>.json` =
`{"version": 1, "character": CharacterData.to_dict()}`, items via `Item.to_dict()` (JSON-native values
only: no Color/Vector2/int keys). `save_id` = sanitized name + unix time. Typed arrays are filled with
`.assign()`; `from_dict` converts every number with `int()`; `Item.from_dict` bumps `Item._next_uid`.

### 11.3 Player controller (`Player`)
- **Input handling:** keyboard actions start from `_unhandled_input` (never `_input`). A mouse-bound skill
  starts only from a press received in `_unhandled_input` while `not UI.is_mouse_over_ui()`; it then counts
  as held while `Input.is_action_pressed(action)`. Skip polled movement/skill keys while
  `get_viewport().gui_get_focus_owner() is LineEdit`. While `ai_control` is true, ignore real input; the
  `ai_*` methods drive the same code paths (bot, tests, tour).
- **Move:** WASD relative to the camera's yaw.
  `velocity = dir × get_move_speed() × skill_runner.movement_multiplier()`; `move_and_slide()`. Face the
  movement direction unless a skill is in use. Using a skill slows the player (≥ 0.35×) instead of rooting;
  moving with no slot of the running skill held cuts its recovery (`end_recovery()`), so full speed is back
  right after the hit.
- **Aim:** `camera_rig.get_mouse_ground_position()`; hovering an enemy targets it.
- **Hover:** when the hover target changes, call `set_hovered(false)` on the old Interactable and
  `set_hovered(true)` on the new one, then emit `Events.hovered_target_changed`.
- **Skills:** hold slot → `try_use(slot skill, aim, target)` whenever not busy (repeat while held);
  `update_target` while held; `release` on key up. LMB on a hovered GroundItem/Interactable → auto-walk
  (`world.find_path`) then `interact(self)`; WASD cancels the auto-walk.
- **Dodge:** `DODGE_DISTANCE` 5 m over `DODGE_TIME` 0.55 s toward move dir (or mouse): speed falls off as
  `(1 − t/T)^DODGE_EASE` (ease 2: ~80% of the distance in the first 40% of the time, `dodge_progress()`),
  the animation tumbles early and rises slowly; steered by WASD while rolling (`DODGE_STEER_RATE`
  10 rad/s), `invulnerable_time = 0.35`, cooldown 1.2 s, cancels skills and the parry, anim `dodge`.
- **Parry (hold Shift; `start_parry()` / `end_parry()`, `ai_parry()` / `ai_release_parry()`):** the guard
  stays up while the key is held (anim `parry_hold` loop, gold guard disc; slowed like a skill; cancels the
  current skill; skills wait until it drops; not while dodging, frozen, stunned or casting the portal;
  ignored while the mouse is over UI, where Shift means shift-click). While held it comes back up by
  itself whenever it may (after the cooldown, a roll, a stun). `Actor._intercept_hit()` (checked first in
  `take_hit`, before god mode / invulnerability): a hit from the other team while the guard is up deals
  nothing ("Parry!" number) and counters: the player turns to it, every hostile within `PARRY_RADIUS`
  5 m in a `PARRY_ARC_DEG` 160° cone gets `stun` for `PARRY_STUN` 1.5 s and `PARRY_KNOCKBACK` 13 m/s of
  knockback (bosses: no knockback), 0.35 s invulnerability, the guard drops and `PARRY_COOLDOWN` 3 s
  starts (no cooldown without a parry), and the player gains a parry charge (max 1): buff
  `parry_charge` ("Parry Charge", with a description) + a gold aura, used up by the next damaging skill
  (`consume_empower()`, see §8.2). HUD: a round Shift slot beside the dodge slot (cooldown pie, gold
  glow + pip while charged).
- **Potions:** life heals 40% max life over 1.5 s; mana 50% over 1.5 s (× (1 + inc(potion_effect)/100)).
  `character.consume_potion_charge(kind)`; a potion can't be used while its own heal-over-time is running
  ("Potion already active"). Player listens to `Events.enemy_killed` and calls
  `character.add_potion_charges(0.25 normal / 0.5 magic / 1 rare / 3 boss)`.
- **Town portal (T):** in a dungeon, alive and not busy → `play_action_animation("cast", 1.0)` and root
  for 1 s (cancelled by dodge, freeze, death) → emit `Events.town_portal_requested`. Ignored in town.
- **Stats:** `level = character.level`. `get_base_mods()` = flat max_life/max_mana from Balance, class
  attributes (ClassDefs), 15 evasion. `get_all_mods()` = base + `character.get_equipment_mods()` +
  `TreeDB.get_mods(allocated, class)` + resist penalty in dungeons (§5.3). Recalculate on
  `equipment_changed`, `passives_changed`, `level_up`; emit `Events.player_stats_changed`. Level up: full
  heal, ring VFX, `Sfx.play("level_up")`, `Events.notify.emit("Level %d" % L, UIStyle.COLOR_GOLD)`.
- **Visuals:** `Assets.model("char_player")` + `Assets.prepare_animations()`; idle / walk (below
  2.8 m/s, speed_scale = speed / 1.82) / run by speed; while an action plays and the player moves, a
  `SkeletonModifier3D` leg layer (`player_legs.gd`) poses the legs from the directional walks — `walk`,
  `walk_right`, `walk_back`, `walk_left`, blended by the direction of movement relative to the facing at
  one shared phase, in step with the ground speed — blended in by speed (not under dodge / die / channel
  / hit);
  one-shots via `play_action_animation` (speed scaled to duration); spin the model during `channel`.
  Main-hand model on `grip_r`, shield/focus on `grip_l`, quiver on `chest`, helmet on `head`
  (`Assets.attach_to_bone`). Tint body parts with `Assets.tint`: body armour → `Torso` + `Arms`, gloves →
  `Hands`, boots → `Feet`. Hit flash (`Assets.set_flash`) on `damaged`; camera shake for hits > 15% of max
  life. Warm shadowless `OmniLight3D` above the player (range ~10). `world.mark_explored(pos, 14)` a few
  times per second. Death → `Events.player_died`, anim `die`, input off.

### 11.4 Camera (`CameraRig`)
Perspective, vertical FOV 45°, the default view from `PRESETS` (yaw 37.5°, pitch 49.4°, 19.5 m; wheel zoom in
`_unhandled_input`), smooth follow. Holding the right mouse button (`ORBIT_BUTTON`) and moving the mouse
orbits (`orbit_by`); skill slot 2 is on the middle button. The rig is a child of the World (not of the Player). Owns an
`AudioListener3D` at the target. Sets the global shader parameter `player_world_pos` every frame. Hover ray
through the mouse (or `mouse_override`): mask 28, areas + bodies; null while `UI.is_mouse_over_ui()`.

---------------------------------------------------------------------------------------------------------

## 12. Enemies

- **Def schema** (`EnemyDB.get_def`): `{"id", "name", "model", "scale", "tint", "life_mult", "damage_mult",
  "move_speed", "attack_speed", "melee_range", "aggro_radius", "xp_mult", "armour_mult", "resist": {t: %},
  "skills": [{"id", "range", "weight", "cooldown" (extra AI delay)}], "ai": "melee"|"ranged"|"caster"|
  "summoner"|"boss", "preferred_range", "min_depth", "boss": bool}`. Defs reference only §8.5 skill ids.
- **Archetypes → skills:** `skeleton_warrior` (char_skeleton, 3.6 m/s) [m_melee]; `skeleton_archer`
  (char_skeleton + bow, keeps 8–10 m) [m_arrow]; `zombie` (char_zombie, 2.3 m/s, life ×1.8, dmg ×1.3)
  [m_melee]; `ghoul` (char_ghoul, 5.5 m/s, life ×0.6) [m_bite, m_leap]; `cultist` (char_cultist)
  [m_firebolt]; `frost_cultist` (char_cultist tinted blue) [m_frostbolt]; `brute` (char_brute, scale 1.0 — the model is already ~2.3 m,
  life ×3) [m_melee, m_slam]; `necromancer` (char_cultist tinted purple, depth ≥ 5) [m_summon, m_firebolt].
  **Bosses** (group `boss`, `is_boss_actor = true`, life_mult 25, fixed names): `boss_lich` (char_lich, odd
  depths) [m_boss_volley, m_boss_nova, m_boss_meteors, m_summon]; `boss_gravebreaker` (char_gravebreaker,
  even depths) [m_melee, m_boss_slam, m_boss_charge, m_boss_spikes].
- **Rarity** (`Balance.MONSTER_RARITY`): 0 normal, 1 magic (blue tint/name), 2 rare (yellow, generated name
  like "Grim Howl", 2–3 mods, 3–4 from depth 10), 3 boss. **Monster mods:** hasted (+30% move/attack/cast
  speed), armoured (+armour, +20 phys reduction), fiery / frigid / shocking (added element + resistance),
  regenerating (2% life/s), vampiric (leech), berserker (+40% damage), resilient (+30 elemental res),
  extra_life (+60% life).
- **AI:** targets are acquired with `CombatQuery` (team_0 actors), re-acquired every think tick (never
  cached). Idle → aggro when a target is within `aggro_radius` with line of sight, or when hit; pack members
  within 8 m aggro together. Chase via `world.find_path` (re-path every 0.5 s; steer directly with LOS).
  Melee in range; ranged/caster keep `preferred_range` (step back if closer than half). Random 0.3–0.8 s
  pause between skill uses. Big attacks use `windup`. Hit stagger per §6.7. Enemies > 40 m from the player
  sleep (physics off, hidden). A boss emits `Events.boss_spawned(self)` the first time it aggroes.
- **Death:** `GameState.award_kill_xp(level, def.xp_mult × MONSTER_RARITY[rarity].xp)`; drops via
  `LootSystem.spawn_drops(LootSystem.roll_monster_drops(level, rarity, p.item_rarity, p.item_quantity,
  p.gold_find), pos)` with the player's stats (`GameState.player.stats.compute(...)` if valid, else 0);
  `Events.enemy_killed.emit(self)`; bosses also `Events.boss_killed`. Play `die`, disable collision,
  sink/fade (`Assets.set_fade`) after ~4 s, free.
- **Visuals:** `Assets.prepare_animations`; overhead life bar (once damaged; always for rare/boss) +
  `StatusVisuals`; rarity tint; hit flash. `get_nameplate_info()` feeds the HUD card.
- **Spawning:** `populate_area(world)` reads `world.get_spawn_groups()`: `pack` → `count` monsters of 1–2
  archetypes allowed at this depth (15% chance the pack is magic), `rare_pack` → 1 rare + 3–4 normals,
  `boss` → the depth's boss. `spawn_enemy(…, world)` adds the enemy itself.

---------------------------------------------------------------------------------------------------------

## 13. World

- **Grid:** `TILE_SIZE = 2` m. Cell (i, j) spans x ∈ [2i, 2i+2], z ∈ [2j, 2j+2]; centre
  `((i + 0.5) × 2, 0, (j + 0.5) × 2)`. `AStarGrid2D` for `find_path` (diagonals only without corner
  cutting). Pillars/large props mark their cells solid.
- **`build(info)` is synchronous** and requires the World in the tree. Ids: `town`, `dungeon`, and `arena`
  (tests/demos: open `size`×`size` floor with perimeter walls, player start at the centre, no spawns).
- **Dungeon generator** (seeded): 44×44 at depth 1 growing to 64×64 by depth 10. Rooms (5–12 cells) +
  corridors 2–3 cells wide, all connected (flood-fill check); "cave" theme adds cellular-automata roughness.
  Start room (player start + portal back to town), boss room (farthest by path distance), 8–14 other rooms.
  Spawn groups: `pack` count = clamp(round(rooms × 1.2), 8, 12) packs of 3–6 (`count` field), 2–4
  `rare_pack`, 1 `boss`; none within 12 m of the start; ≤ 70 monsters total. 2–4 chests. Pillars in big
  rooms, wall torches every ~5 cells (≤ 20 lights), decorative debris (non-colliding).
- **Themes:** `World.theme_for_depth(d)` — crypt (1–3) → cave (4–6) → inferno (7–9) → repeat;
  `World.theme_display_name(theme)`. Different floor/wall tints, fog colour, torch vs crystal vs lava-glow
  lighting. `WorldEnvironment`: dark ambient, fog, glow, filmic tonemap; dim moonlight
  `DirectionalLight3D` with shadows.
- **Rendering:** floors and walls are `MultiMeshInstance3D`s built from duplicated `Assets.mesh(id)`s. Only
  wall cells touching floor get a wall block. Wall collision: one `StaticBody3D` (layer 1) with merged
  `BoxShape3D` runs. **Wall cut-out:** walls/pillars use a `ShaderMaterial` copying each surface's albedo,
  with `global uniform vec3 player_world_pos;` — fragments near the camera→player line and in front of the
  player are dithered away so the player stays visible behind walls.
- **Town:** ~40×40 m hub on the same grid: grass ground, dirt paths, houses (solid cells), trees, fences,
  lamp posts, a well; **Merchant** NPC (`char_merchant` + `town_stall`, `Assets.prepare_animations`, idle)
  → `Events.panel_open_requested.emit("vendor", {})`; **Stash** (`town_stash`) → `"stash"`; **Dungeon
  Gate** (`env_waypoint`) → `"waypoint"` with `{"max_depth": character.max_depth}`; when
  `GameState.town_portal_state` has a world, a **portal back** ("Return to Depth N") → `dungeon_return`.
  Warm daylight (`ProceduralSkyMaterial`, sun with shadows).
- **Interactables** (`scripts/world/interactables/`, class names `World*`): portal (destination `town` /
  `next` / `return`), waypoint gate, vendor NPC, stash chest, chest (Lid opens:
  `lid.rotation.x = -deg_to_rad(110)`, tolerate a missing Lid; `LootSystem.roll_chest_drops`), optionally
  a shrine (30 s buff). Portals emit `Events.area_change_requested` — interaction happens inside the
  player's physics step, the flow defers the actual change.
- `spawn_exit_portals(pos)`: "Descend to Depth N+1" (not at `MAX_DEPTH`) and "Town" portals near `pos`.
- **Minimap:** `get_minimap_data()` (indexing in the stub) + `mark_explored()`.

---------------------------------------------------------------------------------------------------------

## 14. Assets (Blender → glTF → Godot)

### 14.1 Pipeline conventions
- Python scripts in `tools/blender/<module>/`, run as
  `blender --background --factory-startup --python tools/blender/<module>/build_all.py -- [--only id,…]`.
  Deterministic (fixed seeds).
- **Fresh file per model:** `bpy.ops.wm.read_factory_settings(use_empty=True)` before building each id (or
  one Blender process per id); otherwise names collide ("idle.001") and leftovers leak into exports.
  Before exporting a character assert that `sorted(a.name for a in bpy.data.actions)` is exactly its
  §14.3 list and the §14.2 object names exist without `.001` suffixes.
- **Blender 5.2 API:** actions are layered/slotted — `action.fcurves` does not exist. Animate with
  `arm.animation_data.action = act; pose_bone.keyframe_insert("rotation_quaternion"|"rotation_euler"|"location", frame=f)`
  (for direct F-curve access: `bpy_extras.anim_utils.action_ensure_channelbag_for_slot(act, slot).fcurves`).
  `act.use_fake_user = True`. Key animations from frame 0.
- **Export exactly:** `bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_apply=True,
  export_yup=True, export_animation_mode='ACTIONS', export_def_bones=False, export_anim_slide_to_zero=True,
  export_cameras=False, export_lights=False)`. No vertex colours (if needed: `export_vertex_color='ACTIVE'`).
- **Atomic output:** export/render to `assets/models/.tmp/<id>.glb` (icons: `assets/icons/<kind>/.tmp/`),
  then `os.replace()` into place, so no one ever imports a half-written file.
- **Transforms:** every exported object has an identity object transform (apply location/rotation/scale;
  objects at the world origin). The reference point (grip, feet, tile centre, base centre) is the Blender
  WORLD origin. Exception: moving child parts (e.g. `env_chest` `Lid`) whose origin is their pivot.
- Low-poly, flat shaded, **materials with Principled base colours** (+ emission for glowing parts). No image
  textures. Budgets: character ≤ 3k tris, weapon ≤ 800, env tile ≤ 500.
- **Tintable materials** are named `tint_<x>` with base colour ≈ (0.8, 0.8, 0.8); skin, eyes, emissive
  and fixed-colour materials are not prefixed. Every `char_player` body part and every item model has at
  least one `tint_` material. (`Assets.tint` multiplies only `tint*` materials.)
- Metres; humanoids ~1.8 m. Characters face −Y in Blender (+Z in Godot), origin at the feet. Weapons: grip
  at the origin, blade/shaft along +Z in Blender (+Y in Godot), flat of blade facing ±X. Floor tiles: 2×2 m,
  top at z = 0, centred. Wall blocks: 2×2 m footprint, 2.4 m tall, rising from z = 0, centred. Props: origin
  at base centre. Env kit pieces (`env_floor_*`, `env_wall_*`, `env_pillar`) are ONE mesh object each
  (multiple materials OK).
- Import layout in Godot (verified): `root/Armature/Skeleton3D/<MeshInstance3D named after the Blender
  object>`, `root/AnimationPlayer` with animations in the default library under the exact action names,
  loop mode NONE; material `resource_name` = Blender material name. Name the armature object `Armature`.

### 14.2 Humanoid rig (every `char_*`)
Bones: `root` (origin), `hips`, `spine`, `chest`, `neck`, `head`, `upper_arm_l/r`, `lower_arm_l/r`,
`hand_l/r`, `grip_l/r` (non-deforming children of the hands), `upper_leg_l/r`, `lower_leg_l/r`,
`foot_l/r`. Rigid segmented meshes skinned 100% to one bone each (armature modifier + vertex groups).
Separate mesh objects `Head`, `Torso`, `Arms`, `Hands`, `Legs`, `Feet` (+ optional `Hair`, `Details`) —
required names for `char_player`. **Attachment axes (verified):** a `BoneAttachment3D` has its origin at the
bone HEAD, its +Y along the bone's head→tail direction, and its +X along the bone's local X (roll). So:
`grip_r`/`grip_l`: head at the palm centre, tail 0.1 m along the direction the held item's Blender +Z
should point in the idle pose, roll so local X is the blade-flat normal — then a weapon at identity
transform sits in the hand naturally. `head` and `chest` point straight up (+Z) with roll 0; helmets are
modelled with their origin at the `head` bone's head; `offhand_quiver` with its origin at the `chest`
bone's head, geometry offset backwards (Blender +Y) so it hangs on the back, opening over the right
shoulder. Verify every attachment in Godot with screenshots.

### 14.3 Animations (actions on every `char_*`; names exact)
`idle` (loop ~2 s), `run` (loop, matched to ~5 m/s), `attack_slash` (0.6 s, hit ≈ 45%), `attack_slam`
(0.8 s, overhead two-hand smash, ≈ 55%), `attack_stab` (0.5 s), `shoot_bow` (0.7 s, release ≈ 60%),
`shoot_crossbow` (0.6 s, ≈ 40%), `cast` (0.6 s, one hand forward, ≈ 50%), `cast_area` (0.7 s, both arms up
then down, ≈ 55%), `channel` (loop, arms out; code spins the model), `hit` (0.3 s flinch), `die` (1.0 s,
fall and stay down), `dodge` (0.55 s: a quick tumble, then a slower rise). Bosses add `roar` (1.2 s).
`char_player` adds `parry` (0.55 s: low stance, blade held diagonally across the chest, off hand forward),
`parry_hold` (the guard held, loop) and the walks `walk`, `walk_back`, `walk_left`, `walk_right` (loops,
planted feet at 1.82 m/s; the right foot touches down at phase 0 in each; side steps without crossing
the feet, built with a sideways thigh swing, `RigInfo.solve_leg_3d`). `char_merchant` needs only `idle`
(+ optional `talk`). The exporter drops tracks of bones that don't move, so consumers call
`Assets.prepare_animations(model)` (sets `deterministic = true` and loop modes for idle/run/channel).

### 14.4 Catalogue
**assets-characters** — rigged: `char_player` (neutral adventurer; gear shown by tints/attachments),
`char_skeleton`, `char_zombie`, `char_ghoul` (hunched, long arms), `char_cultist` (hooded robe), `char_brute`
(huge, ~2.4 m), `char_lich` (boss, ~3 m, crown, robes, glowing eyes), `char_gravebreaker` (boss, ~3 m, horned,
armour plates), `char_merchant` (NPC, apron). Weapons: `weapon_sword`, `weapon_greatsword`, `weapon_axe`,
`weapon_greataxe`, `weapon_mace`, `weapon_maul`, `weapon_dagger`, `weapon_wand`, `weapon_staff`,
`weapon_bow`, `weapon_crossbow`; off-hands: `offhand_shield`, `offhand_focus` (floating orb/tome),
`offhand_quiver`. Worn helmets: `armor_helmet_str` (plate), `armor_helmet_dex` (leather hood),
`armor_helmet_int` (circlet/crown). Ground-only: `armor_body` (cuirass), `armor_gloves`, `armor_boots`,
`jewel_ring`, `jewel_amulet`, `jewel_belt`, `loot_gold` (coin pile), `loot_potion_life`, `loot_potion_mana`.
**Item icons**: 128×128 transparent PNG per item model id → `assets/icons/items/<id>.png`.

**assets-environment** — dungeon kit: `env_floor_a`, `env_floor_b`, `env_floor_c` (neutral stone, tinted per
theme in code), `env_wall_a`, `env_wall_b`, `env_pillar`, `env_torch` (wall sconce with emissive flame;
origin at the wall face, sticks out along Godot +Z = Blender −Y), `env_brazier`, `env_crate`, `env_barrel`,
`env_bones`, `env_rubble`, `env_rock_a`, `env_rock_b`, `env_crystal` (emissive), `env_chest` (base plus a
separate child object `Lid`, origin on the hinge line at the back-top edge, identity rotation; opened by
`lid.rotation.x = -deg_to_rad(110)`), `env_portal` (standing ring/arch; swirl added in code),
`env_waypoint` (stone gate with runes). Town: `town_house_a`, `town_house_b`, `town_house_c` (~6×6 m, ~6 m
tall), `town_well`, `town_tree_a`, `town_tree_b`, `town_fence` (2 m segment), `town_lamp`, `town_stall`,
`town_stash` (iron-bound chest), `town_cart`, `town_bush`, `town_rock`. Projectiles (point along Godot +Z =
Blender −Y, origin at the centre): `proj_arrow`, `proj_bolt`, `proj_ice_spear`, `proj_meteor`.
**Skill icons**: 128×128 PNG per player skill id (§8.4) → `assets/icons/skills/<id>.png`, a readable symbol
on a dark round badge, colour-coded (melee red/orange, bow/crossbow green, spells by element).

**Icon rendering:** `scene.render.engine = 'BLENDER_EEVEE'` (no 'BLENDER_EEVEE_NEXT' in 5.2) or
`'BLENDER_WORKBENCH'`, `render.film_transparent = True`, PNG RGBA, `view_settings.view_transform =
'Standard'`, 128×128 at 100%, orthographic camera + sun; rendered after the model export.

### 14.5 Validation
Each asset module ships a probe **scene** `tools/godot/probe_<module>.tscn` (+ `.gd`), run with
`tools/gtest.sh <module> res://tools/godot/probe_<module>.tscn`. It loads every id and asserts: exactly one
`Skeleton3D` and one `AnimationPlayer` per character, every §14.3 animation name present without `_001`,
`char_player` has Head/Torso/Arms/Hands/Legs/Feet, rough AABB sizes and origins; prints a report. Plus a
windowed preview scene that saves screenshots to `docs/screenshots/<module>/`, which the author inspects.

---------------------------------------------------------------------------------------------------------

## 15. Game flow (`scripts/main/main.gd`)

- Boot → `UI.show_main_menu()`. `Events.new_game_requested` → `GameState.new_character` → save →
  town. `Events.load_game_requested` → `GameState.load_game` → town.
- **Area change:** `main.gd` handles `Events.area_change_requested` via `_change_area.call_deferred(id,
  params)` and ignores requests while a change is running. Steps:
  1. `UI.close_all_panels()`; if the player is valid, remember `r = player.get_pool_ratios()`, then
     `GameState.player = null; player.queue_free(); rig.queue_free()`.
  2. Old world: if it is being kept (`town` with `keep_dungeon`, or death — see below) `remove_child` it
     and store `GameState.town_portal_state = {"world": w, "position": pos}`; else `queue_free()`.
     `GameState.world = null`. Taking the waypoint to any depth discards a kept dungeon.
  3. `var w := World.new(); GameState.world = w; GameState.current_area = info; add_child(w)` (in the tree
     BEFORE build). For `dungeon_return`, re-attach the kept world instead of building.
  4. `w.build(info)` (synchronous).
  5. `var p := Player.new(); p.setup(GameState.character); p.position = start; GameState.player = p;
     w.add_child(p); p.set_pool_ratios(r)` (town entry: full pools; refill potions).
  6. `var rig := CameraRig.new(); rig.target = p; w.add_child(rig); p.camera_rig = rig; rig.snap_to_target()`.
  7. Fresh dungeons only: `EnemyDB.populate_area(w)`.
  8. Town entry: `character.refill_potions()`, `GameState.vendor_stock = ItemDB.generate_vendor_stock(…)`.
  9. Emit `Events.player_spawned(p)`, `Events.area_entered(info)` (UIRoot closes panels, shows the HUD);
     autosave.
- Area info: town `{"id": "town", "name": "Emberfall", "level": 1, "theme": "town"}`; dungeon
  `{"id": "dungeon", "depth": d, "level": Balance.area_level_for_depth(d), "seed": random,
  "theme": World.theme_for_depth(d), "name": "Depth %d — %s" % [d, World.theme_display_name(theme)]}`.
- **Town portal:** `Events.town_portal_requested` → change area to town with `{"keep_dungeon": true}`.
- **Boss killed** (`Events.boss_killed`): add depth to `cleared_depths`; first clear and depth ≤
  `Balance.BONUS_POINT_MAX_DEPTH` → `character.add_bonus_passive_points(1)`; `max_depth =
  min(MAX_DEPTH, max(max_depth, depth + 1))`; `world.spawn_exit_portals(pos)`; `Events.area_cleared`;
  notification; autosave.
- **Death:** `Events.player_died` → after 1.5 s `UI.open_panel("death")` → `Events.respawn_requested` →
  `character.lose_xp_fraction(0.1)` → town at full life; the dungeon is kept exactly like a town portal
  (portal position = its player start; a living boss resets to full life and leaves combat).
- **Autosave:** on area change, level up, boss kill, and quit/return to menu.
- **Debug keys** (debug builds): F9 level up, F10 spawn 6 random items around the player, F11 toggle
  `GameState.player.god_mode`, F12 screenshot → `user://screenshots/` (skip with a warning when headless).
- **Command line** (after `--`): `--autoplay=SECONDS [--class=…] [--depth=N] [--seed=N]` skips the menu and
  runs a bot through `Player.ai_*` (walk to enemies, use skills, pick up loot, equip upgrades, allocate
  passives, take portals after the boss), logs a summary and quits with 0 (non-zero if broken).
  `--shots=DIR` runs a screenshot tour (menu, town, dungeon fight, inventory, character sheet, passive tree,
  skill book, vendor, stash, death screen) into DIR and quits; it needs a real window (`GTEST_WINDOWED=1`)
  and skips with a warning when headless. `--combat-tour=DIR` does the same for the fighting controls
  (attacking while walking, parry guard / counter / charge, empowered attack + echo, steered dodge).
  All live in `scripts/debug/`.

---------------------------------------------------------------------------------------------------------

## 16. UI

- `UI` autoload (`UIRoot`, implemented by the orchestrator) owns HUD + panels (`UIRoot.PANELS`), the shared
  `TooltipPanel` and notifications; theme `UIStyle.make_theme()`; base 1920×1080 (stretch `canvas_items`,
  aspect `expand`). `Events.area_entered` → close all panels + show HUD. Modal panels (`main_menu`,
  `death`) block Esc and toggles; toggles do nothing without a live player.
- **Mouse filter rule:** UIRoot adds every panel and the HUD with FULL_RECT anchors; the panel ROOT is
  `MOUSE_FILTER_IGNORE` except full-screen panels (`passives`, `pause`, `death`, `main_menu`: STOP). Every
  layout-only node (containers used only for layout, overlays for damage numbers) uses IGNORE; only visible
  frames, slots, buttons, globes and skill-bar slots use STOP. `UI.is_mouse_over_ui()` =
  `get_viewport().gui_get_hovered_control() != null` (correct only under this rule).
- **Focus rule:** buttons, slots and tree nodes use `FOCUS_NONE` (`UIStyle.make_button` does); only
  LineEdits take focus; UIRoot releases focus when a panel closes. Toggle keys are handled in
  `_unhandled_input` only.
- **Standalone panels:** every panel and the HUD work without UIRoot for demos:
  `var p := InventoryPanel.new(); add_child(p); p.on_opened({})`.
- **Notifications** (`Events.notify`, `skill_use_failed`, `inventory_full`) are shown by UIRoot.
- **HUD:** life globe (left) with ES ring, mana globe (right), XP bar, skill bar (6 slots, icon via
  `Assets.skill_icon`, key label via `Controls.skill_slot_label`, cooldown sweep from
  `skill_runner.get_cooldown_ratio`, red tint when `can_use` code ∈ {cost, weapon, level}), potion slots
  with charges and active-potion sweep, buff & ailment icons, area name + level (top right), minimap (Tab =
  large overlay; the HUD handles `toggle_minimap`), boss bar (shown on `boss_spawned`, hidden on the boss's
  `died`, `boss_killed` or `area_entered`), hovered-enemy nameplate (`get_nameplate_info()`), floating
  damage numbers (`Events.damage_number`; crits larger; player damage red), "+N passive points" indicator.
- **Drag & drop payloads:** skill `{"type": "skill", "skill_id": String}` (skill book → HUD slot, HUD slot →
  HUD slot; the HUD slot calls `character.set_skill_in_slot`). Item `{"type": "item", "item": Item, "from":
  "inventory"|"equipment"|"stash"|"vendor", "index": int, "slot": String}`. Drop targets use STOP. Dropping
  an item on the world: the drag source handles `NOTIFICATION_DRAG_END`; if
  `not get_viewport().gui_is_drag_successful() and not UI.is_mouse_over_ui()`, it removes the item and
  calls `LootSystem.spawn_item(item, GameState.player.global_position)`.
- **Items UI:** paper doll (helmet, amulet, main hand, body, off hand, gloves, belt, rings, boots) + 10×6
  grid + gold. Hover → `UI.show_tooltip(item.get_tooltip_lines(attrs), rect, equipped comparison)`.
  Right-click equips/unequips; Ctrl+click sells at the vendor; Shift+click moves inventory↔stash. All
  changes through `CharacterData` mutators (`put_in_inventory`, `put_in_stash`, `equip`, …).
- **Passive tree:** full-screen dark canvas; links and nodes drawn in `_draw()` (allocated bright gold,
  allocatable highlighted, others dim; notables/keystones larger). Drag to pan, wheel to zoom (0.25–2), hover
  tooltip, click allocates along the shortest path (preview, limited by unspent points), right-click refunds
  (gold cost shown), search box highlights matches, header shows points and a Close button.
- **Skill book:** all player skills (`SkillDB.get_player_skills()`), locked ones greyed with level, icon,
  tags, weapon requirement, tooltip `SkillDB.get_tooltip_lines(id, player)`; assign by clicking a slot button
  (LMB/RMB/Q/E/R/F) or dragging onto the HUD skill bar.
- **Menus:** main menu (title, character list with continue/delete, new character: name LineEdit + three
  class cards), pause (resume, save, save & quit to menu, quit), death screen (Respawn), waypoint (depths
  1..max_depth with monster level).

---------------------------------------------------------------------------------------------------------

## 17. Audio ids (`Sfx.play(id, pos)`)
`swing`, `hit_flesh`, `hit_crit`, `hit_block`, `evade`, `bow_shoot`, `crossbow_shoot`, `spell_cast`,
`fireball_cast`, `explosion`, `frost_nova`, `ice_shatter`, `lightning`, `meteor_impact`, `warcry`,
`leap_land`, `teleport`, `whirlwind`, `pickup_item`, `pickup_gold`, `drop_item`, `level_up`, `potion`,
`enemy_die`, `player_hurt`, `player_die`, `boss_roar`, `ui_click`, `ui_open`, `ui_close`, `equip`, `portal`,
`chest_open`, `parry_ready` (guard up), `parry` (a caught blow), `empower` (a parry charge used). Call them
freely; files arrive in the audio pass.

---------------------------------------------------------------------------------------------------------

## 18. Testing & definition of done

- **gtest:** `tools/gtest.sh <module>[-suffix] <scene> [-- args]`. Default isolated mode = frozen wave
  baseline + your owned files (+ `GTEST_EXTRA` live paths, e.g. `GTEST_EXTRA="assets/models"` to see
  assets as the asset agents produce them). `GTEST_FULL=1` = whole live repo. One env per module; use a
  suffix for concurrent runs; run long jobs in the background. Each env has its own `user://`; tests never
  touch `user://saves/` (use `GameState.save_dir`).
- **Parse check** (run after every file write):
  `tools/gtest.sh <module> res://tools/godot/parse_check.tscn -- --path=res://scripts/<dir>,res://tests/unit`.
  Never use `--check-only` or `--script` (they compile without autoloads → false "Identifier not found").
- **Unit tests:** `tests/unit/test_<module>_*.gd` extending `TestCase`; run
  `tools/gtest.sh <module> res://tests/test_runner.tscn -- --filter=test_<module>`. A test fails on failed
  asserts, on ANY engine/script error or `push_error` during it, or after 20 s. Fixtures:
  `await make_world()`, `make_character()`, `spawn_player()`, `spawn_dummy()`; GameState refs are reset
  after each test. Wave-2 tests depend only on wave-0/1 code and your own module; use `TestDummy` and
  stubs for parallel modules (Player/Enemy create their SkillRunner in `_ready` only if
  `skill_runner == null`, so tests can inject one).
- **UI tests** synthesise input with `get_viewport().push_input(event, true)` (other routes don't reach
  Controls headless).
- **Demo scenes:** `tests/scenes/<module>_*.tscn` (+ `.gd`). First line of `_ready`:
  `get_tree().create_timer(20).timeout.connect(get_tree().quit)`. Capture screenshots only when
  `DisplayServer.get_name() != "headless"` (run with `GTEST_WINDOWED=1`; keep windowed runs short — they
  open a real window on the user's desktop), save to
  `OS.get_environment("GTEST_REPO") + "/docs/screenshots/<module>/"`, then LOOK at the PNGs.
- **Done means:** all your tests pass, zero errors in your files in test/demo runs, stub signatures kept,
  the features in your section implemented (not TODO), and a final report: files, public API additions,
  deviations, requests for frozen files, known issues, how to test.

---------------------------------------------------------------------------------------------------------

## 19. Implementation notes from wave 1 (read before building on these modules)

All contract signatures are kept; these are the useful additions and the decisions that differ from, or
refine, the sections above. Read the code for details (every function has a doc comment).

**Kernel** (`scripts/core/`, `game_state.gd`)
- `Actor`: `attributes` dict; `take_damage_from(source, amount, type, is_dot)` (DoT kill credit, freed
  sources safe), `remove_ailment`, `clear_ailments`, `get_chill_effect`, `get_shock_effect`,
  `get_action_speed_mult()` (1 − chill → SkillRunner), `get_move_speed_mult`, `refill_pools()`,
  `knockback_velocity` (decays; subclasses add it to velocity). The Actor plays the `evade` and
  `hit_block` sounds itself. A buff with duration ≤ 0 is permanent. No hit ailments on a killing blow.
  Enemies' `can_pay_cost/pay_cost` always true. A mana/ES pool that grows from max 0 on a live actor
  starts empty and recharges normally. DoT/heal numbers are aggregated per 0.5 s.
- `HitData`: `use_id`, `weapon_type`, `HitData.create(damage, source, tags)`, `has_tag(tag)`; copies with a
  freed source become source = null safely.
- `DamageCalc.build_hit` opts: `use_id` (share one id across all hits of a skill use, from
  `DamageCalc.next_use_id()`), `fire_origin`, `target_pos`, `knockback`, `force_crit`, `no_ailments`,
  `team`. Helpers: `scale_cost` (channel `cost_per_tick`), `get_attack_speed`, `get_cast_speed_mult`,
  `get_average_hit`, `get_base_damage_range`, `get_ailment_chance`, `damage_taken_mult`,
  `point_blank_mult`. Monster skills with `monster_damage` also get the attacker's added damage (so
  fiery/frigid/shocking mods work).
- `CombatQuery`: `get_actors`, `get_allies`, `allies_in_radius`, `hostiles_sorted_by_distance`,
  `is_hostile(a, b)` (freed-safe), `distance_xz`, `distance_to_actor`; `raycast_world` also returns
  `collider` and lifts floor-level points to y = 1.
- `Balance`: `kill_xp`, `monster_rarity(r)`, `monster_mod_count(rarity, depth)`, `total_xp_for_level`,
  `PLAYER_BASE_EVASION`, `DEATH_XP_PENALTY`.
- `ClassDefs`: `get_attribute_mods(class_id)` (use in `Player.get_base_mods`), `get_start_skill_bar`,
  `get_main_attribute`, `get_display_name`, `get_color`.
- `CharacterData`: `equip_from_inventory(index, slot = "", attrs = {})` → `{"ok", "reason", …}` and
  `unequip_to_inventory(slot)` do complete moves (emit `inventory_full` when needed) — UI should use
  them; `get_equip_conflicts(item, slot)`, `find_equipped_slot(item)`, `compute_attributes()` (class +
  gear + passives, for requirement checks without a Player), `allocate_passives(path)` (returns count),
  `refund_cost()`, `mark_depth_cleared(depth)` (true on first clear), `get_skill_in_slot`,
  `get_potion_charges(kind)`, `inventory_free_count`, `find_inventory_index`, `remove_from_inventory`,
  `first_free_stash_index`, `last_xp_loss`. `equip()` checks slot/off-hand rules only (requirements are
  `can_equip`'s job) and returns `[item]` unchanged when refused; ring_1→ring_2 swaps.
- `GameState`: `make_save_id`, `get_save_path`, `has_save`, `last_xp_award`; `award_kill_xp` shows an
  `"xp"` number above the player and carries fractional XP.

**Items** (`scripts/items/`, `item_db.gd`)
- `Item`: `get_unmet_requirements(attrs, level = -1)`, `meets_requirements`, `get_weapon_dps`,
  `get_comparison_lines(other)`, `clone`, `get_tier`, `get_item_class`, `get_effective_level`,
  `get_explicit_mods`, `get_local_mods`. Tooltip lines may carry `parts` (coloured runs), `hint` (affix name
  + tier) and `italic` (flavour) — TooltipPanel should render them.
- `ItemDB`: 258 bases (43 categories × 6 tiers), 65 affixes, 15 uniques; `get_bases_for_slot`,
  `get_categories`, `get_base_for_level`, `pick_slot_type`, `get_all_uniques`, … Returned dicts are SHARED:
  never mutate them. `generate_random_item` accepts a category id ("bow") as slot_type.
- `LootSystem.roll_gold`, `LootSystem.fallback_parent` (loot parent when there is no World).
- `GroundItem.pop_from(origin)`, `is_landed()`, `get_label_position()`; labels stack on screen.

**Tree** (`tree_db.gd`): nodes also have `region` and optional `orbit` ([cx, cy, r]: draw links between two
nodes with the same orbit as arcs via `get_link_arc(a, b)`). UI helpers: `NODE_RADIUS`, `REGION_COLORS`,
`REGION_NAMES`, `get_node_position`, `get_node_radius`, `get_node_type`, `get_region`, `get_links()`,
`find_node_at(pos, slack)`, `get_nodes_in_rect`, `get_allocatable`, `search(text)`,
`get_allocated_lines`, `sanitize_allocation`. Other classes' start nodes can't be allocated/passed.

**World** (`scripts/world/`)
- The **arena is centred on the world origin** (player start `Vector3.ZERO`); read `"origin"` from the
  minimap data. Town and dungeons keep origin (0,0,0) per §13.
- `find_path` returns smoothed waypoints WITHOUT the start point (~0.5 ms on 64×64).
- A **moving light pool** (≤ 17 OmniLights) follows the player/camera focus every 0.25 s; the flow may
  call `world.snap_light_pool()` right after placing the player.
- Portals: the start portal and the exit "Town" portal emit `("town", {"keep_dungeon": true})`;
  "Descend" emits `("dungeon", {"depth": d + 1})`. `world.spawn_town_portal(pos)` is idempotent (reuses a
  portal within 4.5 m, keeps only one) — the flow calls it on `dungeon_return` and after a death respawn.
- Also: `is_dungeon()`, `world_to_cell`, `cell_to_world`, `get_rooms()`, `get_boss_room_center()`,
  `get_path_distance()`, `get_interactables()`, `refresh_town_portal()`, `add_minimap_marker()`,
  minimap `"version"` key (changes when the explored map changes), `theme`, `grid`, `level_root`.
- Interactables (`WorldPortal.setup(dest, depth)`, `WorldChest.setup(tier, level)`, `WorldShrine`,
  `WorldVendorNpc`, `WorldStashChest`, `WorldWaypointGate`) highlight on hover by themselves.

**Characters** (`char_*` glb)
- Run cycles: planted-foot speed per model (set `run` speed_scale = move_speed / ref): player/skeleton
  5.2, brute 5.4, gravebreaker 6.7, ghoul 3.5, cultist 2.8, zombie ~3.3 m/s (may be retuned in the
  polish pass — read the model's `ref_run_speed` from the probe notes if provided).
- Bosses carry their weapons in the mesh (`char_gravebreaker` part `Weapon` = tombstone maul,
  `char_lich` staff); don't attach extras. The lich hovers by itself.
- `char_player`: `Hair` is a separate part — hide it when a helmet is worn. Empty glove/boot slots look
  better tinted a leather colour. Monster part names may be merged into one `Body` mesh in the polish
  pass: only rely on the `Weapon` part name for monsters; tint/flash whole models.
- Item icons are pre-coloured: don't multiply them by the item tint.

**Environment** (`env_*`, `town_*`, `proj_*`): `env_torch` origin on the wall face at floor level
(flame ≈ (0, 2.15, 0.3)); `env_portal` opening centred at (0, 1.65, 0), radius 1.05, facing +Z;
`town_stall` merchant spot (0, 0, −0.5); projectiles fly along +Z (materials `*tip*` mark the front);
glowing parts use `emit_*` materials; kit `tint_*` variants b/c/dark/top are intentionally darker.

---------------------------------------------------------------------------------------------------------

## 20. Acts (forest, desert, gothic town)

Three themed acts sit beside Emberfall and the dungeon depths: Act I forest, Act II desert, Act III
gothic town (`ActDefs.ACT_ORDER`). **Each act is ONE big seamless World**: the town ("hub"), a big open
"outskirts" zone and further zones joined by paths (each with a level offset), plus the act's
**dungeon** (a separate area behind a screen fade) whose door stands in one zone. `ActDefs`
(`scripts/world/acts/act_defs.gd`) holds per act: title, accent, base monster level, daylight, the
generator script, the layout file, the act boss (in the dungeon), the zone boss (outside the dungeon
door), the dungeon (`{"name", "theme", "region"}`, level offset `DUNGEON_LEVEL_OFFSET`) and the town's
name. `ActDefs.regions(act)` lists the town and the layout's zones (`{"id", "name", "level", "safe"}`);
`canonical_zone()` maps the old name "wilds" to "outskirts".

- **Layouts** (`data/layouts/act_<act>.json`, built by `tools/layouts/build_layouts.py` from
  `tools/layouts/specs/<act>.json`): per 2 × 2 m cell, which zone it belongs to (one letter per
  cell, "." = not walkable), zone stats (bbox, centroid, deepest cell), links between zones (where
  they touch), the exit towards the town and the dungeon door. A spec is either a **drawing** (closed
  outlines; walkable = inside an odd number of outlines; labels erased around the seed points; the
  town blob is dropped and becomes the exit; the dungeon box is dropped and its door noted) or
  **blobs** (rounded shapes + paths in metres). Zones are split by a seeded watershed on the distance
  to the walls, so borders fall in the paths between zones.
- **Generators** (`WorldActGen`, `act_gen.gd`; one subclass per act in `act_<act>.gd`, no
  `class_name`): the "hub" zone is the town (hand-placed, as before); the "wilds" zone is the whole
  outdoor map: `use_layout()` sets up the grid, regions, the exit and the start, then the act paints
  each region with the region API (`region_cells/rect/center/links/edge_cells/at/open`,
  `scatter_region`, `auto_spawn_region`, `add_zone_boss`, `dungeon_door`, `set_region_pool`,
  `set_region_theme`, `set_region_arrival`) and the usual helpers (`add_prop`, `add_obstacle`,
  `add_block`, `add_building`, `add_tiles`, lights, glows, shafts, chests, shrines,
  `add_dungeon_entrance`). The dungeon entrance may face any way. The camera looks north-west, so
  entrances should face south or east. It is drawn with the see-through (cut-out) material, and the
  player comes back out in front of it, or at `set_region_arrival("dungeon_exit", pos)`. Keep-outs and
  scatter use spatial hashes. `ground_color()` /
  `ground_height()` run for ~130k ground vertices: use `noise2()` (native FastNoiseLite) and per-cell
  fields (`field_from`, `field_distance_to`, `field_sample`, `distance_to_blocked`). Budgets per act:
  build ≤ ~4.5 s, ≤ ~9000 prop instances, ≤ ~3000 collision shapes. Each act may define its own
  monster variants in `scripts/world/acts/monsters_<act>.gd` (`const MONSTERS := {id: {"base", ...}}`,
  merged by EnemyDB).
- **Composing** (`WorldActComposite`, `act_compose.gd`): generates the town and the wilds, turns the
  wilds so the exits face each other (quarter turns, exact integer cell mapping), places them
  `EXIT_GAP_CELLS` apart, merges the grids, carves the road, transforms every output, drops what lies
  beyond the road's midline, marks the regions (the town up to the midline, the wilds' own zones
  beyond), blends the ground across the midline, lines the walkable edges with the act's border pieces
  (`border_style()`), and returns `regions` (the town first), `region_map`, `arrivals` (per zone plus
  "wilds", "town_portal", "dungeon_exit"), `region_themes`, spawn groups with `region`, `level_offset`
  and `pool`, `road`, `split`, `water_areas`, `fine_step`/`fine_rect` and a build `profile`.
- **World**: `_build_act` builds the ground in 32 m tiles (the wilds' step near walkable ground, the
  town's finer step around the town, 8 m far away). Relief is flattened on and near walkable cells:
  it eases in over ~3.5 m, but ground below a water plane's level eases in over ~2 m, so shores sit
  ~1 m from the walkable edge. It then builds water planes, tiles, props (chunked MultiMeshes),
  the ground detail (below), collision, lights (a moving pool when there are many), glows, shafts,
  environment, particles, interactables and each zone's `decorate()`; `build_profile` records the time
  per phase. Regions:
  `region_at`, `is_safe_at`, `get_region_arrival`, `region_level` (base level + offset),
  `current_region`; crossing a border (0.3 s debounce) updates `area_info` (`zone`, `name`, `safe`,
  `level`, `depth`, `cleared`), blends the environment over 2.5 s, and emits `Events.zone_entered`.
  The blend covers ambient, fog, sun, sky, tonemap and adjustments, plus volumetric fog, which is on
  for the whole act when any region has it. `set_region_theme` overrides merge nested looks such as
  `"volumetric_fog"` key by key. **Lazy
  spawning** (`start_lazy_spawns`, `lazy_spawn_tick`, `pending_groups`, `stop_lazy_spawns`): monster
  groups spawn when the player comes within `LAZY_RADIUS` (56 m), a few per 0.25 s, each with its
  zone's level and pool (`EnemyDB.spawn_group`).
- **Ground detail** (`WorldGroundFx`, `scripts/world/world_ground_fx.gd`, node "GroundFx"):
  - *Ground shader:* the act ground uses `WorldGroundFx.ground_material(style)`, where style =
    `WorldActGen.ground_style()` ("forest" / "desert" / "gothic", default the act id). Per vertex the
    generator gives its colour and four material weights (`ground_detail(x, z)` → UV, UV2). Per pixel
    the shader draws procedural texture with derivative bump mapping:
    - forest: gravel, mud and puddles, leaf litter, moss and needles;
    - desert: pebbles, sandstone slabs, sand bricks, cracked mud, plus wind ripples on open sand;
    - gothic: mud, puddles, dead leaves, grime.
  - *Details:* `add_detail(kind, pos, yaw, size, tint, lift)` / `scatter_details` add flat decals, drawn
    as chunked MultiMesh quads with one procedural shape per kind (`DETAIL_KINDS`: leaf, leaves,
    twigs, needles, straw, pebbles, bones, splinters, blood, puddle, glass, bricks, cracks, sand, moss,
    stain). They lie 1.8 cm above the ground, so also on paving.
  - *Grass:* `add_grass(pos, scale, tint, kind)` / `scatter_grass` add tufts (`GRASS_KINDS`: grass,
    reeds) in chunked MultiMeshes that fade out beyond ~58 m. They sway in the wind and bend away from
    "pushers": the player and the monsters within 30 m, plus fading trail points they leave behind
    (so the grass springs back), at most 32, uploaded to the shared material every frame.
  - The composer carries details and grass across and blends the weights like the colours. Each act
    fills them in `_ground_fx_wilds()` / `_ground_fx_hub()`. The preview's `--only=grass,details` shows
    close-ups.
- **Fog of war** (`WorldFog`, `scripts/world/world_fog.gd`, `World.fog`): a full-screen pass drawn after
  the scene. It rebuilds each pixel's floor position from the depth buffer:
  - ground farther than 14 m from the player darkens (fully at 27 m);
  - ground never explored (`grid.explored`, uploaded as a texture when it changes) is nearly black,
    with ragged, drifting edges; towns only use the distance shade.
  The player reveals `Player.EXPLORE_RADIUS` 22 m around them. The fog is only visible with a player in
  its world, so previews and tools are unaffected. `World.fog_of_war_enabled` / `set_fog_enabled()`,
  also exposed in the debug menu's Cheats tab.
- **Flow** (`main.gd`): `("act", {"act", "zone"})` for another act is a full change (with a "Loading
  …" line on the black screen); for the same act it becomes `"act_local"`, which re-places the player
  in the same World behind a fade (used for the town portal pair, death, and travel within an act).
  Walking between zones is no area change; entering the town refills. `("act_dungeon", {"act"})`
  detaches the act World (`Main._overworld`) and builds the dungeon (`FlowAreas.act_dungeon_info`:
  level = act level + 4, the act boss). Its start portal (`setup_overworld`) emits `"act_return"`
  (back in front of the door). The act boss's death spawns `PortalOut` and `PortalActNext` (the next
  act's town, Emberfall after the last). A zone boss's death clears its zone. A town portal or death
  in the act dungeon keeps the dungeon and leads to the act's town (return portal).
- **World predicates:** `is_act()`, `is_act_hub()` / `is_act_wilds()` (the current region is / is
  not safe), `is_safe_area()`, `is_combat_area()`, `is_daylit()`. `Player.is_in_dungeon()` is true
  outside town in an act.
- **Camera:** the default view is `CameraRig.PRESETS["diagonal"]` (yaw 37.5°, pitch 49.4°, 19.5 m),
  and there is a `"straight"` preset (yaw 0°, pitch 54.1°). The minimap turns with the camera's yaw,
  WASD moves relative to the view, the right mouse button orbits, F2 shows the camera numbers.
- **UI:** the Act Explorer (**M**, pause menu, a town's waystone) lists each act's town, zones (with
  levels) and dungeon. The debug menu (**F1**, pause menu, title screen) has Zones (every act zone and
  dungeon, Emberfall, the depths), Teleport (each zone, the boss, the next pack including packs not yet
  spawned, services, chests, the dungeon door) and Cheats.
- **Assets:** `tools/blender/acts/build_all.py` builds `desert.py` / `forest.py` / `gothic.py`
  (`BUILDERS = {id: fn}`; a module that fails to import is skipped) and runs `--check`.
- **Tools and tests:** `tools/layouts/build_layouts.py` (layouts + preview PNGs in
  `docs/screenshots/acts/layouts/`), `tools/godot/act_preview.tscn` (a whole act: overview, every
  zone's arrival / far spots / top view, road, seam, dungeon door; build time and profile; fly-around
  with `--hold`), `main.tscn -- --acts-tour=DIR`, and `tests/unit/test_acts_world.gd` /
  `test_acts_flow.gd` / `test_acts_debug_panel.gd`.

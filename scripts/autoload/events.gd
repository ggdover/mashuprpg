extends Node
## Autoload "Events": the global signal bus. It decouples gameplay from UI and game flow.
## OWNER: orchestrator. FROZEN during waves 1-2: module agents must NOT edit this file. Need a new signal/stat/helper?
## Keep it in a file you own and list it in your final report; the orchestrator merges between waves.
## Signals have no default arguments: always pass every parameter, e.g.
##   Events.notify.emit("Inventory full", UIStyle.COLOR_BAD)
##
##   Emit:    Events.level_up.emit(5)
##   Connect: Events.level_up.connect(_on_level_up)
##
## Parameters are typed loosely (Node / RefCounted), so this file has no class dependencies.

# ---------------------------------------------------------------- Game flow
## Main menu -> start a new character.
signal new_game_requested(char_name: String, class_id: String)
## Main menu -> load an existing save (save_id comes from GameState.list_saves()).
signal load_game_requested(save_id: String)
signal return_to_menu_requested()
signal quit_requested()
## Ask the game flow to change area. area_id is one of:
##   "town"            params {} or {"keep_dungeon": true} - the hub (keep_dungeon: the current
##                     dungeon World is detached and kept in GameState.town_portal_state)
##   "dungeon"         params {"depth": int}  - generate a fresh dungeon at that depth
##   "dungeon_return"                         - go back into the kept dungeon
signal area_change_requested(area_id: String, params: Dictionary)
## Emitted once the new area is built and the player is placed. See World.area_info for keys.
signal area_entered(area_info: Dictionary)
## A dungeon depth's boss was killed (first and repeat kills alike).
signal area_cleared(area_info: Dictionary)
## Inside an act world the player walked into another region (hub / wilds): area_info with the
## new "zone" / "name" (the HUD shows the name, the flow refills in the hub). No area change.
signal zone_entered(area_info: Dictionary)
## The player finished casting Town Portal (T) in a dungeon; the game flow keeps the dungeon and
## goes to town.
signal town_portal_requested()
signal player_spawned(player: Node)
signal player_died()
## Death screen -> respawn in town.
signal respawn_requested()
signal game_saved()

# ---------------------------------------------------------------- Character / progression
## xp = progress inside the current level.
signal xp_changed(xp: int, xp_needed: int, level: int)
signal level_up(new_level: int)
signal gold_changed(gold: int)
## The player's computed stats were rebuilt (equipment, passives, buffs or level changed).
signal player_stats_changed()
signal passives_changed()
signal skill_bar_changed()
signal potions_changed()

# ---------------------------------------------------------------- Items
signal inventory_changed()
signal equipment_changed(slot: String)
signal stash_changed()
signal item_picked_up(item: RefCounted)
signal gold_picked_up(amount: int)
signal loot_spawned(ground_item: Node)
## An item could not be picked up / moved because the inventory is full (UIRoot shows a message).
signal inventory_full()

# ---------------------------------------------------------------- Combat
## Floating combat text. kind is a damage type ("physical", "fire", "cold", "lightning", "chaos")
## or one of "heal", "mana", "evade", "block", "immune", "player_hurt", "xp".
signal damage_number(position: Vector3, amount: float, kind: String, is_crit: bool)
signal enemy_killed(enemy: Node)
## Emitted by a boss Enemy the first time it aggroes (not at spawn). HUD shows the boss bar.
signal boss_spawned(boss: Node)
signal boss_killed(boss: Node)
## A skill could not be used (player only, throttled by SkillRunner). reason is human readable
## ("Not enough mana", "Requires a Bow"). UIRoot shows it as a notification.
signal skill_use_failed(reason: String)
## Mouse-over target changed: an Enemy, a GroundItem / Interactable, or null.
signal hovered_target_changed(target: Node)

# ---------------------------------------------------------------- UI
## Toggle a panel by name (see UIRoot.PANELS).
signal panel_toggle_requested(panel: String)
## Open a panel with context, e.g. ("vendor", {}) or ("waypoint", {"max_depth": 5}).
signal panel_open_requested(panel: String, context: Dictionary)
signal panel_close_requested(panel: String)
## Centre-screen message ("Inventory full", "Level 5!").
signal notify(text: String, color: Color)

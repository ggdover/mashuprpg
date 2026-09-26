#!/usr/bin/env python3
"""Passive tree generator for Mashup RPG -> data/passive_tree.json (docs/ARCHITECTURE.md §10).

Deterministic, python3 standard library only. OWNER: tree module.

Layout (tree units ~ px at zoom 1, y points DOWN, angles in degrees, 0 = right, 90 = down):
  * 3 class starts at radius 350: sorcerer -90 (top), ranger 30 (lower right), warrior 150 (lower
    left). Each start has three exits to the inner ring (straight ahead and +-40 degrees).
  * three rings of travel nodes: inner (700), middle (1250) and outer (1750), joined by radial
    spokes (inner->middle at the sector centres, middle->outer at the sector boundaries).
  * six 60-degree regions (Int -90, Dex/Int -30, Dex 30, Str/Dex 90, Str 150, Int/Str 210) with
    themed clusters -- wheels (notable in the hub), loops (notable on the rim), forks (two
    notables) and spurs -- hanging off the rings into the space between them.
  * 9 keystones at the end of short spurs outside the outer ring.
  * a small nexus in the centre ("Convergence") joining the three hybrid inner wheels.

Output schema: §10 node fields plus optional additions used by TreeDB / the UI:
  "region": "str"|"dex"|"int"|"str_dex"|"dex_int"|"int_str"|"centre"
  "orbit":  [cx, cy, r] on ring and wheel-rim nodes; a link between two nodes with the same orbit
            may be drawn as the minor arc of that circle (TreeDB.get_link_arc).
  "key":    the node's stable semantic key (see "Stable ids" below).

Stable ids (saves store allocated node ids, so ids must never change between regenerations):
  * Every node gets a semantic KEY describing its slot in the plan, independent of build order:
      start:<class>                      class start
      ring_inner:<k> / ring_middle:<k> / ring_outer:<k>   k-th position on a ring (skips included)
      path[<key a>><key b>]:<i>          i-th travel node on the straight chain a -> b (exits, spokes)
      notable:<slug> / keystone:<slug>   notables and keystones, by name
      <group>:rim:<k>                    wheel/loop rim position k (<group> = slug of the cluster's
                                         first notable, or of the keystone for keystone spurs)
      <group>:stem:<i>, <group>:left:<j>, <group>:right:<j>   fork parts
      <group>:spur:<i>                   i-th small node of a spur (clusters and keystone spurs)
      convergence:<region>               the centre nexus links
  * tools/tree/id_map.json (checked in) maps key -> id. Every run reuses it: known keys keep their
    id, new keys get fresh ids appended after "next_id" (in build order), and ids of keys that
    are no longer built are retired (kept in the map, never reused). So regenerating never
    renumbers existing nodes. Never edit or delete the map by hand; commit it with the json.
  * Changing the plan: APPEND new slots (e.g. add a small at the end of a spur's list, a new
    cluster, a new ring) instead of re-keying existing ones. What a slot holds may change (its
    kind, position or links); the id then refers to the new content of that slot. Renaming a
    notable/keystone changes its key (-> new id; the old one is retired).
  * With no map at all, ids are assigned in build order (this bootstrapped the map from the
    original wave-1 numbering, which it reproduces exactly).

Every stat is validated against StatDefs.STATS parsed from scripts/core/stat_defs.gd, and the
geometry/graph rules are checked (spacing >= 60, links never pass through nodes or cross each
other -- both with straight links and with orbit links drawn as arcs --, every node reachable from
every start without passing other starts, >= 3 main-attribute nodes among the first 12 of each
start, >= 4 small nodes per cluster, unique keys and ids, value rules, counts). Any violation
aborts without writing.

Usage:
  python3 tools/tree/gen_passive_tree.py            # validate, print a summary, write the json + id map
  python3 tools/tree/gen_passive_tree.py --check    # validate + summary only (writes nothing)
  python3 tools/tree/gen_passive_tree.py --out PATH # write the tree somewhere else
  python3 tools/tree/gen_passive_tree.py --id-map PATH  # use / update another id map
  python3 tools/tree/gen_passive_tree.py --quiet    # no summary
  python3 tools/tree/test_gen_passive_tree.py       # generator unit tests (ids, regeneration)
"""
import argparse
import json
import math
import os
import re
import sys
from collections import Counter, deque

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_PATH = os.path.join(ROOT, "data", "passive_tree.json")
ID_MAP_PATH = os.path.join(ROOT, "tools", "tree", "id_map.json")
STAT_DEFS_PATH = os.path.join(ROOT, "scripts", "core", "stat_defs.gd")
# Minimum number of small/attribute nodes in every themed cluster (§10: 4-8 smalls + a notable).
MIN_CLUSTER_SMALLS = 4

# ------------------------------------------------------------------------------------------------
# Geometry constants
# ------------------------------------------------------------------------------------------------
START_RADIUS = 350.0
# ring -> (radius, node count, phase in degrees)
RINGS = {
    1: (700.0, 18, -90.0),
    2: (1250.0, 24, -90.0),
    3: (1750.0, 36, -90.0),
}
RING_GROUP = {1: "ring_inner", 2: "ring_middle", 3: "ring_outer"}
# Ring nodes left out (angle offsets from every sector centre): nothing hangs there.
RING_SKIP = {3: (-10.0, 10.0)}
KEYSTONE_RADIUS = 2080.0
MIN_SPACING = 60.0
# Suggested drawing radii (also exported by TreeDB.NODE_RADIUS); links keep this + margin clear.
DRAW_RADIUS = {"start": 38.0, "keystone": 32.0, "notable": 24.0, "small": 14.0, "attribute": 12.0}
LINK_MARGIN = 10.0

SECTOR_CENTRE = {
    "int": -90.0,
    "dex_int": -30.0,
    "dex": 30.0,
    "str_dex": 90.0,
    "str": 150.0,
    "int_str": 210.0,
}
SECTOR_ORDER = ["int", "dex_int", "dex", "str_dex", "str", "int_str"]
CLASSES = [  # class id, region, start node name, main attribute stat
    ("warrior", "str", "Warrior", "strength"),
    ("ranger", "dex", "Ranger", "dexterity"),
    ("sorcerer", "int", "Sorcerer", "intelligence"),
]

# ------------------------------------------------------------------------------------------------
# Small nodes: kind -> (name, [(stat, op, value), ...]). Values per §10: pools/defences inc,
# damage 8-12% inc, speeds 3-5%, flat only for attributes, crit multiplier and resistances (and
# for stats that only exist as flat values: block, ailment chances, leech, regen %, pierce...).
# ------------------------------------------------------------------------------------------------
SMALL = {
    # attributes (type "attribute")
    "str": ("Strength", [("strength", "flat", 10)]),
    "dex": ("Dexterity", [("dexterity", "flat", 10)]),
    "int": ("Intelligence", [("intelligence", "flat", 10)]),
    # pools & recovery
    "life": ("Life", [("max_life", "inc", 6)]),
    "life_regen": ("Life Regeneration", [("life_regen_percent", "flat", 0.4)]),
    "mana": ("Mana", [("max_mana", "inc", 10)]),
    "mana_regen": ("Mana Regeneration", [("mana_regen", "inc", 15)]),
    "es": ("Energy Shield", [("max_energy_shield", "inc", 10)]),
    "es_recharge": ("Energy Shield Recharge", [("energy_shield_recharge", "inc", 12), ("max_energy_shield", "inc", 4)]),
    "leech": ("Life Leech", [("life_leech", "flat", 0.4)]),
    "life_on_kill": ("Life on Kill", [("life_on_kill", "flat", 4)]),
    "potion": ("Potion Effect", [("potion_effect", "inc", 10)]),
    # defences
    "armour": ("Armour", [("armour", "inc", 15)]),
    "evasion": ("Evasion", [("evasion", "inc", 15)]),
    "armour_eva": ("Armour and Evasion", [("armour", "inc", 8), ("evasion", "inc", 8)]),
    "armour_es": ("Armour and Energy Shield", [("armour", "inc", 8), ("max_energy_shield", "inc", 5)]),
    "eva_es": ("Evasion and Energy Shield", [("evasion", "inc", 8), ("max_energy_shield", "inc", 5)]),
    "block": ("Block", [("block_chance", "flat", 2)]),
    "phys_red": ("Physical Damage Reduction", [("physical_damage_reduction", "flat", 2)]),
    "res_fire": ("Fire Resistance", [("fire_resistance", "flat", 8)]),
    "res_cold": ("Cold Resistance", [("cold_resistance", "flat", 8)]),
    "res_light": ("Lightning Resistance", [("lightning_resistance", "flat", 8)]),
    "res_chaos": ("Chaos Resistance", [("chaos_resistance", "flat", 7)]),
    "res_all": ("Elemental Resistances", [("elemental_resistance", "flat", 6)]),
    # generic damage
    "damage": ("Damage", [("damage", "inc", 8)]),
    "phys": ("Physical Damage", [("physical_damage", "inc", 10)]),
    "melee": ("Melee Damage", [("melee_damage", "inc", 10)]),
    "attack": ("Attack Damage", [("attack_damage", "inc", 10)]),
    "spell": ("Spell Damage", [("spell_damage", "inc", 10)]),
    "projectile": ("Projectile Damage", [("projectile_damage", "inc", 10)]),
    "area": ("Area Damage", [("area_damage", "inc", 10)]),
    "dot": ("Damage over Time", [("damage_over_time", "inc", 10)]),
    "elemental": ("Elemental Damage", [("elemental_damage", "inc", 10)]),
    "fire": ("Fire Damage", [("fire_damage", "inc", 10)]),
    "cold": ("Cold Damage", [("cold_damage", "inc", 10)]),
    "lightning": ("Lightning Damage", [("lightning_damage", "inc", 10)]),
    "chaos": ("Chaos Damage", [("chaos_damage", "inc", 10)]),
    # weapons
    "two_handed": ("Two Handed Damage", [("two_handed_damage", "inc", 12)]),
    "one_handed": ("One Handed Damage", [("one_handed_damage", "inc", 12)]),
    "sword": ("Sword Damage", [("sword_damage", "inc", 12)]),
    "axe": ("Axe Damage", [("axe_damage", "inc", 12)]),
    "mace": ("Mace Damage", [("mace_damage", "inc", 12)]),
    "dagger": ("Dagger Damage", [("dagger_damage", "inc", 12)]),
    "bow": ("Bow Damage", [("bow_damage", "inc", 12)]),
    "crossbow": ("Crossbow Damage", [("crossbow_damage", "inc", 12)]),
    "staff": ("Staff Damage", [("staff_damage", "inc", 12)]),
    # speed
    "attack_speed": ("Attack Speed", [("attack_speed", "inc", 4)]),
    "cast_speed": ("Cast Speed", [("cast_speed", "inc", 4)]),
    "move": ("Movement Speed", [("movement_speed", "inc", 3)]),
    # critical strikes
    "crit": ("Critical Strike Chance", [("crit_chance", "inc", 12)]),
    "crit_multi": ("Critical Strike Multiplier", [("crit_multiplier", "flat", 12)]),
    # ailments
    "bleed": ("Bleeding", [("bleed_chance", "flat", 5)]),
    "poison": ("Poison", [("poison_chance", "flat", 5)]),
    "ignite": ("Ignite", [("ignite_chance", "flat", 5)]),
    "freeze": ("Freeze", [("freeze_chance", "flat", 4)]),
    "shock": ("Shock", [("shock_chance", "flat", 5)]),
    # skill behaviour & utility
    "aoe": ("Area of Effect", [("area_of_effect", "inc", 6)]),
    "proj_speed": ("Projectile Speed", [("projectile_speed", "inc", 10)]),
    "duration": ("Skill Duration", [("skill_duration", "inc", 8)]),
    "cdr": ("Cooldown Recovery", [("cooldown_recovery", "inc", 5)]),
    "mana_cost": ("Mana Efficiency", [("mana_cost", "inc", -4)]),
    "rarity": ("Item Rarity", [("item_rarity", "inc", 8)]),
    "gold": ("Gold Find", [("gold_find", "inc", 10)]),
}
ATTRIBUTE_KINDS = {"str": "strength", "dex": "dexterity", "int": "intelligence"}

# Travel nodes (rings, spokes, exits) cycle through these per region.
REGION_ATTRS = {
    "str": ["str"],
    "dex": ["dex"],
    "int": ["int"],
    "str_dex": ["str", "dex"],
    "dex_int": ["dex", "int"],
    "int_str": ["int", "str"],
    "centre": ["str", "dex", "int"],
}
REGION_THEMES = {
    "str": ["life", "armour", "melee", "life_regen", "phys"],
    "dex": ["evasion", "attack_speed", "projectile", "move", "crit"],
    "int": ["es", "mana", "spell", "cast_speed", "mana_regen"],
    "str_dex": ["attack", "armour_eva", "phys", "life", "attack_speed"],
    "dex_int": ["crit", "eva_es", "elemental", "chaos", "evasion"],
    "int_str": ["fire", "armour_es", "area", "res_all", "es"],
    "centre": ["damage", "life", "res_all"],
}

# ------------------------------------------------------------------------------------------------
# Notables (2-3 mods) and keystones (§10)
# ------------------------------------------------------------------------------------------------
NOTABLES = {
    # --- Int (sorcerer): energy shield, mana, spell damage, cast speed, elements
    "Arcane Potency": [("spell_damage", "inc", 25), ("cast_speed", "inc", 5)],
    "Wellspring of Mana": [("max_mana", "inc", 20), ("mana_regen", "inc", 25)],
    "Crystalline Aegis": [("max_energy_shield", "inc", 25), ("energy_shield_recharge", "inc", 20)],
    "Prismatic Barrier": [("max_energy_shield", "inc", 15), ("elemental_resistance", "flat", 8)],
    "Quickened Incantations": [("cast_speed", "inc", 12), ("spell_damage", "inc", 10)],
    "Mental Discipline": [("mana_cost", "inc", -10), ("max_mana", "inc", 10), ("mana_regen", "inc", 10)],
    "Elemental Conduit": [("elemental_damage", "inc", 25), ("spell_damage", "inc", 10)],
    "Glacial Heart": [("cold_damage", "inc", 25), ("freeze_chance", "flat", 6)],
    "Archmage's Insight": [("spell_damage", "inc", 30), ("max_mana", "inc", 10)],
    # --- Dex/Int: crit, poison, chaos, cold/lightning, evasion + ES
    "Keen Perception": [("crit_chance", "inc", 25), ("crit_multiplier", "flat", 15)],
    "Winter's Embrace": [("cold_damage", "inc", 25), ("freeze_chance", "flat", 8)],
    "Serpent's Kiss": [("poison_chance", "flat", 15), ("damage_over_time", "inc", 15)],
    "Stormcaller": [("lightning_damage", "inc", 25), ("shock_chance", "flat", 10)],
    "Forked Lightning": [("chain", "flat", 1), ("lightning_damage", "inc", 10)],
    "Shadow Veil": [("evasion", "inc", 20), ("max_energy_shield", "inc", 15), ("movement_speed", "inc", 4)],
    "Blightweaver": [("chaos_damage", "inc", 25), ("chaos_resistance", "flat", 12)],
    "Assassin's Mark": [("crit_multiplier", "flat", 25), ("crit_chance", "inc", 15)],
    "Twin Fangs": [("dagger_damage", "inc", 25), ("attack_speed", "inc", 5), ("poison_chance", "flat", 5)],
    "Toxic Bloom": [("poison_chance", "flat", 10), ("damage_over_time", "inc", 20), ("skill_duration", "inc", 10)],
    # --- Dex (ranger): evasion, attack speed, bows, crossbows, projectiles, movement, crit
    "Deadeye": [("bow_damage", "inc", 25), ("crit_chance", "inc", 15)],
    "Fleet Footed": [("movement_speed", "inc", 8), ("evasion", "inc", 20)],
    "Treasure Hunter": [("item_rarity", "inc", 20), ("gold_find", "inc", 20)],
    "Farshot": [("projectile_damage", "inc", 20), ("projectile_speed", "inc", 20)],
    "Sharpshooter": [("crit_chance", "inc", 20), ("projectile_damage", "inc", 10), ("crit_multiplier", "flat", 10)],
    "Hunter's Rhythm": [("attack_speed", "inc", 10), ("attack_damage", "inc", 10)],
    "Heavy Bolts": [("crossbow_damage", "inc", 25), ("pierce", "flat", 1)],
    "Crank and Load": [("crossbow_damage", "inc", 15), ("attack_speed", "inc", 8)],
    "Hail of Arrows": [("additional_projectiles", "flat", 1), ("bow_damage", "inc", 10)],
    # --- Str/Dex: bleed, attack damage, two-handed, armour + evasion, leech
    "Blood Drinker": [("life_leech", "flat", 1.0), ("attack_damage", "inc", 15)],
    "Hemorrhage": [("bleed_chance", "flat", 15), ("damage_over_time", "inc", 15)],
    "Titan's Grip": [("two_handed_damage", "inc", 25), ("melee_damage", "inc", 10)],
    "Ironwood Hide": [("armour", "inc", 20), ("evasion", "inc", 20), ("max_life", "inc", 5)],
    "Warlord's Command": [("attack_damage", "inc", 20), ("attack_speed", "inc", 5)],
    "Executioner": [("crit_multiplier", "flat", 20), ("two_handed_damage", "inc", 15)],
    "Butcher's Art": [("physical_damage", "inc", 20), ("bleed_chance", "flat", 8)],
    "Vampiric Frenzy": [("life_leech", "flat", 0.8), ("attack_speed", "inc", 6), ("life_on_kill", "flat", 5)],
    "Rending Wounds": [("damage_over_time", "inc", 20), ("bleed_chance", "flat", 10), ("physical_damage", "inc", 10)],
    # --- Str (warrior): life, armour, melee, physical, axes/maces/swords, shields/block, regen
    "Brute Force": [("melee_damage", "inc", 25), ("max_life", "inc", 5)],
    "Heart of the Oak": [("max_life", "inc", 12), ("life_regen_percent", "flat", 0.8)],
    "Blade Dancer": [("sword_damage", "inc", 25), ("attack_speed", "inc", 5)],
    "Headsman": [("axe_damage", "inc", 25), ("bleed_chance", "flat", 5)],
    "Iron Skin": [("armour", "inc", 30), ("physical_damage_reduction", "flat", 3)],
    "Unbreakable": [("max_life", "inc", 8), ("armour", "inc", 15), ("damage_taken", "inc", -4)],
    "Shield Wall": [("block_chance", "flat", 6), ("armour", "inc", 15)],
    "Sword and Board": [("one_handed_damage", "inc", 20), ("block_chance", "flat", 3)],
    "Skullcrusher": [("mace_damage", "inc", 25), ("area_damage", "inc", 10)],
    "Troll's Blood": [("life_regen_percent", "flat", 1.5), ("max_life", "inc", 8)],
    # --- Int/Str: fire, ignite, area, armour + ES, mana regen, resistances
    "Elemental Warding": [("elemental_resistance", "flat", 12), ("armour", "inc", 10)],
    "Pyromancer": [("fire_damage", "inc", 25), ("ignite_chance", "flat", 8)],
    "Cataclysm": [("area_damage", "inc", 20), ("area_of_effect", "inc", 12)],
    "Everburning Flame": [("damage_over_time", "inc", 20), ("ignite_chance", "flat", 10), ("fire_damage", "inc", 10)],
    "Sacred Bastion": [("armour", "inc", 20), ("max_energy_shield", "inc", 15), ("block_chance", "flat", 2)],
    "Deep Meditation": [("mana_regen", "inc", 30), ("max_mana", "inc", 10)],
    "Staff Adept": [("staff_damage", "inc", 25), ("block_chance", "flat", 3)],
    "Heart of Flame": [("fire_damage", "inc", 30), ("fire_resistance", "flat", 10)],
    "Crimson Covenant": [("max_life", "inc", 10), ("mana_cost", "inc", -8)],
    # --- centre
    "Convergence": [("all_attributes", "flat", 10), ("damage", "inc", 6)],
}

KEYSTONES = {
    "Mind over Matter": [("mind_over_matter", "flag", 0)],
    "Pain Attunement": [("pain_attunement", "flag", 0)],
    "Glass Cannon": [("damage", "more", 50), ("max_life", "more", -40)],
    "Acrobatics": [("evade_chance", "flat", 30), ("armour", "more", -50), ("max_energy_shield", "more", -50)],
    "Point Blank": [("point_blank", "flag", 0)],
    "Iron Reflexes": [("iron_reflexes", "flag", 0)],
    "Resolute Technique": [("no_crit", "flag", 0), ("attack_damage", "more", 30)],
    "Unwavering Stance": [("cannot_evade", "flag", 0), ("armour", "more", 30), ("physical_damage_reduction", "flat", 10)],
    "Blood Magic": [("blood_magic", "flag", 0), ("max_mana", "more", -100)],
}

# ------------------------------------------------------------------------------------------------
# Content plan per region. Slots (ring, angle offset from the sector centre, +1 out / -1 in):
# ------------------------------------------------------------------------------------------------
SLOTS = {
    "inner": (1, 0.0, -1),     # hybrid regions: hangs inward from the inner ring
    "g1a": (1, -20.0, +1),     # inner ring -> outward
    "g1b": (2, +15.0, -1),     # middle ring -> inward
    "g2a": (2, -15.0, +1),     # middle ring -> outward
    "g2b": (3, 0.0, -1),       # outer ring -> inward
    "g2c": (2, +15.0, +1),     # middle ring -> outward
    "outer": (3, 0.0, +1),     # outer ring -> outward (main-attribute regions)
    "outer_l": (3, -20.0, +1),  # outer ring -> outward (hybrid regions)
    "outer_r": (3, +20.0, +1),
}

# Cluster templates:
#   wheel : n smalls on a circle, notable in the hub (linked to the far rim node(s))
#   loop  : a rim of smalls whose far point is the notable (two ways round)
#   wheel2: wheel + a second notable beyond the far rim node
#   fork  : stem of smalls, then two branches each ending in a notable
#   spur  : a straight line of smalls ending in a notable
CLUSTERS = {
    "int": [
        {"slot": "g1a", "tpl": "wheel", "smalls": ["spell", "int", "cast_speed", "int", "spell"], "notables": ["Arcane Potency"]},
        {"slot": "g1b", "tpl": "loop", "smalls": ["mana", "mana_regen", "mana", "mana_regen", "mana"], "notables": ["Wellspring of Mana"]},
        {"slot": "g2a", "tpl": "wheel2", "smalls": ["es", "es_recharge", "es", "int", "es_recharge", "es"], "notables": ["Crystalline Aegis", "Prismatic Barrier"]},
        {"slot": "g2b", "tpl": "fork", "spread": 28.0, "stem": ["cast_speed"], "left": ["cast_speed", "spell"], "right": ["mana_cost", "mana"], "notables": ["Quickened Incantations", "Mental Discipline"]},
        {"slot": "g2c", "tpl": "fork", "stem": ["elemental"], "left": ["elemental", "spell"], "right": ["cold", "cold"], "notables": ["Elemental Conduit", "Glacial Heart"]},
        {"slot": "outer", "tpl": "loop", "smalls": ["spell", "mana", "mana", "spell"], "notables": ["Archmage's Insight"]},
    ],
    "dex_int": [
        {"slot": "inner", "tpl": "wheel", "smalls": ["crit", "dex", "crit_multi", "crit", "int", "crit"], "notables": ["Keen Perception"], "nexus": True},
        {"slot": "g1a", "tpl": "loop", "smalls": ["cold", "cold", "freeze", "cold", "cold"], "notables": ["Winter's Embrace"]},
        {"slot": "g1b", "tpl": "wheel", "smalls": ["poison", "chaos", "poison", "dot", "poison"], "notables": ["Serpent's Kiss"]},
        {"slot": "g2a", "tpl": "fork", "stem": ["lightning"], "left": ["lightning", "shock"], "right": ["lightning", "elemental"], "notables": ["Stormcaller", "Forked Lightning"]},
        {"slot": "g2b", "tpl": "wheel", "smalls": ["eva_es", "dex", "eva_es", "int", "eva_es"], "notables": ["Shadow Veil"]},
        {"slot": "g2c", "tpl": "loop", "smalls": ["chaos", "res_chaos", "chaos", "dot", "chaos"], "notables": ["Blightweaver"]},
        {"slot": "outer_l", "tpl": "fork", "stem": [], "left": ["crit_multi", "crit"], "right": ["dagger", "dagger"], "notables": ["Assassin's Mark", "Twin Fangs"]},
        {"slot": "outer_r", "tpl": "spur", "bend": -22.0, "smalls": ["poison", "duration", "chaos", "dot"], "notables": ["Toxic Bloom"]},
    ],
    "dex": [
        {"slot": "g1a", "tpl": "wheel", "smalls": ["bow", "crit", "bow", "dex", "bow"], "notables": ["Deadeye"]},
        {"slot": "g1b", "tpl": "wheel2", "smalls": ["move", "evasion", "gold", "rarity", "evasion", "move"], "notables": ["Fleet Footed", "Treasure Hunter"]},
        {"slot": "g2a", "tpl": "wheel2", "smalls": ["projectile", "proj_speed", "projectile", "crit", "proj_speed", "projectile"], "notables": ["Farshot", "Sharpshooter"]},
        {"slot": "g2b", "tpl": "wheel", "smalls": ["attack_speed", "attack_speed", "dex", "attack_speed", "attack_speed"], "notables": ["Hunter's Rhythm"]},
        {"slot": "g2c", "tpl": "fork", "stem": ["crossbow"], "left": ["crossbow", "projectile"], "right": ["crossbow", "attack_speed"], "notables": ["Heavy Bolts", "Crank and Load"]},
        {"slot": "outer", "tpl": "wheel", "smalls": ["projectile", "bow", "projectile", "bow"], "notables": ["Hail of Arrows"]},
    ],
    "str_dex": [
        {"slot": "inner", "tpl": "wheel", "smalls": ["leech", "attack", "str", "leech", "dex", "attack"], "notables": ["Blood Drinker"], "nexus": True},
        {"slot": "g1a", "tpl": "loop", "smalls": ["bleed", "phys", "bleed", "dot", "bleed"], "notables": ["Hemorrhage"]},
        {"slot": "g1b", "tpl": "wheel", "smalls": ["two_handed", "str", "two_handed", "melee", "two_handed"], "notables": ["Titan's Grip"]},
        {"slot": "g2a", "tpl": "wheel", "smalls": ["armour_eva", "str", "armour_eva", "dex", "armour_eva"], "notables": ["Ironwood Hide"]},
        {"slot": "g2b", "tpl": "fork", "spread": 28.0, "stem": ["attack"], "left": ["attack", "attack_speed"], "right": ["two_handed", "crit_multi"], "notables": ["Warlord's Command", "Executioner"]},
        {"slot": "g2c", "tpl": "wheel", "smalls": ["phys", "bleed", "phys", "two_handed", "phys"], "notables": ["Butcher's Art"]},
        {"slot": "outer_l", "tpl": "spur", "bend": 22.0, "smalls": ["leech", "attack_speed", "life_on_kill", "leech"], "notables": ["Vampiric Frenzy"]},
        {"slot": "outer_r", "tpl": "wheel", "smalls": ["bleed", "dot", "bleed", "phys"], "notables": ["Rending Wounds"]},
    ],
    "str": [
        {"slot": "g1a", "tpl": "wheel", "smalls": ["melee", "str", "melee", "phys", "melee"], "notables": ["Brute Force"]},
        {"slot": "g1b", "tpl": "loop", "smalls": ["life", "life_regen", "potion", "life_regen", "life"], "notables": ["Heart of the Oak"]},
        {"slot": "g2a", "tpl": "fork", "stem": ["one_handed"], "left": ["sword", "sword"], "right": ["axe", "axe"], "notables": ["Blade Dancer", "Headsman"]},
        {"slot": "g2b", "tpl": "wheel2", "smalls": ["armour", "armour", "phys_red", "str", "armour", "life"], "notables": ["Iron Skin", "Unbreakable"]},
        {"slot": "g2c", "tpl": "fork", "stem": ["block"], "left": ["block", "armour"], "right": ["one_handed", "block"], "notables": ["Shield Wall", "Sword and Board"]},
        {"slot": "outer", "tpl": "fork", "stem": [], "left": ["mace", "mace"], "right": ["life_regen", "life"], "notables": ["Skullcrusher", "Troll's Blood"]},
    ],
    "int_str": [
        {"slot": "inner", "tpl": "wheel", "smalls": ["res_fire", "str", "res_cold", "res_light", "int", "res_all"], "notables": ["Elemental Warding"], "nexus": True},
        {"slot": "g1a", "tpl": "loop", "smalls": ["fire", "fire", "ignite", "fire", "fire"], "notables": ["Pyromancer"]},
        {"slot": "g1b", "tpl": "wheel", "smalls": ["area", "aoe", "cdr", "aoe", "area"], "notables": ["Cataclysm"]},
        {"slot": "g2a", "tpl": "wheel", "smalls": ["ignite", "dot", "fire", "dot", "ignite"], "notables": ["Everburning Flame"]},
        {"slot": "g2b", "tpl": "wheel", "smalls": ["armour_es", "str", "armour_es", "int", "armour_es"], "notables": ["Sacred Bastion"]},
        {"slot": "g2c", "tpl": "fork", "stem": ["mana_regen"], "left": ["mana_regen", "mana"], "right": ["staff", "staff"], "notables": ["Deep Meditation", "Staff Adept"]},
        {"slot": "outer_l", "tpl": "wheel", "smalls": ["fire", "res_fire", "fire", "fire"], "notables": ["Heart of Flame"]},
        {"slot": "outer_r", "tpl": "spur", "bend": -22.0, "smalls": ["life", "life_regen", "life", "mana_cost"], "notables": ["Crimson Covenant"]},
    ],
}

# Keystones: name -> (region, angle, small kinds on the spur from the outer ring)
KEYSTONE_PLAN = [
    ("Mind over Matter", "int", -110.0, ["mana", "mana"]),
    ("Pain Attunement", "int", -70.0, ["spell", "spell"]),
    ("Glass Cannon", "dex_int", -30.0, ["damage", "damage"]),
    ("Acrobatics", "dex", 10.0, ["evasion", "evasion"]),
    ("Point Blank", "dex", 50.0, ["projectile", "projectile"]),
    ("Iron Reflexes", "str_dex", 90.0, ["armour_eva", "armour_eva"]),
    ("Resolute Technique", "str", 130.0, ["attack", "melee"]),
    ("Unwavering Stance", "str", 170.0, ["armour", "armour"]),
    ("Blood Magic", "int_str", 210.0, ["life", "life"]),
]

WHEEL_RADIUS = {4: 85.0, 5: 100.0, 6: 112.0}
CLUSTER_GAP = 90.0     # anchor -> first cluster node
STEP = 105.0           # spacing along spurs and fork branches
FORK_SPREAD = 36.0     # degrees


# ------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------
def pol(radius, deg):
    a = math.radians(deg)
    return (radius * math.cos(a), radius * math.sin(a))


def norm_deg(a):
    a = math.fmod(a + 180.0, 360.0)
    if a < 0:
        a += 360.0
    return a - 180.0


def region_of_angle(deg):
    best, best_d = None, 999.0
    for key in SECTOR_ORDER:
        d = abs(norm_deg(deg - SECTOR_CENTRE[key] + 0.01))
        if d < best_d:
            best, best_d = key, d
    return best


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def num(v):
    """JSON-friendly number: ints stay ints."""
    if isinstance(v, float) and abs(v - round(v)) < 1e-9:
        return int(round(v))
    return v


def mods_of(triples):
    return [{"stat": s, "op": o, "value": num(v)} for (s, o, v) in triples]


class Builder:
    """Builds the node list. Node "id"s are build-order indices here; assign_ids() then maps
    them to the stable ids of the id map through each node's semantic "key"."""

    def __init__(self):
        self.nodes = []
        self.keys = {}
        self.travel_counters = Counter()
        self.ring_ids = {}
        self.start_ids = {}

    # -------------------------------------------------------------- nodes
    def add(self, ntype, name, pos, mods, group, region, key, cls=None, orbit=None):
        if key in self.keys:
            raise SystemExit("duplicate node key '%s'" % key)
        nid = len(self.nodes)
        node = {
            "id": nid, "key": key, "name": name, "type": ntype,
            "x": round(pos[0], 1), "y": round(pos[1], 1),
            "mods": mods, "links": [], "group": group, "region": region,
        }
        if cls is not None:
            node["class"] = cls
        if orbit is not None:
            node["orbit"] = [round(orbit[0], 1), round(orbit[1], 1), round(orbit[2], 1)]
        self.nodes.append(node)
        self.keys[key] = nid
        return nid

    def add_small(self, kind, pos, group, region, key, orbit=None):
        if kind not in SMALL:
            raise SystemExit("unknown small node kind '%s'" % kind)
        name, triples = SMALL[kind]
        ntype = "attribute" if kind in ATTRIBUTE_KINDS else "small"
        return self.add(ntype, name, pos, mods_of(triples), group, region, key, orbit=orbit)

    def add_notable(self, name, pos, group, region, orbit=None):
        if name not in NOTABLES:
            raise SystemExit("unknown notable '%s'" % name)
        return self.add("notable", name, pos, mods_of(NOTABLES[name]), group, region,
                        "notable:" + slugify(name), orbit=orbit)

    def key(self, nid):
        return self.nodes[nid]["key"]

    def link(self, a, b):
        if a == b:
            raise SystemExit("self link on %d" % a)
        if b not in self.nodes[a]["links"]:
            self.nodes[a]["links"].append(b)
        if a not in self.nodes[b]["links"]:
            self.nodes[b]["links"].append(a)

    def pos(self, nid):
        n = self.nodes[nid]
        return (n["x"], n["y"])

    def travel_kind(self, region, attribute):
        if attribute:
            pool = REGION_ATTRS[region]
            key = region + ":attr"
        else:
            pool = REGION_THEMES[region]
            key = region + ":theme"
        kind = pool[self.travel_counters[key] % len(pool)]
        self.travel_counters[key] += 1
        return kind

    def path(self, a, b, count, pattern, group, region=None):
        """Straight chain of `count` travel nodes between existing nodes a and b.
        pattern: string of 'a' (attribute) / 't' (theme) per node."""
        pa, pb = self.pos(a), self.pos(b)
        prev = a
        ids = []
        for i in range(count):
            t = (i + 1) / (count + 1)
            p = (pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t)
            reg = region or region_of_angle(math.degrees(math.atan2(p[1], p[0])))
            kind = self.travel_kind(reg, pattern[i % len(pattern)] == "a")
            key = "path[%s>%s]:%d" % (self.key(a), self.key(b), i)
            nid = self.add_small(kind, p, group, reg, key)
            self.link(prev, nid)
            prev = nid
            ids.append(nid)
        self.link(prev, b)
        return ids

    # -------------------------------------------------------------- rings
    def build_rings(self):
        for r, (radius, count, phase) in RINGS.items():
            ids = {}
            order = []
            for k in range(count):
                ang = phase + k * 360.0 / count
                if any(abs(norm_deg(ang - SECTOR_CENTRE[sec] - off)) < 1e-6
                       for sec in SECTOR_ORDER for off in RING_SKIP.get(r, ())):
                    continue
                region = region_of_angle(ang)
                kind = self.travel_kind(region, len(order) % 2 == 0)
                key = "%s:%d" % (RING_GROUP[r], k)
                nid = self.add_small(kind, pol(radius, ang), RING_GROUP[r], region, key, (0.0, 0.0, radius))
                ids[k] = nid
                order.append(nid)
            for i in range(len(order)):
                self.link(order[i], order[(i + 1) % len(order)])
            self.ring_ids[r] = ids

    def ring_at(self, r, deg):
        radius, count, phase = RINGS[r]
        step = 360.0 / count
        k = (deg - phase) / step
        idx = int(round(k)) % count
        if abs(k - round(k)) > 1e-6 or idx not in self.ring_ids[r]:
            raise SystemExit("ring %d has no node at %.2f degrees" % (r, deg))
        return self.ring_ids[r][idx]

    # -------------------------------------------------------------- clusters
    def build_cluster(self, region, spec):
        ring, offset, sgn = SLOTS[spec["slot"]]
        ang = SECTOR_CENTRE[region] + offset
        anchor = self.ring_at(ring, ang)
        ax, ay = self.pos(anchor)
        rad = math.radians(ang)
        u = (math.cos(rad) * sgn, math.sin(rad) * sgn)
        v = (-u[1], u[0])

        def P(a, b):
            return (ax + a * u[0] + b * v[0], ay + a * u[1] + b * v[1])

        group = slugify(spec["notables"][0])
        tpl = spec["tpl"]
        far = None
        if tpl in ("wheel", "wheel2", "loop"):
            smalls = spec["smalls"]
            n = len(smalls) + (1 if tpl == "loop" else 0)
            rho = WHEEL_RADIUS[n]
            centre_a = CLUSTER_GAP + rho
            rim = []
            si = 0
            notable_rim = n // 2 if tpl == "loop" else -1
            hub_pos = P(centre_a, 0.0)
            orbit = (hub_pos[0], hub_pos[1], rho)
            for k in range(n):
                phi = 2.0 * math.pi * k / n
                p = P(centre_a - rho * math.cos(phi), rho * math.sin(phi))
                if k == notable_rim:
                    rim.append(self.add_notable(spec["notables"][0], p, group, region, orbit))
                else:
                    rim.append(self.add_small(smalls[si], p, group, region, "%s:rim:%d" % (group, k), orbit))
                    si += 1
            self.link(anchor, rim[0])
            for k in range(n):
                self.link(rim[k], rim[(k + 1) % n])
            if tpl in ("wheel", "wheel2"):
                hub = self.add_notable(spec["notables"][0], hub_pos, group, region)
                if n % 2 == 0:
                    self.link(hub, rim[n // 2])
                    far = rim[n // 2]
                else:
                    self.link(hub, rim[n // 2])
                    self.link(hub, rim[n // 2 + 1])
                    far = rim[n // 2]
                if tpl == "wheel2":
                    if n % 2 != 0:
                        raise SystemExit("wheel2 needs an even rim")
                    outer = self.add_notable(spec["notables"][1], P(centre_a + rho + STEP, 0.0), group, region)
                    self.link(rim[n // 2], outer)
            else:
                far = rim[n // 2]
        elif tpl == "fork":
            prev = anchor
            a = 0.0
            for i, kind in enumerate(spec["stem"]):
                a = CLUSTER_GAP + i * STEP
                nid = self.add_small(kind, P(a, 0.0), group, region, "%s:stem:%d" % (group, i))
                self.link(prev, nid)
                prev = nid
            base_a = a
            base_gap = STEP if spec["stem"] else CLUSTER_GAP + 20.0
            for side, key, nname in ((-1, "left", spec["notables"][0]), (1, "right", spec["notables"][1])):
                d = math.radians(spec.get("spread", FORK_SPREAD)) * side
                dirv = (math.cos(d), math.sin(d))
                bprev = prev
                kinds = spec[key]
                for j in range(len(kinds) + 1):
                    dist = base_gap + j * STEP
                    p = P(base_a + dirv[0] * dist, dirv[1] * dist)
                    if j < len(kinds):
                        nid = self.add_small(kinds[j], p, group, region, "%s:%s:%d" % (group, key, j))
                    else:
                        nid = self.add_notable(nname, p, group, region)
                    self.link(bprev, nid)
                    bprev = nid
        elif tpl == "spur":
            # A line of smalls ending in the notable; "bend" (degrees per step) curves it.
            prev = anchor
            kinds = spec["smalls"]
            heading = 0.0
            pa, pb = CLUSTER_GAP, 0.0
            for i in range(len(kinds) + 1):
                if i > 0:
                    heading += math.radians(spec.get("bend", 0.0))
                    pa += STEP * math.cos(heading)
                    pb += STEP * math.sin(heading)
                p = P(pa, pb)
                if i < len(kinds):
                    nid = self.add_small(kinds[i], p, group, region, "%s:spur:%d" % (group, i))
                else:
                    nid = self.add_notable(spec["notables"][0], p, group, region)
                self.link(prev, nid)
                prev = nid
        else:
            raise SystemExit("unknown template %s" % tpl)
        return far

    # -------------------------------------------------------------- whole tree
    def build(self):
        # Class starts first (ids 0..2), then the rings.
        for cls, region, title, _attr in CLASSES:
            p = pol(START_RADIUS, SECTOR_CENTRE[region])
            self.start_ids[cls] = self.add("start", title, p, [], "start_" + cls, region, "start:" + cls, cls)
        self.build_rings()
        # Start exits to the inner ring: straight out and +-40 degrees (2 travel nodes each).
        for cls, region, _title, _attr in CLASSES:
            s = self.start_ids[cls]
            c = SECTOR_CENTRE[region]
            self.path(s, self.ring_at(1, c - 40.0), 2, "at", "start_" + cls, region)
            self.path(s, self.ring_at(1, c), 2, "at", "start_" + cls, region)
            self.path(s, self.ring_at(1, c + 40.0), 2, "at", "start_" + cls, region)
        # Spokes: inner -> middle at the sector centres, middle -> outer at the boundaries.
        for region in SECTOR_ORDER:
            c = SECTOR_CENTRE[region]
            self.path(self.ring_at(1, c), self.ring_at(2, c), 2, "at", "spoke", region)
            self.path(self.ring_at(2, c + 30.0), self.ring_at(3, c + 30.0), 2, "ta", "spoke")
        # Clusters.
        nexus_far = []
        for region in SECTOR_ORDER:
            for spec in CLUSTERS[region]:
                far = self.build_cluster(region, spec)
                if spec.get("nexus"):
                    nexus_far.append((region, far))
        # Keystones on short spurs outside the outer ring.
        for name, region, ang, kinds in KEYSTONE_PLAN:
            anchor = self.ring_at(3, ang)
            group = slugify(name)
            prev = anchor
            r0 = RINGS[3][0]
            step = (KEYSTONE_RADIUS - r0) / (len(kinds) + 1)
            for i, kind in enumerate(kinds):
                nid = self.add_small(kind, pol(r0 + step * (i + 1), ang), group, region, "%s:spur:%d" % (group, i))
                self.link(prev, nid)
                prev = nid
            k = self.add("keystone", name, pol(KEYSTONE_RADIUS, ang), mods_of(KEYSTONES[name]), group, region,
                         "keystone:" + group)
            self.link(prev, k)
        # Centre nexus joining the three hybrid inner wheels.
        hub = self.add_notable("Convergence", (0.0, 0.0), "convergence", "centre")
        for region, far in nexus_far:
            fx, fy = self.pos(far)
            mid = self.add_small(self.travel_kind(region, True), (fx * 0.55, fy * 0.55), "convergence", region,
                                 "convergence:" + region)
            self.link(far, mid)
            self.link(mid, hub)
        for n in self.nodes:
            n["links"].sort()
        return self.nodes


# ------------------------------------------------------------------------------------------------
# Stable ids (tools/tree/id_map.json)
# ------------------------------------------------------------------------------------------------
ID_MAP_COMMENT = ("Stable passive tree node ids: semantic key -> id (see gen_passive_tree.py, 'Stable ids'). "
                  "Maintained by the generator: known keys keep their id, new keys are appended from next_id, "
                  "ids are never reused. Do not edit by hand.")


def empty_id_map():
    return {"next_id": 0, "ids": {}}


def load_id_map(path):
    """The id map at `path` ({"next_id": int, "ids": {key: id}}), or an empty map if the file does
    not exist. Aborts on a malformed map (duplicate ids, non-int ids, ...)."""
    if not os.path.exists(path):
        return empty_id_map()
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise SystemExit("id map %s is unreadable: %s" % (path, e))
    raw = data.get("ids") if isinstance(data, dict) else None
    if not isinstance(raw, dict):
        raise SystemExit("id map %s has no 'ids' object" % path)
    ids = {}
    owner = {}
    for key, v in raw.items():
        if not isinstance(v, int) or isinstance(v, bool) or v < 0:
            raise SystemExit("id map %s: bad id %r for key %s" % (path, v, key))
        if v in owner:
            raise SystemExit("id map %s: id %d used by both %s and %s" % (path, v, owner[v], key))
        owner[v] = key
        ids[key] = v
    next_id = data.get("next_id", 0)
    if not isinstance(next_id, int) or isinstance(next_id, bool):
        raise SystemExit("id map %s: bad next_id %r" % (path, next_id))
    next_id = max(next_id, max(ids.values()) + 1 if ids else 0)
    return {"next_id": next_id, "ids": ids}


def assign_ids(nodes, id_map):
    """Replace the build-order ids of `nodes` by stable ids from `id_map` (matched by "key").
    Keys missing from the map get new ids from next_id upwards, in build order. Returns
    (nodes sorted by id, updated map, appended keys, retired keys). Does not modify its inputs."""
    ids = dict(id_map["ids"])
    next_id = id_map["next_id"]
    appended = []
    remap = {}
    for n in nodes:
        key = n["key"]
        if key not in ids:
            ids[key] = next_id
            next_id += 1
            appended.append(key)
        remap[n["id"]] = ids[key]
    out = []
    for n in nodes:
        m = dict(n)
        m["id"] = remap[n["id"]]
        m["links"] = sorted(remap[l] for l in n["links"])
        out.append(m)
    out.sort(key=lambda n: n["id"])
    used = set(remap.values())
    retired = sorted((k for k, v in ids.items() if v not in used), key=lambda k: ids[k])
    return out, {"next_id": next_id, "ids": ids}, appended, retired


def id_map_to_json(id_map):
    items = sorted(id_map["ids"].items(), key=lambda kv: kv[1])
    lines = ["{", '"comment": %s,' % json.dumps(ID_MAP_COMMENT), '"next_id": %d,' % id_map["next_id"], '"ids": {']
    for i, (key, v) in enumerate(items):
        lines.append("  %s: %d%s" % (json.dumps(key), v, "," if i < len(items) - 1 else ""))
    lines.append("}}")
    return "\n".join(lines) + "\n"


def build_tree(id_map):
    """Build the whole tree with stable ids: (nodes sorted by id, updated map, appended, retired)."""
    return assign_ids(Builder().build(), id_map)


# ------------------------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------------------------
def load_stat_defs():
    with open(STAT_DEFS_PATH, encoding="utf-8") as f:
        text = f.read()
    start = text.find("const STATS := {")
    if start < 0:
        raise SystemExit("could not find StatDefs.STATS in %s" % STAT_DEFS_PATH)
    end = text.find("\n}\n", start)
    body = text[start:end]
    stats = {}
    for m in re.finditer(r'^\s*"([a-z0-9_]+)"\s*:\s*\{(.*)\}\s*,?\s*$', body, re.M):
        stats[m.group(1)] = {"local": '"local": true' in m.group(2), "flag": '"flag":' in m.group(2)}
    if len(stats) < 50:
        raise SystemExit("parsed only %d stats from stat_defs.gd" % len(stats))
    return stats


def seg_point_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _orient(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def segments_cross(a, b, c, d):
    d1 = _orient(c, d, a)
    d2 = _orient(c, d, b)
    d3 = _orient(a, b, c)
    d4 = _orient(a, b, d)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)) and d1 * d2 < 0 and d3 * d4 < 0


def polylines_cross(p, q):
    for i in range(len(p) - 1):
        for j in range(len(q) - 1):
            if segments_cross(p[i], p[i + 1], q[j], q[j + 1]):
                return True
    return False


ARC_SEGMENTS = 10


def arc_polyline(na, nb):
    """The minor arc between two nodes on the same orbit (as drawn with TreeDB.get_link_arc),
    sampled as a polyline; None if the link is straight."""
    oa, ob = na.get("orbit"), nb.get("orbit")
    if oa is None or oa != ob:
        return None
    cx, cy, r = oa
    ta = math.atan2(na["y"] - cy, na["x"] - cx)
    tb = math.atan2(nb["y"] - cy, nb["x"] - cx)
    sweep = math.atan2(math.sin(tb - ta), math.cos(tb - ta))
    pts = [(na["x"], na["y"])]
    for i in range(1, ARC_SEGMENTS):
        t = ta + sweep * i / ARC_SEGMENTS
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    pts.append((nb["x"], nb["y"]))
    return pts


# Stats that may appear as "flat" on the tree (§10 + stats that only exist as flat values).
FLAT_OK = {
    "strength", "dexterity", "intelligence", "all_attributes", "crit_multiplier",
    "fire_resistance", "cold_resistance", "lightning_resistance", "chaos_resistance", "elemental_resistance",
    "block_chance", "evade_chance", "physical_damage_reduction", "life_leech", "mana_leech",
    "life_regen_percent", "life_on_kill", "mana_on_kill", "life_on_hit",
    "ignite_chance", "freeze_chance", "shock_chance", "bleed_chance", "poison_chance",
    "pierce", "chain", "additional_projectiles",
}


def validate(nodes, stats):
    errors = []
    by_id = {n["id"]: n for n in nodes}
    types = Counter(n["type"] for n in nodes)
    # ---------------------------------------------------------------- counts
    if types["start"] != 3:
        errors.append("expected 3 start nodes, got %d" % types["start"])
    if types["keystone"] != 9:
        errors.append("expected 9 keystones, got %d" % types["keystone"])
    if not 50 <= types["notable"] <= 60:
        errors.append("expected ~55 notables, got %d" % types["notable"])
    if types["attribute"] < 60:
        errors.append("expected >= 60 attribute nodes, got %d" % types["attribute"])
    if not 290 <= types["small"] + types["attribute"] <= 350:
        errors.append("expected ~300 small/attribute nodes, got %d" % (types["small"] + types["attribute"]))
    if not 380 <= len(nodes) <= 430:
        errors.append("expected ~400 nodes, got %d" % len(nodes))
    # ---------------------------------------------------------------- per node
    names_seen = Counter()
    for n in nodes:
        t = n["type"]
        if t == "start":
            if n["mods"]:
                errors.append("start node %d has mods" % n["id"])
            if n.get("class") not in ("warrior", "ranger", "sorcerer"):
                errors.append("start node %d has no valid class" % n["id"])
        else:
            if "class" in n:
                errors.append("non-start node %d has a class" % n["id"])
            if not n["mods"]:
                errors.append("node %d (%s) has no mods" % (n["id"], n["name"]))
        if t in ("notable", "keystone"):
            names_seen[n["name"]] += 1
        if t == "notable" and not 2 <= len(n["mods"]) <= 3:
            errors.append("notable %s should have 2-3 mods" % n["name"])
        if t == "attribute":
            m = n["mods"]
            if len(m) != 1 or m[0]["op"] != "flat" or m[0]["value"] != 10 or m[0]["stat"] not in ("strength", "dexterity", "intelligence"):
                errors.append("attribute node %d must be exactly +10 to one attribute" % n["id"])
        for m in n["mods"]:
            st, op = m.get("stat"), m.get("op")
            if st not in stats:
                errors.append("node %d (%s): unknown stat '%s'" % (n["id"], n["name"], st))
                continue
            if stats[st]["local"]:
                errors.append("node %d (%s): local stat '%s' not allowed on the tree" % (n["id"], n["name"], st))
            if op not in ("flat", "inc", "more", "flag"):
                errors.append("node %d: bad op %s" % (n["id"], op))
            if not isinstance(m.get("value"), (int, float)):
                errors.append("node %d: non-numeric value" % n["id"])
            if op == "flat" and st not in FLAT_OK:
                errors.append("node %d (%s): flat %s not allowed on the tree" % (n["id"], n["name"], st))
            if op == "more" and t != "keystone":
                errors.append("node %d (%s): 'more' mods are keystone-only" % (n["id"], n["name"]))
            if op == "flag" and t != "keystone":
                errors.append("node %d (%s): flags are keystone-only" % (n["id"], n["name"]))
        for l in n["links"]:
            if l not in by_id:
                errors.append("node %d links to unknown %d" % (n["id"], l))
            elif n["id"] not in by_id[l]["links"]:
                errors.append("link %d-%d not symmetric" % (n["id"], l))
            if l == n["id"]:
                errors.append("node %d links to itself" % l)
        if len(set(n["links"])) != len(n["links"]):
            errors.append("node %d has duplicate links" % n["id"])
        if not n["links"]:
            errors.append("node %d is isolated" % n["id"])
    for name, c in names_seen.items():
        if c > 1:
            errors.append("duplicate notable/keystone name %s" % name)
    for name in KEYSTONES:
        if names_seen[name] != 1:
            errors.append("keystone %s missing" % name)
    # ---------------------------------------------------------------- ids, keys, clusters
    for nid, c in Counter(n["id"] for n in nodes).items():
        if c > 1 or not isinstance(nid, int) or nid < 0:
            errors.append("id %r used %d times" % (nid, c))
    for key, c in Counter(n.get("key") for n in nodes).items():
        if not key:
            errors.append("%d nodes without a key" % c)
        elif c > 1:
            errors.append("key %s used %d times" % (key, c))
    groups = {}
    for n in nodes:
        groups.setdefault(n["group"], []).append(n)
    for g, members in groups.items():
        if g == "convergence" or not any(m["type"] == "notable" for m in members):
            continue
        smalls = sum(1 for m in members if m["type"] in ("small", "attribute"))
        if smalls < MIN_CLUSTER_SMALLS:
            errors.append("cluster %s has only %d small nodes (>= %d)" % (g, smalls, MIN_CLUSTER_SMALLS))
    # ---------------------------------------------------------------- geometry
    pts = {n["id"]: (n["x"], n["y"]) for n in nodes}
    ids = [n["id"] for n in nodes]
    min_d = 1e9
    for i in range(len(ids)):
        pi = pts[ids[i]]
        for j in range(i + 1, len(ids)):
            pj = pts[ids[j]]
            d = math.hypot(pi[0] - pj[0], pi[1] - pj[1])
            min_d = min(min_d, d)
            if d < MIN_SPACING:
                errors.append("nodes %d (%s) and %d (%s) only %.1f apart" % (
                    ids[i], by_id[ids[i]]["name"], ids[j], by_id[ids[j]]["name"], d))
    links = sorted({(min(n["id"], l), max(n["id"], l)) for n in nodes for l in n["links"]})
    # Two render modes are validated: every link straight, and orbit links drawn as arcs
    # (TreeDB.get_link_arc). In both, links must not pass through nodes or cross each other.
    crossings = 0
    arcs = 0
    for mode in ("straight", "arc"):
        shapes = {}
        for (a, b) in links:
            poly = arc_polyline(by_id[a], by_id[b]) if mode == "arc" else None
            if poly is None:
                poly = [pts[a], pts[b]]
            elif mode == "arc":
                arcs += 1
            xs = [q[0] for q in poly]
            ys = [q[1] for q in poly]
            shapes[(a, b)] = (poly, (min(xs), min(ys), max(xs), max(ys)))
        for (a, b), (poly, bb) in shapes.items():
            for c in ids:
                if c == a or c == b:
                    continue
                pc = pts[c]
                clear = DRAW_RADIUS[by_id[c]["type"]] + LINK_MARGIN
                if pc[0] < bb[0] - clear or pc[0] > bb[2] + clear or pc[1] < bb[1] - clear or pc[1] > bb[3] + clear:
                    continue
                if min(seg_point_dist(pc, poly[i], poly[i + 1]) for i in range(len(poly) - 1)) < clear:
                    errors.append("%s link %d-%d passes through node %d (%s)" % (mode, a, b, c, by_id[c]["name"]))
        keys = list(shapes.keys())
        for i in range(len(keys)):
            a, b = keys[i]
            pa_, bba = shapes[keys[i]]
            for j in range(i + 1, len(keys)):
                c, d = keys[j]
                if len({a, b, c, d}) < 4:
                    continue
                pb_, bbb = shapes[keys[j]]
                if bba[2] < bbb[0] or bbb[2] < bba[0] or bba[3] < bbb[1] or bbb[3] < bba[1]:
                    continue
                if polylines_cross(pa_, pb_):
                    crossings += 1
                    errors.append("%s links %d-%d and %d-%d cross" % (mode, a, b, c, d))
    for n in nodes:
        r = math.hypot(n["x"], n["y"])
        if n["type"] == "keystone" and r < RINGS[3][0] + 150:
            errors.append("keystone %s is not outside the outer ring" % n["name"])
        if r > 2300:
            errors.append("node %d outside radius 2300" % n["id"])
    # ---------------------------------------------------------------- graph
    starts = {n["class"]: n["id"] for n in nodes if n["type"] == "start"}
    main_attr = {c: a for (c, _r, _t, a) in CLASSES}
    for cls, sid in starts.items():
        order = bfs_order(by_id, sid)
        reached = set(order)
        missing = [i for i in ids if i not in reached and by_id[i]["type"] != "start"]
        if missing:
            errors.append("%s start cannot reach %d nodes (e.g. %s)" % (cls, len(missing), missing[:5]))
        first = order[1:13]
        count = sum(1 for i in first if any(m["stat"] == main_attr[cls] for m in by_id[i]["mods"]))
        if count < 3:
            errors.append("%s: only %d main-attribute nodes among the first 12" % (cls, count))
    return errors, {"min_spacing": min_d, "links": len(links), "crossings": crossings, "arcs": arcs}


def bfs_order(by_id, start):
    """BFS from a start, never passing through other class starts (they are not allocatable)."""
    seen = {start}
    order = [start]
    q = deque([start])
    while q:
        cur = q.popleft()
        for nb in sorted(by_id[cur]["links"]):
            if nb in seen or by_id[nb]["type"] == "start":
                continue
            seen.add(nb)
            order.append(nb)
            q.append(nb)
    return order


def bfs_dist(by_id, start):
    dist = {start: 0}
    q = deque([start])
    while q:
        cur = q.popleft()
        for nb in by_id[cur]["links"]:
            if nb in dist or by_id[nb]["type"] == "start":
                continue
            dist[nb] = dist[cur] + 1
            q.append(nb)
    return dist


def summary(nodes, info):
    by_id = {n["id"]: n for n in nodes}
    out = []
    types = Counter(n["type"] for n in nodes)
    out.append("nodes: %d  links: %d (%d orbit arcs)  min spacing: %.1f  crossings: %d" % (
        len(nodes), info["links"], info["arcs"], info["min_spacing"], info["crossings"]))
    out.append("by type: " + ", ".join("%s %d" % (t, types[t]) for t in ("start", "attribute", "small", "notable", "keystone")))
    regions = Counter(n["region"] for n in nodes)
    out.append("by region: " + ", ".join("%s %d" % (r, regions[r]) for r in SECTOR_ORDER + ["centre"]))
    for key in SECTOR_ORDER:
        nts = [n["name"] for n in nodes if n["region"] == key and n["type"] in ("notable", "keystone")]
        out.append("  %-8s %s" % (key, ", ".join(nts)))
    stat_nodes = Counter()
    for n in nodes:
        for s in {m["stat"] for m in n["mods"]}:
            stat_nodes[s] += 1
    out.append("stats used: %d; top: %s" % (len(stat_nodes), ", ".join("%s %d" % kv for kv in stat_nodes.most_common(16))))
    radius = max(math.hypot(n["x"], n["y"]) for n in nodes)
    out.append("radius: %.0f" % radius)
    for n in nodes:
        if n["type"] != "start":
            continue
        dist = bfs_dist(by_id, n["id"])
        ks = sorted((dist[k["id"]], k["name"]) for k in nodes if k["type"] == "keystone")
        nt = sorted(dist[k["id"]] for k in nodes if k["type"] == "notable")
        out.append("%s: nearest notables %s; keystones %s" % (
            n["class"], nt[:5], ", ".join("%s %d" % (name, d) for d, name in ks)))
    return "\n".join(out)


def to_json(nodes):
    lines = ['{"version": 1, "nodes": [']
    keys = ["id", "name", "type", "x", "y", "mods", "links", "class", "group", "region", "orbit", "key"]
    for i, n in enumerate(nodes):
        ordered = {k: n[k] for k in keys if k in n}
        lines.append(json.dumps(ordered, ensure_ascii=False) + ("," if i < len(nodes) - 1 else ""))
    lines.append("]}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=OUT_PATH)
    ap.add_argument("--id-map", default=ID_MAP_PATH, help="stable id map to reuse and update")
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    stats = load_stat_defs()
    id_map_path = os.path.abspath(args.id_map)
    old_map = load_id_map(id_map_path)
    nodes, new_map, appended, retired = build_tree(old_map)
    errors, info = validate(nodes, stats)
    if not args.quiet or errors:
        print(summary(nodes, info))
    if not args.quiet or appended or retired:
        if not old_map["ids"]:
            print("id map: %s not found -> ids assigned in build order" % id_map_path)
        print("id map: %d keys, next id %d; %d new id(s) appended%s; %d retired%s" % (
            len(new_map["ids"]), new_map["next_id"], len(appended),
            (" (%s)" % ", ".join("%s=%d" % (k, new_map["ids"][k]) for k in appended[:12])) if appended else "",
            len(retired), (" (%s)" % ", ".join(retired[:12])) if retired else ""))
    if errors:
        print("\n%d VALIDATION ERRORS:" % len(errors), file=sys.stderr)
        for e in errors[:60]:
            print("  " + e, file=sys.stderr)
        if len(errors) > 60:
            print("  ... %d more" % (len(errors) - 60), file=sys.stderr)
        return 1
    if args.check:
        print("OK (not written)")
        return 0
    # The map first: if writing the tree fails afterwards, the new ids are still reserved.
    if new_map != old_map or not os.path.exists(id_map_path):
        write_atomic(id_map_path, id_map_to_json(new_map))
        print("wrote %s" % id_map_path)
    out = os.path.abspath(args.out)
    write_atomic(out, to_json(nodes))
    print("wrote %s" % out)
    return 0


def write_atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


if __name__ == "__main__":
    sys.exit(main())

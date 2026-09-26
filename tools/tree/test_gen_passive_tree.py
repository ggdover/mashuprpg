#!/usr/bin/env python3
"""Unit tests for tools/tree/gen_passive_tree.py (python3 stdlib only):
stable ids through tools/tree/id_map.json, regeneration being a no-op, validation rules.

  python3 tools/tree/test_gen_passive_tree.py        # or: python3 -m unittest -v (in tools/tree)
"""
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # no __pycache__ inside the Godot project
sys.path.insert(0, HERE)
import gen_passive_tree as g  # noqa: E402

# The wave-1 plan of the three spur clusters (3 smalls each); the 4th small was appended later.
WAVE1_SPURS = {
    "Toxic Bloom": ["poison", "duration", "chaos"],
    "Vampiric Frenzy": ["leech", "attack_speed", "life_on_kill"],
    "Crimson Covenant": ["life", "life_regen", "life"],
}
WAVE1_NODE_COUNT = 403


def plan_with(mutator):
    """A deep copy of CLUSTERS changed by mutator(clusters)."""
    clusters = copy.deepcopy(g.CLUSTERS)
    mutator(clusters)
    return clusters


def find_spec(clusters, notable):
    for specs in clusters.values():
        for spec in specs:
            if spec["notables"][0] == notable:
                return spec
    raise KeyError(notable)


def wave1_plan(clusters):
    for name, smalls in WAVE1_SPURS.items():
        find_spec(clusters, name)["smalls"] = list(smalls)


class StableIdTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.map = g.load_id_map(g.ID_MAP_PATH)
        cls.nodes, cls.new_map, cls.appended, cls.retired = g.build_tree(cls.map)

    def test_regeneration_is_a_no_op(self):
        self.assertEqual(self.appended, [], "a plain regeneration appends no ids")
        self.assertEqual(self.retired, [], "and retires none")
        self.assertEqual(self.new_map, self.map, "map unchanged")
        with open(g.OUT_PATH, encoding="utf-8") as f:
            self.assertEqual(g.to_json(self.nodes), f.read(), "data/passive_tree.json is up to date")
        with open(g.ID_MAP_PATH, encoding="utf-8") as f:
            self.assertEqual(g.id_map_to_json(self.new_map), f.read(), "id_map.json is up to date")

    def test_tree_validates(self):
        errors, info = g.validate(self.nodes, g.load_stat_defs())
        self.assertEqual(errors, [])
        self.assertEqual(info["crossings"], 0)

    def test_map_matches_nodes(self):
        self.assertEqual(len(self.map["ids"]), len(self.nodes), "no retired keys yet")
        for n in self.nodes:
            self.assertEqual(self.map["ids"][n["key"]], n["id"], n["key"])
        self.assertEqual(self.map["next_id"], max(n["id"] for n in self.nodes) + 1)
        self.assertEqual(len(set(self.map["ids"].values())), len(self.map["ids"]), "ids unique")

    def test_wave1_ids_unchanged(self):
        # Rebuild the wave-1 plan without a map: ids in build order = the original numbering.
        with mock.patch.object(g, "CLUSTERS", plan_with(wave1_plan)):
            old_nodes, _m, appended, _r = g.build_tree(g.empty_id_map())
        self.assertEqual(len(old_nodes), WAVE1_NODE_COUNT)
        self.assertEqual(len(appended), WAVE1_NODE_COUNT)
        self.assertEqual([n["id"] for n in old_nodes], list(range(WAVE1_NODE_COUNT)))
        by_key = {n["key"]: n for n in self.nodes}
        for o in old_nodes:
            self.assertEqual(self.map["ids"][o["key"]], o["id"], "wave-1 id of %s kept" % o["key"])
            n = by_key[o["key"]]
            self.assertEqual((n["name"], n["type"], n["mods"]), (o["name"], o["type"], o["mods"]), o["key"])
        # The 4th spur smalls were appended after the wave-1 ids.
        new_keys = sorted((k for k in self.map["ids"] if k not in {o["key"] for o in old_nodes}),
                          key=lambda k: self.map["ids"][k])
        self.assertEqual(new_keys, ["toxic_bloom:spur:3", "vampiric_frenzy:spur:3", "crimson_covenant:spur:3"])
        self.assertEqual([self.map["ids"][k] for k in new_keys], [403, 404, 405])

    def test_growing_the_plan_appends_ids(self):
        def grow(clusters):
            find_spec(clusters, "Toxic Bloom")["smalls"].append("poison")
            find_spec(clusters, "Blade Dancer")["left"].append("sword")
        with mock.patch.object(g, "CLUSTERS", plan_with(grow)):
            nodes, new_map, appended, retired = g.build_tree(self.map)
        self.assertEqual(appended, ["toxic_bloom:spur:4", "blade_dancer:left:2"], "new slots, in build order")
        self.assertEqual(retired, [])
        self.assertEqual([new_map["ids"][k] for k in appended], [406, 407])
        self.assertEqual(new_map["next_id"], 408)
        for key, nid in self.map["ids"].items():
            self.assertEqual(new_map["ids"][key], nid, "existing id of %s kept" % key)
        ids = [n["id"] for n in nodes]
        self.assertEqual(len(ids), len(set(ids)))
        by_id = {n["id"]: n for n in nodes}
        self.assertEqual(by_id[406]["name"], "Poison")
        self.assertEqual(by_id[self.map["ids"]["notable:toxic_bloom"]]["links"], [406], "notable now after spur:4")

    def test_retired_ids_are_never_reused(self):
        plan = [k for k in g.KEYSTONE_PLAN if k[0] != "Blood Magic"]
        with mock.patch.object(g, "KEYSTONE_PLAN", plan):
            nodes, map2, appended, retired = g.build_tree(self.map)
        self.assertEqual(retired, ["blood_magic:spur:0", "blood_magic:spur:1", "keystone:blood_magic"])
        self.assertEqual(appended, [])
        used = {n["id"] for n in nodes}
        for key in retired:
            self.assertIn(key, map2["ids"], "retired keys stay in the map")
            self.assertNotIn(map2["ids"][key], used)
        # A later addition gets a fresh id, not a retired one.
        with mock.patch.object(g, "KEYSTONE_PLAN", plan), \
                mock.patch.object(g, "CLUSTERS", plan_with(lambda c: find_spec(c, "Toxic Bloom")["smalls"].append("dot"))):
            _nodes, map3, appended, _r = g.build_tree(map2)
        self.assertEqual(appended, ["toxic_bloom:spur:4"])
        self.assertEqual(map3["ids"]["toxic_bloom:spur:4"], self.map["next_id"])
        # Bringing the keystone back restores its old id.
        _nodes, map4, appended, retired = g.build_tree(map3)
        self.assertEqual(appended, [])
        self.assertEqual(map4["ids"]["keystone:blood_magic"], self.map["ids"]["keystone:blood_magic"])
        self.assertEqual(retired, ["toxic_bloom:spur:4"])

    def test_empty_map_uses_build_order(self):
        raw = g.Builder().build()
        nodes, new_map, appended, retired = g.build_tree(g.empty_id_map())
        self.assertEqual([n["key"] for n in raw], appended)
        self.assertEqual([n["id"] for n in nodes], list(range(len(raw))))
        self.assertEqual(new_map["next_id"], len(raw))
        self.assertEqual(retired, [])

    def test_keys_are_semantic_and_unique(self):
        keys = [n["key"] for n in self.nodes]
        self.assertEqual(len(keys), len(set(keys)))
        by_key = {n["key"]: n for n in self.nodes}
        self.assertEqual(by_key["start:warrior"]["type"], "start")
        self.assertEqual(by_key["start:warrior"]["class"], "warrior")
        self.assertEqual(by_key["keystone:resolute_technique"]["name"], "Resolute Technique")
        self.assertEqual(by_key["notable:toxic_bloom"]["name"], "Toxic Bloom")
        self.assertEqual(by_key["ring_outer:0"]["group"], "ring_outer")
        for n in self.nodes:
            if n["type"] == "notable":
                self.assertEqual(n["key"], "notable:" + g.slugify(n["name"]))
            if n["type"] == "keystone":
                self.assertEqual(n["key"], "keystone:" + g.slugify(n["name"]))

    def test_spur_clusters_have_four_smalls(self):
        for name in WAVE1_SPURS:
            group = g.slugify(name)
            members = [n for n in self.nodes if n["group"] == group]
            smalls = sorted(n["key"] for n in members if n["type"] in ("small", "attribute"))
            self.assertEqual(smalls, ["%s:spur:%d" % (group, i) for i in range(4)], name)
            notable = [n for n in members if n["type"] == "notable"]
            self.assertEqual(len(notable), 1)
            by_key = {n["key"]: n for n in members}
            self.assertEqual(notable[0]["links"], [by_key[group + ":spur:3"]["id"]], "notable ends the spur")

    def test_validator_requires_four_smalls_per_cluster(self):
        with mock.patch.object(g, "CLUSTERS", plan_with(wave1_plan)):
            nodes, _m, _a, _r = g.build_tree(g.empty_id_map())
        errors, _info = g.validate(nodes, g.load_stat_defs())
        self.assertEqual(sorted(errors), sorted("cluster %s has only 3 small nodes (>= 4)" % g.slugify(n) for n in WAVE1_SPURS))

    def test_load_id_map_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "map.json")
            self.assertEqual(g.load_id_map(path), g.empty_id_map(), "missing file -> empty map")
            with open(path, "w") as f:
                json.dump({"next_id": 1, "ids": {"a": 0, "b": 5}}, f)
            self.assertEqual(g.load_id_map(path)["next_id"], 6, "next_id never below max + 1")
            for bad in ({"ids": {"a": 1, "b": 1}}, {"ids": {"a": "1"}}, {"ids": {"a": -1}}, {"ids": []}, [1, 2]):
                with open(path, "w") as f:
                    json.dump(bad, f)
                with self.assertRaises(SystemExit, msg=str(bad)):
                    g.load_id_map(path)
            with open(path, "w") as f:
                f.write("{not json")
            with self.assertRaises(SystemExit):
                g.load_id_map(path)

    def test_command_line(self):
        script = os.path.join(HERE, "gen_passive_tree.py")
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "tree.json")
            idmap = os.path.join(tmp, "map.json")
            r = subprocess.run([sys.executable, script, "--check", "--quiet", "--out", out, "--id-map", idmap],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(os.path.exists(out) or os.path.exists(idmap), "--check writes nothing")
            # Without a map, one is created with the build-order numbering.
            fresh_map = os.path.join(tmp, "fresh_map.json")
            r = subprocess.run([sys.executable, script, "--quiet", "--out", out, "--id-map", fresh_map],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            fresh = g.load_id_map(fresh_map)
            self.assertEqual(sorted(fresh["ids"].values()), list(range(len(self.nodes))))
            self.assertEqual(fresh["ids"]["start:warrior"], 0)
            # With (a copy of) the real map: exactly the checked-in files.
            with open(g.ID_MAP_PATH) as f:
                real_map = f.read()
            with open(idmap, "w") as f:
                f.write(real_map)
            r = subprocess.run([sys.executable, script, "--quiet", "--out", out, "--id-map", idmap],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(out) as a, open(g.OUT_PATH) as b:
                self.assertEqual(a.read(), b.read())
            with open(idmap) as f:
                self.assertEqual(f.read(), real_map, "map untouched when nothing changed")
            self.assertFalse(any(name.endswith(".tmp") for name in os.listdir(tmp)), "atomic writes")


if __name__ == "__main__":
    unittest.main(verbosity=2)

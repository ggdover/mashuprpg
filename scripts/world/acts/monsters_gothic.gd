extends RefCounted
## Act III monster variants for the gothic town's outer zones. EnemyDB reads MONSTERS: each entry
## is a base archetype's definition with these overrides (act monsters: they only spawn in acts,
## through the zones' pools in act_gothic.gd). OWNER: acts-gothic.

const MONSTERS := {
	# The Canal Quarter.
	"canal_drowned": {"base": "zombie", "name": "Drowned Dockhand", "tint": Color(0.5, 0.7, 0.68), "min_depth": 1,
		"companions": ["maddened_townsman"], "description": "Pulled from the canal, still dripping, still hungry."},
	# Ashgrove Cemetery.
	"crypt_ghoul": {"base": "ghoul", "name": "Crypt Ghoul", "tint": Color(0.86, 0.88, 0.95), "scale": 0.95, "min_depth": 1,
		"companions": ["shroud_widow"], "description": "Pale and quick; it lives on what the graves give up."},
	"shroud_widow": {"base": "frost_cultist", "name": "Shroud Widow", "tint": Color(0.3, 0.3, 0.36),
		"attach_tint": Color(0.75, 0.8, 0.9), "min_depth": 1, "companions": ["crypt_ghoul"],
		"description": "She weeps frost over every open grave."},
	# Blackmoor Bridge.
	"bridge_sentinel": {"base": "skeleton_warrior", "name": "Blackmoor Sentinel", "tint": Color(0.56, 0.6, 0.7),
		"attach_tint": Color(0.5, 0.52, 0.6), "min_depth": 1, "companions": ["belfry_archer"],
		"description": "Still keeps the bridge, long after the war was lost."},
	# The Abbey Grounds.
	"abbey_flagellant": {"base": "cultist", "name": "Abbey Flagellant", "tint": Color(0.74, 0.24, 0.24),
		"attach_tint": Color(0.85, 0.3, 0.25), "min_depth": 1, "companions": ["church_servant", "blood_acolyte"],
		"description": "Penance in blood, preferably yours."},
}

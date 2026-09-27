extends RefCounted
## Act II (desert) monster variants for its outdoor zones: themed looks and names over the base
## archetypes (EnemyDB merges `MONSTERS` at startup; ids spawn only through the zones' pools set in
## act_desert.gd, never in the Emberfall depths). OWNER: acts-desert.
##
##   Banks of the Iteru  reed_stalker, drowned_boatman (+ the act's jackals, linen dead, archers)
##   The Oasis           caravan_raider, mirage_witch
##   Snake Isles         naga_priest, serpent_guard, reed_stalker, drowned_boatman
##   Anubis Graveyard    embalmer, jackal_archer (+ tomb guardians, linen dead, jackals)
##   Anubis Courtyard    anubite_warden, jackal_priest, jackal_archer (+ colossi, sun priests)

const MONSTERS := {
	"reed_stalker": {"base": "ghoul", "name": "Reed Stalker", "tint": Color(0.74, 0.92, 0.52), "min_depth": 1,
		"companions": ["drowned_boatman"], "description": "Waits in the papyrus for whoever comes down to drink."},
	"drowned_boatman": {"base": "zombie", "name": "Drowned Boatman", "tint": Color(0.78, 1.06, 1.14), "min_depth": 1,
		"companions": ["reed_stalker", "dune_archer"], "description": "The river gave him back, but not all of him."},
	"caravan_raider": {"base": "cultist", "name": "Caravan Raider", "tint": Color(1.25, 0.74, 0.5),
		"attach_tint": Color(0.9, 0.72, 0.42), "min_depth": 1, "companions": ["dune_archer", "mirage_witch"],
		"description": "Burns what he cannot carry off."},
	"mirage_witch": {"base": "frost_cultist", "name": "Mirage Witch", "tint": Color(0.72, 1.08, 1.3), "min_depth": 1,
		"companions": ["caravan_raider"], "description": "Her cold is the only cool thing in the desert."},
	"naga_priest": {"base": "cultist", "name": "Naga Priest", "tint": Color(0.56, 1.06, 0.64),
		"attach_tint": Color(0.5, 0.9, 0.62), "min_depth": 1, "companions": ["serpent_guard", "reed_stalker"],
		"description": "Speaks for the serpent gods of the isles, and burns for them."},
	"serpent_guard": {"base": "skeleton_warrior", "name": "Serpent Guard", "tint": Color(0.72, 1.04, 0.72),
		"attach_tint": Color(0.55, 0.85, 0.7), "min_depth": 1, "companions": ["naga_priest"],
		"description": "Bones of the old temple guard, green with marsh slime."},
	"embalmer": {"base": "cultist", "name": "Embalmer", "tint": Color(1.32, 1.16, 0.86),
		"attach_tint": Color(0.95, 0.78, 0.45), "min_depth": 1, "companions": ["linen_dead", "tomb_guardian"],
		"description": "Still at work in the necropolis, and short of bodies."},
	"jackal_archer": {"base": "skeleton_archer", "name": "Jackal Archer", "tint": Color(0.56, 0.52, 0.5), "min_depth": 1,
		"companions": ["anubite_warden", "tomb_guardian"], "description": "Blackened bones that shoot for the jackal god."},
	"anubite_warden": {"base": "skeleton_warrior", "name": "Anubite Warden", "tint": Color(0.46, 0.43, 0.41),
		"attach_tint": Color(1.0, 0.8, 0.36), "min_depth": 1, "companions": ["jackal_archer", "jackal_priest"],
		"description": "Sworn to the Anubis temple; its blade is gilded."},
	"jackal_priest": {"base": "cultist", "name": "Jackal Priest", "tint": Color(0.5, 0.46, 0.44),
		"attach_tint": Color(1.0, 0.8, 0.36), "min_depth": 1, "companions": ["anubite_warden"],
		"description": "Chants in the jackal god's court and hurls his fire."},
}

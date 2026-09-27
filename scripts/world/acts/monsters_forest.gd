extends RefCounted
## Act I (forest) zone monsters: variants spawned through the wilds' zone pools
## (act_forest.gd set_region_pool), next to the act's own draugr, barrow archers, grey dwarves,
## forest trolls and rime witches (EnemyDefs.ACT_MONSTERS). EnemyDB merges each entry over its
## "base" def at startup. OWNER: acts-forest.

const MONSTERS := {
	# The Mattis Woods and the Hollows: lumpy little trolls of the undergrowth.
	"rumphob": {"base": "zombie", "name": "Rumphob", "tint": Color(0.86, 0.7, 0.5), "scale": 0.74,
		"move_speed": 2.9, "life_mult": 1.35, "min_depth": 1, "companions": ["grey_dwarf", "draugr"],
		"description": "Lumpy, curious and stronger than it looks. 'Why is it so?'"},
	# Stillwater Tarn: the drowned.
	"bog_dead": {"base": "zombie", "name": "Bog Dead", "tint": Color(0.5, 0.62, 0.46), "min_depth": 1,
		"companions": ["rime_witch", "draugr"], "description": "Pulled from the black water of the tarn, weeds and all."},
	# Hell's Gap and the tarn: the wild harpies of the storm.
	"wild_harpy": {"base": "ghoul", "name": "Wild Harpy", "tint": Color(0.72, 0.76, 0.9), "scale": 0.96,
		"aggro_radius": 14.0, "min_depth": 1, "companions": ["forest_troll", "barrow_archer"],
		"description": "Grey-feathered hag of the storm; she swoops down from the treetops, shrieking."},
	# The Hollows: an old grey dwarf with a burning stick.
	"grey_dwarf_elder": {"base": "cultist", "name": "Grey Dwarf Elder", "tint": Color(0.8, 0.84, 0.7), "scale": 0.8,
		"min_depth": 1, "companions": ["grey_dwarf", "rumphob"],
		"description": "Hurls burning pitch from the back of the swarm."},
	# The Barrow Downs: the barrow folk.
	"barrow_guard": {"base": "skeleton_warrior", "name": "Barrow Guard", "tint": Color(0.86, 0.82, 0.64),
		"attach_tint": Color(0.72, 0.56, 0.32), "min_depth": 1, "companions": ["barrow_archer", "cairn_seer"],
		"description": "Old bones in green bronze, still keeping watch over the mounds."},
	"cairn_seer": {"base": "necromancer", "name": "Cairn Seer", "tint": Color(0.56, 0.72, 0.64),
		"attach_tint": Color(0.6, 0.66, 0.56), "min_depth": 1, "companions": ["barrow_guard", "draugr"],
		"description": "A dead völva who calls the barrow folk up from their graves."},
}

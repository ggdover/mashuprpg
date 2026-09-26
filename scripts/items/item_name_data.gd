extends RefCounted
## Word pools for generated rare item names ("Doom Grasp", "Viper Edge"): a first word from
## FIRST plus a second word chosen by base category / slot. OWNER: items (preload, no class_name).

const FIRST: Array[String] = [
	"Agony", "Apocalypse", "Armageddon", "Ashen", "Beast", "Behemoth", "Blight", "Blood", "Bramble",
	"Brimstone", "Brood", "Carrion", "Cataclysm", "Chimeric", "Corpse", "Corruption", "Damnation",
	"Death", "Demon", "Dire", "Doom", "Dragon", "Dread", "Dusk", "Eagle", "Ember", "Empyrean", "Fate",
	"Foe", "Gale", "Ghoul", "Gloom", "Glyph", "Golem", "Grave", "Grim", "Hate", "Havoc", "Honour",
	"Horror", "Hypnotic", "Kraken", "Loath", "Maelstrom", "Mind", "Miracle", "Morbid", "Night",
	"Oblivion", "Onslaught", "Pain", "Pandemonium", "Phoenix", "Plague", "Rage", "Rapture", "Raven",
	"Rune", "Skull", "Sol", "Sorrow", "Soul", "Spirit", "Storm", "Tempest", "Thunder", "Torment",
	"Vengeance", "Victory", "Viper", "Vortex", "Wolf", "Woe", "Wraith", "Wrath",
]

## Second words by category (falls back to the slot type).
const SECOND := {
	"sword": ["Bane", "Beak", "Bite", "Edge", "Fang", "Gutter", "Hunger", "Impaler", "Needle", "Razor", "Saw", "Scalpel", "Slicer", "Song", "Spike", "Stinger", "Thirst"],
	"axe": ["Bane", "Beak", "Bite", "Butcher", "Edge", "Etcher", "Gnash", "Hunger", "Mangler", "Rend", "Roar", "Sever", "Slayer", "Song", "Splitter", "Sunder", "Thirst"],
	"mace": ["Bane", "Batter", "Blast", "Blow", "Brand", "Breaker", "Burst", "Crack", "Crusher", "Grinder", "Knell", "Mangler", "Ram", "Roar", "Ruin", "Shatter", "Smasher", "Star", "Thresher", "Wreck"],
	"dagger": ["Bane", "Barb", "Bite", "Edge", "Etcher", "Fang", "Gutter", "Hunger", "Needle", "Razor", "Scalpel", "Sever", "Skewer", "Slicer", "Song", "Spike", "Stinger", "Thirst"],
	"wand": ["Bane", "Barb", "Bite", "Branch", "Call", "Chant", "Charm", "Cry", "Gnarl", "Goad", "Needle", "Spell", "Spike", "Song", "Thirst", "Weaver"],
	"staff": ["Bane", "Beam", "Branch", "Call", "Chant", "Cry", "Gnarl", "Goad", "Mast", "Pillar", "Pole", "Post", "Roots", "Song", "Spell", "Spire", "Weaver"],
	"bow": ["Arch", "Bane", "Barrage", "Blast", "Branch", "Breeze", "Fletch", "Guide", "Horn", "Mark", "Nock", "Rain", "Reach", "Siege", "Song", "Stinger", "Strike", "Thunder", "Twine", "Volley", "Wind", "Wing"],
	"crossbow": ["Arbiter", "Bane", "Barrage", "Bolt", "Mark", "Quarrel", "Reach", "Siege", "Stinger", "Strike", "Thunder", "Trigger", "Volley", "Verdict", "Windlass"],
	"shield": ["Aegis", "Badge", "Barrier", "Bastion", "Bulwark", "Duty", "Emblem", "Fend", "Guard", "Mark", "Refuge", "Rock", "Rook", "Sanctuary", "Span", "Tower", "Watch", "Wing"],
	"focus": ["Eye", "Gaze", "Heart", "Lens", "Mind", "Omen", "Orb", "Prism", "Sphere", "Star", "Vision"],
	"quiver": ["Arrow", "Barb", "Bite", "Bolt", "Brand", "Dart", "Flight", "Hail", "Impaler", "Nails", "Needle", "Quill", "Rod", "Shot", "Skewer", "Spear", "Spike", "Spire", "Stinger"],
	"helmet": ["Brow", "Corona", "Cowl", "Crest", "Crown", "Dome", "Glance", "Guardian", "Halo", "Horn", "Keep", "Peak", "Salvation", "Shelter", "Star", "Veil", "Visage", "Visor", "Ward"],
	"body": ["Carapace", "Cloak", "Coat", "Curtain", "Guardian", "Hide", "Jack", "Keep", "Mantle", "Pelt", "Salvation", "Sanctuary", "Shell", "Shelter", "Shroud", "Skin", "Suit", "Veil", "Ward", "Wrap"],
	"gloves": ["Caress", "Claw", "Clutches", "Fingers", "Fist", "Grasp", "Grip", "Hand", "Hold", "Knuckle", "Mitts", "Nails", "Palm", "Paw", "Talons", "Touch", "Vise"],
	"boots": ["Dash", "Goad", "Hoof", "League", "March", "Pace", "Road", "Slippers", "Sole", "Span", "Spur", "Stride", "Track", "Trail", "Tread", "Urge"],
	"ring": ["Band", "Circle", "Coil", "Eye", "Finger", "Grasp", "Grip", "Gyre", "Hold", "Knot", "Knuckle", "Loop", "Nail", "Spiral", "Turn", "Twirl", "Whorl"],
	"amulet": ["Beads", "Braid", "Charm", "Choker", "Clasp", "Collar", "Idol", "Gorget", "Heart", "Locket", "Medallion", "Noose", "Pendant", "Rosary", "Scarab", "Talisman", "Torc"],
	"belt": ["Bind", "Bond", "Buckle", "Clasp", "Cord", "Girdle", "Harness", "Lash", "Leash", "Lock", "Shackle", "Snare", "Strap", "Tether", "Thread", "Trap", "Twine"],
}


## Key into SECOND for a base dict.
static func second_key(base: Dictionary) -> String:
	var wt: String = base.get("weapon_type", "")
	if wt != "" and SECOND.has(wt):
		return wt
	var slot: String = base.get("slot_type", "")
	return slot if SECOND.has(slot) else "ring"


static func random_rare_name(base: Dictionary) -> String:
	var words: Array = SECOND[second_key(base)]
	return "%s %s" % [FIRST[randi() % FIRST.size()], words[randi() % words.size()]]

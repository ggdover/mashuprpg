"""Gear pieces of the player (tools/blender/player): shared rules for the family modules
pl_gear_str.py (strength: warriors' iron and steel), pl_gear_dex.py (dexterity: hunters' leather,
hoods and fur) and pl_gear_int.py (intelligence: mages' hoods, robes and crowns).

Every module has `build(L, reg)` that adds, for its family and every tier, the four pieces to the
Look L (pl_body.Look) as parts named part_name(slot, family, tier):
  Helm_<fam>_<tier>  Chest_<fam>_<tier>  Gloves_<fam>_<tier>  Boots_<fam>_<tier>
The three tiers follow the reference sheets ("img references/player"):
  tier 1 = common gear ("low level": light, plain, patched; leather, quilting, simple iron),
  tier 2 = rare gear ("high level" sheets titled MID LEVEL / RARE: fur mantles, trims, coloured
           cloth with borders, capes with an emblem, runed bracers),
  tier 3 = unique gear ("high level" sheets titled HIGH LEVEL / UNIQUE: the heaviest, most ornate
           sets; animal helms / crowns / winged helms, huge fur, long emblem cloaks, ornate plates).
The game shows a piece when an item of that slot is worn (family from the base's first attribute:
str / str_dex / str_int -> str, dex / dex_int -> dex, int -> int; tier from the base tier: 1-2 ->
1, 3-4 -> 2, 5-6 -> 3, uniques one tier higher, max 3), hides the base parts the piece lists
(reg.piece(..., hides=[...]); defaults below) and tints the piece's tint_* surfaces with the item's
tint (albedo x ItemBaseData.ATTR_TINTS: str = steel greys -> gold, dex = leather browns / greens,
int = violets / blues), so put tint_* on the family's identity surface (iron / steel, leather or
cloth) and keep fur, linen, straps and trims fixed.

Rules for every piece:
  * built from the Look's fitting helpers (L.shell, L.sleeve, L.leg_tube, L.dome, L.skirt, L.cape,
    L.fur_collar, L.glove, L.torso_at, L.arm_radius, L.trouser_radius, L.head_spec) so it fits all
    three bodies (f, m1, m2); stay outside the base parts it does not hide (grow >= ~1 cm);
  * a chest piece hides Outfit_Top (with the default outfit's skirts) and Outfit_Belt, so it brings
    its own lower hem / tunic skirt and belt; the trousers (Outfit_Legs) always stay;
  * weights: pl_rig.w_torso / w_arm / w_leg / w_head / w_skirt / w_skirt_legs / w_cape / rigid;
    long hems below the hips use w_skirt (the skirt bones follow the thighs), capes use w_cape (the
    cape bones swing at runtime), hoods / helms use w_head;
  * budgets (triangles, both sides together): helm 400, chest 1600 (2200 with a cape or a big
    mantle), gloves 350, boots 550; tier 1 lighter than that;
  * materials: pl_mesh.mat(name, hex, rough, metal) with names unique to the family
    ("str_leather", "dex_fur"...), and pl_mesh.tint("tint_<slot>_<fam>...") for tinted surfaces.
    Materials are looked up by name (get or create), so a name always means ONE colour / roughness:
    give variants their own names (e.g. per tier "tint_chest_dex_2").
"""
import importlib
import json

SLOTS = ("helm", "chest", "gloves", "boots")
FAMILIES = ("str", "dex", "int")
TIERS = (1, 2, 3)
DEFAULT_HIDES = {
	"helm": ["HairTop"],
	"chest": ["Outfit_Top", "Outfit_Belt"],
	"gloves": ["Hands", "Outfit_Wraps"],
	"boots": ["Outfit_Feet"],
}


def part_name(slot, fam, tier):
	return "%s_%s_%d" % (slot.capitalize(), fam, tier)


class Registry:
	def __init__(self):
		self.pieces = {}

	def piece(self, slot, fam, tier, hides=None, notes=""):
		name = part_name(slot, fam, tier)
		self.pieces[name] = {"slot": slot, "family": fam, "tier": tier,
			"hides": list(DEFAULT_HIDES[slot] if hides is None else hides), "notes": notes}
		return name

	def to_json(self):
		return json.dumps({"version": 1, "pieces": self.pieces}, indent=1, sort_keys=True)


def build_all(L, reg, families=FAMILIES):
	"""Build every available family module's pieces into L. Returns the families built."""
	done = []
	for fam in families:
		try:
			mod = importlib.import_module("pl_gear_" + fam)
		except ModuleNotFoundError:
			continue
		mod.build(L, reg)
		done.append(fam)
	return done


def visible_parts(all_parts, equipped, reg):
	"""The part names shown for `equipped` = {slot: (fam, tier)} (the game's rule)."""
	hidden = set()
	shown = set()
	for slot, (fam, tier) in equipped.items():
		name = part_name(slot, fam, tier)
		if name in reg.pieces:
			shown.add(name)
			hidden.update(reg.pieces[name]["hides"])
	gear = set(reg.pieces)
	return [p for p in all_parts if (p not in gear or p in shown) and p not in hidden]

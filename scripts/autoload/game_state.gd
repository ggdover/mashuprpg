extends Node
## Autoload "GameState": owns the current character, save/load, XP awards and references to the
## live Player and World. OWNER: kernel (wave 1) for data/save/XP; game flow (wave 2) adds the
## area transition logic. Keep every public member/signature.
## See docs/ARCHITECTURE.md §11 and §15.
##
## Save files: save_dir/<save_id>.json = {"version": 1, "save_id", "saved_at": unix time,
## "character": CharacterData.to_dict()}, written atomically (.tmp then rename).

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 1

## Where saves go (tests point this at user://test_saves_<name>/; tests never touch user://saves/).
var save_dir: String = SAVE_DIR

## The character being played (null in the main menu).
var character: CharacterData = null
## The live Player node (null when not in an area).
var player: Player = null
## The live World node (null in the main menu).
var world: World = null
## Info about the current area; same dict as World.area_info.
var current_area: Dictionary = {}
## Saved when a town portal is opened from a dungeon, so "dungeon_return" can resume it.
## {"world": World (detached, kept alive), "position": Vector3} or {}.
var town_portal_state: Dictionary = {}
## Id of the save file the character is stored in.
var save_id: String = ""
## The town vendor's current offer (Items). The game flow rebuilds it on every town entry with
## ItemDB.generate_vendor_stock(max(character.level, Balance.area_level_for_depth(character.max_depth)));
## the vendor panel removes bought items from it and never regenerates it.
var vendor_stock: Array = []
## XP amount of the last award_kill_xp() call (after rounding; 0 if nothing was added).
var last_xp_award: int = 0

## Fractional kill XP carried to the next award (so small awards are never lost to rounding).
var _xp_remainder := 0.0

## Autoload rule: _ready() may only load data and create hidden nodes; GameState loads no save by
## itself. player/world may be null at any time: always check is_instance_valid().


func _process(delta: float) -> void:
	if character != null and player != null and is_instance_valid(player):
		character.play_time += delta


## Create a fresh character: starting items (ItemDB.create_item, normal) equipped, class skill bar
## (via .assign), 3/3 potions, max_depth 1. Sets `character` and a new save_id. Does not change
## area or save. Class attributes are NOT stored on the character (Player.get_base_mods reads
## ClassDefs). Unknown class ids fall back to the warrior (with a warning).
func new_character(char_name: String, class_id: String) -> CharacterData:
	var cid := class_id
	if not ClassDefs.has_class(cid):
		push_warning("GameState.new_character: unknown class '%s', using %s" % [cid, ClassDefs.DEFAULT_CLASS])
		cid = ClassDefs.DEFAULT_CLASS
	var c := CharacterData.new()
	var n := char_name.strip_edges()
	c.char_name = n if n != "" else "Hero"
	c.class_id = cid
	c.level = 1
	c.xp = 0
	c.gold = 0
	c.max_depth = 1
	c.life_potion_charges = Balance.POTION_MAX_CHARGES
	c.mana_potion_charges = Balance.POTION_MAX_CHARGES
	c.skill_bar.assign(ClassDefs.get_start_skill_bar(cid))
	character = c
	for base_id in ClassDefs.get_class_def(cid).get("start_items", []):
		var it: Item = ItemDB.create_item(String(base_id), Item.Rarity.NORMAL)
		if it == null or it.get_base().is_empty():
			push_warning("GameState.new_character: unknown start item '%s'" % base_id)
			continue
		var slot := c.get_default_slot_for(it)
		if slot != "" and c.can_equip(it, slot).get("ok", false):
			for displaced in c.equip(it, slot):
				c.add_to_inventory(displaced)
		elif not c.add_to_inventory(it):
			push_warning("GameState.new_character: no room for start item '%s'" % base_id)
	save_id = make_save_id(c.char_name)
	_xp_remainder = 0.0
	last_xp_award = 0
	return c


## A new unique save id: sanitized name + "_" + unix time (+ "_N" if that file already exists).
func make_save_id(char_name: String) -> String:
	var base := _sanitize(char_name)
	var id := "%s_%d" % [base, int(Time.get_unix_time_from_system())]
	var candidate := id
	var n := 2
	while FileAccess.file_exists(get_save_path(candidate)):
		candidate = "%s_%d" % [id, n]
		n += 1
	return candidate


## Full path of a save file.
func get_save_path(p_save_id: String) -> String:
	return save_dir.path_join(p_save_id + ".json")


func has_save(p_save_id: String) -> bool:
	return _is_safe_id(p_save_id) and FileAccess.file_exists(get_save_path(p_save_id))


## Write `character` to SAVE_DIR/<save_id>.json. Emits Events.game_saved.
func save_game() -> bool:
	if character == null:
		push_warning("GameState.save_game: no character")
		return false
	if save_id == "" or not _is_safe_id(save_id):
		save_id = make_save_id(character.char_name)
	var dir := save_dir
	if not DirAccess.dir_exists_absolute(dir):
		var derr := DirAccess.make_dir_recursive_absolute(dir)
		if derr != OK:
			push_warning("GameState.save_game: can't create %s (%s)" % [dir, error_string(derr)])
			return false
	var data := {
		"version": SAVE_VERSION,
		"save_id": save_id,
		"saved_at": int(Time.get_unix_time_from_system()),
		"character": character.to_dict(),
	}
	var path := get_save_path(save_id)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("GameState.save_game: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var rerr := DirAccess.rename_absolute(tmp, path)
	if rerr != OK:
		push_warning("GameState.save_game: can't rename %s (%s)" % [tmp, error_string(rerr)])
		DirAccess.remove_absolute(tmp)
		return false
	Events.game_saved.emit()
	return true


## Load a save into `character`. Returns false if missing/corrupt.
func load_game(p_save_id: String) -> bool:
	var data := _read_save(p_save_id)
	if data.is_empty():
		return false
	var cd: Variant = data.get("character")
	if not (cd is Dictionary):
		push_warning("GameState.load_game: save '%s' has no character" % p_save_id)
		return false
	character = CharacterData.from_dict(cd)
	save_id = p_save_id
	_xp_remainder = 0.0
	last_xp_award = 0
	return true


## [{"save_id", "char_name", "class_id", "level", "max_depth", "modified": int unix time}], newest first.
func list_saves() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return out
	for f in DirAccess.get_files_at(save_dir):
		if not f.ends_with(".json"):
			continue
		var id := f.get_basename()
		var data := _read_save(id)
		if data.is_empty() or not (data.get("character") is Dictionary):
			continue
		var c: Dictionary = data["character"]
		var modified := int(data.get("saved_at", 0))
		if modified <= 0:
			modified = int(FileAccess.get_modified_time(get_save_path(id)))
		out.append({
			"save_id": id,
			"char_name": String(c.get("char_name", "Hero")),
			"class_id": String(c.get("class_id", ClassDefs.DEFAULT_CLASS)),
			"level": int(c.get("level", 1)),
			"max_depth": int(c.get("max_depth", 1)),
			"modified": modified,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["modified"]) != int(b["modified"]):
			return int(a["modified"]) > int(b["modified"])
		return String(a["save_id"]) > String(b["save_id"]))
	return out


func delete_save(p_save_id: String) -> void:
	if not _is_safe_id(p_save_id):
		push_warning("GameState.delete_save: bad save id '%s'" % p_save_id)
		return
	var path := get_save_path(p_save_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")


## XP for a kill: Balance.monster_xp(monster_level) * xp_mult * Balance.xp_penalty(...), where
## xp_mult already includes the rarity multiplier. Adds it to the character (which emits the
## xp/level signals) and shows a floating "xp" number over the live player. Fractions carry over
## to the next kill. No-op without a character.
func award_kill_xp(monster_level: int, xp_mult: float) -> void:
	last_xp_award = 0
	if character == null or character.is_max_level():
		return
	var amount := Balance.kill_xp(monster_level, xp_mult, character.level) + _xp_remainder
	var whole := int(floorf(amount))
	_xp_remainder = amount - whole
	if whole <= 0:
		return
	last_xp_award = whole
	character.add_xp(whole)
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		Events.damage_number.emit(player.get_aim_point() + Vector3(0, 0.7, 0), float(whole), "xp", false)


## Request an area change (see Events.area_change_requested for area ids).
func change_area(area_id: String, params: Dictionary = {}) -> void:
	Events.area_change_requested.emit(area_id, params)


func is_in_town() -> bool:
	return current_area.get("id", "") == "town"


# ------------------------------------------------------------------ internals

func _read_save(p_save_id: String) -> Dictionary:
	if not _is_safe_id(p_save_id):
		push_warning("GameState: bad save id '%s'" % p_save_id)
		return {}
	var path := get_save_path(p_save_id)
	if not FileAccess.file_exists(path):
		push_warning("GameState: save '%s' not found" % p_save_id)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("GameState: save '%s' is corrupt (line %d: %s)" % [p_save_id, json.get_error_line(), json.get_error_message()])
		return {}
	var data: Variant = json.data
	if not (data is Dictionary):
		push_warning("GameState: save '%s' is not a dictionary" % p_save_id)
		return {}
	if int((data as Dictionary).get("version", 0)) > SAVE_VERSION:
		push_warning("GameState: save '%s' has a newer version" % p_save_id)
	return data


static func _sanitize(s: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	out = out.trim_suffix("_").left(24)
	return out if out != "" else "hero"


static func _is_safe_id(id: String) -> bool:
	return id != "" and not id.contains("/") and not id.contains("\\") and not id.contains("..")

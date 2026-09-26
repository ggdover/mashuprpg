extends Node
## Parse/compile check for GDScript files WITH autoloads available (unlike --check-only/--script,
## which report false "Identifier not found: ItemDB" errors). OWNER: orchestrator.
##
##   tools/gtest.sh <module> res://tools/godot/parse_check.tscn -- --path=res://scripts/items
##   (several: --path=res://scripts/items,res://tests/unit ; default: scripts, tests, tools/godot)
##
## Prints "[PARSE FAIL] <path>" for every script that fails to load/compile; exit code = count.


func _ready() -> void:
	var roots: PackedStringArray = ["res://scripts", "res://tests", "res://tools/godot"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--path="):
			roots = a.substr(7).split(",", false)
	var files: Array[String] = []
	for r in roots:
		if r.ends_with(".gd"):
			files.append(r)
		else:
			_collect(r, files)
	var bad := 0
	for p in files:
		var s := load(p) as GDScript
		if s == null or not s.can_instantiate():
			bad += 1
			print("[PARSE FAIL] ", p)
	print("[parse_check] %d scripts checked, %d failed" % [files.size(), bad])
	get_tree().quit(bad)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not f.begins_with("."):
			var full := dir_path.path_join(f)
			if dir.current_is_dir():
				_collect(full, out)
			elif f.ends_with(".gd"):
				out.append(full)
		f = dir.get_next()

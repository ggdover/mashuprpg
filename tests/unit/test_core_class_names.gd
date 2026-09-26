extends TestCase
## Every class_name must be unique across the project (Godot silently resolves duplicates to one of
## them). New class names must use the module prefixes from docs/ARCHITECTURE.md §4.


func test_class_names_unique() -> void:
	var seen := {}
	for root in ["res://scripts", "res://tests", "res://tools"]:
		_scan(root, seen)
	for cname in seen:
		if (seen[cname] as Array).size() > 1:
			fail("class_name %s declared in %s" % [cname, seen[cname]])


func _scan(dir_path: String, seen: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	var re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	while f != "":
		if not f.begins_with("."):
			var full := dir_path.path_join(f)
			if dir.current_is_dir():
				_scan(full, seen)
			elif f.ends_with(".gd"):
				var text := FileAccess.get_file_as_string(full)
				for m in re.search_all(text):
					var cname := m.get_string(1)
					if not seen.has(cname):
						seen[cname] = []
					seen[cname].append(full)
		f = dir.get_next()

extends TestCase
## Tests for the orchestrator-owned core: StatBlock and StatDefs.


func test_flat_inc_more() -> void:
	var b := StatBlock.new()
	b.add_mods([
		StatBlock.mod("max_life", "flat", 50),
		StatBlock.mod("max_life", "inc", 20),
		StatBlock.mod("max_life", "inc", 30),
		StatBlock.mod("max_life", "more", 10),
		StatBlock.mod("max_life", "more", -50),
	])
	# (100 + 50) * 1.5 * 1.1 * 0.5
	assert_near(b.compute("max_life", 100), 123.75, 0.001, "compute")
	assert_near(b.inc("max_life"), 50, 0.001, "inc sum")


func test_ranges_and_flags() -> void:
	var b := StatBlock.new()
	b.add_mod(StatBlock.mod("added_fire_attack", "flat", 3, 7))
	b.add_mod(StatBlock.mod("added_fire_attack", "flat", 1, 2))
	assert_eq(b.flat_range("added_fire_attack"), Vector2(4, 9), "range sum")
	assert_false(b.has_flag("blood_magic"))
	b.add_mod(StatBlock.mod("blood_magic", "flag"))
	assert_true(b.has_flag("blood_magic"))


func test_describe() -> void:
	assert_eq(StatDefs.describe(StatBlock.mod("max_life", "flat", 25)), "+25 to maximum Life", "flat")
	assert_eq(StatDefs.describe(StatBlock.mod("mana_cost", "inc", -10)), "10% reduced Mana Cost of Skills", "reduced")
	assert_eq(StatDefs.describe(StatBlock.mod("damage", "more", 50)), "50% more Damage", "more")
	assert_eq(StatDefs.describe(StatBlock.mod("added_fire_attack", "flat", 3, 7)), "Adds 3 to 7 Fire Damage to Attacks", "range")
	var lines := StatDefs.describe_mods([StatBlock.mod("strength", "flat", 10), StatBlock.mod("strength", "flat", 5)])
	assert_eq(lines.size(), 1, "merged")
	assert_eq(lines[0], "+15 to Strength", "merged text")


func test_async_test_supported() -> void:
	await get_tree().process_frame
	assert_true(is_inside_tree(), "test node is in tree")

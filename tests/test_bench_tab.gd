class_name TestBenchTab
extends RefCounted
## M6 (MERGE_TRACKER): the thrust stand, the ESC bench and the frame bench are tabs of the Motor, ESC
## and Frame sheets, judging the DESIGN's own selection (not Lab's rails, not a reference fixture).
##   - Motor sheet has a Bench tab; showing it puts a BenchScreen on the stand with this design's motor/prop/pack.
##   - A swapped motor reaches the stand the next time the tab is shown (built fresh each time).
##   - Throttle on the hosted stand spins the rotor and draws current; the ESC bench is on this ESC.
##   - Hiding the tab takes the bench down (nothing spins unattended) and writes the pack's charge back.
## MUTATION: make `_raise` ignore the selection (reference ids) and the pairing checks fail.


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	await tree.process_frame
	var charge_path := "user://test_bench_tab_charge.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(charge_path))
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.pack_charge_path = charge_path
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	out.append(TestResult.new("Motor, ESC and Frame sheets have a Bench tab",
		PartSheetTabs.for_category("motor").any(func(t): return t["id"] == "bench")
		and PartSheetTabs.for_category("esc").any(func(t): return t["id"] == "bench")
		and PartSheetTabs.for_category("frame").any(func(t): return t["id"] == "bench"), ""))
	out.append(TestResult.new("opening the Motor sheet on Bench works", ds.open_part_sheet("motor", "bench"), ""))
	var tab := ds.part_sheet.tab("bench") as BenchTab if ds.part_sheet != null else null
	var stand := tab.screen as BenchScreen if tab != null else null
	out.append(TestResult.new("the stand is up", stand != null, ""))
	if stand == null:
		ds.free()
		return out
	var sel: Dictionary = ds.session.selection
	out.append(TestResult.new("it holds THIS design's motor, prop and pack",
		stand.motor_id == sel["motor"] and stand.propeller_id == sel["propeller"] and stand.battery_id == sel["battery"],
		"%s %s %s" % [stand.motor_id, stand.propeller_id, stand.battery_id]))
	stand.set_throttle(0.8)
	for i in 400:
		stand.advance(0.005)
	out.append(TestResult.new("throttle spins the rotor and draws current", stand.rpm() > 1000.0 and stand.current_a() > 0.5,
		"%.0f rpm %.1f A" % [stand.rpm(), stand.current_a()]))
	# The tab leaves: the bench is taken down and the charge it cost is written.
	ds.part_sheet.show_tab("sheet")
	out.append(TestResult.new("hiding the tab takes the bench down", tab.screen == null, ""))
	out.append(TestResult.new("and writes the pack's charge back", FileAccess.file_exists(charge_path), ""))
	# A swapped motor arrives the next time.
	var other := ""
	for p in catalog.list_category("motor"):
		if String(p.get("part_id", "")) != String(sel["motor"]):
			other = String(p.get("part_id", ""))
			break
	ds.session.selection["motor"] = other
	ds.part_sheet.show_tab("bench")
	var again := tab.screen as BenchScreen
	out.append(TestResult.new("a swapped motor reaches the stand on the next showing",
		again != null and again.motor_id == other and other != "", other))
	ds.part_sheet.close()
	ds.free()
	# ESC bench
	var ds2 := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds2.pack_charge_path = charge_path
	ds2.size = Vector2(1280, 720)
	tree.root.add_child(ds2)
	ds2.open_part_sheet("esc", "bench")
	var etab := ds2.part_sheet.tab("bench") as BenchTab
	var eb := etab.screen as EscBenchScreen if etab != null else null
	out.append(TestResult.new("the ESC bench is on this design's ESC",
		eb != null and eb.esc_id == ds2.session.selection["esc"] and eb.motor_id == ds2.session.selection["motor"],
		eb.esc_id if eb != null else "none"))
	ds2.free()
	var ds3 := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds3.pack_charge_path = charge_path
	ds3.size = Vector2(1280, 720)
	tree.root.add_child(ds3)
	ds3.open_part_sheet("frame", "bench")
	var ftab := ds3.part_sheet.tab("bench") as BenchTab
	out.append(TestResult.new("the frame bench is up on this design's frame",
		ftab != null and ftab.screen is FrameBenchScreen, ""))
	ds3.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(charge_path))
	return out

class_name TestFlightsSheet
extends RefCounted
## M13 (MERGE_TRACKER): Studio is the Flights drawer over the Design Space, beside Field and Mission.
##   - the "..." menu has a Flights item and pressing it opens the drawer on the flights already flown;
##   - the drawer is the real StudioScreen (the log is listed and selectable) and reading it leaves the
##     design alone;
##   - Back and Esc close it and free it;
##   - the drawer builds no `Build`: its source names no catalog or build class (reading a log must never
##     reconstruct a build, StudioScreen's own rule).
##
## MUTATION: removing the `flights_pressed` connection in DesignSpace fails the menu check; making
## `open_flights` return null fails the rest.


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	TestStudio._fresh_dir()
	TestStudio._write_log("flight-20260816-130000.csv", 300, 2)
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), PartsCatalog.load_default())
	ds.size = Vector2(1280, 720)
	tree.root.add_child(ds)
	await tree.process_frame
	var before := ds.session.selection.duplicate(true)

	out.append(TestResult.new("the menu has a Flights item", ds.file_bar.flights_button != null, ""))
	ds.file_bar.flights_button.pressed.emit()
	out.append(TestResult.new("pressing Flights in the menu opens the drawer",
		ds.flights_sheet != null and ds.flights_sheet.visible, str(ds.flights_sheet)))
	ds.open_flights(FlightLogLibrary.load_from(TestStudio.TEST_DIR))
	var sheet := ds.flights_sheet
	out.append(TestResult.new("the drawer hosts Studio over the flights already flown",
		sheet != null and sheet.studio != null and sheet.studio.library.count() == 1, ""))
	sheet.studio.select(sheet.studio.library.ids()[0])
	out.append(TestResult.new("a flight can be selected and its report is drawn in the drawer",
		sheet.studio.selected_id == "flight-20260816-130000.csv", ""))
	out.append(TestResult.new("reading a flight leaves the design as it was", ds.session.selection == before, ""))

	var closed := [false]
	sheet.closed.connect(func(): closed[0] = true)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	sheet._unhandled_key_input(esc)
	out.append(TestResult.new("Esc closes the drawer and it is released",
		closed[0] and ds.flights_sheet == null and not sheet.visible, ""))
	ds.open_flights(FlightLogLibrary.load_from(TestStudio.TEST_DIR))
	ds.flights_sheet.find_child("Back", true, false).pressed.emit()
	out.append(TestResult.new("Back closes the drawer", ds.flights_sheet == null, ""))

	var code := TestPidTunes._code_only(FileAccess.get_file_as_string("res://src/design/flights_sheet.gd"))
	var banned: Array = []
	for token in ["Build.", "PartsCatalog", "from_ids", "DesignSession"]:
		if code.contains(token):
			banned.append(token)
	out.append(TestResult.new("the drawer's source builds no Build", banned.is_empty(), str(banned)))
	ds.queue_free()
	await tree.process_frame
	TestStudio._clean()
	return out

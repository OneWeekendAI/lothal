class_name TestOneBuild
## B5 follow-up (owner's trust bug): the identity sheet, the stats column, the charge chip and the sim all
## report the SAME Build. The session is the one source; a part changed on it (by any path, not only through
## the Design Space's own methods) reaches every reader at once. Also: no raw ids in the sheet's text, and the
## origin line says plainly what the build is.

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	ds.toggle_identity()  # the sheet is open while the part changes: it must follow
	var seed_text := _texts(ds.identity_sheet)
	results.append(TestResult.new("unedited: the origin says Class seed, unedited",
		"Class seed, unedited" in seed_text, seed_text))
	# Swap the battery straight on the session, the way a script, an undo stack or a file open can.
	var old_bat := String(ds.session.selection["battery"])
	for opt in catalog.list_category("battery"):
		var bid := String(opt["part_id"])
		if bid != old_bat and ds.session.swap(catalog, "battery", bid)["ok"]:
			break
	var want := ds.session.build(catalog)
	var info := ds.identity()
	var sheet := _texts(ds.identity_sheet)
	var bat_name := String(info["parts"]["battery"]["name"])
	results.append(TestResult.new("the sheet names the battery now fitted", bat_name in sheet and want != null, sheet))
	var stats_auw := (ds.value_labels["auw_g"] as Label).text
	var want_auw := DesignSpace.format_readout("auw_g", ds.session.readouts(catalog))
	results.append(TestResult.new("the stats column weight is the session build's weight",
		stats_auw == want_auw, "%s vs %s" % [stats_auw, want_auw]))
	results.append(TestResult.new("the sheet weight is the session build's weight",
		"%.0f g" % want.all_up_weight_g() in sheet, sheet))
	results.append(TestResult.new("the top bar chip carries the same weight",
		"%.0f g" % want.all_up_weight_g() in ds.file_bar.identity_button.text, ds.file_bar.identity_button.text))
	var chip := ds.charge_chip.pack_text if ds.charge_chip != null else ""
	results.append(TestResult.new("the charge chip is the same battery",
		ds.charge_chip == null or chip in bat_name, "%s vs %s" % [chip, bat_name]))
	results.append(TestResult.new("edited: the origin says Edited from the class seed",
		"Edited from 5\" seed" in sheet and not ("Class seed, unedited" in sheet), sheet))
	results.append(TestResult.new("no raw part or class id in the sheet text",
		not ("(" in sheet) and not ("battery_" in sheet) and not ("frame_" in sheet) and not ("five_inch" in sheet), sheet))
	ds.free()
	results.append_array(_sim_agrees())
	return results


## Sheet, stats and the sim's own Build agree on a design edited behind the Design Space's back.
static func _sim_agrees() -> Array:
	var results: Array = []
	ProjectLibrary.root = "user://scratch_onebuild_%d" % OS.get_process_id()
	var catalog := PartsCatalog.load_default()
	var shell := GlassShell.new()
	shell._on_project_action("new")
	shell.class_picker.show_class("five_inch")
	shell.class_picker.choose()
	var ds := shell.design_space
	var old_bat := String(ds.session.selection["battery"])
	for opt in catalog.list_category("battery"):
		var bid := String(opt["part_id"])
		if bid != old_bat and ds.session.swap(catalog, "battery", bid)["ok"]:
			break
	var want := ds.session.build(catalog)
	var shown := (ds.value_labels["auw_g"] as Label).text
	shell.fly_it()
	var sim = shell.rooms.sim
	var got: Build = sim.initial_build if sim != null else null
	results.append(TestResult.new("the sim flies the build the sheet describes (same parts, same mass)",
		got != null and got.fingerprint() == want.fingerprint()
		and is_equal_approx(got.all_up_weight_g(), float(ds.identity()["auw_g"])),
		"%s %s" % [got.fingerprint() if got != null else "-", ds.identity()["auw_g"]]))
	results.append(TestResult.new("the stats column agrees with the sim's mass",
		got != null and shown == DesignSpace.format_readout("auw_g", DesignSession.readouts_of(got)), shown))
	if shell.container != null and shell.container.path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(shell.container.path))
	shell.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectLibrary.root))
	ProjectLibrary.root = ProjectLibrary.DIR
	return results


static func _texts(node: Node) -> String:
	var out := ""
	for c in node.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out

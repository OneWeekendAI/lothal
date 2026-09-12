class_name TestControlRails
extends RefCounted
## C3: the rail split. The receiver leaves Video's rail, the GPS and the buzzer join it under
## Control, and `Build.COMPONENT_SYSTEM` is the one table that decides which.
##
## ## What went wrong to make this suite necessary
##
## C2 added `gps` and `buzzer` to `Build.OPTIONAL_COMPONENTS` and they appeared, unasked, on
## VIDEO's rail — because one `ElectronicsPicker` iterated that constant directly and Video's rail
## was the only instance of it. They rendered as the raw strings `gps` and `buzzer`, with no
## `CATEGORY_LABELS` entry, beside a note telling the builder they had been carved out of the
## electronics budget, which neither of them ever was. Nothing failed. That is the whole shape of
## the defect this slice removes and this suite guards: **a component on the wrong rail is not an
## error, it is a mild surprise**, and a component on NO rail is not even that.
##
## ## The rule this suite exists for
##
## `Build.components_for_system` **refuses rather than shrugs**. A category in
## `OPTIONAL_COMPONENTS` that `COMPONENT_SYSTEM` does not claim belongs to no rail, so a filter
## that skipped it would leave that component weighed by the mass model, drawn on the aircraft,
## persisted by the schema — and pickable nowhere in the app. So the function answers NOTHING for
## anybody until the table is fixed, and the rail it was asked for says on screen why it is empty.
## That is P10f's finding applied in advance: *the two lists were never the same list.*
##
## ## What is deliberately NOT here
##
## The five-list coverage rule over every optional component is **C4's**, and it is a slice of its
## own on purpose — the checks below are about the receiver, the GPS and the buzzer specifically,
## and about the table that moved them. `BuildPanel.CATEGORY_ORDER` is still a second hand-written
## list and C4 is where that gets teeth. `LinkDetails` and the panel rows are **C6's**; what stands
## in the Link panel today is `LinkStub`, and the checks below assert the routing, not the rows.

## Each section by name, so a section that produces NOTHING is reported rather than vanishing —
## `tests/test_electronics_ui.gd`'s own guard, for its reason: a runtime error partway through a
## section aborts it, its assertions are never appended, and the suite passes with fewer results
## than were written. GDScript 4 raising on `float == String` is the usual cause.
static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	var sections := {
		"the system entry": _test_the_system_entry(),
		"the rails on a real Lab": _test_the_rails_on_a_real_lab(catalog),
		"where the receiver is": _test_where_the_receiver_is(catalog),
		"no hand-written list": _test_no_hand_written_list(catalog),
		"the ring counts the receiver once": _test_the_ring_counts_the_receiver_once(),
		"the model lights the new parts": _test_the_model_lights_the_new_parts(),
		"leaving a system takes its panels": _test_leaving_a_system_takes_its_panels(),
		"an unclaimed category is loud": _test_an_unclaimed_category_is_loud(catalog),
		"the new categories have labels": _test_the_new_categories_have_labels(),
	}

	var silent: Array = []
	for section in sections:
		var produced: Array = sections[section]
		if produced.is_empty():
			silent.append(section)
		results.append_array(produced)

	results.append(TestResult.new(
		"every section of this suite produced assertions",
		silent.is_empty(),
		"produced nothing: %s" % ("none" if silent.is_empty() else ", ".join(silent))
	))
	return results


# ---------------------------------------------------------------------------
# Row 1 — Control's entry in SYSTEMS
# ---------------------------------------------------------------------------

static func _test_the_system_entry() -> Array:
	var results: Array = []
	var control := _system("Control")

	results.append(TestResult.new(
		"Control's SYSTEMS entry names the FC rail and the Link rail, in that order",
		control.get("rails", []) == ["FC", "Link"],
		"rails %s" % [control.get("rails", [])]))

	results.append(TestResult.new(
		"Control's SYSTEMS entry names the FC, Link and Tune panels",
		control.get("panels", []) == ["FC", "Link", "Tune"],
		"panels %s" % [control.get("panels", [])]))
	return results


## The same claim against a real `LabScreen`, which is what catches a name that routes to nothing:
## the entry above is a list of strings, and strings agree with each other whether or not the tab
## exists. Driven through `select_system_by_name` so a screenshot and this check take one path.
static func _test_the_rails_on_a_real_lab(_catalog: PartsCatalog) -> Array:
	var results: Array = []
	var shell := GlassShell.new()
	shell.select_system_by_name("Control")
	var rails_shown := _shown_titles(shell.lab.rails())
	var panels_shown := _shown_titles(shell.lab.panels)
	shell.free()

	results.append(TestResult.new(
		"selecting Control shows exactly the FC and Link rails",
		rails_shown == ["FC", "Link"],
		"showing %s" % [rails_shown]))

	results.append(TestResult.new(
		"selecting Control shows exactly the FC, Link and Tune panels",
		panels_shown == ["FC", "Link", "Tune"],
		"showing %s" % [panels_shown]))
	return results


# ---------------------------------------------------------------------------
# Row 2 — the receiver is on exactly one rail, and it is Control's
# ---------------------------------------------------------------------------

## THE RAIL A COMPONENT IS PICKED ON, asked of the rails themselves rather than of the table they
## were built from. `has_category` is what `LabScreen.select_component` routes on, so this is the
## same question the app asks when a saved project fits a receiver.
static func _test_where_the_receiver_is(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	var carrying: Array = []
	for rail in lab.component_rails():
		if rail.has_category("receiver"):
			carrying.append(String(rail.name))

	results.append(TestResult.new(
		"the receiver is on exactly one rail",
		carrying.size() == 1,
		"carried by %d rail(s): %s" % [carrying.size(), carrying]))

	results.append(TestResult.new(
		"and the rail it is on is Control's Link rail",
		carrying == ["Link"],
		"carried by %s" % [carrying]))

	# C2's two, whose arrival on Video's rail is what this slice is fixing. One assertion each
	# rather than one over the pair, per feedback_loop_tests_hide_coverage: two components on the
	# wrong rail should be two failures.
	for category in ["gps", "buzzer"]:
		var video_rail := lab.electronics_picker
		results.append(TestResult.new(
			"%s is not on Video's Electronics rail" % category,
			not video_rail.has_category(category),
			"Electronics carries %s" % [video_rail.categories]))

	for category in ["gps", "buzzer"]:
		results.append(TestResult.new(
			"%s is on Control's Link rail" % category,
			lab.link_picker.has_category(category),
			"Link carries %s" % [lab.link_picker.categories]))

	lab.free()
	return results


# ---------------------------------------------------------------------------
# Row 3 — neither list is hand-written
# ---------------------------------------------------------------------------

## Two checks of two different kinds, because the claim has two halves and only one of them is a
## runtime property.
##
## **The runtime half**: each rail's categories are exactly `OPTIONAL_COMPONENTS` filtered by
## `COMPONENT_SYSTEM`, in the mass model's order. The expectation is rebuilt here from the two
## constants rather than read off `components_for_system`, so a filter that stopped filtering is a
## failure rather than a tautology.
##
## **The source half, and why it is not a paranoid extra**: a hand-written list that happens to
## AGREE with the table today is invisible to every runtime check there can be — it is the same
## three strings. What is wrong with it is that it will not move when the table does, and that is a
## property of the source text, not of any value. So the call sites are read: every
## `ElectronicsPicker.new` in `src/` must take its categories from `Build.components_for_system`.
## Same posture as `tests/test_guard_mesh.gd`'s source check, for the same reason — the invariant
## is about what the file says.
static func _test_no_hand_written_list(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var lab := LabScreen.new(catalog, AssemblyTweaks.new(), PackCharge.new())

	for system in ["Video", "Control"]:
		var expected: Array[String] = []
		for category in Build.OPTIONAL_COMPONENTS:
			if String(Build.COMPONENT_SYSTEM.get(category, "")) == system:
				expected.append(String(category))
		var rail := lab.electronics_picker if system == "Video" else lab.link_picker
		results.append(TestResult.new(
			"%s's rail renders exactly the categories COMPONENT_SYSTEM gives it, in weighing order"
				% system,
			rail.categories == expected and not expected.is_empty(),
			"rail %s vs table %s" % [rail.categories, expected]))

	lab.free()

	var source := _source_of("res://src/lab/lab_screen.gd")
	if source == "":
		results.append(TestResult.new(
			"lab_screen.gd is readable", false, "FileAccess.open returned null"))
		return results

	# Every construction of the picker, with whatever it was handed. The categories argument is the
	# second, and the only two call sites in the app are LabScreen's.
	var regex := RegEx.new()
	regex.compile("ElectronicsPicker\\.new\\(\\s*catalog,\\s*([^,]+),")
	var constructions: Array = regex.search_all(source)
	var hand_written: Array = []
	for m in constructions:
		var argument := String((m as RegExMatch).get_string(1)).strip_edges()
		if not argument.begins_with("Build.components_for_system("):
			hand_written.append(argument)

	results.append(TestResult.new(
		"both pickers in lab_screen.gd are constructed from Build.components_for_system",
		constructions.size() == 2 and hand_written.is_empty(),
		"%d construction(s); not from the filter: %s" % [
			constructions.size(),
			"none" if hand_written.is_empty() else ", ".join(hand_written)]))
	return results


# ---------------------------------------------------------------------------
# Row 4 — the ring counts the receiver once
# ---------------------------------------------------------------------------

## `decided_by` is what the completeness ring is arithmetic over, and a category named by two
## systems is credited twice by arithmetic that assumes each decision belongs somewhere once.
## Video never named `receiver`, so this slice MOVES no credit — it adds the name in the one place
## that was missing it, and the check is that the count did not become two on the way.
static func _test_the_ring_counts_the_receiver_once() -> Array:
	var results: Array = []

	var naming: Array = []
	for system in GlassShell.SYSTEMS:
		if (system.get("decided_by", []) as Array).has("receiver"):
			naming.append(String(system["name"]))

	results.append(TestResult.new(
		"exactly one system's decided_by names the receiver",
		naming.size() == 1,
		"named by %d system(s): %s" % [naming.size(), naming]))

	results.append(TestResult.new(
		"and it is Control",
		naming == ["Control"],
		"named by %s" % [naming]))

	results.append(TestResult.new(
		"Video's decided_by is the camera and the VTX, and does not name the receiver",
		_system("Video").get("decided_by", []) == ["camera", "vtx"],
		"Video decided_by %s" % [_system("Video").get("decided_by", [])]))
	return results


# ---------------------------------------------------------------------------
# Row 5 — the model lights the new parts under Control
# ---------------------------------------------------------------------------

## The dimming, driven through `_fade_below` against node names `AirframeModel` actually builds
## (`Component_%s` per category), rather than through `SYSTEM_NODE_PREFIXES` alone: a prefix table
## that agrees with itself is not evidence that a mesh changes transparency.
##
## Four assertions, not one loop: a prefix missing for the GPS and a prefix missing for the buzzer
## are two defects, and one looping assertion would report them as one.
static func _test_the_model_lights_the_new_parts() -> Array:
	var results: Array = []
	var shell := GlassShell.new()

	for category in ["gps", "buzzer"]:
		var root := Node3D.new()
		var mesh := MeshInstance3D.new()
		mesh.name = "Component_%s" % category
		root.add_child(mesh)

		shell._fade_below(root, "", "Control")
		var lit := mesh.transparency
		shell._fade_below(root, "", "Video")
		var dimmed := mesh.transparency
		root.free()

		results.append(TestResult.new(
			"Component_%s is fully opaque with Control focused" % category,
			is_equal_approx(lit, 0.0),
			"transparency %.3f with Control focused" % lit))

		# `> 0.0` AS WELL AS THE CONSTANT, and the first half is the half that can fail. A check
		# written only against `GlassShell.DIM_TRANSPARENCY` moves its own oracle with the code:
		# setting that constant to 0.0 turns the dimming off entirely and this assertion went on
		# passing. Measured, not supposed — that mutation was run and reddened nothing until this
		# clause was added.
		results.append(TestResult.new(
			"Component_%s is dimmed with Video focused" % category,
			dimmed > 0.0 and is_equal_approx(dimmed, GlassShell.DIM_TRANSPARENCY),
			"transparency %.3f with Video focused, expected %.3f" % [
				dimmed, GlassShell.DIM_TRANSPARENCY]))

	shell.free()
	return results


# ---------------------------------------------------------------------------
# Row 6 — leaving a system takes its panels with it
# ---------------------------------------------------------------------------

## Video → Control → Airframe, on a real shell, asserting the panel strip after each step.
##
## **WHY THIS IS HERE AND NOT IN `tests/test_shell_layout.gd`.** That suite is the one that renders
## frames, and it earns that cost for one class of question: where something ENDED UP on screen, in
## pixels. This is not that question. Which panels are hidden is `TabContainer.is_tab_hidden`,
## which is set and readable in the same call with no layout pass — `tests/test_glass_shell.gd`
## already asserts every transition that way, and its header records what happens to a check in
## that file that reaches for `current_tab` instead: 11 of 14 transitions failed against correct
## code. So the hidden set is asserted here, synchronously, and nothing about rects is claimed.
##
## Control is now the widest system in the shell — two rails and three panels — so the step that
## matters is the one OUT of it: three panels retracting to Airframe's four, none of them left over.
static func _test_leaving_a_system_takes_its_panels() -> Array:
	var results: Array = []
	var shell := GlassShell.new()

	var walk := ["Video", "Control", "Airframe"]
	var expected := {
		"Video": ["Electronics"],
		"Control": ["FC", "Link", "Tune"],
		"Airframe": ["Structure", "Arms", "Fasteners", "Layout"],
	}
	var seen := {}
	for system_name in walk:
		shell.select_system_by_name(system_name)
		seen[system_name] = _shown_titles(shell.lab.panels)
	shell.free()

	for system_name in walk:
		results.append(TestResult.new(
			"walking Video -> Control -> Airframe, %s shows exactly its own panels" % system_name,
			seen[system_name] == expected[system_name],
			"showing %s, expected %s" % [seen[system_name], expected[system_name]]))

	# The one that names the defect rather than the rule: Control's Link panel is the newest tab in
	# the shell, so it is the likeliest to be left behind by a retraction that has not been told
	# about it.
	results.append(TestResult.new(
		"and no panel of Control's is still showing in Airframe",
		not (seen["Airframe"] as Array).has("Link")
			and not (seen["Airframe"] as Array).has("FC")
			and not (seen["Airframe"] as Array).has("Tune"),
		"Airframe shows %s" % [seen["Airframe"]]))
	return results


# ---------------------------------------------------------------------------
# Row 7 — an unclaimed category is a loud failure, not a silently unrendered row
# ---------------------------------------------------------------------------

## THE ROW THIS SLICE IS ABOUT. A seventh optional component added to the mass model and forgotten
## in `COMPONENT_SYSTEM` must not simply fail to appear on a rail.
##
## The tables are passed in rather than mutated, because `COMPONENT_SYSTEM` is a `const`
## Dictionary and therefore read-only at runtime — a check that could not inject its own seventh
## category could only ever assert the happy path, which is the shape of a test that cannot fail.
static func _test_an_unclaimed_category_is_loud(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var claimed: Array = ["camera", "vtx", "antenna", "receiver", "gps", "buzzer"]
	var owner := {
		"camera": "Video", "vtx": "Video", "antenna": "Video",
		"receiver": "Control", "gps": "Control", "buzzer": "Control",
	}
	# A seventh component, in the model and in no system — exactly the state C2 was one edit away
	# from shipping.
	var with_orphan: Array = claimed.duplicate()
	with_orphan.append("telemetry")

	# THE VACUITY GUARD. If the happy path returned nothing either, every assertion below about
	# emptiness would pass for the wrong reason.
	var healthy := Build.components_for_system("Video", claimed, owner)
	results.append(TestResult.new(
		"with every category claimed, the filter answers with that system's components",
		healthy == ["camera", "vtx", "antenna"],
		"Video got %s" % [healthy]))

	var refused_video := Build.components_for_system("Video", with_orphan, owner)
	results.append(TestResult.new(
		"one unclaimed category and the filter answers NOTHING for Video — it refuses, not skips",
		refused_video.is_empty(),
		"Video got %s (a shrug would have returned the three claimed ones)" % [refused_video]))

	var refused_control := Build.components_for_system("Control", with_orphan, owner)
	results.append(TestResult.new(
		"and nothing for Control either — the refusal is not local to the rail that lost a part",
		refused_control.is_empty(),
		"Control got %s" % [refused_control]))

	results.append(TestResult.new(
		"the unclaimed category is named, so the error says which table entry is missing",
		Build.unclaimed_components(with_orphan, owner) == ["telemetry"],
		"unclaimed: %s" % [Build.unclaimed_components(with_orphan, owner)]))

	results.append(TestResult.new(
		"and today nothing is unclaimed",
		Build.unclaimed_components().is_empty(),
		"unclaimed: %s" % [Build.unclaimed_components()]))

	# What the refusal looks like on screen: the rail says why it is empty. A form with no rows in
	# it reads as a rendering fault, which is the silence this row forbids.
	var blank := ElectronicsPicker.new(catalog, [] as Array[String], "Link")
	var said: Array = []
	for label in _labels_below(blank):
		if label.text.contains("COMPONENT_SYSTEM"):
			said.append(label.text)
	blank.free()

	results.append(TestResult.new(
		"a rail built from a refusal says COMPONENT_SYSTEM is missing an entry, on screen",
		said.size() == 1,
		"%d label(s) naming the table: %s" % [said.size(), said]))
	return results


# ---------------------------------------------------------------------------
# The labels C2 left missing
# ---------------------------------------------------------------------------

## `gps` and `buzzer` rendered as their own category strings on Video's rail for the whole of C2.
## One assertion each, and each asserts the label is not merely present but DIFFERENT from the raw
## category — `CATEGORY_LABELS.get(category, category)` means a missing entry and a lower-case
## entry are the same pixel.
static func _test_the_new_categories_have_labels() -> Array:
	var results: Array = []
	for category in ["gps", "buzzer"]:
		var label := String(ElectronicsPicker.CATEGORY_LABELS.get(category, category))
		results.append(TestResult.new(
			"%s browses under a written label rather than its category string" % category,
			ElectronicsPicker.CATEGORY_LABELS.has(category) and label != category
				and label != "",
			"labelled \"%s\"" % label))
	return results


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _system(system_name: String) -> Dictionary:
	for system in GlassShell.SYSTEMS:
		if str(system["name"]) == system_name:
			return system
	return {}


static func _shown_titles(tabs: TabContainer) -> Array:
	var out: Array = []
	for i in tabs.get_tab_count():
		if not tabs.is_tab_hidden(i):
			out.append(tabs.get_tab_title(i))
	return out


static func _source_of(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _labels_below(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels_below(child))
	return out

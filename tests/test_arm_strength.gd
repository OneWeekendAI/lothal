class_name TestArmStrength
extends RefCounted
## The crash-strength rating — airframe gaps build plan, slice G4. `ArmStrength` (capacity, the
## catalog reference table, the rating and the size-class note), reached through `FrameWarnings.of`,
## `WarningRows` and the Arms page (`ArmsDetails`).
##
## Where each check could pass while proving nothing, and what stops it:
##   - the thickness, width and material checks assert the EXACT ratio the closed form demands
##     ((t1/t0)^2, b1/b0, sigma1/sigma0), written here and not read back from the code under test,
##     and also that the RANK moves — a capacity that moved while the rank stayed put would be a
##     rating nobody sees.
##   - the absolute capacity is asserted against sigma*b*t^2/(6L) computed in this file, so a units
##     slip (MPa as Pa, mm as m) cannot pass as "it got bigger".
##   - the necked arm is the shape a root-only capacity gets wrong: same root as the plain arm, much
##     lower capacity. A root-only implementation passes every uniform-arm check above.
##   - ranking stability is checked against a TIE handed in both orders: with no tie, a missing
##     tie-break is invisible.
##   - the note has a firing fixture AND a quiet one (feedback: plans whose tests cannot fail,
##     case 8), and both go through FrameWarnings.of, so the wiring is under test.
##   - one result per case, never a loop that fails once (feedback: loop tests hide coverage). The
##     parity check over the catalog is ONE assertion that names every frame that broke it.

const T3K := "carbon_3k_twill_0_90"
const ARM_MM := 110.0
const STRENGTH_3K_PA := 600.0e6


static func run() -> Array:
	var sections := {}
	sections["capacity"] = _capacity()
	sections["references"] = _references()
	sections["size class"] = _size_class()
	sections["note"] = _note()
	sections["page"] = _page()
	var out: Array = []
	for name in sections:
		var list: Array = sections[name]
		if list.is_empty():
			out.append(TestResult.new("arm strength: section '%s' produced results" % name, false,
				"empty — it aborted"))
		out.append_array(list)
	return out


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

static func _materials() -> FrameMaterials:
	return FrameMaterials.load_default()


static func _refs() -> Array:
	return ArmStrength.default_references(_materials())


## A drawn quad X: a 40 mm centre plate and four parallel arms of `width` × `thickness`, `ARM_MM`
## long, in `material`. Optionally necked: the arm narrows to `neck` mm across [50, 60] mm.
static func _drawn(width: float, thickness: float, material: String = T3K,
		neck: float = 0.0) -> AirframeDocument:
	var document := AirframeDocument.new()
	document.id = "test_drawn_strength"
	document.name = "Drawn"
	document.material_id = material
	document.plates.append(AirframeDocument.make_plate(PackedVector2Array([
		Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)]),
		[], 2.0, 0.0, AirframeDocument.ROLE_BOTTOM))
	for index in 4:
		var angle := deg_to_rad(45.0 + 90.0 * float(index))
		var along := Vector2(cos(angle), sin(angle))
		var across := Vector2(-along.y, along.x)
		var half := width * 0.5
		var outline := PackedVector2Array()
		if neck <= 0.0:
			outline = PackedVector2Array([-across * half, along * ARM_MM - across * half,
				along * ARM_MM + across * half, across * half])
		else:
			var n := neck * 0.5
			outline = PackedVector2Array([
				-across * half, along * 50.0 - across * half, along * 50.0 - across * n,
				along * 60.0 - across * n, along * 60.0 - across * half,
				along * ARM_MM - across * half, along * ARM_MM + across * half,
				along * 60.0 + across * half, along * 60.0 + across * n,
				along * 50.0 + across * n, along * 50.0 + across * half, across * half])
		document.plates.append(AirframeDocument.make_arm_plate(
			outline, [], thickness, 0.0, Vector2.ZERO, along * ARM_MM))
	return document


static func _rating(document: AirframeDocument) -> Dictionary:
	var beam := ArmStrength.beam_of(document, _materials())
	return ArmStrength.rate(beam, _materials(), _refs())


## sigma * b * t^2 / (6 L), in newtons, from millimetres — the closed form, written here.
static func _expected_break_n(strength_pa: float, width_mm: float, thickness_mm: float) -> float:
	var b := width_mm / 1000.0
	var t := thickness_mm / 1000.0
	return strength_pa * b * t * t / (6.0 * ARM_MM / 1000.0)


static func _close(a: float, b: float, rel: float = 1.0e-6) -> bool:
	return absf(a - b) <= rel * absf(b)


static func _show(r: Dictionary) -> String:
	return "F %.2f N, stronger than %d of %d, '%s'" % [float(r.get("break_load_n", 0.0)),
		int(r.get("stronger_than", 0)), int(r.get("total", 0)), str(r.get("phrase", ""))]


# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

static func _capacity() -> Array:
	var out: Array = []

	var thin := _rating(_drawn(14.0, 4.0))
	var thick := _rating(_drawn(14.0, 6.0))
	out.append(TestResult.new(
		"arm strength: a uniform arm breaks at sigma*b*t^2/(6L), from the material's own strength",
		_close(float(thin["break_load_n"]), _expected_break_n(STRENGTH_3K_PA, 14.0, 4.0)),
		"%s, want %.2f N" % [_show(thin), _expected_break_n(STRENGTH_3K_PA, 14.0, 4.0)]))
	# MUTATION: hard-code the thickness in ArmStrength.capacity (or take it from the plate stock
	# rather than the beam) and the ratio stops being (6/4)^2.
	out.append(TestResult.new(
		"arm strength: a thicker arm rates above a thinner one, by (t1/t0)^2 and in rank",
		_close(float(thick["break_load_n"]) / float(thin["break_load_n"]), pow(6.0 / 4.0, 2.0))
			and int(thick["stronger_than"]) > int(thin["stronger_than"]),
		"thin %s / thick %s" % [_show(thin), _show(thick)]))

	var narrow := _rating(_drawn(12.0, 5.0))
	var wide := _rating(_drawn(20.0, 5.0))
	# MUTATION: hard-code the width (or read the tip width instead of the section) and this fails.
	out.append(TestResult.new(
		"arm strength: a wider arm rates above a narrower one, linearly in b and in rank",
		_close(float(wide["break_load_n"]) / float(narrow["break_load_n"]), 20.0 / 12.0)
			and int(wide["stronger_than"]) > int(narrow["stronger_than"]),
		"narrow %s / wide %s" % [_show(narrow), _show(wide)]))

	var carbon := _rating(_drawn(14.0, 5.0, T3K))
	var nylon := _rating(_drawn(14.0, 5.0, "pa12_sls"))
	# MUTATION: use a fixed 600 MPa instead of the beam material's strength and this fails.
	out.append(TestResult.new(
		"arm strength: a weaker material lowers the rating, by the strength ratio and in rank",
		_close(float(nylon["break_load_n"]) / float(carbon["break_load_n"]), 48.0 / 600.0)
			and int(nylon["stronger_than"]) < int(carbon["stronger_than"])
			and str(nylon["phrase"]).begins_with("weaker than all ("),
		"carbon %s / nylon %s" % [_show(carbon), _show(nylon)]))

	# The neck: same 20 mm root as the plain arm, 6 mm across [50, 60] mm. At s = 55 mm the
	# section is 6 mm with 55 mm of arm beyond it: sigma*6*t^2/(6*55) — below the root's figure.
	# MUTATION: evaluate only the root station (s = 0) and this reports the un-necked capacity.
	var plain := _rating(_drawn(20.0, 5.0))
	var necked := _rating(_drawn(20.0, 5.0, T3K, 6.0))
	var neck_cap := STRENGTH_3K_PA * 0.006 * 0.005 * 0.005 / (6.0 * 0.055)
	out.append(TestResult.new(
		"arm strength: a necked arm breaks at its neck, not its root",
		_close(float(necked["break_load_n"]), neck_cap, 1.0e-6)
			and absf(float(necked["weakest_s_m"]) - 0.055) < 1.0e-9
			and float(necked["break_load_n"]) < float(plain["break_load_n"]),
		"plain %s / necked %s at s=%.4f, want %.2f N" % [_show(plain), _show(necked),
			float(necked["weakest_s_m"]), neck_cap]))

	# The label: the strength figure's tier is read from materials.json, not asserted by the code.
	# MUTATION: return a fixed "engineering" from strength_tier_of and the carbon side fails; return
	# a fixed "characteristic" and the nylon side does.
	out.append(TestResult.new(
		"arm strength: the strength figure's tier comes from materials.json (carbon characteristic, PA12 engineering)",
		str(carbon["strength_tier"]) == "characteristic" and str(nylon["strength_tier"]) == "engineering",
		"carbon %s / nylon %s" % [carbon["strength_tier"], nylon["strength_tier"]]))
	return out


# ---------------------------------------------------------------------------
# The reference table and ranking
# ---------------------------------------------------------------------------

static func _references() -> Array:
	var out: Array = []
	var refs := _refs()
	var catalog := PartsCatalog.load_default()
	var materials := _materials()

	# Weakest first. MUTATION: delete the sort and the catalog's own (size) order shows through —
	# the Evoque F5 V2 sits after the V3 there and is stronger, so this fails.
	var sorted := true
	for i in range(1, refs.size()):
		if float(refs[i]["break_load_n"]) < float(refs[i - 1]["break_load_n"]):
			sorted = false
	out.append(TestResult.new("arm strength: the reference table is ordered weakest first",
		sorted and refs.size() >= 2, "%d references" % refs.size()))

	# Every plate frame with an arm, and the moulded one left out — counted, so the "of N" is honest.
	var plate_frames := 0
	for frame in catalog.list_category("frame"):
		if str((frame.get("specs", {}) as Dictionary).get("construction", "plate")) != "moulded":
			plate_frames += 1
	out.append(TestResult.new(
		"arm strength: every plate frame in the catalog is a reference, and the moulded whoop is not",
		refs.size() == plate_frames and plate_frames > 0
			and not refs.any(func(r: Dictionary) -> bool: return r["part_id"] == "frame_65mm_whoop"),
		"%d references, %d plate frames" % [refs.size(), plate_frames]))

	# A TIE, handed in both orders, must come out the same way. MUTATION: drop the part_id tie-break
	# and the order follows the input.
	var base: Dictionary = catalog.get_part("frame_5in_freestyle").duplicate(true)
	var twin: Dictionary = base.duplicate(true)
	twin["part_id"] = "frame_5in_freestyle_twin"
	twin["name"] = "Twin"
	var forward := ArmStrength.references_of_frames([twin, base], materials)
	var backward := ArmStrength.references_of_frames([base, twin], materials)
	var ids_f := forward.map(func(r: Dictionary) -> String: return str(r["part_id"]))
	var ids_b := backward.map(func(r: Dictionary) -> String: return str(r["part_id"]))
	out.append(TestResult.new("arm strength: a tie ranks the same whichever order it arrives in",
		ids_f == ids_b and ids_f == ["frame_5in_freestyle", "frame_5in_freestyle_twin"],
		"%s / %s" % [ids_f, ids_b]))

	# PARITY: every catalog frame, rated against the table, is "about as strong as" itself and
	# stronger than exactly the frames below it in the table. ONE assertion naming every frame that
	# breaks it. MUTATION: count `<=` instead of `<` in rate() and every frame counts itself.
	var broken: Array[String] = []
	for i in range(refs.size()):
		var ref: Dictionary = refs[i]
		var document := AirframeDocument.from_catalog_frame(catalog.get_part(str(ref["part_id"])))
		var rating := ArmStrength.rate(ArmStrength.beam_of(document, materials), materials, refs)
		if int(rating["stronger_than"]) != i or not (rating["nearest"] as Array).has(ref["name"]) \
				or not str(rating["phrase"]).begins_with("about as strong as"):
			broken.append("%s: %s (index %d)" % [ref["name"], _show(rating), i])
	out.append(TestResult.new(
		"arm strength: each catalog frame rates as itself, stronger than exactly the frames below it",
		broken.is_empty(), "none" if broken.is_empty() else "; ".join(broken)))

	# Between two references, the phrase names both rather than snapping to one. The 4 mm × 14 mm arm
	# sits at 203.6 N — between the 3" Toothpick and the 3.5" Freestyle, >10% from each.
	# MUTATION: always use the "about as strong as" wording and this fails.
	var between := _rating(_drawn(14.0, 4.0))
	out.append(TestResult.new(
		"arm strength: an arm far from every reference says which two it falls between",
		str(between["phrase"]).begins_with("between the "), _show(between)))
	return out


# ---------------------------------------------------------------------------
# Size class
# ---------------------------------------------------------------------------

static func _size_class() -> Array:
	var out: Array = []
	var refs := _refs()
	var five := ArmStrength.size_class_of(110.0, refs)
	var five_count := refs.filter(func(r: Dictionary) -> bool: return r["size_class"] == "5\"").size()
	out.append(TestResult.new("arm strength: a 110 mm arm is cleanly a 5\" and compares against the 5\" frames",
		bool(five["clean"]) and str(five["size_class"]) == "5\""
			and (five["members"] as Array).size() == five_count and five_count >= 2,
		"%s, %d members of %d" % [five["size_class"], (five["members"] as Array).size(), five_count]))
	# 81.5 mm sits between the 3" Toothpick (75) and the 3.5" Freestyle (88), within 10% of both.
	# MUTATION: delete the two-classes-in-the-window check and this becomes a clean 3".
	var between := ArmStrength.size_class_of(81.5, refs)
	out.append(TestResult.new(
		"arm strength: an arm between two classes is not forced into one — it compares against all frames",
		not bool(between["clean"]) and (between["members"] as Array).size() == refs.size(),
		"clean=%s class='%s' members=%d" % [between["clean"], between["size_class"],
			(between["members"] as Array).size()]))
	return out


# ---------------------------------------------------------------------------
# The note
# ---------------------------------------------------------------------------

static func _arm_note(document: AirframeDocument) -> BuildWarning:
	for warning in FrameWarnings.of(document, AirframeProperties.compute(document, _materials())):
		if warning.id == &"arm_weaker_than_class":
			return warning
	return null


static func _note() -> Array:
	var out: Array = []
	# 1.5 mm × 12 mm at 110 mm: 49 N against the weakest 5" frame's 233 N.
	# MUTATION: make `weaker_than_class` always false (or compare against the class's STRONGEST from
	# above) and this goes quiet.
	var weak := _arm_note(_drawn(12.0, 1.5))
	out.append(TestResult.new(
		"arm strength: an arm much weaker than every 5\" frame raises the CHARACTERISTIC note, on the Arms row",
		weak != null and weak.severity == BuildWarning.Severity.CHARACTERISTIC
			and weak.item == WarningRows.ARMS and weak.short == "arm weaker than every 5\" frame"
			and weak.message.contains("not a crash prediction"),
		"none" if weak == null else "%s / %s / %s" % [weak.item, weak.short, weak.message]))
	# The typical 5": the catalog's own 5" Freestyle preset. MUTATION: compare against the class's
	# STRONGEST instead of its weakest and this fires on a stock frame.
	var typical := _arm_note(AirframeDocument.from_catalog_frame(
		PartsCatalog.load_default().get_part("frame_5in_freestyle")))
	out.append(TestResult.new("arm strength: a typical 5\" arm raises no strength note",
		typical == null, "fired: %s" % (typical.message if typical != null else "")))
	# The weakest frame OF the class must not be flagged against itself (the tie band).
	# MUTATION: compare with `<=` and the 5" Race fires against its own figure.
	var race := _arm_note(AirframeDocument.from_catalog_frame(
		PartsCatalog.load_default().get_part("frame_5in_race")))
	out.append(TestResult.new("arm strength: the weakest 5\" frame is not flagged as weaker than itself",
		race == null, "fired: %s" % (race.message if race != null else "")))
	return out


# ---------------------------------------------------------------------------
# The Arms page
# ---------------------------------------------------------------------------

static func _page() -> Array:
	var out: Array = []
	var panel := ArmsDetails.new()
	panel.render(AirframeDocument.from_catalog_frame(
		PartsCatalog.load_default().get_part("frame_5in_freestyle")))
	var like := panel.row_text("strength_like")
	var rank := panel.row_text("strength_rank")
	var breaks := panel.row_text("break_load")
	var note := panel.strength_note_text()
	panel.set_footer_visible(false)
	var note_on_dock := panel.strength_note_text()
	panel.free()
	var refs := _refs()
	var index := -1
	for i in range(refs.size()):
		if refs[i]["part_id"] == "frame_5in_freestyle":
			index = i
	out.append(TestResult.new(
		"arm strength: the Arms page names the nearest frame and the rank, with the strength's tier",
		like == "about as strong as the 5\" Freestyle"
			and rank == "stronger than %d of %d frames  (characteristic)" % [index, refs.size()],
		"%s / %s" % [like, rank]))
	out.append(TestResult.new(
		"arm strength: the break load is quoted in newtons and as a weight, with the strength's tier",
		breaks == "%.0f N ≈ %.0f kg, at root  (characteristic)" % [
			float(refs[index]["break_load_n"]), float(refs[index]["break_load_n"]) / 9.80665],
		breaks))
	# MUTATION: tie the footnote to the shared footer (hidden on the Lab dock) and the second half
	# fails; drop the sentence and the first half does.
	out.append(TestResult.new(
		"arm strength: the page footnote says impact is not modelled, gives no fall height, and stays on the dock",
		note.contains("Impact energy is not modelled") and note.contains("no fall height")
			and note.contains("does not say an arm survives a crash") and note_on_dock == note,
		"'%s' / dock '%s'" % [note, note_on_dock]))
	return out

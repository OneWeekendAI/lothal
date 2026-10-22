class_name TestStrapsPads
extends RefCounted
## Straps & pads — airframe gaps build plan, slice G1 (airframe.md §6). The pad as a spring
## (`PadMount`), strap slots as holes (`StrapSlots`), the row/page figures (`StrapsPads`), the sheet
## (`StrapsDetails`) and the drawing's straps mode.
##
## Where each check could pass while proving nothing, and what stops it:
##   - "a softer pad passes less above its corner" is a STRICT inequality between two real pads at a
##     frequency above both corners, AND between the two corners — so a transmissibility that ignored
##     f_n, a stiffness that ignored thickness, or a formula that returned 1 all fail it.
##   - every warning is asserted BOTH ways: it fires on the broken geometry, and is absent on the same
##     geometry with the fix — so a check that always fires fails as surely as one that never does.
##     (Each was also mutation-checked by deleting the check in src/: see the G1 report.)
##   - "the presets carry slots" asserts the reference build raises NO strap warning, beside the
##     test that the same plate without its slots raises one.
##   - the pad's lift and mass are asserted equal to Build's and BatteryPad's own numbers, not
##     recomputed here.
##   - sections are collected by name and an empty one fails loudly (a section that aborts mid-run
##     must not read as zero failures).


static func run() -> Array:
	var sections := {}
	sections["spring"] = _the_spring()
	sections["softer"] = _a_softer_pad_passes_less_above_its_corner()
	sections["tiers"] = _tiers_and_refusals()
	sections["pad warnings"] = _pad_warnings()
	sections["slot shape"] = _slots_are_found_by_shape()
	sections["presets"] = _presets_carry_slots_under_the_pack()
	sections["slot warnings"] = _slot_warnings()
	sections["row and page"] = _the_row_and_the_page()
	sections["sheet and drawing"] = _the_sheet_and_the_drawing()
	var out: Array = []
	for name in sections:
		var list: Array = sections[name]
		if list.is_empty():
			out.append(TestResult.new("straps & pads: section '%s' produced results" % name, false,
				"empty — it aborted"))
		out.append_array(list)
	return out


static func _materials() -> FrameMaterials:
	return FrameMaterials.load_default()


# ---------------------------------------------------------------------------
# PadMount
# ---------------------------------------------------------------------------

## k = E·A/t and f_n = √(k/m)/2π, written out by hand for a 40 × 30 mm, 2 mm TPU pad under 200 g.
static func _the_spring() -> Array:
	var out: Array = []
	var e := 0.03e9
	var k_hand := e * (40.0 * 30.0 * 1e-6) / 0.002
	var k := PadMount.stiffness_n_per_m(e, 1200.0, 2.0)
	out.append(TestResult.new("pad: stiffness is E·A/t (1200 mm², 2 mm, 0.03 GPa = 18 MN/m)",
		is_equal_approx(k, k_hand) and is_equal_approx(k, 1.8e7), "%.1f N/m" % k))
	var f_hand := sqrt(k_hand / 0.2) / TAU
	var f := PadMount.natural_frequency_hz(k, 0.2)
	out.append(TestResult.new("pad: natural frequency is √(k/m)/2π",
		is_equal_approx(f, f_hand), "%.2f Hz vs %.2f" % [f, f_hand]))
	var pad := PadMount.compute(_materials(), 1200.0, 2.0, 0.2)
	out.append(TestResult.new("pad: compute reads TPU 95A's modulus from materials.json",
		bool(pad["ok"]) and is_equal_approx(float(pad["modulus_pa"]), 0.03e9)
			and is_equal_approx(float(pad["f_n_hz"]), f_hand), str(pad.get("f_n_hz"))))
	out.append(TestResult.new("pad: the isolation corner is f_n·√2, where T = 1 for any damping",
		is_equal_approx(float(pad["onset_hz"]), f_hand * sqrt(2.0))
			and absf(PadMount.transmissibility(float(pad["onset_hz"]), f_hand, 0.05) - 1.0) < 1e-9
			and absf(PadMount.transmissibility(float(pad["onset_hz"]), f_hand, 0.3) - 1.0) < 1e-9,
		"%.2f Hz" % float(pad["onset_hz"])))
	return out


## THE SLICE'S HEADLINE CHECK. Same pack, same area: a 4 mm pad is softer than a 1 mm one (k ∝ 1/t).
static func _a_softer_pad_passes_less_above_its_corner() -> Array:
	var out: Array = []
	# A small contact (4 × 10 mm feet) so both corners land in the hundreds of hertz.
	var soft := PadMount.compute(_materials(), 40.0, 4.0, 0.185)
	var stiff := PadMount.compute(_materials(), 40.0, 1.0, 0.185)
	var f_soft := float(soft["f_n_hz"])
	var f_stiff := float(stiff["f_n_hz"])
	out.append(TestResult.new("softer pad: the thicker pad has the lower resonance (k ∝ 1/t)",
		f_soft < f_stiff and is_equal_approx(f_stiff / f_soft, 2.0), "%.1f vs %.1f Hz" % [f_soft, f_stiff]))
	# Above BOTH corners: both isolate, the softer one more.
	var high := float(stiff["onset_hz"]) * 3.0
	var t_soft := PadMount.transmissibility(high, f_soft)
	var t_stiff := PadMount.transmissibility(high, f_stiff)
	out.append(TestResult.new("softer pad: above both corners it passes strictly less vibration",
		t_soft < t_stiff and t_stiff < 1.0, "at %.0f Hz: soft %.4f, stiff %.4f" % [high, t_soft, t_stiff]))
	# Between the corners: the softer pad already isolates; the stiffer one still amplifies.
	var between := (float(soft["onset_hz"]) + float(stiff["onset_hz"])) * 0.5
	var b_soft := PadMount.transmissibility(between, f_soft)
	var b_stiff := PadMount.transmissibility(between, f_stiff)
	out.append(TestResult.new("softer pad: past its own corner it isolates where the stiffer pad amplifies",
		b_soft < 1.0 and b_stiff > 1.0, "at %.0f Hz: soft %.3f, stiff %.3f" % [between, b_soft, b_stiff]))
	# And at every frequency well above the soft corner, not one hand-picked point.
	var always := true
	var hz := float(soft["onset_hz"]) * 1.05
	while hz < float(stiff["onset_hz"]) * 10.0:
		always = always and PadMount.transmissibility(hz, f_soft) < PadMount.transmissibility(hz, f_stiff)
		hz *= 1.1
	out.append(TestResult.new("softer pad: less vibration at every frequency swept above its corner",
		always, ""))
	return out


static func _tiers_and_refusals() -> Array:
	var out: Array = []
	var pad := PadMount.compute(_materials(), 1200.0, 2.0, 0.2)
	var tiers: Dictionary = pad["tiers"]
	out.append(TestResult.new("pad tiers: the spring is characteristic, the geometry exact, damping a guess (§8)",
		tiers["f_n_hz"] == "characteristic" and tiers["stiffness_n_m"] == "characteristic"
			and tiers["transmissibility"] == "characteristic" and tiers["area_mm2"] == "exact"
			and tiers["zeta"] == "guess" and is_equal_approx(float(pad["zeta"]), SoftMount.DEFAULT_DAMPING_RATIO),
		str(tiers)))
	out.append(TestResult.new("pad: a material with no modulus is refused by name",
		not bool(PadMount.compute(_materials(), 1200.0, 2.0, 0.2, "no_such_material")["ok"]), ""))
	out.append(TestResult.new("pad: no area, no thickness or no load is refused",
		not bool(PadMount.compute(_materials(), 0.0, 2.0, 0.2)["ok"])
			and not bool(PadMount.compute(_materials(), 1200.0, 0.0, 0.2)["ok"])
			and not bool(PadMount.compute(_materials(), 1200.0, 2.0, 0.0)["ok"]), ""))
	out.append(TestResult.new("pad: a refused pad raises no warning",
		PadMount.warnings(PadMount.compute(_materials(), 0.0, 2.0, 0.2), 180.0).is_empty(), ""))
	return out


static func _ids(list: Array) -> Array:
	var out: Array = []
	for w in list:
		out.append(String((w as BuildWarning).id))
	return out


## Each pad warning, broken and fixed.
static func _pad_warnings() -> Array:
	var out: Array = []
	# Three 3 mm² feet, 5 mm thick, under a 185 g pack: f_n ≈ 86 Hz — inside the loop.
	var mushy := PadMount.compute(_materials(), 9.0, 5.0, 0.185)
	var firm := PadMount.compute(_materials(), 2400.0, 2.0, 0.185)
	out.append(TestResult.new("pad warning: a mount resonating under 100 Hz is flagged too soft",
		float(mushy["f_n_hz"]) < 100.0 and _ids(PadMount.warnings(mushy, 180.0)).has("pad_too_soft"),
		"f_n %.1f Hz, %s" % [float(mushy["f_n_hz"]), _ids(PadMount.warnings(mushy, 180.0))]))
	out.append(TestResult.new("pad warning: the full-footprint pad is not flagged too soft",
		not _ids(PadMount.warnings(firm, 180.0)).has("pad_too_soft"), str(_ids(PadMount.warnings(firm, 180.0)))))
	var mushy_list := PadMount.warnings(mushy, 180.0)
	var too_soft: BuildWarning = mushy_list[0] if not mushy_list.is_empty() \
		else BuildWarning.characteristic(&"none", "")
	out.append(TestResult.new("pad warning: too-soft is limiting, on the Straps & pads row, with a short",
		too_soft.severity == BuildWarning.Severity.LIMITING and too_soft.item == &"straps"
			and too_soft.short == "pad resonance ~%d Hz, in the loop" % roundi(float(mushy["f_n_hz"])),
		too_soft.short))
	# The frame rings at 180 Hz. A full-footprint slab's corner is in the kHz: it passes the ring.
	var passes := PadMount.warnings(firm, 180.0)
	out.append(TestResult.new("pad warning: a pad whose corner is above the frame mode says it passes the ring",
		_ids(passes).has("pad_passes_frame_mode") and float((passes[0] as BuildWarning).values["transmissibility"]) >= 1.0
			and (passes[0] as BuildWarning).severity == BuildWarning.Severity.CHARACTERISTIC, str(_ids(passes))))
	# A pad soft enough that 180 Hz is above its corner (but not inside the loop): no warning at all.
	# 13 mm² at 4 mm: f_n ≈ 115 Hz (out of the loop), corner ≈ 163 Hz (below the 180 Hz mode).
	var isolator := PadMount.compute(_materials(), 13.0, 4.0, 0.185)
	var clean := PadMount.warnings(isolator, 180.0)
	out.append(TestResult.new("pad warning: a pad isolating at the frame mode, above 100 Hz, raises nothing",
		float(isolator["f_n_hz"]) > 100.0 and float(isolator["onset_hz"]) < 180.0 and clean.is_empty(),
		"f_n %.1f, onset %.1f, %s" % [float(isolator["f_n_hz"]), float(isolator["onset_hz"]), _ids(clean)]))
	return out


# ---------------------------------------------------------------------------
# StrapSlots
# ---------------------------------------------------------------------------

static func _slots_are_found_by_shape() -> Array:
	var out: Array = []
	var slot := StrapSlots.make_slot(Vector2(5.0, -3.0), 22.0, 3.5, deg_to_rad(30.0))
	var shape := StrapSlots.measure(slot)
	out.append(TestResult.new("slots: a 22 × 3.5 mm slot at 30° measures 22 × 3.5 along its own axis",
		bool(shape["is_slot"]) and is_equal_approx(float(shape["length_mm"]), 22.0)
			and is_equal_approx(float(shape["width_mm"]), 3.5)
			and (shape["centre"] as Vector2).is_equal_approx(Vector2(5.0, -3.0))
			and absf(absf((shape["axis"] as Vector2).dot(Vector2.from_angle(deg_to_rad(30.0)))) - 1.0) < 1e-6,
		str(shape)))
	var bolt := StrapSlots.measure(PolygonProps.tessellate_circle(Vector2.ZERO, 1.6, 0.1, true))
	var lightening := StrapSlots.measure(PolygonProps.tessellate_circle(Vector2.ZERO, 8.0, 0.1, true))
	out.append(TestResult.new("slots: a bolt hole and a round lightening hole are not slots",
		not bool(bolt["is_slot"]) and not bool(lightening["is_slot"]), ""))
	# A slot is a hole: it subtracts from the plate the mass integrals see.
	var square := PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	var with_slot := PolygonProps.region_properties(square, [slot])
	out.append(TestResult.new("slots: a slot subtracts its own area from the plate (it is wound as a hole)",
		# 1e-3: the 30° corners are Vector2 (single precision), the §3.1 float32 floor.
		absf(float(with_slot["area"]) - (1600.0 - 22.0 * 3.5)) < 1e-3, str(with_slot["area"])))
	return out


## A document whose top plate carries exactly `holes` (plus nothing else), for the warning fixtures.
static func _with_top_holes(holes: Array) -> AirframeDocument:
	var document := AirframeDocument.from_catalog_frame(ReferenceBuild.build().frame)
	for plate in document.plates:
		if str(plate.get("role", "")) == AirframeDocument.ROLE_TOP:
			var flat: Array = []
			for hole in holes:
				flat.append(AirframeDocument.flatten(hole))
			plate["holes"] = flat
	return document


const PACK := Rect2(-17.5, -37.5, 35.0, 75.0)


static func _presets_carry_slots_under_the_pack() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var document := AirframeDocument.from_catalog_frame(build.frame)
	var top := StrapSlots.seat_plate(document, "strap_top")
	var found := StrapSlots.slots(top)
	out.append(TestResult.new("presets: the generated top plate has two 22 × 3.5 mm strap slots",
		found.size() == 2 and is_equal_approx(float(found[0]["length_mm"]), 22.0), str(found.size())))
	var rect := StrapsPads.pack_rect_mm(build)
	out.append(TestResult.new("presets: the pack footprint is Build's seat and size (35 × 75 mm, centred)",
		rect.is_equal_approx(PACK), str(rect)))
	out.append(TestResult.new("presets: the reference build raises no strap or pad warning",
		StrapsPads.warnings(build, document).is_empty(), str(_ids(StrapsPads.warnings(build, document)))))
	var bottom := StrapSlots.seat_plate(document, "strap_bottom")
	out.append(TestResult.new("presets: the bottom plate stays uncut, so the stack has its plate",
		not bottom.is_empty() and StrapSlots.slots(bottom).is_empty(), ""))
	var layout := FrameLayouts.build("quad_x")
	out.append(TestResult.new("presets: a FrameLayouts template's top plate gets the same slots",
		StrapSlots.slots(StrapSlots.seat_plate(layout, "strap_top")).size() == 2, ""))
	return out


## Each slot warning, broken and fixed — the same plate, the same pack, one change.
static func _slot_warnings() -> Array:
	var out: Array = []
	var good := [StrapSlots.make_slot(Vector2(0, -10), 22.0, 3.5), StrapSlots.make_slot(Vector2(0, 10), 22.0, 3.5)]
	var fixed := StrapSlots.warnings(_with_top_holes(good), "strap_top", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: two 22 mm slots under the pack, a 20 mm strap: none",
		fixed.is_empty(), str(_ids(fixed))))

	var none := StrapSlots.warnings(_with_top_holes([]), "strap_top", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: a top plate with no slots says so",
		_ids(none) == ["no_strap_slots"] and (none[0] as BuildWarning).item == &"straps"
			and (none[0] as BuildWarning).severity == BuildWarning.Severity.LIMITING, str(_ids(none))))
	# A round hole is not a slot: a plate of bolt holes still has no slots.
	var bolts := StrapSlots.warnings(_with_top_holes([PolygonProps.tessellate_circle(Vector2(0, 10), 1.6, 0.1, true)]),
		"strap_top", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: a plate with only bolt holes has no strap slots",
		_ids(bolts) == ["no_strap_slots"], str(_ids(bolts))))

	var short := [StrapSlots.make_slot(Vector2(0, -10), 15.0, 3.5), StrapSlots.make_slot(Vector2(0, 10), 22.0, 3.5)]
	var narrow := StrapSlots.warnings(_with_top_holes(short), "strap_top", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: a 15 mm slot for a 20 mm strap is flagged, short form",
		_ids(narrow) == ["strap_slot_narrow"]
			and (narrow[0] as BuildWarning).short == "slot 15 mm, strap needs 21 mm", str(_ids(narrow))))
	var thin := StrapSlots.warnings(_with_top_holes([StrapSlots.make_slot(Vector2(0, -10), 22.0, 2.5),
		StrapSlots.make_slot(Vector2(0, 10), 22.0, 3.5)]), "strap_top", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: a 2.5 mm-wide slot for a 2 mm strap is flagged (needs 3)",
		_ids(thin) == ["strap_slot_narrow"], str(_ids(thin))))
	# The same 15 mm slot passes a 12 mm strap: the check is against the strap, not a fixed size.
	var small_strap := StrapSlots.warnings(_with_top_holes(short), "strap_top", PACK, 12.0, 2.0)
	out.append(TestResult.new("slot warnings: the 15 mm slot passes a 12 mm strap",
		small_strap.is_empty(), str(_ids(small_strap))))

	var astray := [StrapSlots.make_slot(Vector2(0, -10), 22.0, 3.5), StrapSlots.make_slot(Vector2(0, 45), 22.0, 3.5)]
	var off := StrapSlots.warnings(_with_top_holes(astray), "strap_top", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: a slot 45 mm aft, past a 75 mm pack's end, is not under it",
		_ids(off) == ["strap_slot_off_pack"] and int((off[0] as BuildWarning).values["off"]) == 1,
		str(_ids(off))))
	# Slide the pack aft over that slot and the same plate passes.
	var slid := StrapSlots.warnings(_with_top_holes(astray), "strap_top", Rect2(-17.5, -20.0, 35.0, 75.0), 20.0, 2.0)
	out.append(TestResult.new("slot warnings: slide the pack over the slot and it is under the pack again",
		slid.is_empty(), str(_ids(slid))))

	var moulded := AirframeDocument.new()
	out.append(TestResult.new("slot warnings: a frame with no plate to cut (moulded) is not told to cut one",
		StrapSlots.warnings(moulded, "strap_top", PACK, 20.0, 2.0).is_empty(), ""))
	# A pack on the bottom mount is checked against the bottom plate, which the preset leaves uncut.
	var under := StrapSlots.warnings(_with_top_holes(good), "strap_bottom", PACK, 20.0, 2.0)
	out.append(TestResult.new("slot warnings: a bottom-mounted pack is checked against the bottom plate",
		_ids(under) == ["no_strap_slots"] and str((under[0] as BuildWarning).values["plate"]) == "bottom",
		str(_ids(under))))
	return out


# ---------------------------------------------------------------------------
# The row, the page, the sheet, the drawing
# ---------------------------------------------------------------------------

static func _fitted(thickness_mm: float = 2.0) -> Build:
	var build := ReferenceBuild.build()
	var printing := {}
	BatteryPad.set_value(printing, BatteryPad.FITTED, true)
	BatteryPad.set_value(printing, BatteryPad.THICKNESS, thickness_mm)
	build.set_printing(printing)
	return build


static func _the_row_and_the_page() -> Array:
	var out: Array = []
	var build := ReferenceBuild.build()
	var row: Dictionary = {}
	for r in SectionRows.rows("Airframe", build, []):
		if r["id"] == &"straps":
			row = r
	out.append(TestResult.new("straps row: live (not soon), green, names the strap and no pad",
		not bool(row.get("soon", false)) and row.get("status") == SectionRows.OK
			and row.get("choice") == "no pad · 20 mm strap (guess)"
			and row.get("line3") == "2 strap slots under the pack", "%s / %s / %s" % [row.get("choice"),
				row.get("line3"), row.get("status")]))
	out.append(TestResult.new("straps row: its page is the Straps sheet beside the straps drawing",
		row.get("page") == {"panels": ["Straps"], "diagram": "straps"}, str(row.get("page"))))

	var fitted := _fitted()
	var f := StrapsPads.figures(fitted, AirframeDocument.from_catalog_frame(fitted.frame))
	var pad: Dictionary = f["pad"]
	out.append(TestResult.new("straps row: a fitted pad's line 3 is PadMount's isolation corner, with its ~",
		SectionRows.number_of(&"straps", fitted) == "~%d Hz pad isolation corner" % roundi(float(pad["onset_hz"])),
		SectionRows.number_of(&"straps", fitted)))
	var dims := BatteryPad.dimensions(fitted.battery, fitted.printing)
	out.append(TestResult.new("straps figures: the pad's lift and mass are Build's and BatteryPad's (PR17, PR11)",
		is_equal_approx(float(f["lift_mm"]), fitted.battery_rise_m() * 1000.0)
			and is_equal_approx(float(f["lift_mm"]), 2.0)
			and is_equal_approx(float(f["pad_mass_g"]), BatteryPad.mass_kg(dims) * 1000.0),
		"%.2f mm, %.2f g" % [float(f["lift_mm"]), float(f["pad_mass_g"])]))
	out.append(TestResult.new("straps figures: the pad carries the pack's own published mass",
		is_equal_approx(float(pad["load_kg"]), float(fitted.battery["mass_g"]) / 1000.0), str(pad["load_kg"])))
	out.append(TestResult.new("straps figures: the loaded area is the footprint less the pad's two slots",
		is_equal_approx(float(pad["area_mm2"]), float(dims["battery_length_mm"]) * float(dims["battery_width_mm"])
			- 2.0 * float(dims["slot_open_mm"]) * minf(float(dims["slot_across_mm"]), float(dims["battery_width_mm"]))),
		str(pad["area_mm2"])))
	out.append(TestResult.new("straps figures: the frame mode is VibrationModel's, the one the Arms row quotes",
		is_equal_approx(float(f["frame_mode_hz"]), VibrationModel.for_build(fitted).resonance_hz), ""))
	# A thicker pad is a softer spring: the corner the row quotes comes down.
	var thick := StrapsPads.figures(_fitted(4.0), AirframeDocument.from_catalog_frame(fitted.frame))
	out.append(TestResult.new("straps figures: a 4 mm pad's corner is 1/√2 of a 2 mm pad's",
		is_equal_approx(float(thick["pad"]["onset_hz"]) * sqrt(2.0), float(pad["onset_hz"])),
		"%.0f vs %.0f" % [float(thick["pad"]["onset_hz"]), float(pad["onset_hz"])]))
	var numbers := SectionRows.page_numbers(&"straps", fitted)
	out.append(TestResult.new("straps page: the two numbers are the corner against the frame, and the slots",
		numbers == [["Pad isolates above", "~%d Hz · frame ~%d Hz" % [roundi(float(pad["onset_hz"])),
			roundi(float(f["frame_mode_hz"]))]], ["Strap slots", "2 of 2 under the pack"]], str(numbers)))
	# The fitted pad's own warning reaches the row's list, owned by the row.
	var warned: Dictionary = {}
	for r in SectionRows.rows("Airframe", fitted, f["warnings"]):
		if r["id"] == &"straps":
			warned = r
	out.append(TestResult.new("straps row: the fitted slab's 'passes the ring' is on its page, row still green",
		(warned["warnings"] as Array).size() == 1 and warned["status"] == SectionRows.OK
			and ((warned["warnings"] as Array)[0] as BuildWarning).id == PadMount.PAD_PASSES_FRAME_MODE,
		str(warned["status"])))
	var no_slots := _with_top_holes([])
	var amber: Dictionary = {}
	for r in SectionRows.rows("Airframe", build, StrapsPads.warnings(build, no_slots), {"frame_document": no_slots}):
		if r["id"] == &"straps":
			amber = r
	out.append(TestResult.new("straps row: a top plate with no slots turns the row amber with the short",
		amber["status"] == SectionRows.WARN and amber["line3"] == "⚠ no strap slots in the plate",
		"%s / %s" % [amber["status"], amber["line3"]]))
	return out


static func _the_sheet_and_the_drawing() -> Array:
	var out: Array = []
	var fitted := _fitted()
	var document := AirframeDocument.from_catalog_frame(fitted.frame)
	var f := StrapsPads.figures(fitted, document)
	var sheet := StrapsDetails.new()
	sheet.render_straps(document, f)
	out.append(TestResult.new("straps sheet: the resonance carries its characteristic tier",
		sheet.row_text("resonance") == "~%d Hz  (characteristic)" % roundi(float(f["pad"]["f_n_hz"])),
		sheet.row_text("resonance")))
	out.append(TestResult.new("straps sheet: the damping ratio is labelled a guess",
		sheet.row_text("damping") == "0.10  (guess)", sheet.row_text("damping")))
	out.append(TestResult.new("straps sheet: the slots row says count, size and how many are under the pack",
		sheet.row_text("slots") == "2 · 22.0 × 3.5 mm · 2 under the pack", sheet.row_text("slots")))
	out.append(TestResult.new("straps sheet: the frame-mode row says the pad passes it through",
		sheet.row_text("frame_mode").contains("passes it through"), sheet.row_text("frame_mode")))
	var unfitted := ReferenceBuild.build()
	sheet.render_straps(document, StrapsPads.figures(unfitted, document))
	out.append(TestResult.new("straps sheet: with no pad fitted the pad rows dash and say where to fit one",
		sheet.row_text("resonance") == "—" and sheet.row_text("pad").begins_with("— not fitted")
			and sheet.row_text("checks") == "all pass", sheet.row_text("pad")))
	sheet.free()

	var short := _with_top_holes([StrapSlots.make_slot(Vector2(0, -10), 15.0, 3.5),
		StrapSlots.make_slot(Vector2(0, 10), 22.0, 3.5)])
	var diagram := FramePlanDiagram.new()
	diagram.show_plan(short, FramePlanDiagram.MODE_STRAPS,
		FramePlanDiagram.straps_extras(StrapsPads.figures(unfitted, short)))
	out.append(TestResult.new("straps drawing: rings exactly the slot the narrow check flags",
		diagram.slots.size() == 2 and diagram.flagged_slots.size() == 1
			and is_equal_approx(float(diagram.flagged_slots[0]["length_mm"]), 15.0)
			and diagram.pack_rect.is_equal_approx(PACK), "%d flagged" % diagram.flagged_slots.size()))
	diagram.show_plan(document, FramePlanDiagram.MODE_STRAPS,
		FramePlanDiagram.straps_extras(StrapsPads.figures(unfitted, document)))
	out.append(TestResult.new("straps drawing: the preset's slots are drawn and none is ringed",
		diagram.slots.size() == 2 and diagram.flagged_slots.is_empty(), ""))
	diagram.free()
	return out

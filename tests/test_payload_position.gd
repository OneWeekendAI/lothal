class_name TestPayloadPosition
extends RefCounted
## The payload's fore-aft seat (PayloadPart "fore_mm", Build.payload_fore_m): one slider in the Design Space payload
## panel moves the box along the frame's centreline, and the centre of mass, the inertia tensor, the flown core and the
## drawn box all follow. POSITIVE is toward the NOSE (-Z).
##
## Every expectation below is derived by hand in this file (the centre-of-mass shift m*d/M, the parallel-axis term
## m*(|r|^2 E - r r^T)) from the mass, the displacement and the BASE build's own tensor, never from mass_parts() of the
## moved build, so a Build that ignored the offset cannot agree with them.
##
## MUTATIONS (each run once by hand, see the report): drop the fore term from payload_attach_m; flip its sign;
## drop the clamp; skip the PayloadPart.resolve read; always write fore_mm in to_saved; draw the node without the
## offset; make the slider commit nothing.

## Vector3 and Basis hold single floats in this build, so a position near 0.05 m is good to ~5e-9 and a tensor entry to
## ~1e-7 of itself. These bounds sit a hundred times under the smallest effect any check below looks for.
const POS_TOL := 5.0e-8
const REL_TOL := 4.0e-7
const MASS_G := 250.0
const SIZE := [80.0, 70.0, 60.0]   # length (fore-aft), width, height, mm


static func _t(name: String, ok: bool, detail: String) -> TestResult:
	return TestResult.new(name, ok, detail)


static func _with_fore(fore_mm: Variant, base_arm_build: Build = null) -> Build:
	var b: Build = base_arm_build if base_arm_build != null else ReferenceBuild.build()
	var saved := {"kind": "payload_custom", "mass_g": MASS_G, "size_mm": SIZE}
	if fore_mm != null:
		saved["fore_mm"] = fore_mm
	b.set_payload_part(saved)
	return b


## m (|r|^2 E - r r^T) for a point mass, as a Basis, written out entry by entry.
static func _parallel(m: float, r: Vector3) -> Basis:
	var s := r.length_squared()
	return Basis(
		Vector3(m * (s - r.x * r.x), -m * r.x * r.y, -m * r.x * r.z),
		Vector3(-m * r.y * r.x, m * (s - r.y * r.y), -m * r.y * r.z),
		Vector3(-m * r.z * r.x, -m * r.z * r.y, m * (s - r.z * r.z)))


## What the user's drag or key press does to an HSlider: the value changes and value_changed fires (a headless
## slider outside the tree does not emit for a scripted `value =`).
static func _move(slider: HSlider, v: float) -> void:
	slider.set_value_no_signal(v)
	slider.value_changed.emit(v)


static func _sub(a: Basis, b: Basis) -> Basis:
	return Basis(a.x - b.x, a.y - b.y, a.z - b.z)


static func _add(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)


static func _max_abs_diff(a: Basis, b: Basis) -> float:
	var d := _sub(a, b)
	var m := 0.0
	for v in [d.x, d.y, d.z]:
		m = maxf(m, maxf(absf(v.x), maxf(absf(v.y), absf(v.z))))
	return m


static func run() -> Array:
	var out: Array = []
	var catalog := PartsCatalog.load_default()
	out.append_array(_resolve_and_save())
	out.append_array(_default_seat())
	out.append_array(_mass_and_inertia())
	out.append_array(_limits(catalog))
	out.append_array(_flight_model())
	out.append_array(_panel_and_drawing(catalog))
	out.append_array(_persistence(catalog))
	return out


# ---------------------------------------------------------------------------
static func _resolve_and_save() -> Array:
	var out: Array = []
	out.append(_t("a payload with no fore key resolves to 0 mm (every file written before this)",
		PayloadPart.resolve({"kind": "payload_custom"})["fore_mm"] == 0.0, ""))
	out.append(_t("a saved fore figure is read back, signed",
		PayloadPart.resolve({"kind": "payload_custom", "fore_mm": 35.0})["fore_mm"] == 35.0
		and PayloadPart.resolve({"kind": "payload_custom", "fore_mm": -12.5})["fore_mm"] == -12.5, ""))
	out.append(_t("a corrupt fore figure is held to the sanity bound; a non-number is ignored",
		PayloadPart.resolve({"kind": "payload_custom", "fore_mm": 1.0e9})["fore_mm"] == PayloadPart.MAX_FORE_MM
		and PayloadPart.resolve({"kind": "payload_custom", "fore_mm": "far"})["fore_mm"] == 0.0, ""))
	var kind_only := PayloadPart.to_saved("payload_winch", 400.0, 100.0, 70.0, 60.0, 0.0)
	var with_fore := PayloadPart.to_saved("payload_winch", 400.0, 100.0, 70.0, 60.0, 25.0)
	out.append(_t("a payload on the default seat saves with no fore key (sparse, as before); off it, the figure is written",
		not kind_only.has("fore_mm") and with_fore.get("fore_mm", null) == 25.0, str(kind_only) + str(with_fore)))
	return out


# ---------------------------------------------------------------------------
static func _default_seat() -> Array:
	var out: Array = []
	var absent := _with_fore(null)
	var zero := _with_fore(0.0)
	var c := absent.thrust_centroid_xz_m()
	var size := Vector3(SIZE[1], SIZE[2], SIZE[0]) / 1000.0
	var want := Vector3(c.x, absent.lowest_body_y_m() - PayloadPart.MOUNT_GAP_M["plate"] - size.y * 0.5, c.y)
	# The catalog entry's own mount decides the gap; read it the way the part does rather than assume "plate".
	var gap := PayloadPart.mount_gap_m(absent.payload_part)
	want.y = absent.lowest_body_y_m() - gap - size.y * 0.5
	out.append(_t("DEFAULT: with no fore key the box centre is exactly the thrust-centroid seat of today (bit-for-bit)",
		absent.payload_centre_m() == want and absent.payload_attach_m() == Vector3(c.x, absent.lowest_body_y_m(), c.y), str(absent.payload_centre_m()) + " vs " + str(want)))
	out.append(_t("DEFAULT: fore_mm 0 is the same seat, the same mass properties, bit-for-bit",
		zero.payload_centre_m() == absent.payload_centre_m() and var_to_str(zero.mass_properties.com_m) == var_to_str(absent.mass_properties.com_m)
		and zero.mass_properties.inertia == absent.mass_properties.inertia, ""))
	out.append(_t("a build with no payload reports a zero slide and zero range", ReferenceBuild.build().payload_fore_m() == 0.0 and ReferenceBuild.build().payload_fore_limit_m() == 0.0, ""))
	return out


# ---------------------------------------------------------------------------
static func _mass_and_inertia() -> Array:
	var out: Array = []
	var m := MASS_G / 1000.0
	for fore_mm: float in [30.0, -30.0, 10.0]:
		var d := fore_mm / 1000.0
		var b0 := _with_fore(null)
		var b1 := _with_fore(fore_mm)
		var M := b0.mass_properties.total_mass_kg
		var c0 := b0.mass_properties.com_m
		var c1 := b1.mass_properties.com_m
		var dz := c1.z - c0.z
		out.append(_t("fore %+.0f mm: total mass is unchanged by the move" % fore_mm,
			absf(b1.mass_properties.total_mass_kg - M) < POS_TOL, ""))
		# Nose is -Z: a payload moved d forward moves the CG by -m*d/M in Z, and by nothing in X or Y.
		out.append(_t("fore %+.0f mm: the CG moves by exactly -m*d/M = %.6f mm in Z and not at all in X or Y" % [fore_mm, -m * d / M * 1000.0],
			absf(dz - (-m * d / M)) < POS_TOL and absf(c1.x - c0.x) < POS_TOL and absf(c1.y - c0.y) < POS_TOL, "dz %.9f vs %.9f, d %s" % [dz, -m * d / M, str(c1 - c0)]))
		# Inertia about the CG, by hand: undo the base CG shift, swap the payload's parallel-axis term, redo the new CG shift.
		var p0 := b0.payload_centre_m()
		var p1 := b1.payload_centre_m()
		var i_o0 := _add(b0.mass_properties.inertia, _parallel(M, c0))
		var i_o1 := _add(_sub(i_o0, _parallel(m, p0)), _parallel(m, p1))
		var want := _sub(i_o1, _parallel(M, c1))
		var err := _max_abs_diff(b1.mass_properties.inertia, want)
		var scale := b1.mass_properties.inertia.x.x
		out.append(_t("fore %+.0f mm: the inertia tensor equals the hand parallel-axis result (max entry error %s of %s)" % [fore_mm, str(err), str(scale)],
			err < REL_TOL * scale, ""))
		var dp := p1 - p0
		out.append(_t("fore %+.0f mm: the box centre moved by exactly -d in Z and nowhere else" % fore_mm,
			absf(dp.z - (-d)) < POS_TOL and dp.x == 0.0 and dp.y == 0.0, str(dp.z + d)))
		# The pitch inertia about the CG goes by the parallel-axis amount for the payload alone, to first order the Iyy of
		# the tensor is rotation about Y (yaw) and Ixx about X (pitch): both are checked through the tensor above; here the
		# named figures too.
		out.append(_t("fore %+.0f mm: Ixx (pitch) and Izz (roll) in the build agree with the hand tensor" % fore_mm,
			absf(b1.mass_properties.inertia.x.x - want.x.x) < REL_TOL * scale and absf(b1.mass_properties.inertia.z.z - want.z.z) < REL_TOL * scale, ""))
	var b := _with_fore(40.0)
	out.append(_t("the slide is a real change: the pitch inertia differs from the centred payload's",
		absf(b.mass_properties.inertia.x.x - _with_fore(null).mass_properties.inertia.x.x) > 1e-7, ""))
	return out


# ---------------------------------------------------------------------------
static func _limits(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var b := _with_fore(null)
	var half_span := b.arm_m * 0.70710678118654752
	var want_lim := half_span - SIZE[0] / 2000.0
	out.append(_t("the range is the front motor's |z| (arm x cos 45) less half the box length: %.4f m" % want_lim,
		absf(b.payload_fore_limit_m() - want_lim) < POS_TOL, "%.9f" % b.payload_fore_limit_m()))
	var far := _with_fore(5000.0)
	var back := _with_fore(-5000.0)
	out.append(_t("a figure past the frame is held to the limit, both ways, and the box ends flush with the front/rear motor line",
		absf(far.payload_fore_m() - want_lim) < POS_TOL and absf(back.payload_fore_m() + want_lim) < POS_TOL
		and absf((far.thrust_centroid_xz_m().y - far.payload_centre_m().z) - want_lim) < POS_TOL
		and absf((far.payload_centre_m().z - SIZE[0] / 2000.0) - (-half_span)) < POS_TOL, "%.6f" % far.payload_fore_m()))
	out.append(_t("inside the range the figure is applied unclamped", absf(_with_fore(20.0).payload_fore_m() - 0.020) < POS_TOL, ""))
	# A box as long as the span cannot slide; a longer box is held at zero, never negative range.
	var long_box := ReferenceBuild.build()
	long_box.set_payload_part({"kind": "payload_custom", "mass_g": 100.0, "size_mm": [900.0, 70.0, 60.0], "fore_mm": 50.0})
	out.append(_t("a box longer than the frame cannot slide at all", long_box.payload_fore_limit_m() == 0.0 and long_box.payload_fore_m() == 0.0, ""))
	# Another frame, another range: it is the frame's, not a constant.
	var limits := {}
	for f in catalog.list_category("frame"):
		var p := DroneClass.starting_project("five_inch", "t")
		p.parts["frame"] = String((f as Dictionary)["part_id"])
		p.payload = {"kind": "payload_custom", "mass_g": 100.0, "size_mm": [40.0, 40.0, 40.0]}
		var bb := p.to_build(catalog)
		if bb != null:
			limits[snappedf(bb.payload_fore_limit_m(), 1e-6)] = true
			var expect_lim := bb.arm_m * 0.70710678118654752 - 0.020
			if absf(bb.payload_fore_limit_m() - maxf(0.0, expect_lim)) > POS_TOL:
				limits["bad"] = true
	out.append(_t("across every catalog frame the range is arm-derived (several distinct values, each matching the formula)",
		limits.size() > 2 and not limits.has("bad"), str(limits.keys())))
	return out


# ---------------------------------------------------------------------------
static func _flight_model() -> Array:
	var out: Array = []
	var base := _with_fore(null)
	var fore := _with_fore(60.0)
	var aft := _with_fore(-60.0)
	var core := fore.build_drone_core()
	out.append(_t("the flown core carries the moved CG and tensor (it is handed Build.mass_properties, not a fixed lump)",
		core.mass_properties.com_m == fore.mass_properties.com_m and core.mass_properties.inertia == fore.mass_properties.inertia
		and core.mass_properties.com_m != base.mass_properties.com_m, ""))
	# Hover pitch torque is weight * com_z (each motor carries a quarter of the weight at its arm from the CG;
	# the motors average to z = 0): a nose-heavy aircraft reads negative.
	for pair in [[fore, "forward"], [aft, "aft"]]:
		var bb := pair[0] as Build
		var want := bb.weight_n() * bb.mass_properties.com_m.z
		out.append(_t("hover pitch trim torque of the %s payload = weight x CG z (%.5f N m)" % [pair[1], want],
			absf(bb.hover_pitch_trim_nm() - want) < 1e-6, "%.9f" % bb.hover_pitch_trim_nm()))
	out.append(_t("forward is more nose-heavy than centred, which is more than aft (trim torque ordering)",
		fore.hover_pitch_trim_nm() < base.hover_pitch_trim_nm() and base.hover_pitch_trim_nm() < aft.hover_pitch_trim_nm(), ""))
	# And the stepped sim: equal motor commands, free body; the pitch rate it picks up has the sign of the trim torque.
	var rates := {}
	for pair in [["fore", fore], ["base", base], ["aft", aft]]:
		var c := (pair[1] as Build).build_drone_core()
		c.ground_contact_enabled = false
		for i in 50:
			c.step({"M1": 0.5, "M2": 0.5, "M3": 0.5, "M4": 0.5}, 0.001)
		rates[pair[0]] = c.rigid_body.angular_velocity_rad_s.x
	out.append(_t("stepped through the real core, equal throttle: the pitch rate orders fore < base < aft",
		rates["fore"] < rates["base"] and rates["base"] < rates["aft"], str(rates)))
	return out


# ---------------------------------------------------------------------------
static func _panel_and_drawing(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var ds := DesignSpace.new(DesignSession.default_for_class("five_inch"), catalog)
	var pp := ds.payload_panel
	ds.session.set_payload({"kind": "payload_custom", "mass_g": MASS_G, "size_mm": SIZE})
	var b0 := ds.session.build(catalog)
	var lim_mm := floorf(b0.payload_fore_limit_m() * 1000.0 + 1e-6)
	out.append(_t("the panel has the position slider, shown with a payload, centred (0 mm), spanning the frame's own range",
		pp.fore_slider != null and pp.fore_slider.visible and pp._detail.visible and pp.fore_slider.value == 0.0
		and pp.fore_slider.slider.max_value == lim_mm and pp.fore_slider.slider.min_value == -lim_mm and lim_mm > 10.0,
		"%s..%s of %s" % [pp.fore_slider.slider.min_value, pp.fore_slider.slider.max_value, lim_mm]))
	var node0 := ds._payload_node
	var pos0 := node0.position
	var com0 := b0.mass_properties.com_m
	_move(pp.fore_slider.slider, 30.0)
	var saved := ds.session.payload()
	out.append(_t("moving the slider writes fore_mm into the design as one step", saved.get("fore_mm", null) == 30.0 and ds.session.can_undo(), str(saved)))
	var b1 := ds.session.build(catalog)
	var M := b1.mass_properties.total_mass_kg
	out.append(_t("the session's build moved its CG by -m*d/M", absf((b1.mass_properties.com_m.z - com0.z) - (-(MASS_G / 1000.0) * 0.030 / M)) < POS_TOL, ""))
	var node1 := ds._payload_node
	out.append(_t("the box is drawn 30 mm toward the nose of where it was (nose is -Z), same X and height",
		node1 != null and absf((node1.position.z - pos0.z) - (-0.030)) < POS_TOL and absf(node1.position.x - pos0.x) < POS_TOL
		and absf(node1.position.y - pos0.y) < POS_TOL, "%s vs %s" % [str(node1.position) if node1 != null else "none", str(pos0)]))
	# The readout line reads the moved build, and the label follows the slider.
	out.append(_t("the slider reads back what the design holds after a refresh", pp.fore_slider.value == 30.0 and pp.fore_slider.value_label.text.begins_with("30"), pp.fore_slider.value_label.text))
	# A drag is one undo step, not one per millimetre.
	pp.fore_slider.slider.drag_started.emit()
	_move(pp.fore_slider.slider, 31.0)
	_move(pp.fore_slider.slider, 32.0)
	_move(pp.fore_slider.slider, 33.0)
	out.append(_t("mid-drag nothing is committed", ds.session.payload().get("fore_mm", null) == 30.0, str(ds.session.payload())))
	pp.fore_slider.slider.drag_ended.emit(true)
	out.append(_t("releasing commits the final figure once", ds.session.payload().get("fore_mm", null) == 33.0, str(ds.session.payload())))
	ds.session.undo()
	out.append(_t("one undo takes the whole drag back to 30 mm", ds.session.payload().get("fore_mm", null) == 30.0 and pp.fore_slider.value == 30.0, str(ds.session.payload())))
	# Changing the mass keeps the position; changing the kind starts from the kind's own seat.
	pp.mass_stepper.value = 300.0
	pp._on_edit()
	out.append(_t("editing the mass keeps the slid position", ds.session.payload().get("fore_mm", null) == 30.0 and ds.session.payload().get("mass_g", null) == 300.0, str(ds.session.payload())))
	var idx := 1
	pp.kind_option.select(idx)
	pp._on_kind(idx)
	out.append(_t("picking another kind starts from the centred seat", not ds.session.payload().has("fore_mm"), str(ds.session.payload())))
	_move(pp.fore_slider.slider, 0.0)
	out.append(_t("sliding back to 0 saves no fore key", not ds.session.payload().has("fore_mm"), str(ds.session.payload())))
	ds.session.set_payload({})
	out.append(_t("no payload: the slider's section is hidden", not pp._detail.visible, ""))
	ds.free()
	# The range follows the frame: the panel on a tiny whoop offers a smaller span than on a 5 inch.
	var small := DesignSpace.new(DesignSession.default_for_class("tiny_whoop"), catalog)
	small.session.set_payload({"kind": "payload_custom", "mass_g": 5.0, "size_mm": [10.0, 10.0, 10.0]})
	out.append(_t("the slider's range is smaller on a whoop than on a 5 inch (the frame's, not a constant)",
		small.payload_panel.fore_slider.slider.max_value < lim_mm and small.payload_panel.fore_slider.slider.max_value > 0.0, str(small.payload_panel.fore_slider.slider.max_value)))
	small.free()
	return out


# ---------------------------------------------------------------------------
static func _persistence(catalog: PartsCatalog) -> Array:
	var out: Array = []
	var p := DroneClass.starting_project("five_inch", "t")
	p.payload = {"kind": "payload_custom", "mass_g": MASS_G, "size_mm": SIZE, "fore_mm": -22.0}
	var back := Project.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	var b := back.to_build(catalog)
	out.append(_t("the fore figure survives a project save and load through real JSON and moves the reopened build",
		back.payload.get("fore_mm", null) == -22.0 and absf(b.payload_fore_m() + 0.022) < POS_TOL, str(back.payload)))
	var s := DesignSession.default_for_class("five_inch")
	s.set_payload({"kind": "payload_sprayer_tank", "mass_g": 2000.0, "fore_mm": 18.0})
	var d := DesignFile.to_dict(s, "x")
	var loaded := DesignFile.from_dict(JSON.parse_string(JSON.stringify(d)), catalog)
	out.append(_t("a design file round-trips the fore figure",
		bool(loaded["ok"]) and loaded["session"].payload().get("fore_mm", null) == 18.0, str(loaded.get("reason", ""))))
	var old := DroneClass.starting_project("five_inch", "t")
	old.payload = {"kind": "payload_winch"}
	var oldb := Project.from_dict(JSON.parse_string(JSON.stringify(old.to_dict()))).to_build(catalog)
	out.append(_t("an older payload block with no fore key opens at the default seat",
		oldb.payload_fore_m() == 0.0 and oldb.payload_attach_m().z == oldb.thrust_centroid_xz_m().y, ""))
	var twin := b.at_air(AirDensity.new())
	out.append(_t("the sea-level twin the lift verdict compares against keeps the slide",
		twin != null and absf(twin.payload_fore_m() - b.payload_fore_m()) < POS_TOL and twin.payload_centre_m() == b.payload_centre_m(), ""))
	return out

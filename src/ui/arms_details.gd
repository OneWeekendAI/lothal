class_name ArmsDetails
extends AirframePanel
## The Arms tab — airframe.md §4.2-§4.5, read out for the arm this frame actually has.
##
## ## Why arms are a tab and not a rail
##
## Every other entry in the Glass Bench dropdown is a rail: a list of catalog parts you pick from.
## An arm is not a part. You do not buy four arms and fit them; they are cut from the same sheet as
## the frame, and §2 settled that an arm is a plate with a declared centreline rather than a
## different kind of object. So there is nothing to pick, and a picker with nothing in it would be
## a worse lie than no picker. What there IS is a beam with numbers, which is an inspector.
##
## ## Every figure here is LOAD-INDEPENDENT, and that is the design, not a limitation
##
## This tab used to show tip droop at hover, tip droop at full thrust, and the first mode with the
## motor fitted. All three are real numbers and none of them is a property of a FRAME: they need a
## motor's mass and a propeller's thrust, which is to say they need an aircraft nobody has designed
## while they are drawing an arm. The old tab took them from whatever build happened to be loaded,
## so the arm you were looking at was described in terms of a freestyle quad you had not chosen.
##
## What is here instead is the same physics asked a question the geometry can answer:
##
##   - **Tip stiffness, N/m** replaces droop. Droop IS this number divided into a force; a reader
##     with a thrust figure gets their droop with one division, and a reader without one is not
##     shown a number about somebody else's motor.
##   - **Bending stiffness EI** is the quantity underneath it, quoted because it is what changes
##     when you edit the outline and it is comparable between frames of different lengths.
##   - **The BARE first mode** stays, because a bare arm is a frame's own property. The loaded mode
##     — the one the gyro actually sees, and lower by a factor of four on a 5" — belongs to the room
##     that knows which motor is fitted. That the two differ by that much is the reason this tab
##     says "bare" in the row label rather than quietly implying it is the whole answer.
##   - **Stress per newton** replaces stress at full thrust, and **twist per newton-metre** replaces
##     twist under a reference couple, for the same reason and with the same arithmetic left to a
##     reader who has a load.
##
## ## Where the numbers come from
##
## `ArmProfile` measures `b(s)` off the arm plate's own outline (§10 q1), so this tab works on a
## frame you drew a minute ago. It no longer reads `arm_width_mm` from the catalog — a field one
## frame in fifteen carries, which is why fourteen of these rows used to be dashes.
##
## Everything is quoted against `ArmBeam`'s root-fixity factor, which is a declared guess (§5.4).
## The row says so rather than a footnote saying so.

const SPEC_ROWS := [
	{"key": "arm_length", "label": "Arm (centre→motor)"},
	{"key": "section", "label": "Section at root (b × t)"},
	{"key": "taper", "label": "Taper (root → tip)"},
	{"key": "material", "label": "Cut from"},
	{"key": "arm_mass", "label": "Mass, one arm"},
	{"key": "arms_mass", "label": "Mass, all arms"},
	# ---- STIFFNESS AND THE MODE (§4.2, §4.3) ----
	{"key": "k_tip", "label": "Tip stiffness"},
	{"key": "bending_stiffness", "label": "Bending stiffness EI (root)"},
	{"key": "mode_bare", "label": "1st mode, bare arm"},
	{"key": "root_fixity", "label": "Root fixity assumed"},
	# ---- STRENGTH AND SLOP (§4.4, §4.5) ----
	{"key": "stress_root", "label": "Root stress per newton"},
	{"key": "torsion", "label": "Twist per N·m"},
	# ---- CRASH STRENGTH, AS A RANKING (airframe gaps G4, ArmStrength) ----
	{"key": "break_load", "label": "Breaking load at motor"},
	{"key": "strength_like", "label": "Strength vs catalog"},
	{"key": "strength_rank", "label": "Rank among catalog"},
]

## What the strength rows may and may not claim, said under them on every page — the Lab dock hides
## the shared footer (`set_footer_visible`), and this sentence must not go with it.
const STRENGTH_NOTE := "Strength ranks arms under one steady load at the motor. Impact energy " \
	+ "is not modelled, so this gives no fall height and does not say an arm survives a crash. " \
	+ "Catalog arms are Lothal's generated presets of the plate frames (widths assumed where " \
	+ "unpublished); a moulded frame has no plate arm to rank."

var _strength_note: Label


func _init() -> void:
	super(SPEC_ROWS)


func _build_footer(root: VBoxContainer) -> void:
	_strength_note = Label.new()
	_strength_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strength_note.custom_minimum_size = Vector2(280, 0)
	_strength_note.theme_type_variation = &"MutedLabel"
	_strength_note.text = STRENGTH_NOTE
	root.add_child(_strength_note)
	super(root)


## The footnote under the strength rows, as shown. A test seam beside `rendered_text()`.
func strength_note_text() -> String:
	return _strength_note.text if _strength_note != null and _strength_note.visible else ""


## The arm's strength rating against the shipped catalog (ArmStrength.rate), or {} with no arm.
func strength_rating() -> Dictionary:
	var beam := arm_beam()
	if beam == null:
		return {}
	return ArmStrength.rate(beam, materials(), ArmStrength.default_references(materials()))


## True when this frame's arm width is a generated assumption rather than something authored or
## published — see `AirframeDocument.PLATE_WIDTH_ASSUMED`. Every beam figure below is linear or
## worse in the width, so when it is assumed, so are they, and §8 requires that to travel with the
## number rather than sit in a legend.
func _width_is_assumed() -> bool:
	var plates := arm_plates()
	if plates.is_empty():
		return false
	return bool((plates[0] as Dictionary).get(AirframeDocument.PLATE_WIDTH_ASSUMED, false))


## A row's tier, with the assumed-width caveat folded in when it applies.
func _beam_tier(base: String) -> String:
	return base if not _width_is_assumed() else "%s; arm width assumed" % base


func row_text(key: String) -> String:
	match key:
		"arm_length":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			return "%.0f mm" % (beam.length_m * 1000.0)

		"section":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# Width MEASURED off the outline at the root, where the bending moment is largest —
			# and labelled when that outline is a preset's guess rather than a drawing.
			var section := "%.1f mm × %.1f mm" % [
				beam.width_at(0.0) * 1000.0, beam.thickness_m * 1000.0]
			if _width_is_assumed():
				return with_tier(section, "width assumed — no vendor publishes one")
			return section

		"taper":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			var root := beam.width_at(0.0) * 1000.0
			var tip := beam.width_at(beam.length_m) * 1000.0
			if root <= 0.0:
				return "—"
			var ratio := tip / root
			# A taper is the cheapest stiffness-per-gram decision on the whole frame, and it is
			# invisible in every catalog. Named as a shape rather than left as two numbers.
			var reading := "parallel"
			if ratio < 0.95:
				reading = "narrows toward the motor"
			elif ratio > 1.05:
				reading = "widens toward the motor"
			return "%.1f → %.1f mm  (%s)" % [root, tip, reading]

		"material":
			if _document == null:
				return "—"
			var record := materials().get_material(_document.material_id)
			if record.is_empty():
				return "—"
			var label := str(record.get("name", _document.material_id))
			if materials().is_anisotropic(_document.material_id):
				# The modulus this whole tab multiplies by depends on which way the arm was cut out
				# of the sheet, and §8 puts that in the characteristic tier. A builder reading a
				# resonance is entitled to know the number moves with the layup.
				return "%s  (0/90 assumed)" % label
			return label

		"arm_mass":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			return grams(beam.arm_mass_kg())

		"arms_mass":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# Counted off the document rather than assumed to be four. A tricopter and a hex are
			# both drawable here, and "all four" would be a caption that lies about the picture.
			var count := arm_plates().size()
			return "%s  (%d arms)" % [grams(beam.arm_mass_kg() * float(count)), count]

		"k_tip":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# Divide a thrust by this to get droop. That division is left to whoever has a thrust.
			if _width_is_assumed():
				return with_tier("%.0f N/m" % beam.k_tip_n_per_m(), _beam_tier("engineering-grade"))
			return "%.0f N/m" % beam.k_tip_n_per_m()

		"bending_stiffness":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			var ei := beam.youngs_modulus_pa() * beam.second_moment_at(0.0)
			if ei <= 0.0:
				return "—"
			# THE LESSON OF §4.2 LIVES IN THIS ROW. I = b·t³/12, so the thickness beside it is
			# cubed and the width is not: a 20% thicker arm is 1.73× stiffer, a 20% wider one is
			# 1.2×. Edit the outline and watch which number moves.
			return "%.2f N·m²" % ei

		"mode_bare":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# BARE, and the label says so. Hanging a motor and a prop off the tip drops this by
			# roughly a factor of four on a 5" arm (§4.3), and that loaded figure is the one a gyro
			# lives with — it is computed in the room that knows what is fitted, not here.
			if _width_is_assumed():
				return with_tier("%.0f Hz" % beam.resonance_hz(), _beam_tier("engineering-grade"))
			return "%.0f Hz" % beam.resonance_hz()

		"root_fixity":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# §5.4 declares this the one free constant in ArmBeam and declares it a guess. It scales
			# every resonance on this tab, so it is shown rather than buried: a reader who disagrees
			# with 0.85 can scale the mode row themselves.
			return with_tier("%.2f" % beam.root_fixity(), "a declared guess, §5.4")

		"stress_root":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# PER NEWTON. Bending stress is linear in the applied force, exactly, so one newton is
			# not a reference load standing in for a real one — it is the constant of
			# proportionality, and a reader with a thrust figure multiplies.
			var report := beam.strength_report(1.0)
			var stress := float(report["bending_stress_pa"]) / 1.0e6
			if not bool(report["strength_known"]):
				# A material with no published strength yields "not answerable", never "fine".
				return with_tier("%.1f MPa/N" % stress, "no strength figure for this material")
			var allowable := stress / maxf(float(report["bending_fraction"]), 1.0e-12)
			return with_tier(
				"%.1f MPa/N  (allowable %.0f MPa)" % [stress, allowable],
				_beam_tier(str(report["tier"])))

		"torsion":
			var beam := arm_beam()
			if beam == null:
				return no_beam_reason()
			# Also exactly linear in the applied torque, so per-N·m is the whole answer rather than
			# a sample of it. §4.4 claims ranking only, and the tier says so.
			var twist: Dictionary = beam.torsion_deg(1.0)
			return with_tier("%.2f°/N·m" % float(twist["twist_deg"]), _beam_tier(str(twist["tier"])))

		"break_load":
			if arm_beam() == null:
				return no_beam_reason()
			var rating := strength_rating()
			if not bool(rating["known"]):
				return with_tier("—", "no strength figure for this material")
			# The steady load AT THE MOTOR that brings the arm's weakest section to the material's
			# strength (the allowable on the stress row) — in newtons, and as the weight that would
			# do it, because a builder can picture a weight and cannot picture a newton. A static
			# load, not an impact; the tier is the STRENGTH figure's, from materials.json.
			var newtons := float(rating["break_load_n"])
			var where := "at root" if float(rating["weakest_s_m"]) <= 0.0 \
				else "%.0f mm out" % (float(rating["weakest_s_m"]) * 1000.0)
			return with_tier("%.0f N ≈ %.0f kg, %s" % [newtons, newtons / 9.80665, where],
				_beam_tier(str(rating["strength_tier"])))

		"strength_like":
			if arm_beam() == null:
				return no_beam_reason()
			var rating := strength_rating()
			if not bool(rating["known"]) or int(rating["total"]) == 0:
				return "—"
			# The comparison a builder can use: against frames they know, computed the same way.
			return str(rating["phrase"])

		"strength_rank":
			if arm_beam() == null:
				return no_beam_reason()
			var rating := strength_rating()
			if not bool(rating["known"]) or int(rating["total"]) == 0:
				return "—"
			# §8: a ranking may carry no error bar, and the strength figure under it is
			# characteristic for carbon — so the tier on this row is the strength's own.
			return with_tier("stronger than %d of %d frames" % [int(rating["stronger_than"]),
				int(rating["total"])], str(rating["strength_tier"]))

	return super(key)

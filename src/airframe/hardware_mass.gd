class_name HardwareMass
extends RefCounted
## Screws and standoffs: their mass, the stack height they set, and the three ways a bolted joint
## is wrong before it is even flown (airframe.md §5).
##
## ## Derived, never tabulated — and why that is the whole point
##
## Twenty-odd screws and eight standoffs on a 5" build come to 8-15 g. That is more than a camera,
## and today it is invisible: it is inside a frame's published mass if the vendor included the
## hardware bag, and missing entirely if they did not. Nobody knows which.
##
## A tabulated fix would mean a JSON row per fastener length, which is a hundred rows nobody
## maintains and which cannot answer "what if I cut these standoffs down to 8 mm". So mass here is
## an integral of geometry times a density out of FrameMaterials, and it is legitimate to do that
## because the derivation was checked against the thing it replaces:
##
##     M3 round aluminium standoff, D = 5 mm, bore = 3 mm, L = 12 mm, rho = 2700 kg/m³
##         computed  0.407 g
##         listed    0.4 g each (vendors list ten at 4 g)
##
## Under 2% on a part where the vendor figure is itself quoted to one significant figure. That
## single number is the licence for every other fastener mass in the app, which is why
## tests/test_hardware_mass.gd asserts it against the vendor value and not against 0.407.
##
## ## The three checks, and the severity each is spoken at
##
## Lothal warns and never blocks (parts.md, labs-and-sim.md §2.1) — a builder who wants a 4 mm screw
## in a 3 mm plate gets one, and gets told. The severity scale is BuildWarning's, unchanged:
##
##   IMPOSSIBLE     for thread engagement and bottoming out. Both are hard boundaries in the
##                  geometry, of exactly the kind BuildWarning reserves the top severity for: below
##                  1×d of engagement the thread strips, and a screw longer than the bore plus the
##                  plate presses on nothing at all. There is a number in the geometry to point at.
##   LIMITING       for hole-to-edge. It works, and what binds is the edge margin — 1.5×d is the
##                  workshop rule for plate, not a computed tear-out load, so the honest thing is to
##                  name the dimension that binds rather than to declare the plate broken.
##
## Every check reports the numbers it was computed from in `values`, so a panel can present them
## without a second derivation that could drift from the sentence beside it.

const M3_MIN_ENGAGEMENT_RATIO := 1.0
const EDGE_DISTANCE_RATIO := 1.5
## The thread takes roughly 15% off the shank's effective diameter (§5.1): a screw is not a solid
## cylinder of its nominal diameter, it is that cylinder with a helix cut out of it. 0.85·d is the
## published rule of thumb and lands the M3 steel screw masses within the same few percent the
## standoff check above establishes.
const THREAD_DIAMETER_FACTOR := 0.85

const MM3_PER_M3 := 1.0e9
const KG_TO_G := 1000.0


## Mass in grams of a round standoff: an annulus of outer diameter `outer_d_mm`, bore `bore_d_mm`,
## extruded `length_mm`. `density_kg_m3` comes from FrameMaterials, never from a constant here —
## aluminium, alloy and titanium standoffs are all real purchases and the material is the choice.
##
##     m = rho · (pi/4)·(D² − d²) · L
##
## A bore wider than the outer diameter is not a standoff, and returning a negative mass from it
## would quietly lighten an aircraft, so it clamps at zero rather than propagating nonsense.
static func standoff_round_mass_g(outer_d_mm: float, bore_d_mm: float, length_mm: float, density_kg_m3: float) -> float:
	var area_mm2 := PI / 4.0 * (outer_d_mm * outer_d_mm - bore_d_mm * bore_d_mm)
	return _volume_to_grams(area_mm2 * length_mm, density_kg_m3)


## Mass in grams of a hex standoff, measured the way hex stock is sold: across the flats.
##
## The cross-section is a regular hexagon of across-flats `s`, whose area is (sqrt(3)/2)·s² — not
## the (3·sqrt(3)/2)·r² form, which takes the circumradius and is the same number written for a
## dimension no vendor prints on a bag. Getting that wrong is a 15% mass error in the direction of
## "my build weighs less than it does", which is the direction errors are least likely to be
## noticed in.
static func standoff_hex_mass_g(across_flats_mm: float, bore_d_mm: float, length_mm: float, density_kg_m3: float) -> float:
	var area_mm2 := sqrt(3.0) / 2.0 * across_flats_mm * across_flats_mm - PI / 4.0 * bore_d_mm * bore_d_mm
	return _volume_to_grams(area_mm2 * length_mm, density_kg_m3)


## Mass in grams of a screw: threaded shank plus head, per §5.1.
##
##     m ≈ rho · [ (pi/4)·(0.85·d)²·L_shank  +  (pi/4)·D_head²·h_head ]
##
## The head is modelled as a plain cylinder. A socket cap head is a cylinder with a hex socket
## drilled out of it and a countersunk head is a cone, so this is an over-estimate for both by a few
## percent — stated rather than corrected, because correcting it needs a head-profile field a
## builder does not have and would buy nothing at this scale.
static func screw_mass_g(thread_d_mm: float, shank_len_mm: float, head_d_mm: float, head_h_mm: float, density_kg_m3: float) -> float:
	var effective_d := THREAD_DIAMETER_FACTOR * thread_d_mm
	var shank_mm3 := PI / 4.0 * effective_d * effective_d * shank_len_mm
	var head_mm3 := PI / 4.0 * head_d_mm * head_d_mm * head_h_mm
	return _volume_to_grams(shank_mm3 + head_mm3, density_kg_m3)


static func _volume_to_grams(volume_mm3: float, density_kg_m3: float) -> float:
	if volume_mm3 <= 0.0 or density_kg_m3 <= 0.0:
		return 0.0
	return volume_mm3 / MM3_PER_M3 * density_kg_m3 * KG_TO_G


## §5.2. The standoff lengths ARE the vertical layout: sum them, add the plate thicknesses, and you
## have the z of every plate and the height the stack and the pack sit at. No new physics — this is
## the missing INPUT to physics that already exists, because CG height above the thrust plane is
## what couples pitch into roll and nothing was feeding it.
static func stack_height_mm(standoff_lengths_mm: Array, plate_thicknesses_mm: Array) -> float:
	var total := 0.0
	for length in standoff_lengths_mm:
		total += float(length)
	for thickness in plate_thicknesses_mm:
		total += float(thickness)
	return total


## §5.3, first check. A screw must engage at least 1×d of thread or it strips — 3 mm for an M3.
##
##     engagement = L_screw − t_plate − t_stack
##
## `stack_thickness_mm` is everything the screw passes THROUGH before it reaches thread: washers,
## a soft-mount grommet, a second plate. Pass 0.0 when there is nothing.
##
## Returns null when the joint is fine. A null means "nothing to say", which is what lets a caller
## append the result of every check into one list without a branch per check.
static func thread_engagement_warning(screw_len_mm: float, thread_d_mm: float, plate_thickness_mm: float, stack_thickness_mm: float = 0.0) -> BuildWarning:
	var engagement := screw_len_mm - plate_thickness_mm - stack_thickness_mm
	var required := M3_MIN_ENGAGEMENT_RATIO * thread_d_mm
	if engagement >= required:
		return null
	return BuildWarning.impossible(&"thread_engagement",
		"An M%.0f screw %.1f mm long has only %.1f mm of thread left after %.1f mm of plate and %.1f mm of stack, against the %.1f mm — one full diameter — a thread needs to hold. Below that it strips on the first or second assembly, and it strips at the moment you are tightening it rather than in the air." % [
			thread_d_mm, screw_len_mm, engagement, plate_thickness_mm, stack_thickness_mm, required],
		{"engagement_mm": engagement, "required_mm": required, "screw_len_mm": screw_len_mm,
			"thread_d_mm": thread_d_mm, "plate_thickness_mm": plate_thickness_mm,
			"stack_thickness_mm": stack_thickness_mm})


## §5.3, second check. The opposite mistake: a screw longer than the plate plus the depth of thread
## available in the standoff bottoms out inside the standoff. It feels tight — that is the trap —
## but the plate underneath it is not clamped at all, so the joint stays loose forever and the
## builder tightens it harder and strips the standoff instead.
##
## `bore_depth_mm` is the threaded depth of the standoff, which for a female-female standoff is
## typically its full length and for a male-female one is not.
static func bottoming_out_warning(screw_len_mm: float, thread_d_mm: float, plate_thickness_mm: float, bore_depth_mm: float) -> BuildWarning:
	var available := plate_thickness_mm + bore_depth_mm
	if screw_len_mm <= available:
		return null
	return BuildWarning.impossible(&"screw_bottoms_out",
		"An M%.0f screw %.1f mm long bottoms out: %.1f mm of plate plus %.1f mm of standoff bore is %.1f mm of hole, so the last %.1f mm has nowhere to go. It will feel tight while clamping nothing — the plate stays loose however hard you pull on it, and pulling harder strips the standoff." % [
			thread_d_mm, screw_len_mm, plate_thickness_mm, bore_depth_mm, available, screw_len_mm - available],
		{"screw_len_mm": screw_len_mm, "available_mm": available, "overshoot_mm": screw_len_mm - available,
			"plate_thickness_mm": plate_thickness_mm, "bore_depth_mm": bore_depth_mm,
			"thread_d_mm": thread_d_mm})


## §5.3, fourth check. A bolt hole closer than 1.5×d to a plate edge tears out — the material
## between hole and edge is the only thing carrying the bolt's load into the plate, and on carbon it
## goes as a delamination rather than as a bend.
##
## `edge_distance_mm` is the exact polygon-to-point distance from the hole CENTRE to the nearest
## edge, which is the geometry kernel's job to supply; this function is pure arithmetic on it so it
## can be tested without a polygon.
static func hole_to_edge_warning(edge_distance_mm: float, hole_d_mm: float) -> BuildWarning:
	var required := EDGE_DISTANCE_RATIO * hole_d_mm
	if edge_distance_mm >= required:
		return null
	return BuildWarning.limiting(&"hole_to_edge",
		"A %.1f mm hole sits %.1f mm from the plate edge, inside the %.1f mm (1.5x diameter) of material a bolt needs behind it. What binds here is the edge margin, not the plate: move the hole in, or take the outline out, and the same bolt is fine. Left as it is, carbon tears out of the edge in a crash rather than bending." % [
			hole_d_mm, edge_distance_mm, required],
		{"edge_distance_mm": edge_distance_mm, "required_mm": required, "hole_d_mm": hole_d_mm})


## Everything the hardware has to say about one bolted joint, in one list, most severe first — the
## shape FramePlausibility.warnings_for uses, so a caller appends it unconditionally and has no
## opinion about which of these apply.
static func joint_warnings(screw_len_mm: float, thread_d_mm: float, plate_thickness_mm: float, bore_depth_mm: float, edge_distance_mm: float, stack_thickness_mm: float = 0.0) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	for warning in [
		thread_engagement_warning(screw_len_mm, thread_d_mm, plate_thickness_mm, stack_thickness_mm),
		bottoming_out_warning(screw_len_mm, thread_d_mm, plate_thickness_mm, bore_depth_mm),
		# The SCREW's diameter, deliberately, not the drilled clearance hole's: the tear-out rule is
		# written on the bolt size, and reading it off the hole would quietly loosen the
		# requirement by whatever clearance the shop drilled.
		hole_to_edge_warning(edge_distance_mm, thread_d_mm),
	]:
		if warning != null:
			out.append(warning)
	return BuildWarning.by_severity(out)

class_name PropGuard
extends RefCounted
## Prop guards as parts — propulsion.md §6 and slice P9.
##
## ## The `kind` discriminator, and why it comes first
##
## §6.1 borrows airframe.md §9b's most transferable lesson: a physics-bearing part carries a
## discriminator that decides whether a model applies at all, not merely which model applies.
## The frame's `construction: plate | moulded` field kept the plate generator from fabricating a
## carbon arm for an injection-moulded whoop. Prop guards need the same before any geometry:
##
## | `kind`   | What it is                                        | What it may claim                       |
## |----------|---------------------------------------------------|-----------------------------------------|
## | `bumper` | An open ring or cage well clear of the blade tips | Mass, inertia and clearance only.       |
## | `duct`   | A shroud with a small tip gap (cinewhoop, ducted) | Genuinely changes thrust — tip loss.    |
##
## Getting this backwards in either direction is a real error. A bumper credited with duct thrust
## is a free lunch. A cinewhoop treated as a bumper reports a hover throttle that will not fly the
## aircraft.
##
## ## Bumper geometry — mass and the inertia bite
##
## §6.2 is one paragraph and it does the whole job:
##
##     m = rho * V(outline, height, wall)          the airframe.md §3.1 kernel, unchanged
##     I += m * R_guard^2                          at the largest radius on the aircraft
##
## ## Blade tip clearance — the third thing a bumper may claim
##
## §6.1's table grants a bumper "mass, inertia and clearance only", and §6.2 names the check
## exactly: "the guard's inner outline against the prop disc. Exact." It is the one number here
## with no modelling in it at all —
##
##     clearance = (outer_radius - wall) - prop_tip_radius
##
## and §8 files it under **Exact** for that reason. A NEGATIVE clearance is not an error to
## refuse: it is the answer, and it means the ring passes through the disc. `clearance_check`
## reports it rather than clamping it, because a builder who has entered an interfering guard
## needs to be told, not protected from the arithmetic.
##
## The check is also where §6.1's mislabelling becomes DETECTABLE rather than merely warned
## about. `kind` is authored by hand and the two failures it guards ("a bumper credited with
## duct thrust is a free lunch; a cinewhoop treated as a bumper reports a hover throttle that
## will not fly the aircraft") are both silent — the geometry is what gives them away. A ring
## whose gap is small compared with the blade's tip chord IS a shroud whatever its `kind` says.
##
## The comparison uses the tip chord and no new constant, deliberately: it is the same length
## scale `tip_loss_closure` divides by, and the split sits at `gap = chord`, which is the point
## where that closure fraction passes 1/2. That is a property of the rational form already
## chosen, not a threshold picked after looking at a catalog — §6.3's warning about "a bound set
## after seeing the data" applies to this boundary as much as to an augmentation constant.
##
## `clearance_check` REPORTS the disagreement and never resolves it. The model does not silently
## promote a mislabelled bumper to a duct: that would hand back the free lunch §6.1 forbids, from
## a dimension a builder may simply have typed wrong. The caller — a panel, ultimately — asks the
## builder which one it is.
##
## For a circular guard — the only shape P9 ships, per §6.1's "before any geometry" rule and
## the pre-UI slice's habit of the outline being the door open for later — `V = 2π · R_avg ·
## height · wall` and the increment to the aircraft's roll inertia is a point mass at
## `R_guard = mount_radius + outer_radius`. Inertia goes as R², and a guard sits at the largest
## R on the aircraft by construction, so a light guard can beat a heavy motor — the finding
## `tests/test_prop_guard.gd` computes on a real cinewhoop and reports as a ratio.
##
## The doc's simplification — treating the guard as a point mass at R_guard rather than
## integrating a hoop about the aircraft roll axis — biases the inertia HIGH, but by less than
## the ratio it is trying to show: for a thin ring around each motor, the more exact form is
## `I = m·R_motor² + m·R_ring²/2` (parallel-axis plus perpendicular-axis for the ring about
## a diameter), which for R_motor >> R_ring differs from `m·(R_motor + R_ring)²` by a term of
## order `m·R_ring²`. That gap is documented rather than tuned away, and the point-mass form is
## kept because the doc names it and the ratio the acceptance calls for survives either form.
##
## ## Duct — the tip-loss suppression
##
## §6.3 is the strongest single argument in propulsion.md for doing propulsion as geometry: a
## shroud suppresses the tip vortex, and Prandtl's tip-loss factor F already exists in
## `bemt.rs` for unrelated reasons. Close the gap and the leak closes with it:
##
##     F_effective = F_base + closure · (1 − F_base)          continuous, F_effective → 1 as gap → 0
##
## `tip_loss_closure(spec, chord_at_tip_mm)` returns `closure ∈ [0, 1]` and NOTHING else: the
## augmentation constant §6.3 warns against ("a duct-augmentation constant tuned until a known
## cinewhoop hovers at the right throttle — that is a bound set after seeing the data") does
## not exist in this file, and the BEMT integration that reads `closure` is P10 room work.
##
## The functional form is `1 / (1 + gap_mm / chord_at_tip_mm)`, which is monotone, hits 1 at
## gap = 0 and falls to 0 as gap grows. The natural length scale is the blade's tip chord — the
## width of the leaking sheet, the physics's own length. Using a constant scale here would be
## exactly what §0 forbids: nothing about the aircraft's appearance may come from a constant
## that the physics does not also read.
##
## For a bumper, closure is 0.0 regardless of what `tip_gap_mm` the spec might carry, and
## `tests/test_prop_guard.gd` asserts this with a spec deliberately shaped like a duct — because
## the failure §6.1 warns about is silent, and a test that only exercised well-formed bumper
## specs would pass a stub that returned `1.0` for anything with the word "guard" in it.
##
## ## Refusals
##
## - Missing or unknown `kind` — `tier = "unknown_kind"`, all figures zero. A guard whose type
##   the model cannot read is not one it should be attributing mass or inertia to.
## - Non-positive geometry (outer_radius ≤ 0, wall ≤ 0, height ≤ 0, density ≤ 0) — `tier =
##   "insufficient_data:*"`, all figures zero. Same posture soft_mount.gd took for bad grommet
##   specs: an unreadable part models as no part rather than as a class-typical default.
## - Duct with missing `tip_gap_mm` or a chord_at_tip that arrives non-positive from the caller
##   — closure = 0.0, no augmentation claim. §6.3's rule.
## - Clearance against a non-positive prop tip radius, or a spec `compute()` refuses — `NAN`,
##   not zero. Zero clearance is a real and meaningful answer (a shroud flush with the tip), so
##   it must not double as the refusal value the way `0.0` legitimately can for closure.
##
## ## Doubles
##
## Every arithmetic step is GDScript `float`. R is order 1e-1 m, mass is order 1e-2 kg, and
## `m·R²` is order 1e-4 kg·m² — well inside single precision, but the file's siblings all use
## float and consistency is worth more here than saving a byte per number.

const KIND_BUMPER := "bumper"
const KIND_DUCT := "duct"


## The full computation. Returns
##
##     {
##         "kind":                              String,
##         "mass_kg":                           float,
##         "roll_inertia_contribution_kg_m2":   float,
##         "r_guard_m":                         float,   the largest radius, mount + outer
##         "tier":                              String,  "computed" | "unknown_kind" | "insufficient_data:*"
##     }
##
## `spec` fields:
##   kind:              "bumper" or "duct" — required
##   outer_radius_mm:   the ring's own outer radius (about its centre, i.e. the motor)
##   wall_mm:           the ring's radial wall thickness
##   height_mm:         the ring's axial height (extrusion perpendicular to the disc)
##   density_kg_m3:     the ring material's density (ABS ≈ 1050, nylon ≈ 1150, TPU ≈ 1200)
##   mount_radius_mm:   distance from the aircraft roll axis to the ring's centre (arm_mm for
##                      per-motor guards, 0 for a cage that surrounds the whole aircraft)
##   tip_gap_mm:        duct only — the radial gap between blade tip and inner shroud wall
static func compute(spec: Dictionary) -> Dictionary:
	var kind := String(spec.get("kind", ""))
	if kind != KIND_BUMPER and kind != KIND_DUCT:
		return _unknown_kind()

	var outer_r_mm := float(spec.get("outer_radius_mm", 0.0))
	var wall_mm := float(spec.get("wall_mm", 0.0))
	var height_mm := float(spec.get("height_mm", 0.0))
	var density := float(spec.get("density_kg_m3", 0.0))
	var mount_r_mm := float(spec.get("mount_radius_mm", 0.0))

	if outer_r_mm <= 0.0:
		return _insufficient(kind, "outer_radius_non_positive")
	if wall_mm <= 0.0:
		return _insufficient(kind, "wall_non_positive")
	if height_mm <= 0.0:
		return _insufficient(kind, "height_non_positive")
	if density <= 0.0:
		return _insufficient(kind, "density_non_positive")
	if mount_r_mm < 0.0:
		return _insufficient(kind, "mount_radius_negative")

	# Hoop volume: perimeter of the mean circle × cross-section (wall × height). Mean radius is
	# outer − wall/2 so a thick-walled short ring doesn't over-count the corner. For the
	# thin-walled rings a guard actually is (wall ≪ outer_radius) this collapses to 2π·R·h·w.
	var wall_m := wall_mm * 0.001
	var height_m := height_mm * 0.001
	var outer_m := outer_r_mm * 0.001
	var mean_r_m := outer_m - wall_m * 0.5
	if mean_r_m <= 0.0:
		return _insufficient(kind, "wall_thicker_than_ring")

	var volume_m3 := TAU * mean_r_m * height_m * wall_m
	var ring_mass_kg := density * volume_m3

	# The doc's simplification: point mass at R_guard = mount + outer. The bias is documented
	# in this file's header rather than hidden — the cinewhoop ratio the acceptance calls for
	# holds either way, and following the doc's own arithmetic keeps this file readable against
	# the paragraph it implements.
	var r_guard_m := (mount_r_mm + outer_r_mm) * 0.001
	var roll_inertia := ring_mass_kg * r_guard_m * r_guard_m

	return {
		"kind": kind,
		"mass_kg": ring_mass_kg,
		"roll_inertia_contribution_kg_m2": roll_inertia,
		"r_guard_m": r_guard_m,
		"tier": "computed",
	}


## Just the mass, for a callers that only need the number the build sheet prints. Returns
## 0.0 for any spec that `compute()` refuses, on the same posture soft_mount.gd's mount_mass_kg
## takes: an unreadable part is not a fallback to a default part.
static func mass_kg(spec: Dictionary) -> float:
	var result := compute(spec)
	if result["tier"] != "computed":
		return 0.0
	return float(result["mass_kg"])


## Just the roll-inertia contribution — §6.2's `I += m · R_guard²` as a standalone number, for
## a panel row or a comparison against another part at another radius (which is the finding
## `tests/test_prop_guard.gd` reports). Same refusal posture as mass_kg.
##
## This is NOT the shape `AirframeProperties` consumes. That file builds a full 3×3 tensor from
## elements carrying a mass and a position and applies parallel-axis itself, so a guard enters
## it as mass + plan position via its point-element path; handing it this scalar as well would
## count the R² term twice. No caller does either yet — no `guards.json` category exists, so no
## build carries a guard spec to feed in — and that plumbing is P10's, alongside the drawing.
static func roll_inertia_contribution_kg_m2(spec: Dictionary) -> float:
	var result := compute(spec)
	if result["tier"] != "computed":
		return 0.0
	return float(result["roll_inertia_contribution_kg_m2"])


## The tip-loss suppression fraction — §6.3.
##
## Returns `closure ∈ [0, 1]`: 1 means the shroud fully closes the tip leak (F → 1), 0 means
## no closure (baseline F stands). BEMT downstream reads this as
##
##     F_effective = F_base + closure · (1 − F_base)
##
## which is continuous by construction and monotone in gap.
##
## `chord_at_tip_mm` is the physics's own length scale — the width of the leaking sheet — and
## it is passed in rather than kept as a constant here. §0's rule: nothing may come from a
## constant that the physics does not also read.
##
## Bumper: **always 0.0**, regardless of what `tip_gap_mm` the spec carries. §6.1's silent
## failure this file exists to prevent, asserted in the test suite by feeding a bumper a
## duct-shaped spec and checking the return is still zero.
##
## Duct with a missing or non-positive `tip_gap_mm`, or a non-positive `chord_at_tip_mm`:
## 0.0. §6.3's rule that a constant, "tuned until a known cinewhoop hovers at the right
## throttle", is not what this file does. No spec, no claim.
static func tip_loss_closure(spec: Dictionary, chord_at_tip_mm: float) -> float:
	var kind := String(spec.get("kind", ""))
	if kind == KIND_BUMPER:
		return 0.0
	if kind != KIND_DUCT:
		return 0.0
	if chord_at_tip_mm <= 0.0:
		return 0.0
	if not spec.has("tip_gap_mm"):
		return 0.0
	var gap_mm := float(spec.get("tip_gap_mm", -1.0))
	if gap_mm < 0.0:
		return 0.0
	# Rational form, monotone, exact endpoints: closure(gap=0) = 1, closure(gap=∞) = 0.
	# Length ratio gap/chord is dimensionless via the physics's own length, not via a constant.
	return 1.0 / (1.0 + gap_mm / chord_at_tip_mm)


## Blade tip clearance in mm — §6.2's exact pure-geometry check.
##
## `(outer_radius - wall) - prop_tip_radius`, the guard's inner wall against the disc it
## surrounds. Positive is a gap, zero is flush, and NEGATIVE means the ring passes through the
## swept disc — reported, not clamped, because that is a build error the number exists to catch.
##
## Returns `NAN` when the spec is one `compute()` refuses, or when `prop_tip_radius_mm` is not
## positive. Zero is a real clearance, so it cannot also be the refusal value.
static func tip_clearance_mm(spec: Dictionary, prop_tip_radius_mm: float) -> float:
	if prop_tip_radius_mm <= 0.0:
		return NAN
	var result := compute(spec)
	if result["tier"] != "computed":
		return NAN
	var inner_radius_mm := float(spec.get("outer_radius_mm", 0.0)) - float(spec.get("wall_mm", 0.0))
	return inner_radius_mm - prop_tip_radius_mm


## Clearance, plus what the GEOMETRY says the guard is — and whether that agrees with `kind`.
##
## §6.1 names two silent failures and this is where they become visible. Returns
##
##     {
##         "clearance_mm":     float,   NAN when unreadable; negative means interference
##         "gap_ratio":        float,   clearance / chord_at_tip, NAN when unreadable
##         "declared_kind":    String,  what the spec says
##         "geometric_kind":   String,  "duct" | "bumper" | "interference" | "unknown"
##         "kind_disagrees":   bool,    declared and geometric disagree, and both are readable
##     }
##
## `geometric_kind` splits at `gap = chord_at_tip`: at or under one tip chord the ring is a
## shroud (the point where `tip_loss_closure` passes 1/2), above it the ring is well clear and
## is a bumper. Negative clearance is neither — it is `"interference"`, and it disagrees with
## every declared kind because no guard should intersect its own disc.
##
## Nothing is resolved here. A mislabelled bumper does NOT start returning duct closure — see
## this file's header for why the model reports and the builder decides.
static func clearance_check(spec: Dictionary, prop_tip_radius_mm: float,
		chord_at_tip_mm: float) -> Dictionary:
	var declared := String(spec.get("kind", ""))
	if declared != KIND_BUMPER and declared != KIND_DUCT:
		declared = ""
	var clearance := tip_clearance_mm(spec, prop_tip_radius_mm)
	var out := {
		"clearance_mm": clearance,
		"gap_ratio": NAN,
		"declared_kind": declared,
		"geometric_kind": "unknown",
		"kind_disagrees": false,
	}
	if is_nan(clearance):
		return out
	if clearance < 0.0:
		out["geometric_kind"] = "interference"
		out["kind_disagrees"] = declared != ""
		if chord_at_tip_mm > 0.0:
			out["gap_ratio"] = clearance / chord_at_tip_mm
		return out
	if chord_at_tip_mm <= 0.0:
		# No length scale, no claim — the same refusal `tip_loss_closure` makes, for the same
		# reason. The clearance itself still stands; only the classification is withheld.
		return out
	var ratio := clearance / chord_at_tip_mm
	out["gap_ratio"] = ratio
	out["geometric_kind"] = KIND_DUCT if ratio <= 1.0 else KIND_BUMPER
	out["kind_disagrees"] = declared != "" and declared != out["geometric_kind"]
	return out


## What the guard is allowed to say about thrust, as a String rather than a number. §8's
## honesty tiers: a bumper's answer is a hard NO ("unchanged"), and a duct's is "characteristic"
## because published duct data does not exist. A panel that wants to legend the thrust column
## reads this rather than a bare closure fraction.
static func thrust_change_claim(spec: Dictionary) -> String:
	var kind := String(spec.get("kind", ""))
	if kind == KIND_BUMPER:
		return "unchanged"
	if kind == KIND_DUCT:
		return "characteristic"
	return "unknown"


static func _unknown_kind() -> Dictionary:
	return {
		"kind": "",
		"mass_kg": 0.0,
		"roll_inertia_contribution_kg_m2": 0.0,
		"r_guard_m": 0.0,
		"tier": "unknown_kind",
	}


static func _insufficient(kind: String, reason: String) -> Dictionary:
	return {
		"kind": kind,
		"mass_kg": 0.0,
		"roll_inertia_contribution_kg_m2": 0.0,
		"r_guard_m": 0.0,
		"tier": "insufficient_data:" + reason,
	}

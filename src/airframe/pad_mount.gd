class_name PadMount
extends RefCounted
## A pad as a spring — airframe.md §6.2. Pure functions of a material, an area, a thickness and the
## mass sitting on the pad: no Build, no node, no document. The Straps & pads row and page read it
## through `StrapsPads`, which is the one place a build becomes the four numbers this file takes.
##
##     Stiffness            k   = E_pad · A_pad / t_pad
##     Natural frequency    f_n = (1/2π)·√(k/m)
##     Transmissibility     T(f) = √( (1 + (2ζr)²) / ((1 − r²)² + (2ζr)²) ),   r = f / f_n
##
## The transmissibility is NOT re-derived here. It is `FlightLaw.mount_transmissibility`, the one
## curve the motor soft mounts already use (VibrationModel.mount_transmissibility), so there is one
## transmissibility formula in this codebase and the pad and the grommet cannot disagree about what
## an isolator does.
##
## ## Honesty tiers (§8), stated per figure
##
##   - EXACT: the pad's area, thickness, mass and the height it lifts the pack. Arithmetic on
##     geometry; the pad's mass and lift are BatteryPad's and Build's (PR11, PR17), not computed again
##     here.
##   - CHARACTERISTIC: stiffness, natural frequency, transmissibility. §8 puts "pad stiffness" in this
##     tier by name and the pad modulus is one of the four declared free constants: TPU 95A's Young's
##     modulus is quoted as a 0.01-0.05 GPa SPAN (data/materials.json takes the midpoint). A factor of
##     five in E is a factor of √5 ≈ 2.2 in f_n. So these may RANK two pads — thinner is stiffer, more
##     area is stiffer, more mass is lower — and say which side of a resonance a mount is on. They may
##     never put an error bar on a frequency.
##   - The damping ratio is a GUESS, and labelled as one wherever it is shown. See `DAMPING_RATIO`.
##
## ## What this does NOT feed, and why (the seam)
##
## The gyro does not sit on the battery pad. A battery pad isolates the PACK from the frame; the
## sensor is on the flight controller, which is bolted (or grommeted) to the stack. Multiplying the
## battery pad's T(f) into `VibrationModel.angular_rate_at` would claim a TPU slab under the pack
## quiets the gyro, which is not a thing it does. The one pad that WOULD belong in that path is a
## soft-mounted stack: the same spring with the board's mass on it, between the frame and the sensor.
## No document or build describes a stack pad yet, so nothing is fed. When one exists, the seam is:
## `compute(...)` with the stack's mass, and its `f_n_hz` and `DAMPING_RATIO` passed into
## `FlightLaw.vibration_rate`'s params as a second isolator multiplying the forcing (which needs the
## Rust function to take a second (f_n, ζ) pair — params index 6/7 are the motor mount's today).

## The pad material, by FrameMaterials id. A printed TPU 95A pad is what BatteryPad generates.
const MATERIAL_ID := "tpu_95a"

## THE DAMPING RATIO, AND IT IS A GUESS. Borrowed rather than invented: `SoftMount.DEFAULT_DAMPING_RATIO`
## is the middle of the textbook 0.05-0.15 range for elastomer isolators, and a TPU pad is an
## elastomer isolator. One guess in the codebase for "how damped is a rubbery mount", not two that
## can drift. It sets the HEIGHT of the hump at f_n and nothing about where the curve crosses 1.
const DAMPING_RATIO := SoftMount.DEFAULT_DAMPING_RATIO

## Below this a mount puts its own resonance inside the flight-control loop's bandwidth, where it
## amplifies and the aircraft develops a wobble no tune fixes — §6.2's "sub-100 Hz". A line from the
## design document, fixed before any pad was computed against it.
const FLIGHT_BANDWIDTH_HZ := 100.0

## An isolator passes MORE than no isolator below r = √2 and less only above it. This is the corner a
## builder means by "where the pad starts working". Exact, from the formula above (T = 1 at r = √2
## for every ζ).
const ISOLATION_RATIO := 1.4142135623730951

const TIER_EXACT := "exact"
const TIER_CHARACTERISTIC := "characteristic"
const TIER_GUESS := "guess"

const PAD_TOO_SOFT := &"pad_too_soft"
const PAD_PASSES_FRAME_MODE := &"pad_passes_frame_mode"


## N/m. k = E·A/t, with E in pascals and the geometry in millimetres. Zero for any non-positive input
## — a pad of no area or no thickness is not a spring this function will describe.
static func stiffness_n_per_m(modulus_pa: float, area_mm2: float, thickness_mm: float) -> float:
	if modulus_pa <= 0.0 or area_mm2 <= 0.0 or thickness_mm <= 0.0:
		return 0.0
	return modulus_pa * (area_mm2 * 1e-6) / (thickness_mm * 1e-3)


## Hz. f_n = √(k/m)/2π. INF for no mass (nothing on the spring has no resonance to be below); zero for
## no stiffness.
static func natural_frequency_hz(stiffness: float, mass_kg: float) -> float:
	if mass_kg <= 0.0:
		return INF
	if stiffness <= 0.0:
		return 0.0
	return sqrt(stiffness / mass_kg) / TAU


## The share of the frame's vibration at `hz` that reaches what sits on the pad. 1 = as if there were
## no pad; above 1 the pad amplifies; below 1 it isolates. The motor mounts' curve, verbatim.
static func transmissibility(hz: float, f_n_hz: float, zeta: float = DAMPING_RATIO) -> float:
	return FlightLaw.mount_transmissibility(hz, f_n_hz, zeta)


## Where the pad starts isolating: f_n·√2. Below it, more of the frame reaches the load than with no
## pad at all.
static func isolation_onset_hz(f_n_hz: float) -> float:
	return f_n_hz * ISOLATION_RATIO


## Everything the page shows about one pad carrying one mass, or a refusal with a reason.
##
## `{ok, reason, material_id, modulus_pa, area_mm2, thickness_mm, load_kg, stiffness_n_m, f_n_hz,
##   onset_hz, zeta, tiers: {figure: tier}}`
static func compute(materials: FrameMaterials, area_mm2: float, thickness_mm: float,
		load_kg: float, material_id: String = MATERIAL_ID) -> Dictionary:
	var out := {"ok": false, "reason": "", "material_id": material_id, "area_mm2": area_mm2,
		"thickness_mm": thickness_mm, "load_kg": load_kg, "zeta": DAMPING_RATIO,
		"tiers": {"area_mm2": TIER_EXACT, "thickness_mm": TIER_EXACT, "load_kg": TIER_EXACT,
			"stiffness_n_m": TIER_CHARACTERISTIC, "f_n_hz": TIER_CHARACTERISTIC,
			"onset_hz": TIER_CHARACTERISTIC, "transmissibility": TIER_CHARACTERISTIC,
			"zeta": TIER_GUESS}}
	var modulus_gpa := materials.modulus_gpa(material_id) if materials != null else 0.0
	if modulus_gpa <= 0.0:
		out["reason"] = "%s has no Young's modulus in the material table" % material_id
		return out
	if area_mm2 <= 0.0 or thickness_mm <= 0.0:
		out["reason"] = "the pad has no area or no thickness"
		return out
	if load_kg <= 0.0:
		out["reason"] = "nothing sits on the pad"
		return out
	var modulus_pa := modulus_gpa * 1e9
	var k := stiffness_n_per_m(modulus_pa, area_mm2, thickness_mm)
	var f_n := natural_frequency_hz(k, load_kg)
	out.merge({"ok": true, "modulus_pa": modulus_pa, "stiffness_n_m": k, "f_n_hz": f_n,
		"onset_hz": isolation_onset_hz(f_n)}, true)
	return out


## The two §6.2 checks, against the frame's first mode (`frame_mode_hz`, VibrationModel's — 0 or less
## skips the second). Empty for a refused pad.
##
##   - PAD_TOO_SOFT (limiting): f_n inside the flight-control bandwidth. "It cuts both ways": a mount
##     soft enough to land there amplifies the slow motion the controller is trying to make.
##   - PAD_PASSES_FRAME_MODE (characteristic): the frame rings below the pad's isolation onset, so at
##     the one frequency that matters the pad passes the vibration through (or adds to it). This is a
##     statement about what the pad IS — a solid printed slab under a whole pack is a grip pad, not an
##     isolator — not a mistake, which is why it does not turn the row amber.
static func warnings(pad: Dictionary, frame_mode_hz: float) -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []
	if not bool(pad.get("ok", false)):
		return out
	var f_n := float(pad["f_n_hz"])
	if f_n < FLIGHT_BANDWIDTH_HZ:
		out.append(BuildWarning.limiting(PAD_TOO_SOFT,
			"The battery pad is soft enough to put its own resonance at about %d Hz, inside the %d Hz the flight controller works in. Below its isolation corner a pad amplifies rather than isolates, so this one adds a low-frequency wobble that no PID tune removes. Use a thinner or harder pad, or more of it under the pack. (Characteristic: TPU's modulus is a span, so this ranks pads rather than sizing one.)" % [
				roundi(f_n), roundi(FLIGHT_BANDWIDTH_HZ)],
			{"f_n_hz": f_n, "limit_hz": FLIGHT_BANDWIDTH_HZ}))
	var onset := float(pad["onset_hz"])
	if frame_mode_hz > 0.0 and frame_mode_hz < onset:
		var t := transmissibility(frame_mode_hz, f_n, float(pad.get("zeta", DAMPING_RATIO)))
		out.append(BuildWarning.characteristic(PAD_PASSES_FRAME_MODE,
			"The frame's first mode, about %d Hz, is below where the battery pad starts isolating (about %d Hz), so the pad passes %.2f× of that vibration to the pack. A pad isolates only well above its own resonance; this one is stiff enough to act as a grip pad, not a vibration mount. A softer or thicker pad moves the corner down. (Characteristic, and the %.2f damping ratio is a guess.)" % [
				roundi(frame_mode_hz), roundi(onset), t, float(pad.get("zeta", DAMPING_RATIO))],
			{"frame_mode_hz": frame_mode_hz, "onset_hz": onset, "transmissibility": t}))
	return out

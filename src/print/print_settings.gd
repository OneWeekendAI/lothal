class_name PrintSettings
extends RefCounted
## The builder's printing decisions for ONE drone — printed-room slice PR0
## (plans/2026-09-14-printed-room-plan.md). Pure functions over `Project.printing`, which has existed
## and round-tripped since W0.1 with nothing reading it.
##
## PER DRONE, NOT GLOBAL, and that is a deliberate break from the camera tilt and the GPS mast, which
## both live in one `user://assembly_tweaks.json`. A clearance is a property of the printer that will
## make THIS drone's parts, and the persistence design (§3.5) puts it in the project so a shared file
## carries the clearance it was designed with. Two tweaks with a global story plus one with a per-drone
## story is untidy; a third global value would be a third copy of a known debt.
##
## THE CLEARANCE IS A GUESS, and it is said here, in the text the field shows, rather than only in a
## doc. A well-tuned printer wants about 0.15 mm, a tired one 0.35 mm, and the same STL fits on one and
## binds on the other. Validating the default needs a printer and a real frame (tier 4). It is the one
## guess in Lothal that costs filament rather than accuracy.

const CLEARANCE := "fit_clearance_mm"
const DEFAULT_CLEARANCE_MM := 0.20
const MIN_CLEARANCE_MM := 0.0
const MAX_CLEARANCE_MM := 0.60
const CLEARANCE_STEP_MM := 0.05

const MATERIAL := "material"
const DEFAULT_MATERIAL := "tpu_95a"

## Shown under the slider. The voice is the point: it names itself a guess where it is edited.
const CLEARANCE_HINT := "Slack left where a printed part meets a bought one, on every side. 0.20 mm is a guess — a well-tuned printer wants about 0.15, a tired one 0.35. Print one part and adjust; nothing in Lothal can measure your printer."

## Appended to the value while nobody has set it, so the row itself says the number is not a decision.
const GUESS_MARKER := "(guess)"

## TPU 95A, 1.22 g/cm³ — the class-typical datasheet figure (Ultimaker and Polymaker TPU 95A sheets
## both sit at 1.20–1.23). A material's density, not a part's, and not re-sourced per brand. Every
## printed part that has mass reads it here (PR15); the prop guard does not, because its ring is a
## catalog part whose density the catalog publishes (Propulsion P9).
const DENSITY_KG_M3 := 1220.0
## Fraction of each printed part's solid that is filled — ONE guess for every weighted printed part
## (PR15). Solid, because the walls these parts are made of (1.6–2 mm) are all perimeters at any
## slicer's defaults. A builder printing a thicker pad at 15% infill gets a lighter part than the row
## says; validation.md §11 records the battery pad against a real one.
const INFILL_FRACTION := 1.0


## The infill guess as a row says it beside a weight: "solid infill (guess)", or "40% infill (guess)".
static func infill_label(fraction: float = INFILL_FRACTION) -> String:
	if fraction >= 1.0:
		return "solid infill %s" % GUESS_MARKER
	return "%d%% infill %s" % [roundi(fraction * 100.0), GUESS_MARKER]


## A printed part's mass from its volume: the one density and the one infill.
static func printed_mass_kg(volume_mm3: float) -> float:
	return volume_mm3 * 1.0e-9 * DENSITY_KG_M3 * INFILL_FRACTION


## The clearance in force, in millimetres: the stored value clamped, or the default when absent or
## unreadable. An unreadable value is not an error to surface here — Project already records load
## warnings for a bad block, and a part generated at a stated default is better than no part.
static func clearance_mm(printing: Dictionary) -> float:
	var raw: Variant = printing.get(CLEARANCE, null)
	if not (raw is float or raw is int):
		return DEFAULT_CLEARANCE_MM
	return clampf(float(raw), MIN_CLEARANCE_MM, MAX_CLEARANCE_MM)


static func has_clearance_override(printing: Dictionary) -> bool:
	var raw: Variant = printing.get(CLEARANCE, null)
	return raw is float or raw is int


## Stores a clearance, clamped. Writes into the dictionary it is given — the caller owns it.
static func set_clearance_mm(printing: Dictionary, mm: float) -> void:
	printing[CLEARANCE] = clampf(mm, MIN_CLEARANCE_MM, MAX_CLEARANCE_MM)


static func reset_clearance(printing: Dictionary) -> void:
	printing.erase(CLEARANCE)


static func material(printing: Dictionary) -> String:
	var raw: Variant = printing.get(MATERIAL, null)
	return String(raw) if raw is String and String(raw) != "" else DEFAULT_MATERIAL


## What the clearance row reads: "0.20 mm  (guess)" untouched, "0.35 mm" once set.
static func clearance_row_text(printing: Dictionary) -> String:
	return "%.2f mm%s" % [clearance_mm(printing),
		"" if has_clearance_override(printing) else "  " + GUESS_MARKER]

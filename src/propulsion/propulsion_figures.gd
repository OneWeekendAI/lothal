class_name PropulsionFigures
extends RefCounted
## The numbers the Propulsion rows, their page numbers and their charts all read (lab dock design
## §3): one computation per figure, so the list, the page and the drawing cannot disagree. The
## `FrameHardware` pattern, for Propulsion.
##
## Every figure is a composition of `Build` methods that already exist — nothing here is a second
## model. The one worth naming: `peak_each_g` is what THIS PACK can drive (nominal volts, sag, and
## the weakest link's throttle ceiling), which is not the catalogue's "max thrust" (a test stand at
## the test voltage with the motor's own current limit). On the reference build they are 1047 g and
## 1450 g; the row and the chart say which one they are.


## Peak thrust per motor on this pack, grams: `Build.peak_thrust` (sagged, capped) over four.
static func peak_each_g(build: Build) -> float:
	return float(build.peak_thrust()["thrust_n"]) / 4.0 / Build.GRAVITY_MPS2 * 1000.0


## The throttle the weakest link lets this build reach: `{fraction, limiter}`, limiter one of
## "motors", "pack", "ESC" — `Build.limiting_component`, in the builder's words.
static func throttle_ceiling(build: Build) -> Dictionary:
	var limiting := build.limiting_component()
	var limiter: String = {"motors": "motors", "battery": "pack", "esc": "ESC"}.get(
		str(limiting.get("name", "")), str(limiting.get("name", "")))
	return {"fraction": build.max_throttle_fraction(), "limiter": limiter}


## Thrust per motor against throttle, `Vector2(throttle, grams)`, `samples + 1` points from 0 to the
## throttle ceiling — `Build.thrust_at_throttle_n` (sag included), the curve peak_thrust searches.
static func thrust_curve_each_g(build: Build, samples: int = 60) -> Array:
	var out: Array = []
	var cap := build.max_throttle_fraction()
	for i in samples + 1:
		var t := cap * float(i) / float(samples)
		out.append(Vector2(t, build.thrust_at_throttle_n(t) / 4.0 / Build.GRAVITY_MPS2 * 1000.0))
	return out


## The motor's published test, as the catalogue states it: `{grams, volts, prop}` (prop by name).
## Read, not derived — it is drawn on the chart as the reference the curve is compared against.
static func catalogue_test(build: Build) -> Dictionary:
	var specs: Dictionary = build.motor.get("specs", {})
	var test: Dictionary = build.motor.get("thrust_test", {})
	var prop: Dictionary = build.catalog.get_part(str(test.get("prop_id", ""))) \
		if build.catalog != null else {}
	return {"grams": float(specs.get("max_thrust_g", 0.0)),
		"volts": float(test.get("voltage_v", 0.0)),
		"prop": str(prop.get("name", "")) if not prop.is_empty() else ""}


## What each motor must lift to hover: a quarter of the all-up weight, grams.
static func hover_each_g(build: Build) -> float:
	return build.all_up_weight_g() / 4.0


## The rpm the props turn at hover (sag included). 0 for a build that cannot hover.
static func hover_rpm(build: Build) -> float:
	if not build.can_hover():
		return 0.0
	return build.rpm_at_throttle(build.hover_throttle())


## The guards' added mass, grams: four rings, each `PropGuard.mass_kg` — the mass `Build.mass_parts`
## adds, not the catalogue's browsing figure. 0 with none fitted or a spec PropGuard refuses.
static func guard_added_g(build: Build) -> float:
	if build.guard.is_empty():
		return 0.0
	return PropGuard.mass_kg(build.guard.get("specs", {})) * 1000.0 * float(MotorLayout.MOTOR_NAMES.size())


## The fraction the guards add to roll inertia (I_ZZ — AirframeProperties' roll axis): this build's
## tensor against the same aircraft rebuilt without them. 0 with none fitted.
static func guard_roll_inertia_fraction(build: Build) -> float:
	if build.guard.is_empty() or guard_added_g(build) <= 0.0:
		return 0.0
	var bare := without_guard(build).mass_properties.inertia.z.z
	if bare <= 0.0:
		return 0.0
	return (build.mass_properties.inertia.z.z - bare) / bare


## Blade tip to the guard's inner wall, mm (`PropGuard.tip_clearance_mm` against the prop document
## the Prop sheet reads). NAN with none fitted or unreadable.
static func guard_tip_gap_mm(build: Build) -> float:
	if build.guard.is_empty():
		return NAN
	var doc := PropellerDetails.document_for(build.propeller)
	if doc == null:
		return NAN
	return PropGuard.tip_clearance_mm(build.guard.get("specs", {}), doc.radius_mm())


## The same aircraft with no guard: `Build.at_air`'s twin, less the guard.
static func without_guard(build: Build) -> Build:
	var ids := {}
	for category in Build.OPTIONAL_COMPONENTS:
		ids[category] = str((build.components[category] as Dictionary)["part_id"]) \
			if build.components.has(category) else ""
	var twin := Build.from_ids(build.catalog, str(build.frame["part_id"]),
		str(build.motor["part_id"]), str(build.propeller["part_id"]), str(build.battery["part_id"]),
		str(build.esc["part_id"]), str(build.fc["part_id"]), ids, build.air, "",
		build.harness.overrides())
	twin.set_assembly(build.assembly)
	twin.set_printing(build.printing)
	return twin

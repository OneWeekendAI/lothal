class_name ReferenceBuild
extends RefCounted
## The canonical 5" freestyle quad from docs/lothal/parts.md — the fixture every
## mass-properties and motor/propeller test is checked against. Hand-verified on paper
## before any code was written: 496 g all-up, 11.7:1 thrust-to-weight, 29% hover throttle.
##
## Geometry values are engineering estimates (frame/battery/electronics box dimensions,
## motor cylinder radius/height) where parts.md only specifies mass — real manufacturer
## dimensions get authored into data/parts/*.json in the day-5 parts catalog work.

const ARM_M := 0.110          # 5" freestyle frame, centre -> motor (parts.md)
const MOTOR_ONLY_MASS_G := 32.0   # 2207 1960KV motor alone
const PROP_MASS_G := 4.5          # 5x4.3x3 prop, lumped onto the motor for simplicity
const MOTOR_MASS_G := MOTOR_ONLY_MASS_G + PROP_MASS_G
const MOTOR_RADIUS_M := 0.011
const MOTOR_HEIGHT_M := 0.020
const MOTOR_KV := 1960.0
const MOTOR_MAX_THRUST_G := 1450.0   # 5x4.3x3 prop, 4S, per-motor manufacturer figure
const MOTOR_MAX_AMPS := 32.0

const FRAME_MASS_G := 110.0
const FRAME_SIZE_M := Vector3(0.150, 0.010, 0.150)

const BATTERY_MASS_G := 185.0
const BATTERY_SIZE_M := Vector3(0.070, 0.030, 0.035)
const BATTERY_CELLS := 4
const BATTERY_NOMINAL_V := 14.8
const BATTERY_MAH := 1500.0
const BATTERY_INTERNAL_R_OHM := 0.015

const ELECTRONICS_MASS_G := 55.0
const ELECTRONICS_SIZE_M := Vector3(0.030, 0.015, 0.030)

const MOTOR_NAMES := ["M1", "M2", "M3", "M4"]   # rear-right, front-right, rear-left, front-left

static func mass_parts() -> Array:
	var parts: Array = []

	var motor_mass_kg := MOTOR_MASS_G / 1000.0
	var motor_inertia := InertiaPrimitives.cylinder_y_axis(motor_mass_kg, MOTOR_RADIUS_M, MOTOR_HEIGHT_M)
	for name in MOTOR_NAMES:
		var pos := MotorLayout.motor_position(name, ARM_M)
		parts.append(PartMass.new(motor_mass_kg, pos, motor_inertia))

	parts.append(PartMass.new(
		FRAME_MASS_G / 1000.0, Vector3.ZERO, InertiaPrimitives.box(FRAME_MASS_G / 1000.0, FRAME_SIZE_M)
	))
	parts.append(PartMass.new(
		BATTERY_MASS_G / 1000.0, Vector3.ZERO, InertiaPrimitives.box(BATTERY_MASS_G / 1000.0, BATTERY_SIZE_M)
	))
	parts.append(PartMass.new(
		ELECTRONICS_MASS_G / 1000.0, Vector3.ZERO, InertiaPrimitives.box(ELECTRONICS_MASS_G / 1000.0, ELECTRONICS_SIZE_M)
	))

	return parts

static func motor_model() -> MotorModel:
	return MotorModel.new(MOTOR_KV)

static func propeller_k_t() -> float:
	return PropellerModel.fit_k_t(MOTOR_MAX_THRUST_G, MOTOR_KV * BATTERY_NOMINAL_V)

static func propeller_k_q() -> float:
	return PropellerModel.fit_k_q(propeller_k_t())

static func battery_model() -> BatteryModel:
	return BatteryModel.new(BATTERY_NOMINAL_V, BATTERY_INTERNAL_R_OHM, BATTERY_MAH)

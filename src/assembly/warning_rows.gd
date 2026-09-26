class_name WarningRows
extends RefCounted
## Which Lab-list row owns each warning, and the short (<= 40 character) form of it the row shows.
##
## Lab dock design §3 (plans/2026-09-26-lab-dock-design.md): "A warning appears once, on the row of
## the part that causes it", and the row carries at most ~40 characters — a number and its unit, or
## a limit. The full sentence stays where it always was, in `BuildWarning.message`, and is what the
## item's page shows behind "Why?".
##
## ONE TABLE, KEYED BY THE WARNING'S STABLE ID, and `BuildWarning._init` asks it. That is the whole
## wiring: every source of warnings (Build, the plausibility files, the harness, the course, the
## airframe model's fit checks) already constructs a `BuildWarning`, so every one of them gains an
## item and a short with no edit at the source — and the short is formatted from the SAME `values`
## the sentence was written from, so the two cannot drift apart.
##
## An id missing from this table is a loud failure, not a silent default: `tests/test_warning_rows.gd`
## scans `src/` for every id a warning is constructed with and names each one that has no row here.

## The longest a short may be: 38, so the row's "⚠ " prefix keeps line 3 within §3's ~40.
const SHORT_MAX := 38

## Row ids. Stable strings the section table (`SectionRows`) keys its rows by.
const FRAME := &"frame"
const ARMS := &"arms"
const HARDWARE := &"hardware"
const LAYOUT := &"layout"
const MOTORS := &"motors"
const PROPELLERS := &"propellers"
const GUARDS := &"guards"
const BATTERY := &"battery"
const ESC := &"esc"
const HARNESS := &"harness"
const FC := &"fc"
const RECEIVER := &"receiver"
const TUNE := &"tune"
const CAMERA := &"camera"
const VTX := &"vtx"
const PRINTED := &"printed"
const MOTOR_DIRECTION := &"motor_direction"
const PORTS := &"ports"
const FAILSAFE := &"failsafe"
const RATES := &"rates"
const COURSE := &"course"
const CONDITIONS := &"conditions"

## id -> [item, short]. `short` is either a fixed phrase or a format that `_format` fills from the
## warning's own values. Fixed phrases are used where the values carry no single deciding number.
const TABLE := {
	# Airframe
	&"custom_frame": [FRAME, "custom frame — unchecked"],
	&"implausible_frame_mass": [FRAME, "frame mass outside catalog range"],
	# FrameWarnings — what the drawn geometry alone says (airframe.md §7). The whole-frame ones sit on
	# Frame, whose page is the designer that fixes them; the two about one arm sit on Arms.
	&"frame_has_no_plates": [FRAME, "frame has no plates"],
	&"frame_has_no_arms": [FRAME, "frame has no arms"],
	&"frame_has_no_motors": [FRAME, "frame has no motors"],
	&"layout_not_controllable": [FRAME, "motor layout cannot be controlled"],
	&"frame_cg_off_axis": [FRAME, "{cg_off_axis}"],
	&"frame_is_directional": [FRAME, "{directional}"],
	&"arm_has_no_centreline": [ARMS, "an arm has no centreline"],
	&"arm_centreline_leaves_plate": [ARMS, "an arm centreline leaves its plate"],
	&"implausible_arm": [ARMS, "arm section outside catalog range"],
	&"frame_resonance": [ARMS, "{resonance}"],
	&"hover_on_resonance": [ARMS, "{hover_resonance}"],
	&"electronics_lump": [LAYOUT, "electronics mass is a lump"],
	&"screw_bottoms_out": [HARDWARE, "a screw bottoms out"],
	&"thread_engagement": [HARDWARE, "too little thread engaged"],
	&"hole_to_edge": [HARDWARE, "hole too close to the edge"],
	&"mount_attachment": [LAYOUT, "a part has nothing to mount to"],
	&"mount_pattern": [LAYOUT, "mount pattern does not match"],
	&"mount_overhang": [LAYOUT, "a part overhangs its mount"],
	&"mount_pattern_unknown": [LAYOUT, "mount pattern unknown"],
	&"component_in_prop_disc": [LAYOUT, "a part is in a prop disc"],
	&"pack_in_prop_disc": [LAYOUT, "pack is in a prop disc"],
	&"component_larger_than_plate": [LAYOUT, "a part is larger than the plate"],
	&"components_overlap": [LAYOUT, "two parts overlap"],
	&"pack_wider_than_plate": [LAYOUT, "pack is wider than the plate"],
	&"tight_prop_clearance": [LAYOUT, "{tight_clearance}"],
	# Propulsion
	&"prop_clearance": [PROPELLERS, "{prop_clearance}"],
	&"prop_overlap": [PROPELLERS, "props overlap each other"],
	&"prop_unloading": [PROPELLERS, "{prop_unloading}"],
	&"manoeuvre_headroom": [PROPELLERS, "{headroom}"],
	&"prop_extrapolation": [PROPELLERS, "~ extrapolated past thrust table"],
	&"custom_propeller": [PROPELLERS, "custom prop — unchecked"],
	&"implausible_blade_count": [PROPELLERS, "blade count implausible"],
	&"implausible_prop_mass": [PROPELLERS, "prop mass implausible"],
	&"unreadable_blade": [PROPELLERS, "blade cannot be read"],
	&"motor_mount": [MOTORS, "{motor_mount}"],
	&"cannot_hover": [MOTORS, "cannot hover"],
	&"climb_margin": [MOTORS, "{climb}"],
	&"custom_motor": [MOTORS, "custom motor — unchecked"],
	&"implausible_kv_for_stator": [MOTORS, "KV implausible for the stator"],
	&"implausible_test_voltage": [MOTORS, "test voltage implausible"],
	&"implausible_thrust_coefficient": [MOTORS, "thrust figures implausible"],
	&"implausible_thrust_density": [MOTORS, "thrust per gram implausible"],
	# current_limit's item depends on what binds — see `item_of`.
	&"current_limit": [MOTORS, "{current_limit}"],
	# Power
	&"pack_sag": [BATTERY, "{pack_sag}"],
	&"custom_battery": [BATTERY, "custom pack — unchecked"],
	&"implausible_li_ion_c_rating": [BATTERY, "Li-ion C rating implausible"],
	&"implausible_pack_mass_per_energy": [BATTERY, "pack mass per Wh implausible"],
	&"stack_mount": [ESC, "{stack_mount}"],
	&"custom_esc": [ESC, "custom ESC — unchecked"],
	&"esc_burst_below_continuous": [ESC, "burst rating below continuous"],
	&"esc_whole_board_rating": [ESC, "rating may be whole-board"],
	&"harness_ampacity": [HARNESS, "{ampacity}"],
	&"harness_voltage_drop": [HARNESS, "{lead_drop}"],
	&"connector_rating": [HARNESS, "{connector_rating}"],
	&"connector_mismatch": [HARNESS, "{connector_mismatch}"],
	&"capacitor_rule": [HARNESS, "capacitor advised"],
	# Control
	&"fc_stack_mount": [FC, "{stack_mount}"],
	&"fc_mass_budget": [FC, "{fc_mass}"],
	&"custom_flight_controller": [FC, "custom FC — unchecked"],
	&"no_receiver": [RECEIVER, "no receiver fitted"],
	&"buzzer_not_self_powered": [RECEIVER, "buzzer dies with the pack"],
	&"serial_peripherals": [PORTS, "parts want serial ports"],
	&"tune_override": [TUNE, "tune overridden by hand"],
	&"d_noise_ceiling": [TUNE, "D limited by gyro noise"],
	# Video
	&"camera_tilt_into_top_plate": [CAMERA, "{camera_tilt}"],
	&"camera_obstruction": [CAMERA, "{camera_obstruction}"],
	&"vtx_without_antenna": [VTX, "VTX has no antenna"],
	# Config
	&"motor_spin_unflyable": [MOTOR_DIRECTION, "motor directions cannot fly"],
	&"bidir_dshot_unsupported": [MOTOR_DIRECTION, "ESC lacks bidirectional DShot"],
	&"failsafe_gps_rescue_no_gps": [FAILSAFE, "GPS rescue with no GPS"],
	# Field
	&"field_air": [CONDITIONS, "{field_air}"],
	&"field_wind": [CONDITIONS, "{field_wind}"],
	&"course_gate_below_ground": [COURSE, "a gate is below ground"],
	&"course_ring_smaller_than_aircraft": [COURSE, "a ring is smaller than the drone"],
	&"course_rings_intersect": [COURSE, "two rings intersect"],
	&"course_route_through_gate": [COURSE, "route passes through a gate"],
	&"course_route_length": [COURSE, "route length noted"],
	&"course_tightest_turn": [COURSE, "tight turn on the route"],
	&"course_gate_intersects_obstacle": [COURSE, "a gate hits an obstacle"],
	&"course_route_through_obstacle": [COURSE, "route passes an obstacle"],
	&"course_outside_site_extent": [COURSE, "course leaves the site"],
}


static func has(id: StringName) -> bool:
	return TABLE.has(id)


## The row a warning belongs to. "" for an id the table does not know — which a test names.
static func item_of(id: StringName, values: Dictionary) -> StringName:
	if id == &"current_limit":
		# THE PART THAT BINDS OWNS IT (§3): the pack-current warning goes on Battery, not on
		# Motors, ESC and Battery at once.
		match str(values.get("limited_by", "")):
			"battery": return BATTERY
			"esc": return ESC
			_: return MOTORS
	if not TABLE.has(id):
		return &""
	return (TABLE[id] as Array)[0]


## The row's third line for this warning: <= SHORT_MAX characters, formatted from its values.
static func short_of(id: StringName, values: Dictionary) -> String:
	if not TABLE.has(id):
		return ""
	var template := str((TABLE[id] as Array)[1])
	var text := _format(template, values) if template.begins_with("{") else template
	return _clip(text)


static func _clip(text: String) -> String:
	if text.length() <= SHORT_MAX:
		return text
	return text.substr(0, SHORT_MAX - 1) + "…"


static func _pct(fraction: Variant) -> int:
	return roundi(float(fraction) * 100.0)


static func _format(template: String, v: Dictionary) -> String:
	match template:
		"{current_limit}":
			var who: String = {"battery": "pack", "esc": "ESC"}.get(str(v.get("limited_by", "")), "motor")
			return "%s limits you to %d%% throttle" % [who, _pct(v.get("throttle_cap", 1.0))]
		"{pack_sag}":
			# The share of the nominal-volts (bench) thrust the sagging pack can still reach.
			return "sag cuts max thrust to %d%%" % _pct(v.get("usable_fraction", 1.0))
		"{prop_clearance}":
			return "props exceed %.1f\" clearance" % float(v.get("max_prop_inches", 0.0))
		"{motor_mount}":
			return "mount %s, frame %s" % [str(v.get("motor_pattern", "?")),
				str(v.get("frame_pattern", "?"))]
		"{stack_mount}":
			return "board %s, frame %s" % [str(v.get("board_pattern", "?")),
				str(v.get("frame_pattern", "?"))]
		"{fc_mass}":
			return "%d g over electronics budget" % roundi(float(v.get("excess_g", 0.0)))
		"{climb}":
			# (T:W - 1): the thrust left over above hover, in the aircraft's own weights. "climbs at
			# 10.4 g" read as a speed or a mass to a beginner.
			return "spare thrust = %.1f× its own weight" % float(v.get("climb_g", 0.0))
		"{headroom}":
			return "hovers at %d%% — little headroom" % _pct(v.get("hover_throttle", 0.0))
		"{prop_unloading}":
			return "%d%% thrust left at top speed" % _pct(v.get("thrust_fraction_at_top_speed", 0.0))
		"{tight_clearance}":
			return "%s %d mm from a prop disc" % [str(v.get("part", "part")),
				roundi(float(v.get("clearance_mm", 0.0)))]
		"{cg_off_axis}":
			return "CG %.1f mm off the axis" % float(v.get("offset_mm", 0.0))
		"{directional}":
			return "roll and pitch differ %.2f : 1" % float(v.get("ratio", 1.0))
		"{resonance}":
			return "~%d Hz mode inside throttle range" % roundi(float(v.get("resonance_hz", 0.0)))
		"{hover_resonance}":
			return "hover excites ~%d Hz mode" % roundi(float(v.get("resonance_hz", 0.0)))
		"{ampacity}":
			return "%s: %d AWG over its rating" % [str(v.get("segment", "lead")),
				int(v.get("awg", 0))]
		"{lead_drop}":
			# `~`: class-typical lead lengths and a guessed contact resistance (HarnessChecks).
			return "~%.2f V lost in main lead + plug" % float(v.get("harness_drop_v", 0.0))
		"{connector_rating}":
			return "plug rated %d A" % roundi(float(v.get("rating_a", 0.0)))
		"{connector_mismatch}":
			return "plug %s, pack %s" % [str(v.get("lead_family", "?")),
				str(v.get("pack_family", "?"))]
		"{camera_obstruction}":
			# The nearest fitted part and its angle — the same figure the Camera page's number reads
			# (`VideoFigures`); `~` because the lens sits where MountLayout seats the camera.
			return "%s ~%d° off lens axis" % [str(v.get("closest_name", "part")),
				roundi(float(v.get("closest_deg", 0.0)))]
		"{camera_tilt}":
			return "tilt %d° hits the top plate" % roundi(float(v.get("tilt_deg", 0.0)))
		"{field_air}":
			return "air %d%% thinner than sea level" % _pct(v.get("fraction_below_standard", 0.0))
		"{field_wind}":
			return "wind %d km/h" % roundi(float(v.get("wind_kmh", 0.0)))
	return template

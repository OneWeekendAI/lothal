class_name SectionRows
extends RefCounted
## What the Lab's right-hand list says for each section: lab dock design §3 and §4
## (plans/2026-09-26-lab-dock-design.md).
##
## DATA, NOT WIDGETS. `DEFINITIONS` is the §4 table — which rows a section has, what each row's
## page is, and which rail its choice line summons the finder over — and `rows()` turns it into
## three lines per row with functions of a `Build` and nothing else. `SectionList` draws what this
## returns and decides nothing; the shell opens what a row's `page` names.
##
## ## The three lines (§3)
##
##   1. name + status dot: green `ok`, amber `warn`, red `bad`, grey `soon`.
##   2. what was chosen, in one short phrase.
##   3. the ONE number that decides the row, or `⚠ ` + the short form of the worst warning that
##      the row OWNS (`BuildWarning.item`). Never a sentence.
##
## ## Rows whose number is not wired
##
## Where no computed number is readily available the third line is EMPTY rather than invented
## (the brief: "do not invent numbers"). Today: Receiver & link (no receiver publishes an output
## power or a sensitivity, so a range would be invented), Printed parts and Course; and Tune until
## the shell hands it the tune in force (`context.tune`). Their
## warnings still reach line 3 through `item`, so an empty line 3 means "nothing wrong and no number
## yet", not "unchecked".

const SECTIONS := ["Airframe", "Propulsion", "Power", "Control", "Video", "Printed", "Config",
	"Ground kit", "Field"]

const OK := "ok"
const WARN := "warn"
const BAD := "bad"
const SOON := "soon"

## A row: `id` (matches `WarningRows` item ids), `name`, `page` — `{"panels": [tab titles]}` for
## Lab's spec panels or `{"room": id}` for a room the shell owns — `pick`, the rail title whose
## finder the choice line opens, and `soon` for a row with no model behind it.
##
## `page.column` names a rail that must stand beside the page because the finder cannot open it
## (an `ElectronicsPicker` fits several bays at once; see `GlassShell._column_rail_titles`).
const DEFINITIONS := {
	"Airframe": [
		{"id": &"frame", "name": "Frame", "page": {"room": "frame"}, "pick": "Frame"},
		# `diagram`: the page draws its item in plan beside the sheet (`FramePlanDiagram`'s modes).
		# Structure and the catalogue Frame sheet are the Frame page's, in the designer's drawer.
		{"id": &"arms", "name": "Arms", "page": {"panels": ["Arms"], "diagram": "arms"}},
		{"id": &"hardware", "name": "Screws & standoffs",
			"page": {"panels": ["Fasteners"], "diagram": "hardware"}},
		{"id": &"layout", "name": "Layout & fit",
			"page": {"panels": ["Fit", "Layout"], "diagram": "layout"}},
		# §6 of the airframe design models a pad as a spring and nothing of that is built.
		{"id": &"straps", "name": "Straps & pads", "soon": true},
	],
	"Propulsion": [
		# `diagram`: PropulsionDiagram's modes. `sheet`: which half of the Prop panel the page shows
		# (PropellerDetails.set_dock_sheet) — the blade's rows, or the guard's selector alone.
		{"id": &"motors", "name": "Motors", "page": {"panels": ["Motor"], "diagram": "thrust"},
			"pick": "Motor"},
		{"id": &"propellers", "name": "Propellers",
			"page": {"panels": ["Prop"], "diagram": "prop", "sheet": "prop"}, "pick": "Prop"},
		{"id": &"guards", "name": "Prop guards",
			"page": {"panels": ["Prop"], "diagram": "guard", "sheet": "guard"}},
		{"id": &"soft_mounts", "name": "Soft mounts", "soon": true},
	],
	"Power": [
		# `diagram`: PowerDiagram's modes (the pack's sag chart, one ESC channel), and "harness" —
		# the designer's own HarnessSchematic, read-only, beside the Harness sheet and its door.
		{"id": &"battery", "name": "Battery", "page": {"panels": ["Pack"], "diagram": "pack"},
			"pick": "Pack"},
		{"id": &"esc", "name": "ESC", "page": {"panels": ["ESC"], "diagram": "esc"}, "pick": "ESC"},
		{"id": &"harness", "name": "Harness", "page": {"panels": ["Harness"], "diagram": "harness"}},
	],
	"Control": [
		{"id": &"fc", "name": "Flight controller", "page": {"panels": ["FC"]}, "pick": "FC"},
		{"id": &"receiver", "name": "Receiver & link",
			"page": {"panels": ["Link"], "column": "Link"}},
		{"id": &"tune", "name": "Tune", "page": {"panels": ["Tune"]}},
	],
	"Video": [
		{"id": &"camera", "name": "Camera",
			"page": {"panels": ["Camera", "Electronics"], "column": "Electronics"}},
		{"id": &"vtx", "name": "VTX & antenna",
			"page": {"panels": ["Electronics"], "column": "Electronics"}},
	],
	# One row per generated part, expanded in `rows()` — the list is a function of the build.
	"Printed": [
		{"id": &"printed", "name": "Printed parts", "page": {"panels": ["Print"]},
			"each_printed_part": true},
	],
	"Config": [
		{"id": &"motor_direction", "name": "Motor direction", "page": {"panels": ["Motors"]}},
		{"id": &"ports", "name": "Ports", "page": {"panels": ["Ports"]}},
		{"id": &"failsafe", "name": "Failsafe", "page": {"panels": ["Failsafe"]}},
		{"id": &"rates", "name": "Rates", "page": {"panels": ["Rates"]}},
		{"id": &"sheet", "name": "Sheet", "page": {"panels": ["Sheet"]}},
	],
	"Ground kit": [
		{"id": &"radio", "name": "Radio", "soon": true},
		{"id": &"goggles", "name": "Goggles", "soon": true},
		{"id": &"charger", "name": "Charger", "soon": true},
		{"id": &"tools", "name": "Tools", "soon": true},
	],
	"Field": [
		{"id": &"site", "name": "Site", "page": {"room": "field"}},
		{"id": &"course", "name": "Course", "page": {"room": "field"}},
		{"id": &"conditions", "name": "Conditions", "page": {"room": "field"}},
	],
}


## The rows of one section, each `{id, name, choice, number, line3, status, page, pick, soon}`.
##
## `warnings` is every warning the caller holds about this build — `Build.warnings()` plus the
## airframe model's fit checks — and each row takes only the ones whose `item` is its own id.
## `context` carries what a Build does not know: `site`, `course` and `conditions` names; the
## `frame_document` (AirframeDocument) Screws & standoffs reads; and `prop_clearance`
## (`AirframeModel.closest_to_prop()`), Layout & fit's number.
static func rows(section: String, build: Build, warnings: Array = [],
		context: Dictionary = {}) -> Array:
	var out: Array = []
	for definition in DEFINITIONS.get(section, []):
		var row: Dictionary = (definition as Dictionary).duplicate(true)
		if bool(row.get("each_printed_part", false)):
			out.append_array(_printed_rows(row, build))
			continue
		out.append(_resolve(row, build, warnings, context))
	return out


## "N of M": rows decided of rows modelled (§4). A `soon` row is not modelled, so it counts in
## neither; a red row is not decided.
static func count(rows_list: Array) -> Vector2i:
	var decided := 0
	var modelled := 0
	for row in rows_list:
		if bool(row.get("soon", false)):
			continue
		modelled += 1
		# Decided is "not red": a part row with nothing chosen is already red (`_resolve`), and a
		# settings row with no choice line still has a setting in force.
		if str(row["status"]) != BAD:
			decided += 1
	return Vector2i(decided, modelled)


static func header_text(rows_list: Array) -> String:
	var c := count(rows_list)
	return "%d of %d" % [c.x, c.y]


static func _resolve(row: Dictionary, build: Build, warnings: Array, context: Dictionary) -> Dictionary:
	row["choice"] = ""
	row["number"] = ""
	row["line3"] = ""
	row["why"] = []
	row["warnings"] = []
	if bool(row.get("soon", false)):
		row["status"] = SOON
		return row
	var id: StringName = row["id"]
	row["choice"] = choice_of(id, build, context) if build != null else ""
	row["number"] = number_of(id, build, context) if build != null else ""
	var worst := _worst_owned(id, warnings)
	var owned: Array[BuildWarning] = []
	for w in warnings:
		if w is BuildWarning and (w as BuildWarning).item == id:
			owned.append(w as BuildWarning)
			(row["why"] as Array).append((w as BuildWarning).long())
	# The page's list: short + "Why?" each, most severe first (stable within a severity).
	row["warnings"] = Array(BuildWarning.by_severity(owned))
	row["status"] = OK
	row["line3"] = str(row["number"])
	if worst != null and worst.severity != BuildWarning.Severity.CHARACTERISTIC:
		row["status"] = BAD if worst.severity == BuildWarning.Severity.IMPOSSIBLE else WARN
		row["line3"] = "⚠ " + worst.short
	elif str(row["choice"]) == "" and row.has("pick"):
		# Nothing chosen for a row that is a part choice: red, §3 — "not chosen yet".
		row["status"] = BAD
	return row


## The most severe warning this row owns, first-emitted within a severity. Null for none.
static func _worst_owned(id: StringName, warnings: Array) -> BuildWarning:
	var worst: BuildWarning = null
	for w in warnings:
		if not (w is BuildWarning):
			continue
		var entry := w as BuildWarning
		if entry.item != id:
			continue
		if worst == null or entry.severity < worst.severity:
			worst = entry
	return worst


static func _printed_rows(template: Dictionary, build: Build) -> Array:
	var out: Array = []
	if build == null:
		return out
	for part in PrintedParts.for_build(build):
		var row := template.duplicate(true)
		row.erase("each_printed_part")
		row["id"] = StringName("printed:%s" % str(part.get("id", "")))
		row["name"] = str(part.get("label", part.get("id", ""))).split(" — ")[0]
		row["choice"] = "exportable" if bool(part.get("exportable", true)) else "not printable"
		row["number"] = ""
		row["line3"] = ""
		row["why"] = []
		row["status"] = OK
		out.append(row)
	return out


# ---------------------------------------------------------------------------
# Line 2 — what was chosen
# ---------------------------------------------------------------------------

static func choice_of(id: StringName, build: Build, context: Dictionary = {}) -> String:
	match id:
		&"frame":
			return _frame_choice(build.frame)
		&"arms":
			return str((build.frame.get("catalog", {}) as Dictionary).get("material", ""))
		&"hardware":
			return FrameHardware.choice(context.get("frame_document") as AirframeDocument)
		&"layout":
			var stack := str((build.frame.get("specs", {}) as Dictionary).get("stack_mount", ""))
			return "stack %s" % stack if stack != "" else ""
		&"motors":
			return _motor_choice(build.motor)
		&"propellers":
			return _prop_choice(build.propeller)
		&"guards":
			return str(build.guard.get("name", "none")) if not build.guard.is_empty() else "none"
		&"battery":
			return _battery_choice(build.battery)
		&"esc":
			return _esc_choice(build.esc)
		&"harness":
			return _harness_choice(build)
		&"fc":
			return _fc_choice(build.fc)
		&"receiver":
			return _component_name(build, "receiver")
		&"tune":
			var tune := context.get("tune") as RateTune
			return "hand-tuned" if tune != null and tune.has_overrides() else "derived"
		&"camera":
			return _component_name(build, "camera")
		&"vtx":
			return _component_name(build, "vtx")
		&"motor_direction":
			# The same default `ConfigMotorsPanel` reads; a Dictionary is a per-motor custom map.
			var spin: Variant = build.config.get("motor_spin", "props_out")
			return "custom" if spin is Dictionary else str(spin).replace("_", " ")
		&"site", &"course", &"conditions":
			return str(context.get(String(id), ""))
	return ""


static func _frame_choice(frame: Dictionary) -> String:
	var specs: Dictionary = frame.get("specs", {})
	if frame.is_empty():
		return ""
	# The size CLASS ("5\""), not max_prop_inches — that is the clearance (5.1"), a spec.
	var size_class := str((frame.get("catalog", {}) as Dictionary).get("size_class", ""))
	var arm := float(specs.get("arm_mm", 0.0))
	if size_class == "" or arm <= 0.0:
		return str(frame.get("name", ""))
	# Wheelbase is motor to motor across the diagonal: two arms.
	return "%s · %d mm" % [size_class, roundi(arm * 2.0)]


static func _motor_choice(motor: Dictionary) -> String:
	var specs: Dictionary = motor.get("specs", {})
	if motor.is_empty():
		return ""
	return "%02d%02d · %d KV" % [roundi(float(specs.get("stator_diameter_mm", 0.0))),
		roundi(float(specs.get("stator_height_mm", 0.0))), roundi(float(specs.get("kv", 0.0)))]


static func _prop_choice(prop: Dictionary) -> String:
	var specs: Dictionary = prop.get("specs", {})
	if prop.is_empty():
		return ""
	return "%s × %s × %d" % [_trim(float(specs.get("diameter_inches", 0.0))),
		_trim(float(specs.get("pitch_inches", 0.0))), int(specs.get("blades", 0))]


static func _battery_choice(pack: Dictionary) -> String:
	var specs: Dictionary = pack.get("specs", {})
	if pack.is_empty():
		return ""
	return "%dS %d mAh" % [int(specs.get("cells", 0)), roundi(float(specs.get("mah", 0.0)))]


static func _esc_choice(esc: Dictionary) -> String:
	if esc.is_empty():
		return ""
	var kind := str((esc.get("catalog", {}) as Dictionary).get("board_class", ""))
	var amps := roundi(float((esc.get("specs", {}) as Dictionary).get("continuous_a", 0.0)))
	return ("%s %d A" % [kind, amps]).strip_edges()


static func _fc_choice(fc: Dictionary) -> String:
	if fc.is_empty():
		return ""
	var processor := str((fc.get("catalog", {}) as Dictionary).get("processor", ""))
	var pattern := str((fc.get("mounting", {}) as Dictionary).get("pattern", ""))
	if processor == "" or pattern == "":
		return str(fc.get("name", ""))
	return "%s · %s" % [processor, pattern]


static func _harness_choice(build: Build) -> String:
	if build.harness == null:
		return ""
	var awg := int(build.harness.value(Harness.MAIN_LEAD_AWG, build))
	var plug := str(build.harness.connector_row(build).get("name", ""))
	return ("%d AWG · %s" % [awg, plug]) if plug != "" else "%d AWG" % awg


static func _component_name(build: Build, category: String) -> String:
	var part: Dictionary = build.components.get(category, {})
	return str(part.get("name", "")) if not part.is_empty() else "none"


# ---------------------------------------------------------------------------
# Line 3 — the one number that decides the row (computed, never copied from a catalogue)
# ---------------------------------------------------------------------------

static func number_of(id: StringName, build: Build, context: Dictionary = {}) -> String:
	match id:
		&"hardware":
			# Geometry times density over the hardware the frame document derives (airframe.md §5)
			# — the preset's GUESS at the bag, not the bag you own, so it carries its `~`.
			var document := context.get("frame_document") as AirframeDocument
			var grams := FrameHardware.mass_g(document, AirframePanel.materials()) \
				if document != null else 0.0
			return "~%d g hardware" % roundi(grams) if grams > 0.0 else ""
		&"layout":
			# The part closest to a prop disc, measured off the assembled airframe
			# (`AirframeModel.closest_to_prop`). Inside a disc, the impossible warning says it.
			var closest: Dictionary = context.get("prop_clearance", {})
			if closest.is_empty():
				return ""
			return "%s %d mm from a prop" % [str(closest["part"]), roundi(float(closest["mm"]))]
		&"frame":
			return "%d g" % roundi(float(build.frame.get("mass_g", 0.0))) \
				if not build.frame.is_empty() else ""
		&"arms":
			# A guessed scale (VibrationModel's one constant), so it carries its `~` (§3).
			var model := VibrationModel.for_build(build)
			return "~%d Hz 1st mode" % roundi(model.resonance_hz) if model.resonance_hz > 0.0 else ""
		&"motors":
			# What THIS PACK drives each motor to (sag and the weakest link's ceiling included) —
			# not the catalogue's test-stand "max thrust", which the sheet beside it quotes. Said
			# in the row so the two numbers do not read as a contradiction.
			return "%d g max each on this pack" % roundi(PropulsionFigures.peak_each_g(build))
		&"propellers":
			if not build.can_hover():
				return ""
			return "hover %d%%" % roundi(build.hover_throttle() * 100.0)
		&"guards":
			# Computed (four PropGuard rings; the tensor with and without them), not the catalogue's
			# browsing mass. Empty with none fitted: "none" on line 2 already says it.
			var grams := PropulsionFigures.guard_added_g(build)
			if grams <= 0.0:
				return ""
			return "+%d g · roll inertia +%d%%" % [roundi(grams),
				roundi(PropulsionFigures.guard_roll_inertia_fraction(build) * 100.0)]
		&"battery":
			var minutes := build.flight_time_min()
			if minutes <= 0.0:
				return ""
			var seconds := roundi(minutes * 60.0)
			return "~%d:%02d flight" % [floori(seconds / 60.0), seconds % 60]
		&"esc":
			var continuous := build.esc_continuous_a()
			if continuous <= 0.0:
				return ""
			return "%d%% headroom" % roundi(build.esc_channel_headroom_a() / continuous * 100.0)
		&"harness":
			# The worst lead drop: the trunk at a fresh pack's full-throttle draw (PowerFigures), `~`
			# because the lead lengths are class defaults and the plug's resistance a guess.
			if build.harness == null:
				return ""
			return "~%.2f V lost in leads at %d A" % [PowerFigures.harness_drop_v(build),
				roundi(PowerFigures.worst_draw_a(build))]
		&"fc":
			# The UARTs the fitted parts want against the board's count — the class range carries
			# its `~`. Never the difference: ControlPlausibility refuses a spare-port figure.
			return ControlFigures.ports_used_text(build)
		&"tune":
			# The roll D in force against the D this board's gyro noise allows (RateTune's ceiling).
			# `~`: the noise figure is an upper bound (no D-term lowpass is modelled).
			var tune := context.get("tune") as RateTune
			var share := ControlFigures.d_ceiling_share(tune)
			return "D at ~%d%% of noise ceiling" % roundi(share * 100.0) if share > 0.0 else ""
		&"camera":
			var tilt := float(build.assembly_value(AssemblyTweaks.CAMERA_TILT)) \
				if build.assembly.has(AssemblyTweaks.CAMERA_TILT) else -1.0
			return "tilt %d°" % roundi(tilt) if tilt >= 0.0 else ""
		&"vtx":
			var grams := 0.0
			for category in ["vtx", "antenna"]:
				grams += float((build.components.get(category, {}) as Dictionary).get("mass_g", 0.0))
			return "%.1f g" % grams if grams > 0.0 else ""
		&"motor_direction", &"ports", &"failsafe", &"rates":
			return "✓"
		&"site":
			return "%d m" % roundi(build.air.elevation_m) if build.air != null else ""
		&"conditions":
			return "%.2f kg/m³" % build.air.kgm3() if build.air != null else ""
	return ""


# ---------------------------------------------------------------------------
# A page's two summary numbers — the mockup's "Frame mass / Arm 1st mode" pair under the drawing
# ---------------------------------------------------------------------------

## `[[label, value], [label, value]]` for the rows whose page shows a summary pair, else `[]`. Same
## sources as the row's line 3 and the sheet beside it, never a third derivation. `context` as
## `rows()`, plus `pack_side_mm` (AirframeModel.battery_overhang_m().lateral, mm; negative clears).
static func page_numbers(id: StringName, build: Build, context: Dictionary = {}) -> Array:
	var document := context.get("frame_document") as AirframeDocument
	match id:
		&"arms":
			var mode := VibrationModel.for_build(build).resonance_hz
			var stock := FrameHardware.arm_thickness_mm(document)
			return [["1st mode, motors on", "~%d Hz" % roundi(mode) if mode > 0.0 else "—"],
				["Arm stock", "%.1f mm" % stock if stock > 0.0 else "—"]]
		&"hardware":
			var grams := FrameHardware.mass_g(document, AirframePanel.materials()) \
				if document != null else 0.0
			var screws := FrameHardware.screw_summary(document)
			return [["Hardware", "~%d g" % roundi(grams) if grams > 0.0 else "—"],
				["Screws", screws if screws != "" else "—"]]
		&"layout":
			var closest: Dictionary = context.get("prop_clearance", {})
			var side := "—"
			if context.has("pack_side_mm"):
				var mm := float(context["pack_side_mm"])
				side = "%d mm over" % roundi(mm) if mm > 0.0 else "%d mm clear" % roundi(-mm)
			return [["Closest to a prop", "%s · %d mm" % [str(closest["part"]),
					roundi(float(closest["mm"]))] if not closest.is_empty() else "—"],
				["Pack, each side", side]]
		&"motors":
			var ceiling := PropulsionFigures.throttle_ceiling(build)
			return [["Max each, this pack", "%d g" % roundi(PropulsionFigures.peak_each_g(build))],
				["Throttle ceiling", "%d%% · %s" % [roundi(float(ceiling["fraction"]) * 100.0),
					str(ceiling["limiter"])]]]
		&"propellers":
			if not build.can_hover():
				return [["Hover throttle", "won't hover"], ["Hover rpm", "—"]]
			return [["Hover throttle", "%d%%" % roundi(build.hover_throttle() * 100.0)],
				["Hover rpm", "%d rpm" % roundi(PropulsionFigures.hover_rpm(build))]]
		&"guards":
			var grams := PropulsionFigures.guard_added_g(build)
			if grams <= 0.0:
				return [["Added mass", "none fitted"], ["Roll inertia", "—"]]
			return [["Added mass", "+%d g" % roundi(grams)],
				["Roll inertia", "+%d%%" % roundi(PropulsionFigures.guard_roll_inertia_fraction(build) * 100.0)]]
		&"battery":
			# The worst case (a fresh pack at the throttle ceiling) against the pack's rating, and
			# what that draw costs in volts — the two things the sag chart is about.
			# The rating as the Pack sheet prints it ("%.0f"): 112.5 A must not read 113 here and
			# 112 beside it.
			return [["Full-throttle draw", "%d A of %.0f A" % [roundi(PowerFigures.worst_draw_a(build)),
					PowerFigures.pack_limit_a(build)]],
				["Sag at full throttle", "−%.1f V" % PowerFigures.worst_sag_v(build)]]
		&"esc":
			var channel := PowerFigures.esc_channel(build)
			var rating := float(channel["rating"])
			if rating <= 0.0:
				return [["Headroom per channel", "—"], ["Motors' max per channel", "—"]]
			return [["Headroom per channel", "%d A · %d%%" % [roundi(float(channel["headroom"])),
					roundi(float(channel["headroom"]) / rating * 100.0)]],
				["Motors' max per channel", "%d A of %d A" % [roundi(float(channel["motor_max"])),
					roundi(rating)]]]
		&"harness":
			if build.harness == null:
				return [["Lead drop, full throttle", "—"], ["Harness mass", "—"]]
			return [["Lead drop, full throttle", "~%.2f V at %d A" % [PowerFigures.harness_drop_v(build),
					roundi(PowerFigures.worst_draw_a(build))]],
				["Harness mass", "~%.1f g" % PowerFigures.harness_mass_g(build)]]
		&"fc":
			var figure := ControlFigures.ports_figure(build)
			var tune := context.get("tune") as RateTune
			return [["Serial ports used", "%d of %s" % [ControlFigures.serial_demand(build), figure]
					if figure != "" else "%d · count unpublished" % ControlFigures.serial_demand(build)],
				["Gyro noise at the motors", "~%.1f%% at D %.3f" % [
					ControlFigures.d_noise_fraction(build, tune) * 100.0, ControlFigures.installed_kd(tune)]]]
		&"receiver":
			return [["Link mass", "%.1f g" % ControlFigures.link_mass_g(build)],
				["UARTs it takes", "%d" % ControlFigures.link_uarts(build)]]
		&"tune":
			var tune := context.get("tune") as RateTune
			if tune == null:
				return [["Roll D vs noise ceiling", "—"], ["Loop τ roll · pitch · yaw", "—"]]
			var tau := ControlFigures.time_constants_ms(tune)
			var ceiling := "%.3f of %.3f" % [tune.kd.x, tune.kd_ceiling] if is_finite(tune.kd_ceiling) \
				else "%.3f · no ceiling" % tune.kd.x
			return [["Roll D vs noise ceiling", ceiling],
				["Loop τ roll · pitch · yaw", "%d · %d · %d ms" % [roundi(tau.x), roundi(tau.y),
					roundi(tau.z)]]]
	return []


static func _trim(value: float) -> String:
	var text := "%.1f" % value
	return text.trim_suffix(".0")

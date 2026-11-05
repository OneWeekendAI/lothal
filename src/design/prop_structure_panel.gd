class_name PropStructurePanel
extends VBoxContainer
## The Structure tab (PD9). Every number is `PropStructure` or `BladeGeometry`.
##
## NO BREAK WARNING, on purpose. The root model reads under 1 at 25,000 rpm (scaled by diameter) on
## 14 of 20 shelf props, and those props fly daily, so the factor is shown neutrally for comparing
## designs. Flex has the same pessimism and is equally neutral. The one warning here is tip Mach,
## exact arithmetic against the model's stated limit.

const ROWS := ["mass", "cg", "inertia", "balance", "tracking", "stress", "factor", "overspeed", "flex", "tip_mach"]
const NAMES := {
	"mass": "Mass", "cg": "Blade CG", "inertia": "Inertia", "balance": "Balance", "tracking": "Tracking",
	"stress": "Root stress", "factor": "Root factor", "overspeed": "Factor 1 at", "flex": "Flex", "tip_mach": "Tip Mach",
}
const NEUTRAL_NOTE := "Estimates, for comparing designs. Not a prediction of breakage: shelf props that fly daily also read under 1 here."
const STEP_HEAVY_MG := 5.0
const HEAVY_RANGE_MG := Vector2(0.0, 200.0)
const TRACKING_MM := 1.0

var shell: PropDesigner
var heavy_mg := 10.0
var details_open := false
var figs: Dictionary = {}
var last: Dictionary = {}

var note_label: Label
var warning_label: Label
var details_label: Label
var details_toggle: CheckButton
var rpm_value: Label
var heavy_value: Label


func _init(p_shell: PropDesigner) -> void:
	shell = p_shell
	add_theme_constant_override("separation", LothalTheme.SPACE_2)
	note_label = _line("StructureNote")
	note_label.text = NEUTRAL_NOTE
	var grid := shell._figure_grid(ROWS, func(k: String) -> String: return NAMES[k], figs, 110.0)
	grid.name = "StructureFigures"
	add_child(grid)
	warning_label = _line("StructureWarning")
	warning_label.add_theme_color_override("font_color", DesignSpace.WARN_INK)
	rpm_value = shell._add_stepper(self, "StructureRpm", "Rpm", "The rpm for these figures.",
		func(): shell.step_rpm(-PropDesigner.STEP_RPM), func(): shell.step_rpm(PropDesigner.STEP_RPM), 90.0)
	heavy_value = shell._add_stepper(self, "StructureHeavy", "Heavy blade", "How much heavier one blade is than the others.",
		func(): set_heavy(heavy_mg - STEP_HEAVY_MG), func(): set_heavy(heavy_mg + STEP_HEAVY_MG), 90.0)
	details_toggle = CheckButton.new()
	details_toggle.name = "StructureDetailsToggle"
	details_toggle.text = "Details"
	details_toggle.toggled.connect(set_details)
	add_child(details_toggle)
	details_label = _line("StructureDetails")


func _line(node_name: String) -> Label:
	var l := shell._faint("")
	l.name = node_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func set_heavy(mg: float) -> void:
	heavy_mg = clampf(mg, HEAVY_RANGE_MG.x, HEAVY_RANGE_MG.y)
	shell._rederive()


func set_details(open: bool) -> void:
	details_open = open
	shell._rederive()


func _put(key: String, text: String, tag: String) -> void:
	(figs[key] as Label).text = text
	(figs[key + "_tag"] as Label).text = tag


func refresh() -> void:
	var doc := shell.doc
	var rpm := shell.rpm
	var f := shell.figures()
	rpm_value.text = "%d rpm" % roundi(rpm)
	heavy_value.text = "%d mg" % roundi(heavy_mg)
	details_toggle.set_pressed_no_signal(details_open)
	_put("mass", "%.2f g" % float(f.mass_g), "solid section, with hub")
	_put("cg", "%.1f mm" % float(f.cg_mm), "from the shaft")
	_put("inertia", "%.1f g·cm²" % float(f.inertia_gcm2), "blades only")
	var force := BladeGeometry.imbalance_force_n(heavy_mg, float(f.cg_mm), rpm)
	_put("balance", "%.1f N" % force, "1x, %d mg heavy" % roundi(heavy_mg))
	var couple := BladeGeometry.tracking_couple_nm(doc, shell.materials, TRACKING_MM, rpm)
	_put("tracking", "%.3f N·m" % couple, "1 mm out of track (est.)")
	_put("tip_mach", "%.2f" % float(f.tip_mach), "at %d rpm" % roundi(rpm))
	warning_label.text = PropTunnel.FLAG_MACH if float(f.tip_mach) > PropTunnel.MACH_FLAG else ""
	warning_label.visible = warning_label.text != ""
	last = PropStructure.assess(doc, shell.materials, rpm)
	if not last.ok:
		for key: String in ["stress", "factor", "overspeed", "flex"]:
			_put(key, "–", "")
		(figs["stress_tag"] as Label).text = String(last.reason)
	else:
		_put("stress", "%.0f MPa" % float(last.stress_mpa), "(est.)")
		_put("factor", "%.2f" % float(last.factor), "strength / stress (est.)")
		var over := float(last.overspeed_rpm)
		_put("overspeed", "%d rpm" % roundi(over) if over > 0.0 else "–", "(est.)")
		_put("flex", "%.1f mm" % float(last.flex_mm), "%.0f %% of radius (est.)" % float(last.flex_pct_radius))
	details_label.visible = details_open
	details_label.text = _details() if details_open else ""


func _details() -> String:
	var root := "Root t/c %.2f, from %s." % [PropStructure.root_thickness_ratio(shell.doc), PropStructure.ROOT_THICKNESS_SOURCE]
	if not last.ok:
		return root
	return "%s Rectangle section, at the first chord station. Pull %.0f MPa, bending %.0f MPa, strength %.0f MPa. Left out: blade pitch, torque bending, centrifugal stiffening, printed layer lines, fatigue. Flex does not reach the aero." % [
		root, float(last.centrifugal_mpa), float(last.bending_mpa), float(last.strength_mpa)]

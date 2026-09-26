class_name AirframePageChecks
extends RefCounted
## The Airframe section of the Lab dock on a laid-out shell: its rows read the LIVE geometry — the
## frame document the pages render and the assembled airframe — and each row's page shows its own
## item. Called from `TestShellLayout.run` after `LabDockChecks`, for the reason that file gives:
## these are claims about what ended up on screen, and only that suite processes frames.
##
## One result per case, never a loop.

const SETTLE := 4


static func run(shell: GlassShell, tree: SceneTree, _window: Vector2i) -> Array:
	var out: Array = []
	shell.back_to_drone()
	shell.select_system_by_name("Airframe")
	await _settle(tree)
	out.append(_hardware_row_reads_the_live_document(shell))
	out.append(_hardware_row_carries_the_joint_verdict(shell))
	out.append(_layout_row_reads_the_assembled_airframe(shell))
	out.append_array(await _an_edit_in_the_designer_reaches_the_row(shell, tree))
	shell.back_to_drone()
	shell.select_system_by_name("Propulsion")
	await _settle(tree)
	return out


static func _settle(tree: SceneTree) -> void:
	for i in SETTLE:
		await tree.process_frame


static func _row(shell: GlassShell, id: StringName) -> Dictionary:
	for row in shell.section_list().rows():
		if row["id"] == id:
			return row
	return {}


static func _show(row: Dictionary) -> String:
	return "choice='%s' number='%s' line3='%s' status=%s" % [row.get("choice"), row.get("number"),
		row.get("line3"), row.get("status")]


static func _hardware_row_reads_the_live_document(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"hardware")
	var document := shell.lab.frame_document
	var grams := FrameHardware.mass_g(document, AirframePanel.materials())
	return TestResult.new("airframe dock: Screws & standoffs reads the frame document the page shows",
		document != null and row.get("choice") == FrameHardware.choice(document)
			and row.get("number") == "~%d g hardware" % roundi(grams), _show(row))


static func _hardware_row_carries_the_joint_verdict(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"hardware")
	var joint := FrameHardware.joint_warnings(shell.lab.frame_document)
	var want_status := SectionRows.OK if joint.is_empty() else (
		SectionRows.BAD if joint[0].severity == BuildWarning.Severity.IMPOSSIBLE else SectionRows.WARN)
	var want_line3 := str(row.get("number")) if joint.is_empty() else "⚠ " + joint[0].short
	return TestResult.new("airframe dock: Screws & standoffs shows the joint check the page runs",
		row.get("status") == want_status and row.get("line3") == want_line3,
		_show(row) + " joint=%d" % joint.size())


static func _layout_row_reads_the_assembled_airframe(shell: GlassShell) -> TestResult:
	var row := _row(shell, &"layout")
	var closest := shell.lab.airframe.closest_to_prop()
	var want := "%s %d mm from a prop" % [str(closest.get("part", "?")),
		roundi(float(closest.get("mm", 0.0)))]
	return TestResult.new("airframe dock: Layout & fit quotes the assembled airframe's worst clearance",
		not closest.is_empty() and row.get("number") == want, _show(row) + " want '%s'" % want)


## Drawing in the Frame page changes the hardware, so the row under it must follow — on the next
## frame, not on the next section change.
static func _an_edit_in_the_designer_reaches_the_row(shell: GlassShell, tree: SceneTree) -> Array:
	var out: Array = []
	var before := shell.lab.frame_document
	var bare := AirframeDocument.from_dictionary(before.to_dictionary())
	bare.hardware = []
	shell.workbench().document_changed.emit(bare)
	await _settle(tree)
	var row := _row(shell, &"hardware")
	out.append(TestResult.new("airframe dock: removing the hardware in the designer empties the row",
		row.get("choice") == "" and row.get("number") == "", _show(row)))
	shell.workbench().document_changed.emit(before)
	await _settle(tree)
	return out

class_name StudioScreen
extends Control
## Studio — the flights a builder has already flown (LTHL-54).
##
## ===========================================================================
## WHAT THIS IS, AND WHY IT IS A ROOM RATHER THAN A REPORT
## ===========================================================================
##
## LTHL-20 was written as an interrupt: a report shown when a flight ends. That framing is right
## about WHEN this data becomes legible — post-flight, never mid-flight — and wrong about what to
## do to the pilot. Someone flying five test packs in a row does not want five room switches. So
## the report is a destination and landing offers a way in (LTHL-56) rather than taking one.
##
## IT IS NOT A LAB SCREEN, and that is the whole project's organising rule rather than a filing
## preference. Lab is the garage: the room that authors what the aircraft IS. A log is a record of
## what happened in the field. Putting a log browser inside the garage would put the reading of
## flights in the room that writes aircraft, which is the boundary labs-and-sim.md exists to hold.
##
## Studio writes nothing but its own deletions. No tune, no build, no course, no pack.
##
## ===========================================================================
## READING A LOG MUST NEVER RECONSTRUCT A BUILD
## ===========================================================================
##
## The report pane below displays header fields as TEXT IT WAS GIVEN. There is no path from a
## displayed fingerprint to PartsCatalog or Build.from_ids, and tests/test_flight_recorder.gd
## enforces that by reading this file's source alongside the recorder's and the library's.
##
## The temptation is worth naming here, in the file where someone will feel it: a builder looking
## at a log of a good flight will want a "fly this build again" button. THAT BUTTON IS THE BREACH.
## The fingerprint is in the file, the parts are in the garage, and walking back to Lab to pick
## them is the entire cost — which is the cost that keeps one parts catalog instead of two.
##
## ===========================================================================
## WHAT IS DELIBERATELY NOT HERE YET
## ===========================================================================
##
## No plot and no analysis. The trace column is built and left empty, which is not an oversight:
## it establishes the geometry LTHL-55 fills, and this slice is worth shipping without it because
## it is the first time a builder can see that flying produced anything at all.

## The three columns, in the widths LabScreen already proves. The rail matches the field editor's
## 292 and the report pane matches the parts details' 336, so a builder moving between rooms is
## not re-learning where things are.
const RAIL_WIDTH := 292.0
const REPORT_WIDTH := 336.0

## What the trace column says while LTHL-55 is unbuilt. Stated rather than left blank: an empty
## panel reads as a broken screen, and a panel that says what belongs there reads as a screen with
## a next step.
const TRACE_PLACEHOLDER := "The trace goes here.\n\nChannels, plotted over the flight's own clock."

var library: FlightLogLibrary
## Which log the builder is looking at. Held HERE and not in the library, because a selected log is
## where an eye happens to be and persisting it would be inventing a preference nobody expressed.
var selected_id := ""

var _list: ItemList
var _delete_button: Button
var _report: VBoxContainer


## Takes the library rather than building one, so a test can hand over a directory that is not the
## builder's real flight history. Same seam, and for the same reason, as the field editor's
## injected save path.
func _init(p_library: FlightLogLibrary = null) -> void:
	library = p_library if p_library != null else FlightLogLibrary.load_from()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	add_child(row)

	row.add_child(_build_flight_rail())
	row.add_child(_build_trace_column())
	row.add_child(_build_report_pane())

	render()


func _build_flight_rail() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(column)

	var title := Label.new()
	title.text = "FLIGHTS"
	title.theme_type_variation = &"TitleLabel"
	column.add_child(title)

	var note := Label.new()
	note.text = "Recorded with R in the field. Newest first."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(260, 0)
	note.theme_type_variation = &"MutedLabel"
	column.add_child(note)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_row_selected)
	column.add_child(_list)

	_delete_button = Button.new()
	_delete_button.text = "Delete flight"
	_delete_button.pressed.connect(delete_selected)
	column.add_child(_delete_button)

	return panel


## Empty in this slice, on purpose — see the class header.
func _build_trace_column() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = TRACE_PLACEHOLDER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"MutedLabel"
	panel.add_child(label)

	return panel


func _build_report_pane() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(REPORT_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	_report = VBoxContainer.new()
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_report)

	return panel


## ---------------------------------------------------------------------------
## One refresh path
## ---------------------------------------------------------------------------
##
## Rebuilds the list and the report together, the same way LabScreen's _on_selection_changed and
## the field editor's render() do. Partial updates are how a list and the pane beside it come to
## describe two different flights, and there is no state here expensive enough to justify the risk
## — listing is one line of I/O per file.
func render() -> void:
	_render_list()
	_render_report()
	_delete_button.disabled = selected_id.is_empty()


func _render_list() -> void:
	_list.clear()

	var ids := library.ids()
	if ids.is_empty():
		# An explanatory row rather than a blank list, following PartPicker's empty case. A builder
		# who has never pressed R sees an instruction, not a screen that looks broken.
		_list.add_item("No flights recorded yet")
		_list.set_item_disabled(0, true)
		_list.set_item_selectable(0, false)
		return

	for id in ids:
		var summary := library.row(id)
		# The warning is in the ROW, not only in the pane — see FlightLogLibrary.row(). A builder
		# about to compute a spectrum over a teleport should learn it before they pick the file.
		var mark: String = "!" if summary["warn"] else " "
		_list.add_item("%s  %s %s  %s" % [
			summary["when"], Duration.clock(round(summary["duration_s"])), mark,
			summary["aircraft"]])
		if summary["warn"]:
			# Exception: a discontinuous or unreadable log is a warning about the data, not a style
			_list.set_item_custom_fg_color(_list.item_count - 1, LothalTheme.WARNING)

	var index := Array(ids).find(selected_id)
	if index >= 0:
		_list.select(index)


func _render_report() -> void:
	for child in _report.get_children():
		child.queue_free()
		_report.remove_child(child)

	if selected_id.is_empty():
		_add_report_note("Pick a flight.")
		return

	var head := library.header(selected_id)
	if head.is_empty():
		# The house rule from json_store.gd, carried into the UI: a bad file is a warning and a
		# defaulted result, never a crash. The row stays listed and selectable precisely so the
		# builder can delete the thing.
		_add_report_title(selected_id)
		_add_report_note("This log's header could not be read. It may have been truncated by"
			+ " closing the app mid-write. Deleting it is safe.")
		return

	var aircraft: Dictionary = head.get("aircraft", {})

	_add_report_title("THE AIRCRAFT")
	# The FULL six-part fingerprint here, against the rail's truncation. The pane has the width for
	# it, and a truncated fingerprint is a display convenience that must never be the only spelling
	# on screen — see FlightLogLibrary.short_fingerprint.
	_add_report_row("fingerprint", str(aircraft.get("fingerprint", "—")))
	_add_report_row("mass", "%.3f kg" % float(aircraft.get("mass_kg", 0.0)))
	_add_report_row("arm", "%.0f mm" % (float(aircraft.get("arm_m", 0.0)) * 1000.0))
	_add_report_row("prop", "%.1f in, %d blades" % [
		float(aircraft.get("prop_diameter_m", 0.0)) / 0.0254,
		int(aircraft.get("blades", 0))])

	_add_report_title("THE RECORDING")
	_add_report_row("rows", str(head.get("rows", 0)))
	_add_report_row("duration", Duration.clock(round(float(head.get("duration_s", 0.0)))))
	_add_report_row("sample rate", "%.0f Hz" % float(head.get("sample_rate_hz", 0.0)))
	_add_report_row("decimation", str(head.get("decimation", 1)))

	# THE DISCONTINUITY BLOCK, and it is a warning rather than a row when it is nonzero. LTHL-51
	# put the count in the header precisely so a reader could not compute a spectrum across a
	# teleport without being told, and a count rendered as one more grey number beside "rows" is a
	# count that has been told to nobody.
	var jumps := int(head.get("discontinuities", 0))
	if jumps > 0:
		_add_report_warning("%d respawn teleport%s in this recording. The rows they happened on"
			% [jumps, "" if jumps == 1 else "s"]
			+ " are not marked, so position and velocity jump. Differencing across one gives an"
			+ " acceleration that never happened.")
	else:
		_add_report_row("continuous", "yes")

	_add_report_title("THE SENSOR")
	var gyro: Dictionary = head.get("gyro", {})
	_add_report_row("lowpass", "%.0f Hz" % float(gyro.get("lowpass_hz", 0.0)))
	_add_report_row("sample rate", "%.0f Hz" % float(gyro.get("sample_rate_hz", 0.0)))
	_add_report_row("source", str(gyro.get("source", "—")))

	_add_report_title("THE ASSEMBLY")
	var assembly: Dictionary = head.get("assembly", {})
	for key in assembly:
		_add_report_row(str(key).replace("_", " "), str(assembly[key]))

	# The tune is an explicit null when the recorder did not know it, and that is worth showing as
	# "not recorded" rather than as absent: a pane that silently omitted the block would look the
	# same as one flown on default gains.
	_add_report_title("THE TUNE")
	var tune: Variant = head.get("tune", null)
	if tune is Dictionary:
		for axis in tune:
			var gains: Dictionary = tune[axis]
			_add_report_row(str(axis), "P %.4f  I %.4f  D %.4f%s" % [
				float(gains.get("p", 0.0)), float(gains.get("i", 0.0)), float(gains.get("d", 0.0)),
				"  (overridden)" if bool(gains.get("overridden", false)) else ""])
	else:
		_add_report_note("Not recorded.")

	# The caveat travels with the vibration numbers, in the pane, not in a tooltip — validation.md
	# §9 makes this a tier-three characteristic model and LTHL-18 could not promote it. The ranking
	# between builds is trustworthy; the absolute frequency is not.
	_add_report_title("THE VIBRATION MODEL")
	var vibration: Dictionary = head.get("vibration_model", {})
	_add_report_row("resonance", "%.1f Hz" % float(vibration.get("resonance_hz", 0.0)))
	_add_report_row("damping", "%.4f" % float(vibration.get("damping_ratio", 0.0)))
	_add_report_row("imbalance", "%.4f kg" % float(vibration.get("imbalance_kg", 0.0)))
	_add_report_note(str(vibration.get("caveat", "")))


func _add_report_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"TitleLabel"
	_report.add_child(label)


func _add_report_row(key: String, value: String) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = key
	name_label.theme_type_variation = &"MutedLabel"
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.custom_minimum_size = Vector2(190, 0)
	value_label.theme_type_variation = &"ReadoutLabel"
	row.add_child(value_label)

	_report.add_child(row)


func _add_report_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(REPORT_WIDTH - 24.0, 0)
	label.theme_type_variation = &"MutedLabel"
	_report.add_child(label)


func _add_report_warning(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(REPORT_WIDTH - 24.0, 0)
	label.theme_type_variation = &"WarnLabel"
	_report.add_child(label)


## ---------------------------------------------------------------------------
## The two things a builder can do here
## ---------------------------------------------------------------------------

func select(id: String) -> bool:
	if not library.has(id):
		return false
	selected_id = id
	render()
	return true


func delete_selected() -> bool:
	if selected_id.is_empty():
		return false
	if not library.remove(selected_id):
		return false
	selected_id = ""
	render()
	return true


func _on_row_selected(index: int) -> void:
	var ids := library.ids()
	if index < 0 or index >= ids.size():
		return
	selected_id = ids[index]
	render()

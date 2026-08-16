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
## WHAT IS SHOWN, AND WHAT IS COMPUTED (LTHL-20)
## ===========================================================================
##
## The division that keeps this file honest: Studio shows what is IN a log, and anything computed
## FROM a log is a figure with a provenance and a caveat, and those arrive together or not at all.
##
## The arithmetic is all in FlightAnalysis and none of it is here. This file decides ORDER, which
## is its own decision and the one the design argued about: the gyro-vs-omega gap goes first and
## largest, above the header fields, because it is the number no real drone can produce about
## itself and it is the reason for simulating one.
##
## WHAT IS STILL NOT HERE: the export button, which is LTHL-56 along with the landing invitation.

## The three columns, in the widths LabScreen already proves. The rail matches the field editor's
## 292 and the report pane matches the parts details' 336, so a builder moving between rooms is
## not re-learning where things are.
const RAIL_WIDTH := 292.0
const REPORT_WIDTH := 336.0

## How much of the trace column the channel picker claims.
const CHANNEL_LIST_HEIGHT := 132.0

## The clock every channel is drawn against. Requested alongside whatever the builder picked, and
## never itself offered as a channel — plotting time against time is a diagonal line.
const TIME_COLUMN := "t_s"

## What a log opens showing, when it carries them.
##
## THE GAP BETWEEN THESE TWO IS THE PRODUCT'S WHOLE ARGUMENT. omega is what the aircraft did and
## gyro is what the flight controller was told, and no real drone can produce the difference about
## itself. Opening on anything else would bury the one thing this viewer can show that a Betaflight
## log viewer cannot, behind a builder knowing to go looking for it.
const DEFAULT_CHANNELS := ["omega_x_rad_s", "gyro_x_rad_s"]

## Columns a builder is unlikely to want first and which would crowd the top of the picker. Not
## hidden — the list is the header's, in the header's order, and filtering it would be this screen
## having an opinion about a log's contents. Only the DEFAULT selection is opinionated.
const MAX_CHANNELS := 6

var library: FlightLogLibrary
## Which log the builder is looking at. Held HERE and not in the library, because a selected log is
## where an eye happens to be and persisting it would be inventing a preference nobody expressed.
var selected_id := ""

var _list: ItemList
var _delete_button: Button
var _report: VBoxContainer
var _trace: TraceView
var _channel_list: ItemList
var _channel_note: Label
## The channel names offered by the log currently selected, in the header's own order. Empty when
## nothing is selected or the header could not be read.
var _available_channels := PackedStringArray()

## What FlightAnalysis made of the selected log. Null when nothing is selected, and rebuilt on
## selection rather than lazily: every figure in it comes from one pass over the file, and the
## alternative is that pass happening once per figure.
var analysis: FlightAnalysis = null
var _spectrum: SpectrumView = null


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


## The trace, and under it the channels to draw (LTHL-55).
func _build_trace_column() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(column)

	_trace = TraceView.new()
	_trace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_trace)

	_channel_note = Label.new()
	_channel_note.theme_type_variation = &"MutedLabel"
	column.add_child(_channel_note)

	# AN ItemList RATHER THAN A ROW OF CHECKBOXES, because the list is not a fixed set: it is
	# whatever the log's header says, which is 55 names today and 76 after LTHL-52. A wrapped row
	# of that many boxes is a wall; a multi-select list is scrollable and stays one control.
	_channel_list = ItemList.new()
	_channel_list.select_mode = ItemList.SELECT_MULTI
	_channel_list.max_columns = 0
	_channel_list.custom_minimum_size = Vector2(0, CHANNEL_LIST_HEIGHT)
	_channel_list.multi_selected.connect(_on_channel_toggled)
	column.add_child(_channel_list)

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
	_analyse_selected()
	_render_report()
	_render_channels()
	_delete_button.disabled = selected_id.is_empty()


## ---------------------------------------------------------------------------
## The channels, and where the list of them comes from
## ---------------------------------------------------------------------------
##
## THE PICKER IS THE HEADER'S `columns` ARRAY, not a list written here.
##
## This is what makes LTHL-52 free: its twenty-one control-side columns — rcCommand, the setpoint,
## the separated P, I and D terms, the motor commands, the mode — appear in Studio on the day they
## appear in a log, with no change to this file. A hardcoded picker would mean LTHL-52 carried a
## hidden Studio task inside it, discovered late.
##
## It also means old logs open with no special-casing: a file written before those columns existed
## simply offers fewer channels. That is the SCHEMA-stays-at-1 rule paying out in the one place a
## builder would notice it failing.
func _render_channels() -> void:
	_channel_list.clear()
	_available_channels = PackedStringArray()

	var head := library.header(selected_id) if not selected_id.is_empty() else {}
	if head.is_empty():
		_trace.clear()
		_channel_note.text = ""
		return

	var units: Dictionary = head.get("units", {})
	for column_name in head.get("columns", []):
		if str(column_name) == TIME_COLUMN:
			continue
		_available_channels.append(str(column_name))
		# THE UNIT COMES FROM THE FILE AND IS DISPLAYED, NEVER CONVERTED. Lothal is rad/s and
		# Betaflight is deg/s; a viewer that helpfully showed degrees because degrees are more
		# familiar would undo the entire discipline the UNITS table exists to enforce.
		var unit := str(units.get(column_name, ""))
		_channel_list.add_item(str(column_name) if unit.is_empty()
			else "%s  (%s)" % [column_name, unit])

	_select_default_channels()
	_load_selected_channels()


## Selects the opening channels, falling back when a log does not carry them. A pre-LTHL-51 log has
## no electrical_hz; a hypothetical future one might drop something else. Either way the viewer
## opens showing SOMETHING, because a chart that opens blank reads as a broken chart.
func _select_default_channels() -> void:
	var chosen := 0
	for wanted in DEFAULT_CHANNELS:
		var index := Array(_available_channels).find(wanted)
		if index >= 0:
			_channel_list.select(index, false)
			chosen += 1
	if chosen == 0 and _channel_list.item_count > 0:
		_channel_list.select(0, false)


func selected_channels() -> PackedStringArray:
	var out := PackedStringArray()
	for index in _channel_list.get_selected_items():
		if index >= 0 and index < _available_channels.size():
			out.append(_available_channels[index])
	return out


## Reads the picked channels out of the file and hands them to the trace.
##
## THE PARSE IS THE RUST CORE'S. A three-minute log is ~180 000 rows of 55 columns, and doing that
## in GDScript would be seconds of main thread every time a builder clicks a flight. LogReader
## takes the names so only the picked columns are turned into floats — two channels cost a
## twenty-seventh of parsing everything.
##
## A failed or truncated read is a note under the chart, never a crash: json_store.gd's rule, and
## the reason LogReader returns a reason string instead of aborting. A truncated log still draws
## the rows it had, because the flight that ended badly is usually the interesting one.
func _load_selected_channels() -> void:
	var picked := selected_channels()
	if picked.is_empty():
		_trace.clear()
		_channel_note.text = "Pick a channel."
		return

	var request := PackedStringArray([TIME_COLUMN])
	request.append_array(picked)
	var result: Dictionary = LogReader.read_columns(library.path_of(selected_id), request)

	if not bool(result.get("ok", false)):
		_trace.clear()
		_channel_note.text = "Could not read this log: %s" % result.get("reason", "unknown")
		return

	var columns: Dictionary = result.get("columns", {})
	var times: PackedFloat64Array = columns.get(TIME_COLUMN, PackedFloat64Array())
	var series: Dictionary = {}
	for channel in picked:
		if columns.has(channel):
			series[channel] = columns[channel]

	_trace.show_log(times, series)

	var note := "%d rows" % int(result.get("rows", 0))
	# Both of these are the file telling on itself, and both are worth saying out loud rather than
	# quietly drawing a shorter trace. A builder who cannot see that a log stopped early will read
	# the end of the chart as the end of the flight.
	var bad := int(result.get("bad_cells", 0))
	if bad > 0:
		note += "  ·  %d unreadable cells, drawn as gaps" % bad
	var reason := str(result.get("reason", ""))
	if not reason.is_empty():
		note += "  ·  " + reason
	_channel_note.text = note


func _on_channel_toggled(_index: int, _selected: bool) -> void:
	# Guarded rather than left to the builder's judgement, because the cost is not obvious from the
	# UI: each channel is another column parsed out of a file that may be 197 MB, and a builder who
	# selects all 55 to see what happens should get a refusal rather than a freeze.
	var picked := selected_channels()
	if picked.size() > MAX_CHANNELS:
		_channel_list.deselect(_index)
		_channel_note.text = "Six channels at a time. Deselect one first."
		return
	_load_selected_channels()


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


## The one expensive thing Studio does, and it happens once per flight picked.
##
## Roughly eleven columns of a file that may be 197 MB, plus an FFT over every analysis frame of
## it. All of it is in the native core; what is here is the decision to do it EAGERLY, on
## selection, rather than when each figure is first drawn. Lazily, a builder scrolling the report
## pane would pay for the same pass three times and feel it as the pane stuttering.
func _analyse_selected() -> void:
	analysis = null
	if selected_id.is_empty():
		return
	var head := library.header(selected_id)
	if head.is_empty():
		return
	analysis = FlightAnalysis.of(library.path_of(selected_id), head)


func _render_report() -> void:
	# The spectrum widget lives in the pane and the pane is rebuilt wholesale, so the handle has
	# to be dropped before the node behind it is freed. A stale _spectrum is not a crash in
	# GDScript, it is a silently ignored draw call on an orphan.
	_spectrum = null
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

	# MEASURED FROM THIS FLIGHT FIRST, DECLARED BY THE FILE SECOND. The rail already says which
	# aircraft this is, so leading with the fingerprint would spend the top of the pane repeating
	# the row the builder just clicked. What they cannot get anywhere else goes where the eye
	# lands.
	_render_gap()
	_render_d_cost()
	_render_spectrum(head)

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


## ---------------------------------------------------------------------------
## The figures, and the thing each of them is allowed to claim
## ---------------------------------------------------------------------------
##
## THE HEADLINE. A physical quad has exactly one angular rate — whatever its gyro says — and no
## way to find out how much of that was the airframe. Here omega is what the aircraft did, gyro is
## what the flight controller was told, and the ratio between their spreads is the amount of
## motion the sensor invented. That is what the D term amplifies into the motors, it is why FPV
## tuning is done by ear, and it is the one figure in this whole product that justifies simulating
## a drone instead of flying one.
func _render_gap() -> void:
	_add_report_title("SENSOR vs AIRCRAFT")
	if analysis == null or not analysis.ok:
		_add_report_note(analysis.reason if analysis != null else "Not analysed.")
		return
	if analysis.gap.is_empty():
		_add_report_note("This log carries no gyro/omega pair to compare.")
		return

	for axis in FlightAnalysis.AXES:
		if not analysis.gap.has(axis):
			continue
		var figures: Dictionary = analysis.gap[axis]
		var ratio := float(figures["ratio"])
		var hero := Label.new()
		# The largest text on the pane, per the design. INF is printed as a word rather than as a
		# number, because it is what a perfectly still axis honestly produces and "inf x" reads as
		# the answer it is: there was no motion to compare the noise against.
		hero.text = ("%s  %s" % [str(figures["label"]),
			("%.1fx" % ratio) if is_finite(ratio) else "no motion"])
		hero.theme_type_variation = &"SubHeroReadoutLabel"
		_report.add_child(hero)
		_add_report_row("  sensor / actual", "%.5f / %.5f rad/s sd" % [
			float(figures["sensor_sd"]), float(figures["truth_sd"])])

	_add_report_note("How much more motion the gyro reported than the aircraft had. Ground truth"
		+ " is not measurable on a real quad; it is measurable here, and that is the whole reason"
		+ " to fly one of these.")


## What that noise cost, in the units a builder acts on: fraction of full stick spent correcting
## motion that never happened. RateTune's own arithmetic, fed this flight's measured noise rather
## than the modelled figure — see RateTune.noise_fraction_for.
func _render_d_cost() -> void:
	if analysis == null or not analysis.ok:
		return
	_add_report_title("WHAT D COST")
	if analysis.d_cost.is_empty():
		_add_report_note(analysis.d_cost_reason if not analysis.d_cost_reason.is_empty()
			else "No D gain on any axis.")
		return
	for axis in FlightAnalysis.AXES:
		if not analysis.d_cost.has(axis):
			continue
		var figures: Dictionary = analysis.d_cost[axis]
		_add_report_row(str(figures["label"]), "%.2f%% of full command  (D %.4f)" % [
			float(figures["fraction"]) * 100.0, float(figures["kd"])])
	# STATED, not implied. The modelled figure strips the board's own white noise and bias so it
	# measures vibration alone; this one is the whole sensor path, because a log cannot separate
	# them. It is an upper bound on the vibration part and the number that actually reached the
	# motors, and calling it "vibration" would be the more flattering of two wrong labels.
	_add_report_note("RMS, from the gyro-minus-omega noise this flight actually had. That is the"
		+ " whole sensor path — vibration plus the board's own noise — so it is an upper bound on"
		+ " what vibration alone cost.")


## The spectrum, its marks, and the sentence that says what it is allowed to mean.
##
## The vibration model block follows IMMEDIATELY and that placement is the requirement, not a
## layout preference: the dashed "model" line on the chart is anchored on one guessed constant,
## and the caveat explaining that has to be in the same pane as the mark it is about. A tooltip
## or a footnote would be a caveat nobody reads attached to a number everybody does.
func _render_spectrum(p_head: Dictionary) -> void:
	_add_report_title("THE SPECTRUM")
	_spectrum = SpectrumView.new()
	_spectrum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report.add_child(_spectrum)

	if analysis == null or not analysis.ok or analysis.mags.is_empty():
		var why := analysis.spectrum_reason if analysis != null else ""
		_spectrum.clear(why if not why.is_empty() else "No spectrum for this flight.")
	else:
		var marks: Array = []
		for harmonic in analysis.harmonics:
			marks.append({
				"hz": float(harmonic["hz"]),
				"label": "%dx" % int(harmonic["order"]),
				"dashed": false,
			})
		if analysis.modelled_resonance_hz > 0.0:
			marks.append({
				"hz": analysis.modelled_resonance_hz,
				"label": "model",
				"dashed": true,
			})
		_spectrum.show_spectrum(analysis.mags, analysis.bin_hz, marks)
		_add_report_row("channel", FlightAnalysis.SPECTRUM_CHANNEL)
		_add_report_row("frames", "%d x %.3f s, Hann, 75%% overlap" % [
			analysis.frames, FlightAnalysis.FRAME_SECONDS])

	if analysis != null and not analysis.admissibility.is_empty():
		# The LTHL-18 refusal, carried into the UI. A curve drawn for a log the method cannot
		# analyse is worse than no curve, because it looks exactly like one that means something.
		if analysis.admissible:
			_add_report_note(analysis.admissibility)
		else:
			_add_report_warning(analysis.admissibility)

	_add_report_title("THE VIBRATION MODEL")
	var vibration: Dictionary = p_head.get("vibration_model", {})
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

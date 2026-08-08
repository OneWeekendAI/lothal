class_name CustomFcDialog
extends AcceptDialog
## Lab's form for entering a flight controller Lothal does not stock.
##
## A LAB surface and only a Lab surface (labs-and-sim.md: Lab authors, Sim does not).
##
## ---------------------------------------------------------------------------
## THE FORM ASKS FOR AN IMU AND A SAMPLE RATE. IT DOES NOT ASK FOR A NOISE FLOOR.
## ---------------------------------------------------------------------------
##
## `gyro_noise_rad_s` is not a product-page number and nobody should type 0.0062. The builder picks
## their IMU from the part numbers Lothal holds a datasheet for and enters the gyro rate from their
## Betaflight configuration; the noise floor follows from the two. See CustomFlightControllers for
## the derivation and for why it is checked against all six shipped boards rather than asserted.
##
## The sample rate IS typed, and it is the one field here a builder genuinely reads off something —
## their own configurator. Note for anyone comparing against the catalog: the reference board runs
## 1 kHz rather than its part's 8 kHz maximum because its gyro is synced to Lothal's rate loop,
## which is the configuration every oracle in the project is defined at. A custom board at 8 kHz is
## an ordinary board, not a special case.
##
## ---------------------------------------------------------------------------
## THE DERIVED PANEL SAYS TWO DIFFERENT THINGS ABOUT TWO DERIVED NUMBERS
## ---------------------------------------------------------------------------
##
## Derived is not the same as hidden, and — the part this dialog exists to get right — the two
## derived numbers are NOT the same kind of number:
##
##   - the noise floor names the DATASHEET it came from, because it is genuinely datasheet-backed
##     and a builder can go and check it;
##   - the bias says ILLUSTRATIVE, because no datasheet publishes calibration residue and printing
##     it as a plain number beside the noise floor would make it look like one.
##
## An IMU outside the table is not blocked: the density field takes the builder's own figure, and
## their `source` is then what the board stands on. That is what keeps the table honest without
## making it a wall.
##
## `gyro_cutoff_hz` is not on this form. It is 150 on every shipped entry because that is
## Betaflight's default rather than a hardware property — a firmware setting living in a parts
## catalog — and a builder should not be asked to retype a default they did not choose. Moving the
## field out of the catalog is a slice of its own; see CustomFlightControllers' header.

signal fc_saved(part_id: String)

const PROCESSORS := ["F411", "F405", "F722", "H743"]

## The IMUs Lothal holds a density for, plus the escape hatch. Read off
## CustomFlightControllers rather than written again here, for the same reason
## CustomBatteryDialog reads its chemistries off CustomBatteries: an option this dialog offered
## that the model had no figure for would derive a noise floor from nothing.
const OTHER_IMU := "Other (enter density)"

var _imus: Array[String] = []

var _name := LineEdit.new()
var _imu := OptionButton.new()
var _density := SpinBox.new()
var _sample_rate := SpinBox.new()
var _mass := SpinBox.new()
var _pattern := LineEdit.new()
var _processor := OptionButton.new()
var _loop_rate := SpinBox.new()
var _bias_override := SpinBox.new()
var _source := LineEdit.new()
var _derived := Label.new()
var _problems := Label.new()
var _last_problems: Array[String] = []


func _init() -> void:
	title = "New custom flight controller"
	ok_button_text = "Save board"
	confirmed.connect(_on_confirmed)

	var root := VBoxContainer.new()
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	_add_row(grid, "Name", _name)

	for imu in CustomFlightControllers.known_imus():
		_imus.append(str(imu))
		_imu.add_item(str(imu))
	_imus.append(OTHER_IMU)
	_imu.add_item(OTHER_IMU)
	_add_row(grid, "IMU", _imu)

	# Step 0.0001, matching the %.4f the panel prints — a coarser step would round a builder's
	# 0.0038 to 0.004 and fly a different sensor. Left at zero for a listed IMU, where Lothal's own
	# datasheet figure is the one used.
	_density.tooltip_text = "Only for an IMU not in the list: its rate noise density in deg/s/sqrt(Hz), from the datasheet."
	_add_row(grid, "Noise density (deg/s/√Hz)", _configure(_density, 0.0, 1.0, 0.0001))

	_sample_rate.tooltip_text = "The gyro rate in your Betaflight configuration, not the chip's maximum."
	_add_row(grid, "Gyro sample rate (Hz)", _configure(_sample_rate, 0.0, 32000.0, 100.0))
	_add_row(grid, "Board mass (g)", _configure(_mass, 0.0, 100.0, 0.1))

	_pattern.placeholder_text = "30.5x30.5"
	_add_row(grid, "Bolt pattern", _pattern)

	for processor in PROCESSORS:
		_processor.add_item(processor)
	_add_row(grid, "Processor", _processor)
	_add_row(grid, "Loop rate (Hz)", _configure(_loop_rate, 0.0, 32000.0, 100.0))

	_bias_override.tooltip_text = "Leave at 0 unless you have characterised this board's calibration residue yourself."
	_add_row(grid, "Measured bias (rad/s)", _configure(_bias_override, 0.0, 0.05, 0.0001))

	_source.placeholder_text = "where these numbers came from"
	_add_row(grid, "Source", _source)

	_derived.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_derived.custom_minimum_size = Vector2(460, 0)
	root.add_child(_derived)

	for box in [_density, _sample_rate, _bias_override]:
		(box as SpinBox).value_changed.connect(func(_v: float) -> void: _refresh_derived())
	_imu.item_selected.connect(func(_i: int) -> void: _refresh_derived())
	_sample_rate.value = Gyro.DEFAULT_SAMPLE_RATE_HZ
	_refresh_derived()

	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size = Vector2(460, 0)
	_problems.theme_type_variation = &"WarnLabel"
	_problems.add_theme_color_override("font_color", LothalTheme.WARNING)
	_problems.visible = false
	root.add_child(_problems)


static func _configure(box: SpinBox, minimum: float, maximum: float, step: float) -> SpinBox:
	box.min_value = minimum
	box.max_value = maximum
	box.step = step
	box.custom_minimum_size = Vector2(140, 0)
	return box


func _add_row(grid: GridContainer, label_text: String, editor: Control) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(editor)


func _selected_imu() -> String:
	var index := _imu.selected
	if index < 0 or index >= _imus.size():
		return ""
	var chosen := _imus[index]
	return "" if chosen == OTHER_IMU else chosen


## The density override as make_record wants it: NAN for "use Lothal's own figure".
func _density_or_nan() -> float:
	return _density.value if _density.value > 0.0 else NAN


func _bias_or_nan() -> float:
	return _bias_override.value if _bias_override.value > 0.0 else NAN


func _refresh_derived() -> void:
	_derived.text = derived_text()
	# Amber whenever the board is standing on a derivation rather than on a measurement, which is
	# the ordinary case and the one the caveat is about.
	var measured := not is_nan(_bias_or_nan())
	_derived.add_theme_color_override("font_color",
		LothalTheme.TEXT_MUTED if measured else LothalTheme.WARNING)


## What the derived panel says, as a string. Separate from the Label so a test can assert the
## numbers and the caveats without instantiating a Control.
func derived_text() -> String:
	var imu := _selected_imu()
	var rate := _sample_rate.value
	var supplied := _density_or_nan()
	var density := supplied if not is_nan(supplied) else CustomFlightControllers.density_for(imu)

	if density <= 0.0:
		return "Pick an IMU, or choose \"%s\" and enter its rate noise density from the datasheet — the noise floor is derived from it and cannot be guessed." % OTHER_IMU
	if rate <= 0.0:
		return "Enter the gyro sample rate from your Betaflight configuration; the noise floor is derived from it and the IMU's density."

	var noise := CustomFlightControllers.derived_noise_rad_s(density, rate)
	var provenance: String
	if is_nan(supplied):
		provenance = "DERIVED from the %s's published %.4f deg/s/√Hz rate noise density (%s) across %.0f Hz" % [
			imu, density, CustomFlightControllers.datasheet_for(imu), rate]
	else:
		provenance = "DERIVED from the %.4f deg/s/√Hz density you entered across %.0f Hz — Lothal holds no datasheet for this part, so it stands on your source" % [
			density, rate]

	var bias_override := _bias_or_nan()
	var bias_clause: String
	if is_nan(bias_override):
		bias_clause = "Bias %.4f rad/s — ILLUSTRATIVE, a class-typical calibration residue scaled by sensor grade. No datasheet publishes this: it is what one board's one bench calibration left behind, and it varies unit to unit. Measure yours and enter it above if you can." % \
			CustomFlightControllers.derived_bias_rad_s(imu)
	else:
		bias_clause = "Bias %.4f rad/s — your measurement, used as given." % bias_override

	return "Noise floor %.4f rad/s — %s. This one is datasheet-backed, unlike a custom pack's derived resistance. %s" % [
		noise, provenance, bias_clause]


## Fills the form. Public because it is how a test drives the dialog and how "edit this one" would
## populate it later.
##
## An IMU the list does not hold selects nothing and falls through to the density field and then to
## the refusal, rather than being quietly replaced by the first entry — a form that silently picked
## the MPU-6000 for a board the builder named otherwise would fly a sensor they do not own.
func set_fields(part_name: String, imu: String, sample_rate_hz: float, mass_g: float,
		pattern: String, processor: String, loop_rate_hz: int, source: String,
		density: float = NAN, bias_override: float = NAN) -> void:
	_name.text = part_name
	_imu.select(_imus.find(imu))
	_density.value = 0.0 if is_nan(density) else density
	_sample_rate.value = sample_rate_hz
	_mass.value = mass_g
	_pattern.text = pattern
	_processor.select(PROCESSORS.find(processor))
	_loop_rate.value = loop_rate_hz
	_bias_override.value = 0.0 if is_nan(bias_override) else bias_override
	_source.text = source
	_refresh_derived()


func problems() -> Array[String]:
	return _last_problems


## Builds the record, asks CustomFlightControllers to accept it, and writes the file.
##
## The IMU passed to make_record is the SELECTED part number when there is one, and the typed name
## otherwise — which is how a board on an unlisted IMU keeps the part number in its record instead
## of an empty string, and how the refusal can name the part when no density came with it.
func submit() -> Array[String]:
	var document := CustomFlightControllers.load_from()
	var processor_index := _processor.selected
	var imu := _selected_imu()
	if imu == "" and _imu.selected >= 0:
		imu = _imus[_imu.selected]

	var record := CustomFlightControllers.make_record(
		_name.text.strip_edges(), imu, _sample_rate.value, _mass.value,
		_pattern.text.strip_edges(),
		PROCESSORS[processor_index] if processor_index >= 0 else "",
		int(_loop_rate.value), _source.text.strip_edges(),
		_density_or_nan(), _bias_or_nan())

	_last_problems = document.add(record)
	if not _last_problems.is_empty():
		_problems.text = "\n".join(_last_problems)
		_problems.visible = true
		return _last_problems

	_problems.visible = false
	document.save()
	fc_saved.emit(str(record["part_id"]))
	hide()
	return _last_problems


func _on_confirmed() -> void:
	if not submit().is_empty():
		show()

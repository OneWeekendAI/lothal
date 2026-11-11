class_name ConfigTab
extends Control
## A Config or Control panel as a tab of a Part sheet, editing THIS design:
##   flight controller sheet: "board" (what the board is and what its noise costs), "tune" (the three
##   axes and their gains), "rates" (max rate and expo), "ports" (serial supply against need),
##   "failsafe" (stage two, bidirectional DShot and the checks).
##   motor sheet: "spin" (props in or out, and the four directions).
##
## The panels are the old Lab ones (already in Design Space tokens), unchanged; what moves is where
## they read and write. Config decisions live in the session (`DesignSession.set_config`: undo, the
## design file, and the built aircraft the sim flies); gains go to `PidTunes`, the store the sim flies
## its tune from. The panel announces, this tab writes, then everything re-renders from the new build.

const KINDS := ["board", "tune", "rates", "ports", "failsafe", "spin", "configsheet"]

var ds: DesignSpace
var kind := ""
var panel: Control
var _tunes: PidTunes
var _tune: RateTune
## The tune store's file (tests point it at a scratch path).
var tunes_path := PidTunes.SAVE_PATH
## Where the config sheet is written (tests point it at a scratch folder).
var export_dir := ConfigSheet.DIRECTORY


func _init(p_ds: DesignSpace, p_kind: String) -> void:
	ds = p_ds
	kind = p_kind
	name = "ConfigTab_" + kind
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = _make_panel()
	if panel == null:
		return
	add_child(ConfigTab.host(panel))
	ds.session.changed.connect(refresh)
	tree_exiting.connect(func():
		if ds.session.changed.is_connected(refresh):
			ds.session.changed.disconnect(refresh))
	refresh()


## Puts an old panel in a full-size, padded frame. The panels that scroll themselves are given the
## whole area (a scroll inside a scroll collapses to nothing); the rest get a vertical scroll.
static func host(p: Control) -> Control:
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_%s" % side, LothalTheme.SPACE_2)
	# A panel drawn for a narrow column keeps its width (the card hugs its text) rather than stretching.
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if p.custom_minimum_size.x > 0.0 and p.custom_minimum_size.x < 420.0 \
		else Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not p.find_children("*", "ScrollContainer", false, false).is_empty():
		pad.add_child(p)
		return pad
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(p)
	pad.add_child(scroll)
	return pad


func _make_panel() -> Control:
	match kind:
		"board":
			return FcDetails.new()
		"tune":
			var t := TunePanel.new()
			t.tune_changed.connect(_on_tune_changed)
			return t
		"rates":
			var r := ConfigRatesPanel.new()
			r.max_rate_edited.connect(func(v: float): _edit(func(c): RateSettings.set_max_rate_deg_s(c, v)))
			r.expo_edited.connect(func(v: float): _edit(func(c): RateSettings.set_expo(c, v)))
			return r
		"ports":
			var p := ConfigPortsPanel.new()
			p.uart_count_edited.connect(func(n: int): _edit(func(c): PortBudget.set_count(c, n)))
			return p
		"failsafe":
			var f := ConfigFailsafePanel.new()
			f.failsafe_stage2_edited.connect(func(v: String): _edit(func(c): FailsafeSettings.set_stage2(c, v)))
			f.bidir_dshot_edited.connect(func(on: bool): _edit(func(c): FailsafeSettings.set_bidir_dshot(c, on)))
			return f
		"configsheet":
			var cs := ConfigSheetPanel.new()
			cs.export_requested.connect(_export_sheet)
			return cs
		"spin":
			var m := ConfigMotorsPanel.new()
			m.motor_spin_edited.connect(func(v: String): _edit(func(c): c["motor_spin"] = v))
			return m
	return null


## One Config edit: a copy of the decisions, changed, handed to the session (one undo step).
func _edit(mutate: Callable) -> void:
	var cfg := ds.session.config()
	mutate.call(cfg)
	ds.session.set_config(cfg)


func _sheet_name() -> String:
	return ds.design_name if ds.design_name != "" else "Design"


## The configurator sheet to a file: the same text the preview shows, said where it went.
func _export_sheet() -> void:
	var build := ds.session.build(ds._catalog)
	if build == null:
		return
	DirAccess.make_dir_recursive_absolute(export_dir)
	var date := Time.get_date_string_from_system()
	var path := export_dir.path_join(ConfigSheet.default_path(_sheet_name(), date).get_file())
	var landed := ConfigSheet.write(build, _sheet_name(), path, date)
	(panel as ConfigSheetPanel).show_result(ProjectSettings.globalize_path(path), landed)


func _on_tune_changed() -> void:
	var build := ds.session.build(ds._catalog)
	if build == null or _tunes == null or _tune == null:
		return
	_tunes.remember(build, _tune)
	_tunes.save(tunes_path)
	refresh()


## Re-reads the design and repaints the panel.
func refresh() -> void:
	var build := ds.session.build(ds._catalog)
	if build == null or panel == null:
		return
	match kind:
		"board", "tune":
			_tunes = PidTunes.load_from(tunes_path)
			_tune = _tunes.tune_for(build)
			if kind == "board":
				(panel as FcDetails).render(build.fc, build, _tune)
			else:
				(panel as TunePanel).render(build, _tune)
		"configsheet":
			(panel as ConfigSheetPanel).render(build, _sheet_name())
		_:
			panel.call("render", build)

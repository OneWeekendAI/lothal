class_name DsWatchCard
extends DsDrawer
## S6 the watched mission in the sim, in Design Space language: a left drawer (DsDrawer's box) that shows the mission's name,
## a progress bar, the elapsed time against the simulated-time cap and, once the flight ends, the same ResultsPanel the Mission
## picker's Run uses, with "Back to design" under it. Main feeds it each physics frame (`update`) and once at the end (`finish`);
## it computes nothing itself. It takes the mouse only where it is drawn, so the flight keys still reach the sim.

signal back_requested

const TOP_ROOM := 176.0       ## under the HUD's warnings panel
const BOTTOM_KEEP := 200.0    ## above the HUD's aircraft panel
const WIDTH_CARD := 300.0

var mission_label: Label
var bar: ProgressBar
var time_label: Label
var status_label: Label
var results: ResultsPanel
var back_button: Button
## What the bar shows now, 0..1 (tests read it; the bar's own value is this times 100).
var progress := 0.0
var running := false
var done := false


func _init() -> void:
	super("Mission")
	name = "DsWatchCard"
	offset_top = TOP_ROOM
	offset_bottom = TOP_ROOM
	offset_right = LEFT + WIDTH_CARD
	custom_minimum_size = Vector2(WIDTH_CARD, 0)
	close_button.hide()
	mission_label = DsUi.label("", DsUi.INK, LothalTheme.FONT_SIZE_BODY)
	content.add_child(mission_label)
	bar = ProgressBar.new()
	bar.name = "Progress"
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = DsUi.INK_FAINT
	var fill := StyleBoxFlat.new()
	fill.bg_color = DsUi.INK_MUTED
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	content.add_child(bar)
	time_label = DsUi.label("", DsUi.INK)
	content.add_child(time_label)
	status_label = DsUi.label("", DsUi.INK_MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(1, 0)
	content.add_child(status_label)
	results = ResultsPanel.new()
	results.visible = false
	content.add_child(results)
	back_button = DsUi.button("‹ Back to design", false, true)
	back_button.name = "BackToDesign"
	back_button.tooltip_text = "Put the simulator away and return to the design (Esc)"
	back_button.pressed.connect(func() -> void: back_requested.emit())
	back_button.visible = false
	footer.add_child(back_button)
	hide()


func _max_h() -> float:
	var vp := get_viewport_rect().size.y if is_inside_tree() else 720.0
	return maxf(120.0, vp - TOP_ROOM - BOTTOM_KEEP - 60.0 - footer.get_combined_minimum_size().y)


static func clock(seconds: float) -> String:
	var s := int(maxf(0.0, seconds))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## A flight is starting: the bar at zero, the name up, no result yet.
func begin(mission_id: String, limit_s: float) -> void:
	running = true
	done = false
	progress = 0.0
	bar.value = 0.0
	mission_label.text = MissionPicker.mission_name(mission_id)
	status_label.text = "Flying. The bar is the pack used toward the reserve."
	time_label.text = "Elapsed 0:00 of %s limit" % clock(limit_s)
	set_meta("limit_s", limit_s)
	results.visible = false
	results.set_result({})
	back_button.visible = false
	show()


func update(elapsed_s: float, fraction: float) -> void:
	progress = clampf(fraction, 0.0, 1.0)
	bar.value = progress * 100.0
	time_label.text = "Elapsed %s of %s limit" % [clock(elapsed_s), clock(float(get_meta("limit_s", 0.0)))]


## The flight ended: the bar full, the result card shown from `result` (kept, not copied), the way back offered.
func finish(result: Dictionary, elapsed_s: float) -> void:
	running = false
	done = true
	update(elapsed_s, 1.0)
	status_label.text = "Ended: %s" % String(result.get("ended_by", "")).replace("_", " ")
	results.visible = true
	results.set_result(result)
	back_button.visible = true
	_fit()

class_name ConfigSheetPanel
extends PanelContainer
## Config's Sheet panel: the door the artifact leaves by — Config room slice C9
## (plans/2026-09-20-config-room-design.md §3, `2026-08-17-build-sheet-design.md` §2.5).
##
## THE PREVIEW IS THE SHEET, CHARACTER FOR CHARACTER. Not a summary of it, not a highlights list.
## A preview that paraphrased would be a FOURTH wording of every figure in this room — after the
## module's, the panel's and the file's — and the one property C9 is built to hold is that there
## is exactly one wording of each. The test asserts the equality rather than trusting this comment.
##
## THE PANEL WRITES NOTHING, on the rule its four siblings share: pressing Export announces
## `export_requested` and LabScreen does the writing, because LabScreen is the thing that knows
## which drone this is and where its sheets go. A panel that wrote its own file would be a second
## place the artifact is produced, and they would drift.
##
## THE RESULT IS SAID OUT LOUD, both ways. `2026-08-17-build-sheet-design.md` §7's last row is
## about exactly this: a write that failed silently costs an evening, because the builder walks to
## the bench holding nothing and does not find out until they are there.

signal export_requested

var _preview: Label
var _button: Button
var _status: Label


func _init() -> void:
	custom_minimum_size = Vector2(316, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	AssemblyPanel._padded(scroll).add_child(root)

	var title := Label.new()
	title.text = "CONFIG SHEET"
	title.theme_type_variation = &"TitleLabel"
	root.add_child(title)

	var note := Label.new()
	note.text = ("Everything this room knows, in one file to work through with a USB cable in your "
		+ "hand. It is dated and it is never overwritten, so the sheet you built from stays as it "
		+ "was when you built from it.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(280, 0)
	note.theme_type_variation = &"MutedLabel"
	root.add_child(note)
	_prose.append(note)

	_button = Button.new()
	_button.text = "Export sheet"
	_button.pressed.connect(func() -> void: export_requested.emit())
	root.add_child(_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(280, 0)
	_status.theme_type_variation = &"MutedLabel"
	root.add_child(_status)

	root.add_child(HSeparator.new())

	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(280, 0)
	root.add_child(_preview)
	_prose.append(_preview)


## Shows what would be written, for this build, under this name. Reads; never writes.
func render(build: Build, drone_name: String) -> void:
	_preview.text = ConfigSheet.body(build, drone_name)


## Where the sheet went, or that it did not go anywhere. Said by LabScreen after it writes,
## because the panel does not do the writing and so cannot know.
func show_result(path: String, landed: bool) -> void:
	_status.text = ("Wrote %s" % path) if landed else ("COULD NOT WRITE %s" % path)


func preview_text() -> String:
	return _preview.text


func status_text() -> String:
	return _status.text


## The button itself, so a headless check can press it the way a mouse would — the same reason
## `ConfigRatesPanel` hands out its spin boxes. The connection between the control and this
## panel's signal is otherwise untestable outside a window, and it is the thing that breaks.
func export_button() -> Button:
	return _button


## The explanatory sentences, off on a Lab dock page: the row, the page's numbers and the drawing
## say them there (lab dock design: no paragraphs on a page).
var _prose: Array[Control] = []


func set_prose_visible(on: bool) -> void:
	for node in _prose:
		node.visible = on

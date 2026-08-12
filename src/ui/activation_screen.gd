class_name ActivationScreen
extends Control
## The screen shown when Lothal has no valid licence — which is to say, the whole app.
##
## Built in code rather than in a .tscn, like every other screen here: hand-placed UI does not
## survive version control (architecture.md), and this one in particular must be reviewable as a
## diff, because it is the one screen whose failure locks a paying user out of the app.
##
## ---------------------------------------------------------------------------
## THE TONE, AND WHY IT MATTERS MORE HERE THAN ANYWHERE ELSE
## ---------------------------------------------------------------------------
##
## This screen is an obstacle in front of something the user has already downloaded and may
## already have paid for. Handled badly it reads as a shakedown. So it says plainly what it wants
## and why: an address to tell you when a new version exists. It does not claim to be protecting
## anything, does not imply the user is suspected of anything, and does not pretend the check is
## stronger than it is.
##
## ---------------------------------------------------------------------------
## TWO WAYS IN, ONE VERIFIER
## ---------------------------------------------------------------------------
##
## A user can paste the key or open the downloaded .lothalkey file. Both land in exactly the same
## call to `LicenceCheck.verify()` — the file path is not a shortcut that skips a check, it is a
## different way of getting the same bytes. Two verifiers would eventually disagree, and the one
## that disagreed in the permissive direction would be the way in.
##
## The paste box exists because it always works. The file picker exists because pasting a 700-byte
## blob out of a browser download is the kind of thing that goes wrong quietly — a truncated
## selection produces a licence that fails to verify, and the user has no way to know that the
## reason is their own copy rather than our server.
##
## ---------------------------------------------------------------------------
## WHAT THE USER IS TOLD WHEN IT FAILS
## ---------------------------------------------------------------------------
##
## "That key was not accepted", every time, for every reason. The specific `reason` goes to the
## log. This is not secrecy for its own sake — it is that the reasons are either useless to the
## user ("signature did not verify") or actively a hint about which byte to change next. The one
## thing the message does do is point at the honest common cause: an incomplete copy-paste.

const PASTE_PLACEHOLDER := "Paste your activation key here"
## Extension of the file the activation page hands out. Filtered in the picker but NOT required —
## a user who renamed it, or whose browser appended .txt, still gets in, because the verifier
## reads bytes and does not care what the file is called.
const KEY_EXTENSION := "*.lothalkey"
## A licence is under a kilobyte. Anything at this scale is not a licence, and refusing to read it
## stops someone pointing the picker at a 4 GB file and hanging the app on a mistake.
const MAX_KEY_BYTES := 64 * 1024

## Emitted with the verified address once a licence has been accepted and stored.
signal activated(email: String)

var _activation_url: String
var _paste_box: TextEdit
var _message: Label
var _file_dialog: FileDialog = null


func _init(activation_url: String) -> void:
	_activation_url = activation_url
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0


func _ready() -> void:
	var background := ColorRect.new()
	background.color = LothalTheme.SURFACE_BASE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	add_child(background)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", LothalTheme.SPACE_4)
	column.custom_minimum_size = Vector2(520, 0)
	centre.add_child(column)

	column.add_child(_heading("Activate Lothal"))

	# The ask, in the order a person needs it: what we want, what it costs them, what we do with
	# it. "Free" appears early because the sentence is otherwise indistinguishable from a paywall.
	column.add_child(_body(
		"Lothal needs a verified email address before it opens. Signing in is free and takes "
		+ "about twenty seconds — the address is used to tell you when a new version is "
		+ "released, and for nothing else."))

	var open_button := Button.new()
	open_button.text = "Open the activation page"
	open_button.custom_minimum_size = Vector2(0, 36)
	# A browser, not an in-app view. Sign-in belongs somewhere the user can see the address bar
	# and their own password manager can reach — and an embedded web view asking for a Google
	# password is indistinguishable from the phishing pattern people are told to refuse.
	open_button.pressed.connect(func() -> void: OS.shell_open(_activation_url))
	column.add_child(open_button)

	column.add_child(_muted("The page will give you a key. Paste it below, or open the file it "
		+ "downloads."))

	_paste_box = TextEdit.new()
	_paste_box.placeholder_text = PASTE_PLACEHOLDER
	_paste_box.custom_minimum_size = Vector2(0, 110)
	_paste_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(_paste_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	column.add_child(buttons)

	var activate := Button.new()
	activate.text = "Activate"
	activate.custom_minimum_size = Vector2(120, 32)
	activate.pressed.connect(_activate_from_paste)
	buttons.add_child(activate)

	var from_file := Button.new()
	from_file.text = "Open key file…"
	from_file.pressed.connect(_open_file_dialog)
	buttons.add_child(from_file)

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(520, 0)
	_message.visible = false
	column.add_child(_message)

	# The offline case, stated up front rather than discovered. Someone at a flying field with no
	# signal cannot activate, and the useful thing to tell them is that this is a one-time step and
	# the app will not ask again — not to let them find that out by watching a button do nothing.
	column.add_child(_muted(
		"Activation needs an internet connection once. After that Lothal never contacts the "
		+ "internet to check your key, and works offline permanently."))


# ---------------------------------------------------------------------------
# Activation
# ---------------------------------------------------------------------------

func _activate_from_paste() -> void:
	# to_utf8_buffer() on the trimmed text, rather than reading the box as bytes, because what the
	# user pasted is text by definition. strip_edges handles the near-universal case: a copy that
	# picked up a trailing newline from the browser.
	submit(_paste_box.text.strip_edges().to_utf8_buffer())


func _open_file_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.add_filter(KEY_EXTENSION, "Lothal activation key")
		_file_dialog.add_filter("*", "All files")
		_file_dialog.file_selected.connect(_activate_from_file)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


func _activate_from_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_refuse("That file could not be read.")
		return
	if file.get_length() > MAX_KEY_BYTES:
		_refuse("That file is too large to be an activation key.")
		return
	# The file's bytes go in untouched — no strip, no decode, no re-encode. This is the path most
	# likely to carry a licence exactly as issued, and the least excuse for altering it.
	submit(file.get_buffer(file.get_length()))


## Verifies a licence, stores it on success, and reports the outcome. Public and returning a bool
## so the suite can drive the whole path without a display, a click, or a file on disk.
func submit(body: PackedByteArray) -> bool:
	if body.is_empty():
		_refuse("Paste the key from the activation page, or open the file it downloaded.")
		return false

	var result := LicenceCheck.verify(body)
	if not result.valid:
		# The specific reason is logged and never shown. See the header.
		print_verbose("activation refused: %s" % result.reason)
		_refuse("That key was not accepted. Check that you copied all of it — the key is one "
			+ "long block, and a partial copy looks complete.")
		return false

	# Stored BEFORE the signal, and the signal is not sent if the write failed. Opening the app on
	# a licence that did not persist would produce the worst possible sequence: activation appears
	# to work, and the next launch asks again with no explanation.
	if not LicenceCheck.store(body):
		_refuse("That key is valid, but it could not be saved. Check that Lothal can write to "
			+ "its settings folder, then try again.")
		return false

	_message.text = "Activated"
	_message.add_theme_color_override("font_color", LothalTheme.SUCCESS)
	_message.visible = true

	activated.emit(result.email)
	return true


func _refuse(text: String) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", LothalTheme.DANGER)
	_message.visible = true


# ---------------------------------------------------------------------------
# Small builders, so the layout above reads as layout
# ---------------------------------------------------------------------------

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_TITLE)
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	return label


func _muted(text: String) -> Label:
	var label := _body(text)
	label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MUTED)
	return label

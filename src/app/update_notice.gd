class_name UpdateNotice
extends Control
## The one-line bar that says a new Lothal exists, and the HTTP request behind it.
##
## What this deliberately is NOT is a self-updater. Lothal is unsigned by Apple and Microsoft,
## so a build that downloaded and swapped its own executable would be handing every install a
## code path that writes new binaries onto the disk — protected, on this release, by a signature
## check that has never been exercised against a real attacker. The manifest verification in
## UpdateCheck is the foundation for that later; the release it first ships in does nothing more
## dangerous than opening a URL in the user's browser, which is a decision they then make in the
## open with their own eyes on the download.
##
## The other reason is mechanical and unglamorous: Windows cannot replace a running .exe, and
## swapping an .app inside /Applications needs rights Lothal has no business asking for.
##
## Failure here is silent by design. Nobody launched a flight simulator to be told that a
## version check timed out, and there is no action for them to take. Offline, DNS-poisoned,
## bucket down, manifest malformed — all of it produces the same outcome as "you are up to
## date": no bar. The reason is logged and never surfaced.

## Checked at most once per launch, and only after this delay, so the request never competes
## with the first frames of a scene the user is waiting on.
const CHECK_DELAY_SECONDS := 3.0
const REQUEST_TIMEOUT_SECONDS := 8.0
## A manifest is a few hundred bytes. Anything at this scale is not a manifest, and refusing to
## buffer it stops a hostile or broken endpoint from streaming until memory runs out.
const MAX_BODY_BYTES := 256 * 1024

const BAR_HEIGHT := 30.0

var _manifest_url: String
var _installed: String
var _request: HTTPRequest
var _result: UpdateCheck.Result = null


func _init(manifest_url: String, installed_version := LothalVersion.CURRENT) -> void:
	_manifest_url = manifest_url
	_installed = installed_version

	set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor_right = 1.0
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Hidden until there is something to say. A bar that appears and then empties itself would
	# shift the whole layout under the user's cursor a second after launch.
	visible = false


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = REQUEST_TIMEOUT_SECONDS
	_request.body_size_limit = MAX_BODY_BYTES
	_request.request_completed.connect(_on_response)
	add_child(_request)

	var timer := get_tree().create_timer(CHECK_DELAY_SECONDS)
	timer.timeout.connect(_start)


func _start() -> void:
	if _manifest_url.is_empty() or not _manifest_url.begins_with("https://"):
		return
	var error := _request.request(_manifest_url)
	if error != OK:
		print_verbose("update check not started: %d" % error)


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print_verbose("update check: transport result %d, http %d" % [result, code])
		return

	var found := UpdateCheck.parse_manifest(body, UpdateCheck.current_platform(), _installed)
	if not found.available:
		print_verbose("update check: %s" % found.reason)
		return

	_result = found
	_show(found)


func _show(found: UpdateCheck.Result) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LothalTheme.SPACE_3)
	panel.add_child(row)

	var label := Label.new()
	label.text = "Lothal %s is available." % found.version
	label.add_theme_color_override("font_color", LothalTheme.TEXT_MAIN)
	label.add_theme_font_size_override("font_size", LothalTheme.FONT_SIZE_SMALL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	# The button opens a page rather than starting a download, and it is worded so that what
	# happens next is not a surprise: the browser opens, the user sees where the file comes
	# from, and the checksum on that page is theirs to check if they care to.
	var open_button := Button.new()
	open_button.text = "Open download page"
	open_button.pressed.connect(_open_page)
	row.add_child(open_button)

	var dismiss := Button.new()
	dismiss.text = "Not now"
	# Dismissal lasts for this session only. Nothing is written to disk, because a "skipped
	# versions" file is state that can rot into "this install is never offered anything again",
	# and the cost of asking once more next launch is one line the user ignores.
	dismiss.pressed.connect(func() -> void: visible = false)
	row.add_child(dismiss)

	visible = true


func _open_page() -> void:
	if _result == null:
		return
	# The notes page when there is one, the file otherwise. Preferring the page means the user
	# lands somewhere with the checksum and the changes next to the link, rather than watching
	# an unexplained 90 MB zip arrive.
	var target := _result.notes_url if _result.notes_url.begins_with("https://") else _result.download_url
	OS.shell_open(target)
	visible = false

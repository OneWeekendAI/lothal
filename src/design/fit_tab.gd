class_name FitTab
extends Control
## The panels that read and write the design's ASSEMBLY (shims, pad, mount, battery offset, camera
## uptilt) or report what the electronics weigh, as tabs of a Part sheet:
##   frame sheet "fit": the Fit panel (mount, battery offset, shims, reset; `AssemblyPanel`)
##   camera sheet "uptilt": the camera's uptilt and what it does to the picture (`CameraPanel`)
##   camera / vtx sheets "payload": what the video payload costs (`ElectronicsDetails`)
##   receiver / antenna sheets "link": what the receiver and its extras cost (`LinkDetails`)
##
## The old panels are unchanged. Assembly decisions live in the session (`DesignSession.set_tweaks`:
## undo, the design file, and the built aircraft carries them), not in the shared tweaks file. The
## panel edits a working copy; every edit hands the copy to the session, and any change the session
## makes (an undo, a swap) re-reads it.

const KINDS := ["fit", "uptilt", "payload", "link"]

var ds: DesignSpace
var kind := ""
var panel: Control
var tweaks: AssemblyTweaks


func _init(p_ds: DesignSpace, p_kind: String) -> void:
	ds = p_ds
	kind = p_kind
	name = "FitTab_" + kind
	set_anchors_preset(Control.PRESET_FULL_RECT)
	tweaks = AssemblyTweaks.from_dict(ds.session.tweaks.to_dict())
	panel = _make_panel()
	if panel == null:
		return
	add_child(ConfigTab.host(panel))
	ds.session.changed.connect(_on_session_changed)
	tree_exiting.connect(func():
		if ds.session.changed.is_connected(_on_session_changed):
			ds.session.changed.disconnect(_on_session_changed))
	refresh()


func _make_panel() -> Control:
	match kind:
		"fit":
			var a := AssemblyPanel.new(tweaks)
			a.tweaks_changed.connect(_on_tweaks_changed)
			return a
		"uptilt":
			var c := CameraPanel.new()
			c.tilt_edited.connect(func(degrees: float):
				tweaks.set_mm(AssemblyTweaks.CAMERA_TILT, degrees)
				_on_tweaks_changed())
			return c
		"payload":
			return ElectronicsDetails.new()
		"link":
			return LinkDetails.new()
	return null


## The panel changed the working copy: the design takes it (one undo step).
func _on_tweaks_changed() -> void:
	ds.session.set_tweaks(tweaks)


func _on_session_changed() -> void:
	if tweaks.to_dict() != ds.session.tweaks.to_dict():
		tweaks.reset()
		var fresh := ds.session.tweaks.to_dict()
		# The panel holds `tweaks` itself, so the values go in by key, not by replacing the object.
		for key in fresh:
			if AssemblyTweaks.CHOICE_KEYS.has(key):
				tweaks.set_choice(key, String(fresh[key]))
			else:
				tweaks.set_mm(key, float(fresh[key]))
	refresh()


## Re-reads the design and repaints the panel.
func refresh() -> void:
	var build := ds.session.build(ds._catalog)
	if build == null or panel == null:
		return
	match kind:
		"fit":
			(panel as AssemblyPanel).render(build, null)
		"uptilt":
			(panel as CameraPanel).render(build, tweaks, null)
		"payload":
			(panel as ElectronicsDetails).render_components(build)
		"link":
			(panel as LinkDetails).render_components(build)

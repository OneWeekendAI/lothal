extends SceneTree
## Rasterizes icon.svg into every size the macOS iconset needs.
##
##   godot --headless --script res://tools/render_icon.gd
##
## Godot ships an SVG rasterizer (ThorVG), so this needs no rsvg/inkscape/imagemagick.
## Rendering each size from the vector — rather than downscaling one big PNG — is what
## keeps the 16px and 32px entries crisp; a resampled 1024 turns the arms to mush.
##
## WHERE THE OUTPUTS ARE WIRED UP, and why that is documented here rather than next to them:
## icon.svg is the window/taskbar icon, set as `config/icon` in project.godot; icon.icns is the
## macOS bundle icon, set on the export preset. Both used to be explained by a comment sitting
## directly above `config/icon` — until an editor pass rewrote project.godot, stripped the spaces
## out of that comment and joined it to the line below, leaving `config/icon` behind a `#` with the
## window icon silently disabled. It did it twice. A comment in project.godot is not a safe place
## to keep anything, and it is actively dangerous immediately above a setting that matters, so the
## explanation lives here in a file the editor does not rewrite.

const SRC := "res://icon.svg"
const OUT_DIR := "res://build/icon.iconset"

# (pixel size, iconset filename) — Apple's required set, both @1x and @2x.
const SIZES := [
	[16, "icon_16x16.png"],
	[32, "icon_16x16@2x.png"],
	[32, "icon_32x32.png"],
	[64, "icon_32x32@2x.png"],
	[128, "icon_128x128.png"],
	[256, "icon_128x128@2x.png"],
	[256, "icon_256x256.png"],
	[512, "icon_256x256@2x.png"],
	[512, "icon_512x512.png"],
	[1024, "icon_512x512@2x.png"],
]

func _init() -> void:
	var svg := FileAccess.get_file_as_string(SRC)
	if svg.is_empty():
		printerr("could not read %s" % SRC)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	for entry in SIZES:
		var px: int = entry[0]
		var name: String = entry[1]
		var img := Image.new()
		# The source viewBox is 1024 wide, so scale is simply px / 1024.
		var err := img.load_svg_from_string(svg, float(px) / 1024.0)
		if err != OK or img.get_width() != px:
			printerr("render failed for %s (err %d, got %dpx)" % [name, err, img.get_width()])
			quit(1)
			return
		var path := "%s/%s" % [OUT_DIR, name]
		if img.save_png(path) != OK:
			printerr("could not write %s" % path)
			quit(1)
			return
		print("  %4dpx  %s" % [px, name])

	# The 1024 is also the project icon and the README asset.
	var big := Image.new()
	big.load_svg_from_string(svg, 1.0)
	big.save_png("res://icon.png")
	print("  1024px  icon.png")
	quit(0)

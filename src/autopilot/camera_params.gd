class_name CameraParams
extends RefCounted
## Survey camera parameters. Sensor dimensions in mm; px_w is along the long sensor side.
## tag "estimated" = numbers are a generic stand-in, not a measured product.

var sensor_w_mm := 13.2  # long side, lies ACROSS the flight direction
var sensor_h_mm := 8.8   # short side, lies ALONG the flight direction
var focal_mm := 8.8
var px_w := 5472
var px_h := 3648
var min_shot_interval_s := 2.0
var tag := "estimated"
## SR5.1 (presets only): see data/cameras/*.json. Every number carries a tag (measured / published / estimated) and a source.
var preset_id := ""
var preset_name := ""
var pixel_pitch_um := 0.0
var exposure_s := 0.0005         # exposure used for the motion-blur check (estimated unless a preset says otherwise)
var shutter_min_s := 0.0
var field_tags: Dictionary = {}  # field name -> {value, tag, source}
const PRESET_DIR := "res://data/cameras/"
const TAGS: Array[String] = ["measured", "published", "estimated"]


static func generic_1inch() -> CameraParams:
	return CameraParams.new()


## Ground footprint at height (m): Vector2(across, along). along = short sensor side.
func footprint_m(height: float) -> Vector2:
	return Vector2(height * sensor_w_mm / focal_mm, height * sensor_h_mm / focal_mm)


## Ground sample distance in cm per pixel (across-track direction).
func gsd_cm(height: float) -> float:
	return footprint_m(height).x / float(px_w) * 100.0


## Preset ids (file names in data/cameras without .json).
static func preset_ids() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(PRESET_DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


## A camera from data/cameras/<id>.json, or null when the file is missing or unreadable. Footprint follows the
## sensor and focal length; when a preset publishes its FOV, the focal length is derived from that FOV and the sensor width
## so the footprint reproduces the published angle exactly (the pixel pitch then only splits width into pixels).
static func from_preset(id: String) -> CameraParams:
	var f := FileAccess.open(PRESET_DIR + id + ".json", FileAccess.READ)
	if f == null:
		return null
	var doc = JSON.parse_string(f.get_as_text())
	if not (doc is Dictionary) or not (doc as Dictionary).has("fields"):
		return null
	var fl: Dictionary = doc["fields"]
	var c := CameraParams.new()
	c.preset_id = String(doc.get("id", id))
	c.preset_name = String(doc.get("name", id))
	c.field_tags = fl.duplicate(true)
	c.px_w = int(fl["px_w"]["value"])
	c.px_h = int(fl["px_h"]["value"])
	c.pixel_pitch_um = float(fl["pixel_pitch_um"]["value"])
	c.sensor_w_mm = c.px_w * c.pixel_pitch_um / 1000.0
	c.sensor_h_mm = c.px_h * c.pixel_pitch_um / 1000.0
	if fl.has("fov_h_deg"):
		c.focal_mm = c.sensor_w_mm / (2.0 * tan(deg_to_rad(float(fl["fov_h_deg"]["value"])) / 2.0))
	else:
		c.focal_mm = float(fl["focal_mm"]["value"])
	c.shutter_min_s = float(fl["shutter_min_s"]["value"])
	c.exposure_s = float(fl["exposure_s"]["value"])
	c.min_shot_interval_s = float(fl["trigger_min_interval_s"]["value"])
	c.tag = "published" if _all_published(fl) else "estimated"
	return c


static func _all_published(fl: Dictionary) -> bool:
	for k in fl:
		if String(fl[k]["tag"]) != "published":
			return false
	return true

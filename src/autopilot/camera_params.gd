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


static func generic_1inch() -> CameraParams:
	return CameraParams.new()


## Ground footprint at height (m): Vector2(across, along). along = short sensor side.
func footprint_m(height: float) -> Vector2:
	return Vector2(height * sensor_w_mm / focal_mm, height * sensor_h_mm / focal_mm)


## Ground sample distance in cm per pixel (across-track direction).
func gsd_cm(height: float) -> float:
	return footprint_m(height).x / float(px_w) * 100.0

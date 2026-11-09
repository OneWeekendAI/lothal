class_name SunPosition
extends RefCounted
## Sun elevation and azimuth for a place and a UTC time (geometric, no refraction). NOAA Global Monitoring Laboratory solar
## calculator algorithm (Meeus, "Astronomical Algorithms", ch. 25 low-precision form): accurate to about 0.01 degree for
## years 1800-2100. Matters to multispectral capture (SR5+): reflectance targets want the sun well above the horizon.

static func _jd(unix_utc: float) -> float:
	return unix_utc / 86400.0 + 2440587.5


## Returns {elevation_deg, azimuth_deg (clockwise from north), declination_deg, equation_of_time_min}.
static func at(lat_deg: float, lon_deg: float, unix_utc: float) -> Dictionary:
	var jd := _jd(unix_utc)
	var t := (jd - 2451545.0) / 36525.0
	var l0 := fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m := 357.52911 + t * (35999.05029 - 0.0001537 * t)
	var ecc := 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
	var mr := deg_to_rad(m)
	var c := sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2.0 * mr) * (0.019993 - 0.000101 * t) + sin(3.0 * mr) * 0.000289
	var true_long := l0 + c
	var omega := 125.04 - 1934.136 * t
	var lam := true_long - 0.00569 - 0.00478 * sin(deg_to_rad(omega))
	var eps0 := 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
	var eps := eps0 + 0.00256 * cos(deg_to_rad(omega))
	var decl := asin(sin(deg_to_rad(eps)) * sin(deg_to_rad(lam)))
	var y := pow(tan(deg_to_rad(eps) / 2.0), 2.0)
	var l0r := deg_to_rad(l0)
	var eq_time := 4.0 * rad_to_deg(y * sin(2.0 * l0r) - 2.0 * ecc * sin(mr) + 4.0 * ecc * y * sin(mr) * cos(2.0 * l0r) \
		- 0.5 * y * y * sin(4.0 * l0r) - 1.25 * ecc * ecc * sin(2.0 * mr))
	var minutes_utc := fposmod(unix_utc / 60.0, 1440.0)
	var tst := fposmod(minutes_utc + eq_time + 4.0 * lon_deg, 1440.0)
	var ha := tst / 4.0 - 180.0
	var lat := deg_to_rad(lat_deg)
	var har := deg_to_rad(ha)
	var cos_zen := clampf(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(har), -1.0, 1.0)
	var zen := acos(cos_zen)
	var az := 0.0
	var denom := cos(lat) * sin(zen)
	if absf(denom) > 1.0e-9:
		var cos_az := clampf((sin(lat) * cos(zen) - sin(decl)) / denom, -1.0, 1.0)
		var ac := rad_to_deg(acos(cos_az))
		az = fposmod(ac + 180.0, 360.0) if ha > 0.0 else fposmod(540.0 - ac, 360.0)   # NOAA: clockwise from north
	return {"elevation_deg": 90.0 - rad_to_deg(zen), "azimuth_deg": fposmod(az, 360.0), "declination_deg": rad_to_deg(decl), "equation_of_time_min": eq_time}


## Seconds since the Unix epoch of an ISO-8601 UTC stamp "YYYY-MM-DDTHH:MM:SSZ" (or without the Z). -1 when unparseable.
static func parse_utc(stamp: String) -> float:
	var s := stamp.strip_edges()
	if s.ends_with("Z"):
		s = s.substr(0, s.length() - 1)
	if s.length() < 19 or s[10] != "T":
		return -1.0
	return float(Time.get_unix_time_from_datetime_string(s))

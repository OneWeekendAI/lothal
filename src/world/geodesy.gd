class_name Geodesy
extends RefCounted
## SR3 geodesy: the WGS84 ellipsoid, polygon area, and the local tangent-plane (ENU) projection the sim uses.
##
## Polygons of latitude/longitude are FLAT PackedFloat64Array [lat0, lon0, lat1, lon1, ...] in degrees. NOT Vector2: Godot's Vector2 is
## 32-bit float and would put a 3 m error into a coordinate like 40.06 N (measured). Sim-metre polygons are Vector2 (metres fit).
##
## AREA. `polygon_area_m2` is the exact area of the polygon on the WGS84 ELLIPSOID whose edges are straight lines in the
## Lambert cylindrical EQUAL-AREA projection of the ellipsoid (Snyder 1987, "Map Projections: A Working Manual", USGS
## Prof. Paper 1395, eq. 10-15 and 3-12: X = a lambda, Y = a q / 2, with q the authalic function of the latitude). That
## projection preserves area exactly, so a shoelace sum in it is the ellipsoidal area with no projection-scale error at all.
## What it is NOT is Karney's algorithm (Karney 2013, J. Geodesy 87, 43-55), whose edges are geodesics: here an edge between
## two vertices follows the projection's straight line instead (a parallel stays a parallel). The difference is a sliver along each
## edge. MEASURED against GeographicLib's PolygonArea (Karney's algorithm) in tests/test_sr3_world.gd: 1 km square 0.00x %, a 23,999 m2
## field 5e-8 relative, a 2 degree (170 km) box 0.0024 %, a 6 degree box under 0.1 % - so everything up to farm and county size is
## far inside the 0.1 % bound. Beyond a few degrees use Karney's series instead.
##
## ENU. latitude/longitude/height -> Earth-centred Earth-fixed (WGS84 prime-vertical radius form) -> rotate to the local
## East / North / Up axes at the origin. Exact (no small-angle shortcut); the sim frame is x = East, y = Up, z = -North
## (north is -Z, see src/sim/wind.gd).

const A_M := 6378137.0                         ## WGS84 semi-major axis (NIMA TR8350.2)
const INV_F := 298.257223563                   ## WGS84 inverse flattening
const F := 1.0 / INV_F
const E2 := F * (2.0 - F)
const E := 0.08181919084262149                 ## sqrt(E2)
const M2_PER_ACRE := 4046.8564224              ## international acre, exactly 4046.8564224 m2
const M2_PER_HECTARE := 10000.0


## Authalic function q(phi) (Snyder eq. 3-12), phi in radians.
static func _q(phi: float) -> float:
	var s := sin(phi)
	var es := E * s
	return (1.0 - E2) * (s / (1.0 - es * es) - (1.0 / (2.0 * E)) * log((1.0 - es) / (1.0 + es)))


static func _wrap_deg(d: float) -> float:
	var x := fmod(d + 180.0, 360.0)
	if x < 0.0:
		x += 360.0
	return x - 180.0


## Area of the polygon in square metres (always positive). Needs 3 or more vertices; else 0. Longitudes may cross +-180.
static func polygon_area_m2(ll: PackedFloat64Array) -> float:
	var n := floori(ll.size() * 0.5)
	if n < 3:
		return 0.0
	var lon0 := ll[1]
	var y0 := _q(deg_to_rad(ll[0])) * 0.5 * A_M
	var sum := 0.0
	for i in n:
		var j := (i + 1) % n
		var xa := A_M * deg_to_rad(_wrap_deg(ll[2 * i + 1] - lon0))
		var xb := A_M * deg_to_rad(_wrap_deg(ll[2 * j + 1] - lon0))
		var ya := _q(deg_to_rad(ll[2 * i])) * 0.5 * A_M - y0
		var yb := _q(deg_to_rad(ll[2 * j])) * 0.5 * A_M - y0
		sum += (xb - xa) * (ya + yb)
	return absf(sum) * 0.5


static func m2_to_acres(m2: float) -> float:
	return m2 / M2_PER_ACRE


static func m2_to_hectares(m2: float) -> float:
	return m2 / M2_PER_HECTARE


## The planar shortcut that SR3's accuracy test must be able to fail: equirectangular, cos(first-vertex latitude) on the longitude
## difference, spherical earth of radius 6371008.8 m. Kept only so a test can show it disagrees on a large polygon.
static func planar_shortcut_area_m2(ll: PackedFloat64Array) -> float:
	var n := floori(ll.size() * 0.5)
	if n < 3:
		return 0.0
	var lat0 := deg_to_rad(ll[0])          # metres-per-degree taken once at the first vertex, as a quick planar tool would
	var r := 6371008.8
	var sum := 0.0
	for i in n:
		var j := (i + 1) % n
		var xa := r * deg_to_rad(ll[2 * i + 1]) * cos(lat0)
		var xb := r * deg_to_rad(ll[2 * j + 1]) * cos(lat0)
		sum += xa * (r * deg_to_rad(ll[2 * j])) - xb * (r * deg_to_rad(ll[2 * i]))
	return absf(sum) * 0.5


## ECEF metres as [x, y, z] (PackedFloat64Array: a Vector3 would hold only 32 bits, about 0.5 m at earth radius).
static func to_ecef(lat_deg: float, lon_deg: float, h_m: float) -> PackedFloat64Array:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var s := sin(lat)
	var n := A_M / sqrt(1.0 - E2 * s * s)
	return PackedFloat64Array([(n + h_m) * cos(lat) * cos(lon), (n + h_m) * cos(lat) * sin(lon), (n * (1.0 - E2) + h_m) * s])


## [East, North, Up] in metres of a point relative to the origin.
static func latlon_to_enu(lat_deg: float, lon_deg: float, h_m: float, o_lat_deg: float, o_lon_deg: float, o_h_m: float = 0.0) -> PackedFloat64Array:
	var p := to_ecef(lat_deg, lon_deg, h_m)
	var q := to_ecef(o_lat_deg, o_lon_deg, o_h_m)
	var dx := p[0] - q[0]
	var dy := p[1] - q[1]
	var dz := p[2] - q[2]
	var la := deg_to_rad(o_lat_deg)
	var lo := deg_to_rad(o_lon_deg)
	var sl := sin(la)
	var cl := cos(la)
	var so := sin(lo)
	var co := cos(lo)
	return PackedFloat64Array([-so * dx + co * dy,
		-sl * co * dx - sl * so * dy + cl * dz,
		cl * co * dx + cl * so * dy + sl * dz])


## Inverse of latlon_to_enu: returns [lat_deg, lon_deg, height_m].
static func enu_to_latlon(e: float, n: float, u: float, o_lat_deg: float, o_lon_deg: float, o_h_m: float = 0.0) -> PackedFloat64Array:
	var la := deg_to_rad(o_lat_deg)
	var lo := deg_to_rad(o_lon_deg)
	var sl := sin(la)
	var cl := cos(la)
	var so := sin(lo)
	var co := cos(lo)
	var o := to_ecef(o_lat_deg, o_lon_deg, o_h_m)
	return ecef_to_latlon(o[0] - so * e - sl * co * n + cl * co * u,
		o[1] + co * e - sl * so * n + cl * so * u,
		o[2] + cl * n + sl * u)


## Bowring's iteration; converges to well under a micrometre in a few passes. Returns [lat_deg, lon_deg, height_m].
static func ecef_to_latlon(x: float, y: float, z: float) -> PackedFloat64Array:
	var lon := atan2(y, x)
	var r := sqrt(x * x + y * y)
	var lat := atan2(z, r * (1.0 - E2))
	var h := 0.0
	for _i in 6:
		var s := sin(lat)
		var n := A_M / sqrt(1.0 - E2 * s * s)
		h = r / cos(lat) - n
		lat = atan2(z, r * (1.0 - E2 * n / (n + h)))
	return PackedFloat64Array([rad_to_deg(lat), rad_to_deg(lon), h])


## Sim frame (x = East, z = -North) from a lat/lon, relative to the home point.
static func latlon_to_sim(lat_deg: float, lon_deg: float, o_lat_deg: float, o_lon_deg: float) -> Vector2:
	var enu := latlon_to_enu(lat_deg, lon_deg, 0.0, o_lat_deg, o_lon_deg, 0.0)
	return Vector2(enu[0], -enu[1])


## Returns [lat_deg, lon_deg] as 64-bit floats in an Array (not a Vector2, see the header).
static func sim_to_latlon(x: float, z: float, o_lat_deg: float, o_lon_deg: float) -> Array:
	var ll := enu_to_latlon(x, -z, 0.0, o_lat_deg, o_lon_deg, 0.0)
	return [ll[0], ll[1]]


## A whole lat/lon polygon into sim metres.
static func polygon_to_sim(ll: PackedFloat64Array, o_lat_deg: float, o_lon_deg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in floori(ll.size() * 0.5):
		out.append(latlon_to_sim(ll[2 * i], ll[2 * i + 1], o_lat_deg, o_lon_deg))
	return out


## Shoelace area of a sim-metre polygon (flat plane).
static func planar_area_m2(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5

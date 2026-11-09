class_name WorldPresets
extends RefCounted
## Shipped worlds (res://data/worlds/*.world.json, written by tools/build_worlds.gd). Each lists, per field, whether it is
## measured, published or estimated. Nothing here is "measured" by this project; the tags say what the NUMBER is.

const DIR := "res://data/worlds"
const IDS: Array[String] = ["illinois_corn_july", "calm_test_field", "windy_coast", "high_altitude"]

const MPH := 0.44704


static func all() -> Array[World]:
	var out: Array[World] = []
	for id in IDS:
		var w := World.load_from("%s/%s%s" % [DIR, id, WorldLibrary.SUFFIX])
		if w != null:
			out.append(w)
	return out


static func by_id(id: String) -> World:
	return World.load_from("%s/%s%s" % [DIR, id, WorldLibrary.SUFFIX])


## A rectangle (east metres x north metres, its south-west corner `sw` metres east/north of home) as a lat/lon polygon.
static func rect_polygon(lat: float, lon: float, sw_e: float, sw_n: float, east_m: float, north_m: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for c in [Vector2(sw_e, sw_n), Vector2(sw_e + east_m, sw_n), Vector2(sw_e + east_m, sw_n + north_m), Vector2(sw_e, sw_n + north_m)]:
		var ll := Geodesy.enu_to_latlon(c.x, c.y, 0.0, lat, lon, 0.0)
		out.append(snappedf(ll[0], 1.0e-7))
		out.append(snappedf(ll[1], 1.0e-7))
	return out


## The Illinois preset WITHOUT terrain (flat placeholder); tools/build_worlds.gd imports the real 3DEP ground into it.
static func illinois_corn_july() -> World:
	var w := World.new()
	w.world_id = "illinois_corn_july"
	w.world_name = "Illinois corn, July, 15 mph"
	w.description = "A 200 m x 120 m (6 acre) plot on corn-belt farmland south of Urbana, Champaign County, Illinois, mid-July afternoon, 15 mph south-westerly wind over full corn canopy. The location is real; the plot boundary is an illustrative rectangle, not a surveyed parcel."
	w.origin_lat = 40.06
	w.origin_lon = -88.23
	w.polygon = rect_polygon(w.origin_lat, w.origin_lon, 30.0, 0.0, 200.0, 120.0)
	w.surface_name = "full corn canopy (about 2.5 m tall)"
	w.z0_m = 0.15
	w.wind_speed_mps = 15.0 * MPH
	w.wind_ref_height_m = 10.0
	w.wind_from_deg = 225.0
	w.gustiness_mps = 0.12 * 15.0 * MPH * 1.0
	w.temperature_c = snappedf((85.2 - 32.0) / 1.8, 0.1)
	w.humidity_pct = 55.0
	w.pressure_hpa = 0.0
	w.utc = "2026-07-15T18:00:00Z"
	w.set_source("origin", "estimated", "Real location (Champaign County, IL); the exact launch spot is chosen, not surveyed.")
	w.set_source("field.polygon", "estimated", "Illustrative 200 x 120 m rectangle placed on farmland; vertices are WGS84, area is geodesic.")
	w.set_source("terrain", "estimated", "Flat placeholder until the USGS 3DEP tile is imported.")
	w.set_source("surface.z0", "estimated", "Mature corn canopy, z0 0.15 m: within the 0.1-0.25 m range Wieringa (1992, J. Wind Eng. Ind. Aerodyn. 41-44) gives for tall crops; the value inside the range is a choice.")
	w.set_source("wind.speed", "estimated", "Scenario value set by the preset name: 15 mph (6.71 m/s) at the 10 m reference height. Not an observation.")
	w.set_source("wind.from", "estimated", "South-westerly (225 deg) is the prevailing summer direction in central Illinois; a scenario choice.")
	w.set_source("wind.gust", "estimated", "Dryden sigma_u of 12 % of the mean speed, a typical open-terrain turbulence intensity; the user may edit it.")
	w.set_source("air.temperature", "published", "Champaign-Urbana July 1991-2020 average high 85.2 F (29.6 C), Illinois State Water Survey weather almanac (stateclimatologist.web.illinois.edu).")
	w.set_source("air.humidity", "estimated", "55 % RH is a typical July afternoon figure for central Illinois; not taken from a station record.")
	w.set_source("air.pressure", "published", "Left blank: pressure follows the International Standard Atmosphere at the 3DEP elevation of the launch point.")
	w.set_source("time", "estimated", "15 July 2026, 18:00 UTC (1 pm CDT), a scenario time; sun position is computed (NOAA algorithm).")
	return w


static func calm_test_field() -> World:
	var w := World.new()
	w.world_id = "calm_test_field"
	w.world_name = "Calm test field"
	w.description = "Flat 200 m x 120 m field, no wind, International Standard Atmosphere at sea level. The reference for comparing against other worlds."
	w.origin_lat = 40.06
	w.origin_lon = -88.23
	w.origin_elevation_m = 0.0
	w.polygon = rect_polygon(w.origin_lat, w.origin_lon, 30.0, 0.0, 200.0, 120.0)
	w.terrain = Terrain.flat(260.0, 160.0, 130.0, -60.0)
	w.surface_name = "short grass"
	w.z0_m = 0.03
	w.temperature_c = 15.0
	w.humidity_pct = 0.0
	w.utc = "2026-06-21T18:00:00Z"
	w.set_source("origin", "estimated", "Position shared with the Illinois preset; elevation set to sea level on purpose, for ISA.")
	w.set_source("field.polygon", "estimated", "Illustrative rectangle.")
	w.set_source("terrain", "estimated", "Flat by construction.")
	w.set_source("surface.z0", "published", "Short grass 0.03 m, Davenport-Wieringa roughness classification (Wieringa 1992).")
	w.set_source("wind.speed", "estimated", "Zero by definition of a calm test.")
	w.set_source("wind.from", "estimated", "Irrelevant at zero wind.")
	w.set_source("wind.gust", "estimated", "Zero turbulence by definition.")
	w.set_source("air.temperature", "published", "15 C: the ISA sea-level temperature (ICAO Doc 7488).")
	w.set_source("air.humidity", "published", "0 %: the dry-air convention of the ISA.")
	w.set_source("air.pressure", "published", "Blank: ISA pressure at 0 m, 1013.25 hPa.")
	w.set_source("time", "estimated", "Summer solstice, 18:00 UTC; a scenario time.")
	return w


static func windy_coast() -> World:
	var w := World.new()
	w.world_id = "windy_coast"
	w.world_name = "Windy coast, 25 mph"
	w.description = "A flat 200 m x 120 m beach-front plot near Cape Hatteras, North Carolina: strong onshore wind, warm humid air, very smooth surface."
	w.origin_lat = 35.25
	w.origin_lon = -75.53
	w.origin_elevation_m = 2.0
	w.polygon = rect_polygon(w.origin_lat, w.origin_lon, 30.0, 0.0, 200.0, 120.0)
	w.terrain = Terrain.flat(260.0, 160.0, 130.0, -60.0)
	w.surface_name = "sand and sea-front scrub"
	w.z0_m = 0.005
	w.wind_speed_mps = 25.0 * WorldPresets.MPH
	w.wind_from_deg = 90.0
	w.gustiness_mps = 0.15 * 25.0 * WorldPresets.MPH
	w.temperature_c = 27.0
	w.humidity_pct = 75.0
	w.utc = "2026-08-15T17:00:00Z"
	w.set_source("origin", "estimated", "Real stretch of coast (Hatteras Island, NC); launch spot chosen, elevation approximate.")
	w.set_source("field.polygon", "estimated", "Illustrative rectangle.")
	w.set_source("terrain", "estimated", "Flat; the real dunes (a few metres) are not modelled. Import 3DEP to replace.")
	w.set_source("surface.z0", "published", "Sand / smooth open ground 0.005 m: Davenport-Wieringa class 'sea/sand' 0.0002-0.005, upper end (Wieringa 1992).")
	w.set_source("wind.speed", "estimated", "Scenario: 25 mph (11.2 m/s) at 10 m.")
	w.set_source("wind.from", "estimated", "East, onshore on the Atlantic side; scenario choice.")
	w.set_source("wind.gust", "estimated", "Turbulence intensity 15 %, scenario choice; editable.")
	w.set_source("air.temperature", "estimated", "27 C typical August afternoon on the Outer Banks; not from a record.")
	w.set_source("air.humidity", "estimated", "75 % RH typical coastal summer; not from a record.")
	w.set_source("air.pressure", "published", "Blank: ISA pressure at 2 m.")
	w.set_source("time", "estimated", "15 August 2026, 17:00 UTC, scenario.")
	return w


static func high_altitude() -> World:
	var w := World.new()
	w.world_id = "high_altitude"
	w.world_name = "High altitude, Leadville"
	w.description = "A 200 m x 120 m plot at about 3,100 m near Leadville, Colorado: thin cold dry air and a light breeze over short mountain grass. Ground is flat here; import 3DEP for the real slope."
	w.origin_lat = 39.25
	w.origin_lon = -106.29
	w.origin_elevation_m = 3094.0
	w.polygon = rect_polygon(w.origin_lat, w.origin_lon, 30.0, 0.0, 200.0, 120.0)
	w.terrain = Terrain.flat(260.0, 160.0, 130.0, -60.0)
	w.surface_name = "short alpine grass"
	w.z0_m = 0.03
	w.wind_speed_mps = 5.0 * WorldPresets.MPH
	w.wind_from_deg = 270.0
	w.gustiness_mps = 0.2 * 5.0 * WorldPresets.MPH
	w.temperature_c = 12.0
	w.humidity_pct = 30.0
	w.utc = "2026-07-15T19:00:00Z"
	w.set_source("origin", "published", "Leadville, CO elevation 3,094 m (10,152 ft), widely published town elevation (USGS GNIS).")
	w.set_source("field.polygon", "estimated", "Illustrative rectangle.")
	w.set_source("terrain", "estimated", "Flat placeholder; the real ground slopes. Import 3DEP to replace.")
	w.set_source("surface.z0", "published", "Short grass 0.03 m, Davenport-Wieringa class (Wieringa 1992).")
	w.set_source("wind.speed", "estimated", "Scenario: 5 mph light breeze at 10 m.")
	w.set_source("wind.from", "estimated", "West, scenario choice.")
	w.set_source("wind.gust", "estimated", "Turbulence intensity 20 %, mountain air; scenario.")
	w.set_source("air.temperature", "estimated", "12 C: a plausible July afternoon at 3,100 m; not from a record.")
	w.set_source("air.humidity", "estimated", "30 % RH, dry mountain air; scenario.")
	w.set_source("air.pressure", "published", "Blank: ISA pressure at 3,094 m (about 69 kPa).")
	w.set_source("time", "estimated", "15 July 2026, 19:00 UTC (1 pm MDT), scenario.")
	return w

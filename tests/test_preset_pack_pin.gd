class_name TestPresetPackPin
extends RefCounted
## Pins how every shelf battery preset flies on the reference airframe, so the pack designer
## (which adds a second source of battery records) cannot move a preset figure unnoticed.
## Order of each row: AUW g, T:W, hover throttle, flight time min, top speed km/h, R ohm, mass g.

const REL_TOL := 1e-9

const GOLDEN := {
	"battery_1s_300": [325.530708465516, 0.91703059984253, 1.0, 0.0, 46.9173887686143, 0.09, 8.0],
	"battery_1s_550": [330.530708465516, 0.90315850601954, 1.0, 0.0, 46.917388768577, 0.07, 13.0],
	"battery_2s_300": [336.480708465516, 3.36801861838821, 0.54349555896071, 1.28472998627031, 88.0940712825803, 0.03, 19.0],
	"battery_2s_450": [346.180708465516, 3.27364657569647, 0.54525169384672, 1.85342215749067, 89.3548289421305, 0.014, 28.0],
	"battery_3s_650": [382.480708465516, 6.35048269952925, 0.38159046055765, 3.75083437922196, 93.9228720094946, 0.02, 62.0],
	"battery_4s_1300": [477.480708465516, 8.64188216420273, 0.31954025173841, 8.36278390198262, 104.940833999123, 0.011, 155.0],
	"battery_4s_1500": [507.480708465516, 8.13101256738593, 0.33030605792066, 9.05839858930204, 108.1873206628, 0.015, 185.0],
	"battery_4s_3000_liion": [642.480708465516, 6.10911489170682, 0.41363405104594, 12.7211850234457, 121.729725437683, 0.15, 320.0],
	"battery_4s_650": [398.480708465516, 10.3551613179189, 0.29127327029062, 4.88837693489846, 95.8672450116275, 0.018, 78.0],
	"battery_5s_1200": [497.480708465516, 12.4184756581285, 0.26100611727416, 9.28088410503663, 107.116091764687, 0.014, 172.0],
	"battery_6s_1100": [503.480708465516, 16.9718038471897, 0.21865018474373, 10.1090719002254, 107.76010698442, 0.013, 178.0],
	"battery_6s_1300": [530.480708465516, 16.1079859994123, 0.22481848945113, 11.3114003545242, 110.611783268697, 0.017, 205.0],
	"battery_6s_4000_liion": [915.480708465516, 8.89272368003879, 0.33157018027004, 15.1267285414311, 145.308558702462, 0.2, 590.0],
	"battery_6s_5600": [1224.48070846552, 6.97844871368302, 0.34837539333077, 16.0461592789903, 168.051568464435, 0.0065, 892.0],
}

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()
	var ids: Array = []
	for part in catalog.list_category("battery"):
		var pid := String(part.get("part_id", ""))
		if pid.begins_with("battery_"):
			ids.append(pid)
	ids.sort()
	results.append(TestResult.new("the shelf has exactly 14 preset batteries",
		ids.size() == 14, "%d ids: %s" % [ids.size(), ids]))
	for id in ids:
		var b := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, id)
		var got: Array = [b.all_up_weight_g(), b.thrust_to_weight(), b.hover_throttle(),
			b.flight_time_min(), b.top_speed_kmh(),
			float(b.battery.specs.internal_r_ohm), float(b.battery.mass_g)]
		var want: Array = GOLDEN.get(id, [])
		var ok := want.size() == got.size()
		var detail := ""
		if ok:
			for i in got.size():
				if absf(got[i] - want[i]) > REL_TOL * maxf(absf(want[i]), 1e-12):
					ok = false
					detail += " [%d] got %s want %s" % [i, got[i], want[i]]
		results.append(TestResult.new("%s flies exactly as before the pack designer" % id,
			ok, detail if detail != "" else "matches golden"))
	return results

class_name TestPresetPackPin
extends RefCounted
## Pins how every shelf battery preset flies on the reference airframe, so the pack designer
## (which adds a second source of battery records) cannot move a preset figure unnoticed.
## Order of each row: AUW g, T:W, hover throttle, flight time min, top speed km/h, R ohm, mass g.

const REL_TOL := 1e-9
## Column 3 (flight time) RE-PINNED a third time (2026-11-09, kappa decision): induced-power factor 1.15 in hover and forward
## flight, so the 1.045 forward penalty is gone and every pack with a forward leg flies 0.4 to 1.1 percent longer (hover col 2, top
## speed and the rest unchanged to 1e-9).
## Column 3 (flight time) RE-PINNED at SR1 (2026-11-09) for the uncapped forward-flight thrust ratio and directional
## drag, and AGAIN the same day for the bucket-depth terms (induced-power factor 1.15/1.10, profile 1+4.65 mu^2, rear-rotor
## interference): every freestyle-profile pack draws 8 to 13 percent more in forward flight, hover (col 2) unchanged. Earlier note:
## drag; every other column is unchanged to 1e-9, which is the check that hover physics did not move.

const GOLDEN := {
	"battery_1s_300": [325.530708465516, 0.91703059984253, 1.0, 0.0, 46.9173887686143, 0.09, 8.0],
	"battery_1s_550": [330.530708465516, 0.90315850601954, 1.0, 0.0, 46.917388768577, 0.07, 13.0],
	"battery_2s_300": [336.480708465516, 3.36801861838821, 0.54349555896071, 1.20094941005569, 88.0940712825803, 0.03, 19.0],
	"battery_2s_450": [346.180708465516, 3.27364657569647, 0.54525169384672, 1.36017622669237, 89.3548289421305, 0.014, 28.0],
	"battery_3s_650": [382.480708465516, 6.35048269952925, 0.38159046055765, 2.82149331298291, 93.9228720094946, 0.02, 62.0],
	"battery_4s_1300": [477.480708465516, 8.64188216420273, 0.31954025173841, 6.86541730027774, 104.940833999123, 0.011, 155.0],
	"battery_4s_1500": [507.480708465516, 8.13101256738593, 0.33030605792066, 7.72927013780706, 108.1873206628, 0.015, 185.0],
	"battery_4s_3000_liion": [642.480708465516, 6.10911489170682, 0.41363405104594, 11.28454362557402, 121.729725437683, 0.15, 320.0],
	"battery_4s_650": [398.480708465516, 10.3551613179189, 0.29127327029062, 3.82123864675712, 95.8672450116275, 0.018, 78.0],
	"battery_5s_1200": [497.480708465516, 12.4184756581285, 0.26100611727416, 7.68422507987772, 107.116091764687, 0.014, 172.0],
	"battery_6s_1100": [503.480708465516, 16.9718038471897, 0.21865018474373, 8.64772043175294, 107.76010698442, 0.013, 178.0],
	"battery_6s_1300": [530.480708465516, 16.1079859994123, 0.22481848945113, 9.76754697608741, 110.611783268697, 0.017, 205.0],
	"battery_6s_4000_liion": [915.480708465516, 8.89272368003879, 0.33157018027004, 15.01989020969537, 145.308558702462, 0.2, 590.0],
	"battery_6s_5600": [1224.48070846552, 6.97844871368302, 0.34837539333077, 15.63286547353022, 168.051568464435, 0.0065, 892.0],
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

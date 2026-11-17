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

## Column 4 (top speed) RE-PINNED at SR1.3 (2026-11-10) for the four thrust-limited packs (1S x2, 2S x2) only; the other
## ten (lean-capped at 45 degrees, where the top-area drag cancels) are unchanged to 1e-9. top_speed_kmh() now trims the lean
## with directional drag (top area included) and asks whether the rotors, evaluated at that lean and speed, can make the thrust
## it needs. 1S packs (T:W 0.9, cannot hover): 46.9 -> 0.0, the old figure came from a 45 degree lean the aircraft could not hold
## (flight time col 3 is already 0 for them). 2S 300: 88.09 -> 80.85; 2S 450: 89.35 -> 80.67 (the real lean is shallower than the
## fixed 45, so more of the airflow is edgewise, which costs these builds thrust).

## Columns 3 and 4 RE-PINNED at B1 (2026-11-17): per-rotor H-force + flapping with the TPP power path deepen the forward-flight
## bucket (min near 10-12 m/s), so every freestyle-profile pack flies longer (4S 1500 7.73 -> 9.03 min, +17 %; +4 to +27 % across the
## shelf, Li-ion least), and the body Cd*A recalibration (body + rotor drag reproduce the 108.2 km/h calibration) moves top speed by
## under 1.5 %. AUW, T:W, hover throttle, R and mass are unchanged to 1e-9: hover physics did not move.
const GOLDEN := {
	"battery_1s_300": [325.530708465516, 0.91703059984253, 1.0, 0.0, 0.0, 0.09, 8.0],
	"battery_1s_550": [330.530708465516, 0.90315850601954, 1.0, 0.0, 0.0, 0.07, 13.0],
	"battery_2s_300": [336.480708465516, 3.36801861838821, 0.54349555896071, 1.46912689996185, 81.33430947365424, 0.03, 19.0],
	"battery_2s_450": [346.180708465516, 3.27364657569647, 0.54525169384672, 1.7450449748316, 81.07985431236226, 0.014, 28.0],
	"battery_3s_650": [382.480708465516, 6.35048269952925, 0.38159046055765, 3.6300994519581, 93.56131893093392, 0.02, 62.0],
	"battery_4s_1300": [477.480708465516, 8.64188216420273, 0.31954025173841, 8.18695784798645, 104.64419087627809, 0.011, 155.0],
	"battery_4s_1500": [507.480708465516, 8.13101256738593, 0.33030605792066, 9.02710154982905, 108.43297880415629, 0.015, 185.0],
	"battery_4s_3000_liion": [642.480708465516, 6.10911489170682, 0.41363405104594, 12.88147379135282, 122.02916768457376, 0.15, 320.0],
	"battery_4s_650": [398.480708465516, 10.3551613179189, 0.29127327029062, 4.8003449156713, 95.8110902886409, 0.018, 78.0],
	"battery_5s_1200": [497.480708465516, 12.4184756581285, 0.26100611727416, 9.07703789023051, 106.71558631023422, 0.014, 172.0],
	"battery_6s_1100": [503.480708465516, 16.9718038471897, 0.21865018474373, 10.09847616935465, 108.12086897784637, 0.013, 178.0],
	"battery_6s_1300": [530.480708465516, 16.1079859994123, 0.22481848945113, 11.29061709386752, 110.91108318856213, 0.017, 205.0],
	"battery_6s_4000_liion": [915.480708465516, 8.89272368003879, 0.33157018027004, 16.2355874695178, 147.20303909907818, 0.2, 590.0],
	"battery_6s_5600": [1224.48070846552, 6.97844871368302, 0.34837539333077, 16.39732379176158, 167.3801844825617, 0.0065, 892.0],
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

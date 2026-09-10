class_name WireGauge
extends RefCounted
## Wire, as a gauge and a length rather than as a part you pick
## (plans/2026-09-10-power-room-design.md §4.1).
##
## ## Why a derived table and not a parts file
##
## This follows HardwareMass's argument exactly, and it is the same argument. A JSON row per gauge
## is a row nobody maintains, and — decisively — it cannot answer *"what if I shorten these motor
## leads"*, which is the entire question the harness view exists to ask. A connector is a thing you
## buy and it earns a parts file. Wire is two numbers.
##
## So the table below holds physics — area, ampacity, and the geometry mass is integrated out of —
## and the BUILD holds the choices: one gauge and one length per segment.
##
## ## The licence, and it is HardwareMass's standoff check repeated
##
## Mass per metre here is DERIVED, not tabulated: copper area times copper density, plus a silicone
## annulus between the conductor bundle and the published jacket diameter. That is only legitimate
## if the derivation lands on a figure somebody else published, so it was checked against one:
##
##     18 AWG UL 3239 silicone lead wire, jacket OD 0.135" (3.43 mm)
##         computed  17.55 g/m
##         published 17.86 g/m   (12 lb per 1000 ft, wireandcableyourway.com's own spec table)
##
## Under 2%, on the same order as the 0.407 g / 0.4 g standoff number that licenses every derived
## mass in the app. tests/test_wire_gauge.gd asserts that against the PUBLISHED figure and not
## against 17.55, because a test that compares the code to itself proves only that nobody edited the
## code today.
##
## **18 AWG is the only anchored row.** Every other jacket diameter below is class-typical silicone
## hobby wire, and the table says so on each line rather than in a footnote. Under design §0
## (existence before precision) a labelled rough number is allowed; an unlabelled one is not.
##
## ## What is NOT modelled, named rather than left missing
##
##   - Skin effect. DC, and at DShot's fundamental the harness is not a transmission line.
##   - Temperature. Copper's resistivity rises about 0.4%/K, so a lead at 60 C is ~15% more
##     resistant than the table says. Ampacity is a RATING, not a temperature (design §3.5), and a
##     harness thermal state belongs to the heat overlay or to nothing.
##   - The few-percent penalty stranded tinned copper carries over solid annealed copper. Left out
##     deliberately: it is smaller than the jacket-diameter spread above and adding a fudge factor
##     would make the resistivity constant stop meaning copper's resistivity.

## Annealed copper at 20 C. One constant beside the table rather than a column, because it is the
## same number on every row and a column of nine identical values is nine chances to typo one.
const COPPER_RESISTIVITY_OHM_M := 1.724e-8
const COPPER_DENSITY_KG_M3 := 8960.0
## Silicone insulation compounds run 1.1-1.4 g/cm3 depending on filler. 1.25 is the middle of that
## and is a ROUGH value; it is what the 18 AWG anchor above was checked with, and the anchor is what
## constrains it — moving it far enough to matter breaks that check rather than passing quietly.
const SILICONE_DENSITY_KG_M3 := 1250.0
## Round strands in a bundle do not fill their circle. 0.75 is the usual packing figure for a
## concentric lay and is here for ONE purpose: turning a conductor area into the bundle DIAMETER the
## jacket wraps, so the silicone annulus is an annulus and not the whole disc. It never touches
## resistance, which reads area directly.
const STRAND_PACKING_FACTOR := 0.75

## AWG -> [conductor area mm2, chassis-wiring ampacity A, silicone jacket OD mm].
##
## Areas are the standard AWG series and are not negotiable. Ampacity is the CHASSIS-WIRING column
## of the standard table — free air, single conductor, not the far lower power-transmission column,
## because a motor lead is chassis wiring in the literal sense.
##
## Range: 12 AWG at the 6S cinelifter end down to 28 AWG at the whoop end. Nothing in this catalog
## needs anything outside it, and a gauge that is absent refuses (see _row) rather than being
## interpolated into existence.
const GAUGES := {
	12: [3.309, 41.0, 5.0],
	14: [2.081, 32.0, 4.4],
	16: [1.309, 22.0, 3.9],
	# THE ANCHOR. 3.43 mm is 0.135", the published UL 3239 jacket OD; see the header.
	18: [0.823, 16.0, 3.43],
	20: [0.518, 11.0, 2.9],
	22: [0.326, 7.0, 2.4],
	24: [0.205, 3.5, 2.0],
	26: [0.1288, 2.2, 1.7],
	28: [0.0810, 1.4, 1.4],
}

const MM2_PER_M2 := 1.0e6
const KG_TO_G := 1000.0


## Resistance in ohms of one conductor `length_m` long at `awg`.
##
##     R = rho * L / A
##
## Arithmetic, not a model (design §3.2). This is one of the two functions the rest of the app is
## allowed to know about; the drop across a harness segment is this times the current in it, and
## nothing downstream should be dividing by an area of its own.
##
## A run of zero or negative length is zero ohms, not an error: a builder dragging a length field to
## nothing should get a shorter wire, not a refusal.
static func resistance_ohm(awg: int, length_m: float) -> float:
	var row := _row(awg)
	if row.is_empty() or length_m <= 0.0:
		return 0.0
	return COPPER_RESISTIVITY_OHM_M * length_m / (float(row[0]) / MM2_PER_M2)


## Mass in grams of one conductor `length_m` long at `awg`: copper plus its silicone jacket.
##
##     m = L * [ rho_cu * A  +  rho_si * (pi/4)*(OD^2 - d_bundle^2) ]
##
## where d_bundle is the diameter of the strand bundle, area A divided by the packing factor. The
## second of the two public functions, and the reason the harness stops being a 14 g lump at the
## origin in PW2.
##
## Per CONDUCTOR. A connector pair with two leads is two calls, and connectors.json carries its own
## pigtail mass separately for exactly that reason.
static func mass_g(awg: int, length_m: float) -> float:
	var row := _row(awg)
	if row.is_empty() or length_m <= 0.0:
		return 0.0
	var area_mm2 := float(row[0])
	var od_mm := float(row[2])
	var bundle_d_mm := sqrt(4.0 * area_mm2 / STRAND_PACKING_FACTOR / PI)
	var jacket_mm2 := PI / 4.0 * (od_mm * od_mm - bundle_d_mm * bundle_d_mm)
	# Clamps rather than propagating a negative jacket: a jacket OD authored smaller than its own
	# conductor bundle is a typo, and a typo that LIGHTENS an aircraft is the direction of error
	# least likely to be noticed.
	if jacket_mm2 < 0.0:
		jacket_mm2 = 0.0
	var copper_g := area_mm2 / MM2_PER_M2 * COPPER_DENSITY_KG_M3 * KG_TO_G * length_m
	var jacket_g := jacket_mm2 / MM2_PER_M2 * SILICONE_DENSITY_KG_M3 * KG_TO_G * length_m
	return copper_g + jacket_g


## The chassis-wiring rating for a gauge. A LOOKUP, not a derivation — which is why it is not one of
## the two functions the header calls the public surface. PW3's ampacity check compares a segment's
## share of the draw against this; it does not compute a rating.
##
## An unknown gauge returns 0.0, which every comparison reads as "over its rating" — the safe
## direction for a number that decides whether to warn.
static func ampacity_a(awg: int) -> float:
	var row := _row(awg)
	return 0.0 if row.is_empty() else float(row[1])


## The gauges this table covers, ascending — the order a picker wants, thickest wire last.
static func gauges() -> Array:
	var out := GAUGES.keys()
	out.sort()
	return out


## Refuses rather than interpolating. A 19 AWG lead does not exist as a purchase, and inventing a
## row for one would put a number nobody published behind a voltage drop that reads as exact.
static func _row(awg: int) -> Array:
	return GAUGES.get(awg, [])

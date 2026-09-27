extends RefCounted
## The air itself moves. A steady offset plus a seeded gust process, both authored by the
## builder's own `Conditions` (design §4.3) — `Wind` reads that set, it never writes one:
## `Sim authors nothing` (design §6) is a global constraint of this plan and `Wind` is where it
## first has anything to write, so this class is the guard for it.
##
## The steady half is a constant vector for the object's lifetime — `Conditions` is a snapshot the
## builder picked before flying, not something Sim watches for edits mid-flight. The gust half is a
## first-order stochastic process, shaped exactly like `src/sim/gyro.gd`'s sensor noise: white
## noise through a one-pole filter. Built the same way for the same reason gyro.gd states — an
## unseeded global RNG would make every test in this repo that touches the flight loop
## irreproducible, which is a worse defect than having no noise at all.

## AN ALIAS, NOT A NUMBER. The settling time is a field of the weather the builder authors, so it
## lives on `Conditions` beside `gustiness_mps` and is re-exported here under the name every
## caller already spells. Sim authors nothing, and that includes the constants it flies at.
##
## It is still a labelled guess with an editable field (`Conditions.DEFAULT_GUST_TAU_S` says why
## and what it is). Nothing else here is free: the gust amplitude is the builder's own figure.
##
## `p_gust_tau_s` below stays a DEFAULTED ARGUMENT because the test suite drives this process at
## chosen time constants — but a production caller must pass `p_conditions.gust_tau_s`, and the
## one that matters does, through `Main.make_wind()`. A bare `Wind.new(conditions)` flies at the
## default whatever the builder typed, which is the defect that made the Field room's "Gust
## settle" field a dial with no wire.
const DEFAULT_GUST_TAU_S := Conditions.DEFAULT_GUST_TAU_S
const DEFAULT_SEED := 0x10FA2   # distinct from Gyro's, so the two streams never correlate

## The constant part of the wind, m/s, world frame. Built once from `Conditions` in `_init` —
## `wind_speed_mps`/`wind_from_deg` are a builder's snapshot, not something re-read every tick.
var steady_mps: Vector3
var gust_tau_s: float

## Kept for display (the HUD line, check 13) — the figures a builder actually typed, rather than
## a builder having to invert `steady_mps` back into a speed and a bearing to show them.
var speed_mps: float
var from_deg: float

## The amplitude of the gust process, m/s — `conditions.gustiness_mps`, NOT a free constant (see
## `conditions.gd`'s header). Held so `update()`/`reset()` never need the `Conditions` object back.
var gustiness_mps: float

var _rng := RandomNumberGenerator.new()
var _seed: int
## The current gust vector, world frame, m/s. Zero at construction and after every `reset()`.
var _gust := Vector3.ZERO

func _init(p_conditions: Conditions, p_gust_tau_s := DEFAULT_GUST_TAU_S,
		p_seed := DEFAULT_SEED) -> void:
	speed_mps = p_conditions.wind_speed_mps
	from_deg = p_conditions.wind_from_deg
	steady_mps = steady_vector(speed_mps, from_deg)
	gustiness_mps = p_conditions.gustiness_mps
	gust_tau_s = p_gust_tau_s
	_seed = p_seed
	_rng.seed = _seed

## `from_deg` is the bearing the wind comes FROM (0 = north, clockwise — the meteorological
## convention `conditions.gd` names). The air itself moves the OPPOSITE way, so this inverts it at
## this one point — cheaper than inverting every user's intuition. North (`from_deg = 0`) is -Z in
## this codebase's own convention (`main.gd`: "+Z, per the coordinate contract's -Z-is-forward" —
## the camera's forward, -Z, is the direction a builder facing the field calls "ahead"/"north"), so
## a north wind blows the air toward +Z ("south").
##
## THIS IS NOT A GUESS PINNED HERE FOR THE FIRST TIME — `Terrain._banked_height()` (terrain.gd)
## already fixes both axes this way, and independently agrees on both: its NORTH case is
## `distance = half_z + dz`, zero at `dz = -half_z`, so the NORTH edge sits at -Z; its EAST case is
## `distance = half_x - dx`, zero at `dx = +half_x`, so the EAST edge sits at +X. `steady_vector`'s
## own four cardinal cases (see `tests/test_wind.gd`'s `_cardinal_bearings()`) land on exactly
## those axes. Named here so a future reader checks that mapping before "fixing" this one to
## disagree with it.
##
## Nothing here normalises `from_deg` first — `conditions.gd`'s header is explicit that a 370 stays
## 370 — and `sin`/`cos` do not need it normalised either, so none happens here.
static func steady_vector(p_speed_mps: float, p_from_deg: float) -> Vector3:
	# The direction the air MOVES, not the direction it comes from.
	var towards_rad := deg_to_rad(p_from_deg + 180.0)
	return Vector3(p_speed_mps * sin(towards_rad), 0.0, -p_speed_mps * cos(towards_rad))

## Steady plus the current gust — does not advance anything. `update()` is the only thing that
## moves the process forward; this is what a caller reads without paying for a step (e.g. the HUD,
## which draws every frame but must not perturb the physics's own gust stream).
func velocity_mps() -> Vector3:
	return steady_mps + _gust

## Advances the gust process by one physics tick and returns `velocity_mps()`.
##
## The filter: `a = dt / (gust_tau_s + dt)`, exactly `gyro.gd`'s PT1 coefficient — a single time
## constant, assertable rather than approximate. Driven by white noise of standard deviation
## `gustiness_mps * sqrt((2 - a) / a)`, NOT `gustiness_mps` itself: a PT1 driven by noise of
## standard deviation sigma has its OWN standard deviation `sigma * sqrt(a / (2 - a))` (see
## `gyro.gd`'s `_sample()` header for the derivation this inverts), so a driver scaled to
## `gustiness_mps` directly would under-report the builder's own gustiness figure by that same
## factor — worse the slower the gust (small a), which is exactly the regime a hand-flown gust
## front lives in. Solving `sigma * sqrt(a / (2 - a)) = gustiness_mps` for sigma gives the
## expression used below.
func update(dt: float) -> Vector3:
	var a := dt / (gust_tau_s + dt)
	var sigma := gustiness_mps * sqrt((2.0 - a) / a)
	var drive := Vector3(
		_rng.randfn(0.0, sigma),
		_rng.randfn(0.0, sigma),
		_rng.randfn(0.0, sigma))
	_gust += (drive - _gust) * a
	return velocity_mps()

## Re-seeded, so a respawn replays the same gust rather than continuing the old stream — the same
## reason `gyro.gd`'s `reset()` re-seeds. Without this, "the same flight twice" would not be the
## same flight.
func reset() -> void:
	_gust = Vector3.ZERO
	_rng.seed = _seed

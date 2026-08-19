class_name ControlEffectiveness
extends RefCounted
## The control effectiveness matrix B, and everything that falls out of it: the mixer, whether the
## layout can be flown at all, how much authority each axis has, and how badly balanced it is.
##
## This is airframe.md §4.1 (slice A4). It exists to replace ARITHMETIC, not behaviour. Today the
## four motors sit on a symmetric X at fixed positions (motor_layout.gd) and the mixer is a
## hand-written table of +/-1 sign patterns (motor_mixer.gd). Both are correct and both are
## correct for exactly one aircraft. The moment a builder places motors anywhere — six of them, or
## a deadcat with the front arms swept forward, or a stretched X — the table is silently wrong:
## it still produces four numbers, the aircraft still flies, and it flies a different aircraft than
## the one on screen. So the table has to become a computation over the geometry.
##
## NOTHING HERE IS WIRED IN YET. RateModeController still calls MotorMixer. This class is built
## beside the old one and proved equivalent to it (test_control_effectiveness.gd), because the
## thing that would make a rewiring unreviewable is doing it in the same change as the maths.
##
## ---------------------------------------------------------------------------
## THE SIGN CONVENTION, WHICH DOES NOT MATCH THE DESIGN DOC
## ---------------------------------------------------------------------------
##
## airframe.md §4.1 writes the rows as
##
##     roll  = -sum(z_i * T_i)        pitch = +sum(x_i * T_i)
##
## THAT IS WRONG FOR THIS REPO, in two separate ways, and it is wrong in the way that flies
## backwards rather than the way that crashes on the bench. The doc has x and z swapped, and its
## pitch sign inverted. Both fall straight out of the coordinate contract (physics.md §1): the nose
## is -Z and the right side is +X, so ROLL — rotation about the fore-aft axis — is driven by a
## motor's LATERAL position x, and PITCH is driven by its FORE-AFT position z. The doc's rows have
## each axis reading the other one's coordinate.
##
## The repo's authority is MotorLayout.thrust_torque(), the project's only cross product for thrust
## torque. With r = (x, 0, z) and F = (0, T, 0), r x F = (-z*T, 0, x*T), and torque_from_motor()
## then relabels that into the contract's axes as pitch = tau.x, roll = -tau.z. So:
##
##     F     = sum(T_i)
##     roll  = -sum(x_i * T_i)
##     pitch = -sum(z_i * T_i)
##     yaw   =  sum(s_i * q_i * T_i)
##
## Hand-check against test_torque_signs.gd, which is the assertion that pins this down: M1 is the
## REAR-RIGHT motor, at (+a, 0, +a). Extra thrust there lifts the right side (the contract's +Roll
## is right side DOWN, so roll must be negative) and lifts the tail (+Pitch is nose UP, so pitch
## must be negative). Both rows above give -a*T. They agree. The doc's rows would give roll = -a*T
## and pitch = +a*T — half right, which is worse than all wrong, because the sim would still look
## stable and only pitch would be mirrored.
##
## MATCH THE REPO. The doc is the thing that is wrong here, and §4.1 should be corrected.
##
## ---------------------------------------------------------------------------
## ROW ORDER AND UNITS
## ---------------------------------------------------------------------------
##
## Rows are [F, roll, pitch, yaw] — the repo's naming order (MotorMixer.mix() takes throttle,
## roll, pitch, yaw), deliberately NOT the doc's [F, tau_x, tau_y, tau_z], so that nobody reading
## a row index has to translate between an axis name and an axis letter to know what they have.
## Use the ROW_* constants rather than bare integers.
##
## The actuator vector is THRUST PER MOTOR IN NEWTONS, not a normalised throttle command. That is
## the only choice that makes the matrix physical: the row entries then carry real units (row F is
## dimensionless, roll and pitch are metres, yaw is metres of equivalent moment arm), so
## axis_authority() is a number in N*m per N of thrust rather than a number per arbitrary unit.
##
## `drag` on a motor is Q/T — reaction torque per newton of thrust, i.e. k_q/k_t for its prop. It
## is a RATIO and not k_q, because both k_q and k_t scale with omega^2, so their ratio is the one
## number that survives the linearisation this matrix is. It is ~0.01 m for a 5" prop, which is why
## yaw is always the weak axis: two orders of magnitude below an arm length.

const ROW_THRUST := 0
const ROW_ROLL := 1
const ROW_PITCH := 2
const ROW_YAW := 3
const ROW_NAMES := ["thrust", "roll", "pitch", "yaw"]

## Singular values below this fraction of the largest are treated as zero, in rank() and when
## inverting inside the pseudo-inverse. Relative, not absolute, because the rows are in different
## units: an absolute threshold would call a perfectly good 3" quad's yaw row "zero" simply because
## a moment arm of 0.01 m is a small number.
const SINGULAR_TOL := 1.0e-9


## One motor. Plan position relative to the CG in metres (x = right, z = aft; y is irrelevant,
## thrust is along +Y so the vertical offset contributes nothing to any of the four rows), spin
## sign s = +/-1 as in MotorLayout.SPIN, and drag = Q/T in metres.
static func motor(x: float, z: float, spin: float, drag: float) -> Dictionary:
	return {"x": x, "z": z, "spin": spin, "drag": drag}


## Build B: 4 rows, each an Array of N floats. See the header for why these signs.
static func build_matrix(motors: Array) -> Array:
	var n := motors.size()
	var b := []
	for r in 4:
		var row := []
		row.resize(n)
		b.append(row)
	for i in n:
		var m: Dictionary = motors[i]
		b[ROW_THRUST][i] = 1.0
		b[ROW_ROLL][i] = -float(m["x"])
		b[ROW_PITCH][i] = -float(m["z"])
		b[ROW_YAW][i] = float(m["spin"]) * float(m["drag"])
	return b


## The mixer: the Moore-Penrose pseudo-inverse B+ , as N rows of 4. Multiply a desired wrench
## [F, roll, pitch, yaw] by this to get per-motor thrusts in newtons.
##
## Computed as B+ = B^T * (B B^T)+ . That is an exact identity for ANY B, not an approximation and
## not a full-rank shortcut — which matters, because the layouts this class exists to catch are
## precisely the rank-deficient ones. The alternative that suggests itself, (B^T B + lambda I)^-1
## B^T, is an N x N solve of a matrix that is singular by construction whenever N > 4, and the
## regularisation that rescues it also silently biases the answer for every well-conditioned
## layout. Here B B^T is 4 x 4, symmetric, positive semi-definite, and small enough to
## eigen-decompose exactly with cyclic Jacobi; the pseudo-inverse then just drops the eigenvalues
## that are zero rather than fudging them.
##
## For a rank-deficient layout this still returns something. It returns the least-squares,
## minimum-norm answer — the motor commands that come CLOSEST to the demanded wrench. That is the
## right output and it is also a trap: it is never an authorisation to fly. controllable() is.
static func mixer(motors: Array) -> Array:
	var b := build_matrix(motors)
	var n := motors.size()
	var gram := _gram(b)                       # B B^T, 4x4
	var eig := _jacobi_eigen(gram)
	var vectors: Array = eig["vectors"]        # columns are eigenvectors
	var values: Array = eig["values"]

	var max_ev := 0.0
	for v in values:
		max_ev = maxf(max_ev, absf(v))
	# Eigenvalues of B B^T are the SQUARED singular values of B, so the tolerance is squared too.
	var cutoff: float = max_ev * SINGULAR_TOL * SINGULAR_TOL

	# (B B^T)+ = V * diag(1/lambda_k for lambda_k > cutoff, else 0) * V^T
	var gram_pinv := []
	for r in 4:
		var row := []
		row.resize(4)
		row.fill(0.0)
		gram_pinv.append(row)
	for k in 4:
		var lam: float = values[k]
		if lam <= cutoff:
			continue
		var inv := 1.0 / lam
		for r in 4:
			for c in 4:
				gram_pinv[r][c] += inv * float(vectors[r][k]) * float(vectors[c][k])

	# B+ = B^T * gram_pinv  -> N x 4
	var out := []
	for i in n:
		var row := []
		row.resize(4)
		for c in 4:
			var acc := 0.0
			for r in 4:
				acc += float(b[r][i]) * float(gram_pinv[r][c])
			row[c] = acc
		out.append(row)
	return out


## How many of the four axes the layout can actually command, independently.
##
## rank(B) = rank(B B^T), which is why this can be answered from the same 4x4 eigen-decomposition
## the mixer already needs, with no separate elimination pass whose pivoting would be a second
## place for a tolerance to disagree with itself.
static func rank(b: Array) -> int:
	var eig := _jacobi_eigen(_gram(b))
	var values: Array = eig["values"]
	var max_ev := 0.0
	for v in values:
		max_ev = maxf(max_ev, absf(v))
	if max_ev <= 0.0:
		return 0
	var cutoff: float = max_ev * SINGULAR_TOL * SINGULAR_TOL
	var r := 0
	for v in values:
		if v > cutoff:
			r += 1
	return r


## Can this thing be flown? Only if all four axes are independently commandable.
##
## Three motors fails here (a 4 x 3 matrix cannot have rank 4 — a tricopter buys its fourth axis
## with a servo, which is a different aircraft and not one Lothal models). Four motors in a line
## fails too: with every z equal there is no fore-aft lever, so the pitch row is a multiple of the
## thrust row and pitching means changing collective. Returns the reason as well as the verdict,
## because "not controllable" with no explanation is the message a builder cannot act on.
static func controllable(b: Array) -> Dictionary:
	var n: int = (b[0] as Array).size()
	var r := rank(b)
	if r >= 4:
		return {"ok": true, "rank": r, "reason": ""}
	var reason := "layout commands only %d of 4 axes (rank %d)" % [r, r]
	if n < 4:
		reason = "%d motors cannot command 4 axes: at least 4 independent thrusts are needed" % n
	else:
		var dead := []
		var auth := axis_authority(b)
		for row in [ROW_ROLL, ROW_PITCH, ROW_YAW]:
			if float(auth[ROW_NAMES[row]]) <= 0.0:
				dead.append(ROW_NAMES[row])
		if not dead.is_empty():
			reason = "%s authority is zero — motors have no lever arm for %s" % [", ".join(dead), ", ".join(dead)]
		else:
			reason += ": two axes are driven by the same motor pattern (motors are collinear or duplicated)"
	return {"ok": false, "rank": r, "reason": reason}


## Per-axis authority: the Euclidean norm of each row, in real units.
##
## Row norm and not row sum, because the sum cancels: a symmetric X has motors at +a and -a, so
## sum(x) is zero on a frame with plenty of roll authority. The norm is the gain from a unit-norm
## thrust distribution to that axis — thrust in motor-newtons, roll and pitch in N*m per N (i.e.
## metres of effective arm), yaw likewise. Comparable ACROSS axes only in the sense that the units
## of the last three genuinely match; comparing roll to thrust is comparing metres to nothing.
static func axis_authority(b: Array) -> Dictionary:
	var out := {}
	for r in 4:
		var acc := 0.0
		for v in (b[r] as Array):
			acc += float(v) * float(v)
		out[ROW_NAMES[r]] = sqrt(acc)
	return out


## kappa(B) = sigma_max / sigma_min. A layout in the hundreds is one where a small command on the
## weak axis eats most of the throttle headroom. WARN, NEVER BLOCK (labs-and-sim.md §2).
##
## Read it knowing what it is not: because the rows carry different units, kappa is not a pure
## number about the geometry — rescaling the aircraft from metres to millimetres changes it. It is
## still the right ruler for comparing two layouts of the SAME aircraft, which is the only
## comparison anyone makes with it. INF for an uncontrollable layout, which is the honest answer.
static func condition_number(b: Array) -> float:
	var eig := _jacobi_eigen(_gram(b))
	var values: Array = eig["values"]
	var hi := 0.0
	var lo := INF
	for v in values:
		var s: float = sqrt(maxf(v, 0.0))
		hi = maxf(hi, s)
		lo = minf(lo, s)
	if lo <= hi * SINGULAR_TOL:
		return INF
	return hi / lo


## B * thrusts -> the wrench [F, roll, pitch, yaw]. Here so tests and callers never hand-roll it.
static func apply(b: Array, thrusts: Array) -> Array:
	var out := []
	for r in 4:
		var acc := 0.0
		var row: Array = b[r]
		for i in row.size():
			acc += float(row[i]) * float(thrusts[i])
		out.append(acc)
	return out


## B+ * wrench -> per-motor thrusts. `pinv` is what mixer() returned (N rows of 4).
static func apply_mixer(pinv: Array, wrench: Array) -> Array:
	var out := []
	for i in pinv.size():
		var acc := 0.0
		var row: Array = pinv[i]
		for c in 4:
			acc += float(row[c]) * float(wrench[c])
		out.append(acc)
	return out


# --- internals -------------------------------------------------------------------------------

static func _gram(b: Array) -> Array:
	var n: int = (b[0] as Array).size()
	var g := []
	for r in 4:
		var row := []
		row.resize(4)
		row.fill(0.0)
		g.append(row)
	for r in 4:
		for c in 4:
			var acc := 0.0
			for i in n:
				acc += float(b[r][i]) * float(b[c][i])
			g[r][c] = acc
	return g


## Cyclic Jacobi eigen-decomposition of a 4x4 symmetric matrix. Returns eigenvalues and the
## orthonormal eigenvector matrix (eigenvector k is column k).
##
## Jacobi rather than anything cleverer for one reason: it is unconditionally accurate on small
## symmetric matrices INCLUDING the singular ones, which are the cases this whole class is about.
## A characteristic-polynomial root-find would be shorter and would lose most of its digits exactly
## where a near-zero eigenvalue decides whether the aircraft is controllable.
static func _jacobi_eigen(a_in: Array) -> Dictionary:
	var a := []
	for r in 4:
		var row := []
		row.resize(4)
		for c in 4:
			row[c] = float(a_in[r][c])
		a.append(row)
	var v := []
	for r in 4:
		var row := []
		row.resize(4)
		row.fill(0.0)
		row[r] = 1.0
		v.append(row)

	for sweep in 100:
		var off := 0.0
		for r in 4:
			for c in range(r + 1, 4):
				off += float(a[r][c]) * float(a[r][c])
		if off <= 1.0e-30:
			break
		for p in 3:
			for q in range(p + 1, 4):
				var apq: float = a[p][q]
				if absf(apq) <= 1.0e-300:
					continue
				var theta: float = (float(a[q][q]) - float(a[p][p])) / (2.0 * apq)
				var t: float = (1.0 if theta >= 0.0 else -1.0) / (absf(theta) + sqrt(theta * theta + 1.0))
				var c_ := 1.0 / sqrt(t * t + 1.0)
				var s := t * c_
				for k in 4:
					var akp: float = a[k][p]
					var akq: float = a[k][q]
					a[k][p] = c_ * akp - s * akq
					a[k][q] = s * akp + c_ * akq
				for k in 4:
					var apk: float = a[p][k]
					var aqk: float = a[q][k]
					a[p][k] = c_ * apk - s * aqk
					a[q][k] = s * apk + c_ * aqk
				for k in 4:
					var vkp: float = v[k][p]
					var vkq: float = v[k][q]
					v[k][p] = c_ * vkp - s * vkq
					v[k][q] = s * vkp + c_ * vkq

	var values := []
	for r in 4:
		values.append(float(a[r][r]))
	return {"values": values, "vectors": v}

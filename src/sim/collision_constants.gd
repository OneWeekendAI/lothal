class_name CollisionConstants
extends RefCounted
## R1.1: every collision threshold in ONE place. EACH VALUE BELOW IS AN ESTIMATE, not a measurement:
## chosen to be plausible for a 5-inch-class FPV quad, to be replaced when a real drop test exists.
## Nothing else in the collision code carries a literal of its own.

## ESTIMATE. Below this normal speed a hit is a bounce: restitution and friction impulses only, no damage.
const BOUNCE_SPEED_MPS := 2.0
## ESTIMATE. At or above this normal speed the aircraft is destroyed (crash and respawn). Between the two
## thresholds a hit bounces without restitution and damages the prop/arm that touched.
const CRASH_SPEED_MPS := 8.0
## ESTIMATE. Normal speeds under this are resting contact (gravity each tick), not an impact: no bounce, no damage.
const REST_SPEED_MPS := 0.05
## ESTIMATE. Fraction of normal speed returned on a soft hit (carbon/plastic frame on dirt or foam is low).
const RESTITUTION := 0.3
## ESTIMATE. Coulomb friction coefficient of frame/prop plastic on ground or obstacle.
const FRICTION := 0.5
## ESTIMATE. Thrust fraction a prop loses to one hit at just under the crash speed; linear over the damage band.
const MAX_DAMAGE_PER_HIT := 0.6
## ESTIMATE. Share of a hit's damage passed to every prop when the central body (not an arm or prop) takes it.
const BODY_HIT_DAMAGE_SHARE := 0.25
## ESTIMATE. Radius of the central body contact sphere. Kept above GateCourse.GROUND_CLEARANCE_M so a
## resting aircraft never trips the altitude backstop in Main._check_crash.
const BODY_RADIUS_M := 0.03
## ESTIMATE. Radius of the arm-hub and prop-tip contact spheres.
const POINT_RADIUS_M := 0.01
## Gate ring tube radius, from the drawn ring (GateCourse.RING_THICKNESS_M is the tube diameter).
const GATE_TUBE_RADIUS_M := GateCourse.RING_THICKNESS_M * 0.5

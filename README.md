# Lothal

Build an FPV drone from real parts. Fly it. Feel the difference.

![Lothal: the build panel's live stats, and a run at the first gate](preview.gif)

## What it does

Lothal is an open-source drone design workbench and flight simulator. You assemble a
quadcopter from a catalog of real components — frames, motors, propellers, batteries —
and every choice changes the physics. Swap a 4S pack for 6S and the thrust-to-weight,
hover throttle, and flight time all recompute; then you fly it and feel the difference.

Nothing is a canned asset. Prop rotation is integrated from actual RPM, voltage sag is
computed from the pack's internal resistance and the current the motors are really
drawing, and the flight model runs at 1 kHz off measured manufacturer thrust data. The
simulation is the single source of truth: the HUD, the airframe you see, and the way it
flies are three views of one set of numbers.

Then fly the eight-gate circuit and see whether your build is actually faster.

## Run it

Requires [Godot 4.7+](https://godotengine.org/download).

```bash
git clone https://github.com/OneWeekendAI/lothal.git
cd lothal
godot project.godot
```

Press <kbd>F5</kbd> to run. A gamepad is strongly recommended.

### Controls

|                  | Gamepad             | Keyboard              |
| ---------------- | ------------------- | --------------------- |
| Roll / pitch     | Right stick         | Arrow keys            |
| Yaw              | Left stick ←→       | <kbd>A</kbd> <kbd>D</kbd> |
| Throttle         | Left stick ↑↓       | <kbd>W</kbd> <kbd>S</kbd> |
| Angle ↔ acro     | <kbd>A</kbd> button | <kbd>Space</kbd>      |
| Hide build panel | —                   | <kbd>Tab</kbd>        |

Keyboard input is digital, so it is a fallback for testing rather than a way to fly well.

Fly through the lit gate. Gates must be taken in order; the eighth completes a lap, and
your best time is kept in `user://best_lap.json`. Hitting the ground puts you back at the
last gate you cleared and voids the lap in progress.

## Flight model

- Custom integrator at 1 kHz (8 substeps per 120 Hz frame), not Godot's rigid-body solver
- Inertia tensor assembled per build from part masses and positions via the parallel axis theorem
- Thrust and torque from `T = k_t · n²`, `Q = k_q · n²`, with `k_t` fit from the
  manufacturer thrust table the motor's headline figure was measured on, then rescaled to
  the prop actually fitted
- Pack voltage sags under load and sets the RPM ceiling, so a tired pack flies differently
- Motors are current-limited, so an oversized prop runs out of amps before it runs out of volts

Run the test suite headless — 67 checks, including the hover-throttle oracle the whole
model is calibrated against:

```bash
godot --headless --script res://tests/run_tests.gd
```

## Adding parts

The catalog is plain JSON in `data/parts/`, one file per category. Adding a real part is a
small, reviewable PR — that is exactly why it is JSON and not a binary format.

Every part has:

| Field      | Meaning                                                  |
| ---------- | -------------------------------------------------------- |
| `part_id`  | Unique key, referenced by other files. `motor_2207_1960kv` |
| `name`     | What shows in the dropdown. `2207 1960KV`                |
| `category` | `frame`, `motor`, `propeller`, or `battery`              |
| `mass_g`   | Real mass in grams — feeds the mass properties directly  |
| `source`   | Where the numbers came from. Required; see below         |

Then the per-category `specs`:

**`frames.json`** — `arm_mm` (centre to motor, and the sleeper spec: roll inertia goes as
arm², so it dominates how the build feels), `max_prop_inches`, `motor_mount` (e.g. `16x16`).

**`motors.json`** — `kv`, `stator_diameter_mm`, `stator_height_mm`, `max_thrust_g`,
`max_amps`, `poles`. Plus a `mount_pattern` and a `thrust_test` block naming the
`prop_id` and `voltage_v` the headline thrust figure was measured with. That block is not
optional: a thrust number without the prop and pack behind it cannot be turned into a
coefficient, and a guessed coefficient is the one thing this project will not ship.

**`propellers.json`** — `diameter_inches`, `pitch_inches`, `blades`. Thrust goes as
diameter⁴ and shaft torque as diameter⁵, so diameter dominates everything else here.

**`batteries.json`** — `cells`, `nominal_v`, `mah`, `internal_r_ohm`. Internal resistance
is what makes a pack feel strong or tired; it is worth finding a real figure rather than
copying a neighbouring entry.

Two rules for a part PR:

1. **Every spec must come from a real product**, and `source` must say where — a
   manufacturer thrust table, a spec sheet, a bench test. Plausible-looking invented
   numbers are worse than a missing part, because they quietly corrupt the comparison
   between two builds, which is the entire point of the tool.
2. **If a field does not feed the physics, it does not belong in the file yet.** Colour,
   price, and vendor links are not specs.

Incompatible combinations are allowed on purpose. Putting 7" props on a 3" frame warns and
then shows you what happens, because that answer teaches more than a greyed-out dropdown.

## Not in this release

Procedural audio, Betaflight SITL, drag-and-drop assembly, damage modelling, propwash and
ground effect. The observables the flight model publishes (per-motor RPM, live pack
voltage, blade-pass frequency) are what those consumers would be built on, and the
architecture is arranged so that adding one touches no physics code.

## Tech stack

- **Godot 4.7** (GDScript) — engine, UI, rendering
- **Custom 1 kHz flight dynamics** — own integrator, not the rigid-body solver
- **Jolt** — collision queries only

## License

MIT

# Lothal

Build an FPV drone from real parts. Fly it. Feel the difference.

## What it does

Lothal is an open-source drone design workbench and flight simulator. You assemble a
quadcopter from a catalog of real components — frames, motors, propellers, batteries —
and every choice changes the physics. Swap a 4S pack for 6S and the thrust-to-weight,
hover throttle, and flight time all recompute; then you fly it and feel the difference.

Nothing is a canned asset. Motor sound is synthesized from actual RPM, prop rotation is
integrated from actual RPM, and the flight model runs at 1 kHz off measured
manufacturer thrust data. The simulation is the single source of truth.

## Run locally

Requires [Godot 4.4+](https://godotengine.org/download).

```bash
git clone https://github.com/OneWeekendAI/lothal.git
cd lothal
godot project.godot
```

Press <kbd>F5</kbd> to run. A gamepad is strongly recommended.

Run the physics test suite headless:

```bash
godot --headless --script res://tests/run_tests.gd
```

## Adding parts

The component catalog is plain JSON in `data/parts/`. Every part is a real product with
specs taken from manufacturer thrust tables. Adding one is a small PR — see the schema
comment at the top of each file.

## Tech stack

- **Godot 4.4** (GDScript) — engine, UI, rendering
- **Custom 1 kHz flight dynamics** — own integrator, not the rigid-body solver
- **Jolt** — collision queries only
- **Procedural audio** — motor and blade-pass tones synthesized from live RPM

## License

MIT

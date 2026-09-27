# Lothal

Build an FPV drone from real parts. Fly it. Feel the difference.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink.svg)](https://github.com/sponsors/datasciritwik)

![Lothal: the garage turning the build, the Motors and Battery pages, then a run through the first gate](preview.gif)

Lothal is a drone design workbench and flight simulator. You assemble a quadcopter from a
catalog of real components, and every choice changes the physics. Swap a 4S pack for 6S and
the thrust-to-weight, hover throttle and flight time all recompute. Then you fly it and feel
the difference.

## What it does

- **Lab (the garage):** pick a frame, motors, props, battery and electronics from a catalog of
  real parts. The airframe is drawn from their real dimensions, so it doubles as a fit check:
  put 7" props on a 3" frame and you see them collide.
- **Sim (the field):** fly exactly what you built through an eight-gate circuit. Your best lap
  is saved.
- **Real physics:** a custom 1 kHz flight model driven by measured manufacturer thrust data.
  Packs sag under load, motors are current-limited, and inertia comes from where each part sits.
- **Open parts catalog:** plain JSON in `data/parts/`, every number with a source.

A gamepad is strongly recommended. The keyboard works (arrows, W/S/A/D, Space for
angle/acro, Tab to hide the build panel) but only as a fallback.

## Download

Get the latest build for **Windows, macOS and Linux** from
[Releases](https://github.com/OneWeekendAI/lothal/releases).

**First launch:** builds are not yet code-signed, so your OS will warn you once.

- **Windows:** on the SmartScreen prompt, click **More info**, then **Run anyway**.
- **macOS:** open **System Settings → Privacy & Security** and click **Open Anyway**.

## Build from source

You need [Godot 4.7+](https://godotengine.org/download) and a
[Rust toolchain](https://rustup.rs).

```bash
git clone https://github.com/OneWeekendAI/lothal.git
cd lothal/rust
cargo build --release
cd ..
mkdir -p build
cp rust/target/release/liblothal_core.dylib build/   # macOS
# cp rust/target/release/liblothal_core.so build/    # Linux
# copy rust\target\release\lothal_core.dll build\    # Windows
godot project.godot
```

The Rust core holds the physics, so the library must be in `build/` before Godot starts.
Press <kbd>F5</kbd> in the editor to run.

Run the tests headless (every check must pass):

```bash
tools/run_tests_safe.sh      # macOS / Linux
tools/run_tests_safe.ps1     # Windows
```

## Contributing

Bug reports, fixes and new real-world parts are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md). Lothal is a one-person project, so replies may be slow.

## Support the project

Lothal is free and always will be. If it is useful to you, you can
[sponsor it on GitHub](https://github.com/sponsors/datasciritwik). Sponsorship pays for
development time and for the planned hardware that will connect to Lothal.

Sponsors are listed here:

<!-- sponsors -->

Thank you.

## Code size

Counted with `cloc --vcs=git` (tracked files only, so build output is excluded):

<!-- CLOC-START -->
```
github.com/AlDanial/cloc v 2.10
-------------------------------------------------------------------------------
Language                     files          blank        comment           code
-------------------------------------------------------------------------------
GDScript                       497          19858          46787          85333
Text                             1              0              0           6000
JSON                            23              0              0           3697
Rust                            13            263           1130           2284
Python                          10            654           1610           2228
Bourne Shell                     7            109            366            626
Markdown                         3             82              3            234
YAML                             3             32             78            192
Godot Scene                      4             21             33             64
JavaScript                       1             14             47             57
SVG                              1              0              5             27
TOML                             2              6             26             21
PowerShell                       1              6             33             20
-------------------------------------------------------------------------------
SUM:                           566          21045          50118         100783
-------------------------------------------------------------------------------
```
<!-- CLOC-END -->

## License

Lothal is licensed under **GPL-3.0-or-later**. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
The name "Lothal" and its logo are not covered by the GPL.

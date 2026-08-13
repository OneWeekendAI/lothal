# Microsoft Store listing — Lothal

Copy for the Partner Center **Store listings** page, plus the submission answers that are easy to
get wrong. Paste each block into the field named in its heading. Character limits are Microsoft's
and are current as of August 2026; the counts in brackets are what the text below actually uses.

Product: Lothal · Store ID `9N4G4KMTWHLV` · https://apps.microsoft.com/detail/9N4G4KMTWHLV

---

## Product name

```
Lothal
```

## Short description  (max 500) [318]

```
Design an FPV drone from real parts, then fly it. Lothal simulates the aircraft you actually
built — your motors, your props, your battery, your frame — using a physical model rather than
a feel-good approximation. Change a prop and the flight changes. Build in the Lab, fly in the
Sim, and find out before you spend the money.
```

## Description  (max 10,000) [~2,050]

```
Lothal is a workbench for people who build their own FPV quads.

Pick a frame, motors, propellers, an ESC, a flight controller and a battery. Lothal checks that
the parts fit each other and tells you when they don't — a prop that fouls the frame, a stack
that won't mount, a pack that won't sit in the bay. Then it works out what you have actually
built: thrust, hover throttle, thrust-to-weight, current draw, and how long it will stay in the
air.

Then you fly it.

THE POINT: THE SIMULATOR FLIES YOUR BUILD
Most sims give you a menu of preset aircraft. Lothal flies the one on your bench. The powertrain
model is driven by real component figures — motor Kv and Kt, propeller diameter, pitch and blade
count, pack chemistry, cell count and capacity, ESC limits — so the handling in the air is a
consequence of the parts you chose, not a slider someone tuned to feel nice. Fit a heavier pack
and it gets sluggish and flies longer. Move to a higher-pitch prop and top speed rises while
punch-out suffers. Overpropped builds sag and get hot, exactly as they do outdoors.

WHAT YOU CAN DO
· Build from a parts library, or enter your own motors, props, ESCs, flight controllers, frames
  and batteries by their published figures
· See mass, balance and fit checked as you build, with warnings that name the specific problem
· Read a full performance summary before you buy anything: static thrust, hover throttle,
  thrust-to-weight, estimated flight time
· Fly in a 3D simulator with rate-mode controls and a physical model of your own aircraft
· Tune the flight controller — PID rates, filters — and feel the difference immediately
· Fly gate courses, with timing, to practise lines rather than just hover
· Record flights and read the log back: throttle, current, RPM, attitude over time
· Use any USB gamepad or radio transmitter your computer recognises

WHO IT IS FOR
People who are about to spend real money on a build and want to know whether it flies before it
arrives. People with a shelf of parts wondering what combination to try next. People learning
what pitch, Kv and cell count actually do to an aircraft, without crashing one to find out.

WHAT IT IS NOT
Lothal is not a racing game. There is no career mode, no unlocks and no cosmetics. It is a design
tool with a simulator attached, and the simulator exists to answer questions about the design.

Accuracy note: Lothal models the physics of a build from published component figures. It is a
tool for informed judgement, not a guarantee — real aircraft vary with build quality, wind,
temperature and the honesty of a manufacturer's data sheet.

Lothal runs fully offline. It contains no analytics, no telemetry and no advertising, and it makes
no network requests while you use it.
```

## What's new in this version

```
First Microsoft Store release. Lothal 0.2.0 brings the Lab and Sim together: build an aircraft
from real components, check fit and mass, then fly it with a powertrain model driven by the parts
you chose.
```

## Search terms  (max 7, 30 chars each, not shown to customers)

```
fpv simulator
drone builder
quadcopter design
drone flight simulator
fpv freestyle practice
propeller thrust calculator
drone build planner
```

## Short title / additional fields

- **Short title:** `Lothal`
- **Sort title:** leave blank
- **Voice title:** leave blank
- **Copyright and trademark info:** `© 2026 Meetdev. All rights reserved.`
- **Additional license terms:** leave blank unless you want the EULA in NOTICE surfaced here
- **Developed by:** `Meetdev`

---

## Contact and support fields

- **Privacy policy URL:** `https://lothal.meetdev.in/privacy` (live, verified 13 Aug 2026)
- **Website:** `https://lothal.meetdev.in`
- **Support contact info:** `officialritwik098@gmail.com`
- **Support URL:** leave blank — the email above is the whole support channel, and a URL that
  points at a page with no support content on it is worse than none.

## System requirements

Declare only what is true; every requirement narrows who is offered the app.

- **Minimum OS:** Windows 10 version 1809 (10.0.17763.0) — matches the manifest's TargetDeviceFamily
- **Architecture:** x64 only. The Rust core is built for `x86_64-pc-windows-msvc` and there is no
  ARM64 build, so ARM machines will run it under emulation or not be offered it.
- **Recommended hardware:** any GPU capable of Godot 4 forward rendering; the Sim is a 3D scene.
- **Optional:** a USB gamepad or an RC transmitter in joystick mode. Not required — the Lab and
  every analysis screen work with keyboard and mouse.

## Category  — this one is not cosmetic

**Choose: `Developer tools` → `Design tools`.**

The realistic alternatives are `Multimedia design` or a `Games` category, and the games route is
the one to avoid. Microsoft Store policy 10.8.1 requires **games** that sell digital goods to use
Microsoft's in-app commerce; non-game apps may use their own. Lothal sells activation keys from
its own website, so a games category invites a rejection and a revenue share for no benefit. The
description above is written to read as a design tool for the same reason — a listing that talks
about racing and freestyle "gameplay" undercuts the categorisation it sits next to.

---

## Age rating questionnaire — draft answers

Answer these yourself; this is a prepared draft to check rather than compose. The questionnaire is
a binding declaration, so read each question as written in Partner Center before selecting.

| Question | Answer | Why |
| --- | --- | --- |
| Is this app a game? | **No** | It is a design tool with a simulator for evaluating designs. |
| Does it contain violence of any kind? | **No** | Aircraft crash into terrain and gates. No characters, no combat, no depiction of injury. |
| Sexual content, nudity, profanity? | **No** | None. |
| Drugs, alcohol, tobacco, gambling? | **No** | None. |
| Does it collect or transmit personal information? | **No** — for the app | The Store build makes no network requests. Sign-in happens on the website in the user's browser, before installation. Answer per the app's own behaviour. |
| Does it allow users to interact or share content? | **No** | No multiplayer, no chat, no user-to-user sharing. |
| Does it access the internet? | **No** | Confirmed: `HTTPRequest` appears only in the update notice, which is compiled out of Store builds, and `internetClient` is not declared in the manifest. |
| Does it share the user's location? | **No** | None. |
| Miscellaneous / user-generated content | **No** | Builds and courses are local files, not shared through the app. |

Expected outcome: a rating in the "everyone / 3+" band in every region.

---

## Additional Testing Information — the field most likely to sink the submission

Certification testers hit the activation gate on first launch and will fail the app if they cannot
get past it. Fill this in before submitting. Replace the bracketed parts.

```
ACTIVATION IS REQUIRED ON FIRST LAUNCH.

Lothal asks for an activation key the first time it runs. Testers should not need to create an
account — please use the key below, which is a normal permanent licence issued for review.

  Activation key: [PASTE A TEST LICENCE KEY HERE]

How to use it:
  1. Launch Lothal.
  2. On the activation screen, paste the key into the text field.
  3. Press Activate. The app opens immediately and stays activated on subsequent launches.

Notes for the reviewer:
  - The key is verified offline, on the machine, against a public key inside the application.
    The app makes no network requests at any point, including during activation, so no test
    account, network access or credentials are required.
  - The "Get a key" button on that screen opens our website in the system browser. Testers do not
    need to use it, and it is not part of the flow above.
  - A gamepad or transmitter improves the simulator but is not required; the Lab, the build
    checks and the performance readouts are all reachable with keyboard and mouse.
```

Getting the key: sign in at lothal.meetdev.in and issue one the ordinary way. There is no local
issuing script — the activation private key lives in Google Secret Manager and is used only by the
Supabase `issue` function, and `release/keygen.sh` is a different key entirely (it generates the
update-signing pair, and refuses to run twice).

---

## Pricing and availability

- **Base price: Free.** Decided — Lothal is free for everyone for now. Nothing is sold in the app
  and nothing is sold through the Store, which is what keeps policy 10.8.1 irrelevant regardless
  of how the category question is read. Activation stays an email gate rather than a purchase.
- **In-app purchases:** none. Declare none.
- **Markets:** all markets. There is no export, content or licensing reason to narrow it.
- **Free trial:** not applicable while the app is free.
- **Visibility.** Worth considering for the first submission: "Hidden in the Store, available via
  direct link". Certification still runs and the link still works, but the listing goes public
  when you decide rather than the moment Microsoft approves it. Changeable later either way.

Note for whenever Lothal stops being free: switching to paid activation keys sold on
lothal.meetdev.in is a listing change, not a repackaging — but it makes the category question in
the section above load-bearing, so re-read it then.

---

## Screenshots — required, 1–9, minimum 1366×768

Captured and prepared in `~/Downloads/lothalss/store/`, 3416×1910 each, numbered in upload order.
The macOS window chrome was cropped off every one — a Windows Store listing showing macOS traffic
lights reads as the wrong platform, and the app's own UI underneath is platform-neutral.

| # | File | Shows |
| --- | --- | --- |
| 1 | `01-sim-flying-a-gate-course` | Sim: the build in the air, gates, HUD |
| 2 | `02-lab-build-and-performance` | Lab: frame picker + full performance readout |
| 3 | `03-frame-angular-acceleration` | Frame: agility from real inertia and torque |
| 4 | `04-pack-sag-under-load` | Pack: voltage sag under a full-throttle punch |
| 5 | `05-field-course-editor` | Field: gate course editor with lap geometry |
| 6 | `06-flight-controller-detail` | FC: gyro noise and the D ceiling it costs |
| 7 | `07-electronics-and-mass-budget` | Electronics: every gram accounted for |
| 8 | `08-pack-charger` | Pack: the charger and the shelf |
| 9 | `09-custom-motor-entry` | Custom parts: enter a motor from its data sheet |

Two things to decide before uploading:

- **Shot 1 carries the caption "FPV (inset) — 90° placeholder, no tilt".** The word *placeholder*
  sits in the first image a customer sees. Either retake it with the inset closed, or accept it.
- **Shot 9 shows custom parts named "5" Freestyle Ritwik" and "Beast 2207",** and the dialog it
  features is empty with every field at zero. It is the weakest of the nine and the only one
  carrying a personal name. Dropping it costs nothing — eight is a full listing.

Store logo for the listing wants 2160×2160; the repository icon is 1024×1024, so it should be
re-rendered from `icon.svg` rather than upscaled.

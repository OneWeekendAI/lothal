# Frame tap test — what to do, start to finish

**Time: about 40 minutes.** You need a quad, a screwdriver, a phone, calipers, a kitchen scale
and a vise or a workbench clamp. No prior knowledge of the analysis is assumed — do exactly
what is below and send back the files.

This measures two numbers the simulator currently guesses: the frequency a frame arm rings at,
and how fast that ringing dies away. Both come out of the same recording. You hit the arm and
listen to it, which is why nothing has to be flown.

**Assume one attempt.** Read the whole thing once before starting, because two of the steps
(weighing, and measuring the arm) are impossible to go back and do once the quad is reassembled
and out of the door.

---

## 0. Before you touch anything: write down the build

Make a text file called `build.txt` and put these in it. If a number is missing, the analysis
cannot run — these are not optional and they cannot be looked up afterwards.

| What | How | Example |
|---|---|---|
| Frame make and model | off the box or the invoice | `iFlight Nazgul5 V3` |
| **Arm length**, mm | calipers, from the **face of the centre hub** to the **centre of the motor shaft**. Measure it, don't trust the spec sheet — the published figure's convention is not stated anywhere. | `110.4` |
| Arm width and thickness, mm | calipers, mid-arm | `18.0 x 4.0` |
| Motor | model number | `2207 1800KV` |
| **Tip mass with prop**, g | kitchen scale: one motor, its four mounting screws, and one prop, all together | `36.8` |
| **Prop mass**, g | kitchen scale: one prop on its own | `4.6` |
| Prop | size and blade count | `5x4.3x3` |
| Anything else on the arms | TPU, cable ties, LED strips, ND holders — list it, and leave it on | `TPU antenna mount on rear arms` |

Two of these are the whole reason this test is worth doing. LTHL-18 died because the arm length
and the tip mass of every real log we could find were unknown, and inventing them would have
poisoned the result. You are holding the frame, so both are just a measurement.

---

## 1. Set the quad up: clamped, assembled, motors on

**Clamp the centre plate stack in a vise, so all four arms hang free in the air.**

- Clamp on the **centre plates only** — the flat middle section where the stack lives. Not on
  an arm.
- Put something soft (a rag, a sheet of rubber) between the vise jaws and the plates. Nip it up
  firm. Not crushing tight.
- **Motors stay bolted on**, at normal torque, wires routed as they normally are. A bare arm
  rings at a completely different frequency — it is a different measurement, not a rougher
  version of this one.
- Arm bolts at normal flying torque. Don't retorque them specially, and don't loosen anything.

If you have no vise: clamp the plates to the edge of a solid workbench with two G-clamps. **Do
not hold it in your hand.** A hand is neither clamped nor free, it damps the ringing directly
at the root, and damping is one of the two things being measured.

---

## 2. Recording — do BOTH, in this order

### Route A: phone microphone (5 minutes, do this first)

Voice-memo app, quiet room, phone about 30 cm from the arm you're hitting, propped up so you
don't have to hold it. Turn off anything with a fan. Export as **WAV** if the app offers it; if
it only does m4a, send that and say so.

### Route B: the quad's own gyro (preferred, worth the extra 15 minutes)

This measures the vibration **at the flight controller**, through the same soft mounts the
simulator models, and the room disappears entirely. It is the better data. It needs Betaflight
settings changed, which you will change back at the end.

**Props OFF for this route.** The quad has to be armed to log, so no props go anywhere near it.
Route A covers the props-on case.

In the Betaflight configurator CLI, paste this and hit enter:

```
set gyro_lpf1_type = OFF
set gyro_lpf1_static_hz = 0
set gyro_lpf2_type = OFF
set gyro_lpf2_static_hz = 0
set dyn_notch_count = 0
set gyro_notch1_hz = 0
set gyro_notch2_hz = 0
set blackbox_sample_rate = 1/1
set blackbox_device = SPIFLASH
save
```

Those first six lines are the point of the whole route. **The gyro's default 150 Hz lowpass
sits on top of the frequency we're hunting** — on the reference build the mode is above it, so
with the filters on the flight controller literally cannot see most of what we're trying to
measure. The analyser refuses a log whose gyro turns out to have been filtered, and it decides
that from the data rather than from the header, so there is no talking it round.

Then, with **props off** and the battery in: arm the quad, **do not touch the throttle**, do the
taps in section 3, disarm, and download the blackbox log. Decode it to CSV with
`blackbox_decode`.

**Put every setting back afterwards.** Do not fly it like this — a quad with no gyro filtering
will fly badly and can burn motors.

---

## 3. The taps

One tap = one strike, then let it ring out and go quiet for a good two seconds before the next.
Never a double-tap or a bounce.

**How to hit it:** with the **plastic handle** of a screwdriver, on the arm, **about 15 mm
inboard of the motor**. A light, sharp knock — enough to hear it clearly, nowhere near hard
enough to mark the carbon. No metal on carbon.

**Do this set of recordings.** Each is a separate file, five taps each:

| # | File name | Arm | Direction of the tap | Props |
|---|---|---|---|---|
| 1 | `arm_A.wav` | front-left | **downward**, square onto the flat top of the arm | on |
| 2 | `arm_B.wav` | front-right | downward | on |
| 3 | `arm_C.wav` | rear-left | downward | on |
| 4 | `arm_D.wav` | rear-right | downward | on |
| 5 | `lateral.wav` | front-left, again | **sideways**, into the edge of the arm | on |
| 6 | `propsoff.wav` | front-left, again | downward | **off** |
| 7 | `gyro_armA.csv` | front-left | downward | off (route B) |

Files 5 and 6 are not spares. They are how the analyser tells the arm apart from everything
else that rings in the same room:

- an arm bends **up and down** far more easily than side to side, so the real mode must be much
  louder in file 1 than in file 5 — a room echo or the workbench does not care which way the
  screwdriver went;
- taking the prop off makes the arm ring **about 7% higher** and does nothing at all to a room
  resonance, a plate mode, or mains hum.

If either file is missing, the analyser says so and reports a weaker result rather than
pretending.

---

## 4. Send back

- the six WAVs and, if you did route B, the decoded CSV
- `build.txt` from step 0
- one line on the room: hard floor or carpet, anything running (fridge, AC, fan)
- one line on the clamp: vise or G-clamps, and what padding

Then the analysis is:

```bash
.venv/bin/python tools/impact_analysis.py --source wav \
  --arm-mm 110.4 --tip-mass-g 36.8 --prop-mass-g 4.6 \
  arm_A.wav:A:vertical:on arm_B.wav:B:vertical:on \
  arm_C.wav:C:vertical:on arm_D.wav:D:vertical:on \
  lateral.wav:A:lateral:on propsoff.wav:A:vertical:off
```

---

## What can come out of it, all three of which are fine

1. **A number that agrees with 180 Hz.** Useful — the anchor stops being unsourced.
2. **A number that disagrees.** This is the *point*, not a failure. It unblocks
   `RateTune.kd_ceiling_for` either way. The bound was written down and committed before you
   recorded anything, and it does not get widened to accommodate whatever comes out.
3. **"No mode identified."** A real, reportable outcome. It means nothing in the recording
   behaved the way an arm bending mode has to behave, and that is a far better answer than
   confidently naming the loudest peak.

One thing the test cannot do, stated up front so nobody is disappointed: a result inside about
12% cannot tell 180 Hz from 160 Hz, and 160 Hz is the value that flips the reference build to
D-limited. This catches an anchor that is badly wrong. It does not settle the tuning question.

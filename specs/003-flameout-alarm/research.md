# Research: Flameout Alarm

Decisions behind [plan.md](plan.md). R1 was researched during
specification (2026-10-04); R2–R12 during planning. Each gives the decision,
why, and what else was considered. API facts come from the JETI Lua API v1.5
(`docs/vendor/jeti-api.md`, generated locally by `tools/pdf2md.py`) and
`docs/jeti-api-notes.md`.

| # | Topic |
| --- | --- |
| R1 | How ECUs deliver RPM |
| R2 | Alarm audio: one 5-second file per cycle, played immediately |
| R3 | Stopping the alarm, pre-empting and being pre-empted |
| R4 | Telemetry-lost callout during the alarm |
| R5 | Alarm voice and lock tone generation |
| R6 | Missing audio files: fallback beeps |
| R7 | Vibration |
| R8 | Engine monitor state machine and timing |
| R9 | Reading RPM: validity, sensor not found, units |
| R10 | Settings: number entry, thresholds, Cut switch |
| R11 | RPM window drawing and cost |
| R12 | Testing without an engine: emulator sensor and simulated profiles |
| R13 | Test alarm switch |

## R1. How ECUs deliver RPM to a Jeti transmitter

**Question:** In what form does each turbine ECU send RPM over Jeti
telemetry, so the app can read it (spec FR-002, FR-006a, FR-010)?

**Finding: RPM arrives as a plain integer RPM value on a standard Jeti EX
sensor.** Where the data reaches the transmitter as an EX sensor, the
value is the shaft speed in RPM (e.g. 112400), not thousands. The best
evidence is the open-source Jeti ECU telemetry app by Thomas Ekdahl
([thomasekdahlN/jeti](https://github.com/thomasekdahlN/jeti)), which
supports JetCat, KingTech, Xicoy, VSpeak, Digitech and CB-Electroniks
converters. Its display divides the RPM value by 1000 to show "112K" for
every converter (`ecu/lib/window4.lua`), and its per-converter configs
(`ecu/converter/<converter>/<turbine>/config.jsn`) map RPM to a sensor
parameter with no scaling.

The Jeti Lua API already applies the sensor's decimals: a sensor entry has
`value`, `decimals`, `unit` and `valid` (`types/jeti.lua`). So "raw numeric
value" is right in practice: the app reads a number and compares it with
RPM thresholds. The sensor scale setting (FR-006a, default ×1) stays as a
safety valve for any converter found to send a scaled value.

### Per manufacturer

| Manufacturer | Path to Jeti | RPM as EX sensor? | RPM param* | Status sensor? | Confidence |
| --- | --- | --- | --- | --- | --- |
| JetCat | JetCat's own Jeti converter, VSpeak, Digitech or CB-Electroniks converter | Yes | 2 | Yes, param 3: signed code, 13 = Run, negatives = faults | High |
| Xicoy (V6/V10 FADEC, also JetsMunt) | Xicoy telemetry adapter v5 (factory-set for Jeti) | Yes: sensor group "Turbine" with 6 measures (RPM, EGT, ECU battery, throttle %, pump V, fuel %) | 2 | Not as an EX sensor; status shows in the JetiBox screen emulation | High (Xicoy manual) |
| KingTech (G1–G5) | KingTech telemetry unit (lists Jeti support), VSpeak or Digitech converter | Yes | 2 | Not in the KingTech converter config | Medium |
| Swiwin (ECU V3) | VSpeak converter for Swiwin (EX-Sensor / EX-Bus); or the ECU's own telemetry port wired to a receiver's Ext port set to "Jetibox" | VSpeak: yes. Direct: unclear, may be JetiBox text only | — | VSpeak: yes (coded as a numeric value) | Low for direct |
| JetCentral | JetCentral Jeti Telemetry Adapter V2 | Unclear: the adapter ships with its own Lua app (`JCHDT.lc`, firmware ≥ 4.27); its values may not appear as ordinary sensors | — | Shown by its app | Low |
| Enjet Power | Retailers list "telemetry: Jeti, Futaba, FrSky (external module)" | Unknown: no Jeti documentation found | — | Unknown | Low |

\* Parameter number within the converter's sensor, from the Ekdahl configs.
The app doesn't depend on it: the pilot picks the sensor by its label.

### Other observations

- **Update rate** isn't documented by any manufacturer. Jeti EX sensors
  typically refresh several times a second; the 1.0 s detection delay and
  2 s telemetry-loss delay assume at least about 2 updates per second.
  Check on the transmitter with a real converter (plan / test).
- **Sensors appear 30–60 s after power-up** with the Xicoy adapter (its
  manual). Setup's "no sensors yet" message (FR-004) should say to wait.
- **The startup false-alarm problem is real.** Xicoy's adapter disables its
  own low-RPM alarm until the tank drops below 98%, "to avoid the alarms of
  Low RPM ... to be triggered during startup phase". That is the problem
  the app's arming solves.
- **Swiwin and VSpeak:** users report the Swiwin ECU misbehaving with the
  transmitter's "Auto" output period; 11–13 ms fixes it. Not our concern,
  but worth a README note for Swiwin users.
- **ECU status codes** (JetCat: 13 Run, −7/−29/−30 Low rpm, −14 Failsafe;
  Xicoy: 8 Running, 15 Flameout) could confirm a flameout faster than RPM,
  but codes differ per brand and Xicoy doesn't send status as a sensor.
  Stays out of v1 (spec Assumptions).

### Decision

- Read RPM from a pilot-selected EX sensor as plain RPM; keep the scale
  setting at default ×1.
- Supported: any ECU or converter that shows RPM as a normal telemetry
  sensor (JetCat, Xicoy, KingTech via its unit or a converter, Swiwin via
  VSpeak). Not supported: setups whose RPM is only visible in a JetiBox
  screen or inside another vendor's Lua app. The README says so and lists
  what is known per brand.
- Open for testing: JetCentral adapter V2, Enjet, Swiwin direct. If any of
  these turns out to publish RPM as a normal sensor, it just works.

### Related limit found: number entry range

`form.addIntbox` takes values from −32768 to 32767 (`types/jeti.lua`).
Idle RPM (typically 30,000–40,000) and max RPM (100,000–160,000) don't fit
as plain integers. **Decision (2026-10-04):** settings enter them in
steps of 100 RPM, shown in thousands with one decimal ("35.0" = 35,000
RPM): the stored integer is RPM / 100 (max 1,600 for 160,000 RPM). See spec
FR-006.

### Sources

- [thomasekdahlN/jeti: Jeti ECU telemetry Lua app](https://github.com/thomasekdahlN/jeti)
- [Xicoy telemetry adapter v5 user's guide (PDF)](https://www.xicoy.com/downloads/Telemet1_1_en.pdf)
- [Xicoy telemetry adapter product page](https://www.xicoy.com/catalog/product_info.php?products_id=362)
- [VSpeak ECU converter for Swiwin](https://www.vspeak-modell.de/en/ecu-converter/swiwin)
- [VSpeak ECU converter for JetCat (RPM Jets)](https://rpmjets.com/products/ecu-converter-jetcat)
- [JetCentral Jeti telemetry V2 Lua](https://jetcentral.com.mx/telemetry/)
- [KingTech telemetry unit G2–G5 (Pacific RC Jets)](https://pacificrcjets.com/products/kingtech-telemetry-unit)
- [Swiwin + Jeti + VSpeak (RCU Forums)](https://www.rcuniverse.com/forum/rc-jets-120/11710796-swiwin-jeti-v-speak-=-loosing-my-mind.html)
- [Swiwin turbine telemetry adapter from VSpeak (RCU Forums)](https://www.rcuniverse.com/forum/rc-jets-120/11684464-swiwin-turbine-telemetry-adapter-vspeak.html)
- [Enjet Power E100 (Helidirect)](https://www.helidirect.com/products/enjet-power-e100-turbine)

## R2. Alarm audio: one 5-second file per cycle, played immediately

**Decision:** Each alarm cycle is **one pre-built WAV of exactly 5.000 s**:
the urgent "Flameout! Flameout! Flameout!" callout followed by the lock tone
filling the rest. At the start of each cycle `loop()` calls
`system.playFile(CYCLE, AUDIO_IMMEDIATE)`; the next cycle starts when
`now - cycleAt >= 5000`.

**Why:**

- **No gap or overlap (SC-012)** without timing two files from `loop()`.
  Voice-to-tone timing is fixed inside the file; only the 5-second rhythm
  depends on `loop()`, which runs every 20–30 ms (checked on the 100 ms
  logic tick: jitter well inside ±0.3 s).
- **`AUDIO_IMMEDIATE` "starts immediately in the foreground" and "stops any
  previous foreground playback"** (API v1.5, `playFile`). So a cycle starts
  on time even if another app is speaking (FR-025), and if the previous
  cycle's file runs a few ms long, the new one cuts its tail instead of
  queuing behind it.
- `AUDIO_QUEUE` would wait behind any other app's queued speech: rejected.
- A short looping lock-tone file restarted by `loop()` would need precise
  sub-second scheduling and could leave gaps: rejected.

## R3. Stopping the alarm, pre-empting and being pre-empted

**Decision:** Relight and Cut call `system.stopPlayback(AUDIO_IMMEDIATE)`,
which "stops only foreground playback and clears the foreground queue". All
alarm sound stops at once, mid-callout or mid-beep (FR-016, edge case). It
also drops any other app's queued foreground speech at that moment, which is
acceptable at a relight or shutdown.

**Known limits (documented, not solved):**

- **Another app's `AUDIO_IMMEDIATE` cuts our cycle.** Speed Gauge plays its
  stall and overspeed warnings that way, and a dead-stick glide can trigger
  a stall warning. The alarm then resumes at the next 5-second boundary, so
  at most one cycle is shortened. Quickstart checks this with both apps.
- **Transmitter alarms can interrupt foreground playback** ("playback can be
  interrupted by alarms", API v1.5). Native alarms (e.g. low receiver
  voltage) may briefly cut the alarm; again it resumes at the next cycle.
- `AUDIO_BACKGROUND` is "not interruptible by alarms", but it also isn't
  stopped by `stopPlayback(AUDIO_IMMEDIATE)` and would overlap other apps'
  speech instead of pre-empting it. Rejected: an alarm that talks over a
  callout is harder to understand than one that replaces it.

## R4. Telemetry-lost callout during the alarm

**Decision:** A second cycle file, **`cycletl.wav`** (5.000 s), holds the
flameout callout, then "Engine telemetry lost", then a shorter lock tone.
When telemetry passes the loss delay during the alarm, the app sets a flag
and plays `cycletl.wav` instead of `cycle.wav` at the **next** cycle
boundary, once (FR-020a).

**Why:** It keeps the 5-second rhythm (SC-012) and speaks the warning
"between two alarm cycles" without stopping or restarting the alarm.
Playing `tlost.wav` on its own at the boundary would shift the following
cycle by the phrase length. The generator checks that both parts fit
(R5).

While Armed (no alarm), the loss callout is `tlost.wav` with
`AUDIO_IMMEDIATE` (FR-020).

## R5. Alarm voice and lock tone generation

**Decision:** A new script, **`tools/voice/make_flameout.py`**, generates
the app's sounds into `src/Apps/AG-FlmOt/`. It imports the helpers in
`tools/voice/make_voice.py` (`synthesize`, `trim`, `normalize`, `resample`,
`write_wav`, `write_text`) and leaves that script unchanged, so Speed
Gauge's voice set is unaffected. Files, all mono 16-bit 22.05 kHz (verified
to play on the transmitter with Speed Gauge 0.3.0):

| File | Content | Length |
| --- | --- | --- |
| `cycle.wav` | "Flameout!" ×3 (0.12 s apart), then lock tone | exactly 5.000 s |
| `cycletl.wav` | "Flameout!" ×3, "Engine telemetry lost", then lock tone | exactly 5.000 s |
| `tlost.wav` | "Engine telemetry lost" | ≈ 1.3 s |
| `armed.wav` | "Flameout alarm armed" | ≈ 1.3 s |
| `relit.wav` | "Engine relit" | ≈ 1 s |
| `CREDITS.txt` | Piper (MIT) and Amy (CC BY-SA 4.0) | — |

The urgent delivery (spec FR-026) is done **in Python, without ffmpeg**
(not installed here):

- **Speed and pitch together.** The draft's chain was Piper length scale
  0.70, then ffmpeg `asetrate ×1.07` (raises pitch and speeds up 7%) and
  `atempo 0.9346` (slows back down without changing pitch). Equivalent
  without a time-stretch: synthesize at length scale 0.70 × 1.07 = **0.749**
  (7% slower), then resample so it plays 7% faster (`asetrate`). Net speed
  is the draft's 0.70, pitch is up about one semitone. Noise scale 0.5.
- **High-pass 150 Hz** and **+4 dB peaking at 3 kHz**: standard biquads
  (RBJ cookbook) in plain Python.
- **Compression**: threshold −18 dB, ratio 4, attack 3 ms, release 60 ms,
  makeup +4 dB, as a simple peak envelope follower.
- Trim and normalize to Speed Gauge's peak (−1 dBFS) with the existing
  helpers.
- **Lock tone**: 1800 Hz sine plus a 3600 Hz overtone, 45 ms on / 35 ms
  off with 3 ms fades (12.5 beeps/s), from the approved sample, at the same
  peak.

Only the Flameout callouts are urgent; the confirmations and "telemetry
lost" use Speed Gauge's normal speed (1.5) so they sound calm and distinct
from the alarm.

**Self-check** (exit 1 on failure): every file present; both cycle files
exactly 110,250 samples; the voice part of `cycle.wav` ≤ 2.5 s ("about
2 s", FR-023) and of `cycletl.wav` ≤ 4.0 s so at least 1 s of lock tone
remains.

**Alternatives:** extending `make_voice.py` with a `--set` option (touches
the Speed Gauge tool and its self-check: rejected); installing ffmpeg (an
extra dependency for one filter chain: rejected); the draft's samples made
with Amy *low* (the spec asks for the same model as Speed Gauge, *medium*).

## R6. Missing audio files: fallback beeps

**Decision:** `init()` opens each of the five WAVs once (Speed Gauge's
`fileExists` pattern, function-style `io`). If either cycle file is missing,
each alarm cycle instead calls `system.playBeep(9, 1800, 120)` (10 beeps)
at the cycle start and again 2.5 s later, keeping the on-screen FLAMEOUT
and vibration. Settings shows "Voice files missing" (FR-029). A missing
confirmation or `tlost.wav` is skipped silently; the screen still shows the
state.

`playBeep` takes 0–10 extra beeps, 200–10,000 Hz, 20–10,000 ms (API v1.5).
The gap between beeps isn't documented: check by ear (quickstart).

## R7. Vibration

**Decision:** At the start of every alarm cycle,
`system.vibration(false, 4)` and `system.vibration(true, 4)`: three short
pulses on both sticks (FR-030), as in the API example for both sticks. Not
supported on DC/DS-16, which the app doesn't target. Speed Gauge uses
profile 4 for its stall warning; the API calls it "3 × short pulse".

## R8. Engine monitor state machine and timing

**Decision:** A 100 ms logic tick, as in Speed Gauge. States: `OFF`,
`DISARMED`, `ARMED`, `FLAMEOUT`; telemetry validity is tracked alongside,
not as a state, so "no telemetry" can overlay ARMED or FLAMEOUT. Full table
in [data-model.md](data-model.md).

- **One timestamp per condition** (`armSince`, `lowSince`, `clearSince`,
  `invalidSince`), set when the condition starts and cleared when it
  breaks: no counters, no allocation.
- **Cut is checked first every tick** and wins over everything (FR-016).
- **Telemetry loss freezes detection**: an invalid sample clears
  `armSince`, `lowSince` and `clearSince`, so a loss can never complete a
  flameout or a relight (FR-020, FR-021).
- Tick period vs. the specs: alarm start ≤ detection delay + one tick
  (100 ms) + loop jitter, inside SC-001's +0.5 s; relight clear likewise
  for SC-011.

**Alternative:** run the logic every `loop()` (20–30 ms): finer timing
nobody needs, 3–5× the work.

## R9. Reading RPM: validity, sensor not found, units

**Decision:**

- `system.getSensorValueByID(id, param)` each tick, always through
  `system` (the emulator's telemetry app replaces it; Speed Gauge R3).
  `nil` means the sensor isn't in the model's list; `valid == false` means
  no recent data. Both count as invalid for detection.
- `nil` shows **NO SENSOR** (FR-022); `valid == false` shows **NO
  TELEMETRY**. Neither arms.
- RPM = `value × scale` (FR-006a), compared with thresholds precomputed in
  RPM when settings change.
- **Unit check** in settings only (FR-010): accept units that read as RPM
  ignoring case: `rpm`, `U/min`, `1/min` (German converters use the last
  two). Anything else, including an empty unit, shows the warning; the
  sensor stays selectable because some converters send no unit.
- The firmware's own "valid" timeout is unknown. The telemetry-loss delay
  counts from the first invalid sample, so the real delay is a little
  longer than the setting. Measure on the transmitter (quickstart).

## R10. Settings: number entry, thresholds, Cut switch

**Decision:**

- **Idle and max RPM** stored as RPM / 100 in an intbox with 1 decimal, so
  "35.0" = 35,000 RPM (spec FR-006; intbox limit 32,767). Idle range
  0–150.0 (0 = not set; small turbines idle around 50,000–60,000); max
  0–300.0 (0 = auto, 4 × idle; small turbines reach about 240,000). Max ≤
  idle is refused.
- **Thresholds** as whole percentages of idle: arming 50–98 (default 90),
  flameout 20–95 (default 70). A change that would make flameout ≥ arming
  is refused: the box snaps back and a hint explains (FR-007). Arming % <
  100 keeps the arming threshold below idle by construction.
- **Times** in tenths of a second: arming 1.0–10.0 s (3.0), detection
  0.3–5.0 s (1.0), telemetry loss 0.5–10.0 s (2.0).
- **Cut switch**: `form.addInputbox(swCut, false, ...)`, non-proportional.
  The pilot assigns it with the switch in the Cut position; Jeti stores the
  direction in the SwitchItem, so "in Cut" is `getInputsVal(swCut) > 0.5`
  (Speed Gauge R10's rule). A hint says how to assign it.
- **Enable checkbox** is refused (unticked again, hint shows what's
  missing) unless sensor, Cut switch and idle are all set (FR-003).
- **Live RPM row** updated from `loop()` only while the form is open
  (Speed Gauge R17's `formOpen` pattern), at most every 500 ms.
- 17 persisted keys, well under 30 (the test switch, R13, is the 17th) ([data-model.md](data-model.md)).

## R11. RPM window drawing and cost

**Decision:** One telemetry window, size 0 ("auto"), so the pilot places it
at single or double size (verified with Speed Gauge 0.3.0). The print
function picks the layout from `(w, h)`, after Speed Gauge's emulator
title-bar correction (`w == 157` → `h - 26`):

- `h >= 45`: **double layout**, the segmented sweep of
  [design/rpm-window-mockup.svg](design/rpm-window-mockup.svg): 12 segments,
  bottom edge `y = 22 + 40·(1 − t)^2.2`, height `6 + 12·t`, 2 px gaps.
- otherwise: **single layout**, the straight bar.

Segment corner points are computed once per layout in `init()` (integer
arrays, no per-frame trig or allocation). Each frame draws the segments as
filled `lcd.renderer()` polygons at full opacity (one renderer reused, as
Speed Gauge does) and the idle marker as a filled rectangle. Unlit segments
get a dim fill plus a 1 px outline polyline.

**Measured (2026-10-06, DS-24 II, `DEBUG_CPU`):** 5–6% of the per-call
budget for the double-size window (5% armed, 6% with the FLAMEOUT banner),
less than half of Speed Gauge's double-size dial. No fallback needed. Both
window sizes confirmed on the transmitter by screenshot.

**Cost (planning estimate):** Speed Gauge measured that opaque fills are cheap and
semi-transparent anti-aliased polylines are what cost CPU. 12 polygons and
12 thin opaque outlines should stay far below Speed Gauge's double-size
14–18%. Measured with a `DEBUG_CPU` flag (off for release), as in Speed
Gauge. If too costly: drop the outlines first, then fall back to the
straight bar (spec FR-031).

**Number:** "112,400" built by a small formatter only when RPM / 100
changes, so at most once per tick; `FONT_BIG`, right-aligned under the high
end, "RPM" in `FONT_MINI` below it.

**Other transmitters:** the sweep needs `lcd.renderer` (DC/DS-24 only). On
anything that isn't a DS-24 II (`getDeviceType()` lacks "24 II", Speed
Gauge R12), the window shows the state and number as text. The alarm works
everywhere.

**Lit segments:** `ceil(12 · rpm / fullScale)`, capped at 12, none without
data. At idle RPM the lit run ends at the marker. Layout constants are named
so the design can be iterated on the transmitter.

## R12. Testing without an engine: emulator sensor and simulated profiles

**Decision:**

1. **Emulator sensor.** Add a "Turbine" sensor to
   `tools/emulator/sensors.json` (LeonAirRC's Emulated Telemetry): RPM,
   unit `rpm`, 0–160,000 on a slider. The slider fully down makes it invalid,
   which tests telemetry loss.
2. **Simulated profiles.** A `SIM` debug constant in the app (off for
   release, like `DEBUG_CPU`) replaces the sensor read with scripted RPM
   profiles (time, RPM pairs in one table): normal flight with start
   overshoot and decay, chops, flameout, auto-restart that fails then
   relights, telemetry dropouts. That makes SC-001, SC-002, SC-003 and SC-011
   repeatable in the emulator. Switching profiles uses the app's form; the
   table lives in one local to respect the 200-local limit.
3. **Audio** can only be heard on the transmitter (the emulator plays no
   Lua audio); in the emulator the Emulated Telemetry app prints each
   `playFile` and `vibration` call to the console, which checks timing.
4. **Real engine**: bench test on a test model with the turbine's ECU
   converter, never on a model flying that day (constitution verification
   step 4).

**Alternative:** a standalone test runner under plain Lua (none installed;
the state machine would have to be split into a module just for testing).
Rejected for v1.

## R13. Test alarm switch

**Decision:** An optional SwitchItem `swTest` (spec FR-030a). A **rising
edge** (off to on) while the state is OFF or DISARMED starts a test: the
same cycle code as a real alarm (R2, R6, R7), with `cycleAt` set and the
window showing TEST. The test runs while the switch stays on and stops with
`stopPlayback(AUDIO_IMMEDIATE)` when the switch turns off or the app arms.

**Why:**

- **The rising edge** means a switch left on at model load, or after the
  app arms, doesn't start an alarm by itself (spec edge cases).
- **Reusing the alarm path** tests exactly what a flameout would play,
  including the fallback beeps when files are missing, rather than a
  separate preview sound.
- **Ignored while ARMED or FLAMEOUT**, so a test can never mask or imitate a
  real alarm. Arming during a test stops it, so a forgotten switch can't
  sound in flight.
- **Works with monitoring off**, so the sound can be checked before setup
  is finished. This is the one exception to "silent when OFF" (FR-012,
  SC-009).

The test never changes `state`: it's a separate `testOn` flag, so the state
machine (R8) is untouched. The telemetry-lost variant isn't part of the
test.

**Alternatives:** an F-key "Test" in the settings form (works only while
the form is open and can't be bound to a transmitter switch; could be added
later); one cycle per press (a held switch couldn't check the 5-second
rhythm).

# Research: Turbine Throttle Setup

Planning decisions for `specs/002-turbine-throttle-setup/spec.md`. Each item
gives the decision, why, and what else was considered. Items marked
**CALIBRATE** are hypotheses the first implementation task measures in the
emulator and on the transmitter (quickstart section 1) before anything is
built on them.

Sources used throughout: JETI DC/DS Lua API v1.5 (local copy
`docs/vendor/jeti-api.md`), `types/jeti.lua`, `docs/jeti-api-notes.md`, the
JETI DC-16 manual (Other Model Options), and the ECU manuals cited in the
spec's Clarifications.

---

## R1. Reading the throttle output, and converting it to µs (CALIBRATE)

**Decision.** Read the selected output with `system.getInputs("O<n>")`
(`O1`–`O24`, API p. 40) and convert with `us = 1500 + 500 * v`.

**Rationale.** The API returns servo outputs in −1..1 and documents the
`O1`–`O24` codes (the stub in `types/jeti.lua` already lists them). JETI
travel percentages map at 5 µs per percent: ±100% gives 1000–2000 µs (RCU
Forums, Jeti DS-24 thread), and the reference setup (±80% → 1100/1900 µs)
fits the same rule.

**Open points, measured in task 1 against the servo monitor (µs view):**

1. That `O<n>` is the **final** output, after Throttle Cut, Throttle Idle,
   travel and limits. The whole app depends on this. If it turns out to be
   a pre-mix value, verify can't work and the spec has to be revisited
   before going on.
2. Whether `v` is clipped at ±1. If it is, readings beyond 1000–2000 µs
   saturate. In that case the valid target range (FR-003, now 900–2100 µs)
   narrows to 1000–2000 µs and the spec is amended.
3. Agreement within ±5 µs at 5+ points (SC-003), in the emulator and on
   the DS-24 II.

**Measured on the transmitter (Aaron, 2026-10-10, test model, app's
"Signal now"; travel ±100%, cut −100%, idle offset 20%):** CUT + stick
down 1000, **CUT + stick up 1000**, RUN + stick down 1100, RUN + stick up
2000 µs. Open point 1 is **confirmed**: `O<n>` is the final output after
Throttle Cut (the stop rule doesn't trigger). With ±100% travel, readings
run 1000–2000 µs as `1500 + 500 * v` predicts, and idle = low end + 5 ×
offset holds at a second travel setting (R2: 1000 + 100 = 1100).

**Alternatives.** Logging the output with `registerLogVariable`: no, it's
for writing to the log, not reading. Reading the stick and calculating the
output: no, that would verify the app's own math, not the model.

## R2. Converting targets to settings (CALIBRATE)

**Decision.** With 5 µs per percent (R1):

| Setting (JETI wording) | Formula | 1100/1200/1900 | Defaults 1000/1200/1900 |
| --- | --- | --- | --- |
| Servo setup → throttle → Travel − | (1500 − cut) ÷ 5 | 80% | 100% |
| Servo setup → throttle → Travel + | (full − 1500) ÷ 5 | 80% | 80% |
| Throttle Cut → Output value | −100% (always) | −100% | −100% |
| Throttle Idle → Idle offset | (idle − cut) ÷ 5 | 20% | 40% |

The defaults changed to 1000 / 1200 / 1900 on 2026-10-10 (spec
clarifications). The 1100 / 1200 / 1900 column is Aaron's original
reference setup, which the reasoning below uses.

Targets are entered in 5 µs steps, so every value is a whole percent and
SC-006 holds exactly if the formulas hold.

**Rationale.** The reference setup is the only known calibration point,
and it fits these formulas exactly:

- **Throttle Cut −100%** gives 1100 µs at 80% travel. So the cut value is
  scaled by travel (−100% × 0.8 = −80% → 1100 µs), which makes cut always
  the low travel end. A forum setup with cut −125% and limit −125% reaches
  past the travel end the same way.
- **Idle offset 20%** gives +100 µs (1100 → 1200 µs), i.e. offset points
  added after travel at 5 µs each. A pre-travel offset (20% × 0.8 = 16
  points → 1180 µs) does **not** fit the reference, which suggests post-travel.

The JETI manual only says the offset "defines the minimum throttle setting
as a percentage", so the idle-offset rule was the least certain. It was
settled by measurement, below: the Flash reads −60% at idle, not −64%.

**Confirmed (Aaron, 2026-10-10).** Four of Aaron's turbine models (copied
`.jsn` files, kept out of git) all use travel −80/80 on O1, idle offset
20% and Throttle Cut / Throttle Idle on opposite positions of SJ. Three
have cut −100% and the Avanti Mini (Xicoy ECU) has −125%. With cut on, the
servo monitor shows **−80%** on the −100% models, and the stick is
blocked. So the cut value is scaled by travel (−100% × 0.8), and cut
overrides the stick (verify state 2).

**Measured, Flash Ultra EVO (Swiwin ECU; firmware 6.06; servo monitor, %
view):** CUT low −80%, CUT high −80%, RUN low **−60%**, RUN high +80%,
i.e. 1100 / 1100 / 1200 / 1900 µs. Idle = −80 + 20, so **the idle offset
is added after travel**, in output percent (scaled by travel it would be
−64%). The idle-offset formula stands.

**Measured, Avanti Mini (Xicoy ECU; travel −80/80, cut −125%, idle 20%):**
CUT low −100%, CUT high −100%, RUN low **−60%**, RUN high +80%, i.e.
1000 / 1000 / 1200 / 1900 µs. Two conclusions:

1. The cut value is scaled by travel (−125% × 0.8 = −100%), and it
   overrides the stick.
2. Idle counts from the **stick's low end** (−80 + 20), not from the cut
   value.

**Effect on the formulas: none.** The guide always sets cut to −100%, so
the cut point *is* the low end, and (idle − cut) ÷ 5 is the offset from
the low end. The Avanti's targets come out as Travel −100 / +80, cut
−100%, idle 40%: the same outputs by a different route. Verify measures
outputs only, so a pilot's existing Avanti-style setup (cut below the low
end) passes as well. The diagnosis for a low cut reading names both
Travel − and the Throttle Cut value ([verify.md](contracts/verify.md)).

General rule, for reference: low end = 1500 − 5·travelLo; cut = 1500 +
5·cutValue·travelLo/100; idle = low end + 5·offset; full = 1500 +
5·travelHi.

All four formulas live in one small function (contract
[settings-math.md](contracts/settings-math.md)), so a calibration result
changes one place.

**Extra validation from the formulas.** Cut must be below 1500 µs and full
above it, or travel comes out zero or negative. This is the spec's
"targets that need settings outside what the transmitter allows" edge
case. The app refuses such targets with that reason. JETI's travel maximum
(believed 125%, i.e. 875–2125 µs) is outside the 900–2100 µs target range,
so it never binds. Task 1 confirms the maximum.

## R3. Opening transmitter menus

**Decision.** `system.openExternal(":servoSetup")` for endpoints,
`":otherProps"` for Throttle Cut and Throttle Idle, `":devExplorer"` for
receiver failsafe. The safety-switch step has no menu.

**Rationale.** API v1.5 p. 74–75 lists these constants ("Servo setup and
gains", "Other model options (throttle cut etc.)", "Device Explorer"). The
manual puts Throttle Cut and Throttle Idle under "Advanced Properties →
Other Model Options". The stub in `types/jeti.lua` only mentions files, so
task 1 updates its comment with the menu constants (source: API p. 74–75).

**Labels on the transmitter (Aaron, 2026-10-10, `Screen007.png`, kept as
`docs/apps/img/throttle-setup-wizard-cut-idle.png`).** The screen is titled
"Other Model Options". Section "Throttle Cut (Channel: 1)" has
"Throttle-Cut switch" and "Throttle-Cut output value"; section "Throttle
Idle (Channel: 1)" has "Throttle-Idle switch" and "Throttle-Idle offset".
Each switch row shows ✓ when that function is active and ✗ when not, so
with both on one switch they always show opposite marks. The guide text
uses these labels (FR-007).

**Servo Setup labels (Aaron, 2026-10-10, `Screen008.png`).** "Servo No."
selects the output, shown as function name plus output number (e.g.
"Engine 1 (1)"). Rows: "Subtrim", "Max positive", "Max negative" (shown
signed, e.g. −100%), "Max positive limit", "Max negative limit" (defaults
125% / −125%), "Reverse", "Delay positive/negative". A bar at the top
shows the live output in percent. So "Travel −/+" in this research means
Max negative / Max positive on screen. Failsafe labels are still to be
confirmed.

**Measured (transmitter, 2026-10-10).** `openExternal(":servoSetup")`
opens the Servo Setup screen; pressing Esc there returns straight to the
app's Setup inputs screen. R4's resume design is still kept for reopening
the app later.

**Open point (task 1).** The call is asynchronous. What happens to the
app's form when the pilot backs out of the menu isn't documented. The
design doesn't depend on it (R4).

## R4. Keeping the wizard's place (FR-009)

**Decision.** The current screen and guide step are kept in file-level
locals and also `pSave`d whenever they change. The form's init rebuilds
whatever screen those values name. So it doesn't matter whether returning
from a menu reopens the form, re-runs its init, or leaves it untouched.

**Rationale.** In-memory state lives until the model changes (constitution
IV). `pSave` covers a power cycle or reopening the app. Saves commit at
model switch or power-off, which is fine for a wizard.

## R5. Choosing the switch, its CUT position and the stick's idle end

**Decision.**

- **Switch:** `form.addInputbox(item, false, ...)`, read with
  `system.getInputsVal(item)`.
- **Stick:** `form.addInputbox(item, true, ...)` (proportional).
- **CUT position and stick idle end are learned together:** one screen
  asks "Put the switch in CUT and the throttle stick at idle, then press
  Learn". The app stores the sign of each reading (`offSign`, `idleSign`,
  each ±1).
- **Refusals.** A switch reading near 0 (middle of a 3-position switch) is
  refused with "Use a two-position switch". So is a stick not near an end
  (|v| < 0.95).

**Rationale.** How an inputbox encodes a switch's "active" position, and
which way a stick reads with a given stick mode and calibration, varies
and isn't documented. Learning both from the pilot's own hands removes the
question and costs one press. It also matches how the pilot thinks
("this is CUT").

**Found on the transmitter (2026-10-10).** The stick has to be assigned
as **proportional** in the inputbox's dialog. `addInputbox(item, true)`
only *allows* it; assigned as a switch, the stick never reads "middle".
Learn refuses a stick whose `getSwitchInfo(stk).proportional` is false,
and the screen hints "Assign it as proportional (P)."

**Alternatives.** A "+/−" selectbox for CUT: error-prone, since the pilot
doesn't know which sign is which. Assuming stick low = −1: wrong for
inverted assignments.

## R6. What the app can't detect: trim, flight mode, switch reuse

**Decision.** Standing reminders on the verify screen for trim and flight
mode. The safety-switch step text warns about using the same switch
elsewhere. The spec's FR-018 and trim edge case were amended to match
(2026-10-10).

**Rationale.** API v1.5 has no call for digital trim positions (`T1`–`T16`
in `getInputs` are trainer inputs), for the active flight mode, or for
other functions' switch assignments. An off-center trim still shows up as
idle and full failing by the trim amount, which the diagnosis text mentions.

## R7. Verify sequence and output check

**Decision.** Verify runs an **output check**, then the four states in the
spec's order:

0. **Output check** (switch RUN): the pilot moves the stick to idle, then
   to full. The app tracks the output at each end. It fails if the output
   moves less than half of (full target − idle target) ("Wrong output?
   Choose the throttle output"), or if it's lower at full than at idle
   ("Throttle reversed: check servo reverse"). This satisfies FR-017
   ("before measuring"). It also catches a backwards switch: the pilot's
   RUN is then really cut, which holds the output at the cut target
   whatever the stick does ("Switch RUN gave cut: reverse the switch
   assignment").
1. Cut (CUT, idle stick)
2. Cut overrides stick (CUT, full stick)
3. Idle (RUN, idle stick)
4. Full (RUN, full stick)

A failure stops the run at that state with a diagnosis
([verify.md](contracts/verify.md)). The pilot can retry that state
(diagnosis only, clarification Q1) or restart the run.

**Rationale.** Keeping the spec's order keeps its acceptance scenarios
literal. For example, a reversed switch fails at the cut state. The output
check is the only place the stick moves the output in a known direction,
so it has to be its own step in RUN.

**Alternative considered.** Idle → Full → Cut-overrides → Cut, which needs
one hand movement per step and builds the "flip to CUT at full stick"
emergency habit. Rejected because it moves the reversed-switch failure to
a different state than the spec describes. It could be revisited after
bench testing.

## R8. When a reading is taken

**Decision.** For each state, the app waits until:

- the switch is in the required position (`getInputsVal(sw) * offSign ≥
  0.5` for CUT, `≤ −0.5` for RUN);
- the stick is at the required end (`getInputsVal(stk) * idleSign ≥ 0.95`
  for idle, `≤ −0.95` for full);
- both have been steady for **500 ms**: stick within ±0.01 and output
  within ±2 µs.

It then averages **10 samples, 50 ms apart**, and rounds to whole µs. If
the position is lost mid-sample, it starts over. Loop work is rate-limited
to every 50 ms and happens only while a verify is running.

**Rationale.** A 0.95 end band allows for stick calibration that doesn't
quite reach ±1. The steadiness window rejects a stick still moving (spec
edge case). Averaging smooths jitter well inside the ±5 µs SC-003 budget.
The numbers are constants in one table, to tune on the bench.

## R9. Screens: built from form components, no form print function

**Decision.** Every screen is a subform (`form.reinit(n)`) made of labels,
inputboxes, intboxes and a selectbox. Live values (switch position, stick,
output µs, verify progress) update label text with `form.setProperties`
from `loop()`, only while the form is open, at most every 200 ms, and only
when the text changes. F-keys carry the actions (Back / Open / Next,
Learn, Start / Retry / Restart, Done / Not yet).

**Rationale.** The firmware lays out and scrolls form rows itself, so the
unmeasured form canvas (spec research item 5) matters only for line
length. Instruction lines are kept to ≤ 32 characters and checked on the
transmitter (quickstart section 3). Flameout Alarm uses the same
`setProperties`-while-`formOpen` pattern.

**Alternative.** A form print function drawing with `lcd`: needs the
canvas size and duplicates what labels do.

## R10. No telemetry window, no sounds, no assets, no lib module

**Decision.** The app registers one form under `MENU_APPS` and nothing
else: no telemetry window, no voice, no asset folder, no `lib/` module.
The install is the single file `AG-TrbSt.lua` (FR-024, SC-009).

**Rationale.** It's a bench wizard. The spec puts voice out of scope. The
µs conversion and settings math are a few lines with no second user (the
same "R2 rule" Speed Gauge used). `loop()` returns at once unless the form
is open.

## R11. Persistence and invalidating a saved result

**Decision.** 14 `pSave` keys ([data-model.md](data-model.md)). Changing
any setup input while a result is saved first calls `form.question`
("Clear the saved result?"). On Yes it clears the result keys. On No it
puts the previous value back with `form.setValue`. The question appears
once per edit session on that screen, not on every intbox step. The date
is stored as a `yyyymmdd` integer built from `system.getDateTime()`. That
avoids calendar math on `getTime()` seconds, since there's no `os.date`
on the transmitter.

**Rationale.** `form.question` blocks, which is fine in a form callback
and never happens in `loop()` (api notes). Integers, SwitchItems and one
4-element integer array are all storable types.

**Copied models (spec research item 6): resolved.** The model `.jsn`
file holds each app's saved values in its `Lua` section ("Lua-Props" per
app), so copying a model copies the app's saved result too. That's safe:
a copied result shows the original date, and any input change clears it.

## R12. Firmware 6.x Lua API

**Decision.** Plan against API v1.5 plus what this repo has already
verified on 6.03/6.04. No new API is assumed.

**Rationale.** Public 6.03/6.04 notes (jetimodel.com news) mention color
profiles and Wi-Fi, not Lua additions. Aaron's transmitter now runs
**6.06** (two of the model files were saved with it). The calibration in
quickstart section 1 is done on that firmware. Nothing in this design needs a
setting-write API, which constitution I would forbid anyway.

## R13. Transmitter support (FR-025)

**Decision.** If `system.getDeviceType()` doesn't contain "24", the app's
form shows only "Throttle Setup Wizard needs a DC/DS-24" and does
nothing else. If `system.openExternal` is nil (firmware before 5.01), the
Open buttons are hidden and the step text still names the menu.

**Rationale.** The layout and line lengths are designed and tested on the
24 series only. A clear notice satisfies FR-025 for everything else.

---

Sources (web, 2026-10-10):

- [JETI DC-16 manual, Throttle Cut / Throttle Idle (ManualsLib p. 220)](https://www.manualslib.com/manual/1311760/Jeti-Model-Duplex-Dc-16.html?page=220)
- [RCU Forums: Jeti DS-24 thread (±100% → 1000–2000 µs; cut −125% example)](https://www.rcuniverse.com/forum/rc-jets-120/11624694-jeti-ds-24-a-9.html)
- [JETI model news (6.03, 6.04 releases)](https://www.jetimodel.com/news/)
- [Xicoy TurboJet manual v1.5/2024](https://www.xicoyturbines.com/assets/files/XicoyTurbojetManual_EN.pdf)
- [KingTech engine manual 2016](https://kingtechturbine.lu/media/manual/Manual_KingTech20161111.pdf)

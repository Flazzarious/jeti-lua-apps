# Data Model: Battery Capacity

**Feature**: `specs/005-battery-capacity/` | **Date**: 2026-11-01

Saved settings, constant tables, derived values and per-battery session
state. Persistence rules: [research.md R5](research.md#r5-persistence-layout-fr-005-open-question-7-constitution-iv).

## Constant tables (in the app, not saved)

### Category (FR-002, FR-007)

Saved by **id**; ids never change or get reused. Display order is a separate
list, so new categories can be inserted anywhere in the menu.

| id | Name | Default label | Voice file | Chem | Bands Y/O/R | Levels 1/2/3/4 | Current alarm rows | Max callout |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Flight pack | FLIGHT (short: FLT) | `n_flt` | LiPo | 50/30/20 | 50/40/30/20 | shown | on |
| 2 | Receiver | RX | `n_rx` | LiFe | 60/45/30 | 60/50/40/30 | shown | off |
| 3 | Turbine ECU | ECU | `n_ecu` | LiFe | 60/45/30 | 60/50/40/30 | hidden | off |
| 4 | Landing gear | GEAR | `n_gear` | LiFe | 55/40/30 | 60/50/40/30 | shown | off |
| 5 | Brakes | BRAKES (short: BRK) | `n_brk` | LiFe | 55/40/30 | 60/50/40/30 | shown | off |
| 6 | Lights | LIGHTS (short: LGT) | `n_lgt` | LiPo | 40/20/10 | 40/30/20/10 | hidden | off |
| 7 | Aux | AUX | `n_aux` | LiPo | 50/30/20 | 50/40/30/20 | shown | off |
| 8 | Custom | (custom name) | `n_bat` | none (LiPo values) | 50/30/20 | 50/40/30/20 | shown | off |

"Short" labels apply only if the measured width check fails (research R6).
Custom with chemistry "none" keeps LiPo as the selected chemistry; the pilot
picks one.

### Chemistry (FR-006, research R3)

| id | Name | Full | Nominal | Warning | Cutoff | Curve |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | LiPo | 420 | 370 | 360 | 350 | R3 LiPo |
| 2 | LiHV | 435 | 380 | 365 | 350 | R3 LiHV |
| 3 | Li-ion | 420 | 360 | 340 | 320 | R3 Li-ion |
| 4 | LiFe | 360 | 330 | 320 | 300 | R3 LiFe |
| 5 | NiMH/NiCd | 140 | 120 | 115 | 110 | R3 NiMH |

Centivolts per cell. Curves are 11-point resting tables (100 → 0%).

### Band colours (FR-012b, FR-013)

| Band | RGB | Text on fill |
| --- | --- | --- |
| green | 99, 153, 34 | white |
| yellow | 242, 194, 48 | dark 65, 36, 2 |
| orange | 239, 159, 39 | white (dark is the fallback, FR-013) |
| red | 226, 75, 74 | white |

Band: red when `pct < bandR`, else orange when `pct < bandO`, else yellow
when `pct < bandY`, else green ("below" in FR-007 is strict).

## Saved settings (`system.pSave`)

### App keys

| Key | Type | Range | Default | Notes |
| --- | --- | --- | --- | --- |
| `cfgV` | int | 1 | 1 | settings version, for future migration |
| `voice` | int | 0–2 | 0 | 0 unset → app voice if files present; 1 app; 2 transmitter (FR-032) |
| `numOnly` | int | 0/1 | 0 | Speak number only (FR-031) |
| `smallB` | int | 1–4 | 1 | battery in the small window (FR-009); clamped to configured count |
| `title1` | string | ≤ 20 chars | "Battery" | small window title (FR-009a); "" = default |
| `title2` | string | ≤ 20 chars | "Batteries" | double window title (FR-009a); "" = default |

### Per battery N = 1–4: `bNp` (pack), int array

| # | Field | Range | Default | Notes |
| --- | --- | --- | --- | --- |
| 1 | cat | 1–8 | — | category id; key absent = slot empty |
| 2 | num | 0–9 | 0 | label number; 0 = none (only one of its category) |
| 3 | chem | 1–5 | category | chemistry id |
| 4 | cells | 1–14 | 2 | |
| 5 | mAh | 0, 100–30 000 | 0 | rated capacity; required for modes 1–2 |
| 6–7 | capId, capPar | sensor | 0, 0 | capacity source; 0 = none |
| 8 | capMode | 0–4 | 0 | 0 none, 1 mAh, 2 Ah, 3 %, 4 V (R1) |
| 9–10 | vId, vPar | sensor | 0, 0 | optional voltage sensor |
| 11–12 | iId, iPar | sensor | 0, 0 | optional current sensor (a sensor in mA is flagged by field 20, bit 15) |
| 13–16 | vFull, vNom, vWarn, vCut | 50–500 cV | chemistry | per cell |
| 17–19 | bandY, bandO, bandR | 1–99 % | category | strictly descending |
| 20 | edited | bitmask | 0 | bit 0 voltages, 1 bands, 2 levels, 3 low-voltage threshold; bit 15 = current sensor reports mA |

### Per battery N: `bNa` (alarms), int array

| # | Field | Range | Default | Notes |
| --- | --- | --- | --- | --- |
| 1–4 | lvl1…lvl4 | 1–99 % | category | slot levels |
| 5 | lvlOn | bitmask 0–15 | 8 (slot 4 only) | bit k-1 = slot k enabled |
| 6 | rptS | 3–60 s | 5 | lowest-level repeat (FR-018); also low-voltage repeat (FR-021) |
| 7 | maxCnt | 0, 1–20 | 0 | 0 = no limit |
| 8 | lvMode | 0–2 | 1 if voltage reading else 0 | 0 off, 1 per cell, 2 per pack (FR-019) |
| 9 | lvThr | cV | vWarn (× cells in pack mode) | converted on mode change |
| 10 | lvDly | 5–100 ds | 20 | 0.5–10 s |
| 11 | iThr | 0–500 A | 0 | 0 = not set (FR-024) |
| 12 | iDly | 0–100 ds | 0 | 0 = not set |
| 13 | iRpt | 0–60 s | 0 | 0 = not set |
| 14 | maxOn | 0/1 | category | FR-026 |
| 15 | maxSens | 1–50 A | 5 | |
| 16 | npOn | 0/1 | 0 | FR-029; only offered with a voltage reading |
| 17 | npThr | 50–99 % | 90 | |
| 18 | showAll | 0/1 | 0 | "Show all settings" for this battery |

### Per battery N: `bNs` (strings), string array

| # | Field | Default | Notes |
| --- | --- | --- | --- |
| 1 | name | "" | Custom category label, width-checked (R6) |
| 2 | voiceName | "" | transmitter voice name file from `form.addAudioFilebox` (FR-033) |
| 3–5 | capLbl, vLbl, iLbl | "" | sensor labels for "(not found)" display only |

**Totals:** 6 + 3 × 4 = **18 keys** (limit 30).

### Load rules

- Missing key → default. Every integer clamped to its range on load; a
  clamped value is saved back.
- A `bNp` with an unknown category id (from a newer version) keeps the
  battery and shows the category as "Unknown (N)", with Custom defaults for
  speech.
- Slots are compacted on load (an empty slot between two batteries is
  closed up and saved), so batteries 1…n are always contiguous.
- `smallB` > configured count → 1.

## Derived values (recomputed when settings change, not per tick)

Per battery:

- `label`: name for Custom, else category label (short form if R6 needs it),
  plus `"-" .. num` when num > 0. Cached string.
- `speech`: voice file stem and number for the spoken name.
- `voltOf`: which reading is the battery's voltage: the voltage sensor, or
  the capacity source when capMode is 4, or none.
- `hasV`, `hasI`: booleans used to hide rows and suppress alarms (SC-012).
- `lowest`: index of the lowest enabled level.
- `lvThrCell`: low-voltage threshold in cV per cell (pack mode divided by
  cells), for one comparison per tick.
- `iOn`: current alarm complete (iThr, iDly, iRpt all > 0).

App: `useAppVoice = voiceOk and voice ~= 2`.

## Session state per battery (not saved, rebuilt in `init()`)

| Field | Meaning |
| --- | --- |
| `tel` | `NONE`, `LIVE`, `LOST` (research R4) |
| `badSince` | ms when the capacity source went invalid |
| `pct`, `pctLast` | current % (integer) and the value held before a loss |
| `vSum`, `vN`, `vNow` | fast-tick voltage accumulation; last 1 s average (cV) |
| `vEst` | smoothed voltage-based % (R3), float |
| `iNow` | last current (A, float); `nil` when lost |
| `band` | 1 green … 4 red |
| `fired` | bitmask of fired levels |
| `rptN`, `rptT` | repeats played; last start time (ms) |
| `lvBelowT`, `lvAboveT`, `lvOn` | low-voltage timers and active flag |
| `iAboveT`, `iOnT`, `iAlarm` | current-alarm timers and active flag |
| `peak` | `ag_peak` state table; `riseT`, `lastAnn` |
| `npDueT`, `npDone` | new-pack check due time; done for this pack |
| `pend*` | pending callout flags and values (R9) |
| `txtPct`, `txtLine`, `txtSmall` | cached display strings |

## State transitions

### Telemetry (per battery, capacity source)

```text
NONE --first valid reading--> LIVE          (pack session starts: arm levels, npDueT = now + 3 s)
LIVE --invalid for 1 s------> LOST          (grey, "NO TELEM", all pending callouts for it cleared)
LOST --valid, +20 pts (+V)--> LIVE (new)    (reset session; arm from current %; reset max; npDueT)
LOST --valid otherwise------> LIVE (brown)  (keep all session state)
```

### Capacity level k (enabled)

```text
ARMED --pct <= level--> FIRED   (raise pendLvl unless a lower level fired in the same tick)
FIRED --pct >= level + 5--> ARMED
```

At session start every level with `pct <= level` is set FIRED and only the
lowest of them is raised (US2 #4). The lowest enabled level, once FIRED,
re-raises itself every `rptS` (start to start) until `maxCnt` plays, re-arm,
or `LOST`. Editing levels re-arms from the current % (edge case).

### Low-voltage alarm (per battery with `hasV` and lvMode > 0)

```text
OK  --vCell < thr continuously for lvDly--> ALARM  (raise pendLv; flash outline)
ALARM --vCell >= thr + 5 cV continuously for lvDly--> OK
ALARM --new pack--> OK
```

Repeats every `rptS`, limited by `maxCnt`. Uses fast-tick readings.

### Current alarm (per battery with `hasI` and `iOn`)

```text
OK --i > iThr continuously for iDly--> ALARM (raise pendCur, repeat every iRpt)
ALARM --i <= iThr--> OK
```

### Max current

Fast tick: `peak.update` with each reading; when the max rises, `riseT =
now`. Slow tick: raise `pendMax` when `maxOn`, `now − riseT ≥ 1000` and
`max − lastAnn ≥ maxSens`. Reset: app start, model change (new context),
"Reset max current", new pack.

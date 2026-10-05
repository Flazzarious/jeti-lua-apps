# Research: Flameout Alarm

Research notes for the plan. Started during specification (2026-10-04);
`/speckit-plan` extends this file.

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

# Speed Gauge: how air density correction works

A pitot airspeed sensor such as the JETI MSpeed doesn't measure speed
directly. It measures **dynamic pressure**, the extra pressure the air makes
as it rams into the pitot tube:

```
q = ½ × ρ × v²        q = dynamic pressure, ρ = air density, v = true airspeed
```

The sensor turns that pressure into a speed by assuming sea-level air
(ρ₀ = 1.225 kg/m³). Where the air is thinner (at a high field, or on a hot
day) the same speed makes less pressure, so the sensor reads **low**. Speed
Gauge's optional air density correction works out how much thinner the air
is and scales the reading back up to **true airspeed**.

The code is [`src/Apps/lib/ag_dens.lua`](../../src/Apps/lib/ag_dens.lua).
It uses the International Standard Atmosphere (ISA) for the lower
atmosphere (below 11 km / 36,000 ft).

## The calculation

Inputs: field elevation **h** (in meters; feet are converted with
1 ft = 0.3048 m) and air temperature **T** (in kelvin: °C + 273.15).

**1. Standard temperature at the field**

```
T_std = 288.15 − 0.0065 × h        (K)
```

288.15 K is 15 °C, the ISA sea-level temperature. 0.0065 K/m is the
standard lapse rate, about 2 °C (3.6 °F) cooler per 1,000 ft.

**2. Air pressure at the field, as a fraction of sea level**

```
δ = (T_std / 288.15) ^ 5.25588
```

The exponent is g / (R × lapse rate): gravity (9.80665 m/s²) divided by the
gas constant for air (287.05 J/(kg·K)) times the lapse rate.

**3. Air density, as a fraction of sea level**

```
σ = δ × 288.15 / T
```

Density is proportional to pressure divided by temperature (the ideal gas
law), so hotter air at the same pressure is thinner. Where **T** comes from
depends on the **Temperature** setting:

| Temperature setting | T used |
| --- | --- |
| Standard | T_std, the standard temperature for the elevation (σ then depends on elevation only) |
| Manual | the temperature you typed in |
| Sensor | the live reading from the temperature sensor you chose (e.g. the MSpeed's). If it is lost or out of range, Standard is used until it has been back in range for about 10 s. |

**4. Correction factor**

```
k = 1 / √σ
```

Since q = ½ρv², the same pressure in air of density σ × ρ₀ means a true
speed 1/√σ times the sea-level reading.

**5. Applying it**

```
sensor speed = sensor reading × units conversion × Sensor calibration (%) / 100
true speed   = sensor speed × k
```

The **Air density** row on the full-screen gauge and the **Correction**
line in the settings show k as a percentage: k = 1.077 is "+8%".

## Which numbers use which speed

| Uses true speed (sensor × k) | Uses sensor speed |
| --- | --- |
| The speed shown on the gauge and spoken | The stall warning |
| The max speed (marker and callout) | Landing speed (landing callouts, re-arming the stall warning) |
| The overspeed warning | "Callouts start above" and "airspeed alive" |

Why the split:

- **Stall depends on pressure, not true speed.** A wing makes lift from the
  same dynamic pressure that the pitot measures. A model that stalls at
  40 mph at sea level stalls at the same pitot reading at 5,000 ft, even
  though it is then really doing about 43 mph. So you enter your model's
  **sea-level** stall and landing speeds, and the warning compares them with
  the uncorrected sensor speed. On the dial, the stall and landing marks are
  drawn at that speed × k, so they line up with the true-speed arc.
- **Overspeed is about true speed.** Flutter and structural loads depend on
  how fast the model is really going, so the overspeed warning uses true
  speed and its mark is not moved.

The full-screen gauge also shows the uncorrected sensor speed ("RAW") while
correction is on, so you can compare the two.

## Worked example

Field elevation 5,000 ft, Temperature: Standard.

| Step | Calculation | Result |
| --- | --- | --- |
| h | 5,000 × 0.3048 | 1,524 m |
| T_std | 288.15 − 0.0065 × 1,524 | 278.24 K (5.1 °C / 41 °F) |
| δ | (278.24 / 288.15) ^ 5.25588 | 0.832 |
| σ | 0.832 × 288.15 / 278.24 | 0.862 |
| k | 1 / √0.862 | 1.077 (+8%) |

A sensor reading of 100 mph is shown and spoken as **108 mph**. The stall
warning set at 40 mph still goes off when the sensor reads 40 mph.

Same field on a 95 °F (35 °C) day, Temperature: Manual or Sensor:
T = 308.15 K, σ = 0.832 × 288.15 / 308.15 = 0.778, k = 1.134 (+13%), so
100 mph from the sensor is shown as **113 mph**.

## Correction at a glance

k for common field elevations and temperatures (multiply the sensor speed
by it):

| Field elevation | Standard day | 32 °F | 59 °F | 80 °F | 100 °F | 120 °F |
| --- | --- | --- | --- | --- | --- | --- |
| Sea level | 1.000 (59 °F) | 0.974 | 1.000 | 1.020 | 1.039 | 1.057 |
| 1,000 ft | 1.015 (55 °F) | 0.991 | 1.018 | 1.039 | 1.058 | 1.077 |
| 2,000 ft | 1.030 (52 °F) | 1.010 | 1.037 | 1.058 | 1.077 | 1.096 |
| 3,000 ft | 1.045 (48 °F) | 1.028 | 1.056 | 1.077 | 1.097 | 1.117 |
| 5,000 ft | 1.077 (41 °F) | 1.067 | 1.096 | 1.118 | 1.139 | 1.159 |
| 6,000 ft | 1.094 (38 °F) | 1.088 | 1.117 | 1.139 | 1.160 | 1.181 |
| 8,000 ft | 1.128 (30 °F) | 1.130 | 1.160 | 1.184 | 1.205 | 1.227 |
| 10,000 ft | 1.164 (23 °F) | 1.174 | 1.206 | 1.230 | 1.253 | 1.275 |

A cold day at a low field gives k below 1: the air is denser than standard
and the sensor reads high.

## Limits of the model

- **Weather pressure is ignored.** Pressure comes from the field elevation
  and the standard atmosphere. A strong high or low changes real pressure
  by a few percent, which changes the speed by about half that (1–2%).
- **Humidity is ignored.** Humid air is slightly thinner than dry air; on a
  hot, humid day true speed is up to about 1% higher than shown.
- **The model's height above the field is ignored.** The correction uses
  the field elevation. 500 ft above the field changes k by less than 1%.
- **A temperature sensor reads its own surroundings.** One inside a warm
  fuselage, or one that has been sitting in the sun, can read well above
  the outside air and over-correct. Readings outside the setting's limits
  (−29 to 54 °C / −20 to 130 °F) are rejected automatically.
- **GPS speed is not corrected.** GPS measures ground speed, which doesn't
  depend on the air, so correction is turned off for GPS sensors.
- **Don't correct twice.** If your sensor already reports true airspeed,
  leave correction off.

# Speed Gauge

Spoken airspeed callouts, stall and overspeed warnings, and a speedometer
gauge for the JETI **DS-24 II / DC-24 II**.

![Speed Gauge full screen](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/speed-gauge.png)

## What it does

- **Speed callouts** in a clear voice ("eighty five miles per hour"). They
  come more often when the speed is changing and every few seconds below
  landing speed. A continuous switch gives fast number-only callouts.
- **Callouts wait for flight:** nothing is spoken until the model first
  passes "Callouts start above" (default 30 mph), and never below 5 mph.
- **Max speed callout:** "max 201 miles per hour" shortly after each new
  peak.
- **Warnings:** stall (at most twice per slowdown), overspeed and "airspeed
  alive", with stick vibration.
- **Gauge** for the main screen: a speed bar (single size), a small dial
  (double size) or a full-screen dial with stall, overspeed, air density,
  elevation, temperature and raw sensor speed.

  ![Speed Gauge double size, on the main screen](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/speed-gauge-double.png)
  ![Speed Gauge single size, on the main screen](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/speed-gauge-single.png)
- **Air density correction** (optional) shows true airspeed from your field
  elevation and the temperature: standard, entered by hand, or read live
  from a sensor such as the MSpeed's.
- Works with a pitot airspeed sensor (e.g. JETI MSpeed) or a GPS speed.

## Requirements

- JETI **DS-24 II or DC-24 II**, firmware 6.0 or newer. On other DC/DS-24
  transmitters the callouts and warnings work, and the gauge window shows
  a notice instead.
- A telemetry sensor that reports speed.

## Installing

Installing takes a while: Speed Gauge brings its own voice, about 550
files (24 MB), mostly short audio clips, and copying them to the
transmitter is slow. Let JETI Studio finish before disconnecting.

## Setting up

1. Add **Speed Gauge** in *Applications → User Applications*.
2. Open its settings (*Applications → Speed Gauge*):
   - choose your **speed sensor** and the **units**;
   - assign a **callouts on/off switch** (and, if you like, a continuous
     callouts switch);
   - set your model's **landing**, **stall** and **overspeed** speeds;
   - set **Gauge max limit** to your sensor's top speed to use its whole
     range (MSpeed: 350 km/h / 215 mph; MSpeed 450 EX: 450 km/h / 280 mph).
3. Put **Speed Gauge** (single or double size) or **Speed Gauge (full
   screen)** on a page in *Timers/Sensors → Displayed telemetry*.

Every setting has a short explanation on the settings screen. Settings are
saved per model; the max speed resets at each start-up.

## Credits and licenses

- Based on **DFM Speed Announcer** v2.1 by **DFM (Dave McQueeney)**, MIT
  license. Its warning recordings are included unmodified.
- Voice: **Piper** text-to-speech with the voice model **"Amy"** by
  Mycroft / Rhasspy. The voice files (in `/Apps/AG-SpdGa/voice/`) are
  licensed **CC BY-SA 4.0**.
- Speed Gauge itself: MIT license, Copyright (c) 2026 Aaron George.

Source, full credits and license texts:
[github.com/Flazzarious/jeti-lua-apps](https://github.com/Flazzarious/jeti-lua-apps)

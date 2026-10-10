# Flameout Alarm

An urgent, repeating alarm when a turbine flames out, from the engine's RPM
telemetry, and an RPM bar for the main screen, for the JETI
**DS-24 II / DC-24 II**.

![Flameout Alarm on the main screen, armed](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/flameout-alarm-armed.png)

## What it does

- **Flameout alarm:** "Flameout! Flameout! Flameout!" followed by a rapid
  lock tone, repeating every 5 seconds, with three short pulses on both
  sticks. It cuts in over other apps' speech.
- **No false alarms on the ground:** the app arms only once the engine has
  been running at idle (it ignores the start sequence and the start
  overshoot), stays quiet through throttle chops, and disarms silently when
  you move the throttle cut switch to Cut.
- **Auto-restart aware:** while the ECU tries a restart, the alarm keeps
  going; it clears once the engine holds idle again.
- **Telemetry loss is not a flameout:** if the RPM data stops, you hear
  "Engine telemetry lost" instead of the alarm.
- **RPM window:** a segmented RPM bar with a yellow idle marker and the RPM
  as a number (double size), or a compact bar (single size). On a flameout
  the window turns into a red FLAMEOUT banner.

  ![Flameout Alarm during a flameout](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/flameout-alarm-flameout.png)
- **Test alarm switch:** hear the real alarm on the ground, without an
  engine.

**Advisory only.** The app never controls the model or the engine. It does
not replace the ECU's own failsafe, shutdown or auto-restart logic, or your
own monitoring.

## Requirements

- JETI **DS-24 II or DC-24 II**, firmware 6.0 or newer. On other DC/DS-24
  transmitters the alarm works and the window shows text only.
- A turbine whose **RPM reaches the transmitter as a normal telemetry
  sensor**: JetCat, Xicoy and KingTech through their Jeti telemetry adapters
  or a VSpeak/Digitech converter, Swiwin through VSpeak's converter.
  JetCentral, Enjet and Swiwin's direct connection are unconfirmed. RPM shown
  only on a JetiBox screen or inside another maker's app can't be used.

## Setting up

1. Add **Flameout Alarm** in *Applications → User Applications*.
2. Open its settings (*Applications → Flameout Alarm*). Monitoring stays off
   until these three are set:
   - **RPM sensor**: your ECU's RPM. **Live RPM** shows what the app reads;
     if it's off by 10× or 1000×, set **Sensor scale**.
   - **Idle RPM**, in thousands (35.0 = 35,000 RPM), from your ECU's setup.
     Check it against Live RPM with the engine idling.
   - **Cut switch**, assigned while holding the switch in its Cut (engine
     off) position.
   Then tick **Monitoring**.
3. Put **Flameout Alarm** at double size on a page in *Timers/Sensors →
   Displayed telemetry*.
4. Optional: assign a **Test alarm** switch and hold it on to hear the alarm.

The defaults suit most engines: arming at 90% of idle held for 3 s, alarm
below 70% of idle for 1 s, "telemetry lost" after 2 s. If your engine's start
or auto-restart climbs close to 90% of idle before it's running on its own,
raise the arming percentage. Settings are saved per model.

## Credits and licenses

- Voice: **Piper** text-to-speech with the voice model **"Amy"** by
  Mycroft / Rhasspy. The sound files (in `/Apps/AG-FlmOt/`) are licensed
  **CC BY-SA 4.0**.
- Flameout Alarm itself: MIT license, Copyright (c) 2026 Aaron George.

Source, full credits and license texts:
[github.com/Flazzarious/jeti-lua-apps](https://github.com/Flazzarious/jeti-lua-apps)

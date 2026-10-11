# Throttle Setup Wizard

A step-by-step guide to setting up a turbine's throttle on a JETI
**DS-24 II / DC-24 II**, and an app that walks you through it and then
**checks the result** by measuring the throttle signal.

One two-position safety switch selects **engine OFF** (Throttle Cut) or
**engine RUN** (Throttle Idle). The throttle stick then runs from idle to
full. The ECU learns three positions from the transmitter: cut, idle and
full.

![Other Model Options with Throttle Cut and Throttle Idle on the same switch](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-cut-idle.png)

**Bench use only.** Make sure the engine can't start while you do this:
fuel off, or the ECU unplugged from the engine.

## The setup by hand

These steps give the app's default targets: **cut 1000 µs, idle 1200 µs,
full 1900 µs**. That puts idle at 22% of the cut-to-full range, inside what
Xicoy (15–30%) and KingTech (10–30%) ask for. The app works out the values
for other targets.

You need a **two-position switch** for the safety switch. A **JETI
two-position locking switch** for the DS-24 II is highly recommended: you
have to pull the lever out before it will flip, so it can't be bumped to
RUN on the bench or knocked to OFF in flight. Fit it where you can reach it
fast in an emergency, and don't use it for anything else.

### 1. Throttle travel

*Model → Servo Setup*, the throttle output (e.g. channel 1):

| Setting | Value |
| --- | --- |
| Travel − (low end) | 100% |
| Travel + (high end) | 80% |

### 2. Throttle Cut (engine OFF)

*Advanced Properties → Other Model Options → Throttle Cut*:

1. Select **Throttle-Cut switch**. When asked to move a switch, move your
   safety switch **to the position you want for OFF**. That position now
   activates Throttle Cut.
2. Set **Throttle-Cut output value** to **−100%**.

### 3. Throttle Idle (engine RUN)

Same screen, *Throttle Idle*:

1. Select **Throttle-Idle switch**. Move the **same switch to the other
   position (RUN)**.
2. Set **Throttle-Idle offset** to **40%**.

**Check it:** with the switch in RUN, the screen shows **✓** next to
Throttle-Idle switch and **✗** next to Throttle-Cut switch. Flip to OFF and
they swap. If both show the same mark, one of them was assigned in the
wrong position: assign it again.

### 4. Failsafe

The ECU must see signal loss when the transmitter is off or out of range,
and shut the engine down. In the receiver's settings (*Device Explorer →
your receiver*), set the throttle output's failsafe to **Off** (no pulse),
or to a value well below cut (about 1000 µs or less).

Then **test it**: ECU powered, fuel off, switch the transmitter off. The
ECU must report signal loss.

### 5. Check the signal

On the servo monitor the throttle should read:

| Switch | Stick | Monitor | Pulse |
| --- | --- | --- | --- |
| OFF | down | −100% | 1000 µs |
| OFF | **up** | **−100%** | **1000 µs** (cut ignores the stick) |
| RUN | down | −60% | 1200 µs |
| RUN | up | +80% | 1900 µs |

### 6. Teach the ECU

Run your ECU's radio learning ("Teach RC", "Radio setup") and follow its
prompts for cut, idle and full. If the ECU was already taught these exact
values, you can skip this.

## What the app does

- **Asks for** your safety switch, which position is OFF, the throttle stick,
  the throttle output and your targets (default 1000 / 1200 / 1900 µs). It
  refuses targets an ECU can't use, such as idle too close to cut.
- **Shows each step** with the exact values for your targets, and opens the
  right transmitter menu for you.
- **Verifies** by measuring the throttle signal in every switch and stick
  position, and says what's wrong if a step fails (e.g. "Switch RUN gave
  cut. Reverse the switch assignment.").
- **Asks you to test failsafe by hand**, then shows a summary.

The app **can't change any setting itself**: the JETI Lua interface can
only read and open menus, and changing a turbine's throttle from an app
would be unsafe. You make each change; the app tells you exactly what and
then proves it worked. Once the setup passes, remove the app from the
model. Nothing at flight time depends on it.

## Credits and licenses

Throttle Setup Wizard: MIT license, Copyright (c) 2026 Aaron George.

Source, full credits and license texts:
[github.com/Flazzarious/jeti-lua-apps](https://github.com/Flazzarious/jeti-lua-apps)

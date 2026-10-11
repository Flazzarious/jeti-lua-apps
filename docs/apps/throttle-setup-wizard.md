# Throttle Setup Wizard

Set up a turbine's throttle on one **safety switch**, and **prove it works**
before the engine ever starts. For the JETI **DS-24 II / DC-24 II**.

![Other Model Options with Throttle Cut and Throttle Idle on the same switch](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-cut-idle.png)

## One switch instead of the trim

Many pilots still start and stop their turbine the old way: **throttle trim
fully down to stop, trim fully up to arm and idle**, clicking the digital
trim up and down every flight. It works, but it's slow, easy to get wrong,
and slow to shut down in an emergency. Xicoy's manual warns that digital
trims cause an **unstable idle and a delay in shutting off the engine**,
and tells you to use the transmitter's throttle cut switch instead.

The JETI way is simpler and safer: **one two-position safety switch**.

- **CUT**: Throttle Cut, engine off. The stick does nothing.
- **RUN**: Throttle Idle, the engine may run. The stick goes from idle to
  full.

One flick stops the engine, every time, wherever the stick and trim are.
All you have to do is **set up that switch correctly once**. That's the
part people find tricky, and that's what this app is for.

## What the app does for you

You make each change on the transmitter; the app tells you exactly what to
enter, opens the right menu, and then **checks the result by measuring the
throttle signal**. Even if you set everything up by hand (or the model is
already set up), run its check:

1. **Proof, not assumption.** It measures the real throttle signal with the
   switch at CUT and RUN and the stick at idle and full, and shows pass or
   fail against your targets. A setup that looks right in the menus can
   still be wrong, such as a switch assigned the wrong way round.
2. **It tests the dangerous case.** With the switch at CUT and the stick at
   full, the throttle must stay at cut. That is the failure that matters
   most, and it's easy never to check.
3. **It tells you what to fix.** Not just "fail", but which setting:
   "Switch RUN gave cut: reverse the switch assignment", "Full off by
   +40 us: check Max positive", "Throttle reversed: check servo reverse",
   "Output doesn't move: choose the throttle output".
4. **Accurate readings.** It waits until the stick is fully at the end and
   held still, then averages the signal, so a stick at 95% doesn't give a
   false result.
5. **The right values for your ECU.** One proven setup, the same for every
   model: only the Throttle-Cut value changes, −125% for Xicoy (which
   wants idle well clear of cut) and −100% for everything else. No
   guesswork, no trial and error.
6. **Failsafe isn't forgotten.** It won't call the setup complete until you
   confirm a hand test of failsafe, the one safety setting no transmitter
   can measure.
7. **A record.** The summary keeps the switch, ECU type, measured values and
   date for the model, and clears itself if you change the setup.
8. **The same check every time.** Every new model gets the same check, the
   same way, in a couple of minutes.

The app **can't change any setting itself**: the JETI Lua interface can
only read and open menus, and changing a turbine's throttle from an app
would be unsafe. Once the setup passes, remove the app from the model.
Nothing at flight time depends on it.

**Bench use only.** Make sure the engine can't start while you set up or
check: fuel off, or the ECU unplugged from the engine.

## Using the app

1. Add **AG-TrbSt** in *Applications → User Applications*, then open
   **Throttle Setup Wizard** in *Applications*.
2. **Setup inputs:** choose your safety switch and your throttle stick
   (assign it as **proportional, P**), put the switch at CUT and the stick
   at idle (down) and press **Learn**. Choose the throttle output and your
   ECU: **Xicoy**, or **Other** for everything else. Other has been tested
   with KingTech and Swiwin ECUs and should work with most others.
3. **Guided setup:** five steps, each with the exact values and an **Open**
   button for the right menu. Skip this if the model is already set up.
4. **Verify:** follow the prompts for each switch and stick position.
5. **Failsafe:** test it by hand and confirm. The summary then shows
   "Setup complete" and the next step: remove the app, then **re-learn your
   ECU** (Teach RC).

## The setup by hand

One setup for every turbine. Only the **Throttle-Cut output value**
depends on the ECU:

| Setting | Xicoy | Other ECUs |
| --- | --- | --- |
| Max negative / Max positive | −80% / 80% | −80% / 80% |
| Throttle-Cut output value | **−125%** | **−100%** |
| Throttle-Idle offset | 20% | 20% |
| Signal: cut / idle / full | 1000 / 1200 / 1900 µs | 1100 / 1200 / 1900 µs |

**Other ECUs:** tested with **KingTech** and **Swiwin**, and should work
with most other ECUs that learn their throttle range from the receiver
(JetCat, JetCentral and others). **Xicoy** asks for idle at 15–30% of the
cut-to-full range, so it gets −125%, which puts idle at 22%.

You need a **two-position switch** for the safety switch. A **JETI
two-position locking switch** for the DS-24 II is highly recommended: you
have to pull the lever out before it will flip, so it can't be bumped to
RUN on the bench or knocked to CUT in flight. Fit it where you can reach it
fast in an emergency, and don't use it for anything else.

![The short silver locking switch SF, used as the throttle safety switch, next to SE on a DS-24 II](https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-switch.jpg)

*Example: the short silver locking switch **SF** as the safety switch,
shown in RUN (Throttle Cut off, engine allowed to run).*

### 1. Throttle travel

*Model → Servo Setup*, then choose your throttle output in **Servo No.**
(e.g. "Throttle (1)" or "Engine 1 (1)"):

| Setting | Value |
| --- | --- |
| Max negative (low end) | −80% |
| Max positive (high end) | 80% |

Leave **Max negative limit** and **Max positive limit** at their defaults
(−125% / 125%), **Subtrim** at 0% and **Reverse** at No.

### 2. Throttle Cut (CUT position)

*Advanced Properties → Other Model Options → Throttle Cut*:

1. Select **Throttle-Cut switch**. When asked to move a switch, move your
   safety switch **to the position you want for CUT**. That position now
   activates Throttle Cut.
2. Set **Throttle-Cut output value** to **−100%**, or **−125%** for a
   Xicoy ECU.

<img src="https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-cut-100.png" width="240" alt="Throttle Cut on switch Sf with output value -100%, for most ECUs">
<img src="https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-cut-125-xicoy.png" width="240" alt="Throttle Cut on switch Sf with output value -125%, for Xicoy ECUs">

*Left: −100% for most ECUs. Right: −125% for Xicoy. The ✓ next to
Throttle-Cut switch means the switch is at CUT right now.*

### 3. Throttle Idle (RUN position)

Same screen, *Throttle Idle*:

1. Select **Throttle-Idle switch**. Move the **same switch to the other
   position (RUN)**.
2. Set **Throttle-Idle offset** to **20%**.

**Check it:** with the switch in RUN, the screen shows **✓** next to
Throttle-Idle switch and **✗** next to Throttle-Cut switch. Flip to CUT and
they swap. If both show the same mark, one of them was assigned in the
wrong position: assign it again.

Leave the throttle trim centered (or turned off for throttle): the switch
now does the trim's old job.

### 4. Failsafe

If the receiver loses the transmitter's signal (out of range, a flat
transmitter battery, interference), it must not keep the throttle where it
was. The ECU has to see the signal disappear, so it can shut the engine
down.

*Model → Device Explorer → your receiver (e.g. REX12A) → Configuration →
Fail-Safe*:

1. **Fail-Safe**: **Enabled**. Leave **Fail-Safe Delay** at **1.5s** unless
   your ECU's manual says otherwise.
2. Find the **OutPin** your ECU's throttle lead is plugged into (usually
   the same number as the throttle output, e.g. **OutPin 1**).
3. Set its **Mode** to **Out OFF** (no pulse). With no signal, the ECU
   runs its own shutdown. This is the simplest and safest choice.
   - *Never leave the throttle on **Hold***: the engine would stay at
     whatever throttle it had when the link was lost.
   - *Don't use **Fail-Safe** mode with **Value 0%***: 0% is mid-throttle
     (1500 µs).

<img src="https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-rx-config.png" width="240" alt="REX12A Configuration menu with Fail-Safe selected">
<img src="https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/docs/apps/img/throttle-setup-wizard-failsafe-out-off.png" width="240" alt="REX12A Fail-Safe screen: Fail-Safe Enabled, delay 1.5s, OutPin 1 mode Out OFF">

*The receiver's Configuration menu, and its Fail-Safe screen with the
throttle on OutPin 1 set to Out OFF.*

Then **test it**: ECU powered, fuel off, switch the transmitter off. The
ECU must report signal loss.

### 5. Check the signal

On the servo monitor the throttle should read:

| Switch | Stick | Other ECUs | Xicoy |
| --- | --- | --- | --- |
| CUT | down | −80% (1100 µs) | −100% (1000 µs) |
| CUT | **up** | **−80% (1100 µs)** | **−100% (1000 µs)** (cut ignores the stick) |
| RUN | down | −60% (1200 µs) | −60% (1200 µs) |
| RUN | up | +80% (1900 µs) | +80% (1900 µs) |

Or let the app do this for you: that's its **Verify** step.

### 6. Teach the ECU

Run your ECU's radio learning ("Teach RC", "Radio setup") and follow its
prompts for cut, idle and full: switch at CUT for cut, RUN with the stick
down for idle, RUN with the stick up for full. **Always do this** after
setting up or changing these values, even if the ECU was taught before.

### 7. Voice callouts (optional)

Hear **"Turbine off"** when you flip the safety switch to CUT and
**"Turbine on"** when you flip it to RUN. The transmitter plays them
itself, so they keep working after you remove the app.

1. In the app, open **Voice callouts** and press **Copy**. It puts
   `TurbOff.wav` and `TurbOn.wav` in the card's `/Audio` folder. Files
   already there are never replaced.
2. Press **Open** to go to *Sounds on event*. Add your safety switch at
   **CUT** with `TurbOff.wav`, and at **RUN** with `TurbOn.wav`.
3. If you already have callouts for this switch, you'll see them there:
   keep them, swap in these files, or use your own.

The callouts use the same voice as the author's Speed Gauge and Flameout
Alarm apps.

## Credits and licenses

Throttle Setup Wizard: MIT license, Copyright (c) 2026 Aaron George.

Voice callouts: generated with **Piper** text-to-speech using the voice
model **"Amy"** by Mycroft / Rhasspy. The sound files (in
`/Apps/AG-TrbSt/`, and the copies in `/Audio`) are licensed
**CC BY-SA 4.0**.

Xicoy's advice on digital trims is from the Xicoy TurboJet Engines User
Manual (v1.5, 2024); idle ranges from the Xicoy and KingTech manuals.

Source, full credits and license texts:
[github.com/Flazzarious/jeti-lua-apps](https://github.com/Flazzarious/jeti-lua-apps)

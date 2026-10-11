---
name: jeti-voice
description: Generate spoken voice callouts (WAV files) for a JETI Lua app in this repo with Piper's "Amy" voice, so every app sounds the same. Use this whenever an app needs new speech or audio files: callouts, announcements, warnings, alarms, "say X when Y", voice prompts for a switch, or regenerating/changing an existing app's voice. Also use it when wiring those files into an app (playFile, file checks, fallbacks) or into the transmitter's Sounds on event, and for the license credits the voice requires.
---

# JETI voice callouts

Every app in this repo speaks with one voice: Piper text-to-speech with the
US English **"Amy"** model (`en_US-amy-medium`). Speed Gauge (`AG-SpdGa`),
Flameout Alarm (`AG-FlmOt`) and Throttle Setup Wizard (`AG-TrbSt`) all use
it. New callouts should too, so a pilot hears one consistent system.

The generators live in `tools/voice/`. They share `make_voice.py`'s helpers;
each app has its own small script. Read `tools/voice/README.md` for the
history and options of the existing ones.

## 1. Decide the phrases

For each callout, settle:

- **The words**, short and unambiguous over engine noise. Two to four words
  is typical ("Turbine off", "Engine relit").
- **The file name**: 8.3, e.g. `TurbOff.wav`. JETI names are short, and if
  the pilot will pick the file in a transmitter menu, the name should say
  what it is.
- **The delivery**:
  - *Calm* (announcements, confirmations): speed 1.5, no effects. Example:
    `make_turbine.py`.
  - *Urgent* (alarms): pitch-up, presence boost and compression, optionally
    with a lock tone and fixed-length cycles. Example: `make_flameout.py`.
- **A length limit** for the self-check, from how the app uses it (e.g. a
  switch callout should end before the next flick: about 1.5 s; Speed
  Gauge's numbers must fit 1.3 s).
- **Where it plays**: from the app (`system.playFile`), or by the
  transmitter's *Sounds on event* (the app only copies the files to
  `/Audio`, see section 5).

Agree these with the user before generating; they'll listen to the result.

## 2. Write the generator

Create `tools/voice/make_<app>.py` by copying the closest existing script:

- `make_turbine.py`: the minimal template (a list of phrases, calm pace,
  `CREDITS.txt`, a length self-check). Start here for most apps.
- `make_flameout.py`: urgent delivery (filters, compressor), a synthesized
  tone, and assembling exact-length cycles.

Keep these conventions, which the existing scripts share:

- MIT header (`Copyright (c) 2026 Aaron George`, `SPDX-License-Identifier:
  MIT`) and a docstring naming the files it writes and the spec/FR they
  serve.
- Import the helpers from `make_voice.py` (`synthesize`, `trim`,
  `normalize`, `resample`, `write_wav`, `write_text`, `PEAK`) by adding
  `tools/voice` to `sys.path`. **Don't modify `make_voice.py`**: Speed
  Gauge's 512 files depend on it.
- Arguments: `--model` (required), `--out` (default
  `src/Apps/AG-xxxxx`), `--rate` (default 22050), and `--speed` if the
  pace may need tuning.
- Output: mono, 16-bit, 22.05 kHz WAV, trimmed of silence (20 ms kept),
  peak-normalized to −1 dBFS. The DS-24 II plays this format (verified
  with Speed Gauge, 2026-10-03).
- Write `CREDITS.txt` into the output folder (copy the text from an
  existing script and change the app name and the list of processing).
- Self-check at the end: every file exists and fits its length limit.
  Exit 1 on failure.
- Files go in the app's own asset folder, `src/Apps/AG-xxxxx/`
  (constitution V). Code refers to them as `/Apps/AG-xxxxx/<file>`.

Check it compiles: `python -m py_compile tools/voice/make_<app>.py`.

## 3. Generate

Piper is installed from `tools/voice/requirements.txt`
(`python -m pip install -r tools/voice/requirements.txt`). The voice model
is **not** in the repo: `en_US-amy-medium.onnx` and its `.onnx.json` live
in a folder outside it (download from Hugging Face,
`rhasspy/piper-voices`, `en/en_US/amy/medium/`). Ask the user for the path
if you don't know it, then run:

```powershell
python tools/voice/make_<app>.py --model C:\path\to\en_US-amy-medium.onnx
```

Piper varies slightly between runs. If a length check fails, raise
`--speed` a little (e.g. 1.55) rather than loosening the limit.

## 4. Review and commit

- **The user listens on the PC first.** Same voice and pace as the other
  apps? Only they can approve it; leave that task unticked until they do.
- **Commit the generated files** with the app (they're part of the
  install). They are licensed **CC BY-SA 4.0**, not MIT.
- **Credit the voice everywhere constitution VIII requires**: the asset
  folder's `CREDITS.txt`, `CREDITS.md` (add a section for the app), the
  README's app section, and the app's own settings or info screen (a
  `FONT_MINI` line such as "Voice: Piper, Amy (CC BY-SA 4.0).").
- Add a section for the new script to `tools/voice/README.md`.

## 5. Use the files in the app

**Played by the app** (Speed Gauge, Flameout Alarm):

- `system.playFile("/Apps/AG-xxxxx/file.wav", AUDIO_QUEUE)` or
  `AUDIO_IMMEDIATE` for alarms (it cuts in over other speech). Foreground
  playback is WAV only.
- **Check the files exist in `init()`**, not per play: `io.open` the
  absolute path, then the same path without its leading "/" (the JETI
  Studio emulator needs relative paths; the transmitter takes absolute
  ones). Close what you open.
- **If files are missing, degrade quietly**: skip the callout or fall back
  (Flameout uses beeps), and say so on the settings screen. Never error.

**Played by the transmitter's Sounds on event** (Throttle Setup Wizard):

- The app never plays them. It copies them from its asset folder to
  `/Audio` on the pilot's request (JETI's audio picker lists `/Audio` and
  `/Audio/<lang>`), never overwriting an existing file, in small chunks
  across `loop()` calls, verifying the size and deleting a bad copy. Then
  it opens the menu with `system.openExternal(":soundEvent")` and says what
  to assign. See `src/Apps/AG-TrbSt.lua` (Voice callouts) and research R15
  in `specs/002-turbine-throttle-setup/research.md`.
- This keeps callouts working after the app is removed from the model, and
  existing assignments stay visible in JETI's own menu.

## 6. Test where sound actually plays

The JETI Studio emulator plays **no** Lua audio (`playFile` is silent; the
Emulated Telemetry app just prints a line). So:

- In the emulator, check only the logic: file found / missing messages,
  which file would play.
- On the transmitter, check that each file plays, sounds right, and isn't
  cut off, and (for Sounds on event) that the picker lists the files.
  These are MANUAL tasks for the user.

Record anything new about playback or file handling in
`docs/jeti-api-notes.md`.

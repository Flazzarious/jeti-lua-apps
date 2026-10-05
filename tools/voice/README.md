# Speed Gauge voice generator

Speed Gauge speaks its callouts, warnings and startup announcement in one
voice, Piper's US English "Amy" (spec 001, FR-030). The voice is a set of
512 short WAV files in `src/Apps/AG-SpdGa/voice/`:

- `0.wav` … `500.wav`: the numbers;
- `mph`, `kmh`, `kt`, `ms`, `fts`, `pct`: the units and "percent";
- `stall`, `over`, `alive`, `stallat`, `cal`: the warning and startup
  phrases.

The files are **committed** (FR-035, since 2026-10-03), so a normal deploy
includes them. Re-run the generator only to change the voice or its speed.
Without them the app still works, using the transmitter's voice and DFM's
original recordings.

## Generate

1. Python 3.9 or newer, then install Piper (this repo pins its version):

   ```powershell
   python -m pip install -r tools/voice/requirements.txt
   ```

2. Download the voice model from Hugging Face,
   [`rhasspy/piper-voices`](https://huggingface.co/rhasspy/piper-voices),
   folder `en/en_US/amy/medium/`: both `en_US-amy-medium.onnx` and
   `en_US-amy-medium.onnx.json`. Put them together in a folder **outside**
   the repository.

3. Run from the repository root:

   ```powershell
   python tools/voice/make_voice.py --model C:\path\to\en_US-amy-medium.onnx
   ```

   It takes a few minutes and prints its progress.

| Option | Default | Meaning |
| --- | --- | --- |
| `--model` | (required) | Path to the `.onnx` file |
| `--out` | `src/Apps/AG-SpdGa/voice` | Output folder |
| `--rate` | `22050` | Sample rate: 16000, 22050 or 44100 Hz. Use 44100 if the transmitter won't play 22.05 kHz (research R13) |
| `--speed` | `1.5` | Speaking speed relative to Piper's own pace. 1.5 makes every number up to 199 fit SC-009's 1.3 s (longest: 1.28 s, 2026-10-03). 1.0–1.3 sounded slow or ran over. Piper varies slightly between runs: if the self-check fails, try 1.55 |

Each file is mono and 16-bit, trimmed of leading and trailing silence
(20 ms kept at each end), and normalized to the same peak level (−1 dBFS).
The script also writes `CREDITS.txt` and, last, `index.txt` (voice, rate,
speed, file count). A missing `index.txt` means the run didn't finish.

Re-run it at any time to regenerate the set or try another option; it
overwrites the files in place.

## Self-check

At the end the script checks that all 512 files exist and prints the
longest number-only file up to 199. It exits with code 1 if a file is
missing or that file is longer than 1.3 s, because short callouts must fit
the 2-second interval (SC-009). If that happens, try `--speed 1.1`.

## Deploy

The normal deploy copies the voice with the app's asset folder (see
`specs/001-speed-gauge/quickstart.md`):

```powershell
Copy-Item src\Apps\AG-SpdGa $dst -Recurse -Force
```

## Licensing

- **Voice model:** "Amy" (`en_US-amy-medium`) by Mycroft / Rhasspy is
  licensed CC BY-SA 4.0, and the license of the recordings it was trained on
  is undocumented. The committed set in `src/Apps/AG-SpdGa/voice/` is
  therefore CC BY-SA 4.0, not MIT; keep its `CREDITS.txt` with it.
- **Piper:** the `piper-tts` package is GPL-3.0-or-later
  ([OHF-Voice/piper1-gpl](https://github.com/OHF-Voice/piper1-gpl)),
  continuing the original MIT-licensed
  [rhasspy/piper](https://github.com/rhasspy/piper). It is only installed
  locally to run the generator; no Piper code is part of this repository or
  the app.
- **This script:** MIT, like the rest of the repository.

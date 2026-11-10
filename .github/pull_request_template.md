## What and why

<!-- What this changes and why. For a feature: link its specs/NNN-name/ folder. For a fix: the issue it closes. -->

## How it was tested

<!-- Emulator scenarios, and/or transmitter model and firmware, on a test model. Say what you couldn't test. -->

## Checklist

- [ ] Into `develop` (never `main`), from a branch off `develop`
- [ ] `python tools/check.py` passes and LuaLS shows no errors
- [ ] Nothing affects flight: no `registerControl`, `setControl`, `setProperty` or outputs
- [ ] No released app file renamed
- [ ] `SIM` and debug switches left `false`
- [ ] Credits and license notices kept or added where work builds on others' (see CONTRIBUTING.md)

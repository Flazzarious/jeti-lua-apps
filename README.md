# Jeti Lua Apps

A collection of Lua apps for the JETI DS-24 II transmitter, built with a
spec-driven workflow (GitHub Spec Kit + Claude Code) in VS Code.

## Apps

| App | Script | Status | Spec | Based on |
| --- | --- | --- | --- | --- |
| Speed Gauge | [`AG-SpdGa.lua`](src/Apps/AG-SpdGa.lua) | Released (0.3.0) | [001](specs/001-speed-gauge/spec.md) | DFM Speed Announcer by Dave McQueeney (MIT) |

To put an app on your transmitter, see [Installing apps](#installing-apps).

### Speed Gauge

Speaks the model's airspeed, warns at stall and overspeed, and shows speed on
a round gauge, with optional air-density correction (field elevation plus
standard, manual or sensor temperature). DS-24 II / DC-24 II only. Based on
DFM Speed Announcer by Dave McQueeney. Full behavior:
[spec 001](specs/001-speed-gauge/spec.md).

Speed Gauge speaks in its own voice (Piper "Amy"), in
`src/Apps/AG-SpdGa/voice/`. Those files are licensed CC BY-SA 4.0, not MIT
(see [CREDITS.md](CREDITS.md)); [`tools/voice/`](tools/voice/README.md)
regenerates them. Without them the app works in the transmitter's voice.

Apps here are for telemetry, timers, announcements and displays only. Nothing
in this repo may control surfaces, throttle or any flight function. See the
constitution: [`.specify/memory/constitution.md`](.specify/memory/constitution.md).

## Layout

```
.specify/memory/constitution.md   Rules every spec, plan and task inherits
.luarc.json                       LuaLS config (Lua 5.3, globals are errors)
.vscode/                          Editor settings, recommended extensions
types/jeti.lua                    LuaLS stubs for the Jeti API (v1.5 + notes)
docs/jeti-api-notes.md            The API facts that shape how apps are written
docs/examples/style/HELLO.lua     Style reference app (not deployed)
docs/examples/                    Other reference code, incl. official Jeti demos
docs/vendor/                      Generated full API text (gitignored)
specs/NNN-<feature>/              spec.md, plan.md, tasks.md per feature
src/Apps/                         Mirrors /Apps on the transmitter SD card
  AG-xxxxx.lua                    One script per app
  AG-xxxxx/                       That app's sounds, images, language files
  lib/ag_xxxxx.lua                Shared modules, require("ag_xxxxx")
catalog/apps.json                 JETI Studio app catalog (generated, see Installing apps)
catalog/sources.json              Hand-edited app list the catalog is built from
tools/catalog/make_catalog.py     Builds and checks catalog/apps.json
tools/check.py                    Syntax, forbidden-API, naming, encoding checks
tools/pdf2md.py                   Converts Jeti's API PDF for local reference
tests/test_ag_dens.lua            Optional desktop test for the density module (any Lua 5.3)
tools/probe/PROBE.lua             Dev tool: prints the screen/window sizes in the emulator
```

### Multiple apps, one repo

- **Names.** Every app script is `AG-` plus up to 5 letters or digits, so it
  fits the transmitter's 8.3 limit and stays grouped apart from other
  authors' apps (`DFM-*`, `RCT-*`). The menu name is separate and can be
  anything. A released filename is never changed, because the transmitter
  ties each model's settings for an app to its filename.
- **Shared code** goes in `src/Apps/lib/` as `ag_xxxxx.lua`. One copy is loaded
  and shared by every app, so modules hold no state of their own.
- **Specs are per feature, not per app.** A new app and a later change to an
  existing app each get the next number in `specs/`.
- **Installing.** An app is its script, its `AG-xxxxx/` folder, and the
  `lib/` modules it uses. See [Installing apps](#installing-apps).

## Installing apps

There are two ways to get an app onto the transmitter: from JETI Studio's app
catalog, or by copying files by hand. Both need the transmitter connected to
the PC by USB. The DS-24 II then appears as a drive (e.g. `E:`) holding its SD
card.

> **Requires a DS-24 II or DC-24 II** (firmware 6.x). Speed Gauge's display is
> designed for the 24 II screen.

### Option A: JETI Studio app catalog

This repo publishes a catalog that JETI Studio's Lua app manager can read.
Every file in it is downloaded from the app's release tag on GitHub (e.g.
`AG-SpdGa-v0.3.0`) and checked by size and SHA-1 before it is installed.

1. In JETI Studio, open the Lua app manager's sources, the same list that
   holds JETI's own catalog and LeonAirRC's, and add:
   ```
   https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps/main/catalog/apps.json
   ```
   JETI Studio keeps this list in its settings as `AppSources`.
2. Connect the transmitter. Speed Gauge appears in the app list; install it.
   JETI Studio copies every file to the right place.
3. On the transmitter, add the app (step 4 of Option B).

Updates show up in the app manager after each release.

### Option B: copy by hand

The repo's `src/Apps/` folder mirrors the transmitter's `Apps` folder, so
copying is a straight mirror. For Speed Gauge:

| Copy from the repo | To the transmitter |
| --- | --- |
| `src\Apps\AG-SpdGa.lua` | `E:\Apps\AG-SpdGa.lua` |
| `src\Apps\AG-SpdGa\` (the whole folder: sounds, the `voice` subfolder, images, credits) | `E:\Apps\AG-SpdGa\` |
| `src\Apps\lib\ag_dens.lua` and `ag_gauge.lua` | `E:\Apps\lib\` |

1. Get the files from a release: on GitHub, choose the tag (e.g.
   `AG-SpdGa-v0.3.0`) and download the ZIP, or `git checkout AG-SpdGa-v0.3.0`.
   Don't install from `develop` or a feature branch.
2. Copy the three items above. Copying all of `src\Apps\` over `E:\Apps\`
   does the same thing, and also installs any other apps in the repo. Keep
   the folder names exactly as they are: the app plays its sounds from
   `/Apps/AG-SpdGa/...`, and a renamed folder means silent warnings.
3. Eject the drive in Windows before unplugging the cable.
4. On the transmitter: **Applications → User Applications → +**, choose
   Speed Gauge, then open it from the Applications menu to set it up.

**Updating** works the same way: copy the new files over the old ones. Your
settings are kept, because the transmitter stores them under the script's
filename, which never changes.

**In the emulator**, copy the same items into
`%LOCALAPPDATA%\JETI-Studio\Emulator\Apps\`, then refresh the apps
(Applications → User Applications → F1 → F3).

## First-time setup

1. **VS Code extensions.** Open the folder and accept the recommended
   extensions (Lua by sumneko, EditorConfig). LuaLS reads `.luarc.json`, so
   diagnostics also work from the command line and for agents.
2. **Spec Kit.** This repo already contains the constitution. Commit before
   initializing, because `--force` may replace managed files:
   ```bash
   uv tool install specify-cli
   specify init --here --force --integration claude --script ps
   git diff .specify/memory/constitution.md   # restore with git checkout if replaced
   ```
3. **Full API reference (optional, recommended for agents).**
   ```bash
   pip install pypdf
   python tools/pdf2md.py
   ```
   This writes `docs/vendor/jeti-api.md`. It's gitignored because the PDF is
   JETI's copyrighted document.
4. **Lua 5.3 compiler (optional).** `tools/check.py` uses `luac5.3`/`luac` from
   PATH for syntax checks and skips that step with a warning if absent.

## Workflow

1. `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-implement`
   for each feature under `specs/`.
2. Implement in `src/Apps/` following the naming rules above.
3. `python tools/check.py` must pass. LuaLS must show no errors.
4. Run in the JETI Studio DS-24 II emulator: copy the app into
   `%LOCALAPPDATA%\JETI-Studio\Emulator\Apps` (see
   [Installing apps](#installing-apps), Option B). For sensors, use LeonAirRC's
   [Emulator Telemetry](https://github.com/LeonAirRC/Jeti-Lua-Apps) app.
   Remember the emulator has `os`, `debug` and `coroutine`; the radio does not.
5. Copy the app to `/Apps` on the transmitter's SD card (it mounts as USB mass
   storage; see [Installing apps](#installing-apps)). Optionally ship `.lc` bytecode compiled by the matching
   firmware/emulator version; `.lc` files are never committed.
6. First real run on a dedicated test model.

## Branching

| Branch | From | Merges into | Holds |
| --- | --- | --- | --- |
| `main` | | | Released versions only. Every commit is a release, tagged |
| `develop` | `main` | `main`, by pull request only | Finished features waiting for a release |
| `feature/NNN-name` | `develop` | `develop`, by pull request | One spec's work, e.g. `feature/001-speed-gauge` |

`main` is updated **only** by a pull request from `develop`; GitHub enforces
this (a ruleset on `main` and the `PR source is develop` check in
`.github/workflows/main-pr-source.yml`). Version bumps and last fixes happen
on the feature branch or on `develop` before that pull request; there are no
release or hotfix branches.

- A feature branch uses the same `NNN-name` as its `specs/` folder, and
  carries that spec from `/speckit-specify` through `/speckit-implement`.
- Merge a feature into `develop` only after `tools/check.py` passes and the
  quickstart's emulator scenarios have been run.
- Tag releases on `main` as `<script>-v<version>`, e.g. `AG-SpdGa-v1.0.0`,
  matching the app's `version` field. Each app has its own version.

### Releasing an app (and its catalog entry)

The catalog points at release tags, so it is regenerated **before** the
release merges and checked **after** it is tagged:

1. On the feature branch, set the new `version` in the app script and run
   `python tools/catalog/make_catalog.py`. It reads each app's version,
   hashes its committed files, and writes `catalog/apps.json` with URLs for
   the tag the release will get. Commit the catalog with the release.
2. Merge the feature into `develop`, then `develop` into `main` by pull
   request.
3. Tag the merge commit on `main` `<script>-v<version>` and push the tag,
   immediately: until the tag exists, the catalog's links don't resolve.
4. Run `python tools/catalog/make_catalog.py --check`. It fails if the tag is
   missing, or if any tagged file doesn't match the catalog's size and hash.

A new app is added to the catalog by adding it to `catalog/sources.json`.
That entry holds the menu name, author, description link and preview icon;
the script works out the files, including the `lib/` modules the app
`require`s.
- Never commit directly to `main` or `develop`.

## Style reference: HELLO.lua

`docs/examples/style/HELLO.lua` is a small flight timer started by a
user-assigned switch. It is not deployed, but `check.py` and LuaLS still check
it. It demonstrates the conventions every app follows: lifecycle, a settings
form, `pSave`/`pLoad`, a telemetry window, rate-limited `loop()` and cached
display strings.

## API coverage

`types/jeti.lua` follows the JETI DC/DS Lua API v1.5 (December 2019). DS-24 v2
firmware may add functions that aren't in it. Entries marked `UNVERIFIED` were
inferred where the PDF is silent. When a newer API document turns up, update
the stubs and `docs/jeti-api-notes.md` together.

## Credits

Speed Gauge is based on **DFM Speed Announcer** by DFM (Dave McQueeney),
[github.com/davidmcq137/JetiLuaDFM](https://github.com/davidmcq137/JetiLuaDFM).
Much of its behavior comes from that app, and this rewrite wouldn't exist
without it. See [CREDITS.md](CREDITS.md) for all credits and license notices,
including JETI's demos.

## License

MIT. See [LICENSE](LICENSE). Anyone may use, modify and share these apps, as
long as they keep the copyright and license notice. Apps derived from other
people's work also carry those authors' notices, listed in
[CREDITS.md](CREDITS.md). Third-party code copied unmodified into
`docs/examples/` (JETI's demos, DFM Speed Announcer) keeps its own license,
stated in each file.

## References

- Official apps and demos: https://github.com/JETImodel/Lua-Apps
- Community apps and emulator telemetry: https://github.com/LeonAirRC/Jeti-Lua-Apps
- Best practices: https://www.rc-thoughts.com/2016/09/lua-for-jeti-considerations-and-best-practices/
- Lua 5.3 manual: https://www.lua.org/manual/5.3/

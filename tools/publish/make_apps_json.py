"""make_apps_json.py - build Apps.json, the JETI Studio app source file.

Copyright (c) 2026 Aaron George
SPDX-License-Identifier: MIT

JETI Studio (and the Jeti App Manager) install Lua apps from a JSON source
file that users add under File -> Configuration, one URL per line. For each
app it lists the author, version, a preview image, a Markdown description,
the minimum firmware, and every file with the transmitter folder it goes to.
Format: https://github.com/nightflyer88/JetiAppManager#source-file

Each app's files are read from its release tag, and their download links
point at that tag, so users always install exactly the released version.
The description and preview image come from `main`. Run from the repo root
after tagging a release, then commit Apps.json and merge it to `main`:

    python tools/publish/make_apps_json.py

Standard library only.
"""

import json
import subprocess
from pathlib import Path
from urllib.parse import quote

REPO = Path(__file__).resolve().parents[2]
RAW = "https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps"

# One entry per published app. "tag" is its release tag; "paths" are the
# repo paths (files or folders) that make up the app on the transmitter.
APPS = [
    {
        "name": "Speed Gauge",
        "script": "AG-SpdGa",
        "tag": "AG-SpdGa-v0.3.0",
        "author": "Aaron George (based on DFM Speed Announcer by Dave McQueeney)",
        "requiredFirmware": 6.0,
        "description": "docs/apps/speed-gauge.md",
        "previewImg": "docs/apps/img/speed-gauge.png",
        "paths": [
            "src/Apps/AG-SpdGa.lua",
            "src/Apps/AG-SpdGa",
            "src/Apps/lib/ag_dens.lua",
            "src/Apps/lib/ag_gauge.lua",
        ],
    },
]


def git(*args):
    return subprocess.run(["git", *args], cwd=REPO, check=True,
                          capture_output=True, text=True).stdout


def url(ref, path):
    return f"{RAW}/{quote(ref)}/{quote(path)}"


def app_version(tag, script):
    """APP_VERSION from the app's source at its tag, e.g. "V0.3.0"."""
    for line in git("show", f"{tag}:src/Apps/{script}.lua").splitlines():
        if line.startswith("local APP_VERSION"):
            return "V" + line.split('"')[1]
    raise SystemExit(f"APP_VERSION not found in {script}.lua at {tag}")


def entry(app):
    tag = app["tag"]
    files = git("ls-tree", "-r", "--name-only", tag, "--", *app["paths"]).split()
    if not files:
        raise SystemExit(f"no files for {app['name']} at {tag}")
    sources, dests = [], []
    for f in sorted(files):
        # src/Apps mirrors /Apps on the transmitter's SD card.
        dest = "/" + str(Path(f).parent.relative_to("src")).replace("\\", "/")
        sources.append(url(tag, f))
        dests.append(dest)
    return {
        "author": app["author"],
        "version": app_version(tag, app["script"]),
        "previewImg": url("main", app["previewImg"]),
        "description": url("main", app["description"]),
        "requiredFirmware": app["requiredFirmware"],
        # DC/DS-24 family only: the gauge targets the DS-24 II.
        "sourceFile24": sources,
        "destinationPath": dests,
    }


def main():
    out = {app["name"]: entry(app) for app in APPS}
    path = REPO / "Apps.json"
    # open() with newline= (Path.write_text has none before Python 3.10).
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    for name, e in out.items():
        print(f"{name} {e['version']}: {len(e['sourceFile24'])} files")
    print(f"wrote {path.relative_to(REPO)}")


if __name__ == "__main__":
    main()

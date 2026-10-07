"""make_apps_json.py - build Apps.json, the JETI Studio app source file.

Copyright (c) 2026 Aaron George
SPDX-License-Identifier: MIT

JETI Studio installs Lua apps from JSON source files that users add under
File -> Configuration. This writes one in JETI's own format, the format of
JETI's catalog (http://support.jetimodel.cz/files/update-dcds/apps.json)
and of JETI Studio's AppGenerator:

    {"applications": [{"id": 0, "version": ..., "author": ...,
      "hw": [transmitter type IDs], "releaseDate": RFC 2822 date,
      "name": {"en": ...}, "description": {"en": URL of an HTML page},
      "previewIcon": URL, "files": [{"url", "destination", "hash", "size"}]}]}

`destination` is relative to the SD card (e.g. "Apps/AG-SpdGa.lua"),
`hash` is the file's SHA-1 and `size` its length in bytes. Each app's files
are read from its release tag, and their download links point at that tag,
so users always install exactly the released version. The description page
and icon come from `main`.

Run from the repo root after tagging a release, then commit Apps.json and
merge it to `main`:

    python tools/publish/make_apps_json.py

To try it in JETI Studio before publishing, `--local` also writes
Apps.local.json (gitignored), whose description and icon are the files in
this working folder; add its file:/// URL under File -> Configuration.

Standard library only.
"""

import hashlib
import json
import subprocess
import sys
from email.utils import format_datetime
from datetime import datetime, timezone
from pathlib import PurePosixPath
from urllib.parse import quote
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RAW = "https://raw.githubusercontent.com/Flazzarious/jeti-lua-apps"

# Transmitter type IDs ("hw") in JETI's catalog: every "(DC/DS-24II)" app
# there uses exactly 3866 and 3867 (the DS-24 II and DC-24 II).
HW_DCDS24_II = [3866, 3867]

# One entry per published app. "tag" is its release tag; "paths" are the
# repo paths (files or folders) that make up the app on the transmitter.
APPS = [
    {
        "name": "Speed Gauge (DC/DS-24II)",
        "script": "AG-SpdGa",
        "tag": "AG-SpdGa-v0.3.0",
        "author": "Aaron George (based on DFM Speed Announcer by Dave McQueeney)",
        "hw": HW_DCDS24_II,
        "description": "docs/apps/speed-gauge.html",
        "previewIcon": "docs/apps/img/speed-gauge-icon.png",
        "paths": [
            "src/Apps/AG-SpdGa.lua",
            "src/Apps/AG-SpdGa",
            "src/Apps/lib/ag_dens.lua",
            "src/Apps/lib/ag_gauge.lua",
        ],
    },
]


def git(*args, text=True):
    return subprocess.run(["git", *args], cwd=REPO, check=True,
                          capture_output=True, text=text).stdout


def url(ref, path):
    return f"{RAW}/{quote(ref)}/{quote(path)}"


def app_version(tag, script):
    """APP_VERSION from the app's source at its tag, e.g. "0.3.0"."""
    for line in git("show", f"{tag}:src/Apps/{script}.lua").splitlines():
        if line.startswith("local APP_VERSION"):
            return line.split('"')[1]
    raise SystemExit(f"APP_VERSION not found in {script}.lua at {tag}")


def release_date(tag):
    """The tag's date as RFC 2822, e.g. "Sun, 04 Oct 2026 12:00:00 +0000"."""
    stamp = int(git("log", "-1", "--format=%ct", tag).strip())
    return format_datetime(datetime.fromtimestamp(stamp, timezone.utc))


def local_url(path):
    """file:/// URL of a file in this working folder (for --local)."""
    return (REPO / path).resolve().as_uri()


def entry(app, local=False):
    tag = app["tag"]
    paths = git("ls-tree", "-r", "--name-only", tag, "--", *app["paths"]).split()
    if not paths:
        raise SystemExit(f"no files for {app['name']} at {tag}")
    files = []
    for p in sorted(paths):
        data = git("show", f"{tag}:{p}", text=False)
        files.append({
            "url": url(tag, p),
            # src/Apps mirrors Apps on the transmitter's SD card.
            "destination": str(PurePosixPath(p).relative_to("src")),
            "hash": hashlib.sha1(data).hexdigest(),
            "size": len(data),
        })
    return {
        "id": 0,
        "version": app_version(tag, app["script"]),
        "author": app["author"],
        "hw": app["hw"],
        "releaseDate": release_date(tag),
        "name": {"en": app["name"]},
        "description": {"en": local_url(app["description"]) if local
                        else url("main", app["description"])},
        "previewIcon": (local_url(app["previewIcon"]) if local
                        else url("main", app["previewIcon"])),
        "files": files,
    }


def write(path, out):
    # open() with newline= (Path.write_text has none before Python 3.10).
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {path.relative_to(REPO)}")


def main():
    out = {"applications": [entry(app) for app in APPS]}
    write(REPO / "Apps.json", out)
    if "--local" in sys.argv:
        local = REPO / "Apps.local.json"
        write(local, {"applications": [entry(app, local=True) for app in APPS]})
        print(f"JETI Studio test source: {local.resolve().as_uri()}")
    for a in out["applications"]:
        total = sum(f["size"] for f in a["files"])
        print(f"{a['name']['en']} {a['version']}: {len(a['files'])} files, "
              f"{total / 1e6:.1f} MB, {a['releaseDate']}")


if __name__ == "__main__":
    main()

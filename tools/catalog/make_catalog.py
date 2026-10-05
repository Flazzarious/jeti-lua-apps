#!/usr/bin/env python3
"""Build the JETI Studio app catalog (catalog/apps.json) for this repo.

JETI Studio's Lua app manager reads a catalog file: a list of apps, each with
the files to download, where each file goes on the SD card, and the file's
size and SHA-1 hash. This script writes that catalog from catalog/sources.json
(the hand-edited app list) and the app files in src/Apps/.

Every download URL points at the app's release tag, `<script>-v<version>`
(e.g. AG-SpdGa-v0.3.0), never at a branch, so an install always gets exactly
the released files.

Usage (from the repo root):
    python tools/catalog/make_catalog.py           # write catalog/apps.json
    python tools/catalog/make_catalog.py --check   # verify it against the tags

Release order (README, "Releasing"):
  1. On the feature branch, bump the app's version and run this script; it
     reads the version from the script and hashes the committed files.
  2. Merge to develop, then develop -> main by pull request.
  3. Tag the merge commit on main `<script>-v<version>` and push the tag.
  4. Run `--check`. It fails if a tag is missing, or if the tag's files don't
     match the catalog's sizes and hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "catalog" / "sources.json"
CATALOG = ROOT / "catalog" / "apps.json"
REQUIRE = re.compile(r"""require\s*\(?\s*["'](ag_[a-z0-9]+)["']""")
VERSION = re.compile(r"""(?:APP_VERSION\s*=|\bversion\s*=)\s*["']([0-9][0-9A-Za-z.\-]*)["']""")


def git(*args: str, binary: bool = False):
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True)
    return out.stdout if binary else out.stdout.decode("utf-8")


def tracked(prefix: str) -> list[str]:
    """Committed files under a path (never local, untracked junk)."""
    return sorted(p for p in git("ls-files", "--", prefix).splitlines() if p)


def tag_exists(tag: str) -> bool:
    return subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{tag}"],
                          cwd=ROOT, capture_output=True).returncode == 0


def read(path: str, tag: str | None) -> bytes:
    if tag:
        return git("show", f"{tag}:{path}", binary=True)
    return (ROOT / path).read_bytes()


def app_version(script_path: str, tag: str | None = None) -> str:
    m = VERSION.search(read(script_path, tag).decode("utf-8"))
    if not m:
        sys.exit(f"{script_path}: no APP_VERSION / version string found")
    return m.group(1)


def lib_closure(start: str, tag: str | None) -> list[str]:
    """lib/ag_*.lua modules required by a file, followed transitively."""
    found: set[str] = set()
    todo = [start]
    while todo:
        text = read(todo.pop(), tag).decode("utf-8")
        for mod in REQUIRE.findall(text):
            path = f"src/Apps/lib/{mod}.lua"
            if path not in found:
                found.add(path)
                todo.append(path)
    return sorted(found)


def app_files(script: str, tag: str | None) -> list[str]:
    main = f"src/Apps/{script}.lua"
    if tag:
        assets = [p for p in git("ls-tree", "-r", "--name-only", tag, "--",
                                 f"src/Apps/{script}/").splitlines() if p]
    else:
        assets = tracked(f"src/Apps/{script}/")
    return [main, *sorted(assets), *lib_closure(main, tag)]


def release_date(tag: str) -> str:
    if tag_exists(tag):
        stamp = int(git("log", "-1", "--format=%ct", tag).strip())
        when = datetime.fromtimestamp(stamp, timezone.utc)
    else:
        when = datetime.now(timezone.utc)
    return when.strftime("%a, %d %b %Y %H:%M:%S +0000")


def build(src: dict, from_tags: bool) -> dict:
    raw = src["rawBase"].rstrip("/")
    apps = []
    for app in src["apps"]:
        script = app["script"]
        version = app_version(f"src/Apps/{script}.lua")
        tag = f"{script}-v{version}"
        if from_tags and not tag_exists(tag):
            raise SystemExit(f"tag {tag} not found: tag the release on main, then re-run --check")
        ref = tag if from_tags else None
        files = []
        for path in app_files(script, ref):
            data = read(path, ref)
            files.append({
                "url": f"{raw}/{tag}/{quote(path)}",
                "destination": path[len("src/"):],
                "size": len(data),
                "hash": hashlib.sha1(data).hexdigest(),
            })
        apps.append({
            "id": 0,
            "name": app["name"],
            "author": app["author"],
            "version": version,
            "releaseDate": release_date(tag),
            "hw": app.get("hw", src["hw"]),
            "description": app["description"],
            "previewIcon": f"{raw}/{tag}/{quote(app['previewIcon'])}",
            "files": files,
        })
    return {"applications": apps}


def dump(catalog: dict) -> str:
    return json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true",
                    help="verify catalog/apps.json against the release tags")
    args = ap.parse_args()
    src = json.loads(SOURCES.read_text(encoding="utf-8"))

    if not args.check:
        catalog = build(src, from_tags=False)
        CATALOG.write_text(dump(catalog), encoding="utf-8", newline="\n")
        for a in catalog["applications"]:
            total = sum(f["size"] for f in a["files"])
            print(f"{a['name']['en']} {a['version']}: {len(a['files'])} files, "
                  f"{total / 1e6:.1f} MB")
        print(f"wrote {CATALOG.relative_to(ROOT)}")
        return 0

    current = json.loads(CATALOG.read_text(encoding="utf-8"))
    expected = build(src, from_tags=True)
    problems = []
    cur = {a["files"][0]["destination"]: a for a in current["applications"]}
    for a in expected["applications"]:
        key = a["files"][0]["destination"]
        have = cur.get(key)
        if not have:
            problems.append(f"{key}: missing from catalog/apps.json")
            continue
        if have["version"] != a["version"]:
            problems.append(f"{key}: catalog says {have['version']}, script says {a['version']}")
        want = {f["destination"]: f for f in a["files"]}
        got = {f["destination"]: f for f in have["files"]}
        for d in sorted(want.keys() | got.keys()):
            w, g = want.get(d), got.get(d)
            if not g:
                problems.append(f"{d}: in the tag but not in the catalog")
            elif not w:
                problems.append(f"{d}: in the catalog but not in the tag")
            elif (w["hash"], w["size"], w["url"]) != (g["hash"], g["size"], g["url"]):
                problems.append(f"{d}: catalog entry doesn't match the tagged file")
    for p in problems:
        print(f"FAIL  {p}")
    n = sum(len(a["files"]) for a in expected["applications"])
    print(f"{len(expected['applications'])} app(s), {n} file(s) checked against tags, "
          f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

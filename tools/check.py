#!/usr/bin/env python3
"""Pre-emulator checks for Jeti Lua apps (constitution: Verification step 2).

1. Syntax-checks every .lua file under src/ with a Lua 5.3 compiler, if one is
   on PATH (luac5.3 or luac). Skipped with a warning otherwise.
2. Scans for APIs the constitution forbids or that don't exist on the radio.
3. Checks app filenames are 8.3 and files are UTF-8 without BOM.

Exit code is non-zero if anything fails. Run from anywhere:
    python tools/check.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# (pattern, reason). Matched against code with comments and strings stripped.
FORBIDDEN = [
    (r"\bsystem\s*\.\s*registerControl\b", "Principle I: Lua controls can be assigned to flight functions"),
    (r"\bsystem\s*\.\s*setControl\b", "Principle I: Lua controls can be assigned to flight functions"),
    (r"\bsystem\s*\.\s*setProperty\b", "Principle I: can change wireless/trainer mode"),
    (r"\bos\s*\.", "Principle III: os library does not exist on the transmitter"),
    (r"\bdebug\s*\.", "Principle III: debug library does not exist on the transmitter"),
    (r"\bcoroutine\s*\.", "Principle III: coroutine library does not exist on the transmitter"),
    (r"\bbit32\s*\.", "Principle III: bit32 is absent; use native bitwise operators"),
    (r"\bmobdebug\b", "Emulator-only debugger; remove before deploying"),
]
# Allowed only with an explicit spec; reported as warnings.
CAUTION = [
    (r"\bgpio\s*\.\s*(write|mode)\b", "Principle I: gpio output needs a scoped spec"),
    (r"\bserial\s*\.\s*write\b", "Principle I: serial output needs a scoped spec"),
]

EIGHT_THREE = re.compile(r"^[A-Za-z0-9_\-]{1,8}\.lua$")


def strip_comments_and_strings(code: str) -> str:
    """Blank out comments and string literals so scans only see code."""
    out = []
    i, n = 0, len(code)
    while i < n:
        if code.startswith("--", i):
            m = re.match(r"--\[(=*)\[", code[i:])
            if m:
                end = code.find("]" + m.group(1) + "]", i)
                end = n if end == -1 else end + len(m.group(1)) + 2
            else:
                end = code.find("\n", i)
                end = n if end == -1 else end
            out.append(re.sub(r"[^\n]", " ", code[i:end]))
            i = end
            continue
        m = re.match(r"\[(=*)\[", code[i:])
        if m:
            end = code.find("]" + m.group(1) + "]", i)
            end = n if end == -1 else end + len(m.group(1)) + 2
            out.append(re.sub(r"[^\n]", " ", code[i:end]))
            i = end
            continue
        ch = code[i]
        if ch in "\"'":
            j = i + 1
            while j < n and code[j] != ch and code[j] != "\n":
                j += 2 if code[j] == "\\" else 1
            out.append(" " * (min(j + 1, n) - i))
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    files = sorted(SRC.rglob("*.lua"))
    if not files:
        print("No .lua files under src/")
        return 0

    luac = shutil.which("luac5.3") or shutil.which("luac")
    if luac is None:
        warnings.append("luac not found on PATH; syntax check skipped")

    apps_dir = SRC / "Apps"
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            errors.append(f"{rel}: has a UTF-8 BOM (Principle V)")
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            errors.append(f"{rel}: not valid UTF-8 ({exc}) (Principle V)")
            continue
        if b"\r\n" in raw:
            errors.append(f"{rel}: CRLF line endings (Principle V)")

        if path.parent == apps_dir and not EIGHT_THREE.match(path.name):
            errors.append(f"{rel}: app filename is not 8.3 (Principle V)")

        if luac:
            result = subprocess.run(
                [luac, "-p", str(path)], capture_output=True, text=True
            )
            if result.returncode != 0:
                errors.append(f"{rel}: syntax error: {result.stderr.strip()}")

        code = strip_comments_and_strings(text)
        for lineno, line in enumerate(code.splitlines(), start=1):
            for pattern, reason in FORBIDDEN:
                if re.search(pattern, line):
                    errors.append(f"{rel}:{lineno}: forbidden API ({reason})")
            for pattern, reason in CAUTION:
                if re.search(pattern, line):
                    warnings.append(f"{rel}:{lineno}: {reason}")

    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"FAIL  {e}")
    print(f"{len(files)} file(s) checked, {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

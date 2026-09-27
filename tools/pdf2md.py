#!/usr/bin/env python3
"""Download JETI's Lua API PDF and convert it to text for local reference.

The output lands in docs/vendor/, which is gitignored: the PDF is JETI's
copyrighted document, so each checkout regenerates it instead of committing it.

Usage:
    pip install pypdf
    python tools/pdf2md.py              # download from GitHub, then convert
    python tools/pdf2md.py path/to.pdf  # convert a PDF you already have
"""

from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

PDF_URL = (
    "https://github.com/JETImodel/Lua-Apps/raw/master/Doc/"
    "JETI%20DCDS_Lua_API_1.5.pdf"
)
ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "docs" / "vendor"


def main() -> int:
    try:
        from pypdf import PdfReader
    except ImportError:
        print("pypdf is required: pip install pypdf", file=sys.stderr)
        return 1

    VENDOR.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) > 1:
        pdf_path = Path(sys.argv[1])
    else:
        pdf_path = VENDOR / "jeti-lua-api-1.5.pdf"
        if not pdf_path.exists():
            print(f"Downloading {PDF_URL}")
            urllib.request.urlretrieve(PDF_URL, pdf_path)

    reader = PdfReader(str(pdf_path))
    out = VENDOR / "jeti-api.md"
    with out.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"<!-- Generated from {pdf_path.name} by tools/pdf2md.py. Do not edit. -->\n\n")
        for number, page in enumerate(reader.pages, start=1):
            text = page.extract_text(extraction_mode="layout") or ""
            fh.write(f"\n\n<!-- page {number} -->\n\n```text\n{text.rstrip()}\n```\n")

    print(f"Wrote {out} ({len(reader.pages)} pages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

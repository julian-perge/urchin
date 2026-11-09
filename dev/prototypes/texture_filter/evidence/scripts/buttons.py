#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# ///
"""Which Button nodes in the scenes carry text, an icon, both or neither."""
import re
import sys
from pathlib import Path
from collections import Counter

root = Path(sys.argv[1])
tally = Counter()
rows = []
for path in sorted((root / "scenes").rglob("*.tscn")):
    text = path.read_text()
    for chunk in re.split(r"(?=^\[)", text, flags=re.M):
        m = re.match(r'\[node name="([^"]+)" type="Button"', chunk)
        if not m:
            continue
        has_text = bool(re.search(r'^text = "[^"]', chunk, re.M))
        has_icon = bool(re.search(r"^icon = ", chunk, re.M))
        kind = "both" if has_text and has_icon else "text" if has_text else "icon" if has_icon else "neither"
        tally[kind] += 1
        if kind in ("both", "neither"):
            rows.append((kind, path.relative_to(root).as_posix(), m[1]))
print(dict(tally))
for r in rows:
    print(*r)

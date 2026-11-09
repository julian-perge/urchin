#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow"]
# ///
"""How far today's pinned ffdec render of the win frame is from the one committed on the prototype branch."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

T = Path.home() / "tmp/2026-11-09-urchin-filter"
OLD = T / "proto/dev/prototypes/victory_containers/images"
NEW = T / "ref_today/images"
for sub in ("ref", "art"):
    print(f"== {sub}")
    for new_path in sorted((NEW / sub).glob("*.png")):
        old_path = OLD / sub / new_path.name
        if not old_path.exists():
            print(f"  {new_path.name}: no committed copy")
            continue
        a = np.asarray(Image.open(old_path).convert("RGBA"), dtype=np.int16)
        b = np.asarray(Image.open(new_path).convert("RGBA"), dtype=np.int16)
        if a.shape != b.shape:
            print(f"  {new_path.name}: size {a.shape[1]}x{a.shape[0]} -> {b.shape[1]}x{b.shape[0]}")
            continue
        d = np.abs(a - b).max(axis=2)
        changed = d > 0
        line = f"  {new_path.name}: {int(changed.sum())} of {d.size} differ ({changed.mean():.3%})"
        if changed.any():
            line += f", max {int(d.max())}, p99 of changed {np.percentile(d[changed], 99):.0f}"
        print(line)
old_art = json.loads((T / "proto/dev/prototypes/victory_containers/art.json").read_text())
new_art = json.loads((T / "ref_today/art.json").read_text())
diffs = [k for k in sorted(set(old_art) | set(new_art)) if old_art.get(k) != new_art.get(k)]
print("art.json keys that differ:", diffs)

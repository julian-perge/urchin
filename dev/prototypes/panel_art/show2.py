#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
from __future__ import annotations

import json
from collections import Counter

rows = json.load(open("panels.json"))
order = [
    "flat-rect",
    "outline",
    "gradient-rect",
    "multi",
    "lines",
    "nonrect-solid",
    "nonrect-gradient",
]
KM = "Bevel shadow #ca6e6e"
for cat in order:
    print("=====", cat)
    for r in rows:
        if r["category"] != cat:
            continue
        b = r["bounds"]
        w, h = b[2] - b[0], b[3] - b[1]
        screens = Counter(u["screen"].replace("KRINMENU:", "K:") for u in r["uses"])
        sc = ",".join(f"{k}*{v}" if v > 1 else k for k, v in screens.items())
        filt = Counter()
        scales = set()
        sizes = set()
        clip = any(u["clip"] for u in r["uses"])
        allclip = all(u["clip"] for u in r["uses"])
        for u in r["uses"]:
            own = [
                f.split(" ")[0] + ("(inner)" if " inner" in f else "") for f in u["own"]
            ]
            ch = [
                f.split(" ")[0] + ("(inner)" if " inner" in f else "")
                for f in u["chain"]
                if not f.startswith("Bevel shadow #ca6e6e")
                and not (
                    f.startswith("Glow #000000@255 blur 2x2")
                    and u["screen"].startswith("KRINMENU")
                )
                and not (
                    f.startswith(
                        "DropShadow #000000@255 blur 5x5 angle 45 dist 5 str 1.00"
                    )
                    and u["screen"].startswith("KRINMENU")
                    and " inner" not in f
                )
            ]
            filt[
                ("own:" + "+".join(own) if own else "")
                + (" chain:" + "+".join(ch) if ch else "")
            ] += 1
            scales.add((u["scale"][0], u["scale"][1]))
            sizes.add((round(u["rect"][2], 1), round(u["rect"][3], 1)))
        s = f"{r['cid']:>5} {w:.1f}x{h:.1f} e{r['n_edges']}c{r['n_curves']} | F {'; '.join(r['fills']) or '-'} | L {'; '.join(r['lines']) or '-'}"
        print(s[:230])
        print(f"        in {sc[:200]}")
        fs = "; ".join(f"[{k}]x{v}" if k else f"[none]x{v}" for k, v in filt.items())
        print(
            f"        filters {fs[:220]} {'CLIPMASK' if allclip else ('some-clip' if clip else '')} sizes {sorted(sizes)[:4]}{'...' if len(sizes) > 4 else ''}"
        )

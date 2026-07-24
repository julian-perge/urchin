# extract_item_looks.py
# Item "looks" art keys from source_files/action_script/frame_42/DoAction_16.as:
# createNewItemKrin() advances the id counter (with manual jumps
# itemKrinIDnow = 99/299/499 between blocks); wearables (b > 1) default to
# looks "NINJA" inside the function; a following `gghhjjuu.looks = "X"`
# overrides the item just created.
#
# Writes converted_json/item_looks.json (merged by convert_items.py) and
# patches resources/items/<id>_*.tres in place.
#
# Run: uv run python3 conversion_scripts/swf_extraction/extract_item_looks.py
from __future__ import annotations

import json
import re
import sys

from .. import ACTION_SCRIPT, CONVERTED_JSON, REPO_ROOT

SRC = ACTION_SCRIPT / "frame_42" / "DoAction_16.as"
ITEMS_DIR = REPO_ROOT / "resources" / "items"
OUT = CONVERTED_JSON / "item_looks.json"

CREATE_RE = re.compile(r'createNewItemKrin\("(.*?)",(-?\d+),')
LOOKS_RE = re.compile(
    r'(?:gghhjjuu|_root\["KRINITEM" \+ itemKrinIDnow\])\.looks = "([^"]*)"'
)
JUMP_RE = re.compile(r"^itemKrinIDnow = (-?\d+);")


def main():
    looks = {}
    item_id = -1
    for line in SRC.read_text().splitlines():
        jm = JUMP_RE.match(line.strip())
        if jm:
            item_id = int(jm.group(1))
            continue
        cm = CREATE_RE.search(line)
        if cm:
            item_id += 1
            if int(cm.group(2)) > 1:
                looks[item_id] = "NINJA"
            continue
        lm = LOOKS_RE.search(line)
        if lm and item_id >= 0:
            looks[item_id] = lm.group(1)

    print(f"looks entries: {len(looks)}", file=sys.stderr)
    OUT.write_text(json.dumps({str(k): v for k, v in sorted(looks.items())}, indent=1))
    print("wrote", OUT, file=sys.stderr)

    patched = 0
    for tres in ITEMS_DIR.glob("*.tres"):
        tid = int(tres.name.split("_", 1)[0])
        look = looks.get(tid, "")
        text = tres.read_text()
        if re.search(r"^looks = ", text, re.M):
            text = re.sub(r'^looks = ".*"$', 'looks = "%s"' % look, text, flags=re.M)
        elif look:
            text = re.sub(
                r'^(internal_name = ".*")$',
                '\\1\nlooks = "%s"' % look,
                text,
                count=1,
                flags=re.M,
            )
        else:
            continue
        tres.write_text(text)
        patched += 1
    print(f"tres patched: {patched}", file=sys.stderr)


if __name__ == "__main__":
    main()

# Fails when an extract_* entry point in pyproject.toml has no test module that
# imports its module. Ticket #178 added a 329-line extractor with no test
# because its spec named only GDScript seams, and only the review caught it.
# Extractors that had no tests before this check sit in UNTESTED. Remove a name
# from it when you add tests, and never add one.
from __future__ import annotations

import re
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

UNTESTED = {
    "battle_screen",
    "battle_screen_motion",
    "buff_icons",
    "doll_art",
    "faces",
    "item_looks",
    "start_screens",
    "store_art",
    "vfx_scenes",
    "zone_hub",
}


def extractor_modules() -> set[str]:
    scripts = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["scripts"]
    return {
        target.split(":")[0].rsplit(".", 1)[1]
        for name, target in scripts.items()
        if name.startswith("extract_") and ".extract." in target
    }


def imported_by_tests(module: str) -> bool:
    pattern = re.compile(
        rf"urchin_dev\.swf\.extract(\.{module}\b|\s+import\s+[^\n]*\b{module}\b)"
    )
    return any(
        pattern.search(test.read_text())
        for test in (ROOT / "dev/tests").glob("test_*.py")
    )


def test_every_extractor_has_a_test_module_that_imports_it():
    untested = {m for m in extractor_modules() if not imported_by_tests(m)}
    assert untested == UNTESTED, (
        "extractors without tests: "
        f"{sorted(untested - UNTESTED)}; tested but still in UNTESTED: "
        f"{sorted(UNTESTED - untested)}"
    )

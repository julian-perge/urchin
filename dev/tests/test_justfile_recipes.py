# Fails when a script in pyproject.toml has no `just` recipe. AGENTS.md says
# every extraction and conversion script has one, and extract_cs_intro and
# extract_cutscene_skip had none until a full regeneration tried to run them.
from __future__ import annotations

import re
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_every_extract_convert_and_export_script_has_a_recipe():
    scripts = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["scripts"]
    recipes = set(
        re.findall(
            r"^([a-z][a-z0-9-]*)\b[^\n]*:", (ROOT / "justfile").read_text(), re.M
        )
    )
    missing = sorted(
        name
        for name in scripts
        if name.startswith(("extract_", "convert_", "export_"))
        and name.replace("_", "-") not in recipes
    )
    assert missing == []

# These tests hand gd_parse.py logs trimmed from real Godot 4.7.2 --check-only
# runs in this repo on 2026-11-10, so none of them needs Godot.
from __future__ import annotations

from urchin_dev.checks.gd_parse import parse_errors

CLEAN = "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org\n\n"

# A comment joined to the `static func` line below it.
BROKEN = (
    CLEAN + '\x1b[1;31mSCRIPT ERROR: Parse Error: Unexpected "Indent" in class'
    " body.\x1b[0m\n"
    "          at: GDScript::reload (res://scripts/battle/battle_settlement.gd:36)\n"
    'ERROR: Failed to load script "res://scripts/battle/battle_settlement.gd" with'
    ' error "Parse error".\n'
    "   at: load (modules/gdscript/gdscript_resource_format.cpp:46)\n"
)

# --check-only compiles without the autoloads, so any script naming one logs this.
AUTOLOAD_FALSE_POSITIVE = (
    CLEAN + "SCRIPT ERROR: Compile Error: Identifier not found: AudioManagerAuto\n"
    "          at: GDScript::reload (res://scripts/ui/main_menu.gd:74)\n"
    'ERROR: Failed to load script "res://scripts/ui/main_menu.gd" with error'
    ' "Compilation failed".\n'
)


def test_a_clean_log_has_no_parse_errors():
    assert parse_errors(CLEAN) == []


def test_a_parse_error_is_reported_with_its_location():
    [error] = parse_errors(BROKEN)
    assert 'Unexpected "Indent" in class body.' in error
    assert "battle_settlement.gd:36" in error


def test_an_autoload_compile_error_is_not_reported():
    assert parse_errors(AUTOLOAD_FALSE_POSITIVE) == []

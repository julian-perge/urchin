# Local shortcuts for urchin. `just` lists them, and `just <recipe>` runs one.
#
# Every command goes through just so that it knows which OS it runs on, finds Godot,
# and stops with a clear message when a tool is missing. The Python scripts read
# GODOT_BIN and do not look for Godot themselves, so run them through just.
#
# Settings that differ per machine go in a gitignored .env file in this folder.
# .env.example lists them. A variable set in the shell wins over .env.

set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]

# Recipe arguments arrive as $1, $2 and so on, so variadic recipes forward them with "$@" and keep each argument intact.
set positional-arguments

# On macOS Godot is the app bundle. Elsewhere it is `godot` on PATH. GODOT_BIN in the shell or in .env replaces either.
export GODOT_BIN := env("GODOT_BIN", if os() == "macos" { "/Applications/Godot.app/Contents/MacOS/Godot" } else { "godot" })

[private]
default:
    @just --list --unsorted

# Recipes that call a tool depend on this, so a missing tool stops the recipe before it starts. AGENTS.md says how to install each one.
[private]
require +tools:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=()
    for tool in "$@"; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "error: missing ${missing[*]}. See the Setup section of AGENTS.md." >&2
        exit 1
    fi

# GODOT_BIN is a path on macOS and a command name elsewhere, and `command -v` accepts both.
[private]
require-godot:
    @command -v "$GODOT_BIN" >/dev/null || { echo "error: no Godot at GODOT_BIN=$GODOT_BIN. Install Godot 4.7.2 or set GODOT_BIN in .env. See the Setup section of AGENTS.md." >&2; exit 1; }

[doc('Run Godot import in a new worktree and warn when URCHIN_SWF_DIR has no SWFs')]
[group('godot')]
setup-worktree: require-godot
    uv run setup_worktree

[doc('Import the assets, which tests need after anything under assets/ changes')]
[group('godot')]
import: require-godot
    "$GODOT_BIN" --headless --import --path .

[doc('Run any Godot command, for example: just godot --headless --check-only -s res://scripts/x.gd --path .')]
[group('godot')]
godot *args: require-godot
    "$GODOT_BIN" "$@"

[doc('Run the GUT suite, one test file, or -gunit_test_name=<name>')]
[group('godot')]
gut *args: require-godot
    uv run gut "$@"

[doc('Parse-check the given .gd files, as the gd-parse commit hook does')]
[group('godot')]
gd-parse +files: require-godot
    uv run check_gd_parse "$@"

[doc('Run the Python package tests under dev/tests/')]
[group('python')]
pytest *args:
    uv run pytest "$@"

[doc('Run the Python tests, then the GUT suite')]
[group('python')]
test: pytest gut

[doc('Look up a function, a global, a script or a line of the original ActionScript')]
[group('python')]
as-lookup *args:
    uv run as_lookup "$@"

[doc('Merge one ticket branch into the integration branch, then push it')]
[group('python')]
merge-ticket *args: require-godot
    uv run merge_ticket "$@"

[doc('Run every pre-commit hook on every file')]
[group('lint')]
lint: (require "prek")
    prek run --all-files --show-diff-on-failure

[doc('Remove caches, build artifacts and editor temp files')]
[group('lint')]
clean:
    find . -name __pycache__ -prune -exec rm -rf {} +
    find . -name '*.egg-info' -prune -exec rm -rf {} +
    find . -type f \( -name '*.py[co]' -o -name '*~' -o -name '@*' -o -name '#*#' -o -name '*.orig' -o -name '*.rej' \) -delete
    rm -rf build dist

[doc('Run convert_battles, which converts the extracted data into JSON and Godot resources')]
[group('convert')]
convert-battles *args:
    uv run convert_battles "$@"

[doc('Run convert_buffs, which converts the extracted data into JSON and Godot resources')]
[group('convert')]
convert-buffs *args:
    uv run convert_buffs "$@"

[doc('Run convert_items, which converts the extracted data into JSON and Godot resources')]
[group('convert')]
convert-items *args:
    uv run convert_items "$@"

[doc('Run convert_moves, which converts the extracted data into JSON and Godot resources')]
[group('convert')]
convert-moves *args:
    uv run convert_moves "$@"

[doc('Run convert_units, which converts the extracted data into JSON and Godot resources')]
[group('convert')]
convert-units *args:
    uv run convert_units "$@"

[doc('Run export_swf_sources, which reads the SWF through ffdec')]
[group('extract')]
export-swf-sources *args: (require "ffdec" "java")
    uv run export_swf_sources "$@"

[doc('Run extract_ability_icons, which reads the SWF through ffdec')]
[group('extract')]
extract-ability-icons *args: (require "ffdec" "java")
    uv run extract_ability_icons "$@"

[doc('Run extract_battle_screen, which reads the SWF through ffdec')]
[group('extract')]
extract-battle-screen *args: (require "ffdec" "java")
    uv run extract_battle_screen "$@"

[doc('Run extract_battle_screen_motion, which reads the SWF through ffdec')]
[group('extract')]
extract-battle-screen-motion *args: (require "ffdec" "java")
    uv run extract_battle_screen_motion "$@"

[doc('Run extract_buff_icons, which reads the SWF through ffdec')]
[group('extract')]
extract-buff-icons *args: (require "ffdec" "java")
    uv run extract_buff_icons "$@"

[doc('Run extract_combat_text, which reads the SWF through ffdec')]
[group('extract')]
extract-combat-text *args: (require "ffdec" "java")
    uv run extract_combat_text "$@"

[doc('Run extract_cutscenes, which reads the SWF through ffdec')]
[group('extract')]
extract-cutscenes *args: (require "ffdec" "java")
    uv run extract_cutscenes "$@"

[doc('Run extract_doll_art, which reads the SWF through ffdec')]
[group('extract')]
extract-doll-art *args: (require "ffdec" "java")
    uv run extract_doll_art "$@"

[doc('Run extract_faces, which reads the SWF through ffdec')]
[group('extract')]
extract-faces *args: (require "ffdec" "java")
    uv run extract_faces "$@"

[doc('Run extract_floating_numbers, which reads the SWF through ffdec')]
[group('extract')]
extract-floating-numbers *args: (require "ffdec" "java")
    uv run extract_floating_numbers "$@"

[doc('Run extract_item_icons, which reads the SWF through ffdec')]
[group('extract')]
extract-item-icons *args: (require "ffdec" "java")
    uv run extract_item_icons "$@"

[doc('Run extract_item_looks, which reads the SWF through ffdec')]
[group('extract')]
extract-item-looks *args: (require "ffdec" "java")
    uv run extract_item_looks "$@"

[doc('Run extract_as_index, which reads the SWF through ffdec')]
[group('extract')]
extract-as-index *args: (require "ffdec" "java")
    uv run extract_as_index "$@"

[doc('Run extract_label_xref, which reads the SWF through ffdec')]
[group('extract')]
extract-label-xref *args: (require "ffdec" "java")
    uv run extract_label_xref "$@"

[doc('Run extract_model1_animations, which reads the SWF through ffdec')]
[group('extract')]
extract-model1-animations *args: (require "ffdec" "java")
    uv run extract_model1_animations "$@"

[doc('Run extract_rig_clips, which reads the SWF through ffdec')]
[group('extract')]
extract-rig-clips *args: (require "ffdec" "java")
    uv run extract_rig_clips "$@"

[doc('Run extract_start_screens, which reads the SWF through ffdec')]
[group('extract')]
extract-start-screens *args: (require "ffdec" "java")
    uv run extract_start_screens "$@"

[doc('Run extract_zone_hub, which reads the SWF through ffdec')]
[group('extract')]
extract-zone-hub *args: (require "ffdec" "java")
    uv run extract_zone_hub "$@"

[doc('Run extract_store_art, which reads the SWF through ffdec')]
[group('extract')]
extract-store-art *args: (require "ffdec" "java")
    uv run extract_store_art "$@"

[doc('Run extract_vfx, which reads the SWF through ffdec')]
[group('extract')]
extract-vfx *args: (require "ffdec" "java")
    uv run extract_vfx "$@"

[doc('Run extract_vfx_scenes, which reads the SWF through ffdec')]
[group('extract')]
extract-vfx-scenes *args: (require "ffdec" "java")
    uv run extract_vfx_scenes "$@"

[doc('Run extract_window_chrome, which reads the SWF through ffdec')]
[group('extract')]
extract-window-chrome *args: (require "ffdec" "java")
    uv run extract_window_chrome "$@"

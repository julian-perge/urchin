#!/usr/bin/env bash

# Copies a QA save preset into one of the game's save slots. A preset with a
# matching .achievements.cfg also replaces the game's achievements file, and the
# first replacement keeps the original as achievements.cfg.bak.

set -euo pipefail

presets_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
user_dir="$HOME/Library/Application Support/Godot/app_userdata/urchin"
achievements="$user_dir/achievements.cfg"
achievements_backup="$achievements.bak"

usage() {
    echo "Usage: $0 <preset> <slot 1-4>"
    echo "       $0 --list"
    echo "       $0 --restore-achievements"
}

list_presets() {
    for preset_file in "$presets_dir"/*.tres; do
        basename "$preset_file" .tres
    done
}

restore_achievements() {
    if [[ ! -f "$achievements_backup" ]]; then
        echo "No backup to restore at $achievements_backup" >&2
        exit 1
    fi
    mv "$achievements_backup" "$achievements"
    echo "Restored achievements.cfg from the backup."
}

replace_achievements() {
    local variant_file="$1"
    if [[ ! -f "$achievements_backup" ]]; then
        if [[ -f "$achievements" ]]; then
            cp "$achievements" "$achievements_backup"
        else
            # An empty backup stands in for a missing file, because the game
            # reads both as no achievements unlocked.
            : >"$achievements_backup"
        fi
    fi
    cp "$variant_file" "$achievements"
}

case "${1:-}" in
    --list)
        list_presets
        exit 0
        ;;
    --restore-achievements)
        restore_achievements
        exit 0
        ;;
esac

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 2
fi

preset="$1"
slot="$2"
preset_file="$presets_dir/$preset.tres"
variant_file="$presets_dir/$preset.achievements.cfg"

if [[ ! -f "$preset_file" ]]; then
    echo "Unknown preset: $preset (--list shows them)" >&2
    exit 1
fi
if [[ ! "$slot" =~ ^[1-4]$ ]]; then
    echo "Slot must be 1 to 4, got: $slot" >&2
    exit 1
fi

mkdir -p "$user_dir/saves"
cp "$preset_file" "$user_dir/saves/slot$slot.tres"
echo "Copied $preset to slot $slot."
if [[ -f "$variant_file" ]]; then
    replace_achievements "$variant_file"
    echo "Replaced achievements.cfg. $0 --restore-achievements puts the original back."
fi
echo "Start the game after this. A running game keeps the slot it already loaded."

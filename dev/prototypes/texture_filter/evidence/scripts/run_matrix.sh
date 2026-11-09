#!/usr/bin/env bash
set -u
T=$HOME/tmp/2026-11-09-urchin-filter
W=/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/admiring-davinci-f28a5d
C=$T/clone_mip
G=/Applications/Godot.app/Contents/MacOS/Godot
D=$T/filterdriver.gd
export GODOT_SLOTS=2

run() {
	local proj=$1 filter=$2 res=$3 label=$4 name=$5
	shift 5
	local O=$T/cap/$label
	mkdir -p "$O"
	fish "$HOME/tmp/2026-11-07-godot-slots/godot-slot.fish" "$G" -d --path "$proj" --embedded --fixed-fps 30 --quit-after 400 --resolution "$res" -s "$D" -- --snap=project --filter="$filter" --out="$O/$name" "$@" > "$O/$name.log" 2>&1 < /dev/null
	echo "$label/$name exit $?"
}

scene_set() {
	local proj=$1 filter=$2 res=$3 label=$4
	shift 4
	run "$proj" "$filter" "$res" "$label" battle "$@" --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
	run "$proj" "$filter" "$res" "$label" hub "$@" --hub --scene=res://scenes/game.tscn --frames=60
	run "$proj" "$filter" "$res" "$label" inv "$@" --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:inventory_window --open-frame=20 --frames=40
	run "$proj" "$filter" "$res" "$label" store "$@" --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:store_window --open-frame=20 --frames=40
	run "$proj" "$filter" "$res" "$label" abil "$@" --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:abilities_window --open-frame=20 --frames=40
	run "$proj" "$filter" "$res" "$label" title "$@" --scene=res://scenes/main_menu.tscn --frames=30
}

scene_set "$W" nearest 1600x1200 nearest_2x --scan
scene_set "$W" linear 1600x1200 linear_2x
scene_set "$W" nearest 800x600 nearest_1x
scene_set "$W" linear 800x600 linear_1x
run "$W" nearest 1600x1200 nearest_2x_repeat battle --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
for res in 1200x900 2400x1800 3200x2400; do
	run "$W" nearest "$res" "nearest_$res" battle --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
	run "$W" linear "$res" "linear_$res" battle --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
done

until rg -q '^done$' "$T/import_mip.log"; do sleep 5; done
scene_set "$C" mip 1600x1200 mip_2x
scene_set "$C" mip 800x600 mip_1x
run "$C" linear 1600x1200 linear_2x_clone battle --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
for res in 1200x900 2400x1800 3200x2400; do
	run "$C" mip "$res" "mip_$res" battle --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
done
echo MATRIX_DONE

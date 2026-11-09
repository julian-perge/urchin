#!/usr/bin/env bash
set -u
T=$HOME/tmp/2026-11-09-urchin-filter
W=/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/admiring-davinci-f28a5d
C=$T/clone_proto
G=/Applications/Godot.app/Contents/MacOS/Godot
D=$T/filterdriver.gd
export GODOT_SLOTS=2
run() {
	local proj=$1 filter=$2 res=$3 label=$4 name=$5
	shift 5
	local O=$T/$label
	mkdir -p "$O"
	fish "$HOME/tmp/2026-11-07-godot-slots/godot-slot.fish" "$G" -d --path "$proj" --embedded --fixed-fps 30 --quit-after 400 --resolution "$res" -s "$D" -- --snap=project --filter="$filter" --out="$O/$name" "$@" > "$O/$name.log" 2>&1 < /dev/null
	echo "$label/$name exit $?"
}
# The scan again with the fixed scale, 2x window, nearest.
L=cap/scan2
run "$W" nearest 1600x1200 $L battle --scan --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
run "$W" nearest 1600x1200 $L hub --scan --hub --scene=res://scenes/game.tscn --frames=60
run "$W" nearest 1600x1200 $L inv --scan --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:inventory_window --open-frame=20 --frames=40
run "$W" nearest 1600x1200 $L store --scan --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:store_window --open-frame=20 --frames=40
run "$W" nearest 1600x1200 $L abil --scan --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:abilities_window --open-frame=20 --frames=40
run "$W" nearest 1600x1200 $L title --scan --scene=res://scenes/main_menu.tscn --frames=30
# The victory prototype on today's main, snapping off from the project settings.
for size in 1600x1200:2x 800x600:1x; do
	res=${size%%:*}; tag=${size##*:}
	for filter in nearest linear; do
		for variant in B C; do
			L=vic/${filter}_${tag}
			for mode in ref chrome panels live; do
				run "$C" "$filter" "$res" "$L" "${variant}_${mode}" --scene=res://scenes/battle/victory_screen_prototype.tscn --variant=$variant --mode=$mode --clean --frames=30
			done
			run "$C" "$filter" "$res" "$L" "${variant}_sentinel" --scene=res://scenes/battle/victory_screen_prototype.tscn --variant=$variant --mode=ref --clean --sentinel --frames=30
		done
	done
done
echo VICTORY_DONE

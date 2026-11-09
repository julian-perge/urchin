#!/usr/bin/env bash
set -u
T=$HOME/tmp/2026-11-09-urchin-filter
W=/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/admiring-davinci-f28a5d
G=/Applications/Godot.app/Contents/MacOS/Godot
D=$T/filterdriver.gd
export GODOT_SLOTS=2
run() {
	local res=$1 label=$2 name=$3
	shift 3
	local O=$T/var/$label
	mkdir -p "$O"
	fish "$HOME/tmp/2026-11-07-godot-slots/godot-slot.fish" "$G" -d --path "$W" --embedded --fixed-fps 30 --quit-after 400 --resolution "$res" -s "$D" -- --snap=project --filter=none --clean --out="$O/$name" "$@" > "$O/$name.log" 2>&1 < /dev/null
	echo "$label/$name exit $?"
}
for size in 1600x1200:2x 800x600:1x; do
	res=${size%%:*}; tag=${size##*:}
	for v in A B C D; do
		run "$res" "${v}_$tag" battle --variant=$v --scene=res://scenes/battle_scene.tscn --battle=109 --frames=120
		run "$res" "${v}_$tag" store --variant=$v --hub --scene=res://scenes/game.tscn --open=Hotbar:toggle_menu_screen:store_window --open-frame=20 --frames=40
	done
done
echo VARIANTS_DONE

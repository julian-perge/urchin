#!/usr/bin/env bash
set -u
T=$HOME/tmp/2026-11-09-urchin-filter
W=/Users/sweetjp/Documents/godot/urchin/.claude/worktrees/admiring-davinci-f28a5d
CM=$T/clone_mip
CF=$T/clone_font
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
fish "$HOME/tmp/2026-11-07-godot-slots/godot-slot.fish" "$G" --headless --import --path "$CF" > "$T/import_font.log" 2>&1 < /dev/null
echo import_font done
for size in 800x600:1x 1600x1200:2x 1200x900:1p5x 2400x1800:3x 3200x2400:4x; do
	res=${size%%:*}; tag=${size##*:}
	run "$W" nearest "$res" "halls/nearest_$tag" h --mode=halls --pairs=$T/halls/ref/pairs.json
	run "$W" linear "$res" "halls/linear_$tag" h --mode=halls --pairs=$T/halls/ref/pairs.json
	run "$CM" mip "$res" "halls/mip_$tag" h --mode=halls --pairs=$T/halls/ref/pairs.json
done
for size in 800x600:1x 1600x1200:2x 1200x900:1p5x; do
	res=${size%%:*}; tag=${size##*:}
	for filter in nearest linear; do
		run "$W" "$filter" "$res" "text/opensans_${filter}_$tag" syn --mode=synthetic
		run "$CF" "$filter" "$res" "text/heros_${filter}_$tag" syn --mode=synthetic
	done
done
echo HALLS_DONE

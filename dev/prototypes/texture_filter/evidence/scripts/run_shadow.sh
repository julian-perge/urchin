#!/usr/bin/env bash
export GODOT_SLOTS=2
for n in nearest linear; do
	P=/Users/sweetjp/tmp/2026-11-09-urchin-filter/shadow/$n
	fish $HOME/tmp/2026-11-07-godot-slots/godot-slot.fish /Applications/Godot.app/Contents/MacOS/Godot -d --path "$P" --embedded --quit-after 900 -s main.gd -- --no-snap --out="$P/out" > "$P/run.log" 2>&1 < /dev/null
	echo "$n exit $?"
done
echo SHADOW_DONE

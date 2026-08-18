# Implementation Plan — Cutscenes

## Problem Statement
`ZoneProgression.after_battle_won()` already computes which cutscene should play after a story battle (`CS_CUT2` through `CS_CUT5`) but nothing consumes the result — `battle_scene.gd:764` discards the returned dict outright. The goal is to extract the 4 original cutscenes from the web SWF and play them back at the same point in the flow the original did: after the victory screen's Continue button, before returning to the zone hub.

## Requirements
- Extract `CS_CUT2`/`CS_CUT3`/`CS_CUT4`/`CS_CUT5` as playable video files with their original embedded audio, full frame-accurate fidelity (every filter/color-transform/blend-mode baked in correctly — not approximated)
- A `CutscenePlayer` scene that fades in from black, plays the video, fades back to black, and signals completion — unskippable, matching the original (confirmed: none of the 4 have a skip button)
- `battle_scene.gd` captures the cutscene id `after_battle_won()` already returns (currently thrown away) and plays it via `CutscenePlayer` before proceeding to `game.tscn`, matching the original's Continue-button check on `afterCut`
- Fix `zone_progression.gd`'s `CUTSCENE_BATTLES` entry `513: "CS_CUT5"` — battle 513 doesn't exist (confirmed against `battles.json`, the story block tops out at 512, already verified zero-drift against the source AS in a prior session). CS_CUT5 can never currently trigger.
- GUT coverage for `CUTSCENE_BATTLES` id validity (would have caught the 513 bug), the `after_battle_won` → cutscene-id plumbing, and `CutscenePlayer`'s fade timing/`finished` signal

## Background

### What's actually in scope
Traced via `frame_219/DoAction.as` (the post-battle root-timeline script) and the `cutSceneEnd`-setting frames in the full AS export: a completed story battle sets `afterCut` (a root-timeline frame label) and `gotoSceneKrin` (the post-cutscene destination — `overMap`/`Navigation`/`endMenu` in the original, all of which just become `game.tscn` in this port). The victory screen's Continue button (`DefineButton2_3004`) checks `if (_root.afterCut != "None") { _root.gotoAndStop(_root.afterCut); }`. Two more cutscenes exist in the SWF (`CS_INTRO`, `CS_CUT1`) but aren't referenced by `CUTSCENE_BATTLES` — out of scope unless requested separately. `CS_INTRO` is also structurally different (a `DefineEditTextTag` caption-card slideshow with a SKIP button) from the 4 in scope, which have zero text tags and no skip button.

Each in-scope cutscene is one self-contained `DefineSprite` on the root timeline, confirmed via `sprite_body`/`snapshot_timeline` plus the `_root.cutSceneEnd = true; stop();` trigger on each one's last frame:

| Label | Battle id | Sprite chid | Frames | Guide-overlay chid to strip |
|---|---|---|---|---|
| `CS_CUT2` | 109 | 3643 | 2084 | 3478 |
| `CS_CUT3` | 210 | 3928 | 621 | 3812 |
| `CS_CUT4` | 409 | 3960 | 501 | 3812 (same as CS_CUT3) |
| `CS_CUT5` | 512 (bug: currently 513) | 4038 | 1237 | 3962 |

Entry/exit is a shared fade mechanism (`frame_263/PlaceObject2_3466_80`'s `onClipEvent(enterFrame)`): fades in from black on cutscene start (`_alpha -= 5` per frame while `cutSceneEnd == false`), then on `cutSceneEnd == true` fades back to black (`_alpha += 5`) and once fully opaque resets music state and does `gotoAndPlay(gotoSceneKrin)`.

### Extraction mechanism — verified live, not just documented
`ffdec -format sprite:avi -selectid <chid> -export sprite <outdir> <swf>` renders a sprite's own internal timeline directly, independent of the root stage — tested on all 4 chids above, all render correctly (helicopters/gradient sky for CS_CUT4, a blood-splatter face reveal for CS_CUT5, etc.), with every filter/color-transform/blend-mode already correctly composited by ffdec's own renderer. This is the same fidelity bar the existing `MODEL1` battle-doll timeline never had to meet (that player only carries position/rotation/scale — no filters/color at all), so this approach actually exceeds the project's established precedent rather than falling short of it, for far less engineering effort than a from-scratch Godot timeline player would take.

Output is **lossless PNG-per-frame in an AVI container** (confirmed via `ffprobe`: `codec_name=png`, RGBA, no inter-frame compression) — this is why a 20MB SWF balloons into a 250MB+ intermediate file per cutscene (every frame is a fully independent raster, none of the SWF's vector/shape reuse survives). Expected and fine — it's a throwaway intermediate, not what ships. Running all 4 cutscenes' raw exports simultaneously needs several GB of scratch disk; the extraction script should transcode-then-delete each one rather than keeping all 4 around at once.

Each raw export also contains a **guide overlay baked into the sprite's own display list** — a red safe-frame rectangle plus an SMPTE-style color-bar/calibration strip, most likely left in by whatever studio produced these cutscenes as production QC reference. Confirmed NOT an `ffdec` rendering artifact (checked `-listconfigs` fully, grepped the ffdec source tree for `safeframe`/`testcard`/`colorbar`/`debugRect` — zero hits) and confirmed pixel-static across frames (identical bounding box at two different frame numbers in the same export). Each cutscene embeds its own separate copy at its own characterId (not one shared asset — confirmed `3812` from CS_CUT3/CS_CUT4 does not appear at all in CS_CUT2 or CS_CUT5's sprite body).

**The fix is `ffdec -removeCharacter <in.swf> <out.swf> <chid>` on a working copy before exporting** — verified this cleans the overlay with zero side effects on 3 of the 4 chids (CS_CUT4, CS_CUT5 fully re-exported and visually confirmed; CS_CUT2's export was still running as of this plan being written, same mechanism, high confidence). **Do NOT use `-removeCharacterWithDependencies`** — tested and confirmed it cascades: since the guide overlay is placed *inside* the cutscene sprite, dependency-removal treats the parent as "depending on" the child and deletes the whole cutscene sprite along with it. Plain `-removeCharacter` only drops the one placement, leaving everything else in the sprite untouched.

### Audio
The embedded audio is a `SoundStreamHeadTag`/`SoundStreamBlockTag` MP3 stream tied directly to each cutscene sprite's own timeline — confirmed via `sprite_body`: `streamSoundCompression="2"` (MP3). This is **not** reachable through `ffdec`'s CLI `sound:`/`movie:` export types (tested both against these chids directly — both silently produced nothing; those export types expect a standalone `DefineSound`-tagged character, which a sprite-embedded stream isn't). The raw MP3 bytes are directly available though: each `SoundStreamBlockTag` carries a `streamSoundData` hex attribute (confirmed present via `sprite_body`). Per the SWF10 spec, an MP3-compressed stream block is a 4-byte header (2-byte sample count, 2-byte seek-samples) followed by the actual MPEG frame bytes — walking every block in frame order, stripping the 4-byte header, and concatenating the rest produces a playable MP3. This is a well-documented SWF-audio-extraction technique, not a novel one.

### Final format
Godot's only built-in video codec is Ogg Theora (confirmed via current Godot docs — WebM support was removed from core in 4.0, would need a third-party GDExtension). The local `ffmpeg` build has no Theora encoder (checked `ffmpeg -encoders`; only `libvpx`/VP8/VP9 present) — extraction requires either `ffmpeg2theora` or a Theora-enabled `ffmpeg` build as a one-time environment dependency.

### Wiring point
`battle_scene.gd:764` calls `ZoneProgression.after_battle_won(save, battle.id, was_story)` and discards the returned `Dictionary` (which already contains a `"cutscene"` key — see `zone_progression.gd:137`). `zone_manager.gd`'s `report_battle_won()` wraps the same call and *does* return the dict, but has zero callers — dead code, not the actual path. The real Continue-button equivalent is `_on_victory_proceed()` → `_on_continue_pressed()` (`battle_scene.gd:792-801`), which unconditionally does `change_scene_to_file("res://scenes/game.tscn")` — this is where the cutscene check belongs, matching the original's `DefineButton2_3004` logic exactly.

## Task Breakdown

### Task 1: Build the extraction script (`dev/urchin_dev/swf/extract/cutscenes.py`)
- Objective: one script producing `assets/cutscenes/CS_CUT{2,3,4,5}.ogv`, run via `uv run extract_cutscenes`.
- Per cutscene: `ffdec -removeCharacter` (working copy, strip the guide-overlay chid from the table above) → `ffdec -format sprite:avi -selectid <chid> -export sprite` (video, silent) → walk `sprite_body`'s `SoundStreamBlockTag`s in frame order, strip the 4-byte MP3 block header per block, concatenate to a raw `.mp3` → `ffmpeg` mux (video + audio) and transcode to Ogg Theora → delete the intermediate AVI/MP3/stripped-SWF copy immediately (avoid holding multiple GB of intermediates at once).
- Add `CUTSCENE_SPRITES` and `CUTSCENE_GUIDE_OVERLAY_CIDS` tables to the script matching the table in Background, sourced the same way `item_icons.py`/`ability_icons.py` source their sprite ids — as documented constants with a comment citing how they were found, not re-derived at read time.
- Verify each output: frame count matches (`ffprobe -show_streams`), audio track present, no leftover guide-overlay pixels in a sampled frame (visual spot-check, not automated).
- Demo: `assets/cutscenes/CS_CUT2.ogv` through `CS_CUT5.ogv` exist, each playable standalone (e.g. via `ffplay`), audio synced, no red box/color bar visible.

### Task 2: `CutscenePlayer` scene (`scenes/cutscenes/cutscene_player.tscn` + `cutscene_player.gd`)
- Objective: a reusable player matching the original's entry/exit fade, no skip.
- `VideoStreamPlayer` (autoplay off, `stream` set per call) + a full-screen `ColorRect` (black) on top, both children of a `Control`.
- `func play(cutscene_id: String) -> void`: loads `res://assets/cutscenes/%s.ogv" % cutscene_id`, fades the `ColorRect` from opaque to transparent (tween, matching the original's ease), starts the video, awaits its `finished` signal, fades the `ColorRect` back to opaque, emits this scene's own `finished` signal, `queue_free()`s.
- No button/input handling at all — matches the confirmed absence of a skip mechanism on all 4 in-scope cutscenes.
- GUT test (add to a new `test/unit/test_cutscene_player.gd`): instantiate, call `play()` with `animation_speed` scaled up (matching the existing pattern in `battle_scene.gd`'s `_pause` helper) so the test doesn't wait real-time for fade tweens, assert the `finished` signal fires and the `ColorRect` ends fully opaque.
- Demo: calling `CutscenePlayer.play("CS_CUT2")` from anywhere fades to the video, plays it with audio, fades to black, frees itself.

### Task 3: Wire the trigger, fix the battle-id bug
- Objective: a completed story battle actually plays its cutscene before returning to the hub.
- In `zone_progression.gd`: change `CUTSCENE_BATTLES`'s `513: "CS_CUT5"` to `512: "CS_CUT5"`.
- In `battle_scene.gd`: capture `after_battle_won`'s return value at line 764 (`var battle_result: Dictionary = ZoneProgression.after_battle_won(...)`), store `battle_result.get("cutscene", "")` on the scene (e.g. `_pending_cutscene`).
- In `_on_victory_proceed()`: if `_pending_cutscene` is non-empty, instance `CutscenePlayer`, `await` its `finished` signal, *then* call `_on_continue_pressed()` — otherwise call it immediately as today.
- GUT test: assert `CUTSCENE_BATTLES`'s keys are all real battle ids (`battles.json` lookup) — this is the test that would have caught the 513 bug, so it stays as a standing regression guard. Assert `after_battle_won(save, 109, true)` (etc. for 210/409/512) returns `"cutscene": "CS_CUTn"` for each of the four.
- Demo: winning battle 109 (or 210/409/512) plays the matching cutscene before the zone hub loads; winning any other battle skips straight to the hub as before.

### Task 4: Full pass and suite run
- Objective: confirm all 4 cutscenes play correctly in the real game flow, not just in isolated extraction tests.
- Manually trigger each of the 4 story battles (or fast-path via save-state manipulation in a debug run) and confirm: fade-in, correct video, synced audio, fade-out, return to the zone hub, save state advances normally.
- Run the full GUT headless suite — new tests from Tasks 1-3 plus the existing suite, all green.
- Demo: end-to-end — win battle 109, watch `CS_CUT2` play with audio, land back in the zone hub with progress advanced, same for 210/409/512.

**DONE (2026-08-18) — automated half.** All 4 `.ogv`s regenerated (see Task 1's file history), GUT suite green: 103/103 tests, 625 asserts. Added a debug entry point
(`battle_scene.gd`'s `_maybe_start_debug_battle()`) so a specific battle can be jumped into directly instead of playing through the zone hub:
`godot --path . res://scenes/battle_scene.tscn -- --battle=108` (108/210/408/512 are the real `CUTSCENE_BATTLES` ids — note the plan's table above says 109/409, that's stale
against the actual constant, not re-verified here). Uses a throwaway slot -1 save (`GameData.new_game(-1, ...)`, never persisted) so it can't clobber a real save file.

Manual playthrough of zone 1's story battles (not yet all 4 cutscene battles) surfaced 4 real bugs unrelated to cutscene playback itself — logged in `NEXT_PHASES.md`
("Battle bugs found playtesting zone 1"): second Leath battle's dialogue doesn't play, miss-animation/MISS-text placement, radial menu not closing on click-away, and
death animation timing tied to the attacker's return instead of the target's HP hitting zero. Not investigated or fixed yet.

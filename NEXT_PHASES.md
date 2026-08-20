# Next phases

**Every phase of the revival roadmap is complete** (2026-07-18). The full game loop runs and is tested end-to-end: zone orb -> battle selection from quest progression -> roster assembly (player with
talents/gear, companions, enemies) -> playable battle scene with paper-doll visuals, input, and audio -> victory rewards, leveling, drops, achievements, autosave -> back to the zone with progress
advanced. 83 GUT tests / 553 asserts cover it headless.

Delivered, in order: data pipeline fixes, zones + shops, damage/heal/focus formulas, the buff system, the save system, skill/talent trees, the battle turn-loop orchestrator + enemy AI, post-battle
rewards, leveling/respec, zone battle content wiring + the companion party system, item equip validation, the store UI repair, the audio manager, achievements, and the character paper doll + battle
scene. See `KNOWN_GAPS.md` for the handful of deliberate approximations and `SWF_DIFFERENCES.md` for web-vs-Steam data findings.

## Polish backlog (nothing blocks anything - pick by taste)

The UI/scene layer was rebuilt 2026-07-18: main menu (save slots + new-game flow), 7 per-zone hub scenes with SWF-exact orb positions (`scenes/zones/`), the zone-hub shell (`game.tscn` + `game.gd`),
the hotbar (menu buttons / world-map / zone progress), the zone map with SWF-exact button positions, and the asset tree reorganized (`assets/backgrounds/{hub,battle,sky}`,
`assets/ui/{hotbar,battle,store,zone_map}`). Base resolution is the original 800x600 stage (canvas_items stretch), so every SWF-extracted coordinate drops in 1:1.

- **Timeline-accurate animations**

  - **DONE (2026-07-18) - first six labels.** The full MODEL1 timeline (371 frames at 30 fps, per-part affine matrices) lives in `resources/sprites/model1_animations.json` (regenerate:
    `swf_extraction/extract_model1_animations.py`). `character_visual.gd` plays `stand` (idle loop), `hit`, `dead`, and the melee sequence `run` -> `Attack` -> `runback` with run-to-target motion
    (`play_melee(offset)`, battle scene paces on `melee_finished`).
  - **DONE (2026-07-21) - attack variants.** Each move's `addNewMove` param 12 is its animation label (`Ability.animation_label`: Attack / Attack_Upper / Attack_Stab for Melee strikes;
    Krin.Firebolt-style projectile clip names for Missile moves; unused for Shock, which casts). Melee moves run to the target and damage lands at `attack_connected` (mid-swing), with runback after.
  - **DONE (2026-07-21) - movement/timing model.** The faithful krinMelee port (see `DECODED_ALGORITHMS.md`): eased ~0.47 s dash that interrupts the run label, impact at 0.5 s into the strike, the
    strike flowing through `attack2` (the downswing - not a variant), runback at 1.0 s with the eased return.
  - **DONE (2026-07-21) - cast, stun family, and Missile projectiles.** `cast` (189-219) now plays the real MODEL1 label for both Missile and Shock casters; Shock resolves its impact instantly
    (matches the source's same-tick `BAMBAMBAM`), Missile awaits a krinBoltMake-ported `Projectile` bolt's arrival before landing the hit. The stun family (`stun` 220-239 one-shot ->
    `stun2` 240-279 loop -> `outofstun` 280-295 one-shot) is a real value-comparison state machine (`CharacterVisual.enter_stun`/`exit_stun`) driven off the krinBuff `STUN` running total, not a
    fixed `!= 0` toggle - see `DECODED_ALGORITHMS.md`.
  - **Remaining:** the MODEL4 (female) timeline.

- **Missile projectile art** - **DONE (2026-08-19)**, see `.superpowers/sdd/2026-08-18-missile-projectile-art/` for the full 6-task breakdown. `Projectile` no longer draws a generic tinted
  circle+line for every bolt - it plays the real per-element clip art, and impact effects land at the target on every hit, matching `DECODED_ALGORITHMS.md`'s krinBoltMake section:

  - All 51 clips (15 bolts, `KrinTrail`, 35 `BOOM_*`/`ex_*` impacts) extracted from the web-build SWF into `assets/vfx/{bolts,trail,impacts}/<clip>/<frame>.png` - per-frame folders, not
    packed spritesheets, a deliberate architecture change made mid-plan: two impact clips (`BOOM1`, `BOOM2`) pack wider than Godot's 32768px texture-import cap, which silently rescales the
    whole sheet and desyncs every packed frame's region. Those folders are still where every clip's frames live, but nothing reads them by folder path at run time any more - see the VFX
    registration scenes entry below.
  - `Ability.visual_effect_color` parses the `11_visual_effect_color` hex column (the real `colortobe` glow value), replacing the cast glow's earlier element-color approximation for both
    Missile and Shock moves - Melee is untouched, it never sets `colortobe`.
  - `ImpactEffect` - a one-shot `BOOM_*`/`ex_*` clip player that frees itself when its animation finishes. One genuine deviation from source: the original never explicitly removes its own
    equivalent clips (`"bbb"+counter` in `frame_42/DoAction_4.as`'s krinBoltMake) - a deliberate improvement, not an unfaithful port.
  - `Projectile` rewritten from a bare script into a real `.tscn`: the bolt plays its real clip untinted (alpha-only fade-in), the trail is a genuine 33-frame fade-in/fade-out pulse baked
    into its own timeline (not manually faded), RGB-tinted by `trail_color`, spawned once at the bolt's position and grown via `scale.x` every tick. Its `arrived` signal was renamed
    `reached_target`. A miss now flies the bolt fully past the target off this port's own screen bounds instead of stopping at it (`did_hit` gates whether `reached_target` frees the bolt
    immediately or lets it keep flying), matching `strikeSuccess`'s hit/miss branch. The `Bolt`/`Trail` `AnimatedSprite2D` children this task gave it were replaced a day later by a generated
    scene per clip - see the entry below.
  - `battle_scene.gd` wires `_spawn_impact()` at all three impact hook points - melee's `on_impact` lambda, the Shock branch, and missile's `_fire_projectile` (after `reached_target`) -
    gated on `result.type != MISS` exactly like krinBoltMake's own `strikeSuccess` check, and `_fire_projectile` now instances the real `Projectile` scene instead of a bare `Projectile.new()`
    (dormant breakage left over from the scene-conversion task, since no existing test drove a live Missile move far enough to reach it - fixed here).

  GUT suite green: 169/169 tests, 844 asserts. Manual visual check (a live Missile move showing real bolt/trail art, a miss flying past, the cast glow tinted by the move's own color) was not
  completed - this environment has no interactive/screenshot tooling for a native (non-browser) Godot window, worth a project owner eyes-on pass.

- **VFX registration scenes** - **DONE (2026-08-20)**, see `.superpowers/sdd/2026-08-19-vfx-registration-scenes/` for the full 6-task breakdown. Closes the registration-point mismatch parked at
  the end of the missile projectile art work above: bolts and impacts drew with Godot's default `centered = true`, which centers a clip on its own bounding box instead of on the origin the
  source SWF drew it around, and a rotating bolt swings visibly wide of a pivot that far off. Every clip now has a generated scene of its own with its real registration point baked in:

  - `make_timeline_bounds()` (`dev/urchin_dev/swf/xml_lib.py`) unions a sprite's rendered bounds across every frame of its own timeline, recursing the same way into nested children - some
    clips' children are independently-animating sub-timelines of their own. The existing `make_char_bounds()` (first frame only) is untouched; the doll-art pipeline depends on it.
  - `extract_vfx_offsets` writes `assets/vfx/vfx_offsets.json`: one real `x`/`y`/`w`/`h` per clip in natural unzoomed px, the same convention `resources/sprites/doll_offsets.json` uses. Sizes
    come from the extracted PNG's own pixel dimensions, because ffdec's PNG exporter bakes a glow filter's footprint into the canvas and no bounds tag in the XML can see it.
  - `extract_vfx_scenes` bakes each clip's frames and its offset into a scene of its own under `scenes/battle/vfx/{bolts,trail,impacts}/<clip>.tscn` - `centered = false`, the real `position`,
    and the `scale` that undoes the extractor's 2x zoom. Both scripts are one-time generators: run, output reviewed and committed, not part of the normal build.
  - `Projectile` and `ImpactEffect` instantiate the resolved clip's scene by name instead of scanning a PNG folder, so nothing computes a position or a scale correction at play time.
    `battle_scene.gd` is unchanged. `VfxFrames.load_frames()` and `VfxFrames.VFX_SCALE` are retired; `sanitize()` (clip name -> scene filename) is all that is left of that class.
  - The final review caught 13 of the 51 clips landing on wrong bounds, from two separate causes. `snapshot_timeline()`'s matrix search covers a fixed 1200-character slice after each
    `PlaceObject` tag, which can reach past a tag carrying no matrix of its own and borrow the next tag's. And `DefineMorphShapeTag` children were dropped as if they held no art, which
    shrank `BOOM_STAR`'s whole computed footprint to 22.2x23.25 px against a real 169.5x161.75. Both are fixed inside `make_timeline_bounds()` and private helpers only it calls, leaving
    `snapshot_timeline()` alone for the five other extractors already built on its current behavior. `extract_vfx_offsets` now also reports any clip whose horizontal and vertical glow
    padding disagree by more than 1 px, which is how all 13 of these would have shown up at extraction time.

  GUT suite green: 178/178 tests. All 51 clips' computed bounds were checked against ffdec's own SVG-per-frame export, an independent renderer, and every edge agrees to within 0.05 px. Still
  no visual check: this environment has no screenshot tooling for a native Godot window, so a project owner eyes-on pass on a live Missile move remains worth doing.

- **Battle bugs found playtesting zone 1 (2026-08-18)** - **ALL 4 FIXED**, surfaced manually verifying the cutscene work above (see the debug battle-jump entry point in `.claude/plan_cutscenes.md`'s Task 4 note):

  - **FIXED** - the first Doctor Leath battle (104) played its scripted dialogue; the second (105, "Twisted Experiment") didn't. Root cause: `BattleRunner.setup()` calls `_drain_speeches()` once before any `advance_half_turn()` exists, to catch speeches scripted for `turnTime:0` (fire the instant the battle begins) - but `battle_scene.gd` never reads `runner.events` directly, only whatever each `advance_half_turn()` call returns (`events.slice(events_start)`, sliced from THAT call's own starting point). Anything appended during `setup()` sits before every future call's slice window and is never played - silently dropping any `turnTime:0` speech in every battle, not just 105 (104 has 3 speeches, 2 of which aren't `turnTime:0` and did play, masking that its first line was also lost). Fixed by having `setup()` return its own pre-loop events the same way `advance_half_turn()` does, and having `_battle_loop()` play them first. Covered at both layers: `test_battle_runner.gd`'s `test_setup_returns_its_own_turn_time_zero_speeches`, `test_battle_scene.gd`'s `test_setup_time_speech_plays_through_the_real_scene`.
  - **FIXED** - a miss skipped the attack animation entirely, showing only a floating `MISS` label. Root cause: `_execute_move_action()` logged a miss as its own bare `"miss"` event type instead
    of a `"move"` event, and `battle_scene.gd`'s `_play_move_event()` (the run/swing/cast presentation) only ever triggers on `"move"` - a genuine deviation from the original, which dispatches the
    caster's animation purely off the move's own type (`addNewMove` param 10), with hit/miss only swapping the impact-time damage NUMBER to a special miss frame (see `DECODED_ALGORITHMS.md`'s
    "Battle presentation per animation type"). Fixed by logging a miss as a `"move"` event with `result: {"type": "miss"}` - the full animation now plays, and `_show_move_result()` shows `MISS`
    at the actual target instead of a damage number. Re the target-slot part of the report: read the old code and confirmed `target_slot` was always set to the real target, both in the event and
    in the `_float_text()` call that displayed it - not independently investigated further, so unconfirmed whether that was a real second bug or just how a frozen no-animation frame read visually;
    worth another look after this fix if `MISS` still seems to land on the wrong character. Covered by `test_battle_runner.gd`'s `test_misses_are_move_events_not_a_separate_type`.
  - **FIXED** - clicking a character opened their radial ability menu, but clicking empty space didn't close it (only clicking a different character did, via `_on_unit_clicked`'s own
    `_close_radial_menu()` call). Root cause: there was no click-away handling at all. Added `_unhandled_input()` - a unit's `hit_button` and every orb are real `Button`s, so a click on either
    is consumed before it gets there; it only ever fires for a click that landed on neither, i.e. empty battlefield space. Covered by `test_battle_scene.gd`'s
    `test_radial_menu_closes_on_click_away`.
  - **FIXED** - a unit's death animation waited until the attacker returned to its starting position, instead of firing as soon as HP hits zero. Root cause: the queued `"death"` event only
    gets processed by `_play_events()` after the whole preceding `"move"` event's `await` resolves - for melee, that's after the caster's runback finishes, not when the killing blow lands.
    `_show_move_result()` (the impact moment - damage number, HIT flinch) is where death needs to fire too. Fixed by playing death synchronously there when `result.target_died` is true (skipping
    the HIT flinch in that case, as before), and skipping the later queued `"death"` event's own playback when its `cause` is `"move"` (already played) - `damage_over_time` deaths (buff ticks,
    no impact moment to hook into) still play from the queued event as before. Covered by `test_battle_scene.gd`'s `test_death_plays_at_impact_not_after_caster_returns`.

- **Battle screen niceties** - **DONE (2026-08-18)**, see `.claude/plan_battle_screen_niceties.md` for the full task breakdown. All 5 items shipped:

  - The original hotbar-style battle UI art - `BottomBar/Backdrop` now renders `assets/ui/battle/hotbar_background.png` (a `TextureRect`, was a plain `ColorRect`), instead of leaving the
    extracted art unused.
  - The 120-second decision countdown - `battle_scene.gd`'s `_process()` ticks `_decision_timer` down from `BattleRunner.BATTLE_TIME_LIMIT` while `_player_action_pending` is true, shown as
    a ring (`assets/ui/battle/battle_pbar_full.png`) + numeric label in the bottom bar's `Panel3`. Visual-only, deliberately does NOT force-pass the turn at 0 like the original did - this
    port's turn-based flow already removed real-time pressure everywhere else, and reintroducing it here wasn't asked for.
  - Target highlighting - a hover ring around each unit fades in over ~0.17s and out over ~0.67s (source-verified 30fps timing), but only fades in during the player's own decision
    window (fade-out always plays, ungated). Alongside this, the radial ability menu's dismissal was corrected to match the live original game: moving the mouse away from the clicked
    unit and its fanned-out orbs fades the menu out, replacing this port's earlier click-away guess, which the project owner confirmed doesn't match the real game.
  - Buff icons over units - `unit_overlay.gd` shows up to 7 active buff icons per unit, sorted by remaining duration descending, using art from the buff icon sheet, `DefineSprite 100`
    (`DefineSprite 2427` is the ability sheet, a different clip). The original picks a buff's icon by frame label: buffs are registered under their name
    (`addNewBuffKrin("TWINGUARDIANS", ...)`, `frame42/sonny2_addNewBuffKrin.txt:543`) and moves name the buff they apply as a string, so `buffIcon.gotoAndStop(buffId)` gets that name
    and Flash resolves it as a label. `buffs.json`'s numeric `id` is only the order those 470 registration calls run in; it never reaches the sheet. The sheet holds 33 distinct
    drawings across 400 frames and labels several buffs onto each, so 8 of the 419 extracted icons (about 2%, including FIRESAM and TWINGUARDIANS) share frame 1, a plain filled
    rounded rectangle. The source itself groups them that way. Also fixed along the way: buff id 0 (TWINGUARDIANS) is a real buff, not an empty-slot sentinel (the sentinel used
    everywhere else in the codebase is `buff_id: -1`) - the original filter silently dropped it.
  - A combat log panel - `CombatLogPanel` (the project's first `RichTextLabel` panel), off/hidden by default and toggled via a new "Log" button in the bottom bar's
    `Panel3`, per the project owner's explicit choice. `_format_line()` mirrors `battle_scene.gd`'s `_play_events()` event-type match exactly, so every event type that already drives
    animation/audio also gets a readable line, appended live as the fight plays rather than after the fact.

  GUT suite green: 147/147 tests (assert counts vary run to run since several integration tests drive a real RNG/AI battle to completion - one clean run: 731 asserts).

  Final-review fix wave (2026-08-18): a stale radial-menu fade tween could silently close a brand-new menu opened on a different unit while an earlier one was still fading out - fixed by killing
  the in-flight tween in `_close_radial_menu()`. The combat log's `RichTextLabel` used to sit inside a `ScrollContainer`, and the two scroll mechanisms fought - the label auto-scrolled inside its
  own oversized viewport while the outer container stayed parked at the top, so new lines never actually became visible; fixed by making the label the panel's direct child. Four smaller items were
  also cleaned up: `refresh_buffs()` now skips rebuilding the buff row when nothing changed (it was rebuilding on every combat event, dropping an open tooltip mid-hover for no reason); the combat
  log caps at 200 lines instead of growing unbounded over a long fight; `buff_icons.py`'s inline sanitize regex is now a named `sanitize()` matching `item_icons.py`'s own convention, mirrored
  exactly by `BuffIcons._sanitize()` in GDScript; `pyproject.toml`'s `extract_buff_icons` entry moved to its alphabetical position.

  **Deferred, not fixed** (all cosmetic, low-value): the hover-ring's fade tween still fires (a 0-length no-op) on every mouse enter/exit during an AI turn, harmless but wasteful; the combat log
  panel, when toggled on, can visually overlap and swallow clicks on slot 5's unit overlay (low impact since the log is off by default); `BottomBar/Backdrop`'s texture is stretched slightly larger
  than the Panel1-3 region it was measured against - worth an eyes-on check, not a code fix.

- **Item click-n-drag** - **DONE (2026-08-18)**, project owner request 2026-07-18. See `.claude/plan_item_drag_and_drop.md` for the full task breakdown. `ItemSlot` is both drag source
  (`_get_drag_data`, a semi-transparent 31x31 preview) and drop target (`_can_drop_data`/`_drop_data`) via Godot's built-in Control drag API - inventory<->inventory swaps, inventory<->equip
  equips/unequips, and dropping on the sell button sells (hover previews the price in its tooltip). New `GameData.swap_inventory_slots`/`unequip_to_slot` back the two operations click never
  needed. Click-to-equip/click-to-keep is untouched, both interaction modes work simultaneously. One real deviation from the plan found while executing it: `InventoryPanel.sell_pressed` now
  carries the `GameItem` directly (not an `ItemSlot`) and the sell-button drop emits that signal rather than calling `GameData.sell_item()` directly - `store_window.gd`'s handler also calls
  `refresh_store()` afterward, which `InventoryPanel` has no way to know about, so routing both the click and the drag-drop through one signal keeps that behavior identical either way.
  Click-to-equip/click-to-keep stands in until then.

- **Menu screens**

  - **Built (2026-07-18)** from the original menu clip (DefineSprite 3142, stage origin 400.5/222.4; frame 1 = inventory, 16 = store, 25 = abilities, 45 = achievements):
    `scenes/ui/menu/inventory_window.tscn`, `abilities_window.tscn`, `achievements_window.tscn`, plus the rebuilt `scenes/ui/store/store_window.tscn` - all wired to hotbar buttons with the green
    active-icon glow. Chrome art extracted at 2x into `assets/ui/menu/`.
  - **DONE (2026-08-17)** - party portrait faces. `dev/urchin_dev/swf/extract/faces.py` rewritten to export the face clip (`DefineSprite 2978`) directly via `ffdec`'s own sprite renderer instead
    of reassembling it shape-by-shape - the old per-shape compositor only carried position/scale, silently dropping the filters/color transforms several characters' portraits depend on (e.g.
    Veradux's glowing eyes), so every portrait rendered as a near-black silhouette. Also dropped the old chrome-compositing pass entirely (pasting sprites 333/2896/2895 onto the face) - confirmed
    via `inventory_window.tscn` that the slot border already comes from `item_slot.tscn`, the same reusable bordered-slot scene used everywhere else; compositing it a second time onto the face was
    both redundant and the source of a stray-artifact bug. Now extracts all 40 named portraits in the clip (5 companions + the player + every named story NPC - `Doctor Hedger`, `The Warden`,
    `Clemons The Deceiver`, etc.), not just the 6 party-facing ones the old script hardcoded.
  - **Still missing on these screens:** the abilities tutorial callout box and drag-to-socket placement (click-to-place stands in). (Ability orb icons are also done - see the ability menu redesign
    phase below.)

- **Screens not yet built** (hotbar buttons dimmed): options, respec button flow (logic in `Leveling.respec`), team-select (`PlayerSave.party_deployed` is ready), character appearance customization
  (SkinSet/HairSet/GSet persistence). References in `assets/references/`.

- **Item icons**: 325 original icons extracted from the icon sheet (sprite 2064) into `assets/ui/items/` with 311 items repointed (2026-07-18).
  - **DONE (2026-08-17)** - `extract_item_icons.py`'s `ICON_OVERRIDES` idempotency check tested two independent substrings (the override path anywhere in the file, `slot_image` pointing at
    `icon_slot` anywhere in the file) instead of confirming they were the same `ext_resource`. A leftover duplicate resource on item 5 (A Broken Pipe) made both substrings true on unrelated lines,
    so the check read "already patched" and silently skipped repointing it, run after run, even with a correct `ICON_OVERRIDES` entry present. Fixed (tie the check to one atomic string); item 5
    now shows its real icon (`assets/item_slot_icons/OTHER/A_Broken_Pipe.png`) instead of sprite 2064's mismatched frame. See `docs/item-icon-extraction.md` for the extraction commands.
  - **DONE (2026-08-17) - content audit.** The "~135 items with no icon-clip label" figure this bullet used to carry was stale - re-checked every item's sanitized name against all 327 real
    (non-empty-snap) labels in sprite 2064 directly. Actual count today: **4** items with no match at all - `Tool` (id 1), `Golden Crowbar`/`Golden Pipe`/`Golden Axe` (ids 681-683, cosmetic
    variants with no distinct icon frame in the original sheet either - fuzzy-matched against every label, no close candidate exists for any of the four) - plus item 0's `None` sentinel (the
    empty-slot placeholder, correctly iconless, not a real item). All four already fall back to `assets/item_slot_icons/` correctly; no further fix needed for them.
    Two other things this audit turned up:
    - **Fixed**: `scripts/editor/items.gd`'s own `SLOT_ICON_OVERRIDES` (a second copy of the id-5/id-11 override table, used when regenerating `.tres` files from `items.json` from scratch) only
      had id 11 - item 5's fix would have silently reverted the next time anyone ran that script. Added id 5; both files now cross-reference each other's override table so they don't drift again.
    - **Not fixed, lower priority**: 4 pairs of items share a display name and so share one slot icon by the current sanitize-key lookup (`Surgery Blade` ids 16/501, `Frosted Leggings` ids
      125/322, `Riot Shield` ids 188/653, `Metal Shield` ids 203/516). Two pairs (`Surgery Blade`, `Metal Shield`) already share the same equipped paper-doll art (`looks`), so sharing an icon is
      correct. The other two (`Frosted Leggings`, `Riot Shield`) have *different* `looks` per id, meaning two visually-distinct equipped items currently show the same slot icon - a real but minor
      content gap, not investigated further this pass.
    Still worth a manual side-by-side pass against the live game for the 309 items that DO get an automatic sprite-2064 match, since id 5/11 prove a labeled frame can point at the wrong content
    without tripping any of the checks above.
  - **DONE (2026-08-18)** - `item_icons.py` rewritten the same way `faces.py` was: every frame now exported directly via ffdec's own sprite renderer (`-format sprite:png -selectid 2064`) instead
    of reassembled shape-by-shape. The old per-shape compositor only carried position/scale off each PlaceObject, silently dropping any colorTransform/filter - confirmed on item 592 "Ancient Cage",
    whose old icon was missing the glowing yellow ward markings the live game shows. All 327 icons re-extracted; likely also the explanation for the 10 icons flagged above as changing pixels under
    a newer `ffdec` (that bullet's anomaly list predates this rewrite and is superseded by it).
    Took two passes to get the crop right. `DefineShape 1913`, present in every frame, looked at first like a stray editor-bounds guide (same shape of bug as the old `SKIP_CIDS`, which had
    excluded it from compositing on that same assumption) - stripping it via `-removeCharacter` seemed to fix things, until a wider check showed most icons had grown far past their old size (item
    69 "A Broken Pipe" alone went from a correct 63x63px to 101x140). 1913 turned out to be a real SWF clip mask (`clipDepth="15"` on its own placement, depth 2) - the same clipping mechanic
    `cutscenes.py`'s wrapper sprites use, just within one timeline instead of split across a wrapper/inner pair - and stripping it let ffdec render everything the mask normally hides. Left in
    place, every frame comes back correctly masked to ~62x62px regardless of that item's own art size, and just needs trimming off the mostly-transparent full-timeline export canvas (`ffdec` sizes
    every frame's PNG to the whole 856-frame timeline's union bounds) - no fixed-box math needed, same as `faces.py`. Item 0's `None` placeholder now gets a real (blank, 1x1) icon too, a side
    effect of no longer skipping frames with an empty PlaceObject snapshot. `ICON_OVERRIDES` (items 5/11's hand-picked-icon table) removed from this script now that the fixed extraction agrees with
    the fallback art those two items were pointed at - `scripts/editor/items.gd`'s independent `SLOT_ICON_OVERRIDES` copy still exists and still applies to those two when regenerating `.tres` from
    scratch, which is fine since both sources now render the same icon either way.

- **Zone hub art for zones 6/7**: no dedicated hub art exists in the extracted assets - the scenes reuse the wide battle backdrops (`battle/CHURCH.png`, `battle/STREETS.png`), aspect-cropped. Zone 7's
  training orb position is also borrowed from zone 6 (the original Steam-only zone frame has no training orb placement).

- **Cutscenes** - **DONE (2026-08-18)**, see `.claude/plan_cutscenes.md` for the full task breakdown. All 4 cutscenes (`CS_CUT2`-`CS_CUT5`) extracted as `.ogv` with audio (via ffdec's own
  sprite:avi renderer, every filter/color-transform/blend-mode baked in correctly), a `CutscenePlayer` scene matches the original's fade-in/fade-out, wired into the victory-screen Continue flow.
  GUT suite green: 103/103 tests, 625 asserts.

  Also fixed along the way, a real progression-blocking bug (found manually playtesting zone 1, not just a cutscene issue): `CUTSCENE_BATTLES` was keyed to 108/408/512 instead of the real
  109/210/409/513, because `resources/battles/` was missing those three ids entirely (`dev/urchin_dev/convert/battles.py`'s raw input mislabels each zone's real final story battle with the
  next block's seed id - 109 came through as 199, 409 as 499, 513 as 599; see that file's `MISLABELED_BATTLE_IDS` comment for the mechanism, confirmed via `SWF_DIFFERENCES.md`'s already-documented
  `battleCreationID` reset-statement quirk). This meant CS_CUT2 fired one battle before zone 1's actual boss fight, and the boss fight itself (109) couldn't load at all - blank/white screen on
  the story orb, zone 2 never unlocking since quest progress could never pass `progress_max`. Fixed at the source (id corrected at conversion time, the 3 affected `.tres` regenerated,
  `CUTSCENE_BATTLES` back to the real ids).

  A real playthrough of the fixed battle 109 then surfaced two more bugs, both fixed: `_on_continue_pressed()` always returned to the current zone hub after a
  cutscene, when the original's `gotoSceneKrin` (frame_219) actually opens the zone map for CS_CUT2/CS_CUT4 (both unlock a new zone) and only stays on the hub for
  CS_CUT3 - added `ZoneProgression.CUTSCENE_GOTO_SCENE`/`ZoneManager.open_zone_map_on_load` to thread that through. Separately, the zone map's connector lines
  between zones had never been built at all (`frame_449`'s procedurally-drawn `krinMapper.lineMC`, colored by unlock state) - ported into a new
  `scripts/zones/zone_map_connectors.gd`. GUT suite green: 104/104 tests, 629 asserts.

- **Shatter Bolt**: the one `"Attack"`-category move - the original never handled it either.

## Ability menu redesign

**DONE (2026-07-23).** `scripts/ui/menu/abilities_window.gd` and `scenes/ui/menu/abilities_window.tscn` now match the original's richer three-region layout: real icon art extracted from
`DefineSprite 2427` (104 `FrameLabelTag`s, confirmed full coverage of every active move and every passive buff family actually used in `TalentTree.TREES`), a rich floating tooltip
(icon + title + description + cost/cooldown + next-rank preview) shown on hover over tree nodes, pool rows, and wheel sockets, prerequisite-colored
connector lines drawn between talent-tree nodes, and the pool row migrated to a reusable `ability_pool_row.tscn` (icon + name `AbilityPoolRow` component, instanced 5x, `populate()`/`clear()`
driven). The tooltip's data is still built by a pure `AbilityTooltipBuilder` (`build_sections()`, renamed from `build_fields()`), but it's now rendered by the shared `GameTooltip` autoload
rather than a dedicated `AbilityTooltip` scene - see the **Rich tooltip rework** section below.

Two known, deliberate gaps: passive-node tooltip descriptions render blank, because the source `buffs.json` has no tooltip text for any tree-passive buff (verified across all 53 rank-entries
in all 14 buff families actually used - not a bug); and the original's ~5-frame hover delay before showing the next-rank preview text (frame label `GO7`) was not reproduced - the rich tooltip
shows everything immediately on hover.

## UI architecture: native Godot Containers instead of code-built controls

Everything under `scripts/ui/` originally built its Control tree imperatively at runtime (`Button.new()`, `StyleBoxFlat.new()`, manual `.position`/`.size` assignment). `item_slot.gd`,
`store_window.gd`, `inventory_panel.gd`, `abilities_window.gd`, `achievements_window.gd`, `hotbar.gd`, `inventory_window.gd`, `main_menu.gd`, `victory_screen.gd`, and now `battle_scene.gd` are all
migrated (see the **DONE** notes below) - `menu_theme.gd`'s `add_texture_rect`/`add_label` helpers that this phase called out as a symptom are deleted entirely, and this phase is now fully
complete. The goal was to migrate toward declarative `.tscn` scenes with real Container
nodes, matching how Godot's own demo projects are built - reference clone at `/Users/julianperge/DEVELOPER/git_repos/godotengine/godot-demo-projects/2d/` (`dodge_the_creeps`, `platformer/gui`, and
`role_playing_game/combat` were surveyed). Conventions worth adopting, in order of impact:

- **One small reusable `.tscn` per repeated element, instanced via `PackedScene`.** The RPG demo's `combat/interface/info.tscn` (a standalone "stat card": Name label + HP ProgressBar, no script of
  its own) is instantiated once per combatant by `ui.gd` (`@export var info_scene: PackedScene`, loop of `.instantiate()` + set a couple of child properties + `add_child()`), never built
  node-by-node in a loop. This is the direct template for `item_slot.gd`: make an `item_slot.tscn` (icon TextureRect + price Label + hover highlight, laid out in the editor) and have
  `store_window.gd`/`inventory_panel.gd` instance it per slot instead of constructing each slot's Controls from scratch in code.
- **Scripts hold `@onready` references and mutation methods, not tree-building.** Across every demo reviewed (`hud.gd`, `coins_counter.gd`, `pause_menu.gd`), the attached script's job is limited to
  `$Path/To/Node` lookups plus small functions that set `.text`/`.value`/`.visible` on nodes the editor already laid out - never constructing the nodes themselves at runtime.
- **Containers + size_flags for anything that reflows; anchors_preset + offsets only for fixed/pinned chrome.** `GridContainer`/`HBoxContainer`/`VBoxContainer`/`PanelContainer`/`CenterContainer`
  children use `size_flags_horizontal/vertical` (`EXPAND_FILL` / `SHRINK_CENTER`) and let the container solve layout; static HUD pieces that never reflow (score labels, pinned counters) just use an
  anchor preset plus manual offsets, no container needed.
  Store/inventory grids and the ability pool list are exactly the reflowing case containers are for.
- **Centralize styling in Theme `.tres` resources, not code.** The demos define `Button`/`Panel`/`ProgressBar` styles once in a shared `theme.tres` (`StyleBoxTexture` or `StyleBoxFlat` per control
  type), use `theme_type_variation` for one-off panel styles that share most of a base style, and reserve `theme_override_*` for genuine per-instance exceptions. This project didn't go as far as a
  shared `theme.tres` - each migrated `.tscn` bakes its own `theme_override_*` properties per node instead - but `menu_theme.gd`'s `add_texture_rect`/`add_label` runtime-construction helpers, which
  existed only because nothing was theme-driven yet, are now deleted (zero remaining callers once `inventory_window.gd`/`main_menu.gd`/`victory_screen.gd` were migrated). `menu_theme.gd` itself
  stays - its remaining members (`ELEMENT_COLORS`, `STAT_LABELS`/`STAT_COLORS`, `bar_fill_fraction()`, `texture()`, `format_money()`, etc.) are genuinely reusable non-construction utilities.

Sequencing note: this is a large, cross-cutting change and nothing above blocks it from happening incrementally - `item_slot.gd`/`store_window.gd` are explicitly named as the smallest, most
self-contained starting point. Since the ability menu redesign above is new work rather than an existing screen, it's worth doing that phase in the NEW `.tscn`-plus-Container style directly, once
the pattern is proven on the store, rather than building it flat now and re-migrating it later.

**DONE (2026-07-21):** `scripts/ui/store/item_slot.gd`, `scripts/ui/store/store_window.gd`, `scripts/ui/inventory_panel.gd`, `scripts/ui/menu/abilities_window.gd`,
`scripts/ui/menu/achievements_window.gd`, and `scripts/ui/hotbar.gd` migrated - `item_slot.tscn` now owns the hover highlight as a real child node, `store_window.tscn` now owns every static chrome
node plus a `GridContainer` for the 15-slot catalog, `inventory.tscn` now owns its panel/title/money-bar chrome plus a `GridContainer` for the 6x6 slot grid, `abilities_window.tscn` now owns its
static chrome/attribute panel plus a `VBoxContainer` for the 5-row ability pool (the 28-node talent tree keeps its irregular-pitch positions and fully data-dependent per-node styling in code via a
reusable `talent_node.tscn`, the same instanced-`PackedScene` pattern as `ItemSlot`, and the 8-socket wheel stays entirely code-driven by design), `achievements_window.tscn` now owns its chrome plus
all 10 fixed-position achievement plates (only each plate's locked/unlocked `StyleBoxFlat` and label color stay code-driven), and `hotbar.tscn` - already the most declarative of the group, built
with real `HBoxContainer`/`CenterContainer`/`VBoxContainer` layout from the start - now also owns the quit button and every button's glow/icon overlay children, with only the per-instance
hover-tint wiring left in code. `scripts/ui/menu/inventory_window.gd` is also migrated - `inventory_window.tscn` now owns its static chrome (backdrop, close button, status label, left/center panel
textures, name/level/experience-row content, all 5 stat rows, Piercing/Defense titles), all 16 element-bar tracks and fills (8 "per" + 8 "def"), the party bar background, and all 6 fixed portrait
frames (each an instance of `item_slot.tscn` with a static `Face` child) - only the bars' fill height/position (`_update_bar()`) and the portraits' tooltip/dimming (`_refresh_portraits()`) stay
code-driven, both genuinely live-save-dependent. `scripts/ui/main_menu.gd` is also migrated - `scenes/main_menu.tscn` (already partially declarative before this pass) now owns the title label, the
class-select screen's chrome and all 3 fixed-order class cards (Psychological/Biological/Hydraulic, each wired via a `[connection]` with the class id bound as a literal) plus its Cancel button,
and the settings screen's chrome, difficulty picker (3 buttons sharing one `ButtonGroup` sub-resource), and 3 toggle rows (Tutorial/Sound/Autosave, each with its own named handler method since
their side effects differ - Sound's also mutes an audio bus) plus its Start/Back buttons - only the save-slot button list stays code-driven (`_refresh_slot_buttons()`, count is `GameData.NUM_SLOTS`
and each label depends on live save data). `scripts/ui/menu/inventory_window.gd`, `scripts/ui/main_menu.gd`, and `scripts/battle/victory_screen.gd` are also migrated, completing the retirement of
`menu_theme.gd`'s runtime `add_texture_rect`/`add_label` helpers (both deleted - zero remaining callers). `victory_screen.gd` didn't have a `.tscn` at all before this - it now has
`scenes/battle/victory_screen.tscn` for its static chrome, plus a new reusable `scenes/battle/victory_experience_row.tscn` (instanced once per fighter, 1-3 depending on the deployed party) for
what used to be raw per-row `MenuTheme` calls, matching the same instanced-`PackedScene` pattern as `ItemSlot`/`talent_node.tscn`. Only the drop slots (`ItemSlotScene`, count varies per battle)
and the embedded `InventoryPanel` stay code-instanced, both already using the established `PackedScene` pattern from the start. `battle_scene.gd`'s instantiation call site was updated from
`.new()` to `preload(...).instantiate()` accordingly.

**DONE (2026-07-23):** `scripts/battle/battle_scene.gd` is also migrated, completing this phase entirely. `scenes/battle_scene.tscn` now owns the bottom bar's static chrome (backdrop, three
panels, the Pass button, and the Retreat button - the Pass ring's `_draw()` callback stays code, its color depends on live turn state) and a static `SkyFill` node (only its color/size mutation,
sampled from whichever zone background loads, stays code). Two new reusable scenes cover the two genuinely-variable-count-but-fixed-structure pieces: `scenes/battle/unit_overlay.tscn` (name,
health/focus bars, hover ring, hit button - instanced once per battling unit, 2-6 depending on the roster) and `scenes/battle/stance_row.tscn` (name + 5 stance buttons - instanced once per
deployed companion, 0-2), both matching the same instanced-`PackedScene` pattern as `ItemSlot`/`talent_node.tscn`/`VictoryExperienceRow`. The radial ability menu, floating combat text, and
projectile bolts all stay fully code-driven, unchanged - each is transient, recomputed on every occurrence, with no reusable structure a static template would capture.

## Enum conversion audit

**DONE (2026-08-18).** Prompted by the project owner adding static typings across the codebase, then asked to also reduce copy-paste and re-audit for anything the first pass missed. 9 enums
landed one commit at a time (plus a fresh re-audit before starting, since a few of this section's own file:line citations had gone stale - see below), each with GUT coverage and a green suite
verified after every step:

- **`PlayerClass`** (`PlayerSave.PlayerClass`) - `CLASS_NAMES` deduped down to one copy (`PlayerSave.CLASS_NAMES`), used by `Leveling.CLASS_BASE_RATIOS`, `TalentTree.STARTING_MOVES`/`TREES`,
  `Achievements.classes_cleared`, `main_menu.gd`/`abilities_window.gd`'s class-select flow.
- **`AggressionStance`** (`Party.AggressionStance`) - `get_ag_mode`/`set_ag_mode`/`apply_aggression_mode` and `battle_scene.gd`'s stance-row wiring; `scripts/editor/units.gd`'s duplicate
  `AGGRESSION_ORDER` now references `Party.AGGRESSION_NAMES` instead of restating it.
- **`MovePool`** (`CombatUnit.MovePool`) - the `battle_ai.gd`/`battle_runner.gd` "attack"/"defense"/"absolute" pool tag.
- **`Team`** (`CombatUnit.Team`) + **`Relation`** (`battle_scene.gd`) - the magic `1`/`2` team side and the `"player"/"ally"/"enemy"` `RING_COLORS` key.
- **`BattleEventType`** (`BattleRunner.EventType`) + **`MoveResultType`** (`BattleManager.ResultType`) + **`DeathCause`** (`BattleRunner.DeathCause`) - found during the re-audit, not in the
  original list: `battle_runner.gd`/`battle_scene.gd`'s internally-invented event-log and move-result string dispatch, both with no `_:` default case (a typo previously failed silently).
- **`Difficulty`/`Leveling.Stat` partial adoption finished** - `ZoneProgression.max_zone`, `achievements.gd`'s 3 raw difficulty comparisons, `main_menu.gd`'s difficulty picker,
  `Leveling.spend_stat_point`/`abilities_window.gd`'s attribute-plus handler.
- **`Equipment.EquipSlot`** - only `MAIN_HAND_SLOT`/`SECONDARY_SLOT` and the slot-kind params (`can_equip`/`equip`/`unequip`) - the UI's purely positional 0-6 equip-slot indices
  (`EQUIP_SLOT_CENTERS`, `equip_doll_view.gd`'s `equip_index`) correctly stay plain `int`, per this section's own original judgment call.
- **`CombatUnit.Element`** - initially scoped down to just the enum + `element_from_name()` lookup helper, over save-format migration risk (`PlayerSave.per`/`def` are `@export`-persisted -
  retyping their keys changes every existing save file's `.tres` shape on disk). Finished properly the same day once the project owner confirmed there are no live users yet to worry about:
  `CombatUnit.per_u`/`def_u`/`base_per`/`base_def` and `PlayerSave.per`/`def` are now `Dictionary[Element, float]`, and `Ability.damage_element_type`/`dispel_element_types`/`Buff.element_type`
  are `Element`/`Array[Element]`, converted once at JSON-load time via `element_from_name()` (the one place a String survives, since the source data is text) - every downstream consumer
  (`battle_manager.gd`'s per/def lookups, `combat_unit.gd`'s buff-element matching, the 5 `MenuTheme.ELEMENT_COLORS` lookup sites) now reads/writes the enum directly, no more find()-by-name at
  render time. `item.stats`'s own `"piercing"/"defense"` sub-dicts stay String-keyed in `equipment.gd`/`combat_unit.gd`'s `from_character()` reads - those are parsed straight from JSON, which
  can't have non-string object keys, so there's no equivalent conversion available there; read by name, write into the now-Element-keyed `base_per`/`per`/etc. by position.
  **This DOES break old save files' `.tres` shape** (confirmed live: loading a pre-existing local save with the old String-keyed `per`/`def` threw "Unable to convert key from String to int" -
  exactly the risk flagged above) - acceptable now, not once this ships to real players.
- **`CharacterVisual.set_state()`** now takes `State` directly (signature tightening, zero behavior change - every call site already passed `State.X`).

**Stale citations found re-auditing** (worth remembering for next time an old audit gets acted on late): this section's `main_menu.gd:11`/`main_menu.gd:19` citations for `CLASS_NAMES`/
`DIFFICULTY_NAMES` were wrong by the time this work started - that file had been migrated to Container scenes since (see the UI architecture phase below), and class/difficulty names now live as
literal button text + `binds=[N]` connections in `main_menu.tscn` itself, not a GDScript array. `MenuTheme.STAT_LABELS`/`STAT_COLORS`, described here as "aligned to `Stat` by convention only, no
reference to the enum," turned out to have zero actual callers anywhere - dead code, not a live-but-unenumerated site; left alone since removing it wasn't asked for.

**Existing convention** (now used in 15+ places): `enum Name { A, B, C }` declared single-line for small sets or one-value-per-line for bigger ones, paired with an enum-keyed
`Dictionary[EnumType, ValueType]` for lookup/message tables or an `Array[EnumType]` for enum-typed ordered lists. Persisted/exported fields and anything sourced straight from external data stay
plain `int`/`String` even when enum-valued (`PlayerSave.difficulty`, `BattleRunner.win_condition`, `Ability.effect_category`) to keep `.tres`/save serialization and data loading simple; only
function parameters/locals/match targets take the enum type directly. New enum work should follow this exact split.

- **Explicitly NOT enum candidates** (open-ended/data-driven content, matches the project owner's own exclusion): zone/battle/shop/item id-keyed dictionaries (`ZoneManager.ZONES`,
  `StoreManager.ZONE_SHOP_IDS`/`SHOP_DIALOGUE`/`KRIN_SHOP_ITEMS`, `GameData.STARTING_EQUIPMENT`, `ZoneProgression`'s battle-cap tables), `Achievements.NAMES`/`DESCRIPTIONS` (text content), and
  `hotbar.gd`'s `MENU_BUTTON_GROUPS`/`HOVER_COLORS` (keyed by actual Godot scene-node names, not a portable "kind" concept).

## Rich tooltip rework

**DONE (2026-08-20).** A shared `GameTooltip` autoload (`scripts/ui/game_tooltip.gd` + `scenes/ui/game_tooltip.tscn`, a `CanvasLayer` rendering a stack of independently-colored,
independently-backgrounded sections) replaces both the ability screen's old single-panel `AbilityTooltip` and every other screen's plain Godot `tooltip_text` (which can only show one
uniform box in one text color). Its palette lives in `scripts/ui/tooltip_theme.gd` (`TooltipTheme`), recovered from the original's own `KrinToolTipper` clip data rather than guessed.
5 call sites now build sections and hand them to `GameTooltip`: item slots (`item_slot.gd`), hotbar buttons (`hotbar.gd`), the abilities screen (`abilities_window.gd`), in-battle
ability orbs (`battle_scene.gd`), and buff icons (`unit_overlay.gd`).

## Testing: GUT

GUT 9.7.1 is vendored at `addons/gut/`, tests in `test/unit/` + `test/integration/`, config in `.gutconfig.json`. Run headless (exits nonzero on failure):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Compile-check a script without GUT: `Godot --headless --check-only -s <script.gd> --path .` (run `--headless --editor --quit --path .` once after adding new `class_name` scripts, or the class
cache is stale and reports false "not declared" errors - this is per-checkout, so re-run it in any other worktree or the main checkout after merging in new `class_name` classes, even if the
branch itself already verified green).

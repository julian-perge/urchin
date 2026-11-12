# source_files

Decompiled source material extracted from the two SWFs in `URCHIN_SWF_DIR` (see AGENTS.md, Setup)
(`sonny-2-2900.swf` = ArmorGames web build, `SONNY2.swf` = Steam build).
Everything here regenerates with:

```sh
uv run export_swf_sources
```

`--xml` also rewrites the `swf_xml/` dumps, which adds ~284 MB to LFS.

(ffdec, the JPEXS decompiler CLI, must be at `~/.local/bin/ffdec`.)

| Directory | Contents |
|---|---|
| `action_script/` | Full ffdec script export of the web SWF: every frame DoAction, DefineSprite frame script, and DefineButton2 handler. The authority for game logic ports. |
| `action_script_curated/` | Hand-picked, commented excerpts used by the original data ports (previously `dev/action_script_files/`). |
| `swf_xml/` | `ffdec -swf2xml` dumps of both SWFs, kept for grepping. Geometry comes from the SWFs through `dev/urchin_dev/swf/swf_index.py` and `timeline.py`, and nothing reads the dumps. Large files - the web dump is ~143 MB. |
| `extraction_outputs/` | Scratch outputs from analysis runs that are worth keeping but are not consumed by the game. |

Analysis and extraction tooling lives in `dev/urchin_dev/swf/`:

- `swf_index.py` - reads tags, placements, labels, shape bounds and sound streams straight from a SWF
- `timeline.py` - folds the placements into one display list per frame
- `render.py` - renders frames through the ffdec_lib driver (`ffdec_lib.py`) and places each one on the stage
- `strip.py` - builds the stripped copies and strip lists the extractors render from, refusing clip masks
- `item_looks.py` - regenerates `converted_json/item_looks.json` + patches item `.tres` looks
- `faces.py` - regenerates `assets/ui/menu/portraits/*.png`
- `extract/zone_hub.py` - regenerates the zone-hub backgrounds and the orb's arc shapes
- `extract/store_art.py` - regenerates the per-shop keeper scenes
- `extract/battle_screen.py` - regenerates the battle halls, skies, chrome and stance button art, plus `battle_layout.json`
- `extract/combat_text.py` - regenerates the Combat text banner's band and `combat_text.json`
- `export_swf_sources.py` - regenerates this directory

JSON parsing across `dev/` goes through
`dev/urchin_dev/swf/models.py` (msgspec-backed models + loaders
for the AMF-style runtime dumps in `data_json/`).

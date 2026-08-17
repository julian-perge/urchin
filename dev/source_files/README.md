# source_files

Decompiled source material extracted from the two SWFs at the repo root
(`sonny-2-2900.swf` = ArmorGames web build, `SONNY2.swf` = Steam build).
Everything here regenerates with:

```sh
uv run python3 export_swf_sources
```

(ffdec, the JPEXS decompiler CLI, must be at `~/.local/bin/ffdec`.)

| Directory | Contents |
|---|---|
| `action_script/` | Full ffdec script export of the web SWF: every frame DoAction, DefineSprite frame script, and DefineButton2 handler. The authority for game logic ports. |
| `action_script_curated/` | Hand-picked, commented excerpts used by the original data ports (previously `dev/action_script_files/`). |
| `swf_xml/` | `ffdec -swf2xml` dumps of both SWFs. The authority for geometry: placement matrices (twips, divide by 20 for px), shape bounds, sprite timelines, export names. Large files - the web dump is ~143 MB. |
| `extraction_outputs/` | Scratch outputs from analysis runs that are worth keeping but are not consumed by the game. |

Analysis and extraction tooling lives in `dev/urchin_dev/swf/`:

- `xml_lib.py` - shared swf2xml parsing (bounds, timelines, matrices)
- `doll_offsets.py` - regenerates `resources/sprites/doll_offsets.json`
- `item_looks.py` - regenerates `converted_json/item_looks.json` + patches item `.tres` looks
- `faces.py` - regenerates `assets/ui/menu/portraits/*.png`
- `export_swf_sources.py` - regenerates this directory

JSON parsing across `dev/` goes through
`dev/urchin_dev/swf/models.py` (msgspec-backed models + loaders
for the AMF-style runtime dumps in `data_json/`).

# Spec: lookup

Source issue: [#346](https://github.com/julian-perge/urchin/issues/346).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md), `docs/agents/actionscript.md` and `docs/agents/godot.md`. Review standards are in [CODING_STANDARDS.md](../CODING_STANDARDS.md). The idea is `docs/ideas/one-lookup-for-gdscript-and-actionscript.md`. The decision to build a CLI and not adopt an MCP server is [ADR 0009](../docs/adr/0009-build-just-lookup-not-a-gdscript-mcp.md). The benchmark and its rerun steps are `docs/research/2026-11-18-gdscript-mcp-benchmark.md`.

## Objective

Give a session one command, `just lookup <query>`, that answers "where is this, who calls it, and which original code does it port" for GDScript as well as ActionScript. `just as-lookup` does this for the ActionScript only (spec [#247](https://github.com/julian-perge/urchin/issues/247)). A GDScript question still costs an `rg` and several partial reads: about 3,340 code-reading calls in urchin transcripts from 2026-11-04 to 2026-11-18, against 729 for the ActionScript export and 33 for `just as-lookup` (idea doc, all Evidence).

The user is a session or a cold subagent that reads, ports, reviews or tests battle code. The lookup is a navigation aid. The original code and the tests stay the authority.

The work has five parts:

1. **The GDScript index.** `uv run extract_gd_index` parses the tracked `.gd` files and writes `dev/converted_json/gd_index.jsonl`. The file is checked in.
2. **The joined lookup.** `just lookup <query>` answers from both indexes, with the ports in both directions.
3. **The facts join.** Each answer also prints the sections of `DECODED_ALGORITHMS.md` that cite the same range or name the same file and function.
4. **String values.** Both indexes hold string literals, so `just lookup Angry_Dux` finds the line.
5. **The rerun.** The 7 benchmark questions run again with the lookup as a fourth condition, with 2 or 3 questions from real sessions added.

## Assumptions

Marked "proposed" are this spec's choices. The others are Evidence or settled by the project owner while this spec was drafted.

- **Settled:** `just lookup` is the new name. `just as-lookup` stays as an alias, so the doc rules and old transcripts keep working. The GDScript index is its own file, `gd_index.jsonl`, with the same record style as `as_index.jsonl`. The parser is `tree-sitter-gdscript`. The rerun adds 2 or 3 real-session questions.
- **Evidence:** `tree-sitter-gdscript` 6.1.0 is on PyPI. A probe (2026-11-18, `~/tmp/2026-11-18-gd-parse-probe/probe.py`) parsed all 166 tracked `.gd` files under `scripts/`, `test/` and `dev/` with 0 error nodes. It found 2,079 `function_definition` nodes and 46 `signal_statement` nodes. The 86 files under `addons/` are vendored and are not indexed.
- **Evidence:** `as_index.jsonl` has 895 records and is 609 KB. `just as-lookup` already prints `ports`, which is the GDScript comments that cite an AS range, read at each run from tracked `.gd` files.
- **Evidence:** 32 of 35 sections of `DECODED_ALGORITHMS.md` cite a `.as` line, and 124 of 158 `.as` mentions carry a line (idea doc). So a join by cited range finds most sections.
- **Evidence:** `just as-lookup Angry_Dux` finds no match, because the index holds names and not string values. `Angry_Dux` is at `dev/source_files/action_script/frame_42/DoAction_8.as:38` and at `scripts/battle/battle_scene.gd:40`.
- **Guess:** A caller list by name is good enough for GDScript. Signals, `call()` and duck typing are not resolved by name. The first build task measures this (see Success criteria 7).
- **Guess:** Sessions run `just lookup` with no hint beyond the doc rule. The rerun measures this with the `lookup` condition, and the week-after count with `reads.py` checks it.
- **Proposed:** The same thresholds as the AS lookup apply: source lines print for a range of 120 lines or less, and a record over 60 lines gets an outline of statements of 15 lines or more, to depth 3.

## The GDScript index

One JSON object per line. Keys are sorted. Records are sorted by `file`, then by `start`. A second run writes the same bytes. The builder reads only tracked `.gd` files under `scripts/`, `test/` and `dev/`, so it runs on a fresh checkout with no SWF and no Godot.

**`gd_script`**: one for each file.

| Field | Content |
| --- | --- |
| `kind` | `"gd_script"` |
| `file` | Repo-relative path, as in `scripts/battle/battle_scene.gd` |
| `lines` | Line count |
| `class_name`, `extends` | As declared, or absent |
| `signals` | Each `signal` the file declares: `{"name", "line", "params"}` |
| `strings` | See "String values" |

**`gd_function`**: one for each `func`, including `static func` and each inner class's functions. A lambda does not get a record. Its calls belong to the function that holds it.

| Field | Content |
| --- | --- |
| `kind` | `"gd_function"` |
| `name` | The declared name |
| `owner` | `class_name`, the inner class, or the file stem |
| `file`, `start`, `end` | The file and the 1-based line range of the whole function, from the `func` line to its last body line |
| `params` | Parameter names in order |
| `calls` | `{"name", "line", "receiver"}` for each call whose name some indexed function defines. `receiver` is the source text before the last `.`, or `null` for a bare call |
| `connects` | `{"signal", "line", "receiver", "target"}` for each `X.connect(Y)`. `target` is the callable's source text, as in `_on_stance_pressed.bind(...)` or `lambda` |
| `emits` | `{"signal", "line"}` for each `X.emit(...)` and `emit_signal("X")` |
| `outline` | As in the AS index. Absent on a short function |
| `strings` | See "String values" |

A caller is found by name, as in the AS index. The index does not judge whether a receiver can hold that function. The lookup prints the receiver, and the reader judges. A connected callable (`connect(_on_x)`) counts as a call site of `_on_x` with kind `connect`, so the signal route to a handler shows in its callers.

### Port links

The GDScript side of a port link is the existing citation reader in `as_lookup.py` (`read_citations`, `tracked_citations`). This spec adds no annotation format. The new lookup uses it in both directions:

- From an AS range: the GDScript comments that cite it (unchanged).
- From a GDScript function: the AS ranges that the comments inside it, or directly above it, cite. For each, the lookup prints the AS function that holds the cited range.

### String values

A string literal is indexed when its text matches `[A-Za-z0-9_]{3,}`. This covers sound names, frame labels and dictionary keys, and leaves out sentences and format strings (proposed). On a `gd_function` or `as` function or script record, `strings` is a sorted list of `{"value", "lines"}`. The builder adds this field to `as_index.jsonl` records too, so `extract_as_index` changes and its checked-in file changes once. The lookup matches a query to a string value by exact text first, then without case.

The size of each index is a guess to measure. Each index file stays under 1.5 MB (proposed). If a file goes over, the build issue reports it and proposes a narrower rule before it commits.

## The lookup

`just lookup <query>` (`uv run lookup`, proposed). `just as-lookup` runs the same command. It reads both indexes and the tracked `.gd` files. It does not import a parser.

| Query | Match |
| --- | --- |
| A function name, `tick_buffs` or `executeMove` | Every function record of either language with that name |
| A global name, `perKSuccess` | As today: writers and readers in the AS |
| A signal name, `proceed_pressed` | The `signal` line, each `connect` and each `emit` |
| A string value, `Angry_Dux` | Each record that holds the literal, with the line, in either language |
| A repo path, `scripts/battle/combat_unit.gd` | The script record and the functions in it |
| A path with a line, `scripts/battle/battle_runner.gd:119` | The innermost function and outline block that hold the line |
| An export path, with or without a line | As today |

A query that matches in both languages prints one section for each, GDScript first when the query is a repo path or ends in `.gd` and ActionScript first when it ends in `.as`, and otherwise in the order of the table (proposed). Each section is headed with its language.

Output for a GDScript function, in this order:

1. **Location.** Repo-relative path and line range, in a form the Read tool accepts.
2. **Source.** The lines when the range is 120 lines or less. Otherwise the outline. `--source` and `--no-source` work as in `as_lookup`.
3. **Callers.** Each call site as path, line, the enclosing function, the receiver and the kind (`call`, `connect`, `test`). A name defined in more than one file lists each definition's callers apart. The list prints at most 40 rows and a count of the rest (proposed).
4. **Calls.** Each function it calls, with that function's location.
5. **Signals.** Each signal it connects to and each it emits, with lines.
6. **Ports.** Each AS range its comments cite, with the AS function that holds it.
7. **Facts.** See below.

For an AS function the existing answer stays, and gains a **Facts** section.

Exit code 0 means a match. Exit code 1 means no match, and the lookup prints the nearest names from both indexes.

## The facts join

A fact is a `##` section of `DECODED_ALGORITHMS.md`. The lookup reads the file at each run, as it reads the `.gd` comments. It links a section to an answer in two ways:

- The section cites an AS path with a line part that overlaps the answer's AS range. A citation with no line part links to the script.
- The section names the answer's `.gd` path, or names the function in backticks next to that path. For example the `krinMelee` section names `scripts/entities/character_visual.gd` and `play_melee`.

Each linked section prints as its heading and its line in the file, as `DECODED_ALGORITHMS.md:7  krinMelee - the melee run/strike/runback`. The lookup prints no section text. The reader opens the file at that line.

`KNOWN_GAPS.md` and `docs/research/` have no stable section format for this join, so they are deferred (see Out of scope).

## Commands

```
just lookup tick_buffs               prints one answer
just lookup Angry_Dux                finds a string value
just as-lookup executeMove           alias of just lookup
just extract-gd-index                writes dev/converted_json/gd_index.jsonl
just extract-as-index                rewrites as_index.jsonl with string values (needs ffdec and java)
just pytest                          the Python tests
just gut                             the GUT suite
```

`just extract-gd-index` is a new recipe for `uv run extract_gd_index`, with the same pattern as the other extractors. It needs neither ffdec nor Godot.

## Project structure

Follows `AGENTS.md`. New or changed locations (names proposed):

```
dev/urchin_dev/gd_index.py             parses .gd files and writes gd_index.jsonl
dev/urchin_dev/lookup.py               reads both indexes, joins ports and facts, prints the answer
dev/urchin_dev/as_lookup.py            keeps the AS answers and the citation reader; lookup.py calls it
dev/urchin_dev/swf/as_index.py         adds strings to its records
dev/converted_json/gd_index.jsonl      the checked-in GDScript index
dev/converted_json/as_index.jsonl      rewritten once, with strings
dev/tests/test_gd_index.py
dev/tests/test_lookup.py
pyproject.toml                         entry points extract_gd_index and lookup, tree-sitter-gdscript
justfile                               recipes lookup and extract-gd-index, as-lookup kept
docs/agents/godot.md                   one line: run just lookup before rg on .gd files
docs/agents/actionscript.md            as-lookup rule now names just lookup
AGENTS.md                              the Commands line names just lookup
docs/research/                         the rerun result, in the benchmark note
```

`gd_index.py` reuses the output helpers of `as_index.py` and does not copy them.

## Code style

As in `as_index.py` and `as_lookup.py`: a header comment that says what the file reads and writes, frozen dataclasses, stdlib `json`, and output that diffs by record. Comments follow the rules in the user's global instructions.

```python
# gd_index reads the tracked .gd files and writes gd_index.jsonl. It does
# not read the SWF, the XML dump or Godot, so it runs on a fresh checkout.
import tree_sitter_gdscript
from tree_sitter import Language, Parser

_PARSER = Parser(Language(tree_sitter_gdscript.language()))
```

The snippet shows style only.

## Testing strategy

Tests are pytest under `dev/tests/`. They read the tracked `.gd` files, the checked-in indexes and `DECODED_ALGORITHMS.md`. They read no SWF and no XML dump. `just pytest` runs them. Write each test first, and name the seams here as the approved test seams for the build:

- **The index is current.** A test builds the records in memory and compares the bytes with `gd_index.jsonl`. A second test does the same for `as_index.jsonl` after the strings change.
- **Every file parses.** Each tracked `.gd` file under the three folders has no error node.
- **Invariants on every record.**
  - `start` and `end` lie inside the file, and `start <= end`.
  - The first line of a `gd_function` holds `func` and its name.
  - The line of each call holds the callee's name followed by `(`, or the name in a `connect`.
  - The line of each string holds its value.
- **An independent count.** The number of `gd_function` records equals a regex count of `^\s*(static\s+)?func\s` lines over the same files. The test computes both numbers. It does not type a number.
- **Known answers, read from the files.** `tick_buffs` is in `scripts/battle/combat_unit.gd` and has a caller at `scripts/battle/battle_runner.gd:247` through `_execute_action` (idea doc and benchmark question U3, check on the build commit). `presenter.voice_cue` connects to `AudioManagerAuto.voice` in `battle_scene.gd`. The lookup of `Angry_Dux` returns the AS line 38 and the GDScript line 40.
- **The lookup.** Each query form in the table returns its match on the real indexes. A wrong name exits 1 and prints near names from both languages. A name with two definitions lists the callers of each apart. A caller list over 40 rows is cut and counted.
- **Ports in both directions.** A fixture with comments `:82`, `:40-64` and `:188, 261` links to the right AS functions from a GDScript function. The existing AS-to-GDScript ports test still passes.
- **The facts join.** A fixture file with a line-citing section and a path-naming section links each one. The real file links the `krinMelee` section to `frame_42/DoAction_4.as` and to `play_melee`.
- **The alias.** `just as-lookup executeMove` and `just lookup executeMove` print the same bytes.
- **Must-fail controls.** Delete one line from a copy of each index and expect the currency tests to fail. Move one `func` line in a copy of a `.gd` file and expect an invariant to fail. Run Python mutation checks with `PYTHONDONTWRITEBYTECODE=1`.
- **Whole suite.** `just pytest` and `just gut` pass before each commit. `check_doc_paths` passes on the edited docs.

## Boundaries

- Always: Build both indexes from the tracked files by script. Keep the output byte-stable. Print paths that the Read tool accepts. Keep the lookup free of the parser import. Index only files that git tracks, and leave out `addons/`.
- Ask first: A third dependency. A change to the record fields after the first build issue lands. A change to the citation format. A change to the 120, 60, 15 and 3 thresholds. Adding `.tscn` or `.tres` files to the index.
- Never: Edit an index file by hand. Edit a file under `dev/source_files/action_script/`. Put a behavior summary in an index or in the lookup output. Print the text of a fact section as if it were the original. Read the SWF or the XML dump in a test. Delete or weaken a test to make the suite pass.

## Out of scope

- `.tscn` node trees and node paths, typed call resolution, and any edit tools (idea doc).
- Joining `KNOWN_GAPS.md` and `docs/research/` into the facts. They have no stable section format. A later spec can add one.
- A GDScript MCP server, the `julian-perge/godot-mcp` fork symbol tools, `hi-godot/godot-ai`, and a code-graph MCP. ADR 0009 records why.
- Splitting `test_battle_scene.gd` and `battle_scene.gd`. Revisit only if the lookup data shows that the search step in those files still costs calls.
- Resolving signal connections through `call()`, `callv()` and duck typing.

## Success criteria

1. `just extract-gd-index` writes `gd_index.jsonl` from tracked files in under 5 seconds, with no SWF and no Godot. A second run changes no byte. Each index file is under 1.5 MB.
2. All 166 tracked `.gd` files parse with no error node, and every invariant holds on every record.
3. `just lookup tick_buffs` prints the location, the source or outline, the callers (`battle_runner.gd:247` among them), the calls, the signals and the ports.
4. `just lookup Angry_Dux` prints the AS line and the GDScript line that hold it.
5. `just lookup krinMelee` and a lookup of `play_melee` both print the `DECODED_ALGORITHMS.md` section of `krinMelee`.
6. `just as-lookup` still answers every query that it answered before, with the same output apart from the new Facts section.
7. A check of the name-based caller guess: for 10 battle functions, the lookup's callers match a hand search by `rg`, or the report lists each miss and its cause (signal, `call()`, duck typing, other). This is a report on the issue and not a gate. The 10 functions are chosen from `battle_scene.gd`, `battle_runner.gd` and `combat_unit.gd`, and the report names them.
8. The rerun: the 7 questions of the 2026-11-18 benchmark, plus 2 or 3 questions mined from urchin transcripts with `reads.py` (written as U8 to U10 with reference answers before the run), run with `baseline` and `lookup` conditions on the same commit, 2 runs each. The `lookup` condition uses `mcp-none.json` and no hint. The result goes in `docs/research/2026-11-18-gdscript-mcp-benchmark.md` as a dated section. The target is `lookup` context at or below `baseline` (proposed). A result above `baseline` is posted on #346 as a decision, with the question that cost the most.
9. `docs/agents/godot.md`, `docs/agents/actionscript.md` and `AGENTS.md` name `just lookup`, and `check_doc_paths` passes.
10. `just pytest` and `just gut` pass.
11. One week after the rule lands, `reads.py` shows the count of `just lookup` calls against GDScript partial reads. This is a check after the build, not a gate on a build issue. #346 stays open for it.

## Open questions

- Does `strings` on every record make `as_index.jsonl` too large? Criterion 1 sets 1.5 MB, and the first build task reports the real size.
- Should the lookup print the callers of a test helper? The spec labels test callers `test` and lists them. If they crowd out production callers in the 40-row cap, a build issue can sort them last and reports it.

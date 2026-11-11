# Spec: as-index

Source issue: [#247](https://github.com/julian-perge/urchin/issues/247).

Commands, project structure and code style are in [AGENTS.md](../AGENTS.md) and `docs/agents/actionscript.md`. Review standards are in [CODING_STANDARDS.md](../CODING_STANDARDS.md).

## Objective

Give an agent one command that answers "where is this piece of the original, what calls it, what does it touch, and where is its port". Today each subagent finds the answer again with a search and then a read.

The user is a cold subagent (implementer or reviewer) or a session that ports from the original or checks a port against it.

The evidence is in the session transcripts. 154 of 245 transcripts touch `dev/source_files/action_script/`, with 2,208 calls, and 87% of those calls are in subagents. The usual pattern is `rg 'function X'` to find the file, then `sed -n` a line range.

The work has three parts:

1. **The index.** `uv run extract_as_index` parses the tracked export and writes `dev/converted_json/as_index.jsonl`. The file is checked in.
2. **The lookup.** `uv run as_lookup <query>` reads the index, reads the port links from the `.gd` comments, and prints the answer.
3. **The citation check.** `uv run check_as_citations` is a prek hook. It fails a commit when a `.gd` comment cites an AS path or line that does not exist.

The index is for navigation only. An agent still reads the original lines. The index is not an authority on behavior.

## Assumptions

- The export under `dev/source_files/action_script/` does not change. It is tracked, so the builder and its tests run on a fresh checkout with no SWF.
- ffdec's AS1/2 output parses as JavaScript when the header line of a handler (`on(release){` or `onClipEvent(load){`) becomes a function header. A probe with `tree-sitter-javascript` parsed 820 of 820 game scripts with 0 errors on Python 3.14.
- A game script is an `.as` file under a `frame_*`, `DefineSprite_*` or `DefineButton2_*` folder. There are 820. The other 49 files are the `__Packages` tree and the class files at the top of the export. They look like Flash's `mx` component library. The build confirms this for each file before it leaves the file out, and it indexes any game class it finds there.
- The game scripts hold 54 function declarations with 45 distinct names. Other functions are assigned, as in `lifeBarUpdate = function(PWLC)` at `frame_42/DoAction_8.as:271`. The index covers both.
- A port link is an AS path in a `#` comment of a tracked `.gd` file, as in `frame_42/DoAction_8.as:82`. There are 322 today. This spec adds no new annotation format.
- Names and paths marked "proposed" are this spec's choice.

## The index

One JSON object per line. Keys are sorted. Records are sorted by `file`, then by `start`. A second run writes the same bytes.

There are two kinds of record.

**`script`**: one for each game script.

| Field | Content |
| --- | --- |
| `kind` | `"script"` |
| `file` | Path under the export, as in `frame_42/DoAction_8.as` |
| `lines` | Line count of the file |
| `owner` | The fields of `label_xref.Script`: `kind` (`frame`, `clip`, `button`), `timeline`, `frame`, `placed`, `depth`, `button` |
| `event` | The handler's event text, as in `onClipEvent(enterFrame)` or `on(release)`. Absent on a frame script |
| `calls`, `writes`, `reads` | What the script does outside the functions it defines. See below |
| `outline` | See below. Absent on a short script |

**`function`**: one for each function a game script defines.

| Field | Content |
| --- | --- |
| `kind` | `"function"` |
| `name` | The declared name, or the last segment of the assignment target |
| `declared_as` | `"declaration"`, or `"assignment"` with `target` holding the full target text, as in `_root.lifeBarUpdate` |
| `file`, `start`, `end` | The file and the 1-based line range of the whole function |
| `params` | Parameter names in order |
| `calls`, `writes`, `reads`, `outline` | As on a script, for the function's own body |

A function nested in another function gets its own record. Its lines also stay in the outer record's range.

**`calls`** is a list of `{"name", "line", "receiver"}`. The builder records a call only when `name` is a function that some game script defines. `receiver` is the source text before the last `.`, or `null` for a bare call. The index does not judge whether a receiver can hold that function. The lookup prints the receiver, and the reader judges.

**`writes`** is a list of `{"name", "lines"}`, one entry per name, with every line that assigns it. **`reads`** is a sorted list of names with no lines. The naming rule is the same for both:

- A name is the longest static dotted path. It stops before the first computed segment or call. `_root.Krin.zoneName[_root.Krin.sectionIn]` reads `_root.Krin.zoneName` and `_root.Krin.sectionIn`.
- A path that starts at `_root`, `_global`, `_parent` or `this` keeps that prefix.
- A path that starts at a bare identifier is recorded when the identifier is not a parameter, not a `var` of the enclosing function, and not a Flash built-in. The record keeps the bare form, as in `AVGNUMC`. The index does not resolve which timeline a bare name lands on. `docs/agents/actionscript.md` records how that guess went wrong for `IDKT`.
- A computed segment with a string literal prefix keeps the prefix and a `*`. `_root["playerKrin" + n]` is `_root.playerKrin*`.

**`outline`** exists on a record that spans more than 60 lines (proposed). It lists each statement that spans 15 lines or more, to a depth of 3 (both proposed), as `{"start", "end", "depth", "head"}`. `head` is the statement's first source line, stripped and cut at 100 characters. The conductor, `frame_217/PlaceObject2_3389_480/CLIPACTIONRECORD onClipEvent(enterFrame).as`, is one 873-line handler. Its outline starts with `10-588 if(_root.InBattle)`, `12-111 if(_root.BAMBAMBAM)` and `139-587 if(_root.nextPlayer)`.

A record, shortened to show the shape:

```json
{"calls":[{"line":27,"name":"perScript","receiver":null}],"declared_as":"declaration","end":250,"file":"frame_42/DoAction_8.as","kind":"function","name":"executeMove","outline":[],"params":["IDKM","IDKM2","IDKC","IDKT"],"reads":["_root.perKSuccess"],"start":1,"writes":[{"lines":[3],"name":"AVGNUMC"},{"lines":[21],"name":"_root.perKSuccess"}]}
```

## The lookup

`uv run as_lookup <query>` (proposed name). It needs no parser. It reads the JSONL and the tracked `.gd` files.

| Query | Match |
| --- | --- |
| A function name, `executeMove` | Every function record with that name |
| A global name, `perKSuccess` or `_root.Krin.zoneName` | Every record that writes or reads a name whose full path or last segment equals the query |
| An export path or a unique suffix of one, `DoAction_8.as` | The script record and the functions in it |
| A path with a line, `frame_42/DoAction_8.as:82` | The innermost function and outline block that hold the line |

A name is matched exactly first. With no exact match, the lookup matches without case and says so. A name that is both a function and a global prints both.

Output for each match, in this order:

1. **Location.** The repo-relative path and line range, in a form the Read tool accepts.
2. **Source.** The source lines with line numbers when the range is 120 lines or less (proposed). Otherwise the outline. `--source` forces the lines. `--no-source` leaves them out.
3. **Callers.** Each call site as path, line, the enclosing function or script, and the receiver.
4. **Calls.** Each function it calls, with that function's location.
5. **Globals.** Names written, with lines. Names read.
6. **Ports.** Each `.gd` citation of this range: the `.gd` path and line, the GDScript function, and the comment line.

For a global query the output is the writers (path and line) and the readers (the record's location).

Exit code 0 means a match. Exit code 1 means no match, and the lookup prints the nearest names.

### Port links

The lookup reads the citations at each run, because they change with every GDScript edit.

- A citation is an export path in a `#` comment, with an optional line part: `:82`, `:40-64` or `:188, 261`.
- A path resolves when it equals a path under the export, or when it is a run of whole trailing components of exactly one such path. `check_doc_paths` uses the same idea for docs.
- A citation with lines links to every record whose range overlaps a cited line. A citation with no line links to the script record.
- The GDScript function is the `func` that holds the comment. When the comment block sits directly above a `func` line, it is that `func`. A comment above the first `func` belongs to the file.

## The citation check

`uv run check_as_citations` (proposed), as a prek hook on `\.gd$` files. It uses the lookup's resolver. A citation fails when its path resolves to no export file, resolves to more than one, or names a line past the end of the file. The message gives the `.gd` path and line, the citation, and the reason.

13 citations fail today. Seven name a file that does not exist at that path, and six name a line past the end. An example is `frame_4/DoAction.as:44` in `scripts/ui/game_tooltip.gd`: the root `frame_4/DoAction.as` has 7 lines, so the citation dropped a `DefineSprite_` prefix. The build finds the right file for each of the 13 and corrects the comment. It does not delete a citation to make the hook pass.

## Commands

```
uv run extract_as_index          writes dev/converted_json/as_index.jsonl
uv run as_lookup executeMove     prints one answer
uv run check_as_citations        checks every tracked .gd file
uv run pytest dev/tests/test_as_index.py dev/tests/test_as_lookup.py dev/tests/test_as_citations.py
uv run pytest                    the whole Python suite
```

## Project structure

Follows `AGENTS.md`. New or changed locations (all names proposed):

```
dev/urchin_dev/swf/as_index.py            parses the export, builds and writes the records
dev/urchin_dev/as_lookup.py               reads the index and the citations, prints the answer
dev/urchin_dev/checks/as_citations.py     the prek hook
dev/converted_json/as_index.jsonl         the checked-in index
dev/tests/test_as_index.py
dev/tests/test_as_lookup.py
dev/tests/test_as_citations.py
pyproject.toml                            three entry points, tree-sitter and tree-sitter-javascript
prek.toml                                 the as-citations hook
docs/agents/actionscript.md               tells agents to run as_lookup before rg
AGENTS.md                                 one line under Commands
docs/research/2026-11-11-as-index/        as_reads.py and the two probe scripts, moved from ~/tmp/2026-11-11-as-map-probe
```

`as_index.py` reuses `parse_script_path` and `Script` from `label_xref.py` for the owner. It does not copy them.

## Code style

As in `label_xref.py`: a header comment that says what the file reads and writes, frozen dataclasses, stdlib `json`, and output that diffs by record.

```python
# ffdec writes a handler's first line as `on(release){` or
# `onClipEvent(load){`, which is not JavaScript. The rewrite keeps every
# line number, so a node's row is the line an agent reads in the export.
_HANDLER = re.compile(rb"^(\s*)(on|onClipEvent)\s*\(([^)]*)\)\s*\{", re.MULTILINE)


def as_javascript(source: bytes) -> bytes:
    return _HANDLER.sub(lambda m: m.group(1) + b"function __handler(){", source)
```

The snippet shows style only.

## Testing strategy

Tests are pytest under `dev/tests/`. They read the tracked export, the checked-in index and tracked `.gd` files. They read no SWF and no XML dump.

- **The index is current.** A test builds the records in memory and compares the bytes with `as_index.jsonl`.
- **Every script parses.** The parse of each of the 820 game scripts has no error node.
- **Invariants, checked on every record.**
  - `start` and `end` lie inside the file, and `start <= end`.
  - The first line of a function record holds its name.
  - The line of each call holds the callee's name followed by `(`.
  - Each line of each write holds the last segment of the written name.
  - Each outline entry lies inside its record's range.
- **An independent count.** The number of `declaration` records equals a regex count of `function NAME(` lines over the same files, which is 54 today. The test computes both numbers. It does not type 54.
- **Known answers, read from the export.** `executeMove` is `frame_42/DoAction_8.as:1-250` and the conductor calls it through `_root`. `lifeBarUpdate` is an `assignment` at line 271 of the same file. The conductor has an outline, and its first entry starts at line 10.
- **The lookup.** Each query form in the table returns its match on the real index. A wrong name exits 1 and prints near names. A citation fixture with `:82`, `:40-64` and `:188, 261` links to the right records. A comment block above a `func` belongs to that `func`.
- **The citation check.** Fixtures cover a good citation, a missing file, an ambiguous suffix and a line past the end. A second test runs the check over the tracked `.gd` files and expects no failure, after the 13 corrections.
- **Must-fail controls.** Delete one line from a copy of the index and expect the currency test to fail. Add one line to a copy of an export file and expect an invariant to fail. Run Python mutation checks with `PYTHONDONTWRITEBYTECODE=1`.
- **Whole suite.** `uv run pytest` and `uv run gut` pass before each commit.

## Boundaries

- Always: Build the index from the export by script. Keep the output byte-stable. Print paths that the Read tool accepts. Keep the lookup free of the parser import, so it starts fast.
- Ask first: A third dependency. A change to the record fields after the first build issue lands. A change to `label_xref.py` beyond importing from it. A citation format other than the one the `.gd` comments use today.
- Never: Edit `as_index.jsonl` by hand. Edit a file under `dev/source_files/action_script/`. Put a behavior summary in the index. Delete or weaken a citation to make the hook pass. Read the SWF or the XML dump in a test.

## Out of scope

- Behavior summaries that replace a read of the AS.
- Sprite placement, frame labels and the XML dump. `label_xref.json` covers labels and gotos.
- Changes to `DECODED_ALGORITHMS.md`.
- A graph of the GDScript itself. The index links to the port. It does not map the port.
- Line checks for AS citations in Markdown docs and specs. `check_doc_paths` already checks that their paths exist.
- A DuckDB or SQLite file. DuckDB reads the JSONL in place when a session wants SQL.
- Resolving which timeline a bare name lands on.

## Success criteria

1. `uv run extract_as_index` writes `as_index.jsonl` from the tracked export, with no SWF, in under 5 seconds. A second run changes no byte.
2. All 820 game scripts parse with no error node, and every invariant holds on every record.
3. `uv run as_lookup executeMove` prints the location `frame_42/DoAction_8.as:1-250`, the outline, both call sites in the conductor, the globals, and the `.gd` citations of those lines.
4. `uv run as_lookup lifeBarUpdate` finds the assigned function. A lookup of the conductor's path prints its outline.
5. `uv run check_as_citations` passes on the tracked `.gd` files after the 13 corrections, and fails on each bad fixture.
6. `docs/agents/actionscript.md` and `AGENTS.md` name `as_lookup`, and `check_doc_paths` passes.
7. `uv run pytest` and `uv run gut` pass.
8. After 20 new transcripts that touch the AS, `as_reads.py` shows 7.1 or fewer AS calls per transcript, against 14.3 today (2,208 calls over 154 transcripts). The script counts `as_lookup` calls as AS calls. This is a check after the build, not a gate on a build issue.

## Settled on approval

The spec was approved as drafted on 2026-11-11. These points were open questions in the draft, and the approval accepts each one as written.

1. **Thresholds.** Source lines print at 120 lines or less. A record over 60 lines gets an outline, of statements of 15 lines or more, to depth 3. The 15 and the 3 come from one probe of the conductor, so a build issue can change them when the outline of another long script reads badly. It reports the change.
2. **Reads have no line numbers.** Writes carry every line. Reads carry names only, to keep the file small. An agent that needs the read lines of one name runs `rg` on the one file the lookup names.
3. **Names.** `extract_as_index`, `as_lookup`, `check_as_citations` and `dev/converted_json/as_index.jsonl` are the names.
4. **The 49 files left out.** The build checks that each is component library code, and it indexes any game class it finds among them.
5. **Criterion 8.** It needs about 20 new transcripts, so it does not close with the build. Issue #247 stays open for it after the build issues close.

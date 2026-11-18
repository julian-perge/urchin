# Build `just lookup` instead of adopting a GDScript MCP server

A session that works on urchin needs one lookup that answers "where is this, who calls it, and which original code does it port" for GDScript as well as ActionScript. The project builds a CLI recipe, `just lookup <name>`, that extends the AS index behind `just as-lookup` to `.gd` files. It does not adopt a GDScript MCP server. The idea doc [one-lookup-for-gdscript-and-actionscript](../ideas/one-lookup-for-gdscript-and-actionscript.md) has the problem and the scope. [2026-11-18-gdscript-mcp-benchmark](../research/2026-11-18-gdscript-mcp-benchmark.md) has the measurements and the steps to rerun them.

## Why not an MCP server

The benchmark ran `claude -p` on two clones at `e6b9f34a`. It used 7 questions, 2 runs each, and gave each MCP condition a hint that names its tools. All 42 answers were correct, so the difference is cost.

| Condition | Context, U1 to U6 | Change | Tool calls | MCP calls |
| --- | --- | --- | --- | --- |
| `rg` and `just as-lookup` | 1,374k | 0% | 48 | 0 |
| sunerpy/godot-mcp 0.8.0, `core` profile | 2,013k | +47% | 71 | 11 |
| godotlens-mcp | 1,464k | +7% | 61 | 10 |

- Neither server beats `rg` on context. The godotlens result is +7% with 2 runs per question, which is within the spread, so it is a tie and not a loss.
- sunerpy returns long JSON, and sessions searched with `rg` after it anyway. It also writes a 64 MB `.godot-mcp/` folder into the project.
- godotlens needs a running Godot editor with the language server on port 6005. In one run it showed a stale default value (`= null` where the file says `= {}`).
- Headless Claude Code keeps MCP tools behind ToolSearch and does not call them without a hint (measured in the blender-addon benchmark). A CLI recipe with a rule in the docs needs no ToolSearch step. `just as-lookup` already shows that this works: its use rose to 22 calls on 2026-11-17.
- A general code-graph MCP (codebase-memory-mcp, graphify) used 21% and 16% more context than `rg` in the blender-addon benchmark, so it is out too.

## What follows from it

- **`just lookup <name>` covers both languages.** For a GDScript function it prints the file and line range, the callers, the calls, the signals, and the AS range that its comments cite. It also prints the facts that cite the same range. The original code and the tests stay the authority. The lookup is a navigation aid, as `docs/agents/actionscript.md` says of `as-lookup`.
- **`docs/agents/godot.md` gets one line** that says to run the lookup before `rg`.
- **The index holds string values.** `just as-lookup Angry_Dux` found no match, because the index holds names and not string values, and the session fell back to `rg`.
- **The benchmark reruns with `just lookup` as a fourth condition**, and `baseline` reruns on the same commit. Numbers from 2026-11-18 are not compared against a later commit.
- **The `julian-perge/godot-mcp` fork gets no symbol tools.** Whether `hi-godot/godot-ai` replaces the fork is a separate decision.

## Open and unproven

- That a name-based caller list is good enough for GDScript is a guess. Signals, `call()` and duck typing are not resolved by name. The check: compare the lookup's callers of 10 battle functions with a hand search.
- That sessions run the lookup with no hint beyond the doc rule is a guess. The check: count `just lookup` calls against GDScript partial reads in the week after the rule lands.
- That the lookup cuts tokens on real questions is open until the fourth-condition rerun. The 7 questions came from the most read files, not from real sessions.
- This record reverses if a GDScript MCP server answers the same questions with fewer tokens than the lookup does in that rerun.

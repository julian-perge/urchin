# godot-mcp as a submodule for verify-urchin

Date: 2026-11-22. Confirmed with Julian in an interview-me session.

- **Outcome:** godot-mcp's `mcp_harness.gd` gets the read-only `node` and
  `tree` commands and a window-title env var. Urchin adds godot-mcp as a
  submodule at `vendor/godot-mcp`. `urchin_verify.py` passes
  `vendor/godot-mcp/src/scripts/mcp_harness.gd` with `-s`. The wrapper file,
  `HARNESS_CANDIDATES` and `DEV/git_repos` go away.
- **User:** Julian and any agent that runs verify-urchin on the Mac, on WSL or
  in a new worktree.
- **Why now:** the skill guesses where the clone is, and its generic code sits
  in urchin instead of in godot-mcp.
- **Success:**
  - In a fresh urchin worktree, `just setup-worktree` sets up the submodule.
  - The skill's proof run (launch, doctor, battle attack, stop) passes and
    keeps its evidence.
  - The godot-mcp change has its own tests.
- **Editing in place:**
  - `.gitmodules` sets `branch = main`.
  - AGENTS.md gets one rule: before you edit in `vendor/godot-mcp`, run
    `git -C vendor/godot-mcp switch -c <branch>`. Push that branch, then
    commit the new pin in urchin.
  - The same rule says the MCP server does not see edits made in the
    submodule.
- **Constraint:** the pin points at the commit on the godot-mcp PR branch, and
  it gets updated after that PR merges. The urchin work goes on PR #488 as more
  commits.
- **Added in the spec stage:** the godot-mcp server also gets `inspect_node`
  and `inspect_tree` tools for the two new harness commands.
- **Changed after the godot-mcp PR #17 review:** the pin is the merge commit
  of #17 on `main`, not the PR branch head. #17 merges first, with a merge
  commit.
- **Out of scope:**
  - Running the MCP server from the submodule.
  - The godot-ai research.
  - `~/code/godot-mcp` stays. It is still where the MCP server runs, and
    nothing deletes it.

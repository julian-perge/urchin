# Multi-model build workers

Status: a draft for a trial. Nothing here has run in this repo. The research behind it is `docs/research/2026-11-12-multi-llm-setup.md`. The research used direct vendor keys. This doc uses OpenRouter instead, which the research covers only as an alternative.

Read this before you dispatch a Build or Bug task to a worker model. A worker reads the section [Worker rules](#worker-rules).

## Roles

The stages are those of [Workflow](workflow.md). Only Build and Bug change.

| Stage | Model | Tool |
| --- | --- | --- |
| Idea, Design, Spec, Plan | Claude Opus 5.5 at `xhigh` effort | Claude Code |
| Build or Bug, a task that spans files and is fully specified | the `large` tier: Xiaomi MiMo-V2.6-Pro | OpenCode through OpenRouter |
| Build or Bug, a small mechanical task that an existing test covers | the `small` tier: DeepSeek V4.1 Flash | OpenCode through OpenRouter |
| Build or Bug, a task whose "how" is still open | Opus | Claude Code |
| Review | Opus, in a new session | Claude Code |

The research found no public benchmark that puts MiMo above DeepSeek. Run both tiers on the same kind of task before you treat this split as settled.

## What is on the machine, not in this repo

- `worker-run <stage> <tier> <issue>` runs one worker in the current worktree and logs the run.
- The OpenCode agents `worker-build-large`, `worker-build-small`, `worker-bug-large` and `worker-bug-small`. Each names its model and loads the `agent-skills` skills of its stage. A worker has no `/agent-skills:build` command, and OpenCode 2 cannot run a command headless, so `worker-run` starts one of these agents instead.
- The OpenRouter key, which OpenCode stores outside every repo.

## Which tasks go to a worker

- Only a task issue labelled `ready-for-agent`, with `Acceptance criteria` and a `Verification` command. `worker-run` refuses any other issue.
- Start with tasks whose `Verification` is a `just gut` path. Keep ActionScript ports and extractor changes on Opus until the trial has numbers.
- A worker sends what it reads to OpenRouter, which passes it to the host that serves the model. The ActionScript export and the SWF dump are git-ignored and not for distribution, so the worker rules keep them from a worker. The user decides whether a task that needs them may go to a worker at all.

## Dispatch

1. Claim the issue, as [Issue tracker](issue-tracker.md) says.
2. Make the worktree and set it up:

   ```sh
   git worktree add .worktrees/<issue>-<slug> -b <type>/<issue>-<slug>
   cd .worktrees/<issue>-<slug> && just setup-worktree
   ```

3. Run the worker there:

   ```sh
   worker-run build large <issue>
   ```

The worker sees nothing of the session that dispatched it. Its command makes it read `AGENTS.md`, the worker rules below, the task issue and the spec file. Anything else the worker must know goes into the task issue before dispatch.

When workers run in parallel, set `GODOT_SLOTS` so they do not run out of memory.

## Worker rules

These rules are for the worker. They win over a skill where the two differ.

- Run every command through `just`, as `AGENTS.md` says. The worktree is already set up.
- Read the topic doc under `docs/agents/` that matches the task before you write code. `AGENTS.md` lists them.
- Stay on the branch you are on. Run `just gut` before each commit. Commit subject: `<type>: <summary> (#<issue>)`.
- Do not push, open a pull request, or change an issue's labels, assignee or comments.
- Do not run `just as-lookup` or an extractor, and do not open the ActionScript export or the SWF dump. If the task needs one of them, stop and report that.
- Do not hand-cut art or hand-place a coordinate. `AGENTS.md` gives the one exception.
- End with the report your command asks for: the files changed, the output of the `Verification` command, and every guess and gap.

## After the worker stops

- Run `just gut` and the task's `Verification` yourself, and read the diff against each acceptance criterion. Do not rely on the worker's report: in the research, a cheap model passed all 20 of its own tests, diverged from the spec in six places, and reported features the code did not have.
- Then push the branch, open the pull request, and print the review command, as the Build section of [Workflow](workflow.md) says. Review runs in a new session as usual.
- Allow two rounds of rework. After that, Opus builds the task. The limit is a judgment, not a measured number.

## Log

`worker-run` adds a row per run to `~/.local/state/worker-runs/runs.tsv`: the model, the wall-clock time, the exit code and the number of commits. The cost of a run is on the OpenRouter activity page. Add the Opus cost of dispatch and checking, the rework rounds, and whether Opus finished the task itself, so the trial can be judged.

## Settings

- Do not set `ANTHROPIC_BASE_URL`, and do not put a gateway variable in a Claude Code settings file. Either one changes which credential the Opus session uses.
- OpenRouter is for the workers only. The Opus session stays on its own login.

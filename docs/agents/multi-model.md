# Multi-model build workers

Status: a draft for a trial, tracked in [#274](https://github.com/julian-perge/urchin/issues/274). The research behind it is `docs/research/2026-11-12-multi-llm-setup.md`. The research used direct vendor keys. This doc uses OpenRouter instead, which the research covers only as an alternative.

Read this before you dispatch a Build or Bug task to a worker model. A worker reads the section [Worker rules](#worker-rules).

## Roles

The stages are those of [Workflow](workflow.md). Only Build and Bug change. Opus is the overseer: it dispatches each worker, answers it through rework comments, and reviews the code. It does not build.

| Stage | Model | Tool |
| --- | --- | --- |
| Idea, Design, Spec, Plan | Claude Opus 5.5 | Claude Code |
| Build or Bug, a task that spans files and is fully specified | the `large` tier: Xiaomi MiMo-V2.6-Pro | OpenCode through OpenRouter |
| Build or Bug, a small mechanical task that an existing test covers | the `small` tier: DeepSeek V4.1 Flash | OpenCode through OpenRouter |
| Dispatch, checks and review of a worker's branch | Opus, the overseer | Claude Code |

A task whose "how" is still open is not a worker task. It goes back to Plan.

The research found no public benchmark that puts MiMo above DeepSeek. Run both tiers on the same kind of task before you treat this split as settled.

## What is on the machine, not in this repo

- `worker-run <stage> <tier> <issue>` runs one worker in the current worktree and logs the run. It refuses to start when the issue does not carry `ready-for-agent`, when HEAD is detached or on `main` or `master`, or when the tree has uncommitted work. It checks nothing else in the issue.
- `~/.config/opencode/stages.toml` names the model of each tier and the skills of each stage. `gen-opencode-stages` writes the OpenCode agents `worker-build-large`, `worker-build-small`, `worker-bug-large` and `worker-bug-small` from it. A worker has no `/agent-skills:build` command, and OpenCode 2 cannot run a command headless, so `worker-run` starts one of these agents instead.
- The OpenRouter key, which OpenCode stores outside every repo.

## Which tasks go to a worker

- Only a task issue labelled `ready-for-agent`, with `Acceptance criteria` and a `Verification` command. `worker-run` checks only the label, so check the rest before you dispatch.
- The `Verification` runs through `just` and is a `just gut` path. The task's output has no art and no rects.
- Out of scope for the trial: ActionScript ports, extractor changes, `/agent-skills:build auto`, and workers in parallel.
- A worker sends what it reads to OpenRouter, which passes it to the host that serves the model.

## Dispatch

Start a worker in a Build session with one sentence:

- `Build #<issue> with a <tier> worker` runs `worker-run build <tier> <issue>`.
- `Fix #<issue> with a <tier> worker` runs `worker-run bug <tier> <issue>`.

There is no slash command or `just` recipe for these yet. The session then does these steps:

1. Read the Build section of [Workflow](workflow.md). Claim the issue, as [Issue tracker](issue-tracker.md) says.
2. Make the worktree and set it up:

   ```sh
   git worktree add .worktrees/<issue>-<slug> -b <type>/<issue>-<slug>
   cd .worktrees/<issue>-<slug> && just setup-worktree
   ```

3. Run the worker there:

   ```sh
   worker-run build large <issue>
   ```

The worker sees nothing of the session that dispatched it. The worker agent's prompt makes it read `AGENTS.md`, the worker rules below, the task issue with its comments, the spec file, and the topic docs that `AGENTS.md` lists for the task. Anything else the worker must know goes into the task issue before dispatch.

## Worker rules

These rules are for the worker. They win over a skill and over the agent's prompt where they differ.

- Run every command through `just`, as `AGENTS.md` says. The worktree is already set up.
- Do not pipe `just gut` into another command. Its exit code is the result, and a pipe gives the exit code of the last command instead. In the smoke test of #274, the small tier ran `just gut` into `tail` and reported the exit code of `tail`.
- Read the spec file that the issue's `Spec` line names. When it has none, use the `spec/` path in the parent issue's body. When neither names one, the issue is the whole spec.
- Before you write code, read the topic docs that `AGENTS.md` lists for the task, and `CODING_STANDARDS.md` at the repo root.
- A spec's glossary line is a task, not a fact. Check `GLOSSARY.md` before you rely on a term that the spec says it has. If the term is missing, add the entry in the first task that uses it.
- Stay on the branch you are on. Run the `Every task` verify command from `AGENTS.md`, `just gut`, before each commit. Commit subject: `<type>: <summary> (#<issue>)`.
- Do not push, open a pull request, or change an issue's labels, assignee or comments.
- Do not hand-cut art or hand-place a coordinate. `AGENTS.md` gives the one exception.
- If the task turns out to need an ActionScript port, an extractor change, art or rects, stop and report that the task is on the wrong tier.
- Report each choice that changes user-visible behavior. Do not ask.
- End with the report the worker agent's prompt asks for: the files changed, the output of the `Verification` command, and every guess, accepted gap and inferred rule.

## After the worker stops

The overseer does these steps in the session that dispatched the worker. It does not fix the code itself.

1. Run `just gut` and the task's `Verification` yourself, and read the diff against each acceptance criterion. Read `CODING_STANDARDS.md` before you call the change verified. Do not rely on the worker's report: in the research, a cheap model passed all 20 of its own tests, diverged from the spec in six places, and reported features the code did not have.
2. Confirm that the branch was not pushed: `git ls-remote --heads origin <branch>` prints nothing. The deny rules of the worker agents and of `opencode.jsonc` have holes.
3. Review the branch with the review command from the Build section of [Workflow](workflow.md), without the `PR` part, because the pull request does not exist yet. The overseer did not write the code, so it does not review its own work.
4. Put the findings of the check and the review in a comment on the task issue, and run `worker-run` again. The worker reads the issue's comments.
5. After two rounds of rework, a small-tier task moves to the large tier for two new rounds. A large-tier task stops: report to the user, and the task goes back to Plan.
6. Put each user-visible choice from the worker's report to the user before you push.
7. Push the branch, open the pull request with `Closes #<issue>` in its body, and stop. The last line is the PR's URL for the user to merge, because the review already ran.

## Log

`worker-run` adds a row per run to `~/.local/state/worker-runs/runs.tsv`. Its columns are `date`, `repo`, `issue`, `stage`, `tier`, `model`, `seconds`, `exit`, `commits`, `uncommitted_files` and `log`, the path of the run's full output.

The trial records more per run, in one comment per run on #274:

- the model
- the worker's cost, from the OpenRouter activity page
- the overseer's cost for dispatch, checks and review, from `npx ccusage session` on its transcript
- the wall-clock time
- the rework rounds
- how the task ended: a pull request, moved up a tier, or sent back

## Settings

- Do not set `ANTHROPIC_BASE_URL`, and do not put a gateway variable in a Claude Code settings file. Either one changes which credential the Opus session uses.
- OpenRouter is for the workers only. The Opus session stays on its own login.
- `opencode.jsonc` at the repo root denies `just merge-ticket` and every shell command that names `merge_ticket`, for every OpenCode agent in this repo, because `merge_ticket` pushes.

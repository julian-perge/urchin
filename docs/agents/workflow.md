# Workflow

Read this before any `/agent-skills` command. The commands default to `SPEC.md` and `tasks/todo.md`. This repo uses the tracker mode of `planning-and-task-breakdown`: GitHub issues hold the tasks, and files under `spec/` hold the specs. [Issue tracker](issue-tracker.md) holds the `gh` commands that no helper covers.

The user types each stage. Run one stage per session. When it ends, print the next stage's command as the last line, with real issue, PR and file values, and stop. The user pastes that line into a new session, so it must need no edits. `/agent-skills:next` prints the same commands for the whole tracker.

## Helpers

`agent-skills` is on the PATH of every agent. When a verb covers a lookup, use the verb and do not write the `gh` call yourself.

| Verb | Use |
| --- | --- |
| `agent-skills issue <n>` | The issue with its labels, assignee, parent, spec, blockers, pull requests, sub-issues and comments. `--full` prints all of it. |
| `agent-skills pr <pr>` | The PR with its task, spec, standard, checks and files, and the review command. |
| `agent-skills frontier <parent>` | The parent's open sub-issues and the next task to build. |
| `agent-skills claim <n>` | Assign the task to `@me` and make its branch from the default branch. |
| `agent-skills next-cmd <stage> <n>` | The paste line that ends a stage: `review <pr>`, `build <parent>`, `plan <issue>` or `spec <issue>`. |
| `agent-skills run -- <cmd>` | Run a test, lint or build command once. It saves the full log and prints the exit code, the result lines and the last lines. Read the log when you need more, and do not run the command again. |
| `agent-skills next` | What `/agent-skills:next` prints, for the whole tracker. |

## Stages

| Stage | Command | Result |
| --- | --- | --- |
| Idea | `/agent-skills:idea-refine <issue>` | A sharp goal, as a comment on the issue. |
| Design | `/agent-skills:interview-me <issue>` | A settled design, as a comment on the issue. |
| Spec | `/agent-skills:spec <issue>` | `spec/<issue>-<slug>.md`. |
| Plan | `/agent-skills:plan <issue>` | One sub-issue per task. |
| Build | `/agent-skills:build <task issue>` | One branch, one pull request. |
| Bug | `/agent-skills:test <issue>` | A failing test, then the fix, on one branch with one pull request. |
| Review | `/agent-skills:review issue #<task>, PR #<pr>, spec <spec file>, standard <standard file>` | Findings against the standards and the spec. |

An issue that is one task with acceptance criteria goes straight to Build.

## Labels

| Label | Meaning |
| --- | --- |
| `needs-triage` | Nobody has judged the issue yet. |
| `needs-info` | The issue waits for an answer from its reporter. |
| `ready-for-agent` | One task with acceptance criteria. An agent can build it unattended. |
| `ready-for-human` | The work needs the user's hands or judgment. |
| `wontfix` | The issue will not be done. |

An open issue carries exactly one of these. Change a label only when the user approves it.

## Design

Read `GLOSSARY.md`, `docs/adr/` and `CODING_STANDARDS.md` (those that exist) before the first question. Use the glossary's terms. Report any conflict with an ADR.

Record each settled decision as an ADR in `docs/adr/` with the `documentation-and-adrs` skill, and continue the existing numbering. Add each settled term to `GLOSSARY.md` when the repo has one.

## Spec

Save the spec to `spec/<issue>-<slug>.md`, where `<issue>` is the source issue. Link the source issue on the first line. For commands, structure and code style, link `AGENTS.md`. Comment the spec's path on the source issue.

## Plan

Publish each task as a sub-issue of the source issue. Add blockers as native `blocked_by` dependencies. A task body names no blocker: a body list goes stale, and the native edges stay true.

Give every item of a spec's list to one task. A review of each task alone misses an item that two tasks share: the battle screen spec asked for six chrome rects, one task wrote the PNGs and another wrote the JSON, and the JSON got two.

Task body: `Parent`, `Spec` (the spec file's path), `What to build`, `Acceptance criteria`, `Verification` (the exact command). Label each task `ready-for-agent`.

`tasks/plan.md` holds the plan's decisions, risks and an ordered list of the task issue numbers. It is git-ignored scratch. A plan is complete when every issue it lists is closed, and a complete plan can be replaced without asking.

## Build

`/agent-skills:build` reads one argument, `auto`. Any other text selects single-task mode, so the task issue number you type is context. The plan is the open sub-issues of the source issue.

Pick the task with `agent-skills frontier <source issue>`. Claim it with `agent-skills claim <n>`, which also makes the branch.

One task, one branch, one pull request. Branch: `<type>/<issue>-<slug>`, or `retro/<name>` for retro work. Commit subject: `<type>: <summary> (#<issue>)`, with a conventional-commit type (`feat`, `fix`, `chore`, `docs`). PR title: a plain sentence. Put `Closes #<issue>` in the PR body. Bug tasks start with a failing test.

`/agent-skills:build auto` runs every task of one spec on one branch, `<type>/<source issue>-<slug>`, with one commit per task. Its pull request closes every task issue. `agent-skills claim <source issue> --no-assign` makes that branch, and `agent-skills claim <task> --no-branch` claims each task.

A spec's glossary line is a task, not a fact. A spec that says "`GLOSSARY.md` has **X**" may describe the glossary it means to leave behind, so check the file before you rely on it. If the term is missing, the first task that uses it adds the entry. Spec #49 said its four terms existed, none did, two implementers noticed and neither added them, and the code review found the gap.

Run the verify command from `AGENTS.md` (`Every task`) with `agent-skills run --` before each commit. Open the pull request, print the review command and stop. The user merges.

The review command is the session's last line, and `agent-skills next-cmd review <pr>` prints it:

```
/agent-skills:review issue #<task>, PR #<pr>, spec <spec file>, standard CODING_STANDARDS.md
```

- **Spec file**: the `Spec` line of the task body. When the task body has none, use the `spec/` path in the parent issue's body. When neither names one, leave out the `spec` part.
- In `auto` mode, `<task>` is the source issue.

A Bug session ends with the same command.

To have a worker model build the task, type `Build #<issue> with a <tier> worker`, or `Fix #<issue> with a <tier> worker` for a bug, and follow [Multi-model build workers](multi-model.md). That session reviews the worker's branch itself, so it ends with the PR's URL, not the review command.

## Review

Run the review in a new session, not in the build session. The command starts no subagent, so the build session would review its own work. Check out the PR branch first (`gh pr checkout <pr>`), because the command reviews staged changes or recent commits.

Run `/agent-skills:review` on the branch with the command that the Build section gives. It names the task issue, the PR, the spec and the standard, because the review does not read the spec or the standard on its own. 12 of the first 13 reviews in this repo ran without the spec or the standard, and each had to run again. Start the review with `agent-skills pr <pr>`, which shows all four.

Fix small findings in the review session. Start a new build session for large ones.

A worker's branch is the exception. The overseer session that dispatched the worker reviews it, and the findings go back to the worker as a comment on the task issue. The overseer does not fix them itself.

## Reports

Report every guess and every gap you accepted. Put any choice that changes user-visible behavior to the user before you commit.

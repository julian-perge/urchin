# Whether agents open the topic doc an index points at

Date: 2026-11-08. Issue #55 plans to turn `CLAUDE.md` into a short `AGENTS.md` index whose lines send the agent to topic docs under `docs/agents/`, and its one comment asks how often an agent opens the matching doc without being told to. This review reads the first-party documentation and source for Claude Code, Codex, the agents.md format, Cursor and GitHub Copilot, the published evaluations that come closest to the question, and the two first-party issue trackers. It then measures the question on this Mac's own Claude Code transcripts. Nothing in urchin changed except this file.

Every claim carries a tag:

- [source]: read in documentation, source code or a paper. The link is given.
- [measured]: counted from this Mac's transcripts or from a GitHub search. Section 4.1 and section 3 give the method.
- [anecdotal]: an issue report in a first-party tracker. It shows the behavior was reported, not how often it happens.
- [inferred]: reasoned from the cited sources. The reasoning is given.
- [guess]: no source read here settles it. Section 5 names the check that does.

## Answer

**Rarely, and mostly after the agent has already acted.** [measured] In 58 cases where a transcript had a pointer loaded and then did something the pointed-at doc covers, the agent never opened the doc in 44, opened it on its own in 11, and opened it on its own before its first related action in 7, which is 12%. The prompt named the doc in the other 3 (section 4.2).

- Main sessions did better than subagents. They opened the doc on their own in 7 of 12 cases, 4 of them before acting. Subagents did in 4 of 46, 3 before acting.
- urchin's own pointers: the issue tracker doc was opened in 2 of the 4 main sessions that ran `gh issue`, both times after the first `gh issue` call, and in none of the 19 subagents that ran it (section 4.2).

**Naming the doc in the prompt is what gets it read.** [measured] Subagents read a doc their brief named in 30 of 32 cases, and a doc reachable only through the loaded index in 5 of 313 (section 4.3).

**Phrasing the pointer as a trigger made no visible difference here.** [measured] Pointers written as "before X, read Y" or behind a condition label were opened on their own in 5 of 25 topic cases, and plain "See X" pointers in 6 of 33. [inferred] Both samples are small and come from different repos and tasks, so this shows that neither phrasing reached a majority, not that they are equal.

**The tools' own documentation agrees.** [source] Where a tool's docs or source cover it, a file is not loaded because an instruction file mentions it in words: Claude Code's docs say so, Codex's loader has no such step, and Cursor does not inline a file that a rule @-mentions. Anthropic, on a `CLAUDE.md` that tells Claude in words to read `AGENTS.md`: "Claude sees AGENTS.md only if it decides to open the file" ([memory](https://code.claude.com/docs/en/memory), section "Remove an earlier AGENTS.md workaround"). Apart from Claude Code's hooks, every mechanism that loads a doc on demand without the model choosing is keyed to file paths:

| Mechanism | Loads without the model choosing | When it loads | Read by | Evidence |
|---|---|---|---|---|
| Text in the root `AGENTS.md` or `CLAUDE.md` | Yes | Session start, and again after compaction | All four tools, each through the file name it reads | [source] 1.1, 1.3 to 1.5 |
| `@path` import in `CLAUDE.md` | Yes | Session start, with the importing file | Claude Code only | [source] 1.1 |
| `.claude/rules/*.md` with `paths:` | Yes | When Claude reads, writes or edits a matching file | Claude Code only | [source] 1.1 |
| Subdirectory `CLAUDE.md` | Yes | When Claude reads, writes or edits a file in that directory | Claude Code only | [source] 1.1 |
| Subdirectory `AGENTS.md` | Depends on the tool | Cursor: when working on files in that directory. Copilot: the nearest one wins. Claude Code: only when no `CLAUDE.md` exists. Codex: never below its launch directory | Cursor, Copilot, Claude Code in part | [source] 1.1, 1.3, 1.5 |
| Hook `additionalContext` | Yes | At the hook's event, such as before a matching Bash call | Claude Code only | [source] 1.1 |
| Skill matched by its description | No | When the model matches the description, or the user types its name | Claude Code, Codex | [source] 1.1 to 1.3, 2.1 |
| Plain pointer, or "before X, read Y" | No | When the model decides to open the file | All | [source] 1.1, 1.5; [measured] 4.2 |
| A subagent brief that names the doc | No, but it was read 30 of 32 times | The subagent's first turn | All | [measured] 4.3 |

**For #55:** [inferred] A "Read the doc that matches the task" list delivers a lesson only to the sessions that choose to open it, which here happened before the first related action in 7 of 58 cases. Lessons that guard against a known failure should load by mechanism: the few that apply to every task stay in `AGENTS.md`, file-area lessons attach to their files through path-scoped rules, every subagent brief names the topic doc, and the pointer list stays as the fallback for tools that read only `AGENTS.md`. Section 6 gives the layout and which parts are measured.

## How to read this

- A pair is one transcript and one doc whose pointer was in that transcript's loaded instructions. A topic case is a pair whose transcript later did something the doc covers. Section 4.1 defines "did something" per doc.
- Opened on its own, or unprompted: opened when no user message, loaded skill text or subagent brief before it named `docs/agents/<doc>.md`. A read that follows the agent's own `ls docs/agents` or a re-read of the index file still counts as unprompted.
- Before and after are relative to the first topic action after the pointer loaded.
- urchin is named. The three other local repos with the same layout are repos A, B and C. Their names, domains and the names of their domain-specific docs are left out, and so is every transcript's text.
- The transcripts ran Claude Code v2.1.317 to v2.1.319, mostly on Claude Opus 5.5 with some on Sonnet 5.5 and Haiku 5.5. Their sessions started between 2026-11-05 and 2026-11-09 UTC, and they were read on 2026-11-09 at 04:30 UTC. [source] Claude Code deletes transcripts after its retention period ([memory](https://code.claude.com/docs/en/memory), "Storage location"), and [measured] the oldest transcript left on this Mac is from 2026-10-04, a month before the first of these pointers, so retention removed no session that could have loaded one. Codex was not measured on this Mac.
- [source] In the installed mattpocock-skills 1.3.1 plugin (`rg 'docs/agents/|provided to you' skills/engineering/*/SKILL.md` inside the plugin directory), the only skill whose text names a `docs/agents/` path is `setup-matt-pocock-skills`, which writes the files. `code-review`, `implement-spec`, `to-spec`, `to-tickets`, `triage` and `wayfinder` say the tracker or the label mapping should already be in context and send the user to the setup skill if not, and `wayfinder` also tells the agent to consult the tracker doc's wayfinding section without giving its path. [measured] Of those six, only `code-review` was loaded in a transcript that had the pointer, and outside the sessions that ran the setup skill no open followed a skill that named the doc.
- Codex source links are pinned to openai/codex commit `8703d32bd0ea5cf26768859a3dd476df906ba053` (`gh api repos/openai/codex/commits/main`, 2026-11-09). Web pages were read on 2026-11-08 and 2026-11-09.

## 1. How each tool loads instructions and the docs they mention

### 1.1 Claude Code

- [source] At launch Claude Code loads `CLAUDE.md` and `CLAUDE.local.md` from the working directory and every directory above it. A subdirectory's `CLAUDE.md` loads once Claude reads, writes or edits a file in that subdirectory, a single-file `cat` or `head` included ([memory, How CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load)).
- [source] The content reaches the model as a user message after the system prompt, and the docs promise no strict compliance ([memory](https://code.claude.com/docs/en/memory), "Claude isn't following my CLAUDE.md").
- [source] An `@path` import expands at launch next to the file that imports it, recursively up to four hops, so it organizes a long file without lowering its context cost. A path inside backticks stays literal text ([memory, Import additional files](https://code.claude.com/docs/en/memory#import-additional-files)). urchin's three pointer lines are backticked paths with no `@`, so they are plain mentions.
- [source] A plain mention is not loaded. The docs make the point in their advice on old `AGENTS.md` workarounds, quoted in the Answer, and tell the reader to replace such a sentence with an `@AGENTS.md` import ([memory](https://code.claude.com/docs/en/memory), "Remove an earlier AGENTS.md workaround").
- [source] A path-scoped rule, a `.claude/rules/*.md` file with a `paths:` list, loads when Claude uses Read, Write or Edit on a matching file or reads one with a single-file Bash command. A rule without `paths:` loads at launch like `.claude/CLAUDE.md` ([memory, Path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules)). The docs compare this with per-directory `CLAUDE.md` files and recommend rules when the same convention covers scattered paths ([large codebases](https://code.claude.com/docs/en/large-codebases), "Choose between per-directory CLAUDE.md and path-scoped rules").
- [source] A file that loads on demand and is over a per-file limit, 40,000 characters with a 200K context window, arrives cut short with a note to read the rest, and the rest stays out of context until Claude chooses to read it ([memory, Claude ignores the end of my subdirectory CLAUDE.md](https://code.claude.com/docs/en/memory#claude-ignores-the-end-of-my-subdirectory-claude-md)).
- [source] Since v2.1.277 Claude Code reads `AGENTS.md` as project instructions, but by default only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists in the working directory or above it. With one present it reads the `CLAUDE.md` files only. By default a subdirectory's `AGENTS.md` is read only in that no-`CLAUDE.md` case, and only when Claude opens a file there with the Read tool. A Project instructions setting can make Claude read both kinds of file. Some sessions cannot read `AGENTS.md` at all, such as the first session after an upgrade from v2.1.276 or earlier, and the docs recommend an `@AGENTS.md` import for those ([memory, AGENTS.md](https://code.claude.com/docs/en/memory#agents-md)).
- [measured] The transcripts agree. Sessions that started where no `CLAUDE.md` existed in the working directory or above it listed a parent directory's `AGENTS.md` as a loaded project file, and no urchin session listed that file, because urchin has a `CLAUDE.md` (the `instructions` attachments described in section 4.1).
- [source] The docs target under 200 lines per `CLAUDE.md` and say longer files reduce adherence. They send multi-step procedures to skills and part-of-the-codebase instructions to path-scoped rules ([memory, Write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions)).
- [source] A skill's name and description sit in context on every turn, and its body loads when Claude or the user invokes it ([skills](https://code.claude.com/docs/en/skills)). Claude picks a skill by matching the task against descriptions and can miss one when descriptions are vague or overlap ([features overview](https://code.claude.com/docs/en/features-overview), "Understand how features load"). The listing's budget is 1% of the context window, it drops the descriptions of the least used skills when it overflows, and each description is capped at 1,536 characters. A skill's `paths:` field limits automatic loading to matching files. The page has its own troubleshooting list for a skill that does not trigger ([skills, Skill not triggering](https://code.claude.com/docs/en/skills#skill-not-triggering)).
- [source] A subagent starts with `CLAUDE.md` and git status, except the built-in Explore and Plan agents, which start with neither, and agents defined with `omitClaudeMd` ([features overview](https://code.claude.com/docs/en/features-overview), Subagents tab).
- [source] After compaction Claude Code re-reads the root `CLAUDE.md` from disk, nested `CLAUDE.md` files and path-scoped rules load again on demand ([memory](https://code.claude.com/docs/en/memory), "Instructions seem lost after /compact"), and invoked skills are re-attached at up to 5,000 tokens each and 25,000 in total ([skills](https://code.claude.com/docs/en/skills)). [measured] In the session that commissioned this review, three of its four compactions were followed within a second by an `instructions` attachment that carried urchin's `CLAUDE.md`, pointer lines included.
- [source] A hook can return `additionalContext`. For PreToolUse and PostToolUse, Claude Code wraps it in a system reminder next to the tool result, and for UserPromptSubmit it goes next to the prompt. The InstructionsLoaded hook fires whenever a `CLAUDE.md` or rules file loads, with load reasons such as `path_glob_match`, `nested_traversal` and `compact` ([hooks](https://code.claude.com/docs/en/hooks), "Add context for Claude").

### 1.2 Agent Skills and progressive disclosure

- [source] Anthropic's engineering post describes three levels: every skill's name and description in the system prompt at startup, the `SKILL.md` body once the skill looks relevant, and further linked files that Claude may open as it needs them ([Zhang, Lazuka and Murag, 2025-10-16](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)).
- [source] The authoring guide warns that Claude may only preview a file referenced from another referenced file, for example with `head -100`, and therefore keeps references one level deep from `SKILL.md`. It asks for a table of contents at the top of reference files over 100 lines, and it lists missed connections, references Claude fails to follow, among the things to watch for ([Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)).
- [source] Anthropic's context engineering post describes Claude Code as a hybrid, with `CLAUDE.md` loaded up front and glob and grep for retrieval at runtime. It names the cost of runtime retrieval: exploring is slower than reading precomputed data, and without guidance an agent wastes context on dead ends ([Rajasekaran et al., 2025-09-29](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)).
- [measured] The previews show up locally: 20 of the 42 first opens in section 4 were limited to a search, a line range or a pipe into `head`, `rg` or similar, including 6 of the 7 in main sessions.

### 1.3 Codex

- [source] Codex builds its instruction chain once per run. It reads the global `AGENTS.override.md` or `AGENTS.md` in its home directory, then one file per directory from the project root down to the working directory, checking `AGENTS.override.md`, then `AGENTS.md`, then any `project_doc_fallback_filenames`, and concatenates them root first ([AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md), where `developers.openai.com/codex/guides/agents-md` now redirects).
- [source] The loader matches. The project root is the nearest ancestor with a marker, `.git` by default, and the search goes neither above it nor below the working directory ([agents_md.rs:7-18](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/core/src/agents_md.rs#L7-L18), [:222-247](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/core/src/agents_md.rs#L222-L247)). Each directory contributes the first name that exists ([:251-276](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/core/src/agents_md.rs#L251-L276), [:279-300](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/core/src/agents_md.rs#L279-L300)). The default budget is 32,768 bytes ([defaults.toml:9](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/config/defaults.toml#L9)), and the file that crosses it is truncated with a warning while later files are skipped ([agents_md.rs:145-173](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/core/src/agents_md.rs#L145-L173)).
- [source] The loader resolves no links or imports. It reads only the files those rules name and concatenates their text ([agents_md.rs:384-417](https://github.com/openai/codex/blob/8703d32bd0ea5cf26768859a3dd476df906ba053/codex-rs/core/src/agents_md.rs#L384-L417)). [anecdotal] Requests for an include directive (openai/codex#17401) and for loading nested `AGENTS.md` files as the agent moves through the tree (openai/codex#12115) are open.
- [source] Codex skills follow the same pattern as Claude Code's: name, description and path in the initial list, the full `SKILL.md` once Codex picks the skill, a list budget of 2% of the context window, and descriptions shortened first when the list overflows ([Build skills](https://learn.chatgpt.com/docs/build-skills)).

### 1.4 The agents.md format

- [source] An `AGENTS.md` is plain Markdown with no import or link mechanism. Agents read the nearest one in the directory tree, the one closest to the edited file wins, and explicit chat prompts override all of them. The Agentic AI Foundation under the Linux Foundation now stewards the format ([agents.md](https://agents.md/)).

### 1.5 Cursor and GitHub Copilot

- [source] Cursor has four rule types: always applied, applied when the agent judges the description relevant, applied when a file matches the rule's globs, and applied when @-mentioned. A file @-mentioned inside a rule is not inlined into the prompt, and Cursor says to put whatever must always be in context in the rule body. Nested `AGENTS.md` files apply when working with files in their directory. Cursor suggests keeping rules under 500 lines ([Cursor rules](https://cursor.com/docs/context/rules)).
- [source] Copilot's path-specific instructions, `.github/instructions/*.instructions.md` files with an `applyTo` glob, apply when the glob matches a file Copilot is working on, and only in the cloud agent and code review. The nearest `AGENTS.md` in the tree takes precedence ([Copilot repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions)).
- [inferred] Across 1.1 to 1.5, every mechanism that loads a doc on demand without the model choosing is keyed to file paths, apart from Claude Code's hooks. None is keyed to the kind of task, so a doc about a workflow such as filing issues can only load up front, through a hook, or by the model's choice.

## 2. Published measurements

### 2.1 On-demand docs and skills

- [source] Vercel ran evals on Next.js 16 APIs that are missing from training data. Its post is the primary source for its own eval, and it names neither the model nor the agent. The docs skill was never invoked in 56% of cases and left the pass rate at the 53% baseline. An instruction to explore the project first and then invoke the skill raised it to 79%, and a stronger "must invoke" wording made the agent fixate on the docs and miss project context. An always-loaded 8 KB index in `AGENTS.md` that pointed at doc files in the project, with a standing instruction to prefer retrieval over training knowledge, reached 100% ([Gao, 2026-01-27](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)). [inferred] The agent still had to open the indexed files, so this compares a skill with an always-loaded index plus a standing order, not with no index.
- [source] The first version of SkillsBench ran 86 tasks across 11 domains in 7 agent and model configurations, over 7,308 trajectories. Curated skills raised the average pass rate by 16.2 points, self-generated skills gave no benefit on average, and 16 of 84 tasks did worse with skills ([Li et al., arXiv 2602.12670v1](https://arxiv.org/abs/2602.12670v1)). Version 4, of 2026-06-14, reports 33.9% to 50.5% across 87 tasks and 18 model and harness configurations.
- [source] SkillJuror held each skill's content fixed on 82 SkillsBench tasks and changed only its layout. A short root file pointing at supporting files, instead of one flat file, raised the distinct supporting resources an agent touched per trajectory from 1.18 to 3.85 and added 17 passing trials out of 410, or 4.1% ([Chen et al., arXiv 2606.11543](https://arxiv.org/abs/2606.11543)). [inferred] Once a skill is loaded, its pointers do get followed.
- [source] On 557 SWE-chat sessions, instruction files and agents' working notes made up 60.5% of the agents' documentation interactions, classical technical documentation 10.6% and API references 1.3%. 70.2% of consultations were self-initiated and 7.5% followed a failure ([Gao and Chen, arXiv 2608.20195](https://arxiv.org/abs/2608.20195)). The abstract does not say whether agents followed links out of instruction files.
- [inferred] No study found here measures how often an agent opens a doc that an always-loaded index points at. Vercel's 56% is the nearest number, and it is about a skill.

### 2.2 Context files

- [source] Context files did not raise task success on SWE-bench tasks or on repositories with developer-written files, and they raised inference cost by over 20%. Agents did follow the instructions inside them ([Gloaguen et al., arXiv 2602.11988](https://arxiv.org/abs/2602.11988), v3 of 2026-09-29).
- [source] On 124 pull requests in 10 repositories, an `AGENTS.md` went with a 28.64% lower median runtime and 16.58% fewer output tokens at comparable completion ([Lulla et al., arXiv 2601.20404](https://arxiv.org/abs/2601.20404)).
- [source] A 288-run ablation across Claude Code and Codex on 17 tasks found that the context strategy changed correctness by no measurable amount, bounded to roughly 10 to 15 points ([Khatri, arXiv 2607.27250](https://arxiv.org/abs/2607.27250)).

### 2.3 Instruction count and context length

- [source] IFScale: with 500 keyword instructions, the best of 20 models reached 68% accuracy, and models favored earlier instructions ([Jaroslawicz et al., arXiv 2507.11538](https://arxiv.org/abs/2507.11538)).
- [source] Models use information at the start or end of a long input better than in the middle ([Liu et al., arXiv 2307.03172](https://arxiv.org/abs/2307.03172), TACL).
- [source] Across 18 models, performance grew less reliable as input length grew, even on simple tasks ([Hong, Troynikov and Huber, 2025-07-14](https://www.trychroma.com/research/context-rot)).
- [source] With retrieval made perfect, performance still fell by 13.9% to 85% as inputs grew within the models' claimed context length, and it fell even when the added tokens were whitespace ([Du et al., arXiv 2510.05381](https://arxiv.org/abs/2510.05381)).
- [inferred] This is the price of moving every lesson into the always-loaded file instead: each added line competes with all the others.

## 3. Reported behavior in the issue trackers

[anecdotal] The counts come from the GitHub search API on 2026-11-09 (`gh api -X GET search/issues -f q=...`). They show that people report each behavior and say nothing about how often it happens. For the first row, a title counts as ignored or not followed when it matches this case-insensitive pattern:

```text
ignor|not (being )?follow|n.t follow|not obey|n.t obey|disregard|violat|not respect|not adher|n.t adher|forget|forgot|not honou?r|n.t honou?r|not (being )?appl|n.t appl|not (being )?(us|read)ed|n.t (use|read)|stops? following|overrid
```

| Query | Issues | Classification |
|---|---|---|
| anthropics/claude-code, `is:issue in:title CLAUDE.md` | 984 | 332 titles match the pattern. A systematic sample of every 13th match, 25 titles, has 21 about the model not following loaded instructions and 4 about instructions not reaching the model or a feature |
| anthropics/claude-code, `is:issue "referenced in CLAUDE.md"` | 41 | By hand: 3 report a referenced file not read or not followed (#28006, #29446, #51039), 3 ask to change how referenced files load (#11759, #23952, #77818), 9 are import bugs, 11 are general adherence complaints, 15 are other |
| anthropics/claude-code, `is:issue in:title skill trigger` | 73 | By hand: 9 report a skill not loading on its own when expected (#10766, #21947, #30387, #32184, #34648, #36570, #52185, #62049, #68086), 3 of them in headless mode, and 2 report one loading too eagerly (#30355, #69164) |
| openai/codex, `is:issue in:title AGENTS.md` | 155 | 32 titles match the pattern. By hand: 15 say the model ignored a loaded `AGENTS.md`, 13 say a file was not loaded, was truncated or was looked for in the wrong place (#2927, #3540, #5113, #5804, #9836, #12128, #13386, #15421, #15683, #23223, #30789, #54755, #58389), and 4 are other |
| openai/codex, `is:issue in:title skill trigger` | 10 | By hand: 6 report a skill loading when it should not, such as #34712 and #34896, and none report one failing to load |

- [anecdotal] One report found that a skill's `paths:` field never loaded the skill when Claude read a matching file, with the API traffic inspected through a proxy. It was closed as not planned (anthropics/claude-code#62049).

## 4. Local measurement

### 4.1 Method

1. Repos. [measured] Four repos on this Mac have a `CLAUDE.md` or `AGENTS.md` that points at `docs/agents/*.md`: urchin, through plain lines in its `CLAUDE.md` since `400d0db7`, and repos A, B and C, through `AGENTS.md` imported by a one-line `CLAUDE.md`. They were found by grepping each repo whose Claude Code project directory exists for `docs/agents` in `CLAUDE.md`, `AGENTS.md` and `CLAUDE.local.md`. One more project directory belongs to a repo directory that no longer exists, and none of its transcripts loaded a pointer.
2. Transcripts. Every JSONL file in the matching project directories under `<config dir>/projects/`: urchin's own directory and its three desktop worktree directories, repos A to C, the missing repo, and one scratch workspace whose transcripts mention `docs/agents`. Main sessions are `<session>.jsonl` and subagent sidechains are `<session>/subagents/agent-*.jsonl`. This review's own sidechain was left out. That makes 233 files, read one line at a time.
3. Pointer loaded. Claude Code writes an `attachment` entry of type `instructions` that lists loaded instruction files with their path and full content, at session start and at later reloads such as after compaction. A doc counts as pointed at from the first such entry whose content contains `docs/agents/<doc>.md`. 70 files had one.

   ```bash
   jq -c 'select(.type=="attachment" and .attachment.type=="instructions")
     | [.timestamp, [.attachment.files[] | select(.content|test("docs/agents/")) | .path]]' SESSION.jsonl
   ```

4. Actions, in order. Each `tool_use` block in the assistant messages, with its `file_path` or `command`:

   ```bash
   jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
     | {name, path: .input.file_path, cmd: .input.command}' SESSION.jsonl
   ```

5. Topic action, counted only after the pointer loaded:
   - `issue-tracker.md`: a Bash call to `gh issue`, `gh search issues` or `gh api .../issues` against the repo's own tracker. Repo A keeps its tracker as local files, so there it is a Read, Write or Edit of a file under its tracker directory.
   - `triage-labels.md`: a Bash call with `--label`, `--add-label`, `--remove-label` or `gh label`, or with one of the five label strings. In repo A, a Write or Edit of a tracker file whose new text holds a label string.
   - `domain.md`: a Write or Edit of `GLOSSARY.md`, `GLOSSARY-MAP.md` or a file under `docs/adr/`.
   - Trigger-phrased pointers in repos A to C: the edits or commands their condition names, such as code edits, test edits, commits, build file edits, test runner commands and edits under a named directory.
6. Opened: a Read of the doc, a Grep scoped to it, or a Bash call in which `cat`, `head`, `tail`, `sed -n`, `awk`, `nl`, `less`, `bat`, `rg`, `grep` or `git show` takes its path as an argument. A call that only adds, commits, copies, diffs or lints the file does not count. Searches and line ranges count as opened and are also tallied as limited.
7. Prompted: a user message, a loaded skill's text (the meta message that starts with the skill's base directory) or, for a subagent, its first message, the brief, named `docs/agents/<doc>.md` before the first open. Anything else is unprompted.
8. Excluded: transcripts that created or rewrote a `docs/agents` file or ran the setup skill that writes them, because they knew the content. That removes 3 main sessions, one each in urchin, repo B and repo C, and the one pair in a repo C subagent that rewrote the doc.

### 4.2 Results when the topic came up

[measured]

| Transcripts | Pairs (transcripts) | Opened on its own, before the first topic action | Opened on its own, after | Opened, prompt named it | Never opened |
|---|---|---|---|---|---|
| Main sessions, plain pointer | 8 (5) | 2 | 3 | 0 | 3 |
| Main sessions, trigger-phrased pointer | 4 (1) | 2 | 0 | 0 | 2 |
| Subagents, plain pointer | 25 (22) | 1 | 0 | 2 | 22 |
| Subagents, trigger-phrased pointer | 21 (14) | 2 | 1 | 1 | 17 |
| All | 58 | 7 | 4 | 3 | 44 |

urchin's three pointers, from the rows above:

| Doc | Main sessions with the topic | Opened on its own | Never | Subagents with the topic | Opened | Never |
|---|---|---|---|---|---|---|
| `issue-tracker.md` | 4 | 2, both after the first `gh issue` call | 2 | 19 | 0 | 19 |
| `triage-labels.md` | 2 | 1, just before the first label call | 1 | 0 | - | - |
| `domain.md` | 0 | - | - | 3 | 2 named in the brief, 1 on its own | 0 |

- [measured] The issue topic arrived early. In the three urchin main sessions that had the pointer from the start, the first `gh issue` call was tool call 3, 19 and 24, and in the fourth, `gh issue` calls began before the pointer existed. 18 of the 19 subagents got a brief that spelled out the `gh issue view` call and made it their first or second tool call, so they had no reason to look anything up. The 19th reached its first `gh issue` call at tool call 95.
- [measured] The one subagent that opened `domain.md` on its own had already read an ADR. Its open came before its first edit to `GLOSSARY.md` or `docs/adr/` but after its first read of one.
- [measured] In repo A's one main session the trigger-phrased pointers split two ways. The architecture and execution docs were both opened early, before the first code edit and before the first run they cover. The testing doc was never opened across 27 test edits, and the commit workflow doc was never opened across 62 commits.

### 4.3 Whether the doc was named

[measured] Every pair with the pointer loaded, whether or not the topic came up, transcripts that wrote the doc left out:

| Transcripts | Doc named in the brief | Read | Doc reachable only through the loaded index | Read |
|---|---|---|---|---|
| Subagents, urchin | 2 | 2 | 61 | 1 |
| Subagents, repos A to C | 30 | 28 | 252 | 4 |
| Main sessions, urchin and repo A | 0 | - | 22 | 7 |

### 4.4 Limits

- Small sample: 6 main sessions with a pointer and no authoring, in two repos, started on 2026-11-07 and 2026-11-08 UTC, for one user and one tool.
- The subagent numbers mostly measure the parent's briefs. When a brief hands over the exact command, as 18 of the 19 urchin briefs with `gh issue` activity did, there is nothing left to look up.
- Topic detection only sees actions. A topic that came up in conversation and led to no matching tool call is missed.
- Opening the doc stands in for using it. Whether the sessions that skipped `issue-tracker.md` broke its conventions was not measured. [guess] Many did not need it, because urchin's one-line summary already says the tracker is GitHub Issues through `gh`, and `gh` defaults cover viewing and commenting.

## 5. Open questions and checks

- C1, path-scoped rules in subagents and after compaction. [guess] The pages read here say subagents start with `CLAUDE.md` and say nothing about rules there. Add an InstructionsLoaded hook that logs the file path and load reason, run one subagent that reads a matching file, and run `/compact` in a main session that then reads one. The log settles both.
- C2, a symlinked rule. [guess] Whether `.claude/rules/<topic>.md` as a symlink to `docs/agents/<topic>.md`, with the `paths:` frontmatter in the doc, loads on a matching read. The same hook settles it in one session.
- C3, a controlled comparison. The same ten urchin task prompts in fresh sessions with one lesson delivered four ways: a "See X" pointer, a "before X, read Y" pointer, a path-scoped rule and inline text. Count opens or loads before the first related action, and whether the lesson's original failure comes back.
- C4, a rerun. Run section 4.1 again a week after #55 lands, with the same definitions, and compare lessons delivered by rules with lessons behind pointers.
- C5, Codex. The same count from Codex session logs, which this review did not read.

## 6. What this implies for #55

Measured here: the open rates in sections 4.2 and 4.3. Read from sources: what each mechanism loads and when, in section 1. Everything else in this section is inferred from those two, and it is tagged that way.

1. Do not count on the "Read the doc that matches the task" list to deliver lessons. [measured] In this user's own sessions such pointers were opened before the first related action in 7 of 58 topic cases, and subagents opened them on their own in 4 of 46. [source] Anthropic's docs say a file mentioned in words is seen only if Claude decides to open it. [inferred] Keep the list, because it is the only route Codex and other tools have to the topic docs, and phrase each entry as the trigger it is, since that costs nothing. Do not treat it as delivery.
2. Sort the lessons by what should load them. [inferred]
   - Every task, or a mistake that is expensive to repeat: inline in `AGENTS.md`, in the "Every task" list. [source] Anthropic targets under 200 lines and says longer files reduce adherence, and section 2.3 measures the same effect.
   - Tied to files: a path-scoped rule. For urchin that means `dev/source_files/action_script/**` for the ActionScript reading lessons, `dev/urchin_dev/swf/**` for the art extraction lessons, and `scripts/**`, `scenes/**` and `test/**` for the Godot lessons. [source] Each then loads when Claude reads, writes or edits a matching file, whatever the task says. It works in Claude Code only, so the same text has to stay reachable from `AGENTS.md`. One file can serve both if each rule is a symlink to its topic doc, which C2 checks.
   - Tied to commands rather than files, such as running `--import` after writing under `assets/` or committing the `.png.import` and `.uid` sidecars: these follow a command, not a file Claude opens, so they belong in the "Every task" list, or in a hook if they must hold every time. [source] A PreToolUse hook can add a doc's text next to the result of a matching Bash call.
   - Workflow docs such as the issue tracker: [measured] agents ran `gh issue` calls before opening the doc or without ever opening it. [source] The mattpocock skills that use the tracker expect its details to be in context already. [inferred] Put the facts `gh` does not suggest into the summary line itself, such as the sub-issue and blocking commands, and leave the rest in the doc.
   - Procedures run on request: a skill the user invokes by name. [source] Description matching is not dependable either: Vercel saw a skill go unused in 56% of cases, and Anthropic's docs carry a troubleshooting list for skills that do not trigger.
3. Name the topic doc in every subagent brief. [measured] Briefs that named a doc got it read in 30 of 32 cases, against 5 of 313 for the index alone. [source] Explore and Plan subagents do not receive `CLAUDE.md` at all, so for them the brief is the only route.
4. Keep `CLAUDE.md` as `@AGENTS.md`, as #55 plans. [source] Reading `AGENTS.md` directly needs v2.1.277 or later and is unavailable in some sessions, and Anthropic recommends the import for exactly those sessions. With that root `CLAUDE.md` present, Claude Code skips subdirectory `AGENTS.md` files by default. [inferred] So under the default setting, per-directory files for Claude Code have to be `CLAUDE.md` files or rules, not nested `AGENTS.md` files, and [source] Codex never loads nested files below its launch directory either.
5. Shape each topic doc for a partial read. [measured] 20 of 42 first opens here were a search, a line range or a truncated pipe. [source] Anthropic's authoring guide asks for references one hop from the index and a table of contents at the top of any file over 100 lines. [inferred] Put the rule first and its commit evidence after it, so a `head` of the file still carries the rule.

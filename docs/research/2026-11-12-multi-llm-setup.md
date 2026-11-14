# Let Opus supervise two cheap workers

The most robust way to reproduce the comment's setup is to run **stock Claude Code, signed in normally, as the Opus 5.5 overseer at `xhigh` effort**, and have it hand implementation to **OpenCode running headlessly against MiMo-V2.6-Pro and DeepSeek V4.1 Flash**, each task in its own git worktree, with Opus reviewing the resulting diff. That split keeps the Claude subscription, effort controls and review features intact, because Anthropic does not support non-Claude models inside Claude Code through any gateway ([Claude Code docs](https://code.claude.com/docs/en/llm-gateway)). All three names in the comment are real, shipping models, and the price gap is large: Opus 5.5 costs $4/$20 per million input/output tokens against $0.435/$0.87 for MiMo and $0.15/$0.60 for DeepSeek off-peak. On Windows 10 the whole stack belongs inside WSL2; on the MacBook it runs natively. The evidence on payoff is mixed: the two most careful 2026 write-ups saw token bills fall by roughly 60% while active time and supervision rose, and no mixed variant beat a solo frontier model on quality, cost and time at once. Nobody has published a test of this exact trio, so treat the setup as an experiment you measure, not a proven saving. Two findings cut against the comment's own hierarchy: DeepSeek's October snapshot matches or beats MiMo on public coding benchmarks, and a flat Claude subscription removes most of the economic case for delegating at all.

## The three models span a 15–30x price gap

Each informal name maps to a specific product. "Opus 5.5 xtra high" is Anthropic's **Claude Opus 5.5** (`claude-opus-5-5`, released 22 September 2026, 1M context) run at the `xhigh` effort level, which sits between `high` and `max` and is two notches above the model's `medium` default ([mixed-news](https://mixed-news.com/en/claude-opus-5-5-price-4-per-million-tokens-usage-limits/), [Claude Platform docs](https://platform.claude.com/docs/build-with-claude/effort)). "Mimo 2.6 pro high" is Xiaomi's open-weights **MiMo-V2.6-Pro** (`mimo-v2.6-pro`, 21 September 2026); one coding-agent registry maps only `off` and `high` reasoning levels for it, so "high" most likely just means reasoning switched on ([OpenRouter](https://openrouter.ai/xiaomi/mimo-v2.6-pro), [pi.dev](https://pi.dev/models/xiaomi-token-plan-ams/mimo-v2-6-pro)). "DeepSeek 4.1 Flash 1017" is the 17 October 2026 new-weights snapshot of **DeepSeek V4.1 Flash**, called `deepseek-flash` on DeepSeek's own API and `deepseek/deepseek-v4.1-flash-1017` on OpenRouter ([mer.vin](https://mer.vin/news/deepseek-v4-1-flash-1017-open-weights-api-and-pricing/), [Morph](https://www.morphllm.com/deepseek-api)).

| | Opus 5.5 | MiMo-V2.6-Pro | DeepSeek V4.1 Flash (1017) |
|---|---|---|---|
| Role in the comment | Design, review, overseer | Medium and large tasks | Small tasks |
| Input / output per 1M tokens | $4 / $20 | $0.435 / $0.87 | $0.15 / $0.60 off-peak; $0.30 / $1.20 peak |
| Cache read per 1M | $0.20 | $0.0036 | $0.003 off-peak |
| Fixed-price option | Claude subscription (Pro and higher tiers; check current prices and Opus limits) | Token Plan $6, $16, $50 or $100 per month | None; pay per token only |
| Terminal-Bench 4.0 | 66.4% | about 35% | 42.3% (vendor-reported) |

Prices come from launch coverage and vendor pages ([mixed-news](https://mixed-news.com/en/claude-opus-5-5-price-4-per-million-tokens-usage-limits/), [MiMo pricing](https://mimo.mi.com/docs/en-US/price/pay-as-you-go), [OrcaRouter](https://www.orcarouter.ai/blog/deepseek-v4-1-flash-pricing)); plan prices from a tracker and Xiaomi's docs ([BenchLM](https://benchlm.ai/md/coding-plans.md), [Xiaomi Token Plan](https://mimo.mi.com/docs/en-US/tokenplan/Token Plan/subscription)); benchmark rows from [computingforgeeks](https://computingforgeeks.com/claude-opus-5-5-released-features-benchmarks/), [OpenRouter](https://openrouter.ai/xiaomi/mimo-v2.6-pro) and [mer.vin](https://mer.vin/news/deepseek-v4-1-flash-1017-open-weights-api-and-pricing/). Blended at three input tokens per output token, that works out to roughly $8.00 per million for Opus, $0.54 for MiMo and $0.26 for DeepSeek off-peak, so the workers are about **15x and 30x cheaper**. Thinking tokens bill at the output rate, so `xhigh` widens the real gap further ([computingforgeeks](https://computingforgeeks.com/claude-opus-5-5-released-features-benchmarks/)).

Two details undercut the comment's ordering. DeepSeek charges double during weekday peak windows (01:00–04:00 and 06:00–10:00 UTC), at which point MiMo's output is the cheaper of the two ([Morph](https://www.morphllm.com/deepseek-api)). And on like-for-like coding rows DeepSeek 1017 leads MiMo: DeepSWE v1.1 77.0 against roughly 72, ProgramBench 29.1 against 26.5 ([mer.vin](https://mer.vin/news/deepseek-v4-1-flash-1017-open-weights-api-and-pricing/), [aireiter](https://aireiter.com/blog/mimo-v2-6-pro-review-tested)). Vendor numbers deserve a discount, though: DeepSeek's Terminal-Bench 2.1 score fell from a claimed 90.6% to 74.5% in an independent run ([BenchLM](https://benchlm.ai/models/deepseek-v4-1-flash)). The defensible reading is that Opus is clearly a tier above both, while "MiMo for bigger, DeepSeek for smaller" is the commenter's preference, not a benchmark result. Try both workers on the same tasks before committing.

Xiaomi's Token Plan is roughly at par with pay-as-you-go at the $6 tier (4.1B credits buy about 13.7M uncached MiMo-Pro input tokens at the published 300 credits per token), so it buys predictability, not a discount. It is also restricted to interactive coding tools: using the key for automated scripts can get it suspended ([Xiaomi Token Plan](https://mimo.mi.com/docs/en-US/tokenplan/Token Plan/subscription)). Since the recommended loop drives the worker from a script-like shell call, **use a prepaid pay-as-you-go MiMo key**, not a Token Plan key.

## Claude Code oversees best when workers run in OpenCode

Three architectures can assign different vendors to different roles, and they differ mainly in what breaks.

| Approach | How roles get models | What you give up |
|---|---|---|
| **Claude Code overseer + headless OpenCode workers (recommended)** | Opus in Claude Code; `opencode run -m provider/model` per task | Worker activity is visible only through its final output and the diff |
| OpenCode (or Kilo Code) as the single harness | Each agent or subagent takes a `provider/model#variant` string | Opus bills per token via API key; no Claude subscription login |
| Claude Code behind a router (claude-code-router, LiteLLM) | Proxy maps model IDs or subagent tags to vendors | Unsupported by Anthropic; subscription login is replaced once a gateway credential is set |

Claude Code has real per-role controls: subagent files in `.claude/agents/` accept `model` and `effort` fields, `opusplan` uses Opus for planning and Sonnet for execution, and an experimental advisor lets a cheaper model consult Opus ([Claude Code subagents](https://code.claude.com/docs/en/subagents), [model config](https://code.claude.com/docs/en/model-config)). All of them assume Claude models. The advisor attaches only to recognised Claude main models, so it cannot sit above MiMo or DeepSeek ([advisor docs](https://code.claude.com/docs/en/advisor.md)). A process talks to one endpoint, so mixing vendors inside one Claude Code session requires a proxy, and once a gateway credential is active, requests bill per token to that credential instead of the subscription ([LLM gateway docs](https://code.claude.com/docs/en/llm-gateway)). Routers also bring edit-format failures and lost prompt caching when switching models ([Morph](https://www.morphllm.com/claude-code-router)).

OpenCode is the cleanest single-tool fit. A subagent "uses its configured model", any OpenAI-compatible endpoint can be added as a provider, and `opencode run` executes non-interactively with `--model` and `--agent` flags ([OpenCode agents](https://opencode.ai/docs/agents/), [providers](https://opencode.ai/docs/providers/), [CLI](https://thdxr.dev.opencode.ai/docs/cli)). The catch is Opus: OpenCode dropped Claude Pro/Max login in February 2026 after Anthropic's legal requests, so Opus there costs API rates ([The Register](https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access)). Combining the two tools gets the best of each, and it is the one published cross-vendor overseer design with data: in April 2026 a tester had Opus drive OpenCode as a subprocess to dispatch work to Kimi and Qwen ([AkitaOnRails](https://akitaonrails.com/en/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/)).

Other tools fit less well. Aider offers only two coding roles (`--architect` main model plus `--editor-model`; the weak model writes commit messages), Goose switches lead and worker by turn count rather than by task, and Roo Code was archived on 15 May 2026 ([Aider](https://aider.chat/docs/config/options.html), [Goose](https://block.github.io/goose/docs/tutorials/lead-worker), [Morph](https://www.morphllm.com/roo-code)). Kilo Code is the viable VS Code alternative, with OpenCode-style per-agent models ([Kilo docs](https://kilo.ai/docs/customize/custom-subagents)).

## Setup runs through WSL2, direct keys and prepaid balances

**Platform.** Claude Code supports Windows 10 1809+ natively, but sandboxing works only under WSL 2, and OpenCode's own docs recommend WSL for file-system performance and tool compatibility ([Claude Code setup](https://code.claude.com/docs/en/setup), [OpenCode WSL](https://opencode.ai/docs/windows-wsl)). Keeping both tools on the same side avoids path translation between Windows and Linux, so install WSL2 Ubuntu, keep repos in the Linux filesystem (for example `~/code`, not `/mnt/c`), and install both there. On the MacBook the same commands run natively.

```bash
# WSL2 Ubuntu or macOS
curl -fsSL https://claude.ai/install.sh | bash     # Claude Code (macOS alt: brew install --cask claude-code)
curl -fsSL https://opencode.ai/install | bash      # OpenCode
claude --version && claude doctor
```

**Accounts and keys.** Sign Claude Code in with a Claude subscription (Pro or higher is required; the notes found no source stating which tiers include Opus 5.5 or at what limits). Create prepaid API balances at Xiaomi and DeepSeek. Direct keys are the cheapest route for one developer; OpenRouter adds a single bill at a 5.5% fee on credit purchases ([OpenRouter](https://openrouter.ai/blog/insights/openrouter-vs-litellm/)). Export the worker keys from `~/.bashrc` or `~/.zshrc`. Two rules protect the overseer: never place third-party gateway variables in `~/.claude/settings.json`, because settings-file values override the shell and an active `ANTHROPIC_AUTH_TOKEN` displaces the subscription login; and never set `ANTHROPIC_BASE_URL` alone to a third-party host, because the subscription credential stays active and is routed through that URL ([gateway connection docs](https://code.claude.com/docs/en/llm-gateway-connect)). Run `/status` to confirm which credential a session uses.

**Overseer effort.** Start with `claude --effort xhigh`, or set `"effortLevel": "xhigh"` in settings ([model config](https://code.claude.com/docs/en/model-config)). Anthropic describes `xhigh` as suited to long agentic coding runs with token budgets in the millions, so drop to `medium` or `high` for routine dispatching if limits bite ([effort docs](https://platform.claude.com/docs/build-with-claude/effort)).

**Worker providers.** Xiaomi's OpenAI-compatible base URL is `https://api.xiaomimimo.com/v1` and DeepSeek's is `https://api.deepseek.com` ([Xiaomi docs](https://mimo.mi.com/static/docs/quick-start/summary/first-api-call.md), [Morph](https://www.morphllm.com/deepseek-api)). The sketch below follows OpenCode's current documented key names but is **untested**; OpenCode's docs exist in v1 and v2 forms with different key names, and DeepSeek may already be a built-in provider reachable through `/connect`.

```jsonc
// ~/.config/opencode/opencode.jsonc — illustrative, verify against current docs
{
  "providers": {
    "xiaomi": {
      "name": "Xiaomi MiMo", "env": ["XIAOMI_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "https://api.xiaomimimo.com/v1" },
      "models": { "mimo-v2.6-pro": { "name": "MiMo V2.6 Pro" } }
    },
    "deepseek": {
      "name": "DeepSeek", "env": ["DEEPSEEK_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "https://api.deepseek.com" },
      "models": { "deepseek-flash": { "name": "DeepSeek V4.1 Flash" } }
    }
  }
}
```

Smoke-test each worker alone (`opencode run -m xiaomi/mimo-v2.6-pro "..."`) on a multi-turn tool-using task before wiring it to Opus. Both models return a `reasoning_content` field, Xiaomi recommends passing it back on every turn, and an earlier DeepSeek model failed on turn two in OpenCode when that field was stripped ([Xiaomi docs](https://mimo.mi.com/static/docs/quick-start/summary/first-api-call.md), [AkitaOnRails](https://akitaonrails.com/en/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/)).

**Privacy and the local tier.** DeepSeek's policy stores data in China for as long as the account exists and lists training as a purpose; Xiaomi's platform policy promises no training on text without consent, but a tracker reading its product-family policy reports the opposite default ([Developers Digest](https://www.developersdigest.tech/models/data-retention/deepseek), [Xiaomi privacy policy](https://privacy.mi.com/XiaomiMiMoPlatform/en_GB/), [Standard Compute](https://standardcompute.com/providers/xiaomi)). Claude Code on a Pro or Max account trains on your code only while the model-improvement setting is on, so turn it off ([Claude Code data usage](https://code.claude.com/docs/en/data-usage)). Hobby code is low-risk; keep secrets, employer or client code and third-party personal data off the Chinese endpoints. That is the real job for the RTX 3090 Ti: Qwen3.8-27B at Q4_K_M (about 15.3 GiB) fits 24 GB with a large context, but cold prefill of a 30K context can take minutes and tool calling is fragile ([Redreamality](https://redreamality.com/blog/local-qwen3-8-replace-claude-code-vram-quant-harness-2026/)). With hosted workers this cheap, a local tier is a privacy and offline option, not a saving, so add it last, if at all. No source covered local models on the MacBook.

## The daily loop is spec, worktree, gates, then Opus review

The best-documented loop starts in the overseer session. Opus writes a spec and splits it into task files, each with a description, specific acceptance criteria, explicit non-goals and the commands that verify it; one practitioner's rule is "the card is the spec" ([karun.me](https://dev.to/javatarz/multi-agent-development-workflows-with-claude-code-n23)). Briefs must be self-contained, because a delegated worker sees none of the overseer's conversation. Anthropic's minimum is an objective, an output format, tool guidance and clear task boundaries ([Simon Willison quoting Anthropic](https://simonwillison.net/2025/Jun/14/multi-agent-research-system/)).

Triage follows how well-specified and self-contained a task is, not its line count. Practitioners report cheap models coping when the goal is well defined and the code well separated, and keep work involving timing, parallelism, state machines or external dependencies on the strong model ([Codeminer42](https://blog.codeminer42.com/?p=13219), [Kilo](https://blog.kilo.ai/p/we-gave-claude-opus-47-and-kimi-k26), [Hacker News](https://news.ycombinator.com/item?id=49875484)). A workable rubric from that evidence: mechanical or single-file tasks with an existing test go to DeepSeek; multi-file but fully specified tasks with acceptance tests go to MiMo; anything where the "how" is still open stays with Opus.

Dispatch has to be explicit. Given free choice, strong models made **zero delegations in all seven variants** of one benchmark, even with "use proactively" wording ([AkitaOnRails](https://akitaonrails.com/en/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/)). Put the rule in `CLAUDE.md`: implementation tasks are dispatched, never done inline. A dispatch then looks like this (illustrative):

```bash
git worktree add ../wt-042 -b work/042-export-csv
cd ../wt-042 && opencode run -m xiaomi/mimo-v2.6-pro \
  "Implement tasks/042.md exactly. Run the listed verification commands. Report changed files and results."
```

Before any model review, run deterministic gates in fail-fast order: formatting, lint, type checks, tests, a clean build ([karun.me](https://dev.to/javatarz/multi-agent-development-workflows-with-claude-code-n23)). Then Opus reviews `git diff` against each acceptance criterion and runs the checks itself. It should never trust the worker's summary: in one test a cheap model passed all 20 of its own tests yet diverged from the spec in six places, and its completion report claimed features the code lacked ([Kilo](https://blog.kilo.ai/p/we-gave-claude-opus-47-and-kimi-k26)). Approval merges the branch; rejection sends written feedback to a fresh worker run. Cap rework at one or two rounds, then move the task up a tier or re-scope it. That limit is a judgement call, not a measured figure, but unbounded loops are a documented way to erase the savings ([Hacker News](https://news.ycombinator.com/item?id=49875484)). Merge between dependent tasks so later work does not start from stale code.

## Token bills fall about 60 percent while supervision time rises

The case for the pattern is real but narrower than the comment implies. In a Rails benchmark, solo Opus scored 97/100 in 18 minutes for about $4; Opus delegating to Kimi scored 95 in 25 minutes for $2–3, and roughly 14 Opus dispatches added about $11 of planner cost that the executor logs did not show. The author concluded mixing is not worth it for continuous, cohesive coding work ([AkitaOnRails](https://akitaonrails.com/en/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/)). A second single-run comparison put a cheap model following an Opus plan at **41% of Opus's cost but about 3.5x the active time**, with around 18 corrective check-ins against zero. Its diagnosis: a plan closes the "what" gap and leaves the "how" gap open ([Codeminer42](https://blog.codeminer42.com/?p=13219)). Hacker News reports run both ways. One user automates Opus-plan, DeepSeek-implement, Opus-review loops for about $1; another found the same pattern "produces worse code with higher spend" ([Hacker News](https://news.ycombinator.com/item?id=49875484)).

The positive evidence comes from tighter designs. Anthropic reports Sonnet with an Opus advisor gained 2.7 points on SWE-bench Multilingual at 11.9% lower cost, though that is vendor-reported and Claude-only ([Anthropic](https://claude.com/blog/the-advisor-strategy)). Orchestration also helps weak executors more than strong ones: one model jumped from 46 to 93 under an Opus planner while a stronger one moved from 87 to 97 ([AkitaOnRails](https://akitaonrails.com/en/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/)).

The split pays under three conditions: you pay per token or regularly hit subscription limits, tasks are well bounded, and runs proceed unattended so wall-clock time is cheap. Under a flat subscription with headroom, extra Opus calls cost nothing at the margin, which removes most of the economic argument ([AkitaOnRails](https://akitaonrails.com/en/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/)). All of these measurements predate Opus 5.5, MiMo-V2.6-Pro and DeepSeek 1017, so the direction transfers and the magnitudes do not. Other standing caveats: Anthropic alleges Xiaomi routed MiMo users' sessions to Claude to generate training data, which Xiaomi had not answered as of 2 October ([The Batch](https://www.deeplearning.ai/the-batch/an-unexpected-open-weights-leader)); subscription rules for third-party harnesses and headless use changed several times in 2026 ([The New Stack](https://thenewstack.io/anthropic-claude-harness-restrictions/)); and a compromised LiteLLM release in March 2026 stole environment variables, a reminder that any proxy holding every provider key is a prime target ([Datadog Security Labs](https://securitylabs.datadoghq.com/articles/litellm-compromised-pypi-teampcp-supply-chain-campaign/)).

## Conclusion

The comment describes a cost hierarchy, but the research points to a different organising principle: **independence of verification**. Cheap models fail by quietly diverging from the spec while reporting success, so the value of the overseer lies less in its planning than in a review that reads the diff, runs the build and trusts nothing the worker says. Build that gate first and the choice of worker becomes a cheap, swappable decision. That matters because the MiMo-over-DeepSeek ordering already looks dated after the 17 October snapshot.

Run the setup as a two-week experiment. For each task, log the tier, model, cost including planner and reviewer tokens, wall-clock time, rework rounds and whether Opus ended up doing the work itself; then compare against Opus working solo on similar tasks. If the subscription never hits its limits, the honest result may be that solo Opus at `high` is the better workflow, with the cheap tier reserved for unattended batches and for days when the quota runs out.

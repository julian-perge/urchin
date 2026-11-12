# /// script
# requires-python = ">=3.13"
# ///
"""Measure how urchin sessions touch the original ActionScript.

A Bash call that runs `uv run as_lookup` counts as an AS call of the kind
"as_lookup". Give a path as the one argument to also write the description and
the command of each Bash call that names the export, one call to a line.
"""
import glob
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOTS = glob.glob("/Users/sweetjp/.claude/projects/-Users-sweetjp-code-urchin*") + glob.glob(
    "/Users/sweetjp/.claude/projects/-Users-sweetjp-Documents-godot-urchin*"
)
AS_RE = re.compile(r"action_script|\.as\b")
LOOKUP_RE = re.compile(r"uv run as_lookup\b")
AS_FILE_RE = re.compile(r"(frame_\d+/[\w.]+\.as|DefineSprite_[\w/.]+\.as|[\w/]+\.as)\b")
DOCS = ["DECODED_ALGORITHMS.md", "action_script_curated", "KNOWN_GAPS.md", "docs/agents/actionscript.md"]

files = [p for r in ROOTS for p in Path(r).rglob("*.jsonl")]
sessions_total = len(files)

read_files = Counter()  # AS file -> Read calls
read_sessions = defaultdict(set)  # AS file -> sessions
full_reads = Counter()
calls_by_kind = Counter()
result_chars_by_kind = Counter()
sess_calls = Counter()
sess_chars = Counter()
grep_patterns = Counter()
grep_pattern_sessions = defaultdict(set)
bash_descs = []
doc_sessions = defaultdict(set)
as_sessions = set()
sub_as = Counter()
first_ts = {}

for f in files:
    sid = str(f)
    is_sub = "subagents" in f.parts or f.name.startswith("agent-")
    pending = {}
    try:
        fh = f.open()
    except OSError:
        continue
    for line in fh:
        if "tool_use" not in line and "tool_result" not in line:
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = o.get("message") or {}
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for b in content:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                name = b.get("name")
                inp = b.get("input") or {}
                blob = json.dumps(inp)
                for d in DOCS:
                    if d in blob and name in ("Read", "Grep", "Bash"):
                        doc_sessions[d].add(sid)
                if name not in ("Read", "Grep", "Bash", "Glob"):
                    continue
                lookup = name == "Bash" and LOOKUP_RE.search(inp.get("command", ""))
                if not lookup and not AS_RE.search(blob):
                    continue
                if "action_script_curated" in blob and "action_script/" not in blob:
                    kind = "curated"
                elif name == "Read":
                    kind = "Read"
                    p = inp.get("file_path", "")
                    m = re.search(r"action_script/(.*)$", p)
                    key = m.group(1) if m else p
                    read_files[key] += 1
                    read_sessions[key].add(sid)
                    if not inp.get("offset") and not inp.get("limit"):
                        full_reads[key] += 1
                elif name == "Grep":
                    kind = "Grep"
                    pat = inp.get("pattern", "")
                    grep_patterns[pat] += 1
                    grep_pattern_sessions[pat].add(sid)
                elif name == "Bash":
                    cmd = inp.get("command", "")
                    if "action_script" in cmd:
                        kind = "Bash"
                        bash_descs.append((inp.get("description", ""), cmd[:300]))
                        for m in re.finditer(r"rg\s+(?:-\S+\s+)*(['\"])(.+?)\1", cmd):
                            grep_patterns[m.group(2)] += 1
                            grep_pattern_sessions[m.group(2)].add(sid)
                    elif lookup:
                        kind = "as_lookup"
                    else:
                        continue
                else:
                    kind = "Glob"
                calls_by_kind[kind] += 1
                sess_calls[sid] += 1
                as_sessions.add(sid)
                if is_sub:
                    sub_as[kind] += 1
                pending[b.get("id")] = kind
                first_ts.setdefault(sid, o.get("timestamp", ""))
            elif b.get("type") == "tool_result":
                k = pending.pop(b.get("tool_use_id"), None)
                if k is None:
                    continue
                c = b.get("content")
                n = len(c) if isinstance(c, str) else sum(len(x.get("text", "")) for x in c if isinstance(x, dict)) if isinstance(c, list) else 0
                result_chars_by_kind[k] += n
                sess_chars[sid] += n

out = sys.stdout
p = lambda *a: print(*a, file=out)
p(f"transcripts: {sessions_total}; touching AS: {len(as_sessions)}")
p("calls by kind:", dict(calls_by_kind))
p(f"AS calls: {sum(calls_by_kind.values())}, or {sum(calls_by_kind.values()) / len(as_sessions):.1f} for each transcript that touches the AS")
p("of which in subagent transcripts:", dict(sub_as))
p("result chars by kind:", {k: f"{v/1e6:.1f}M (~{v/4/1e6:.1f}M tok)" for k, v in result_chars_by_kind.items()})
p("doc sessions:", {d: len(s) for d, s in doc_sessions.items()})
both = as_sessions & doc_sessions["DECODED_ALGORITHMS.md"]
p(f"AS sessions that also opened DECODED_ALGORITHMS.md: {len(both)} of {len(as_sessions)}")
p("\nTop 40 AS files by sessions that Read them (sessions, reads, full reads):")
for k, s in sorted(read_sessions.items(), key=lambda kv: -len(kv[1]))[:40]:
    p(f"  {len(s):4d} {read_files[k]:5d} {full_reads[k]:5d}  {k}")
p(f"distinct AS files read: {len(read_files)}")
p("\nTop 60 search patterns over AS (sessions, uses):")
for pat, s in sorted(grep_pattern_sessions.items(), key=lambda kv: -len(kv[1]))[:60]:
    p(f"  {len(s):4d} {grep_patterns[pat]:5d}  {pat[:110]}")
p("\nTop 15 sessions by AS result chars:")
for sid, n in sess_chars.most_common(15):
    p(f"  {n/1e3:8.0f}k chars {sess_calls[sid]:4d} calls {first_ts.get(sid,'')[:10]}  {sid.split('projects/')[1][-70:]}")
if len(sys.argv) > 1:
    Path(sys.argv[1]).write_text("\n".join(f"{d}\t{c}" for d, c in bash_descs))

# /// script
# requires-python = ">=3.13"
# dependencies = ["tree-sitter>=0.25,<0.26", "tree-sitter-javascript>=0.23,<0.26"]
# ///
"""Second pass: rewrite the on()/onClipEvent() header to a function header, skip the mx library."""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import tree_sitter_javascript as tsjs
from tree_sitter import Language, Parser

root = Path(sys.argv[1])
parser = Parser(Language(tsjs.language()))
HANDLER = re.compile(rb"^(\s*)(on|onClipEvent)\s*\(([^)]*)\)\s*\{", re.M)
sys.setrecursionlimit(100000)

files = [f for f in sorted(root.rglob("*.as")) if "__Packages" not in f.parts and f.parent != root]
err_files, err_lines, lines = [], 0, 0
funcs = {}
calls = defaultdict(list)  # callee -> [(file, line)]
writes, reads = defaultdict(set), defaultdict(set)  # _root.X -> files


def callee_name(fn):
    if fn.type == "identifier":
        return fn.text.decode()
    if fn.type == "member_expression":
        obj, prop = fn.child_by_field_name("object"), fn.child_by_field_name("property")
        if obj.text in (b"_root", b"_parent", b"this", b"_global"):
            return prop.text.decode()
    return None


def walk(n, rel):
    global err_lines
    if n.type == "ERROR" or n.is_missing:
        err_lines += n.end_point[0] - n.start_point[0] + 1
    if n.type == "function_declaration":
        nm = n.child_by_field_name("name").text.decode()
        if nm != "__handler":
            funcs.setdefault(nm, []).append((rel, n.start_point[0] + 1, n.end_point[0] + 1))
    elif n.type == "call_expression":
        nm = callee_name(n.child_by_field_name("function"))
        if nm:
            calls[nm].append((rel, n.start_point[0] + 1))
    elif n.type == "member_expression" and n.child_by_field_name("object").text == b"_root":
        prop = n.child_by_field_name("property").text.decode()
        par = n.parent
        if par.type in ("assignment_expression", "augmented_assignment_expression") and par.child_by_field_name("left") == n:
            writes[prop].add(rel)
        else:
            reads[prop].add(rel)
    for c in n.children:
        walk(c, rel)


for f in files:
    src = HANDLER.sub(lambda m: m.group(1) + b"function __handler(){", f.read_bytes())
    lines += src.count(b"\n") + 1
    tree = parser.parse(src)
    rel = str(f.relative_to(root))
    b = err_lines
    walk(tree.root_node, rel)
    if tree.root_node.has_error:
        err_files.append((err_lines - b, rel))

print(f"game files {len(files)}, lines {lines}, files with parse errors {len(err_files)}, error lines {err_lines}")
for n, rel in sorted(err_files, reverse=True)[:8]:
    print(f"  {n:4d}  {rel}")
print(f"named functions: {sum(len(v) for v in funcs.values())} ({len(funcs)} distinct)")
print(f"call sites resolved to a named function: {sum(len(v) for k, v in calls.items() if k in funcs)}")
print(f"distinct _root globals: written {len(writes)}, read {len(reads)}")
kinds = Counter("frame script" if "DoAction" in r else "clip handler" if "CLIPACTION" in r else "button handler" if "BUTTONCOND" in r else "other" for r in map(lambda f: str(f.relative_to(root)), files))
print("file kinds:", dict(kinds))
for name in ("executeMove", "lifeBarUpdate", "krinAddNewUnit", "checkBuffsOnUnit"):
    for rel, s, e in funcs.get(name, []):
        cs = calls[name]
        print(f"  {name}: {rel}:{s}-{e}  call sites {len(cs)} in {len({c[0] for c in cs})} files")
print("  _root.perKSuccess written in:", sorted(writes["perKSuccess"]), "read in:", len(reads["perKSuccess"]), "files")

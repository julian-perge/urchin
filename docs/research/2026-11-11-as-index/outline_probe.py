# /// script
# requires-python = ">=3.13"
# dependencies = ["tree-sitter>=0.25,<0.26", "tree-sitter-javascript>=0.23,<0.26"]
# ///
"""Print the block outline of one script at depth 1 and 2, to see whether an outline is useful."""
import re
import sys
from pathlib import Path

import tree_sitter_javascript as tsjs
from tree_sitter import Language, Parser

HANDLER = re.compile(rb"^(\s*)(on|onClipEvent)\s*\(([^)]*)\)\s*\{", re.M)
src = HANDLER.sub(lambda m: m.group(1) + b"function __handler(){", Path(sys.argv[1]).read_bytes())
root = Parser(Language(tsjs.language())).parse(src).root_node
lines = src.split(b"\n")


def body(n):
    if n.type == "function_declaration":
        return n.child_by_field_name("body")
    if n.type == "if_statement":
        return n.child_by_field_name("consequence")
    return None


def show(n, depth, maxd):
    for c in n.named_children:
        span = c.end_point[0] - c.start_point[0] + 1
        if span >= 15:
            print(f"{'  '*depth}{c.start_point[0]+1}-{c.end_point[0]+1}  {lines[c.start_point[0]].decode().strip()[:80]}")
            b = body(c)
            if b is not None and depth < maxd:
                show(b, depth + 1, maxd)


show(root, 0, int(sys.argv[2]))

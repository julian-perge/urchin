# label_xref.py
# Writes dev/converted_json/label_xref.json: every frame label in the web SWF,
# with the sprite and frame it lives on and every goto in the ActionScript
# that can select it. It reads the SWF through swf_index.py and the goto calls
# from ffdec's script export in dev/source_files/action_script/, and calls
# neither ffdec nor the XML dump.
#
# The export path of a script names the code's owner:
#   frame_N/...                     root frame N
#   DefineSprite_S[_Name]/frame_N/  frame N of sprite S
#   .../PlaceObjectK_C[_name]_D/    a clip action on character C at depth D
#   DefineButton2_B/...             a condition action of button B
#
# A goto's receiver is resolved the way AVM1 scopes the code it sits in. A
# frame script acts on its own timeline. A clip action (onClipEvent) acts on
# the clip it is attached to, so a bare gotoAndStop or a "this." in one moves
# the placed character, not the timeline that places it. A button is not a
# timeline, so a button action acts on every timeline that places the button.
# From there a dotted name walks the instance names in the SWF's placements,
# "_root" starts at the root and "_parent" climbs to every timeline that
# places the current one. A computed name like this["st" + i] matches every
# instance name with that prefix and gets flagged. A name with more than one
# character behind it yields every one of them, also flagged. Code inside a
# function is scoped by the script that defines it, which is wrong when the
# function runs on another object: krinMelee in frame_42/DoAction_4.as is a
# root frame script, so its this.inner resolves to the root's own "inner".
# Those gotos carry a flag saying so.
#
# AVM1 matches frame labels case-insensitively ("In AVM1, frame labels are
# case insensitive (ASCII).", Ruffle core/src/display_object/movie_clip.rs),
# so every label comparison here folds case. Instance names are not folded,
# since SWF 7 and later make ActionScript identifiers case-sensitive.
#
# Run: uv run extract_label_xref
from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

from urchin_dev import ACTION_SCRIPT, CONVERTED_JSON, WEB_SWF
from urchin_dev.swf.swf_index import SwfIndex, read_swf

OUT = CONVERTED_JSON / "label_xref.json"
BATTLES_JSON = CONVERTED_JSON / "battles.json"
ROOT = 0


@dataclass(frozen=True)
class ValueSet:
    """A dynamic goto target whose possible values come from game data.
    `expression` matches the decompiled argument exactly, or as a prefix when
    it ends in "[". `sprite` is the timeline the goto lands on."""

    name: str
    expression: str
    sprite: int
    source: str


# The one hand-written table in this module. Every value each entry can take
# is checked against the labels of its sprite, so a wrong entry shows up as
# misses in the output and in dev/tests/test_label_xref.py.
VALUE_SETS = (
    ValueSet(
        "zone_background",
        "_root.Krin.ZoneBG",
        3435,
        "dev/converted_json/battles.json zone_background",
    ),
    ValueSet(
        "sky_background",
        "_root.Krin.SkyBG",
        3454,
        "dev/converted_json/battles.json sky_background",
    ),
    ValueSet(
        "item_name",
        "_root.KrinLang.ENGLISH.ITEMNAME[",
        2064,
        "KrinLang.ENGLISH.ITEMNAME in frame_1/DoAction.as",
    ),
    ValueSet(
        "zone_name",
        "_root.Krin.zoneName[_root.Krin.sectionIn]",
        3287,
        "Krin.zoneName in frame_41/DoAction_2.as",
    ),
)

_SPRITE_DIR = re.compile(r"DefineSprite_(\d+)(?:_.*)?$")
_BUTTON_DIR = re.compile(r"DefineButton2?_(\d+)$")
_FRAME_DIR = re.compile(r"frame_(\d+)$")
_PLACE_DIR = re.compile(r"PlaceObject\d?_(\d+)_(?:.*_)?(\d+)$")
_GOTO = re.compile(r"\bgotoAnd(Stop|Play)\(")
_IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
_ITEM_NAME = re.compile(
    r'^KrinLang\.ENGLISH\.ITEMNAME\[(\d+)\] = "((?:[^"\\]|\\.)*)";$', re.MULTILINE
)
_ZONE_NAMES = re.compile(r"^Krin\.zoneName = \[(.*)\];$", re.MULTILINE)
_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
_HIDE = re.compile(r"^(\s*)(?:(.+?)\.)?_visible\s*=\s*false\s*;", re.MULTILINE)


@dataclass(frozen=True)
class Script:
    """Where one exported script runs. kind is "frame", "clip", "button" or
    "other" (class definitions and init code, which name no timeline)."""

    path: str
    kind: str
    timeline: int | None
    frame: int | None
    placed: int | None = None
    depth: int | None = None
    button: int | None = None


def parse_script_path(rel: Path) -> Script:
    parts = list(rel.parts[:-1])
    path = rel.as_posix()
    timeline = ROOT
    if parts and (m := _BUTTON_DIR.match(parts[0])):
        return Script(path, "button", None, None, button=int(m.group(1)))
    if parts and (m := _SPRITE_DIR.match(parts[0])):
        timeline = int(m.group(1))
        parts = parts[1:]
    if not parts or not (m := _FRAME_DIR.match(parts[0])):
        return Script(path, "other", None, None)
    frame = int(m.group(1))
    if len(parts) > 1 and (m := _PLACE_DIR.match(parts[1])):
        return Script(path, "clip", timeline, frame, int(m.group(1)), int(m.group(2)))
    return Script(path, "frame", timeline, frame)


def unescape(text: str) -> str:
    """Undo ffdec's escapes in a decompiled string literal, which writes
    Guard's Leggings as Guard\\'s Leggings."""
    escapes = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f"}
    return re.sub(r"\\(.)", lambda m: escapes.get(m.group(1), m.group(1)), text)


def _escaped(text: str, i: int) -> bool:
    """True when text[i] follows an odd run of backslashes."""
    run = 0
    while i - run - 1 >= 0 and text[i - run - 1] == "\\":
        run += 1
    return run % 2 == 1


def _function_spans(text: str) -> list[tuple[int, int]]:
    """-> (start, end) of every function body in a decompiled script."""
    spans = []
    for m in re.finditer(r"\bfunction\b", text):
        i = text.find("{", m.end())
        if i == -1:
            continue
        start, depth = i, 0
        while i < len(text):
            ch = text[i]
            if ch == '"':
                i += 1
                while text[i] != '"':
                    i += 2 if text[i] == "\\" else 1
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    spans.append((start, i))
                    break
            i += 1
    return spans


def _skip_back(text: str, i: int, close: str) -> int:
    """-> index of the bracket opening the one closing at text[i]."""
    opener = {"]": "[", ")": "("}[close]
    depth = 0
    while i >= 0:
        ch = text[i]
        if ch == '"':
            i -= 1
            while i >= 0 and not (text[i] == '"' and not _escaped(text, i)):
                i -= 1
        elif ch in "])":
            depth += 1
        elif ch in "[(":
            depth -= 1
            if depth == 0:
                if ch != opener:
                    raise ValueError(f"unbalanced {close!r} at {i}")
                return i
        i -= 1
    raise ValueError(f"no opener for {close!r}")


def _receiver_before(text: str, dot: int) -> str:
    """-> the receiver expression ending just before text[dot] == "."."""
    i = dot - 1
    while i >= 0:
        ch = text[i]
        if ch in "])":
            i = _skip_back(text, i, ch) - 1
        elif ch.isalnum() or ch in "_$.":
            i -= 1
        else:
            break
    return text[i + 1 : dot]


def _argument_after(text: str, open_paren: int) -> str:
    depth, i = 0, open_paren
    while i < len(text):
        ch = text[i]
        if ch == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[open_paren + 1 : i].strip()
        i += 1
    raise ValueError(f"unbalanced call at {open_paren}")


@dataclass(frozen=True)
class GotoCall:
    line: int
    method: str
    receiver: str | None
    argument: str
    in_function: bool = False


def goto_calls(text: str) -> list[GotoCall]:
    calls = []
    functions = _function_spans(text)
    for m in _GOTO.finditer(text):
        start = m.start()
        receiver = None
        if start > 0 and text[start - 1] == ".":
            receiver = _receiver_before(text, start - 1)
        calls.append(
            GotoCall(
                text.count("\n", 0, start) + 1,
                "gotoAnd" + m.group(1),
                receiver,
                _argument_after(text, m.end() - 1),
                any(a < start < b for a, b in functions),
            )
        )
    return calls


def receiver_segments(receiver: str) -> list[tuple[str, str]]:
    """Split `a.b["c" + i].d` into [("name", "a"), ("name", "b"),
    ("index", '"c" + i'), ("name", "d")]."""
    segments, i = [], 0
    while i < len(receiver):
        if receiver[i] == ".":
            i += 1
            continue
        if receiver[i] == "[":
            depth, j = 0, i
            while True:
                if receiver[j] == "[":
                    depth += 1
                elif receiver[j] == "]":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            segments.append(("index", receiver[i + 1 : j].strip()))
            i = j + 1
            continue
        m = _IDENT.match(receiver, i)
        if m is None:
            raise ValueError(f"cannot split receiver {receiver!r}")
        segments.append(("name", m.group(0)))
        i = m.end()
    return segments


class Resolver:
    def __init__(self, index: SwfIndex):
        self.names: dict[int, dict[str, set[int]]] = defaultdict(
            lambda: defaultdict(set)
        )
        self.placers: dict[int, set[int]] = defaultdict(set)
        for p in index.placements:
            if p.character_id is None:
                continue
            self.placers[p.character_id].add(p.owner)
            if p.name is not None:
                self.names[p.owner][p.name].add(p.character_id)
        # A name placed by a move-only PlaceObject keeps the character
        # already at that depth, so resolve those through the depth.
        at_depth: dict[tuple[int, int], int] = {}
        for p in index.placements:
            if p.character_id is not None:
                at_depth[(p.owner, p.depth)] = p.character_id
            elif p.name is not None and (p.owner, p.depth) in at_depth:
                self.names[p.owner][p.name].add(at_depth[(p.owner, p.depth)])
        self.labels: dict[int, dict[str, tuple[str, int]]] = defaultdict(dict)
        self.label_at: dict[int, dict[int, str]] = defaultdict(dict)
        for label in index.labels:
            self.labels[label.owner].setdefault(
                label.name.lower(), (label.name, label.frame)
            )
            self.label_at[label.owner].setdefault(label.frame, label.name)

    def scope(self, script: Script) -> set[int]:
        if script.kind == "frame":
            return {script.timeline}
        if script.kind == "clip":
            return {script.placed}
        if script.kind == "button":
            return set(self.placers.get(script.button, ()))
        return set()

    def walk(self, script: Script, receiver: str | None):
        """-> (timelines, flags) the receiver can name, from the script's
        own scope. An empty set means it could not be resolved."""
        current = self.scope(script)
        flags: list[str] = []
        if receiver is None:
            return current, flags
        try:
            segments = receiver_segments(receiver)
        except ValueError:
            flags.append("receiver not parsed")
            return set(), flags
        for n, (kind, value) in enumerate(segments):
            if kind == "name" and value in ("_root", "_level0") and n == 0:
                current = {ROOT}
            elif kind == "name" and value == "this" and n == 0:
                pass
            elif kind == "name" and value == "_parent":
                current = set().union(*(self.placers.get(t, set()) for t in current))
            elif kind == "name":
                current = self._named(current, value, flags)
            else:
                current = self._indexed(current, value, flags)
            if not current:
                return set(), flags
        return current, flags

    def _named(self, timelines: set[int], name: str, flags: list[str]) -> set[int]:
        found = set().union(*(self.names[t].get(name, set()) for t in timelines))
        if len(found) > 1:
            flags.append(f"{name} names {len(found)} characters")
        return found

    def _indexed(self, timelines: set[int], expr: str, flags: list[str]) -> set[int]:
        literal = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', expr)
        if literal:
            return self._named(timelines, unescape(literal.group(1)), flags)
        prefix = re.match(r'"((?:[^"\\]|\\.)*)"\s*\+', expr)
        if prefix is None:
            flags.append(f"computed name [{expr}]")
            return set()
        start = unescape(prefix.group(1))
        found = {
            cid
            for t in timelines
            for name, cids in self.names[t].items()
            if name.startswith(start)
            for cid in cids
        }
        flags.append(f"prefix match [{expr}]")
        return found

    def find_label(self, sprite: int, value: str) -> tuple[str, int] | None:
        return self.labels.get(sprite, {}).get(value.lower())


def load_value_sets(action_script: Path, battles_json: Path) -> dict[str, list]:
    """-> {value set name: [(key, value), ...]}. The key is what identifies a
    value in its source: a battle id, an item id or a zone index."""
    battles = json.loads(battles_json.read_text())["battles"]
    items_text = (action_script / "frame_1" / "DoAction.as").read_text()
    zones_text = (action_script / "frame_41" / "DoAction_2.as").read_text()
    zones = _ZONE_NAMES.search(zones_text)
    if zones is None:
        raise ValueError("Krin.zoneName not found in frame_41/DoAction_2.as")
    return {
        "zone_background": [(b["id"], b["zone_background"]) for b in battles],
        "sky_background": [(b["id"], b["sky_background"]) for b in battles],
        "item_name": [
            (int(m.group(1)), unescape(m.group(2)))
            for m in _ITEM_NAME.finditer(items_text)
        ],
        "zone_name": [
            (i, unescape(s)) for i, s in enumerate(_STRING.findall(zones.group(1)))
        ],
    }


def value_set_for(argument: str) -> ValueSet | None:
    for vs in VALUE_SETS:
        if vs.expression.endswith("["):
            if argument.startswith(vs.expression):
                return vs
        elif argument == vs.expression:
            return vs
    return None


def hidden_on_load(action_script: Path) -> list[dict]:
    """Load handlers that set a _visible to false, with each receiver. This
    is a list to review rather than strip, since some hide only under a
    condition: 3312 hides itself only when _root.Krin.BattlePick == 2."""
    found = []
    for path in sorted(action_script.rglob("*onClipEvent(load*).as")):
        rel = path.relative_to(action_script)
        script = parse_script_path(rel)
        receivers = []
        for m in _HIDE.finditer(path.read_text()):
            target = m.group(2)
            receivers.append("self" if target in (None, "this") else target)
        if receivers:
            found.append(
                {
                    "file": rel.as_posix(),
                    "owner": script.timeline,
                    "frame": script.frame,
                    "placed": script.placed,
                    "depth": script.depth,
                    "hides_self": "self" in receivers,
                    "receivers": sorted(set(receivers)),
                }
            )
    return found


def resolve_goto(resolver, values, script, call) -> dict:
    """-> one goto's record. status is "label" when it selects one or more
    (sprite, label) pairs, "frame" when it names a frame number on resolved
    timelines, and "unresolved" with a reason otherwise."""
    record = {
        "method": call.method,
        "receiver": call.receiver,
        "argument": call.argument,
    }
    targets, flags = resolver.walk(script, call.receiver)
    if call.in_function:
        flags.append("inside a function, which may run on another object")
    string = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', call.argument)
    if string:
        wanted = unescape(string.group(1))
        hits = sorted(
            (t, hit[0])
            for t in targets
            if (hit := resolver.find_label(t, wanted)) is not None
        )
        if hits:
            record |= {"status": "label", "via": "literal", "selects": hits}
        elif targets:
            reason = f"no label {wanted!r} on {sorted(targets)}"
            record |= {"status": "unresolved", "reason": reason}
        else:
            record |= {"status": "unresolved", "reason": "receiver not resolved"}
    elif re.fullmatch(r"\d+", call.argument):
        frame = int(call.argument)
        if targets:
            record |= {
                "status": "frame",
                "frame": frame,
                "selects": [
                    (t, resolver.label_at[t].get(frame)) for t in sorted(targets)
                ],
            }
        else:
            record |= {"status": "unresolved", "reason": "receiver not resolved"}
    elif (vs := value_set_for(call.argument)) is not None:
        if targets and vs.sprite not in targets:
            flags.append(f"receiver resolves to {sorted(targets)}, not {vs.sprite}")
        hits = sorted(
            {
                (vs.sprite, hit[0])
                for _key, value in values[vs.name]
                if (hit := resolver.find_label(vs.sprite, value)) is not None
            }
        )
        if hits:
            record |= {"status": "label", "via": vs.name, "selects": hits}
        else:
            reason = f"no {vs.name} value is a label of {vs.sprite}"
            record |= {"status": "unresolved", "reason": reason}
    else:
        record |= {"status": "unresolved", "reason": "dynamic target"}
    if flags:
        record["flags"] = flags
    return record


def build(index: SwfIndex, action_script: Path, battles_json: Path) -> dict:
    resolver = Resolver(index)
    values = load_value_sets(action_script, battles_json)
    gotos = []
    for path in sorted(action_script.rglob("*.as")):
        rel = path.relative_to(action_script)
        script = parse_script_path(rel)
        for call in goto_calls(path.read_text()):
            record = resolve_goto(resolver, values, script, call)
            gotos.append(
                {"id": len(gotos), "file": rel.as_posix(), "line": call.line} | record
            )

    selected = defaultdict(list)
    for goto in gotos:
        if goto["status"] in ("label", "frame"):
            for sprite, label in goto["selects"]:
                if label is not None:
                    selected[(sprite, label)].append(goto["id"])
    exports = defaultdict(list)
    for name, cid in index.exports.items():
        exports[cid].append(name)
    labels = [
        {
            "sprite": label.owner,
            "export": sorted(exports.get(label.owner, [])),
            "label": label.name,
            "frame": label.frame,
            "gotos": selected.get((label.owner, label.name), []),
        }
        for label in sorted(index.labels, key=lambda lb: (lb.owner, lb.frame, lb.name))
    ]

    value_sets = {}
    for vs in VALUE_SETS:
        entries = values[vs.name]
        misses = sorted(
            {(k, v) for k, v in entries if resolver.find_label(vs.sprite, v) is None}
        )
        value_sets[vs.name] = {
            "expression": vs.expression,
            "sprite": vs.sprite,
            "source": vs.source,
            "values": len({v.lower() for _k, v in entries}),
            "misses": [{"key": k, "value": v} for k, v in misses],
        }

    def argument_kind(goto):
        if goto["argument"].startswith('"'):
            return "literal"
        return "numeric" if goto["argument"].isdigit() else "dynamic"

    return {
        "swf": WEB_SWF.name,
        "counts": {
            "sprites": len(index.sprite_frames),
            "labels": len(index.labels),
            "clip_depth_placements": sum(
                p.clip_depth is not None for p in index.placements
            ),
            "code_blocks": len(index.code),
            "gotos": len(gotos),
            "gotos_by_argument": dict(
                sorted(Counter(argument_kind(g) for g in gotos).items())
            ),
            "gotos_by_status": dict(
                sorted(Counter(g["status"] for g in gotos).items())
            ),
        },
        "labels": labels,
        "gotos": gotos,
        "value_sets": value_sets,
        "hidden_on_load": hidden_on_load(action_script),
    }


def dumps(xref: dict) -> str:
    """JSON with one label, goto or handler per line, so a regenerated file
    diffs by record."""
    lines = ["{"]
    for n, (key, value) in enumerate(xref.items()):
        comma = "," if n + 1 < len(xref) else ""
        if isinstance(value, list):
            rows = [" " + json.dumps(row) for row in value]
            body = ",\n ".join(rows)
            lines.append(f" {json.dumps(key)}: [\n {body}\n ]{comma}")
        else:
            lines.append(f" {json.dumps(key)}: {json.dumps(value)}{comma}")
    return "\n".join(lines) + "\n}\n"


def main():
    xref = build(read_swf(WEB_SWF), ACTION_SCRIPT, BATTLES_JSON)
    OUT.write_text(dumps(xref))
    print(json.dumps(xref["counts"]), file=sys.stderr)
    for name, vs in xref["value_sets"].items():
        misses = ", ".join(f"{m['value']} ({m['key']})" for m in vs["misses"])
        print(f"{name} on {vs['sprite']}: misses {misses or 'none'}", file=sys.stderr)
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()

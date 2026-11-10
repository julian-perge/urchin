# doc_paths.py
# The prek hook that fails a commit when a backticked path in the agent docs
# names nothing. The lessons in those docs keep their paths as evidence, and a
# commit that renames or deletes a file can leave one pointing at nothing, so
# the hook checks every doc on every commit rather than only the docs a commit
# touches.
#
# A path under ~/ or / has to exist on this machine. Any other path resolves
# when it is a run of whole components inside some path in the git index. That
# way a path written relative to a folder its lesson names, such as
# frame_41/DoAction_2.as inside dev/source_files/action_script/, and a bare file
# name such as render.py both resolve without the doc spelling out where they
# sit.
from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Collection, Iterator, Sequence
from pathlib import Path, PurePosixPath

from urchin_dev.checks import indexed_paths

FENCE = re.compile(r" {0,3}(```|~~~)")
CODE_SPAN = re.compile(
    r"(?<!`)(`+)(?!`)((?:(?!\n[ \t]*\n).)+?)(?<!`)\1(?!`)", re.DOTALL
)
CODE_CHARS = re.compile(r"[<>*{}()\[\]=\"'#@$|^?!,;:]")
SLASH_COMMAND = re.compile(r"/[\w-]+")


def code_spans(text: str) -> Iterator[tuple[int, str]]:
    """A code span can wrap across lines inside a paragraph, as the save preset
    command in docs/agents/godot.md does, so spans are matched over the whole
    text with its fenced blocks blanked out. Each one comes back with the line it starts on
    and its line breaks folded into spaces."""
    lines = text.split("\n")
    fenced = False
    for number, line in enumerate(lines):
        fence = FENCE.match(line)
        if fence:
            fenced = not fenced
        if fence or fenced:
            lines[number] = ""
    prose = "\n".join(lines)
    for span in CODE_SPAN.finditer(prose):
        yield prose.count("\n", 0, span.start()) + 1, " ".join(span.group(2).split())


def is_path(word: str, extensions: Collection[str]) -> bool:
    """A word reads as a path when it has a slash or ends in an extension some
    indexed file has, which keeps names such as `Krin.zoneName` out. Flags,
    placeholders, code, slash commands and bare extensions such as `.png.import`
    never read as paths, and of the URLs only Godot's `res://` does, because it
    points into the repo."""
    if "://" in word:
        scheme, _, rest = word.partition("://")
        return scheme == "res" and is_path(rest, extensions)
    if word.startswith("-") or CODE_CHARS.search(word) or SLASH_COMMAND.fullmatch(word):
        return False
    parts = word.rstrip("/").rsplit("/", 1)[-1].split(".")
    if "/" not in word and parts[0] == "" and set(parts[1:]) <= set(extensions):
        return False
    return "/" in word or (len(parts) > 1 and parts[-1] in extensions)


def on_disk(path: str) -> bool:
    return Path(path).expanduser().exists()


def path_words(span: str, extensions: Collection[str]) -> list[str]:
    """A span with spaces is usually a command, so each of its words is judged
    on its own, unless the whole span is a path under ~/ or / that exists spaces
    and all, such as the FFDec config under ~/Library/Application Support. A
    GDScript test id such as `a.gd::test_b` stands for its file."""
    if " " in span and span.startswith(("~/", "/")) and on_disk(span):
        return [span]
    words = (word.split("::", 1)[0] for word in span.split(" "))
    return [word for word in words if is_path(word, extensions)]


def resolves(word: str, slashed_paths: Collection[str]) -> bool:
    """Each indexed path arrives with a slash at both ends, so a run of whole
    components matches as a substring and `der.py` does not match `render.py`."""
    if word.startswith(("~/", "/")):
        return on_disk(word)
    slashed_word = "/" + word.removeprefix("res://").strip("/") + "/"
    return any(slashed_word in path for path in slashed_paths)


def broken_paths(
    text: str, index: Collection[str], not_a_path: Collection[str]
) -> list[tuple[int, str]]:
    extensions = {PurePosixPath(path).suffix[1:] for path in index} - {""}
    slashed_paths = ["/" + path + "/" for path in index]
    return [
        (line, word)
        for line, span in code_spans(text)
        for word in path_words(span, extensions)
        if word not in not_a_path and not resolves(word, slashed_paths)
    ]


def doc_files(docs: Sequence[str]) -> list[Path]:
    files = []
    for doc in map(Path, docs):
        files += sorted(doc.glob("*.md")) if doc.is_dir() else [doc]
    return files


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fail when a backticked path in Markdown names nothing."
    )
    parser.add_argument("docs", nargs="+", help="Markdown files, or folders of them")
    parser.add_argument(
        "--not-a-path",
        action="append",
        default=[],
        metavar="SPAN",
        help="a span that reads as a path but names something outside the repo",
    )
    args = parser.parse_args()
    index = indexed_paths()
    failures = []
    for doc in doc_files(args.docs):
        if not doc.is_file():
            failures.append(f"{doc} does not exist")
            continue
        failures += [
            f"{doc}:{line}: {word} does not exist"
            for line, word in broken_paths(doc.read_text(), index, args.not_a_path)
        ]
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        print(
            "Fix the path, or pass a span that only reads as a path to"
            " --not-a-path in prek.toml.",
            file=sys.stderr,
        )
    return 1 if failures else 0

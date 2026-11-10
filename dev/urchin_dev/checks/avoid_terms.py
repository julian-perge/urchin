# avoid_terms.py
# The prek hook that fails a commit when an added line in a staged Markdown
# file, or in a comment of a staged GDScript file, uses a term that one of
# GLOSSARY.md's _Avoid_ lines names. DECODED_ALGORITHMS.md once said "a hit for
# 0", which is under Shield block's _Avoid_ line, and only the reviewer caught
# it. The hook reads only the lines the commit adds, so text already in the
# repo never blocks a commit, and it skips GLOSSARY.md, which has to name the
# terms it warns against. Text in backticks, inline or in a fenced block, is
# skipped too, because it quotes a name from the code or the original, such as
# the original's "selector" clip, rather than naming a concept.
from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Collection, Iterable, Iterator
from pathlib import Path

from urchin_dev.checks.doc_paths import CODE_SPAN, FENCE
from urchin_dev.run import run

GLOSSARY = "GLOSSARY.md"
AVOID_LINE = re.compile(r"^_Avoid_:\s*(.*)$", re.MULTILINE)
HUNK = re.compile(r"^@@ -\S+ \+(\d+)(?:,\d+)? @@")


def avoid_terms(glossary: str) -> list[str]:
    """An _Avoid_ line lists its terms between commas. A term can carry an
    explanation after ", which", such as "Party roster, which is the save's
    list of companions", and the explanation is not a term."""
    terms = []
    for line in AVOID_LINE.findall(glossary):
        terms += [term.strip() for term in line.split(", which ", 1)[0].split(",")]
    return [term for term in terms if term]


def term_pattern(terms: Iterable[str]) -> re.Pattern[str]:
    """Longer terms come first, so "hit flash" wins over "hit" on the same
    words."""
    alternatives = [
        r"\s+".join(map(re.escape, term.split()))
        for term in sorted(set(terms), key=len, reverse=True)
    ]
    return re.compile(rf"(?<!\w)(?:{'|'.join(alternatives)})(?!\w)", re.IGNORECASE)


def gdscript_comment(line: str) -> str:
    """A `#` inside a string, such as a color "#ff0000", does not start a
    comment. A string that spans lines is not tracked, so its later lines read
    as code."""
    quote = ""
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
        elif quote and char == "\\":
            escaped = True
        elif quote:
            quote = "" if char == quote else quote
        elif char in "\"'":
            quote = char
        elif char == "#":
            return line[index:]
    return ""


def fenced_lines(text: str) -> set[int]:
    """The numbers of a Markdown file's lines that open, hold or close a
    fenced code block."""
    fenced = set()
    inside = False
    for number, line in enumerate(text.split("\n"), 1):
        fence = FENCE.match(line)
        if fence:
            inside = not inside
        if fence or inside:
            fenced.add(number)
    return fenced


def checked_text(path: str, line: str) -> str:
    text = gdscript_comment(line) if path.endswith(".gd") else line
    return CODE_SPAN.sub(" ", text)


def avoided_uses(
    path: str,
    added: Iterable[tuple[int, str]],
    terms: Collection[str],
    fenced: Collection[int] = (),
) -> list[tuple[int, str]]:
    """`fenced` holds the numbers of the lines in fenced code blocks, which
    are skipped."""
    if not terms or path == GLOSSARY:
        return []
    pattern = term_pattern(terms)
    return [
        (number, match.group(0))
        for number, line in added
        if number not in fenced
        for match in pattern.finditer(checked_text(path, line))
    ]


def added_lines(diff: str) -> Iterator[tuple[int, str]]:
    """Reads a `git diff --unified=0` of one file and yields each added line
    with its line number in the new file."""
    number = 0
    for line in diff.split("\n"):
        hunk = HUNK.match(line)
        if hunk:
            number = int(hunk.group(1))
        elif line.startswith("+") and not line.startswith("+++"):
            yield number, line[1:]
            number += 1


def staged_diff(path: str) -> str:
    return run(
        ["git", "diff", "--cached", "--unified=0", "--no-color", "--", path]
    ).stdout


def staged_fenced_lines(path: str) -> set[int]:
    """An added line can sit inside a fence the diff does not show, so the
    fences come from the whole staged file. GDScript has no fences."""
    if not path.endswith(".md"):
        return set()
    return fenced_lines(run(["git", "show", f":{path}"]).stdout)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fail when a staged line uses a term GLOSSARY.md says to avoid."
    )
    parser.add_argument("paths", nargs="*", help="staged .md and .gd files")
    parser.add_argument(
        "--allow",
        action="append",
        default=[],
        metavar="TERM",
        help="an _Avoid_ term the hook does not check",
    )
    args = parser.parse_args()
    allowed = {term.casefold() for term in args.allow}
    terms = [
        term
        for term in avoid_terms(Path(GLOSSARY).read_text())
        if term.casefold() not in allowed
    ]
    failures = [
        f"{path}:{number}: {term!r} is an _Avoid_ term in {GLOSSARY}"
        for path in args.paths
        for number, term in avoided_uses(
            path, added_lines(staged_diff(path)), terms, staged_fenced_lines(path)
        )
    ]
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        print(
            f"Use the term {GLOSSARY} defines instead, or pass a term too common"
            " to check to --allow in prek.toml.",
            file=sys.stderr,
        )
    return 1 if failures else 0

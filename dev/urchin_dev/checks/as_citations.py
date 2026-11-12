# as_citations.py
# The prek hook that fails a commit when a GDScript comment cites a place in
# the original ActionScript that does not exist. A citation fails when its path
# names no export file, when it is the end of more than one export file, or
# when it names a line past the end of the file. The line counts come from the
# checked-in index, so the check does not read the export.
#
# With file arguments it checks those files. With none it checks every tracked
# .gd file.
from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from urchin_dev.as_lookup import (
    Citation,
    load,
    read_citations,
    resolve,
    tracked_citations,
)


def line_counts(records: list[dict]) -> dict[str, int]:
    return {r["file"]: r["lines"] for r in records if r["kind"] == "script"}


def _written(citation: Citation) -> str:
    parts = [
        str(start) if start == end else f"{start}-{end}"
        for start, end in citation.lines
    ]
    return citation.path + (":" + ", ".join(parts) if parts else "")


def _reason(citation: Citation, lines: dict[str, int]) -> str | None:
    found = resolve(citation.path, lines)
    if not found:
        return "names no export file"
    if len(found) > 1:
        return f"is the end of {len(found)} export files: {', '.join(found)}"
    last = max((end for _, end in citation.lines), default=0)
    if last > lines[found[0]]:
        return f"names line {last}, and {found[0]} has {lines[found[0]]} lines"
    return None


def failures(citations: Sequence[Citation], lines: dict[str, int]) -> list[str]:
    """One message for each citation that fails. `lines` gives the line count
    of each export file."""
    return [
        f"{citation.gd}:{citation.line}: {_written(citation)} {reason}"
        for citation in citations
        if (reason := _reason(citation, lines))
    ]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Fail when a GDScript comment cites an ActionScript file or"
        " line that does not exist."
    )
    parser.add_argument("files", nargs="*", help=".gd files; none checks all of them")
    args = parser.parse_args(argv)
    if args.files:
        citations = [
            citation
            for file in args.files
            for citation in read_citations(Path(file).read_text(encoding="utf-8"), file)
        ]
    else:
        citations = tracked_citations()
    failed = failures(citations, line_counts(load()))
    for failure in failed:
        print(failure, file=sys.stderr)
    if failed:
        print(
            "Correct the path or the line. `uv run as_lookup <path>` lists the"
            " export files that a path can name.",
            file=sys.stderr,
        )
    return 1 if failed else 0

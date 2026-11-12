# merge_ticket.py
# Merges one ticket branch into the integration branch checked out in the
# current worktree, then pushes it. The implement-spec orchestrator once gave
# each merge to a subagent, and seven of them spent about 35k tokens each on
# three tool calls, while every merged tree was the same as its ticket's tree.
# This script makes that merge one command. It runs the test suites only when
# the merged tree differs from the ticket's tree, because the ticket's
# implementer already ran them on that exact tree.
#
# The script runs Godot twice, one process at a time, each in a Godot slot.
from __future__ import annotations

import argparse
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass

from urchin_dev.godot import godot_bin, godot_slot
from urchin_dev.run import run


class MergeConflict(Exception):
    def __init__(self, files: list[str]):
        super().__init__(", ".join(files))
        self.files = files


@dataclass(frozen=True)
class Merged:
    head: str
    tests_ran: bool


def git(*args: str) -> str:
    return run(["git", *args]).stdout.strip()


def run_suites() -> None:
    """The import comes first, because the GUT suite fails with "No loader
    found for resource" on any asset the merge brought in unimported."""
    godot = godot_bin()
    with godot_slot():
        run([godot, "--headless", "--import", "--path", "."])
    with godot_slot():
        run([godot, "--headless", "-s", "res://addons/gut/gut_cmdln.gd", "--path", "."])
    run(["uv", "run", "pytest"])


def merge_ticket(
    branch: str, message: str, suites: Callable[[], None] = run_suites
) -> Merged:
    """Raises MergeConflict after aborting the merge, and passes on the error
    of a failing suite with the merge commit left in place and unpushed."""
    merge = subprocess.run(
        ["git", "merge", "--no-ff", "-m", message, branch],
        capture_output=True,
        text=True,
    )
    if merge.returncode != 0:
        conflicts = git("diff", "--name-only", "--diff-filter=U").split("\n")
        if conflicts == [""]:
            raise RuntimeError(f"git merge failed:\n{merge.stdout}{merge.stderr}")
        git("merge", "--abort")
        raise MergeConflict(conflicts)
    tests_ran = git("rev-parse", "HEAD^{tree}") != git(
        "rev-parse", f"{branch}^{{tree}}"
    )
    head = git("rev-parse", "HEAD")
    try:
        if tests_ran:
            suites()
        git("push", "origin", "HEAD")
    except RuntimeError as error:
        raise RuntimeError(
            f"{error}\nThe merge commit {head} stays in place and is not pushed."
            " Fix the failure, or run git reset --hard HEAD^ to drop the merge."
        ) from error
    return Merged(head, tests_ran)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Merge a ticket branch into the checked-out integration"
        " branch, test the result when its tree differs from the ticket's,"
        " and push."
    )
    parser.add_argument("branch", help="the ticket branch to merge")
    parser.add_argument("-m", "--message", required=True, help="the merge message")
    args = parser.parse_args()
    try:
        merged = merge_ticket(args.branch, args.message)
    except MergeConflict as conflict:
        print(
            f"Merging {args.branch} conflicts, so the merge was aborted:",
            file=sys.stderr,
        )
        for path in conflict.files:
            print(f"  {path}", file=sys.stderr)
        return 1
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    print(f"head: {merged.head}")
    print(
        "tests: ran and passed"
        if merged.tests_ran
        else f"tests: not run, the merged tree is {args.branch}'s tree"
    )
    return 0

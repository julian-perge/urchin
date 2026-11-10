# These tests merge ticket branches in a throwaway git repository under
# tmp_path that pushes to a bare repository beside it. They hand merge_ticket a
# stand-in for the test suites, so Godot never runs.
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from urchin_dev.merge_ticket import MergeConflict, merge_ticket


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def commit_file(name: str, text: str) -> None:
    Path(name).write_text(text)
    git("add", name)
    git("commit", "-q", "-m", f"write {name}")


@pytest.fixture
def integration(tmp_path, monkeypatch):
    """An integration branch with one commit, pushed to a bare origin."""
    for name in ("GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE"):
        monkeypatch.delenv(name, raising=False)
    subprocess.run(["git", "init", "-q", "--bare", tmp_path / "origin.git"], check=True)
    monkeypatch.chdir(tmp_path)
    git("init", "-q", "-b", "integration", "work")
    monkeypatch.chdir(tmp_path / "work")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.com")
    git("config", "commit.gpgsign", "false")
    git("remote", "add", "origin", str(tmp_path / "origin.git"))
    commit_file("a.txt", "a\n")
    git("push", "-q", "origin", "HEAD")
    return tmp_path


class Suites:
    def __init__(self):
        self.runs = 0

    def __call__(self):
        self.runs += 1


def test_a_branch_whose_tree_the_merge_keeps_is_pushed_without_tests(integration):
    git("checkout", "-q", "-b", "ticket")
    commit_file("b.txt", "b\n")
    git("checkout", "-q", "integration")
    suites = Suites()
    merged = merge_ticket("ticket", "Merge ticket", suites)
    assert (merged.tests_ran, suites.runs) == (False, 0)
    assert merged.head == git("rev-parse", "HEAD")
    assert git("log", "-1", "--format=%s") == "Merge ticket"
    assert git("rev-parse", "HEAD^2") == git("rev-parse", "ticket")
    assert (
        git("--git-dir", str(integration / "origin.git"), "rev-parse", "integration")
        == merged.head
    )


def test_a_merge_that_changes_the_branch_tree_runs_the_suites(integration):
    git("checkout", "-q", "-b", "ticket")
    commit_file("b.txt", "b\n")
    git("checkout", "-q", "integration")
    commit_file("c.txt", "c\n")
    suites = Suites()
    merged = merge_ticket("ticket", "Merge ticket", suites)
    assert (merged.tests_ran, suites.runs) == (True, 1)
    assert (
        git("--git-dir", str(integration / "origin.git"), "rev-parse", "integration")
        == merged.head
    )


def test_a_conflict_aborts_the_merge_and_names_its_files(integration):
    pushed = git("rev-parse", "HEAD")
    git("checkout", "-q", "-b", "ticket")
    commit_file("a.txt", "ticket\n")
    commit_file("b.txt", "b\n")
    git("checkout", "-q", "integration")
    commit_file("a.txt", "integration\n")
    head = git("rev-parse", "HEAD")
    suites = Suites()
    with pytest.raises(MergeConflict) as conflict:
        merge_ticket("ticket", "Merge ticket", suites)
    assert conflict.value.files == ["a.txt"]
    assert (git("rev-parse", "HEAD"), git("status", "--porcelain"), suites.runs) == (
        head,
        "",
        0,
    )
    assert (
        git("--git-dir", str(integration / "origin.git"), "rev-parse", "integration")
        == pushed
    )


def test_a_failing_suite_leaves_the_merge_unpushed(integration):
    pushed = git("rev-parse", "HEAD")
    git("checkout", "-q", "-b", "ticket")
    commit_file("b.txt", "b\n")
    git("checkout", "-q", "integration")
    commit_file("c.txt", "c\n")

    def failing_suites():
        raise RuntimeError("GUT failed")

    with pytest.raises(RuntimeError, match="GUT failed"):
        merge_ticket("ticket", "Merge ticket", failing_suites)
    assert git("rev-parse", "HEAD^2") == git("rev-parse", "ticket")
    assert (
        git("--git-dir", str(integration / "origin.git"), "rev-parse", "integration")
        == pushed
    )

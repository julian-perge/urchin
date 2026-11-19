"""Tests for .claude/hooks/enforce-tools.sh, fed the JSON of a PreToolUse event."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
HOOK = REPO / ".claude" / "hooks" / "enforce-tools.sh"
LOCK = "lockf -k /tmp/urchin-ffdec.lock"


def run_hook(command: str, cwd: Path = REPO) -> subprocess.CompletedProcess[str]:
    payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)}
    return subprocess.run(
        [str(HOOK)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize(
    ("command", "message"),
    [
        ("godot --headless --path .", "Run Godot through just"),
        (
            "/Applications/Godot.app/Contents/MacOS/Godot --path .",
            "Run Godot through just",
        ),
        ('"$GODOT_BIN" --headless --import --path .', "Run Godot through just"),
        (
            "uv run gut test/unit/test_shaders.gd",
            "Run 'just gut' instead of 'uv run gut'",
        ),
        ("uv run pytest -q", "Run 'just pytest'"),
        ("cd dev && uv run extract_faces", "Run 'just extract-faces'"),
        ("just --command git status", "not through 'just --command'"),
        ("just --command uv run gut", "Run 'just gut'"),
        ("just extract-faces", "two ffdec processes must never run at once"),
        (
            "just trace-swf web && just trace-run web flash",
            "'just trace-swf' runs ffdec",
        ),
        ("ffdec -export sprite out sonny2.swf", "two ffdec processes"),
        ("java -jar ~/ffdec/ffdec.jar -export sprite out x.swf", "two ffdec processes"),
        ("just gut | tail -5", "Do not pipe 'just gut'"),
        ("just gut 2>&1 | tee gut.log", "Do not pipe 'just gut'"),
        ("just test |& tail", "Do not pipe 'just test'"),
        ("agent-skills run -- just gut | tail", "Do not pipe 'just gut'"),
        ("(just gut) | tail -1", "Do not pipe a ( ) group"),
        ("{ just gut; } | tail -1", "Do not pipe a { } group"),
        ("${GODOT_BIN:-godot} --version", "Run Godot through just"),
        ("flock /tmp/other.lock -c 'just extract-faces'", "two ffdec processes"),
    ],
)
def test_blocks(command: str, message: str) -> None:
    result = run_hook(command)
    assert result.returncode == 2, result.stderr
    assert message in result.stderr


@pytest.mark.parametrize(
    "command",
    [
        "just gut",
        "just gut || echo failed",
        "(just gut) && echo passed",
        "{ just gut; } || echo failed",
        "just gut; (echo hi) | cat",
        "flock /tmp/urchin-ffdec.lock -c 'just extract-faces'",
        "agent-skills run -- just gut",
        "just godot --headless --check-only -s res://scripts/x.gd --path .",
        "uv run ruff check",
        "uv run check_godot_sidecars",
        "just --command uv run check_godot_sidecars",
        "just extract-screen-rects",
        f"{LOCK} just extract-faces",
        f"{LOCK} bash -c 'just trace-swf web && just trace-run web flash'",
        "java -version",
        'echo "uv run gut | godot"',
        "rg -n godot scripts",
    ],
)
def test_allows(command: str) -> None:
    result = run_hook(command)
    assert result.returncode == 0, result.stderr


def git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=repo,
        check=True,
        capture_output=True,
    )


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    git(tmp_path, "init", "-q")
    (tmp_path / "clean.py").write_text("x = 1\n")
    git(tmp_path, "add", "clean.py")
    git(tmp_path, "commit", "-q", "-m", "start")
    (tmp_path / "pyproject.toml").write_text('[project]\nname = "urchin-dev"\n')
    return tmp_path


def test_commit_of_clean_python_passes(repo: Path) -> None:
    (repo / "clean.py").write_text("y = 2\n")
    git(repo, "add", "clean.py")
    assert run_hook("git commit -m 'feat: y'", repo).returncode == 0


def test_commit_of_unformatted_python_is_blocked(repo: Path) -> None:
    (repo / "bad.py").write_text("x=1\n")
    git(repo, "add", "bad.py")
    result = run_hook("git commit -m 'feat: x'", repo)
    assert result.returncode == 2
    assert "ruff format --check" in result.stderr
    assert "bad.py" in result.stderr


def test_commit_of_python_with_a_lint_finding_is_blocked(repo: Path) -> None:
    (repo / "unused.py").write_text("import os\n")
    git(repo, "add", "unused.py")
    result = run_hook("git commit -m 'feat: os'", repo)
    assert result.returncode == 2
    assert "ruff check" in result.stderr


def test_commit_dash_c_checks_that_repo(repo: Path) -> None:
    (repo / "bad.py").write_text("x=1\n")
    git(repo, "add", "bad.py")
    assert run_hook(f"git -C {repo} commit -m 'feat: x'").returncode == 2


def test_commit_after_cd_checks_that_repo(repo: Path) -> None:
    (repo / "bad.py").write_text("x=1\n")
    git(repo, "add", "bad.py")
    assert run_hook(f"cd {repo} && git commit -m 'feat: x'").returncode == 2


def test_commit_all_checks_unstaged_tracked_python(repo: Path) -> None:
    (repo / "clean.py").write_text("x=1\n")
    assert run_hook("git commit -m 'feat: x'", repo).returncode == 0
    assert run_hook("git commit -am 'feat: x'", repo).returncode == 2


def test_commit_outside_an_urchin_checkout_passes(repo: Path) -> None:
    (repo / "pyproject.toml").write_text('[project]\nname = "other"\n')
    (repo / "bad.py").write_text("x=1\n")
    git(repo, "add", "bad.py")
    assert run_hook("git commit -m 'feat: x'", repo).returncode == 0


def test_commit_passes_with_a_warning_when_uv_cannot_run(
    repo: Path, tmp_path_factory: pytest.TempPathFactory
) -> None:
    (repo / "bad.py").write_text("x=1\n")
    git(repo, "add", "bad.py")
    bin_dir = tmp_path_factory.mktemp("bin")
    for tool in ("bash", "cat", "jq", "git", "dirname", "grep"):
        found = shutil.which(tool)
        assert found
        (bin_dir / tool).symlink_to(found)
    payload = {
        "tool_name": "Bash",
        "tool_input": {"command": "git commit -m x"},
        "cwd": str(repo),
    }
    result = subprocess.run(
        [str(HOOK)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=False,
        env={"PATH": str(bin_dir), "HOME": str(repo)},
    )
    assert result.returncode == 0, result.stderr
    assert "could not start ruff" in json.loads(result.stdout)["systemMessage"]

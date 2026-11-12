# These tests hand run_gut a fake Godot that records its arguments and replays
# logs trimmed from real GUT 9.7.1 runs in this repo on 2026-11-10, so none of
# them needs Godot.
from __future__ import annotations

from pathlib import Path

import pytest
from urchin_dev.gut import godot_command, run_gut

PASSED = (
    "---  GUT  ---\n"
    "\x1b[1m[INFO]:  \x1b[0musing [app_userdata/urchin] for temporary output.\n"
    "\x1b[4m\n\nres://test/unit/test_project_settings.gd\n"
    "\x1b[0m* test_pixel_snapping_stays_off\n"
    "\x1b[1m1/1 passed.\n"
    "\x1b[0m\n"
    "Totals\n"
    "------\n"
    "Scripts               1\n"
    "Tests                 1\n"
    "Passing Tests         1\n"
    "Asserts               2\n"
    "Time              0.466s\n"
    "\x1b[32m---- All tests passed! ----\n"
    "\x1b[0m\n"
)

# A test file with `var probe: NoSuchClassAnywhere`, run alone. GUT skips the
# file and still exits 0, as the 2026-11-10 entry in ~/.config/papercuts.md
# records.
UNPARSEABLE_FILE = (
    "---  GUT  ---\n"
    'SCRIPT ERROR: Parse Error: Could not find type "NoSuchClassAnywhere" in the'
    " current scope.\n"
    "          at: GDScript::reload (res://test/unit/test_zz_broken_probe.gd:3)\n"
    'ERROR: Failed to load script "res://test/unit/test_zz_broken_probe.gd" with'
    ' error "Parse error".\n'
    "\x1b[33m[GUT WARNING]:  \x1b[0mIgnoring script"
    " res://test/unit/test_zz_broken_probe.gd because it does not extend GutTest\n"
    "\x1b[31m[GUT ERROR]:  \x1b[0mNothing was run.\n"
    "On the one hand nothing failed, on the other hand nothing did anything.\n"
)

NO_TEST_MATCHED = (
    "---  GUT  ---\n"
    "\x1b[4m\n\nres://test/integration/test_zone_battle_flow.gd\n"
    "\x1b[0m\n"
    "\x1b[31m[GUT ERROR]:  \x1b[0mNothing was run.\n"
    "On the one hand nothing failed, on the other hand nothing did anything.\n"
    'Ran Tests matching "no_test_has_this_name"\n'
)


class FakeGodot:
    def __init__(self, *results: tuple[int, str]):
        self.results = list(results)
        self.calls: list[list[str]] = []
        self.homes: list[Path | None] = []
        self.home_existed: list[bool] = []

    def __call__(self, args, home=None):
        self.calls.append(list(args))
        self.homes.append(home)
        if home is not None:
            self.home_existed.append(home.is_dir())
        result = self.results.pop(0)
        if isinstance(result, BaseException):
            raise result
        return result


@pytest.fixture
def project(tmp_path: Path) -> Path:
    root = tmp_path / "urchin"
    (root / ".godot").mkdir(parents=True)
    (root / "test" / "unit").mkdir(parents=True)
    (root / "test" / "unit" / "test_a.gd").write_text("extends GutTest\n")
    (tmp_path / "test_outside.gd").write_text("extends GutTest\n")
    return root


def test_no_arguments_runs_the_whole_suite(project):
    godot = FakeGodot((0, PASSED))
    assert run_gut([], project, project, godot) == 0
    assert godot.calls == [
        ["--headless", "-s", "res://addons/gut/gut_cmdln.gd", "--path", str(project)]
    ]


def test_a_test_file_that_does_not_parse_fails_although_gut_exits_0(project):
    assert run_gut([], project, project, FakeGodot((0, UNPARSEABLE_FILE))) == 1


def test_a_run_where_no_test_matched_fails_although_gut_exits_0(project):
    assert run_gut([], project, project, FakeGodot((0, NO_TEST_MATCHED))) == 1


def test_a_crash_keeps_godots_exit_code(project):
    assert run_gut([], project, project, FakeGodot((134, ""))) == 134


def test_a_test_file_path_runs_only_that_file(project):
    godot = FakeGodot((0, PASSED))
    assert run_gut(["test/unit/test_a.gd"], project, project, godot) == 0
    assert godot.calls[-1][-2:] == ["-gdir=", "-gtest=res://test/unit/test_a.gd"]


@pytest.mark.parametrize(
    ("cwd", "arg"),
    [
        ("test", "unit/test_a.gd"),
        ("test/unit", "../unit/./test_a.gd"),
        ("test", "res://test/unit/test_a.gd"),
    ],
)
def test_a_test_file_path_can_be_relative_to_the_shell_or_to_the_project(
    project, cwd, arg
):
    godot = FakeGodot((0, PASSED))
    run_gut([arg], project / cwd, project, godot)
    assert godot.calls[-1][-1] == "-gtest=res://test/unit/test_a.gd"


def test_an_absolute_test_file_path_works(project):
    godot = FakeGodot((0, PASSED))
    run_gut([str(project / "test/unit/test_a.gd")], Path("/"), project, godot)
    assert godot.calls[-1][-1] == "-gtest=res://test/unit/test_a.gd"


def test_gut_options_pass_through_and_do_not_narrow_the_dirs(project):
    godot = FakeGodot((0, PASSED))
    run_gut(["-gunit_test_name=test_b"], project, project, godot)
    assert godot.calls[-1][-1] == "-gunit_test_name=test_b"
    assert "-gdir=" not in godot.calls[-1]


@pytest.mark.parametrize("arg", ["test/unit/test_missing.gd", "../test_outside.gd"])
def test_a_path_that_names_no_test_file_in_the_project_stops_before_godot(project, arg):
    godot = FakeGodot()
    with pytest.raises(SystemExit, match="is not a test file"):
        run_gut([arg], project, project, godot)
    assert godot.calls == []


def test_a_checkout_with_no_import_cache_imports_before_the_run(project):
    (project / ".godot").rmdir()
    godot = FakeGodot((0, "import done\n"), (0, PASSED))
    assert run_gut([], project, project, godot) == 0
    assert godot.calls[0] == ["--headless", "--import", "--path", str(project)]
    assert godot.calls[1][:3] == ["--headless", "-s", "res://addons/gut/gut_cmdln.gd"]


def test_a_failed_import_stops_before_the_run(project):
    (project / ".godot").rmdir()
    godot = FakeGodot((1, "import failed\n"), (0, PASSED))
    assert run_gut([], project, project, godot) == 1
    assert godot.calls == [["--headless", "--import", "--path", str(project)]]


def test_the_run_gets_a_home_folder_of_its_own_that_is_gone_afterwards(project):
    godot = FakeGodot((0, PASSED))
    assert run_gut([], project, project, godot) == 0
    [home] = godot.homes
    assert home is not None
    assert home != Path.home()
    assert godot.home_existed == [True]
    assert not home.exists()


def test_two_runs_get_different_home_folders(project):
    godot = FakeGodot((0, PASSED), (0, PASSED))
    run_gut([], project, project, godot)
    run_gut([], project, project, godot)
    assert godot.homes[0] != godot.homes[1]


@pytest.mark.parametrize("result", [(1, "a test failed\n"), (0, UNPARSEABLE_FILE)])
def test_the_home_folder_is_gone_after_a_failing_run(project, result):
    godot = FakeGodot(result)
    assert run_gut([], project, project, godot) != 0
    assert not godot.homes[0].exists()


def test_the_home_folder_is_gone_after_a_run_that_raises(project):
    godot = FakeGodot(KeyboardInterrupt())
    with pytest.raises(KeyboardInterrupt):
        run_gut([], project, project, godot)
    assert not godot.homes[0].exists()


def test_the_import_step_keeps_the_real_home(project):
    (project / ".godot").rmdir()
    godot = FakeGodot((0, "import done\n"), (0, PASSED))
    run_gut([], project, project, godot)
    assert godot.homes[0] is None
    assert godot.homes[1] is not None


def test_the_new_home_is_set_by_env_before_the_godot_binary(monkeypatch):
    monkeypatch.setenv("GODOT_BIN", "/Godot")
    assert godot_command(["--headless"], Path("/tmp/h")) == [
        "env",
        "HOME=/tmp/h",
        "/Godot",
        "--headless",
    ]
    assert godot_command(["--headless"], None) == ["/Godot", "--headless"]

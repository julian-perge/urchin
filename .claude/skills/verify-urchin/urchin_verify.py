#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Launch, drive and stop an isolated urchin game for verification.

Each run has a name and a folder, ~/tmp/<date>-verify-urchin/<run>/. The game
reads and writes its own user:// folder under data/ there, so a run never
touches the saves, achievements.cfg or battle.log of the real game. The
evidence/ folder holds the screenshots and the action log, and stop keeps it.

  urchin_verify.py launch <run> [--scene res://x.tscn] [--preset NAME:SLOT]
                          [--sound] [-- game args]
  urchin_verify.py doctor <run>
  urchin_verify.py send <run> '<json commands>' [--label NAME] [--warp]
  urchin_verify.py click <run> <node> [--label NAME] [--wait MS]
  urchin_verify.py shot <run> <label>
  urchin_verify.py node <run> <node> [--props a,b]
  urchin_verify.py tree <run> [<node>] [--depth N] [--all]
  urchin_verify.py userdir <run>
  urchin_verify.py log <run> [-n LINES] [--grep TEXT]
  urchin_verify.py stop <run>
  urchin_verify.py list
"""

from __future__ import annotations

import argparse
import base64
import datetime
import json
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

TMP_ROOT = Path.home() / "tmp"
RUN_SUFFIX = "-verify-urchin"
HARNESS = Path("vendor/godot-mcp/src/scripts/mcp_harness.gd")
ERROR_MARKERS = ("SCRIPT ERROR", "Parse Error", "SHADER ERROR")
READY_MARKER = "[godot-mcp harness] listening on"


def now() -> datetime.datetime:
    return datetime.datetime.now(datetime.UTC).astimezone()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def repo_root() -> Path:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if out.returncode != 0:
        fail("run this from inside an urchin checkout")
    root = Path(out.stdout.strip())
    if not (root / "project.godot").exists():
        fail(f"{root} has no project.godot")
    return root


def git_head(root: Path) -> str:
    return subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()


def find_harness(root: Path) -> Path:
    override = os.environ.get("URCHIN_VERIFY_HARNESS")
    if override:
        # Godot starts in the repo root, so a relative path is resolved here,
        # from the folder that the helper runs in.
        harness = Path(override).expanduser().resolve()
        if not harness.exists():
            fail(f"URCHIN_VERIFY_HARNESS is {override}, and that file does not exist")
        return harness
    if not (root / HARNESS).exists():
        fail(
            "vendor/godot-mcp is empty. Run just setup-worktree, or git submodule update --init vendor/godot-mcp"
        )
    return root / HARNESS


# A pull or a branch switch moves urchin's pin but leaves the files in
# vendor/godot-mcp alone unless submodule.recurse is set, so a run could load
# an old harness with no sign of it. A branch checked out in the submodule
# means someone is editing the harness there, so that case only gets a note.
def harness_drift(root: Path, harness: Path) -> tuple[str, bool]:
    if harness.resolve() != (root / HARNESS).resolve():
        return "", False
    submodule = ["git", "-C", str(root / "vendor/godot-mcp")]
    pinned = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-s", "vendor/godot-mcp"],
        capture_output=True,
        text=True,
    ).stdout.split()
    current = subprocess.run(
        [*submodule, "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()
    if len(pinned) < 2 or pinned[1] == current:
        return "", False
    branch = subprocess.run(
        [*submodule, "symbolic-ref", "-q", "--short", "HEAD"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    where = f"branch {branch} at {current[:8]}" if branch else current[:8]
    message = f"vendor/godot-mcp is at {where}, but urchin pins {pinned[1][:8]}"
    if branch:
        return message, False
    return message + ". Run git submodule update --init vendor/godot-mcp", True


def real_user_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Godot/app_userdata/urchin"
    data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    return Path(data_home) / "godot/app_userdata/urchin"


def isolated_user_dir(data: Path) -> Path:
    if sys.platform == "darwin":
        return data / "Library/Application Support/Godot/app_userdata/urchin"
    return data / "godot/app_userdata/urchin"


def isolated_env(data: Path) -> dict:
    env = dict(os.environ)
    env["XDG_DATA_HOME"] = str(data)
    if sys.platform == "darwin":
        env["HOME"] = str(data)
    return env


def fingerprint(folder: Path) -> dict:
    """Size and mtime of each save, achievements file and log of the real game."""
    prints = {}
    for pattern in ("saves/*", "achievements.cfg*", "logs/*"):
        for path in sorted(folder.glob(pattern)):
            if path.is_file():
                stat = path.stat()
                prints[str(path.relative_to(folder))] = [stat.st_size, stat.st_mtime_ns]
    return prints


def run_dir(run: str, create: bool = False) -> Path:
    if create:
        return TMP_ROOT / f"{now():%Y-%m-%d}{RUN_SUFFIX}" / run
    matches = sorted(TMP_ROOT.glob(f"*{RUN_SUFFIX}/{run}/state.json"))
    if not matches:
        fail(f"no run named {run}. Start one with: urchin_verify.py launch {run}")
    return matches[-1].parent


def load_state(run: str) -> tuple[Path, dict]:
    folder = run_dir(run)
    return folder, json.loads((folder / "state.json").read_text())


def save_state(folder: Path, state: dict) -> None:
    (folder / "state.json").write_text(json.dumps(state, indent=2) + "\n")


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def group_pids(pgid: int) -> list[int]:
    out = subprocess.run(
        ["ps", "-eo", "pid=,pgid="], capture_output=True, text=True
    ).stdout
    pids = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and int(parts[1]) == pgid:
            pids.append(int(parts[0]))
    return pids


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request(
    state: dict, commands: list, timeout: float = 60.0, warp: bool = False
) -> dict:
    body = {"token": state["token"], "commands": commands, "warp_mouse": warp}
    payload = json.dumps(body) + "\n"
    with socket.create_connection(
        ("127.0.0.1", state["port"]), timeout=timeout
    ) as sock:
        sock.sendall(payload.encode())
        chunks = []
        while True:
            chunk = sock.recv(1 << 20)
            if not chunk:
                break
            chunks.append(chunk)
    text = b"".join(chunks).decode()
    if not text.strip():
        return {
            "ok": False,
            "error": "the harness closed the connection with no answer",
        }
    return json.loads(text)


def log_errors(log: Path) -> list[str]:
    if not log.exists():
        return []
    return [
        line
        for line in log.read_text(errors="replace").splitlines()
        if any(m in line for m in ERROR_MARKERS)
    ]


def record(
    folder: Path,
    state: dict,
    commands: list,
    label: str,
    timeout: float = 60.0,
    warp: bool = False,
) -> dict:
    """Sends commands, saves each screenshot as evidence, and logs the action."""
    started = time.time()
    answer = request(state, commands, timeout, warp)
    state["seq"] = state.get("seq", 0) + 1
    shots = []
    for index, result in enumerate(answer.get("results", [])):
        png = result.pop("png_base64", None)
        if png is not None:
            name = (
                f"{state['seq']:03d}-{label}"
                + (f"-{index}" if len(commands) > 1 else "")
                + ".png"
            )
            path = folder / "evidence" / name
            path.write_bytes(base64.b64decode(png))
            result["saved"] = str(path)
            shots.append(str(path))
    save_state(folder, state)
    entry = {
        "seq": state["seq"],
        "label": label,
        "at": datetime.datetime.fromtimestamp(started, datetime.UTC)
        .astimezone()
        .isoformat(timespec="seconds"),
        "warp_mouse": warp,
        "commands": commands,
        "answer": answer,
    }
    with (folder / "evidence" / "actions.jsonl").open("a") as actions:
        actions.write(json.dumps(entry) + "\n")
    return answer


def print_answer(answer: dict) -> None:
    print(json.dumps(answer, indent=2))
    if not answer.get("ok"):
        sys.exit(1)


def cmd_launch(args: argparse.Namespace) -> None:
    root = repo_root()
    harness = find_harness(root)
    drift, stale = harness_drift(root, harness)
    if stale:
        fail(drift)
    folder = run_dir(args.run, create=True)
    if (folder / "state.json").exists():
        state = json.loads((folder / "state.json").read_text())
        if state.get("status") == "running" and pid_alive(state["pid"]):
            fail(
                f"run {args.run} is already running (pid {state['pid']}). Stop it first, or pick another name"
            )
    data = folder / "data"
    evidence = folder / "evidence"
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    evidence.mkdir(parents=True, exist_ok=True)
    env = isolated_env(data)
    for preset in args.preset:
        name, _, slot = preset.partition(":")
        if not slot:
            fail(f"--preset takes NAME:SLOT, such as zone3_boss:1, not {preset}")
        out = subprocess.run(
            ["just", "apply-preset", name, slot],
            cwd=root,
            env=env,
            capture_output=True,
            text=True,
        )
        (evidence / f"preset-{name}-{slot}.log").write_text(out.stdout + out.stderr)
        if out.returncode != 0:
            fail(f"just apply-preset {name} {slot} failed:\n{out.stdout}{out.stderr}")
    port = free_port()
    token = secrets.token_hex(16)
    env["GODOT_MCP_HARNESS_PORT"] = str(port)
    env["GODOT_MCP_HARNESS_TOKEN"] = token
    env["GODOT_MCP_HARNESS_TITLE"] = f"AGENT VERIFY - {args.run}"
    command = ["just", "godot", "--path", str(root)]
    if not args.sound:
        command += ["--audio-driver", "Dummy"]
    command += ["-s", str(harness)]
    if args.scene:
        command.append(args.scene)
    game_args = args.game_args
    if game_args:
        command += ["--", *game_args]
    log = folder / "godot.log"
    real = real_user_dir()
    with log.open("w") as log_file:
        process = subprocess.Popen(
            command,
            cwd=root,
            env=env,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    state = {
        "run": args.run,
        "status": "running",
        "pid": process.pid,
        "pgid": process.pid,
        "port": port,
        "token": token,
        "repo": str(root),
        "head": git_head(root),
        "harness": str(harness),
        "command": command,
        "data": str(data),
        "user_dir": str(isolated_user_dir(data)),
        "real_user_dir": str(real),
        "real_fingerprint": fingerprint(real),
        "started": now().isoformat(timespec="seconds"),
        "seq": 0,
    }
    save_state(folder, state)
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        if process.poll() is not None:
            fail(
                f"Godot exited with {process.returncode} before it was ready. Log: {log}"
            )
        if READY_MARKER in log.read_text(errors="replace"):
            break
        time.sleep(0.25)
    else:
        fail(
            f"no harness listening line after {args.timeout} s. Log: {log}. Run stop {args.run}"
        )
    while time.time() < deadline:
        answer = record(
            folder,
            state,
            [{"type": "wait", "duration_ms": args.settle_ms}, {"type": "screenshot"}],
            "launch",
        )
        if answer.get("ok"):
            break
        time.sleep(1)
    else:
        fail(
            f"the game drew no frame: {answer}. Is the window minimized? Run stop {args.run}"
        )
    errors = log_errors(log)
    parse_errors = [line for line in errors if "Parse Error" in line]
    if parse_errors:
        fail(
            "the game started with parse errors, so a script did not load: "
            + parse_errors[0]
            + f". A stale class cache causes this: run just import, then stop {args.run}"
            " and launch again"
        )
    print(
        json.dumps(
            {
                "ready": True,
                "run": args.run,
                "folder": str(folder),
                "evidence": str(evidence),
                "screenshot": answer["results"][-1].get("saved"),
                "log_errors": errors,
                **({"harness_note": drift} if drift else {}),
            },
            indent=2,
        )
    )


def cmd_doctor(args: argparse.Namespace) -> None:
    folder, state = load_state(args.run)
    checks = {}
    alive = state.get("status") == "running" and pid_alive(state["pid"])
    checks["process_up"] = alive
    # Every run loads the same harness file, so the run's own token in a
    # process's environment is what marks that process as this run's Godot.
    godot_pids = []
    token = f"GODOT_MCP_HARNESS_TOKEN={state['token']}".encode()
    if alive:
        for pid in group_pids(state["pgid"]):
            try:
                program = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")[0]
                environ = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
            except OSError:
                continue
            if token in environ and "just" not in Path(program.decode()).name:
                godot_pids.append(pid)
    checks["godot_runs_our_harness"] = bool(godot_pids) or sys.platform == "darwin"
    try:
        answer = request(state, [], timeout=5)
        checks["harness_answers_with_our_token"] = bool(answer.get("ok"))
    except OSError as error:
        checks["harness_answers_with_our_token"] = False
        checks["harness_error"] = str(error)
    checks["same_commit_as_launch"] = git_head(Path(state["repo"])) == state["head"]
    drift, stale = harness_drift(Path(state["repo"]), Path(state["harness"]))
    checks["harness_matches_pin"] = not stale
    if drift:
        checks["harness_note"] = drift
    checks["isolated_user_dir_exists"] = Path(state["user_dir"]).is_dir()
    checks["real_user_dir_unchanged"] = (
        fingerprint(Path(state["real_user_dir"])) == state["real_fingerprint"]
    )
    errors = log_errors(folder / "godot.log")
    checks["no_parse_errors"] = not any("Parse Error" in line for line in errors)
    checks["log_errors"] = errors[-10:]
    healthy = all(
        v
        for k, v in checks.items()
        if k not in ("log_errors", "harness_error", "harness_note")
    )
    checks["healthy"] = healthy
    checks["godot_pids"] = godot_pids
    print(json.dumps(checks, indent=2))
    if not healthy:
        sys.exit(1)


def cmd_send(args: argparse.Namespace) -> None:
    folder, state = load_state(args.run)
    raw = (
        Path(args.commands[1:]).read_text()
        if args.commands.startswith("@")
        else args.commands
    )
    commands = json.loads(raw)
    if isinstance(commands, dict):
        commands = [commands]
    print_answer(record(folder, state, commands, args.label, args.timeout, args.warp))


def cmd_click(args: argparse.Namespace) -> None:
    folder, state = load_state(args.run)
    found = request(state, [{"type": "node", "path": args.node}])
    info = found.get("results", [{}])[0]
    if not found.get("ok") or "center" not in info:
        print_answer({"ok": False, "error": f"cannot click {args.node}", "node": info})
    if not info.get("visible", True):
        print_answer({"ok": False, "error": f"{args.node} is hidden", "node": info})
    x, y = info["center"]
    commands = [
        {"type": "click", "x": x, "y": y},
        {"type": "wait", "duration_ms": args.wait},
        {"type": "screenshot"},
    ]
    answer = record(folder, state, commands, args.label or Path(args.node).name)
    answer["node"] = info
    print_answer(answer)


def cmd_shot(args: argparse.Namespace) -> None:
    folder, state = load_state(args.run)
    print_answer(record(folder, state, [{"type": "screenshot"}], args.label))


def cmd_node(args: argparse.Namespace) -> None:
    _, state = load_state(args.run)
    props = [p for p in (args.props or "").split(",") if p]
    print_answer(
        request(
            state,
            [
                {"type": "node", "path": path, **({"props": props} if props else {})}
                for path in args.node
            ],
        )
    )


def cmd_tree(args: argparse.Namespace) -> None:
    _, state = load_state(args.run)
    answer = request(
        state,
        [
            {
                "type": "tree",
                "path": args.node or "",
                "depth": args.depth,
                "include_hidden": args.all,
            }
        ],
    )
    if not answer.get("ok"):
        print_answer(answer)
    result = answer["results"][0]
    print(f"scene {result['scene']}")
    for entry in result["nodes"]:
        rect = entry.get("rect")
        where = f" rect={[round(v, 1) for v in rect]}" if rect else ""
        text = f" text={entry['text'][:40]!r}" if entry.get("text") else ""
        hidden = "" if entry.get("visible", True) else " hidden"
        name = entry["path"].rsplit("/", 1)[-1]
        if args.paths:
            name = entry["path"].removeprefix(result["root"] + "/")
        print(f"{'  ' * entry['depth']}{name} ({entry['class']}){where}{text}{hidden}")


def cmd_userdir(args: argparse.Namespace) -> None:
    _, state = load_state(args.run)
    print(state["user_dir"])


def cmd_log(args: argparse.Namespace) -> None:
    folder, _ = load_state(args.run)
    lines = (folder / "godot.log").read_text(errors="replace").splitlines()
    if args.grep:
        lines = [line for line in lines if args.grep in line]
    print("\n".join(lines[-args.n :]))


def cmd_stop(args: argparse.Namespace) -> None:
    folder, state = load_state(args.run)
    evidence = folder / "evidence"
    user_dir = Path(state["user_dir"])
    if state.get("status") == "running":
        try:
            os.killpg(state["pgid"], signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.time() + 10
        while group_pids(state["pgid"]) and time.time() < deadline:
            time.sleep(0.25)
        if group_pids(state["pgid"]):
            try:
                os.killpg(state["pgid"], signal.SIGKILL)
            except ProcessLookupError:
                pass
    if user_dir.is_dir():
        shutil.copytree(
            user_dir,
            evidence / "user_data",
            ignore=shutil.ignore_patterns("shader_cache", "vulkan"),
            dirs_exist_ok=True,
        )
    if (folder / "godot.log").exists():
        shutil.copy2(folder / "godot.log", evidence / "godot.log")
    unchanged = fingerprint(Path(state["real_user_dir"])) == state["real_fingerprint"]
    shutil.rmtree(folder / "data", ignore_errors=True)
    state["status"] = "stopped"
    state["stopped"] = now().isoformat(timespec="seconds")
    save_state(folder, state)
    print(
        json.dumps(
            {
                "stopped": args.run,
                "evidence": str(evidence),
                "files": sorted(p.name for p in evidence.iterdir()),
                "real_user_dir_unchanged": unchanged,
                "left_running": group_pids(state["pgid"]),
            },
            indent=2,
        )
    )


def cmd_list(_: argparse.Namespace) -> None:
    for path in sorted(TMP_ROOT.glob(f"*{RUN_SUFFIX}/*/state.json")):
        state = json.loads(path.read_text())
        alive = state.get("status") == "running" and pid_alive(state["pid"])
        print(
            f"{state['run']}\t{'running' if alive else state.get('status')}\tpid {state['pid']}\t{path.parent}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("launch")
    p.add_argument("run")
    p.add_argument("--scene", help="res:// scene to run instead of the main menu")
    p.add_argument(
        "--preset",
        action="append",
        default=[],
        help="NAME:SLOT, a QA save preset to copy into the run's own user:// first",
    )
    p.add_argument(
        "--sound",
        action="store_true",
        help="play audio; the default uses the Dummy audio driver",
    )
    p.add_argument("--timeout", type=float, default=180)
    p.add_argument(
        "--settle-ms", type=int, default=1500, help="wait before the launch screenshot"
    )
    p.set_defaults(func=cmd_launch)
    p = sub.add_parser("doctor")
    p.add_argument("run")
    p.set_defaults(func=cmd_doctor)
    p = sub.add_parser("send")
    p.add_argument("run")
    p.add_argument("commands", help="a JSON command or list of commands, or @file")
    p.add_argument("--label", default="send")
    p.add_argument("--timeout", type=float, default=60)
    p.add_argument(
        "--warp",
        action="store_true",
        help="also move the real cursor, which hover tooltips need on Linux",
    )
    p.set_defaults(func=cmd_send)
    p = sub.add_parser("click")
    p.add_argument("run")
    p.add_argument("node", help="node name or path, as tree prints it")
    p.add_argument("--label")
    p.add_argument(
        "--wait", type=int, default=500, help="ms to wait before the screenshot"
    )
    p.set_defaults(func=cmd_click)
    p = sub.add_parser("shot")
    p.add_argument("run")
    p.add_argument("label")
    p.set_defaults(func=cmd_shot)
    p = sub.add_parser("node")
    p.add_argument("run")
    p.add_argument("node", nargs="+")
    p.add_argument("--props", help="comma-separated property names to read")
    p.set_defaults(func=cmd_node)
    p = sub.add_parser("tree")
    p.add_argument("run")
    p.add_argument("node", nargs="?")
    p.add_argument("--depth", type=int, default=3)
    p.add_argument("--all", action="store_true", help="include hidden nodes")
    p.add_argument(
        "--paths", action="store_true", help="print the path that click and node take"
    )
    p.set_defaults(func=cmd_tree)
    p = sub.add_parser("userdir")
    p.add_argument("run")
    p.set_defaults(func=cmd_userdir)
    p = sub.add_parser("log")
    p.add_argument("run")
    p.add_argument("-n", type=int, default=40)
    p.add_argument("--grep")
    p.set_defaults(func=cmd_log)
    p = sub.add_parser("stop")
    p.add_argument("run")
    p.set_defaults(func=cmd_stop)
    p = sub.add_parser("list")
    p.set_defaults(func=cmd_list)
    # Everything after a bare -- goes to the game, as OS.get_cmdline_user_args().
    argv = sys.argv[1:]
    split = argv.index("--") if "--" in argv else len(argv)
    args = parser.parse_args(argv[:split])
    args.game_args = argv[split + 1 :]
    args.func(args)


if __name__ == "__main__":
    main()

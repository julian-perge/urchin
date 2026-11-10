from __future__ import annotations

from urchin_dev.run import stream


def test_stream_prints_stdout_and_stderr_as_one_log_and_returns_it(capfd):
    code, output = stream(["sh", "-c", "echo GUT; echo SCRIPT ERROR >&2; exit 3"])
    assert (code, output) == (3, "GUT\nSCRIPT ERROR\n")
    assert capfd.readouterr().out == "GUT\nSCRIPT ERROR\n"

# Tests trace.py with probe files in a temporary folder. No SWF, ffdec or
# player is needed.
from __future__ import annotations

from urchin_dev.swf.trace import read_probes, with_probes


def test_with_probes_puts_the_probes_first_in_name_order_and_keeps_the_frame_script(
    tmp_path,
):
    (tmp_path / "b_second.as").write_text("trace(2);")
    (tmp_path / "a_first.as").write_text("trace(1);\n\n")
    (tmp_path / "notes.txt").write_text("not a probe")
    frame_script = "var x = 1;\r\nStage.showMenu = false();\r\n"

    result = with_probes(frame_script, read_probes(tmp_path))

    assert result.endswith(frame_script)
    assert result.removesuffix(frame_script) == "trace(1);\ntrace(2);\n"

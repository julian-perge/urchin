# extract_vfx's clean-up of a clip's folder on files made in a temporary
# folder, so no test needs the gitignored SWF.
from __future__ import annotations

from urchin_dev.swf.extract import vfx


def test_a_run_deletes_the_frames_a_clip_no_longer_has_and_their_imports(tmp_path):
    # BOOM_SPARK went from 25 frames to 20, and vfx_scenes.py builds a clip's
    # scene from every PNG in its folder.
    for n in range(1, 6):
        (tmp_path / f"{n}.png").write_bytes(b"")
        (tmp_path / f"{n}.png.import").write_bytes(b"")
    vfx.remove_frames_past(tmp_path, 3)
    assert sorted(path.name for path in tmp_path.iterdir()) == [
        "1.png",
        "1.png.import",
        "2.png",
        "2.png.import",
        "3.png",
        "3.png.import",
    ]

# strip.py's refusals on SWF bytes built by hand, so no test needs the
# gitignored SWF or ffdec.
from __future__ import annotations

import struct
from pathlib import Path

import pytest
from test_swf_index import place2, swf, tag
from urchin_dev.swf import strip
from urchin_dev.swf.strip import StripError
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SHAPE,
    TAG_DEFINE_SPRITE,
    TAG_END,
    TAG_PLACE_OBJECT2,
    TAG_SHOW_FRAME,
    parse_swf,
)

SHOW = tag(TAG_SHOW_FRAME)


def shape(cid: int) -> bytes:
    return tag(TAG_DEFINE_SHAPE, struct.pack("<H", cid) + b"\0\0\0\0\0")


def mask(depth: int, cid: int, clip_depth: int) -> bytes:
    """A PlaceObject2 carrying a character and a clipDepth."""
    return tag(
        TAG_PLACE_OBJECT2, bytes([0x42]) + struct.pack("<HHH", depth, cid, clip_depth)
    )


def movie() -> bytes:
    """Shape 10 masks inside sprite 20 and on the root, shape 11 is plain, and
    shape 12 is defined but placed nowhere."""
    sprite = struct.pack("<HH", 20, 1) + mask(2, 10, 15) + SHOW + tag(TAG_END)
    return swf(
        shape(10),
        shape(11),
        shape(12),
        tag(TAG_DEFINE_SPRITE, sprite),
        place2(1, cid=20),
        mask(3, 10, 9),
        place2(4, cid=11),
        SHOW,
        frames=1,
    )


def test_a_clip_mask_is_refused_naming_every_placement_of_it():
    with pytest.raises(StripError) as error:
        strip.check(parse_swf(movie()), {10: "looks like scaffolding", 11: "plain"})
    message = str(error.value)
    assert "timeline 20 frame 1 depth 2 clipDepth 15" in message
    assert "timeline 0 frame 1 depth 3 clipDepth 9" in message
    assert "character 11" not in message


def test_an_id_nothing_places_is_refused():
    with pytest.raises(StripError, match="12 .*nothing places it"):
        strip.check(parse_swf(movie()), {12: "a stale entry"})


def test_a_strip_list_is_every_id_once_they_pass(tmp_path):
    path = tmp_path / "movie.swf"
    path.write_bytes(movie())
    assert strip.strip_list(path, {20: "the sprite", 11: "the plain shape"}) == [11, 20]


def test_a_copy_strips_every_id_in_one_ffdec_call(tmp_path, monkeypatch):
    path = tmp_path / "movie.swf"
    path.write_bytes(movie())
    calls = []

    def fake_run(cmd: list[str]) -> None:
        calls.append(cmd)
        Path(cmd[3]).write_bytes(b"stripped")

    monkeypatch.setattr(strip, "run", fake_run)
    with strip.stripped_copy(path, {20: "the sprite", 11: "the plain shape"}) as copy:
        assert copy.read_bytes() == b"stripped"
    assert [cmd[1:3] + cmd[4:] for cmd in calls] == [
        ["-removeCharacter", str(path), "11", "20"]
    ]
    assert not copy.exists()


def test_a_copy_refuses_before_it_runs_ffdec(tmp_path, monkeypatch):
    path = tmp_path / "movie.swf"
    path.write_bytes(movie())
    monkeypatch.setattr(strip, "run", lambda cmd: pytest.fail("ffdec ran"))
    with pytest.raises(StripError), strip.stripped_copy(path, {10: "a mask"}):
        pass


def test_a_strip_list_refuses_a_clip_mask(tmp_path):
    path = tmp_path / "movie.swf"
    path.write_bytes(movie())
    with pytest.raises(StripError, match="character 10 .*clip mask"):
        strip.strip_list(path, {10: "a mask"})

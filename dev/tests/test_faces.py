# The face record: where the cropped portraits sit in clip 2978, so a scene that
# shows one can take its rect from the SWF. The tests use rects built by hand, so
# no test needs the gitignored SWF or ffdec.
from __future__ import annotations

import pytest
from PIL import Image
from urchin_dev.swf import render
from urchin_dev.swf.extract import faces


def trimmed(rect: tuple[float, float, float, float]) -> render.Trimmed:
    return render.Trimmed(Image.new("RGBA", (1, 1)), (0, 0, 1, 1), rect)


def test_crop_record_is_where_the_crop_box_sits_in_the_clip():
    cut = [trimmed((1.0, 2.0, 28.0, 38.0)), trimmed((1.0, 2.0, 28.0, 38.0))]
    assert faces.crop_record(cut, 5.0) == {
        "relative_to": "sprite 2978",
        "rect": [1.0, 2.0, 28.0, 38.0],
        "size": [140, 190],
        "zoom": 5.0,
    }


def test_crop_record_refuses_frames_whose_crop_boxes_differ():
    cut = [trimmed((1.0, 2.0, 28.0, 38.0)), trimmed((1.0, 3.0, 28.0, 38.0))]
    with pytest.raises(ValueError, match="differ"):
        faces.crop_record(cut, 5.0)


def test_crop_record_refuses_no_frames():
    with pytest.raises(ValueError, match="no frame"):
        faces.crop_record([], 5.0)

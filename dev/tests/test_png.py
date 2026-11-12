# Checks that png.save writes bytes that depend only on the pixels, and that no
# extractor writes a PNG another way. Pillow's own encoder compresses with the
# zlib build of the machine it runs on, so the same pixels came out as
# different bytes on Linux and on macOS.
from __future__ import annotations

import io
import re

from PIL import Image
from urchin_dev import REPO_ROOT, png


def sample() -> Image.Image:
    image = Image.new("RGBA", (37, 21), (0, 0, 0, 0))
    for x in range(37):
        for y in range(21):
            image.putpixel(
                (x, y), (x * 7 % 256, y * 11 % 256, (x * y) % 256, (x + y) * 5 % 256)
            )
    return image


def test_the_saved_png_has_the_same_pixels(tmp_path):
    out = tmp_path / "a.png"
    png.save(sample(), out)
    with Image.open(out) as saved:
        assert saved.convert("RGBA").tobytes() == sample().tobytes()


def test_the_same_pixels_give_the_same_bytes_whatever_encoding_they_came_from(tmp_path):
    pillow_fast = io.BytesIO()
    sample().save(pillow_fast, "PNG", compress_level=1)
    reopened = Image.open(io.BytesIO(pillow_fast.getvalue()))
    png.save(sample(), tmp_path / "a.png")
    png.save(reopened, tmp_path / "b.png")
    assert (tmp_path / "a.png").read_bytes() == (tmp_path / "b.png").read_bytes()


def test_an_rgb_image_gives_the_bytes_of_its_opaque_rgba_copy(tmp_path):
    rgb = sample().convert("RGB")
    png.save(rgb, tmp_path / "rgb.png")
    png.save(rgb.convert("RGBA"), tmp_path / "rgba.png")
    assert (tmp_path / "rgb.png").read_bytes() == (tmp_path / "rgba.png").read_bytes()


def test_png_save_copy_writes_the_bytes_save_would(tmp_path):
    source = tmp_path / "rendered.png"
    sample().save(source, compress_level=9)
    png.save_copy(source, tmp_path / "copy.png")
    png.save(sample(), tmp_path / "saved.png")
    assert (tmp_path / "copy.png").read_bytes() == (tmp_path / "saved.png").read_bytes()


def test_no_extractor_writes_a_png_without_png_save():
    writers = re.compile(r"\.save\(|copyfile\(|shutil\.copy")
    found = [
        f"{path.name}:{n}: {line.strip()}"
        for path in sorted((REPO_ROOT / "dev/urchin_dev/swf/extract").glob("*.py"))
        for n, line in enumerate(path.read_text().splitlines(), start=1)
        if writers.search(line) and "png.save" not in line
    ]
    # cutscenes.py copies the encoded video, which is not a PNG.
    assert found == [
        "cutscenes.py:664: shutil.copyfile(ogv_path, OUT_DIR / ogv_path.name)"
    ]

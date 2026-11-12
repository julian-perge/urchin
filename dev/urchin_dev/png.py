# png.py
# Every PNG an extractor writes goes through save() or save_copy(). Pillow's
# encoder, and the Java encoder the ffdec driver uses, compress with the zlib
# build of the machine they run on, so the same pixels came out as different
# bytes on Linux and on macOS. oxipng carries its own compressor, so its bytes
# depend only on the pixels and on the pyoxipng-ng version pyproject.toml pins.
from __future__ import annotations

from pathlib import Path

import oxipng
from PIL import Image

LEVEL = 2


def save(image: Image.Image, path: Path) -> None:
    """Write `image` to `path` as a PNG built from its RGBA pixels alone.
    oxipng may store it with fewer channels or a palette when no pixel
    needs more, and the pixels read back the same."""
    rgba = image.convert("RGBA")
    raw = oxipng.RawImage(
        rgba.tobytes(), rgba.width, rgba.height, color_type=oxipng.ColorType.rgba()
    )
    path.write_bytes(
        raw.create_optimized_png(level=LEVEL, strip=oxipng.StripChunks.safe())
    )


def save_copy(source: Path, path: Path) -> None:
    """Write the PNG at `source` to `path` through save()."""
    with Image.open(source) as image:
        save(image, path)

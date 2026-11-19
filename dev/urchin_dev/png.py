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
MIPMAPS_OFF = "mipmaps/generate=false"
MIPMAPS_ON = "mipmaps/generate=true"
# Godot fills in the uid, the paths and every other param of a .import file
# that holds only these lines, and keeps the params it finds when it imports.
MIPMAPPED_IMPORT = (
    '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
    f"[params]\n\n{MIPMAPS_ON}\n"
)


def save(image: Image.Image, path: Path, *, mipmaps: bool = False) -> None:
    """Write `image` to `path` as a PNG built from its RGBA pixels alone.
    oxipng may store it with fewer channels or a palette when no pixel
    needs more, and the pixels read back the same. With `mipmaps`, the
    PNG's .import file asks Godot to import it with mipmaps."""
    rgba = image.convert("RGBA")
    raw = oxipng.RawImage(
        rgba.tobytes(), rgba.width, rgba.height, color_type=oxipng.ColorType.rgba()
    )
    path.write_bytes(
        raw.create_optimized_png(level=LEVEL, strip=oxipng.StripChunks.safe())
    )
    if mipmaps:
        import_with_mipmaps(path)


def import_with_mipmaps(path: Path) -> None:
    """Turn mipmaps on in the .import file of the PNG at `path`, and keep the
    rest of it, so the uid that scenes refer to stays. A PNG with no .import
    file gets one that holds only the importer and the mipmaps param."""
    sidecar = path.with_name(path.name + ".import")
    if not sidecar.exists():
        sidecar.write_text(MIPMAPPED_IMPORT)
        return
    text = sidecar.read_text()
    if MIPMAPS_ON in text.splitlines():
        return
    if MIPMAPS_OFF in text.splitlines():
        text = text.replace(MIPMAPS_OFF, MIPMAPS_ON)
    else:
        text = text.replace("[params]\n\n", f"[params]\n\n{MIPMAPS_ON}\n")
    sidecar.write_text(text)


def save_copy(source: Path, path: Path) -> None:
    """Write the PNG at `source` to `path` through save()."""
    with Image.open(source) as image:
        save(image, path)

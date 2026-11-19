# Checks that every doll part PNG is imported with mipmaps. The parts are
# rendered at 2x, and MODEL8 draws them at about 0.67, so an 800x575 window
# shows each PNG at about a third of its size and only a mipmap level keeps the
# edges from aliasing (#482). extract_doll_art and extract_model_pieces turn
# mipmaps on through png.save, and this catches a PNG that came another way.
from __future__ import annotations

from urchin_dev import REPO_ROOT

SPRITES = REPO_ROOT / "resources/sprites"


def doll_pngs():
    yield from (p for p in SPRITES.glob("*.png") if p.name != "doll_shadow.png")
    yield from (SPRITES / "model_pieces").glob("*.png")
    yield from (SPRITES / "glow_scales").glob("*.png")


def test_every_doll_part_png_is_imported_with_mipmaps():
    pngs = list(doll_pngs())
    assert len(pngs) > 1000
    flat = [
        str(p.relative_to(REPO_ROOT))
        for p in pngs
        if "mipmaps/generate=true"
        not in p.with_name(p.name + ".import").read_text().splitlines()
    ]
    assert flat == []

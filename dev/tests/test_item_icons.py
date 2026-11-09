# extract_item_icons run against every committed item resource, with
# ffdec_lib.render faked so no test needs Java, ffdec or the gitignored SWF.
from __future__ import annotations

import re

from test_render import fake_driver, result
from urchin_dev import REPO_ROOT
from urchin_dev.swf import timeline
from urchin_dev.swf.extract import item_icons

ITEMS = sorted((REPO_ROOT / "resources" / "items").glob("*.tres"))
ICONS = REPO_ROOT / "assets" / "ui" / "items"
NAME = re.compile(r'^name = "(.*)"$', re.MULTILINE)
SLOT_IMAGE = re.compile(r'^slot_image = ExtResource\("([^"]*)"\)$', re.MULTILINE)
NO_ICON_LABEL = {"Tool", "Golden Crowbar", "Golden Pipe", "Golden Axe"}


def stamp(tres):
    return tres.read_bytes(), tres.stat().st_mtime_ns


def slot_image_resource(text: str) -> tuple[str, str] | None:
    """-> the (uid, path) of the texture slot_image names, or None."""
    slot = SLOT_IMAGE.search(text)
    if slot is None:
        return None
    line = re.search(
        r'^\[ext_resource type="Texture2D" uid="([^"]*)" path="([^"]*)"'
        rf' id="{re.escape(slot.group(1))}"\]$',
        text,
        re.MULTILINE,
    )
    return None if line is None else (line.group(1), line.group(2))


def texture_uid(icon) -> str | None:
    """-> the uid Godot imported the icon under, or None when it isn't imported
    as a texture, because a Texture2D export loads as null from anything else."""
    sidecar = icon.with_name(icon.name + ".import").read_text()
    if 'importer="texture"' not in sidecar:
        return None
    return re.search(r'^uid="([^"]*)"$', sidecar, re.MULTILINE).group(1)


def test_a_run_leaves_every_editor_saved_item_resource_alone(tmp_path, monkeypatch):
    # Each real item name becomes a label, so a step that repoints items by
    # name would reach every one of these files and show up as a change.
    names = [m.group(1) for tres in ITEMS if (m := NAME.search(tres.read_text()))]
    labels = {name: frame for frame, name in enumerate(names, start=1)}
    monkeypatch.setattr(item_icons, "OUT_DIR", tmp_path)
    monkeypatch.setattr(item_icons, "read_swf", lambda swf: None)
    monkeypatch.setattr(timeline, "labels", lambda swf, sprite: labels)
    rect = (0, 0, 200, 200)
    fake_driver(
        monkeypatch,
        [result(20, 20, rect, rect)] * len(labels),
        [(2, 2, 8, 8)] * len(labels),
    )
    before = {tres: stamp(tres) for tres in ITEMS}

    item_icons.main()

    assert [tres.name for tres in ITEMS if stamp(tres) != before[tres]] == []
    assert len(list(tmp_path.glob("*.png"))) == len(labels)


def test_every_named_item_shows_the_icon_extracted_for_its_name():
    icons = {icon.stem.lower(): icon for icon in ICONS.glob("*.png")}
    wrong, no_label = {}, set()
    for tres in ITEMS:
        text = tres.read_text()
        name = NAME.search(text)
        if name is None:
            continue
        icon = icons.get(item_icons.sanitize(name.group(1)).lower())
        if icon is None:
            no_label.add(name.group(1))
            continue
        # Godot resolves a uid before it looks at the path, so a stale uid
        # would load the old texture even with the right path beside it.
        expected = (texture_uid(icon), f"res://assets/ui/items/{icon.name}")
        actual = slot_image_resource(text)
        if actual != expected:
            wrong[tres.name] = actual
    assert wrong == {}
    assert no_label == NO_ICON_LABEL

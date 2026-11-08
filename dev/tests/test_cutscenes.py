# Pins every cutscene to the wrapper the root timeline places on its own
# label's frame, as recorded in label_xref.json, so the mapping can no longer
# shift by one label.
from __future__ import annotations

import json

from urchin_dev.swf.extract.cutscenes import CUTSCENES
from urchin_dev.swf.label_xref import OUT


def test_each_cutscene_uses_the_wrapper_on_its_own_label_frame():
    xref = json.loads(OUT.read_text())
    root = {r["label"]: r for r in xref["labels"] if r["sprite"] == 0}
    for label, (_animation, wrapper, _frames, _overlay) in CUTSCENES.items():
        assert root[label]["places"] == [wrapper], label

# Builds sonny-2-2900.extract.swf: the web SWF with every character deleted
# that the game hides at runtime. Extraction scripts render against this copy
# instead of the original so that ffdec's own renderer - which handles clip
# masks, surface filters and gradient fills correctly, none of which
# shape-by-shape compositing in Python can carry - produces what the player
# actually sees.
#
# The problem this solves: a character can be fully opaque and on top of the
# art in the SWF's own tag data, yet never visible in the running game,
# because ActionScript on its PlaceObject hides it. No static renderer can
# know that without executing the ActionScript, so ffdec draws it, correctly,
# and the export is ruined. Deleting the character from a working copy is the
# cheapest way to tell the renderer what the ActionScript would have.
#
# NEVER add a clip mask to STRIPPED_CHARACTERS. A mask also looks like an
# unwanted shape sitting on top of the art, and removing one silently
# unclips everything it covered. item_icons.py's header records that exact
# mistake being made and reverted: DefineShape 1913 is placed at depth 2 with
# clipDepth="15" on every frame of the item sheet (DefineSprite 2064), it was
# stripped here on the assumption that it was editor scaffolding, and item 69
# "A Broken Pipe" ballooned from a correctly-masked 63x63px to 101x140.
# Before adding an id, confirm its placements carry no clipDepth.
#
# Run: uv run prepare_extract_swf
from __future__ import annotations

import subprocess
import sys

from urchin_dev import FFDEC, WEB_SWF, WEB_SWF_EXTRACT

# characterId -> why the running game never shows it.
#
# Both of these belong to the ability icon sheet (DefineSprite 2427) and are
# the move-cooldown display: a black disc with a turn counter on it, drawn
# over the icon art while an ability is cooling down. Neither is visible on a
# ready ability, which is the state every icon is extracted in.
STRIPPED_CHARACTERS: dict[int, str] = {
    # DefineSprite 2241, placed at depth 11 and named "bfilter" - a fully
    # opaque black disc covering nearly all of the icon art beneath it. Its
    # onLoad clip handler is `if (_parent.dontHide != true) this._visible =
    # false;`, so it hides itself the moment it loads unless the parent asked
    # for the darkened cooldown look. Decoded from the placement's
    # clipActions bytecode: ActionPush "_parent", GetVariable, ActionPush
    # "dontHide", GetMember, Equals2, ActionIf, then ActionPush ("", 7,
    # false) into SetProperty - where property index 7 is _visible.
    2241: "cooldown darkener, hides itself in onLoad",
    # DefineEditText 2245, placed at depth 13, initialText "00", grey
    # (153,153,153). The cooldown turn counter that sits on the disc above.
    # It survives a shape-by-shape compositor only by accident, because an
    # edit text carries `bounds` where a shape carries `shapeBounds` and the
    # bounds lookup returns nothing for it.
    2245: "cooldown turn counter, hidden with its disc",
}


def require_extract_swf():
    """Resolve the prepared extraction SWF, failing with a usable message.

    Kept deliberately dumb: it checks that the file exists and never rebuilds
    it. Rebuild by hand after changing STRIPPED_CHARACTERS or replacing the
    source SWF.
    """
    if not WEB_SWF_EXTRACT.is_file():
        raise SystemExit(
            f"Missing prepared extraction SWF: {WEB_SWF_EXTRACT}\n"
            f"Build it with:\n"
            f"  uv run prepare_extract_swf"
        )
    return WEB_SWF_EXTRACT


def main():
    if not WEB_SWF.is_file():
        raise SystemExit(f"Missing source SWF: {WEB_SWF}")

    ids = sorted(STRIPPED_CHARACTERS)
    cmd = [
        str(FFDEC),
        "-removeCharacter",
        str(WEB_SWF),
        str(WEB_SWF_EXTRACT),
        *(str(cid) for cid in ids),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    if not WEB_SWF_EXTRACT.is_file():
        raise RuntimeError(f"ffdec reported success but wrote no {WEB_SWF_EXTRACT}")

    for cid in ids:
        print(f"stripped {cid}: {STRIPPED_CHARACTERS[cid]}", file=sys.stderr)
    size_mb = WEB_SWF_EXTRACT.stat().st_size / (1024 * 1024)
    print(f"wrote {WEB_SWF_EXTRACT} ({size_mb:.1f} MB)", file=sys.stderr)


if __name__ == "__main__":
    main()

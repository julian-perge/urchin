# The rect record (spec/107-ui-foundation.md, Part 4): where each piece of a
# Screen or Window sits on the Stage in the SWF, written to
#
#   test/fixtures/screen_rects.json
#
# test/unit/test_screen_rects.gd instantiates every scene in the record and
# checks that each piece lands where the record says, after the containers lay
# it out. So a scene can type its numbers into its .tscn, and this record keeps
# them honest.
#
# SCENES is the per-scene config. Each Window or Screen build issue adds its
# scene, the timeline and frame that place its pieces, and one entry for each
# node that draws a piece. port_only names the nodes the port draws and the
# SWF does not, so the test skips them.
#
# A piece has one of these kinds:
#   "point" - a Node2D at a sprite placement, with its position and scale.
#   "centre" - a Control that the port centres on the registration point of
#             a child that a sprite places on its own first frame, found by
#             the child's instance name. A tree node of the Abilities Window is
#             one. It is recorded as that point on the Stage, and as the
#             sprite's DropShadow when it has one, which the port draws as the
#             Control's StyleBoxFlat shadow. The Control's size is the port's
#             own, so the record holds no rect for it.
#   "panel" - a flat Panel (Part 3): a sprite whose one shape has a solid fill
#             and a line, under an inner DropShadow. Its rect is the fill rect
#             grown by half the border. The fill rect is ShapeBounds through
#             the placement matrix, shrunk on each side by half the line width
#             times that axis's scale.
#   "text"  - an edit text, recorded as the rect Flash lays its text out in
#             (label_layout.text_rect), with its font height, colour and
#             alignment.
#   "art"   - a piece drawn from a PNG of extract_window_chrome,
#             extract_start_screens or extract_hotbar_icons, or from the bottom
#             bar of extract_battle_screen, which a TextureRect shows at the
#             rect that render measured, with the PNG's path. The rect and the
#             PNG come from the render's record by the art's name, not from the
#             piece's depth. For art measured from a sprite, the sprite at the
#             piece's depth must be the one the render was measured from. For
#             art measured from the stage, the code only checks that the depth
#             exists on the frame, so a wrong depth there is not caught.
#   "art_set" - art that changes while the game runs, which a TextureRect shows
#             from one of several PNGs that share one rect and one size. The
#             piece's art names the set in art_set_sources: the Store keeper's
#             seven shop PNGs are one, and the battle clock's lit rings
#             another. It is recorded as the rect and size of the shared crop,
#             and the list of PNGs. The piece's depth must hold the character
#             `character`, and the crop's rect is on the Stage already, so the
#             placement matrix is not applied.
#   "face"  - the portrait clip 2978, which the port draws as a TextureRect that
#             shows a different PNG for each fighter. It is recorded as the crop
#             box that extract_faces cut every portrait to, placed with the
#             clip's matrix, and it has no texture.
#   "hit"   - a button that draws nothing, only a hit square, recorded as the
#             hit shape's bounds through the placement matrix.
#   "button" - a button that draws art, which the port draws as a native
#             Button. It is recorded as the bounds of the shapes its up state
#             draws, each through its button record's matrix and then the
#             placement matrix. A hotbar square is one: the port draws its art
#             as an "art" piece and puts a Button on this rect to take clicks.
#   "box"   - a shape of one solid fill and no line, which the port draws as a
#             ColorRect, recorded as its ShapeBounds through the placement
#             matrix with its fill colour.
#   "shape" - a shape that an "art" piece draws with a filter around it, where
#             the port also needs the shape's own rect. It is recorded as the
#             ShapeBounds through the placement matrix, and the port puts a
#             plain Control on it. The zone fill is one: the game scales it
#             from the shape's left edge, and its art is wider than the shape.
#   "inner_shadow" - an overlay that draws the inner DropShadow of a sprite's
#             placement over everything the sprite holds, rows that the game
#             adds while it runs included. The ability pool, sprite 3120, is
#             the one (julian-perge/urchin#190). It is recorded as the rect of
#             the sprite's clip mask, at the piece's inner_depth, and as the
#             shadow's blur, distance and angle, which the overlay's shader
#             takes.
#   "doll"  - the doll that a frame places as loose part clips, which the port
#             draws as one CharacterVisual. It is recorded as the position and
#             scale that put the rig's stand pose where the clips sit, and as
#             the union rect of the unequipped male doll's art (doll_record).
#
# An "art" piece whose render is measured from a sprite of its own is placed
# by where that sprite sits: the sprite at `depth`, or the sprite at
# `inner_depth` inside it. An "art" piece whose render is measured on the Stage
# at another depth, `rendered_at`, is moved by the distance between the two
# placements. The six hotbar squares are one PNG that way.
#
# A piece that a sprite places on its own first frame names the sprite's depth
# and its own inner_depth, and it is measured from where the sprite sits.
# When the sprite's placement carries a DropShadow, Flash shadows every text
# field inside it, so a text piece there records the shadow too.
#
# The record reads the web build, sonny-2-2900.swf. A piece that names a
# `steam` placement is moved to where the Steam build, SONNY2.swf, places it
# on the same frame. The six hotbar slots do: the web build places them 13 px
# higher. Its Armor Games strip 3176 is an overlay under that row and does not
# move the buttons.
#
# A timeline other than the root is measured from where the root's Navigation
# frame places it, which for KRINMENU is (400.50, 222.40).
#
# Run: uv run extract_screen_rects
from __future__ import annotations

import json
import math
import re
import statistics
from dataclasses import dataclass, field

from PIL import Image

from urchin_dev import ACTION_SCRIPT, REPO_ROOT, STEAM_SWF, WEB_SWF
from urchin_dev.swf import label_layout, render, timeline
from urchin_dev.swf.extract import (
    battle_screen,
    faces,
    hotbar_icons,
    start_screens,
    store_art,
    window_chrome,
    zone_hub,
)
from urchin_dev.swf.swf_index import (
    ButtonRecord,
    DropShadow,
    EditText,
    StyleSet,
    SwfIndex,
    button_records,
    character_kind,
    drop_shadow,
    edit_text,
    read_swf,
    shape_bounds,
    shape_styles,
)

RECORD = REPO_ROOT / "test" / "fixtures" / "screen_rects.json"
CHROME_TEXTURES = "res://assets/ui/window"
MENU_TEXTURES = "res://assets/ui/menu"
BATTLE_TEXTURES = "res://assets/ui/battle"
HOTBAR_TEXTURES = "res://assets/ui/hotbar"
STORE_TEXTURES = "res://assets/ui/store/backdrops"
# The menu art, by the record that extract_start_screens writes beside each PNG.
MENU_ART = {
    "logo": start_screens.LOGO_RECORD,
    "start_background": start_screens.BACKGROUND_RECORD,
}
KRINMENU = 3142
HUB_FRAME = "Navigation"
# The Inventory frame places its doll as 31 loose clips with the characters 121
# to 143: 15 male parts, the same 15 with an _f suffix for a female doll, and
# the ground shadow 143. The menu script shows one of the two sets
# (updateDoll) and attaches the art at run time.
DOLL_CHARACTERS = range(121, 144)
DOLL_SCRIPT = f"DefineSprite_{KRINMENU}/frame_1/DoAction.as"
# The rig's part origins and the art's bounds, which the port's CharacterVisual
# reads. The rig's stand label starts on its first frame, and that frame is
# the pose the menu doll holds.
RIG_ANIMATIONS = REPO_ROOT / "resources" / "sprites" / "model1_animations.json"
DOLL_OFFSETS = REPO_ROOT / "resources" / "sprites" / "doll_offsets.json"
# The player's look, which the record's union rect is drawn for: male, skin
# ONE and hair ONE (combat_unit.gd gives the player ["MODEL1", "ONE", "ONE",
# "M"], from the seeds in frame_42).
DOLL_LOOK = {"gender": "M", "skin": "ONE", "hair": "ONE"}
# How far a placed part's scale and rotation may be from the rig's stand pose
# times the doll's mirrored scale, as a difference of matrix entries.
DOLL_MATRIX_TOLERANCE = 0.005


@dataclass(frozen=True)
class Piece:
    kind: str
    # The depth that places the piece, or None when `instance` finds it.
    depth: int | None
    art: str | None = None
    # The instance name of the placement, for a piece that the SWF names
    # instead of a depth the record has to type, such as itemSlot0.
    instance: str | None = None
    # The depth of the piece inside the sprite at `depth`, on the sprite's
    # first frame, for a piece that the scene's timeline does not place itself.
    inner_depth: int | None = None
    # The depth whose placement the art was rendered from. A Stage render moves
    # by the placement difference. A sprite-local render uses this depth's
    # sprite as its source and the current placement as its origin.
    rendered_at: int | None = None
    # The depth, or the instance name, that places the same piece on the same
    # frame of the Steam build, for a piece the port puts where that build does.
    steam: int | str | None = None
    # The id of the character the placement must hold. A piece whose depth
    # the record types by hand names it, so a depth that points at another
    # character fails here and not in a rect that moved with it.
    character: int | None = None
    # The 0-based stroked path, from the top down, of an outline shape that
    # draws several boxes with one line, for a piece the port builds as one
    # Panel for each box. A "shape" piece with a path is that box's stroke
    # centre line.
    path: int | None = None
    # The depths that lead from the placement at `depth` down to the piece, one
    # for each sprite on the way: each is read on the first frame of the sprite
    # that the step before it reached. `inner_depth` is the same for one step.
    via: tuple[int, ...] = ()
    # For a "centre": the instance name of the child inside the sprite, such
    # as st0 inside talenttreefull.
    inner_instance: str | None = None
    # For a "doll": whether the frame places the female set of the 15 parts
    # next to the male one. The Inventory frame does and the shop frame does not.
    female_set: bool = True

    def __post_init__(self) -> None:
        if (self.depth is None) == (self.instance is None):
            raise ValueError(
                f"A piece needs a depth or an instance name, not both or neither:"
                f" depth {self.depth}, instance {self.instance}"
            )
        if self.kind in ("art", "art_set") and self.art is None:
            raise ValueError(
                f"An {self.kind} piece needs the name of its art: depth {self.depth},"
                f" instance {self.instance}"
            )
        if self.kind == "centre" and self.inner_instance is None:
            raise ValueError(
                f"A centre piece needs the inner_instance of its child: depth"
                f" {self.depth}, instance {self.instance}"
            )


@dataclass(frozen=True)
class Scene:
    timeline: int
    frame: str
    pieces: dict[str, Piece]
    port_only: tuple[str, ...] = field(default=())
    # The depths of the frame whose characters the port leaves out by an ADR.
    # The compare tool takes them out of its reference too.
    left_out: tuple[int, ...] = field(default=())
    # Characters excluded from a static chrome score, such as the fade and orbs.
    compare_strip: tuple[int, ...] = field(default=())


# The victory frame's experience rows, top to bottom, by the depth that
# places each, and the pieces inside sprite 3002 by their own depth.
VICTORY_ROWS = {"PlayerSlot": 1197, "CompanionSlot0": 1111, "CompanionSlot1": 1154}
VICTORY_ROW_PIECES: dict[str, tuple[str, int, str | None]] = {
    "Frame": ("art", 2, "victory_row"),
    "Face": ("face", 3, None),
    "NameLabel": ("text", 37, None),
    "LevelLabel": ("text", 38, None),
    "Bar": ("art", 39, "xp_bar"),
    "Gloss": ("art", 41, "xp_gloss_victory"),
    "PercentLabel": ("text", 42, None),
}

# The Inventory frame places the element bar block, sprite 2877, twice: perBarShow
# for the piercing bars and defBarShow for the defense bars. The block holds
# eight bars, each as a track and four layers. A layer of bar k is at the
# depth `first + 2 * k` of the block, and every layer of a bar draws the same
# 11x68 rect until the menu script sets its height.
BAR_BLOCKS = {"PerBars": "perBarShow", "DefBars": "defBarShow"}
BAR_TRACK_DEPTH = 1
BAR_LAYER_DEPTHS = {"Ybar": 17, "Bar": 34, "Gbar": 50, "Xbar": 66}
BAR_COUNT = 8

# The Inventory frame places the six party faces, sprite 2979, as fa0 to fa5. A
# face holds its parts at these depths of its own first frame: the black backing
# (shape 333), the face clip under its mask, the dim that a member outside the
# Deployed pair keeps (`blacker`, sprite 2896), the hit button and the selection
# frame (sprite 2893, drawn by the art "party_frame").
PARTY_FACES = 6
PARTY_FACE_PIECES = {
    "Backing": lambda n: Piece("box", None, instance=f"fa{n}", inner_depth=1),
    "Face": lambda n: Piece("face", None, instance=f"fa{n}", inner_depth=2),
    "Blacker": lambda n: Piece("box", None, instance=f"fa{n}", inner_depth=36),
    "HitButton": lambda n: Piece("hit", None, instance=f"fa{n}", inner_depth=38),
    "Frame": lambda n: Piece("art", None, art="party_frame", instance=f"fa{n}"),
}

# The skills frame's tree 'talenttreefull' names its nodes st0 to st27, and
# the ring 'selector' names its sockets thing0 to thing7.
TREE_NODES = 28
RING_SOCKETS = 8

# The frame names the grid's slots itemSlot0 to itemSlot35, row by row.
INVENTORY_SLOTS = 36
INVENTORY_COLUMNS = 6

# The title frame's pieces, by their path in title_panel.tscn
# (spec/107-title-slots.md, The title). The SWF places the Play caption twice,
# 2699 at depth 8 with no filter and 2696 at depth 11 with the caption's Glow
# and DropShadow, at one spot. The port draws one Label for both. The frame
# also places "Play More Games!" and "Play the Original Sonny" at depths 10 and
# 12, the Armor Games line at depth 38 and its logo at depth 41, which the port
# leaves out (docs/adr/0002-leave-out-the-armor-games-branding.md).
TITLE_FRAME = "mainMenu"
TITLE_PIECES = {
    "Logo": Piece("art", 6, art="logo"),
    "Captions/PlaySlot/Caption": Piece("text", 11),
    "Captions/PlaySlot/HitButton": Piece("hit", 18),
    "Captions/GameManualSlot/Caption": Piece("text", 9),
    "Captions/GameManualSlot/HitButton": Piece("hit", 14),
    "Captions/CreditsSlot/Caption": Piece("text", 13),
    "Captions/CreditsSlot/HitButton": Piece("hit", 22),
}

# The choice frame's pieces, by their path in mode_panel.tscn
# (spec/107-title-slots.md, The choice). The frame also places "PvP Arena" at
# depth 14 and its hit button at depth 15, which the port leaves out
# (docs/adr/0006-leave-out-the-pvp-arena.md).
CHOICE_FRAME = "subMenu"
CHOICE_PIECES = {
    "Logo": Piece("art", 6, art="logo"),
    "Captions/NewGameSlot/Caption": Piece("text", 8),
    "Captions/NewGameSlot/HitButton": Piece("hit", 10),
    "Captions/LoadGameSlot/Caption": Piece("text", 9),
    "Captions/LoadGameSlot/HitButton": Piece("hit", 12),
}

# The six hotbar slots that share the 0.671 square, by their slot node in
# hotbar.tscn: the depth of the slot's button and the name of its icon art
# (spec/107-hub.md, The hotbar). The button draws the square, so the square's
# art and the hit rect are two pieces at one depth. The second depth is the
# same button's in the Steam build, whose row the port uses.
HOTBAR_SLOTS: dict[str, tuple[int, int, str]] = {
    "Inventory": (126, 126, "inventory"),
    "Abilities": (128, 128, "abilities"),
    "Save": (130, 130, "save"),
    "Options": (136, 136, "options"),
    "Respec": (138, 138, "respec"),
    "Achievements": (165, 157, "achievements"),
}
if (
    tuple(depth for depth, _steam, _icon in HOTBAR_SLOTS.values())
    != window_chrome.SQUARE_DEPTHS
):
    raise ValueError("HOTBAR_SLOTS and window_chrome.SQUARE_DEPTHS disagree")


def hotbar_icon(name: str, *, steam: bool = False) -> Piece:
    instance = hotbar_icons.ICONS[name]
    return Piece(
        "art", None, art=name, instance=instance, steam=instance if steam else None
    )


HOTBAR_PIECES = {
    "BottomBar": Piece("art", 1, art="bottom_bar"),
    **{
        f"{slot}Slot/{node}": piece
        for slot, (depth, steam, icon) in HOTBAR_SLOTS.items()
        for node, piece in {
            "Square": Piece(
                "art",
                depth,
                art="hotbar_square",
                rendered_at=window_chrome.SQUARE_DEPTHS[0],
                steam=steam,
            ),
            "Icon": hotbar_icon(icon, steam=True),
            f"{slot}Button": Piece("button", depth, steam=steam),
        }.items()
    },
    "ZoneMapSlot/Square": Piece(
        "art", window_chrome.WORLD_MAP_DEPTH, art="hotbar_world_map"
    ),
    "ZoneMapSlot/Icon": hotbar_icon("world_map"),
    "ZoneMapSlot/ZoneMapButton": Piece("button", window_chrome.WORLD_MAP_DEPTH),
    "QuitSlot/Square": Piece("art", window_chrome.QUIT_DEPTH, art="hotbar_quit"),
    "QuitSlot/Red": Piece("art", window_chrome.QUIT_RED_DEPTH, art="hotbar_quit_red"),
    "QuitSlot/QuitButton": Piece("button", window_chrome.QUIT_DEPTH),
    # The zone progress bar 3149 holds the track and the fill. The game sets the
    # fill's width (frame_181/DoAction.as:11), so ZoneFill is the fill's shape,
    # which hotbar.gd scales, and its Art is the fill's render at full width.
    "ZoneTrack": Piece("art", window_chrome.ZONE_BAR_ROOT_DEPTH, art="zone_track"),
    "ZoneFill": Piece(
        "shape",
        window_chrome.ZONE_BAR_ROOT_DEPTH,
        inner_depth=window_chrome.ZONE_BAR_FILL_DEPTH,
    ),
    "ZoneFill/Art": Piece("art", window_chrome.ZONE_BAR_ROOT_DEPTH, art="zone_fill"),
    "ZoneTitleSlot/ZoneTitle": Piece("text", 173),
    "ZoneSubtitleSlot/ZoneSubtitle": Piece("text", 174),
    "StageSlot/StageLabel": Piece("text", 172),
}

# The slot list frame's pieces, by their path in slot_panel.tscn
# (spec/107-title-slots.md, The slot list). Each row is the "Slot" caption, the
# slot's number, the save's name and one hit button over the first two. The
# frame also places the arena's pick text at depth 26, which the port leaves
# out (docs/adr/0006-leave-out-the-pvp-arena.md).
SLOTS_FRAME = "dataMenu"
SLOT_ROW_DEPTHS = {
    "Row1": {"SlotLabel": 6, "Number": 14, "SaveName": 7, "HitButton": 18},
    "Row2": {"SlotLabel": 11, "Number": 15, "SaveName": 8, "HitButton": 20},
    "Row3": {"SlotLabel": 12, "Number": 16, "SaveName": 9, "HitButton": 22},
    "Row4": {"SlotLabel": 13, "Number": 17, "SaveName": 10, "HitButton": 24},
}
SLOT_PIECES = {
    f"Rows/{row}/{node}": Piece("hit" if node == "HitButton" else "text", depth)
    for row, depths in SLOT_ROW_DEPTHS.items()
    for node, depth in depths.items()
}

SCENES: dict[str, Scene] = {
    # The victory frame's left Panel and the field at its top. It is a test
    # scene, so the generic test and its must-fail control have a scene to run.
    "res://test/fixtures/screen_rects/victory_left_panel.tscn": Scene(
        timeline=KRINMENU,
        frame="win",
        pieces={
            "LeftPanel": Piece("panel", 11),
            "LeftPanel/Heading": Piece("text", 1240),
        },
    ),
    # One ShellPanel of each fill, where the inventory frame places them, so
    # the test checks each fill against its sprite: 2990 is tall, 2992 is bar
    # and 2988 is centre.
    "res://test/fixtures/screen_rects/shell_panel_fills.tscn": Scene(
        timeline=KRINMENU,
        frame="inventory",
        pieces={
            "Tall": Piece("panel", 11),
            "Bar": Piece("panel", 5),
            "Centre": Piece("panel", 21),
        },
    ),
    # The 1 px line 2995 at depth 1 is not drawn (spec/107-window-shell.md).
    "res://scenes/ui/window/window_shell.tscn": Scene(
        timeline=KRINMENU,
        frame="inventory",
        pieces={
            "Backdrop": Piece("art", window_chrome.BACKDROP_DEPTH, art="backdrop"),
            "CloseArt": Piece("art", window_chrome.CLOSE_X_DEPTH, art="close_x"),
            "CloseButton": Piece("hit", 1434),
        },
    ),
    # The right column of 36 item slots and the money bar
    # (spec/107-window-shell.md, RightColumn). The shop frame is the one frame
    # that places all of it, the sell slot included, and the inventory frame
    # places the other pieces at the same depths. The euro sign and the amount
    # carry a Glow and a DropShadow filter. A Label can't draw either, so the
    # record leaves the two filters out and the port draws neither.
    "res://scenes/ui/window/right_column.tscn": Scene(
        timeline=KRINMENU,
        frame="shop",
        pieces={
            "TallPanel": Piece("panel", 7),
            "Title": Piece("text", 1430),
            **{
                f"Grid/Row{i // INVENTORY_COLUMNS}/Slot{i % INVENTORY_COLUMNS}": Piece(
                    "art", None, art="slot_inventory", instance=f"itemSlot{i}"
                )
                for i in range(INVENTORY_SLOTS)
            },
            "BarPanel": Piece("panel", 5),
            "EuroSign": Piece("text", 1424),
            "Amount": Piece("text", 1423),
            "SellSlot/Art": Piece(
                "art", window_chrome.SELL_SLOT_DEPTH, art="sell_slot"
            ),
            "DeleteSlot/Art": Piece(
                "art", window_chrome.DELETE_SLOT_DEPTH, art="delete_slot"
            ),
        },
        # SellSlot and DeleteSlot are Buttons that draw only a hover highlight over
        # the art. Their Art children are pieces, so the test still checks them.
        port_only=(
            "SellSlot",
            "DeleteSlot",
            *(
                f"Grid/Row{i // INVENTORY_COLUMNS}/Slot{i % INVENTORY_COLUMNS}/{node}"
                for i in range(INVENTORY_SLOTS)
                for node in ("ItemIcon", "Highlight")
            ),
        ),
    ),
    # The skills frame (spec/107-abilities.md). StatusLabel has no piece in the
    # SWF, and the icon and rank text on each tree node are the port's own. The
    # ability pool is sprite 3120, `talentPool`. Its clip mask 3117 at depth 1
    # clips the backing 3119 at depth 2 and the rows the game adds to
    # talentPool2 at depth 3. The frame 3116 at depth 7 and the scroll buttons
    # at depths 8 and 11 sit outside the mask. The pool's rows are the port's
    # own design (ADR 0007), so they have no piece.
    "res://scenes/ui/menu/abilities_window.tscn": Scene(
        timeline=KRINMENU,
        frame="skills",
        pieces={
            "WindowShell/Backdrop": Piece(
                "art", window_chrome.BACKDROP_DEPTH, art="backdrop"
            ),
            "WindowShell/CloseArt": Piece(
                "art", window_chrome.CLOSE_X_DEPTH, art="close_x"
            ),
            "WindowShell/CloseButton": Piece("hit", 1434),
            "TreePanel": Piece("panel", 7),
            "PointsPanel": Piece("panel", 23),
            "AttributesPanel": Piece("panel", 21),
            "ActionPanel": Piece("panel", 5),
            "TreeTitle": Piece("text", 673),
            "ActionBarTitle": Piece("text", 672),
            "PoolTitle": Piece("text", 674),
            "AttributesTitle": Piece("text", 671),
            "NameLabel": Piece("text", 653),
            "LevelLabel": Piece("text", 654),
            "AbilityPointsLabel": Piece("text", 651),
            "AbilityPointsValue": Piece("text", 655),
            "AttributePointsLabel": Piece("text", 652),
            "AttributePointsValue": Piece("text", 656),
            "HintLabel": Piece("text", 675, inner_depth=1),
            "PlusColumn/VitalitySlot/VitalityPlus": Piece("button", 668),
            "PlusColumn/StrengthSlot/StrengthPlus": Piece("button", 659),
            "PlusColumn/InstinctSlot/InstinctPlus": Piece("button", 662),
            "PlusColumn/SpeedSlot/SpeedPlus": Piece("button", 665),
            "AttributeRows/VitalityRow/VitalityLabel": Piece("text", 643),
            "AttributeRows/StrengthRow/StrengthLabel": Piece("text", 644),
            "AttributeRows/InstinctRow/InstinctLabel": Piece("text", 645),
            "AttributeRows/SpeedRow/SpeedLabel": Piece("text", 646),
            "AttributeRows/VitalityRow/VitalityValue": Piece("text", 647),
            "AttributeRows/StrengthRow/StrengthValue": Piece("text", 648),
            "AttributeRows/InstinctRow/InstinctValue": Piece("text", 649),
            "AttributeRows/SpeedRow/SpeedValue": Piece("text", 650),
            **{
                f"TreeNodes/Node{n}": Piece(
                    "centre", None, instance="talenttreefull", inner_instance=f"st{n}"
                )
                for n in range(TREE_NODES)
            },
            **{
                f"Socket{n}": Piece(
                    "centre", None, instance="selector", inner_instance=f"thing{n}"
                )
                for n in range(RING_SOCKETS)
            },
            "Pool": Piece("shape", None, instance="talentPool", inner_depth=1),
            "Pool/Mask": Piece("shape", None, instance="talentPool", inner_depth=1),
            "Pool/Mask/Backing": Piece(
                "box", None, instance="talentPool", inner_depth=2
            ),
            "Pool/Frame": Piece("art", None, art="pool_frame", instance="talentPool"),
            "Pool/ScrollUpButton": Piece(
                "button", None, instance="talentPool", inner_depth=8
            ),
            "Pool/ScrollDownButton": Piece(
                "button", None, instance="talentPool", inner_depth=11
            ),
            "Pool/Shadow": Piece(
                "inner_shadow", None, instance="talentPool", inner_depth=1
            ),
        },
        port_only=(
            "StatusLabel",
            "Pool/Mask/Rows",
            *(
                f"TreeNodes/Node{n}/{node}"
                for n in range(TREE_NODES)
                for node in ("IconRect", "RankLabel")
            ),
        ),
        # The compare tool scores the panels and the pool's chrome. The tree
        # 3100, the ring 3109, the plus buttons 3068 to 3071 with their colour
        # plates statColor 3075, and the scroll buttons 3114 and 3115 are left
        # to the rect test. The port draws them as native Buttons and
        # code-drawn nodes with a look of its own (ADR 0007), and the capture
        # hides them.
        compare_strip=(3100, 3109, 3068, 3069, 3070, 3071, 3075, 3114, 3115),
    ),
    # The background that every menu frame from mainMenu to endMenu places at
    # depths 1, 2 and 5: the backdrop 2701, the swirl 307 and the splatter 2700.
    # extract_start_screens renders the three as one PNG of the whole Stage, so
    # the piece names the first of them. The scene's root is the piece.
    "res://scenes/ui/menu/menu_background.tscn": Scene(
        timeline=0,
        frame=TITLE_FRAME,
        pieces={".": Piece("art", 1, art="start_background")},
    ),
    # Back, which every menu frame after the title places at depths 35 and 36.
    # subMenu is the first of them.
    "res://scenes/ui/menu/menu_back.tscn": Scene(
        timeline=0,
        frame=CHOICE_FRAME,
        pieces={"Caption": Piece("text", 35), "HitButton": Piece("hit", 36)},
    ),
    "res://scenes/ui/menu/mode_panel.tscn": Scene(
        timeline=0, frame=CHOICE_FRAME, pieces=CHOICE_PIECES
    ),
    # The choice as the menu shows it: the background, the choice and Back. The
    # menu opens on the title, and a capture shows a scene as it opens, so the
    # compare tool scores this scene against the choice frame. Depths 38 and 41
    # are the Armor Games line and logo, as on the title. PvP Arena is left out
    # too, and is not listed, because an edit text and a hit button draw nothing
    # in the reference.
    "res://test/fixtures/screen_rects/choice_screen.tscn": Scene(
        timeline=0,
        frame=CHOICE_FRAME,
        pieces={
            "Background": Piece("art", 1, art="start_background"),
            **{f"ModePanel/{path}": piece for path, piece in CHOICE_PIECES.items()},
            "Back/Caption": Piece("text", 35),
            "Back/HitButton": Piece("hit", 36),
        },
        left_out=(38, 41),
    ),
    "res://scenes/ui/menu/slot_panel.tscn": Scene(
        timeline=0, frame=SLOTS_FRAME, pieces=SLOT_PIECES
    ),
    # The slot list as the menu shows it: the background, the rows and Back,
    # for the compare tool, as choice_screen.tscn is for the choice. Depths 38
    # and 41 are the Armor Games line and logo, as on the title.
    "res://test/fixtures/screen_rects/slots_screen.tscn": Scene(
        timeline=0,
        frame=SLOTS_FRAME,
        pieces={
            "Background": Piece("art", 1, art="start_background"),
            **{f"SlotPanel/{path}": piece for path, piece in SLOT_PIECES.items()},
            "Back/Caption": Piece("text", 35),
            "Back/HitButton": Piece("hit", 36),
        },
        left_out=(38, 41),
    ),
    "res://scenes/ui/menu/title_panel.tscn": Scene(
        timeline=0, frame=TITLE_FRAME, pieces=TITLE_PIECES
    ),
    # The menu opens on the title, so it is the scene the compare tool scores
    # against the title frame, and the record checks that its instances of the
    # background and the title land where their own scenes put them. The other
    # panels stand for later frames. Depth 38 is the Armor Games copyright line
    # and depth 41 its logo. The two publisher links at depths 10, 12, 16 and
    # 20 are left out too, and are not listed, because they draw nothing in the
    # reference: chrome mode strips every edit text, and a hit button has no
    # art.
    "res://scenes/main_menu.tscn": Scene(
        timeline=0,
        frame=TITLE_FRAME,
        pieces={
            "Background": Piece("art", 1, art="start_background"),
            **{f"TitlePanel/{path}": piece for path, piece in TITLE_PIECES.items()},
        },
        port_only=(
            "ModePanel",
            "NamePanel",
            "SlotPanel",
            "NewGamePanel",
            "OptionsPanel",
        ),
        left_out=(38, 41),
    ),
    # The bottom bar body 3317, which the hub frame and the battle frame both
    # place at depth 1 (spec/107-hub.md, The bottom bar body). The scene's root
    # is the piece.
    "res://scenes/ui/bottom_bar.tscn": Scene(
        timeline=0, frame=HUB_FRAME, pieces={".": Piece("art", 1, art="bottom_bar")}
    ),
    # The hotbar on the bottom bar. Each Glow and InnerGlow holds the port's
    # hover, which the SWF draws as Glow filters on the icon. Depth 144 is the
    # Armor Games strip 3176.
    "res://scenes/ui/hotbar.tscn": Scene(
        timeline=0,
        frame=HUB_FRAME,
        pieces=HOTBAR_PIECES,
        port_only=(
            *(
                f"{slot}Slot/{holder}"
                for slot in (*HOTBAR_SLOTS, "ZoneMap")
                for holder in ("Glow", "InnerGlow")
            ),
        ),
        left_out=(144,),
    ),
}


ZONE_SCENES = (
    "zone1_prison",
    "zone2_village",
    "zone3_train",
    "zone4_tunnels",
    "zone5_city",
    "zone6_rome",
    "zone7_shotul",
)
# Each pair names the orb depth and its button depth on the zone's frame.
# Zone 7 has no training orb, because every frame under the JAPAN label places
# a story orb and a shop orb only. The ROME training button at depth 56 is
# removed at frame 86 and nothing replaces it.
ZONE_ORBS = (
    {"StoryFight": (27, 48), "ItemStore": (31, 50), "TrainingFight": (35, 56)},
    {"StoryFight": (27, 48), "ItemStore": (31, 50), "TrainingFight": (35, 56)},
    {"StoryFight": (27, 48), "ItemStore": (31, 50), "TrainingFight": (52, 56)},
    {"StoryFight": (27, 48), "ItemStore": (31, 50), "TrainingFight": (52, 56)},
    {"StoryFight": (27, 48), "ItemStore": (31, 50), "TrainingFight": (52, 56)},
    {"StoryFight": (27, 31), "ItemStore": (58, 62), "TrainingFight": (52, 56)},
    {"StoryFight": (26, 30), "ItemStore": (32, 36)},
)
# The info spots of zones 1 to 5, by the number n of the NAVTITLE[n] and
# NAVTEXT[n] that the spot's press shows, each as (depth, button id). The
# buttons hold a hit shape and nothing else, and the zone's frame places no
# orb sprite on them. Neither the depth nor the button id runs in the order of
# n, so dev/tests/test_screen_rects.py reads each button's press script for its
# n. Zones 6 and 7 have none.
ZONE_SPOTS = (
    {1: (39, 3193), 2: (41, 3192), 3: (43, 3191), 4: (45, 3190)},
    {5: (66, 3207), 6: (64, 3208), 7: (60, 3210), 8: (62, 3209), 9: (58, 3211)},
    {10: (58, 3218), 11: (62, 3216), 12: (60, 3217), 13: (64, 3215)},
    {14: (58, 3237), 15: (62, 3235), 16: (60, 3236)},
    {17: (60, 3201), 18: (58, 3202), 19: (62, 3200), 20: (64, 3199)},
    {},
    {},
)
for zone, (slug, orbs, spots) in enumerate(
    zip(ZONE_SCENES, ZONE_ORBS, ZONE_SPOTS, strict=True), 1
):
    SCENES[f"res://scenes/zones/{slug}.tscn"] = Scene(
        timeline=zone_hub.HUB_SPRITE,
        frame=zone_hub.ZONE_LABELS[zone],
        pieces={
            "HubArt": Piece(
                "art", next(iter(orbs.values()))[0], art=zone_hub.ZONE_LABELS[zone]
            ),
            **{name: Piece("point", depths[0]) for name, depths in orbs.items()},
            **{
                f"{name}/Control": Piece("hit", depths[1])
                for name, depths in orbs.items()
            },
            **{
                f"InfoSpot{n}": Piece("hit", depth, character=button)
                for n, (depth, button) in spots.items()
            },
        },
        port_only=tuple(
            f"{name}/{part}"
            for name in orbs
            for part in ("bottom", "middle", "top", "CollisionShape2D")
        ),
    )


# The info card krinNavFadeSpeech (2848) is placed once on the hub frame and
# holds the dim, the frame's sprite, the close prompt and its hit button
# (spec/107-hub.md, The info card). The title and the text are placed on the
# frame itself at depths 1659 and 1658, outside the sprite. The frame's and the
# face's art are two renders of one sprite, because the shadow on the face is
# its own (extract_window_chrome).
SCENES["res://scenes/ui/hub_card.tscn"] = Scene(
    timeline=0,
    frame=HUB_FRAME,
    pieces={
        "Dim": Piece(
            "box", window_chrome.CARD_DEPTH, inner_depth=window_chrome.CARD_DIM_DEPTH
        ),
        "Frame": Piece("art", window_chrome.CARD_DEPTH, art="hub_card_frame"),
        "Face": Piece("art", window_chrome.CARD_DEPTH, art="hub_card_face"),
        "Title": Piece("text", 1659),
        "Body": Piece("text", 1658),
        "Prompt": Piece(
            "text",
            window_chrome.CARD_DEPTH,
            inner_depth=window_chrome.CARD_PROMPT_DEPTH,
        ),
        "CloseButton": Piece(
            "hit", window_chrome.CARD_DEPTH, inner_depth=window_chrome.CARD_CLOSE_DEPTH
        ),
    },
)


# This fixture scores the static Hub chrome. Animated orbs are checked by the
# zone records, and the Windows, banners and card have their own build tasks.
HUB_CHROME = "res://test/fixtures/screen_rects/hub_chrome.tscn"
SCENES[HUB_CHROME] = Scene(
    timeline=0,
    frame=HUB_FRAME,
    pieces={
        "HubArt": Piece("art", 59, art="PRISON"),
        **{f"Hotbar/{path}": piece for path, piece in HOTBAR_PIECES.items()},
    },
    port_only=tuple(
        f"Hotbar/{path}" for path in SCENES["res://scenes/ui/hotbar.tscn"].port_only
    ),
    left_out=(144,),
    compare_strip=(2837, 2836, 2848, 2839, 2840, 2717, 2852, 3142, 3196, 3312),
)


# The Inventory record covers #226's shell and left panel, #227's doll and
# experience row, #228's stat rows and #231's party faces. #230's element bars are two
# blocks, each a shade over the eight bars and a row of bars with a track and
# four layers (BAR_LAYER_DEPTHS). The shade is the one shape 2874, which fills
# all eight bars with a gradient, so it is one piece for each block.
# The frame places the doll as 31 clips, which depth 912 names by the ground
# shadow 143, and the port draws as the one Doll. The port draws no ground
# shadow. The experience fill is the sprite 2867 on its first frame, which the
# game scales to the experience, and its gloss is the shape 2864.
INVENTORY_SCENE = "res://scenes/ui/menu/inventory_window.tscn"
SCENES[INVENTORY_SCENE] = Scene(
    timeline=KRINMENU,
    frame="inventory",
    pieces={
        **{
            f"WindowShell/{node}": piece
            for node, piece in SCENES[
                "res://scenes/ui/window/window_shell.tscn"
            ].pieces.items()
        },
        "LeftPanel": Piece("panel", 11),
        "PartyBar": Piece("panel", 9),
        "CenterPanel": Piece("panel", 21),
        # Shape 2980 draws three stacked boxes with one line: the stats, the
        # piercing bars and the defense bars.
        "CenterPanel/Content/StatsOutline": Piece("outline", 994, path=0),
        "CenterPanel/Content/PiercingOutline": Piece("outline", 994, path=1),
        "CenterPanel/Content/DefenseOutline": Piece("outline", 994, path=2),
        **{
            f"{block}/Shade": Piece("art", None, art="bar_shade", instance=instance)
            for block, instance in BAR_BLOCKS.items()
        },
        **{
            f"{block}/Bars/Bar{k}/{node}": Piece(
                kind, None, instance=instance, inner_depth=first + 2 * k
            )
            for block, instance in BAR_BLOCKS.items()
            for k in range(BAR_COUNT)
            for node, kind, first in (
                ("Track", "box", BAR_TRACK_DEPTH),
                *((layer, "shape", depth) for layer, depth in BAR_LAYER_DEPTHS.items()),
            )
        },
        **{
            f"PartyFaces/Face{n}/Parts/{node}": piece(n)
            for n in range(PARTY_FACES)
            for node, piece in PARTY_FACE_PIECES.items()
        },
        "LeftPanel/Content/Header/NameRow/NameLabel": Piece("text", 1241),
        "LeftPanel/Content/Header/InfoRow/LevelLabel": Piece("text", 1242),
        "LeftPanel/Content/EquipDollView/Doll": Piece("doll", 912, character=143),
        "ExperienceLabel": Piece("text", 1417),
        "ExpLeftBox": Piece("box", 1418),
        "ExpFill": Piece("art", 1419, art="xp_bar"),
        "ExpGloss": Piece("art", 1421, art="xp_gloss"),
        "ExpPercent": Piece("text", 1422),
        # The menu script fills the five names with SYSTEM[0] to [4] plus ":",
        # and the five values with the stats of the selected member.
        **{
            f"CenterPanel/Content/Stat{column}/Row{i}/Label": Piece(
                "text", first + i, character=character - i
            )
            for column, first, character in (
                ("Names", 1243, 2889),
                ("Values", 1248, 2884),
            )
            for i in range(5)
        },
        **{
            f"LeftPanel/Content/EquipDollView/Slot{i}": Piece(
                "art",
                None,
                art="slot_inventory",
                instance=f"playerSlot{i}",
                rendered_at=30,
            )
            for i in range(7)
        },
        # The compare tool's panels mode takes only pieces that are placed by
        # a depth, so each grid slot is named here by its depth and not by its
        # instance name. The frame places itemSlot n at depth 30 + 21 * n.
        **{
            f"RightColumn/{node}": (
                Piece(
                    "art",
                    30 + 21 * int(piece.instance.removeprefix("itemSlot")),
                    art=piece.art,
                )
                if piece.instance is not None
                else piece
            )
            for node, piece in SCENES[
                "res://scenes/ui/window/right_column.tscn"
            ].pieces.items()
            if not node.startswith("SellSlot")
        },
    },
    port_only=(
        "LeftPanel/Content/StatusLabel",
        "LeftPanel/Content/EquipDollView/Doll/Body",
        *(
            f"LeftPanel/Content/EquipDollView/Slot{i}/{node}"
            for i in range(7)
            for node in ("ItemIcon", "Highlight")
        ),
        "PiercingLabel",
        "DefenseLabel",
        # Each Gbar and Xbar draws its Glow behind itself, on a node that is
        # larger than the bar.
        *(
            f"{block}/Bars/Bar{k}/{layer}/Glow"
            for block in BAR_BLOCKS
            for k in range(BAR_COUNT)
            for layer in ("Gbar", "Xbar")
        ),
        *(
            f"RightColumn/{node}"
            for node in SCENES["res://scenes/ui/window/right_column.tscn"].port_only
        ),
    ),
)


# The shop frame (spec/107-store.md). Its left panel holds the keeper's scene,
# sprite 3036 at depth 25, which the port draws as one TextureRect of the shop's
# PNG, and the keeper's line, the edit text 3019 (vb2). The centre bottom panel
# holds the hint, the edit text 3018 (vb1), and the 15 wares, sprite 3013 as
# dropSlot0 to dropSlot14, drawn with the art of the inventory slot 2986. The
# first piece of the frame's grid, itemSlot0 at depth 30, is the sprite that
# art was rendered from. The 7 equip slots, sprite 2984 scaled to 0.86, use the
# same art at that scale. The frame places the doll as 16 clips, the 15 male
# parts and the ground shadow 143 at depth 1229, and the port draws it as the
# one Doll, with no ground shadow. StatusLabel has no piece in the SWF.
STORE_SCENE = "res://scenes/ui/store/store_window.tscn"
STORE_WARES = 15
STORE_WARE_COLUMNS = 5
STORE_EQUIP_SLOTS = 7
SCENES[STORE_SCENE] = Scene(
    timeline=KRINMENU,
    frame="shop",
    pieces={
        **{
            f"WindowShell/{node}": piece
            for node, piece in SCENES[
                "res://scenes/ui/window/window_shell.tscn"
            ].pieces.items()
        },
        "LeftPanel": Piece("panel", 11),
        "CentreTopPanel": Piece("panel", 21),
        "CentreBottomPanel": Piece("panel", 23),
        "LeftPanel/Content/KeeperArt": Piece(
            "art_set", 25, art="store_keeper", character=3036
        ),
        "LeftPanel/Content/KeeperLine": Piece("text", 1101, character=3019),
        "CentreBottomPanel/Content/Hint": Piece("text", 1102, character=3018),
        "CentreTopPanel/Content/EquipDollView/Doll": Piece(
            "doll", 1229, character=143, female_set=False
        ),
        **{
            f"CentreTopPanel/Content/EquipDollView/Slot{i}": Piece(
                "art",
                None,
                art="slot_inventory",
                instance=f"playerSlot{i}",
                rendered_at=30,
            )
            for i in range(STORE_EQUIP_SLOTS)
        },
        **{
            f"CentreBottomPanel/Content/Wares/Row{i // STORE_WARE_COLUMNS}"
            f"/Slot{i % STORE_WARE_COLUMNS}": Piece(
                "art",
                None,
                art="slot_inventory",
                instance=f"dropSlot{i}",
                rendered_at=30,
            )
            for i in range(STORE_WARES)
        },
        **{
            f"RightColumn/{node}": piece
            for node, piece in SCENES[
                "res://scenes/ui/window/right_column.tscn"
            ].pieces.items()
        },
    },
    port_only=(
        "CentreBottomPanel/Content/StatusLabel",
        "CentreTopPanel/Content/EquipDollView/Doll/Body",
        *(
            f"CentreTopPanel/Content/EquipDollView/Slot{i}/{node}"
            for i in range(STORE_EQUIP_SLOTS)
            for node in ("ItemIcon", "Highlight")
        ),
        *(
            f"CentreBottomPanel/Content/Wares/Row{i // STORE_WARE_COLUMNS}"
            f"/Slot{i % STORE_WARE_COLUMNS}/{node}"
            for i in range(STORE_WARES)
            for node in ("ItemIcon", "Highlight")
        ),
        *(
            f"RightColumn/{node}"
            for node in SCENES["res://scenes/ui/window/right_column.tscn"].port_only
        ),
    ),
    # Each of the frame's 36 inventory slots (2986) holds the item sheet 2064,
    # whose frame the game script sets to the item (DefineSprite_3142/frame_16/
    # DoAction.as). ffdec runs no script and draws a white square there, so the
    # compare tool takes the sheet out and scores the empty slot.
    compare_strip=(2064,),
)


# The top status bar record that extract_top_bar writes. The bar parts of the
# Battle screen are placed from it, because a part's own rect is a render's.
TOP_BAR_RECORD = REPO_ROOT / "assets" / "ui" / "battle" / "top_bar" / "top_bar.json"
TOP_BAR_TEXTURES = "res://assets/ui/battle/top_bar"
BAR_TEXT_NODES = {
    "playerName": "PlayerName",
    "lifeNow": "LifeNow",
    "lifeMax": "LifeMax",
    "focusNow": "FocusNow",
    "focusMax": "FocusMax",
}
# The parts of `inner2`, by their node in the port and their part name.
BAR_INNER2_NODES = {
    "FocusBack": "fill:focus_back",
    "LifeBack": "fill:life_back",
    "Shade": "inner2:Shade",
    "FocusFill": "fill:focus",
    "Black": "inner2:Black",
    "LifeFill": "fill:life",
    "Frame": "inner2:Frame",
}


def top_bar_pieces() -> dict[str, Piece]:
    """-> the pieces of the six status bars, by their path in
    top_status_bar.tscn, which the Battle screen holds as TopStatusBar. Bar n is
    the placement p<n>BAR of the battle frame."""
    pieces = {}
    for slot in range(1, 7):
        name = f"p{slot}BAR"
        base = f"TopStatusBar/Bar{slot}"
        pieces[f"{base}/Inner/Backing"] = Piece(
            "bar_part", None, instance=name, art="backing"
        )
        for variable, node in BAR_TEXT_NODES.items():
            pieces[f"{base}/Inner/{node}"] = Piece(
                "bar_part", None, instance=name, art=f"text:{variable}"
            )
        for node, part in BAR_INNER2_NODES.items():
            pieces[f"{base}/Inner2/{node}"] = Piece(
                "bar_part", None, instance=name, art=part
            )
    return pieces


# The Battle screen's frame, KRINBATTLESCENE (spec/67-battle-hud.md). Each task of
# the spec records the pieces it builds. The rest of the scene is in port_only
# until a task records it and takes its node out.
#
# Shape 333 is placed twice: at depth 70 inside sprite 3455 as the black backdrop,
# and at depth 72 as the mask whose clipDepth 340 clips the hall, the sky and the
# fighters. The Hall window is the mask, so it is the one that is recorded. Its
# rect is 0.4 px from `chrome.stage_rect`, which is the backdrop's render.
BATTLE_SCENE = "res://scenes/battle_scene.tscn"
SCENES[BATTLE_SCENE] = Scene(
    timeline=0,
    frame=battle_screen.FRAME_LABEL,
    pieces={
        "TopPanel": Piece("art", 59, art="top_panel", character=3465),
        "HallWindow": Piece("box", 72, character=333),
        "HallOutline": Piece("outline", 341, character=3415),
        # The bottom bar body 3317, and the pieces the battle frame puts on it.
        # StanceHost is the panel of the upper member row, slot 5's p5 on the
        # SHOW frame of 3312, which the conductor shows during the player's
        # half-turn. RightPanel is the right one of the bar's three boxes, which
        # the original leaves empty.
        "BottomBar/Bar": Piece("art", 1, art="bottom_bar", character=3317),
        "BottomBar/StanceHost": Piece("shape", 1, via=(7, 1, 1), character=3317),
        # Each member row is the panel of one copy of the member bar 3311 in 3312's
        # SHOW frame: slot 5's p5 above slot 3's p3. The container is the upper
        # row's panel.
        "BottomBar/StanceHost/Row5": Piece("shape", 1, via=(7, 1, 1), character=3317),
        "BottomBar/StanceHost/Row3": Piece("shape", 1, via=(7, 49, 1), character=3317),
        "BottomBar/StanceHost/Row5/NameLabel": Piece(
            "text", 1, via=(7, 1, 2), character=3317
        ),
        "BottomBar/StanceHost/Row3/NameLabel": Piece(
            "text", 1, via=(7, 49, 2), character=3317
        ),
        "BottomBar/RightPanel": Piece("shape", 1, via=(1, 1), path=2, character=3317),
        "BottomBar/PassButton": Piece("button", 498, character=3383),
        "BottomBar/AlertIcon": Piece("art", 65, art="alert_icon", character=3460),
        # The clock 3389: its dark ring, and its lit ring, which shows one render
        # of thingerClock at a time.
        "BottomBar/Clock": Piece("point", 480, character=3389),
        "BottomBar/Clock/Disc": Piece("art", 480, art="clock_disc", character=3389),
        "BottomBar/Clock/Ring": Piece("art_set", 480, art="clock_ring", character=3389),
        "BottomBar/RetreatButton": Piece("button", 644, character=3356),
        **top_bar_pieces(),
    },
    # HallSpace holds the sky, the hall and the fighters, whose art the battle
    # loads when it starts.
    port_only=(
        "HallWindow/HallSpace",
        "RadialMenu",
        # The smoothers' bands, which the bar shows only while a change plays.
        *(
            f"TopStatusBar/Bar{slot}/Inner2/{band}"
            for slot in range(1, 7)
            for band in ("LifeSmoother", "FocusSmoother")
        ),
        # What a row draws inside its panel, other than its name: the panel's art,
        # the buttons of the active frame and the text of the inactive one.
        # StanceRow places them from battle_layout.json and member_rows.json, which
        # extract_battle_screen and extract_member_rows measure off the SWF.
        *(
            f"BottomBar/StanceHost/Row{slot}/{part}"
            for slot in (5, 3)
            for part in (
                "Panel",
                "InactiveLabel",
                "Mode0",
                "Mode1",
                "Mode2",
                "Mode3",
                "Mode4",
            )
        ),
        "BottomBar/RightPanel/CombatLogPanel",
        "BottomBar/RightPanel/LogToggleButton",
        "CombatTextBanner",
        "UI",
        "Fade",
    ),
    # What the frame draws that the port leaves to the game's own state: BATTLESCREEN
    # 3435 (the hall and its placeholder rigs), the sky 3454, the fade 3355, the
    # selector rings 3394 and 3382, the clock 3389, the move icon 2427 and the move
    # button 3383, the Combat text 2852, the speech box 3367 and 3172, the tooltip
    # 2717 and the pick prompt 3373.
    compare_strip=(
        3435,
        3454,
        3355,
        3394,
        3382,
        3389,
        2427,
        3383,
        2852,
        3367,
        3172,
        2717,
        3373,
        # The status bars, whose parts the rect test checks one by one: ffdec
        # runs no script, so it draws every right-hand bar as a left-hand one and
        # every fill in the color of frame 1. The member rows and the retreat
        # button, which the port draws as its own art.
        3414,
        3312,
        3356,
    ),
)


def color_hex(color: tuple[int, int, int, int]) -> str:
    """-> "rrggbbaa", as Godot's Color.to_html() writes it."""
    return "{:02x}{:02x}{:02x}{:02x}".format(*color)


def _scale(matrix) -> tuple[float, float]:
    scale_x, skew0, skew1, scale_y, _tx, _ty = matrix
    if skew0 or skew1:
        raise ValueError(f"matrix {matrix} rotates or skews, and a rect can't hold it")
    return scale_x, scale_y


def centre_record(
    holder_matrix, child_matrix, origin, shadow: DropShadow | None
) -> dict:
    """-> the Stage point where a sprite placed with `holder_matrix` puts the
    registration point of a child placed with `child_matrix`. The holder's
    scale scales the child's translation. The holder's `shadow` is recorded
    as text_shadow writes it, and the rect test checks its blur too, because a
    StyleBoxFlat shadow has a size."""
    scale_x, scale_y = _scale(holder_matrix)
    _scale(child_matrix)
    record = {
        "kind": "centre",
        "position": [
            round(
                origin[0]
                + (holder_matrix[4] + scale_x * child_matrix[4]) / render.TWIPS,
                4,
            ),
            round(
                origin[1]
                + (holder_matrix[5] + scale_y * child_matrix[5]) / render.TWIPS,
                4,
            ),
        ],
    }
    if shadow is not None:
        record["shadow"] = text_shadow(shadow)
    return record


def stage_rect(bounds, matrix, origin) -> tuple[float, float, float, float]:
    """-> (x, y, w, h) in design px of `bounds` (twips) placed with `matrix`
    on a timeline whose origin is `origin`."""
    scale_x, scale_y = _scale(matrix)
    xs = sorted(v * scale_x for v in (bounds[0], bounds[2]))
    ys = sorted(v * scale_y for v in (bounds[1], bounds[3]))
    x = origin[0] + (xs[0] + matrix[4]) / render.TWIPS
    y = origin[1] + (ys[0] + matrix[5]) / render.TWIPS
    return x, y, (xs[1] - xs[0]) / render.TWIPS, (ys[1] - ys[0]) / render.TWIPS


def fill_rect(bounds, line_width, matrix, origin):
    half = line_width / 2
    inner = (bounds[0] + half, bounds[1] + half, bounds[2] - half, bounds[3] - half)
    return stage_rect(inner, matrix, origin)


def border_width(line_width: int, scale: tuple[float, float]) -> int:
    """-> PanelRecipe.border_width() for a line of `line_width` twips."""
    mean = math.sqrt((scale[0] ** 2 + scale[1] ** 2) / 2)
    return round(line_width / render.TWIPS * mean)


def _check_shadow(shadow: DropShadow) -> None:
    """Raises unless the shared ShaderMaterial can draw `shadow`. It takes only
    a blur, a distance and an angle, and multiplies towards black."""
    if not shadow.inner:
        raise ValueError(f"{shadow} is not an inner shadow")
    if shadow.knockout:
        raise ValueError(f"{shadow} is a knockout")
    if shadow.blur_x != shadow.blur_y:
        raise ValueError(f"{shadow} has two blur values")
    if shadow.color != (0, 0, 0, 255):
        raise ValueError(f"{shadow} has a colour other than opaque black")
    if shadow.strength != 1.0:
        raise ValueError(f"{shadow} has a strength other than 1")


def shadow_entry(shadow: DropShadow) -> dict:
    """-> the blur, distance and angle that the inner shadow ramp of
    scenes/ui/panel_shadow.gdshaderinc takes, once _check_shadow() has said
    that the ramp can draw `shadow`."""
    _check_shadow(shadow)
    return {"angle": shadow.angle, "blur": shadow.blur_x, "distance": shadow.distance}


def panel_record(*, bounds, line_width, matrix, origin, fill, line, shadow) -> dict:
    shadow_record = shadow_entry(shadow)
    border = border_width(line_width, _scale(matrix))
    x, y, w, h = fill_rect(bounds, line_width, matrix, origin)
    grow = border / 2
    return {
        "kind": "panel",
        "rect": [round(v, 4) for v in (x - grow, y - grow, w + border, h + border)],
        "fill": color_hex(fill),
        "line": color_hex(line),
        "border": border,
        "shadow": shadow_record,
    }


def text_record(text: EditText, matrix, origin) -> dict:
    if _scale(matrix) != (1.0, 1.0):
        raise ValueError(f"matrix {matrix} scales the field, and a Label can't")
    placed = (
        origin[0] + matrix[4] / render.TWIPS,
        origin[1] + matrix[5] / render.TWIPS,
    )
    rect = label_layout.text_rect(text, placed)
    entry = {
        "kind": "text",
        "rect": [rect["x"], rect["y"], rect["w"], rect["h"]],
        "font_size": text.font_height / render.TWIPS,
        "color": color_hex(text.color),
        "align": label_layout.ALIGNMENTS[text.align],
    }
    # Static text of one line says what it shows, so a Label that shows it can be
    # checked against the SWF's own characters. The game fills every other field.
    if label_layout.one_static_line(text):
        entry["text"] = text.initial_text.removesuffix("\r")
    # Flash puts the lines of a field one font height plus the field's leading
    # apart. A field that wraps, or a multiline field that is not one line of
    # static text, can show more than one line, so its pitch is recorded. A
    # field of one line has no pitch to check.
    if text.word_wrap or (text.multiline and not label_layout.one_static_line(text)):
        entry["line_pitch"] = (text.font_height + (text.leading or 0)) / render.TWIPS
    return entry


def text_shadow(shadow: DropShadow) -> dict:
    """-> the shadow a Label draws for a DropShadow on the sprite that holds
    its field: the offset in px, and the colour with the strength in its
    alpha. A Label can't blur its shadow, so the blur is recorded but the
    rect test does not check it."""
    if shadow.inner:
        raise ValueError(f"{shadow} is an inner shadow, and a Label's is outer")
    if shadow.knockout:
        raise ValueError(f"{shadow} is a knockout")
    if shadow.blur_x != shadow.blur_y:
        raise ValueError(f"{shadow} has two blur values")
    angle = math.radians(shadow.angle)
    r, g, b, a = shadow.color
    return {
        "offset": [
            round(shadow.distance * math.cos(angle), 4),
            round(shadow.distance * math.sin(angle), 4),
        ],
        "color": color_hex((r, g, b, min(255, round(a * shadow.strength)))),
        "blur": shadow.blur_x,
    }


def _shadow_of(layer: timeline.Layer) -> DropShadow | None:
    shadows = [
        drop_shadow(record)
        for name, record in zip(layer.filters, layer.filter_records, strict=True)
        if name == "DropShadow"
    ]
    if len(shadows) > 1:
        raise ValueError(
            f"character {layer.character_id} has {len(shadows)} DropShadows"
        )
    return shadows[0] if shadows else None


def battle_chrome_source(name: str) -> dict:
    """-> the render record of one battle chrome PNG, which extract_battle_screen
    writes as a rect only. Its zoom is that extractor's, and its size is read
    from the PNG."""
    rect = json.loads(battle_screen.LAYOUT_JSON.read_text())["chrome"][name]
    with Image.open(battle_screen.BATTLE_UI_DIR / f"{name}.png") as image:
        size = list(image.size)
    return {
        "rect": [rect["x"], rect["y"], rect["w"], rect["h"]],
        "size": size,
        "zoom": battle_screen.ZOOM,
    }


def art_sources() -> dict[str, tuple[dict, str]]:
    """-> the render record and the res:// folder of every PNG an art piece can
    name. Only window_chrome.json says what a rect is measured from. Every
    other record is measured from the Stage, so each gets that relative_to."""
    sources = {
        name: (entry, CHROME_TEXTURES)
        for name, entry in json.loads(window_chrome.RECORD.read_text()).items()
    }
    icons = json.loads(hotbar_icons.RECORD.read_text())["icons"]
    on_stage = [
        *(
            (name, json.loads(record.read_text()), MENU_TEXTURES)
            for name, record in MENU_ART.items()
        ),
        ("bottom_bar", battle_chrome_source("bottom_bar"), BATTLE_TEXTURES),
        ("top_panel", battle_chrome_source("top_panel"), BATTLE_TEXTURES),
        ("alert_icon", battle_chrome_source("alert_icon"), BATTLE_TEXTURES),
        ("clock_disc", battle_chrome_source("clock_disc"), BATTLE_TEXTURES),
        *(
            (
                name,
                {key: icon[key] for key in ("rect", "size", "zoom")},
                HOTBAR_TEXTURES,
            )
            for name, icon in icons.items()
        ),
    ]
    for name, record, textures in on_stage:
        if name in sources:
            raise ValueError(f"two art sources are named {name}")
        sources[name] = ({**record, "relative_to": "stage"}, textures)
    for name, entry in json.loads(zone_hub.RECORD.read_text()).items():
        sources[name] = (
            {**entry, "relative_to": "stage"},
            "res://assets/backgrounds/hub",
        )
    return sources


def moved_art(entry: dict, matrix, rendered_matrix) -> dict:
    """-> the render record `entry`, measured on the Stage where
    `rendered_matrix` places the art, moved to where `matrix` places the same
    art."""
    if entry["relative_to"] != "stage":
        raise ValueError(
            f"a rect measured from {entry['relative_to']} has no Stage position to move"
        )
    if _scale(matrix) != _scale(rendered_matrix):
        raise ValueError(
            f"matrix {matrix} does not have the scale of {rendered_matrix}, so"
            " the art is another size there"
        )
    x, y, w, h = entry["rect"]
    dx = (matrix[4] - rendered_matrix[4]) / render.TWIPS
    dy = (matrix[5] - rendered_matrix[5]) / render.TWIPS
    return {**entry, "rect": [round(x + dx, 4), round(y + dy, 4), w, h]}


def art_record(
    name: str,
    chrome: dict,
    sprite_origins: dict | None = None,
    textures: str = CHROME_TEXTURES,
    scale: float = 1.0,
) -> dict:
    """-> the record of the render record `chrome` of piece `name`, whose PNG
    is in the res:// folder `textures`. A rect measured from a sprite is moved
    to the stage by that sprite's origin in `sprite_origins`, keyed as
    "sprite <id>". When the frame scales that sprite by `scale`, the rect's
    offset and size scale with it, and the PNG holds 1 / scale as many pixels
    for each Stage px, so the zoom does too."""
    relative_to = chrome["relative_to"]
    shift = (0.0, 0.0)
    if scale != 1.0 and relative_to == "stage":
        raise ValueError(
            f"{name}'s rect is measured from the Stage, which a scale of {scale}"
            " cannot move"
        )
    if relative_to != "stage":
        if relative_to not in (sprite_origins or {}):
            raise ValueError(
                f"{name}'s rect is measured from {relative_to}, which does not"
                " place this piece"
            )
        shift = sprite_origins[relative_to]
    x, y, w, h = chrome["rect"]
    return {
        "kind": "art",
        "rect": [
            round(shift[0] + x * scale, 4),
            round(shift[1] + y * scale, 4),
            round(w * scale, 4),
            round(h * scale, 4),
        ],
        "texture": f"{textures}/{name}.png",
        "size": chrome["size"],
        "zoom": chrome["zoom"] if scale == 1.0 else round(chrome["zoom"] / scale, 6),
    }


def art_set_sources() -> dict[str, tuple[dict, list[str]]]:
    """-> the crop record and the res:// PNGs of every art set a piece can name.
    The battle clock's PNGs are listed frame label first and then by time, as
    extract_battle_screen names them."""
    clock = json.loads(battle_screen.LAYOUT_JSON.read_text())["clock"]
    folder = f"{BATTLE_TEXTURES}/{battle_screen.CLOCK_DIR.name}"
    return {
        "store_keeper": (
            json.loads(store_art.RECORD.read_text()),
            [f"{STORE_TEXTURES}/shop{shop}.png" for shop in store_art.SHOP_IDS],
        ),
        "clock_ring": (
            {
                "rect": [clock["rect"][key] for key in ("x", "y", "w", "h")],
                "size": clock["size"],
                "zoom": clock["zoom"],
                "relative_to": "stage",
            },
            [
                f"{folder}/{label}_{time_now:03d}.png"
                for label in clock["labels"]
                for time_now in range(clock["limit"] + 1)
            ],
        ),
    }


def art_set_record(crop: dict, textures: list[str]) -> dict:
    """-> the record of art that shows one of `textures`, which all have the
    one rect, size and zoom of `crop` (a record of the extractor that wrote
    them, measured from the Stage)."""
    if crop["relative_to"] != "stage":
        raise ValueError(
            f"the crop is measured from {crop['relative_to']}, not the Stage"
        )
    if not textures:
        raise ValueError("an art set needs at least one texture")
    return {
        "kind": "art_set",
        "rect": [round(v, 4) for v in crop["rect"]],
        "textures": list(textures),
        "size": crop["size"],
        "zoom": crop["zoom"],
    }


def box_record(bounds, matrix, origin, fill: tuple[int, int, int, int]) -> dict:
    """-> the record of a shape of one solid fill and no line, which the port
    draws as a ColorRect."""
    return {
        "kind": "box",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
        "fill": color_hex(fill),
    }


def inner_shadow_record(bounds, matrix, origin, shadow: DropShadow) -> dict:
    """-> the record of an overlay on the clip mask whose ShapeBounds are
    `bounds`, which draws `shadow` over what the mask's sprite holds."""
    return {
        "kind": "inner_shadow",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
        "shadow": shadow_entry(shadow),
    }


def shape_record(bounds, matrix, origin) -> dict:
    """-> the record of a shape the port puts a plain Control on."""
    return {
        "kind": "shape",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
    }


def outline_record(
    bounds, matrix, origin, styles: list[StyleSet], path: int | None = None
) -> dict:
    """-> the record of an outline shape, or of its `path`th stroked path, from
    the top down, when the shape draws several boxes with one line. A path's
    rect is its edges grown by half the line, as the whole shape's bounds are,
    and the paths' rects must cover the shape's bounds exactly."""
    only = styles[0] if len(styles) == 1 else None
    if only is None or only.fills or only.used_fills or len(only.lines) != 1:
        raise ValueError("an outline needs one line and no fill")
    width, color = only.lines[0]
    if path is not None:
        half = width / 2
        grown = [
            (xmin - half, ymin - half, xmax + half, ymax + half)
            for xmin, ymin, xmax, ymax in sorted(
                only.paths, key=lambda box: (box[1], box[0])
            )
        ]
        covered = (
            min(g[0] for g in grown),
            min(g[1] for g in grown),
            max(g[2] for g in grown),
            max(g[3] for g in grown),
        )
        if any(abs(a - b) > 1 for a, b in zip(covered, bounds, strict=True)):
            raise ValueError(
                f"the outline's {len(grown)} paths cover {covered}, not its bounds {bounds}"
            )
        bounds = grown[path]
    return {
        "kind": "outline",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
        "line": color_hex(color),
        "border": border_width(width, _scale(matrix)),
    }


def path_shape_record(styles: list[StyleSet], path: int, matrix, origin) -> dict:
    """-> the record of the `path`th stroked path of a shape, from the top down
    and from the left, as the line's centre. It is the rect inside the line's
    outer edge, for a piece that sits over a box the shape draws with one line."""
    if len(styles) != 1 or not styles[0].paths:
        raise ValueError("a path shape needs one style set with stroked paths")
    boxes = sorted(styles[0].paths, key=lambda box: (box[1], box[0]))
    if not 0 <= path < len(boxes):
        raise ValueError(f"the shape has {len(boxes)} paths, not a path {path}")
    return shape_record(boxes[path], matrix, origin)


def bar_part_record(part: str, matrix, bar: dict, name: str) -> dict:
    """-> the record of one part of the status bar that the battle frame places
    as `name` with `matrix`. `bar` is top_bar.json. The part is an art piece, a
    fill at its full width or a text field. Every rect in that file is in the bar
    sprite's design px, or in `inner2`'s, which the right-hand bars mirror, so this
    puts it through the placement. The bar's scale is not the same in x and y, so
    an art piece has a zoom for each axis."""
    sx, skew0, skew1, sy, tx, ty = matrix
    if skew0 or skew1:
        raise ValueError(f"{name} is placed with {matrix}")
    flags = bar["placements"][name]
    mirrored = flags["inner2_xscale"] is not None and flags["inner2_xscale"] < 0
    frame = bar["inner"]["frames"][flags["inner_frame"] or "first"]

    def on_stage(rect, flip: bool) -> list[float]:
        x, y, w, h = rect
        left = -x - w if flip else x
        return [
            round(tx / render.TWIPS + sx * left, 4),
            round(ty / render.TWIPS + sy * y, 4),
            round(sx * w, 4),
            round(sy * h, 4),
        ]

    def art(entry: dict, rect: list[float], flip: bool) -> dict:
        stage = on_stage(rect, flip)
        return {
            "kind": "art",
            "rect": stage,
            "texture": f"{TOP_BAR_TEXTURES}/{entry['file']}",
            "size": entry["size"],
            "zoom": [entry["size"][0] / stage[2], entry["size"][1] / stage[3]],
        }

    kind, _, which = part.partition(":")
    if part == "backing":
        entry = frame["art"]
        return art(entry, entry["rect"], False)
    if kind == "text":
        field = next(f for f in frame["fields"] if f["variable"] == which)
        shadow = bar["shadow"]
        angle = math.radians(shadow["angle"])
        alpha = int(shadow["color"][6:8], 16)
        return {
            "kind": "text",
            "rect": on_stage(field["rect"], False),
            "font_size": field["font_size"],
            "color": field["color"],
            "align": field["align"],
            "shadow": {
                "offset": [
                    round(sx * shadow["distance"] * math.cos(angle), 4),
                    round(sy * shadow["distance"] * math.sin(angle), 4),
                ],
                "color": shadow["color"][:6]
                + f"{min(255, round(alpha * shadow['strength'])):02x}",
                "blur": shadow["blur_x"],
            },
        }
    if kind == "inner2":
        entry = bar["inner2"]["art"][which]
        return art(entry, entry["rect"], mirrored)
    if kind == "fill":
        bars = bar["bars"]["life" if which.startswith("life") else "focus"]
        entry = bar["art"][bars["art"]]
        x, y, w, h = entry["rect"]
        rect = [bars["x"] + x * bars["scale_x"], bars["y"] + y, w * bars["scale_x"], h]
        return art(entry, rect, mirrored)
    raise ValueError(f"unknown bar part {part!r}")


def through_sprites(index: SwfIndex, layer: timeline.Layer) -> tuple[int, tuple]:
    """-> (shape id, matrix) of the one shape that `layer` draws, with the
    matrices of every sprite on the way down folded into one. Each sprite must
    hold exactly one thing on its first frame, and no matrix may rotate or
    skew, so the result still says only a scale and a translation."""
    matrix = layer.matrix
    character = layer.character_id
    _scale(matrix)
    while character_kind(index, character) == "sprite":
        held = list(timeline.frames(index, character)[0].values())
        if len(held) != 1:
            raise ValueError(
                f"sprite {character} holds {len(held)} things, not exactly one"
            )
        inner = held[0]
        scale_x, scale_y = _scale(inner.matrix)
        outer_x, _skew0, _skew1, outer_y, tx, ty = matrix
        matrix = (
            outer_x * scale_x,
            0.0,
            0.0,
            outer_y * scale_y,
            tx + outer_x * inner.matrix[4],
            ty + outer_y * inner.matrix[5],
        )
        character = inner.character_id
    return character, matrix


def _shape(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    """-> shape_record() of the shape `layer` places, or of the one shape that
    the sprites it places hold."""
    shape, matrix = through_sprites(index, layer)
    return shape_record(shape_bounds(index, shape), matrix, origin)


def face_record(crop, matrix, origin) -> dict:
    """-> the record of a portrait, as the crop box of extract_faces placed with
    `matrix`, the matrix that places the face clip. `crop` is (x, y, w, h) in the
    clip's own design px. The portrait is a different texture for each fighter,
    so the record holds the rect and no texture."""
    x, y, w, h = crop
    bounds = tuple(v * render.TWIPS for v in (x, y, x + w, y + h))
    return {
        "kind": "face",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
    }


def hit_record(records: list[ButtonRecord], bounds, matrix, origin) -> dict:
    """-> the record of a button that `records` describe, whose one hit shape
    has `bounds`, placed with `matrix`."""
    drawn = [(sorted(r.states), r.character_id) for r in records]
    if len(records) != 1 or records[0].states != {"hit"}:
        raise ValueError(
            f"the button draws {drawn}, and the port keeps a hit area only"
        )
    if records[0].matrix != timeline.IDENTITY:
        raise ValueError(f"the button moves its hit shape: {records[0].matrix}")
    return {
        "kind": "hit",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
    }


def button_record(
    button: int, records: list[ButtonRecord], bounds: dict, matrix, origin
) -> dict:
    """-> the record of the button `button`, whose `records` draw art, as the
    rect of the shapes its up state draws, each placed in the button with its
    record's matrix, and the button placed with `matrix`. `bounds` maps each
    shape to its ShapeBounds."""
    up = [r for r in records if "up" in r.states]
    if not up:
        raise ValueError(f"button {button} draws nothing in its up state")
    for r in up:
        if r.character_id not in bounds:
            raise ValueError(
                f"button {button} draws character {r.character_id} in its up"
                " state, which is not a shape"
            )
    shapes = [_in_button(bounds[r.character_id], r.matrix) for r in up]
    union = (
        min(b[0] for b in shapes),
        min(b[1] for b in shapes),
        max(b[2] for b in shapes),
        max(b[3] for b in shapes),
    )
    return {
        "kind": "button",
        "rect": [round(v, 4) for v in stage_rect(union, matrix, origin)],
    }


def _in_button(bounds, matrix) -> tuple[float, float, float, float]:
    """-> `bounds` (twips) through a button record's `matrix`, in the button's
    own twips."""
    scale_x, scale_y = _scale(matrix)
    xs = sorted(v * scale_x + matrix[4] for v in (bounds[0], bounds[2]))
    ys = sorted(v * scale_y + matrix[5] for v in (bounds[1], bounds[3]))
    return xs[0], ys[0], xs[1], ys[1]


def _button(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    records = button_records(index, layer.character_id)
    bounds = {
        r.character_id: shape_bounds(index, r.character_id)
        for r in records
        if character_kind(index, r.character_id) == "shape"
    }
    return button_record(layer.character_id, records, bounds, layer.matrix, origin)


def inner_origin(matrix, origin) -> tuple[float, float]:
    """-> the origin of a sprite's own timeline, when the sprite is placed with
    `matrix` on a timeline whose origin is `origin`."""
    if _scale(matrix) != (1.0, 1.0):
        raise ValueError(f"matrix {matrix} scales the sprite, and an origin can't")
    return (origin[0] + matrix[4] / render.TWIPS, origin[1] + matrix[5] / render.TWIPS)


def _hit(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    records = button_records(index, layer.character_id)
    shape = records[0].character_id if records else None
    if shape is None or character_kind(index, shape) != "shape":
        raise ValueError(f"button {layer.character_id} has no hit shape")
    return hit_record(records, shape_bounds(index, shape), layer.matrix, origin)


def _panel(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    where = f"panel sprite {layer.character_id}"
    shapes = list(timeline.frames(index, layer.character_id)[0].values())
    if len(shapes) != 1 or character_kind(index, shapes[0].character_id) != "shape":
        raise ValueError(f"{where} does not hold exactly one shape")
    inner = shapes[0]
    if inner.matrix != timeline.IDENTITY:
        raise ValueError(f"{where} places its shape with {inner.matrix}")
    shadows = [
        drop_shadow(record)
        for name, record in zip(layer.filters, layer.filter_records, strict=True)
        if name == "DropShadow"
    ]
    if len(shadows) != 1 or len(layer.filters) != 1:
        raise ValueError(f"{where} has filters {layer.filters}, not one DropShadow")
    fill, line_style = one_fill_and_line(
        shape_styles(index, inner.character_id), inner.character_id
    )
    return panel_record(
        bounds=shape_bounds(index, inner.character_id),
        line_width=line_style[0],
        matrix=layer.matrix,
        origin=origin,
        fill=fill,
        line=line_style[1],
        shadow=shadows[0],
    )


def one_fill_and_line(
    sets: list[StyleSet], shape: int
) -> tuple[tuple[int, int, int, int], tuple[int, tuple[int, int, int, int]]]:
    """-> (fill colour, (line width in twips, line colour)) of a Panel's shape.
    Raises unless the shape has one style set, whose only fill is a solid
    colour that its edges use as fill 1, and one line. A shape that declares new
    styles partway through draws more with them, and its first style set alone
    would record the wrong fill or line. Shape 3001 did that (`6b0bb46e`)."""
    if len(sets) != 1:
        raise ValueError(f"shape {shape} has {len(sets)} style sets, not one")
    only = sets[0]
    if only.used_fills != {1}:
        raise ValueError(f"shape {shape} uses fills {set(only.used_fills)}, not fill 1")
    if only.fills[0] is None:
        raise ValueError(f"shape {shape}'s fill 1 is not a solid colour")
    if len(only.lines) != 1:
        raise ValueError(f"shape {shape} has {len(only.lines)} lines, not one line")
    return only.fills[0], only.lines[0]


def one_solid_fill(sets: list[StyleSet], shape: int) -> tuple[int, int, int, int]:
    """-> the colour of a shape that fills with one solid fill and strokes no
    line. Its first style set alone can't say so, because a shape can declare
    new styles partway through and draw more with them."""
    only = sets[0] if len(sets) == 1 else None
    if (
        only is None
        or only.line_bounds
        or only.used_fills != {1}
        or only.fills[0] is None
    ):
        raise ValueError(f"shape {shape} is not one solid fill with no line")
    return only.fills[0]


def _box(index: SwfIndex, layer: timeline.Layer, origin) -> dict:
    shape, matrix = through_sprites(index, layer)
    if character_kind(index, shape) != "shape":
        raise ValueError(f"box {shape} is not a shape")
    fill = one_solid_fill(shape_styles(index, shape), shape)
    return box_record(shape_bounds(index, shape), matrix, origin, fill)


def _string_array(script: str, name: str) -> list[str]:
    found = re.findall(rf"{name} = \[((?:\"\w+\",?)+)\];", script)
    if len(found) != 1:
        raise ValueError(f"{DOLL_SCRIPT}: {len(found)} statements fill {name}")
    return re.findall(r"\w+", found[0])


def doll_parts(script: str) -> list[tuple[str, str]]:
    """-> (part name, art code) for each doll part, in the order of the menu
    script's dollPartsArray. The art of a part is named from its code, as in
    M_SARM_ONE. A WEAPON part has no skin art."""
    names = _string_array(script, "dollPartsArray")
    codes = _string_array(script, "dollPartsCores2")
    if len(names) != len(codes):
        raise ValueError(
            f"{DOLL_SCRIPT}: {len(names)} doll parts and {len(codes)} art codes"
        )
    return list(zip(names, codes, strict=True))


def _doll_scale(placed: dict[str, timeline.Layer], rig: dict) -> float:
    """-> the scale s of the doll, where each placed part's matrix is the rig's
    matrix for that part with x mirrored and everything scaled by s. It is the
    least squares fit over every part. Raises when a part is a different
    pose: another rotation, another scale, or no mirror."""
    top = bottom = 0.0
    for name, layer in placed.items():
        a, b, c, d = layer.matrix[:4]
        ra, rb, rc, rd = rig[name][:4]
        top += -a * ra - c * rc + b * rb + d * rd
        bottom += ra * ra + rb * rb + rc * rc + rd * rd
    scale = top / bottom
    misses = {}
    for name, layer in placed.items():
        ra, rb, rc, rd = rig[name][:4]
        expected = (-scale * ra, scale * rb, -scale * rc, scale * rd)
        misses[name] = max(
            abs(m - e) for m, e in zip(layer.matrix[:4], expected, strict=True)
        )
    name = max(misses, key=misses.__getitem__)
    if misses[name] > DOLL_MATRIX_TOLERANCE:
        raise ValueError(
            f"the doll's {name} is not the rig's stand pose, mirrored and"
            f" scaled by {scale:.4f}: a matrix entry is {misses[name]:.4f} away"
        )
    return scale


def doll_record(
    layers: dict[int, timeline.Layer],
    parts: list[tuple[str, str]],
    rig: dict[str, list[float]],
    offsets: dict[str, dict],
    origin: tuple[float, float],
    female_set: bool = True,
) -> dict:
    """-> the record of the doll that `layers` place as loose clips: where the
    rig's stand pose lands on the Stage, as the doll's position and scale, and
    the union rect of the art of DOLL_LOOK's unequipped doll under the male
    placements.

    `rig` is the rig's stand pose as one [a, b, c, d, tx, ty] matrix in px for
    each part, and `offsets` the art bounds of doll_offsets.json. The scale is
    fitted from the parts' matrices, and the position is the median over the
    parts of where each placed origin puts the doll. The median holds against
    a part whose origin the SWF moves off the pose, which the menu does with
    arm1 by 1 px in x and y.

    The frame places the male parts, the ground shadow and, when `female_set`
    is true, the same parts again with an _f suffix."""
    held = [layer for layer in layers.values() if layer.character_id in DOLL_CHARACTERS]
    expected = (2 if female_set else 1) * len(parts) + 1
    if len(held) != expected:
        raise ValueError(f"the frame places {len(held)} doll clips, not {expected}")
    names = {layer.name: layer for layer in held if layer.name}
    wanted = [name for name, _code in parts]
    for name in (*wanted, *(f"{name}_f" for name in wanted if female_set)):
        if name not in names:
            raise ValueError(f"the frame places no doll clip named {name}")
    placed = {name: names[name] for name in wanted}
    scale = _doll_scale(placed, rig)
    x0 = statistics.median(
        layer.matrix[4] / render.TWIPS + scale * rig[name][4]
        for name, layer in placed.items()
    )
    y0 = statistics.median(
        layer.matrix[5] / render.TWIPS - scale * rig[name][5]
        for name, layer in placed.items()
    )
    xs: list[float] = []
    ys: list[float] = []
    for name, code in parts:
        art = (
            []
            if code == "WEAPON"
            else [f"{DOLL_LOOK['gender']}_S{code}_{DOLL_LOOK['skin']}"]
        )
        if name == "head":
            art.append(f"HAIR_{DOLL_LOOK['hair']}")
        a, b, c, d, tx, ty = placed[name].matrix
        for key in art:
            # A part the original leaves empty has no entry, as in the port.
            if key not in offsets:
                continue
            box = offsets[key]
            for x, y in (
                (box["x"], box["y"]),
                (box["x"] + box["w"], box["y"]),
                (box["x"], box["y"] + box["h"]),
                (box["x"] + box["w"], box["y"] + box["h"]),
            ):
                xs.append(origin[0] + (a * x + c * y + tx / render.TWIPS))
                ys.append(origin[1] + (b * x + d * y + ty / render.TWIPS))
    return {
        "kind": "doll",
        "position": [round(origin[0] + x0, 4), round(origin[1] + y0, 4)],
        "scale": [round(-scale, 4), round(scale, 4)],
        "look": dict(DOLL_LOOK),
        "rect": [
            round(min(xs), 4),
            round(min(ys), 4),
            round(max(xs) - min(xs), 4),
            round(max(ys) - min(ys), 4),
        ],
    }


RIG_NAME = re.compile(r"player([1-6])")


def fighter_marks(origin, layers: dict[int, timeline.Layer]) -> dict[str, list[float]]:
    """-> {slot: [x, y]}: where one hall label of BATTLESCREEN, placed at
    `origin`, puts the fighter rig of each slot on the Stage. A slot is the digit
    of the rig's instance name, player1 to player6. Another character of the
    label is the hall's art, which this leaves alone."""
    marks: dict[str, list[float]] = {}
    for depth, layer in layers.items():
        if layer.character_id != battle_screen.FIGHTER_RIG:
            continue
        found = RIG_NAME.fullmatch(layer.name or "")
        if found is None or found[1] in marks:
            raise ValueError(
                f"depth {depth} holds the fighter rig as {layer.name!r}, which is"
                " not a slot that is still free"
            )
        marks[found[1]] = [
            round(origin[0] + layer.matrix[4] / render.TWIPS, 4),
            round(origin[1] + layer.matrix[5] / render.TWIPS, 4),
        ]
    if sorted(marks) != list("123456"):
        raise ValueError(f"the label places the rig for slots {sorted(marks)}, not 1-6")
    return marks


def hall_fighter_marks(index: SwfIndex) -> dict[str, dict[str, list[float]]]:
    """-> fighter_marks() of every hall label, by the label's key in
    battle_layout.json."""
    frame = timeline.frame_of(index, 0, battle_screen.FRAME_LABEL)
    origin = render.placement_origin(index, 0, frame, battle_screen.HALL_SPRITE)
    by_frame = timeline.frames(index, battle_screen.HALL_SPRITE)
    return {
        label.replace(" ", "_"): fighter_marks(origin, by_frame[number - 1])
        for label, number in battle_screen.sprite_label_frames(
            index, battle_screen.HALL_SPRITE
        ).items()
    }


def origin_of(index: SwfIndex, owner: int) -> tuple[float, float]:
    if owner == 0:
        return 0.0, 0.0
    hub = timeline.frame_of(index, 0, HUB_FRAME)
    return render.placement_origin(index, 0, hub, owner)


def placed_layer(
    layers: dict[int, timeline.Layer], where: int | str, path: str, frame: str
) -> timeline.Layer:
    """-> the layer of `layers` at the depth `where`, or the one layer with
    the instance name `where`."""
    if isinstance(where, int):
        if where not in layers:
            raise ValueError(f"{path}: frame {frame} has no depth {where}")
        return layers[where]
    named = [layer for layer in layers.values() if layer.name == where]
    if len(named) != 1:
        raise ValueError(
            f"{path}: frame {frame} places {len(named)} instances named {where}"
        )
    return named[0]


def moved_to_steam(record: dict, matrix, steam_matrix) -> dict:
    """-> `record`, which holds the rect of a piece the web build places with
    `matrix`, moved to where the Steam build places the same piece with
    `steam_matrix`."""
    if _scale(matrix) != _scale(steam_matrix):
        raise ValueError(
            f"the Steam placement {steam_matrix} does not have the scale of"
            f" {matrix}, so the piece is another size there"
        )
    x, y, w, h = record["rect"]
    dx = (steam_matrix[4] - matrix[4]) / render.TWIPS
    dy = (steam_matrix[5] - matrix[5]) / render.TWIPS
    return {**record, "rect": [round(x + dx, 4), round(y + dy, 4), w, h]}


def scene_record(
    index: SwfIndex, scene: Scene, steam_index: SwfIndex | None = None
) -> dict:
    origin = origin_of(index, scene.timeline)
    frame = timeline.frame_of(index, scene.timeline, scene.frame)
    layers = timeline.frames(index, scene.timeline)[frame - 1]
    steam_layers = None
    if any(piece.steam is not None for piece in scene.pieces.values()):
        if steam_index is None:
            raise ValueError(
                f"frame {scene.frame} has a piece with a Steam placement, and"
                " no Steam build was given"
            )
        steam_frame = timeline.frame_of(steam_index, scene.timeline, scene.frame)
        steam_layers = timeline.frames(steam_index, scene.timeline)[steam_frame - 1]
    art = art_sources()
    pieces = {}
    for path, piece in scene.pieces.items():
        where = piece.depth if piece.instance is None else piece.instance
        layer = placed_layer(layers, where, path, scene.frame)
        if piece.character is not None and layer.character_id != piece.character:
            raise ValueError(
                f"{path}: depth {where} of frame {scene.frame} holds character"
                f" {layer.character_id}, not {piece.character}"
            )
        if piece.kind == "centre":
            first = timeline.frames(index, layer.character_id)[0]
            child = placed_layer(
                first, piece.inner_instance, path, f"1 of sprite {layer.character_id}"
            )
            pieces[path] = centre_record(
                layer.matrix, child.matrix, origin, _shadow_of(layer)
            )
            continue
        placed = layer
        piece_origin = origin
        sprite_origins = {}
        art_scale = 1.0
        holder_shadow = None
        if piece.inner_depth is None:
            sprite = f"sprite {layer.character_id}"
            if piece.kind == "art" and art[piece.art][0]["relative_to"] == sprite:
                sprite_origins[sprite] = inner_origin(layer.matrix, origin)
        else:
            holder_shadow = _shadow_of(layer)
            piece_origin = inner_origin(layer.matrix, origin)
            sprite_origins[f"sprite {layer.character_id}"] = piece_origin
            first = timeline.frames(index, layer.character_id)[0]
            if piece.inner_depth not in first:
                raise ValueError(
                    f"{path}: sprite {layer.character_id} has no depth"
                    f" {piece.inner_depth} on its first frame"
                )
            layer = first[piece.inner_depth]
            # A face is placed with a scale, so no origin of its own exists.
            if (
                piece.kind != "face"
                and character_kind(index, layer.character_id) == "sprite"
            ):
                sprite_origins[f"sprite {layer.character_id}"] = inner_origin(
                    layer.matrix, piece_origin
                )
        for step in piece.via:
            if piece.inner_depth is not None:
                raise ValueError(f"{path}: a piece names inner_depth or via, not both")
            piece_origin = inner_origin(layer.matrix, piece_origin)
            first = timeline.frames(index, layer.character_id)[0]
            if step not in first:
                raise ValueError(
                    f"{path}: sprite {layer.character_id} has no depth {step} on its"
                    " first frame"
                )
            layer = first[step]
        if piece.kind == "point":
            pieces[path] = {
                "kind": "point",
                "position": [
                    round(piece_origin[0] + layer.matrix[4] / render.TWIPS, 4),
                    round(piece_origin[1] + layer.matrix[5] / render.TWIPS, 4),
                ],
                "scale": list(_scale(layer.matrix)),
            }
        elif piece.kind == "panel":
            pieces[path] = _panel(index, layer, piece_origin)
        elif piece.kind == "text":
            text = edit_text(index, layer.character_id)
            pieces[path] = text_record(text, layer.matrix, piece_origin)
            if holder_shadow is not None:
                pieces[path]["shadow"] = text_shadow(holder_shadow)
        elif piece.kind == "button":
            pieces[path] = _button(index, layer, piece_origin)
        elif piece.kind == "art":
            entry, textures = art[piece.art]
            if piece.rendered_at is not None:
                rendered = layers[piece.rendered_at]
                if entry["relative_to"] == f"sprite {rendered.character_id}":
                    # #211 shares the grid's art with equip slots. Place that
                    # sprite-local render at the equip slot's own origin, and
                    # at its own scale: the shop frame scales them to 0.86.
                    scale_x, scale_y = _scale(layer.matrix)
                    rendered_x, rendered_y = _scale(rendered.matrix)
                    if scale_x / rendered_x != scale_y / rendered_y:
                        raise ValueError(
                            "shared sprite art has to keep the same scale in x and y"
                        )
                    art_scale = scale_x / rendered_x
                    sprite_origins[entry["relative_to"]] = (
                        piece_origin[0] + layer.matrix[4] / render.TWIPS,
                        piece_origin[1] + layer.matrix[5] / render.TWIPS,
                    )
                else:
                    entry = moved_art(entry, layer.matrix, rendered.matrix)
            pieces[path] = art_record(
                piece.art, entry, sprite_origins, textures, art_scale
            )
        elif piece.kind == "art_set":
            pieces[path] = art_set_record(*art_set_sources()[piece.art])
        elif piece.kind == "face":
            if layer.character_id != faces.FACE_CLIP:
                raise ValueError(
                    f"{path}: depth {piece.inner_depth} holds {layer.character_id},"
                    f" not the face clip {faces.FACE_CLIP}"
                )
            crop = json.loads(faces.RECORD.read_text())["rect"]
            pieces[path] = face_record(crop, layer.matrix, piece_origin)
        elif piece.kind == "box":
            pieces[path] = _box(index, layer, piece_origin)
        elif piece.kind == "shape" and piece.path is not None:
            pieces[path] = path_shape_record(
                shape_styles(index, layer.character_id),
                piece.path,
                layer.matrix,
                piece_origin,
            )
        elif piece.kind == "shape":
            pieces[path] = _shape(index, layer, piece_origin)
        elif piece.kind == "inner_shadow":
            if holder_shadow is None:
                raise ValueError(
                    f"{path}: an inner_shadow piece needs an inner_depth inside a"
                    " sprite placed with a DropShadow"
                )
            shape, matrix = through_sprites(index, layer)
            pieces[path] = inner_shadow_record(
                shape_bounds(index, shape), matrix, piece_origin, holder_shadow
            )
        elif piece.kind == "outline":
            pieces[path] = outline_record(
                shape_bounds(index, layer.character_id),
                layer.matrix,
                piece_origin,
                shape_styles(index, layer.character_id),
                piece.path,
            )
        elif piece.kind == "bar_part":
            pieces[path] = bar_part_record(
                piece.art,
                layer.matrix,
                json.loads(TOP_BAR_RECORD.read_text()),
                layer.name,
            )
        elif piece.kind == "hit":
            pieces[path] = _hit(index, layer, piece_origin)
        elif piece.kind == "doll":
            rig = json.loads(RIG_ANIMATIONS.read_text())
            stand = int(rig["labels"]["stand"]["start"]) - 1
            pieces[path] = doll_record(
                layers,
                doll_parts((ACTION_SCRIPT / DOLL_SCRIPT).read_text("utf-8")),
                rig["frames"][stand],
                json.loads(DOLL_OFFSETS.read_text()),
                piece_origin,
                piece.female_set,
            )
        else:
            raise ValueError(f"{path}: unknown piece kind {piece.kind!r}")
        if piece.steam is not None:
            steam = placed_layer(steam_layers, piece.steam, path, scene.frame)
            pieces[path] = moved_to_steam(pieces[path], placed.matrix, steam.matrix)
    return {
        "timeline": scene.timeline,
        "frame": scene.frame,
        "origin": [round(v, 4) for v in origin],
        "port_only": list(scene.port_only),
        "pieces": pieces,
    }


# The victory frame, "win" (spec/107-victory.md). The left Panel holds the
# heading and the three experience rows, each a placement of sprite 3002: the
# player's at depth 1197, then friendlySlotsFFTT[0] and [1] at 1111 and 1154.
# The face is the clip 2978 at depth 3 of the row, and extract_faces writes
# where its crop sits in it. The row's shape 3001 has no fill across the row: it
# strokes a 1 px line around it and fills only the box under the bar. The port
# draws it as the victory_row art, which holds the shape under the row's
# DropShadow. The centre Panel holds the 15 drop slots, dropSlot0 to dropSlot14,
# the gain text and Proceed. The frame places no close X (depths 1431 and 1434)
# and no sell slot (depth 1281), so the record leaves out the shell's close
# pieces and the right column's SellSlot.
VICTORY_SCENE = "res://scenes/ui/menu/victory_window.tscn"
VICTORY_DROPS = 15
VICTORY_DROP_COLUMNS = 5
SCENES[VICTORY_SCENE] = Scene(
    timeline=KRINMENU,
    frame="win",
    pieces={
        **{
            f"WindowShell/{node}": piece
            for node, piece in SCENES[
                "res://scenes/ui/window/window_shell.tscn"
            ].pieces.items()
            if node == "Backdrop"
        },
        "LeftPanel": Piece("panel", 11),
        "CentrePanel": Piece("panel", 21),
        "Heading": Piece("text", 1240, character=2996),
        **{
            f"ExpRows/{slot}/Row/{node}": Piece(kind, depth, art=art, inner_depth=inner)
            for slot, depth in VICTORY_ROWS.items()
            for node, (kind, inner, art) in VICTORY_ROW_PIECES.items()
        },
        "DropsLabel": Piece("text", 1107, character=3005),
        **{
            f"Drops/Row{i // VICTORY_DROP_COLUMNS}/Slot{i % VICTORY_DROP_COLUMNS}": Piece(
                "art",
                None,
                art="slot_inventory",
                instance=f"dropSlot{i}",
                rendered_at=30,
            )
            for i in range(VICTORY_DROPS)
        },
        "NoItemsLabel": Piece("text", 1110, character=3003),
        "ClickHintLabel": Piece("text", 1105, character=3007),
        "MoneyLabel": Piece("text", 1101, character=3011),
        "MoneyValue": Piece("text", 1102, character=3010),
        "ExpLabel": Piece("text", 1103, character=3009),
        "ExpValue": Piece("text", 1104, character=3008),
        "ProceedHintLabel": Piece("text", 1106, character=3006),
        "ProceedLabel": Piece("text", 23, character=3014),
        "ProceedButton": Piece("hit", 1108, character=3004),
        **{
            f"RightColumn/{node}": piece
            for node, piece in SCENES[
                "res://scenes/ui/window/right_column.tscn"
            ].pieces.items()
            if not node.startswith("SellSlot")
        },
    },
    port_only=(
        "WindowShell/CloseArt",
        "WindowShell/CloseButton",
        *(
            f"Drops/Row{i // VICTORY_DROP_COLUMNS}/Slot{i % VICTORY_DROP_COLUMNS}/{node}"
            for i in range(VICTORY_DROPS)
            for node in ("ItemIcon", "Highlight")
        ),
        *(
            f"RightColumn/{node}"
            for node in SCENES["res://scenes/ui/window/right_column.tscn"].port_only
        ),
    ),
    # Each of the frame's 36 inventory slots (2986) holds the item sheet 2064,
    # which the game script sets to the item. ffdec draws a white square there,
    # so the compare tool takes the sheet out and scores the empty slot.
    compare_strip=(2064,),
)


def main():
    index = read_swf(WEB_SWF)
    steam_index = read_swf(STEAM_SWF)
    record = {
        "scenes": {
            path: scene_record(index, scene, steam_index)
            for path, scene in SCENES.items()
        },
        "fighter_marks": hall_fighter_marks(index),
    }
    RECORD.parent.mkdir(parents=True, exist_ok=True)
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

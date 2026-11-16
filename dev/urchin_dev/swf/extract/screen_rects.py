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
# A piece is one of seven kinds:
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
#             rect that render measured, with the PNG's path. A window chrome
#             depth is the one window_chrome renders, so the two extractors cannot name
#             different placements.
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
# A timeline other than the root is measured from where the root's Navigation
# frame places it, which for KRINMENU is (400.50, 222.40).
#
# Run: uv run extract_screen_rects
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field

from PIL import Image

from urchin_dev import REPO_ROOT, WEB_SWF
from urchin_dev.swf import label_layout, render, timeline
from urchin_dev.swf.extract import (
    battle_screen,
    faces,
    hotbar_icons,
    start_screens,
    window_chrome,
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
# The menu art, by the record that extract_start_screens writes beside each PNG.
MENU_ART = {
    "logo": start_screens.LOGO_RECORD,
    "start_background": start_screens.BACKGROUND_RECORD,
}
KRINMENU = 3142
HUB_FRAME = "Navigation"


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
    # The depth whose placement the art's render was measured at, for art that
    # the frame places at several depths and the extractor rendered at one.
    rendered_at: int | None = None

    def __post_init__(self) -> None:
        if (self.depth is None) == (self.instance is None):
            raise ValueError(
                f"A piece needs a depth or an instance name, not both or neither:"
                f" depth {self.depth}, instance {self.instance}"
            )
        if self.kind == "art" and self.art is None:
            raise ValueError(
                f"An art piece needs the name of its art: depth {self.depth},"
                f" instance {self.instance}"
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
# art and the hit rect are two pieces at one depth.
HOTBAR_SLOTS: dict[str, tuple[int, str]] = {
    "Inventory": (126, "inventory"),
    "Abilities": (128, "abilities"),
    "Save": (130, "save"),
    "Options": (136, "options"),
    "Respec": (138, "respec"),
    "Achievements": (165, "achievements"),
}
if (
    tuple(depth for depth, _icon in HOTBAR_SLOTS.values())
    != window_chrome.SQUARE_DEPTHS
):
    raise ValueError("HOTBAR_SLOTS and window_chrome.SQUARE_DEPTHS disagree")


def hotbar_icon(name: str) -> Piece:
    return Piece("art", None, art=name, instance=hotbar_icons.ICONS[name])


HOTBAR_PIECES = {
    "BottomBar": Piece("art", 1, art="bottom_bar"),
    **{
        f"{slot}Slot/{node}": piece
        for slot, (depth, icon) in HOTBAR_SLOTS.items()
        for node, piece in {
            "Square": Piece(
                "art",
                depth,
                art="hotbar_square",
                rendered_at=window_chrome.SQUARE_DEPTHS[0],
            ),
            "Icon": hotbar_icon(icon),
            f"{slot}Button": Piece("button", depth),
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
    # The victory frame's three experience rows, each a placement of sprite
    # 3002: the player's at depth 1197, then friendlySlotsFFTT[0] and [1] at
    # 1111 and 1154. The rest of the Victory screen is port only until the
    # Victory Window replaces it (spec/107-victory.md). The face is the clip 2978
    # at depth 3 of the row, and extract_faces writes where its crop sits in it.
    # The row's shape 3001 has no fill across the row: it strokes a 1 px line
    # around it and fills only the box under the bar. The port draws it as the
    # victory_row art, which holds the shape under the row's DropShadow.
    "res://scenes/battle/victory_screen.tscn": Scene(
        timeline=KRINMENU,
        frame="win",
        pieces={
            f"ExpRows/{slot}/Row/{node}": Piece(kind, depth, art=art, inner_depth=inner)
            for slot, depth in VICTORY_ROWS.items()
            for node, (kind, inner, art) in VICTORY_ROW_PIECES.items()
        },
        port_only=(
            "Backdrop",
            "LeftPanel",
            "ExperienceLabel",
            "MiddlePanel",
            "DropsLabel",
            "ClickHintLabel",
            "MoneyLabel",
            "MoneyValue",
            "ExpLabel",
            "ExpValue",
            "ProceedHintLabel",
            "ProceedButton",
            "RightColumn",
        ),
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
    # The skills frame (spec/107-abilities.md). The tree nodes and the pool
    # are port only here until #237 and #238 record them. StatusLabel has no
    # piece in the SWF.
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
        },
        port_only=(
            "StatusLabel",
            "TreeNodes",
            "PoolBackdrop",
            "PoolRows",
            "ScrollUpButton",
            "ScrollDownButton",
            *(f"Socket{i}" for i in range(8)),
        ),
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
    # The hotbar on the bottom bar. Each Glow is the port's hover, which the SWF
    # draws as a Glow filter on the icon. ZoneInfo is the zone progress, which
    # is port only until #221 records it. Depth 144 is the Armor Games strip
    # 3176.
    "res://scenes/ui/hotbar.tscn": Scene(
        timeline=0,
        frame=HUB_FRAME,
        pieces=HOTBAR_PIECES,
        port_only=(
            "ZoneInfo",
            *(f"{slot}Slot/Glow" for slot in (*HOTBAR_SLOTS, "ZoneMap")),
        ),
        left_out=(144,),
    ),
}


def color_hex(color: tuple[int, int, int, int]) -> str:
    """-> "rrggbbaa", as Godot's Color.to_html() writes it."""
    return "{:02x}{:02x}{:02x}{:02x}".format(*color)


def _scale(matrix) -> tuple[float, float]:
    scale_x, skew0, skew1, scale_y, _tx, _ty = matrix
    if skew0 or skew1:
        raise ValueError(f"matrix {matrix} rotates or skews, and a rect can't hold it")
    return scale_x, scale_y


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


def panel_record(*, bounds, line_width, matrix, origin, fill, line, shadow) -> dict:
    _check_shadow(shadow)
    border = border_width(line_width, _scale(matrix))
    x, y, w, h = fill_rect(bounds, line_width, matrix, origin)
    grow = border / 2
    return {
        "kind": "panel",
        "rect": [round(v, 4) for v in (x - grow, y - grow, w + border, h + border)],
        "fill": color_hex(fill),
        "line": color_hex(line),
        "border": border,
        "shadow": {
            "angle": shadow.angle,
            "blur": shadow.blur_x,
            "distance": shadow.distance,
        },
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


def bottom_bar_source() -> dict:
    """-> the render record of the bottom bar, which extract_battle_screen
    writes as a rect only. Its zoom is that extractor's, and its size is read
    from the PNG."""
    rect = json.loads(battle_screen.LAYOUT_JSON.read_text())["chrome"]["bottom_bar"]
    with Image.open(battle_screen.BATTLE_UI_DIR / "bottom_bar.png") as image:
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
        ("bottom_bar", bottom_bar_source(), BATTLE_TEXTURES),
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
) -> dict:
    """-> the record of the render record `chrome` of piece `name`, whose PNG
    is in the res:// folder `textures`. A rect measured from a sprite is moved
    to the stage by that sprite's origin in `sprite_origins`, keyed as
    "sprite <id>"."""
    relative_to = chrome["relative_to"]
    shift = (0.0, 0.0)
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
        "rect": [round(x + shift[0], 4), round(y + shift[1], 4), w, h],
        "texture": f"{textures}/{name}.png",
        "size": chrome["size"],
        "zoom": chrome["zoom"],
    }


def box_record(bounds, matrix, origin, fill: tuple[int, int, int, int]) -> dict:
    """-> the record of a shape of one solid fill and no line, which the port
    draws as a ColorRect."""
    return {
        "kind": "box",
        "rect": [round(v, 4) for v in stage_rect(bounds, matrix, origin)],
        "fill": color_hex(fill),
    }


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


def button_record(records: list[ButtonRecord], bounds: dict, matrix, origin) -> dict:
    """-> the record of a button that draws art, as the rect of the shapes its
    up state draws, each placed in the button with its record's matrix, and
    the button placed with `matrix`. `bounds` maps each shape to its
    ShapeBounds."""
    up = [r for r in records if "up" in r.states]
    if not up:
        raise ValueError("the button draws nothing in its up state")
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
    return button_record(records, bounds, layer.matrix, origin)


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
    shape = layer.character_id
    if character_kind(index, shape) != "shape":
        raise ValueError(f"box {shape} is not a shape")
    fill = one_solid_fill(shape_styles(index, shape), shape)
    return box_record(shape_bounds(index, shape), layer.matrix, origin, fill)


def origin_of(index: SwfIndex, owner: int) -> tuple[float, float]:
    if owner == 0:
        return 0.0, 0.0
    hub = timeline.frame_of(index, 0, HUB_FRAME)
    return render.placement_origin(index, 0, hub, owner)


def scene_record(index: SwfIndex, scene: Scene) -> dict:
    origin = origin_of(index, scene.timeline)
    frame = timeline.frame_of(index, scene.timeline, scene.frame)
    layers = timeline.frames(index, scene.timeline)[frame - 1]
    art = art_sources()
    pieces = {}
    for path, piece in scene.pieces.items():
        if piece.instance is None:
            layer = layers.get(piece.depth)
            if layer is None:
                raise ValueError(
                    f"{path}: frame {scene.frame} has no depth {piece.depth}"
                )
        else:
            named = [layer for layer in layers.values() if layer.name == piece.instance]
            if len(named) != 1:
                raise ValueError(
                    f"{path}: frame {scene.frame} places {len(named)} instances"
                    f" named {piece.instance}"
                )
            layer = named[0]
        piece_origin = origin
        sprite_origins = {}
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
        if piece.kind == "panel":
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
                entry = moved_art(entry, layer.matrix, rendered.matrix)
            pieces[path] = art_record(piece.art, entry, sprite_origins, textures)
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
        elif piece.kind == "hit":
            pieces[path] = _hit(index, layer, piece_origin)
        else:
            raise ValueError(f"{path}: unknown piece kind {piece.kind!r}")
    return {
        "timeline": scene.timeline,
        "frame": scene.frame,
        "origin": [round(v, 4) for v in origin],
        "port_only": list(scene.port_only),
        "pieces": pieces,
    }


def main():
    index = read_swf(WEB_SWF)
    record = {
        "scenes": {path: scene_record(index, scene) for path, scene in SCENES.items()}
    }
    RECORD.parent.mkdir(parents=True, exist_ok=True)
    RECORD.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

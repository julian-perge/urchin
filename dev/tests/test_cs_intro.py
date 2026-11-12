# extract_cs_intro's checks on SWF bytes built by hand, so no test needs the
# gitignored SWF. Each check says in its docstring what it raises unless, and
# each of those claims has a test here.
from __future__ import annotations

import struct

import pytest
from test_avm1 import (
    END,
    GET_MEMBER,
    GET_VARIABLE,
    SET_MEMBER,
    SET_VARIABLE,
    STOP,
    constant_pool,
    push,
    record,
    script,
)
from test_swf_index import place2, swf, tag
from urchin_dev.swf import avm1, timeline
from urchin_dev.swf.extract import cs_intro
from urchin_dev.swf.swf_index import (
    TAG_DEFINE_SPRITE,
    TAG_DO_ACTION,
    TAG_SHOW_FRAME,
    TAG_SOUND_STREAM_BLOCK,
    parse_swf,
)

ADD2 = b"\x47"

# The pool of a frame script like frame_263/DoAction.as: the variable the script
# sets, then the names it reads the strings through.
FIELD, FIELD_2, ROOT, KRIN_LANG, CHOSEN, MENU = range(6)
READ_NAMES = (
    "introText1",
    "introText2",
    "_root",
    "KrinLang",
    cs_intro.LANGUAGE_VARIABLE,
    "MENU",
)


def menu_statement(
    field: int,
    number: int,
    *,
    root: int = ROOT,
    krin_lang: int = KRIN_LANG,
    chosen: int = CHOSEN,
    menu: int = MENU,
    last_read: bytes = GET_MEMBER,
) -> bytes:
    """`field = root.krin_lang[chosen].menu[number]`, which the original writes
    as `introText1 = _root.KrinLang[KLangChoosen].MENU[86];` with the pool
    indexes it is given."""
    return (
        push(("pool", field), ("pool", root))
        + GET_VARIABLE
        + push(("pool", krin_lang))
        + GET_MEMBER
        + push(("pool", chosen))
        + GET_VARIABLE
        + GET_MEMBER
        + push(("pool", menu))
        + GET_MEMBER
        + push(number)
        + last_read
        + SET_VARIABLE
    )


def frame_script(*statements: bytes, extra_pool: tuple[str, ...] = ()):
    """-> (index, block) for a SWF whose one frame runs stop() and then the
    statements, as frame_263/DoAction.as does."""
    return script(
        constant_pool(*READ_NAMES, *extra_pool) + STOP + b"".join(statements) + END
    )


def test_menu_numbers_are_the_menu_entries_the_frame_script_reads_by_variable():
    index, block = frame_script(menu_statement(FIELD, 86), menu_statement(FIELD_2, 87))
    assert cs_intro.menu_numbers(index, block) == {"introText1": 86, "introText2": 87}


def test_a_frame_script_that_does_more_than_read_menu_entries_is_refused():
    # An Add2 after the statements, which the script would run and the extractor
    # would not see.
    index, block = script(
        constant_pool(*READ_NAMES) + menu_statement(FIELD, 86) + ADD2 + END
    )
    with pytest.raises(RuntimeError, match="not a list of MENU statements"):
        cs_intro.menu_numbers(index, block)


def test_a_frame_script_with_no_menu_statement_is_refused():
    index, block = frame_script()
    with pytest.raises(RuntimeError, match="not a list of MENU statements"):
        cs_intro.menu_numbers(index, block)


def test_a_statement_with_the_actions_of_another_shape_is_refused():
    # The last read is a GetVariable where a MENU statement has a GetMember, so
    # the statement has as many actions as a MENU one and is not one.
    index, block = frame_script(menu_statement(FIELD, 86, last_read=GET_VARIABLE))
    with pytest.raises(RuntimeError, match="not a MENU statement"):
        cs_intro.menu_numbers(index, block)


@pytest.mark.parametrize("changed", ["root", "krin_lang", "chosen", "menu"])
def test_a_statement_that_reads_from_anywhere_but_the_language_table_is_refused(
    changed,
):
    # Each name, in turn, is swapped for another in the pool.
    other = len(READ_NAMES)
    index, block = frame_script(
        menu_statement(FIELD, 86, **{changed: other}), extra_pool=("SYSTEM",)
    )
    with pytest.raises(RuntimeError, match="not a read of _root.KrinLang"):
        cs_intro.menu_numbers(index, block)


def assigned(*entries: tuple[str, int, object]) -> list[avm1.Assignment]:
    """-> the assignments of a script that runs `KrinLang.<language>.MENU[<n>] =
    <value>` for each entry. A value is text or a number."""
    languages = sorted({language for language, _, _ in entries})
    texts = sorted({v for _, _, v in entries if isinstance(v, str)})
    pool = ("KrinLang", "MENU", *languages, *texts)
    body = constant_pool(*pool)
    for language, number, value in entries:
        pushed = ("pool", pool.index(value)) if isinstance(value, str) else value
        body += (
            push(("pool", 0))
            + GET_VARIABLE
            + push(("pool", pool.index(language)))
            + GET_MEMBER
            + push(("pool", 1))
            + GET_MEMBER
            + push(number, pushed)
            + SET_MEMBER
        )
    index, block = script(body + END)
    return avm1.statements(index, block)


def test_menu_strings_are_the_text_set_for_each_entry_of_the_chosen_language():
    strings = cs_intro.menu_strings(
        assigned(
            ("ENGLISH", 86, "One month ago."),
            ("FRENCH", 86, "Il y a un mois."),
            ("ENGLISH", 87, "He remembers nothing."),
        ),
        "ENGLISH",
    )
    assert strings == {86: "One month ago.", 87: "He remembers nothing."}


def test_an_entry_set_to_the_same_text_twice_is_not_a_conflict():
    # Frames 1 and 41 of the original both build the English table.
    strings = cs_intro.menu_strings(
        assigned(("ENGLISH", 86, "One month ago."), ("ENGLISH", 86, "One month ago.")),
        "ENGLISH",
    )
    assert strings == {86: "One month ago."}


def test_an_entry_set_to_something_other_than_text_is_refused():
    with pytest.raises(TypeError, match=r"MENU\[86\] is set to 5, not text"):
        cs_intro.menu_strings(assigned(("ENGLISH", 86, 5)), "ENGLISH")


def test_an_entry_set_to_two_different_texts_is_refused():
    # The line the player sees would depend on which script ran last.
    with pytest.raises(RuntimeError, match=r"MENU\[86\] is set to 'One' and to 'Two'"):
        cs_intro.menu_strings(
            assigned(("ENGLISH", 86, "One"), ("ENGLISH", 86, "Two")), "ENGLISH"
        )


def test_the_conflict_check_leaves_out_the_other_languages():
    strings = cs_intro.menu_strings(
        assigned(("ENGLISH", 86, "One"), ("FRENCH", 86, "Un")), "ENGLISH"
    )
    assert strings == {86: "One"}


def language_assignments(*values: str | int) -> list[avm1.Assignment]:
    """-> the assignments of a script that sets KLangChoosen to each value in
    turn."""
    pool = (cs_intro.LANGUAGE_VARIABLE, *[v for v in values if isinstance(v, str)])
    body = constant_pool(*pool)
    for value in values:
        pushed = ("pool", pool.index(value)) if isinstance(value, str) else value
        body += push(("pool", 0), pushed) + SET_VARIABLE
    index, block = script(body + END)
    return avm1.statements(index, block)


def test_the_language_is_the_one_text_the_scripts_set():
    # Frame 1 and frame 41 both set it, to the same text.
    assert cs_intro.language(language_assignments("ENGLISH", "ENGLISH")) == "ENGLISH"


@pytest.mark.parametrize(
    "values",
    [(), ("ENGLISH", "FRENCH"), (7,)],
    ids=["never set", "set to two texts", "set to a number"],
)
def test_a_language_that_is_not_one_text_is_refused(values):
    with pytest.raises(
        RuntimeError, match=f"want one text in {cs_intro.LANGUAGE_VARIABLE}"
    ):
        cs_intro.language(language_assignments(*values))


TIMER = cs_intro.TIMER
STAND_IN_CHARACTER = 99


def sets(flag: str, value: bool) -> bytes:
    """`_root.<flag> = <value>;` as a sprite's last frame runs it."""
    return (
        constant_pool("_root", flag)
        + push(("pool", 0))
        + GET_VARIABLE
        + push(("pool", 1))
        + record(0x96, bytes([5, value]))
        + SET_MEMBER
        + END
    )


# The timer sprite's last frame in the original is `_root.cutSceneEnd = true;`.
SETS_END = sets(cs_intro.END_VARIABLE, True)
SETS_END_FALSE = sets(cs_intro.END_VARIABLE, False)
SETS_OTHER = sets("otherFlag", True)


def timer_swf(
    *,
    frames: int = 6,
    script_on: tuple[int, ...] = (6,),
    actions: bytes = SETS_END,
    draws: bool = False,
    sound: bool = False,
    placed: bool = True,
) -> bytes:
    """A SWF with sprite 3470 of `frames` frames, whose frames in `script_on`
    run `actions`, and whose first frame draws a shape when `draws` is true and
    streams a sound when `sound` is true. Its one root frame places the sprite
    when `placed` is true."""
    body = b""
    for frame in range(1, frames + 1):
        if frame == 1 and draws:
            body += place2(1, cid=STAND_IN_CHARACTER)
        if frame == 1 and sound:
            body += tag(TAG_SOUND_STREAM_BLOCK, b"\x01\x00\x00\x00data")
        if frame in script_on:
            body += tag(TAG_DO_ACTION, actions)
        body += tag(TAG_SHOW_FRAME)
    sprite = tag(TAG_DEFINE_SPRITE, struct.pack("<HH", TIMER, frames) + body + tag(0))
    return swf(sprite, place2(5, cid=TIMER) if placed else b"", tag(TAG_SHOW_FRAME))


def hold_frames_of(data: bytes) -> int:
    index = parse_swf(data)
    return cs_intro.hold_frames(index, timeline.frames(index, 0)[0])


def test_the_screen_holds_for_the_frame_count_of_its_silent_timer_sprite():
    assert hold_frames_of(timer_swf(frames=6)) == 6


def test_a_frame_that_does_not_place_the_timer_sprite_is_refused():
    with pytest.raises(RuntimeError, match="does not place sprite 3470"):
        hold_frames_of(timer_swf(placed=False))


@pytest.mark.parametrize(
    "script_on",
    [(), (3,), (6, 3)],
    ids=["no script", "script before the last frame", "scripts on two frames"],
)
def test_a_timer_that_runs_anything_but_one_script_on_its_last_frame_is_refused(
    script_on,
):
    with pytest.raises(RuntimeError, match="want its last frame, 6"):
        hold_frames_of(timer_swf(script_on=script_on))


@pytest.mark.parametrize(
    "actions", [SETS_END_FALSE, SETS_OTHER], ids=["sets it false", "sets another flag"]
)
def test_a_last_frame_that_does_not_set_cut_scene_end_to_true_is_refused(actions):
    with pytest.raises(RuntimeError, match="last frame sets"):
        hold_frames_of(timer_swf(actions=actions))


def test_a_timer_that_draws_something_is_refused():
    with pytest.raises(RuntimeError, match="draws something"):
        hold_frames_of(timer_swf(draws=True))


def test_a_timer_that_plays_a_sound_is_refused():
    with pytest.raises(RuntimeError, match="plays a sound"):
        hold_frames_of(timer_swf(sound=True))

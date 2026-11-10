# These tests hand avoid_terms.py glossary text and added lines built by hand,
# so none of them needs a git repository.
from __future__ import annotations

from urchin_dev.checks.avoid_terms import added_lines, avoid_terms, avoided_uses

GLOSSARY = """\
**Shield block**:
A hit the target's shield is bigger than.
_Avoid_: Absorb, a hit for 0

**Battle roster**:
The units placed in one battle.
_Avoid_: Party roster, which is the save's list of companions who have joined
"""


def test_each_avoid_line_gives_its_terms_without_their_explanations():
    assert avoid_terms(GLOSSARY) == ["Absorb", "a hit for 0", "Party roster"]


def test_a_term_matches_as_a_whole_word_in_any_case():
    added = [(3, "It plays A Hit For 0 here."), (4, "The shield absorbed it.")]
    assert avoided_uses("a.md", added, ["Absorb", "a hit for 0"]) == [
        (3, "A Hit For 0")
    ]


def test_only_the_comment_of_a_gdscript_line_is_checked():
    added = [
        (1, 'var absorb := "#absorb"  # A shield block, not an absorb.'),
        (2, "func absorb() -> void:"),
    ]
    assert avoided_uses("a.gd", added, ["Absorb"]) == [(1, "absorb")]


def test_glossary_md_may_name_the_terms_it_warns_against():
    assert avoided_uses("GLOSSARY.md", [(1, "_Avoid_: Absorb")], ["Absorb"]) == []


def test_only_added_lines_are_read_from_a_diff_with_their_new_line_numbers():
    diff = (
        "diff --git a/a.md b/a.md\n--- a/a.md\n+++ b/a.md\n"
        "@@ -3 +3,2 @@\n-old absorb\n+new one\n+new two\n"
        "@@ -9,0 +11 @@\n+new three\n"
    )
    assert list(added_lines(diff)) == [
        (3, "new one"),
        (4, "new two"),
        (11, "new three"),
    ]

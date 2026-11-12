# convert_strings's reading of the KrinLang.ENGLISH table, on an AS sample
# written by hand, so no test needs the SWF or the AS export.
from __future__ import annotations

import pytest
from urchin_dev.convert import strings

SAMPLE = """\
KrinLang = new Object();
KrinLang.ENGLISH = new Object();
KrinLang.ENGLISH.MENU = new Array();
KrinLang.ENGLISH.MENU[0] = "Alpha";
KrinLang.ENGLISH.MENU[2] = "It\\'s \\"quoted\\"";
KrinLang.ENGLISH.MENU[1] = "Beta";
KrinLang.ENGLISH.MENU[1] = "Beta again";
KrinLang.ENGLISH.SHOP = new Array();
KrinLang.ENGLISH.SHOP[0] = "Shop";
KrinLang.ENGLISH.SHOP[3] = 0;
KrinLang.ENGLISH.SKLOAD = "Points";
KrinLang.ENGLISH.BUFFS = new Object();
KrinLang.ENGLISH.BUFFS.RAGE = "Rage ’";
KrinLang.GERMAN = new Object();
KrinLang.GERMAN.MENU = new Array();
KrinLang.GERMAN.MENU[0] = "Ignored"
KLangChoosen = "ENGLISH";
"""


def test_parse_keeps_the_as_index_of_each_entry():
    table = strings.parse_english(SAMPLE)
    assert table["MENU"] == ["Alpha", "Beta again", 'It\'s "quoted"']


def test_parse_leaves_a_hole_as_null_and_keeps_numbers():
    table = strings.parse_english(SAMPLE)
    assert table["SHOP"] == ["Shop", None, None, 0]


def test_parse_reads_scalars_and_nested_objects():
    table = strings.parse_english(SAMPLE)
    assert table["SKLOAD"] == "Points"
    assert table["BUFFS"] == {"RAGE": "Rage ’"}


def test_parse_skips_the_other_languages():
    table = strings.parse_english(SAMPLE)
    assert set(table) == {"MENU", "SHOP", "SKLOAD", "BUFFS"}


def test_parse_fails_on_an_english_line_it_cannot_read():
    with pytest.raises(ValueError, match="line 2"):
        strings.parse_english(
            "KrinLang.ENGLISH.MENU = new Array();\n"
            'KrinLang.ENGLISH.MENU[0] = "a" + "b";\n'
        )


def test_dumps_twice_gives_identical_bytes():
    table = strings.parse_english(SAMPLE)
    assert strings.dumps(table) == strings.dumps(strings.parse_english(SAMPLE))
    assert strings.dumps(table).endswith("\n")

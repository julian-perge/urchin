# convert_battle_hints's reading of the post-battle hint table, on an AS sample
# written by hand, so no test needs the SWF or the AS export.
from __future__ import annotations

import pytest
from urchin_dev.convert import battle_hints

SAMPLE = """\
krinNavHideUI = function(whatToDo)
{
   navTitle = _root.KrinLang[KLangChoosen].NAVTITLE[whatToDo];
};
pggKKuuIIoo = 0;
Krin.bEr = 100;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 504;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 33;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
krinNavTutSpeech = function()
{
   if(Krin.tutSpeecher == false)
   {
      navTitle = Krin.progressSpeech[Krin.previousBattleSp][0];
   }
};
"""


def test_parse_gives_each_battle_the_index_of_its_text_in_the_as():
    assert battle_hints.parse_hints(SAMPLE) == {"100": 0, "504": 1, "33": 2}


def test_parse_keeps_a_battle_whose_text_the_table_lacks():
    # The port skips such a hint when it shows one, so the converter must not.
    assert "33" in battle_hints.parse_hints(SAMPLE)


def test_parse_fails_when_a_block_reads_another_array():
    source = SAMPLE.replace("NAVTEXT2[pggKKuuIIoo]", "NAVTEXT[pggKKuuIIoo]", 1)
    with pytest.raises(ValueError, match="line 9"):
        battle_hints.parse_hints(source)


def test_parse_fails_when_a_slot_reads_the_other_array():
    source = SAMPLE.replace("[0] = _root", "[1] = _root", 1)
    with pytest.raises(ValueError, match="line 8: slot 1 reads NAVTITLE2"):
        battle_hints.parse_hints(source)


def test_parse_fails_when_a_block_has_no_text_line():
    lines = SAMPLE.splitlines()
    del lines[8]
    with pytest.raises(ValueError, match="battle 100"):
        battle_hints.parse_hints("\n".join(lines) + "\n")


def test_parse_fails_on_a_hint_line_it_cannot_read():
    with pytest.raises(ValueError, match="line 2"):
        battle_hints.parse_hints(
            "pggKKuuIIoo = 0;\nKrin.progressSpeech[Krin.bEr][2] = 5;\n"
        )


def test_parse_fails_when_the_as_has_no_hints():
    with pytest.raises(ValueError, match="no hints"):
        battle_hints.parse_hints("krinNavHideUI = function() {};\n")


def test_dumps_twice_gives_identical_bytes():
    table = battle_hints.parse_hints(SAMPLE)
    assert battle_hints.dumps(table) == battle_hints.dumps(
        battle_hints.parse_hints(SAMPLE)
    )
    assert battle_hints.dumps(table).endswith("\n")

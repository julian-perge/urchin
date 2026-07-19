navTitle = "";
navText = "";
Krin.PauseForScreen = false;
Krin.wSaver = krinXbarPro.bar._width;
Krin.levelMaxProgress = parseInt(questHub[Krin.sectionIn].progressMax);
Krin.levelMinProgress = parseInt(Krin.questProgress[Krin.sectionIn]);
if(Krin.levelMinProgress > Krin.levelMaxProgress)
{
   Krin.levelMinProgress = Krin.levelMaxProgress;
}
krinXbarPro.bar._width = Krin.levelMinProgress / Krin.levelMaxProgress * Krin.wSaver;
klt1 = _root.KrinLang[KLangChoosen].SYSTEM[9] + Krin.sectionIn;
klt2 = _root.KrinLang[KLangChoosen].ZONES[Krin.sectionIn] + ": " + _root.KrinLang[KLangChoosen].ZONES2[Krin.sectionIn];
klt3 = _root.KrinLang[KLangChoosen].SYSTEM[10] + (parseInt(Krin.questProgress[Krin.sectionIn]) + 1);
addSound("Music",1);
_root.slotSaveGO = Krin.slotInUse;

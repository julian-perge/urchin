on(rollOver){
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.tt = _root.KrinLang[KLangChoosen].SYSTEM[25];
   _root.KrinToolTipper.t = _root.KrinLang[KLangChoosen].SYSTEM[26];
   _root.KrinToolTipper.gotoAndStop("GO");
}

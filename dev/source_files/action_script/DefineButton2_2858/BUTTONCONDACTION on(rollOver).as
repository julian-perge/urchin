on(rollOver){
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.tt = _root.KrinLang[_root.KLangChoosen].MENU[1];
   _root.KrinToolTipper.t = _root.KrinLang[_root.KLangChoosen].MENU[2];
   _root.KrinToolTipper.gotoAndStop("GO");
}

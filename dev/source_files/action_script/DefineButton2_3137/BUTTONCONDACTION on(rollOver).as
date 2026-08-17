on(rollOver){
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.tt = _root.KrinLang[_root.KLangChoosen].ACH[achNum];
   _root.KrinToolTipper.t = _root.KrinLang[_root.KLangChoosen].ACHDESC[achNum];
   _root.KrinToolTipper.gotoAndStop("GO");
}

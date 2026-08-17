on(rollOver){
   _root.thereIsASlotSelected = true;
   ui_but1.gotoAndPlay("START");
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.tt = _root.KrinLang[KLangChoosen].SYSTEM[17];
   _root.KrinToolTipper.t = _root.KrinLang[KLangChoosen].SYSTEM[18];
   _root.KrinToolTipper.gotoAndStop("GO");
}

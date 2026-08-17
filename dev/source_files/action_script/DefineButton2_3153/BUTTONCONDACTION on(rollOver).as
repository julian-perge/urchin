on(rollOver){
   ui_but7.gotoAndPlay("START");
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.tt = _root.KrinLang[KLangChoosen].SYSTEM[42];
   _root.KrinToolTipper.t = _root.KrinLang[KLangChoosen].SYSTEM[43];
   _root.KrinToolTipper.gotoAndStop("GO");
}

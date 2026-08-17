on(rollOver){
   ui_but3.gotoAndPlay("START");
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.tt = _root.KrinLang[KLangChoosen].SYSTEM[21];
   _root.KrinToolTipper.t = _root.KrinLang[KLangChoosen].SYSTEM[22];
   _root.KrinToolTipper.gotoAndStop("GO");
}

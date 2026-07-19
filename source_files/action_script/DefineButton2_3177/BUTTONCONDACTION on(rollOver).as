on(rollOver){
   ui_but6.gotoAndPlay("START");
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.tt = _root.KrinLang[_root.KLangChoosen].SYSTEM[27];
   _root.KrinToolTipper.t = _root.KrinLang[_root.KLangChoosen].SYSTEM[28];
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   _root.KrinToolTipper.gotoAndStop("GO");
}

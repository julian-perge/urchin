on(rollOver){
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.colorChange = "Common";
   _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
   if(id != 0)
   {
      _root.KrinToolTipper.t = _root.KrinLang[_root.KLangChoosen].MENU[48];
   }
   else
   {
      _root.KrinToolTipper.t = _root.KrinLang[_root.KLangChoosen].MENU[49];
   }
   _root.KrinToolTipper.tt = _root.Krin.NameSets[id];
   _root.KrinToolTipper.gotoAndStop("GO");
}

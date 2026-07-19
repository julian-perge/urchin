on(rollOver){
   psychoDis.gotoAndPlay("START");
   _root.thereIsASlotSelected = true;
   _root.KrinToolTipper.tt = _root.KrinLang[KLangChoosen].CLASS[2];
   if(!_root.gameLimited)
   {
      _root.KrinToolTipper.t = _root.KrinLang[KLangChoosen].CLASSDESCRIPT[2];
   }
   else
   {
      _root.KrinToolTipper.t = _root.KrinLang[KLangChoosen].CLASSDESCRIPT[3];
   }
   _root.KrinToolTipper.gotoAndStop("GO");
}

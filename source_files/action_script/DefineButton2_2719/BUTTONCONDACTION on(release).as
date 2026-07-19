on(release){
   _root.Krin.slotInUse = 4;
   if(_root.Krin.dataMode == "save")
   {
      _root.Krin.nameUser = _root.krinNameUser;
      _root.thereIsASlotSelected = false;
      _root.KrinToolTipper.tt = "";
      _root.KrinToolTipper.t = "";
      _root.KrinToolTipper.gotoAndStop(1);
      gotoAndStop("classMenu");
   }
   else if(_root["slot" + _root.Krin.slotInUse].data.nameUser != undefined)
   {
      _root.krinNameUser = _root["slot" + _root.Krin.slotInUse].data.nameUser;
      _root.krinHandleData(_root.Krin.slotInUse);
      _root["slot" + _root.Krin.slotInUse].flush();
      if(arenaMode == true)
      {
         _root["arenaPlayer" + currentArenaPlayer].krinNameUser = _root.krinNameUser;
         if(currentArenaPlayer == 1)
         {
            currentArenaPlayer++;
            pickText = _root.KrinLang[KLangChoosen].MENU[73];
         }
         else
         {
            gotoAndStop("ArenaNav");
         }
      }
      else
      {
         gotoAndStop("Navigation");
      }
   }
}

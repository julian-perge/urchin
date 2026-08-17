on(release){
   if(_root["slot" + _root.slotSaveGO].data.nameUser != undefined)
   {
      _root.krinHandleData(_root.slotSaveGO);
      _root.Krin.slotInUse = _root.slotSaveGO;
      _root["slot" + _root.slotSaveGO].flush();
      gotoAndStop("Navigation");
   }
   else
   {
      gotoAndStop("mainMenu");
   }
}

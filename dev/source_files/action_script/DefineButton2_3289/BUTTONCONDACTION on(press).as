on(press){
   i = 1;
   while(i < 6)
   {
      _parent["b" + i].COVER.gotoAndStop("BLACK");
      i++;
   }
   COVER.gotoAndStop("WHITE");
   _root["playerKrin" + _parent.pN].agMode = pN;
   _root["playerKrin" + _parent.pN].Aggression = _root.agModeAr1[pN];
   _root["playerKrin" + _parent.pN].LifeBoundary1 = _root.agModeAr2[pN];
   _root["playerKrin" + _parent.pN].LifeBoundary2 = _root.agModeAr3[pN];
   _root["playerKrin" + _parent.pN].FocusAggression = _root.agModeAr4[pN];
   _root["playerKrin" + _parent.pN].FocusRegenLimit = _root.agModeAr5[pN];
}

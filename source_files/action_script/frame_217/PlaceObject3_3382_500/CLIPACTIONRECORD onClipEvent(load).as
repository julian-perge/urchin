onClipEvent(load){
   function refreshOrbs(theGuy)
   {
      i = 0;
      while(i < 8)
      {
         this["thing" + i].gotoAndStop(_root["KRINABILITY" + _root[theGuy].moveMatrix[i]][0]);
         this["thing" + i].toolTipTitle = _root["KRINABILITY" + _root[theGuy].moveMatrix[i]][17];
         this["thing" + i].toolTip = _root["KRINABILITYB" + _root[theGuy].moveMatrix[i]][17];
         this["thing" + i].toolTip3 = _root["KRINABILITYB" + _root[theGuy].moveMatrix[i]][18];
         for(u in _root.elementMainArray)
         {
            if(_root.elementMainArray[u] == _root["KRINABILITYB" + _root[theGuy].moveMatrix[i]][0])
            {
               this["thing" + i].KNcolor2 = _root.elementColorArray[u];
            }
         }
         if(_root["KRINABILITY" + _root[theGuy].moveMatrix[i]][0] == "None")
         {
            this["thingo" + i]._visible = false;
            this["thing" + i].zero = true;
         }
         else
         {
            this["thingo" + i]._visible = true;
         }
         this["thing" + i].assignedThing = i;
         this["thing" + i].ACD = "";
         i++;
      }
   }
   clicker = false;
   _visible = false;
   refreshOrbs("Krin");
   if(_root.arenaMode)
   {
      refreshOrbs("arenaPlayer" + _root.Krin.playerNumber);
   }
}

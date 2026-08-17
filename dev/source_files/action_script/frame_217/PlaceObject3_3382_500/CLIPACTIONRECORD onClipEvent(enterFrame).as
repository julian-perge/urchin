onClipEvent(enterFrame){
   if(clicker)
   {
      if(_root.arenaMode)
      {
         theGuy = "arenaPlayer" + _root.Krin.playerNumber;
      }
      else
      {
         theGuy = "Krin";
      }
      i = 0;
      while(i < 8)
      {
         _root.selector["thing" + i].bfilter._visible = false;
         this["thing" + i].bfilter._alpha = 75;
         if(_root["KRINABILITY" + _root[theGuy].moveMatrix[i]][_root.theEnemyToMoveVS2] == 0)
         {
            _root.selector["thing" + i].bfilter._visible = true;
         }
         if(_root[theGuy].abilityCoolDown[i] > 0)
         {
            this["thing" + i].ACD = _root[theGuy].abilityCoolDown[i];
            _root.selector["thing" + i].bfilter._visible = true;
         }
         else
         {
            this["thing" + i].ACD = "";
         }
         i++;
      }
      if(_alpha < 100)
      {
         _alpha = _alpha + 50;
      }
      else
      {
         _alpha = 100;
         i = 0;
         while(i < 8)
         {
            this["thing" + i].bfilter._alpha = 85;
            i++;
         }
         clicker = false;
      }
   }
   else if(!this.hitTest(_root._xmouse,_root._ymouse))
   {
      _alpha = _alpha - 10;
      i = 0;
      while(i < 8)
      {
         this["thing" + i].ACD = "";
         i++;
      }
      if(_alpha <= 0)
      {
         _visible = false;
      }
   }
   else
   {
      _alpha = 100;
      i = 0;
      while(i < 8)
      {
         _root.selector["thing" + i].bfilter._visible = false;
         this["thing" + i].bfilter._alpha = 85;
         if(_root["KRINABILITY" + _root[theGuy].moveMatrix[i]][_root.theEnemyToMoveVS2] == 0)
         {
            _root.selector["thing" + i].bfilter._visible = true;
         }
         if(_root[theGuy].abilityCoolDown[i] > 0)
         {
            this["thing" + i].ACD = _root[theGuy].abilityCoolDown[i];
            _root.selector["thing" + i].bfilter._visible = true;
         }
         else
         {
            this["thing" + i].ACD = "";
         }
         i++;
      }
   }
}

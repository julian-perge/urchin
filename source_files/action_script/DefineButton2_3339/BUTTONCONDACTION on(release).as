on(release){
   if(!PvPCodeLode)
   {
      Krin.singlePlayer = false;
      Krin.playerNumber = 1;
      turnBasedKrin = true;
      Krin.BattlePick = 1;
      _root.KRS = new Array();
      r = 0;
      while(r < 100)
      {
         _root.KRS[r] = random(100);
         r++;
      }
      _root.KRSC = 0;
      gotoAndStop("LOADBATTLESCENE");
      play();
   }
}

onClipEvent(enterFrame){
   if(prx != undefined)
   {
      avIn.gotoAndStop("mainPlayer");
      if(sLmT2 == 0)
      {
         _root.Krin.PauseForScreen2 = false;
      }
      else
      {
         sLmT2--;
      }
      if(setLimiter > 0)
      {
         if(_root.Krin.LevelStats[prx] < 30)
         {
            setLimiter--;
            exp += adderPer;
            exp2 = Math.round(exp) + "%";
            bar._width = exp / 100 * 95.10000000000001;
            if(exp >= 100)
            {
               _parent.playerLeveled = true;
               exp -= 100;
               exp2 = "100%";
               _root.Krin.LevelStats[prx]++;
               _root.Krin.Level++;
               bar.gotoAndStop("level");
               bar._width = 95.10000000000001;
               levelI = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root.Krin.LevelStats[prx];
               _root.Krin.skillPoints++;
               _root.Krin.statPoints += _root.givePoints(_root.Krin.Level,false);
            }
         }
      }
      else
      {
         _root.Krin.ExpSets[prx] = exp;
      }
   }
}

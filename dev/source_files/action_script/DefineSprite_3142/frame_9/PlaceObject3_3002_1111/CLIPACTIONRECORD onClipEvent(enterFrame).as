onClipEvent(enterFrame){
   if(prx != undefined)
   {
      avIn.gotoAndStop(prx);
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
               exp -= 100;
               exp2 = "100%";
               _root.Krin.LevelStats[prx]++;
               bar.gotoAndStop("level");
               bar._width = 95.10000000000001;
               levelI = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root.Krin.LevelStats[prx];
            }
         }
      }
      else
      {
         _root.Krin.ExpSets[prx] = exp;
      }
   }
}

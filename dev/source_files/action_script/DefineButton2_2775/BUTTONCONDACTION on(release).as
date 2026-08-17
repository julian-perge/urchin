on(release){
   Krin.difficulty++;
   if(Krin.difficulty >= 3)
   {
      Krin.difficulty = 0;
   }
   if(Krin.difficulty == 0)
   {
      t_dif2 = _root.KrinLang[_root.KLangChoosen].MENU[79];
   }
   else if(Krin.difficulty == 1)
   {
      t_dif2 = _root.KrinLang[_root.KLangChoosen].MENU[80];
   }
   else
   {
      t_dif2 = _root.KrinLang[_root.KLangChoosen].MENU[81];
   }
}

on(release){
   if(Krin.tutorOn == false)
   {
      t_tut2 = _root.KrinLang[_root.KLangChoosen].MENU[84];
      Krin.tutorOn = true;
   }
   else
   {
      t_tut2 = _root.KrinLang[_root.KLangChoosen].MENU[83];
      Krin.tutorOn = false;
   }
}

on(release){
   if(!PvPCodeLode)
   {
      exportPvPCode(1);
      krinNavFadeSpeech.gotoAndStop("START");
      krinNavFadeSpeech._visible = true;
      krinNavFadeSpeech.navText = exportPvPArray;
      krinNavFadeSpeech.naxTevt.selectable = true;
      PvPCodeLode = true;
   }
}

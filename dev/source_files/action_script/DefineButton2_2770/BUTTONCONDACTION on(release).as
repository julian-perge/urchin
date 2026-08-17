on(release){
   if(Krin.tutorOn == true)
   {
      _root.gotoSceneKrin = "IntroSeq";
      gotoAndStop("CS_INTRO");
   }
   else
   {
      _root.gotoSceneKrin = "IntroSeq2";
      gotoAndStop("CS_INTRO2");
   }
}

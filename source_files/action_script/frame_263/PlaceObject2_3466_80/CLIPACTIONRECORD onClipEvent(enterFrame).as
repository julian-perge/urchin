onClipEvent(enterFrame){
   if(_root.cutSceneEnd == false)
   {
      if(_alpha > 0)
      {
         _alpha = _alpha - 5;
      }
   }
   else
   {
      _alpha = _alpha + 5;
      if(_alpha >= 100)
      {
         _quality = _root.Krin.qual;
         if(_root.gotoSceneKrin == "endMenu")
         {
            _root.soundModeKrin = 0;
            _root.soundPlayCounter = 0;
         }
         if(_root.gotoSceneKrin == "overMap")
         {
            _root.soundPlayCounter = 0;
            _root.soundModeKrin = 0;
            _root.addSound("Music",1);
         }
         if(_root.gotoSceneKrin == "Navigation")
         {
            _root.soundPlayCounter = 0;
            _root.soundModeKrin = 0;
            _root.addSound("Music",1);
         }
         _root.Krin.cutsceneSequence = 0;
         _root.gotoAndPlay(_root.gotoSceneKrin);
      }
   }
}

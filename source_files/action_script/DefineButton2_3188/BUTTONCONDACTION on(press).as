on(press){
   if(_root.Krin.PauseForScreen != true)
   {
      _root.Krin.bossFight = false;
      _root.Krin.BattlePick = _root.Krin.sectionIn * 100 + _root.Krin.questProgress[_root.Krin.sectionIn];
      _root.Krin.progressFight = true;
      if(_root.Krin.questProgress[_root.Krin.sectionIn] > _root.questHub[_root.Krin.sectionIn].progressMax)
      {
         _root.Krin.usedTraining = true;
         _root.Krin.BattlePick = _root.Krin.sectionIn * 100 + _root.questHub[_root.Krin.sectionIn].progressMax;
         _root.Krin.progressFight = false;
         _root.Krin.bossFight = true;
      }
      if(_root.Krin.questProgress[_root.Krin.sectionIn] == _root.questHub[_root.Krin.sectionIn].progressMax)
      {
         _root.Krin.bossFight = true;
      }
      if(_root.Krin.BattlePick == 109 && _root.Krin.progressFight == true)
      {
         _root.afterCut = "CS_CUT1";
         _root.gotoSceneKrin = "LOADBATTLESCENE";
         stopAllSounds();
         _root.gotoAndPlay("CS_CUT1");
      }
      else
      {
         _root.gotoAndPlay("LOADBATTLESCENE");
      }
      _root.KrinScreen._visible = false;
   }
}

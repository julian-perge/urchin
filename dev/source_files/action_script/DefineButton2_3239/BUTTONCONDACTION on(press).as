on(press){
   if(_root.Krin.PauseForScreen != true)
   {
      _root.Krin.bossFight = false;
      _root.Krin.BattlePick = _root.Krin.sectionIn * 100 + _root.Krin.questProgress[_root.Krin.sectionIn];
      _root.Krin.progressFight = true;
      if(_root.Krin.questProgress[_root.Krin.sectionIn] > _root.questHub[_root.Krin.sectionIn].progressMax)
      {
         _root.Krin.BattlePick = _root.Krin.sectionIn * 100 + _root.questHub[_root.Krin.sectionIn].progressMax - 1;
         _root.Krin.progressFight = false;
         _root.Krin.bossFight = true;
         _root.Krin.usedTraining = true;
      }
      if(_root.Krin.questProgress[_root.Krin.sectionIn] == _root.questHub[_root.Krin.sectionIn].progressMax1)
      {
         _root.Krin.bossFight = true;
      }
      _root.gotoAndPlay("LOADBATTLESCENE");
      _root.KrinScreen._visible = false;
   }
}

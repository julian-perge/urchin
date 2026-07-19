if(Krin.bossFight == true && Krin.progressFight == true)
{
   Krin.bossJustPwned = true;
}
else
{
   Krin.bossJustPwned = false;
}
if(Krin.bossFight == true)
{
   Krin.bossJustPwned2 = true;
}
else
{
   Krin.bossJustPwned2 = false;
}
if(Krin.progressFight == true)
{
   achProgF = true;
}
else
{
   achProgF = false;
}
trace("Sonny attacked = " + AchVal1);
trace("Sonny has team = " + AchVal2);
trace("team member count = " + AchVal3);
trace("turns to win = " + AchVal4);
Krin.bossMusic = false;
Krin.bossFight = false;
afterCut = "None";
if(Krin.progressFight)
{
   Krin.questProgress[Krin.sectionIn]++;
   Krin.progressFight = false;
   if(Krin.BattlePick == 109)
   {
      afterCut = "CS_CUT2";
      gotoSceneKrin = "overMap";
   }
   if(Krin.BattlePick == 210)
   {
      afterCut = "CS_CUT3";
      gotoSceneKrin = "Navigation";
   }
   if(Krin.BattlePick == 409)
   {
      afterCut = "CS_CUT4";
      gotoSceneKrin = "overMap";
   }
   if(Krin.BattlePick == 513)
   {
      afterCut = "CS_CUT5";
      gotoSceneKrin = "endMenu";
   }
}
if(Krin.questProgress[2] > 1)
{
   _root.Krin.friendArray = [0,1,2,-1,-1,-1];
}
if(Krin.questProgress[5] > 4)
{
   _root.Krin.friendArray = [0,1,2,3,-1,-1];
}
if(Krin.BattlePick == 2)
{
   Krin.moveMatrix[0] = Krin.startSkill1;
   Krin.moveMatrix[1] = Krin.startSkill2;
}
Krin.tutSpeecher = false;
Krin.previousBattleSp = Krin.BattlePick;
Mouse.removeListener(someListenerKrin);
if(Krin.cutsceneSequence != 0)
{
   stopAllSounds();
   _root.gotoAndStop(Krin.cutsceneSequence);
}
else
{
   _root.gotoAndStop("Navigation");
}

menuMode = false;
hitTarget = new Array();
i = 0;
while(i < 6)
{
   hitTarget[i] = 0;
   i++;
}
_root.moveToMakeGGTT = 0;
if(turnBasedKrin)
{
}
turnTimeKKK = 0;
turnTimeKKK2 = 0;
nextSpeechKKK = true;
onMouseDown = function()
{
   if(_root.InBattle == false && battleClocker.timerWait == 0 && _root.winCondition < 0 && _root.speechDone == true)
   {
      hitTargetX = 0;
      i = 0;
      while(i < 6)
      {
         if(hitTarget[i])
         {
            hitTargetX = 1;
            _root.theEnemyToMoveVS = _root["KrinSelector" + (i + 1)].TargetEr;
            _root.theEnemyToMoveVS2 = _root["KrinSelector" + (i + 1)].TargetType;
            if(arenaMode)
            {
               _root.selector.refreshOrbs("arenaPlayer" + _root.Krin.playerNumber);
               if(_root.theEnemyToMoveVS == _root.Krin.playerNumber)
               {
                  _root.theEnemyToMoveVS2 = 2;
               }
               if(_root.theEnemyToMoveVS == _root.Krin.playerNumber + 2 || _root.theEnemyToMoveVS == _root.Krin.playerNumber + 4)
               {
                  _root.theEnemyToMoveVS2 = 4;
               }
            }
         }
         i++;
      }
      if(hitTargetX)
      {
         selector._alpha = 0;
         selector._visible = true;
         selector.clicker = true;
         selector._x = HTX;
         selector._y = HTY;
      }
   }
};

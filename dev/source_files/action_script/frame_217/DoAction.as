BattleTime = 120;
BattleTimeLimit = 120;
BattleTimeNow = 0;
InBattle = false;
CurrentMoveID = 0;
_root.hardSkip = false;
_root.nextSpeechKKK = true;
_root.speechDone = false;
MoveArrayFINAL = new Array();
i = 0;
while(i < 9)
{
   MoveArrayFINAL[i] = 0;
   i++;
}
autoMoveK = false;
speechOn = 0;
var someListenerKrin = new Object();
someListenerKrin.onMouseDown = function()
{
   if(!(_root.InBattle == false && battleClocker.timerWait == 0 && _root.winCondition < 0 && _root.speechDone == true))
   {
      _root.KrinCombatText.combatTexter = _root.KrinLang[KLangChoosen].MENU[37];
      _root.KrinCombatText.play();
   }
};
Mouse.addListener(someListenerKrin);

function dressChar(nameOfForm, player_id, standard, model_dress, skin_dress, gender_dress, hair_dress, weapon1_dress, weapon2_dress)
{
   if(standard == "STANDARD")
   {
      model_dress = _root["playerKrin" + player_id].model[0];
      skin_dress = _root["playerKrin" + player_id].model[1];
      gender_dress = _root["playerKrin" + player_id].model[3];
      hair_dress = _root["playerKrin" + player_id].model[2];
   }
   _root["playerKrin" + player_id].dressNow = nameOfForm;
   dollPartsArray = new Array();
   dollPartsArray = ["head","chest","arm1","arm2","hand1","hand2","leg1","leg2","leg3","leg4","foot1","foot2","weapon1","weapon2","shoulder"];
   dollPartsCores = new Array();
   dollPartsCores = [0,1,1,1,2,2,3,3,4,4,4,4,5,6,1];
   dollPartsCores2 = new Array();
   dollPartsCores2 = ["HEAD","CHEST","ARM","ARM","HAND","HAND","ARM","ARM","LEG2","LEG2","FOOT","FOOT","WEAPON","WEAPON","SHOULDER"];
   BATTLESCREEN["player" + player_id].inner.removeMovieClip();
   BATTLESCREEN["player" + player_id].attachMovie(model_dress,"inner",0);
   if(model_dress == "MODEL5")
   {
      BATTLESCREEN["player" + player_id].inner._xscale *= 0.8;
      BATTLESCREEN["player" + player_id].inner._yscale *= 0.8;
      BATTLESCREEN["player" + player_id].inner._y += 10;
   }
   for(h in dollPartsArray)
   {
      BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie(gender_dress + "_S" + dollPartsCores2[h] + "_" + skin_dress,"innerX",-1);
      if(standard == "STANDARD")
      {
         if(_root["playerKrin" + player_id].equip[dollPartsCores[h]] != 0)
         {
            BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie(gender_dress + "_" + dollPartsCores2[h] + "_" + _root["playerKrin" + player_id].equip[dollPartsCores[h]],"inner",0);
         }
         if(_root["playerKrin" + player_id].equip[0] == 0 || _root["playerKrin" + player_id].model[3] == "F")
         {
            BATTLESCREEN["player" + player_id].inner.head.attachMovie("HAIR_" + hair_dress,"hair",2);
         }
         if(h == 12 || h == 13)
         {
            BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie("M_" + dollPartsCores2[h] + "_" + _root["playerKrin" + player_id].equip[dollPartsCores[h]],"inner",0);
         }
      }
      else
      {
         BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie(gender_dress + "_" + dollPartsCores2[h] + "_" + standard,"inner",0);
         if(hair_dress != "")
         {
            BATTLESCREEN["player" + player_id].inner.head.attachMovie("HAIR_" + hair_dress,"hair",2);
         }
         if(h == 12 || h == 13)
         {
            if(h == 12 && weapon1_dress != "")
            {
               BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie("M_" + dollPartsCores2[h] + "_" + weapon1_dress,"inner",0);
            }
            else if(h == 13 && weapon2_dress != "")
            {
               BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie("M_" + dollPartsCores2[h] + "_" + weapon2_dress,"inner",0);
            }
            else
            {
               BATTLESCREEN["player" + player_id].inner[dollPartsArray[h]].attachMovie("M_" + dollPartsCores2[h] + "_" + _root["playerKrin" + player_id].equip[dollPartsCores[h]],"inner",0);
            }
         }
      }
   }
}
function TeamSelect()
{
   Team1Speed = 0;
   Team2Speed = 0;
   Team1Div = 0;
   Team2Div = 0;
   i = 1;
   while(i < 7)
   {
      if(_root["playerKrin" + i].active == true)
      {
         if(Math.pow(-1,i) < 0)
         {
            Team1Speed += _root["playerKrin" + i].SPEEDU;
            Team1Div++;
         }
         else
         {
            Team2Speed += _root["playerKrin" + i].SPEEDU;
            Team2Div++;
         }
      }
      i++;
   }
   Team1Speed /= Team1Div;
   Team2Speed /= Team2Div;
   if(absoluteStart != 0)
   {
      if(absoluteStart == 1)
      {
         Team1Speed = 10000000000000;
      }
      if(absoluteStart == 2)
      {
         Team2Speed = 10000000000000;
      }
      if(Krin.timeLock != true)
      {
         absoluteStart = 0;
      }
   }
   if(Team1Speed > Team2Speed)
   {
      TeamMove = 1;
      s1tm = 0;
      s2tm = 3;
   }
   if(Team2Speed > Team1Speed)
   {
      TeamMove = 2;
      s1tm = 3;
      s2tm = 0;
   }
   if(Team1Speed == Team2Speed)
   {
      if(Krin.singlePlayer)
      {
         TeamMove = 1;
         s1tm = 0;
         s2tm = 3;
      }
      else if(teamSetRandomSpeed > 50)
      {
         TeamMove = 1;
         s1tm = 0;
         s2tm = 3;
      }
      else
      {
         TeamMove = 2;
         s1tm = 3;
         s2tm = 0;
      }
   }
   TurnTime = 2;
   TeamMoveNow = TeamMove;
   TeamSpeedAdder();
   i = 1;
   while(i < 7)
   {
      if(_root["playerKrin" + i].active == true)
      {
         if(_root["playerKrin" + i].teamSide == TeamMoveNow)
         {
            _root["playerKrin" + i].AIGoER = 1;
         }
         else
         {
            _root["playerKrin" + i].AIGoER = 0;
         }
      }
      i++;
   }
   if(arenaMode)
   {
      if(TeamMove == 1)
      {
         _root.Krin.playerNumber = 1;
      }
      else
      {
         _root.Krin.playerNumber = 2;
      }
   }
}
stop();
if(arenaMode)
{
   Krin.player = 2;
}
else
{
   Krin.player = _root["playerKrin" + Krin.playerNumber];
}
i = 1;
while(i < 7)
{
   if(_root["playerKrin" + i].active == false)
   {
      BATTLESCREEN["player" + i]._visible = false;
   }
   else
   {
      dressChar("STANDARD",i,"STANDARD","model","skin","gender","hair","wep1","wep2");
   }
   i++;
}
_root.healedThisTurn = new Array();
i = 1;
while(i < 7)
{
   _root.healedThisTurn[i] = 0;
   i++;
}
Krin.EnemyXP = 0;
Krin.EnemyXP2 = 1;
Krin.EnemyXP3 = 0;
goodSelect = 3;
badSelect = 2;
i = 1;
while(i < 7)
{
   if(arenaMode)
   {
      krinChangeColor(_root["KrinSelector" + i],"Orange");
      if(_root["playerKrin" + i].active == true)
      {
         _root["KrinSelector" + i]._x = _root.BATTLESCREEN["player" + i]._x + _root.BATTLESCREEN._x;
         _root["KrinSelector" + i]._y = _root.BATTLESCREEN["player" + i]._y + _root.BATTLESCREEN._y;
         _root["KrinSelector" + i].TargetEr = i;
         _root["KrinSelector" + i].TargetType = 3;
         _root["KrinSelector" + i].TargetName = _root["playerKrin" + i].playerName;
         _root["KrinSelector" + i].TargetLevel = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root["playerKrin" + i].plevel;
      }
   }
   else if(_root["playerKrin" + i].active == true)
   {
      if(_root["playerKrin" + i].teamSide == Krin.player.teamSide)
      {
         if(_root["playerKrin" + i] == Krin.player)
         {
            KrinSelector1._x = _root.BATTLESCREEN["player" + i]._x + _root.BATTLESCREEN._x;
            KrinSelector1._y = _root.BATTLESCREEN["player" + i]._y + _root.BATTLESCREEN._y;
            KrinSelector1.TargetEr = i;
            KrinSelector1.TargetType = 2;
            KrinSelector1.TargetName = _root["playerKrin" + i].playerName;
            KrinSelector1.TargetLevel = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root["playerKrin" + i].plevel;
         }
         else
         {
            _root["KrinSelector" + goodSelect]._x = _root.BATTLESCREEN["player" + i]._x + _root.BATTLESCREEN._x;
            _root["KrinSelector" + goodSelect]._y = _root.BATTLESCREEN["player" + i]._y + _root.BATTLESCREEN._y;
            _root["KrinSelector" + goodSelect].TargetEr = i;
            _root["KrinSelector" + goodSelect].TargetType = 4;
            _root["KrinSelector" + goodSelect].TargetName = _root["playerKrin" + i].playerName;
            _root["KrinSelector" + goodSelect].TargetLevel = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root["playerKrin" + i].plevel;
            goodSelect += 2;
         }
      }
      else
      {
         _root["KrinSelector" + badSelect]._x = _root.BATTLESCREEN["player" + i]._x + _root.BATTLESCREEN._x;
         _root["KrinSelector" + badSelect]._y = _root.BATTLESCREEN["player" + i]._y + _root.BATTLESCREEN._y;
         Krin.EnemyXP += _root["playerKrin" + i].plevel;
         Krin.EnemyXP2 += 0.2;
         Krin.EnemyXP3 += 1;
         _root["KrinSelector" + badSelect].TargetEr = i;
         _root["KrinSelector" + badSelect].TargetType = 3;
         _root["KrinSelector" + badSelect].TargetName = _root["playerKrin" + i].playerName;
         _root["KrinSelector" + badSelect].TargetLevel = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root["playerKrin" + i].plevel;
         badSelect += 2;
      }
   }
   i++;
}
PlayerToMove = 0;
NextPlayer = false;
MoveEnd = true;
_root.KRRR();
teamSetRandomSpeed = _root.KRSO;
AIGoERSwitch = function()
{
   i = 1;
   while(i < 7)
   {
      if(_root["playerKrin" + i].AIGoER == 0)
      {
         _root["playerKrin" + i].AIGoER = 1;
      }
      else
      {
         _root["playerKrin" + i].AIGoER = 0;
      }
      i++;
   }
};
TeamSpeedAdder = function()
{
   var _loc2_ = new Array();
   _loc2_.push({id:1,speed:_root.playerKrin1.SPEEDU});
   _loc2_.push({id:3,speed:_root.playerKrin3.SPEEDU});
   _loc2_.push({id:5,speed:_root.playerKrin5.SPEEDU});
   _loc2_.sortOn(["speed","id"],[Array.DESCENDING | Array.NUMERIC,Array.DESCENDING | Array.NUMERIC]);
   _root["playerKrin" + _loc2_[0].id].teamAdder = 0;
   _root["playerKrin" + _loc2_[1].id].teamAdder = 1;
   _root["playerKrin" + _loc2_[2].id].teamAdder = 2;
   var _loc3_ = new Array();
   _loc3_.push({id:2,speed:_root.playerKrin2.SPEEDU});
   _loc3_.push({id:4,speed:_root.playerKrin4.SPEEDU});
   _loc3_.push({id:6,speed:_root.playerKrin6.SPEEDU});
   _loc3_.sortOn(["speed","id"],[Array.DESCENDING | Array.NUMERIC,Array.DESCENDING | Array.NUMERIC]);
   _root["playerKrin" + _loc3_[0].id].teamAdder = 0;
   _root["playerKrin" + _loc3_[1].id].teamAdder = 1;
   _root["playerKrin" + _loc3_[2].id].teamAdder = 2;
   _root.AITeamMoveOrder = new Array();
   i = 0;
   while(i < 3)
   {
      _root.AITeamMoveOrder[i + s1tm] = _loc2_[i].id;
      _root.AITeamMoveOrder[i + s2tm] = _loc3_[i].id;
      i++;
   }
};
TeamSelect();
PrevTeam = TeamMove;
i = 1;
while(i < 7)
{
   krinAddMove(i,i,0);
   i++;
}

function AImoveAdder(p)
{
   pg = _root["playerKrin" + p];
   if(pg.AIAD == false)
   {
      gMtYuIo = pg.teamSide;
      checkerForFriends = 0;
      if(_root["playerKrin" + gMtYuIo].active == true && gMtYuIo != p)
      {
         checkerForFriends = 1;
         numberLockKrin = gMtYuIo;
         focusCheck = _root["playerKrin" + gMtYuIo].FOCUSN;
         playerFocusCheck = gMtYuIo;
      }
      if(_root["playerKrin" + (gMtYuIo + 2)].active == true && gMtYuIo + 2 != p)
      {
         checkerForFriends = 1;
         numberLockKrin = gMtYuIo + 2;
         if(_root["playerKrin" + (gMtYuIo + 2)].FOCUSN < focusCheck)
         {
            focusCheck = _root["playerKrin" + (gMtYuIo + 2)].FOCUSN;
            playerFocusCheck = gMtYuIo + 2;
         }
      }
      if(_root["playerKrin" + (gMtYuIo + 4)].active == true && gMtYuIo + 4 != p)
      {
         checkerForFriends = 1;
         numberLockKrin = gMtYuIo + 4;
         if(_root["playerKrin" + (gMtYuIo + 4)].FOCUSN < focusCheck)
         {
            focusCheck = _root["playerKrin" + (gMtYuIo + 4)].FOCUSN;
            playerFocusCheck = gMtYuIo + 4;
         }
      }
      moveFilterABS0 = new Array();
      moveFilterABS1 = new Array();
      parallelFilterABS = new Array();
      parallelFilterABS2 = new Array();
      for(i in pg.CDArrayABS)
      {
         if(pg.CDArrayABS[i] == 0)
         {
            if(pg.moveArrayABS[i][1] == 0 || pg.moveArrayABS[i][1] == _root.phase)
            {
               moveFilterABS0.push(pg.moveArrayABS[i][0]);
               parallelFilterABS.push(i);
            }
         }
      }
      for(i in moveFilterABS0)
      {
         if(_root["KRINABILITY" + moveFilterABS0[i]][5] * pg.SILENCED == 0 && pg.FOCUSN >= _root["KRINABILITY" + moveFilterABS0[i]][5] && pg.LIFEN > _root["KRINABILITY" + moveFilterABS0[i]][6] + Math.round(pg.LIFEU * _root["KRINABILITY" + moveFilterABS0[i]][16]))
         {
            if(_root["KRINABILITY" + moveFilterABS0[i]][2] + _root["KRINABILITY" + moveFilterABS0[i]][3] > 0 || checkerForFriends == 1)
            {
               moveFilterABS1.push(moveFilterABS0[i]);
               parallelFilterABS2.push(parallelFilterABS[i]);
            }
         }
      }
      moveFilterA0 = new Array();
      moveFilterA1 = new Array();
      moveFilterA2 = new Array();
      parallelFilterA = new Array();
      parallelFilterA2 = new Array();
      parallelFilterA3 = new Array();
      moveFilterD0 = new Array();
      moveFilterD1 = new Array();
      moveFilterD2 = new Array();
      parallelFilterD = new Array();
      parallelFilterD2 = new Array();
      parallelFilterD3 = new Array();
      if(moveFilterABS1.length < 1)
      {
         useABS = false;
         for(var i in pg.CDArrayA)
         {
            if(pg.CDArrayA[i] == 0)
            {
               moveFilterA0.push(pg.moveArrayA[i]);
               parallelFilterA.push(i);
            }
         }
         focusMove = false;
         for(i in moveFilterA0)
         {
            if(_root["KRINABILITY" + moveFilterA0[i]][5] * pg.SILENCED == 0 && pg.FOCUSN >= _root["KRINABILITY" + moveFilterA0[i]][5] && pg.LIFEN > _root["KRINABILITY" + moveFilterA0[i]][6] + Math.round(pg.LIFEU * _root["KRINABILITY" + moveFilterA0[i]][16]))
            {
               if(_root["KRINABILITY" + moveFilterA0[i]][14] != "Focus" || _root["KRINABILITY" + moveFilterA0[i]][4] > 0 && focusCheck < pg.FocusRegenLimit || _root["KRINABILITY" + moveFilterA0[i]][2] > 0 && pg.FOCUSN < pg.FocusRegenLimit)
               {
                  moveFilterA1.push(moveFilterA0[i]);
                  parallelFilterA2.push(parallelFilterA[i]);
                  if(_root["KRINABILITY" + moveFilterA0[i]][4] > 0 && focusCheck < pg.FocusRegenLimit)
                  {
                     if(playerFocusCheck != p)
                     {
                        focusMove = true;
                        focusSelectNum = i;
                     }
                  }
                  if(_root["KRINABILITY" + moveFilterA0[i]][2] > 0 && pg.FOCUSN < pg.FocusRegenLimit)
                  {
                     focusMove = true;
                     focusSelectNum = i;
                     playerFocusCheck = p;
                  }
               }
            }
         }
         for(i in moveFilterA1)
         {
            if(_root["KRINABILITY" + moveFilterA1[i]][2] + _root["KRINABILITY" + moveFilterA1[i]][3] > 0 || checkerForFriends == 1)
            {
               moveFilterA2.push(moveFilterA1[i]);
               parallelFilterA3.push(parallelFilterA2[i]);
            }
         }
         for(var i in pg.CDArrayD)
         {
            if(pg.CDArrayD[i] == 0)
            {
               moveFilterD0.push(pg.moveArrayD[i]);
               parallelFilterD.push(i);
            }
         }
         for(i in moveFilterD0)
         {
            if(_root["KRINABILITY" + moveFilterD0[i]][5] * pg.SILENCED == 0 && pg.FOCUSN >= _root["KRINABILITY" + moveFilterD0[i]][5] && pg.LIFEN > _root["KRINABILITY" + moveFilterD0[i]][6] + Math.round(pg.LIFEU * _root["KRINABILITY" + moveFilterD0[i]][16]))
            {
               moveFilterD1.push(moveFilterD0[i]);
               parallelFilterD2.push(parallelFilterD[i]);
            }
         }
         D_Array_F = new Array();
         D_Array_S = new Array();
         D_Array_E = new Array();
         D_Array_E_PARA = new Array();
         D_Array_F_PARA = new Array();
         D_Array_S_PARA = new Array();
         for(i in moveFilterD1)
         {
            if(_root["KRINABILITY" + moveFilterD1[i]][2] + _root["KRINABILITY" + moveFilterD1[i]][3] > 0 || checkerForFriends == 1)
            {
               moveFilterD2.push(moveFilterD1[i]);
               parallelFilterD3.push(parallelFilterD2[i]);
               if(_root["KRINABILITY" + moveFilterD1[i]][4] == 1)
               {
                  D_Array_F.push(moveFilterD1[i]);
                  D_Array_F_PARA.push(parallelFilterD2[i]);
               }
               if(_root["KRINABILITY" + moveFilterD1[i]][2] == 1)
               {
                  D_Array_S.push(moveFilterD1[i]);
                  D_Array_S_PARA.push(parallelFilterD2[i]);
               }
               if(_root["KRINABILITY" + moveFilterD1[i]][3] == 1)
               {
                  D_Array_E.push(moveFilterD1[i]);
                  D_Array_E_PARA.push(parallelFilterD2[i]);
               }
            }
         }
      }
      else
      {
         useABS = true;
      }
      AIATTACKMODE = true;
      ScriptEnderKAIA = false;
      if(moveFilterA2.length == 0)
      {
         ScriptEnderKAIA = true;
         AIATTACKMODE = false;
      }
      if(moveFilterD2.length == 0)
      {
         ScriptEnderKAIA = true;
      }
      LifeFullAIChecker = 0;
      LifeFullAITotal = 0;
      if(_root["playerKrin" + gMtYuIo].active)
      {
         LifeFullAITotal += _root["playerKrin" + gMtYuIo].LIFEU;
         LifeFullAIChecker += _root["playerKrin" + gMtYuIo].LIFEU - (_root["playerKrin" + gMtYuIo].LIFEN + _root.healedThisTurn[gMtYuIo]);
      }
      if(_root["playerKrin" + (gMtYuIo + 2)].active)
      {
         LifeFullAITotal += _root["playerKrin" + (gMtYuIo + 2)].LIFEU;
         LifeFullAIChecker += _root["playerKrin" + (gMtYuIo + 2)].LIFEU - (_root["playerKrin" + (gMtYuIo + 2)].LIFEN + _root.healedThisTurn[gMtYuIo + 2]);
      }
      if(_root["playerKrin" + (gMtYuIo + 4)].active)
      {
         LifeFullAITotal += _root["playerKrin" + (gMtYuIo + 4)].LIFEU;
         LifeFullAIChecker += _root["playerKrin" + (gMtYuIo + 4)].LIFEU - (_root["playerKrin" + (gMtYuIo + 4)].LIFEN + _root.healedThisTurn[gMtYuIo + 4]);
      }
      krinAITargetCheckedHEALTEST = false;
      if(_root["playerKrin" + gMtYuIo].active)
      {
         tarToBe = gMtYuIo;
         if(tarToBe == pg.playerID)
         {
            if(D_Array_S.length + D_Array_E.length > 0)
            {
               krinAITargetCheckedHEALTEST = tarToBe;
            }
         }
         else if(D_Array_F.length + D_Array_E.length > 0)
         {
            krinAITargetCheckedHEALTEST = tarToBe;
         }
      }
      if(_root["playerKrin" + (gMtYuIo + 2)].active)
      {
         if(krinAITargetCheckedHEALTEST == false || _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEN == _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEU || (_root["playerKrin" + (gMtYuIo + 2)].LIFEN + _root.healedThisTurn[gMtYuIo + 2]) / _root["playerKrin" + (gMtYuIo + 2)].LIFEU <= (_root["playerKrin" + gMtYuIo].LIFEN + _root.healedThisTurn[gMtYuIo]) / _root["playerKrin" + gMtYuIo].LIFEU)
         {
            tarToBe = gMtYuIo + 2;
            if(tarToBe == pg.playerID)
            {
               if(D_Array_S.length + D_Array_E.length > 0)
               {
                  krinAITargetCheckedHEALTEST = tarToBe;
               }
            }
            else if(D_Array_F.length + D_Array_E.length > 0)
            {
               krinAITargetCheckedHEALTEST = tarToBe;
            }
         }
      }
      if(_root["playerKrin" + (gMtYuIo + 4)].active)
      {
         if(krinAITargetCheckedHEALTEST == false || _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEN == _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEU || (_root["playerKrin" + (gMtYuIo + 4)].LIFEN + _root.healedThisTurn[gMtYuIo + 4]) / _root["playerKrin" + (gMtYuIo + 4)].LIFEU <= (_root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEN + _root.healedThisTurn[krinAITargetCheckedHEALTEST]) / _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEU)
         {
            tarToBe = gMtYuIo + 4;
            if(tarToBe == pg.playerID)
            {
               if(D_Array_S.length + D_Array_E.length > 0)
               {
                  krinAITargetCheckedHEALTEST = tarToBe;
               }
            }
            else if(D_Array_F.length + D_Array_E.length > 0)
            {
               krinAITargetCheckedHEALTEST = tarToBe;
            }
         }
      }
      lifeNumToCheck = _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEN / _root["playerKrin" + krinAITargetCheckedHEALTEST].LIFEU;
      if(!ScriptEnderKAIA)
      {
         LifeAICR = lifeNumToCheck * 100;
         if(LifeAICR <= pg.LifeBoundary1)
         {
            if(LifeAICR <= pg.LifeBoundary2)
            {
               AIATTACKMODE = false;
            }
            else
            {
               _root.KRRR();
               if(pg.Aggression >= _root.KRSO)
               {
                  AIATTACKMODE = true;
               }
               else
               {
                  AIATTACKMODE = false;
               }
            }
         }
      }
      if(useABS != true)
      {
         if(AIATTACKMODE == true)
         {
            if(focusMove)
            {
               selectedMoveToMake = moveFilterA0[focusSelectNum];
               CDtoPUT = parallelFilterA[focusSelectNum];
            }
            else
            {
               MoveSelectBits = 100 / moveFilterA2.length;
               _root.KRRR();
               counterFilter = Math.ceil(_root.KRSO / MoveSelectBits) - 1;
               if(counterFilter < 0)
               {
                  counterFilter = 0;
               }
               selectedMoveToMake = moveFilterA2[counterFilter];
               CDtoPUT = parallelFilterA3[counterFilter];
            }
         }
         else
         {
            focusMove = false;
            moveD_final = new Array();
            moveD_final = moveFilterD2;
            moveD_final_para = new Array();
            moveD_final_para = parallelFilterD3;
            if(krinAITargetCheckedHEALTEST != false)
            {
               moveFilterD2 = new Array();
               parallelFilterD3 = new Array();
               for(iujk in moveD_final)
               {
                  if(pg.playerID == krinAITargetCheckedHEALTEST)
                  {
                     if(_root["KRINABILITY" + moveD_final[iujk]][2] + _root["KRINABILITY" + moveD_final[iujk]][3] > 0)
                     {
                        moveFilterD2.push(moveD_final[iujk]);
                        parallelFilterD3.push(moveD_final_para[iujk]);
                     }
                  }
                  else if(_root["KRINABILITY" + moveD_final[iujk]][4] + _root["KRINABILITY" + moveD_final[iujk]][3] > 0)
                  {
                     moveFilterD2.push(moveD_final[iujk]);
                     parallelFilterD3.push(moveD_final_para[iujk]);
                  }
               }
            }
            MoveSelectBits = 100 / moveFilterD2.length;
            _root.KRRR();
            counterFilter = Math.ceil(_root.KRSO / MoveSelectBits) - 1;
            if(counterFilter < 0)
            {
               counterFilter = 0;
            }
            selectedMoveToMake = moveFilterD2[counterFilter];
            CDtoPUT = parallelFilterD3[counterFilter];
         }
      }
      else
      {
         MoveSelectBits = 100 / moveFilterABS1.length;
         _root.KRRR();
         counterFilter = Math.ceil(_root.KRSO / MoveSelectBits) - 1;
         if(counterFilter < 0)
         {
            counterFilter = 0;
         }
         selectedMoveToMake = moveFilterABS1[counterFilter];
         CDtoPUT = parallelFilterABS2[counterFilter];
      }
      krinAITargetChecked = 0;
      if(_root["KRINABILITY" + selectedMoveToMake][2] == 1)
      {
         krinAITargetChecked = p;
      }
      if(_root["KRINABILITY" + selectedMoveToMake][3] == 1)
      {
         aliveEnemies = new Array();
         gMtYuIo = pg.teamSide;
         weakestEnemyNow = 0;
         if(_root["playerKrin" + (7 - gMtYuIo)].active == true)
         {
            aliveEnemies.push(7 - gMtYuIo);
            weakestEnemyNow = 7 - gMtYuIo;
         }
         if(_root["playerKrin" + (5 - gMtYuIo)].active == true)
         {
            aliveEnemies.push(5 - gMtYuIo);
            if(_root["playerKrin" + (5 - gMtYuIo)].LIFEN + _root["playerKrin" + (5 - gMtYuIo)].SHIELD < _root["playerKrin" + weakestEnemyNow].LIFEN + _root["playerKrin" + weakestEnemyNow].SHIELD || weakestEnemyNow == 0)
            {
               weakestEnemyNow = 5 - gMtYuIo;
            }
         }
         if(_root["playerKrin" + (3 - gMtYuIo)].active == true)
         {
            aliveEnemies.push(3 - gMtYuIo);
            if(_root["playerKrin" + (3 - gMtYuIo)].LIFEN + _root["playerKrin" + (3 - gMtYuIo)].SHIELD < _root["playerKrin" + weakestEnemyNow].LIFEN + _root["playerKrin" + weakestEnemyNow].SHIELD || weakestEnemyNow == 0)
            {
               weakestEnemyNow = 3 - gMtYuIo;
            }
         }
         _root.KRRR();
         if(_root.KRSO < pg.FocusAggression)
         {
            krinAITargetChecked = weakestEnemyNow;
         }
         else
         {
            MoveSelectBits2 = 100 / aliveEnemies.length;
            _root.KRRR();
            counterFilter1 = Math.ceil(_root.KRSO / MoveSelectBits2) - 1;
            if(counterFilter1 < 0)
            {
               counterFilter1 = 0;
            }
            krinAITargetChecked = aliveEnemies[counterFilter1];
         }
      }
      if(_root["KRINABILITY" + selectedMoveToMake][4] == 1 && (krinAITargetChecked == 0 || krinAITargetChecked == p))
      {
         IDKC = _root["playerKrin" + p];
         IDKM2 = _root["KRINABILITYB" + selectedMoveToMake];
         healGuesserK = IDKM2[10] * ((IDKC.STRENGTHU + IDKM2[1]) * IDKM2[2] + (IDKC.MAGICU + IDKM2[3]) * IDKM2[4] + (IDKC.SPEEDU + IDKM2[5]) * IDKM2[6] + IDKC.FOCUSN * IDKM2[11] + IDKM2[9]);
         krinAITargetChecked = krinAITargetCheckedHEALTEST;
         _root.healedThisTurn[krinAITargetChecked] += healGuesserK;
      }
      if(_root["KRINABILITY" + selectedMoveToMake][4] == 1 && _root["KRINABILITY" + selectedMoveToMake][2] == 0)
      {
         krinAITargetChecked = numberLockKrin;
      }
      if(focusMove)
      {
         krinAITargetChecked = playerFocusCheck;
      }
      if(selectedMoveToMake == undefined)
      {
         _root.krinAddMove(p,p,0);
      }
      else if(aliveEnemies.length == 0)
      {
         _root.krinAddMove(p,p,0);
      }
      else
      {
         if(useABS != true)
         {
            if(AIATTACKMODE == true)
            {
               pg.AI_CD_ARR = "CDArrayA";
               pg.AI_CD_PUT = CDtoPUT;
            }
            else
            {
               pg.AI_CD_ARR = "CDArrayD";
               pg.AI_CD_PUT = CDtoPUT;
            }
         }
         else
         {
            pg.AI_CD_ARR = "CDArrayABS";
            pg.AI_CD_PUT = CDtoPUT;
         }
         if(krinAITargetChecked == 0)
         {
            krinAITargetChecked = aliveEnemies[counterFilter1];
         }
         _root.krinAddMove(p,krinAITargetChecked,selectedMoveToMake);
      }
   }
}
LowerCD = function(a)
{
   k = 0;
   while(k < 20)
   {
      if(_root["playerKrin" + a].CDArrayD[k] > 0)
      {
         _root["playerKrin" + a].CDArrayD[k]--;
      }
      if(_root["playerKrin" + a].CDArrayA[k] > 0)
      {
         _root["playerKrin" + a].CDArrayA[k]--;
      }
      if(_root["playerKrin" + a].CDArrayABS[k] > 0)
      {
         _root["playerKrin" + a].CDArrayABS[k]--;
      }
      k++;
   }
};

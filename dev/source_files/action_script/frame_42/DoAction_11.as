function addMoveForPlayer(txvd)
{
   var _loc3_;
   if(menuMode)
   {
      theGuy = "Krin";
      if(UITmouseHold == 0)
      {
         _root[theGuy].moveMatrix[txvd] = 0;
      }
      else
      {
         tracer = 0;
         o = 0;
         while(o < 8)
         {
            if(_root[theGuy].moveMatrix[o] == UITmouseHold)
            {
               tracer++;
            }
            o++;
         }
         if(tracer < _root["KRINABILITY" + UITmouseHold][8])
         {
            _root[theGuy].moveMatrix[txvd] = UITmouseHold;
         }
         else
         {
            KrinCombatText.combatTexter = _root.KrinLang[KLangChoosen].SKILLERROR;
            KrinCombatText.play();
         }
         UITmouseHold = 0;
      }
      _root.KrinToolTipper.inner2.gotoAndStop(_root["KRINABILITY" + _root.UITmouseHold][0]);
      _root.KrinToolTipper.inner2.ACD = "";
      unloadMovie(_root.KrinToolTipper.inner2.bfilter);
      for(u in _root.elementMainArray)
      {
         if(_root.elementMainArray[u] == _root["KRINABILITYB" + _root.UITmouseHold][0])
         {
            _root.KrinToolTipper.inner2.KNcolor2 = _root.elementColorArray[u];
         }
      }
      KRINMENU.KrinCreateAbilityMatrix();
   }
   else
   {
      if(arenaMode)
      {
         theGuy = "arenaPlayer" + Krin.playerNumber;
      }
      else
      {
         theGuy = "Krin";
      }
      checkPassforKrinMove = true;
      rovnrevbnr = _root["playerKrin" + Krin.playerNumber];
      mAry5 = _root["KRINABILITY" + _root[theGuy].moveMatrix[txvd]];
      mAry6 = _root["KRINABILITYB" + _root[theGuy].moveMatrix[txvd]];
      if(checkBuffsOnUnit(mAry6[23],mAry6[24],_root.theEnemyToMoveVS))
      {
         checkPassforKrinMove = false;
         KrinCombatText.combatTexter = "The target\'s status does not meet the requirements of this move.";
      }
      if(rovnrevbnr.FOCUSN < mAry5[5])
      {
         checkPassforKrinMove = false;
         KrinCombatText.combatTexter = "You cannot use this move because you don\'t have enough Focus.";
      }
      if(mAry5[5] * rovnrevbnr.SILENCED != 0)
      {
         checkPassforKrinMove = false;
         KrinCombatText.combatTexter = "You cannot use moves that require Focus this turn.";
      }
      if(_root[theGuy].abilityCoolDown[txvd] != 0)
      {
         checkPassforKrinMove = false;
         KrinCombatText.combatTexter = "This move is not ready yet.";
      }
      if(rovnrevbnr.LIFEN <= mAry5[6] + Math.round(rovnrevbnr.LIFEU * mAry5[16]))
      {
         checkPassforKrinMove = false;
         KrinCombatText.combatTexter = "You cannot use this move because you don\'t have enough Health.";
      }
      if(mAry5[_root.theEnemyToMoveVS2] == 0)
      {
         checkPassforKrinMove = false;
         KrinCombatText.combatTexter = "You cannot use this move on that target.";
      }
      if(checkPassforKrinMove)
      {
         if(mAry5[14] == "Heal" || mAry5[10] == "DispelF")
         {
            _root.healedThisTurn[_root.theEnemyToMoveVS] += mAry6[10] * ((rovnrevbnr.STRENGTHU + mAry6[1]) * mAry6[2] + (rovnrevbnr.MAGICU + mAry6[3]) * mAry6[4] + (rovnrevbnr.SPEEDU + mAry6[5]) * mAry6[6] + rovnrevbnr.FOCUSN * mAry6[11] + mAry6[9]);
         }
         _root.moveCoolDownBreaker = txvd;
         _root.krinAddMove(Krin.playerNumber,_root.theEnemyToMoveVS,_root[theGuy].moveMatrix[txvd]);
         if(!_root.turnBasedKrin)
         {
            _root.BattleTimeNow = _root.BattleTimeLimit - 5;
         }
         _root.UI_BAR.subAI_BAR.gotoAndStop("HIDE");
         _root.moveChoosen = true;
         _root.selector._visible = false;
         _root.krinToMove._visible = true;
         _root.krinToMove2._visible = true;
         _root.krinToMove.gotoAndStop(mAry5[0]);
         _root.krinToMove.toolTipTitle = mAry5[0];
         _root.krinToMove.toolTip = "You will use this ability on " + _root["playerKrin" + _root.theEnemyToMoveVS].playerName + ". Click to cancel this ability.";
         _root.moveToMakeGGTT = _root[theGuy].moveMatrix[txvd];
         for(u in _root.elementMainArray)
         {
            if(_root.elementMainArray[u] == _root["KRINABILITYB" + _root[theGuy].moveMatrix[txvd]][0])
            {
               KNcolor3 = _root.elementColorArray[u];
               _root.krinToMove.KNcolor2 = KNcolor3;
            }
         }
         _loc3_ = new Color(_root.krinToMove.moveColor);
         _loc3_.setRGB(KNcolor3);
         moveSelectBoomer.play();
      }
      else
      {
         KrinCombatText.gotoAndPlay("GO");
      }
   }
}
function checkBuffsOnUnit(n_element, n_numberNeed, n_target)
{
   mTarget2 = _root["playerKrin" + n_target];
   testNumberUp = 0;
   krin_u = 0;
   while(krin_u < _root.maxBuffLimit)
   {
      if(mTarget2.BUFFARRAYK[krin_u].CD > 0 && n_element == _root["KRINBUFF" + mTarget2.BUFFARRAYK[krin_u].buffId][1])
      {
         testNumberUp++;
      }
      krin_u++;
   }
   if(testNumberUp < n_numberNeed)
   {
      return true;
   }
}

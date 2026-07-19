function executeMove(IDKM, IDKM2, IDKC, IDKT)
{
   AVGNUMC = 100 + 15 * IDKC.plevel;
   SPEEDCRITCALC = IDKC.SPEEDU / getStat(10,IDKC.plevel) - 1;
   PERCALK = IDKC.PERU[IDKM2[0]] / AVGNUMC;
   DEFCALK = IDKT.DEFU[IDKM2[0]] / AVGNUMC;
   if(DEFCALK <= 0)
   {
      DEFCALK = 0.1;
   }
   if(PERCALK <= 0)
   {
      PERCALK = 0.1;
   }
   CRITCALC_X = PERCALK / DEFCALK;
   if(CRITCALC_X > 10)
   {
      CRITCALC_X = 10;
   }
   PERCOEF = 1;
   _root.perKSuccess = false;
   focusCoEF = IDKM2[25] + IDKC.FOCUSN / 100 * IDKM2[11];
   if(IDKM[14] == "Full Damage")
   {
      numberOutputInner1 = (IDKC.STRENGTHU + IDKM2[1]) * IDKM2[2] + (IDKC.MAGICU + IDKM2[3]) * IDKM2[4] + (IDKC.SPEEDU + IDKM2[5]) * IDKM2[6] + IDKM2[9];
      coEFKN6723 = IDKM2[10];
      perScript(PERCALK,DEFCALK,IDKM2);
      if(_root.perKSuccess)
      {
         _root.GridShaker.play();
         coEFKN6724 = 0.016666667 * Math.pow(CRITCALC_X + 1,4) - 0.25 * Math.pow(CRITCALC_X + 1,3) + 1.233333 * Math.pow(CRITCALC_X + 1,2) - 1.9000000000000001 * (CRITCALC_X + 1) + 1.9000000000000001;
         if(coEFKN6724 < 0)
         {
            coEFKN6724 = 0;
         }
         if(IDKC.playerName == "Veradux")
         {
            _root.addSound("Effects","Angry_Dux");
         }
         if(IDKC.playerName == "Roald")
         {
            _root.addSound("Effects","Angry_Roald");
         }
      }
      else
      {
         if(CRITCALC_X <= 1)
         {
            coEFKN6724 = CRITCALC_X;
         }
         else
         {
            coEFKN6724 = 1 + 0.07 * (PERCALK - DEFCALK);
         }
         if(coEFKN6724 <= 0)
         {
            coEFKN6724 = 0.01;
         }
      }
      _root.DamageOutputKrinFinal = Math.ceil(IDKC.DMG + IDKT.IDMG + numberOutputInner1 * focusCoEF * coEFKN6723 * coEFKN6724 * (1 + IDKC.DMG2) * (1 + IDKT.IDMG2) * IDKT.IDMGP2);
      if(_root.DamageOutputKrinFinal <= 0 || _root.DamageOutputKrinFinal == NaN)
      {
         _root.DamageOutputKrinFinal = 1;
      }
      differenceForSH = 0;
      if(IDKT.SHIELD > 0)
      {
         differenceForSH = IDKT.SHIELD - _root.DamageOutputKrinFinal;
      }
      if(differenceForSH > 0)
      {
         IDKT.SHIELD -= _root.DamageOutputKrinFinal;
         _root.BATTLESCREEN["player" + IDKT.playerID].shield.play();
         _root.addSound("Effects","sfx_shield");
         _root.KrinNumberShow("shield","player" + IDKT.playerID,IDKM2[0]);
      }
      else
      {
         _root.DamageOutputKrinFinal -= IDKT.SHIELD;
         _root.KrinNumberShow(_root.DamageOutputKrinFinal,"player" + IDKT.playerID,IDKM2[0]);
         IDKT.SHIELD = 0;
         if(IDKT.SSWITCH == 0)
         {
            _root.KrinNumberShow(_root.DamageOutputKrinFinal,"player" + IDKT.playerID,IDKM2[0]);
            IDKT.LIFEN -= _root.DamageOutputKrinFinal;
            if(IDKT.LIFEN <= 0)
            {
               IDKT.LIFEN = 0;
               IDKT.FOCUSN = 0;
            }
            if(IDKC.playerName == "Sonny")
            {
               AchVal1 += _root.DamageOutputKrinFinal;
            }
            _root.BATTLEFLASH.hitTarget = _root.BATTLESCREEN["player" + IDKT.playerID];
            _root.BATTLEFLASH.DFTC = IDKT.characterColorState;
            _root.BATTLEFLASH.DFTF = IDKT.characterFilterState;
            _root.BATTLEFLASH.DFTP = IDKT;
            _root.BATTLEFLASH.gotoAndPlay("hit");
            if(IDKT.STUN == 0)
            {
               _root.BATTLESCREEN["player" + IDKT.playerID].inner.gotoAndPlay("hit");
            }
            if(IDKT.LIFEN == 0)
            {
               _root.BATTLESCREEN["player" + IDKT.playerID].inner.gotoAndPlay("dead");
               IDKT.active = false;
               wefvergrervw = 1;
               while(wefvergrervw < 7)
               {
                  if(!_root.arenaMode)
                  {
                     if(IDKT.playerID == _root.Krin.playerNumber)
                     {
                        _root["KrinSelector" + wefvergrervw]._x = -300;
                        _root["KrinSelector" + wefvergrervw]._y = -300;
                     }
                     if(_root["KrinSelector" + wefvergrervw].TargetEr == IDKT.playerID)
                     {
                        _root["KrinSelector" + wefvergrervw]._x = -300;
                        _root["KrinSelector" + wefvergrervw]._y = -300;
                     }
                  }
                  wefvergrervw++;
               }
               _root.krinAddMove(IDKT.playerID,IDKT.playerID,0);
            }
            else
            {
               addSound("Effects",IDKT.voiceHit[random(3)]);
            }
         }
         else
         {
            if(_root.DamageOutputKrinFinal != NaN)
            {
               _root.KrinNumberShow(_root.DamageOutputKrinFinal,"player" + IDKT.playerID,"HEAL");
               IDKT.LIFEN += _root.DamageOutputKrinFinal;
            }
            if(IDKT.LIFEN > IDKT.LIFEU)
            {
               IDKT.LIFEN = IDKT.LIFEU;
            }
            _root.BATTLEFLASH.hitTarget = _root.BATTLESCREEN["player" + IDKT.playerID];
            _root.BATTLEFLASH.DFTC = IDKT.characterColorState;
            _root.BATTLEFLASH.DFTF = IDKT.characterFilterState;
            _root.BATTLEFLASH.DFTP = IDKT;
            _root.BATTLEFLASH.gotoAndPlay("heal");
         }
         _root.lifeBarUpdate(IDKT.playerID);
      }
   }
   if(IDKM[14] == "Heal")
   {
      numberOutputInner1 = (IDKC.STRENGTHU + IDKM2[1]) * IDKM2[2] + (IDKC.MAGICU + IDKM2[3]) * IDKM2[4] + (IDKC.SPEEDU + IDKM2[5]) * IDKM2[6] + IDKC.LIFEU * IDKM2[12] + IDKM2[9];
      coEFKN6723 = IDKM2[10];
      perScript(PERCALK,1,IDKM2);
      if(_root.perKSuccess)
      {
         _root.GridShaker.play();
         coEFKN6724 = 1.5;
      }
      else
      {
         coEFKN6724 = 1;
      }
      _root.DamageOutputKrinFinal = Math.ceil(numberOutputInner1 * focusCoEF * coEFKN6723 * coEFKN6724 * IDKC.HEALMOD * IDKT.HEALMOD_PLUS * IDKT.HEALMOD_MINUS);
      if(_root.DamageOutputKrinFinal <= 0)
      {
         _root.DamageOutputKrinFinal = 0;
      }
      if(_root.DamageOutputKrinFinal > 0)
      {
         if(IDKT.SSWITCH == 0)
         {
            _root.KrinNumberShow(_root.DamageOutputKrinFinal,"player" + IDKT.playerID,"HEAL");
            IDKT.LIFEN += _root.DamageOutputKrinFinal;
            if(IDKT.LIFEN > IDKT.LIFEU)
            {
               IDKT.LIFEN = IDKT.LIFEU;
            }
            _root.BATTLEFLASH.hitTarget = _root.BATTLESCREEN["player" + IDKT.playerID];
            _root.BATTLEFLASH.DFTC = IDKT.characterColorState;
            _root.BATTLEFLASH.DFTF = IDKT.characterFilterState;
            _root.BATTLEFLASH.DFTP = IDKT;
            _root.BATTLEFLASH.gotoAndPlay("heal");
            _root.lifeBarUpdate(IDKT.playerID);
         }
         else
         {
            _root.KrinNumberShow(_root.DamageOutputKrinFinal,"player" + IDKT.playerID,"Shadow");
            IDKT.LIFEN -= _root.DamageOutputKrinFinal;
            if(IDKT.LIFEN <= 0)
            {
               IDKT.LIFEN = 0;
               IDKT.FOCUSN = 0;
            }
            _root.lifeBarUpdate(IDKT.playerID);
            _root.BATTLEFLASH.hitTarget = _root.BATTLESCREEN["player" + IDKT.playerID];
            _root.BATTLEFLASH.DFTC = IDKT.characterColorState;
            _root.BATTLEFLASH.DFTF = IDKT.characterFilterState;
            _root.BATTLEFLASH.DFTP = IDKT;
            _root.BATTLEFLASH.gotoAndPlay("hit");
            if(IDKT.STUN == 0)
            {
               _root.BATTLESCREEN["player" + IDKT.playerID].inner.gotoAndPlay("hit");
            }
            if(IDKT.LIFEN == 0)
            {
               _root.BATTLESCREEN["player" + IDKT.playerID].inner.gotoAndPlay("dead");
               IDKT.active = false;
               wefvergrervw = 1;
               while(wefvergrervw < 7)
               {
                  if(IDKT.playerID == _root.Krin.playerNumber)
                  {
                     _root["KrinSelector" + wefvergrervw]._x = -300;
                     _root["KrinSelector" + wefvergrervw]._y = -300;
                  }
                  if(_root["KrinSelector" + wefvergrervw].TargetEr == IDKT.playerID)
                  {
                     _root["KrinSelector" + wefvergrervw]._x = -300;
                     _root["KrinSelector" + wefvergrervw]._y = -300;
                  }
                  wefvergrervw++;
               }
               _root.krinAddMove(IDKT.playerID,IDKT.playerID,0);
            }
         }
      }
   }
   if(IDKM[14] == "Focus")
   {
      IDKT.FOCUSN += IDKM2[9];
      if(IDKT.FOCUSN > IDKT.FOCUSU)
      {
         IDKT.FOCUSN = IDKT.FOCUSU;
      }
      if(IDKT.FOCUSN < 0)
      {
         IDKT.FOCUSN = 0;
      }
      _root.BATTLEFLASH.hitTarget = _root.BATTLESCREEN["player" + IDKT.playerID];
      _root.BATTLEFLASH.DFTC = IDKT.characterColorState;
      _root.BATTLEFLASH.DFTF = IDKT.characterFilterState;
      _root.BATTLEFLASH.DFTP = IDKT;
      _root.BATTLEFLASH.gotoAndPlay("focus");
      _root.lifeBarUpdate(IDKT.playerID);
   }
}
function perScript(PERCALKK, DEFCALKK, GGG)
{
   _root.KRRR();
   if(SPEEDCRITCALC < 0)
   {
      SPEEDCRITCALC = 0;
   }
   if(_root.KRSO < (PERCALKK + GGG[7] + SPEEDCRITCALC) * GGG[8] / DEFCALKK * 15)
   {
      _root.perKSuccess = true;
   }
   else
   {
      _root.perKSuccess = false;
   }
}
BarHolder = new Array();
BarHolder2 = new Array();
BarHolder3 = new Array();
BarHolder4 = new Array();
lifeBarUpdate = function(PWLC)
{
   ghjul = _root["playerKrin" + PWLC];
   _root["p" + PWLC + "BAR"].inner.lifeNow = ghjul.LIFEN;
   _root["p" + PWLC + "BAR"].inner.lifeMax = ghjul.LIFEU;
   _root["p" + PWLC + "BAR"].inner.focusNow = ghjul.FOCUSN;
   _root["p" + PWLC + "BAR"].inner.focusMax = ghjul.FOCUSU;
   _root["p" + PWLC + "BAR"].inner.playerName = ghjul.playerName;
   if(firstUpdate)
   {
      BarHolder[PWLC - 1] = ghjul.LIFEN;
      BarHolder2[PWLC - 1] = ghjul.FOCUSN;
      BarHolder3[PWLC - 1] = Math.round(ghjul.LIFEN / ghjul.LIFEU * 100);
      BarHolder4[PWLC - 1] = ghjul.LIFEU;
      LNUS = 0;
      FNUS = 0;
      wPerCentKrin = _root["p" + PWLC + "BAR"].inner.lifeNow / _root["p" + PWLC + "BAR"].inner.lifeMax;
      _root["p" + PWLC + "BAR"].inner2.lB.LBS.LCC.gotoAndStop(Math.round(wPerCentKrin * 100));
      _root["p" + PWLC + "BAR"].inner2.lB.LCC.gotoAndStop(Math.round(wPerCentKrin * 100));
      _root["p" + PWLC + "BAR"].inner2.lB2.LCC.gotoAndStop(Math.round(wPerCentKrin * 100));
   }
   else
   {
      LNUS = ghjul.LIFEN - BarHolder[PWLC - 1];
      if(Math.round(ghjul.LIFEN / ghjul.LIFEU * 100) == BarHolder3[PWLC - 1])
      {
         LNUS = 0;
      }
      FNUS = ghjul.FOCUSN - BarHolder2[PWLC - 1];
      LNUSC = Math.sqrt(Math.pow(LNUS,2)) / ghjul.LIFEU;
      FNUSC = Math.sqrt(Math.pow(FNUS,2)) / ghjul.FOCUSU;
      if(_root.Krin.IronSkinner)
      {
         _root.Krin.IronSkinner = false;
         LNUSC = Math.abs(ghjul.LIFEN / ghjul.LIFEU - BarHolder[PWLC - 1] / BarHolder4[PWLC - 1]);
      }
      BarHolder[PWLC - 1] = ghjul.LIFEN;
      BarHolder2[PWLC - 1] = ghjul.FOCUSN;
      BarHolder4[PWLC - 1] = ghjul.LIFEU;
      BarHolder3[PWLC - 1] = Math.round(ghjul.LIFEN / ghjul.LIFEU * 100);
   }
   if(FNUS != 0)
   {
      wPerCentKrin2 = _root["p" + PWLC + "BAR"].inner.focusNow / _root["p" + PWLC + "BAR"].inner.focusMax;
      if(FNUS < 1)
      {
         _root["p" + PWLC + "BAR"].inner2.fB._width = _root["p" + PWLC + "BAR"].inner2.fB.wsaver * wPerCentKrin2;
      }
      _root["p" + PWLC + "BAR"].inner2.fB3.attachMovie("LifeBarSmoother2","LBS",1);
      _root["p" + PWLC + "BAR"].inner2.fB3.LBS._x = _root["p" + PWLC + "BAR"].inner2.fB._width * 1.2710000000000006 - 1;
      _root["p" + PWLC + "BAR"].inner2.fB3.LBS._width = _root["p" + PWLC + "BAR"].inner2.fB.wsaver * 1.2710000000000006 * FNUSC;
      if(FNUS > 0)
      {
         _root["p" + PWLC + "BAR"].inner2.fB3.LBS.gotoAndPlay("healSmooth");
         _root["p" + PWLC + "BAR"].inner2.fB3.LBS.wsaver = _root["p" + PWLC + "BAR"].inner2.lB.wsaver * wPerCentKrin2;
      }
   }
   if(LNUS != 0 || firstUpdate == true)
   {
      wPerCentKrin = _root["p" + PWLC + "BAR"].inner.lifeNow / _root["p" + PWLC + "BAR"].inner.lifeMax;
      if(LNUS < 1 || firstUpdate == true)
      {
         _root["p" + PWLC + "BAR"].inner2.lB._width = _root["p" + PWLC + "BAR"].inner2.lB.wsaver * wPerCentKrin;
      }
      if(firstUpdate != true)
      {
         _root["p" + PWLC + "BAR"].inner2.lB3.attachMovie("LifeBarSmoother","LBS",1);
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS._x = _root["p" + PWLC + "BAR"].inner2.lB._width * 1.2710000000000006 - 1;
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS._width = _root["p" + PWLC + "BAR"].inner2.lB.wsaver * 1.2710000000000006 * LNUSC;
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS.LCC.gotoAndStop(Math.round(wPerCentKrin * 100) + 1);
      }
      _root["p" + PWLC + "BAR"].inner2.lB.LCC.gotoAndStop(Math.round(wPerCentKrin * 100) + 1);
      _root["p" + PWLC + "BAR"].inner2.lB2.LCC.gotoAndStop(Math.round(wPerCentKrin * 100) + 1);
      if(ghjul.LIFEN == 0)
      {
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS.deadNow = true;
         addSound("Effects",ghjul.voiceDie);
      }
      if(LNUS > 0)
      {
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS.gotoAndPlay("healSmooth");
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS.stopper = Math.round(wPerCentKrin * 100) + 1;
         _root["p" + PWLC + "BAR"].inner2.lB3.LBS.wsaver = _root["p" + PWLC + "BAR"].inner2.lB.wsaver * wPerCentKrin;
      }
   }
};

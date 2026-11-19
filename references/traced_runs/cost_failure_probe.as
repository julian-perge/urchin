// A throwaway Probe for #39. It is not kept in dev/probes because it changes what
// the game does: it runs the English, CLICK TO PLAY and Knight class buttons' code,
// starts battle 100 on Heroic through root frame 180, refills every unit's life at
// each AI decision, and quits the player when it is done.
// It forces cost failures at dispatch and traces COST lines from wrappers around
// AImoveAdder, buffTicker, executeMove, KrinNumberShow, lifeBarUpdate and KRRR.
// clipMoveBammer is the conductor's own moveBammer (_root.battleClocker), and
// rootMoveBammer is _root.moveBammer. PAID lines come from lifeBarUpdate, which
// buffTicker also calls, so a PAID line right after TICK_BEFORE is not a payment.
// A: an enemy's Focus is set to -1 after it decides, and it gets Digitalis.
// B: as A, and _root.strikeSuccess is set to false, as a missed earlier roll leaves it.
// C: the ally's Focus is set to -1 and it has no buff that ticks, then the player passes.
// D: the ally's move is refiled as Dux Electro (20 Focus) with Focus 60, the player
//    casts Disrupt (110) on it, and the two swap teamAdder so the player acts first.
_global.zzT = 0;
_global.zzStep = 0;
_global.zzHalf = 0;
_global.zzDrained = 0;
_global.zzDrainId = 0;
_global.zzEnemyDone = 0;
_global.zzAllyDone = 0;
_global.zzDDone = 0;
_global.zzDStart = 0;
_global.zzWrapped = false;
function zzS(tag, u)
{
   var c = _root.battleClocker;
   var mv = _root[_root.MoveArrayFINAL[_root.PlayerToMove] + "MOVE"];
   return "COST\t" + tag + "\tunit=" + u.playerID + "\tteam=" + u.teamSide + "\tclipMoveBammer=" + c.moveBammer + "\trootMoveBammer=" + _root.moveBammer + "\tstrikeSuccess=" + _root.strikeSuccess + "\tBAM=" + _root.BAMBAMBAM + "\tFOCUSN=" + u.FOCUSN + "\tLIFEN=" + u.LIFEN + "\tmCaster=" + c.mCaster.playerID + "\tmTarget=" + c.mTarget.playerID + "\tmoveId=" + mv[3] + "\tfocusCost=" + c.mAry1[5] + "\tframe=" + _global.zzT;
}
function zzWrap()
{
   var oAI = _root.AImoveAdder;
   _root.AImoveAdder = function(p)
   {
      var r = oAI.apply(this, arguments);
      var u = _root["playerKrin" + p];
      var me = _root["playerKrin" + _root.Krin.playerNumber];
      var k = 1;
      while(k < 7)
      {
         if(_root["playerKrin" + k].active)
         {
            _root["playerKrin" + k].LIFEN = _root["playerKrin" + k].LIFEU;
         }
         k++;
      }
      if(u.teamSide == me.teamSide && p != _root.Krin.playerNumber && _global.zzDStart > 0 && _global.zzHalf >= _global.zzDStart && _global.zzDDone < 3 && _global.zzDrainId != _global.zzHalf)
      {
         _global.zzDrainId = _global.zzHalf;
         _global.zzDDone++;
         var ab = false;
         var w = 0;
         while(w < _root.maxBuffLimit)
         {
            if(u.BUFFARRAYK[w].CD > 0)
            {
               ab = true;
            }
            w++;
         }
         if(!ab)
         {
            _root.applyBuffKrin(u,"IDIGITALIS",1,_root.playerKrin2);
         }
         var ta = u.teamAdder;
         u.teamAdder = me.teamAdder;
         me.teamAdder = ta;
         _root.krinAddMove(p,2,10);
         u.FOCUSN = 60;
         me.FOCUSN = me.FOCUSU;
         _root.krinAddMove(_root.Krin.playerNumber,p,110);
         trace(zzS("SETUP_D_DISRUPT", u) + "\tallyHadBuff=" + ab + "\tmeSPEEDU=" + me.SPEEDU + "\tallySPEEDU=" + u.SPEEDU + "\tmeTeamAdder=" + me.teamAdder + "\tallyTeamAdder=" + u.teamAdder);
         trace("COST\tDATA\t110\t" + _root.KRINABILITY110.join(",") + "\tB\t" + _root.KRINABILITYB110.join(","));
         trace("COST\tDATA\t10\t" + _root.KRINABILITY10.join(","));
      }
      if(u.teamSide == me.teamSide && p != _root.Krin.playerNumber && _global.zzHalf >= 2 && _global.zzEnemyDone >= 4 && _global.zzAllyDone < 3 && _global.zzDrainId != _global.zzHalf)
      {
         _global.zzDrainId = _global.zzHalf;
         _global.zzAllyDone++;
         var pb = false;
         var q = 0;
         while(q < _root.maxBuffLimit)
         {
            if(me.BUFFARRAYK[q].CD > 0)
            {
               pb = true;
            }
            q++;
         }
         if(!pb)
         {
            _root.applyBuffKrin(me,"IDIGITALIS",1,_root.playerKrin2);
         }
         u.FOCUSN = -1;
         _root.strikeSuccess = true;
         if(_global.zzAllyDone >= 3)
         {
            _global.zzDStart = _global.zzHalf + 2;
         }
         trace(zzS("DRAIN_C_ALLY", u) + "\tplayerHadBuff=" + pb + "\tallyDOT=" + u.DOTTICKERARRAY.join(","));
      }
      if(u.teamSide != me.teamSide && _global.zzHalf >= 2 && _global.zzEnemyDone < 4 && _global.zzDrainId != _global.zzHalf)
      {
         _global.zzDrainId = _global.zzHalf;
         _global.zzEnemyDone++;
         _global.zzDrained++;
         if(_global.zzEnemyDone >= 3)
         {
            _root.strikeSuccess = false;
         }
         var hasBuff = false;
         var b = 0;
         while(b < _root.maxBuffLimit)
         {
            if(u.BUFFARRAYK[b].CD > 0)
            {
               hasBuff = true;
            }
            b++;
         }
         if(!hasBuff)
         {
            _root.applyBuffKrin(u,"IDIGITALIS",1,me);
         }
         u.FOCUSN = -1;
         trace(zzS(_global.zzEnemyDone >= 3 ? "DRAIN_B_STALE_MISS" : "DRAIN_A", u) + "\thadBuff=" + hasBuff + "\tDOT=" + u.DOTTICKERARRAY.join(","));
      }
      return r;
   };
   var oBT = _root.buffTicker;
   _root.buffTicker = function(u)
   {
      trace(zzS("TICK_BEFORE", u));
      var r = oBT.apply(this, arguments);
      trace(zzS("TICK_AFTER", u) + "\tbuffTickChecker=" + _root.buffTickChecker);
      return r;
   };
   var oEM = _root.executeMove;
   _root.executeMove = function(a1, a2, cst, tgt)
   {
      var lifeBefore = tgt.LIFEN;
      trace(zzS("EXEC_BEFORE", cst) + "\ttarget=" + tgt.playerID + "\ttargetLife=" + lifeBefore + "\ta1=" + a1.slice(0,8).join(",") + "\ta2_13=" + a2[13] + "\ttargetFocus=" + tgt.FOCUSN);
      var r = oEM.apply(this, arguments);
      trace(zzS("EXEC_AFTER", cst) + "\ttarget=" + tgt.playerID + "\ttargetLife=" + tgt.LIFEN + "\ttargetFocus=" + tgt.FOCUSN);
      return r;
   };
   var oNS = _root.KrinNumberShow;
   _root.KrinNumberShow = function(n, who)
   {
      if(n == "miss")
      {
         trace(zzS("MISS", _root.battleClocker.mCaster) + "\twho=" + who);
      }
      return oNS.apply(this, arguments);
   };
   var oLB = _root.lifeBarUpdate;
   _root.lifeBarUpdate = function(id)
   {
      if(_root.battleClocker.mCaster.playerID == id && _root.battleClocker.moveStart != true)
      {
         trace(zzS("PAID", _root.battleClocker.mCaster));
      }
      return oLB.apply(this, arguments);
   };
   var oKR = _root.KRRR;
   _root.KRRR = function()
   {
      var r = oKR.apply(this, arguments);
      trace("COST\tROLL\tKRSO=" + _root.KRSO + "\tcaster=" + _root.battleClocker.mCaster.playerID + "\tframe=" + _global.zzT);
      return r;
   };
   _global.zzWrapped = true;
   trace("COST\twrapped");
}
_root.createEmptyMovieClip("zzCost", 98766);
_root.zzCost.onEnterFrame = function()
{
   _global.zzT++;
   if(_global.zzT > 30000)
   {
      trace("COST\tgave_up");
      fscommand("quit");
      delete this.onEnterFrame;
      return;
   }
   if(!_global.zzWrapped && _root.executeMove != undefined && _root.AImoveAdder != undefined && _root.lifeBarUpdate != undefined)
   {
      zzWrap();
   }
   if(_global.zzStep == 0)
   {
      if(_root._currentframe == 1 && _global.zzT > 5)
      {
         _root.KLangChoosen = "ENGLISH";
         _root.gotoAndStop("playFromHere");
         _root.play();
      }
      else if(_root._currentframe == 4 || _root._currentframe == 5)
      {
         _root.play();
      }
      else if(_root._currentframe >= 44 && _root._currentframe < 90 && _global.zzWrapped)
      {
         _global.zzStep = 1;
         _global.zzWait = _global.zzT + 30;
      }
      return;
   }
   if(_global.zzStep == 1 && _global.zzT > _global.zzWait)
   {
      trace("COST\tmenu_frame\t" + _root._currentframe);
      _root.Krin.Class = 0;
      _root.loadTalents(_root.Krin.Class);
      _root.assignPointsStart(_root.Krin.Class);
      _root.Krin.moveMatrix[0] = _root.Krin.startSkill1;
      _root.Krin.moveMatrix[1] = _root.Krin.startSkill2;
      _root.Krin.moveMatrix2[0] = _root.Krin.startSkill1;
      _root.Krin.moveMatrix2[1] = _root.Krin.startSkill2;
      _root.gotoAndStop("optionsMenu");
      _global.zzStep = 2;
      _global.zzWait = _global.zzT + 10;
      return;
   }
   if(_global.zzStep == 2 && _global.zzT > _global.zzWait)
   {
      trace("COST\toptions_frame\t" + _root._currentframe + "\tdifficulty_was\t" + _root.Krin.difficulty);
      _root.Krin.difficulty = 2;
      _root.Krin.tutorOn = false;
      _root.gotoSceneKrin = "IntroSeq2";
      _root.gotoAndStop(180);
      _global.zzStep = 3;
      return;
   }
   if(_global.zzStep == 3)
   {
      if(_root.InBattle != this.lastIn)
      {
         this.lastIn = _root.InBattle;
         if(_root.InBattle)
         {
            _global.zzHalf++;
            trace("COST\tHALF\t" + _global.zzHalf + "\tTeamMoveNow=" + _root.TeamMoveNow + "\tturnBased=" + _root.turnBasedKrin + "\tframe=" + _global.zzT);
         }
      }
      if(_global.zzDDone >= 3 && _root.InBattle == false && _global.zzDrainId != _global.zzHalf)
      {
         trace("COST\tdone");
         fscommand("quit");
         _global.zzStep = 4;
      }
      if(_root.winCondition >= 0 && _global.zzStep == 3)
      {
         trace("COST\tbattle_over\t" + _root.winCondition);
         fscommand("quit");
         _global.zzStep = 4;
      }
   }
};

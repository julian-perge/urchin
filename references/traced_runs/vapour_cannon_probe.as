// A throwaway Probe for #492. It is not kept in dev/probes because it changes what
// the game does: it runs the English, CLICK TO PLAY and Knight class buttons' code,
// starts battle 100 on Heroic through root frame 180, as
// cost_failure_probe.as does, refills every unit's life each time a move is
// filed, and quits the player when it is done.
// A wrapper around krinAddMove files Vapour Cannon (276) in place of the move
// that an AI unit chose: an enemy casts it on the player, and the Companion casts
// it on unit 2, until each side has made 3 Vapour Cannon bolts. A cast of another
// move still gets traced. The Probe does not wrap AImoveAdder, because
// dev/probes/aimove.as wraps it again whenever it is not on top. In Flash 11.9
// the two wrappers then called each other at the first AI decision, and all
// ActionScript stopped while the animations played on.
// A wrapper around krinBoltMake wraps each bolt's onEnterFrame. After the
// original runs, a BOLT line gives the bolt, its KrinTrail and the BATTLESCREEN
// zoom on that frame. getBounds gives each clip's art in BATTLESCREEN space, so
// the head end of the bolt and the far end of the trail can be compared.
// After the bolt is gone, a TRAIL line from the trail's own onEnterFrame gives
// the trail for up to 40 frames. In Ruffle a trail's onEnterFrame still ran
// thousands of frames after its animation ended.
// The steps run on a 33 ms setInterval, as aimove_drive_probe.as does, because in Ruffle an onEnterFrame clip made here
// stopped running when the game reached the main menu (root frame 45).
_global.zzT = 0;
_global.zzStep = 0;
_global.zzWrapped = false;
_global.zzEnemyBolts = 0;
_global.zzAllyBolts = 0;
_global.zzCasts = 0;
_global.zzTrails = [];
_global.zzLastBolt = 0;
function zzB(c)
{
   if(c == undefined || c._x == undefined)
   {
      return "none";
   }
   var b = c.getBounds(_root.BATTLESCREEN);
   return b.xMin + "," + b.xMax + "," + b.yMin + "," + b.yMax;
}
function zzTrail(tt)
{
   if(tt == undefined || tt._x == undefined)
   {
      return "trail=none";
   }
   return "trailX=" + tt._x + "\ttrailY=" + tt._y + "\ttrailRot=" + tt._rotation + "\ttrailFrame=" + tt._currentframe + "\tinnerXscale=" + tt.inner._xscale + "\tinnerFrame=" + tt.inner._currentframe + "\ttrailBounds=" + zzB(tt);
}
function zzScreen()
{
   var s = _root.BATTLESCREEN;
   return "screenX=" + s._x + "\tscreenY=" + s._y + "\tscreenXscale=" + s._xscale + "\tscreenYscale=" + s._yscale + "\tframe=" + _global.zzT;
}
function zzWrap()
{
   var oAdd = _root.krinAddMove;
   _root.krinAddMove = function(playerID, targetID, moveID)
   {
      var u = _root["playerKrin" + playerID];
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
      if(u.teamSide != me.teamSide && _global.zzEnemyBolts < 3)
      {
         trace("VAP\tfiled\tcaster=" + playerID + "\ttarget=" + _root.Krin.playerNumber + "\tchosen=" + moveID + "\t" + zzScreen());
         return oAdd.apply(this, [playerID, _root.Krin.playerNumber, 276]);
      }
      if(u.teamSide == me.teamSide && playerID != _root.Krin.playerNumber && _global.zzAllyBolts < 3)
      {
         trace("VAP\tfiled\tcaster=" + playerID + "\ttarget=2\tchosen=" + moveID + "\t" + zzScreen());
         return oAdd.apply(this, [playerID, 2, 276]);
      }
      return oAdd.apply(this, arguments);
   };
   var oBM = _root.krinBoltMake;
   _root.krinBoltMake = function(shooter, hitter, tColorKrin, projectileModel, boomType)
   {
      var r = oBM.apply(this, arguments);
      var id = _root.boltMakerCounter;
      var bolt = _root.BATTLESCREEN["t" + id];
      var cast = ++_global.zzCasts;
      if(projectileModel == "Krin.Iceblade")
      {
         if(_root["playerKrin" + shooter._name.substr(6)].teamSide == _root["playerKrin" + _root.Krin.playerNumber].teamSide)
         {
            _global.zzAllyBolts++;
         }
         else
         {
            _global.zzEnemyBolts++;
         }
      }
      trace("VAP\tmade\tcast=" + cast + "\tid=" + id + "\tmodel=" + projectileModel + "\tboom=" + boomType + "\tcolor=" + tColorKrin + "\tshooter=" + shooter._name + "\tshooterX=" + shooter._x + "\tshooterY=" + shooter._y + "\thitter=" + hitter._name + "\thitterX=" + hitter._x + "\thitterY=" + hitter._y + "\tstrikeSuccess=" + _root.strikeSuccess + "\tboltX=" + bolt._x + "\tboltY=" + bolt._y + "\tSpeedConst=" + bolt.SpeedConst + "\tboltBounds=" + zzB(bolt) + "\tkrinBoltTime=" + _root.krinBoltTime + "\tkrinBoltIncrease=" + _root.krinBoltIncrease + "\t" + zzScreen());
      var oEF = bolt.onEnterFrame;
      bolt.zzN = 0;
      bolt.onEnterFrame = function()
      {
         var n = ++this.zzN;
         oEF.apply(this, arguments);
         var tt = _root.BATTLESCREEN["tt" + id];
         if(this._x == undefined)
         {
            trace("BOLT\tcast=" + cast + "\tn=" + n + "\tremoved=true\t" + zzTrail(tt) + "\t" + zzScreen());
            _global.zzTrails.push(cast);
            _global.zzLastBolt = _global.zzT;
            if(tt != undefined && tt._x != undefined)
            {
               var oTT = tt.onEnterFrame;
               tt.zzAfter = 0;
               tt.onEnterFrame = function()
               {
                  if(oTT != undefined)
                  {
                     oTT.apply(this, arguments);
                  }
                  var a = ++this.zzAfter;
                  trace("TRAIL\tcast=" + cast + "\tafter=" + a + "\t" + zzTrail(this) + "\t" + zzScreen());
                  if(a >= 40 || this._currentframe == 0)
                  {
                     this.onEnterFrame = oTT;
                  }
               };
            }
            return undefined;
         }
         trace("BOLT\tcast=" + cast + "\tn=" + n + "\tremoved=false\tboltX=" + this._x + "\tboltY=" + this._y + "\tboltRot=" + this._rotation + "\tboltAlpha=" + this._alpha + "\tSpeedConst=" + this.SpeedConst + "\tboltFrame=" + this._currentframe + "\tboltBounds=" + zzB(this) + "\t" + zzTrail(tt) + "\t" + zzScreen());
      };
      return r;
   };
   _global.zzWrapped = true;
   trace("VAP\twrapped");
}
_global.zzTick = function()
{
   _global.zzT++;
   if(_global.zzT > 30000)
   {
      trace("VAP\tgave_up");
      clearInterval(_global.zzTimer);
      fscommand("quit");
      return;
   }
   if(!_global.zzWrapped && _root.krinBoltMake != undefined && _root.krinAddMove != undefined)
   {
      zzWrap();
   }
   if(_root._currentframe != _global.zzFrame)
   {
      _global.zzFrame = _root._currentframe;
      trace("VAP\troot_frame\t" + _root._currentframe + "\tstep=" + _global.zzStep + "\tframe=" + _global.zzT);
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
      _root.Krin.difficulty = 2;
      _root.Krin.tutorOn = false;
      _root.gotoSceneKrin = "IntroSeq2";
      _root.gotoAndStop(180);
      _global.zzStep = 3;
      return;
   }
   if(_global.zzStep == 3)
   {
      if(_global.zzEnemyBolts >= 3 && _global.zzAllyBolts >= 3 && _global.zzT > _global.zzLastBolt + 70)
      {
         trace("VAP\tdone");
         clearInterval(_global.zzTimer);
         fscommand("quit");
         _global.zzStep = 4;
      }
      else if(_root.winCondition >= 0)
      {
         trace("VAP\tbattle_over\t" + _root.winCondition);
         clearInterval(_global.zzTimer);
         fscommand("quit");
         _global.zzStep = 4;
      }
   }
};
_global.zzTimer = setInterval(_global.zzTick, 33);

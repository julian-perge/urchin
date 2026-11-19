_global.__capHex = function(n) {
   var s = n.toString(16);
   while(s.length < 6)
   {
      s = "0" + s;
   }
   return s;
};
_global.__capStopAll = function(mc, f) {
   mc.gotoAndStop(f);
   for(var k in mc)
   {
      var c = mc[k];
      if(typeof c == "movieclip" && c._parent == mc)
      {
         _global.__capStopAll(c,1);
      }
   }
};
_global.__capDoll = function(tag) {
   var B = _root.BATTLESCREEN;
   trace("BS\t" + tag + "\t" + B._x + "\t" + B._y + "\t" + B._xscale + "\t" + B._yscale);
   var id = 1;
   while(id < 7)
   {
      var p = B["player" + id];
      var u = _root["playerKrin" + id];
      var b = p.getBounds(_root);
      var inn = p.inner;
      trace("DOLL\t" + tag + "\t" + id + "\t" + u.krinName + "\t" + u.model + "\t" + p._visible + "\t" + p._x + "\t" + p._y + "\t" + p._xscale + "\t" + p._yscale + "\t" + p.getDepth() + "\t" + inn._currentframe + "\t" + inn._x + "\t" + inn._y + "\t" + inn._xscale + "\t" + inn._yscale + "\t" + b.xMin + "," + b.yMin + "," + b.xMax + "," + b.yMax);
      for(var k in inn)
      {
         var c = inn[k];
         if(typeof c == "movieclip" && c._parent == inn)
         {
            var cb = c.getBounds(_root);
            trace("PART\t" + tag + "\t" + id + "\t" + k + "\t" + c.getDepth() + "\t" + c._visible + "\t" + c._currentframe + "/" + c._totalframes + "\t" + c._x + "\t" + c._y + "\t" + c._xscale + "\t" + c._yscale + "\t" + c._rotation + "\t" + cb.xMin + "," + cb.yMin + "," + cb.xMax + "," + cb.yMax + "\t" + (c.innerX != undefined) + "\t" + (c.inner != undefined) + "\t" + (c.hair != undefined));
         }
      }
      id++;
   }
};
_global.__capSnapStage = function(name) {
   var bd = new flash.display.BitmapData(800,575,false,0);
   bd.draw(_root);
   _global.__capQueue.push({name:name,bd:bd});
};
_global.__capSnapDolls = function(name) {
   var bd = new flash.display.BitmapData(800,575,false,0);
   var B = _root.BATTLESCREEN;
   var ids = [];
   var id = 1;
   while(id < 7)
   {
      if(B["player" + id]._visible)
      {
         ids.push(id);
      }
      id++;
   }
   ids.sort(function(a, b) {
      return B["player" + a].getDepth() - B["player" + b].getDepth();
   });
   var i = 0;
   while(i < ids.length)
   {
      var p = B["player" + ids[i]];
      bd.draw(p,p.transform.concatenatedMatrix);
      i++;
   }
   _global.__capQueue.push({name:name,bd:bd});
};
_global.__capFreeze = function(f) {
   var id = 1;
   while(id < 7)
   {
      var inn = _root.BATTLESCREEN["player" + id].inner;
      if(inn != undefined)
      {
         _global.__capStopAll(inn,f);
      }
      id++;
   }
};
_global.__capStep = function() {
   var S = _global.__capState;
   S.t++;
   if(S.mode == "wait")
   {
      if(_root.BATTLESCREEN.player2.inner._totalframes > 1 && _root.BATTLESCREEN.player6.inner._totalframes > 1)
      {
         S.mode = "settle";
         S.t = 0;
         trace("CAPTURE\tdolls\t" + _root._currentframe);
      }
      return undefined;
   }
   if(S.mode == "settle")
   {
      if(S.t == 3)
      {
         _global.__capDoll("natural");
         _global.__capSnapStage("natural_stage");
         _global.__capSnapDolls("natural_dolls");
         _global.__capFreeze(1);
      }
      else if(S.t == 6)
      {
         _global.__capDoll("stand01");
         _global.__capSnapStage("stand01_stage");
         _global.__capSnapDolls("stand01_dolls");
         _global.__capFreeze(16);
      }
      else if(S.t == 9)
      {
         _global.__capDoll("stand16");
         _global.__capSnapStage("stand16_stage");
         _global.__capSnapDolls("stand16_dolls");
         S.mode = "dump";
         S.row = 0;
      }
      return undefined;
   }
   if(S.mode == "dump")
   {
      if(_global.__capQueue.length == 0)
      {
         trace("CAPTURE\tdone");
         _global.__capClip.onEnterFrame = undefined;
         return undefined;
      }
      var job = _global.__capQueue[0];
      var end = S.row + 20;
      if(end > 575)
      {
         end = 575;
      }
      while(S.row < end)
      {
         var line = "";
         var x = 0;
         while(x < 800)
         {
            line += _global.__capHex(job.bd.getPixel(x,S.row));
            x++;
         }
         trace("ROW\t" + job.name + "\t0\t" + S.row + "\t" + line);
         S.row++;
      }
      if(S.row >= 575)
      {
         job.bd.dispose();
         _global.__capQueue.shift();
         S.row = 0;
      }
   }
};
_global.__capPoll = function() {
   var f = _root._currentframe;
   if(f == 1)
   {
      _root.KLangChoosen = "ENGLISH";
      _root.gotoAndStop("playFromHere");
      _root.play();
   }
   else if(f == 4 || f == 5)
   {
      _root.play();
   }
   else if(f == 46 && _global.__capState == undefined)
   {
      clearInterval(_global.__capTimer);
      trace("CAPTURE\tstart");
      _global.__capQueue = [];
      _global.__capState = {mode:"wait",t:0};
      _global.__capClip = _root.createEmptyMovieClip("__capClip",30001);
      _global.__capClip.onEnterFrame = _global.__capStep;
      var K = _root.Krin;
      K.ClassStats[0] = K.Class + 1;
      K.sectionIn = 4;
      K.BattlePick = 408;
      K.progressFight = false;
      K.bossFight = true;
      _root.gotoAndStop("LOADBATTLESCENE");
      _root.play();
   }
};
_global.__capTimer = setInterval(_global.__capPoll,250);

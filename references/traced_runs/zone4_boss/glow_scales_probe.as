_global.__capHex = function(n) {
   var s = n.toString(16);
   while(s.length < 6)
   {
      s = "0" + s;
   }
   return s;
};
_global.__capStep = function() {
   var S = _global.__capState;
   S.t++;
   if(S.t == 4)
   {
      S.bd = new flash.display.BitmapData(800,575,false,0);
      S.bd.draw(_root);
      S.row = 0;
      var i = 0;
      while(i < S.clips.length)
      {
         var c = S.clips[i];
         var b = c.getBounds(_root);
         trace("CLIP\t" + c._name + "\t" + c._x + "\t" + c._y + "\t" + c._xscale + "\t" + b.xMin + "," + b.yMin + "," + b.xMax + "," + b.yMax + "\t" + c.getDepth());
         i++;
      }
   }
   else if(S.t > 4)
   {
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
            line += _global.__capHex(S.bd.getPixel(x,S.row));
            x++;
         }
         trace("ROW\tscales\t0\t" + S.row + "\t" + line);
         S.row++;
      }
      if(S.row >= 575)
      {
         trace("CAPTURE\tdone");
         _global.__capClip.onEnterFrame = undefined;
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
      var bg = _root.createEmptyMovieClip("__capBg",30002);
      bg.beginFill(0,100);
      bg.moveTo(0,0);
      bg.lineTo(800,0);
      bg.lineTo(800,575);
      bg.lineTo(0,575);
      bg.lineTo(0,0);
      bg.endFill();
      var specs = [["M_SFOOT_HYDRA2",200,90,150],["M_SFOOT_HYDRA2",100,230,150],["M_SFOOT_HYDRA2",66.9,330,150],["M_SFOOT_HYDRA2",50,420,150],["M_SFOOT_HYDRA",200,90,420],["M_SFOOT_HYDRA",100,230,420],["M_SFOOT_HYDRA",66.9,330,420],["M_SFOOT_HYDRA",50,420,420]];
      var clips = [];
      var i = 0;
      while(i < specs.length)
      {
         var s = specs[i];
         var c = _root.attachMovie(s[0],"__cap" + i,30010 + i);
         c._xscale = c._yscale = s[1];
         c._x = s[2];
         c._y = s[3];
         clips.push(c);
         i++;
      }
      _global.__capState = {t:0,clips:clips};
      _global.__capClip = _root.createEmptyMovieClip("__capClip",30001);
      _global.__capClip.onEnterFrame = _global.__capStep;
   }
};
_global.__capTimer = setInterval(_global.__capPoll,250);

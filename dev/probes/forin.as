_global.__forinKeys = function(a) {
   var out = "";
   for(var k in a)
   {
      out += (out == "" ? "" : ",") + k;
   }
   return out;
};
_global.__forinLog = function(name, a) {
   trace("FORIN\t" + name + "\t" + a.length + "\t" + _global.__forinKeys(a));
};
_global.__forinSynthetic = function() {
   var log = _global.__forinLog;
   var a = [10,11,12,13,14];
   log("literal5", a);
   a = [0,0,0,0,0,0,0,0];
   log("literal8", a);
   var n = [];
   n.length = 38;
   var z = 0;
   while(z < 38)
   {
      n[z] = 0;
      z++;
   }
   log("literal38_built_by_index", n);
   log("literal38", [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
   log("new_Array_3_args", new Array(10,11,12));
   log("new_Array_5", new Array(5));
   var b = new Array();
   var i = 0;
   while(i < 5)
   {
      b[i] = 0;
      i++;
   }
   log("index_ascending", b);
   var c = new Array();
   i = 4;
   while(i >= 0)
   {
      c[i] = 0;
      i--;
   }
   log("index_descending", c);
   var d = new Array();
   d[2] = 0;
   d[0] = 0;
   d[4] = 0;
   d[1] = 0;
   d[3] = 0;
   log("index_2_0_4_1_3", d);
   var e = new Array();
   i = 0;
   while(i < 5)
   {
      e.push(i);
      i++;
   }
   log("push5", e);
   e[1] = 99;
   log("push5_then_overwrite_1", e);
   e[7] = 0;
   log("push5_then_write_7", e);
   var f = [10,11,12,13,14];
   delete f[2];
   log("literal5_delete_2", f);
   f[2] = 0;
   log("literal5_delete_2_rewrite_2", f);
   var g = [10,11,12,13,14];
   g.splice(1,1);
   log("literal5_splice_1_1", g);
   var h = [10,11,12,13,14];
   h.splice(1,0,99);
   log("literal5_splice_insert_at_1", h);
   var s = [10,11,12,13,14];
   s.shift();
   log("literal5_shift", s);
   var r = [10,11,12,13,14];
   r.reverse();
   log("literal5_reverse", r);
   var o = [3,1,2];
   o.sort();
   log("literal3_sort", o);
   var src = [7,8,9];
   var copy = new Array();
   for(var k in src)
   {
      copy[k] = src[k];
   }
   log("copy_of_literal3_by_for_in", copy);
   var pushed = new Array();
   for(k in copy)
   {
      pushed.push(copy[k]);
   }
   log("push_in_for_in_order_of_that_copy", pushed);
};
_global.__forinSynthetic();
_global.__forinGame = function() {
   var log = _global.__forinLog;
   if(_root._currentframe <= 42)
   {
      return undefined;
   }
   var K = _root.Krin;
   clearInterval(_global.__forinTimer);
   log("game_Krin.itemArray", K.itemArray);
   log("game_Krin.skillAdderMatrix", K.skillAdderMatrix);
   log("game_Krin.PIU", K.PIU);
   log("game_KRINITEM100.statUpdater", _root.KRINITEM100.statUpdater);
   log("game_KRINITEM100.statUpdaterP", _root.KRINITEM100.statUpdaterP);
   log("game_KRINITEM100.statUpdaterD", _root.KRINITEM100.statUpdaterD);
   var u = 0;
   var found = 0;
   while(u < 120 && found < 3)
   {
      var unit = _root["KNU" + u];
      if(unit.movesA != undefined && unit.movesA.length >= 3)
      {
         found++;
         log("game_KNU" + u + ".movesA", unit.movesA);
         var cd = new Array();
         for(var k in unit.movesA)
         {
            cd[k] = 0;
         }
         log("game_KNU" + u + ".CDArrayA_built_as_DoAction_14", cd);
         var filter = new Array();
         for(k in cd)
         {
            filter.push(k);
         }
         log("game_KNU" + u + ".parallelFilterA_built_as_DoAction_9", filter);
      }
      u++;
   }
   trace("FORIN\tdone");
};
_global.__forinTimer = setInterval(_global.__forinGame, 200);

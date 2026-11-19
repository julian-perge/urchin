_global.__aiNames = ["AIATTACKMODE","CDtoPUT","D_Array_E","D_Array_E_PARA","D_Array_F","D_Array_F_PARA","D_Array_S","D_Array_S_PARA","IDKC","IDKM2","LifeAICR","LifeFullAIChecker","LifeFullAITotal","MoveSelectBits","MoveSelectBits2","ScriptEnderKAIA","aliveEnemies","checkerForFriends","counterFilter","counterFilter1","focusCheck","focusMove","focusSelectNum","gMtYuIo","healGuesserK","i","iujk","krinAITargetChecked","krinAITargetCheckedHEALTEST","lifeNumToCheck","moveD_final","moveD_final_para","moveFilterA0","moveFilterA1","moveFilterA2","moveFilterABS0","moveFilterABS1","moveFilterD0","moveFilterD1","moveFilterD2","numberLockKrin","parallelFilterA","parallelFilterA2","parallelFilterA3","parallelFilterABS","parallelFilterABS2","parallelFilterD","parallelFilterD2","parallelFilterD3","pg","playerFocusCheck","selectedMoveToMake","tarToBe","useABS","weakestEnemyNow","KRSO","KRSC"];
_global.__aiHealKeys = [0,1,2,3,4,5,6,7,"false","undefined"];
_global.__aiGroups = ["none","all","focus","fmove","darr","alive","lock"];
_global.__aiSave = function(p) {
   var s = new Object();
   var n = _global.__aiNames;
   var k = 0;
   while(k < n.length)
   {
      s[n[k]] = _root[n[k]];
      k++;
   }
   s.healed = new Object();
   var h = _global.__aiHealKeys;
   k = 0;
   while(k < h.length)
   {
      s.healed[h[k]] = _root.healedThisTurn[h[k]];
      k++;
   }
   s.cdArr = _root["playerKrin" + p].AI_CD_ARR;
   s.cdPut = _root["playerKrin" + p].AI_CD_PUT;
   return s;
};
_global.__aiLoad = function(s, p) {
   var n = _global.__aiNames;
   var k = 0;
   while(k < n.length)
   {
      _root[n[k]] = s[n[k]];
      k++;
   }
   if(_root.healedThisTurn != undefined)
   {
      var h = _global.__aiHealKeys;
      k = 0;
      while(k < h.length)
      {
         if(s.healed[h[k]] == undefined)
         {
            delete _root.healedThisTurn[h[k]];
         }
         else
         {
            _root.healedThisTurn[h[k]] = s.healed[h[k]];
         }
         k++;
      }
   }
   _root["playerKrin" + p].AI_CD_ARR = s.cdArr;
   _root["playerKrin" + p].AI_CD_PUT = s.cdPut;
};
_global.__aiFresh = function(g, p) {
   var R = _root;
   if(g == "all" || g == "focus")
   {
      R.focusCheck = Number.POSITIVE_INFINITY;
      R.playerFocusCheck = 0;
   }
   if(g == "all" || g == "fmove")
   {
      R.focusMove = false;
      R.focusSelectNum = undefined;
   }
   if(g == "all" || g == "darr")
   {
      R.D_Array_F = new Array();
      R.D_Array_S = new Array();
      R.D_Array_E = new Array();
      R.D_Array_F_PARA = new Array();
      R.D_Array_S_PARA = new Array();
      R.D_Array_E_PARA = new Array();
   }
   if(g == "all" || g == "alive")
   {
      var t = R["playerKrin" + p].teamSide;
      var a = new Array();
      if(R["playerKrin" + (7 - t)].active == true)
      {
         a.push(7 - t);
      }
      if(R["playerKrin" + (5 - t)].active == true)
      {
         a.push(5 - t);
      }
      if(R["playerKrin" + (3 - t)].active == true)
      {
         a.push(3 - t);
      }
      R.aliveEnemies = a;
      R.counterFilter1 = undefined;
   }
   if(g == "all" || g == "lock")
   {
      R.numberLockKrin = 0;
   }
};
_global.__aiList = function(a) {
   if(a == undefined)
   {
      return "u";
   }
   return "[" + a.join(" ") + "]";
};
_global.__aiHealed = function(s) {
   var out = "";
   var h = _global.__aiHealKeys;
   var k = 0;
   while(k < h.length)
   {
      if(_root.healedThisTurn[h[k]] != s.healed[h[k]])
      {
         out += "h" + h[k];
      }
      k++;
   }
   return out;
};
_global.__aiWrap = function(p) {
   var R = _root;
   var orig = _global.__aiOrig;
   if(R["playerKrin" + p].AIAD != false)
   {
      trace("AIMOVE_SKIP\t" + R.Krin.BattlePick + "\t" + p);
      return orig.apply(this, arguments);
   }
   _global.__aiCalls++;
   var entry = _global.__aiSave(p);
   var realAdd = R.krinAddMove;
   var got = new Object();
   R.krinAddMove = function(a, b, c) {
      got.out = c + ">" + b;
      return realAdd.apply(this, arguments);
   };
   var res = orig.apply(this, arguments);
   var real = got.out + ">" + _global.__aiHealed(entry);
   var abs = R.useABS;
   var post = _global.__aiSave(p);
   var line = "AIMOVE\t" + _global.__aiCalls + "\t" + R.Krin.BattlePick + "\t" + R.phase + "\t" + p + "\t" + _global.__aiLast + "\t" + abs + "\tfc=" + entry.focusCheck + "\tpfc=" + entry.playerFocusCheck + "\tfm=" + entry.focusMove + "\tnlk=" + entry.numberLockKrin + "\tae=" + _global.__aiList(entry.aliveEnemies) + "\tcf1=" + entry.counterFilter1 + "\tD=" + entry.D_Array_F.length + "," + entry.D_Array_S.length + "," + entry.D_Array_E.length + "\treal=" + real;
   var g = 0;
   while(g < _global.__aiGroups.length)
   {
      var name = _global.__aiGroups[g];
      _global.__aiLoad(entry, p);
      _global.__aiFresh(name, p);
      got.out = "none";
      R.krinAddMove = function(a, b, c) {
         got.out = c + ">" + b;
      };
      orig.apply(this, arguments);
      line += "\t" + name + "=" + got.out + ">" + _global.__aiHealed(entry);
      g++;
   }
   R.krinAddMove = realAdd;
   _global.__aiLoad(post, p);
   _global.__aiLast = p;
   trace(line);
   return res;
};
_global.__aiHook = function() {
   if(_root._currentframe < 42 || _root.AImoveAdder == undefined || _root.AImoveAdder == _global.__aiWrap)
   {
      return undefined;
   }
   _global.__aiOrig = _root.AImoveAdder;
   _root.AImoveAdder = _global.__aiWrap;
   trace("AIMOVE_HOOK\tinstalled\t" + _root._currentframe);
};
_global.__aiCalls = 0;
_global.__aiLast = 0;
_global.__aiTimer = setInterval(_global.__aiHook, 200);

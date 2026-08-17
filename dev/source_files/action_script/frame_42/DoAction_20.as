function checkIfAllStar()
{
   b_CheckYU = 0;
   p_CheckYU = 0;
   h_CheckYU = 0;
   cfg = 1;
   while(cfg < 5)
   {
      k_slotter = _root["slot" + cfg];
      if(k_slotter.data.difficulty == 2)
      {
         if(k_slotter.data.questProgress[5] > 13)
         {
            if(k_slotter.data.Class == 0)
            {
               b_CheckYU = 1;
            }
            if(k_slotter.data.Class == 1)
            {
               p_CheckYU = 1;
            }
            if(k_slotter.data.Class == 2)
            {
               h_CheckYU = 1;
            }
         }
      }
      cfg++;
   }
   if(Krin.difficulty == 2)
   {
      if(Krin.questProgress[5] > 13)
      {
         if(Krin.data.Class == 0)
         {
            b_CheckYU = 1;
         }
         if(Krin.data.Class == 1)
         {
            p_CheckYU = 1;
         }
         if(Krin.data.Class == 2)
         {
            h_CheckYU = 1;
         }
      }
   }
   if(b_CheckYU + p_CheckYU + h_CheckYU == 3)
   {
      return true;
   }
   trace("PROFILE " + (b_CheckYU + p_CheckYU + h_CheckYU));
   trace("H " + h_CheckYU);
   trace("B " + b_CheckYU);
   trace("P " + p_CheckYU);
   return false;
}
function krinHandleData(slotNum)
{
   k_slotter = _root["slot" + slotNum];
   if(Krin.dataMode == "save")
   {
      for(krinf in saveArray1)
      {
         k_slotter.data[saveArray1[krinf]] = _root.Krin[saveArray1[krinf]];
      }
      for(krinh in elementMainArray)
      {
         k_slotter.data.PER = new Object();
         k_slotter.data.PER[elementMainArray[krinh]] = _root.Krin.PER[elementMainArray[krinh]];
         k_slotter.data.DEF = new Object();
         k_slotter.data.DEF[elementMainArray[krinh]] = _root.Krin.DEF[elementMainArray[krinh]];
      }
      for(krinf in saveArray2)
      {
         k_slotter.data[saveArray2[krinf]] = new Array();
         for(kring in _root.Krin[saveArray2[krinf]])
         {
            k_slotter.data[saveArray2[krinf]][kring] = _root.Krin[saveArray2[krinf]][kring];
         }
      }
   }
   else
   {
      Krin.tutSpeecher = true;
      Krin.progressFight = false;
      for(krinf in saveArray1)
      {
         if(k_slotter.data[saveArray1[krinf]] == undefined)
         {
            k_slotter.data[saveArray1[krinf]] = _root.Krin[saveArray1[krinf]];
         }
         _root.Krin[saveArray1[krinf]] = k_slotter.data[saveArray1[krinf]];
         if(_root.arenaMode)
         {
            _root["arenaPlayer" + _root.currentArenaPlayer][saveArray1[krinf]] = k_slotter.data[saveArray1[krinf]];
         }
      }
      for(krinh in elementMainArray)
      {
         _root.Krin.PER[elementMainArray[krinh]] = k_slotter.data.PER[elementMainArray[krinh]];
         _root.Krin.DEF[elementMainArray[krinh]] = k_slotter.data.DEF[elementMainArray[krinh]];
         if(_root.arenaMode == true)
         {
            _root["arenaPlayer" + _root.currentArenaPlayer].PER[elementMainArray[krinh]] = _root.Krin.PER[elementMainArray[krinh]];
            _root["arenaPlayer" + _root.currentArenaPlayer].DEF[elementMainArray[krinh]] = _root.Krin.DEF[elementMainArray[krinh]];
         }
      }
      for(krinf in saveArray2)
      {
         for(kring in k_slotter.data[saveArray2[krinf]])
         {
            if(k_slotter.data[saveArray2[krinf]][kring] != undefined)
            {
               _root.Krin[saveArray2[krinf]][kring] = k_slotter.data[saveArray2[krinf]][kring];
               if(_root.arenaMode)
               {
                  _root["arenaPlayer" + _root.currentArenaPlayer][saveArray2[krinf]][kring] = k_slotter.data[saveArray2[krinf]][kring];
               }
            }
         }
      }
      loadTalents(Krin.Class);
   }
   k_slotter.flush();
}
function loadPvPCode(entry, playerNum)
{
   _root.PvP_LOAD_SUCCESS = false;
   failPvPload = false;
   var _loc7_ = entry.split(",*$*,");
   var _loc4_ = _loc7_[1].split(",");
   var _loc8_ = _loc7_[3].split(",");
   var _loc6_ = _loc7_[2].split(",*^*,");
   var _loc9_ = _loc7_[4].split(",*^*,");
   numbEyPvP = parseFloat(_loc7_[5]);
   var _loc2_ = new Array();
   var _loc5_ = new Array();
   if(_loc7_[0] != "START_!&!%" || _loc7_[6] != "!&!%_END")
   {
      failPvPload = true;
   }
   krinf = 0;
   while(krinf < saveArray1.length)
   {
      if(!isNaN(parseFloat(_loc4_[krinf])))
      {
         if(parseFloat(_loc4_[krinf]) != parseFloat(_loc8_[krinf]) / numbEyPvP)
         {
            if(saveArray1[krinf] != "pointResidue")
            {
               failPvPload = true;
            }
         }
      }
      krinf++;
   }
   krinf = 0;
   while(krinf < saveArray2.length)
   {
      _loc2_[krinf] = _loc6_[krinf].split(",");
      _loc5_[krinf] = _loc9_[krinf].split(",");
      kring = 0;
      while(kring < _loc2_[krinf].length)
      {
         if(!isNaN(parseFloat(_loc2_[krinf][kring])))
         {
            if(parseFloat(_loc2_[krinf][kring]) != parseFloat(_loc5_[krinf][kring]) / numbEyPvP)
            {
               if(saveArray2[krinf] != "ExpSets")
               {
                  failPvPload = true;
               }
            }
         }
         kring++;
      }
      krinf++;
   }
   if(!failPvPload)
   {
      _root.PvP_LOAD_SUCCESS = true;
      krinf = 0;
      while(krinf < saveArray1.length)
      {
         if(!isNaN(parseFloat(_loc4_[krinf])))
         {
            _root["arenaPlayer" + playerNum][saveArray1[krinf]] = parseFloat(_loc4_[krinf]);
         }
         else
         {
            _root["arenaPlayer" + playerNum][saveArray1[krinf]] = _loc4_[krinf];
         }
         krinf++;
      }
      krinf = 0;
      while(krinf < saveArray2.length)
      {
         _loc2_[krinf] = _loc6_[krinf].split(",");
         kring = 0;
         while(kring < _loc2_[krinf].length)
         {
            if(!isNaN(parseFloat(_loc2_[krinf][kring])))
            {
               _root["arenaPlayer" + playerNum][saveArray2[krinf]][kring] = parseFloat(_loc2_[krinf][kring]);
            }
            else
            {
               _root["arenaPlayer" + playerNum][saveArray2[krinf]][kring] = _loc2_[krinf][kring];
            }
            kring++;
         }
         krinf++;
      }
   }
   else
   {
      _root.PvP_LOAD_SUCCESS = false;
   }
}
function exportPvPCode(playerNum)
{
   exportPvPArray = new Array();
   exportPvPArrayX = new Array();
   exportPvPArrayZ = new Array();
   exportPvPArray.push("START_!&!%");
   exportPvPArray.push("*$*");
   numEncr = 7;
   krinf = 0;
   while(krinf < saveArray1.length)
   {
      jimBobPvP = parseFloat(_root["arenaPlayer" + playerNum][saveArray1[krinf]]);
      if(!isNaN(jimBobPvP))
      {
         exportPvPArrayX.push(numEncr * jimBobPvP);
      }
      else
      {
         exportPvPArrayX.push(_root["arenaPlayer" + playerNum][saveArray1[krinf]]);
      }
      exportPvPArray.push(_root["arenaPlayer" + playerNum][saveArray1[krinf]]);
      krinf++;
   }
   exportPvPArray.push("*$*");
   krinf = 0;
   while(krinf < saveArray2.length)
   {
      adYet = false;
      kring = 0;
      while(kring < _root["arenaPlayer" + playerNum][saveArray2[krinf]].length)
      {
         adYet = true;
         exportPvPArray.push(_root["arenaPlayer" + playerNum][saveArray2[krinf]][kring]);
         if(!isNaN(parseFloat(_root["arenaPlayer" + playerNum][saveArray2[krinf]][kring])))
         {
            exportPvPArrayZ.push(numEncr * parseFloat(_root["arenaPlayer" + playerNum][saveArray2[krinf]][kring]));
         }
         else
         {
            exportPvPArrayZ.push(_root["arenaPlayer" + playerNum][saveArray2[krinf]][kring]);
         }
         kring++;
      }
      if(krinf < saveArray2.length - 1)
      {
         if(adYet)
         {
            exportPvPArray.push("*^*");
            exportPvPArrayZ.push("*^*");
         }
         else
         {
            exportPvPArray.push("NODATA");
            exportPvPArray.push("*^*");
            exportPvPArrayZ.push("NODATA");
            exportPvPArrayZ.push("*^*");
         }
      }
      krinf++;
   }
   exportPvPArray.push("*$*");
   exportPvPArray.push(exportPvPArrayX);
   exportPvPArray.push("*$*");
   exportPvPArray.push(exportPvPArrayZ);
   exportPvPArray.push("*$*");
   exportPvPArray.push(numEncr);
   exportPvPArray.push("*$*");
   exportPvPArray.push("!&!%_END");
}
var slot1 = SharedObject.getLocal("slot1");
var slot2 = SharedObject.getLocal("slot2");
var slot3 = SharedObject.getLocal("slot3");
var slot4 = SharedObject.getLocal("slot4");
saveArray1 = new Array();
saveArray2 = new Array();
saveArray1 = ["usedTraining","difficulty","pointResidue","respecSet","lastDay2","lastDay1","qual","autoSaver","graphics","sound","nameUser","sectionIn","progressLevelOn","Euro","Class","Level","skillPoints","statPoints","Exp","STRENGTH","MAGIC","FOCUS","SPEED","LIFE"];
saveArray2 = ["questProgress","agArray0","agArray1","agArray2","agArray3","agArray4","agArray5","agMode","moveMatrix","moveMatrix2","moveMatrix2Limit","talentMainArray","skillAdderMatrix","skillAdderMatrixOld","buffAdderMatrix","itemArray","friendArray","LevelStats","equipArray0","equipArray1","equipArray2","equipArray3","equipArray4","equipArray5","PerSets0","PerSets1","PerSets2","PerSets3","PerSets4","PerSets5","DefSets0","DefSets1","DefSets2","DefSets3","DefSets4","DefSets5","StatSets5","StatSets0","StatSets1","StatSets2","StatSets3","StatSets4","friendArrayX","ExpSets","ClassStats"];

function updateFriends()
{
   i = 1;
   while(i < 6)
   {
      this["fa" + i].blacker._visible = true;
      this["fa" + i].inTheTeam = false;
      if(_root.Krin.friendArrayX[0] == i)
      {
         this["fa" + i].blacker._visible = false;
         this["fa" + i].inTheTeam = true;
         this["fa" + i].inTheTeam2 = 0;
      }
      if(_root.Krin.friendArrayX[1] == i)
      {
         this["fa" + i].blacker._visible = false;
         this["fa" + i].inTheTeam = true;
         this["fa" + i].inTheTeam2 = 1;
      }
      i++;
   }
}
function updateEquip()
{
   for(w in _root.Krin.equipArray0)
   {
      this["playerSlot" + w].inner.gotoAndStop(_root.KrinLang[_root.KLangChoosen].ITEMNAME[_root.Krin["equipArray" + _root.Krin.MenuPlayerSelect][w]]);
      this["playerSlot" + w].id = w;
      this["playerSlot" + w].slotType = "playerSlot";
   }
}
function updateDoll()
{
   if(_root.Krin.gArray[_root.Krin.GSet[_root.Krin.MenuPlayerSelect]] == "M")
   {
      modelchooser = "";
      for(h in dollPartsArray)
      {
         this[dollPartsArray[h]]._visible = true;
         this[dollPartsArray[h] + "_f"]._visible = false;
      }
   }
   else
   {
      modelchooser = "_f";
      for(h in dollPartsArray)
      {
         this[dollPartsArray[h]]._visible = false;
         this[dollPartsArray[h] + "_f"]._visible = true;
      }
   }
   for(h in dollPartsArray)
   {
      removeMovieClip(this[dollPartsArray[h]].inner);
      removeMovieClip(this[dollPartsArray[h]].innerX);
      removeMovieClip(this[dollPartsArray[h] + "_f"].inner);
      removeMovieClip(this[dollPartsArray[h] + "_f"].innerX);
   }
   for(h in dollPartsArray)
   {
      this[dollPartsArray[h] + modelchooser].attachMovie(_root.Krin.gArray[_root.Krin.GSet[_root.Krin.MenuPlayerSelect]] + "_S" + dollPartsCores2[h] + "_" + _root.Krin.skinArray[_root.Krin.SkinSet[_root.Krin.MenuPlayerSelect]],"innerX",-1);
      this[dollPartsArray[h] + modelchooser].attachMovie(_root.Krin.gArray[_root.Krin.GSet[_root.Krin.MenuPlayerSelect]] + "_" + dollPartsCores2[h] + "_" + _root["KRINITEM" + _root.Krin["equipArray" + _root.Krin.MenuPlayerSelect][dollPartsCores[h]]].looks,"inner",0);
      if(h == 12 || h == 13)
      {
         this[dollPartsArray[h] + modelchooser].attachMovie("M_" + dollPartsCores2[h] + "_" + _root["KRINITEM" + _root.Krin["equipArray" + _root.Krin.MenuPlayerSelect][dollPartsCores[h]]].looks,"inner",0);
      }
   }
   removeMovieClip(this.head.hair);
   if(_root.Krin["equipArray" + _root.Krin.MenuPlayerSelect][dollPartsCores[h]] == 0 || _root.Krin.GSet[_root.Krin.MenuPlayerSelect] == 1)
   {
      this.head.attachMovie("HAIR_" + _root.Krin.hairArray[_root.Krin.HairSet[_root.Krin.MenuPlayerSelect]],"hair",2);
   }
}
function updateAvs()
{
   i = 0;
   while(i < 6)
   {
      this["fa" + i].borderFrame._visible = false;
      if(i == _root.Krin.MenuPlayerSelect)
      {
         this["fa" + i].borderFrame._visible = true;
      }
      i++;
   }
}
function updateStatus()
{
   yut_name = _root.Krin.NameSets[_root.Krin.MenuPlayerSelect];
   yut_per = _root.KrinLang[_root.KLangChoosen].SYSTEM[5];
   yut_def = _root.KrinLang[_root.KLangChoosen].SYSTEM[6];
   yut_info51 = _root.KrinLang[_root.KLangChoosen].MENU[17];
   yut_info = _root.KrinLang[_root.KLangChoosen].MENU[0] + _root.Krin.LevelStats[_root.Krin.MenuPlayerSelect] + " " + _root.KrinLang[_root.KLangChoosen].CLASS[_root.Krin.ClassStats[_root.Krin.MenuPlayerSelect] - 1];
   yut_def2 = new Array();
   yut_per2 = new Array();
   yut_lif2 = _root.Krin["StatSets" + _root.Krin.MenuPlayerSelect][0] + Math.ceil(_root.getStat(_root["KNU" + _root.Krin.ClassStats[_root.Krin.MenuPlayerSelect]][1],_root.Krin.LevelStats[_root.Krin.MenuPlayerSelect],true));
   yut_str2 = _root.Krin["StatSets" + _root.Krin.MenuPlayerSelect][1] + Math.ceil(_root.getStat(_root["KNU" + _root.Krin.ClassStats[_root.Krin.MenuPlayerSelect]][2],_root.Krin.LevelStats[_root.Krin.MenuPlayerSelect],true));
   yut_mag2 = _root.Krin["StatSets" + _root.Krin.MenuPlayerSelect][2] + Math.ceil(_root.getStat(_root["KNU" + _root.Krin.ClassStats[_root.Krin.MenuPlayerSelect]][3],_root.Krin.LevelStats[_root.Krin.MenuPlayerSelect],true));
   yut_spd2 = _root.Krin["StatSets" + _root.Krin.MenuPlayerSelect][3] + Math.ceil(_root.getStat(_root["KNU" + _root.Krin.ClassStats[_root.Krin.MenuPlayerSelect]][4],_root.Krin.LevelStats[_root.Krin.MenuPlayerSelect],true));
   yut_foc2 = _root.Krin["StatSets" + _root.Krin.MenuPlayerSelect][4] + Math.ceil(_root["KNU" + _root.Krin.ClassStats[_root.Krin.MenuPlayerSelect]][5]);
   wefjnew = 0;
   while(wefjnew < 8)
   {
      yut_per2[wefjnew] = _root.Krin["PerSets" + _root.Krin.MenuPlayerSelect][wefjnew] + Math.ceil(100 + 15 * _root.Krin.LevelStats[_root.Krin.MenuPlayerSelect]);
      yut_def2[wefjnew] = _root.Krin["DefSets" + _root.Krin.MenuPlayerSelect][wefjnew] + Math.ceil(100 + 15 * _root.Krin.LevelStats[_root.Krin.MenuPlayerSelect]);
      AVGNUMC = 100 + 15 * _root.Krin.LevelStats[_root.Krin.MenuPlayerSelect];
      CRITCALC_X = yut_per2[wefjnew] / AVGNUMC;
      nT1 = 0.016666667 * Math.pow(CRITCALC_X + 1,4) - 0.25 * Math.pow(CRITCALC_X + 1,3) + 1.233333 * Math.pow(CRITCALC_X + 1,2) - 1.9000000000000001 * (CRITCALC_X + 1) + 0.9000000000000002;
      nT2 = 15 * (yut_per2[wefjnew] / (100 + 15 * _root.Krin.LevelStats[_root.Krin.MenuPlayerSelect]));
      nT3 = 0.07 * (CRITCALC_X - 1);
      nT1_x = Math.round(nT1 * 100);
      nT2_x = Math.round(nT2);
      nT3_x = Math.round(nT3 * 100);
      perBarShow["bar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH * nT1;
      perBarShow["gbar" + wefjnew]._height = perBarShow["gbar" + wefjnew].saveH * nT2;
      perBarShow["xbar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH * nT3;
      perBarShow["tt_" + wefjnew].toolTipTitle = _root.KrinLang[_root.KLangChoosen].ELEMENTS[wefjnew] + " " + _root.KrinLang[_root.KLangChoosen].SYSTEM[5] + ": " + yut_per2[wefjnew];
      perBarShow["tt_" + wefjnew].toolTip = _root.KrinLang[_root.KLangChoosen].SYSTEM[38] + " " + nT2_x + "% " + _root.KrinLang[_root.KLangChoosen].SYSTEM[37] + " " + nT1_x + "% " + _root.KrinLang[_root.KLangChoosen].SYSTEM[39] + " " + nT3_x + "% " + _root.KrinLang[_root.KLangChoosen].SYSTEM[40];
      if(perBarShow["bar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {
         perBarShow["bar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH;
      }
      if(perBarShow["gbar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {
         perBarShow["gbar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH;
      }
      CRITCALC_X = yut_def2[wefjnew] / AVGNUMC;
      DEF_FACTOR = 1;
      DEF_CALC_ER = 1 / CRITCALC_X;
      if(DEF_CALC_ER > 1)
      {
         DEF_FACTOR = 0;
      }
      if(DEF_CALC_ER < 1)
      {
         DEF_FACTOR = 2;
      }
      if(DEF_CALC_ER < 0.81)
      {
         DEF_FACTOR = 3;
      }
      if(DEF_CALC_ER < 0.6100000000000001)
      {
         DEF_FACTOR = 4;
      }
      if(DEF_CALC_ER < 0.41000000000000014)
      {
         DEF_FACTOR = 5;
      }
      if(DEF_CALC_ER < 0.31000000000000005)
      {
         DEF_FACTOR = 6;
      }
      nT4 = 0.016666667 * Math.pow(CRITCALC_X + 1,4) - 0.25 * Math.pow(CRITCALC_X + 1,3) + 1.233333 * Math.pow(CRITCALC_X + 1,2) - 1.9000000000000001 * (CRITCALC_X + 1) + 0.9000000000000002;
      nT5 = 15 * (yut_def2[wefjnew] / (100 + 15 * _root.Krin.LevelStats[_root.Krin.MenuPlayerSelect]));
      nT6 = 0.07 * (CRITCALC_X - 1);
      nT4_x = Math.round(nT4 * 100);
      nT5_x = nT5;
      nT6_x = Math.round(nT6 * 100);
      defBarShow["bar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH * nT4;
      defBarShow["gbar" + wefjnew]._height = perBarShow["gbar" + wefjnew].saveH * nT5;
      defBarShow["xbar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH * nT6;
      defBarShow["tt_" + wefjnew].toolTipTitle = _root.KrinLang[_root.KLangChoosen].ELEMENTS[wefjnew] + " " + _root.KrinLang[_root.KLangChoosen].SYSTEM[6] + ": " + yut_def2[wefjnew];
      defBarShow["tt_" + wefjnew].toolTip = _root.KrinLang[_root.KLangChoosen].DEFTIP[DEF_FACTOR];
      if(defBarShow["bar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {
         defBarShow["bar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH;
      }
      if(defBarShow["gbar" + wefjnew]._height > perBarShow["bar" + wefjnew].saveH)
      {
         defBarShow["gbar" + wefjnew]._height = perBarShow["bar" + wefjnew].saveH;
      }
      wefjnew++;
   }
   if(_root.Krin.MenuPlayerSelect == 0)
   {
      _root.Krin.LIFE = yut_lif2;
      _root.Krin.STRENGTH = yut_str2;
      _root.Krin.MAGIC = yut_mag2;
      _root.Krin.SPEED = yut_spd2;
      _root.Krin.FOCUS = yut_foc2;
      wefjnew = 0;
      while(wefjnew < 8)
      {
         _root.Krin.PER[_root.elementMainArray[wefjnew]] = yut_per2[wefjnew];
         _root.Krin.DEF[_root.elementMainArray[wefjnew]] = yut_def2[wefjnew];
         wefjnew++;
      }
   }
}
stop();
i = 0;
while(i < 6)
{
   this["fa" + i].id = _root.Krin.friendArray[i];
   if(this["fa" + i].id < 0)
   {
      this["fa" + i]._visible = false;
   }
   else
   {
      if(i == 0)
      {
         this["fa" + i].avIn.gotoAndStop("mainPlayer");
      }
      this["fa" + i].avIn.gotoAndStop(_root.Krin.friendArray[i]);
   }
   i++;
}
teamChangeCD = true;
bickerPicker = 0;
if(_root.Krin.friendArrayX[0] == 0)
{
   bickerPicker = 0;
}
if(_root.Krin.friendArrayX[1] == 0)
{
   bickerPicker = 1;
}
updateFriends();
wefjnew = 0;
while(wefjnew < 8)
{
   perBarShow["bar" + wefjnew].saveH = perBarShow["bar" + wefjnew]._height;
   var my_colorKKCCXX = new Color(perBarShow["bar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(perBarShow["gbar" + wefjnew]);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(perBarShow["ybar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   perBarShow["gbar" + wefjnew].saveH = perBarShow["bar" + wefjnew]._height / 100;
   wefjnew++;
}
wefjnew = 0;
while(wefjnew < 8)
{
   var my_colorKKCCXX = new Color(defBarShow["bar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(defBarShow["gbar" + wefjnew]);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   var my_colorKKCCXX = new Color(defBarShow["ybar" + wefjnew].inner);
   my_colorKKCCXX.setRGB(_root.elementColorArray[wefjnew]);
   wefjnew++;
}
yut_lif = _root.KrinLang[_root.KLangChoosen].SYSTEM[0] + ":";
yut_str = _root.KrinLang[_root.KLangChoosen].SYSTEM[1] + ":";
yut_mag = _root.KrinLang[_root.KLangChoosen].SYSTEM[2] + ":";
yut_spd = _root.KrinLang[_root.KLangChoosen].SYSTEM[3] + ":";
yut_foc = _root.KrinLang[_root.KLangChoosen].SYSTEM[4] + ":";
_root.Krin.MenuPlayerSelect = 0;
for(w in _root.Krin.itemArray)
{
   this["itemSlot" + w].inner.gotoAndStop(_root.KrinLang[_root.KLangChoosen].ITEMNAME[_root.Krin.itemArray[w]]);
   this["itemSlot" + w].id = w;
   this["itemSlot" + w].slotType = "itemSlot";
}
dollPartsArray = new Array();
dollPartsArray = ["head","chest","arm1","arm2","hand1","hand2","leg1","leg2","leg3","leg4","foot1","foot2","weapon1","weapon2","shoulder"];
dollPartsCores = new Array();
dollPartsCores = [0,1,1,1,2,2,3,3,4,4,4,4,5,6,1];
dollPartsCores2 = new Array();
dollPartsCores2 = ["HEAD","CHEST","ARM","ARM","HAND","HAND","ARM","ARM","LEG2","LEG2","FOOT","FOOT","WEAPON","WEAPON","SHOULDER"];
updateEquip();
updateDoll();
updateAvs();
updateStatus();
dumbEuro = _root.Krin.Euro;

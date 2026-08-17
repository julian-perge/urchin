_root.Krin.PauseForScreen = true;
_root.Krin.PauseForScreen2 = true;
_root.Krin.dataMode = "save";
itemsthatdropped = 0;
_root.KrinScreen._visible = false;
_root.Krin.EnemyXPFinal = _root.Krin.EnemyXP / _root.Krin.EnemyXP3;
for(w in _root.Krin.itemArray)
{
   this["itemSlot" + w].inner.gotoAndStop(_root.KrinLang[_root.KLangChoosen].ITEMNAME[_root.Krin.itemArray[w]]);
   this["itemSlot" + w].id = w;
   this["itemSlot" + w].slotType = "itemSlot";
}
w = 0;
while(w < 15)
{
   this["dropSlot" + w].inner.gotoAndStop(_root.KrinLang[_root.KLangChoosen].ITEMNAME[_root.Krin.dropArray[w]]);
   this["dropSlot" + w].id = w;
   this["dropSlot" + w].slotType = "drop";
   if(_root.Krin.dropArray[w] == 0)
   {
      this["dropSlot" + w]._visible = false;
   }
   else
   {
      itemsthatdropped = 1;
   }
   w++;
}
if(itemsthatdropped == 0)
{
   vb99 = _root.KrinLang[_root.KLangChoosen].MENU[12];
   vb2 = "";
}
else
{
   vb99 = "";
   vb2 = _root.KrinLang[_root.KLangChoosen].VICTORY[1];
}
tempGain = _root.moneyConstGain / _root.totalEnemyGain;
trace("TEMPGAIN " + tempGain);
trace("TEMPGAIN " + _root.respecValue(tempGain));
moneyGain = Math.round(0.7000000000000001 * _root.respecValue(tempGain));
_root.Krin.Euro += moneyGain;
dumbEuro = _root.Krin.Euro;
vb1 = _root.KrinLang[_root.KLangChoosen].VICTORY[0];
vb3 = _root.KrinLang[_root.KLangChoosen].VICTORY[2];
vb4 = _root.KrinLang[_root.KLangChoosen].VICTORY[3];
vb5 = "€" + moneyGain;
vbbc1 = _root.KrinLang[_root.KLangChoosen].MENU[15];
vb7 = _root.KrinLang[_root.KLangChoosen].VICTORY[4];
vb8 = _root.KrinLang[_root.KLangChoosen].MENU[13];

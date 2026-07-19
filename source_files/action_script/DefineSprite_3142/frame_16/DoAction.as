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
updateEquip();
updateDoll();
updateAvs();
updateStatus();
dumbEuro = _root.Krin.Euro;
dumbEuro = _root.Krin.Euro;
_root.krinSetShop(_root.Krin.shopId);
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
   this["dropSlot" + w].slotType = "buy";
   if(_root.Krin.dropArray[w] == 0)
   {
      this["dropSlot" + w]._visible = false;
   }
   else
   {
      this["dropSlot" + w]._visible = true;
   }
   w++;
}
vb1 = _root.KrinLang[_root.KLangChoosen].MENU[6];
vb2 = _root.KrinLang[_root.KLangChoosen].SHOP[_root.Krin.shopId];

i = 1;
while(i < 5)
{
   _root["nameSlot" + i] = _root["slot" + i].data.nameUser;
   _root["slot" + i].flush();
   if(_root["nameSlot" + i] == undefined)
   {
      _root["nameSlot" + i] = "< Empty Slot >";
   }
   i++;
}
slotNamerText = _root.KrinLang[KLangChoosen].MENU[23];
if(arenaMode)
{
   if(currentArenaPlayer == 1)
   {
      pickText = _root.KrinLang[KLangChoosen].MENU[72];
   }
}
else
{
   pickText = "";
}

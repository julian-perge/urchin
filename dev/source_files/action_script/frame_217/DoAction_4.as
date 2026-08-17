thtk = 1;
while(thtk < 7)
{
   if(_root["playerKrin" + thtk].active == true)
   {
      if(_root["playerKrin" + thtk].passiveBuffs.length > 0)
      {
         for(krinb in _root["playerKrin" + thtk].passiveBuffs)
         {
            _root.applyBuffKrin(_root["playerKrin" + thtk],_root["playerKrin" + thtk].passiveBuffs[krinb],1,_root["playerKrin" + thtk]);
         }
         _root.firstUpdate = true;
         _root.applyChangesKrin(_root["playerKrin" + thtk]);
         _root.firstUpdate = false;
      }
   }
   thtk++;
}

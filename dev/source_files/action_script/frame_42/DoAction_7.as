numberMatrixKrin = new Array();
numberMatrixKrin = ["Zero","One","Two","Three","Four","Five","Six","Seven","Eight","Nine"];
numberSpacingKrin = 19;
numberDepthCyler = 1620;
KrinNumberShow = function(inputNumberK, tarKN, KNcolor)
{
   var _loc4_;
   if(inputNumberK > 0 || inputNumberK == "miss" || inputNumberK == "shield")
   {
      if(KNcolor == "HEAL")
      {
         KNcolor2 = 6749952;
      }
      else
      {
         for(i in elementMainArray)
         {
            if(elementMainArray[i] == KNcolor)
            {
               KNcolor2 = elementColorArray[i];
            }
         }
      }
      if(inputNumberK != "miss" && inputNumberK != "shield")
      {
         gKMP = 1;
         while(inputNumberK / gKMP >= 1)
         {
            gKMP *= 10;
         }
         gKMP /= 10;
         gKMPsteps = Math.round(Math.log(gKMP) / 2.302585092994046);
         inputNumberK2 = inputNumberK;
         totalLKrinN = _root.numberSpacingKrin * (gKMPsteps - 1);
         KrinNOffset = - totalLKrinN / 2 - 10;
      }
      _root.BATTLESCREEN.attachMovie("NumberFixer","NumberFixer" + _root.numberDepthCyler,_root.numberDepthCyler);
      _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler]._x = _root.BATTLESCREEN[tarKN]._x;
      _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler]._y = _root.BATTLESCREEN[tarKN]._y;
      if(inputNumberK != "miss" && inputNumberK != "shield")
      {
         if(_root.perKSuccess)
         {
            _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].gotoAndPlay("critical");
         }
         else
         {
            _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].gotoAndPlay("normal");
         }
         i = gKMPsteps;
         while(i > -1)
         {
            _root["digitKVar" + i] = Math.floor(inputNumberK2 / Math.pow(10,i));
            inputNumberK2 -= _root["digitKVar" + i] * Math.pow(10,i);
            _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].flasher.attachMovie("NumberSetter","NumSet" + i,i);
            _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].flasher["NumSet" + i]._x = KrinNOffset + (_root.numberSpacingKrin * gKMPsteps - _root.numberSpacingKrin * i);
            _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].flasher["NumSet" + i].gotoAndStop(_root.numberMatrixKrin[_root["digitKVar" + i]]);
            _loc4_ = new Color(_root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].flasher["NumSet" + i].KN);
            _loc4_.setRGB(KNcolor2);
            i--;
         }
      }
      else if(inputNumberK == "miss")
      {
         _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].gotoAndPlay("miss");
         _loc4_ = new Color(_root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].flasher.KN);
         _loc4_.setRGB(KNcolor2);
      }
      else
      {
         _root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].gotoAndPlay("shield");
         _loc4_ = new Color(_root.BATTLESCREEN["NumberFixer" + _root.numberDepthCyler].flasher.KN);
         _loc4_.setRGB(KNcolor2);
      }
      _root.numberDepthCyler = _root.numberDepthCyler + 1;
      if(_root.numberDepthCyler == 1640)
      {
         _root.numberDepthCyler = 1620;
      }
   }
};

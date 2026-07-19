if(_root.achProgF)
{
   if(_root.Krin.BattlePick == 109)
   {
      _root.awardAch(0);
   }
   if(_root.Krin.difficulty > 0)
   {
      if(_root.Krin.BattlePick == 308)
      {
         if(!_root.AchVal2)
         {
            _root.awardAch(1);
         }
      }
      if(_root.Krin.BattlePick == 408)
      {
         if(_root.AchVal1 < 2000)
         {
            _root.awardAch(2);
         }
      }
   }
   if(_root.Krin.difficulty == 2)
   {
      if(_root.Krin.usedTraining == false)
      {
         if(_root.Krin.BattlePick == 212)
         {
            _root.awardAch(3);
         }
         if(_root.Krin.BattlePick == 513)
         {
            _root.awardAch(4);
         }
      }
   }
}
if(_root.Krin.BattlePick == 600)
{
   if(_root.AchVal3 == 1)
   {
      _root.awardAch(6);
   }
}
if(_root.Krin.BattlePick == 601)
{
   if(_root.AchVal4 <= 40)
   {
      _root.awardAch(7);
   }
}
if(_root.Krin.BattlePick == 602)
{
   if(!_root.AchVal2)
   {
      _root.awardAch(8);
   }
}
if(_root.Krin.BattlePick == 703)
{
   _root.awardAch(9);
}
if(_root.checkIfAllStar())
{
   _root.awardAch(5);
}

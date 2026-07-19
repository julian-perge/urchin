on(release){
   if(_root.Krin.statPoints > 0)
   {
      _root.Krin.StatSets0[0]++;
      _root.Krin.statPoints--;
      statPoints--;
      yut_lif2++;
      _root.Krin.LIFE++;
      if(_root.Krin.statPoints == 0)
      {
         statColor.gotoAndStop("dead");
      }
   }
}

function getStat(s_ratio, s_level, s_mode)
{
   if(s_level <= 0)
   {
      return 0;
   }
   if(s_level <= 5)
   {
      s_a = (9.25 * s_level + 45.75) / 4 * (s_ratio / 10);
   }
   else
   {
      s_a = (-0.0000213 * Math.pow(s_level,5) + 0.002 * Math.pow(s_level,4) - 0.0693 * Math.pow(s_level,3) + 1.43 * Math.pow(s_level,2) - 8.8533 * s_level + 39.5) * (s_ratio / 10);
   }
   if(s_level < 20)
   {
      s_r = -0.01929824 * s_level + 0.7159600000000003;
   }
   else
   {
      s_r = 0.33000000000000007;
   }
   if(s_mode == true)
   {
      s_a *= s_r / 2;
   }
   if(s_mode == false)
   {
      s_a *= 1 - s_r;
   }
   return s_a;
}
function givePoints(i_level, i_respec)
{
   i_b = getStat(40,i_level,true);
   if(i_respec)
   {
      i_a = Math.floor(i_b);
      i_e = i_b - i_a;
      Krin.pointResidue = 0;
   }
   else
   {
      i_c = getStat(40,i_level - 1,true);
      i_d = i_b - i_c;
      i_a = Math.floor(i_d);
      i_e = i_d - i_a;
   }
   Krin.pointResidue += i_e;
   if(Krin.pointResidue >= 1)
   {
      Krin.pointResidue--;
      i_a++;
   }
   return i_a;
}
function assignPointsStart(a_class)
{
   free_points = givePoints(1,true);
   split_ratio = new Array();
   split_ratio.push({val:_root["KNU" + (a_class + 1)][1] / 40 * free_points,id:0});
   split_ratio.push({val:_root["KNU" + (a_class + 1)][2] / 40 * free_points,id:1});
   split_ratio.push({val:_root["KNU" + (a_class + 1)][3] / 40 * free_points,id:2});
   split_ratio.push({val:_root["KNU" + (a_class + 1)][4] / 40 * free_points,id:3});
   for(i in split_ratio)
   {
      Krin.pointResidue += split_ratio[i].val - Math.floor(split_ratio[i].val);
      Krin.StatSets0[i] += Math.floor(split_ratio[i].val);
   }
   split_ratio.sortOn(["val","id"],[Array.DESCENDING | Array.NUMERIC,Array.NUMERIC]);
   cycle_split = 0;
   while(Krin.pointResidue >= 1)
   {
      Krin.StatSets0[split_ratio[cycle_split].id]++;
      cycle_split++;
      Krin.pointResidue--;
   }
}

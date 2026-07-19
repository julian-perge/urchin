expWorkOut = function(enemyXP, yourXP)
{
   Krin.diffXP = 1 + (enemyXP - yourXP) * 0.1;
   if(Krin.diffXP < 0)
   {
      Krin.diffXP = 0;
   }
   if(Krin.diffXP > 3)
   {
      Krin.diffXP = 3;
   }
   Krin.totalXP = 1.8000000000000005 * Krin.diffXP * (100 / (1 + Math.pow(yourXP,0.6)));
};

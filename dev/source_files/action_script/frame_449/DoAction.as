thingerDepthK = 0;
stop();
toGive = 0;
toGive = questHub.length;
if(achGet[4] == 0)
{
   toGive = questHub.length - 1;
}
if(Krin.difficulty == 1)
{
   toGive = questHub.length - 1;
}
if(Krin.difficulty == 0)
{
   toGive = questHub.length - 2;
}
i = 1;
while(i < toGive)
{
   krinMapper["mb" + i].sectionID = i;
   if(i > 1)
   {
      krinMapper.lineMC.createEmptyMovieClip("line_mc" + thingerDepthK,thingerDepthK);
      krinMapper.lineMC["line_mc" + thingerDepthK].lineStyle(6,0,100);
      krinMapper.lineMC["line_mc" + thingerDepthK].moveTo(krinMapper["mb" + i]._x,krinMapper["mb" + i]._y);
      krinMapper.lineMC["line_mc" + thingerDepthK].lineTo(krinMapper["mb" + questHub[i].linked]._x,krinMapper["mb" + questHub[i].linked]._y);
      thingerDepthK++;
   }
   if(i == 1 || questHub[questHub[i].linked].progressMax < Krin.questProgress[questHub[i].linked])
   {
      krinMapper["mb" + i].canUse = true;
      if(i > 1)
      {
         krinMapper.lineMC.createEmptyMovieClip("line_mc" + thingerDepthK,thingerDepthK);
         krinMapper.lineMC["line_mc" + thingerDepthK].lineStyle(2,3246559,100);
         krinMapper.lineMC["line_mc" + thingerDepthK].moveTo(krinMapper["mb" + i]._x,krinMapper["mb" + i]._y);
         krinMapper.lineMC["line_mc" + thingerDepthK].lineTo(krinMapper["mb" + questHub[i].linked]._x,krinMapper["mb" + questHub[i].linked]._y);
         thingerDepthK++;
      }
   }
   else
   {
      if(i > 1)
      {
         krinMapper.lineMC.createEmptyMovieClip("line_mc" + thingerDepthK,thingerDepthK);
         krinMapper.lineMC["line_mc" + thingerDepthK].lineStyle(2,3355443,100);
         krinMapper.lineMC["line_mc" + thingerDepthK].moveTo(krinMapper["mb" + i]._x,krinMapper["mb" + i]._y);
         krinMapper.lineMC["line_mc" + thingerDepthK].lineTo(krinMapper["mb" + questHub[i].linked]._x,krinMapper["mb" + questHub[i].linked]._y);
         thingerDepthK++;
      }
      krinMapper["mb" + i].underGF.gotoAndStop("blank");
      krinMapper["mb" + i].canUse = false;
   }
   i++;
}

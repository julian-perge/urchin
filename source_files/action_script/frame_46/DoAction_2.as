function awardAch(achNum)
{
   if(achGet[achNum] != 1)
   {
      achGet[achNum] = 1;
      achSlot.data.achGet[achNum] = 1;
      achSlot.flush();
      ach_Display.play();
      achGlobal = achNum;
   }
}
achGet = new Array();
achGet = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
var achSlot = SharedObject.getLocal("achSlot");
if(achSlot.data.achState == true)
{
   for(i in achGet)
   {
      achGet[i] = achSlot.data.achGet[i];
   }
}
else
{
   achSlot.data.achState = true;
   achSlot.data.achGet = new Array();
   for(i in achGet)
   {
      achSlot.data.achGet[i] = achGet[i];
   }
}
achSlot.flush();

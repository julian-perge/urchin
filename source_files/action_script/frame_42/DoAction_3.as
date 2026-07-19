function krinChangeColor(target, colorType)
{
   var _loc6_;
   var _loc11_;
   if(colorType == "Enrage")
   {
      _loc6_ = new flash.geom.ColorTransform();
      _loc11_ = new flash.geom.Transform(target);
      _loc6_.redOffset = 30;
      _loc6_.greenOffset = -130;
      _loc6_.blueOffset = -130;
      _loc11_.colorTransform = _loc6_;
   }
   var _loc5_;
   var _loc9_;
   if(colorType == "Poison")
   {
      _loc5_ = new flash.geom.ColorTransform();
      _loc9_ = new flash.geom.Transform(target);
      _loc5_.redOffset = -50;
      _loc5_.greenOffset = 0;
      _loc5_.blueOffset = -225;
      _loc9_.colorTransform = _loc5_;
   }
   var _loc7_;
   var _loc12_;
   if(colorType == "Normal")
   {
      _loc7_ = new flash.geom.ColorTransform();
      _loc12_ = new flash.geom.Transform(target);
      _loc7_.redOffset = 0;
      _loc7_.greenOffset = 0;
      _loc7_.blueOffset = 0;
      _loc12_.colorTransform = _loc7_;
   }
   var _loc4_;
   var _loc10_;
   if(colorType == "Hit")
   {
      _loc4_ = new flash.geom.ColorTransform();
      _loc10_ = new flash.geom.Transform(target);
      _loc4_.redOffset = 0;
      _loc4_.greenOffset = 0;
      _loc4_.blueOffset = 0;
      _loc10_.colorTransform = _loc4_;
   }
   var _loc3_;
   var _loc8_;
   if(colorType == "Common")
   {
      _loc3_ = new flash.geom.ColorTransform();
      _loc8_ = new flash.geom.Transform(target);
      _loc3_.redOffset = 0;
      _loc3_.greenOffset = 0;
      _loc3_.blueOffset = 0;
      _loc8_.colorTransform = _loc3_;
   }
   if(colorType == "Uncommon")
   {
      _loc3_ = new flash.geom.ColorTransform();
      _loc8_ = new flash.geom.Transform(target);
      _loc3_.redOffset = -62;
      _loc3_.greenOffset = -51;
      _loc3_.blueOffset = 0;
      _loc8_.colorTransform = _loc3_;
   }
   if(colorType == "Rare")
   {
      _loc3_ = new flash.geom.ColorTransform();
      _loc8_ = new flash.geom.Transform(target);
      _loc3_.redOffset = 86;
      _loc3_.greenOffset = 0;
      _loc3_.blueOffset = -164;
      _loc8_.colorTransform = _loc3_;
   }
   if(colorType == "Orange")
   {
      _loc3_ = new flash.geom.ColorTransform();
      _loc8_ = new flash.geom.Transform(target);
      _loc3_.redOffset = 126;
      _loc3_.greenOffset = 15;
      _loc3_.blueOffset = -200;
      _loc8_.colorTransform = _loc3_;
   }
   if(colorType == "Unique")
   {
      _loc3_ = new flash.geom.ColorTransform();
      _loc8_ = new flash.geom.Transform(target);
      _loc3_.redOffset = -67;
      _loc3_.greenOffset = 0;
      _loc3_.blueOffset = -159;
      _loc8_.colorTransform = _loc3_;
   }
   if(colorType == "Hit")
   {
      _loc4_ = new flash.geom.ColorTransform();
      _loc10_ = new flash.geom.Transform(target);
      _loc4_.redOffset = 0;
      _loc4_.greenOffset = 0;
      _loc4_.blueOffset = 0;
      _loc10_.colorTransform = _loc4_;
   }
}
var KrinFilterNone = new Array();
var KFBlur0 = new flash.filters.BlurFilter(2,2,1);
var KrinFilterBlur0 = new Array();
KrinFilterBlu0r.push(KFBlur0);
var KFBlur1 = new flash.filters.BlurFilter(4,4,1);
var KrinFilterBlur1 = new Array();
KrinFilterBlur1.push(KFBlur1);
var KFBlur2 = new flash.filters.BlurFilter(6,6,1);
var KrinFilterBlur2 = new Array();
KrinFilterBlur2.push(KFBlur2);
var KFBlur3 = new flash.filters.BlurFilter(8,8,1);
var KrinFilterBlur3 = new Array();
KrinFilterBlur3.push(KFBlur3);
var KFHit1 = new flash.filters.GlowFilter(16777215,1,100,100,10,1,true,false);
var KFHit2 = new flash.filters.GlowFilter(16763904,1,10,10,1,1,false,false);
var KFHit3 = new flash.filters.GlowFilter(16763904,1,10,10,1,1,true,false);
var KrinFilterHit = new Array();
KrinFilterHit.push(KFHit1);
KrinFilterHit.push(KFHit2);
KrinFilterHit.push(KFHit3);
var KFHeal1 = new flash.filters.GlowFilter(16777215,1,100,100,10,1,true,false);
var KFHeal2 = new flash.filters.GlowFilter(10092288,1,10,10,1,1,false,false);
var KFHeal3 = new flash.filters.GlowFilter(10092288,1,10,10,1,1,true,false);
var KrinFilterHeal = new Array();
KrinFilterHeal.push(KFHeal1);
KrinFilterHeal.push(KFHeal2);
KrinFilterHeal.push(KFHeal3);
var KFIce1 = new flash.filters.GlowFilter(16777215,1,14,14,1.4000000000000001,1,true,true);
var KFIce2 = new flash.filters.GlowFilter(3381759,1,24,24,3.8000000000000003,1,false,false);
var KrinFilterFrost = new Array();
KrinFilterFrost.push(KFIce1);
KrinFilterFrost.push(KFIce2);
var KFGreen1 = new flash.filters.GlowFilter(16777215,1,14,14,1.4000000000000001,1,true,true);
var KFGreen2 = new flash.filters.GlowFilter(3407616,1,24,24,3.8000000000000003,1,false,false);
var KrinFilterFrostGreen = new Array();
KrinFilterFrostGreen.push(KFGreen1);
KrinFilterFrostGreen.push(KFGreen2);
var KFFire1 = new flash.filters.GlowFilter(16776960,1,14,14,1.4000000000000001,1,true,true);
var KFFire2 = new flash.filters.GlowFilter(16763904,1,11,11,4.700000000000002,3,false,false);
var KFFire3 = new flash.filters.GlowFilter(16724736,1,33,33,2.2,1,false,false);
var KrinFilterFlame = new Array();
KrinFilterFlame.push(KFFire1);
KrinFilterFlame.push(KFFire2);
KrinFilterFlame.push(KFFire3);
var KFShadow1 = new flash.filters.GlowFilter(0,1,18,18,5,1,true,true);
var KFShadow2 = new flash.filters.GlowFilter(6697830,1,4,4,2.8000000000000003,1,false,false);
var KrinFilterShadow = new Array();
KrinFilterShadow.push(KFShadow1);
KrinFilterShadow.push(KFShadow2);
var KFIcy1 = new flash.filters.GlowFilter(6750207,1,9,9,3.8000000000000003,1,false,false);
var KrinFilterIcy = new Array();
KrinFilterIcy.push(KFIcy1);
var KFRed1 = new flash.filters.GlowFilter(16737792,1,10,10,1.7,1,false,false);
var KrinFilterRed = new Array();
KrinFilterRed.push(KFRed1);
var KFOrange1 = new flash.filters.GlowFilter(3407871,1,12,12,1.5,1,false,false);
var KrinFilterOrange = new Array();
KrinFilterOrange.push(KFOrange1);
var KFFocus1 = new flash.filters.GlowFilter(16777215,1,100,100,10,1,true,false);
var KFFocus2 = new flash.filters.GlowFilter(3407871,1,10,10,1,1,false,false);
var KFFocus3 = new flash.filters.GlowFilter(3407871,1,10,10,1,1,true,false);
var KrinFilterFocus = new Array();
KrinFilterFocus.push(KFFocus1);
KrinFilterFocus.push(KFFocus2);
KrinFilterFocus.push(KFFocus3);

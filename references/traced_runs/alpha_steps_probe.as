// A throwaway Probe for #442. It is not kept in dev/probes because it adds clips
// to the stage and quits the player. ALPHA lines step the _alpha of an empty clip
// by the same amount on every frame. FADE lines replay the enterFrame logic of
// each fade of the original on an empty clip, with the frame on which its input
// changes, and trace the _alpha that each frame left.
_root.createEmptyMovieClip("__alphaProbe", 16001);
_root.__alphaProbe.frame = 0;
_root.__alphaProbe.cases = [["in5", 0, 5], ["in10", 0, 10], ["in15", 0, 15], ["in20", 0, 20], ["in50", 0, 50], ["out5", 100, -5], ["out10", 100, -10], ["out15", 100, -15], ["out15from99", 99, -15], ["out20", 100, -20]];
_root.__alphaProbe.fades = ["ring", "speech", "radial", "hub", "cutscene", "bolt"];
_root.__alphaProbe.i = 0;
while(_root.__alphaProbe.i < _root.__alphaProbe.cases.length)
{
   var __c = _root.__alphaProbe.cases[_root.__alphaProbe.i];
   _root.__alphaProbe.createEmptyMovieClip(__c[0], _root.__alphaProbe.i + 1);
   _root.__alphaProbe[__c[0]]._alpha = __c[1];
   trace("ALPHA\t0\t" + __c[0] + "\t" + _root.__alphaProbe[__c[0]]._alpha);
   _root.__alphaProbe.i++;
}
_root.__alphaProbe.i = 0;
while(_root.__alphaProbe.i < _root.__alphaProbe.fades.length)
{
   _root.__alphaProbe.createEmptyMovieClip(_root.__alphaProbe.fades[_root.__alphaProbe.i], _root.__alphaProbe.i + 20);
   _root.__alphaProbe.i++;
}
// The ring (frame_217/PlaceObject3_3394_450): hovered on frames 1 to 10.
_root.__alphaProbe.ring._alpha = 0;
// The speech box (frame_217/PlaceObject2_3367_634): a line is up on frames 1 to 30 and 56 on.
_root.__alphaProbe.speech._alpha = 0;
// The orb ring (frame_217/PlaceObject3_3382_500): opened at 0, then the mouse is off it.
_root.__alphaProbe.radial._alpha = 0;
_root.__alphaProbe.radial.clicker = true;
_root.__alphaProbe.radial.shown = true;
// The Hub's fade (frame_181/PlaceObject2_2837_1660), with its load alpha.
_root.__alphaProbe.hub._alpha = 99;
// The cutscene's fade clip (frame_263/PlaceObject2_3466_80): placed opaque, cutSceneEnd from frame 26.
_root.__alphaProbe.cutscene._alpha = 100;
_root.__alphaProbe.cutscene.gone = false;
// The bolt (frame_42/DoAction_4.as:161-164), attached at 0.
_root.__alphaProbe.bolt._alpha = 0;
_root.__alphaProbe.i = 0;
while(_root.__alphaProbe.i < _root.__alphaProbe.fades.length)
{
   var __n = _root.__alphaProbe.fades[_root.__alphaProbe.i];
   trace("FADE\t0\t" + __n + "\t" + _root.__alphaProbe[__n]._alpha);
   _root.__alphaProbe.i++;
}
_root.__alphaProbe.onEnterFrame = function()
{
   this.frame++;
   var k = 0;
   while(k < this.cases.length)
   {
      var c = this.cases[k];
      this[c[0]]._alpha += c[2];
      trace("ALPHA\t" + this.frame + "\t" + c[0] + "\t" + this[c[0]]._alpha);
      k++;
   }
   var r = this.ring;
   if(this.frame <= 10)
   {
      if(r._alpha < 100)
      {
         r._alpha = r._alpha + 20;
      }
   }
   else if(r._alpha > 0)
   {
      r._alpha = r._alpha - 5;
   }
   var s = this.speech;
   if(this.frame <= 30 || this.frame >= 56)
   {
      if(s._alpha < 100)
      {
         s._alpha = s._alpha + 5;
      }
      else
      {
         s._alpha = 100;
      }
   }
   else if(s._alpha > 0)
   {
      s._alpha = s._alpha - 5;
   }
   var m = this.radial;
   if(m.shown)
   {
      if(m.clicker)
      {
         if(m._alpha < 100)
         {
            m._alpha = m._alpha + 50;
         }
         else
         {
            m._alpha = 100;
            m.clicker = false;
         }
      }
      else
      {
         m._alpha = m._alpha - 10;
         if(m._alpha <= 0)
         {
            m.shown = false;
            trace("FADE\t" + this.frame + "\tradial\thidden");
         }
      }
   }
   var h = this.hub;
   if(h._alpha > 0)
   {
      h._alpha = h._alpha - 15;
   }
   var q = this.cutscene;
   if(!q.gone)
   {
      if(this.frame < 26)
      {
         if(q._alpha > 0)
         {
            q._alpha = q._alpha - 5;
         }
      }
      else
      {
         q._alpha = q._alpha + 5;
         if(q._alpha >= 100)
         {
            q.gone = true;
            trace("FADE\t" + this.frame + "\tcutscene\tgone");
         }
      }
   }
   var b = this.bolt;
   if(b._alpha < 100)
   {
      b._alpha += 10;
   }
   var j = 0;
   while(j < this.fades.length)
   {
      trace("FADE\t" + this.frame + "\t" + this.fades[j] + "\t" + this[this.fades[j]]._alpha);
      j++;
   }
   if(this.frame >= 80)
   {
      trace("ALPHA\tdone");
      delete this.onEnterFrame;
      fscommand("quit");
   }
};

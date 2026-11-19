// A throwaway Probe for #37, kept as a reference and not in dev/probes/, so no
// Traced copy builds it. It changes what the game does: it clicks through the
// language screen and CLICK TO PLAY, then on the main menu sets Heroic, a
// four-member party (Sonny, Veradux, Roald, Felicity) at one level, and starts
// each battle of the queue in turn through LOADBATTLESCENE, as the hub's fight
// button does. On Heroic the player's half-turn passes by itself after 4
// seconds, so only AI units choose moves. Each run used this file with these
// queues and levels:
//   run 2 (Ruffle): queue [109,212,513], levels [10,14,27]
//   run 3 (Ruffle): queue [212,513,212,513,109], levels [25,45,25,45,12]
//   run 4 (Ruffle): queue [307,510,703,104,307,510], levels [18,27,34,7,18,27]
//   run 5 (Flash):  queue [212,212], levels [25,25]
_global.__drv = {state:"boot",idx:0,ticks:0,queue:[109,212,513],levels:[10,14,27]};
_global.__drvStart = function() {
   var D = _global.__drv;
   var K = _root.Krin;
   var lv = D.levels[D.idx];
   K.difficulty = 2;
   K.Level = lv;
   var j = 0;
   while(j < 4)
   {
      K.LevelStats[j] = lv;
      j++;
   }
   K.friendArray = [0,1,2,3,-1,-1];
   K.friendArrayX = [1,2];
   K.bossFight = true;
   K.progressFight = false;
   K.BattlePick = D.queue[D.idx];
   D.state = "loading";
   D.ticks = 0;
   trace("AIDRIVE\tstart\t" + K.BattlePick + "\t" + lv);
   _root.gotoAndPlay("LOADBATTLESCENE");
};
_global.__drvStep = function() {
   var D = _global.__drv;
   var f = _root._currentframe;
   D.ticks++;
   if(D.state == "boot")
   {
      if(f == 1 && D.ticks > 4)
      {
         _root.KLangChoosen = "ENGLISH";
         _root.gotoAndStop("playFromHere");
         _root.play();
      }
      else if(f == 4 || f == 5)
      {
         _root.play();
      }
      else if(f == 46 && D.ticks > 10)
      {
         _global.__drvStart();
      }
   }
   else if(D.state == "loading")
   {
      if(f >= 201 && _root.winCondition == -1)
      {
         D.state = "fighting";
         D.ticks = 0;
      }
   }
   else if(D.state == "fighting")
   {
      if(_root.winCondition != -1 || D.ticks > 2400)
      {
         trace("AIDRIVE\tend\t" + _root.Krin.BattlePick + "\t" + _root.winCondition + "\t" + D.ticks);
         D.state = "after";
         D.ticks = 0;
      }
   }
   else if(D.state == "after")
   {
      if(D.ticks > 16)
      {
         D.idx++;
         if(D.idx < D.queue.length)
         {
            _global.__drvStart();
         }
         else
         {
            trace("AIDRIVE\tdone");
            D.state = "done";
            clearInterval(_global.__drvTimer);
         }
      }
   }
};
_global.__drvTimer = setInterval(_global.__drvStep, 500);

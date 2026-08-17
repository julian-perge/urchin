function addSound(a, b)
{
   if(_root.Krin.sound)
   {
      if(a == "Effects")
      {
         if(b != undefined)
         {
            _root["my_sound" + soundCounter].setVolume(80);
            _root["my_sound" + soundCounter].attachSound(b);
            _root["my_sound" + soundCounter].start();
            soundCounter++;
            if(soundCounter == 4)
            {
               soundCounter = 1;
            }
         }
      }
      if(a == "Music")
      {
         if(b == 1)
         {
            if(soundModeKrin != 1)
            {
               soundModeKrin = 1;
               _root["music" + musicCounter].attachSound(soundPlayArray[soundPlayCounter]);
               soundPlayCounter++;
               if(soundPlayCounter == 12)
               {
                  soundPlayCounter = 0;
               }
               trace(soundPlayCounter);
               _root["music" + musicCounter].setVolume(0);
               _root["music" + musicCounter].start(0,80);
               musicCounter++;
               musicCounter2++;
               musicSwitch = 1;
               volUpRate = 0;
               if(musicCounter == 3)
               {
                  musicCounter = 1;
               }
               if(musicCounter2 == 3)
               {
                  musicCounter2 = 1;
               }
            }
         }
         if(b == 2)
         {
            if(soundModeKrin != 2)
            {
               soundModeKrin = 2;
               bossMusicYesNo = false;
               if(_root.Krin.bossFight == true || _root.Krin.bossMusic == true)
               {
                  bossMusicYesNo = true;
               }
               if(_root.Krin.progressLevelOn == 24)
               {
                  bossMusicYesNo = true;
               }
               if(_root.Krin.progressLevelOn == 30)
               {
                  bossMusicYesNo = true;
               }
               if(_root.Krin.progressLevelOn == 36)
               {
                  bossMusicYesNo = true;
               }
               if(bossMusicYesNo)
               {
                  _root["music" + musicCounter].attachSound("_music_boss");
               }
               else
               {
                  _root["music" + musicCounter].attachSound(soundPlayArray[soundPlayCounter]);
               }
               trace(soundPlayCounter);
               soundPlayCounter++;
               if(soundPlayCounter == 12)
               {
                  soundPlayCounter = 0;
               }
               if(bangStart)
               {
                  _root["music" + musicCounter].setVolume(80);
                  volUpRate = 80;
                  bangStart = false;
                  _root["music" + musicCounter2].stop();
               }
               else
               {
                  _root["music" + musicCounter].setVolume(0);
                  volUpRate = 0;
               }
               _root["music" + musicCounter].start(0,80);
               musicCounter++;
               musicCounter2++;
               musicSwitch = 1;
               if(musicCounter == 3)
               {
                  musicCounter = 1;
               }
               if(musicCounter2 == 3)
               {
                  musicCounter2 = 1;
               }
            }
         }
      }
   }
}
attachMovie("dog","dog1",1000);
attachMovie("dog","dog2",1001);
attachMovie("dog","dogA",1002);
attachMovie("dog","dogB",1003);
attachMovie("dog","dogC",1004);
var my_sound1 = new Sound(_root.dogA);
var my_sound2 = new Sound(_root.dogB);
var my_sound3 = new Sound(_root.dogC);
music1 = new Sound(_root.dog1);
music2 = new Sound(_root.dog2);
soundCounter = 1;
musicCounter = 1;
musicCounter2 = 2;
musicSwitch = 0;
onEnterFrame = function()
{
   if(musicSwitch)
   {
      if(volUpRate < 80)
      {
         volUpRate += 5;
         _root["music" + musicCounter2].setVolume(volUpRate);
         _root["music" + musicCounter].setVolume(80 - volUpRate);
         if(volUpRate == 80)
         {
            _root["music" + musicCounter].stop();
            musicSwitch = false;
         }
      }
   }
};

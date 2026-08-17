krinNavSpeech = function(speechIDKrin)
{
   if(_root.Krin.PauseForScreen != true)
   {
      _root.Krin.PauseForScreen = true;
      _root.krinNavHideUI(1);
   }
};
krinNavHideUI = function(whatToDo)
{
   if(_root.Krin.PauseForScreen == false)
   {
      _root.krinNavFadeSpeech._visible = true;
      _root.Krin.PauseForScreen = true;
      navTitle = _root.KrinLang[KLangChoosen].NAVTITLE[whatToDo];
      navText = _root.KrinLang[KLangChoosen].NAVTEXT[whatToDo];
   }
   else
   {
      _root.krinNavFadeSpeech._visible = false;
      _root.Krin.PauseForScreen = false;
      navTitle = "";
      navText = "";
   }
};
pggKKuuIIoo = 0;
Krin.bEr = 100;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 101;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 102;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 103;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 104;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 504;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
Krin.bEr = 33;
Krin.progressSpeech[Krin.bEr] = new Array();
Krin.progressSpeech[Krin.bEr][0] = _root.KrinLang[KLangChoosen].NAVTITLE2[pggKKuuIIoo];
Krin.progressSpeech[Krin.bEr][1] = _root.KrinLang[KLangChoosen].NAVTEXT2[pggKKuuIIoo];
pggKKuuIIoo++;
krinNavTutSpeech = function()
{
   if(Krin.tutSpeecher == false)
   {
      Krin.tutSpeecher = true;
      if(Krin.progressSpeech[Krin.previousBattleSp].length == 2)
      {
         _root.krinNavFadeSpeech._visible = true;
         _root.Krin.PauseForScreen = true;
         navTitle = Krin.progressSpeech[Krin.previousBattleSp][0];
         navText = Krin.progressSpeech[Krin.previousBattleSp][1];
         Krin.previousBattleSp = 0;
      }
   }
};

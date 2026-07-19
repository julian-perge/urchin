function refreshArenaUI()
{
   arenaPlayer1.krinNameUser = arenaPlayer1.nameUser;
   arenaPlayer2.krinNameUser = arenaPlayer2.nameUser;
   title1_1 = arenaPlayer1.krinNameUser;
   title2_1 = arenaPlayer2.krinNameUser;
   title1_2 = _root.KrinLang[KLangChoosen].SYSTEM[41] + arenaPlayer1.Level;
   title2_2 = _root.KrinLang[KLangChoosen].SYSTEM[41] + arenaPlayer2.Level;
   pvpIcon1.gotoAndStop(arenaPlayer1.Class + 1);
   pvpIcon2.gotoAndStop(arenaPlayer2.Class + 1);
   PvPCodeLode = false;
}
stop();
refreshArenaUI();
t_export = _root.KrinLang[_root.KLangChoosen].MENU[74];
t_import = _root.KrinLang[_root.KLangChoosen].MENU[75];
t_fight = _root.KrinLang[_root.KLangChoosen].MENU[76];
t_exit = _root.KrinLang[_root.KLangChoosen].MENU[77];
addSound("Music",1);

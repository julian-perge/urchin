onClipEvent(enterFrame){
   if(this.hitTest(_root._xmouse,_root._ymouse))
   {
      _root.KrinToolTipper.gotoAndPlay("GO");
      _root.KrinToolTipper.tt = _root.KrinLang[_root.KLangChoosen].MENU[54 + _parent.pN] + " " + _root.KrinLang[_root.KLangChoosen].MENU[64];
      _root.KrinToolTipper.t = _root.KrinLang[_root.KLangChoosen].MENU[59 + _parent.pN];
   }
}

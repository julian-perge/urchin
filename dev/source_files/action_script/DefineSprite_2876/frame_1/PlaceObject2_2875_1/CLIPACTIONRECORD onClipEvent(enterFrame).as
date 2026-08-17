onClipEvent(enterFrame){
   if(this.hitTest(_root._xmouse,_root._ymouse))
   {
      _root.KrinToolTipper.colorChange = "Common";
      _root.krinChangeColor(_root.KrinToolTipper.fontBacker2,_root.KrinToolTipper.colorChange);
      _root.KrinToolTipper.gotoAndPlay("GO");
      _root.KrinToolTipper.tt = _parent.toolTipTitle;
      _root.KrinToolTipper.t = _parent.toolTip;
   }
}

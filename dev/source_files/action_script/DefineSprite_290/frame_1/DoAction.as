onEnterFrame = function()
{
   urlStart = _url.indexOf("://") + 3;
   urlEnd = _url.indexOf("/",urlStart);
   domain = _url.substring(urlStart,urlEnd);
   LastDot = domain.lastIndexOf(".") - 1;
   pfixEnd = domain.lastIndexOf(".",LastDot) + 1;
   domain = domain.substring(pfixEnd,domain.length);
   if(domain != "" && domain != "armorgames.com")
   {
      _root.gameLimited = true;
   }
};
this._visible = false;

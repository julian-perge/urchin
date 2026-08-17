function sitelock()
{
   lock = true;
   for(i in urls_allowed)
   {
      currUrl = _url.toLowerCase();
      if(currUrl.indexOf(urls_allowed[i]) > 0)
      {
         lock = false;
      }
      if(currUrl.indexOf("http:") <= 0)
      {
         lock = false;
      }
   }
   if(lock)
   {
      gotoAndStop("YES_LOCK");
   }
   else
   {
      gotoAndStop("NO_LOCK");
      play();
   }
}
urls_allowed = ["armorgames.com"];
sitelock();

onClipEvent(load){
   zoomTime = 9;
   zoomRatio = 14;
   scaleChange = 30;
   zoomStep = zoomRatio / zoomTime;
   zoomFactor = zoomTime * (zoomStep + zoomRatio) / 2;
   zoomPoint = 0;
}

_global.__gotoLog = function(mc, kind, target) {
   trace("GOTO\t" + kind + "\t" + mc + "\t" + mc._currentframe + "\t" + target);
};
_global.__origStop = MovieClip.prototype.gotoAndStop;
_global.__origPlay = MovieClip.prototype.gotoAndPlay;
MovieClip.prototype.gotoAndStop = function(f) {
   _global.__gotoLog(this, "stop", f);
   _global.__origStop.apply(this, arguments);
};
MovieClip.prototype.gotoAndPlay = function(f) {
   _global.__gotoLog(this, "play", f);
   _global.__origPlay.apply(this, arguments);
};
ASSetPropFlags(MovieClip.prototype, ["gotoAndStop", "gotoAndPlay"], 1, 0);

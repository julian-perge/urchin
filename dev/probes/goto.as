_global.__origStop = MovieClip.prototype.gotoAndStop;
_global.__origPlay = MovieClip.prototype.gotoAndPlay;
_global.__gotoLog = function(mc, kind, from, target) {
   trace("GOTO\t" + kind + "\t" + mc + "\t" + mc._totalframes + "\t" + from + "\t" + target + "\t" + mc._currentframe);
};
MovieClip.prototype.gotoAndStop = function(f) {
   var from = this._currentframe;
   _global.__origStop.apply(this, arguments);
   _global.__gotoLog(this, "stop", from, f);
};
MovieClip.prototype.gotoAndPlay = function(f) {
   var from = this._currentframe;
   _global.__origPlay.apply(this, arguments);
   _global.__gotoLog(this, "play", from, f);
};
ASSetPropFlags(MovieClip.prototype, ["gotoAndStop", "gotoAndPlay"], 1, 0);
trace("HOOK\tinstalled\t" + (MovieClip.prototype.gotoAndStop != _global.__origStop));

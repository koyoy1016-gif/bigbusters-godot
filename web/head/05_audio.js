// 版86：ゲームの音（ブラウザの Web Audio）を、スマホで聞こえやすくする。
// 1. iPhone（Safari 16.4 から）：本体の消音スイッチ（マナーモード）がオンだと、ブラウザの音はふつう消える。
//    navigator.audioSession を「playback（再生）」にすると、音楽アプリと同じ扱いになり、消音スイッチがオンでも鳴る。
//    （この仕組みがないブラウザでは、何もしない）
// 2. ほかのタブ・ホーム画面に行った時は、音を止める（もどったら、また鳴らす）。playback にすると、画面を消しても鳴りつづけることがあるため。
//    Godot が作る音の入れ物（AudioContext）を覚えておき、見えない間は suspend（一時停止）する。
window.bbAudio = (function () {
  var state = { session: 'none', contexts: [], hidden: false, suspended: 0, resumed: 0 };
  try {
    if (typeof navigator !== 'undefined' && navigator.audioSession) {
      navigator.audioSession.type = 'playback';
      state.session = navigator.audioSession.type;
    }
  } catch (e) {
    state.session = 'error';
  }
  var Orig = typeof window !== 'undefined' ? (window.AudioContext || window.webkitAudioContext) : null;
  if (Orig) {
    var Wrapped = function (opts) {
      var ctx = opts === undefined ? new Orig() : new Orig(opts);
      state.contexts.push(ctx);
      return ctx;
    };
    Wrapped.prototype = Orig.prototype;
    window.AudioContext = Wrapped;
    if (window.webkitAudioContext) {
      window.webkitAudioContext = Wrapped;
    }
  }
  state.onVisibility = function () {
    var hidden = typeof document !== 'undefined' && document.visibilityState === 'hidden';
    state.hidden = hidden;
    for (var i = 0; i < state.contexts.length; i++) {
      var c = state.contexts[i];
      try {
        if (hidden && c.state === 'running') {
          c.suspend();
          state.suspended += 1;
        } else if (!hidden && c.state === 'suspended') {
          c.resume();
          state.resumed += 1;
        }
      } catch (e) {}
    }
  };
  if (typeof document !== 'undefined' && document.addEventListener) {
    document.addEventListener('visibilitychange', state.onVisibility);
  }
  return state;
})();

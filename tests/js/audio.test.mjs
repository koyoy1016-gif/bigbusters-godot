// 実行: node --test tests/js/audio.test.mjs
// 版86：web/head/05_audio.js（iPhone の消音スイッチでも鳴らす・見えない間は音を止める）を、偽のブラウザで確かめる。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const code = readFileSync(path.join(here, '..', '..', 'web', 'head', '05_audio.js'), 'utf8');

function makeBrowser({ audioSession = true, webkitOnly = false } = {}) {
  const listeners = {};
  class FakeCtx {
    constructor(opts) {
      this.opts = opts;
      this.state = 'running';
    }
    suspend() { this.state = 'suspended'; return Promise.resolve(); }
    resume() { this.state = 'running'; return Promise.resolve(); }
  }
  const document = {
    visibilityState: 'visible',
    addEventListener: (name, fn) => { (listeners[name] ||= []).push(fn); },
  };
  const navigator = audioSession ? { audioSession: { type: 'auto' } } : {};
  const window = {};
  if (webkitOnly) window.webkitAudioContext = FakeCtx; else window.AudioContext = FakeCtx;
  const ctx = vm.createContext({ window, document, navigator });
  vm.runInContext(code, ctx);
  const fire = (name) => (listeners[name] || []).forEach((fn) => fn());
  return { window, document, navigator, FakeCtx, fire };
}

test('iPhone：audioSession を playback（再生）にする（消音スイッチでも鳴る）', () => {
  const b = makeBrowser();
  assert.equal(b.navigator.audioSession.type, 'playback');
  assert.equal(b.window.bbAudio.session, 'playback');
});

test('audioSession がないブラウザでは、何もしないで動く', () => {
  const b = makeBrowser({ audioSession: false });
  assert.equal(b.window.bbAudio.session, 'none');
  const c = new b.window.AudioContext({ latencyHint: 'interactive' });
  assert.equal(c.state, 'running');
});

test('Godot が作る音の入れ物は、ふつうに作れて、覚えておく', () => {
  const b = makeBrowser();
  const c = new b.window.AudioContext({ sampleRate: 44100 });
  assert.ok(c instanceof b.FakeCtx);
  assert.ok(c instanceof b.window.AudioContext);
  assert.deepEqual(c.opts, { sampleRate: 44100 });
  assert.equal(b.window.bbAudio.contexts.length, 1);
});

test('ほかのタブ・ホーム画面へ行くと止め、もどると鳴らす', () => {
  const b = makeBrowser();
  const c = new b.window.AudioContext();
  b.document.visibilityState = 'hidden';
  b.fire('visibilitychange');
  assert.equal(c.state, 'suspended');
  b.document.visibilityState = 'visible';
  b.fire('visibilitychange');
  assert.equal(c.state, 'running');
  assert.equal(b.window.bbAudio.suspended, 1);
  assert.equal(b.window.bbAudio.resumed, 1);
});

test('古い Safari（webkitAudioContext だけ）でも動く', () => {
  const b = makeBrowser({ webkitOnly: true });
  const c = new b.window.AudioContext();
  assert.ok(c instanceof b.FakeCtx);
  assert.equal(b.window.webkitAudioContext, b.window.AudioContext);
});

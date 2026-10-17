// 実行: node --test tests/js/
// ブラウザ側の入り口（export_presets.cfg の head_include）を、偽のSDKで動かして確かめる。
// 本物のFirebaseには接続しない。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const cfg = readFileSync(path.join(here, '..', '..', 'export_presets.cfg'), 'utf8');
const heads = [...cfg.matchAll(/html\/head_include="([\s\S]*?)"\n/g)].map((m) => m[1]);
const head = heads.find((h) => h.length > 0);
const script = head.replace(/^<script>/, '').replace(/<\/script>$/, '');

function makeFakeSdk(opts = {}) {
  const store = new Map(); // パス → 値
  const disconnect = new Map(); // パス → 'remove'
  const listeners = new Set();
  const counts = { signIn: 0 };
  const children = (prefix) => {
    const out = {};
    for (const [p, v] of store) {
      if (p.startsWith(prefix + '/')) out[p.slice(prefix.length + 1)] = v;
    }
    return out;
  };
  const snapOf = (ref) => ({ val: () => { const c = children(ref.path); return Object.keys(c).length ? c : null; } });
  const notify = () => listeners.forEach((l) => l());
  return {
    store,
    disconnect,
    counts,
    app: { initializeApp: (c) => ({ c }) },
    auth: {
      getAuth: (app) => ({ app }),
      signInAnonymously: async () => {
        counts.signIn++;
        if (opts.signInError) throw opts.signInError;
        return { user: { uid: opts.uid ?? 'abc' } };
      },
    },
    db: {
      getDatabase: (app) => ({ app }),
      ref: (db, p) => ({ path: p }),
      get: async (ref) => snapOf(ref),
      set: async (ref, v) => {
        if (opts.deny && opts.deny(ref.path, v)) throw new Error('PERMISSION_DENIED: Permission denied');
        if (opts.setError) throw opts.setError;
        store.set(ref.path, v);
        notify();
      },
      remove: async (ref) => { store.delete(ref.path); notify(); },
      onValue: (ref, cb) => {
        const l = () => cb(snapOf(ref));
        listeners.add(l);
        l();
        return () => listeners.delete(l);
      },
      onDisconnect: (ref) => ({
        remove: async () => { disconnect.set(ref.path, 'remove'); },
        cancel: async () => { disconnect.delete(ref.path); },
      }),
    },
  };
}

function load(sdk) {
  const sandbox = { console, Date, JSON, Promise, Object, Array, String, Error };
  sandbox.window = { bbFirebaseLoadSdk: () => Promise.resolve(sdk) };
  vm.runInNewContext(script, sandbox);
  return sandbox.window.bbFirebase;
}

const CFG = '{"projectId":"bigbusters-new"}';

test('空の部屋：p1に入り、部屋に書き、切断時の削除を予約する', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  const slot = await bb.joinRoom(CFG, '1234');
  assert.equal(slot, 'p1');
  assert.equal(bb.state.status, 'in_room');
  assert.equal(bb.state.slot, 'p1');
  assert.equal(bb.state.uid, 'abc');
  const written = sdk.store.get('rooms/1234/players/p1');
  assert.equal(written.uid, 'abc');
  assert.equal(typeof written.joinedAt, 'number');
  assert.equal(sdk.disconnect.get('rooms/1234/players/p1'), 'remove');
  assert.deepEqual([...bb.state.members], ['p1']);
});

test('p1が埋まっていれば、p2に入る', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  sdk.store.set('rooms/1234/players/p1', { uid: 'zzz', joinedAt: 1 });
  const bb = load(sdk);
  assert.equal(await bb.joinRoom(CFG, '1234'), 'p2');
  assert.equal(sdk.store.get('rooms/1234/players/p2').uid, 'abc');
});

test('書き込みの直前に取られたら（権限で拒否）、次の枠に入る', async () => {
  const sdk = makeFakeSdk({ uid: 'abc', deny: (path) => path === 'rooms/1234/players/p1' });
  const bb = load(sdk);
  assert.equal(await bb.joinRoom(CFG, '1234'), 'p2');
  assert.equal(bb.state.status, 'in_room');
});

test('4枠とも埋まっていれば、満員になり、入らない', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  for (const s of ['p1', 'p2', 'p3', 'p4']) sdk.store.set(`rooms/1234/players/${s}`, { uid: 'x' + s, joinedAt: 1 });
  const bb = load(sdk);
  assert.equal(await bb.joinRoom(CFG, '1234'), '');
  assert.equal(bb.state.status, 'full');
  assert.equal(sdk.store.get('rooms/1234/players/p1').uid, 'xp1');
  assert.deepEqual([...bb.state.members], ['p1', 'p2', 'p3', 'p4']);
});

test('権限以外のエラーは、入らずに失敗として表示する', async () => {
  const sdk = makeFakeSdk({ uid: 'abc', setError: new Error('network down') });
  const bb = load(sdk);
  assert.equal(await bb.joinRoom(CFG, '1234'), '');
  assert.equal(bb.state.status, 'error');
  assert.match(bb.state.error, /network down/);
});

test('退出すると、枠と切断時の削除の予約が消え、状態は left になる', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  await bb.joinRoom(CFG, '1234');
  await bb.leaveRoom();
  assert.equal(sdk.store.has('rooms/1234/players/p1'), false);
  assert.equal(sdk.disconnect.has('rooms/1234/players/p1'), false);
  assert.equal(bb.state.status, 'left');
  assert.equal(bb.state.slot, '');
});

test('他の人が入ると、在室の一覧が更新される', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  await bb.joinRoom(CFG, '1234');
  await sdk.db.set({ path: 'rooms/1234/players/p3' }, { uid: 'q', joinedAt: 2 });
  assert.deepEqual([...bb.state.members], ['p1', 'p3']);
});

test('入り直しても、サインインは1回だけ', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  await bb.joinRoom(CFG, '1234');
  await bb.leaveRoom();
  await bb.joinRoom(CFG, '1234');
  assert.equal(sdk.counts.signIn, 1);
  assert.equal(bb.state.status, 'in_room');
});

test('入っていなければ、位置は送らない', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  assert.equal(bb.sendPosition(0.5, 0.5), false);
  assert.equal(bb.state.sent, 0);
});

test('入っていれば、位置を自分の枠に書き、送った数を数える', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  await bb.joinRoom(CFG, '1234');
  assert.equal(bb.sendPosition(0.25, 0.75), true);
  const pos = sdk.store.get('rooms/1234/positions/p1');
  assert.equal(pos.x, 0.25);
  assert.equal(pos.y, 0.75);
  assert.equal(typeof pos.t, 'number');
  assert.equal(bb.state.sent, 1);
});

test('他の人の位置を受け取り、受けた数を数える', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  await bb.joinRoom(CFG, '1234');
  await sdk.db.set({ path: 'rooms/1234/positions/p2' }, { x: 0.1, y: 0.9, t: 5 });
  assert.equal(bb.state.positions.p2.x, 0.1);
  assert.ok(bb.state.received >= 1);
});

test('退出すると、位置も消え、切断時の削除の予約も取り消す', async () => {
  const sdk = makeFakeSdk({ uid: 'abc' });
  const bb = load(sdk);
  await bb.joinRoom(CFG, '1234');
  bb.sendPosition(0.5, 0.5);
  assert.equal(sdk.disconnect.get('rooms/1234/positions/p1'), 'remove');
  await bb.leaveRoom();
  assert.equal(sdk.store.has('rooms/1234/positions/p1'), false);
  assert.equal(sdk.disconnect.has('rooms/1234/positions/p1'), false);
  assert.equal(Object.keys(bb.state.positions).length, 0);
});

// 実行: node --test tests/js/account.test.mjs
// ログイン・復旧コード・フレンド・しょうたい（web/head/30_account.js）を、偽のSDKで確かめる。本物のFirebaseには接続しない。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { webcrypto } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const headDir = path.join(here, '..', '..', 'web', 'head');
const script = ['10_room.js', '20_share.js', '30_account.js'].map((f) => readFileSync(path.join(headDir, f), 'utf8')).join('\n');
const CFG = '{"projectId":"bigbusters-new"}';

// 共有の部分（データと、アカウントの台帳）。端末ごとに、ログインの状態（auth）は別
function makeWorld() {
  return { store: new Map(), users: new Map(), listeners: new Set(), counter: 0 };
}

function makeSdk(world) {
  const { store, users, listeners } = world;
  const children = (prefix) => {
    const out = {};
    for (const [p, v] of store) {
      if (p.startsWith(prefix + '/')) out[p.slice(prefix.length + 1)] = v;
    }
    return out;
  };
  const snapOf = (ref) => ({
    val: () => {
      if (store.has(ref.path)) return store.get(ref.path);
      const c = children(ref.path);
      return Object.keys(c).length ? c : null;
    },
  });
  const notify = () => listeners.forEach((l) => l());
  const auths = new Map();
  const newUser = (email, password, anon) => {
    const user = { uid: 'u' + (++world.counter), isAnonymous: anon, email: email || null };
    if (email) users.set(email, { user, password });
    return user;
  };
  return {
    app: { initializeApp: (c, name = 'default') => ({ name }) },
    auth: {
      getAuth: (app) => {
        const name = app ? app.name : 'default';
        if (!auths.has(name)) auths.set(name, { name, currentUser: null, authStateReady: async () => {} });
        return auths.get(name);
      },
      signInAnonymously: async (auth) => { auth.currentUser = newUser(null, null, true); return { user: auth.currentUser }; },
      createUserWithEmailAndPassword: async (auth, email, password) => {
        if (users.has(email)) throw Object.assign(new Error('x'), { code: 'auth/email-already-in-use' });
        if (password.length < 6) throw Object.assign(new Error('x'), { code: 'auth/weak-password' });
        auth.currentUser = newUser(email, password, false);
        return { user: auth.currentUser };
      },
      signInWithEmailAndPassword: async (auth, email, password) => {
        const u = users.get(email);
        if (!u || u.password !== password) throw Object.assign(new Error('x'), { code: 'auth/invalid-credential' });
        auth.currentUser = u.user;
        return { user: u.user };
      },
      signOut: async (auth) => { auth.currentUser = null; },
      linkWithCredential: async (user, cred) => {
        if (users.has(cred.email)) throw Object.assign(new Error('x'), { code: 'auth/email-already-in-use' });
        user.email = cred.email;
        user.isAnonymous = false;
        users.set(cred.email, { user, password: cred.password });
        return { user };
      },
      EmailAuthProvider: { credential: (email, password) => ({ email, password }) },
    },
    db: {
      getDatabase: () => ({}),
      ref: (db, p) => ({ path: p }),
      get: async (ref) => snapOf(ref),
      runTransaction: async (ref, fn) => {
        const v = fn(store.has(ref.path) ? store.get(ref.path) : null);
        store.set(ref.path, v);
        notify();
        return { committed: true, snapshot: { val: () => v } };
      },
      set: async (ref, v) => { store.set(ref.path, v); notify(); },
      remove: async (ref) => {
        store.delete(ref.path);
        for (const p of [...store.keys()]) if (p.startsWith(ref.path + '/')) store.delete(p);
        notify();
      },
      onValue: (ref, cb) => {
        if (ref.path === '.info/connected') { cb({ val: () => true }); return () => {}; }
        const l = () => cb(snapOf(ref));
        listeners.add(l);
        l();
        return () => listeners.delete(l);
      },
      onDisconnect: () => ({ remove: async () => {}, cancel: async () => {} }),
    },
  };
}

// 1台ぶんのブラウザ（同じ世界を共有）
function device(world) {
  const sdk = makeSdk(world);
  const sandbox = { console, Date, JSON, Promise, Object, Array, String, Error, Number, Math, Uint8Array, crypto: webcrypto, setTimeout: () => 0 };
  sandbox.window = { bbFirebaseLoadSdk: () => Promise.resolve(sdk), bbNoHeartbeat: true, crypto: webcrypto };
  vm.runInNewContext(script, sandbox);
  const acc = sandbox.window.bbAccount;
  return { acc, sdk, bb: sandbox.window.bbFirebase };
}

const same = (a, b, msg) => assert.equal(JSON.stringify(a), JSON.stringify(b), msg);
const settle = () => new Promise((r) => setTimeout(r, 0));

test('ログインを作る：記録の持ち主・ID・復旧コード・フレンドコードができ、パスワードでログインできる', async () => {
  const world = makeWorld();
  const a = device(world);
  await a.acc.init(CFG);
  a.acc.setSave(JSON.stringify({ coins: 260, wins: 3, character: 'healer', quality: 'low' }));
  assert.equal(a.acc.state.signedIn, false);
  const short = await a.acc.register('abc');
  assert.equal(short.ok, false, '短いパスワードは断る');
  const r = await a.acc.register('secret-pass');
  assert.equal(r.ok, true, a.acc.state.message);
  assert.equal(r.loginId, '1', 'IDは1番から順の数字');
  assert.match(r.recoveryCode, /^[A-Z2-9]{20}$/);
  assert.equal(a.acc.state.signedIn, true);
  const sid = a.acc.state.sid;
  assert.match(sid, /^[A-Z2-9]{12}$/);
  const owners = [...world.store.keys()].filter((k) => k.startsWith('saves/' + sid + '/owners/'));
  assert.equal(owners.length, 2, '持ち主は、本人と復旧用の2つ');
  assert.ok(world.store.get('saves/' + sid + '/recovery'), '復旧用アカウントの uid を、書きかえできない形で記録');
  same({ sid, gen: '1' }, world.store.get('ids/' + r.loginId), 'IDの台帳');
  assert.equal(world.store.get('saves/' + sid + '/data').coins, 260, '記録を保存');
  assert.equal(world.store.get('friendCodes/' + a.acc.state.friendCode), sid, 'フレンドコードの台帳');
  assert.equal(a.sdk.auth.getAuth().currentUser.isAnonymous, false, '匿名ログインが、メールのログインにつながる（uidは同じ）');
  const again = await a.acc.register('secret-pass');
  assert.equal(again.ok, false, 'ログインずみの人は、もう一度作れない');

  // 別の端末：IDとパスワードでログイン→記録を引きつぐ
  const b = device(world);
  await b.acc.init(CFG);
  await b.bb._connect(CFG);
  const bad = await b.acc.login(r.loginId, 'wrong-pass');
  assert.equal(bad.ok, false);
  assert.match(b.acc.state.message, /ちがいます/);
  const unknown = await b.acc.login('ZZZZZZZZZZ', 'secret-pass');
  assert.equal(unknown.ok, false);
  const good = await b.acc.login(r.loginId.toLowerCase(), 'secret-pass');
  assert.equal(good.ok, true, '小文字で入れても通る');
  assert.equal(b.acc.state.needReload, true);
  // ページを読みこみなおしたあと（同じ端末で、もう一度 init）：状態が戻り、記録を読む
  const b2 = device(world);
  b2.sdk.auth.getAuth().currentUser = b.sdk.auth.getAuth().currentUser;
  await b2.acc.init(CFG);
  assert.equal(b2.acc.state.signedIn, true);
  assert.equal(b2.acc.state.loginId, r.loginId);
  assert.equal(b2.acc.state.save.coins, 260);
  assert.equal(b2.acc.state.friendCode, a.acc.state.friendCode);
});

test('パスワードを忘れたら、復旧コードで新しいパスワードにできる。古いパスワードは使えなくなる', async () => {
  const world = makeWorld();
  const a = device(world);
  await a.acc.init(CFG);
  const r = await a.acc.register('old-password');
  const sid = a.acc.state.sid;
  const oldOwners = [...world.store.keys()].filter((k) => k.startsWith('saves/' + sid + '/owners/'));
  const b = device(world);
  await b.acc.init(CFG);
  const wrong = await b.acc.recover(r.loginId, 'AAAAAAAAAAAAAAAAAAAA', 'new-password');
  assert.equal(wrong.ok, false, '復旧コードが違えば、できない');
  const short = await b.acc.recover(r.loginId, r.recoveryCode, 'x');
  assert.equal(short.ok, false);
  const ok = await b.acc.recover(r.loginId, r.recoveryCode, 'new-password');
  assert.equal(ok.ok, true, b.acc.state.message);
  assert.equal(world.store.get('ids/' + r.loginId).gen, '2');
  const owners = [...world.store.keys()].filter((k) => k.startsWith('saves/' + sid + '/owners/'));
  assert.equal(owners.length, 2, '持ち主：復旧用と新しいアカウント');
  const removed = oldOwners.filter((k) => !owners.includes(k));
  assert.equal(removed.length, 1, '古いパスワードのアカウントは、持ち主から外れる');
  const c = device(world);
  await c.acc.init(CFG);
  assert.equal((await c.acc.login(r.loginId, 'old-password')).ok, false, '古いパスワードではログインできない');
  assert.equal((await c.acc.login(r.loginId, 'new-password')).ok, true, '新しいパスワードで入れる');
  // 復旧コードは、そのあとも使える（もう一度忘れても大丈夫）
  const d = device(world);
  await d.acc.init(CFG);
  assert.equal((await d.acc.recover(r.loginId, r.recoveryCode.toLowerCase(), 'third-password')).ok, true);
  assert.equal(world.store.get('ids/' + r.loginId).gen, '3');
});

test('フレンド：コードで申しこみ→ひきうける→おたがいに入る。しょうたいは、フレンドどうしだけ', async () => {
  const world = makeWorld();
  const a = device(world);
  const b = device(world);
  await a.acc.init(CFG);
  await b.acc.init(CFG);
  await a.acc.register('password-a');
  await b.acc.register('password-b');
  await a.acc.setNickname('えー');
  await b.acc.setNickname('びー');
  assert.equal((await a.acc.requestFriend('ZZZZZZZZ')).ok, false, '知らないコード');
  assert.equal((await a.acc.requestFriend(a.acc.state.friendCode)).ok, false, '自分のコード');
  assert.equal((await a.acc.requestFriend(b.acc.state.friendCode)).ok, true);
  await settle();
  same(b.acc.state.inbox.map((i) => [i.from, i.type, i.nickname]), [[a.acc.state.sid, 'friend', 'えー']], 'bに申しこみが届く');
  same(b.acc.state.friends, [], 'ひきうける前は、フレンドではない');
  await b.acc.acceptFriend(a.acc.state.sid);
  await settle();
  await settle();
  same(b.acc.state.friends.map((f) => f.sid), [a.acc.state.sid], 'bのフレンドにaが入る');
  same(a.acc.state.friends.map((f) => [f.sid, f.nickname]), [[b.acc.state.sid, 'びー']], 'aのフレンドにbが入る');
  assert.equal(a.acc.state.inbox.length, 0, 'ひきうけの知らせは、片づく');
  assert.equal(b.acc.state.inbox.length, 0);
  // しょうたい
  await a.acc.invite(b.acc.state.sid, '4321');
  await settle();
  same(b.acc.state.inbox.map((i) => [i.type, i.room, i.nickname]), [['invite', '4321', 'えー']], 'bにしょうたいが届く');
  await b.acc.removeInbox(a.acc.state.sid);
  await settle();
  assert.equal(b.acc.state.inbox.length, 0, 'とじると消える');
  // 古いしょうたいは、見せずに消す
  world.store.set('inbox/' + b.acc.state.sid + '/' + a.acc.state.sid, { type: 'invite', room: '1111', nickname: 'えー', t: Date.now() - 11 * 60 * 1000 });
  world.listeners.forEach((l) => l());
  await settle();
  assert.equal(b.acc.state.inbox.length, 0, '10分すぎたしょうたいは出さない');
  assert.equal(world.store.has('inbox/' + b.acc.state.sid + '/' + a.acc.state.sid), false);
});

test('ゲスト（ログインなし）は、フレンドの操作ができない。ログインの設定がまだなら、案内が出る', async () => {
  const world = makeWorld();
  const a = device(world);
  await a.acc.init(CFG);
  assert.equal((await a.acc.requestFriend('ABCDEFGH')).ok, false);
  assert.match(a.acc.state.message, /ログイン/);
  // メール/パスワードがオフ：復旧用アカウントを作る時点で断られる
  const sdk = a.sdk;
  const orig = sdk.auth.createUserWithEmailAndPassword;
  sdk.auth.createUserWithEmailAndPassword = async () => { throw Object.assign(new Error('x'), { code: 'auth/operation-not-allowed' }); };
  const r = await a.acc.register('password-ok');
  assert.equal(r.ok, false);
  assert.match(a.acc.state.message, /メール\/パスワード/);
  assert.equal(a.sdk.auth.getAuth().currentUser.isAnonymous, true, '失敗しても、ゲストのまま');
  sdk.auth.createUserWithEmailAndPassword = orig;
});

test('IDは1番から順に配る。使われている番号は飛ばす。かんたんすぎるパスワードは断る', async () => {
  const world = makeWorld();
  world.store.set('ids/2', { sid: 'AAAAAAAAAAAA', gen: '1' });
  const a = device(world);
  await a.acc.init(CFG);
  assert.equal((await a.acc.register('111111')).ok, false, '同じ文字だけは断る');
  assert.equal((await a.acc.register('123456')).ok, false, 'よくある並びは断る');
  assert.equal((await a.acc.register('abc')).ok, false);
  const r1 = await a.acc.register('mypass');
  assert.equal(r1.ok, true, a.acc.state.message);
  assert.equal(r1.loginId, '1');
  const b = device(world);
  await b.acc.init(CFG);
  const r2 = await b.acc.register('otherpass');
  assert.equal(r2.loginId, '3', '2番は使われているので飛ばす');
  const c = device(world);
  await c.acc.init(CFG);
  assert.equal((await c.acc.login('1', 'mypass')).ok, true, '数字のIDでログインできる');
});

test('同じ人が使える画面は1つだけ。あとから開いた画面が使える', async () => {
  const world = makeWorld();
  const a = device(world);
  await a.acc.init(CFG);
  await a.acc.register('mypass');
  await a.acc.claimSession();
  assert.equal(a.acc.state.displaced, false);
  // 同じアカウントで、別の端末がログイン
  const b = device(world);
  await b.acc.init(CFG);
  await b.sdk.auth.signInWithEmailAndPassword(b.sdk.auth.getAuth(), '1.1@bb.example.com', 'mypass');
  await b.acc.init(CFG);
  assert.equal(b.acc.state.sid, a.acc.state.sid);
  await b.acc.claimSession();
  await settle();
  assert.equal(a.acc.state.displaced, true, '先の画面は外される');
  assert.equal(b.acc.state.displaced, false);
  await a.acc.claimSession();
  await settle();
  assert.equal(b.acc.state.displaced, true, 'この画面でつかう、で取りもどせる');
  assert.equal(a.acc.state.displaced, false);
});

test('ゲストは、端末（uid）ごとに1つ。べつの人どうしは外し合わない', async () => {
  const world = makeWorld();
  const a = device(world);
  const b = device(world);
  await a.acc.init(CFG);
  await b.acc.init(CFG);
  await a.acc.claimSession();
  await b.acc.claimSession();
  await settle();
  assert.equal(a.acc.state.displaced, false);
  assert.equal(b.acc.state.displaced, false);
});

test('ログインを切りかえる前に、ゲストの席を空ける（同じ人が2人に数えられない）。失敗したら入り直す', async () => {
  const world = makeWorld();
  const a = device(world);
  await a.acc.init(CFG);
  await a.acc.register('mypass');
  const g = device(world);
  await g.acc.init(CFG);
  await g.bb.joinRoom(CFG, '4321');
  assert.ok(world.store.has('rooms/4321/players/p1'));
  const bad = await g.acc.login('1', 'wrong-pass');
  assert.equal(bad.ok, false);
  await settle();
  assert.ok(world.store.has('rooms/4321/players/p1'), 'パスワードをまちがえたら、席にもどる');
  const ok = await g.acc.login('1', 'mypass');
  assert.equal(ok.ok, true);
  assert.equal(world.store.has('rooms/4321/players/p1'), false, 'ログインに成功したら、ゲストの席は空いている');
});

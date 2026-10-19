window.bbAccount = {
  state: {
    status: 'idle', busy: false, message: '', signedIn: false, loginId: '', sid: '', nickname: '',
    friendCode: '', friends: [], inbox: [], save: null, recoveryCode: '', needReload: false, displaced: false, sessionOn: false
  },
  _cfg: '',
  _save: null,
  _domain: 'bb.example.com',
  _alphabet: 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
  _unsubInbox: null,
  _unsubFriends: null,
  _inviteMaxMs: 600000,
  // 文字（紛らわしい 0 O 1 I は除く）。32種類なので、バイト値の下5ビットで、かたよりなく選べる
  _rand: function (n) {
    var buf = new Uint8Array(n);
    var c = (typeof crypto !== 'undefined') ? crypto : window.crypto;
    c.getRandomValues(buf);
    var out = '';
    for (var i = 0; i < n; i++) { out += this._alphabet.charAt(buf[i] & 31); }
    return out;
  },
  _email: function (loginId, gen) {
    return String(loginId).toLowerCase() + '.' + gen + '@' + this._domain;
  },
  // ログインを切りかえる前に、ゲストの席を空ける（切りかえたあとでは、前の席を片づけられず、同じ人が2人に数えられる）
  _leaveKeep: function () {
    var rb = window.bbFirebase;
    var want = rb && rb._desired;
    if (!rb || !want || !rb.leaveRoom) { return Promise.resolve(null); }
    return Promise.resolve(rb.leaveRoom()).then(function () { return want; }, function () { return want; });
  },
  _rejoin: function (want) {
    var rb = window.bbFirebase;
    if (want && rb && rb.joinRoom) { rb.joinRoom(want.configJson, want.code, want.timingJson); }
  },
  // 番号札：1番から順に配る。先に誰かが使っていた番号（いたずら）は飛ばす
  _issueId: function (c, tries) {
    var self = this;
    if (tries > 20) { return Promise.reject(this._stop('IDを つくれませんでした。もういちど ためしてください')); }
    return c.d.runTransaction(this._ref(c, 'counter/ids'), function (cur) { return (typeof cur === 'number' ? cur : 0) + 1; }).then(function (r) {
      var id = String(r.snapshot.val());
      return self._get(c, 'ids/' + id).then(function (taken) {
        return taken ? self._issueId(c, tries + 1) : id;
      });
    });
  },
  // パスワードの強さ（Firebaseは6もじ以上）。かんたんすぎるものは断る
  _weakPassword: function (p) {
    if (typeof p !== 'string' || p.length < 6) { return 'パスワードは 6もじ いじょうに してください'; }
    if (p.split(p.charAt(0)).join('') === '' || /^(123456|1234567|12345678|123456789|password|qwerty|abcdef|abc123|111222)$/i.test(p)) { return 'かんたんすぎます。ほかの パスワードに してください'; }
    return '';
  },
  _clean: function (text) {
    return String(text || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  },
  _explain: function (e) {
    var c = (e && e.code) ? String(e.code) : '';
    var m = String((e && e.message) || e || '');
    if (/wrong-password|invalid-credential|user-not-found|invalid-login/.test(c)) { return 'IDかパスワードが ちがいます'; }
    if (/weak-password/.test(c)) { return 'パスワードが みじかすぎます'; }
    if (/network/.test(c)) { return 'つうしんに しっぱいしました'; }
    if (/operation-not-allowed|admin-restricted/.test(c)) { return 'ログインの せっていが まだです（Firebaseで メール/パスワードを オンに してください）'; }
    if (/too-many-requests/.test(c)) { return 'しばらく まってから もういちど ためしてください'; }
    if (/PERMISSION_DENIED|permission/i.test(m)) { return 'Firebaseのルールが まだ 新しくなっていません'; }
    return 'エラー：' + (c || m);
  },
  _fail: function (e) {
    this.state.busy = false;
    this.state.message = (e && e.bbMessage) ? e.bbMessage : this._explain(e);
    return { ok: false, message: this.state.message };
  },
  _stop: function (text) {
    var e = new Error(text);
    e.bbMessage = text;
    return e;
  },
  _ctx: function () {
    var self = this;
    return window.bbFirebase._connect(this._cfg).then(function (s) {
      return { s: s, sdk: s.sdk, d: s.sdk.db, auth: s.sdk.auth.getAuth(), db: s.database };
    });
  },
  // 別の接続（別アプリ）で、いまのログインを切り替えずに、メールのアカウントを作る
  _createOther: function (c, email, password) {
    var app2 = c.sdk.app.initializeApp(JSON.parse(this._cfg), 'bb-secondary');
    var auth2 = c.sdk.auth.getAuth(app2);
    return c.sdk.auth.createUserWithEmailAndPassword(auth2, email, password).then(function (cred) {
      var uid = cred.user.uid;
      return Promise.resolve(c.sdk.auth.signOut(auth2)).then(function () { return uid; });
    });
  },
  _ref: function (c, path) { return c.d.ref(c.db, path); },
  _set: function (c, path, value) { return c.d.set(this._ref(c, path), value); },
  _get: function (c, path) { return c.d.get(this._ref(c, path)).then(function (snap) { return snap.val(); }); },
  _remove: function (c, path) { return c.d.remove(this._ref(c, path)); },
  // 別の端末でなまえを変えていると、この端末の記憶が古いので、送る直前に、サーバーのなまえを読む
  _freshNickname: function (c) {
    var self = this;
    return this._get(c, 'profiles/' + this.state.sid + '/nickname').then(function (n) {
      self.state.nickname = n || '';
    });
  },
  _saveObject: function () {
    var o = this._save || {};
    return {
      coins: Math.max(0, Math.floor(Number(o.coins) || 0)),
      wins: Math.max(0, Math.floor(Number(o.wins) || 0)),
      character: String(o.character || '').slice(0, 40),
      quality: String(o.quality || '').slice(0, 16),
      t: Date.now()
    };
  },
  init: function (cfgJson) {
    var self = this;
    this._cfg = cfgJson;
    this.state.status = 'pending';
    return this._ctx().then(function (c) {
      var user = c.auth.currentUser;
      if (user && !user.isAnonymous) { return self._restore(c, user); }
      self.state.status = 'ok';
      return null;
    }).catch(function (e) { self.state.status = 'error'; self._fail(e); });
  },
  // ログインずみの人の、保存・プロフィール・フレンドを読み、見張りを始める
  _restore: function (c, user) {
    var self = this;
    var local = String(user.email || '').split('@')[0].split('.')[0].toUpperCase();
    return this._get(c, 'links/' + user.uid).then(function (sid) {
      if (!sid) { throw self._stop('アカウントの じょうほうが みつかりません'); }
      self.state.sid = sid;
      self.state.loginId = local;
      return Promise.all([self._get(c, 'profiles/' + sid), self._get(c, 'saves/' + sid + '/data')]).then(function (r) {
        var profile = r[0] || {};
        self.state.nickname = profile.nickname || '';
        self.state.friendCode = profile.friendCode || '';
        self.state.save = r[1] || null;
        self.state.signedIn = true;
        self.state.status = 'ok';
        self._watch(c);
      });
    });
  },
  _watch: function (c) {
    var self = this;
    if (this._unsubInbox) { this._unsubInbox(); }
    if (this._unsubFriends) { this._unsubFriends(); }
    var sid = this.state.sid;
    this._unsubFriends = c.d.onValue(this._ref(c, 'saves/' + sid + '/friends'), function (snap) {
      var v = snap.val() || {};
      self.state.friends = Object.keys(v).map(function (k) { return { sid: k, nickname: (v[k] && v[k].nickname) || '' }; });
    });
    this._unsubInbox = c.d.onValue(this._ref(c, 'inbox/' + sid), function (snap) {
      var v = snap.val() || {};
      var items = [];
      Object.keys(v).forEach(function (from) {
        var it = v[from] || {};
        if (it.type === 'friend_ok') {
          // 相手が、フレンドの申しこみを引きうけた：自分のフレンドにも入れる
          self._set(c, 'saves/' + sid + '/friends/' + from, { nickname: it.nickname || '', t: Date.now() })
            .then(function () { return self._remove(c, 'inbox/' + sid + '/' + from); })
            .catch(function () {});
        } else if (it.type === 'invite' && Date.now() - (it.t || 0) > self._inviteMaxMs) {
          self._remove(c, 'inbox/' + sid + '/' + from).catch(function () {});
        } else {
          items.push({ from: from, type: it.type, nickname: it.nickname || '', room: it.room || '', t: it.t || 0 });
        }
      });
      self.state.inbox = items;
    });
  },
  // ---- ログインを作る（いまの匿名ログインに、IDとパスワードをつなぐ。記録はそのまま引きつぐ） ----
  register: function (password) {
    var self = this;
    var weak = this._weakPassword(password);
    if (weak) { return Promise.resolve(this._fail(this._stop(weak))); }
    this.state.busy = true;
    this.state.message = 'ログインを つくっています…';
    var loginId = '';
    var recovery = this._rand(20);
    var sid = this._rand(12);
    var fcode = this._rand(8);
    var ctx = null;
    var uidRecovery = '';
    return this._ctx().then(function (c) {
      ctx = c;
      var user = c.auth.currentUser;
      if (!user) { throw self._stop('ログインの じゅんびが できていません'); }
      if (!user.isAnonymous) { throw self._stop('もう ログインずみです'); }
      // ①IDは、1番から順の数字（番号札の係りを1つずつ増やす）
      return self._issueId(c, 0).then(function (id) {
        loginId = id;
        // ②復旧用のアカウント（パスワード＝復旧コード）
        return self._createOther(c, self._email(loginId, 'r'), recovery);
      });
    }).then(function (uidR) {
      uidRecovery = uidR;
      var uid = ctx.auth.currentUser.uid;
      // ②記録の持ち主として、自分と復旧用を登録（先に自分、あとで復旧用）
      return self._set(ctx, 'saves/' + sid + '/owners/' + uid, true)
        .then(function () { return self._set(ctx, 'saves/' + sid + '/recovery', uidRecovery); })
        .then(function () { return self._set(ctx, 'saves/' + sid + '/owners/' + uidRecovery, true); })
        .then(function () { return self._set(ctx, 'links/' + uid, sid); })
        .then(function () { return self._set(ctx, 'ids/' + loginId, { sid: sid, gen: '1' }); })
        .then(function () { return self._set(ctx, 'friendCodes/' + fcode, sid); })
        .then(function () { return self._set(ctx, 'profiles/' + sid, { nickname: '', friendCode: fcode }); })
        .then(function () { return self._set(ctx, 'saves/' + sid + '/data', self._saveObject()); });
    }).then(function () {
      // ③最後に、メールのログインをつなぐ（ここで失敗しても、記録はむだになるだけで、ゲストのまま遊べる）
      var cred = ctx.sdk.auth.EmailAuthProvider.credential(self._email(loginId, '1'), password);
      return ctx.sdk.auth.linkWithCredential(ctx.auth.currentUser, cred);
    }).then(function () {
      self.state.sid = sid;
      self.state.loginId = loginId;
      self.state.friendCode = fcode;
      self.state.nickname = '';
      self.state.signedIn = true;
      self.state.recoveryCode = recovery;
      self.state.busy = false;
      self.state.message = 'ログインを つくりました。IDと復旧コードを メモしてください';
      self._watch(ctx);
      return { ok: true, loginId: loginId, recoveryCode: recovery };
    }).catch(function (e) { return self._fail(e); });
  },
  // ---- ログイン（IDとパスワード）。別の端末で、記録を引きつぐとき ----
  login: function (loginIdRaw, password) {
    var self = this;
    var loginId = this._clean(loginIdRaw);
    this.state.busy = true;
    this.state.message = 'ログインしています…';
    var ctx = null;
    var want = null;
    return this._ctx().then(function (c) {
      ctx = c;
      return self._get(c, 'ids/' + loginId);
    }).then(function (idv) {
      if (!idv) { throw self._stop('IDかパスワードが ちがいます'); }
      return self._leaveKeep().then(function (w) {
        want = w;
        return ctx.sdk.auth.signInWithEmailAndPassword(ctx.auth, self._email(loginId, idv.gen), password);
      });
    }).then(function () {
      self.state.busy = false;
      self.state.needReload = true;
      self.state.message = 'ログインしました。ページを よみこみなおします';
      self._reloadSoon();
      return { ok: true };
    }).catch(function (e) { self._rejoin(want); return self._fail(e); });
  },
  // ---- パスワードをわすれたとき：復旧コードで、新しいパスワードを決める ----
  recover: function (loginIdRaw, code, newPassword) {
    var self = this;
    var loginId = this._clean(loginIdRaw);
    var weakNew = this._weakPassword(newPassword);
    if (weakNew) { return Promise.resolve(this._fail(this._stop(weakNew))); }
    this.state.busy = true;
    this.state.message = '復旧しています…';
    var ctx = null;
    var want = null;
    var idv = null;
    var uidR = '';
    return this._ctx().then(function (c) {
      ctx = c;
      return self._get(c, 'ids/' + loginId);
    }).then(function (v) {
      if (!v) { throw self._stop('IDか 復旧コードが ちがいます'); }
      idv = v;
      return self._leaveKeep().then(function (w) {
        want = w;
        return ctx.sdk.auth.signInWithEmailAndPassword(ctx.auth, self._email(loginId, 'r'), self._clean(code));
      });
    }).then(function (cred) {
      uidR = cred.user.uid;
      var newGen = String(Number(idv.gen) + 1);
      idv.newGen = newGen;
      return self._set(ctx, 'links/' + uidR, idv.sid)
        .then(function () { return self._createOther(ctx, self._email(loginId, newGen), newPassword); });
    }).then(function (uidN) {
      // 新しいアカウントを持ち主に入れ、古いパスワードのアカウントは、持ち主から外す
      return self._get(ctx, 'saves/' + idv.sid + '/owners').then(function (owners) {
        var tasks = [];
        Object.keys(owners || {}).forEach(function (u) {
          if (u !== uidR && u !== uidN) { tasks.push(self._remove(ctx, 'saves/' + idv.sid + '/owners/' + u)); }
        });
        return Promise.all(tasks);
      }).then(function () { return self._set(ctx, 'saves/' + idv.sid + '/owners/' + uidN, true); })
        .then(function () { return self._set(ctx, 'ids/' + loginId, { sid: idv.sid, gen: idv.newGen }); });
    }).then(function () {
      return ctx.sdk.auth.signInWithEmailAndPassword(ctx.auth, self._email(loginId, idv.newGen), newPassword);
    }).then(function (cred) {
      return self._set(ctx, 'links/' + cred.user.uid, idv.sid);
    }).then(function () {
      self.state.busy = false;
      self.state.needReload = true;
      self.state.message = 'あたらしい パスワードに しました。ページを よみこみなおします';
      self._reloadSoon();
      return { ok: true };
    }).catch(function (e) { return self._fail(e); });
  },
  logout: function () {
    var self = this;
    var want = null;
    return this._leaveKeep().then(function (w) {
      want = w;
      return self._ctx();
    }).then(function (c) { return c.sdk.auth.signOut(c.auth); }).then(function () {
      self.state.signedIn = false;
      self.state.needReload = true;
      self._reloadSoon();
      return { ok: true };
    }).catch(function (e) { self._rejoin(want); return self._fail(e); });
  },
  // ---- 1つの人（アカウント。ゲストは端末）が、同時に使える画面は1つだけ。あとから開いた画面が使える ----
  claimSession: function () {
    var self = this;
    return this._ctx().then(function (c) {
      var key = self.state.sid || c.auth.currentUser.uid;
      self._token = self._rand(16);
      if (self._unsubSession) { self._unsubSession(); self._unsubSession = null; }
      self.state.displaced = false;
      var ref = self._ref(c, 'active/' + key);
      return c.d.set(ref, { token: self._token, t: Date.now() }).then(function () {
        self._unsubSession = c.d.onValue(ref, function (snap) {
          var v = snap.val();
          self.state.displaced = !!(v && v.token !== self._token);
        });
        self.state.sessionOn = true;
        return { ok: true };
      });
    }).catch(function (e) { return self._fail(e); });
  },
  _reloadSoon: function () {
    setTimeout(function () {
      try {
        var room = (window.bbFirebase && window.bbFirebase.state.room) || '';
        window.location.href = window.location.origin + window.location.pathname + (room ? '?room=' + room : '');
      } catch (e) {}
    }, 1200);
  },
  // ---- 記録の保存（ゲームの記録を、ログインずみのときだけ、サーバーにも書く） ----
  setSave: function (json) {
    try { this._save = JSON.parse(json); } catch (e) { return Promise.resolve(false); }
    if (!this.state.signedIn) { return Promise.resolve(false); }
    var self = this;
    return this._ctx().then(function (c) {
      return self._set(c, 'saves/' + self.state.sid + '/data', self._saveObject());
    }).then(function () { return true; }, function () { return false; });
  },
  setNickname: function (name) {
    var self = this;
    var n = '';
    Array.from(String(name || '').trim()).forEach(function (ch) { if ((n + ch).length <= 12) { n += ch; } });
    if (!this.state.signedIn) { return Promise.resolve(this._fail(this._stop('ログインが ひつようです'))); }
    return this._ctx().then(function (c) {
      return self._set(c, 'profiles/' + self.state.sid + '/nickname', n);
    }).then(function () {
      self.state.nickname = n;
      self.state.message = 'なまえを かえました';
      return { ok: true };
    }).catch(function (e) { return self._fail(e); });
  },
  // ---- フレンド ----
  requestFriend: function (codeRaw) {
    var self = this;
    var code = this._clean(codeRaw);
    if (!this.state.signedIn) { return Promise.resolve(this._fail(this._stop('ログインが ひつようです'))); }
    var ctx = null;
    return this._ctx().then(function (c) {
      ctx = c;
      return self._freshNickname(c).then(function () { return self._get(c, 'friendCodes/' + code); });
    }).then(function (target) {
      if (!target) { throw self._stop('そのコードは みつかりません'); }
      if (target === self.state.sid) { throw self._stop('それは じぶんの コードです'); }
      return self._set(ctx, 'inbox/' + target + '/' + self.state.sid, { type: 'friend', nickname: self.state.nickname, t: Date.now() });
    }).then(function () {
      self.state.message = 'フレンドの もうしこみを おくりました。あいてが ひきうけると フレンドになります';
      return { ok: true };
    }).catch(function (e) { return self._fail(e); });
  },
  acceptFriend: function (from) {
    var self = this;
    var ctx = null;
    var item = null;
    this.state.inbox.forEach(function (i) { if (i.from === from && i.type === 'friend') { item = i; } });
    if (!item) { return Promise.resolve({ ok: false }); }
    return this._ctx().then(function (c) {
      ctx = c;
      return self._freshNickname(c);
    }).then(function () {
      return self._set(ctx, 'saves/' + self.state.sid + '/friends/' + from, { nickname: item.nickname, t: Date.now() });
    }).then(function () {
      return self._set(ctx, 'inbox/' + from + '/' + self.state.sid, { type: 'friend_ok', nickname: self.state.nickname, t: Date.now() });
    }).then(function () {
      return self._remove(ctx, 'inbox/' + self.state.sid + '/' + from);
    }).then(function () { return { ok: true }; }).catch(function (e) { return self._fail(e); });
  },
  removeInbox: function (from) {
    var self = this;
    return this._ctx().then(function (c) { return self._remove(c, 'inbox/' + self.state.sid + '/' + from); })
      .then(function () { return { ok: true }; }).catch(function (e) { return self._fail(e); });
  },
  invite: function (friendSid, room) {
    var self = this;
    return this._ctx().then(function (c) {
      return self._freshNickname(c).then(function () {
        return self._set(c, 'inbox/' + friendSid + '/' + self.state.sid, { type: 'invite', room: String(room), nickname: self.state.nickname, t: Date.now() });
      });
    }).then(function () {
      self.state.message = 'しょうたいを おくりました';
      return { ok: true };
    }).catch(function (e) { return self._fail(e); });
  },
  // ---- 画面：本物の入力欄（スマホのキーボード・パスワード保存が、ふつうに動くように、ブラウザ側で作る） ----
  hideForm: function () {
    var old = document.getElementById('bb-account');
    if (old && old.parentNode) { old.parentNode.removeChild(old); }
  },
  showForm: function (kind, labels) {
    var self = this;
    this.hideForm();
    var box = document.createElement('div');
    box.id = 'bb-account';
    box.style.cssText = 'position:fixed;left:0;right:0;top:0;bottom:0;z-index:99998;background:rgba(10,14,22,0.96);color:#fff;padding:20px;font-family:sans-serif;overflow:auto;text-align:center;';
    var title = document.createElement('div');
    title.textContent = labels['title_' + kind] || kind;
    title.style.cssText = 'font-size:22px;margin:12px 0;';
    box.appendChild(title);
    var inputs = {};
    var addInput = function (key, type, label) {
      var wrap = document.createElement('div');
      wrap.style.cssText = 'margin:10px 0;';
      var lab = document.createElement('div');
      lab.textContent = label;
      lab.style.cssText = 'font-size:15px;margin-bottom:4px;';
      var input = document.createElement('input');
      input.type = type;
      input.style.cssText = 'width:90%;max-width:360px;font-size:18px;padding:10px;border-radius:6px;border:0;';
      if (type === 'password') { input.autocomplete = kind === 'login' ? 'current-password' : 'new-password'; }
      wrap.appendChild(lab);
      wrap.appendChild(input);
      box.appendChild(wrap);
      inputs[key] = input;
    };
    if (kind === 'register') { addInput('pw', 'password', labels.password); addInput('pw2', 'password', labels.password_again); }
    if (kind === 'login') { addInput('id', 'text', labels.login_id); addInput('pw', 'password', labels.password); }
    if (kind === 'recover') { addInput('id', 'text', labels.login_id); addInput('code', 'text', labels.recovery_code); addInput('pw', 'password', labels.new_password); }
    if (kind === 'friend') { addInput('code', 'text', labels.friend_code); }
    if (kind === 'nickname') { addInput('name', 'text', labels.nickname); }
    var msg = document.createElement('div');
    msg.style.cssText = 'min-height:24px;margin:12px 0;font-size:16px;color:#ffd866;white-space:pre-wrap;';
    box.appendChild(msg);
    var result = document.createElement('div');
    result.style.cssText = 'margin:8px 0;';
    box.appendChild(result);
    var style = 'font-size:18px;padding:12px 20px;margin:6px;border:0;border-radius:8px;color:#fff;';
    var ok = document.createElement('button');
    ok.textContent = labels.submit;
    ok.style.cssText = style + 'background:#3366cc;';
    var close = document.createElement('button');
    close.textContent = labels.close;
    close.style.cssText = style + 'background:#444;';
    var showCodes = function (r) {
      result.innerHTML = '';
      var items = [[labels.login_id, r.loginId], [labels.recovery_code, r.recoveryCode]];
      items.forEach(function (it) {
        var row = document.createElement('div');
        row.style.cssText = 'margin:8px 0;';
        var l = document.createElement('div');
        l.textContent = it[0];
        l.style.cssText = 'font-size:14px;';
        var f = document.createElement('input');
        f.type = 'text';
        f.readOnly = true;
        f.value = it[1];
        f.style.cssText = 'width:90%;max-width:360px;font-size:20px;padding:8px;text-align:center;letter-spacing:2px;';
        row.appendChild(l);
        row.appendChild(f);
        result.appendChild(row);
      });
      var note = document.createElement('div');
      note.textContent = labels.save_note;
      note.style.cssText = 'font-size:14px;color:#ff9a9a;margin-top:6px;';
      result.appendChild(note);
    };
    ok.onclick = function () {
      if (self.state.busy) { return; }
      var run = null;
      if (kind === 'register') {
        if (inputs.pw.value !== inputs.pw2.value) { msg.textContent = labels.mismatch; return; }
        run = self.register(inputs.pw.value);
      } else if (kind === 'login') {
        run = self.login(inputs.id.value, inputs.pw.value);
      } else if (kind === 'recover') {
        run = self.recover(inputs.id.value, inputs.code.value, inputs.pw.value);
      } else if (kind === 'friend') {
        run = self.requestFriend(inputs.code.value);
      } else if (kind === 'nickname') {
        run = self.setNickname(inputs.name.value);
      }
      msg.textContent = '…';
      run.then(function (r) {
        msg.textContent = self.state.message;
        if (r && r.ok && kind === 'register') { showCodes(r); }
      });
    };
    close.onclick = function () { self.hideForm(); };
    var row = document.createElement('div');
    row.appendChild(ok);
    row.appendChild(close);
    box.appendChild(row);
    document.body.appendChild(box);
  }
};

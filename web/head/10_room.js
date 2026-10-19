window.bbFirebase = {
  state: { status: 'idle', uid: '', error: '', room: '', slot: '', members: [], positions: {}, hits: {}, hp: {}, chars: {}, votes: {}, effects: {}, phases: {}, who: {}, round: 0, offset: 0, sent: 0, received: 0, connection: 'unknown' },
  _active: null,
  _session: null,
  _unsubscribe: null,
  _unsubscribePositions: null,
  _unsubscribeHits: null,
  _unsubscribeHp: null,
  _unsubscribeRound: null,
  _unsubscribeOffset: null,
  _unsubscribeConnection: null,
  _desired: null,
  _retryTimer: null,
  _attempt: 0,
  _joining: null,
  _heartbeat: null,
  _checking: false,
  _checkStarted: 0,
  _replyMs: 8000,
  _timing: { hold_ms: 60000, heartbeat_ms: 5000 },
  _roster: {},
  _joinedAt: 0,
  _visibilityBound: false,
  _parseTiming: function (t) {
    var o = {};
    try { o = JSON.parse(t || '{}') || {}; } catch (e) { o = {}; }
    return {
      hold_ms: typeof o.hold_ms === 'number' ? o.hold_ms : 60000,
      heartbeat_ms: typeof o.heartbeat_ms === 'number' ? o.heartbeat_ms : 5000
    };
  },
  _loadSdk: function () {
    if (window.bbFirebaseLoadSdk) { return window.bbFirebaseLoadSdk(); }
    var base = 'https://www.gstatic.com/firebasejs/11.10.0/';
    return Promise.all([
      import(base + 'firebase-app.js'),
      import(base + 'firebase-auth.js'),
      import(base + 'firebase-database.js')
    ]).then(function (m) { return { app: m[0], auth: m[1], db: m[2] }; });
  },
  _connect: function (configJson) {
    var self = this;
    if (!this._session) {
      this._session = this._loadSdk().then(function (sdk) {
        var app = sdk.app.initializeApp(JSON.parse(configJson));
        var auth = sdk.auth.getAuth(app);
        // 前のログインが残っていれば、それを使う（匿名ログインで上書きしない。アカウントのログインを保つため）
        var ready = auth.authStateReady ? auth.authStateReady() : Promise.resolve();
        return ready.then(function () {
          return auth.currentUser ? { user: auth.currentUser } : sdk.auth.signInAnonymously(auth);
        }).then(function (cred) {
          self.state.uid = cred.user.uid;
          self._active = { sdk: sdk, database: sdk.db.getDatabase(app), uid: cred.user.uid };
          self._watchConnection(self._active);
          return self._active;
        });
      }).catch(function (e) {
        self._session = null;
        throw e;
      });
    }
    return this._session;
  },
  _fail: function (e) {
    this.state.error = ((e && e.code) ? e.code + ' ' : '') + ((e && e.message) ? e.message : String(e));
    this.state.status = 'error';
  },
  _isDenied: function (e) {
    return !!e && /PERMISSION_DENIED|permission/i.test(String((e && e.message) || e));
  },
  nextDelayMs: function (attempt) {
    return Math.min(1000 * Math.pow(2, attempt), 16000);
  },
  signIn: function (configJson) {
    if (this.state.status !== 'idle') { return Promise.resolve(); }
    var self = this;
    this.state.status = 'pending';
    return this._connect(configJson).then(function () {
      self.state.status = 'ok';
    }, function (e) { self._fail(e); });
  },
  // 枠が生きているか：ほかの人の枠で、最後の書き直しが保持時間の内
  _isLive: function (v, uid) {
    return !!v && v.uid !== uid && (Date.now() - (v.seen || 0)) < this._timing.hold_ms;
  },
  joinRoom: function (configJson, code, timingJson) {
    var self = this;
    if (this._joining && this._joining.code === code) { return this._joining.promise; }
    if (this.state.slot && this.state.room === code && this.state.status === 'in_room') {
      return Promise.resolve(this.state.slot);
    }
    if (this.state.slot && this.state.room !== code) {
      return this.leaveRoom().then(function () { return self.joinRoom(configJson, code, timingJson); });
    }
    this._desired = { configJson: configJson, code: code, timingJson: timingJson || '{}' };
    this._timing = this._parseTiming(timingJson);
    this.state.room = code;
    this.state.error = '';
    this.state.status = 'joining';
    var promise = this._connect(configJson).then(function (s) {
      var d = s.sdk.db;
      return d.get(d.ref(s.database, 'rooms/' + code + '/players')).then(function (snap) {
        return self._tryClaim(s, code, snap.val() || {}, 0);
      });
    }).catch(function (e) {
      self._fail(e);
      return '';
    }).then(function (slot) {
      self._joining = null;
      return slot;
    });
    this._joining = { code: code, promise: promise };
    return promise;
  },
  _tryClaim: function (s, code, taken, i) {
    var self = this;
    var slots = ['p1', 'p2', 'p3', 'p4'];
    if (i >= slots.length) {
      this.state.status = 'full';
      this._desired = null;
      this._watch(s, code);
      this._stopHeartbeat();
      return Promise.resolve('');
    }
    var slot = slots[i];
    if (this._isLive(taken[slot], s.uid)) { return this._tryClaim(s, code, taken, i + 1); }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + code + '/players/' + slot);
    var posRef = d.ref(s.database, 'rooms/' + code + '/positions/' + slot);
    var hitsRef = d.ref(s.database, 'rooms/' + code + '/hits/' + slot);
    var joinedAt = Date.now();
    return d.set(ref, { uid: s.uid, joinedAt: joinedAt, seen: joinedAt }).then(function () {
      return d.onDisconnect(posRef).remove();
    }).then(function () {
      return d.set(hitsRef, 0).catch(function () {});
    }).then(function () {
      return d.remove(d.ref(s.database, 'rooms/' + code + '/phase/' + slot)).catch(function () {});
    }).then(function () {
      return d.remove(d.ref(s.database, 'rooms/' + code + '/who/' + slot)).catch(function () {});
    }).then(function () {
      self._phase = '';
      self._joinedAt = joinedAt;
      self.state.slot = slot;
      self.state.status = 'in_room';
      self._attempt = 0;
      self._watch(s, code);
      return slot;
    }, function (e) {
      if (!self._isDenied(e)) { throw e; }
      return self._tryClaim(s, code, taken, i + 1);
    });
  },
  _stopWatch: function () {
    if (this._unsubscribe) { this._unsubscribe(); this._unsubscribe = null; }
    if (this._unsubscribePositions) { this._unsubscribePositions(); this._unsubscribePositions = null; }
    if (this._unsubscribeHits) { this._unsubscribeHits(); this._unsubscribeHits = null; }
    if (this._unsubscribeHp) { this._unsubscribeHp(); this._unsubscribeHp = null; }
    if (this._unsubscribeRound) { this._unsubscribeRound(); this._unsubscribeRound = null; }
    if (this._unsubscribeChars) { this._unsubscribeChars(); this._unsubscribeChars = null; }
    if (this._unsubscribeVotes) { this._unsubscribeVotes(); this._unsubscribeVotes = null; }
    if (this._unsubscribeEffects) { this._unsubscribeEffects(); this._unsubscribeEffects = null; }
    if (this._unsubscribePhases) { this._unsubscribePhases(); this._unsubscribePhases = null; }
    if (this._unsubscribeWho) { this._unsubscribeWho(); this._unsubscribeWho = null; }
  },
  // 在室の一覧：保持時間の内に書き直された枠だけを数える
  _refreshMembers: function () {
    var v = this._roster || {};
    var now = Date.now();
    var hold = this._timing.hold_ms;
    this.state.members = ['p1', 'p2', 'p3', 'p4'].filter(function (x) {
      return !!v[x] && (now - (v[x].seen || 0)) < hold;
    });
  },
  _watch: function (s, code) {
    var self = this;
    var d = s.sdk.db;
    this._stopWatch();
    this._unsubscribe = d.onValue(d.ref(s.database, 'rooms/' + code + '/players'), function (snap) {
      self._roster = snap.val() || {};
      self._refreshMembers();
    }, function (e) { self._fail(e); });
    this._unsubscribePositions = d.onValue(d.ref(s.database, 'rooms/' + code + '/positions'), function (snap) {
      self.state.received += 1;
      self.state.positions = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribeHits = d.onValue(d.ref(s.database, 'rooms/' + code + '/hits'), function (snap) {
      self.state.hits = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribeHp = d.onValue(d.ref(s.database, 'rooms/' + code + '/hp'), function (snap) {
      self.state.hp = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribeRound = d.onValue(d.ref(s.database, 'rooms/' + code + '/round'), function (snap) {
      var v = snap.val();
      self.state.round = typeof v === 'number' ? v : 0;
    }, function (e) { self._fail(e); });
    this._unsubscribeChars = d.onValue(d.ref(s.database, 'rooms/' + code + '/chars'), function (snap) {
      self.state.chars = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribeVotes = d.onValue(d.ref(s.database, 'rooms/' + code + '/votes'), function (snap) {
      self.state.votes = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribeEffects = d.onValue(d.ref(s.database, 'rooms/' + code + '/effects'), function (snap) {
      self.state.effects = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribePhases = d.onValue(d.ref(s.database, 'rooms/' + code + '/phase'), function (snap) {
      self.state.phases = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._unsubscribeWho = d.onValue(d.ref(s.database, 'rooms/' + code + '/who'), function (snap) {
      self.state.who = snap.val() || {};
    }, function (e) { self._fail(e); });
    this._startHeartbeat();
  },
  _watchConnection: function (s) {
    var self = this;
    var d = s.sdk.db;
    if (this._unsubscribeConnection) { this._unsubscribeConnection(); }
    if (this._unsubscribeOffset) { this._unsubscribeOffset(); }
    this._unsubscribeOffset = d.onValue(d.ref(s.database, '.info/serverTimeOffset'), function (snap) {
      var v = snap.val();
      self.state.offset = typeof v === 'number' ? v : 0;
    }, function () {});
    this._unsubscribeConnection = d.onValue(d.ref(s.database, '.info/connected'), function (snap) {
      if (snap.val() === true) {
        self.state.connection = 'connected';
        if (self._desired) { self._ensureInRoom(); }
      } else {
        self.state.connection = 'disconnected';
        if (self._desired) { self.state.status = 'reconnecting'; }
      }
    }, function (e) { self._fail(e); });
  },
  _startHeartbeat: function () {
    var self = this;
    if (!window.bbNoHeartbeat && !this._heartbeat) {
      this._heartbeat = setInterval(function () {
        self._beat();
        self._refreshMembers();
      }, this._timing.heartbeat_ms);
    }
    if (typeof document !== 'undefined' && !this._visibilityBound) {
      this._visibilityBound = true;
      document.addEventListener('visibilitychange', function () {
        if (!document.hidden && self._desired) {
          self._beat();
          self._refreshMembers();
        }
      });
    }
  },
  _stopHeartbeat: function () {
    if (this._heartbeat) { clearInterval(this._heartbeat); this._heartbeat = null; }
  },
  // 心拍：自分の枠に、今の時刻を書き直す。枠を取られていれば（拒否）、次の枠に入る
  _beat: function () {
    var self = this;
    var s = this._active;
    var want = this._desired;
    var slot = this.state.slot;
    if (!s || !want || !slot || this.state.status === 'joining') { return; }
    if (this._checking) {
      if (Date.now() - this._checkStarted > this._replyMs) {
        this._checking = false;
        this.state.connection = 'disconnected';
        this.state.status = 'reconnecting';
      }
      return;
    }
    this._checking = true;
    this._checkStarted = Date.now();
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + want.code + '/players/' + slot);
    d.set(ref, { uid: s.uid, joinedAt: this._joinedAt, seen: Date.now() }).then(function () {
      self._checking = false;
      self.state.connection = 'connected';
      if (self.state.status === 'reconnecting') { self.state.status = 'in_room'; }
    }, function (e) {
      self._checking = false;
      if (self._isDenied(e)) {
        self.state.slot = '';
        self._rejoin();
      }
    });
  },
  _ensureInRoom: function () {
    var self = this;
    var s = this._active;
    var want = this._desired;
    var slot = this.state.slot;
    if (!s || !want || !slot || this.state.status === 'joining') { return; }
    var d = s.sdk.db;
    d.get(d.ref(s.database, 'rooms/' + want.code + '/players/' + slot)).then(function (snap) {
      var v = snap.val();
      if (v && v.uid === s.uid) {
        self.state.status = 'in_room';
        self._beat();
        return;
      }
      self.state.slot = '';
      self._rejoin();
    }, function () {
      self._scheduleRetry();
    });
  },
  _rejoin: function () {
    var self = this;
    var want = this._desired;
    if (!want) { return; }
    this.state.status = 'joining';
    this.joinRoom(want.configJson, want.code, want.timingJson).then(function (slot) {
      if (slot || !self._desired) { return; }
      self._scheduleRetry();
    });
  },
  _scheduleRetry: function () {
    var self = this;
    if (this._retryTimer) { clearTimeout(this._retryTimer); }
    var delay = this.nextDelayMs(this._attempt);
    this._attempt += 1;
    this.state.status = 'reconnecting';
    this._retryTimer = setTimeout(function () {
      self._retryTimer = null;
      if (self._desired) { self._rejoin(); }
    }, delay);
  },
  sendPosition: function (x, y) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/positions/' + slot);
    var self = this;
    this.state.sent += 1;
    d.set(ref, { x: x, y: y, t: Date.now() }).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // 自分が与えた合計ダメージを、自分の枠に書く（ボスの体力は、全員の合計から計算する）
  sendHits: function (total) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/hits/' + slot);
    var self = this;
    d.set(ref, total).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // 自分の体力を、自分の枠に書く（{hp, round}。round は、どの戦いの体力か。なかまの体力の表示と、全滅の判定に使う）
  sendHp: function (hp, round) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/hp/' + slot);
    var self = this;
    d.set(ref, { hp: hp, round: round }).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // 自分が選んだキャラの id を、自分の枠に書く（なかまの表示と、ハイライトのキャラに使う）
  sendChar: function (id) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/chars/' + slot);
    var self = this;
    d.set(ref, id).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // 「さいせん／ロビー」の投票を、自分の枠に書く（round は、どの戦いのあとの投票か）
  sendVote: function (vote, round) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/votes/' + slot);
    var self = this;
    d.set(ref, { v: vote, round: round }).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // いまの状態（lobby / ready / battle / result）を、自分の枠に書く。入ってくる人が、戦いの最中かを知るのに使う
  sendPhase: function (v) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/phase/' + slot);
    var self = this;
    this._phase = v;
    d.set(ref, { v: v, t: Date.now() }).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // 味方に効く技（回復・バリアなど）を、自分の枠に書く。type は技の種類、t はサーバー時刻、value は数値
  sendEffect: function (type, t, value, round) {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/effects/' + slot);
    var self = this;
    d.set(ref, { type: type, t: t, value: value, round: round }).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  // 戦いを始める：開始の時刻（サーバー時刻）を、部屋に書く。全員が、同じ時刻から数える
  startRound: function () {
    var s = this._active;
    var slot = this.state.slot;
    if (!s || !slot) { return false; }
    var d = s.sdk.db;
    var ref = d.ref(s.database, 'rooms/' + this.state.room + '/round');
    var self = this;
    d.set(ref, Date.now() + this.state.offset).catch(function (e) {
      self.state.error = String((e && e.message) || e);
    });
    return true;
  },
  leaveRoom: function () {
    var self = this;
    var s = this._active;
    var slot = this.state.slot;
    this._desired = null;
    this._stopHeartbeat();
    if (this._retryTimer) { clearTimeout(this._retryTimer); this._retryTimer = null; }
    if (!s || !slot) { return Promise.resolve(); }
    var d = s.sdk.db;
    var room = this.state.room;
    var ref = d.ref(s.database, 'rooms/' + room + '/players/' + slot);
    var posRef = d.ref(s.database, 'rooms/' + room + '/positions/' + slot);
    var hitsRef = d.ref(s.database, 'rooms/' + room + '/hits/' + slot);
    var hpRef = d.ref(s.database, 'rooms/' + room + '/hp/' + slot);
    var charRef = d.ref(s.database, 'rooms/' + room + '/chars/' + slot);
    var voteRef = d.ref(s.database, 'rooms/' + room + '/votes/' + slot);
    var effectRef = d.ref(s.database, 'rooms/' + room + '/effects/' + slot);
    var phaseRef = d.ref(s.database, 'rooms/' + room + '/phase/' + slot);
    var whoRef = d.ref(s.database, 'rooms/' + room + '/who/' + slot);
    return d.onDisconnect(posRef).cancel().then(function () {
      return d.remove(ref);
    }).then(function () {
      return d.remove(posRef);
    }).then(function () {
      return d.remove(hitsRef).catch(function () {});
    }).then(function () {
      return d.remove(hpRef).catch(function () {});
    }).then(function () {
      return d.remove(charRef).catch(function () {});
    }).then(function () {
      return d.remove(voteRef).catch(function () {});
    }).then(function () {
      return d.remove(effectRef).catch(function () {});
    }).then(function () {
      return d.remove(phaseRef).catch(function () {});
    }).then(function () {
      return d.remove(whoRef).catch(function () {});
    }).then(function () {
      self._stopWatch();
      self.state.slot = '';
      self.state.members = [];
      self.state.positions = {};
      self.state.hits = {};
      self.state.hp = {};
      self.state.chars = {};
      self.state.votes = {};
      self.state.effects = {};
      self.state.phases = {};
      self.state.who = {};
      self.state.round = 0;
      self.state.status = 'left';
    }, function (e) { self._fail(e); });
  }
};

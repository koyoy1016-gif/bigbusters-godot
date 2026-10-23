extends RefCounted
## 画面の流れの決まりごと（画面を持たない計算だけ。テストしやすい）。
## 版109：はじめの画面（アカウントを選ぶ）→ ロビー → 戦い → 結果（勝ち負け・コイン）→（ハイライト → 結果）／
##        再戦 → 再戦の準備（START を押すまで始めない）→ 戦い／ロビー

const TITLE := "title"
const LOBBY := "lobby"
const BATTLE := "battle"
const HIGHLIGHT := "highlight"
const REWARD := "reward"
const NEXT := "next"
const FORMATION := "formation"
const ACCOUNT := "account"
const FRIENDS := "friends"
const ROOM := "room"  # 版81：へやの画面（ロビーの右端「へやを つくる」から）
const START := "start"  # 版82：はじめの画面（新しく作る・ログイン・ログインせずに遊ぶ）
const GACHA := "gacha"  # 版83：剣士を引っぱって斬るガチャ
const READY := "rematch_ready"  # 版109：再戦の準備（START を押すまで、戦いを始めない）

const TRANSITIONS := {
	"title": {"loaded": "lobby", "start": "start"},
	"start": {"enter": "lobby"},
	"lobby": {"play": "battle", "formation": "formation", "account": "account", "friends": "friends", "room": "room", "gacha": "gacha"},
	"gacha": {"back": "lobby"},
	"room": {"back": "lobby"},
	"account": {"back": "lobby"},
	"friends": {"back": "lobby"},
	"formation": {"back": "lobby"},
	"battle": {"ended": "reward"},
	"highlight": {"done": "reward"},
	"reward": {"highlight": "highlight", "rematch": "rematch_ready", "lobby": "lobby"},
	"rematch_ready": {"start": "battle", "lobby": "lobby"},
	"next": {"rematch": "rematch_ready", "lobby": "lobby"},
}


## いまの状態と出来事から、次の状態を返す。決まりにない出来事なら、いまの状態のまま
static func next_state(state: String, event: String) -> String:
	var table: Dictionary = TRANSITIONS.get(state, {})
	return str(table.get(event, state))


## 版109：はじめの画面（アカウントを選ぶ）のボタンを、押せるようにしてよいか。
## online：ログインの仕組みがある（ブラウザ）。status：ログインの準備の状態。準備中（idle・pending）は待つ。
## 長く待っても準備ができなければ（max_wait_sec）、押せるようにする（ゲストで遊べる）。ログインの仕組みがない所は、すぐ
static func start_ready(online: bool, status: String, waited_sec: float, max_wait_sec: float) -> bool:
	if not online:
		return true
	return not (status in ["idle", "pending", ""]) or waited_sec >= max_wait_sec


## 報酬のコイン（倒したら多く、全滅でも少しもらえる）
static func reward_coins(won: bool, win_coins: int, lose_coins: int) -> int:
	return win_coins if won else lose_coins


## プレイヤーランク（倒した回数から。wins_per_rank 回ごとに1上がる。最低1）
static func player_rank(wins: int, wins_per_rank: int) -> int:
	if wins_per_rank <= 0:
		return 1
	return 1 + maxi(0, wins) / wins_per_rank


## 全員で「さいせん」を選んだか。votes は {枠: "rematch" か "lobby"}、members は部屋にいる枠。
## 全員が rematch → "rematch"。1人でも lobby → "lobby"。まだ選んでいない人がいる → "wait"
static func rematch_decision(votes: Dictionary, members: Array) -> String:
	if members.is_empty():
		return "wait"
	var all_rematch := true
	for slot in members:
		var v := str(votes.get(str(slot), ""))
		if v == "lobby":
			return "lobby"
		if v != "rematch":
			all_rematch = false
	return "rematch" if all_rematch else "wait"


## 部屋の votes（{枠: {v, round}}）から、いまの戦い（round_ms）の分だけ取り出す。前の戦いの古い投票は無視する
static func current_votes(raw: Dictionary, round_ms: float) -> Dictionary:
	var out := {}
	for slot in raw:
		var item: Variant = raw[slot]
		if item is Dictionary and float(item.get("round", 0.0)) == round_ms:
			out[str(slot)] = str(item.get("v", ""))
	return out


## 部屋にいる人のうち、いちばん若い枠（p1が先）。「さいせん」の開始の時刻を書く係
static func lowest_slot(members: Array) -> String:
	var best := ""
	for slot in members:
		if best == "" or str(slot) < best:
			best = str(slot)
	return best


## 「さいせん」を選んだ人の数
static func vote_count(votes: Dictionary, members: Array) -> int:
	var n := 0
	for slot in members:
		if str(votes.get(str(slot), "")) == "rematch":
			n += 1
	return n


## 自分以外の、部屋にいる人の枠（部屋につながっていなければ空）
static func other_members(room: Dictionary) -> Array:
	if str(room.get("status", "")) != "in_room":
		return []
	var mine := str(room.get("slot", ""))
	var out: Array = []
	for m in room.get("members", []):
		if str(m) != mine:
			out.append(str(m))
	return out


## 部屋のだれかが、戦い中か結果の画面か（そのあいだは、あとから来た人は戦いに入れない）
static func others_busy(room: Dictionary) -> bool:
	var phases: Dictionary = room.get("phases", {}) if room.get("phases") is Dictionary else {}
	for m in other_members(room):
		var p: Variant = phases.get(m)
		if p is Dictionary and str(p.get("v", "")) in ["battle", "result"]:
			return true
	return false


## 部屋の全員が、「プレイ」を押したか（ひとりのときも、true）
static func all_ready(room: Dictionary) -> bool:
	var phases: Dictionary = room.get("phases", {}) if room.get("phases") is Dictionary else {}
	for m in other_members(room):
		var p: Variant = phases.get(m)
		if not (p is Dictionary and str(p.get("v", "")) in ["ready", "battle"]):
			return false
	return true


## 画面の状態から、部屋のみんなに見せる状態の名前にする
static func phase_of(state_name: String, waiting_ready: bool) -> String:
	match state_name:
		BATTLE:
			return "battle"
		HIGHLIGHT, REWARD, NEXT, READY:
			return "result"
		LOBBY, ROOM, START, GACHA:
			return "ready" if waiting_ready else "lobby"
	return "lobby"


## 部屋が、いっぱいか（max は、部屋の定員）
static func party_full(room: Dictionary, max_players: int) -> bool:
	return str(room.get("status", "")) == "in_room" and (room.get("members", []) as Array).size() >= max_players

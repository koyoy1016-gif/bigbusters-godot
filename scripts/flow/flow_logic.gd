extends RefCounted
## 画面の流れの決まりごと（画面を持たない計算だけ。テストしやすい）。
## タイトル → ロビー → 戦い → ハイライト → 報酬 → （さいせん → 戦い／つぎへ → さいせん → 戦い／ロビー）

const TITLE := "title"
const LOBBY := "lobby"
const BATTLE := "battle"
const HIGHLIGHT := "highlight"
const REWARD := "reward"
const NEXT := "next"
const FORMATION := "formation"

const TRANSITIONS := {
	"title": {"loaded": "lobby"},
	"lobby": {"play": "battle", "formation": "formation"},
	"formation": {"back": "lobby"},
	"battle": {"ended": "highlight"},
	"highlight": {"done": "reward"},
	"reward": {"rematch": "battle", "next": "next", "lobby": "lobby"},
	"next": {"rematch": "battle", "lobby": "lobby"},
}


## いまの状態と出来事から、次の状態を返す。決まりにない出来事なら、いまの状態のまま
static func next_state(state: String, event: String) -> String:
	var table: Dictionary = TRANSITIONS.get(state, {})
	return str(table.get(event, state))


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

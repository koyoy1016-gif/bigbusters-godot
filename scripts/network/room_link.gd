extends RefCounted
## 部屋の合言葉を自動で作り、しょうたいのURLにする。通信はしない（計算だけ）。
## URL を踏んだ人は、?room=合言葉 で同じ部屋に入る。踏まなかった人は、毎回べつの合言葉になる。

const RoomCode := preload("res://scripts/network/room_code.gd")


## digits 桁のランダムな合言葉（先頭が0でもよい）
static func generate_code(digits: int, rng: RandomNumberGenerator) -> String:
	var out := ""
	for i in maxi(digits, 1):
		out += str(rng.randi_range(0, 9))
	return out


## URL の ?room= が正しい合言葉ならそれ、なければ新しく作る。戻り値：{code, from_url}
static func pick(query: Variant, digits: int, rng: RandomNumberGenerator) -> Dictionary:
	if query is String and RoomCode.is_valid_code(query, digits):
		return {"code": query, "from_url": true}
	return {"code": generate_code(digits, rng), "from_url": false}


## しょうたいURL：ページの場所（? より前）に ?room=合言葉 をつける。もとに ? や # があっても、それは捨てる
static func build_url(base: String, code: String) -> String:
	var clean := base.split("#")[0].split("?")[0]
	return clean + "?room=" + code


## フレンドのURL：ページの場所に ?friend=フレンドコード をつける
static func build_friend_url(base: String, friend_code: String) -> String:
	var clean := base.split("#")[0].split("?")[0]
	return clean + "?friend=" + friend_code


## ブラウザ側の「おくる」画面を出す呼び出し（LINE・共有・コピーのボタンは、ブラウザ側の本物のボタン）
static func build_share_call(url: String, labels: Dictionary) -> String:
	return "window.bbShare.show(%s, %s)" % [JSON.stringify(url), JSON.stringify(labels)]

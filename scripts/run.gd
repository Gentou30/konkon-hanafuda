class_name Run
extends RefCounted

## 1回の挑戦（ラン）の状態。画面は持たず、game.gd とバランス確認のボットの両方から使う。

var deck := []          # 持っている札すべて
var draw_pile := []
var hand := []
var money := Rules.START_MONEY
var charms := []        # [{id, counter}]
var form_levels := {}   # 形 id → 巻物で上げたレベル
var stage := 0          # 0〜2
var bout := 0          # 0=小場 1=大場 2=親分
var score := 0
var plays_left := 0
var discards_left := 0
var bosses := []
var used_forms := []
var sort_by_kind := false
var required_count := 0  # おタマの「猫の目」：出す枚数（0なら自由）
var oracle_month := 0    # 玉藻の「幻術」：お題の月
var _need_roll := false
var rng := RandomNumberGenerator.new()
## 結果画面用
var best_hand := 0
var best_form := ""
var yaku_made := {}


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	deck = Cards.full_deck()
	var early: Array = Rules.BOSS_POOL_EARLY.duplicate()
	var first: String = early[rng.randi() % early.size()]
	var mid := []
	for b in Rules.BOSS_POOL_MID:
		if b != first:
			mid.append(b)
	bosses = [first, mid[rng.randi() % mid.size()], Rules.FINAL_BOSS]


func has_charm(id: String) -> bool:
	return Scoring.has_charm(self, id)


func boss_id() -> String:
	return bosses[stage] if bout == 2 else ""


func target() -> int:
	return Rules.TARGETS[stage][bout]


func hand_size() -> int:
	var n := Rules.HAND_SIZE
	if has_charm("rokuro"):
		n += 2
	return n


func start_round() -> void:
	score = 0
	used_forms.clear()
	plays_left = Rules.PLAYS
	discards_left = Rules.DISCARDS
	if has_charm("chochin"):
		plays_left += 1
		discards_left += 1
	if has_charm("gashadokuro"):
		plays_left -= 1
	if has_charm("yukionna"):
		discards_left += 1
	if boss_id() == "kurobo":
		discards_left = 0
	plays_left = max(plays_left, 1)
	required_count = 0
	oracle_month = 0
	draw_pile = deck.duplicate()
	_shuffle(draw_pile)
	hand.clear()
	_need_roll = true
	draw_to_full()


## 親分のお題（出す枚数・お題の月）を決め直す。札を出したあと、引き足してから
func _roll_boss_task() -> void:
	match boss_id():
		"otama":
			required_count = mini(rng.randi_range(3, 5), hand.size())
		"tamamo":
			if not hand.is_empty():
				oracle_month = hand[rng.randi() % hand.size()].month


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func draw_to_full() -> Array:
	var drawn := []
	while hand.size() < hand_size() and not draw_pile.is_empty():
		var c = draw_pile.pop_back()
		hand.append(c)
		drawn.append(c)
	sort_hand()
	if _need_roll:
		_need_roll = false
		_roll_boss_task()
	return drawn


func sort_hand() -> void:
	if sort_by_kind:
		hand.sort_custom(func(a, b): return a.kind > b.kind or (a.kind == b.kind and a.month < b.month))
	else:
		hand.sort_custom(func(a, b): return a.month < b.month or (a.month == b.month and a.kind > b.kind))


## 札を出す。結果（Scoring.evaluate の戻り値）を返す
func play(cards: Array) -> Dictionary:
	var r := Scoring.evaluate(cards, self)
	score += r.total
	plays_left -= 1
	used_forms.append(r.form)
	for y in r.yaku:
		yaku_made[y] = yaku_made.get(y, 0) + 1
	for ch in charms:
		if ch.id == "kyubi":
			ch.counter = ch.get("counter", 0) + r.yaku.size()
	_need_roll = true
	if r.total > best_hand:
		best_hand = r.total
		best_form = r.form_name
	for c in cards:
		hand.erase(c)
	return r


func discard(cards: Array) -> void:
	discards_left -= 1
	for ch in charms:
		if ch.id == "kasha":
			ch.counter = ch.get("counter", 0) + 1
	for c in cards:
		hand.erase(c)


func won() -> bool:
	return score >= target()


func lost() -> bool:
	return not won() and (plays_left <= 0 or (hand.is_empty() and draw_pile.is_empty()))


## 勝ったときの稼ぎの内訳 [[名前, 文], ...]
func payout() -> Array:
	var out := [["%sに勝った" % Rules.ROUND_NAMES[bout], Rules.ROUND_REWARD[bout]]]
	if plays_left > 0:
		out.append(["残りの出す回数 ×%d" % plays_left, plays_left])
	if has_charm("binbo"):
		if money >= 2:
			out.append(["貧乏神：所持金が半分", -(money / 2)])
	else:
		var cap := Rules.INTEREST_MAX + (3 if has_charm("zashiki") else 0)
		var interest: int = min(money / Rules.INTEREST_STEP, cap)
		if interest > 0:
			out.append(["利子（5文ごとに1文）", interest])
	if has_charm("zashiki"):
		out.append(["座敷わらし", 4])
	return out


## 次の場へ。全部勝ったら true
func advance() -> bool:
	bout += 1
	if bout >= 3:
		bout = 0
		stage += 1
	return stage >= 3


func charm_slots_free() -> int:
	return Rules.MAX_CHARMS - charms.size()


## 店の品ぞろえ。[{type: "charm"/"scroll"/"talisman", id, price}]
func shop_offers() -> Array:
	var out := []
	var pool := []
	for id in Rules.CHARMS.keys():
		if not has_charm(id):
			pool.append(id)
	_shuffle(pool)
	for i in min(2, pool.size()):
		out.append({"type": "charm", "id": pool[i], "price": Rules.CHARMS[pool[i]][1]})
	# 巻物は低い形ほど出やすい
	var forms := ["pair", "pair", "two_pair", "three", "three", "straight", "flush", "full", "four"]
	var f: String = forms[rng.randi() % forms.size()]
	out.append({"type": "scroll", "id": f, "price": 3})
	var tl: Array = Rules.TALISMANS.keys()
	_shuffle(tl)
	for i in 2:
		out.append({"type": "talisman", "id": tl[i], "price": Rules.TALISMANS[tl[i]][1]})
	return out


func add_charm(id: String) -> void:
	charms.append({"id": id, "counter": 0})
	if id == "tsukumo":
		# 付喪神：来たときに札2枚を金箔にする
		var plain := deck.filter(func(c): return not c.gold)
		_shuffle(plain)
		for c in plain.slice(0, 2):
			c.gold = true


func sell_price(id: String) -> int:
	return max(1, Rules.CHARMS[id][1] / 2)


## お札の対象に選べる札（山札から無作為に6枚）
func talisman_choices() -> Array:
	var a := deck.duplicate()
	_shuffle(a)
	return a.slice(0, 6)


func apply_talisman(id: String, c: Dictionary) -> void:
	match id:
		"gold": c.gold = true
		"ink": c.bonus += 20
		"copy": deck.append(Cards.copy(c))
		"purge": deck.erase(c)
		"kind_up": c.kind = min(c.kind + 1, Cards.KIND_HIKARI)

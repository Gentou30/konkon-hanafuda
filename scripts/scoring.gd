class_name Scoring

## 出した札の点数を計算する。点 = チップ合計 × 倍率。
## 演出のため、何がいくつ足されたかを steps に順番に残す。
##   step: { "src": "form"/"card"/"yaku"/"charm"/"boss", "index": 札や式神の位置, "text": 表示,
##           "chips": 足すチップ, "mult": 足す倍率, "xmult": 掛ける倍率(1なら無し) }


## 月の組み合わせから形を決める。wild = どの月にもなれる札の数
static func detect_form(cards: Array, wild_ok: bool) -> String:
	var n := cards.size()
	var counts := {}
	var wild := 0
	for c in cards:
		if wild_ok and c.month == 11:
			wild += 1
		else:
			counts[c.month] = counts.get(c.month, 0) + 1
	var vals: Array = counts.values()
	vals.sort()
	vals.reverse()
	if vals.is_empty():
		vals = [0]
	vals[0] += wild  # どの月にもなれる札は一番多い月に合わせるのが常に得
	var flush := n == 5
	for c in cards:
		if c.kind != cards[0].kind:
			flush = false
	var straight := n == 5 and _is_straight(counts, wild)
	if vals[0] >= 5:
		return "five"
	if straight and flush:
		return "straight_flush"
	if vals[0] == 4:
		return "four"
	if vals[0] == 3 and vals.size() > 1 and vals[1] >= 2:
		return "full"
	if flush:
		return "flush"
	if straight:
		return "straight"
	if vals[0] == 3:
		return "three"
	if vals[0] == 2 and vals.size() > 1 and vals[1] == 2:
		return "two_pair"
	if vals[0] == 2:
		return "pair"
	return "high"


## 5枚の月が続いているか（12月→1月もつながる）。wild の札は抜けた月を埋める
static func _is_straight(counts: Dictionary, wild: int) -> bool:
	for v in counts.values():
		if v > 1:
			return false
	for start in range(1, 13):
		var ok := true
		for m in counts.keys():
			if (m - start + 12) % 12 >= 5:
				ok = false
				break
		if ok and counts.size() + wild == 5:
			return true
	return false


static func detect_yaku(cards: Array) -> Array:
	var tags := {}
	var hikari := 0
	var ame := false
	for c in cards:
		for t in c.tags:
			tags[t] = tags.get(t, 0) + 1
		if c.kind == Cards.KIND_HIKARI:
			hikari += 1
			if c.month == 11:
				ame = true
	var out := []
	if hikari >= 5:
		out.append("goko")
	elif hikari == 4:
		out.append("ameshiko" if ame else "shiko")
	elif hikari == 3 and not ame:
		out.append("sanko")
	if tags.has("ino") and tags.has("shika") and tags.has("cho"):
		out.append("inoshikacho")
	if tags.get("aka", 0) >= 3:
		out.append("akatan")
	if tags.get("ao", 0) >= 3:
		out.append("aotan")
	if tags.has("sake") and tags.has("maku"):
		out.append("hanami")
	if tags.has("sake") and tags.has("tsuki"):
		out.append("tsukimi")
	return out


## 札1枚が使える役の名前（ヒント用）
static func card_yaku(c: Dictionary) -> Array:
	var out := []
	if c.kind == Cards.KIND_HIKARI:
		out.append("光の役（三光・四光・五光）")
	for t in c.tags:
		match t:
			"ino", "shika", "cho": out.append("猪鹿蝶")
			"aka": out.append("赤短")
			"ao": out.append("青短")
			"maku": out.append("花見で一杯")
			"tsuki": out.append("月見で一杯")
			"sake": out.append("花見で一杯・月見で一杯")
	return out


## 役の近道：手札の中で、あと何枚で役になるか。[[名前, 持っている数, 要る数, 足りない札の名前], ...]
static func yaku_progress(cards: Array) -> Array:
	var has := {}
	var hikari := 0
	for c in cards:
		for t in c.tags:
			has[t] = true
		if c.kind == Cards.KIND_HIKARI:
			hikari += 1
	var out := []
	var groups := [
		["猪鹿蝶", ["ino", "shika", "cho"], {"ino": "7月の猪", "shika": "10月の鹿", "cho": "6月の蝶"}],
		["赤短", [], {}], ["青短", [], {}],
		["花見で一杯", ["maku", "sake"], {"maku": "3月の幕", "sake": "9月の盃"}],
		["月見で一杯", ["tsuki", "sake"], {"tsuki": "8月の月", "sake": "9月の盃"}],
	]
	for g in groups:
		if g[0] == "赤短" or g[0] == "青短":
			var tag := "aka" if g[0] == "赤短" else "ao"
			var n := 0
			for c in cards:
				if c.tags.has(tag):
					n += 1
			if n > 0:
				var miss := "1〜3月の赤短" if tag == "aka" else "6・9・10月の青短"
				out.append([g[0], mini(n, 3), 3, miss])
			continue
		var got := 0
		var miss := []
		for t in g[1]:
			if has.has(t):
				got += 1
			else:
				miss.append(g[2][t])
		if got > 0:
			out.append([g[0], got, g[1].size(), "・".join(miss)])
	if hikari > 0:
		var need := 3 if hikari < 3 else (4 if hikari < 4 else 5)
		out.append(["光の役", hikari, need, "光の札（1・3・8・11・12月）"])
	return out


static func yaku_def(id: String) -> Array:
	for y in Rules.YAKU:
		if y[0] == id:
			return y
	return []


static func has_charm(run, id: String) -> bool:
	for ch in run.charms:
		if ch.id == id:
			return true
	return false


## run: Run（式神・形のレベル・残り回数・親分などを読む）。中身は書き換えない
static func evaluate(cards: Array, run) -> Dictionary:
	var steps := []
	var form := detect_form(cards, has_charm(run, "karakasa"))
	var fd := Rules.form_def(form)
	var lv: int = run.form_levels.get(form, 0)
	var chips: float = fd[2] + fd[4] * lv
	var mult: float = fd[3] + fd[5] * lv
	steps.append({"src": "form", "index": -1, "text": fd[1] + (" Lv%d" % (lv + 1) if lv > 0 else ""),
		"chips": chips, "mult": mult, "xmult": 1.0})
	var boss: String = run.boss_id()

	# 札1枚ずつ
	for i in cards.size():
		var c: Dictionary = cards[i]
		var cc := float(Cards.chips(c))
		var cm := 0.0
		var cx := 1.0
		if boss == "ponkichi" and c.kind == Cards.KIND_KASU:
			cc = float(c.bonus)
		if c.gold:
			cm += 3
		for ch in run.charms:
			match ch.id:
				"kappa":
					if c.kind == Cards.KIND_KASU: cc += 12
				"ittan":
					if c.kind == Cards.KIND_TAN: cm += 2
				"onibi":
					if c.kind == Cards.KIND_HIKARI: cm += 4
				"tsukumo":
					if c.gold: cx *= 1.5
				"karakasa":
					if c.month == 11: cm += 3
				"shuten":
					if c.tags.has("sake"): cm += 9
					elif c.kind == Cards.KIND_TANE: cm += 3
		steps.append({"src": "card", "index": i, "text": "", "chips": cc, "mult": cm, "xmult": cx})

	# 役
	var yaku := detect_yaku(cards)
	for y in yaku:
		var yd := yaku_def(y)
		steps.append({"src": "yaku", "index": -1, "text": yd[1], "chips": float(yd[2]), "mult": float(yd[3]), "xmult": 1.0})

	# 式神（並び順に効く）
	var month_counts := {}
	for c in cards:
		month_counts[c.month] = month_counts.get(c.month, 0) + 1
	var has_match := form in ["pair", "two_pair", "three", "full", "four", "five"]
	var kind_counts := {}
	for c in cards:
		kind_counts[c.kind] = kind_counts.get(c.kind, 0) + 1
	for i in run.charms.size():
		var ch: Dictionary = run.charms[i]
		var s := {"src": "charm", "index": i, "text": "", "chips": 0.0, "mult": 0.0, "xmult": 1.0}
		match ch.id:
			"maneki": s.mult = 4
			"haratsuzumi": if has_match: s.mult = 6
			"tengu": if longest_run(cards) >= 3: s.xmult = 2.0
			"noppera": if cards.size() <= 3: s.xmult = 3.0
			"kasha": s.chips = 6 * ch.get("counter", 0)
			"kyubi": s.xmult = kyubi_mult(ch.get("counter", 0) + yaku.size())
			"nekomata": if kind_counts.values().max() >= 3: s.xmult = 2.0
			"gashadokuro": s.xmult = 3.0
			"binbo": s.mult = 8
			"yukionna": s.mult = 2 * run.discards_left
			"umibozu": s.chips = 30 * run.discards_left
			"hitotsume":
				if cards.size() == 1:
					s.chips = 60
					s.xmult = 3.0
			"inugami": s.mult = floor(run.money / 5.0)
			"baku": if run.plays_left <= 1: s.xmult = 4.0
		if s.chips != 0 or s.mult != 0 or s.xmult != 1.0:
			steps.append(s)

	# 玉藻の幻術：お題の月を含めれば倍率×2、含めなければ点が半分
	var halved := false
	if boss == "tamamo":
		var hit := false
		for c in cards:
			if c.month == run.oracle_month:
				hit = true
		if hit:
			steps.append({"src": "boss", "index": -1, "text": "お題の月！", "chips": 0.0, "mult": 0.0, "xmult": 2.0})
		else:
			halved = true

	# 合計（足し算は順に、掛け算はその時点の倍率に掛ける）
	var tc := 0.0
	var tm := 0.0
	for s in steps:
		tc += s.chips
		tm += s.mult
		tm *= s.xmult
	var total := tc * tm
	if boss == "kawataro" and run.used_forms.has(form):
		halved = true
	if halved:
		total /= 2.0
	return {"form": form, "form_name": fd[1], "yaku": yaku, "steps": steps,
		"chips": tc, "mult": tm, "total": int(round(total)), "halved": halved}


static func kyubi_mult(n: int) -> float:
	return 1.0 + 0.5 * n


## 月が続いている一番長い並び（12月→1月もつながる）
static func longest_run(cards: Array) -> int:
	var has := {}
	for c in cards:
		has[c.month] = true
	if has.size() >= 12:
		return 12
	var best := 0
	for m in has:
		if has.has((m + 10) % 12 + 1):
			continue  # 並びの先頭からだけ数える
		var n := 1
		while has.has((m - 1 + n) % 12 + 1):
			n += 1
		best = maxi(best, n)
	return best


## ボット・おすすめ用：手札から一番点の高い出し方を探す（最大5枚。おタマの「猫の目」なら決まった枚数）
static func best_play(hand: Array, run) -> Dictionary:
	var best := {"total": -1, "cards": []}
	var n := hand.size()
	for mask in range(1, 1 << n):
		var cnt := 0
		var m := mask
		while m:
			cnt += m & 1
			m >>= 1
		if cnt > Rules.MAX_SELECT or (run.required_count > 0 and cnt != run.required_count):
			continue
		var pick := []
		for i in n:
			if mask & (1 << i):
				pick.append(hand[i])
		var r := evaluate(pick, run)
		if r.total > best.total:
			best = {"total": r.total, "cards": pick, "form": r.form}
	return best

extends SceneTree

## バランス確認：ボットに最後まで遊ばせて、どこまで進めるかを数える。
## godot --headless -s res://tools/balance_sim.gd -- 回数 [detail]
## ボットは「一番点の高い出し方」を選び、弱いときは使わない札を捨てる。店では式神を優先して買う。

const BUY_ORDER := ["maneki", "haratsuzumi", "kappa", "inugami", "onibi", "ittan", "chochin", "kyubi",
	"kasha", "rokuro", "shuten", "baku", "nekomata", "umibozu", "zashiki", "gashadokuro", "binbo"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 50
	var detail := args.size() > 1
	for plan in ["賢い", "店に寄らない"]:
		var reach := {}
		var cleared := 0
		var t0 := Time.get_ticks_msec()
		for i in n:
			var res := _play_run(i, plan == "賢い", detail and i < 2)
			reach[res] = reach.get(res, 0) + 1
			if res == 9:
				cleared += 1
		var keys := reach.keys()
		keys.sort()
		var s := PackedStringArray()
		for k in keys:
			s.append("%d場:%d" % [k, reach[k]])
		print("%s  クリア %d/%d  到達(勝った場数) %s  (%.1fs)" % [plan, cleared, n, " ".join(s), (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## 勝った場の数を返す（9なら全クリア）
func _play_run(seed_value: int, shop: bool, log: bool) -> int:
	var run := Run.new(seed_value)
	var wins := 0
	while true:
		run.start_round()
		while not run.won() and not run.lost():
			var best := Scoring.best_play(run.hand, run)
			var weak: bool = best.total * run.plays_left < (run.target() - run.score)
			if weak and run.discards_left > 0 and not run.draw_pile.is_empty():
				var throw := []
				for c in run.hand:
					if not best.cards.has(c) and throw.size() < Rules.MAX_SELECT:
						throw.append(c)
				if throw.is_empty():
					throw = best.cards.slice(0, 2)
				run.discard(throw)
				run.draw_to_full()
				continue
			run.play(best.cards)
			run.draw_to_full()
		if log:
			print("  宿%d %s 目標%d → %d  手札%d 式神%s" % [run.stage + 1, Rules.ROUND_NAMES[run.bout], run.target(), run.score, run.hand_size(), run.charms.map(func(c): return c.id)])
		if not run.won():
			return wins
		wins += 1
		for p in run.payout():
			run.money += p[1]
		if run.advance():
			return wins
		if shop:
			_shop(run)
	return wins


func _shop(run: Run) -> void:
	var offers := run.shop_offers()
	for o in offers:
		if o.type == "charm" and run.charm_slots_free() > 0 and run.money >= o.price and BUY_ORDER.has(o.id):
			run.money -= o.price
			run.add_charm(o.id)
	for o in offers:
		if o.type == "scroll" and run.money >= o.price + 3 and o.id in ["pair", "two_pair", "three"]:
			run.money -= o.price
			run.form_levels[o.id] = run.form_levels.get(o.id, 0) + 1
		if o.type == "talisman" and o.id == "gold" and run.money >= o.price + 4:
			run.money -= o.price
			var ch := run.talisman_choices()
			ch.sort_custom(func(a, b): return a.kind > b.kind)
			run.apply_talisman("gold", ch[0])

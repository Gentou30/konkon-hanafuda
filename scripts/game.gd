extends Control

## ゲーム全体の進行と画面。
## TITLE → (STORY / HOWTO) → INTRO(場の前) → PLAY → PAYOUT → SHOP → INTRO … → CLEAR / GAMEOVER
## 画面は状態ごとに _screen の下に組み立て、向きが変わったら組み直す（PLAY は配置だけ直す）。

enum { TITLE, STORY, HOWTO, INTRO, PLAY, PAYOUT, SHOP, GAMEOVER, CLEAR }

const SPEAKERS := {"K": "コン", "G": "ギン"}

var state := TITLE
var run: Run
var busy := false            # 演出中は操作を受けない
var _screen: Control
var _bg: TextureRect
var _dim: ColorRect
var _ambient: Ambient        # 背景の上を舞う木の葉・花びら・狐火
var _fx: Control             # 浮かぶ文字などを載せる一番上の層
var _talk_layer: Control
var _talk_lines := []
var _talk_i := 0
var _talk_done: Callable
var _boss_for_talk := ""
var _talk_seen := ""        # 最後に会話を出した画面（組み直しで繰り返さない）
var _overlay: Control        # 役一覧・お札の札選び
var _overlay_modal := false  # お札の札選びは選ぶまで閉じられない（払ったお金が無駄になるため）
var _talk_label: Label
var _talk_typing: Tween
var _talk_pics := {}         # 会話の立ち絵（話者 → TextureRect）。話者が変わったら動かす

# PLAY 画面の部品
var _ui := {}
var _views := []             # 手札の CardView
var _played := []            # 場に出した CardView
var _charm_views := []
var _say_tween: Tween
var _mini := {}              # ミニキャラ（kon / gin / boss）

# 店
var _offers := []
var _reroll_cost := Rules.REROLL_COST
var _shop_msg := ""
var _payout := []


func _ready() -> void:
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_ambient = Ambient.new()
	add_child(_ambient)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 札（z_index 50〜）より上に出す
	_fx.z_index = 100
	add_child(_fx)
	_talk_layer = Control.new()
	_talk_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_talk_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_talk_layer.z_index = 200
	add_child(_talk_layer)
	Screen.layout_changed.connect(_on_layout)
	_set_state(TITLE)


# ───────────────────────── 共通 ─────────────────────────

static func tex(name: String) -> Texture2D:
	for ext in ["png", "jpg"]:
		var p := "res://assets/images/%s.%s" % [name, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _set_state(s: int) -> void:
	state = s
	_close_overlay()
	_build()


func _on_layout() -> void:
	if state == PLAY and not _ui.is_empty():
		_layout_play()
	else:
		_build()
	if not _talk_lines.is_empty():
		_show_talk_line()


func _clear_screen() -> void:
	for c in _screen.get_children():
		c.queue_free()
	_ui.clear()
	_views.clear()
	_played.clear()
	_charm_views.clear()


func _build() -> void:
	_clear_screen()
	match state:
		TITLE: _build_title()
		STORY: _build_text_page("あらすじ", Scenario.STORY, false)
		HOWTO: _build_text_page("遊び方", Scenario.HOW_TO, true)
		INTRO: _build_intro()
		PLAY: _build_play()
		PAYOUT: _build_payout()
		SHOP: _build_shop()
		GAMEOVER: _build_end(false)
		CLEAR: _build_end(true)


func _set_bg(name: String, dim: float) -> void:
	if _bg.texture != tex(name):
		_bg.texture = tex(name)
		# ゆっくり寄っていく（止まった絵に見せない）
		_bg.pivot_offset = _view() / 2
		_bg.scale = Vector2.ONE
		var t := create_tween().set_loops()
		t.tween_property(_bg, "scale", Vector2(1.06, 1.06), 18.0).set_trans(Tween.TRANS_SINE)
		t.tween_property(_bg, "scale", Vector2.ONE, 18.0).set_trans(Tween.TRANS_SINE)
	_dim.color = Color(0.03, 0.01, 0.04, dim)
	var kind: String = {"bg_stage1": "leaf", "bg_stage2": "petal", "bg_stage3": "wisp", "title": "petal",
		"bg_shop": "wisp"}.get(name, "")
	_set_ambient(kind)


## 宿場ごとの背景
func _stage_bg() -> String:
	return "bg_stage%d" % (run.stage + 1)


func _stage_bgm() -> String:
	var boss := run.boss_id()
	if boss == Rules.FINAL_BOSS:
		return "final"
	if boss != "":
		return "boss"
	return "den%d" % (run.stage + 1)


## 背景の上を舞うもの。leaf 紅葉 / petal 花びら / wisp 狐火
func _set_ambient(kind: String) -> void:
	if kind != _ambient.kind:
		_ambient.setup(kind, _view())
	else:
		_ambient.resize(_view())


func _view() -> Vector2:
	return size


## skin: 漆の札の色（red / blue / gray / purple / green）。"flat" は小さいボタン用の平たい見た目
func _button(text: String, cb: Callable, font: int = 30, skin: String = "red") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font)
	if skin == "flat":
		UiStyle.button_styles(b, Color(0.3, 0.3, 0.4))
	else:
		UiStyle.tex_button(b, skin)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		if busy or not _talk_lines.is_empty():
			return
		Audio.sfx("click")
		cb.call())
	# 触れると少し浮き上がる
	b.resized.connect(func(): b.pivot_offset = b.size / 2)
	b.mouse_entered.connect(func():
		if not b.disabled:
			create_tween().tween_property(b, "scale", Vector2(1.04, 1.04), 0.08))
	b.mouse_exited.connect(func(): create_tween().tween_property(b, "scale", Vector2.ONE, 0.08))
	_screen.add_child(b)
	return b


## 大きい枠は漆と金具のパネル
func _tex_panel(rect: Rect2, parent: Control = null, alpha: float = 0.95, small: bool = false) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UiStyle.tex_panel(alpha, small))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _screen).add_child(p)
	_place(p, rect)
	return p


func _panel(rect: Rect2, edge: Color = UiStyle.GOLD, bg: Color = UiStyle.PANEL_BG, parent: Control = null) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UiStyle.panel(edge, bg))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _screen).add_child(p)
	_place(p, rect)
	return p


func _text(text: String, rect: Rect2, fsize: int, color: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, parent: Control = null) -> Label:
	var l := UiStyle.label(text, fsize, color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _screen).add_child(l)
	_place(l, rect)
	return l


func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


func _picture(name: String, rect: Rect2, parent: Control = null) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _screen).add_child(t)
	_place(t, rect)
	return t


func _input(event: InputEvent) -> void:
	if not _talk_lines.is_empty():
		var adv: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER])
		if adv:
			get_viewport().set_input_as_handled()
			_advance_talk()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if k == KEY_M:
		Audio.toggle_mute()
		if state == TITLE:
			_build()
		return
	if _overlay:
		if k == KEY_ESCAPE and not _overlay_modal:
			_close_overlay()
		return
	if OS.is_debug_build():
		_debug_key(k)
	match state:
		TITLE:
			if k in [KEY_SPACE, KEY_ENTER]: _new_run()
		STORY, HOWTO:
			if k in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]: _set_state(TITLE)
		INTRO:
			if k in [KEY_SPACE, KEY_ENTER]: _start_bout()
		PLAY:
			if busy:
				return
			if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < _views.size():
				_toggle(_views[k - KEY_1])
			elif k == KEY_ENTER or k == KEY_SPACE:
				_play()
			elif k == KEY_X or k == KEY_BACKSPACE:
				_discard()
		PAYOUT:
			if k in [KEY_SPACE, KEY_ENTER]: _after_payout()
		SHOP:
			pass
		GAMEOVER, CLEAR:
			if k in [KEY_SPACE, KEY_ENTER]: _set_state(TITLE)


func _debug_key(k: int) -> void:
	match k:
		KEY_F1:
			if run: run.money += 20
			if state == SHOP: _build()
		KEY_F2:
			if state == PLAY and not busy:
				run.score = run.target()
				_round_won()
		KEY_F3:
			if state == PLAY: _game_over()
		KEY_F4:
			if run:
				run.stage = 2
				run.bout = 2
				_set_state(INTRO)
		KEY_F5:
			# 親分の場の前で、親分を入れ替える（見た目の確認用）
			if run and state == INTRO and run.bout == 2:
				var ids := Rules.BOSSES.keys()
				run.bosses[run.stage] = ids[(ids.find(run.bosses[run.stage]) + 1) % ids.size()]
				_talk_seen = ""
				_talk_lines = []
				_set_state(INTRO)


# ───────────────────────── 会話 ─────────────────────────

## lines: [[話者, セリフ], ...]。終わったら done を呼ぶ
func _talk(lines: Array, done: Callable = Callable(), boss: String = "") -> void:
	var key := "%d_%d_%d" % [state, run.stage if run else -1, run.bout if run else -1]
	if key == _talk_seen:
		return
	_talk_seen = key
	_talk_lines = lines
	_talk_i = 0
	_talk_done = done
	_boss_for_talk = boss
	_show_talk_line()


func _show_talk_line() -> void:
	for c in _talk_layer.get_children():
		c.queue_free()
	_talk_pics.clear()
	if _talk_lines.is_empty():
		return
	var v := _view()
	var line: Array = _talk_lines[_talk_i]
	var who: String = line[0]
	var prev: String = _talk_lines[_talk_i - 1][0] if _talk_i > 0 else ""
	# 画面全体で入力を受けて次へ進める
	var catcher := ColorRect.new()
	catcher.color = Color(0, 0, 0, 0.3)
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_talk_layer.add_child(catcher)
	var h := 200.0 if not Screen.portrait else 250.0
	var box := Rect2(16, v.y - h - 16, v.x - 32, h)
	var pw := 250.0 if not Screen.portrait else 230.0
	# 立ち絵：左にコン、右に親分（親分がいない会話ではギン）。親分の会話でギンが話すときは左に入れ替わる
	var right := "B" if _boss_for_talk != "" else "G"
	var left := "K"
	if right == "B":
		for i in _talk_i + 1:
			if _talk_lines[i][0] != "B":
				left = _talk_lines[i][0]
	for side in [left, right]:
		var is_left: bool = side == left
		var pic := _talk_pic_name(side, line if side == who else [])
		var pr := Rect2(box.position.x + (10.0 if is_left else box.size.x - pw - 10), box.position.y - pw * 1.05, pw, pw * 1.15)
		var t := _picture(pic, pr, _talk_layer)
		t.flip_h = not is_left and side != "B"
		t.pivot_offset = Vector2(pw / 2, pw * 1.15)
		var speaking: bool = side == who
		t.modulate = Color.WHITE if speaking else Color(0.45, 0.42, 0.5)
		if speaking:
			# 話し始めにぴょんと跳ねる。「！」のある台詞は大きく
			var big := (line[1] as String).contains("！")
			var tw := create_tween()
			tw.tween_property(t, "position:y", pr.position.y - (26.0 if big else 10.0), 0.09).set_ease(Tween.EASE_OUT)
			tw.tween_property(t, "position:y", pr.position.y, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			if side != prev and _talk_i > 0:
				t.scale = Vector2(0.92, 0.92)
				create_tween().tween_property(t, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _talk_i == 0:
			# 最初の1行は横から入ってくる
			var from := pr.position.x + (-120.0 if is_left else 120.0)
			t.position.x = from
			t.modulate.a = 0.0
			var tw2 := create_tween().set_parallel()
			tw2.tween_property(t, "position:x", pr.position.x, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw2.tween_property(t, "modulate:a", 1.0, 0.2)
		_talk_pics[side] = t
	var p := _tex_panel(box, _talk_layer, 0.97)
	var nc := UiStyle.GOLD if who == "K" else (Color(0.75, 0.85, 1.0) if who == "G" else UiStyle.MULT)
	var name := _talk_name(who)
	# 名札
	var tag := _panel(Rect2(box.position + Vector2(28 if who != "B" else box.size.x - 300, -26), Vector2(270, 48)),
		nc, Color(0.1, 0.05, 0.06, 0.97), _talk_layer)
	tag.add_theme_stylebox_override("panel", UiStyle.panel(nc, Color(0.1, 0.05, 0.06, 0.97), 4, 22))
	_text(name, Rect2(tag.position + Vector2(0, 4), tag.size - Vector2(0, 8)), 26, nc, HORIZONTAL_ALIGNMENT_CENTER, _talk_layer)
	var fs := 30
	_talk_label = _text(line[1], Rect2(box.position + Vector2(32, 36), box.size - Vector2(64, 60)), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _talk_layer)
	# 1文字ずつ出す
	_talk_label.visible_ratio = 0.0
	if _talk_typing:
		_talk_typing.kill()
	_talk_typing = create_tween()
	_talk_typing.tween_property(_talk_label, "visible_ratio", 1.0, 0.025 * (line[1] as String).length())
	var hint := _text("▼", Rect2(box.end - Vector2(60, 50), Vector2(40, 36)), 24, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, _talk_layer)
	var ht := create_tween().set_loops()
	ht.tween_property(hint, "position:y", hint.position.y + 6, 0.4).set_trans(Tween.TRANS_SINE)
	ht.tween_property(hint, "position:y", hint.position.y, 0.4).set_trans(Tween.TRANS_SINE)
	ht.bind_node(hint)


func _talk_name(who: String) -> String:
	match who:
		"K": return "コン"
		"G": return "ギン"
		"B": return Rules.BOSSES[_boss_for_talk][0] if _boss_for_talk != "" else "親分"
	return ""


## 話者の立ち絵の名前。line が渡されればコンの表情を反映する
func _talk_pic_name(who: String, line: Array) -> String:
	match who:
		"K": return "kon_" + (line[2] if line.size() > 2 else "normal")
		"G": return "gin"
		"B": return "boss_" + _boss_for_talk
	return ""


func _advance_talk() -> void:
	# 文字を出している途中なら、まず全部出す
	if _talk_label and is_instance_valid(_talk_label) and _talk_label.visible_ratio < 1.0:
		if _talk_typing:
			_talk_typing.kill()
		_talk_label.visible_ratio = 1.0
		return
	Audio.sfx("click", -10.0)
	_talk_i += 1
	if _talk_i >= _talk_lines.size():
		_talk_lines = []
		for c in _talk_layer.get_children():
			c.queue_free()
		if _talk_done.is_valid():
			_talk_done.call()
		return
	_show_talk_line()


# ───────────────────────── タイトル ─────────────────────────

func _build_title() -> void:
	_set_bg("title", 0.05)
	Audio.bgm("title")
	var v := _view()
	var p := Screen.portrait
	var lx := 48.0 if not p else 40.0
	var top := 36.0 if not p else 70.0
	var w := 620.0 if not p else v.x - 80
	# 左（縦画面では上）をなだらかに暗くしてロゴを読みやすくする
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.01, 0.06, 0.85))
	g.set_color(1, Color(0.03, 0.01, 0.06, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0) if not p else Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if not p else Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(shade)
	_place(shade, Rect2(0, 0, 820, v.y) if not p else Rect2(0, 0, v.x, 720))
	# 後ろで揺れる花札
	var fan := Control.new()
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(fan)
	fan.position = Vector2(lx + 470, top + 150) if not p else Vector2(v.x - 110, top + 480)
	for i in 3:
		var cv := CardView.new(Cards.make(Cards.DEFS[[0, 8, 28][i]], [0, 8, 28][i]))
		cv.interactive = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.size = Vector2(110, 170)
		cv.position = Vector2(-55, -170)
		cv.pivot_offset = Vector2(55, 200)
		cv.rotation = deg_to_rad(-24 + i * 24)
		cv.modulate.a = 0.0
		fan.add_child(cv)
		var t := create_tween().bind_node(cv)
		t.tween_interval(0.9 + i * 0.12)
		t.tween_property(cv, "modulate:a", 0.95, 0.3)
		var sway := create_tween().set_loops()
		sway.tween_property(cv, "rotation", cv.rotation + 0.05, 1.6 + i * 0.3).set_trans(Tween.TRANS_SINE)
		sway.tween_property(cv, "rotation", cv.rotation - 0.03, 1.6 + i * 0.3).set_trans(Tween.TRANS_SINE)
		sway.bind_node(cv)
	# ロゴ前の帯
	var rib := _panel(Rect2(lx, top, 380, 44), UiStyle.GOLD, Color(0.6, 0.1, 0.08, 0.95))
	rib.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GOLD, Color(0.6, 0.1, 0.08, 0.95), 4, 22))
	_text("妖怪賭場の花札ローグライク", Rect2(lx, top + 5, 380, 36), 24, Color(1, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	# ロゴ：1文字ずつ落ちてきて弾む
	var logo := Control.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(logo)
	logo.position = Vector2(lx, top + 56)
	var lines := ["こんこん", "花札道中"]
	var k := 0
	for row in 2:
		for i in 4:
			var ch := UiStyle.label(lines[row][i], 104, Color(1, 0.86, 0.4) if row == 1 else Color.WHITE, 20)
			ch.add_theme_color_override("font_outline_color", Color(0.45, 0.06, 0.04))
			ch.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
			ch.add_theme_constant_override("shadow_offset_x", 6)
			ch.add_theme_constant_override("shadow_offset_y", 8)
			ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			logo.add_child(ch)
			var to := Vector2(i * 108 + row * 56, row * 122)
			ch.size = Vector2(110, 130)
			ch.position = to - Vector2(0, 300)
			ch.modulate.a = 0.0
			var t := create_tween().bind_node(ch)
			t.tween_interval(0.08 * k)
			t.tween_property(ch, "modulate:a", 1.0, 0.05)
			t.parallel().tween_property(ch, "position", to, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			# ゆらゆら（文字ごとに少しずらす）
			t.tween_callback(func():
				var f := create_tween().set_loops()
				f.tween_property(ch, "position:y", to.y - 6, 1.2 + 0.1 * (k % 3)).set_trans(Tween.TRANS_SINE)
				f.tween_property(ch, "position:y", to.y, 1.2 + 0.1 * (k % 3)).set_trans(Tween.TRANS_SINE)
				f.bind_node(ch))
			k += 1
	var sub := _text("〜小狐と、あぶらあげ奪還の一夜〜", Rect2(lx, top + 316, w, 40), 28, Color(1, 0.92, 0.8))
	sub.modulate.a = 0.0
	create_tween().bind_node(sub).tween_property(sub, "modulate:a", 1.0, 0.6).set_delay(0.9)
	# ボタン（左から順にすべり込む）
	var by := top + 380
	var bw := 340.0
	var btns := [["はじめる", _new_run, "red"], ["あらすじ・登場人物", func(): _set_state(STORY), "purple"],
		["遊び方・役の一覧", func(): _set_state(HOWTO), "blue"],
		["音  " + ("OFF" if Audio.muted else "ON") + "  [M]", func(): Audio.toggle_mute(); _build(), "gray"]]
	if p:
		by = v.y - 470
		bw = v.x - 300
		lx = 40
	for i in btns.size():
		var b := _button(btns[i][0], btns[i][1], 32 if i == 0 else 24, btns[i][2])
		var r := Rect2(lx, by + i * 78, bw, 68 if i == 0 else 60)
		_place(b, r)
		b.position.x = -bw - 40
		create_tween().bind_node(b).tween_property(b, "position:x", r.position.x, 0.35).set_delay(1.0 + i * 0.08) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# コンとギン
	var mk := MiniChar.new("kon")
	var mg := MiniChar.new("gin", true)
	_screen.add_child(mk)
	_screen.add_child(mg)
	if p:
		_place(mk, Rect2(v.x - 250, v.y - 330, 170, 170))
		_place(mg, Rect2(v.x - 150, v.y - 300, 140, 140))
	else:
		_place(mk, Rect2(lx + bw + 20, by + 120, 150, 150))
		_place(mg, Rect2(lx + bw + 140, by + 140, 130, 130))
	var hop := create_tween().set_loops()
	hop.tween_interval(2.6)
	hop.tween_callback(func(): mk.act(MiniChar.HAPPY, 0.8, true))
	hop.tween_interval(2.2)
	hop.tween_callback(func(): mk.act(MiniChar.SPECIAL, 1.4))
	hop.tween_interval(0.5)
	hop.tween_callback(func(): mg.act(MiniChar.SPECIAL, 1.0, true))
	hop.bind_node(mk)
	var ver := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	_text("build " + (ver if ver != "" else "dev") + "   画像は生成AIで作成しています", Rect2(16, v.y - 34, v.x - 32, 30), 16, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)


func _build_text_page(title: String, body: String, with_table: bool) -> void:
	_set_bg("bg_stage1", 0.6)
	var v := _view()
	_text(title, Rect2(0, 24, v.x, 60), 44, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var area := Rect2(40, 100, v.x - 80, v.y - 200)
	_tex_panel(area)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_screen.add_child(sc)
	_place(sc, area.grow(-16))
	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = area.size.x - 48
	vb.add_theme_constant_override("separation", 12)
	sc.add_child(vb)
	var l := UiStyle.label(body, 26 if not Screen.portrait else 24)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	if with_table:
		vb.add_child(UiStyle.label("■ 形（同じ月・続いた月・同じ種類）", 26, UiStyle.GOLD))
		for f in Rules.FORMS:
			var row := UiStyle.label("%s  %d×%d　%s" % [f[1], f[2], f[3], Rules.FORM_HELP[f[0]]], 22)
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(row)
		vb.add_child(UiStyle.label("■ 役（形に上乗せ）", 26, UiStyle.GOLD))
		for y in Rules.YAKU:
			var row := UiStyle.label("%s  +%dチップ +%d倍　%s" % [y[1], y[2], y[3], y[4]], 22)
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(row)
		vb.add_child(UiStyle.label("■ 札1枚のチップ：光15 / タネ8 / 短冊6 / カス3", 22))
	var b := _button("もどる  [Space]", func(): _set_state(TITLE), 26, "gray")
	_place(b, Rect2(v.x / 2 - 150, v.y - 84, 300, 60))


# ───────────────────────── ラン ─────────────────────────

func _new_run() -> void:
	run = Run.new()
	_set_state(INTRO)


## 場の前：道中すごろく・目標・親分の決まりを見せる
func _build_intro() -> void:
	var boss := run.boss_id()
	_set_bg(_stage_bg(), 0.5)
	Audio.bgm(_stage_bgm())
	var v := _view()
	var p := Screen.portrait
	var w := 860.0 if not p else v.x - 32
	# 道中すごろく
	var mh := 150.0
	var mbox := Rect2((v.x - w) / 2, 16, w, mh + 20)
	_tex_panel(mbox, null, 0.85)
	var map := ProgressMap.new(run, true)
	_screen.add_child(map)
	_place(map, Rect2(mbox.position + Vector2(10, 4), Vector2(w - 20, mh + 6)))
	var cur := run.stage * 3 + run.bout
	if cur > 0 and _talk_lines.is_empty():
		map.walk = 0.0
		create_tween().bind_node(map).tween_property(map, "walk", 1.0, 0.8).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	var box := Rect2((v.x - w) / 2, mbox.end.y + 14, w, 250 if boss == "" else 380)
	_tex_panel(box)
	_text("%s　%s（%d / 9 戦目）" % [Rules.STAGE_NAMES[run.stage], Rules.ROUND_NAMES[run.bout], cur + 1],
		Rect2(box.position + Vector2(0, 20), Vector2(w, 40)), 28, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var goal := _text("目標  %s 点" % _num(run.target()), Rect2(box.position + Vector2(0, 66), Vector2(w, 70)), 54, UiStyle.MULT, HORIZONTAL_ALIGNMENT_CENTER)
	_pop(goal)
	_text("勝てば %d文＋α　／　出す %d回・捨てる %d回" % [Rules.ROUND_REWARD[run.bout], _preview_plays(), _preview_discards()],
		Rect2(box.position + Vector2(0, 150), Vector2(w, 40)), 22, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	if boss != "":
		var bm := MiniChar.new(boss, true)
		_screen.add_child(bm)
		_place(bm, Rect2(box.position + Vector2(30, 190), Vector2(170, 170)))
		bm.act(MiniChar.SPECIAL, 2.0, true)
		_text(Rules.BOSSES[boss][0], Rect2(box.position + Vector2(220, 200), Vector2(w - 250, 40)), 30, UiStyle.GOLD)
		_text(Rules.BOSSES[boss][1], Rect2(box.position + Vector2(220, 248), Vector2(w - 250, 120)), 24, Color.WHITE)
	var b := _button("勝負！  [Space]", _start_bout, 34)
	_place(b, Rect2(v.x / 2 - 170, box.end.y + 20, 340, 74))
	# 会話（宿場の最初・親分のとき）
	if not _talk_lines.is_empty():
		return
	if boss != "":
		Audio.sfx("boss")
		_talk(Scenario.BOSS_TALKS[boss], Callable(), boss)
	elif run.bout == 0:
		_talk(Scenario.STAGE_TALKS[run.stage])
	else:
		_talk(Scenario.pick(Scenario.BOUT_TALKS))


func _preview_plays() -> int:
	var n := Rules.PLAYS + (1 if run.has_charm("chochin") else 0) - (1 if run.has_charm("gashadokuro") else 0)
	return max(n, 1)


func _preview_discards() -> int:
	if run.boss_id() == "kurobo":
		return 0
	return Rules.DISCARDS + (1 if run.has_charm("yukionna") else 0) + (1 if run.has_charm("chochin") else 0)


func _start_bout() -> void:
	run.start_round()
	_set_state(PLAY)
	Audio.sfx("shuffle")


# ───────────────────────── 勝負の画面 ─────────────────────────

func _build_play() -> void:
	_set_bg(_stage_bg(), 0.45)
	Audio.bgm(_stage_bgm())
	var u := _ui
	u.info = _tex_panel(Rect2(), null, 0.92, true)
	u.stage = _text("", Rect2(), 22, UiStyle.GOLD)
	u.map = ProgressMap.new(run)
	_screen.add_child(u.map)
	u.target = _text("", Rect2(), 24)
	u.score = _text("", Rect2(), 44, Color.WHITE)
	u.bar_bg = ColorRect.new()
	u.bar_bg.color = Color(0, 0, 0, 0.6)
	_screen.add_child(u.bar_bg)
	u.bar = ColorRect.new()
	u.bar.color = UiStyle.SHU
	_screen.add_child(u.bar)
	u.counts = _text("", Rect2(), 24)
	u.money = _text("", Rect2(), 26, UiStyle.GOLD)
	u.deck = _button("", _show_deck, 18, "flat")
	var boss := run.boss_id()
	if boss != "":
		u.boss_box = _panel(Rect2(), UiStyle.MULT, Color(0.2, 0.04, 0.06, 0.85))
		u.boss_rule = _text(Rules.BOSSES[boss][2], Rect2(), 17, Color(1, 0.85, 0.8))
		u.boss_task = _text("", Rect2(), 20, UiStyle.GOLD)
		u.boss_mini = MiniChar.new(boss, true)
		_screen.add_child(u.boss_mini)
	# ミニキャラと吹き出し
	u.kon = MiniChar.new("kon")
	u.gin = MiniChar.new("gin")
	_screen.add_child(u.kon)
	_screen.add_child(u.gin)
	u.bubble = _panel(Rect2(), Color.WHITE, Color(1, 1, 1, 0.96))
	u.bubble_name = _text("", Rect2(), 16, UiStyle.SHU)
	u.bubble_name.add_theme_constant_override("outline_size", 0)
	u.bubble_text = _text("", Rect2(), 19, Color(0.1, 0.05, 0.05), HORIZONTAL_ALIGNMENT_LEFT)
	u.bubble_text.add_theme_constant_override("outline_size", 0)
	_bubble_visible(false)
	# 形と点の箱
	u.form = _text("", Rect2(), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.chips_box = _panel(Rect2(), UiStyle.AI, Color(0.05, 0.1, 0.25, 0.92))
	u.chips = _text("0", Rect2(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.x = _text("×", Rect2(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.mult_box = _panel(Rect2(), UiStyle.MULT, Color(0.25, 0.05, 0.05, 0.92))
	u.mult = _text("0", Rect2(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.total = _text("", Rect2(), 56, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	u.total.z_index = 70  # 場の札より手前
	# 役の近道（場に札が無いあいだ、場の真ん中に出す）
	u.guide_box = _panel(Rect2(), Color(1, 1, 1, 0.25), Color(0.05, 0.02, 0.05, 0.6))
	u.guide_title = _text("役の近道", Rect2(), 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	u.guide = RichTextLabel.new()
	u.guide.bbcode_enabled = true
	u.guide.fit_content = false
	u.guide.scroll_active = false
	u.guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	u.guide.add_theme_font_size_override("normal_font_size", 21)
	u.guide.add_theme_constant_override("outline_size", 6)
	u.guide.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.03))
	_screen.add_child(u.guide)
	# 式神
	for i in Rules.MAX_CHARMS:
		var slot := _charm_slot(i)
		_charm_views.append(slot)
	u.tip = _text("", Rect2(), 20, Color(1, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	# ボタン
	u.sort = _button("並べ替え", _toggle_sort, 20, "gray")
	u.discard = _button("捨てる", _discard, 28, "blue")
	u.play = _button("出す", _play, 32)
	u.help = _button("役", _show_help, 24, "gray")
	for c in run.hand:
		_add_view(c)
	_layout_play()
	_refresh()
	_update_preview()
	if boss != "":
		_say_boss(Scenario.BOSS_TAUNTS[boss] if boss in ["kurobo", "ponkichi"] else _boss_task_text(), 2.4)


func _charm_slot(i: int) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	UiStyle.button_styles(b, Color(0.35, 0.2, 0.45))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = true
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 52)
	b.add_theme_constant_override("h_separation", 4)
	b.pressed.connect(func(): _show_charm_tip(i))
	b.mouse_entered.connect(func(): _show_charm_tip(i))
	_screen.add_child(b)
	return b


func _show_charm_tip(i: int) -> void:
	if i >= run.charms.size():
		_ui.tip.text = "式神は店で買える（最大%d体）" % Rules.MAX_CHARMS
		return
	var id: String = run.charms[i].id
	_ui.tip.text = "%s：%s%s" % [Rules.CHARMS[id][0], Rules.CHARMS[id][2], _charm_counter_text(run.charms[i])]


func _charm_counter_text(ch: Dictionary) -> String:
	match ch.id:
		"kasha": return "（今 チップ+%d）" % (6 * ch.get("counter", 0))
		"kyubi": return "（今 ×%s）" % _fmt(Scoring.kyubi_mult(ch.get("counter", 0)))
	return ""


func _add_view(c: Dictionary) -> CardView:
	var cv := CardView.new(c)
	cv.tapped.connect(_toggle)
	cv.mouse_entered.connect(func(): _show_card_tip(cv))
	_screen.add_child(cv)
	_views.append(cv)
	return cv


## 札に触れたら、その札が使える役を教える
func _show_card_tip(cv: CardView) -> void:
	if state != PLAY or not _ui.has("tip"):
		return
	var c := cv.card
	var uses := Scoring.card_yaku(c)
	_ui.tip.text = "%s（%s・チップ%d）%s" % [Cards.label(c), Cards.KIND_NAMES[c.kind], Cards.chips(c),
		("　役：" + "・".join(uses)) if not uses.is_empty() else ""]


## 画面の大きさから各部品の位置を決める
func _layout_play() -> void:
	var u := _ui
	var v := _view()
	var p := Screen.portrait
	var cw := 104.0
	if p:
		var info := Rect2(12, 12, v.x - 24, 236)
		_place(u.info, info)
		_place(u.stage, Rect2(32, 28, 440, 30))
		_place(u.map, Rect2(32, 60, 430, 30))
		_place(u.target, Rect2(32, 96, 440, 34))
		_place(u.score, Rect2(32, 124, 440, 56))
		_place(u.bar_bg, Rect2(32, 182, 430, 12))
		_place(u.counts, Rect2(32, 200, 470, 34))
		_place(u.money, Rect2(32, 200, 440, 34))
		u.money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_place(u.kon, Rect2(v.x - 250, 70, 140, 140))
		_place(u.gin, Rect2(v.x - 140, 80, 120, 130))
		_place(u.bubble, Rect2(v.x - 420, 256, 404, 82))
		var cy := 256.0
		if u.has("boss_box"):
			_place(u.boss_box, Rect2(12, cy, v.x - 444, 82))
			_place(u.boss_mini, Rect2(18, cy - 30, 100, 110))
			_place(u.boss_rule, Rect2(120, cy + 6, v.x - 570, 26))
			_place(u.boss_task, Rect2(120, cy + 34, v.x - 570, 46))
		cy += 92
		var sw := (v.x - 24 - 4 * 8) / 5.0
		for i in _charm_views.size():
			_place(_charm_views[i], Rect2(12 + i * (sw + 8), cy, sw, 76))
		_place(u.tip, Rect2(12, cy + 80, v.x - 24, 54))
		# 縦長の画面では余った高さを札の間に配る
		var by := v.y - 110
		var hand_y := by - cw * 1.55 - 40
		var fy: float = lerp(cy + 140, hand_y - 420, 0.5)
		_place(u.form, Rect2(0, fy, v.x, 44))
		_place(u.chips_box, Rect2(v.x / 2 - 230, fy + 50, 200, 70))
		_place(u.x, Rect2(v.x / 2 - 30, fy + 56, 60, 60))
		_place(u.mult_box, Rect2(v.x / 2 + 30, fy + 50, 200, 70))
		u.play_area = Rect2(20, fy + 150, v.x - 40, cw * 1.55)
		_place(u.total, Rect2(0, fy + 150 + cw * 1.55 + 10, v.x, 70))
		u.hand_area = Rect2(12, hand_y, v.x - 24, cw * 1.55)
		_place(u.sort, Rect2(12, by, 150, 84))
		_place(u.discard, Rect2(170, by, 176, 84))
		_place(u.play, Rect2(354, by, 240, 84))
		_place(u.help, Rect2(602, by, 106, 84))
		_place(u.deck, Rect2(v.x - 260, by - 50, 244, 42))
	else:
		var info := Rect2(8, 8, 308, v.y - 16)
		_place(u.info, info)
		_place(u.stage, Rect2(30, 26, 270, 30))
		_place(u.map, Rect2(26, 56, 272, 30))
		_place(u.target, Rect2(30, 94, 270, 34))
		_place(u.score, Rect2(30, 122, 270, 56))
		_place(u.bar_bg, Rect2(30, 178, 264, 12))
		_place(u.counts, Rect2(30, 196, 270, 64))
		_place(u.money, Rect2(30, 260, 270, 36))
		u.money.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_place(u.deck, Rect2(30, 300, 264, 36))
		if u.has("boss_box"):
			_place(u.boss_box, Rect2(26, 344, 272, 104))
			_place(u.boss_mini, Rect2(20, 330, 90, 116))
			_place(u.boss_rule, Rect2(108, 350, 186, 26))
			_place(u.boss_task, Rect2(108, 378, 186, 66))
		_place(u.bubble, Rect2(24, 456, 278, 92))
		_place(u.kon, Rect2(36, v.y - 176, 150, 150))
		_place(u.gin, Rect2(160, v.y - 170, 130, 140))
		var x0 := 328.0
		var aw := v.x - x0 - 12
		var sw := (aw - 4 * 10) / 5.0
		for i in _charm_views.size():
			_place(_charm_views[i], Rect2(x0 + i * (sw + 10), 12, sw, 70))
		_place(u.tip, Rect2(x0, 86, aw, 30))
		var cx := x0 + aw / 2
		_place(u.form, Rect2(x0, 118, aw, 44))
		_place(u.chips_box, Rect2(cx - 230, 164, 190, 64))
		_place(u.x, Rect2(cx - 30, 166, 60, 60))
		_place(u.mult_box, Rect2(cx + 40, 164, 190, 64))
		u.play_area = Rect2(x0, 246, aw, cw * 1.55)
		_place(u.total, Rect2(x0, 246 + cw * 1.55 - 26, aw, 70))
		u.hand_area = Rect2(x0, 450, aw, cw * 1.55)
		var by := v.y - 84
		_place(u.sort, Rect2(x0, by, 150, 70))
		_place(u.help, Rect2(x0 + 158, by, 92, 70))
		_place(u.discard, Rect2(cx - 40, by, 184, 70))
		_place(u.play, Rect2(cx + 152, by, 232, 70))
	_place(u.chips, Rect2(u.chips_box.position, u.chips_box.size - Vector2(0, 6)))
	_place(u.mult, Rect2(u.mult_box.position, u.mult_box.size - Vector2(0, 6)))
	var bb: Rect2 = u.bubble.get_rect()
	_place(u.bubble_name, Rect2(bb.position + Vector2(12, 4), Vector2(bb.size.x - 24, 22)))
	_place(u.bubble_text, Rect2(bb.position + Vector2(12, 26), bb.size - Vector2(24, 30)))
	var pa: Rect2 = u.play_area
	var gw: float = min(pa.size.x, 640.0)
	var gr := Rect2(pa.position.x + (pa.size.x - gw) / 2, pa.position.y + 6, gw, pa.size.y - 12)
	_place(u.guide_box, gr)
	_place(u.guide_title, Rect2(gr.position + Vector2(0, 6), Vector2(gr.size.x, 24)))
	_place(u.guide, Rect2(gr.position + Vector2(16, 34), gr.size - Vector2(32, 38)))
	u.card_size = Vector2(cw, cw * 1.55)
	_layout_hand(false)
	_layout_played()
	_refresh_bar()


func _hand_pos(i: int, n: int, sel: bool) -> Vector2:
	var a: Rect2 = _ui.hand_area
	var cs: Vector2 = _ui.card_size
	var step: float = min(cs.x + 10, (a.size.x - cs.x) / max(n - 1, 1))
	var total := step * (n - 1) + cs.x
	var x := a.position.x + (a.size.x - total) / 2 + step * i
	return Vector2(x, a.position.y - (cs.y * 0.22 if sel else 0.0))


func _layout_hand(animate: bool = true) -> void:
	var n := _views.size()
	for i in n:
		var cv: CardView = _views[i]
		cv.size = _ui.card_size
		var to := _hand_pos(i, n, cv.selected)
		cv.z_index = i
		if animate:
			create_tween().tween_property(cv, "position", to, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			cv.position = to


func _played_pos(i: int, n: int) -> Vector2:
	var a: Rect2 = _ui.play_area
	var cs: Vector2 = _ui.card_size
	var step := cs.x + 14
	var total := step * (n - 1) + cs.x
	return Vector2(a.position.x + (a.size.x - total) / 2 + step * i, a.position.y)


func _layout_played() -> void:
	for i in _played.size():
		_played[i].size = _ui.card_size
		_played[i].position = _played_pos(i, _played.size())


func _refresh() -> void:
	var u := _ui
	u.stage.text = "%s ・ %s" % [Rules.STAGE_NAMES[run.stage], Rules.ROUND_NAMES[run.bout]]
	u.target.text = "目標 %s 点" % _num(run.target())
	u.score.text = _num(run.score)
	u.counts.text = ("出す 残り%d回\n捨てる 残り%d回" if not Screen.portrait else "出す %d回 / 捨てる %d回") % [run.plays_left, run.discards_left]
	u.money.text = "%d 文" % run.money
	u.deck.text = "山札 %d / %d枚  ▶見る" % [run.draw_pile.size(), run.deck.size()]
	if u.has("boss_task"):
		u.boss_task.text = _boss_task_text()
	# 玉藻のお題の月の札を光らせる
	for cv in _views:
		cv.marked = run.boss_id() == "tamamo" and cv.card.month == run.oracle_month
	for i in _charm_views.size():
		var b: Button = _charm_views[i]
		if i < run.charms.size():
			var ch: Dictionary = run.charms[i]
			b.text = Rules.CHARMS[ch.id][0] + _charm_badge(ch)
			b.icon = tex("charms/" + ch.id)
			b.modulate = Color.WHITE
		else:
			b.text = "ー"
			b.icon = null
			b.modulate = Color(1, 1, 1, 0.45)
	_refresh_bar()
	_update_buttons()


func _charm_badge(ch: Dictionary) -> String:
	match ch.id:
		"kasha": return "\n+%d" % (6 * ch.get("counter", 0))
		"kyubi": return "\n×%s" % _fmt(Scoring.kyubi_mult(ch.get("counter", 0)))
	return ""


func _refresh_bar() -> void:
	if not _ui.has("bar_bg"):
		return
	var r: Rect2 = _ui.bar_bg.get_rect()
	var t: float = clamp(float(run.score) / run.target(), 0.0, 1.0)
	_place(_ui.bar, Rect2(r.position, Vector2(r.size.x * t, r.size.y)))
	_ui.bar.color = UiStyle.GOLD if t >= 1.0 else UiStyle.SHU


func _update_buttons() -> void:
	var n := _selected().size()
	var need := run.required_count
	_ui.play.disabled = busy or n == 0 or (need > 0 and n != need)
	_ui.discard.disabled = busy or n == 0 or run.discards_left <= 0
	_ui.play.text = ("出す (%d)" % run.plays_left) if need == 0 else ("%d枚で出す (%d)" % [need, run.plays_left])
	_ui.discard.text = "捨てる (%d)" % run.discards_left


## 親分のお題（その場の今の状態）
func _boss_task_text() -> String:
	match run.boss_id():
		"otama": return "お題：%d枚で出す" % run.required_count
		"tamamo": return "お題：%d月（%s）" % [run.oracle_month, Cards.MONTH_NAMES[run.oracle_month]]
		"ponkichi": return "カスはチップ0"
		"kurobo": return "捨てる 0回"
		"kawataro":
			var used := run.used_forms.map(func(f): return Rules.form_def(f)[1])
			return "出した形：" + ("・".join(used) if not used.is_empty() else "まだ無し")
	return ""


func _selected() -> Array:
	var out := []
	for cv in _views:
		if cv.selected:
			out.append(cv)
	return out


func _toggle(cv: CardView) -> void:
	if busy or state != PLAY or not _views.has(cv):
		return
	if not cv.selected and _selected().size() >= Rules.MAX_SELECT:
		_say(Scenario.SAY_MAX[0])
		return
	cv.selected = not cv.selected
	Audio.sfx("select", -6.0, 1.15 if cv.selected else 0.9)
	_layout_hand()
	_update_preview()
	_update_buttons()


func _toggle_sort() -> void:
	run.sort_by_kind = not run.sort_by_kind
	run.sort_hand()
	var order := []
	for c in run.hand:
		for cv in _views:
			if cv.card == c:
				order.append(cv)
	_views = order
	_layout_hand()
	_ui.sort.text = "並べ替え\n" + ("種類順" if run.sort_by_kind else "月順")


## 役の近道：手札で作れそうな役と、あと何が要るか
func _update_guide() -> void:
	var u := _ui
	var show := _played.is_empty()
	for k in ["guide_box", "guide_title", "guide"]:
		u[k].visible = show
	if not show:
		return
	var prog := Scoring.yaku_progress(run.hand)
	prog.sort_custom(func(a, b): return float(a[1]) / a[2] > float(b[1]) / b[2])
	var lines := []
	for y in prog.slice(0, 3):
		var dots := "●".repeat(mini(y[1], y[2])) + "○".repeat(maxi(y[2] - y[1], 0))
		if y[1] >= y[2]:
			lines.append("[color=#ffd166]%s %s　そろってる！ 一緒に出そう[/color]" % [y[0], dots])
		else:
			lines.append("%s [color=#ffd166]%s[/color]　[color=#bbbbbb]あと：%s[/color]" % [y[0], dots, y[3]])
	if lines.is_empty():
		lines.append("[color=#aaaaaa]手札に役の札はありません。札の下の印（猪・鹿・蝶・盃・赤短…）が役の札です[/color]")
	u.guide.text = "\n".join(lines)


## 選んでいる札でできる形を前もって見せる
func _update_preview() -> void:
	var sel := _selected()
	_ui.total.text = ""
	_update_guide()
	if sel.is_empty():
		_ui.form.text = "札を選んでください"
		_ui.form.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		_ui.chips.text = "0"
		_ui.mult.text = "0"
		return
	var cards := sel.map(func(cv): return cv.card)
	var form := Scoring.detect_form(cards, run.has_charm("karakasa"))
	var fd := Rules.form_def(form)
	var lv: int = run.form_levels.get(form, 0)
	var names := [fd[1] + (" Lv%d" % (lv + 1) if lv > 0 else "")]
	for y in Scoring.detect_yaku(cards):
		names.append(Scoring.yaku_def(y)[1])
	_ui.form.text = " ＋ ".join(names)
	_ui.form.add_theme_color_override("font_color", UiStyle.GOLD if names.size() > 1 else Color.WHITE)
	_ui.chips.text = str(fd[2] + fd[4] * lv)
	_ui.mult.text = str(fd[3] + fd[5] * lv)


func _play() -> void:
	if busy or state != PLAY:
		return
	var sel := _selected()
	if sel.is_empty():
		return
	if run.required_count > 0 and sel.size() != run.required_count:
		_say_boss(Scenario.BOSS_TAUNTS["otama"])
		return
	busy = true
	_update_guide()
	_ui.guide_box.visible = false
	_ui.guide_title.visible = false
	_ui.guide.visible = false
	_update_buttons()
	_ui.tip.text = ""
	var cards := sel.map(func(cv): return cv.card)
	var before := run.score
	var r := run.play(cards)
	# 場へ
	for cv in sel:
		_views.erase(cv)
		cv.selected = false
		cv.interactive = false
		_played.append(cv)
	Audio.sfx("play")
	for i in _played.size():
		var cv: CardView = _played[i]
		cv.z_index = 50 + i
		create_tween().tween_property(cv, "position", _played_pos(i, _played.size()), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_layout_hand()
	await _wait(0.35)
	await _animate_score(r)
	# 点を足す
	var t := create_tween()
	t.tween_method(func(x: float): _ui.score.text = _num(int(x)), float(before), float(run.score), 0.6)
	Audio.sfx("coin")
	await _wait(0.2)
	_refresh_bar()
	if run.score >= run.target() and before < run.target():
		_ui.score.add_theme_color_override("font_color", UiStyle.GOLD)
	_react(r, before)
	await _wait(0.7)
	# 場の札を片付ける
	for cv in _played:
		var tw := create_tween().set_parallel()
		tw.tween_property(cv, "position", cv.position + Vector2(_view().x, -80), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(cv, "rotation", 0.6, 0.35)
		tw.chain().tween_callback(cv.queue_free)
	_played.clear()
	_ui.total.text = ""
	await _wait(0.3)
	await _after_hand_change()


func _discard() -> void:
	if busy or state != PLAY or run.discards_left <= 0:
		return
	var sel := _selected()
	if sel.is_empty():
		return
	busy = true
	_update_buttons()
	run.discard(sel.map(func(cv): return cv.card))
	Audio.sfx("discard")
	for cv in sel:
		_views.erase(cv)
		var tw := create_tween().set_parallel()
		tw.tween_property(cv, "position", cv.position + Vector2(0, 300), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(cv, "modulate:a", 0.0, 0.3)
		tw.chain().tween_callback(cv.queue_free)
	if randf() < 0.35:
		_say(Scenario.pick(Scenario.SAY_DISCARD))
	elif run.has_charm("kasha"):
		_float_text("火車 チップ+6", _charm_center("kasha"), Color(1, 0.6, 0.3), 24)
	_layout_hand()
	await _wait(0.3)
	await _after_hand_change()


## 札を引き足して、勝ち負けを判定する
func _after_hand_change() -> void:
	var drawn := run.draw_to_full()
	for c in drawn:
		var cv := _add_view(c)
		cv.size = _ui.card_size
		cv.position = Vector2(_view().x + 50, _ui.hand_area.position.y)
	# 手札の並び（run.hand の順）に合わせる
	var order := []
	for c in run.hand:
		for cv in _views:
			if cv.card == c:
				order.append(cv)
	_views = order
	if not drawn.is_empty():
		Audio.sfx("card", -8.0)
	_layout_hand()
	await _wait(0.25)
	busy = false
	var task_before: String = _ui.boss_task.text if _ui.has("boss_task") else ""
	_refresh()
	_update_preview()
	if run.won():
		_round_won()
	elif run.lost():
		_game_over()
	elif run.plays_left == 1 and run.score < run.target():
		_say(Scenario.pick(Scenario.SAY_DANGER), "panic")
	elif _ui.has("boss_task") and _ui.boss_task.text != task_before and run.boss_id() in ["otama", "tamamo"]:
		# お題が変わったことを親分が告げる
		_pop(_ui.boss_task)
		_ui.boss_mini.act(MiniChar.SPECIAL, 1.2, true)
		_say_boss(_boss_task_text(), 2.0)


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout


## 点の計算を1段ずつ見せる
func _animate_score(r: Dictionary) -> void:
	var chips := 0.0
	var mult := 0.0
	var pitch := 1.0
	for s in r.steps:
		chips += s.chips
		mult += s.mult
		mult *= s.xmult
		match s.src:
			"form":
				_ui.form.text = s.text
				_ui.form.add_theme_color_override("font_color", Color.WHITE)
				_pop(_ui.form)
				Audio.sfx("chip")
			"card":
				if s.chips == 0 and s.mult == 0 and s.xmult == 1.0:
					continue
				var cv: CardView = _played[s.index]
				_pop(cv)
				var at := cv.position + Vector2(cv.size.x / 2, cv.size.y * 0.45)
				if s.chips != 0:
					_float_text("+%d" % s.chips, at, UiStyle.AI)
				if s.mult != 0:
					_float_text("+%d倍" % s.mult, at + Vector2(0, -34), UiStyle.MULT)
				if s.xmult != 1.0:
					_float_text("×%s" % _fmt(s.xmult), at + Vector2(0, -68), UiStyle.MULT)
				Audio.sfx("chip", -4.0, pitch)
				pitch = min(pitch + 0.06, 2.0)
			"yaku":
				_banner(s.text + "！", UiStyle.GOLD)
				Audio.sfx("yaku")
				_ui.kon.act(MiniChar.HAPPY, 1.0, true)
				await _wait(0.45)
			"boss":
				_banner(s.text + " ×%s" % _fmt(s.xmult), Color(0.85, 0.6, 1.0), 60)
				Audio.sfx("xmult")
				_ui.boss_mini.act(MiniChar.PANIC, 1.2, false, true)
				await _wait(0.35)
			"charm":
				var b: Control = _charm_views[s.index]
				_pop(b)
				var at := b.position + Vector2(b.size.x / 2, b.size.y + 10)
				var txt := ""
				if s.chips != 0: txt += "+%d " % s.chips
				if s.mult != 0: txt += "+%d倍 " % s.mult
				if s.xmult != 1.0: txt += "×%s" % _fmt(s.xmult)
				_float_text(txt.strip_edges(), at, UiStyle.MULT if s.chips == 0 else UiStyle.AI)
				Audio.sfx("mult" if s.xmult == 1.0 else "xmult")
		_ui.chips.text = _num(int(chips))
		_ui.mult.text = _fmt(mult)
		await _wait(0.22)
	var total: int = r.total
	if r.halved:
		_ui.boss_mini.act(MiniChar.SPECIAL, 1.4, true)
		_say_boss(Scenario.BOSS_TAUNTS[run.boss_id()], 2.0)
		_banner("半分！", UiStyle.MULT, 60)
		await _wait(0.4)
	_ui.total.text = "= " + _num(total) + ("（半分）" if r.halved else "")
	_pop(_ui.total)
	Audio.sfx("total", -2.0)
	if total >= run.target() * 0.5:
		_shake(self)
	await _wait(0.4)


func _react(r: Dictionary, before: int) -> void:
	if not r.yaku.is_empty():
		_say(Scenario.pick(Scenario.SAY_YAKU), "happy")
	elif r.total >= run.target() * 0.4:
		_say(Scenario.pick(Scenario.SAY_BIG), "happy")
		if _ui.has("boss_mini"):
			_ui.boss_mini.act(MiniChar.PANIC, 1.5, false, true)
	elif r.total < run.target() * 0.12:
		_say(Scenario.pick(Scenario.SAY_SMALL), "panic")


func _bubble_visible(on: bool) -> void:
	for k in ["bubble", "bubble_name", "bubble_text"]:
		_ui[k].visible = on


## 吹き出しを出す。speaker: コン/ギン/親分の名前
func _bubble(speaker: String, text: String, col: Color) -> void:
	_bubble_visible(true)
	_ui.bubble_name.text = speaker
	_ui.bubble_name.add_theme_color_override("font_color", col)
	_ui.bubble_text.text = text
	_pop(_ui.bubble)


## コンが言って、ギンがツッコむ。pair: [コン, ギン]（ギンが "" なら黙る）
func _say(pair: Array, mood: String = "normal") -> void:
	if not _ui.has("bubble"):
		return
	var frame: int = {"normal": MiniChar.IDLE, "happy": MiniChar.HAPPY, "panic": MiniChar.PANIC, "smug": MiniChar.SPECIAL}[mood]
	_ui.kon.act(frame, 1.6, mood == "happy", mood == "panic")
	_bubble("コン", pair[0], UiStyle.SHU)
	if _say_tween:
		_say_tween.kill()
	_say_tween = create_tween()
	if pair.size() > 1 and pair[1] != "":
		_say_tween.tween_interval(1.6)
		_say_tween.tween_callback(func():
			if _ui.has("bubble"):
				_ui.gin.act(MiniChar.SPECIAL, 1.2, true)
				_bubble("ギン", pair[1], Color(0.2, 0.4, 0.75)))
	_say_tween.tween_interval(2.2)
	_say_tween.tween_callback(func():
		if _ui.has("bubble"):
			_bubble_visible(false))


func _say_boss(text: String, sec: float = 2.4) -> void:
	if not _ui.has("boss_mini"):
		return
	_ui.boss_mini.act(MiniChar.SPECIAL, 1.0)
	_bubble(Rules.BOSSES[run.boss_id()][0], text, Color(0.6, 0.15, 0.4))
	if _say_tween:
		_say_tween.kill()
	_say_tween = create_tween()
	_say_tween.tween_interval(sec)
	_say_tween.tween_callback(func():
		if _ui.has("bubble"):
			_bubble_visible(false))


func _charm_center(id: String) -> Vector2:
	for i in run.charms.size():
		if run.charms[i].id == id and i < _charm_views.size():
			var b: Control = _charm_views[i]
			return b.position + b.size / 2 + Vector2(0, 40)
	return _view() / 2


func _round_won() -> void:
	busy = true
	Audio.jingle("win")
	_banner("勝ち！", UiStyle.GOLD, 96)
	_ui.kon.act(MiniChar.HAPPY, 2.0, true)
	_ui.gin.act(MiniChar.HAPPY, 2.0, true)
	if _ui.has("boss_mini"):
		_ui.boss_mini.act(MiniChar.PANIC, 2.0, false, true)
	_confetti()
	await _wait(1.6)
	busy = false
	_payout = run.payout()
	_set_state(PAYOUT)


func _game_over() -> void:
	busy = true
	Audio.jingle("lose")
	_banner("あと %s 点…" % _num(run.target() - run.score), UiStyle.MULT, 64)
	_ui.kon.act(MiniChar.PANIC, 2.5, false, true)
	_ui.gin.act(MiniChar.PANIC, 2.5)
	if _ui.has("boss_mini"):
		_ui.boss_mini.act(MiniChar.HAPPY, 2.5, true)
	await _wait(2.0)
	busy = false
	_set_state(GAMEOVER)


## 勝ったときに花札の紙吹雪
func _confetti() -> void:
	var v := _view()
	for i in 26:
		var r := ColorRect.new()
		r.size = Vector2(10, 16)
		r.color = [UiStyle.GOLD, UiStyle.SHU, Color(1, 1, 1), Color(0.4, 0.8, 0.5)][i % 4]
		r.position = Vector2(randf() * v.x, -20 - randf() * 120)
		r.rotation = randf() * TAU
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(r)
		var t := create_tween().set_parallel()
		var dur := randf_range(1.2, 2.0)
		t.tween_property(r, "position:y", v.y + 40, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(r, "position:x", r.position.x + randf_range(-120, 120), dur)
		t.tween_property(r, "rotation", r.rotation + randf_range(-8, 8), dur)
		t.chain().tween_callback(r.queue_free)


# ───────────────────────── 演出 ─────────────────────────

func _float_text(text: String, at: Vector2, color: Color, fsize: int = 30) -> void:
	var l := UiStyle.label(text, fsize, color, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(240, fsize + 16)
	l.position = at - Vector2(120, fsize)
	l.pivot_offset = l.size / 2
	_fx.add_child(l)
	var t := create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y - 50, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.5)
	t.chain().tween_callback(l.queue_free)


## 画面の真ん中に帯つきの大きな文字を出す（札より上の層）
func _banner(text: String, color: Color, fsize: int = 72) -> void:
	var v := _view()
	var y := v.y * 0.36
	var band := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.02, 0.04, 0.82)
	sb.border_color = color
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	band.add_theme_stylebox_override("panel", sb)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(v.x, fsize + 40)
	band.position = Vector2(0, y - 6)
	band.pivot_offset = band.size / 2
	band.scale = Vector2(1, 0)
	_fx.add_child(band)
	var l := UiStyle.label(text, fsize, color, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(v.x, fsize + 30)
	l.position = Vector2(0, y)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.3, 0.3)
	_fx.add_child(l)
	var t := create_tween()
	t.tween_property(band, "scale", Vector2.ONE, 0.12)
	t.parallel().tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(band, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)
	t.tween_callback(band.queue_free)


func _pop(c: Control) -> void:
	c.pivot_offset = c.size / 2
	var t := create_tween()
	t.tween_property(c, "scale", Vector2(1.15, 1.15), 0.07)
	t.tween_property(c, "scale", Vector2.ONE, 0.12)


func _shake(c: Control) -> void:
	var t := create_tween()
	for i in 6:
		t.tween_property(c, "position", Vector2(randf_range(-8, 8), randf_range(-6, 6)), 0.04)
	t.tween_property(c, "position", Vector2.ZERO, 0.04)


static func _num(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _fmt(x: float) -> String:
	if abs(x - round(x)) < 0.01:
		return str(int(round(x)))
	return "%.1f" % x


# ───────────────────────── 稼ぎ・店 ─────────────────────────

func _build_payout() -> void:
	_set_bg(_stage_bg(), 0.6)
	var v := _view()
	var w := 600.0 if not Screen.portrait else v.x - 60
	var box := Rect2((v.x - w) / 2, 80, w, 120 + _payout.size() * 54 + 90)
	_tex_panel(box)
	_text("稼ぎ", Rect2(box.position + Vector2(0, 16), Vector2(w, 50)), 40, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var sum := 0
	for i in _payout.size():
		var row: Array = _payout[i]
		sum += row[1]
		var y := box.position.y + 90 + i * 54
		var a := _text(row[0], Rect2(box.position.x + 30, y, w - 200, 44), 26)
		var b := _text("%+d文" % row[1], Rect2(box.end.x - 180, y, 150, 44), 28, UiStyle.GOLD if row[1] >= 0 else UiStyle.MULT, HORIZONTAL_ALIGNMENT_RIGHT)
		a.modulate.a = 0
		b.modulate.a = 0
		var t := create_tween()
		t.tween_interval(0.25 + i * 0.3)
		t.tween_callback(func(): Audio.sfx("coin", -6.0, 1.0 + i * 0.1))
		t.tween_property(a, "modulate:a", 1.0, 0.15)
		t.parallel().tween_property(b, "modulate:a", 1.0, 0.15)
	_text("所持金  %d文 → %d文" % [run.money, run.money + sum], Rect2(box.position.x, box.end.y - 70, w, 50), 30,
		Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var last := run.stage == 2 and run.bout == 2
	var b := _button(("玉藻に挑んだ結果へ" if last else "店へ") + "  [Space]", _after_payout, 30)
	_place(b, Rect2(v.x / 2 - 190, box.end.y + 30, 380, 70))
	var boss := run.boss_id()
	if _talk_lines.is_empty() and not last:
		if Scenario.BOSS_WIN_TALKS.has(boss):
			_talk(Scenario.BOSS_WIN_TALKS[boss], Callable(), boss)
		else:
			_talk(Scenario.pick(Scenario.WIN_TALKS))


func _after_payout() -> void:
	for p in _payout:
		run.money += p[1]
	_payout = []
	if run.advance():
		_set_state(CLEAR)
		return
	_offers = run.shop_offers()
	_reroll_cost = Rules.REROLL_COST
	_shop_msg = Scenario.pick(Scenario.SHOP_GREETINGS)
	_set_state(SHOP)


func _build_shop() -> void:
	_set_bg("bg_shop", 0.4)
	Audio.bgm("shop")
	var v := _view()
	var p := Screen.portrait
	_text("夜市", Rect2(24, 16, 300, 60), 44, UiStyle.GOLD)
	_text("所持金 %d文" % run.money, Rect2(v.x - 324, 20, 300, 50), 34, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# 品物
	var cols := 3 if not p else 2
	var area := Rect2(300, 90, v.x - 320, 420) if not p else Rect2(16, 300, v.x - 32, 560)
	var gw := (area.size.x - (cols - 1) * 12) / cols
	var gh := 196.0 if not p else 176.0
	for i in _offers.size():
		var o: Dictionary = _offers[i]
		var r := Rect2(area.position + Vector2((i % cols) * (gw + 12), (i / cols) * (gh + 12)), Vector2(gw, gh))
		_offer_card(o, i, r)
	# コンと吹き出し
	var kr := Rect2(30, v.y - 250, 150, 150) if not p else Rect2(v.x - 250, 120, 140, 140)
	var mk := MiniChar.new("kon")
	_screen.add_child(mk)
	_place(mk, kr)
	var mg := MiniChar.new("gin", true)
	_screen.add_child(mg)
	_place(mg, Rect2(kr.position + Vector2(kr.size.x * 0.8, kr.size.y * 0.1), kr.size * 0.9))
	if _shop_msg.contains("ギン"):
		mk.act(MiniChar.HAPPY, 1.0, true)
		var t := create_tween().bind_node(mg)
		t.tween_interval(0.5)
		t.tween_callback(func(): mg.act(MiniChar.SPECIAL, 1.2, true))
	var br := Rect2(16, 86, 276, 196) if not p else Rect2(16, 90, v.x - 270, 190)
	_panel(br, Color.WHITE, Color(1, 1, 1, 0.95))
	var bt := _text(_shop_msg, br.grow(-12), 20, Color(0.1, 0.05, 0.05))
	bt.add_theme_constant_override("outline_size", 0)
	# 持っている式神（タップで売る）
	var oy := area.end.y + 14 if not p else 880.0
	_text("持っている式神（タップで売る）  %d/%d" % [run.charms.size(), Rules.MAX_CHARMS], Rect2(area.position.x, oy, area.size.x, 32), 22, Color(1, 1, 1, 0.85))
	var sw := (area.size.x - 4 * 8) / 5.0
	for i in run.charms.size():
		var ch: Dictionary = run.charms[i]
		var b := _button("%s\n売る %d文" % [Rules.CHARMS[ch.id][0], run.sell_price(ch.id)], _sell.bind(i), 18, "flat")
		b.icon = tex("charms/" + ch.id)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 48)
		_place(b, Rect2(area.position.x + i * (sw + 8), oy + 36, sw, 70))
	# 札の情報・ボタン
	var levels := []
	for f in run.form_levels:
		levels.append("%s Lv%d" % [Rules.form_def(f)[1], run.form_levels[f] + 1])
	_text("山札 %d枚%s" % [run.deck.size(), ("　／　" + "・".join(levels)) if not levels.is_empty() else ""],
		Rect2(area.position.x, oy + 112, area.size.x, 30), 20, Color(1, 1, 1, 0.75))
	var by := v.y - 86
	var rr := _button("品物を入れ替える (%d文)" % _reroll_cost, _reroll, 22, "blue")
	rr.disabled = run.money < _reroll_cost
	var nb := _button("次の場へ  →", _leave_shop, 28, "green")
	if p:
		_place(rr, Rect2(16, by, v.x / 2 - 24, 70))
		_place(nb, Rect2(v.x / 2 + 8, by, v.x / 2 - 24, 70))
	else:
		_place(rr, Rect2(v.x - 640, by, 300, 66))
		_place(nb, Rect2(v.x - 324, by, 300, 66))


func _offer_card(o: Dictionary, i: int, r: Rect2) -> void:
	var title := ""
	var tag := ""
	var desc := ""
	var col := Color(0.35, 0.2, 0.45)
	match o.type:
		"charm":
			title = Rules.CHARMS[o.id][0]
			tag = "式神"
			desc = Rules.CHARMS[o.id][2]
		"scroll":
			var fd := Rules.form_def(o.id)
			var lv: int = run.form_levels.get(o.id, 0)
			title = "%sの巻物" % fd[1]
			tag = "巻物"
			desc = "%s を Lv%d に（チップ+%d 倍率+%d）" % [fd[1], lv + 2, fd[4], fd[5]]
			col = Color(0.2, 0.4, 0.3)
		"talisman":
			title = Rules.TALISMANS[o.id][0]
			tag = "お札"
			desc = Rules.TALISMANS[o.id][2]
			col = Color(0.5, 0.25, 0.15)
	var b := _button("", _buy.bind(i), 20, "flat")
	UiStyle.button_styles(b, col)
	b.add_theme_stylebox_override("normal", UiStyle.panel(UiStyle.GOLD, Color(col.darkened(0.45), 0.95), 6, 12))
	_place(b, r)
	var can: bool = run.money >= o.price and not (o.type == "charm" and run.charm_slots_free() <= 0)
	b.disabled = not can
	var pic := 0.0
	if o.type == "charm":
		pic = min(96.0, r.size.y - 60)
		_picture("charms/" + o.id, Rect2(r.position + Vector2(10, r.size.y - pic - 8), Vector2(pic, pic)))
	_text("［%s］%s" % [tag, title], Rect2(r.position + Vector2(14, 10), Vector2(r.size.x - 28, 34)), 24, UiStyle.GOLD)
	_text(desc, Rect2(r.position + Vector2(14, 48), Vector2(r.size.x - 28, r.size.y - 100)), 19)
	_text("%d文" % o.price, Rect2(r.position + Vector2(14, r.size.y - 46), Vector2(r.size.x - 28, 36)), 26,
		Color.WHITE if can else Color(1, 0.5, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)


func _buy(i: int) -> void:
	var o: Dictionary = _offers[i]
	if run.money < o.price:
		return
	match o.type:
		"charm":
			if run.charm_slots_free() <= 0:
				return
			run.money -= o.price
			run.add_charm(o.id)
			var q: Array = Scenario.CHARM_QUIPS.get(o.id, ["ゲット！", "…"])
			_shop_msg = "コン「%s」\nギン「%s」" % q
		"scroll":
			run.money -= o.price
			run.form_levels[o.id] = run.form_levels.get(o.id, 0) + 1
			_shop_msg = "コン「%sが強くなった！ 巻物って読むと強くなるんだね！」\nギン「お前、枕にしてただろ」" % Rules.form_def(o.id)[1]
		"talisman":
			run.money -= o.price
			_offers.remove_at(i)
			Audio.sfx("buy")
			_pick_card_for(o.id)
			return
	_offers.remove_at(i)
	Audio.sfx("buy")
	_build()


func _sell(i: int) -> void:
	var id: String = run.charms[i].id
	run.money += run.sell_price(id)
	run.charms.remove_at(i)
	_shop_msg = "コン「%sさん、今までありがとう！」\nギン「別れ際だけは礼儀正しいな」" % Rules.CHARMS[id][0]
	Audio.sfx("coin")
	_build()


func _reroll() -> void:
	if run.money < _reroll_cost:
		return
	run.money -= _reroll_cost
	_reroll_cost += 1
	_offers = run.shop_offers()
	_shop_msg = "店主「新しい品物、入りました〜！」\nギン「入れ替えにも金がかかるのを忘れるな」"
	Audio.sfx("shuffle")
	_build()


func _leave_shop() -> void:
	_set_state(INTRO)


## お札：山札から出た6枚から1枚選ぶ
func _pick_card_for(tid: String) -> void:
	_close_overlay()
	var v := _view()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.75)
	_overlay.z_index = 150
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var lab := UiStyle.label("%s：どの札に使う？" % Rules.TALISMANS[tid][0], 34, UiStyle.GOLD)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(v.x, 50)
	lab.position = Vector2(0, 60)
	_overlay.add_child(lab)
	var sub := UiStyle.label(Rules.TALISMANS[tid][2], 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(v.x, 40)
	sub.position = Vector2(0, 116)
	_overlay.add_child(sub)
	_overlay_modal = true
	var choices := run.talisman_choices()
	var cw := 140.0 if not Screen.portrait else 150.0
	var cols := choices.size() if not Screen.portrait else 3
	var step := cw + 20
	for i in choices.size():
		var cv := CardView.new(choices[i])
		cv.size = Vector2(cw, cw * 1.55)
		var row := i / cols
		var col := i % cols
		var n: int = mini(cols, choices.size())
		cv.position = Vector2((v.x - (step * n - 20)) / 2 + col * step, 200 + row * (cw * 1.55 + 30))
		cv.tapped.connect(func(view: CardView):
			run.apply_talisman(tid, view.card)
			Audio.sfx("yaku")
			_shop_msg = "コン「%sに%sを使った！」\nギン「…札が喜んでいる気がする」" % [Cards.label(view.card), Rules.TALISMANS[tid][0]]
			_close_overlay()
			_build())
		_overlay.add_child(cv)


## 山札の中身：まだ引いていない札は明るく、使った札は暗く
func _show_deck() -> void:
	_close_overlay()
	var v := _view()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.03, 0.01, 0.02, 0.96)
	_overlay.z_index = 150
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var lab := UiStyle.label("山札（明るい札がまだ残っている）  残り %d枚" % run.draw_pile.size(), 28, UiStyle.GOLD)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(v.x, 44)
	lab.position = Vector2(0, 16)
	_overlay.add_child(lab)
	var cards := run.deck.duplicate()
	cards.sort_custom(func(a, b): return a.month < b.month or (a.month == b.month and a.kind > b.kind))
	var cols := 16 if not Screen.portrait else 8
	var cw: float = (v.x - 40) / cols - 6
	cw = min(cw, 76.0)
	var step := cw + 6
	var x0 := (v.x - step * cols) / 2
	for i in cards.size():
		var cv := CardView.new(cards[i])
		cv.interactive = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.size = Vector2(cw, cw * 1.55)
		cv.position = Vector2(x0 + (i % cols) * step, 72 + (i / cols) * (cw * 1.55 + 6))
		if not run.draw_pile.has(cards[i]):
			cv.modulate = Color(0.35, 0.35, 0.35, 0.8)
		_overlay.add_child(cv)
	var b := Button.new()
	b.text = "閉じる [Esc]"
	b.add_theme_font_size_override("font_size", 26)
	UiStyle.tex_button(b, "gray")
	b.position = Vector2(v.x / 2 - 130, v.y - 86)
	b.size = Vector2(260, 64)
	b.pressed.connect(_close_overlay)
	_overlay.add_child(b)


func _show_help() -> void:
	_close_overlay()
	var v := _view()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.88)
	_overlay.z_index = 150
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.position = Vector2(40, 30)
	sc.size = Vector2(v.x - 80, v.y - 130)
	_overlay.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = v.x - 100
	sc.add_child(vb)
	vb.add_child(UiStyle.label("■ 形", 28, UiStyle.GOLD))
	for f in Rules.FORMS:
		var lv: int = run.form_levels.get(f[0], 0) if run else 0
		var row := UiStyle.label("%s%s  %d×%d　%s" % [f[1], " Lv%d" % (lv + 1) if lv > 0 else "", f[2] + f[4] * lv, f[3] + f[5] * lv, Rules.FORM_HELP[f[0]]], 22)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(row)
	vb.add_child(UiStyle.label("■ 役（形に上乗せ）", 28, UiStyle.GOLD))
	for y in Rules.YAKU:
		var row := UiStyle.label("%s  +%dチップ +%d倍　%s" % [y[1], y[2], y[3], y[4]], 22)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(row)
	vb.add_child(UiStyle.label("■ 役の札（札の下に印が付いている）", 28, UiStyle.GOLD))
	for t in ["光：松に鶴(1月)・桜に幕(3月)・芒に月(8月)・柳に小野道風(11月・雨)・桐に鳳凰(12月)",
			"猪鹿蝶：萩に猪(7月)・紅葉に鹿(10月)・牡丹に蝶(6月)",
			"赤短：松・梅・桜の赤い短冊(1〜3月)　／　青短：牡丹・菊・紅葉の青い短冊(6・9・10月)",
			"盃：菊に盃(9月) … 桜に幕と組めば花見で一杯、芒に月と組めば月見で一杯"]:
		var row := UiStyle.label(t, 21)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(row)
	vb.add_child(UiStyle.label("札1枚のチップ：光15 / タネ8 / 短冊6 / カス3　金箔は倍率+3", 22))
	var b := Button.new()
	b.text = "閉じる [Esc]"
	b.add_theme_font_size_override("font_size", 26)
	UiStyle.tex_button(b, "gray")
	b.position = Vector2(v.x / 2 - 130, v.y - 86)
	b.size = Vector2(260, 64)
	b.pressed.connect(_close_overlay)
	_overlay.add_child(b)


func _close_overlay() -> void:
	_overlay_modal = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null


# ───────────────────────── 終わり ─────────────────────────

func _build_end(clear: bool) -> void:
	var v := _view()
	var p := Screen.portrait
	if clear:
		_set_bg("title", 0.35)
	else:
		_set_bg(_stage_bg(), 0.7)
	var w := 720.0 if not p else v.x - 40
	var box := Rect2((v.x - w) / 2, 40, w, 460)
	_tex_panel(box)
	_text("あぶらあげ 奪還！" if clear else "文無し…", Rect2(box.position + Vector2(0, 20), Vector2(w, 80)), 60,
		UiStyle.GOLD if clear else UiStyle.MULT, HORIZONTAL_ALIGNMENT_CENTER)
	var reached := "全9戦 勝ち抜き" if clear else "%s・%s で敗退（%d / 9 戦）" % [Rules.STAGE_NAMES[run.stage], Rules.ROUND_NAMES[run.bout], run.stage * 3 + run.bout]
	var yk := []
	for y in run.yaku_made:
		yk.append("%s×%d" % [Scoring.yaku_def(y)[1], run.yaku_made[y]])
	var chs := run.charms.map(func(c): return Rules.CHARMS[c.id][0])
	var body := "%s\n一番の大技：%s点（%s）\n作った役：%s\n最後の式神：%s" % [reached, _num(run.best_hand), run.best_form if run.best_form != "" else "ー",
		"、".join(yk) if not yk.is_empty() else "なし", "、".join(chs) if not chs.is_empty() else "なし"]
	_text(body, Rect2(box.position + Vector2(36, 120), Vector2(w - 72, 320)), 26)
	var mk := MiniChar.new("kon")
	_screen.add_child(mk)
	_place(mk, Rect2(box.end.x - 190, box.end.y - 180, 160, 160))
	var loop := create_tween().set_loops()
	loop.tween_callback(func(): mk.act(MiniChar.HAPPY if clear else MiniChar.PANIC, 1.2, clear, not clear))
	loop.tween_interval(2.0)
	loop.bind_node(mk)
	var b := _button("タイトルへ  [Space]", func(): _set_state(TITLE), 28, "gray")
	_place(b, Rect2(v.x / 2 - 170, box.end.y + 30, 340, 70))
	if _talk_lines.is_empty():
		if clear:
			Audio.jingle("clear")
			_talk(Scenario.CLEAR_TALK, Callable(), "tamamo")
		else:
			_talk(Scenario.pick(Scenario.GAMEOVER_TALKS))

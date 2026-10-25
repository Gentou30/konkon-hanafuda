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
var _fx: Control             # 浮かぶ文字などを載せる一番上の層
var _talk_layer: Control
var _talk_lines := []
var _talk_i := 0
var _talk_done: Callable
var _boss_for_talk := ""
var _talk_seen := ""        # 最後に会話を出した画面（組み直しで繰り返さない）
var _overlay: Control        # 役一覧・お札の札選び
var _overlay_modal := false  # お札の札選びは選ぶまで閉じられない（払ったお金が無駄になるため）

# PLAY 画面の部品
var _ui := {}
var _views := []             # 手札の CardView
var _played := []            # 場に出した CardView
var _charm_views := []
var _kon_tween: Tween

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
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_talk_layer = Control.new()
	_talk_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_talk_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_bg.texture = tex(name)
	_dim.color = Color(0.03, 0.01, 0.04, dim)


func _view() -> Vector2:
	return size


func _button(text: String, cb: Callable, font: int = 30, main: Color = UiStyle.SHU) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font)
	UiStyle.button_styles(b, main)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		if busy or not _talk_lines.is_empty():
			return
		Audio.sfx("click")
		cb.call())
	_screen.add_child(b)
	return b


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
	if _talk_lines.is_empty():
		return
	var v := _view()
	var line: Array = _talk_lines[_talk_i]
	var who: String = line[0]
	# 画面全体で入力を受けて次へ進める
	var catcher := ColorRect.new()
	catcher.color = Color(0, 0, 0, 0.25)
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_talk_layer.add_child(catcher)
	var h := 200.0 if not Screen.portrait else 240.0
	var box := Rect2(16, v.y - h - 16, v.x - 32, h)
	var pw := 220.0 if not Screen.portrait else 200.0
	var name := ""
	var pic := ""
	match who:
		"K":
			name = "コン"
			pic = "kon_normal"
			if line.size() > 2:
				pic = "kon_" + line[2]
		"G":
			name = "ギン"
			pic = "gin"
		"B":
			name = Rules.BOSSES[_boss_for_talk][0] if _boss_for_talk != "" else "親分"
			pic = "boss_" + _boss_for_talk
	var left := who != "B"
	var pr := Rect2(box.position.x + (0.0 if left else box.size.x - pw), box.position.y - pw * 0.95, pw, pw * 1.15)
	_picture(pic, pr, _talk_layer)
	var p := _panel(box, UiStyle.GOLD, Color(0.07, 0.03, 0.04, 0.94), _talk_layer)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nc := UiStyle.GOLD if who == "K" else (Color(0.75, 0.85, 1.0) if who == "G" else UiStyle.MULT)
	_text(name, Rect2(box.position + Vector2(24, 12), Vector2(400, 40)), 28, nc, HORIZONTAL_ALIGNMENT_LEFT, _talk_layer)
	var fs := 30 if not Screen.portrait else 30
	_text(line[1], Rect2(box.position + Vector2(24, 56), box.size - Vector2(48, 70)), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, _talk_layer)
	_text("▼ タップ / Space", Rect2(box.end - Vector2(300, 42), Vector2(284, 36)), 18, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, _talk_layer)


func _advance_talk() -> void:
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
	_set_bg("title", 0.15)
	Audio.bgm("title")
	var v := _view()
	var p := Screen.portrait
	var lx := 40.0
	var top := 40.0 if not p else 60.0
	var w := 640.0 if not p else v.x - 80
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.05, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(shade)
	_place(shade, Rect2(0, 0, (w + 80) if not p else v.x, v.y if not p else 560))
	_text("妖怪賭場の花札ローグライク", Rect2(lx, top, w, 40), 26, UiStyle.GOLD)
	var logo := _text("こんこん\n花札道中", Rect2(lx, top + 40, w, 260), 96, Color.WHITE)
	logo.add_theme_constant_override("line_spacing", -14)
	UiStyle.outline(logo, 18)
	logo.add_theme_color_override("font_outline_color", UiStyle.SHU.darkened(0.5))
	_text("〜小狐と、あぶらあげ奪還の一夜〜", Rect2(lx, top + 300, w, 40), 26, Color(1, 0.9, 0.8))
	var by := top + 370
	var bw := 300.0
	var btns := [["はじめる  [Space]", _new_run], ["あらすじ", func(): _set_state(STORY)],
		["遊び方・役の一覧", func(): _set_state(HOWTO)], ["音  " + ("OFF" if Audio.muted else "ON") + "  [M]", func(): Audio.toggle_mute(); _build()]]
	if p:
		by = v.y - 420
		bw = v.x - 160
		lx = 80
	for i in btns.size():
		var b := _button(btns[i][0], btns[i][1], 28 if i == 0 else 24)
		_place(b, Rect2(lx, by + i * 76, bw, 64 if i == 0 else 58))
	var ver := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	_text("build " + (ver if ver != "" else "dev") + "   画像は生成AIで作成しています", Rect2(16, v.y - 34, v.x - 32, 30), 16, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)


func _build_text_page(title: String, body: String, with_table: bool) -> void:
	_set_bg("bg_den", 0.75)
	var v := _view()
	_text(title, Rect2(0, 24, v.x, 60), 44, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var area := Rect2(40, 100, v.x - 80, v.y - 200)
	_panel(area)
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
	var b := _button("もどる  [Space]", func(): _set_state(TITLE), 26)
	_place(b, Rect2(v.x / 2 - 150, v.y - 84, 300, 60))


# ───────────────────────── ラン ─────────────────────────

func _new_run() -> void:
	run = Run.new()
	_set_state(INTRO)


## 場の前：宿場の名前・目標・親分の決まりを見せる
func _build_intro() -> void:
	var boss := run.boss_id()
	_set_bg("bg_den", 0.55)
	Audio.bgm("boss" if boss != "" else "den")
	var v := _view()
	var p := Screen.portrait
	var w := 760.0 if not p else v.x - 40
	var box := Rect2((v.x - w) / 2, 40 if not p else 80, w, 380 if boss == "" else 460)
	_panel(box, UiStyle.MULT if boss != "" else UiStyle.GOLD)
	_text(Rules.STAGE_NAMES[run.stage], Rect2(box.position + Vector2(0, 16), Vector2(w, 44)), 34, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_text("%s（%d / 9 戦目）" % [Rules.ROUND_NAMES[run.bout], run.stage * 3 + run.bout + 1],
		Rect2(box.position + Vector2(0, 66), Vector2(w, 40)), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_text("目標  %s 点" % _num(run.target()), Rect2(box.position + Vector2(0, 116), Vector2(w, 60)), 48, UiStyle.MULT, HORIZONTAL_ALIGNMENT_CENTER)
	_text("勝てば %d文＋α　／　出す %d回・捨てる %d回" % [Rules.ROUND_REWARD[run.bout], _preview_plays(), _preview_discards()],
		Rect2(box.position + Vector2(0, 186), Vector2(w, 40)), 22, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	if boss != "":
		_picture("boss_" + boss, Rect2(box.position + Vector2(30, 230), Vector2(200, 200)))
		_text(Rules.BOSSES[boss][0], Rect2(box.position + Vector2(250, 240), Vector2(w - 280, 40)), 30, UiStyle.GOLD)
		_text(Rules.BOSSES[boss][1], Rect2(box.position + Vector2(250, 290), Vector2(w - 280, 130)), 26, Color.WHITE)
	var b := _button("勝負！  [Space]", _start_bout, 32)
	_place(b, Rect2(v.x / 2 - 160, box.end.y + 24, 320, 70))
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
	if run.boss_id() == "tamamo":
		n -= 1
	return max(n, 1)


func _preview_discards() -> int:
	if run.boss_id() == "kurobo":
		return 0
	return Rules.DISCARDS + (2 if run.has_charm("yukionna") else 0)


func _start_bout() -> void:
	run.start_round()
	_set_state(PLAY)
	Audio.sfx("shuffle")


# ───────────────────────── 勝負の画面 ─────────────────────────

func _build_play() -> void:
	_set_bg("bg_den", 0.45)
	Audio.bgm("boss" if run.boss_id() != "" else "den")
	var u := _ui
	u.info = _panel(Rect2())
	u.stage = _text("", Rect2(), 22, UiStyle.GOLD)
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
	u.deck = _button("", _show_deck, 18, Color(0.3, 0.3, 0.4))
	var boss := run.boss_id()
	if boss != "":
		u.boss_pic = _picture("boss_" + boss, Rect2())
		u.boss_rule = _text(Rules.BOSSES[boss][1], Rect2(), 18, Color(1, 0.8, 0.75))
	u.kon = _picture("kon_normal", Rect2())
	u.bubble = _panel(Rect2(), Color.WHITE, Color(1, 1, 1, 0.95))
	u.bubble_text = _text("", Rect2(), 20, Color(0.1, 0.05, 0.05), HORIZONTAL_ALIGNMENT_LEFT)
	u.bubble_text.add_theme_constant_override("outline_size", 0)
	u.bubble.visible = false
	u.bubble_text.visible = false
	# 形と点の箱
	u.form = _text("", Rect2(), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.chips_box = _panel(Rect2(), UiStyle.AI, Color(0.05, 0.1, 0.25, 0.92))
	u.chips = _text("0", Rect2(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.x = _text("×", Rect2(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.mult_box = _panel(Rect2(), UiStyle.MULT, Color(0.25, 0.05, 0.05, 0.92))
	u.mult = _text("0", Rect2(), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	u.total = _text("", Rect2(), 56, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	# 式神
	for i in Rules.MAX_CHARMS:
		var slot := _charm_slot(i)
		_charm_views.append(slot)
	u.tip = _text("", Rect2(), 20, Color(1, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	# ボタン
	u.sort = _button("並べ替え", _toggle_sort, 22, Color(0.3, 0.3, 0.4))
	u.discard = _button("捨てる", _discard, 28, Color(0.25, 0.35, 0.7))
	u.play = _button("出す", _play, 32)
	u.help = _button("役", _show_help, 24, Color(0.3, 0.3, 0.4))
	for c in run.hand:
		_add_view(c)
	_layout_play()
	_refresh()
	_update_preview()


func _charm_slot(i: int) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
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
		"kasha": return "（今 +%d）" % ch.get("counter", 0)
		"kyubi": return "（今 ×%.2f）" % (1.0 + 0.25 * ch.get("counter", 0))
	return ""


func _add_view(c: Dictionary) -> CardView:
	var cv := CardView.new(c)
	cv.tapped.connect(_toggle)
	_screen.add_child(cv)
	_views.append(cv)
	return cv


## 画面の大きさから各部品の位置を決める
func _layout_play() -> void:
	var u := _ui
	var v := _view()
	var p := Screen.portrait
	var cw := 104.0
	if p:
		var info := Rect2(12, 12, v.x - 24, 210)
		_place(u.info, info)
		_place(u.stage, Rect2(30, 22, 440, 30))
		_place(u.target, Rect2(30, 54, 440, 34))
		_place(u.score, Rect2(30, 84, 440, 56))
		_place(u.bar_bg, Rect2(30, 144, 440, 14))
		_place(u.counts, Rect2(30, 166, 470, 34))
		_place(u.money, Rect2(30, 166, 660, 34))
		u.money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_place(u.kon, Rect2(v.x - 210, 14, 190, 190))
		if u.has("boss_pic"):
			_place(u.boss_pic, Rect2(v.x - 330, 20, 120, 120))
			_place(u.boss_rule, Rect2(30, 228, v.x - 60, 30))
		var cy := 270.0
		var sw := (v.x - 24 - 4 * 8) / 5.0
		for i in _charm_views.size():
			_place(_charm_views[i], Rect2(12 + i * (sw + 8), cy, sw, 76))
		_place(u.tip, Rect2(12, cy + 82, v.x - 24, 30))
		# 縦長の画面では余った高さを札の間に配る
		var by := v.y - 110
		var hand_y := by - cw * 1.55 - 40
		var fy: float = lerp(400.0, hand_y - 420, 0.5)
		_place(u.form, Rect2(0, fy, v.x, 44))
		_place(u.chips_box, Rect2(v.x / 2 - 230, fy + 50, 200, 70))
		_place(u.x, Rect2(v.x / 2 - 30, fy + 56, 60, 60))
		_place(u.mult_box, Rect2(v.x / 2 + 30, fy + 50, 200, 70))
		u.play_area = Rect2(20, fy + 150, v.x - 40, cw * 1.55)
		_place(u.total, Rect2(0, fy + 150 + cw * 1.55 + 10, v.x, 70))
		u.hand_area = Rect2(12, hand_y, v.x - 24, cw * 1.55)
		_place(u.sort, Rect2(16, by, 150, 80))
		_place(u.discard, Rect2(180, by, 170, 80))
		_place(u.play, Rect2(364, by, 220, 80))
		_place(u.help, Rect2(598, by, 106, 80))
		_place(u.deck, Rect2(v.x - 260, by - 50, 244, 42))
		_place(u.bubble, Rect2(v.x - 470, 150, 300, 90))
	else:
		var info := Rect2(12, 12, 300, v.y - 24)
		_place(u.info, info)
		_place(u.stage, Rect2(28, 24, 270, 60))
		_place(u.target, Rect2(28, 84, 270, 34))
		_place(u.score, Rect2(28, 114, 270, 56))
		_place(u.bar_bg, Rect2(28, 174, 268, 14))
		_place(u.counts, Rect2(28, 198, 270, 70))
		_place(u.money, Rect2(28, 268, 270, 36))
		u.money.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if u.has("boss_pic"):
			_place(u.boss_pic, Rect2(28, 340, 90, 90))
			_place(u.boss_rule, Rect2(122, 340, 180, 100))
		_place(u.kon, Rect2(20, v.y - 270, 260, 260))
		_place(u.deck, Rect2(28, 300, 268, 36))
		var x0 := 330.0
		var aw := v.x - x0 - 16
		var sw := (aw - 4 * 10) / 5.0
		for i in _charm_views.size():
			_place(_charm_views[i], Rect2(x0 + i * (sw + 10), 14, sw, 70))
		_place(u.tip, Rect2(x0, 88, aw, 30))
		var cx := x0 + aw / 2
		_place(u.form, Rect2(x0, 120, aw, 44))
		_place(u.chips_box, Rect2(cx - 230, 166, 190, 64))
		_place(u.x, Rect2(cx - 30, 168, 60, 60))
		_place(u.mult_box, Rect2(cx + 40, 166, 190, 64))
		u.play_area = Rect2(x0, 250, aw, cw * 1.55)
		_place(u.total, Rect2(x0, 250 + cw * 0.5, aw, 70))
		u.hand_area = Rect2(x0, 450, aw, cw * 1.55)
		var by := v.y - 84
		_place(u.sort, Rect2(x0, by, 150, 66))
		_place(u.help, Rect2(x0 + 160, by, 90, 66))
		_place(u.discard, Rect2(cx - 40, by, 180, 66))
		_place(u.play, Rect2(cx + 150, by, 220, 66))
		_place(u.bubble, Rect2(250, v.y - 250, 300, 90))
	_place(u.chips, Rect2(u.chips_box.position, u.chips_box.size - Vector2(0, 6)))
	_place(u.mult, Rect2(u.mult_box.position, u.mult_box.size - Vector2(0, 6)))
	_place(u.bubble_text, u.bubble.get_rect().grow(-12))
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
	u.stage.text = "%s\n%s" % [Rules.STAGE_NAMES[run.stage], Rules.ROUND_NAMES[run.bout]] if not Screen.portrait \
		else "%s ・ %s" % [Rules.STAGE_NAMES[run.stage], Rules.ROUND_NAMES[run.bout]]
	u.target.text = "目標 %s 点" % _num(run.target())
	u.score.text = _num(run.score)
	u.counts.text = ("出す 残り%d回\n捨てる 残り%d回" if not Screen.portrait else "出す %d回 / 捨てる %d回") % [run.plays_left, run.discards_left]
	u.money.text = "%d 文" % run.money
	u.deck.text = "山札 %d / %d枚  ▶見る" % [run.draw_pile.size(), run.deck.size()]
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
		"kasha": return "\n+%d" % ch.get("counter", 0)
		"kyubi": return "\n×%.2f" % (1.0 + 0.25 * ch.get("counter", 0))
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
	_ui.play.disabled = busy or n == 0
	_ui.discard.disabled = busy or n == 0 or run.discards_left <= 0
	_ui.play.text = "出す (%d)" % run.plays_left
	_ui.discard.text = "捨てる (%d)" % run.discards_left


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
		_say("5枚までだよ！")
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


## 選んでいる札でできる形を前もって見せる
func _update_preview() -> void:
	var sel := _selected()
	_ui.total.text = ""
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
	busy = true
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
	# 玉藻の幻術：手札が消える
	if run.boss_id() == "tamamo":
		for cv in _views:
			var tw := create_tween()
			tw.tween_property(cv, "modulate:a", 0.0, 0.3)
			tw.tween_callback(cv.queue_free)
		_views.clear()
		_float_text("幻術！", _ui.hand_area.get_center(), Color(0.8, 0.5, 1.0), 48)
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
	_refresh()
	_update_preview()
	if run.won():
		_round_won()
	elif run.lost():
		_game_over()
	elif run.plays_left == 1 and run.score < run.target():
		_say(Scenario.pick(Scenario.SAY_DANGER), "panic")


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
	elif r.total < run.target() * 0.12:
		_say(Scenario.pick(Scenario.SAY_SMALL), "panic")


## コンの吹き出し
func _say(text: String, mood: String = "normal") -> void:
	if not _ui.has("bubble"):
		return
	_ui.bubble.visible = true
	_ui.bubble_text.visible = true
	_ui.bubble_text.text = text
	_ui.kon.texture = tex("kon_" + mood)
	_pop(_ui.bubble)
	if _kon_tween:
		_kon_tween.kill()
	_kon_tween = create_tween()
	_kon_tween.tween_interval(2.6)
	_kon_tween.tween_callback(func():
		if _ui.has("bubble"):
			_ui.bubble.visible = false
			_ui.bubble_text.visible = false
			_ui.kon.texture = tex("kon_normal"))


func _round_won() -> void:
	busy = true
	Audio.jingle("win")
	_banner("勝ち！", UiStyle.GOLD, 96)
	_ui.kon.texture = tex("kon_happy")
	await _wait(1.6)
	busy = false
	_payout = run.payout()
	_set_state(PAYOUT)


func _game_over() -> void:
	busy = true
	Audio.jingle("lose")
	_banner("あと %s 点…" % _num(run.target() - run.score), UiStyle.MULT, 64)
	_ui.kon.texture = tex("kon_panic")
	await _wait(2.0)
	busy = false
	_set_state(GAMEOVER)


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


func _banner(text: String, color: Color, fsize: int = 72) -> void:
	var v := _view()
	var l := UiStyle.label(text, fsize, color, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(v.x, fsize + 30)
	l.position = Vector2(0, v.y * 0.38)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.3, 0.3)
	_fx.add_child(l)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


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
	_set_bg("bg_den", 0.6)
	var v := _view()
	var w := 600.0 if not Screen.portrait else v.x - 60
	var box := Rect2((v.x - w) / 2, 80, w, 120 + _payout.size() * 54 + 90)
	_panel(box)
	_text("稼ぎ", Rect2(box.position + Vector2(0, 16), Vector2(w, 50)), 40, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var sum := 0
	for i in _payout.size():
		var row: Array = _payout[i]
		sum += row[1]
		var y := box.position.y + 90 + i * 54
		var a := _text(row[0], Rect2(box.position.x + 30, y, w - 200, 44), 26)
		var b := _text("+%d文" % row[1], Rect2(box.end.x - 180, y, 150, 44), 28, UiStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
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
	if _talk_lines.is_empty() and not last:
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
	_shop_msg = "いらっしゃい！ 妖怪の夜市だよ！"
	_set_state(SHOP)


func _build_shop() -> void:
	_set_bg("bg_shop", 0.45)
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
	var kr := Rect2(10, v.y - 330, 280, 280) if not p else Rect2(v.x - 230, 80, 210, 210)
	_picture("kon_smug", kr)
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
		var b := _button("%s\n売る %d文" % [Rules.CHARMS[ch.id][0], run.sell_price(ch.id)], _sell.bind(i), 18, Color(0.35, 0.2, 0.45))
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
	var rr := _button("品物を入れ替える (%d文)" % _reroll_cost, _reroll, 22, Color(0.25, 0.35, 0.7))
	rr.disabled = run.money < _reroll_cost
	var nb := _button("次の場へ  →", _leave_shop, 28)
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
	var b := _button("", _buy.bind(i), 20, col)
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
			_shop_msg = Scenario.CHARM_QUIPS.get(o.id, "ゲット！") + "\nギン「" + Scenario.pick(Scenario.BUY_REPLY)[1] + "」"
		"scroll":
			run.money -= o.price
			run.form_levels[o.id] = run.form_levels.get(o.id, 0) + 1
			_shop_msg = "%sが強くなった！ 巻物って読むと強くなるんだね！\nギン「読んでないだろ」" % Rules.form_def(o.id)[1]
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
	_shop_msg = "%sさん、今までありがとう！\nギン「売った金で何を買う気だ」" % Rules.CHARMS[id][0]
	Audio.sfx("coin")
	_build()


func _reroll() -> void:
	if run.money < _reroll_cost:
		return
	run.money -= _reroll_cost
	_reroll_cost += 1
	_offers = run.shop_offers()
	_shop_msg = "新しい品物、入りました〜！"
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
			_shop_msg = "%sに%sを使った！\nギン「…札が喜んでいる気がする」" % [Cards.label(view.card), Rules.TALISMANS[tid][0]]
			_close_overlay()
			_build())
		_overlay.add_child(cv)


## 山札の中身：まだ引いていない札は明るく、使った札は暗く
func _show_deck() -> void:
	_close_overlay()
	var v := _view()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.03, 0.01, 0.02, 0.96)
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
	UiStyle.button_styles(b)
	b.position = Vector2(v.x / 2 - 130, v.y - 86)
	b.size = Vector2(260, 64)
	b.pressed.connect(_close_overlay)
	_overlay.add_child(b)


func _show_help() -> void:
	_close_overlay()
	var v := _view()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.85)
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
	vb.add_child(UiStyle.label("札1枚のチップ：光15 / タネ8 / 短冊6 / カス3　金箔は倍率+3", 22))
	var b := Button.new()
	b.text = "閉じる [Esc]"
	b.add_theme_font_size_override("font_size", 26)
	UiStyle.button_styles(b)
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
		_set_bg("bg_den", 0.7)
	var w := 720.0 if not p else v.x - 40
	var box := Rect2((v.x - w) / 2, 40, w, 460)
	_panel(box, UiStyle.GOLD if clear else UiStyle.MULT)
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
	_picture("kon_happy" if clear else "kon_panic", Rect2(box.end.x - 200, box.end.y - 200, 190, 190))
	var b := _button("タイトルへ  [Space]", func(): _set_state(TITLE), 28)
	_place(b, Rect2(v.x / 2 - 170, box.end.y + 30, 340, 70))
	if _talk_lines.is_empty():
		if clear:
			Audio.jingle("clear")
			_talk(Scenario.CLEAR_TALK, Callable(), "tamamo")
		else:
			_talk(Scenario.pick(Scenario.GAMEOVER_TALKS))

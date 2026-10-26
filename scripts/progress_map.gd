class_name ProgressMap
extends Control

## 道中すごろく：全9戦のどこにいるかを、宿場ごとに3つずつ並んだ丸で見せる。
## 親分の丸には親分のミニキャラ、今いる丸には跳ねるコンを描く（big = 場の前の大きい版）。

var run: Run
var big := false
var _t := 0.0
## コンが前の丸から今の丸へ跳んでいく途中（0→1）
var walk := 1.0


func _init(r: Run, is_big: bool = false) -> void:
	run = r
	big = is_big
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func node_pos(i: int) -> Vector2:
	# 宿場の間は少し広く空ける
	var gap := 0.6
	var units := 8 + gap * 2
	var step := size.x / (units + 1.0)
	var x := step * (0.5 + i + gap * (i / 3)) + step * 0.5
	return Vector2(x, size.y * (0.62 if big else 0.5))


func _draw() -> void:
	var cur := run.stage * 3 + run.bout
	var font := get_theme_default_font()
	var r := size.y * (0.13 if big else 0.28)
	# 道
	for i in 8:
		var a := node_pos(i)
		var b := node_pos(i + 1)
		var col := UiStyle.GOLD if i < cur else Color(1, 1, 1, 0.25)
		draw_line(a, b, col, 3.0 if big else 2.0)
	for i in 9:
		var p := node_pos(i)
		var boss := i % 3 == 2
		var rr := r * (1.3 if boss else 1.0)
		var done := i < cur
		var now := i == cur
		var fill := Color(0.12, 0.08, 0.1)
		if done:
			fill = UiStyle.GOLD.darkened(0.2)
		elif now:
			fill = UiStyle.SHU.lightened(0.15 + 0.15 * sin(_t * 5.0))
		draw_circle(p, rr + 2, Color(0, 0, 0, 0.6))
		draw_circle(p, rr, fill)
		draw_arc(p, rr, 0, TAU, 32, UiStyle.GOLD if (done or now or boss) else Color(1, 1, 1, 0.4), 2.0, true)
		var mark := "✓" if done else ("親" if boss else str(i % 3 + 1))
		if i == 8 and not done:
			mark = "九"
		var fs := int(rr * 1.1)
		draw_string(font, p + Vector2(-rr, fs * 0.36), mark, HORIZONTAL_ALIGNMENT_CENTER, rr * 2, fs,
			Color(0.1, 0.05, 0.05) if done else Color.WHITE)
		# 親分のミニキャラ
		if big and boss:
			var tex := MiniChar.sheet(run.bosses[i / 3])
			if tex:
				var w := size.y * 0.5
				var m := Color(1, 1, 1, 0.5) if done else Color.WHITE
				draw_texture_rect_region(tex, Rect2(p + Vector2(-w / 2, -rr - w + 4), Vector2(w, w)),
					Rect2((MiniChar.PANIC if done else MiniChar.IDLE) * MiniChar.CELL, 0, MiniChar.CELL, MiniChar.CELL), m)
	if big:
		for s in 3:
			var c := (node_pos(s * 3) + node_pos(s * 3 + 2)) / 2
			var nm: String = Rules.STAGE_NAMES[s]
			draw_string(font, Vector2(c.x - 150, size.y - 4), nm, HORIZONTAL_ALIGNMENT_CENTER, 300, 18,
				UiStyle.GOLD if s == run.stage else Color(1, 1, 1, 0.55))
	# コン（前の丸から今の丸へ跳んでくる）。小さい版は丸の色だけで示す
	var kon := MiniChar.sheet("kon")
	if big and kon and cur < 9:
		var w := size.y * 0.5
		var p := node_pos(max(cur - 1, 0)).lerp(node_pos(cur), walk)
		var hop: float = abs(sin(_t * 4.0)) * w * 0.06 + sin(walk * PI) * w * 0.5
		var base := p + Vector2(0, -r * 1.3 - hop)
		if cur % 3 == 2:
			base.x -= w * 0.6  # 親分と重ならないよう左に立つ
		draw_texture_rect_region(kon, Rect2(base + Vector2(-w / 2, -w + 6), Vector2(w, w)),
			Rect2((MiniChar.HAPPY if walk < 1.0 else MiniChar.IDLE) * MiniChar.CELL, 0, MiniChar.CELL, MiniChar.CELL))

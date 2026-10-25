class_name UiStyle

## 見た目の共通設定。黒漆に金のふち、朱色を差し色にした和風。

const GOLD := Color(1.0, 0.82, 0.35)
const SHU := Color(0.9, 0.27, 0.18)       # 朱色
const AI := Color(0.35, 0.6, 1.0)         # 藍（チップの色）
const MULT := Color(1.0, 0.38, 0.32)      # 倍率の色
const PANEL_BG := Color(0.08, 0.04, 0.05, 0.86)
const PAPER := Color(0.98, 0.95, 0.86)


## 金のふちと、外側にうっすら光る影を持つ角丸パネル
static func panel(edge: Color = GOLD, bg: Color = PANEL_BG, glow: int = 8, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(edge, 0.35)
	sb.shadow_size = glow
	sb.anti_aliasing = true
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func button_styles(b: Button, main: Color = SHU) -> void:
	b.add_theme_stylebox_override("normal", panel(GOLD, Color(main.darkened(0.35), 0.97), 4, 12))
	b.add_theme_stylebox_override("hover", panel(Color.WHITE, Color(main.darkened(0.15), 0.97), 10, 12))
	b.add_theme_stylebox_override("pressed", panel(GOLD, Color(main.darkened(0.55), 0.97), 2, 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", panel(Color(0.4, 0.35, 0.3), Color(0.12, 0.1, 0.1, 0.9), 0, 12))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.45))


## 文字に黒いふち取りを付けて、派手な背景の上でも読めるようにする
static func outline(l: Control, size: int = 8) -> void:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.03, 0.95))


static func label(text: String, size: int, color: Color = Color.WHITE, ol: int = 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	outline(l, ol)
	return l

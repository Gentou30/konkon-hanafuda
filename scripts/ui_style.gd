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


## 漆塗りの札のボタン（assets/images/ui/btn_<skin>.png を9分割で伸ばす）。skin: red / blue / gray / purple / green
## 高さ 50px 未満のボタンでは角の飾りがつぶれるので、button_styles を使う
static func tex_button(b: Button, skin: String = "red") -> void:
	var t: Texture2D = load("res://assets/images/ui/btn_%s.png" % skin)
	var gray: Texture2D = load("res://assets/images/ui/btn_gray.png")
	b.add_theme_stylebox_override("normal", _tex_box(t, Color.WHITE))
	b.add_theme_stylebox_override("hover", _tex_box(t, Color(1.25, 1.2, 1.1)))
	b.add_theme_stylebox_override("pressed", _tex_box(t, Color(0.75, 0.7, 0.7)))
	b.add_theme_stylebox_override("disabled", _tex_box(gray, Color(0.55, 0.55, 0.55, 0.9)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.75))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.7, 0.68, 0.65))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.03, 0.02, 0.9))


static func _tex_box(t: Texture2D, mod: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = 30
	sb.texture_margin_right = 30
	sb.texture_margin_top = 22
	sb.texture_margin_bottom = 22
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.modulate_color = mod
	return sb


## 黒漆に金具の付いた大きいパネル
## small: 角の金具が小さい版（細い枠用）
static func tex_panel(alpha: float = 0.95, small: bool = false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/images/ui/panel_s.png" if small else "res://assets/images/ui/panel.png")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 27 if small else 46)
		sb.set_content_margin(side, 16)
	sb.modulate_color = Color(1, 1, 1, alpha)
	return sb

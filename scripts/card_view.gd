class_name CardView
extends Control

## 花札1枚の見た目。絵（assets/images/cards/<art>.png）の上に、月と種類の札を重ねて読みやすくする。
## 絵が無い月は色と漢字だけで描く。

signal tapped(view: CardView)

const KIND_COLORS := [Color(0.45, 0.42, 0.4), Color(0.85, 0.2, 0.2), Color(0.2, 0.6, 0.3), Color(0.95, 0.7, 0.1)]
const MONTH_COLORS := [Color.BLACK, Color(0.2, 0.5, 0.3), Color(0.85, 0.3, 0.4), Color(0.95, 0.6, 0.7), Color(0.55, 0.4, 0.8),
	Color(0.35, 0.35, 0.8), Color(0.85, 0.2, 0.3), Color(0.75, 0.35, 0.45), Color(0.6, 0.55, 0.3), Color(0.9, 0.7, 0.2),
	Color(0.85, 0.3, 0.1), Color(0.3, 0.45, 0.35), Color(0.5, 0.35, 0.6)]

static var _tex_cache := {}

var card: Dictionary
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var face_down := false
var hovered := false
var interactive := true


func _init(c: Dictionary = {}) -> void:
	card = c
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func(): pivot_offset = size / 2)
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())


static func texture_for(art: String) -> Texture2D:
	if not _tex_cache.has(art):
		var p := "res://assets/images/cards/%s.png" % art
		_tex_cache[art] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[art]


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		tapped.emit(self)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := size.x * 0.08
	var font := get_theme_default_font()
	# 影
	draw_style_box(_box(Color(0, 0, 0, 0.45), Color.TRANSPARENT, 0, rad), Rect2(Vector2(3, 5), size))
	if face_down:
		draw_style_box(_box(Color(0.55, 0.1, 0.1), UiStyle.GOLD, 3, rad), r)
		draw_string(font, Vector2(0, size.y * 0.58), "狐", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.45), Color(1, 0.85, 0.5, 0.8))
		return
	var tex := texture_for(card.art)
	var inner := r.grow(-size.x * 0.06)
	if tex:
		# 絵に札のふちまで描いてある
		draw_texture_rect(tex, r, false)
		if card.gold:
			draw_style_box(_box(Color(1, 0.85, 0.3, 0.12), UiStyle.GOLD, 5, rad), r)
	else:
		draw_style_box(_box(UiStyle.PAPER, Color(0.15, 0.1, 0.08), 2, rad), r)
		draw_rect(inner, MONTH_COLORS[card.month].darkened(0.1))
		draw_string(font, Vector2(inner.position.x, inner.get_center().y + size.x * 0.18), Cards.MONTH_NAMES[card.month],
			HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, int(size.x * 0.36), Color(1, 1, 1, 0.9))
	# 月（左上）
	var fs := int(size.x * 0.18)
	var badge := Rect2(Vector2(2, 2), Vector2(fs * (2.4 if card.month >= 10 else 1.9), fs * 1.35))
	draw_style_box(_box(Color(0.08, 0.04, 0.05, 0.85), Color(1, 1, 1, 0.5), 1, fs * 0.3), badge)
	draw_string(font, badge.position + Vector2(0, fs * 1.05), "%d月" % card.month, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, fs, Color.WHITE)
	# 種類（下）
	var kc: Color = KIND_COLORS[card.kind]
	if card.kind == Cards.KIND_TAN and card.tags.has("ao"):
		kc = Color(0.2, 0.35, 0.9)
	var kb := Rect2(Vector2(size.x * 0.12, size.y - fs * 1.55), Vector2(size.x * 0.76, fs * 1.4))
	draw_style_box(_box(kc, Color(1, 1, 1, 0.8), 2, fs * 0.5), kb)
	var kname: String = Cards.KIND_NAMES[card.kind]
	if card.tags.has("aka"):
		kname = "赤短"
	elif card.tags.has("ao"):
		kname = "青短"
	draw_string(font, kb.position + Vector2(0, fs * 1.08), kname, HORIZONTAL_ALIGNMENT_CENTER, kb.size.x, fs, Color.WHITE)
	if card.bonus > 0:
		draw_string(font, Vector2(0, size.y - fs * 1.8), "+%d" % card.bonus, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, int(fs * 0.9), UiStyle.AI)
	if selected:
		draw_style_box(_box(Color.TRANSPARENT, UiStyle.GOLD, 5, rad), r.grow(3))
	elif hovered and interactive:
		draw_style_box(_box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.8), 2, rad), r)


func _box(bg: Color, border: Color, bw: int, rad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	return sb

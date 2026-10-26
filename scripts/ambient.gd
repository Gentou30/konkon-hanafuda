class_name Ambient
extends Node2D

## 背景の上を舞う粒（leaf 紅葉 / petal 花びら / wisp 狐火）。
## CPUParticles2D は Web の描画で色や形が崩れることがあったので、自前で数十枚を描く。

var kind := ""
var area := Vector2(1280, 720)
var _tex: Texture2D
var _bits := []  # [{pos, vel, rot, spin, scale, phase, life}]


func setup(k: String, view: Vector2) -> void:
	kind = k
	area = view
	_tex = load("res://assets/images/ui/fx_%s.png" % k) if k != "" else null
	_bits.clear()
	var n: int = {"leaf": 18, "petal": 26, "wisp": 12}.get(k, 0)
	for i in n:
		_bits.append(_spawn(true))


func resize(view: Vector2) -> void:
	area = view


func _spawn(anywhere: bool) -> Dictionary:
	var b := {"rot": randf() * TAU, "spin": randf_range(-2.0, 2.0), "phase": randf() * TAU, "life": 0.0}
	match kind:
		"wisp":
			b.pos = Vector2(randf() * area.x, area.y * randf() if anywhere else area.y + 30)
			b.vel = Vector2(randf_range(-6, 6), randf_range(-30, -12))
			b.scale = randf_range(0.4, 1.0)
		_:
			b.pos = Vector2(randf() * (area.x + 200), area.y * randf() if anywhere else -30.0)
			b.vel = Vector2(randf_range(-30, -10), randf_range(30, 70))
			b.scale = randf_range(0.25, 0.5) if kind == "leaf" else randf_range(0.18, 0.32)
	return b


func _process(delta: float) -> void:
	if _tex == null:
		return
	for i in _bits.size():
		var b: Dictionary = _bits[i]
		b.life += delta
		# ひらひら（横に揺れる）
		var sway := sin(b.life * 1.6 + b.phase) * (20.0 if kind != "wisp" else 8.0)
		b.pos += (b.vel + Vector2(sway, 0)) * delta
		b.rot += b.spin * delta
		if b.pos.y > area.y + 40 or b.pos.y < -60 or b.pos.x < -60:
			_bits[i] = _spawn(false)
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var s := _tex.get_size()
	for b in _bits:
		var a := 0.85
		if kind == "wisp":
			# 狐火は明滅しながら上っていく
			a = clamp(0.4 + 0.4 * sin(b.life * 2.0 + b.phase), 0.1, 0.8)
		draw_set_transform(b.pos, b.rot if kind != "wisp" else 0.0, Vector2.ONE * b.scale)
		draw_texture(_tex, -s / 2, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO)

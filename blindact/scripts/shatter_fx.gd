class_name ShatterFX
extends Control
## Breaks the current frame like glass: cracks run out from the impact point,
## then the picture falls apart into triangular shards that fly outwards,
## spin and drop into the dark. Call shatter() with a screenshot texture.

signal finished

var _shards: Array = []        # [Polygon2D, vel, spin, delay]
var _cracks: Array = []        # polylines in screen space
var _t := 0.0
var _phase := ""               # crack | fly
var _impact := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func shatter(tex: Texture2D, impact_frac := Vector2(0.5, 0.45)) -> void:
	var sz := size
	_impact = impact_frac * sz
	# points: dense near the impact, sparse at the edges, plus the border
	var pts := PackedVector2Array()
	pts.append_array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)])
	for i in 9:
		pts.append(Vector2(sz.x * float(i + 1) / 10.0, 0.0))
		pts.append(Vector2(sz.x * float(i + 1) / 10.0, sz.y))
	for i in 5:
		pts.append(Vector2(0.0, sz.y * float(i + 1) / 6.0))
		pts.append(Vector2(sz.x, sz.y * float(i + 1) / 6.0))
	for i in 150:
		var r := pow(_rng.randf(), 1.8) * sz.length() * 0.6
		var a := _rng.randf() * TAU
		var p := _impact + Vector2(cos(a), sin(a)) * r
		if Rect2(Vector2.ZERO, sz).has_point(p):
			pts.append(p)
	pts.append(_impact)
	var tris := Geometry2D.triangulate_delaunay(pts)
	for k in range(0, tris.size(), 3):
		var a := pts[tris[k]]
		var b := pts[tris[k + 1]]
		var c := pts[tris[k + 2]]
		var cen := (a + b + c) / 3.0
		var poly := Polygon2D.new()
		poly.texture = tex
		poly.polygon = PackedVector2Array([a - cen, b - cen, c - cen])
		var ts := tex.get_size()
		poly.uv = PackedVector2Array([a / sz * ts, b / sz * ts, c / sz * ts])
		poly.position = cen
		add_child(poly)
		var away := (cen - _impact)
		var dist := away.length()
		var dir := away / maxf(dist, 1.0)
		var speed := lerpf(900.0, 160.0, clampf(dist / (sz.length() * 0.6), 0.0, 1.0)) * _rng.randf_range(0.7, 1.3)
		_shards.append([poly, dir * speed, _rng.randf_range(-6.0, 6.0), dist / 2600.0])
	# cracks radiating from the impact
	for i in 14:
		var a := TAU * float(i) / 14.0 + _rng.randf_range(-0.2, 0.2)
		var line := PackedVector2Array([_impact])
		var p := _impact
		var ln := _rng.randf_range(0.25, 0.7) * sz.length()
		var steps := 12
		for s in steps:
			a += _rng.randf_range(-0.25, 0.25)
			p += Vector2(cos(a), sin(a)) * ln / steps
			line.append(p)
		_cracks.append(line)
	_phase = "crack"
	_t = 0.0


func _process(delta: float) -> void:
	if _phase == "":
		return
	_t += delta
	if _phase == "crack":
		queue_redraw()
		if _t > 0.32:
			_phase = "fly"
			_t = 0.0
		return
	queue_redraw()
	var alive := 0
	for s: Array in _shards:
		var poly: Polygon2D = s[0]
		if _t < float(s[3]):
			alive += 1
			continue
		var v: Vector2 = s[1]
		v.y += 1400.0 * delta
		s[1] = v
		poly.position += v * delta
		poly.rotation += float(s[2]) * delta
		poly.scale *= 1.0 - 0.25 * delta
		poly.modulate = Color(1, 1, 1, clampf(1.0 - (_t - float(s[3])) / 1.3, 0.0, 1.0))
		if poly.modulate.a > 0.01:
			alive += 1
	if alive == 0 or _t > 2.2:
		_phase = ""
		finished.emit()


func _draw() -> void:
	if _phase == "crack":
		var k := clampf(_t / 0.3, 0.0, 1.0)
		for line: PackedVector2Array in _cracks:
			var n := maxi(2, int(line.size() * k))
			draw_polyline(line.slice(0, n), Color(1.0, 0.92, 0.9, 0.85), 2.0, true)
		draw_circle(_impact, 6.0 + 20.0 * k, Color(1, 1, 1, 0.25 * (1.0 - k)))

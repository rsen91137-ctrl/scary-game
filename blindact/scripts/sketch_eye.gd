class_name SketchEye
extends Control
## The pre-game background: the owner's sketch of an eye, redrawn as a
## creepy hand-drawn red ink animation. Every stroke is regenerated a dozen
## times a second with fresh jitter ("line boil"), the lines are doubled and
## overshoot like a nervous hand, the pupil is a scribbled blot, vessels
## scratch in from the corners and ink tears run down from the lower lid.
## The director drives the public fields; post effects (glow, stretch, blur,
## shake, grain) are done by shaders/sketch_post.gdshader on top.

const INK := Color(0.72, 0.05, 0.04)
const INK_DARK := Color(0.32, 0.01, 0.01)
const INK_PALE := Color(0.9, 0.55, 0.5)

# lid geometry in eye units (iris radius 0.5), from the sketch
const X_L := -2.0
const Y_L := 0.07
const X_R := 1.35
const Y_R := -0.25

var center := Vector2(0.56, 0.40)      # screen fraction of the iris centre
var unit := 0.25                       # screen heights per eye unit
var gaze := Vector2.ZERO               # iris offset in eye units
var gaze_target := Vector2.ZERO
var pupil := 0.42                      # 0..1
var pupil_target := 0.42
var blink := 0.0
var wide := 0.0
var tremble := 0.0                     # 0..1 extra boil / shake
var bleed := 0.0                       # 0..1 ink tears
var scribble := 0.0                    # 0..1 violent scratching over the eye
var veins := 0.6                       # 0..1
var boil_fps := 11.0
var alpha := 1.0

var _seed := 1
var _boil_t := 0.0
var _t := 0.0
var _blink_t := -1.0
var _blink_len := 0.25
var _blink_hold := 0.0
var _vel := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _vein_paths: Array = []            # fixed vessel layout (eye units)
var _lash_roots: Array = []
var _drips: Array = []                 # [x, speed, width, delay]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7
	_build_layout()
	_rng.randomize()


func _build_layout() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	# vessels: branching scratches from both corners towards the iris
	for i in 16:
		var left := i % 2 == 0
		var p := Vector2(r.randf_range(-1.85, -1.2) if left else r.randf_range(0.95, 1.25), r.randf_range(-0.2, 0.25))
		var dir := (Vector2(0.0, 0.1) - p).normalized()
		var path: Array[Vector2] = [p]
		var n := r.randi_range(6, 11)
		for k in n:
			dir = dir.rotated(r.randf_range(-0.6, 0.6))
			p += dir * r.randf_range(0.05, 0.1)
			path.append(p)
			if p.length() < 0.62:
				break
			if r.randf() < 0.25:
				var b: Array[Vector2] = [p]
				var bd := dir.rotated(r.randf_range(0.6, 1.2) * (1.0 if r.randf() < 0.5 else -1.0))
				var bp := p
				for j in r.randi_range(2, 4):
					bd = bd.rotated(r.randf_range(-0.5, 0.5))
					bp += bd * r.randf_range(0.04, 0.08)
					b.append(bp)
				_vein_paths.append(b)
		_vein_paths.append(path)
	for i in 46:
		_lash_roots.append([r.randf_range(0.03, 0.95), r.randf_range(0.7, 1.15)])
	for i in 5:
		_drips.append([r.randf_range(-0.6, 0.75), r.randf_range(0.6, 1.4), r.randf_range(0.012, 0.03), r.randf_range(0.0, 0.5)])


func do_blink(len := 0.25, hold := 0.0) -> void:
	if _blink_t < 0.0:
		_blink_t = 0.0
		_blink_len = len
		_blink_hold = hold


func _process(delta: float) -> void:
	_t += delta
	_boil_t += delta
	var fps := boil_fps + tremble * 14.0
	if _boil_t >= 1.0 / fps:
		_boil_t = 0.0
		_seed += 1
	# springy gaze
	var k := 260.0
	var steps := maxi(1, ceili(delta / 0.005))
	var h := delta / steps
	for i in steps:
		_vel += ((gaze_target - gaze) * k - _vel * 2.0 * sqrt(k) * 0.85) * h
		gaze += _vel * h
	pupil = lerpf(pupil, pupil_target, 1.0 - exp(-delta * 4.0))
	var b := 0.0
	if _blink_t >= 0.0:
		_blink_t += delta
		var c := _blink_len * 0.4
		var o := _blink_len * 0.6
		if _blink_t < c:
			b = _blink_t / c
		elif _blink_t < c + _blink_hold:
			b = 1.0
		elif _blink_t < c + _blink_hold + o:
			b = 1.0 - (_blink_t - c - _blink_hold) / o
		else:
			_blink_t = -1.0
	blink = b
	queue_redraw()


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------
static func _bump2(s: float, pk: float, pl: float, pr: float) -> float:
	s = clampf(s, 0.0, 1.0)
	var left := s < pk
	var u := s / pk if left else (1.0 - s) / (1.0 - pk)
	return pow(maxf(sin(0.5 * PI * u), 0.0), pl if left else pr)


func _lid(x: float, upper: bool) -> float:
	var s := (x - X_L) / (X_R - X_L)
	var base := lerpf(Y_L, Y_R, clampf(s, 0.0, 1.0))
	var lo := base - 0.32 * (1.0 + 0.15 * wide) * _bump2(s, 0.65, 1.85, 0.45)
	if not upper:
		return lerpf(lo, base - 0.13 * _bump2(s, 0.65, 1.85, 0.45), 0.3 * blink)
	var up := base + 0.69 * (1.0 + 0.3 * wide) * _bump2(s, 0.68, 1.6, 0.5)
	var lo_now := lerpf(lo, base - 0.13 * _bump2(s, 0.65, 1.85, 0.45), 0.3 * blink)
	return lerpf(up, lo_now + 0.004, smoothstep(0.0, 1.0, blink))


func _to_screen(p: Vector2) -> Vector2:
	var sz := size
	return Vector2(center.x * sz.x + p.x * unit * sz.y, center.y * sz.y - p.y * unit * sz.y)


func _jit(p: Vector2, amp: float, salt: float) -> Vector2:
	# smooth-ish noise that changes completely every boil frame
	var s := float(_seed) * 13.17 + salt
	return p + Vector2(sin(p.x * 7.3 + s * 1.7) + sin(p.y * 11.1 - s * 2.3), cos(p.x * 9.7 - s * 1.1) + sin(p.y * 6.9 + s * 2.9)) * amp * 0.5


# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------
## A tapered ink stroke through eye-space points.
func _stroke(pts: Array[Vector2], width_px: float, col: Color, jitter: float, salt: float, taper := true) -> void:
	if pts.size() < 2:
		return
	var amp := jitter * (1.0 + tremble * 2.5)
	var sp := PackedVector2Array()
	for i in pts.size():
		sp.append(_to_screen(_jit(pts[i], amp, salt + float(i) * 0.37)))
	var n := sp.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var a := sp[maxi(i - 1, 0)]
		var b := sp[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		var tt := float(i) / float(n - 1)
		var w := width_px * (sin(PI * clampf(tt * 0.92 + 0.04, 0.0, 1.0)) if taper else 1.0)
		w *= 0.75 + 0.5 * absf(sin(tt * 9.0 + salt + float(_seed)))   # pressure wobble
		left.append(sp[i] + nrm * w * 0.5)
		right.append(sp[i] - nrm * w * 0.5)
	var poly := PackedVector2Array(left)
	for i in range(n - 1, -1, -1):
		poly.append(right[i])
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		draw_polyline(sp, col, maxf(width_px * 0.6, 1.0), true)
		return
	var cols := PackedColorArray()
	cols.resize(poly.size())
	cols.fill(col)
	var idx := PackedInt32Array(tris)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, poly, cols)


func _curve(f: Callable, x0: float, x1: float, n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in n + 1:
		var x := lerpf(x0, x1, float(i) / n)
		out.append(Vector2(x, f.call(x)))
	return out


func _draw() -> void:
	var px := size.y * unit                 # pixels per eye unit
	var w := clampf(px * 0.018, 2.0, 9.0)   # main line width
	var ink := Color(INK, INK.a * alpha)
	var ink_d := Color(INK_DARK, alpha)
	var faint := Color(INK.r, INK.g, INK.b, 0.35 * alpha)
	var up := func(x: float) -> float: return _lid(x, true)
	var lo := func(x: float) -> float: return _lid(x, false)

	# vessels in the white (drawn first, under everything)
	for vi in _vein_paths.size():
		var path: Array = _vein_paths[vi]
		var vp: Array[Vector2] = []
		for q: Vector2 in path:
			var y_hi := _lid(q.x, true)
			var y_lo := _lid(q.x, false)
			if q.y < y_hi - 0.02 and q.y > y_lo + 0.02:
				vp.append(q)
		if vp.size() >= 2:
			_stroke(vp, w * 0.35, Color(INK.r, INK.g, INK.b, 0.5 * veins * alpha), 0.012, 50.0 + vi)

	# iris: an open circle drawn twice, like the sketch (gap low on the left)
	var ic := Vector2(gaze.x, 0.11 + gaze.y)
	var ir := 0.5
	for pass_i in 2:
		var a0 := deg_to_rad(205.0 + pass_i * 14.0)
		var sweep := deg_to_rad(332.0 - pass_i * 22.0)
		var circ: Array[Vector2] = []
		for i in 40:
			var a := a0 - sweep * float(i) / 39.0
			var rr := ir * (1.0 + 0.03 * sin(a * 3.0 + float(pass_i)))
			var q := ic + Vector2(cos(a), sin(a)) * rr
			circ.append(_clip_to_lids(q))
		_stroke(circ, w * (1.0 if pass_i == 0 else 0.6), ink if pass_i == 0 else faint, 0.02, 10.0 + pass_i * 3.0)
	# radial scratches inside the iris
	var pr := lerpf(0.12, 0.36, pupil)
	for i in 34:
		var a := TAU * float(i) / 34.0 + float(_seed % 3) * 0.05
		var r0 := pr + 0.03
		var r1 := ir * (0.72 + 0.22 * fmod(float(i) * 0.618, 1.0))
		var s0 := ic + Vector2(cos(a), sin(a)) * r0
		var s1 := ic + Vector2(cos(a + 0.05), sin(a + 0.05)) * r1
		if _inside_lids(s0) and _inside_lids(s1):
			_stroke([s0, s1] as Array[Vector2], w * 0.28, faint, 0.006, 80.0 + i)
	# pupil: a scribbled blot
	var blot := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		var rr := pr * (1.0 + 0.08 * sin(a * 5.0 + float(_seed) * 0.9) + 0.05 * sin(a * 11.0 - float(_seed)))
		var q := ic + Vector2(cos(a), sin(a)) * rr
		if _inside_lids(q):
			blot.append(_to_screen(q))
		else:
			blot.append(_to_screen(_clip_to_lids(q)))
	if blot.size() > 3:
		draw_colored_polygon(blot, Color(0.06, 0.0, 0.0, alpha))
	for k in 5:
		var sc: Array[Vector2] = []
		for i in 9:
			var a := _rng_det(k * 31 + i) * TAU
			var rr := pr * (0.25 + 0.75 * _rng_det(k * 17 + i * 3))
			sc.append(_clip_to_lids(ic + Vector2(cos(a), sin(a)) * rr))
		_stroke(sc, w * 0.5, ink_d, 0.01, 120.0 + k)
	# catchlight: a pale scratched square on the upper left of the iris
	if blink < 0.5:
		var hl := ic + Vector2(-0.17, 0.2)
		var sq: Array[Vector2] = [hl, hl + Vector2(0.07, 0.0), hl + Vector2(0.07, -0.06), hl + Vector2(0.0, -0.06), hl]
		if _inside_lids(hl):
			_stroke(sq, w * 0.45, Color(INK_PALE, 0.8 * alpha), 0.008, 140.0, false)

	# lids: a heavy line plus nervous repeats; the lines run off the left edge
	var x_edge := (-center.x * size.x) / px - 0.2
	for pass_i in 3:
		var wd := w * (1.25 if pass_i == 0 else 0.55)
		var cl := ink if pass_i == 0 else faint
		var off := 0.012 * float(pass_i)
		var top := _curve(up, X_L, X_R - 0.02, 44)
		top.push_front(Vector2(x_edge, Y_L + 0.06 + off))
		_stroke(top, wd, cl, 0.022, 200.0 + pass_i * 5.0)
		var bot := _curve(lo, X_L, X_R - 0.08, 44)
		bot.push_front(Vector2(x_edge, Y_L - 0.04 - off))
		_stroke(bot, wd, cl, 0.022, 220.0 + pass_i * 5.0)
	# crease above, bag below
	var crease := func(x: float) -> float: return _lid(x, true) + 0.24 + 0.08 * _bump2((x - X_L) / (X_R - X_L), 0.68, 1.2, 0.8) * (1.0 - blink * 0.5)
	_stroke(_curve(crease, -1.4, 1.05, 30), w * 0.5, faint, 0.03, 300.0)
	var bag := func(x: float) -> float: return _lid(x, false) - 0.2 - 0.05 * sin((x + 1.0) * 1.3)
	_stroke(_curve(bag, -0.9, 1.0, 24), w * 0.4, Color(INK.r, INK.g, INK.b, 0.22 * alpha), 0.03, 320.0)
	# lashes: quick flicks along the upper lid, a few under the lower one
	for i in _lash_roots.size():
		var lr: Array = _lash_roots[i]
		var s: float = lr[0]
		var x := lerpf(X_L, X_R, s)
		var root := Vector2(x, _lid(x, true))
		var ln: float = lr[1] * 0.2 * (0.5 + 0.8 * sin(PI * clampf(s * 1.1, 0.0, 1.0)))
		var tilt := (s - 0.7) * 1.4
		var dirv := Vector2(sin(tilt), cos(tilt)) * (1.0 - 1.6 * blink)
		var tip := root + dirv * ln
		var mid := root + dirv * ln * 0.55 + Vector2(-0.02, 0.0)
		_stroke([root, mid, tip] as Array[Vector2], w * 0.45, ink, 0.01, 400.0 + i)
	for i in 14:
		var s := 0.15 + 0.6 * float(i) / 13.0
		var x := lerpf(X_L, X_R, s)
		var root := Vector2(x, _lid(x, false))
		var tip := root + Vector2((s - 0.6) * 0.1, -0.07 - 0.03 * fmod(float(i) * 0.37, 1.0))
		_stroke([root, tip] as Array[Vector2], w * 0.3, faint, 0.008, 500.0 + i)

	# ink tears
	if bleed > 0.001:
		for i in _drips.size():
			var d: Array = _drips[i]
			var dx: float = d[0]
			var prog := clampf((bleed - float(d[3]) * 0.5) * float(d[1]), 0.0, 1.6)
			if prog <= 0.0:
				continue
			var y0 := _lid(dx, false) - 0.01
			var pts: Array[Vector2] = []
			for k in 12:
				var tt := float(k) / 11.0 * prog
				pts.append(Vector2(dx + 0.02 * sin(tt * 7.0 + float(i)), y0 - tt))
			_stroke(pts, w * (0.7 + float(d[2]) * 20.0), ink, 0.004, 600.0 + i, false)
			var tip: Vector2 = _to_screen(pts[-1])
			draw_circle(tip + Vector2(0, px * 0.012), px * (0.022 + float(d[2])), Color(INK, alpha))

	# violent scribbles over everything
	if scribble > 0.01:
		var n := int(4 + scribble * 14)
		for k in n:
			var sc: Array[Vector2] = []
			var p := Vector2(_rng_det(k * 7 + _seed) * 3.0 - 1.6, _rng_det(k * 11 + _seed) * 1.2 - 0.5)
			for i in 10:
				p += Vector2(_rng_det(k * 13 + i + _seed) - 0.5, _rng_det(k * 19 + i * 5 + _seed) - 0.5) * 0.5
				sc.append(p)
			_stroke(sc, w * (0.3 + 0.7 * _rng_det(k + _seed)), Color(INK.r, INK.g, INK.b, (0.4 + 0.5 * scribble) * alpha), 0.03, 700.0 + k)


func _rng_det(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(_seed) * 0.01) * 43758.5453, 1.0)


func _inside_lids(q: Vector2) -> bool:
	if q.x <= X_L or q.x >= X_R:
		return false
	return q.y < _lid(q.x, true) - 0.01 and q.y > _lid(q.x, false) + 0.01


func _clip_to_lids(q: Vector2) -> Vector2:
	var x := clampf(q.x, X_L + 0.01, X_R - 0.01)
	return Vector2(q.x, clampf(q.y, _lid(x, false) + 0.012, _lid(x, true) - 0.012))

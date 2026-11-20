class_name StairWalker
extends Node3D
## The menu camera: a "blind" man climbing the stairwell with a white cane.
## Walks a smooth switchback path (StairBuilder geometry) one floor per lap,
## at a careful pace, sometimes stopping to hesitate and listen. The cane
## sweeps ahead and taps the steps; taps and footsteps are noises that wake
## the sensor lights. When a lap ends he is moved down one floor (seamless).

signal tapped(pos: Vector3)
signal stepped(pos: Vector3)
signal lap_done

const EYE := 1.6

var cam: Camera3D
var cane: MeshInstance3D
var speed := 0.33
var paused := false
var breath := 0.0                 # chest motion from BodySounds
var shake_scale := 1.0
var look_offset := Vector2.ZERO   # extra yaw/pitch (turning towards a sound)
var look_target := Vector2.ZERO
var floor_offset := 0.0           # world y of the current lap's floor

var _pts: PackedVector2Array      # baked xz path for one lap
var _hts: PackedFloat32Array      # floor height (relative) at each point
var _len: PackedFloat32Array      # cumulative length
var _s := 0.0
var _y := 0.0
var _yaw := 0.0
var _pitch := -0.18
var _step_t := 0.0
var _step_len := 0.95
var _step_side := 1.0
var _cane_phase := 0.0
var _kick := Vector2.ZERO
var _kick_v := Vector2.ZERO
var _hesitate := 0.0
var _next_hesitate := 9.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.03
	cam.far = 60.0
	cam.current = true
	add_child(cam)
	_build_cane()
	_bake()
	_s = 0.0
	_y = EYE
	var p := _sample(0.0)
	var t := _tangent(0.0)
	_yaw = atan2(-t.x, -t.y)
	position = Vector3(p.x, EYE, p.y)


func _build_cane() -> void:
	cane = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0065
	cm.bottom_radius = 0.0065
	cm.height = 1.0
	cm.radial_segments = 8
	cane.mesh = cm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cane.gdshader")
	cane.material_override = mat
	add_child(cane)
	cane.top_level = true


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _bake() -> void:
	var zh := StairBuilder.ZH
	var zl := StairBuilder.ZL
	var way := [
		Vector2(-0.68, 0.55), Vector2(-0.68, 1.05), Vector2(-0.68, zh - 0.05), Vector2(-0.6, zh + 0.6),
		Vector2(-0.1, zh + 0.8), Vector2(0.55, zh + 0.5), Vector2(0.68, zh - 0.05), Vector2(0.68, zl + 0.1),
		Vector2(0.62, 0.45), Vector2(0.15, 0.05), Vector2(-0.45, 0.15), Vector2(-0.68, 0.55),
	]
	# phantom neighbours from the previous / next lap make the loop seamless
	var pts: Array = [way[-2]] + way + [way[1]]
	_pts = PackedVector2Array()
	for i in range(1, pts.size() - 2):
		for k in 24:
			_pts.append(_catmull(pts[i - 1], pts[i], pts[i + 1], pts[i + 2], float(k) / 24.0))
	_pts.append(way[-1])
	_len = PackedFloat32Array()
	_hts = PackedFloat32Array()
	var acc := 0.0
	var passed_half := false
	var upper := false
	for i in _pts.size():
		if i > 0:
			acc += _pts[i].distance_to(_pts[i - 1])
		_len.append(acc)
		var p := _pts[i]
		if p.y >= zh:
			passed_half = true
		var h := 0.0
		if not passed_half:
			h = clampf((p.y - zl) / (zh - zl), 0.0, 1.0) * StairBuilder.H * 0.5
		else:
			if p.y < zl and p.x > -0.2:
				upper = true
			if upper or p.y < zl:
				h = StairBuilder.H
			elif p.y >= zh:
				h = StairBuilder.H * 0.5
			else:
				h = StairBuilder.H * 0.5 + clampf((zh - p.y) / (zh - zl), 0.0, 1.0) * StairBuilder.H * 0.5
		_hts.append(h)


func lap_length() -> float:
	return _len[_len.size() - 1]


func _index_at(s: float) -> int:
	var lo := 0
	var hi := _len.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _len[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


func _sample(s: float) -> Vector2:
	var i := _index_at(s)
	var j := mini(i + 1, _pts.size() - 1)
	var seg := maxf(_len[j] - _len[i], 1e-5)
	return _pts[i].lerp(_pts[j], clampf((s - _len[i]) / seg, 0.0, 1.0))


func _height(s: float) -> float:
	var i := _index_at(s)
	var j := mini(i + 1, _pts.size() - 1)
	var seg := maxf(_len[j] - _len[i], 1e-5)
	return lerpf(_hts[i], _hts[j], clampf((s - _len[i]) / seg, 0.0, 1.0))


func _tangent(s: float) -> Vector2:
	var a := _sample(s)
	var b := _sample(minf(s + 0.35, lap_length()))
	if b.distance_to(a) < 1e-4:
		b = _sample(minf(s + 0.35 - lap_length(), lap_length())) + Vector2(0, 0.001)
	return (b - a).normalized()


func on_stairs() -> bool:
	var p := _sample(_s)
	return p.y > StairBuilder.ZL and p.y < StairBuilder.ZH


func heartbeat_kick(strength: float) -> void:
	_kick_v += Vector2(_rng.randf_range(-1.0, 1.0) * 0.4, -1.0) * strength * 0.9 * shake_scale


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	# hesitation: he stops, listens, then goes on
	if _hesitate > 0.0:
		_hesitate -= delta
	else:
		_next_hesitate -= delta
		if _next_hesitate <= 0.0:
			_hesitate = _rng.randf_range(1.5, 3.5)
			_next_hesitate = _rng.randf_range(10.0, 22.0)
			look_target = Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.05, 0.15))
	var moving := not paused and _hesitate <= 0.0
	var v := speed * (0.85 if on_stairs() else 1.1)
	if moving:
		_s += v * delta
		_step_t += delta
		if _step_t >= _step_len:
			_step_t -= _step_len
			_step_side = -_step_side
			stepped.emit(global_position - Vector3(0, EYE, 0))
		if _s >= lap_length():
			_s -= lap_length()
			floor_offset += 0.0
			lap_done.emit()
	else:
		look_offset = look_offset.lerp(look_target, 1.0 - exp(-delta * 1.5))
	if moving:
		look_target = look_target.lerp(Vector2.ZERO, 1.0 - exp(-delta * 0.6))
		look_offset = look_offset.lerp(look_target, 1.0 - exp(-delta * 1.5))
	var p := _sample(_s)
	var t := _tangent(_s)
	var target_yaw := atan2(-t.x, -t.y)
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-delta * 2.2))
	var want_y := floor_offset + _height(_s) + EYE
	_y = lerpf(_y, want_y, 1.0 - exp(-delta * 4.0))
	# a careful gait: each step dips and sways the head a little
	var ph := _step_t / _step_len
	var bob := (sin(ph * PI) - 0.5) * 0.022 if moving else 0.0
	var sway := sin(ph * PI) * 0.012 * _step_side if moving else 0.0
	# heartbeat kick spring (sub-stepped: stable at low frame rates)
	var k := 220.0
	var steps := maxi(1, ceili(delta / 0.006))
	var h := delta / steps
	for i in steps:
		_kick_v += (-_kick * k - _kick_v * 2.0 * sqrt(k) * 0.6) * h
		_kick += _kick_v * h
	position = Vector3(p.x, _y + bob + breath * 0.008, p.y)
	var pitch := (-0.2 if on_stairs() else -0.07) + look_offset.y + _kick.y * 0.01
	_pitch = lerpf(_pitch, pitch, 1.0 - exp(-delta * 2.0))
	cam.rotation = Vector3(_pitch, look_offset.x + _kick.x * 0.01, sway * 0.6)
	rotation = Vector3(0.0, _yaw, 0.0)
	cam.position = Vector3(sway, 0.0, 0.0)
	_update_cane(delta, moving)


func _update_cane(delta: float, moving: bool) -> void:
	# hand low at the right, the tip sweeping an arc ahead on the floor
	if moving:
		_cane_phase += delta / _step_len * PI
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x) * -1.0
	var hand := global_position + right * 0.24 + fwd * 0.28 + Vector3(0, -0.78, 0)
	var swing := sin(_cane_phase)
	var tip_xz := global_position + fwd * 0.95 + right * swing * 0.32
	var ground := _ground_at(Vector2(tip_xz.x, tip_xz.z))
	var lift := maxf(0.0, cos(_cane_phase)) * 0.0 + (1.0 - absf(swing)) * 0.06
	var tip := Vector3(tip_xz.x, ground + lift, tip_xz.z)
	var was := cane.get_meta("down", false) as bool
	var down := absf(swing) > 0.92
	if down and not was and moving:
		tapped.emit(tip)
	cane.set_meta("down", down)
	var d := tip - hand
	var mid := hand + d * 0.5
	var up := d.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var xax := up.cross(ref).normalized()
	var zax := xax.cross(up).normalized()
	cane.global_transform = Transform3D(Basis(xax, up * d.length(), zax), mid)


func _ground_at(xz: Vector2) -> float:
	var x := xz.x
	var z := xz.y
	var base := floor_offset
	var on_upper := _hts[_index_at(_s)] >= StairBuilder.H - 0.01
	if on_upper:
		base += StairBuilder.H
	if z < StairBuilder.ZL:
		return base
	var half := floor_offset + StairBuilder.H * 0.5
	if z >= StairBuilder.ZH:
		return half
	var k := (z - StairBuilder.ZL) / (StairBuilder.ZH - StairBuilder.ZL)
	var steps := floorf(k * (StairBuilder.NRISE - 1)) + 1.0
	if x < 0.0:
		return floor_offset + steps * (StairBuilder.H * 0.5 / StairBuilder.NRISE)
	return half + (StairBuilder.NRISE - steps) * (StairBuilder.H * 0.5 / StairBuilder.NRISE)

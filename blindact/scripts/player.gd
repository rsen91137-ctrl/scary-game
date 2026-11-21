class_name Player
extends CharacterBody3D
## The protagonist: a mute who pretends to be blind. First person.
##   walk    WASD + mouse, the white cane sweeps ahead and taps
##   seated  at the piano: look around within limits, hands on the keys
##   hidden  in the wardrobe: peek through the gap
##   locked  the director moves the camera (cutscenes, being grabbed)
## Hold SPACE to close your eyes. E interacts. Moving the mouse up-down /
## left-right quickly is a nod / a shake of the head (the only way he
## answers). The director reads look direction and angular speed for tells.

signal interacted(id: String)
signal tapped(pos: Vector3)
signal stepped(pos: Vector3)
signal gesture(kind: String)

const EYE := 1.62

var mode := "walk"
var cam: Camera3D
var head: Node3D
var cane: MeshInstance3D
var yaw := 0.0
var pitch := 0.0
var yaw_center := 0.0
var yaw_range := PI            # seated / hidden limits around yaw_center
var pitch_range := Vector2(-1.25, 1.2)
var speed := 1.05
var eyes_closed := false
var can_close_eyes := true
var ang_speed := 0.0           # smoothed camera angular speed (rad/s)
var _view_from := Vector2.ZERO
var _view_to := Vector2.ZERO
var _view_t := 1.0
var _view_len := 1.0
var _step_n := 0
var _eye_cur := EYE
var focus: Area3D              # interactable under the crosshair
var cane_enabled := true
var shake_scale := 1.0
var breath := 0.0
var expect_gesture := false
var eye_h := EYE                # head height (lower when seated)
var on_stairs := false         # climbing: shorter strides, a step up each time
var step_len := 0.62           # seconds per footstep (shorter on the stairs)

var _step_t := 0.0
var _cane_phase := 0.0
var _prev_dir := Vector3.FORWARD
var _kick := Vector2.ZERO
var _kick_v := Vector2.ZERO
var _g_samples: Array = []     # [time, dx, dy]
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _locked_xf := Transform3D()
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _cane_tip_pos := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	collision_layer = 1
	collision_mask = 1
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.02
	cam.far = 80.0
	cam.current = true
	head.add_child(cam)
	_build_cane()


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
	cane.top_level = true
	add_child(cane)


func look_dir() -> Vector3:
	return -cam.global_basis.z


func eye_pos() -> Vector3:
	return cam.global_position


func set_mode(m: String, center_yaw := INF) -> void:
	mode = m
	if center_yaw != INF:
		yaw_center = center_yaw
		yaw = center_yaw
	match m:
		"seated":
			yaw_range = deg_to_rad(105.0)
			pitch_range = Vector2(-0.65, 0.6)
			eye_h = 1.18
		"hidden":
			yaw_range = deg_to_rad(35.0)
			pitch_range = Vector2(-0.3, 0.3)
			eye_h = 1.55
		"still":
			yaw_range = deg_to_rad(70.0)
			pitch_range = Vector2(-0.5, 0.45)
			eye_h = EYE
		"walk":
			yaw_range = PI
			pitch_range = Vector2(-1.25, 1.2)
			eye_h = EYE
		_:
			yaw_range = PI
			pitch_range = Vector2(-1.25, 1.2)
	cane.visible = m == "walk" and cane_enabled


func snap_eye() -> void:
	_eye_cur = eye_h


func heartbeat_kick(strength: float) -> void:
	_kick_v += Vector2(_rng.randf_range(-1.0, 1.0) * 0.4, -1.0) * strength * 0.8 * shake_scale


## Turn the view to look at `p` over `secs`, easing in and out (the game
## turning your head for you; not counted as your own jerk of the head).
func look_toward(p: Vector3, secs := 0.6) -> void:
	var d := p - eye_pos()
	_view_from = Vector2(yaw, pitch)
	_view_to = Vector2(yaw + wrapf(atan2(-d.x, -d.z) - yaw, -PI, PI),
			clampf(atan2(d.y, Vector2(d.x, d.z).length()), pitch_range.x, pitch_range.y))
	_view_len = maxf(secs, 0.01)
	_view_t = 0.0


## For cutscenes: look at a world point over time (mode locked keeps it).
func face_point(p: Vector3, k := 1.0) -> void:
	var d := p - eye_pos()
	var ty := atan2(-d.x, -d.z)
	var tp := atan2(d.y, Vector2(d.x, d.z).length())
	yaw = lerp_angle(yaw, ty, k)
	pitch = lerpf(pitch, tp, k)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and mode != "locked":
		var m := event as InputEventMouseMotion
		var s := 0.0022 * Settings.mouse_sensitivity
		yaw -= m.relative.x * s
		pitch -= m.relative.y * s
		_g_samples.append([_t, m.relative.x, m.relative.y])
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_E and focus and mode != "locked":
			interacted.emit(String(focus.get_meta("id", "")))
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mode == "walk":
			_tap_now()


func _tap_now() -> void:
	var tip := _cane_tip()
	tapped.emit(tip)


func _physics_process(delta: float) -> void:
	if mode != "walk":
		velocity = Vector3.ZERO
		return
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	input = input.limit_length(1.0)
	var dir := (Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y))
	var sp := speed * (0.55 if eyes_closed else 1.0)
	var want := Vector2(dir.x, dir.z) * sp
	var cur := Vector2(velocity.x, velocity.z)
	cur = cur.move_toward(want, (7.0 if want.length() > cur.length() else 10.0) * delta)
	velocity.x = cur.x
	velocity.z = cur.y
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	on_stairs = is_on_floor() and get_floor_normal().y < 0.97
	step_len = 0.44 if on_stairs else 0.62
	if input.length() > 0.1:
		_step_t += delta
		if _step_t > step_len:
			_step_t = 0.0
			_step_n += 1
			stepped.emit(global_position)
		# pushing but not moving for a while: something holds us; step free
		if global_position.distance_to(_last_pos) < 0.004:
			_stuck_t += delta
			if _stuck_t > 1.2:
				_stuck_t = 0.0
				unstick()
		else:
			_stuck_t = 0.0
	else:
		_stuck_t = 0.0
	_last_pos = global_position


func _process(delta: float) -> void:
	_t += delta
	delta = minf(delta, 0.1)
	# eyes
	eyes_closed = can_close_eyes and Input.is_key_pressed(KEY_SPACE) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# limits
	if mode == "seated" or mode == "hidden" or mode == "still":
		var dy := wrapf(yaw - yaw_center, -PI, PI)
		yaw = yaw_center + clampf(dy, -yaw_range, yaw_range)
	if _view_t < 1.0:
		_view_t = minf(1.0, _view_t + delta / _view_len)
		var vk := smoothstep(0.0, 1.0, _view_t)
		yaw = lerpf(_view_from.x, _view_to.x, vk)
		pitch = lerpf(_view_from.y, _view_to.y, vk)
	pitch = clampf(pitch, pitch_range.x, pitch_range.y)
	# heartbeat kick spring (sub-stepped)
	var k := 220.0
	var steps := maxi(1, ceili(delta / 0.006))
	var h := delta / steps
	for i in steps:
		_kick_v += (-_kick * k - _kick_v * 2.0 * sqrt(k) * 0.6) * h
		_kick += _kick_v * h
	var moving := mode == "walk" and Vector2(velocity.x, velocity.z).length() > 0.1
	var bob := 0.0
	if moving:
		var ph := clampf(_step_t / step_len, 0.0, 1.0)
		# on the stairs every stride lifts you a riser: rise, then settle
		bob = (sin(ph * PI) * 0.032 - 0.012) if on_stairs else sin(ph * PI) * 0.018
	# sitting down and getting up ease the eye height
	_eye_cur = lerpf(_eye_cur, eye_h, 1.0 - exp(-5.0 * delta))
	head.position.y = _eye_cur + bob + breath * 0.006
	head.rotation = Vector3(0.0, yaw, 0.0)
	# the head rolls a touch from foot to foot as you walk
	var roll := 0.0
	if moving:
		var sp_k := clampf(Vector2(velocity.x, velocity.z).length() / 1.4, 0.0, 1.0)
		roll = sin((float(_step_n) + clampf(_step_t / step_len, 0.0, 1.0)) * PI) * 0.0045 * sp_k
	cam.rotation = Vector3(pitch + _kick.y * 0.01, _kick.x * 0.01, roll)
	# angular speed of the view (for flinch detection)
	var dirv := look_dir()
	var a := _prev_dir.angle_to(dirv) / maxf(delta, 0.001)
	if _view_t < 1.0:
		a = 0.0
	ang_speed = lerpf(ang_speed, a, 1.0 - exp(-delta * 18.0))
	_prev_dir = dirv
	_update_focus()
	_update_cane(delta, moving)
	_update_gesture()


func _update_focus() -> void:
	focus = null
	if mode == "locked":
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye_pos(), eye_pos() + look_dir() * 1.7)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.collision_mask = 2 | 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit and hit.collider is Area3D and (hit.collider as Area3D).has_meta("interact"):
		focus = hit.collider
	elif hit.is_empty() or not (hit.collider is Area3D):
		# a second pass for areas behind thin colliders
		q.collide_with_bodies = false
		var hit2 := space.intersect_ray(q)
		if hit2 and hit2.collider is Area3D and (hit2.collider as Area3D).has_meta("interact"):
			focus = hit2.collider


## Where the cane's tip is: swinging ahead, resting on whatever is under it
## (the next steps when climbing) and never through a wall.
func _cane_tip() -> Vector3:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var swing := sin(_cane_phase)
	var tip := global_position + fwd * 0.95 + right * swing * 0.3
	tip.y = global_position.y + 0.02
	if not is_inside_tree():
		return tip
	var space := get_world_3d().direct_space_state
	var hand := global_position + Vector3(0, EYE - 0.8, 0) + right * 0.24 + fwd * 0.28
	# the ground under the tip (a step up or down)
	var q := PhysicsRayQueryParameters3D.create(Vector3(tip.x, global_position.y + 0.75, tip.z), Vector3(tip.x, global_position.y - 0.8, tip.z))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit:
		tip.y = float(hit.position.y) + 0.01
	# a wall, a railing or furniture between the hand and the tip stops it
	var q2 := PhysicsRayQueryParameters3D.create(hand, tip)
	q2.exclude = [get_rid()]
	q2.collision_mask = 1 | 4
	var hit2 := space.intersect_ray(q2)
	if hit2:
		tip = (hit2.position as Vector3) + (hand - (hit2.position as Vector3)).normalized() * 0.015
	_cane_tip_pos = tip
	return tip


## Free the body if it is caught inside furniture: try spots around it.
func unstick() -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.27
	shape.height = 1.6
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1 | 4
	params.exclude = [get_rid()]
	for r: float in [0.0, 0.3, 0.5, 0.75, 1.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var p := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			params.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.9, 0))
			if space.intersect_shape(params, 1).is_empty():
				global_position = p
				return


func _update_cane(delta: float, moving: bool) -> void:
	if not cane.visible:
		return
	if moving:
		_cane_phase += delta / 0.62 * PI
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hand := global_position + Vector3(0, EYE - 0.8, 0) + right * 0.24 + fwd * 0.28
	var tip := _cane_tip()
	var down := absf(sin(_cane_phase)) > 0.93
	var was := cane.get_meta("down", false) as bool
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


## Nod = quick up-down-up of the mouse; shake = left-right-left.
func _update_gesture() -> void:
	while not _g_samples.is_empty() and _t - float(_g_samples[0][0]) > 0.9:
		_g_samples.pop_front()
	if not expect_gesture or _g_samples.size() < 4:
		return
	var rev_x := 0
	var rev_y := 0
	var sx := 0.0
	var sy := 0.0
	var amp_x := 0.0
	var amp_y := 0.0
	var lx := 0.0
	var ly := 0.0
	for smp: Array in _g_samples:
		var dx: float = smp[1]
		var dy: float = smp[2]
		amp_x += absf(dx)
		amp_y += absf(dy)
		if absf(dx) > 2.0:
			if lx != 0.0 and signf(dx) != signf(lx):
				rev_x += 1
			lx = dx
		if absf(dy) > 2.0:
			if ly != 0.0 and signf(dy) != signf(ly):
				rev_y += 1
			ly = dy
		sx += dx
		sy += dy
	if rev_y >= 2 and amp_y > 120.0 and amp_y > amp_x * 1.5:
		_g_samples.clear()
		gesture.emit("nod")
	elif rev_x >= 2 and amp_x > 160.0 and amp_x > amp_y * 1.5:
		_g_samples.clear()
		gesture.emit("shake")

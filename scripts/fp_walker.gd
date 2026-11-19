class_name FPWalker
extends Node3D
## First-person camera rig: the (invisible) protagonist walks slowly down the
## corridor. Head bob follows the footsteps, the chest rises with every breath,
## the gaze drifts, and every heartbeat kicks the camera (position, pitch,
## roll, FOV punch) through a spring so the whole screen throbs.

signal footstep(foot: int)

@export var speed := 0.46          # m/s, a slow, reluctant walk
@export var step_rate := 1.08      # steps per second
@export var eye_height := 1.62

var walking := true
var walk_factor := 1.0             # 0..1, eased when starting/stopping
var shake_scale := 1.0             # user setting
var breath := 0.0                  # -1..1 from the breathing controller
var tension := 0.0                 # 0..1, makes the gait stiffer and the gaze jumpier
var dizzy := 0.0                   # 0..1 vertigo: the world tilts and swims, the walk staggers

var head: Node3D
var cam: Camera3D
var base_fov := 62.0

var _phase := 0.0
var _last_step := 0
var _t := 0.0
var _look := Vector2.ZERO          # yaw, pitch (rad)
var _look_target := Vector2.ZERO
var _look_timer := 4.0
# springs for the heartbeat kick
var _kp := Vector3.ZERO
var _kpv := Vector3.ZERO
var _kr := Vector3.ZERO
var _krv := Vector3.ZERO
var _fov_k := 0.0
var _fov_kv := 0.0
var _rng := RandomNumberGenerator.new()
var _glance_at: Node3D = null
var _glance_time := 0.0


func _ready() -> void:
	_rng.randomize()
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = base_fov
	cam.near = 0.04
	cam.far = 400.0
	cam.current = true
	head.add_child(cam)


## Heartbeat kick. strength ~0.3 (calm) .. 1.5 (panic)
func heartbeat_kick(strength: float) -> void:
	# a hard thump: head jolts down/forward, small random yaw/roll, FOV punch
	var s := strength * shake_scale
	_kpv += Vector3(_rng.randf_range(-0.6, 0.6), -1.0 + _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.4, 0.4)) * 0.11 * s
	_krv += Vector3(-1.0 - _rng.randf() * 0.4, _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.8, 0.8)) * 0.2 * s
	_fov_kv -= 30.0 * s


func glance_at(target: Node3D, duration: float) -> void:
	_glance_at = target
	_glance_time = duration


func reset_to(z: float) -> void:
	position = Vector3(0.0, 0.0, z)
	_phase = 0.0
	_last_step = 0
	_look = Vector2.ZERO
	_look_target = Vector2.ZERO


func _process(delta: float) -> void:
	_t += delta
	walk_factor = move_toward(walk_factor, 1.0 if walking else 0.0, delta * 0.6)
	var wf := smoothstep(0.0, 1.0, walk_factor)
	var stagger := 1.0 - dizzy * (0.45 + 0.35 * sin(_t * 1.9) * sin(_t * 0.7))
	position.z -= speed * wf * stagger * delta
	position.x = sin(_t * 0.31) * 0.22 * dizzy + sin(_t * 0.11) * 0.05
	_phase += step_rate * wf * stagger * delta

	# footfalls at integer phase
	var step_idx := int(floor(_phase))
	if step_idx != _last_step:
		_last_step = step_idx
		footstep.emit(step_idx % 2)

	# --- head bob: lowest at each footfall, highest mid-stride; lateral sway per stride
	var p := _phase * TAU
	var bob_y := -(0.5 + 0.5 * cos(p)) * 0.032 * wf
	var sway_x := sin(p * 0.5) * 0.022 * wf
	var roll := sin(p * 0.5) * deg_to_rad(0.55) * wf
	var pitch_bob := cos(p) * deg_to_rad(0.35) * wf

	# --- breathing (chest rise) and a faint idle tremor that grows with tension
	var br_y := breath * (0.007 + 0.006 * tension)
	var br_pitch := breath * deg_to_rad(0.25 + 0.35 * tension)
	var trem := Vector2(sin(_t * 9.1) + sin(_t * 13.7), sin(_t * 11.3) + sin(_t * 7.9)) * deg_to_rad(0.05) * tension

	# --- gaze: slow drift + occasional glances (towards the lake, the trees, a lamp)
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = _rng.randf_range(5.0, 11.0) * (1.0 - 0.5 * tension)
		if _rng.randf() < 0.35:
			_look_target = Vector2(deg_to_rad(_rng.randf_range(-22.0, 22.0)), deg_to_rad(_rng.randf_range(-4.0, 3.0)))
		else:
			_look_target = Vector2(deg_to_rad(_rng.randf_range(-6.0, 6.0)), deg_to_rad(_rng.randf_range(-2.5, 1.5)))
	var target := _look_target
	if _glance_at and _glance_time > 0.0:
		_glance_time -= delta
		var to := _glance_at.global_position - cam.global_position
		var yaw := atan2(-to.x, -to.z)
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		target = Vector2(clampf(yaw, -0.6, 0.6), clampf(pitch, -0.3, 0.45))
	var look_speed := 0.55 + 1.2 * tension
	_look = _look.lerp(target, 1.0 - exp(-delta * look_speed))
	var drift := Vector2(sin(_t * 0.21) * 0.6 + sin(_t * 0.53) * 0.3, sin(_t * 0.17) * 0.4) * deg_to_rad(1.1)

	# --- heartbeat springs (sub-stepped so they stay stable on frame hitches)
	var k := 260.0
	var c := 2.0 * sqrt(k) * 0.55
	var kf := 180.0
	var cf := 2.0 * sqrt(kf) * 0.6
	var n := clampi(ceili(delta / (1.0 / 240.0)), 1, 64)
	var dt := minf(delta, 0.25) / float(n)
	for _i in n:
		_kpv += (-k * _kp - c * _kpv) * dt
		_kp += _kpv * dt
		_krv += (-k * _kr - c * _krv) * dt
		_kr += _krv * dt
		_fov_kv += (-kf * _fov_k - cf * _fov_kv) * dt
		_fov_k += _fov_kv * dt
	_kp = _kp.limit_length(0.5)
	_kr = _kr.limit_length(1.5)
	_fov_k = clampf(_fov_k, -40.0, 40.0)

	# vertigo: slow rolling and pitching, the horizon swims
	var vr := (sin(_t * 0.53) * 7.0 + sin(_t * 1.31) * 2.2) * dizzy
	var vp := (sin(_t * 0.71) * 2.8 + sin(_t * 1.7) * 0.8) * dizzy
	var vy := sin(_t * 0.29) * 6.0 * dizzy
	head.position = Vector3(sway_x, eye_height + bob_y + br_y - 0.05 * dizzy, 0.0) + _kp
	head.rotation = Vector3(
		_look.y + drift.y + pitch_bob + br_pitch + trem.y + _kr.x + deg_to_rad(vp),
		_look.x + drift.x + trem.x + _kr.y * 0.6 + deg_to_rad(vy),
		roll + _kr.z * 0.8 + deg_to_rad(vr))
	cam.fov = base_fov + _fov_k + sin(_t * 0.83) * 5.0 * dizzy

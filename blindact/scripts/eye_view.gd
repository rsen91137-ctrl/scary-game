class_name EyeView
extends ColorRect
## Full-screen ColorRect drawing the eye (shaders/eye.gdshader). The director
## drives the public fields; this node smooths them into shader uniforms.

var mat: ShaderMaterial

var gaze := Vector2.ZERO           # current (yaw, pitch)
var gaze_target := Vector2.ZERO
var pupil := 0.38
var pupil_target := 0.38
var blink := 0.0
var squint := 0.0
var wide := 0.0
var redness := 0.75
var vein_pulse := 0.0
var bleed := 0.0
var milky := 0.0
var red_reflex := 0.0
var light := 1.0
var window_light := 1.0
var center := Vector2(0.5, 0.4)
var scale_units := 0.34

var _blink_t := -1.0               # running blink animation time
var _blink_len := 0.22
var _blink_hold := 0.0
var _saccade_v := Vector2.ZERO
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/eye.gdshader")
	for pair: Array in [["iris_tex", "eye_iris"], ["vein_tex", "eye_veins"], ["skin_tex", "eye_skin"],
			["skin_n_tex", "eye_skin_n"], ["lash_up_tex", "eye_lash_up"], ["lash_lo_tex", "eye_lash_lo"]]:
		var path := "res://assets/textures/%s.png" % pair[1]
		if ResourceLoader.exists(path):
			mat.set_shader_parameter(pair[0], load(path))
	material = mat
	color = Color.BLACK


## Start a blink: len = close+open duration, hold = time kept shut.
func do_blink(len := 0.22, hold := 0.0) -> void:
	if _blink_t >= 0.0:
		return
	_blink_t = 0.0
	_blink_len = len
	_blink_hold = hold


func is_blinking() -> bool:
	return _blink_t >= 0.0


## Fast eye movement: jumps most of the way at once, then settles.
func saccade_to(target: Vector2) -> void:
	gaze_target = target


func _process(delta: float) -> void:
	_t += delta
	# gaze: critically damped spring, fast like a real saccade
	var k := 900.0
	var d := 2.0 * sqrt(k) * 0.9
	var steps := maxi(1, ceili(delta / 0.004))
	var h := delta / steps
	for i in steps:
		var acc := (gaze_target - gaze) * k - _saccade_v * d
		_saccade_v += acc * h
		gaze += _saccade_v * h
	# micro tremor + drift
	var micro := Vector2(sin(_t * 41.0) * 0.0015 + sin(_t * 23.0) * 0.001, cos(_t * 37.0) * 0.0012)
	pupil = lerpf(pupil, pupil_target, 1.0 - exp(-delta * 3.0))
	var hippus := 0.025 * sin(_t * 1.3) + 0.015 * sin(_t * 2.9 + 1.0)
	# blink envelope: close fast, hold, open slower
	var b := 0.0
	if _blink_t >= 0.0:
		_blink_t += delta
		var close_t := _blink_len * 0.38
		var open_t := _blink_len * 0.62
		if _blink_t < close_t:
			b = _blink_t / close_t
		elif _blink_t < close_t + _blink_hold:
			b = 1.0
		elif _blink_t < close_t + _blink_hold + open_t:
			b = 1.0 - (_blink_t - close_t - _blink_hold) / open_t
		else:
			_blink_t = -1.0
	blink = maxf(b, 0.0)
	mat.set_shader_parameter("gaze", gaze + micro)
	mat.set_shader_parameter("pupil", clampf(pupil + hippus, 0.0, 1.0))
	mat.set_shader_parameter("blink", clampf(maxf(blink, squint * 0.0), 0.0, 1.0))
	mat.set_shader_parameter("squint", squint)
	mat.set_shader_parameter("wide", wide)
	mat.set_shader_parameter("redness", redness)
	mat.set_shader_parameter("vein_pulse", vein_pulse)
	mat.set_shader_parameter("bleed", bleed)
	mat.set_shader_parameter("milky", milky)
	mat.set_shader_parameter("red_reflex", red_reflex)
	mat.set_shader_parameter("light", light)
	mat.set_shader_parameter("window_light", window_light)
	mat.set_shader_parameter("eye_center", center)
	mat.set_shader_parameter("eye_scale", scale_units)
	mat.set_shader_parameter("time_s", _t)

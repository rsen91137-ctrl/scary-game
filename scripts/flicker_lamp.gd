extends Node3D
## A failing lamp. Pendant bulbs hang from the beam and sway in the wind; the
## far lamp is a cold floodlight with a camera starburst. Each lamp runs its
## own flicker behaviour; the menu director can override all of them for
## scripted scares (blackouts, surges).

signal dropped(strength: float)   # emitted when the lamp suddenly goes dark

@export var mode := "flicker"     # steady | flicker | dying | dead | end
@export var pendant := true
@export var seed_value := 1

var base_energy := 2.4
var base_color := Color(1.0, 0.66, 0.36)
var level := 1.0                  # current output 0..1
var override_level := -1.0        # >= 0 forces the output
var override_time := 0.0

var light: OmniLight3D
var bulb_mat: StandardMaterial3D
var flare_mat: ShaderMaterial
var pivot: Node3D
var buzz: AudioStreamPlayer3D
var zap: AudioStreamPlayer3D

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _next_event := 0.0
var _burst_left := 0.0
var _hold := 0.0
var _burst_level := 1.0
var _swing := Vector2.ZERO
var _swing_v := Vector2.ZERO
var _prev_level := 1.0


func _ready() -> void:
	_rng.seed = seed_value
	_t = _rng.randf() * 100.0
	_next_event = _rng.randf_range(1.5, 6.0)
	if mode == "end":
		base_energy = 9.0
		base_color = Color(0.86, 0.92, 1.0)
	_build()


func _build() -> void:
	pivot = Node3D.new()
	add_child(pivot)
	var bulb_pos := Vector3.ZERO
	var glass := SphereMesh.new()
	if pendant:
		var wire := CylinderMesh.new()
		wire.top_radius = 0.004
		wire.bottom_radius = 0.004
		wire.height = 0.3
		var wm := MeshInstance3D.new()
		wm.mesh = wire
		wm.position = Vector3(0, -0.15, 0)
		wm.material_override = _dark_mat()
		pivot.add_child(wm)
		var shade := CylinderMesh.new()
		shade.top_radius = 0.035
		shade.bottom_radius = 0.13
		shade.height = 0.1
		shade.cap_bottom = false
		var sm := MeshInstance3D.new()
		sm.mesh = shade
		sm.position = Vector3(0, -0.33, 0)
		var shade_mat := _dark_mat()
		shade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		shade_mat.metallic = 0.5
		shade_mat.roughness = 0.5
		sm.material_override = shade_mat
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(sm)
		bulb_pos = Vector3(0, -0.4, 0)
		glass.radius = 0.035
		glass.height = 0.08
	else:
		var head := BoxMesh.new()
		head.size = Vector3(0.36, 0.16, 0.26)
		var hm := MeshInstance3D.new()
		hm.mesh = head
		hm.material_override = _dark_mat()
		hm.position = Vector3(0, 0.12, 0)
		pivot.add_child(hm)
		bulb_pos = Vector3(0, 0.0, 0)
		glass.radius = 0.09
		glass.height = 0.08
	bulb_mat = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1, 1, 1)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = base_color
	bulb_mat.emission_energy_multiplier = 30.0
	var gm := MeshInstance3D.new()
	gm.mesh = glass
	gm.material_override = bulb_mat
	gm.position = bulb_pos
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(gm)

	light = OmniLight3D.new()
	light.position = bulb_pos + Vector3(0, -0.02 if pendant else -0.12, 0)
	light.light_color = base_color
	light.light_energy = base_energy
	light.omni_range = 26.0 if mode == "end" else 10.0
	light.omni_attenuation = 1.15
	light.light_size = 0.03 if pendant else 0.12
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 1.2
	light.light_volumetric_fog_energy = 4.5 if mode == "end" else 2.6
	light.distance_fade_enabled = true
	light.distance_fade_begin = 60.0 if mode == "end" else 40.0
	light.distance_fade_shadow = 45.0 if mode == "end" else 24.0
	light.distance_fade_length = 12.0
	pivot.add_child(light)

	var fq := QuadMesh.new()
	fq.size = Vector2(1, 1)
	flare_mat = ShaderMaterial.new()
	flare_mat.shader = load("res://shaders/flare.gdshader")
	flare_mat.set_shader_parameter("flare_tex", load("res://assets/textures/starburst.png"))
	flare_mat.set_shader_parameter("color", base_color)
	flare_mat.set_shader_parameter("screen_size", 1.1 if mode == "end" else 0.45)
	flare_mat.set_shader_parameter("rotation", _rng.randf_range(-0.2, 0.2))
	flare_mat.render_priority = 10
	var fm := MeshInstance3D.new()
	fm.mesh = fq
	fm.material_override = flare_mat
	fm.position = bulb_pos
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fm.extra_cull_margin = 4.0
	pivot.add_child(fm)

	buzz = AudioStreamPlayer3D.new()
	buzz.position = bulb_pos
	buzz.bus = "Ambience"
	buzz.unit_size = 2.0
	buzz.max_distance = 18.0
	buzz.attenuation_filter_cutoff_hz = 6000.0
	var bstream := _load_audio("res://assets/audio/lamp_buzz.ogg")
	if bstream:
		buzz.stream = bstream
		buzz.autoplay = true
	pivot.add_child(buzz)
	zap = AudioStreamPlayer3D.new()
	zap.position = bulb_pos
	zap.bus = "Ambience"
	zap.unit_size = 3.0
	zap.max_distance = 30.0
	zap.stream = _load_audio("res://assets/audio/lamp_zap.ogg")
	pivot.add_child(zap)


func _dark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.04)
	m.roughness = 0.6
	return m


func _load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Re-roll this lamp when its corridor stretch is recycled.
## Inactive lamps are hidden and stop processing entirely.
func configure(active: bool, new_mode: String, new_seed: int) -> void:
	mode = new_mode
	seed_value = new_seed
	_rng.seed = new_seed
	_t = _rng.randf() * 100.0
	_next_event = _rng.randf_range(1.5, 6.0)
	_burst_left = 0.0
	_hold = 0.0
	override_level = -1.0
	_swing = Vector2(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.05))
	_swing_v = Vector2.ZERO
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if buzz and buzz.stream:
		if active and mode != "dead":
			if not buzz.playing:
				buzz.play(_rng.randf() * 3.0)
		else:
			buzz.stop()
	if active and light:
		level = _behaviour(0.0)
		_prev_level = level
		_apply()


## Force the lamp output for `duration` seconds (level < 0 releases).
func force(lvl: float, duration: float) -> void:
	override_level = lvl
	override_time = duration


func _process(delta: float) -> void:
	_t += delta
	var target := _behaviour(delta)
	if override_level >= 0.0:
		override_time -= delta
		target = override_level
		if override_time <= 0.0:
			override_level = -1.0
	level = target
	_apply()
	if pendant:
		_sway(delta)


func _behaviour(delta: float) -> float:
	var hum := 1.0 - 0.035 * (sin(_t * 31.0) * 0.5 + sin(_t * 17.3) * 0.5)
	match mode:
		"dead":
			return 0.0
		"steady":
			_next_event -= delta
			if _next_event <= 0.0:
				_burst_left = _rng.randf_range(0.08, 0.3)
				_next_event = _rng.randf_range(14.0, 30.0)
			if _burst_left > 0.0:
				_burst_left -= delta
				return 0.45 * hum
			return hum
		"end":
			_next_event -= delta
			if _next_event <= 0.0:
				_burst_left = _rng.randf_range(0.15, 0.9)
				_next_event = _rng.randf_range(9.0, 22.0)
			if _burst_left > 0.0:
				_burst_left -= delta
				return _stutter(delta, 0.05, 1.0)
			return hum
		"dying":
			_next_event -= delta
			if _next_event <= 0.0:
				_burst_left = _rng.randf_range(0.06, 0.45)
				_next_event = _rng.randf_range(1.8, 6.0)
			if _burst_left > 0.0:
				_burst_left -= delta
				return _stutter(delta, 0.15, 1.0)
			return 0.14 + 0.04 * sin(_t * 3.1) * sin(_t * 1.3)
		_:
			_next_event -= delta
			if _next_event <= 0.0:
				_burst_left = _rng.randf_range(0.2, 1.4)
				_next_event = _rng.randf_range(2.5, 9.0)
			if _burst_left > 0.0:
				_burst_left -= delta
				return _stutter(delta, 0.0, 1.0)
			return hum


func _stutter(delta: float, lo: float, hi: float) -> float:
	_hold -= delta
	if _hold <= 0.0:
		_hold = _rng.randf_range(0.02, 0.11)
		_burst_level = lo + _rng.randf() * 0.25 if _rng.randf() < 0.55 else hi * _rng.randf_range(0.75, 1.0)
	return _burst_level


func _apply() -> void:
	var l := clampf(level, 0.0, 1.2)
	# incandescent: dim filament glows deep orange
	var col := base_color
	if mode != "end":
		col = Color(1.0, 0.42, 0.14).lerp(base_color, sqrt(clampf(l, 0.0, 1.0)))
	light.light_energy = base_energy * l
	light.light_color = col
	light.visible = l > 0.003
	bulb_mat.emission = col
	bulb_mat.emission_energy_multiplier = 30.0 * pow(l, 1.3) + 0.05
	flare_mat.set_shader_parameter("intensity", pow(l, 1.5) * (1.2 if mode == "end" else 0.75))
	flare_mat.set_shader_parameter("color", col)
	if buzz and buzz.stream:
		buzz.volume_db = linear_to_db(clampf(0.05 + l * 0.7, 0.0001, 1.0)) - 6.0
		buzz.pitch_scale = 0.98 + 0.04 * l
	# sudden drop -> zap + signal (the heartbeat reacts to it)
	if _prev_level - l > 0.5:
		dropped.emit(_prev_level - l)
		if zap and zap.stream and _rng.randf() < 0.6:
			zap.pitch_scale = _rng.randf_range(0.8, 1.25)
			zap.volume_db = -4.0
			zap.play()
	_prev_level = l


func _sway(delta: float) -> void:
	# lightly damped pendulum pushed by gusts
	var w0 := 2.0 * PI * 0.78
	var gust := Vector2(sin(_t * 0.37 + seed_value) + 0.6 * sin(_t * 1.13), cos(_t * 0.29 + seed_value * 0.7) + 0.5 * sin(_t * 0.91)) * 0.035
	var acc := -w0 * w0 * _swing - 0.45 * _swing_v + gust * w0 * w0
	_swing_v += acc * delta
	_swing += _swing_v * delta
	pivot.rotation = Vector3(_swing.x, 0.0, _swing.y)

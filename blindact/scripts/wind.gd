class_name Wind
extends Node
## The night wind outside: calm, then a gust that comes through the trees and
## goes again. One value drives everything that moves with it: the sway of the
## branches and leaves (global shader parameter `wind_gust`, read by the
## foliage shaders, so their shadows on the ground move too), the rustle of
## the leaves and the wind in the pines, and clouds over the moon.

var gust := 0.3                  # 0 calm .. 1 a hard gust
var moon: DirectionalLight3D     # dims as cloud passes over it
var moon_energy := 1.0

var _target := 0.3
var _t := 0.0
var _next := 2.0
var _cloud := 1.0
var _cloud_target := 1.0
var _rustle: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_rustle = _loop("res://assets/audio/leaves_rustle_loop.ogg")
	_wind = _loop("res://assets/audio/wind_loop.ogg")


func _loop(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Ambience"
	p.volume_db = -40.0
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	if p.stream:
		p.play()
		p.finished.connect(p.play)
	return p


func _process(delta: float) -> void:
	_t += delta
	_next -= delta
	if _next <= 0.0:
		# a gust builds, holds, dies; now and then a dead calm
		_target = 0.06 if _rng.randf() < 0.18 else _rng.randf_range(0.3, 1.0)
		_next = _rng.randf_range(2.5, 7.5)
		if _rng.randf() < 0.3:
			_cloud_target = _rng.randf_range(0.35, 1.0)
	gust = move_toward(gust, _target, delta * (0.45 if _target > gust else 0.22))
	_cloud = move_toward(_cloud, _cloud_target, delta * 0.08)
	var flutter := gust * (1.0 + 0.18 * sin(_t * 2.7) + 0.08 * sin(_t * 7.3))
	RenderingServer.global_shader_parameter_set("wind_gust", flutter)
	if _rustle:
		_rustle.volume_db = linear_to_db(0.04 + 0.96 * gust * gust) - 6.0
	if _wind:
		_wind.volume_db = linear_to_db(0.15 + 0.85 * gust) - 10.0
	if moon:
		moon.light_energy = moon_energy * _cloud

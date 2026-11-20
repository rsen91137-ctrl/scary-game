class_name SensorLight
extends Node3D
## A bare bulb on a motion/sound sensor, the kind that clicks on when you
## make a noise on the stairs and leaves you in the dark a few seconds later.
## Old ones stutter when they come on; dying ones never quite make it.

signal switched(on: bool)

var light: OmniLight3D
var bulb_mat: StandardMaterial3D
var hold := 7.0               # seconds it stays on
var dying := false
var broken := false
var energy := 1.7
var level := 0.0

var _target := 0.0
var _timer := 0.0
var _stutter := 0.0
var _rng := RandomNumberGenerator.new()
var _click: AudioStreamPlayer3D


func _ready() -> void:
	_rng.randomize()
	var sock := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.03
	cm.height = 0.07
	sock.mesh = cm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.045, 0.04)
	dark.roughness = 0.6
	sock.material_override = dark
	sock.position.y = 0.04
	add_child(sock)
	var wire := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.004
	wm.bottom_radius = 0.004
	wm.height = 0.25
	wire.mesh = wm
	wire.material_override = dark
	wire.position.y = 0.2
	add_child(wire)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.09
	bulb.mesh = sm
	bulb_mat = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(0.9, 0.85, 0.75, 0.8)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.62, 0.3)
	bulb_mat.emission_energy_multiplier = 0.0
	bulb.material_override = bulb_mat
	add_child(bulb)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.66, 0.38)
	light.omni_range = 7.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	light.light_size = 0.05
	light.light_volumetric_fog_energy = 0.6
	light.light_energy = 0.0
	light.position.y = -0.06
	add_child(light)
	_click = AudioStreamPlayer3D.new()
	_click.bus = "SFX"
	_click.unit_size = 3.0
	if ResourceLoader.exists("res://assets/audio/relay_click.ogg"):
		_click.stream = load("res://assets/audio/relay_click.ogg")
	add_child(_click)


## Something made a noise near the sensor.
func trigger() -> void:
	if broken:
		return
	if _target < 0.5:
		_stutter = _rng.randf_range(0.15, 0.6) if (dying or _rng.randf() < 0.3) else 0.0
		if _click.stream:
			_click.pitch_scale = _rng.randf_range(0.9, 1.1)
			_click.play()
		switched.emit(true)
	_target = 1.0
	_timer = hold * (_rng.randf_range(0.5, 0.8) if dying else 1.0)


func kill() -> void:
	_timer = 0.0


func _process(delta: float) -> void:
	if _target > 0.5:
		_timer -= delta
		if _timer <= 0.0:
			_target = 0.0
			switched.emit(false)
	var want := _target
	if _stutter > 0.0:
		_stutter -= delta
		want = _target * (1.0 if _rng.randf() < 0.45 else 0.05)
	if dying and _target > 0.5 and _rng.randf() < delta * 2.0:
		want *= _rng.randf_range(0.2, 0.7)
	# filament: quick on, slower glow off
	level = move_toward(level, want, delta * (14.0 if want > level else 3.5))
	light.light_energy = energy * level
	bulb_mat.emission_energy_multiplier = 6.0 * level
	light.visible = level > 0.003

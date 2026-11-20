class_name WhisperPlayer
extends Node
## The man's whispers (assets/audio/voice). Each line is played on the Voice
## bus, panned to a random side, and announced with whispered(...) so the
## red subtitle can appear on that side of the screen.

signal whispered(line: int, pan: float, duration: float)

const LINES := 12
var _player: AudioStreamPlayer
var _murmur: AudioStreamPlayer
var _panner: AudioEffectPanner
var _rng := RandomNumberGenerator.new()
var _last := -1


func _ready() -> void:
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)
	_murmur = AudioStreamPlayer.new()
	_murmur.bus = "Voice"
	add_child(_murmur)
	var vo := AudioServer.get_bus_index("Voice")
	for k in AudioServer.get_bus_effect_count(vo):
		if AudioServer.get_bus_effect(vo, k) is AudioEffectPanner:
			_panner = AudioServer.get_bus_effect(vo, k)


func _lang() -> String:
	return "zh" if TranslationServer.get_locale().begins_with("zh") else "en"


## Plays a line (random if line < 1). Returns its duration.
func whisper(line := -1, pan := 999.0, vol_db := -4.0) -> float:
	if line < 1:
		line = _rng.randi_range(1, LINES)
		if line == _last:
			line = line % LINES + 1
	_last = line
	var path := "res://assets/audio/voice/whisper_%s_%d.ogg" % [_lang(), line]
	if not ResourceLoader.exists(path):
		return 0.0
	if pan > 1.5:
		pan = _rng.randf_range(0.45, 0.95) * (1.0 if _rng.randf() < 0.5 else -1.0)
	if _panner:
		_panner.pan = pan
	_player.stream = load(path)
	_player.volume_db = vol_db
	_player.pitch_scale = _rng.randf_range(0.93, 1.02)
	_player.play()
	var dur: float = _player.stream.get_length() / _player.pitch_scale
	whispered.emit(line, pan, dur)
	return dur


func murmur(vol_db := -14.0) -> void:
	var path := "res://assets/audio/voice/murmur_%d.ogg" % _rng.randi_range(1, 4)
	if ResourceLoader.exists(path):
		_murmur.stream = load(path)
		_murmur.volume_db = vol_db
		_murmur.play()


func is_playing() -> bool:
	return _player.playing

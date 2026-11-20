extends Node
## Autoload "Settings": persistent player options (user://settings.cfg),
## audio bus setup, the microphone input and window/vsync application.
## Scenes listen to `changed` to apply graphics quality and brightness.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_KEYS := ["Q_LOW", "Q_MEDIUM", "Q_HIGH", "Q_ULTRA"]

var brightness := 1.0        # display brightness multiplier 0.5 .. 1.6
var master_volume := 0.9
var music_volume := 0.8
var sfx_volume := 0.9
var fullscreen := true
var vsync := true
var quality := 2             # 0 low .. 3 ultra
var shake := 1.0             # heartbeat screen shake strength 0 .. 1.5
var film_grain := true
var language := "zh_CN"       # see I18n.LANGUAGES
var mouse_sensitivity := 1.0  # 0.3 .. 2.0
var subtitles := true
# microphone ("don't make a sound") -----------------------------------------
var mic_enabled := true
var mic_device := "Default"
var mic_sensitivity := 1.0    # 0.5 (forgiving) .. 1.5 (strict)
var mic_noise_db := -58.0     # calibrated room noise (dBFS)
var mic_voice_db := -26.0     # calibrated normal speaking level (dBFS)
var mic_calibrated := false
var difficulty := 1           # 0 easy, 1 normal, 2 hard, 3 nightmare
var mic_this_run := true      # chosen on the calibration screen (not saved)

var mic_player: AudioStreamPlayer
var mic_capture: AudioEffectCapture


func _ready() -> void:
	_setup_buses()
	I18n.register()
	load_settings()
	apply()
	_setup_mic()


func _add_bus(bus_name: String, send := "Master") -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, send)
	return idx


func _setup_buses() -> void:
	for bus_name: String in ["Music", "SFX", "Ambience", "Body", "Voice", "Piano"]:
		_add_bus(bus_name)
	# the house: a small, damp room
	var amb := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(amb) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.5
		rv.damping = 0.55
		rv.wet = 0.2
		rv.dry = 1.0
		rv.spread = 0.8
		AudioServer.add_bus_effect(amb, rv)
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rv2 := AudioEffectReverb.new()
		rv2.room_size = 0.35
		rv2.damping = 0.65
		rv2.wet = 0.14
		AudioServer.add_bus_effect(sfx, rv2)
	# the old upright in a high-ceilinged room
	var pno := AudioServer.get_bus_index("Piano")
	if AudioServer.get_bus_effect_count(pno) == 0:
		var rv3 := AudioEffectReverb.new()
		rv3.room_size = 0.62
		rv3.damping = 0.5
		rv3.wet = 0.26
		rv3.dry = 0.95
		rv3.spread = 0.9
		rv3.predelay_msec = 18.0
		AudioServer.add_bus_effect(pno, rv3)
	# voices (the man, the whispers): panned per line, close and intimate
	var vo := AudioServer.get_bus_index("Voice")
	if AudioServer.get_bus_effect_count(vo) == 0:
		AudioServer.add_bus_effect(vo, AudioEffectPanner.new())
		var rv4 := AudioEffectReverb.new()
		rv4.room_size = 0.3
		rv4.damping = 0.7
		rv4.wet = 0.12
		AudioServer.add_bus_effect(vo, rv4)
	# low-pass on the world buses: the director closes it for muffling
	for bus_name: String in ["Music", "Ambience", "SFX", "Piano", "Voice"]:
		var bi := AudioServer.get_bus_index(bus_name)
		var has_lp := false
		for k in AudioServer.get_bus_effect_count(bi):
			has_lp = has_lp or AudioServer.get_bus_effect(bi, k) is AudioEffectLowPassFilter
		if not has_lp:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20000.0
			lp.resonance = 0.6
			AudioServer.add_bus_effect(bi, lp)
	# body sounds (heartbeat, breathing) are "inside the head": dry, compressed
	var body := AudioServer.get_bus_index("Body")
	if AudioServer.get_bus_effect_count(body) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14.0
		comp.ratio = 3.0
		AudioServer.add_bus_effect(body, comp)
	# microphone: captured for analysis, never played back
	var mic := _add_bus("Mic")
	if AudioServer.get_bus_effect_count(mic) == 0:
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(mic, cap)
	AudioServer.set_bus_mute(mic, true)
	mic_capture = AudioServer.get_bus_effect(mic, 0) as AudioEffectCapture


## Starts (or restarts) the microphone stream. Effects run before the bus
## mute, so the capture effect still receives the input while nothing is heard.
func _setup_mic() -> void:
	if mic_player == null:
		mic_player = AudioStreamPlayer.new()
		mic_player.bus = "Mic"
		mic_player.name = "MicInput"
		add_child(mic_player)
	mic_player.stop()
	if not mic_enabled or _is_headless():
		return
	var devices := AudioServer.get_input_device_list()
	if mic_device in devices:
		AudioServer.input_device = mic_device
	else:
		AudioServer.input_device = "Default"
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.play()
	if mic_capture:
		mic_capture.clear_buffer()


func input_devices() -> Array[String]:
	var out: Array[String] = []
	for d: String in AudioServer.get_input_device_list():
		out.append(d)
	if out.is_empty():
		out.append("Default")
	return out


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	brightness = cf.get_value("video", "brightness", brightness)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	vsync = cf.get_value("video", "vsync", vsync)
	quality = cf.get_value("video", "quality", quality)
	film_grain = cf.get_value("video", "film_grain", film_grain)
	shake = cf.get_value("video", "shake", shake)
	master_volume = cf.get_value("audio", "master", master_volume)
	music_volume = cf.get_value("audio", "music", music_volume)
	sfx_volume = cf.get_value("audio", "sfx", sfx_volume)
	language = cf.get_value("general", "language", language)
	mouse_sensitivity = cf.get_value("general", "mouse_sensitivity", mouse_sensitivity)
	subtitles = cf.get_value("general", "subtitles", subtitles)
	difficulty = cf.get_value("general", "difficulty", difficulty)
	mic_enabled = cf.get_value("mic", "enabled", mic_enabled)
	mic_device = cf.get_value("mic", "device", mic_device)
	mic_sensitivity = cf.get_value("mic", "sensitivity", mic_sensitivity)
	mic_noise_db = cf.get_value("mic", "noise_db", mic_noise_db)
	mic_voice_db = cf.get_value("mic", "voice_db", mic_voice_db)
	mic_calibrated = cf.get_value("mic", "calibrated", mic_calibrated)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "brightness", brightness)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "film_grain", film_grain)
	cf.set_value("video", "shake", shake)
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("general", "language", language)
	cf.set_value("general", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("general", "subtitles", subtitles)
	cf.set_value("general", "difficulty", difficulty)
	cf.set_value("mic", "enabled", mic_enabled)
	cf.set_value("mic", "device", mic_device)
	cf.set_value("mic", "sensitivity", mic_sensitivity)
	cf.set_value("mic", "noise_db", mic_noise_db)
	cf.set_value("mic", "voice_db", mic_voice_db)
	cf.set_value("mic", "calibrated", mic_calibrated)
	cf.save(PATH)


func apply() -> void:
	if not _is_headless():
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
			if not fullscreen:
				var scr := DisplayServer.screen_get_size()
				var size := Vector2i(int(scr.x * 0.75), int(scr.y * 0.75))
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position((scr - size) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	TranslationServer.set_locale(language)
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambience", sfx_volume)
	_set_bus("Body", sfx_volume)
	_set_bus("Voice", sfx_volume)
	_set_bus("Piano", sfx_volume)
	changed.emit()


func apply_mic() -> void:
	_setup_mic()
	changed.emit()


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

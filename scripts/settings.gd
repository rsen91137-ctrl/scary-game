extends Node
## Autoload "Settings": persistent player options (user://settings.cfg),
## audio bus setup and window/vsync application. Scenes listen to `changed`
## to apply graphics quality and brightness.

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


func _ready() -> void:
	_setup_buses()
	I18n.register()
	load_settings()
	apply()


func _setup_buses() -> void:
	for bus_name: String in ["Music", "SFX", "Ambience", "Body"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# a little space on the world sounds (footsteps under the pergola, lamps)
	var amb := AudioServer.get_bus_index("Ambience")
	if AudioServer.get_bus_effect_count(amb) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.45
		rv.damping = 0.6
		rv.wet = 0.18
		rv.dry = 1.0
		rv.spread = 0.8
		AudioServer.add_bus_effect(amb, rv)
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rv2 := AudioEffectReverb.new()
		rv2.room_size = 0.3
		rv2.damping = 0.7
		rv2.wet = 0.12
		AudioServer.add_bus_effect(sfx, rv2)
	# low-pass on the world buses: the director closes it during tinnitus/vertigo
	for bus_name: String in ["Music", "Ambience", "SFX"]:
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
	changed.emit()


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

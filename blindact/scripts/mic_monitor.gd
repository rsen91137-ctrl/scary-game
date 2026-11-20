class_name MicMonitor
extends Node
## Reads the microphone capture effect set up by Settings and turns it into
## levels the game can judge: a fast level, a slow room baseline, and
## "sounds" = the level staying clearly above the calibrated threshold for a
## while (short clicks from a keyboard are ignored; a gasp or a word is not).

signal sound_started(db: float)
signal sound_ended(db_peak: float, duration: float)

var level_db := -90.0        # ~50 ms
var baseline_db := -60.0     # slow room level
var peak_db := -90.0         # decaying peak for meters
var active := false          # true while a sound is going on
var digital_silence := 0.0   # seconds of exact zeros (no device / muted)
var enabled := true

const MIN_SOUND := 0.12      # a sound must last this long to count

var _above := 0.0
var _sound_peak := -90.0
var _sound_len := 0.0


func threshold_db() -> float:
	## Between the calibrated room noise and the calibrated gasp, moved by the
	## sensitivity setting (higher sensitivity = lower threshold).
	var noise := Settings.mic_noise_db
	var voice := maxf(Settings.mic_voice_db, noise + 8.0)
	var k := clampf(0.55 - 0.3 * (Settings.mic_sensitivity - 1.0), 0.2, 0.85)
	return maxf(noise + (voice - noise) * k, baseline_db + 6.0)


func has_input() -> bool:
	return Settings.mic_enabled and Settings.mic_capture != null and digital_silence < 2.5


func _process(delta: float) -> void:
	var cap: AudioEffectCapture = Settings.mic_capture
	if cap == null or not Settings.mic_enabled:
		level_db = -90.0
		return
	var n := cap.get_frames_available()
	if n > 0:
		var buf := cap.get_buffer(n)
		var acc := 0.0
		var zeros := true
		for f: Vector2 in buf:
			var m := (f.x + f.y) * 0.5
			acc += m * m
			if zeros and (f.x != 0.0 or f.y != 0.0):
				zeros = false
		var rms := sqrt(acc / float(n))
		var db := linear_to_db(maxf(rms, 0.00001))
		level_db = lerpf(level_db, db, 1.0 - exp(-delta / 0.05))
		digital_silence = digital_silence + delta if zeros else 0.0
	peak_db = maxf(level_db, peak_db - delta * 30.0)
	if not enabled:
		return
	var thr := threshold_db()
	if level_db > thr:
		_above += delta
		_sound_peak = maxf(_sound_peak, level_db)
		if not active and _above >= MIN_SOUND:
			active = true
			_sound_len = _above
			sound_started.emit(level_db)
		elif active:
			_sound_len += delta
	else:
		if active:
			active = false
			sound_ended.emit(_sound_peak, _sound_len)
		_above = 0.0
		_sound_peak = -90.0
		# the room baseline only follows quiet periods
		baseline_db = lerpf(baseline_db, level_db, 1.0 - exp(-delta / 2.5))

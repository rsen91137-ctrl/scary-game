class_name Difficulty
extends RefCounted
## Everything a difficulty level changes, in one table. Read with
## Difficulty.get_value("key"), which uses Settings.difficulty.
##
##   mic_k            where the "you made a sound" threshold sits between the
##                    calibrated room noise (0) and the calibrated gasp (1);
##                    > 1 means louder than a gasp (only screams count)
##   mic_min_len      how long a sound must last to count (s)
##   scare_rate       multiplier on how often scares/tests happen
##   scare_intensity  0..1, how far the scares go
##   suspicion_gain   multiplier on suspicion from every tell
##   suspicion_decay  suspicion lost per second when you behave
##   suspicion_max    suspicion at which he knows
##   fixate_time      seconds you may rest your gaze on something while watched
##   clue_glow        0..1, how much evidence gives itself away (glint, sound)
##   decoys           number of false clues
##   frame_gain       multiplier on the frame meter
##   chase_speed      killer speed multiplier in the chase
##   hearing_m        how far he hears you in the chase (m)
##   warn_watched     whether you get a hint when he is watching you

const PRESETS := [
	{   # easy
		"mic_k": 1.25, "mic_min_len": 0.22, "scare_rate": 0.7, "scare_intensity": 0.6,
		"suspicion_gain": 0.6, "suspicion_decay": 1.6, "suspicion_max": 100.0, "fixate_time": 1.6,
		"clue_glow": 0.8, "decoys": 0, "frame_gain": 0.7, "chase_speed": 0.85, "hearing_m": 4.0,
		"warn_watched": true,
	},
	{   # normal
		"mic_k": 0.55, "mic_min_len": 0.12, "scare_rate": 1.0, "scare_intensity": 0.85,
		"suspicion_gain": 1.0, "suspicion_decay": 1.0, "suspicion_max": 100.0, "fixate_time": 1.0,
		"clue_glow": 0.0, "decoys": 0, "frame_gain": 1.0, "chase_speed": 1.0, "hearing_m": 6.0,
		"warn_watched": false,
	},
	{   # hard
		"mic_k": 0.35, "mic_min_len": 0.08, "scare_rate": 1.3, "scare_intensity": 1.0,
		"suspicion_gain": 1.4, "suspicion_decay": 0.7, "suspicion_max": 100.0, "fixate_time": 0.7,
		"clue_glow": 0.0, "decoys": 2, "frame_gain": 1.3, "chase_speed": 1.12, "hearing_m": 8.0,
		"warn_watched": false,
	},
	{   # nightmare
		"mic_k": 0.2, "mic_min_len": 0.05, "scare_rate": 1.6, "scare_intensity": 1.0,
		"suspicion_gain": 99.0, "suspicion_decay": 0.0, "suspicion_max": 1.0, "fixate_time": 0.45,
		"clue_glow": 0.0, "decoys": 3, "frame_gain": 1.6, "chase_speed": 1.25, "hearing_m": 11.0,
		"warn_watched": false,
	},
]


static func get_value(key: String) -> Variant:
	var i := clampi(Settings.difficulty, 0, PRESETS.size() - 1)
	return PRESETS[i].get(key, PRESETS[1][key])

extends Node
## Development helper (only with the user arg --capture):
##   --shots=2,6,12      seconds at which to save screenshots
##   --out=/abs/dir      where to save them
##   --lang=en           UI language
##   --quality=N         graphics preset
## Scene-specific flags are read by each scene's director.

var _shots: Array[float] = []
var _out := "user://shots"
var _t := 0.0
var _idx := 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			for s: String in a.substr(8).split(","):
				_shots.append(float(s))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--quality="):
			Settings.quality = int(a.substr(10))
			Settings.apply()
		elif a.begins_with("--lang="):
			Settings.language = a.substr(7)
			Settings.apply()
	DirAccess.make_dir_recursive_absolute(_out)


func _process(delta: float) -> void:
	_t += delta
	if _idx < _shots.size() and _t >= _shots[_idx]:
		var img := get_viewport().get_texture().get_image()
		var path := "%s/shot_%02d.png" % [_out, _idx]
		img.save_png(path)
		print("CAPTURE ", path, " fps=", Engine.get_frames_per_second())
		_idx += 1
		if _idx >= _shots.size():
			get_tree().quit()

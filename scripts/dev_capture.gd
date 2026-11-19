extends Node
## Development helper (only active with the user arg --capture):
##   --shots=2,6,12      seconds at which to save screenshots
##   --out=/abs/dir      where to save them
##   --z=-20             teleport the walker to this z first
## Usage: godot --path . -- --capture --shots=8 --out=/tmp/shots

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
		elif a.begins_with("--exposure="):
			var w := get_parent().get("world") as Node
			if w:
				var e: Environment = w.get("env")
				w.set("base_exposure", float(a.substr(11)))
				e.tonemap_exposure = float(a.substr(11))
		elif a.begins_with("--atlas="):
			get_viewport().positional_shadow_atlas_size = int(a.substr(8))
		elif a.begins_with("--testlight"):
			var tl := OmniLight3D.new()
			tl.light_energy = 4.0
			tl.omni_range = 12.0
			tl.position = Vector3(0.0, 2.0, -3.0)
			get_parent().add_child(tl)
		elif a.begins_with("--noshadows"):
			for lamp: Node3D in (get_parent().get("corridor") as Node3D).get("lamps"):
				(lamp.get("light") as OmniLight3D).shadow_enabled = false
		elif a.begins_with("--nolightsize"):
			for lamp: Node3D in (get_parent().get("corridor") as Node3D).get("lamps"):
				(lamp.get("light") as OmniLight3D).light_size = 0.0
		elif a.begins_with("--nomsaa"):
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		elif a.begins_with("--nofog"):
			var w2 := get_parent().get("world") as Node
			if w2:
				var e2: Environment = w2.get("env")
				e2.volumetric_fog_enabled = false
				e2.fog_enabled = false
				(w2.get("mist") as Node3D).visible = false
				(w2.get("lake_mist") as Node3D).visible = false
		elif a.begins_with("--settings"):
			get_tree().create_timer(0.3).timeout.connect(func() -> void: (get_parent().get("ui") as Node).call("_on_settings"))
		elif a.begins_with("--lang="):
			Settings.language = a.substr(7)
			Settings.apply()
		elif a.begins_with("--episode="):
			get_parent().call("_start_episode", a.substr(10))
		elif a.begins_with("--firstep="):
			get_parent().set("next_episode", float(a.substr(10)))
		elif a.begins_with("--noui"):
			var ui := get_parent().get("ui") as Control
			if ui:
				ui.visible = false
		elif a.begins_with("--z="):
			var w := get_parent().get_node_or_null("Walker")
			if w:
				w.call("reset_to", float(a.substr(4)))
	DirAccess.make_dir_recursive_absolute(_out)
	if OS.get_cmdline_user_args().has("--dump"):
		_dump.call_deferred()


func _dump() -> void:
	await get_tree().create_timer(0.5).timeout
	var c := get_parent().get("corridor") as Node3D
	var w := get_parent().get("walker") as Node3D
	print("walker ", w.global_position, " cam ", (w.get("cam") as Camera3D).global_position, " fwd ", -(w.get("cam") as Camera3D).global_basis.z)
	print("cam current: ", (w.get("cam") as Camera3D).current, " vp cam: ", get_viewport().get_camera_3d())
	for lamp: Node3D in c.get("lamps"):
		var l: OmniLight3D = lamp.get("light")
		print("lamp ", lamp.name, " pos ", l.global_position, " energy ", l.light_energy, " vis ", l.is_visible_in_tree(), " level ", lamp.get("level"))
	print("children of corridor: ", c.get_child_count())


var _trace_t := 0.0
var _last_state := ""


func _trace(delta: float) -> void:
	var d := get_parent()
	var st: String = d.get("state")
	_trace_t += delta
	if st != _last_state or _trace_t >= 5.0:
		_trace_t = 0.0
		_last_state = st
		var body: Node = d.get("body")
		var w: Node3D = d.get("walker")
		print("t=%6.1f state=%-8s z=%7.2f stress=%.2f bpm=%5.1f fade=%.2f breath=%s" % [_t, st, w.position.z, body.get("stress"), body.get("bpm"), d.get("fade"), body.call("_breath_set")])


func _process(delta: float) -> void:
	_t += delta
	if OS.get_cmdline_user_args().has("--trace"):
		_trace(delta)
	if _idx < _shots.size() and _t >= _shots[_idx]:
		var img := get_viewport().get_texture().get_image()
		var path := "%s/shot_%02d.png" % [_out, _idx]
		img.save_png(path)
		print("CAPTURE ", path, " fps=", Engine.get_frames_per_second())
		_idx += 1
		if _idx >= _shots.size():
			get_tree().quit()

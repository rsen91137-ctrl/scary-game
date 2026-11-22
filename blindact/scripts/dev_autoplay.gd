extends Node
## Development only (user arg --autoplay): plays the whole night like a
## careful player so every sequence runs headless and errors surface.
##   --autoplay           behave (survive)
##   --autoplay=expose    make a sound during the first test (-> the chase)

var game: Node
var mode := "behave"
var _t := 0.0
var _act := ""
var _act_t := 0.0
var _did := {}


func _ready() -> void:
	game = get_parent()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay="):
			mode = a.substr(11)
	print("[auto] mode ", mode)


func _once(key: String) -> bool:
	if _did.has(key):
		return false
	_did[key] = true
	return true


func _process(delta: float) -> void:
	_t += delta
	var act: String = game.get("act")
	if act != _act:
		print("[auto] t=%.1f act %s -> %s  susp=%.0f frame=%.0f" % [_t, _act, act, game.state.suspicion, game.state.frame])
		_act = act
		_act_t = 0.0
	_act_t += delta
	var p: Player = game.player
	var piano: PianoGame = game.piano_ui
	if piano.active:
		# perfect playing
		for n: Array in piano.notes:
			if int(n[3]) == 0 and absf(float(n[0]) - piano.t) < 0.03:
				var ev := InputEventKey.new()
				ev.keycode = PianoGame.KEYS[int(n[1])]
				ev.pressed = true
				piano._unhandled_input(ev)
	match act:
		"home":
			if fmod(_act_t, 1.5) < get_process_delta_time():
				for id: String in ["home_phone", "glasses", "cane", "home_door"]:
					p.interacted.emit(id)
			if _act_t > 10.0:
				game.set("_clicks", 2)
		"outside":
			if _act_t > 4.0 and _once("to_unit") and game.ext:
				p.global_position = game.ext_spot("her_unit_door") + Vector3(0, 0.1, 0)
			if _act_t > 5.0 and fmod(_act_t, 1.0) < get_process_delta_time():
				p.interacted.emit("her_unit")
		"forest":
			# run the forest path to the road, a little faster than he can
			if _once("fpath"):
				set_meta("fpts", game.ext.path(p.global_position, game.ext_spot("forest_exit")))
				set_meta("fi", 0)
				set_meta("fu", 0.0)
			var fp: PackedVector3Array = get_meta("fpts")
			var fi: int = get_meta("fi")
			if fi < fp.size() - 1:
				var fu: float = float(get_meta("fu")) + delta * 3.2 / maxf(0.01, fp[fi].distance_to(fp[fi + 1]))
				if fu >= 1.0:
					fu = 0.0
					fi += 1
					set_meta("fi", fi)
				set_meta("fu", fu)
				if fi < fp.size() - 1:
					p.global_position = fp[fi].lerp(fp[fi + 1], fu) + Vector3(0, 0.1, 0)
		"door_chase":
			# run down the stairs, a little faster than he can follow
			var H := StairBuilder.H
			var k: int = game.stairs.her_floor
			if _once("runpath"):
				var pts: Array[Vector3] = []
				for f in range(k, 0, -1):
					var y := H * f
					pts.append_array([Vector3(0.0, y, 0.3), Vector3(0.68, y, 1.25), Vector3(0.68, y - H * 0.5, 3.45),
						Vector3(0.0, y - H * 0.5, 4.1), Vector3(-0.68, y - H * 0.5, 3.45), Vector3(-0.68, y - H, 1.25), Vector3(0.0, y - H, 0.3)])
				pts.append(Vector3(-0.68, 0.0, 0.4))
				set_meta("pts", pts)
				set_meta("i", 0)
				set_meta("u", 0.0)
			var pts: Array = get_meta("pts")
			var i: int = get_meta("i")
			if i < pts.size() - 1:
				var u: float = float(get_meta("u")) + delta * 3.1 / maxf(0.01, Vector3(pts[i]).distance_to(pts[i + 1]))
				if u >= 1.0:
					u = 0.0
					i += 1
					set_meta("i", i)
				set_meta("u", u)
				if i < pts.size() - 1:
					p.global_position = game.stairs.to_global(Vector3(pts[i]).lerp(pts[i + 1], u) + Vector3(0, 0.05, 0))
		"stairs":
			if mode == "run" and p.mode == "walk" and game.ui.get("_hint").text != "" and _act_t > 3.0 and game.man.visible and _once("flee"):
				p.global_position += Vector3(0.0, 0.0, 1.5).rotated(Vector3.UP, p.yaw + PI)
			if _act_t > 3.0 and _once("climb2"):
				p.global_position = game.stairs.to_global(Vector3(-0.6, StairBuilder.H * game.stairs.her_floor + 0.05, -0.4))
			if _act_t > 5.0 and fmod(_act_t, 1.5) < get_process_delta_time():
				p.interacted.emit("her_door")
			if p.expect_gesture:
				p.gesture.emit("nod")
		"flat":
			if mode == "expose" and _act_t > 15.0 and _once("noise"):
				game.state.expose("TELL_VOICE")
			# the owner's test: a scream into the microphone, at any moment at all
			if mode == "scream" and _act_t > 14.0:
				if _once("scream"):
					game.mic.set_process(false)
					Settings.mic_this_run = true
					Settings.mic_noise_db = -50.0
					Settings.mic_voice_db = -25.0
					print("[auto] screaming: tests open=%d susp=%.0f" % [game.state._tests.size(), game.state.suspicion])
				game.mic.level_db = -4.0
			if p.expect_gesture:
				p.gesture.emit("nod")
			var obj: String = game.ui.get("_objective").text
			var sp: Dictionary = game.flat.spots
			var tick := fmod(_act_t, 1.0) < get_process_delta_time()
			game.set_meta("bot_eat", p.mode == "seated" and game.scares.room_at(p.global_position) == "dining" and fmod(_t, 1.9) < 1.25)
			if bool(game.get("entering")):
				if _act_t > 6.0 and _once("to_piano"):
					p.global_position = sp.piano_seat + Vector3(0.7, 0.05, 0.0)
			elif obj == tr("OBJ_PREFIX") + tr("OBJ_BATH"):
				if p.mode == "walk" and game.scares.room_at(p.global_position) != "bath":
					p.global_position = Vector3(1.2, 0.05, 4.35)
				elif tick:
					p.interacted.emit("cabinet")
					p.interacted.emit("sink")
			elif obj == tr("OBJ_PREFIX") + tr("OBJ_BACK"):
				if p.mode == "walk" and p.global_position.distance_to(sp.piano_seat) > 1.2:
					p.global_position = sp.piano_seat + Vector3(0.5, 0.05, 0.0)
			elif obj == tr("OBJ_PREFIX") + tr("OBJ_KITCHEN") or obj == tr("OBJ_PREFIX") + tr("OBJ_PLATES") or obj == tr("OBJ_PREFIX") + tr("OBJ_CUTLERY"):
				if p.mode == "walk" and game.scares.room_at(p.global_position) != "kitchen":
					p.global_position = sp.get("kitchen_mid", Vector3(-7.5, 0.0, 7.0)) + Vector3(0, 0.05, 0)
				elif tick:
					for id: String in ["plates", "lay_plates", "cutlery", "lay_cutlery"]:
						p.interacted.emit(id)
			elif obj == tr("OBJ_PREFIX") + tr("OBJ_DINNER"):
				if p.mode == "walk" and p.global_position.distance_to(sp.get("dinner_seat", Vector3(-7.0, 0.0, 2.95))) > 0.8:
					p.global_position = sp.get("dinner_seat", Vector3(-7.0, 0.0, 2.95)) + Vector3(0, 0.05, 0)
			elif obj == tr("OBJ_PREFIX") + tr("OBJ_ATTIC"):
				if p.mode == "walk" and game.scares.room_at(p.global_position) != "attic":
					p.global_position = sp.get("attic_arrive", Vector3(-2.9, 2.95, 6.0)) + Vector3(0, 0.05, 0)
			elif obj == tr("OBJ_PREFIX") + tr("OBJ_BED"):
				if tick:
					p.interacted.emit("attic_bed")
		"chase":
			if _once("hide"):
				p.global_position = game.flat.spots.wardrobe_front + Vector3(0, 0.05, 0)
				p.interacted.emit("wardrobe")
			if _act_t > 25.0 and _once("escape"):
				p.interacted.emit("wardrobe")
				p.global_position = game.flat.spots.escape + Vector3(0, 0.05, 0)
				p.interacted.emit("window_escape")
		"end":
			if _once("end"):
				print("[auto] END after %.1fs  susp=%.0f frame=%.0f evidence=%s log=%s" % [_t, game.state.suspicion, game.state.frame, game.state.evidence, game.state.log_lines])

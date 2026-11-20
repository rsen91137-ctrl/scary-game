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
		"climb":
			# up to the third floor, where the phone rings
			if _act_t > 2.0 and _once("climb"):
				p.global_position = game.stairs.to_global(Vector3(-0.6, StairBuilder.H + 0.05, -0.4))
		"stairs":
			if _act_t > 3.0 and _once("climb2"):
				p.global_position = game.stairs.to_global(Vector3(-0.6, StairBuilder.H * game.stairs.her_floor + 0.05, -0.4))
			if _act_t > 5.0 and fmod(_act_t, 1.5) < get_process_delta_time():
				p.interacted.emit("her_door")
			if p.expect_gesture:
				p.gesture.emit("nod")
		"flat":
			if mode == "expose" and _act_t > 15.0 and _once("noise"):
				game.state.expose("TELL_VOICE")
			if p.expect_gesture:
				p.gesture.emit("nod")
			# walking parts: walk the hall, wash, come back, leave
			# (never move while he charges: that is exactly the bait)
			if p.mode == "walk" and not piano.active and float(game.get("adrenaline")) < 0.05:
				var bath_done: bool = _did.has("sink")
				if not bath_done:
					if _once("to_bath"):
						p.global_position = Vector3(0.0, 0.05, 3.25)
					elif _act_t > 0.0 and _did.has("to_bath") and not _did.has("in_bath") and p.global_position.z > 3.0:
						_did["in_bath"] = true
						p.global_position = Vector3(1.6, 0.05, 4.2)
					elif _did.has("in_bath") and fmod(_act_t, 1.0) < get_process_delta_time():
						p.interacted.emit("cabinet")
						p.interacted.emit("sink")
						if game.player.mode == "locked":
							_did["sink"] = true
				elif not _did.has("back"):
					if _once("leave_bath"):
						p.global_position = Vector3(0.0, 0.05, 2.0)
					elif _once("back"):
						p.global_position = game.flat.spots.piano_seat + Vector3(0.5, 0.05, 0.0)
				elif _did.has("back") and _act_t > 0.0 and game.state.playing_piano == false and _once("exit_try"):
					pass
				if _did.has("back") and not piano.active and _act_t > 5.0:
					var fi: Vector3 = game.flat.spots.front_inside
					if p.global_position.distance_to(fi) > 0.5 and _did.has("exit_try"):
						p.global_position = fi + Vector3(0, 0.05, 0)
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

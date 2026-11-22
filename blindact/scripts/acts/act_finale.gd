class_name ActFinale
extends Act
## Three in the morning. One more piece for her, the longest. Then he sits
## down on the bench beside you and says the thing he has been turning over
## all night. If someone heard you tonight, they are on the stairs.

func run() -> void:
	var p: Player = g.player
	g._tr("finale")
	g.ui.fade_to(1.0, 0.8)
	await wait(1.0)
	if not alive():
		return
	g.storm(true)
	g._sit_at_piano()
	g.man.visible = true
	g.man.follow_height = false
	g.man.stop()
	g._man_sit_now()
	g.ui.fade_to(0.0, 1.0)
	await wait(1.2)
	await g.man_say("MAN_F_1", 3.2)
	if not alive():
		return
	g.scares.density = 1.6
	g.piano_ui.start(PianoGame.nocturne())
	g.state.playing_piano = true
	g.scares.run(gen)
	g._piano_tests(gen, g.piano_ui.length)
	var sirens: bool = g.police_called
	var siren_at: float = g.piano_ui.length * 0.62
	var t := 0.0
	while alive() and g.piano_ui.active:
		await wait(0.25)
		t += 0.25
		if sirens and t > siren_at:
			sirens = false
			g._sfx("res://assets/audio/siren_far.ogg", -6.0)
			await wait(3.0)
			await g.man_say("MAN_F_SIRENS", 2.4)
			g.state.expose("TELL_SIRENS")
			return
	if not alive():
		return
	g.state.playing_piano = false
	g.scares.density = 1.0
	# he comes and sits beside you on the bench, close, and says it
	var bench: Vector3 = g.flat.spots.piano_seat
	var fwd := Vector3(g.flat.spots.piano_view).normalized()
	var left := Vector3.UP.cross(fwd).normalized()
	await g.man_walk(bench + left * 0.55 - fwd * 0.1, bench + fwd)
	g.man.set_pose("lean_in", 0.8)
	await wait(0.9)
	await g.man_say("MAN_F_KNOW", 3.0)
	if not alive():
		return
	g.state.watched = true
	g.state.visual("final", g.man.bone_pos("head"), 7.0, 1.6)
	g.state.composure(7.0, 1.2)
	g.hush_room(7.0)
	await wait(7.0)
	if not alive():
		return
	await g.man_say("MAN_F_NO", 3.0)
	await g.man_say("MAN_F_GO", 2.6)
	if not alive():
		return
	g.man.set_pose("stand", 0.6)
	g._ending_exit()

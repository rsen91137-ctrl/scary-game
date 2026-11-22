class_name ActOutside
extends RefCounted
## The walk outside: from his door across the estate, past the misty edge of
## the forest, to her block; returns when he uses her unit's door (her_unit).
##
## The game node is expected to have: player (Player), ui (GameUI), world
## (InteriorEnv), amb (AudioStreamPlayer), act, wait(secs), _alive(g), and
## the ExteriorBuilder as `ext` / `exterior` or as a child (one is built and
## placed at (400, 0, 0) if there is none). While the act runs game.act is
## "outside"; game._on_step can ask ext.step_sound(pos) for the right
## footstep. On return the screen is black and the indoor environment is back.
##
##   await ActOutside.new().run(self, _gen)


func run(game: Node, g: int) -> void:
	var gm = game
	var ext := await find_exterior(game)
	if ext == null or not gm._alive(g):
		return
	var player: Player = gm.player
	var ui = gm.ui
	var world: InteriorEnv = gm.world
	gm.act = "outside"
	if gm.get("amb") and gm.amb is AudioStreamPlayer:
		(gm.amb as AudioStreamPlayer).stop()
	ui.fade_now(1.0)
	ext.enter(world.world_env)
	player.velocity = Vector3.ZERO
	player.global_position = ext.spots.his_door
	player.set_mode("walk", ext.spot_yaw.his_door)
	player.yaw = ext.spot_yaw.his_door
	player.pitch = -0.05
	player.cane_enabled = true
	player.snap_eye()
	await gm.wait(0.5)
	if not gm._alive(g):
		ext.exit(world.world_env)
		return
	ui.fade_to(0.0, 2.2)
	await gm.wait(1.4)
	ui.objective("OBJ_OUTSIDE")
	ui.hint_hold("HINT_OUTSIDE")
	var state := {"done": false, "t": 0.0, "hint": true, "strayed": false}
	var cb := func(id: String) -> void: state.done = state.done or id == "her_unit"
	player.interacted.connect(cb)
	var tree := game.get_tree()
	while not bool(state.done):
		await tree.process_frame
		if not gm._alive(g):
			player.interacted.disconnect(cb)
			ext.exit(world.world_env)
			return
		state.t = float(state.t) + game.get_process_delta_time()
		if bool(state.hint) and float(state.t) > 9.0:
			ui.hint_clear()
			state.hint = false
		# wandered off into the trees on the way: remind him where he is going
		var fk := ext.in_forest(player.global_position)
		if fk > 0.45 and not bool(state.strayed):
			state.strayed = true
			ui.hint("HINT_OUTSIDE", 4.0)
		elif fk < 0.1:
			state.strayed = false
	player.interacted.disconnect(cb)
	ui.hint_clear()
	ui.objective("")
	player.set_mode("locked")
	var door: Vector3 = ext.interactables.her_unit.global_position
	player.look_toward(door, 0.5)
	await gm.wait(0.6)
	ui.fade_to(1.0, 0.9)
	await gm.wait(1.1)
	ext.exit(world.world_env)


## The game's ExteriorBuilder (built and placed at (400, 0, 0) if missing).
static func find_exterior(game: Node) -> ExteriorBuilder:
	var ext: ExteriorBuilder = null
	for prop: String in ["ext", "exterior"]:
		var v = game.get(prop)
		if v is ExteriorBuilder:
			ext = v
	if ext == null:
		for c: Node in game.get_children():
			if c is ExteriorBuilder:
				ext = c
	if ext == null:
		ext = ExteriorBuilder.new()
		ext.name = "Exterior"
		ext.position = Vector3(400.0, 0.0, 0.0)
		game.add_child(ext)
	if not ext.spots.has("his_door"):
		if ext.get_child_count() == 0:
			await ext.build()
		else:
			await ext.built
	return ext

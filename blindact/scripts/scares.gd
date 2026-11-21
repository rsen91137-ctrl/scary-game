class_name Scares
extends Node
## Jump scares: how one is delivered (sound, camera, light, grade), the things
## the pianist's panic shows him, and a director that deals them out in a
## different order, at different moments, every night.
##
## Almost all of it is in his head. The husband sees none of it; he only reads
## the player: a sound, a jerk of the view, feet that stop, hands that fumble.

const STINGERS := 12
const MAJORS := ["pop", "lunge", "upside", "side", "rise", "stare", "blackout", "turn"]
## Stingers with no voice in them (scrape, slam, piano), and all of them.
const HARD: Array[int] = [2, 3, 5, 6, 8, 10, 11]
## Places she can stand and be seen from across a room (flat coordinates).
const FAR_SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, 5.7), Vector3(0.0, 0.0, 1.1), Vector3(1.3, 0.0, 4.3),
	Vector3(-1.0, 0.0, 1.9), Vector3(-2.6, 0.0, 1.2), Vector3(-1.6, 0.0, 4.6), Vector3(0.0, 0.0, 7.3),
	Vector3(-3.0, 0.0, 4.4), Vector3(-0.3, 0.0, 3.4)]

var game: Node                # the night's director (game.gd)
var ghost: CharacterRig       # whichever of the two is being shown
var ghost_w: CharacterRig     # her
var ghost_m: CharacterRig     # him, as fear paints him
var busy := 0                 # scripted beats in progress: the random ones wait
var bot := false              # autoplay: no scares that need an answer
var density := 1.0
var count := 0
var majors := 0
var open := 0.0               # the grade opens for a moment so the thing is seen
var showing := false
var dev_hold := 0.0            # (dev) hold every apparition this long, for stills
var dev_who := ""             # (dev) "m" or "w": which face

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _bag: Array[int] = []
var _recent: Array[String] = []
var _last_major := -99.0
var _offs := {}                # rig -> where its head is, in its own space
var _last_sting := 0
var _key: OmniLight3D
var _glitch := 0.0
var _double := 0.0
var _flash := 0.0
var _neg := 0.0
var _shock := 0.0              # the whole picture thrown about
var _scream_last := 0
var _dark := false
var _streams := {}
var _running := false
var _amb_tw: Tween


func setup(p_game: Node) -> void:
	game = p_game
	_rng.randomize()
	if AudioServer.get_bus_index("Scare") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Scare")
		AudioServer.set_bus_send(i, "Master")
		if ClassDB.class_exists("AudioEffectHardLimiter"):
			AudioServer.add_bus_effect(i, ClassDB.instantiate("AudioEffectHardLimiter"))
	for i in STINGERS:
		_load("scare_%02d" % (i + 1))
	for i in 6:
		_load("scream_%d" % (i + 1))
	for n: String in ["flash_tick", "scream_far_1", "scream_far_2", "bang_1", "bang_2", "breath_near", "wet_thud",
			"dread_swell", "relay_click", "whoosh"]:
		_load(n)
	_key = OmniLight3D.new()
	_key.light_color = Color(0.86, 1.0, 0.93)
	_key.omni_range = 2.0
	_key.omni_attenuation = 1.6
	_key.shadow_enabled = false
	_key.visible = false
	add_child(_key)
	ghost_w = _make_ghost("woman", "womang")
	ghost_m = _make_ghost("man", "manm")
	ghost = ghost_w


func _make_ghost(who: String, tex: String) -> CharacterRig:
	var r := CharacterRig.new()
	r.name = "Ghost_" + who
	add_child(r)
	r.setup(who, tex, false)
	r.alive = false
	r.undead = true
	r.visible = false
	return r


func _off() -> Vector3:
	return _offs.get(ghost, Vector3(0.0, 1.5, 0.03))


func _sting(from_hard: bool) -> String:
	var k := 0
	for i in 6:
		k = HARD[_rng.randi() % HARD.size()] if from_hard else _rng.randi_range(1, STINGERS)
		if k != _last_sting:
			break
	_last_sting = k
	return "scare_%02d" % k


func _load(n: String) -> void:
	var p := "res://assets/audio/%s.ogg" % n
	if ResourceLoader.exists(p):
		_streams[n] = load(p)


func _play(n: String, vol := 0.0) -> void:
	if not _streams.has(n):
		return
	var p := AudioStreamPlayer.new()
	p.bus = "Scare"
	p.stream = _streams[n]
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _play3d(n: String, pos: Vector3, vol := 0.0, unit := 3.0) -> void:
	if not _streams.has(n):
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = "Scare"
	p.stream = _streams[n]
	p.volume_db = vol
	p.unit_size = unit
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Under the loading fade: draw her once so nothing hitches the first time.
func prewarm() -> void:
	var p: Player = game.player
	for r: CharacterRig in [ghost_m, ghost_w]:
		ghost = r
		r.set_pose("stand", 0.0)
		_show(p.eye_pos() + p.aim_dir() * 0.7, p.eye_pos(), false, 0.05)
		for i in 3:
			await get_tree().process_frame
		_offs[r] = r.global_transform.affine_inverse() * r.bone_pos("head")
		_hide()


# ---------------------------------------------------------------------------
# delivery
# ---------------------------------------------------------------------------

## The hit itself: a stinger that is never the same twice running, the view
## snapping tight and shaking, torn frames, the lenses clearing for a moment,
## the room's sound dropping out from under it. Then he reads your composure.
func hit(strength := 1.0, sting := true, style := "") -> void:
	count += 1
	var s := clampf(strength, 0.0, 1.3)
	var big := s > 0.7
	if sting and style == "":
		# no two alike: a scream, a blow with no voice in it, the picture
		# first and the sound behind it, or no blow at all
		style = _weighted({"scream": 3.6, "hit": 3.4, "late": 1.6, "quiet": 1.4}) if big else "hit"
	var jolt := s
	if sting:
		var vol := lerpf(-6.0, 4.0, clampf(strength, 0.0, 1.0))
		match style:
			"scream":
				var k := _rng.randi_range(1, 6)
				if k == _scream_last:
					k = k % 6 + 1
				_scream_last = k
				_play("scream_%d" % k, 3.0)
				_play(_sting(true), vol - 4.0)
			"late":
				_play("flash_tick", -9.0)
				jolt = 0.3
				var lt := create_tween()
				lt.tween_interval(_rng.randf_range(0.25, 0.5))
				lt.tween_callback(func() -> void:
					_play(_sting(true), vol)
					_shock = maxf(_shock, s)
					_glitch = 1.0
					game.player.scare_punch(s))
			"quiet":
				_play("breath_near", 2.0)
				_play("wet_thud", -5.0)
				jolt = 0.35
			_:
				_play(_sting(false), vol)
	if big and jolt > 0.7:
		# the picture strobes: blown out, inside out, torn
		var tw := create_tween()
		tw.tween_interval(0.1)
		tw.tween_callback(func() -> void: _flash = 0.5)
		tw.tween_interval(0.1)
		tw.tween_callback(func() -> void: _neg = 1.0)
		tw.tween_interval(0.14)
		tw.tween_callback(func() -> void: _glitch = 1.0)
	_shock = maxf(_shock, jolt)
	game.player.scare_punch(jolt)
	_glitch = maxf(_glitch, jolt)
	_double = maxf(_double, 0.9 * s)
	_flash = maxf(_flash, 0.3 * jolt)
	open = maxf(open, minf(1.0, s * 1.4))
	game.red_flash = maxf(game.red_flash, 0.55 * jolt)
	game.adrenaline = maxf(game.adrenaline, minf(1.0, s))
	game.body.stress = maxf(game.body.stress, minf(1.0, s))
	game.player.heartbeat_kick(1.3 * s)
	game.state.composure(4.5 if big else 2.6, clampf(s, 0.4, 1.0))
	if big:
		hush(1.2, 2.5)


## The room's own sound drops away, then creeps back.
func hush(hold: float, back := 2.0) -> void:
	var amb: AudioStreamPlayer = game.amb
	if amb == null:
		return
	if _amb_tw:
		_amb_tw.kill()
	amb.volume_db = -34.0
	_amb_tw = create_tween()
	_amb_tw.tween_interval(hold)
	_amb_tw.tween_property(amb, "volume_db", -8.0, back)


func _process(delta: float) -> void:
	_t += delta
	_glitch = maxf(0.0, _glitch - delta * 6.5)
	_double = maxf(0.0, _double - delta * 1.3)
	_flash = maxf(0.0, _flash - delta * 9.0)
	_neg = maxf(0.0, _neg - delta * 14.0)
	open = maxf(0.0, open - delta * 0.85)
	_shock = maxf(0.0, _shock - delta * (0.9 + 0.9 * _shock))
	var pm: ShaderMaterial = game.post_mat
	if pm:
		# runs after the director's own _process: the shock rides on top of it
		var sh := _shock * _shock
		pm.set_shader_parameter("tremble", maxf(float(game.adrenaline) * 0.6, sh * 3.6))
		pm.set_shader_parameter("zoom", float(game.adrenaline) * 0.05 + sh * 0.22 * (0.6 + 0.4 * sin(_t * 47.0)))
		pm.set_shader_parameter("aberration", 0.0012 + sh * 0.022)
		pm.set_shader_parameter("blur", sh * 0.35)
		pm.set_shader_parameter("glitch", _glitch)
		pm.set_shader_parameter("ghost", _double)
		pm.set_shader_parameter("flash", _flash)
		pm.set_shader_parameter("negative", 1.0 if _neg > 0.45 else 0.0)


func _put(head_at: Vector3, eye: Vector3, upside: bool, tilt := 0.0) -> void:
	var f := eye - head_at
	f.y = 0.0
	if f.length() < 0.01:
		f = Vector3.BACK
	var b := Basis.looking_at(f.normalized(), Vector3.DOWN if upside else Vector3.UP, true)
	b = b * Basis(Vector3.BACK, tilt)
	ghost.global_transform = Transform3D(b, head_at - b * _off())
	if _key.visible:
		var to := eye - head_at
		_key.global_position = head_at + to.normalized() * minf(0.4, to.length() * 0.6) + Vector3(0.0, 0.14, 0.0)


func _show(head_at: Vector3, eye: Vector3, upside := false, light := 1.0, tilt := 0.0) -> void:
	showing = true
	ghost.visible = true
	ghost.look_node = game.player.head
	_key.visible = true
	_key.light_energy = 0.75 * light
	_put(head_at, eye, upside, tilt)


func _hide() -> void:
	showing = false
	for r: CharacterRig in [ghost_w, ghost_m]:
		if r:
			r.visible = false
	if _key:
		_key.visible = false


func lights(on: bool) -> void:
	if on == (not _dark):
		return
	_dark = not on
	for n: String in game.flat.lamps:
		var l: Light3D = game.flat.lamps[n]
		if is_instance_valid(l):
			l.visible = on


func stop() -> void:
	_running = false
	busy = 0
	_hide()
	lights(true)


# ---------------------------------------------------------------------------
# what he sees
# ---------------------------------------------------------------------------

## Her face, all at once, a hand's breadth from yours.
##   pop     there in one frame, creeping closer
##   lunge   across the room and into your face in a seventh of a second
##   upside  hanging down from above, the wrong way up
##   side    leaning in from the edge of your sight
func pop(kind := "pop", quiet_first := true) -> void:
	if showing:
		return
	busy += 1
	majors += 1
	_last_major = _t
	var p: Player = game.player
	# her, or what fear has made of him
	ghost = ghost_m if _rng.randf() < 0.3 else ghost_w
	if dev_who != "":
		ghost = ghost_m if dev_who == "m" else ghost_w
	# some nights the room goes quiet first; on others there is no warning at all
	if quiet_first and _rng.randf() < 0.4:
		hush(1.6, 1.5)
		await game.wait(_rng.randf_range(0.5, 1.3))
	var eye := p.eye_pos()
	var dir := p.aim_dir()
	dir.y = clampf(dir.y, -0.3, 0.3)
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var upside := kind == "upside"
	var tilt := _rng.randf_range(-0.5, 0.5) if _rng.randf() < 0.6 else 0.0
	var d0 := 0.31
	var off := Vector3.ZERO
	var from_y := 0.0
	match kind:
		"lunge":
			d0 = 2.4
		"side":
			d0 = 0.27
			off = right * (0.17 if _rng.randf() < 0.5 else -0.17)
		"rise":
			from_y = -0.45
		"upside":
			from_y = 0.4
		"stare":
			d0 = _rng.randf_range(1.1, 1.7)
	var yo := Vector3(0.0, -0.02 if upside else 0.02, 0.0)
	ghost.jaw_open = 0.1 if kind == "stare" else 1.0
	ghost.lid_wide = 1.0
	_show(eye + dir * d0 + off + yo + Vector3(0.0, from_y, 0.0), eye, upside, 1.0, tilt)
	if kind == "stare":
		# she only stands there, in arm's reach, and looks. Then she does not.
		game.state.composure(2.0, 0.5)
		game.player.heartbeat_kick(0.5)
		_play("dread_swell", -8.0)
		var w := _rng.randf_range(0.7, 1.8) if dev_hold <= 0.0 else 1.0
		var head_at := ghost.bone_pos("head")
		while w > 0.0 and showing:
			w -= get_process_delta_time()
			_put(head_at, p.eye_pos(), false, tilt + 0.03 * sin(w * 23.0))
			await get_tree().process_frame
		eye = p.eye_pos()
		ghost.jaw_open = 1.0
		kind = "lunge"
	hit(1.0, true, "quiet" if kind == "rise" and _rng.randf() < 0.5 else "")
	if _rng.randf() < 0.4:
		_neg = 1.0
	var hold := _rng.randf_range(0.55, 0.95) if dev_hold <= 0.0 else dev_hold
	if kind == "rise":
		hold += 0.5
	var t := 0.0
	while t < hold and showing:
		t += get_process_delta_time()
		eye = p.eye_pos()
		var k := clampf(t / 0.14, 0.0, 1.0)
		var d := d0 - 0.07 * clampf(t / hold, 0.0, 1.0)
		if kind == "lunge":
			d = lerpf(d0, 0.25, 1.0 - (1.0 - k) * (1.0 - k))
		var yy := from_y * (1.0 - smoothstep(0.0, 0.45 if kind == "rise" else 0.12, t))
		var jit := Vector3(sin(t * 91.0), sin(t * 123.0), 0.0) * 0.005
		_put(eye + dir * d + off * (1.0 - 0.4 * k) + yo + Vector3(0.0, yy, 0.0) + jit, eye, upside, tilt + 0.05 * sin(t * 37.0))
		await get_tree().process_frame
	_hide()
	_neg = 1.0
	busy -= 1
	# sometimes she is not done: again, from somewhere else, before you have breathed
	if _rng.randf() < 0.22 and dev_hold <= 0.0 and _running:
		await game.wait(_rng.randf_range(0.35, 0.9))
		await pop(["side", "pop", "upside"][_rng.randi() % 3], false)


## Three frames of her, and a tick: was that anything at all?
func subliminal() -> void:
	if showing:
		return
	var p: Player = game.player
	var n := 2 if _rng.randf() < 0.3 else 1
	for i in n:
		var eye := p.eye_pos()
		var dir := p.aim_dir()
		dir.y = clampf(dir.y, -0.3, 0.3)
		var upside := _rng.randf() < 0.3
		ghost = ghost_m if _rng.randf() < 0.3 else ghost_w
		ghost.jaw_open = 1.0
		ghost.lid_wide = 1.0
		_show(eye + dir.normalized() * 0.28 + Vector3(0.0, -0.02 if upside else 0.02, 0.0), eye, upside, 1.2)
		_neg = 1.0
		_play("flash_tick", -2.0)
		hit(0.4, false)
		await game.wait(0.08 if dev_hold <= 0.0 else dev_hold)
		_hide()
		if i < n - 1:
			await game.wait(_rng.randf_range(0.18, 0.4))


## She is standing across the room. Look straight at her and she may come.
func far() -> bool:
	if showing:
		return false
	var p: Player = game.player
	var eye := p.eye_pos()
	var aim := p.aim_dir()
	var best := Vector3.INF
	var best_s := -1.0
	for s: Vector3 in FAR_SPOTS:
		var h := s + Vector3(0.0, 1.5, 0.0)
		var to := h - eye
		var d := to.length()
		if d < 2.2 or d > 8.5:
			continue
		var ang := aim.angle_to(to.normalized())
		if ang > deg_to_rad(52.0) or ang < deg_to_rad(7.0):
			continue
		if not game._line_of_sight(eye, h):
			continue
		var sc := _rng.randf()
		if sc > best_s:
			best_s = sc
			best = s
	if best == Vector3.INF:
		return false
	busy += 1
	ghost = ghost_w
	var head_at := best + Vector3(0.0, _off().y, 0.0)
	ghost.jaw_open = 0.3
	ghost.lid_wide = 1.0
	_show(head_at, eye, false, 0.55)
	game.state.visual("ghost", head_at, 3.0, 0.7)
	game.state.composure(2.6, 0.5)
	game.player.heartbeat_kick(0.5)
	_play("dread_swell", -9.0)
	var comes := _rng.randf() < 0.55
	var life := _rng.randf_range(1.5, 2.8) if dev_hold <= 0.0 else dev_hold
	var seen := 0.0
	var t := 0.0
	while t < life and showing:
		var dt := get_process_delta_time()
		t += dt
		if p.aim_dir().angle_to((head_at - p.eye_pos()).normalized()) < deg_to_rad(11.0):
			seen += dt
		if comes and seen > 0.3:
			# you looked. She crosses the room before the frame is over.
			majors += 1
			_last_major = _t
			ghost.jaw_open = 1.0
			hit(1.0)
			var u := 0.0
			while u < 0.75 and showing:
				u += get_process_delta_time()
				var k := clampf(u / 0.2, 0.0, 1.0)
				eye = p.eye_pos()
				var dir := p.aim_dir()
				var target := eye + dir * 0.27 + Vector3(0.0, 0.02, 0.0)
				_put(head_at.lerp(target, 1.0 - (1.0 - k) * (1.0 - k)), eye, false)
				await get_tree().process_frame
			break
		await get_tree().process_frame
	_hide()
	_neg = 1.0
	busy -= 1
	return true


## The lights go. In the dark, a breath. When they come back she may be there.
func blackout() -> void:
	if showing:
		return
	busy += 1
	_play("relay_click", 0.0)
	lights(false)
	hush(2.0, 2.0)
	if _rng.randf() < 0.6:
		_play("breath_near", -3.0)
	await game.wait(_rng.randf_range(1.0, 2.6))
	_play("relay_click", -2.0)
	lights(true)
	busy -= 1
	if _rng.randf() < 0.65:
		await pop("pop", false)
	else:
		game.state.composure(2.0, 0.4)


## Nothing, until you turn round.
func turn_pop(limit := 12.0) -> void:
	var p: Player = game.player
	var yaw0: float = p.yaw
	var t := 0.0
	while t < limit and p.mode == "walk" and _running:
		await game.wait(0.05)
		t += 0.05
		if busy == 0 and absf(wrapf(p.yaw - yaw0, -PI, PI)) > 1.7:
			await pop("pop", false)
			return


## A scream in another room, a breath on your neck, her whisper: only you hear
## it. He heard nothing; turn to it and he knows.
func phantom_sound() -> void:
	var p: Player = game.player
	var back := -p.aim_dir()
	back.y = 0.0
	back = back.normalized()
	var side := back.cross(Vector3.UP) * _rng.randf_range(-1.0, 1.0)
	var pos := p.eye_pos() + (back + side * 0.9).normalized() * _rng.randf_range(0.5, 2.6)
	var n: String = ["scream_far_1", "scream_far_2", "breath_near", "whisper"][_rng.randi() % 4]
	if n == "whisper":
		var w := "res://assets/audio/voice/whisper_%s_%d.ogg" % ["en", _rng.randi_range(1, 10)]
		if ResourceLoader.exists(w):
			game._sfx3d(w, pos, 2.0, 1.2)
		else:
			_play3d("breath_near", pos, 0.0, 1.5)
	else:
		_play3d(n, pos, 3.0 if n.begins_with("scream") else 0.0, 2.2)
	game.state.phantom(pos, 2.8)
	game.state.composure(2.6, 0.5)
	game.player.heartbeat_kick(0.6)
	count += 1


## A fist on the front door: that one is real, and he looks round at it too.
func real_bang() -> void:
	var pos: Vector3 = game.flat.spots.front_inside + Vector3(0.0, 1.2, -0.5)
	_play3d("bang_%d" % _rng.randi_range(1, 2), pos, 5.0, 6.0)
	game.state.sound("bang", pos, 2.8, 0.6)
	game.player.heartbeat_kick(0.7)
	count += 1
	var man: CharacterRig = game.man
	if man.visible:
		var keep := man.look_node
		man.look_node = null
		man.look_target = pos
		await game.wait(2.2)
		man.look_target = Vector3.INF
		man.look_node = keep


## The body itself: her head snaps round to you, her jaw drops open.
func corpse_snap(strength := 0.9) -> void:
	var w: CharacterRig = game.woman
	w.undead = true
	w.look_node = game.player.head
	w.jaw_open = 1.0
	w.lid_wide = 1.0
	hit(strength)
	_play3d("wet_thud", w.bone_pos("head"), 0.0, 2.0)
	game.state.visual("corpse", w.bone_pos("head"), 4.0, 0.8)


func corpse_rest() -> void:
	var w: CharacterRig = game.woman
	w.undead = false
	w.look_node = null
	w.jaw_open = 0.25
	w.lid_wide = 0.6


# ---------------------------------------------------------------------------
# the director: never the same night twice
# ---------------------------------------------------------------------------

func run(gen: int) -> void:
	if _running:
		return
	_running = true
	var next := _t + _rng.randf_range(8.0, 14.0)
	var major_gap := _rng.randf_range(14.0, 24.0)
	while _running and game._alive(gen) and game.act == "flat":
		await game.wait(0.2)
		if not _running:
			break
		if busy > 0 or _t < next or game.state.exposed_flag:
			continue
		var p: Player = game.player
		var ctx := ""
		if p.mode == "seated" and game.state.playing_piano:
			ctx = "seated"
		elif p.mode == "walk":
			ctx = "walk"
		if ctx == "":
			continue
		var pool := {"subliminal": 2.2, "phantom": 2.4, "far": 2.2 if ctx == "walk" else 0.5}
		if not bot:
			pool["bang"] = 0.7
		if _t - _last_major > major_gap:
			pool["pop"] = 3.0
			pool["upside"] = 2.2
			pool["side"] = 2.2
			pool["rise"] = 2.2
			pool["stare"] = 2.6
			pool["blackout"] = 2.0
			if ctx == "walk":
				pool["lunge"] = 3.2
				pool["turn"] = 2.2
		for r: String in _recent:
			if pool.has(r):
				pool[r] = float(pool[r]) * 0.12
		var pick := _weighted(pool)
		_recent.append(pick)
		if _recent.size() > 3:
			_recent.pop_front()
		var did := true
		game._tr("scare " + pick + " (" + ctx + ")")
		match pick:
			"pop", "upside", "side", "lunge", "rise", "stare":
				await pop(pick)
			"blackout":
				await blackout()
			"turn":
				turn_pop()
			"subliminal":
				await subliminal()
			"phantom":
				phantom_sound()
			"far":
				did = await far()
			"bang":
				real_bang()
		if pick in MAJORS:
			major_gap = _rng.randf_range(14.0, 26.0) / density
		next = _t + (_rng.randf_range(5.0, 11.0) / density if did else 1.5)
	_running = false


func _weighted(pool: Dictionary) -> String:
	var total := 0.0
	for k: String in pool:
		total += float(pool[k])
	var r := _rng.randf() * total
	for k: String in pool:
		r -= float(pool[k])
		if r <= 0.0:
			return k
	return String(pool.keys()[0])

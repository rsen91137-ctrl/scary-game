class_name ExteriorBuilder
extends Node3D
## The outdoor night, built in code: a 1980s housing estate (five blocks of
## five and six storeys round a courtyard, unit entrances, lit windows,
## balconies, pipes, a bike shed, bins, a parked car, benches, railings with
## a gap) under a moon in a misty mixed forest, and a forest chase route from
## her unit through the gap to a road (footbridge over a stream, a hunter's
## stand, a collapsed shed, an uprooted spruce and a hollow log, an abandoned
## car; dead ends; hiding places).
##
## Placed by game.gd at (400, 0, 0); everything is built in local coordinates
## (metres; x east, z south, y up; the courtyard centre is the origin).
##
## API
##   await build()                   everything (a coroutine, a few frames)
##   spots {name: global Vector3}     his_door, her_unit_door, courtyard_mid,
##                                    forest_gate (the railing gap), forest_exit
##                                    (on the road), chase_start (below her
##                                    unit's steps), her_door_step (on the
##                                    landing at her door: where he comes out),
##                                    hide_1..hide_7 (+ hide_k_front), and
##                                    bridge, stand, shed, wreck, root_plate
##   spot_yaw {name: yaw}             player yaw (0 looks along -z) for his_door,
##                                    her_unit_door, chase_start, her_door_step,
##                                    forest_gate, forest_exit, hide_k (looking
##                                    out), hide_k_front (looking in)
##   interactables {id: Area3D}       her_unit (ACT_ENTER, always on) and
##                                    hide_1..hide_7 (ACT_HIDE, off until
##                                    set_hides_active(true))
##   height_at(x, z) -> float         local ground height (bridge deck and
##                                    entrance landings included)
##   path(from, to) -> PackedVector3Array   global points, A* over the whole
##                                    area (0.5 m cells), y from height_at
##                                    (about 0.1 ms for a pursuer 5-40 m behind;
##                                    routes in or out of the walled courtyard go
##                                    through the railing gap)
##   enter(world_env) / exit(world_env)     outdoor night on / off: swaps the
##                                    Environment and camera attributes (no DOF
##                                    outside), raises the current camera's far
##                                    plane to 170 m, shows the exterior and its
##                                    lights, runs the ambience, the lamp
##                                    flicker, the gusts and the mist
##   step_sound(pos) -> String        footstep file for that ground (leaves,
##                                    gravel / paving)
##   in_forest(pos) -> float          0 in the courtyard .. 1 deep in the trees
##   at_road(pos) -> bool             on the road (the way out)
##   set_hides_active(on)             hiding places answer E (ACT_HIDE)
##   exposure_boost                   night exposure multiplier (1.5 - 1.7 while
##                                    the dark glasses' grade is on)
##   built (signal)                   emitted when build() is done
## The lamps flicker on their own (modes steady / flicker / dying / dead in
## `lamps`); her unit's bulb is dying. Outdoor footstep and ambience files are
## made by tools/gen_outside_sfx.py, textures by tools/gen_forest.py.

signal built

const X0 := -110.0
const X1 := 210.0
const Z0 := -100.0
const Z1 := 140.0
const CELL := 0.5
const CHUNK := 32.0
const WALK := Rect2(-86.0, -76.0, 279.0, 195.0)        # x, z, w, d: where you can go
const ESTATE := Rect2(-50.0, -44.0, 100.0, 92.0)       # flattened ground round the blocks
const COURT := Rect2(-38.0, -31.0, 74.0, 63.0)          # inside the ring of blocks
const ROAD_X := 184.0
const ROAD_HW := 3.5

const SFX := "res://assets/audio/"

var spots := {}
var spot_yaw := {}
var interactables := {}
var lamps: Array = []
var active := false
var build_ms := 0
var env: Environment
## Multiplies the night's exposure (the game's dark-glasses grade takes about a
## stop away: 1.5 - 1.7 keeps the forest readable through them).
var exposure_boost := 1.0

var _m := {}
var _hgrid := PackedFloat32Array()
var _hw := 0
var _hd := 0
var _gw := 0
var _gd := 0
var _dirt := PackedByteArray()      # 0.5 m grid: path dirt 0..255
var _pdist := PackedFloat32Array()  # 0.5 m grid: distance beyond a trail edge (m)
var _solid := PackedByteArray()     # 0.5 m grid: 1 = blocked for path()
var _astar: AStarGrid2D
var _trails: Array = []             # [{pts: PackedVector2Array, w: float, fade: bool}]
var _rects: Array = []              # estate paved rects [Rect2, kind]
var _blocks: Array = []             # [{xf, len, depth, top}]
var _entr: Array = []               # [{xf: Transform3D, inv: Transform3D}]
var _excl: Array = []               # [Vector2 centre, radius]
var _body: StaticBody3D
var _shapes := {}
var _noise_a: FastNoiseLite
var _noise_b: FastNoiseLite
var _noise_c: FastNoiseLite
var _bridge := {}
var _moon: DirectionalLight3D
var _lights: Node3D
var _far: Node3D
var _amb_court: AudioStreamPlayer
var _amb_forest: AudioStreamPlayer
var _saved_env: Environment
var _saved_attr: CameraAttributes
var _saved_cam: Camera3D
var _saved_far := -1.0
var _attr: CameraAttributesPractical
var _fog_k := 0.0
var _mist: Array = []
var _fol_mats: Array = []
var _bark_mats: Array = []
var _gust := 0.3
var _gust_noise: FastNoiseLite
var _amb_rustle: AudioStreamPlayer
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _capture := false
var _hide_list: Array = []
var _gap_cells: Array[Vector2i] = []


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------
func build() -> void:
	var t0 := Time.get_ticks_msec()
	_capture = OS.get_cmdline_user_args().has("--capture")
	_rng.seed = 1983
	visible = false
	_noise_a = FastNoiseLite.new()
	_noise_a.seed = 11
	_noise_a.frequency = 0.016
	_noise_a.fractal_octaves = 3
	_noise_b = FastNoiseLite.new()
	_noise_b.seed = 23
	_noise_b.frequency = 0.05
	_noise_b.fractal_octaves = 2
	_noise_c = FastNoiseLite.new()
	_noise_c.seed = 37
	_noise_c.frequency = 0.21
	_noise_c.fractal_octaves = 1
	_body = StaticBody3D.new()
	_body.name = "Colliders"
	add_child(_body)
	_lights = Node3D.new()
	_lights.name = "Lights"
	add_child(_lights)
	_materials()
	_layout()
	_heights()
	_trail_fields()
	var steps: Array[Callable] = [_terrain, _estate, _blocks_build, _street, _landmarks, _forest, _undergrowth, _road, _nav, _cc0_dressing, _environment, _finish]
	for f: Callable in steps:
		var ts := Time.get_ticks_msec()
		f.call()
		if OS.get_cmdline_user_args().has("--trace"):
			print("[ext] %s %d ms" % [f.get_method(), Time.get_ticks_msec() - ts])
		await get_tree().process_frame
	build_ms = Time.get_ticks_msec() - t0
	print("[ext] build %d ms" % build_ms)
	built.emit()


# ---------------------------------------------------------------------------
# CC0 photoscans along the trails (Poly Haven, docs/CREDITS_CC0.md): ferns,
# nettles, low shrubs, fallen branches and moss tufts where the eye is
# closest. Plants only: nothing that blocks the way.
# ---------------------------------------------------------------------------
func _cc0_dressing() -> void:
	if not ResourceLoader.exists("res://assets/cc0/models/fern_02/fern_02_1k.gltf"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var trails: Array[PackedVector3Array] = []
	if spots.has("chase_start") and spots.has("forest_exit"):
		trails.append(path(spots.chase_start, spots.forest_exit))
	for k in range(1, 12):
		if spots.has("hide_%d" % k) and spots.has("chase_start"):
			trails.append(path(spots.chase_start, spots["hide_%d" % k]))
	var kinds := {"fern_02": [], "nettle_plant": [], "shrub_03": [], "shrub_04": [], "dry_branches_medium_01": [], "moss_01": []}
	var weights := {"fern_02": 0.34, "nettle_plant": 0.16, "shrub_03": 0.12, "shrub_04": 0.12, "dry_branches_medium_01": 0.1, "moss_01": 0.16}
	var used := {}
	for tr: PackedVector3Array in trails:
		for i in range(1, tr.size() - 1):
			var a := tr[i]
			var dir := (tr[i + 1] - tr[i - 1])
			dir.y = 0.0
			if dir.length() < 0.01:
				continue
			dir = dir.normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			for s: float in [-1.0, 1.0]:
				if rng.randf() < 0.35:
					continue
				var gp := a + side * s * rng.randf_range(1.0, 3.6) + dir * rng.randf_range(-0.8, 0.8)
				var key := Vector2i(int(gp.x * 1.2), int(gp.z * 1.2))
				if used.has(key) or in_forest(gp) < 0.15:
					continue
				used[key] = true
				var r := rng.randf()
				var kind := "fern_02"
				for k: String in weights:
					r -= float(weights[k])
					if r <= 0.0:
						kind = k
						break
				var lp := to_local(gp)
				var y := height_at(lp.x, lp.z)
				var sc := rng.randf_range(0.8, 1.35) * (2.2 if kind == "moss_01" else 1.0)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
				(kinds[kind] as Array).append(Transform3D(b, Vector3(lp.x, y - 0.02, lp.z)))
	var holder := Node3D.new()
	holder.name = "CC0Dressing"
	add_child(holder)
	var counts := {}
	for k: String in kinds:
		counts[k] = (kinds[k] as Array).size()
		CC0Props.scatter(holder, k, kinds[k], false, 34.0)
	if OS.get_cmdline_user_args().has("--trace"):
		print("[ext] cc0 trails=%d %s" % [trails.size(), counts])


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------
func _tex(n: String) -> Texture2D:
	# "cc0:<id>_<map>": a Poly Haven photoscan (assets/cc0/textures, docs/CREDITS_CC0.md)
	if n.begins_with("cc0:"):
		var body := n.substr(4)
		var cut := body.rfind("_")
		var cp := "res://assets/cc0/textures/%s/%s.jpg" % [body.substr(0, cut), body]
		if ResourceLoader.exists(cp):
			return load(cp)
		n = body
	for ext: String in [".jpg", ".png"]:
		var p := "res://assets/textures/forest/%s%s" % [n, ext]
		if ResourceLoader.exists(p):
			return load(p)
	var q := "res://assets/textures/%s.png" % n
	return load(q) if ResourceLoader.exists(q) else null


func _std(base: String, uv: float, tint := Color.WHITE, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(base + "_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(base + "_normal")
	var rt := _tex(base + "_rough")
	if rt:
		m.roughness_texture = rt
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough
	m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _flat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _bark(tex: String, tint: Color, height: float, moss: float, base_dark := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	_bark_mats.append(m)
	m.shader = load("res://shaders/foliage_bark.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(tex + "_albedo"))
	m.set_shader_parameter("normal_tex", _tex(tex + "_normal"))
	m.set_shader_parameter("rough_tex", _tex(tex + "_rough"))
	m.set_shader_parameter("moss_tex", _tex("moss_albedo"))
	m.set_shader_parameter("moss_nrm", _tex("moss_normal"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tree_height", height)
	m.set_shader_parameter("moss_amount", moss)
	m.set_shader_parameter("base_dark", base_dark)
	m.set_shader_parameter("uv_scale", Vector2(1.0, 0.75))
	return m


func _leaf(tex: String, tint: Color, height: float, extra := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tree_height", height)
	for k: String in extra:
		m.set_shader_parameter(k, extra[k])
	m.set_meta("fade_far", float(extra.get("fade_far", 0.0)))
	_fol_mats.append(m)
	return m


func _materials() -> void:
	var m := _m
	# trees: each species' bark and needles share tree_height (wind bend)
	m.bark_pine = _bark("cc0:pine_bark", Color(1.0, 0.95, 0.92), 19.0, 0.45)
	m.bark_pine.set_shader_parameter("uv_scale", Vector2(1.0, 0.62))
	m.bark_spruce = _bark("cc0:bark_brown_02", Color(0.86, 0.86, 0.88), 17.0, 0.6)
	m.bark_spruce.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
	m.bark_oak = _bark("bark_oak", Color(0.95, 1.0, 0.97), 13.0, 0.8)
	m.bark_birch = _bark("bark_birch", Color(0.92, 0.96, 0.98), 13.0, 0.35, 1.0)
	m.bark_dead = _bark("cc0:moss_wood", Color(0.85, 0.85, 0.85), 9.0, 0.4)
	m.leaf_pine = _leaf("card_pine", Color(0.9, 1.0, 0.95), 19.0, {"translucency": 0.3})
	m.leaf_spruce = _leaf("card_spruce", Color(0.85, 1.0, 0.95), 17.0, {"translucency": 0.25, "alpha_cut": 0.38})
	m.leaf_twigs = _leaf("card_twigs", Color(0.95, 0.95, 1.0), 13.0, {"translucency": 0.15, "alpha_cut": 0.32, "flutter_amt": 0.5})
	m.leaf_birch = _leaf("card_birch", Color(1.0, 1.0, 1.0), 13.0, {"translucency": 0.3, "alpha_cut": 0.32, "flutter_amt": 1.6})
	m.leaf_fern = _leaf("card_fern", Color(0.85, 1.0, 0.9), 1.0, {"translucency": 0.45, "sway_amt": 0.0, "branch_amt": 0.6, "flutter_amt": 1.2, "fade_far": 30.0, "fade_len": 7.0})
	m.leaf_bush = _leaf("card_bush", Color(0.92, 1.0, 0.96), 1.0, {"translucency": 0.35, "sway_amt": 0.0, "branch_amt": 0.5, "flutter_amt": 1.0, "fade_far": 38.0, "fade_len": 8.0})
	m.leaf_grass = _leaf("card_grass", Color(0.88, 1.0, 0.92), 1.0, {"translucency": 0.4, "sway_amt": 0.0, "branch_amt": 0.8, "flutter_amt": 1.4, "fade_far": 22.0, "fade_len": 6.0, "alpha_cut": 0.4})
	m.leaf_hedge = _leaf("card_bush", Color(0.82, 0.96, 0.9), 1.0, {"translucency": 0.3, "sway_amt": 0.0, "branch_amt": 0.3, "flutter_amt": 0.8})
	# rock: triplanar in object space, moss on top
	m.rock = _shader(ROCK_SHADER)
	for k: String in ["rock_albedo", "rock_normal", "rock_rough", "moss_albedo", "moss_normal"]:
		m.rock.set_shader_parameter(k.replace("_albedo", "_a").replace("_normal", "_n").replace("_rough", "_r"), _tex(k))
	# estate
	m.render_mint = _std("render", 0.5, Color(0.44, 0.62, 0.55))
	m.render_teal = _std("render", 0.5, Color(0.36, 0.55, 0.58))
	m.render_violet = _std("render", 0.5, Color(0.5, 0.5, 0.66))
	m.tiles_blue = _std("tiles", 1.0, Color(0.5, 0.6, 0.74))
	m.brick = _std("brick", 0.8, Color(0.78, 0.8, 0.86))
	m.wall_bal = _std("render", 0.5, Color(0.5, 0.58, 0.6))
	m.band = _std("concrete", 0.6, Color(0.55, 0.6, 0.62))
	m.plinth = _std("concrete", 0.6, Color(0.36, 0.4, 0.42))
	m.roof = _std("roof", 0.4)
	m.concrete = _std("concrete", 0.7, Color(0.72, 0.74, 0.75))
	m.step = _std("concrete", 0.9, Color(0.66, 0.68, 0.7))
	m.kerb = _std("concrete", 0.8, Color(0.62, 0.65, 0.66))
	m.hut_wall = _std("render", 0.5, Color(0.5, 0.6, 0.62))
	m.paving = _ground_mat("paving", 2.0, Color(0.78, 0.84, 0.86), 0.55)
	m.asphalt = _ground_mat("asphalt", 4.0, Color(0.85, 0.9, 0.95), 0.7)
	m.road = _ground_mat("asphalt", 4.0, Color(0.75, 0.78, 0.82), 0.35)
	m.gravel = _ground_mat("ground_dirt", 2.0, Color(0.75, 0.75, 0.78), 0.2)
	var frame := _flat(Color(0.86, 0.9, 0.88), 0.55)
	frame.vertex_color_use_as_albedo = true
	frame.albedo_texture = _tex("render_albedo")
	frame.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.frame = frame
	m.cage = _std("rust", 1.5, Color(0.55, 0.6, 0.62), 0.9)
	m.ac = _flat(Color(0.62, 0.66, 0.66), 0.5)
	m.dark_metal = _flat(Color(0.08, 0.09, 0.1), 0.5, 0.6)
	m.galv = _flat(Color(0.42, 0.45, 0.47), 0.45, 0.8)
	m.alu = _flat(Color(0.56, 0.6, 0.62), 0.35, 0.85)
	m.pipe = _flat(Color(0.3, 0.33, 0.34), 0.55, 0.2)
	m.chrome = _flat(Color(0.62, 0.64, 0.66), 0.22, 1.0)
	m.rubber = _flat(Color(0.03, 0.03, 0.035), 0.85)
	m.lamp_pole = _std("rust", 1.0, Color(0.42, 0.5, 0.48), 0.8)
	m.lamp_head = _flat(Color(0.22, 0.25, 0.27), 0.45, 0.5)
	var lg := StandardMaterial3D.new()
	lg.albedo_color = Color(0.85, 0.9, 0.95)
	lg.emission_enabled = true
	lg.emission = Color(0.6, 0.9, 1.0)
	lg.emission_energy_multiplier = 8.0
	lg.roughness = 0.2
	m.lamp_glass = lg
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(0.9, 0.92, 0.95)
	bulb.emission_enabled = true
	bulb.emission = Color(0.75, 0.88, 1.0)
	bulb.emission_energy_multiplier = 6.0
	m.bulb = bulb
	m.door_green = _std("door_green", 1.0)
	m.door_green.normal_texture = _tex("door_normal")
	m.door_green.roughness_texture = _tex("door_rough")
	m.door_blue = _std("door_blue", 1.0)
	m.door_blue.normal_texture = _tex("door_normal")
	m.door_blue.roughness_texture = _tex("door_rough")
	var gd := StandardMaterial3D.new()
	gd.albedo_color = Color(0.12, 0.16, 0.18, 0.85)
	gd.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gd.roughness = 0.15
	gd.metallic_specular = 0.8
	m.glass_door = gd
	m.glass_win = _shader(WINDOW_SHADER)
	m.glass_win.set_shader_parameter("vertex_data", true)
	m.glass_win_mm = _shader(WINDOW_SHADER)
	m.glass_hut = m.glass_win
	var sign := StandardMaterial3D.new()
	sign.albedo_texture = _tex("signs")
	sign.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sign.alpha_scissor_threshold = 0.35
	sign.roughness = 0.85
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.sign = sign
	m.streak = _shader(STREAK_SHADER)
	m.streak.set_shader_parameter("tex", _tex("streaks"))
	m.halo = _shader(HALO_SHADER)
	m.cloth = _shader(CLOTH_SHADER)
	m.corrugated = _std("rust", 0.8, Color(0.5, 0.58, 0.6), 0.9)
	m.corrugated.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rust = _std("rust", 1.0, Color(0.85, 0.8, 0.78))
	m.planks = _std("planks", 0.5, Color(0.8, 0.84, 0.82))
	m.wood_slat = _std("planks", 1.0, Color(0.7, 0.66, 0.62))
	m.granite = _std("rock", 1.2, Color(0.74, 0.76, 0.8), 0.6)
	m.cork = _flat(Color(0.32, 0.25, 0.18), 0.95)
	m.play_paint = _std("rust", 1.2, Color(0.35, 0.62, 0.6), 0.7)
	m.bin_green = _flat(Color(0.08, 0.3, 0.16), 0.55)
	m.bin_blue = _flat(Color(0.07, 0.16, 0.38), 0.55)
	m.bin_grey = _flat(Color(0.2, 0.22, 0.24), 0.6)
	m.bag_black = _flat(Color(0.02, 0.02, 0.025), 0.3)
	m.bag_blue = _flat(Color(0.05, 0.12, 0.3), 0.3)
	m.car_teal = _flat(Color(0.12, 0.3, 0.32), 0.35, 0.3)
	m.car_teal.clearcoat_enabled = true
	m.car_teal.clearcoat = 0.4
	var cg := StandardMaterial3D.new()
	cg.albedo_color = Color(0.03, 0.04, 0.05)
	cg.roughness = 0.05
	cg.metallic_specular = 0.9
	m.car_glass = cg
	m.car_light = _flat(Color(0.7, 0.72, 0.7), 0.1)
	m.tail_light = _flat(Color(0.35, 0.03, 0.03), 0.2)
	m.plate = _flat(Color(0.05, 0.12, 0.42), 0.4)
	m.bus_sign = _flat(Color(0.08, 0.2, 0.5), 0.45)
	m.soil = _std("ground_dirt", 0.5, Color(0.8, 0.78, 0.75))
	m.rotten_wood = _std("ground_litter", 0.6, Color(0.55, 0.5, 0.45))
	m.bike_black = _flat(Color(0.03, 0.035, 0.04), 0.4, 0.3)
	m.bike_green = _flat(Color(0.06, 0.2, 0.16), 0.45, 0.3)
	m.paint_line = _flat(Color(0.62, 0.64, 0.6), 0.75)
	m.water = _shader(WATER_SHADER)
	m.water.set_shader_parameter("nmap", _tex("water_normal"))
	m.terrain = _shader(TERRAIN_SHADER)
	for pair: Array in [["litter_a", "cc0:forest_floor_albedo"], ["litter_n", "cc0:forest_floor_normal"], ["litter_r", "cc0:forest_floor_rough"],
			["dirt_a", "cc0:stony_dirt_path_albedo"], ["dirt_n", "cc0:stony_dirt_path_normal"], ["dirt_r", "cc0:stony_dirt_path_rough"],
			["lawn_a", "ground_lawn_albedo"], ["lawn_n", "ground_lawn_normal"], ["moss_a", "moss_albedo"], ["moss_n", "moss_normal"],
			["mud_a", "cc0:mud_forest_albedo"], ["mud_n", "cc0:mud_forest_normal"]]:
		m.terrain.set_shader_parameter(pair[0], _tex(pair[1]))


func _ground_mat(base: String, tile: float, tint: Color, puddles: float) -> ShaderMaterial:
	var m := _shader(SURFACE_SHADER)
	m.set_shader_parameter("alb_tex", _tex(base + "_albedo"))
	m.set_shader_parameter("nrm_tex", _tex(base + "_normal"))
	m.set_shader_parameter("rgh_tex", _tex(base + "_rough"))
	m.set_shader_parameter("tile_m", tile)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("puddles", puddles)
	return m


const NOISE_FN := """
float hsh(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hsh(i), hsh(i + vec2(1.0, 0.0)), u.x), mix(hsh(i + vec2(0.0, 1.0)), hsh(i + vec2(1.0, 1.0)), u.x), u.y);
}
"""

const TERRAIN_SHADER := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The ground: leaf litter and needles, moss, lawn, trodden dirt paths, mud
// by the stream; masks from a splat texture over the whole area (R path,
// G moss, B lawn, A wet), broken up with noise so edges stay organic.
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec4 splat_rect = vec4(-110.0, -100.0, 0.003125, 0.0041667);
uniform sampler2D litter_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_r : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_r : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D lawn_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lawn_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 lp;
""" + NOISE_FN + """
void vertex() {
	lp = VERTEX;
}
void fragment() {
	vec2 suv = (lp.xz - splat_rect.xy) * splat_rect.zw;
	vec4 s = texture(splat, suv);
	vec2 uv = lp.xz;
	float br = vn(uv * 0.35) * 0.6 + vn(uv * 1.7) * 0.4;
	vec2 luv = uv / 2.6;
	vec3 alb = mix(texture(litter_a, luv).rgb, texture(litter_a, luv * 0.31 + 0.37).rgb, 0.35);
	alb *= mix(vec3(0.86, 0.92, 1.0), vec3(1.04, 0.96, 0.86), vn(uv * 0.035));
	vec3 nm = texture(litter_n, luv).rgb;
	float rough = texture(litter_r, luv).r;
	float mk = smoothstep(0.35, 0.75, s.g + (br - 0.5) * 0.5);
	vec2 muv = uv / 1.4;
	alb = mix(alb, texture(moss_a, muv).rgb, mk);
	nm = mix(nm, texture(moss_n, muv).rgb, mk);
	rough = mix(rough, 0.95, mk);
	float gk = smoothstep(0.3, 0.7, s.b + (br - 0.5) * 0.4);
	vec2 guv = uv / 2.0;
	alb = mix(alb, texture(lawn_a, guv).rgb * vec3(0.9, 1.0, 0.95), gk);
	nm = mix(nm, texture(lawn_n, guv).rgb, gk);
	rough = mix(rough, 0.9, gk);
	float pk = smoothstep(0.16, 0.55, s.r + (br - 0.5) * 0.3);
	vec2 duv = uv / 2.2;
	alb = mix(alb, texture(dirt_a, duv).rgb * vec3(1.45, 1.4, 1.35), pk);
	nm = mix(nm, texture(dirt_n, duv).rgb, pk);
	rough = mix(rough, texture(dirt_r, duv).r, pk);
	float wk = smoothstep(0.3, 0.72, s.a + (br - 0.5) * 0.3);
	vec2 wuv = uv / 1.5;
	alb = mix(alb, texture(mud_a, wuv).rgb, wk);
	nm = mix(nm, texture(mud_n, wuv).rgb, wk);
	rough = mix(rough, 0.28, wk);
	ALBEDO = alb;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
"""

const SURFACE_SHADER := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Paving and asphalt mapped in world XZ, with damp patches and puddles that
// mirror the lamps.
uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rgh_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float puddles = 0.5;
varying vec3 wp;
""" + NOISE_FN + """
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wp.xz / tile_m;
	vec3 a = texture(alb_tex, uv).rgb * tint;
	vec3 n = texture(nrm_tex, uv).rgb;
	float r = texture(rgh_tex, uv).r;
	float w = vn(wp.xz * 0.17) * 0.7 + vn(wp.xz * 0.9) * 0.3;
	float damp = smoothstep(0.42, 0.6, w) * puddles;
	float pud = smoothstep(0.6, 0.66, w) * puddles;
	a *= 1.0 - 0.38 * damp;
	r = mix(r, 0.32, damp);
	r = mix(r, 0.025, pud);
	n = mix(n, vec3(0.5, 0.5, 1.0), pud);
	ALBEDO = a;
	NORMAL_MAP = n;
	ROUGHNESS = r;
	SPECULAR = mix(0.4, 0.65, pud);
}
"""

const ROCK_SHADER := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Boulders: granite mapped three ways in world space (so big and small rocks
// share one grain), moss on the tops.
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_r : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.7;
uniform float moss = 0.8;
uniform vec3 tint : source_color = vec3(0.8, 0.86, 0.9);
varying vec3 op;
varying vec3 on;
varying vec3 wn;
void vertex() {
	op = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	on = wn;
}
void fragment() {
	vec3 bw = pow(abs(on), vec3(4.0));
	bw /= dot(bw, vec3(1.0));
	vec2 ux = op.zy * scale;
	vec2 uy = op.xz * scale;
	vec2 uz = op.xy * scale;
	vec3 a = texture(rock_a, ux).rgb * bw.x + texture(rock_a, uy).rgb * bw.y + texture(rock_a, uz).rgb * bw.z;
	vec3 n = texture(rock_n, ux).rgb * bw.x + texture(rock_n, uy).rgb * bw.y + texture(rock_n, uz).rgb * bw.z;
	float r = texture(rock_r, ux).r * bw.x + texture(rock_r, uy).r * bw.y + texture(rock_r, uz).r * bw.z;
	float mn = texture(moss_a, uy * 0.4).g;
	float mk = smoothstep(0.45, 0.8, wn.y + (mn - 0.3) * 0.9) * moss;
	a = mix(a * tint, texture(moss_a, uy * 1.6).rgb, mk);
	n = mix(n, texture(moss_n, uy * 1.6).rgb, mk);
	ALBEDO = a;
	NORMAL_MAP = n;
	ROUGHNESS = mix(r, 0.95, mk);
	SPECULAR = 0.35;
}
"""

const WATER_SHADER := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The stream: dark, slow, rippling; mirrors the sky and the moon.
uniform sampler2D nmap : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.01, 0.02, 0.022);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wp.xz * 0.32;
	vec3 n1 = texture(nmap, uv + vec2(0.0, TIME * 0.06)).rgb;
	vec3 n2 = texture(nmap, uv * 1.8 + vec2(TIME * 0.015, TIME * 0.1)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = 0.5;
	ALBEDO = color;
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
}
"""

const WINDOW_SHADER := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Window glass. Data per pane (MultiMesh custom or, for vertex_data, the
// vertex colour): x = lit 0..1, y = warm 0 .. cool 1, z = seed, w = a TV.
// Lit: light through curtains with a gap between them; dark: glass that
// mirrors the sky over faint curtain folds.
uniform bool vertex_data = false;
uniform float energy = 0.6;
varying vec4 d;
float h1(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}
void vertex() {
	d = vertex_data ? COLOR : INSTANCE_CUSTOM;
}
void fragment() {
	float lit = d.x;
	float seed = d.z * 91.7 + 1.0;
	vec2 uv = UV;
	vec3 lc = mix(vec3(1.0, 0.46, 0.14), vec3(0.26, 0.5, 1.0), d.y);
	vec3 cloth = mix(vec3(1.0, 0.72, 0.42), vec3(0.6, 0.78, 1.0), d.y);
	float gw = 0.06 + 0.34 * h1(seed);
	float gc = 0.25 + 0.5 * h1(seed + 3.1);
	float gap = smoothstep(gw * 0.5, gw * 0.5 - 0.04, abs(uv.x - gc));
	float folds = 0.55 + 0.45 * sin(uv.x * (26.0 + 30.0 * h1(seed + 5.0)) + seed);
	float curt = mix(folds * 0.45, 1.0, gap);
	lc *= mix(cloth, vec3(1.0), gap);
	float glow = 0.7 + 0.4 * exp(-pow((uv.x - 0.5) * 2.0, 2.0) - pow((uv.y - 0.3) * 2.2, 2.0));
	float flick = 1.0;
	if (d.w > 0.5 && d.w < 1.5) {
		flick = 0.6 + 0.4 * sin(TIME * 9.0 + seed) * sin(TIME * 2.7 + seed * 2.0) + 0.15 * sin(TIME * 23.0 + seed);
		lc = mix(lc, vec3(0.45, 0.68, 1.0), 0.75);
	}
	vec3 alb = mix(vec3(0.025, 0.03, 0.04), vec3(0.055, 0.065, 0.075), folds * (1.0 - gap));
	vec3 em = lc * curt * glow * lit * flick * energy;
	if (d.w > 1.5) {
		// someone standing behind the curtain, shifting now and then
		float sx = 0.4 + 0.07 * sin(TIME * 0.19) + 0.03 * sin(TIME * 0.47);
		float head = smoothstep(0.085, 0.065, length((uv - vec2(sx, 0.34)) * vec2(1.0, 0.72)));
		float shoulders = smoothstep(0.02, 0.0, abs(uv.x - sx) - 0.17 * smoothstep(0.4, 0.58, uv.y)) * step(0.43, uv.y);
		em *= 1.0 - 0.88 * max(head, shoulders);
	}
	ALBEDO = alb * (1.0 - lit * 0.6);
	ROUGHNESS = 0.06 + 0.12 * h1(seed + 9.0);
	SPECULAR = 0.7;
	EMISSION = em;
}
"""

const STREAK_SHADER := """shader_type spatial;
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
// Grime run down a wall (MultiMesh custom: x = atlas column 0..0.75, y = strength).
uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
varying vec4 d;
void vertex() {
	d = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 uv = vec2(d.x + clamp(UV.x, 0.01, 0.99) * 0.25, UV.y);
	float a = clamp(texture(tex, uv).a * d.y * 1.6, 0.0, 1.0);
	a *= exp(-length(VERTEX) * 0.018);
	ALBEDO = mix(vec3(1.0), vec3(0.22, 0.25, 0.24), a);
}
"""

const HALO_SHADER := """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The glow round a lamp in the damp air: a soft billboard, faded close up.
uniform vec3 color : source_color = vec3(0.6, 0.9, 1.0);
uniform float intensity = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = exp(-r * r * 7.0) * 0.55 + exp(-r * 9.0) * 0.45;
	float dist = length(VERTEX);
	a *= smoothstep(1.0, 5.0, dist) * exp(-dist * 0.018);
	ALBEDO = color * a * intensity * 0.4;
}
"""

const CLOTH_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Washing on a line, stirring in the wind. COLOR.r picks the faded colour,
// COLOR.g stripes; UV.y is 0 at the line and 1 at the hem.
varying vec2 c;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float hang = UV.y;
	VERTEX.z += (sin(TIME * 1.6 + wp.x * 1.3 + COLOR.r * 6.0) * 0.07 + sin(TIME * 3.3 + wp.x * 3.1) * 0.015) * hang;
	VERTEX.x += sin(TIME * 1.1 + COLOR.g * 5.0) * 0.02 * hang;
	c = COLOR.rg;
}
void fragment() {
	vec3 col = vec3(0.2, 0.42, 0.44);
	if (c.x > 0.2) { col = vec3(0.16, 0.24, 0.42); }
	if (c.x > 0.4) { col = vec3(0.55, 0.56, 0.5); }
	if (c.x > 0.6) { col = vec3(0.3, 0.36, 0.3); }
	if (c.x > 0.8) { col = vec3(0.42, 0.4, 0.52); }
	if (c.y > 0.6) { col *= 0.75 + 0.25 * step(0.5, fract(UV.x * 7.0)); }
	ALBEDO = col;
	ROUGHNESS = 0.92;
	BACKLIGHT = col * 0.35;
}
"""

# ---------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------
## number, origin (front-left corner), yaw, length, floors, units, wall, door
const BLOCKS := [
	[1, Vector3(18, 0, -31), PI, 56.0, 6, 4, "render_mint", "door_green"],
	[2, Vector3(-38, 0, -22), -PI * 0.5, 44.0, 5, 3, "tiles_blue", "door_blue"],
	[3, Vector3(36, 0, 10), PI * 0.5, 40.0, 6, 3, "brick", "door_green"],
	[4, Vector3(-36, 0, 32), 0.0, 34.0, 5, 3, "render_teal", "door_blue"],
	[5, Vector3(4, 0, 32), 0.0, 42.0, 6, 3, "render_violet", "door_blue"],
]
const HIS_BLOCK := 1
const HIS_UNIT := 3
const HER_BLOCK := 5
const HER_UNIT := 3
const PAVE := [
	[Rect2(-36, -28.5, 66, 3), "paving"],
	[Rect2(30.5, -28.5, 3, 58.5), "paving"],
	[Rect2(-36, 27, 81.4, 3), "paving"],
	[Rect2(-36, -28.5, 3, 58.5), "paving"],
	[Rect2(-10, -8, 20, 17), "paving"],
	[Rect2(-1.5, -25.5, 3, 17.5), "paving"],
	[Rect2(-1.5, 9, 3, 18), "paving"],
	[Rect2(-33, -1.5, 23, 3), "paving"],
	[Rect2(10, -1.5, 20.5, 3), "paving"],
	[Rect2(25, -18, 5.5, 26), "asphalt"],
	[Rect2(24, -100, 6, 71.5), "asphalt"],
]
## fences: from, to, gap (metres along) or none
const FENCES := [
	[Vector2(-37.6, -31.4), Vector2(-38.3, -21.6), Vector2(-1, -1)],
	[Vector2(17.6, -31.2), Vector2(23.4, -31.2), Vector2(-1, -1)],
	[Vector2(34.3, -31.2), Vector2(36.9, -31.2), Vector2(-1, -1)],
	[Vector2(46.6, 9.6), Vector2(45.7, 32.4), Vector2(9.9, 12.5)],
	[Vector2(-2.4, 32.3), Vector2(4.4, 32.3), Vector2(-1, -1)],
	[Vector2(-38.1, 21.6), Vector2(-35.6, 32.4), Vector2(-1, -1)],
]
const ENCLOSURE := [Rect2(-38.0, -31.0, 74.0, 63.0), Rect2(36.0, 10.0, 10.4, 22.2)]
const GAP_C := Vector2(46.16, 20.8)
const GATE_X := Vector2(23.6, 30.4)
const GATE_Z := -31.2
const MAIN_TRAIL := [Vector2(43.5, 27.6), Vector2(45.0, 24.2), Vector2(46.2, 20.9), Vector2(49.5, 20.1), Vector2(55, 19), Vector2(64, 23),
	Vector2(73, 18), Vector2(83, 21), Vector2(92, 30), Vector2(98.6, 31.7), Vector2(101.2, 32.0), Vector2(103.5, 32.0), Vector2(107.5, 32.0),
	Vector2(109.8, 32.0), Vector2(115, 40), Vector2(122, 34), Vector2(130, 46), Vector2(137, 52), Vector2(143, 63), Vector2(151, 70),
	Vector2(158, 82), Vector2(166, 90), Vector2(174, 95), Vector2(181.5, 97.6)]
const SIDE_TRAILS := [
	[[Vector2(73, 18), Vector2(72, 10), Vector2(75, 2), Vector2(77.5, -3.5), Vector2(79, -10), Vector2(80, -15.5)], 1.2, true],
	[[Vector2(92, 30), Vector2(95, 38), Vector2(98.5, 45), Vector2(100, 52), Vector2(100.5, 57)], 1.1, true],
	[[Vector2(122, 34), Vector2(127, 27), Vector2(133, 23.8), Vector2(139, 27), Vector2(141.5, 36), Vector2(140.5, 45), Vector2(137, 52)], 1.2, false],
	[[Vector2(143, 63), Vector2(136, 67), Vector2(128, 71), Vector2(121, 74), Vector2(117.6, 75.3)], 1.1, true],
	[[Vector2(111.6, 32.4), Vector2(111.4, 25), Vector2(108.8, 14), Vector2(110.5, 5), Vector2(112, -2)], 1.0, true],
	[[Vector2(158, 82), Vector2(153.5, 87), Vector2(150.4, 91.2)], 1.0, true],
	[[Vector2(151, 70), Vector2(157, 64), Vector2(164, 58.5), Vector2(170, 54.5), Vector2(174.5, 52.5)], 1.3, true],
]
const BRIDGE_C := Vector2(105.5, 32.0)
const BRIDGE_LEN := 8.6
const SHED := [Vector2(80.8, -5.2), -PI * 0.5]
const STAND := [Vector2(134.5, 19.4), 0.0]
const WOODPILE := [Vector2(138.6, 22.4), 0.15]
const ROOTPLATE := [Vector2(113.2, 79.6), 0.4]
const HOLLOW := [Vector2(117.8, 79.9), PI * 0.5]
const WRECK := [Vector2(156.0, 68.6), PI * 0.25]
const BOULDERS := [[Vector2(97.6, 48.8), 1.5], [Vector2(96.3, 50.9), 1.2], [Vector2(98.9, 51.0), 0.9]]
const THICKET_1 := [Vector2(63.5, 27.6), Vector2(65.1, 28.7), Vector2(62.1, 29.0), Vector2(64.2, 30.0)]
const SAPLING_6 := Vector2(149.4, 93.6)


func _layout() -> void:
	_trails.clear()
	_trails.append({"pts": _spline(MAIN_TRAIL), "w": 1.7, "fade": false})
	for st: Array in SIDE_TRAILS:
		_trails.append({"pts": _spline(st[0]), "w": float(st[1]), "fade": bool(st[2])})
	for pv: Array in PAVE:
		_rects.append(pv)
	# exclusion zones for trees and big scatter
	for e: Array in [[SHED[0], 4.6], [STAND[0], 3.6], [WOODPILE[0], 2.6], [BRIDGE_C, 5.6], [ROOTPLATE[0], 3.2], [HOLLOW[0], 4.0],
			[WRECK[0], 4.2], [Vector2(97.6, 49.8), 3.4], [Vector2(63.6, 28.5), 2.8], [SAPLING_6, 3.2], [Vector2(51.5, 22.8), 1.6],
			[Vector2(176.0, 52.4), 3.0], [Vector2(100.5, 58.0), 3.0]]:
		_excl.append(e)
	var rp: Vector2 = ROOTPLATE[0]
	var rd := Vector2(-cos(float(ROOTPLATE[1])), sin(float(ROOTPLATE[1])))
	for k in 5:
		_excl.append([rp + rd * (1.8 + k * 1.8), 1.6])


## Catmull-Rom through the control points, sampled every 0.5 m.
func _spline(ctrl: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		var steps := maxi(1, int(p1.distance_to(p2) / 0.5))
		for s in steps:
			var t := float(s) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out


func stream_x(z: float) -> float:
	return 104.0 + 3.0 * sin(z / 23.0) + 1.5 * sin(z / 9.0 + 1.0)


func _road_h(z: float) -> float:
	return _noise_a.get_noise_2d(ROAD_X, z) * 1.3


# ---------------------------------------------------------------------------
# heights (1 m grid), trail fields (0.5 m grid)
# ---------------------------------------------------------------------------
func _heights() -> void:
	_hw = int(X1 - X0) + 1
	_hd = int(Z1 - Z0) + 1
	_hgrid.resize(_hw * _hd)
	for j in _hd:
		var z := Z0 + j
		var rh := _road_h(z)
		for i in _hw:
			var x := X0 + i
			var low := _noise_a.get_noise_2d(x, z) * 1.6
			var h := low + _noise_b.get_noise_2d(x, z) * 0.55 + _noise_c.get_noise_2d(x, z) * 0.12
			var dx := maxf(maxf(ESTATE.position.x - x, x - ESTATE.end.x), 0.0)
			var dz := maxf(maxf(ESTATE.position.y - z, z - ESTATE.end.y), 0.0)
			var we := smoothstep(0.0, 18.0, sqrt(dx * dx + dz * dz))
			h *= we
			var wr := smoothstep(ROAD_HW + 1.5, ROAD_HW + 8.0, absf(x - ROAD_X))
			h = lerpf(rh, h, wr)
			_hgrid[j * _hw + i] = h
	_bridge = {"base": 0.0}


func _trail_fields() -> void:
	_gw = int((X1 - X0) / CELL)
	_gd = int((Z1 - Z0) / CELL)
	_dirt.resize(_gw * _gd)
	_dirt.fill(0)
	_pdist.resize(_gw * _gd)
	_pdist.fill(99.0)
	for tr: Dictionary in _trails:
		var pts: PackedVector2Array = tr.pts
		var w: float = tr.w
		var fade: bool = tr.fade
		var n := pts.size()
		for k in n:
			var f := float(k) / float(maxi(n - 1, 1))
			var s := 1.0
			var ww := w
			if fade and f > 0.6:
				s = lerpf(1.0, 0.18, (f - 0.6) / 0.4)
				ww = lerpf(w, w * 0.6, (f - 0.6) / 0.4)
			_stamp_trail(pts[k], ww, s)
	# smooth the ground along the trails, sink them a touch; the bridge approaches
	var b0 := _hraw(BRIDGE_C.x - BRIDGE_LEN * 0.5, BRIDGE_C.y)
	var b1 := _hraw(BRIDGE_C.x + BRIDGE_LEN * 0.5, BRIDGE_C.y)
	var deck := (b0 + b1) * 0.5
	_bridge = {"base": deck}
	var smooth := _hgrid.duplicate()
	for j in range(1, _hd - 1):
		for i in range(1, _hw - 1):
			var acc := 0.0
			for dj in range(-2, 3):
				var jj := clampi(j + dj, 0, _hd - 1)
				for di in range(-2, 3):
					acc += _hgrid[jj * _hw + clampi(i + di, 0, _hw - 1)]
			smooth[j * _hw + i] = acc / 25.0
	for j in _hd:
		var z := Z0 + j
		var sx := stream_x(z)
		for i in _hw:
			var x := X0 + i
			var idx := j * _hw + i
			var pd := _pdist_at(x, z)
			var h := _hgrid[idx]
			if pd < 2.5:
				var k := 1.0 - smoothstep(0.0, 2.5, pd)
				h = lerpf(h, smooth[idx], k * 0.85) - 0.05 * (1.0 - smoothstep(-0.6, 0.2, pd))
			var bdx := absf(x - BRIDGE_C.x)
			var bdz := absf(z - BRIDGE_C.y)
			if bdx < 10.0 and bdz < 4.0:
				var wb := (1.0 - smoothstep(4.0, 10.0, bdx)) * (1.0 - smoothstep(1.5, 4.0, bdz))
				h = lerpf(h, deck, wb)
			var ds := absf(x - sx)
			if ds < 3.4:
				h -= 0.95 * (1.0 - smoothstep(0.75, 3.2, ds))
			_hgrid[idx] = h


func _stamp_trail(p: Vector2, w: float, s: float) -> void:
	var r := w * 0.5 + 2.0
	var i0 := maxi(0, int((p.x - r - X0) / CELL))
	var i1 := mini(_gw - 1, int((p.x + r - X0) / CELL))
	var j0 := maxi(0, int((p.y - r - Z0) / CELL))
	var j1 := mini(_gd - 1, int((p.y + r - Z0) / CELL))
	var hw := w * 0.5
	for j in range(j0, j1 + 1):
		var cz := Z0 + (j + 0.5) * CELL
		for i in range(i0, i1 + 1):
			var cx := X0 + (i + 0.5) * CELL
			var d := Vector2(cx - p.x, cz - p.y).length()
			var idx := j * _gw + i
			var ed := d - hw
			if ed < _pdist[idx]:
				_pdist[idx] = ed
			var dv := s * (1.0 - smoothstep(hw * 0.55, hw * 1.15, d))
			var b := int(dv * 255.0)
			if b > _dirt[idx]:
				_dirt[idx] = b


func _pdist_at(x: float, z: float) -> float:
	var i := clampi(int((x - X0) / CELL), 0, _gw - 1)
	var j := clampi(int((z - Z0) / CELL), 0, _gd - 1)
	return _pdist[j * _gw + i]


func _dirt_at(x: float, z: float) -> float:
	var i := clampi(int((x - X0) / CELL), 0, _gw - 1)
	var j := clampi(int((z - Z0) / CELL), 0, _gd - 1)
	return _dirt[j * _gw + i] / 255.0


func _hraw(x: float, z: float) -> float:
	var fx := clampf(x - X0, 0.0, float(_hw - 1) - 0.001)
	var fz := clampf(z - Z0, 0.0, float(_hd - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := _hgrid[j * _hw + i]
	var b := _hgrid[j * _hw + i + 1]
	var c := _hgrid[(j + 1) * _hw + i]
	var d := _hgrid[(j + 1) * _hw + i + 1]
	# the same diagonal split as the terrain triangles
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


## Local ground height at (x, z): terrain, the footbridge deck, entrance landings.
func height_at(x: float, z: float) -> float:
	if not _bridge.is_empty() and absf(x - BRIDGE_C.x) < BRIDGE_LEN * 0.5 + 0.8 and absf(z - BRIDGE_C.y) < 0.85:
		return float(_bridge.base) + 0.04
	if x > COURT.position.x - 13.0 and x < COURT.end.x + 13.0 and z > COURT.position.y - 13.0 and z < COURT.end.y + 13.0:
		for e: Dictionary in _entr:
			var q: Vector3 = (e.inv as Transform3D) * Vector3(x, 0.0, z)
			if absf(q.x) < 1.3 and q.z > -0.3 and q.z < 2.45:
				if q.z < 1.3:
					return ExteriorProps.GF
				return lerpf(ExteriorProps.GF, 0.0, (q.z - 1.3) / 1.15)
	return _hraw(x, z)


func _in_rects(x: float, z: float, margin := 0.0) -> bool:
	for r: Array in _rects:
		if (r[0] as Rect2).grow(margin).has_point(Vector2(x, z)):
			return true
	return false


func _in_block(x: float, z: float, margin := 0.0) -> bool:
	for b: Dictionary in _blocks:
		var q: Vector3 = (b.inv as Transform3D) * Vector3(x, 0.0, z)
		if q.x > -margin and q.x < float(b.len) + margin and q.z > -margin and q.z < float(b.depth) + margin:
			return true
	return false


# ---------------------------------------------------------------------------
# colliders (one static body; shapes shared by size)
# ---------------------------------------------------------------------------
func _box_col(size: Vector3, xf: Transform3D) -> void:
	var key := "b%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _shapes.has(key):
		var bs := BoxShape3D.new()
		bs.size = size
		_shapes[key] = bs
	var o := _body.create_shape_owner(_body)
	_body.shape_owner_add_shape(o, _shapes[key])
	_body.shape_owner_set_transform(o, xf)


func _cyl_col(r: float, h: float, pos: Vector3) -> void:
	var rr := snappedf(r, 0.02)
	var key := "c%.2f_%.1f" % [rr, h]
	if not _shapes.has(key):
		var cs := CylinderShape3D.new()
		cs.radius = rr
		cs.height = h
		_shapes[key] = cs
	var o := _body.create_shape_owner(_body)
	_body.shape_owner_add_shape(o, _shapes[key])
	_body.shape_owner_set_transform(o, Transform3D(Basis.IDENTITY, pos + Vector3(0, h * 0.5 - 0.3, 0)))


## Prop colliders given in a node's space.
func _cols_from(node: Node3D, cols: Array) -> void:
	var base := transform_to_local(node)
	for c: Array in cols:
		_box_col(c[0], base * (c[1] as Transform3D))
	cols.clear()


func transform_to_local(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


# ---------------------------------------------------------------------------
# terrain: chunked meshes, trimesh colliders, the splat map
# ---------------------------------------------------------------------------
func _terrain() -> void:
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	var ncx := int(ceil((X1 - X0) / CHUNK))
	var ncz := int(ceil((Z1 - Z0) / CHUNK))
	for cz in ncz:
		for cx in ncx:
			var i0 := int(cx * CHUNK)
			var j0 := int(cz * CHUNK)
			var i1 := mini(i0 + int(CHUNK), _hw - 1)
			var j1 := mini(j0 + int(CHUNK), _hd - 1)
			var nx := i1 - i0 + 1
			var nz := j1 - j0 + 1
			var v := PackedVector3Array()
			var nrm := PackedVector3Array()
			var uv := PackedVector2Array()
			v.resize(nx * nz)
			nrm.resize(nx * nz)
			uv.resize(nx * nz)
			for j in nz:
				for i in nx:
					var gi := i0 + i
					var gj := j0 + j
					var h := _hgrid[gj * _hw + gi]
					var x := X0 + gi
					var z := Z0 + gj
					var hl := _hgrid[gj * _hw + maxi(gi - 1, 0)]
					var hr := _hgrid[gj * _hw + mini(gi + 1, _hw - 1)]
					var hu := _hgrid[maxi(gj - 1, 0) * _hw + gi]
					var hd := _hgrid[mini(gj + 1, _hd - 1) * _hw + gi]
					var k := j * nx + i
					v[k] = Vector3(x, h, z)
					nrm[k] = Vector3(hl - hr, 2.0, hu - hd).normalized()
					uv[k] = Vector2(x, z)
			var idx := PackedInt32Array()
			var faces := PackedVector3Array()
			for j in nz - 1:
				for i in nx - 1:
					var a := j * nx + i
					var b := a + 1
					var c := a + nx
					var d := c + 1
					# split along b-c (matches _hraw); clockwise seen from above
					for t: Array in [[a, b, c], [b, d, c]]:
						idx.append(t[0])
						idx.append(t[1])
						idx.append(t[2])
						faces.append(v[t[0]])
						faces.append(v[t[1]])
						faces.append(v[t[2]])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_NORMAL] = nrm
			arr[Mesh.ARRAY_TEX_UV] = uv
			arr[Mesh.ARRAY_INDEX] = idx
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.generate_tangents()
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
			mesh.surface_set_material(0, _m.terrain)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 190.0
			root.add_child(mi)
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var o := _body.create_shape_owner(_body)
			_body.shape_owner_add_shape(o, shape)
	_splat()


func _splat() -> void:
	var data := PackedByteArray()
	data.resize(_gw * _gd * 4)
	for j in _gd:
		var z := Z0 + (j + 0.5) * CELL
		var sx := stream_x(z)
		for i in _gw:
			var x := X0 + (i + 0.5) * CELL
			var k := (j * _gw + i) * 4
			var path := float(_dirt[j * _gw + i]) / 255.0
			var moss := clampf(_noise_b.get_noise_2d(x * 0.7 + 50.0, z * 0.7) * 1.4 + 0.15, 0.0, 1.0)
			var lawn := 0.0
			var wet := 0.0
			if COURT.grow(-0.5).has_point(Vector2(x, z)) or Rect2(36.0, 10.0, 10.0, 21.5).has_point(Vector2(x, z)):
				lawn = 1.0
				moss *= 0.3
			if absf(x - ROAD_X) < ROAD_HW + 2.6 and absf(x - ROAD_X) > ROAD_HW + 0.3:
				lawn = maxf(lawn, 0.75)
			var ds := absf(x - sx)
			if ds < 2.6:
				wet = 1.0 - smoothstep(1.2, 2.6, ds)
				moss = maxf(moss, (1.0 - smoothstep(2.0, 4.0, ds)) * 0.8)
			elif ds < 6.0:
				moss = maxf(moss, (1.0 - smoothstep(2.6, 6.0, ds)) * 0.7)
			if path > 0.2:
				wet = maxf(wet, clampf(_noise_c.get_noise_2d(x * 1.7, z * 1.7) * 2.0 - 0.7, 0.0, 1.0) * path)
				moss *= 0.5
			data[k] = int(path * 255.0)
			data[k + 1] = int(clampf(moss, 0.0, 1.0) * 255.0)
			data[k + 2] = int(lawn * 255.0)
			data[k + 3] = int(clampf(wet, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(_gw, _gd, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(img)
	_m.terrain.set_shader_parameter("splat", tex)
	_m.terrain.set_shader_parameter("splat_rect", Vector4(X0, Z0, 1.0 / (X1 - X0), 1.0 / (Z1 - Z0)))

# ---------------------------------------------------------------------------
# the solid grid for path(): every box collider taller than a kerb blocks it
# ---------------------------------------------------------------------------
func _solid_obb(size: Vector3, xf: Transform3D, inflate := 0.32) -> void:
	if _solid.is_empty():
		return
	var hx := size.x * 0.5 + inflate
	var hz := size.z * 0.5 + inflate
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
	var az := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
	if ax.length() < 0.5 or az.length() < 0.5:
		return
	var c := Vector2(xf.origin.x, xf.origin.z)
	var ext := absf(ax.x) * hx + absf(az.x) * hz
	var exz := absf(ax.y) * hx + absf(az.y) * hz
	var i0 := maxi(0, int((c.x - ext - X0) / CELL))
	var i1 := mini(_gw - 1, int((c.x + ext - X0) / CELL))
	var j0 := maxi(0, int((c.y - exz - Z0) / CELL))
	var j1 := mini(_gd - 1, int((c.y + exz - Z0) / CELL))
	for j in range(j0, j1 + 1):
		var cz := Z0 + (j + 0.5) * CELL
		for i in range(i0, i1 + 1):
			var d := Vector2(X0 + (i + 0.5) * CELL, cz) - c
			if absf(d.dot(ax)) <= hx and absf(d.dot(az)) <= hz:
				_solid[j * _gw + i] = 1


func _solid_disc(p: Vector2, r: float) -> void:
	var i0 := maxi(0, int((p.x - r - X0) / CELL))
	var i1 := mini(_gw - 1, int((p.x + r - X0) / CELL))
	var j0 := maxi(0, int((p.y - r - Z0) / CELL))
	var j1 := mini(_gd - 1, int((p.y + r - Z0) / CELL))
	var r2 := r * r
	for j in range(j0, j1 + 1):
		var cz := Z0 + (j + 0.5) * CELL - p.y
		for i in range(i0, i1 + 1):
			var cx := X0 + (i + 0.5) * CELL - p.x
			if cx * cx + cz * cz <= r2:
				_solid[j * _gw + i] = 1


## A box collider that also blocks path() when it is more than knee high.
func _wall(size: Vector3, xf: Transform3D) -> void:
	_box_col(size, xf)
	var ground := _hraw(xf.origin.x, xf.origin.z) if not _hgrid.is_empty() else 0.0
	if xf.origin.y + size.y * 0.5 > ground + 0.1 and absf(xf.basis.y.normalized().y) > 0.95:
		_solid_obb(size, xf)


func _wall_cols(node: Node3D, cols: Array) -> void:
	var base := transform_to_local(node)
	for c: Array in cols:
		_wall(c[0], base * (c[1] as Transform3D))
	cols.clear()


# ---------------------------------------------------------------------------
# the estate: paving, kerbs, lawns
# ---------------------------------------------------------------------------
func _estate() -> void:
	_solid.resize(_gw * _gd)
	_solid.fill(0)
	var root := Node3D.new()
	root.name = "Estate"
	add_child(root)
	var pav := ExteriorProps.MBuf.new()
	var asp := ExteriorProps.MBuf.new()
	for r: Array in _rects:
		_ground_strip(pav if r[1] == "paving" else asp, r[0], 2.0, 0.025)
	var mesh := pav.to_mesh(_m.paving, true)
	asp.commit(mesh, _m.asphalt, true)
	var g := MeshInstance3D.new()
	g.mesh = mesh
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)


## Kerbs where the paving meets the lawn (after the blocks and entrances exist).
func _kerbs() -> void:
	var root := get_node("Estate") as Node3D
	# kerbs where paving meets the lawn
	var kb := ExteriorProps.MBuf.new()
	for r: Array in _rects:
		if r[1] != "paving":
			continue
		var rc: Rect2 = r[0]
		var edges := [[rc.position, Vector2(rc.end.x, rc.position.y), Vector2(0, -1)], [Vector2(rc.position.x, rc.end.y), rc.end, Vector2(0, 1)],
			[rc.position, Vector2(rc.position.x, rc.end.y), Vector2(-1, 0)], [Vector2(rc.end.x, rc.position.y), rc.end, Vector2(1, 0)]]
		for e: Array in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var nrm: Vector2 = e[2]
			var length := a.distance_to(b)
			var dir := (b - a) / maxf(length, 0.01)
			var run_start := -1.0
			var t := 0.0
			while t <= length + 0.01:
				var p := a + dir * minf(t, length)
				var q := p + nrm * 0.3
				var need := COURT.has_point(q) and not _in_rects(q.x, q.y) and not _in_block(q.x, q.y, 0.4) and not _entrance_near(q, 0.6)
				if need and run_start < 0.0:
					run_start = t
				if (not need or t >= length) and run_start >= 0.0:
					var t1 := minf(t, length)
					if t1 - run_start > 0.3:
						var mid := a + dir * (run_start + t1) * 0.5 + nrm * 0.06
						var basis := Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(dir.x, 0, dir.y).cross(Vector3.UP))
						kb.box(Transform3D(basis, Vector3(mid.x, 0.03, mid.y)), Vector3(t1 - run_start, 0.15, 0.12))
					run_start = -1.0
				t += 0.5
	var km := MeshInstance3D.new()
	km.mesh = kb.to_mesh(_m.kerb, true)
	km.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(km)


func _entrance_near(q: Vector2, margin: float) -> bool:
	for e: Dictionary in _entr:
		var p: Vector3 = (e.inv as Transform3D) * Vector3(q.x, 0.0, q.y)
		if absf(p.x) < 1.3 + margin and p.z > -0.3 and p.z < 2.5 + margin:
			return true
	return false


## A paved strip over a rectangle that follows the ground (quads every `step` m).
func _ground_strip(b: ExteriorProps.MBuf, rc: Rect2, step: float, lift: float) -> void:
	var nx := maxi(1, int(ceil(rc.size.x / step)))
	var nz := maxi(1, int(ceil(rc.size.y / step)))
	for j in nz:
		for i in nx:
			var x0 := rc.position.x + rc.size.x * float(i) / nx
			var x1 := rc.position.x + rc.size.x * float(i + 1) / nx
			var z0 := rc.position.y + rc.size.y * float(j) / nz
			var z1 := rc.position.y + rc.size.y * float(j + 1) / nz
			var p0 := Vector3(x0, _hraw(x0, z0) + lift, z0)
			var p1 := Vector3(x1, _hraw(x1, z0) + lift, z0)
			var p2 := Vector3(x1, _hraw(x1, z1) + lift, z1)
			var p3 := Vector3(x0, _hraw(x0, z1) + lift, z1)
			var nn := (p3 - p0).cross(p1 - p0).normalized()
			ExteriorProps.fquad(b, p0, p1, p2, p3, nn, Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))


# ---------------------------------------------------------------------------
# the blocks, their entrances and the instanced window parts
# ---------------------------------------------------------------------------
func _blocks_build() -> void:
	var root := get_node("Estate") as Node3D
	var parts := {}
	for spec: Array in BLOCKS:
		var num: int = spec[0]
		var xf := Transform3D(Basis(Vector3.UP, float(spec[2])), spec[1])
		var length: float = spec[3]
		var res := ExteriorProps.block(root, _m, {"len": length, "depth": 11.0, "floors": spec[4], "units": spec[5], "wall": _m[spec[6]],
				"number": num, "door": _m[spec[7]], "seed": 100 + num, "lit": 0.14, "xf": xf, "someone": Vector2i(HER_UNIT - 1, 3) if num == HER_BLOCK else Vector2i(-1, -1)}, parts)
		var top: float = res.top
		_blocks.append({"xf": xf, "inv": xf.affine_inverse(), "len": length, "depth": 11.0, "top": top, "num": num})
		_box_col(Vector3(length, top + 0.6, 11.0), xf * Transform3D(Basis.IDENTITY, Vector3(length * 0.5, (top + 0.6) * 0.5 - 0.3, 5.5)))
		_solid_obb(Vector3(length, 1.0, 11.0), xf * Transform3D(Basis.IDENTITY, Vector3(length * 0.5, 0.5, 5.5)), 0.32)
		for e: Dictionary in res.entrances:
			var unit: int = e.unit
			var oxf := xf * ExteriorProps.opening_xf(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD, float(e.u), 0.0)
			var ent := ExteriorProps.entrance(root, _m, oxf, unit, _m[spec[7]], num * 10 + unit)
			for c: Array in ent.colliders:
				_box_col(c[0], oxf * (c[1] as Transform3D))
			_entr.append({"xf": oxf, "inv": oxf.affine_inverse(), "block": num, "unit": unit})
			var mode := "steady"
			var hers := num == HER_BLOCK and unit == HER_UNIT
			var his := num == HIS_BLOCK and unit == HIS_UNIT
			if hers:
				mode = "dying"
			elif not his:
				var r := _rng.randf()
				mode = "steady" if r < 0.45 else ("flicker" if r < 0.6 else "dead")
			_add_lamp(ent.light, [ent.bulb], null, mode, 6.0, null)
			if hers:
				_interact("her_unit", "ACT_ENTER", oxf * Transform3D(Basis.IDENTITY, Vector3(0, ExteriorProps.GF + 1.1, 0.35)), Vector3(1.8, 2.3, 1.0), true)
				_spot("her_unit_door", oxf * Vector3(0, 0, 2.75), _yaw_toward(oxf * Vector3(0, 0, 2.75), oxf * Vector3(0, 1.0, 0)))
				_spot("chase_start", oxf * Vector3(0, 0, 2.9), _yaw_toward(oxf * Vector3(0, 0, 2.9), oxf * Vector3(0, 0, 6.0)))
				_spot("her_door_step", oxf * Vector3(0, ExteriorProps.GF, 0.35), _yaw_toward(oxf * Vector3(0, 0, 0.35), oxf * Vector3(0, 0, 4.0)))
			if his:
				_spot("his_door", oxf * Vector3(0, 0, 2.75), _yaw_toward(oxf * Vector3(0, 0, 2.75), oxf * Vector3(0, 0, 8.0)))
	_parts_to_multimesh(root, parts)
	_kerbs()


func _parts_to_multimesh(root: Node3D, parts: Dictionary) -> void:
	var glass := ExteriorProps.MBuf.new()
	ExteriorProps.fquad(glass, Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), Vector3.BACK,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	var streak := ExteriorProps.MBuf.new()
	ExteriorProps.fquad(streak, Vector3(-0.5, -1, 0), Vector3(0.5, -1, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3.BACK,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	var frame_cols := [Color(0.62, 0.78, 0.7), Color(0.9, 0.93, 0.92), Color(0.5, 0.36, 0.26), Color(0.66, 0.72, 0.78), Color(0.46, 0.62, 0.72)]
	var fr := RandomNumberGenerator.new()
	fr.seed = 77
	for kind: String in parts:
		var list: Array = parts[kind]
		if kind.begins_with("frame_"):
			for it: Array in list:
				it[1] = frame_cols[fr.randi_range(0, frame_cols.size() - 1)] * fr.randf_range(0.85, 1.05)
			_mm(root, ExteriorProps.window_frame(kind.substr(6), _m), list, false, true, false)
		elif kind.begins_with("cage_"):
			_mm(root, ExteriorProps.window_cage(kind.substr(5), _m), list, false, false, false)
		elif kind == "glass":
			_mm(root, glass.to_mesh(_m.glass_win_mm), list, true, false, false)
		elif kind == "sill":
			var sm := MeshUtil.box(Vector3.ONE)
			sm.surface_set_material(0, _m.band)
			_mm(root, sm, list, false, false, false)
		elif kind == "ac":
			_mm(root, ExteriorProps.ac_unit(_m), list, false, false, true)
		elif kind == "streak":
			_mm(root, streak.to_mesh(_m.streak), list, true, false, false)
		elif kind == "bal_open" or kind == "bal_closed" or kind == "laundry":
			var nvar := 3
			var groups: Array = [[], [], []]
			for i in list.size():
				groups[i % nvar].append(list[i])
			for v in nvar:
				if groups[v].is_empty():
					continue
				var mesh: Mesh
				if kind == "laundry":
					mesh = ExteriorProps.laundry(_m, 300 + v, 2.2)
				else:
					mesh = ExteriorProps.balcony(_m, kind == "bal_closed", 200 + v * 13 + (7 if kind == "bal_closed" else 0))
				_mm(root, mesh, groups[v], false, false, kind != "laundry")


func _mm(parent: Node3D, mesh: Mesh, list: Array, custom: bool, colors: bool, shadow: bool, vis_end := 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var it: Array = list[i]
		mm.set_instance_transform(i, it[0])
		if custom:
			mm.set_instance_custom_data(i, it[1])
		if colors:
			mm.set_instance_color(i, it[1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
	parent.add_child(mmi)
	return mmi


func _spot(name: String, local: Vector3, yaw := INF) -> void:
	spots[name] = to_global(local)
	if yaw != INF:
		spot_yaw[name] = yaw + global_rotation.y


## Player yaw (0 looks along -z) for looking from a towards b (local points).
func _yaw_toward(a: Vector3, b: Vector3) -> float:
	var d := b - a
	return atan2(-d.x, -d.z)


func _interact(id: String, prompt: String, xf: Transform3D, size: Vector3, on: bool) -> Area3D:
	var a := Area3D.new()
	a.name = "I_" + id
	a.transform = xf
	a.collision_layer = 2 if on else 0
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.set_meta("interact", prompt)
	a.set_meta("id", id)
	add_child(a)
	interactables[id] = a
	return a


## Hiding places answer E only while the chase is on.
func set_hides_active(on: bool) -> void:
	for id: String in interactables:
		if id.begins_with("hide_"):
			(interactables[id] as Area3D).collision_layer = 2 if on else 0


# ---------------------------------------------------------------------------
# lamps (street lamps, entrance bulbs, the bike shed tube): each runs its own
# flicker: steady | flicker | dying | dead
# ---------------------------------------------------------------------------
func _add_lamp(light: Light3D, mats: Array, halo: ShaderMaterial, mode: String, emit: float, buzz_at: Node3D) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = 500 + lamps.size() * 17
	var L := {"light": light, "mats": mats, "halo": halo, "mode": mode, "energy": light.light_energy, "emit": emit,
		"t": r.randf() * 50.0, "next": r.randf_range(1.0, 6.0), "burst": 0.0, "hold": 0.0, "blevel": 1.0, "level": 1.0,
		"rng": r, "buzz": null, "prev": 1.0}
	if buzz_at and ResourceLoader.exists(SFX + "lamp_buzz.ogg"):
		var p := AudioStreamPlayer3D.new()
		var st: AudioStream = load(SFX + "lamp_buzz.ogg")
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		p.stream = st
		p.bus = "Ambience"
		p.unit_size = 2.5
		p.max_distance = 16.0
		p.volume_db = -14.0
		buzz_at.add_child(p)
		L.buzz = p
	lamps.append(L)
	_lamp_apply(L, 0.0 if mode == "dead" else 1.0)
	return L


func _lamp_level(L: Dictionary, delta: float) -> float:
	L.t = float(L.t) + delta
	var t: float = L.t
	var r: RandomNumberGenerator = L.rng
	var hum := 1.0 - 0.03 * (sin(t * 31.0) * 0.5 + sin(t * 17.3) * 0.5)
	match String(L.mode):
		"dead":
			return 0.0
		"steady":
			L.next = float(L.next) - delta
			if float(L.next) <= 0.0:
				L.burst = r.randf_range(0.06, 0.25)
				L.next = r.randf_range(12.0, 30.0)
			if float(L.burst) > 0.0:
				L.burst = float(L.burst) - delta
				return 0.5 * hum
			return hum
		"dying":
			L.next = float(L.next) - delta
			if float(L.next) <= 0.0:
				L.burst = r.randf_range(0.1, 0.6)
				L.next = r.randf_range(1.5, 5.0)
			if float(L.burst) > 0.0:
				L.burst = float(L.burst) - delta
				return _lamp_stutter(L, delta, 0.05, 1.0)
			return 0.22 + 0.06 * sin(t * 3.1) * sin(t * 1.3)
		_:
			L.next = float(L.next) - delta
			if float(L.next) <= 0.0:
				L.burst = r.randf_range(0.15, 1.1)
				L.next = r.randf_range(3.0, 10.0)
			if float(L.burst) > 0.0:
				L.burst = float(L.burst) - delta
				return _lamp_stutter(L, delta, 0.0, 1.0)
			return hum


func _lamp_stutter(L: Dictionary, delta: float, lo: float, hi: float) -> float:
	var r: RandomNumberGenerator = L.rng
	L.hold = float(L.hold) - delta
	if float(L.hold) <= 0.0:
		L.hold = r.randf_range(0.02, 0.1)
		L.blevel = lo + r.randf() * 0.25 if r.randf() < 0.55 else hi * r.randf_range(0.75, 1.0)
	return L.blevel


func _lamp_apply(L: Dictionary, level: float) -> void:
	var light: Light3D = L.light
	light.light_energy = float(L.energy) * level
	light.visible = level > 0.01
	for mt: StandardMaterial3D in L.mats:
		mt.emission_energy_multiplier = float(L.emit) * pow(level, 1.3) + 0.03
	if L.halo:
		(L.halo as ShaderMaterial).set_shader_parameter("intensity", pow(level, 1.5))
	if L.buzz:
		var p: AudioStreamPlayer3D = L.buzz
		p.volume_db = linear_to_db(clampf(0.05 + level * 0.8, 0.0001, 1.0)) - 13.0


# ---------------------------------------------------------------------------
# street furniture
# ---------------------------------------------------------------------------
const LAMPS := [
	[Vector2(-24, -24.8), Vector2(0, -1), "mercury", "steady", false],
	[Vector2(-8, -24.8), Vector2(0, -1), "mercury", "flicker", false],
	[Vector2(10, -24.8), Vector2(0, -1), "mercury", "steady", false],
	[Vector2(29.0, -24.4), Vector2(-0.7, -0.7), "mercury", "steady", false],
	[Vector2(34.4, -6.0), Vector2(-1, 0), "sodium", "steady", true],
	[Vector2(34.4, 13.0), Vector2(-1, 0), "mercury", "dying", false],
	[Vector2(42.2, 25.4), Vector2(0.3, 1), "mercury", "flicker", true],
	[Vector2(24.0, 25.6), Vector2(0, 1), "mercury", "steady", false],
	[Vector2(6.0, 25.6), Vector2(0, 1), "mercury", "steady", false],
	[Vector2(-16.0, 25.6), Vector2(0, 1), "sodium", "flicker", false],
	[Vector2(-32.4, 12.0), Vector2(-1, 0), "mercury", "dead", false],
	[Vector2(-32.4, -12.0), Vector2(-1, 0), "mercury", "steady", false],
	[Vector2(-9.4, -7.4), Vector2(0.7, 0.7), "mercury", "steady", false],
]


func _street() -> void:
	var root := get_node("Estate") as Node3D
	var cols: Array = []
	for L: Array in LAMPS:
		var p: Vector2 = L[0]
		var d: Vector2 = (L[1] as Vector2).normalized()
		var xf := Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3(p.x, 0.0, p.y))
		var lamp := ExteriorProps.street_lamp(_lights, _m, xf, L[2], 6.8, cols)
		_wall_cols(lamp.node, cols)
		var light: SpotLight3D = lamp.light
		if L[4]:
			light.shadow_enabled = true
		_add_lamp(light, [lamp.glass], lamp.halo, L[3], 8.0, lamp.node.get_child(lamp.node.get_child_count() - 1) as Node3D)
	# bike shed along the front of block 2, open to its path
	var bikes := [ExteriorProps.bicycle(_m, _m.bike_black), ExteriorProps.bicycle(_m, _m.bike_green), ExteriorProps.bicycle(_m, _m.bike_black)]
	var shed := ExteriorProps.bike_shed(root, _m, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-27.6, 0, -14.0)), 10.0, bikes, cols, 5)
	_wall_cols(shed.node, cols)
	_add_lamp(shed.light, [shed.tube], null, "flicker", 5.0, shed.node)
	# a bicycle left against a lamp post and one by her entrance
	var b1 := ExteriorProps.mi(root, bikes[0], Vector3(-30.9, 0, 11.4), Vector3(0.12, 0.4, 0))
	b1.name = "LoneBike"
	ExteriorProps.mi(root, bikes[1], Vector3(36.6, 0, 30.4), Vector3(-0.1, PI * 0.5, 0))
	# bins
	var bin_mats := [_m.bin_green, _m.bin_green, _m.bin_blue, _m.bin_grey]
	for k in 4:
		var bn := ExteriorProps.wheelie_bin(root, _m, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)), Vector3(-9.6 + k * 0.78, 0, 25.3)), bin_mats[k], k == 2, cols)
		_wall_cols(bn, cols)
	for k in 3:
		ExteriorProps.rubbish_bag(root, _m, Vector3(-5.9 + _rng.randf_range(-0.3, 0.5), 0, 25.4 + _rng.randf_range(-0.3, 0.3)), 40 + k)
	for k in 2:
		var bn2 := ExteriorProps.wheelie_bin(root, _m, Transform3D(Basis(Vector3.UP, PI + _rng.randf_range(-0.1, 0.1)), Vector3(21.6 + k * 0.8, 0, -24.6)), bin_mats[k * 3], false, cols)
		_wall_cols(bn2, cols)
	# parked cars by block 3
	var car := ExteriorProps.car(root, _m, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(27.7, 0, -4.4)), _m.car_teal, false, 3, cols)
	_wall_cols(car, cols)
	var navy := _m.car_teal.duplicate() as StandardMaterial3D
	navy.albedo_color = Color(0.06, 0.09, 0.2)
	var car2 := ExteriorProps.car(root, _m, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(27.8, 0, 4.6)), navy, false, 4, cols)
	_wall_cols(car2, cols)
	# benches, the stone table, a washing line, a climbing frame, the notice board
	for bxf: Transform3D in [Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(8.6, 0, -4.0)), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(8.6, 0, 4.0)),
			Transform3D(Basis(Vector3.UP, PI), Vector3(-11.6, 0, -24.4)), Transform3D(Basis.IDENTITY, Vector3(16.0, 0, 26.0))]:
		var bench := ExteriorProps.bench(root, _m, bxf, cols)
		_wall_cols(bench, cols)
	_wall_cols(ExteriorProps.stone_table(root, _m, Vector3(-4.0, 0, 3.0), cols), cols)
	_wall_cols(ExteriorProps.clothes_line(root, _m, Transform3D(Basis.IDENTITY, Vector3(-27.0, 0, 5.6)), 6.0, 9, cols), cols)
	_wall_cols(ExteriorProps.climbing_frame(root, _m, Transform3D(Basis(Vector3.UP, 0.3), Vector3(15.0, 0, 16.0)), cols), cols)
	_wall_cols(ExteriorProps.notice_board(root, _m, Transform3D(Basis(Vector3.UP, PI), Vector3(-14.4, 0, -24.4)), cols), cols)
	# railings round the courtyard, the gap to the forest, the gate and its hut
	var bars := ExteriorProps.MBuf.new()
	var conc := ExteriorProps.MBuf.new()
	var fcols: Array = []
	for f: Array in FENCES:
		var a: Vector2 = f[0]
		var c: Vector2 = f[1]
		ExteriorProps.railing(bars, conc, Vector3(a.x, _hraw(a.x, a.y), a.y), Vector3(c.x, _hraw(c.x, c.y), c.y), _rng, fcols, f[2])
	ExteriorProps.railing(bars, conc, Vector3(36.8, 0, -31.2), Vector3(36.8, 0, -29.4), _rng, fcols)
	for c2: Array in fcols:
		_wall(c2[0], c2[1])
	var fm := bars.to_mesh(_m.lamp_pole, true)
	conc.commit(fm, _m.concrete, true)
	var fmi := MeshInstance3D.new()
	fmi.mesh = fm
	root.add_child(fmi)
	var gate := ExteriorProps.gatehouse(root, _m, Transform3D(Basis.IDENTITY, Vector3(GATE_X.x, 0, GATE_Z)), GATE_X.y - GATE_X.x, cols)
	_wall_cols(gate.node, cols)
	_wall(Vector3(1.0, 1.8, 0.4), Transform3D(Basis.IDENTITY, Vector3(GATE_X.y + 0.5, 0.9, GATE_Z)))
	_add_lamp(gate.light, [], null, "steady", 0.0, null)
	# hedges along the square
	var hedge: Array = []
	for z in range(-7, 9):
		if absf(z + 0.5) < 2.0:
			continue
		for sx: float in [-10.6, 10.6]:
			hedge.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.15)), Vector3(sx, 0, z + 0.5)), Color(0, 0, _rng.randf(), 0)])
	_mm(root, ExteriorProps.bush(9, _m, 0.9), hedge, true, false, false, 70.0).material_override = _m.leaf_hedge
	for h: Array in hedge:
		_solid_obb(Vector3(0.5, 1.0, 0.5), h[0], 0.0)

# ---------------------------------------------------------------------------
# the forest landmarks and the hiding places
# ---------------------------------------------------------------------------
var _forced_trees: Array = []        # [kind, variant, Vector2, yaw, scale, collide]
var _world_env: WorldEnvironment


func _xf2(p: Vector2, yaw: float, lift := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, height_at(p.x, p.y) + lift, p.y))


func _landmarks() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	var cols: Array = []
	# the footbridge: deck walkable, railings solid
	var deck: float = _bridge.base
	var br := ExteriorProps.footbridge(root, _m, Transform3D(Basis.IDENTITY, Vector3(BRIDGE_C.x, deck + 0.04, BRIDGE_C.y)), BRIDGE_LEN, 61, cols)
	var bxf := transform_to_local(br)
	for c: Array in cols:
		if (c[0] as Vector3).y < 0.5:
			_box_col(c[0], bxf * (c[1] as Transform3D))
		else:
			_wall(c[0], bxf * (c[1] as Transform3D))
	cols.clear()
	_spot("bridge", Vector3(BRIDGE_C.x, deck + 0.04, BRIDGE_C.y))
	# the hunter's stand and its woodpile
	var stand := ExteriorProps.hunters_stand(root, _m, _xf2(STAND[0], STAND[1]), 71, cols)
	_wall_cols(stand, cols)
	_spot("stand", Vector3((STAND[0] as Vector2).x, height_at((STAND[0] as Vector2).x, (STAND[0] as Vector2).y), (STAND[0] as Vector2).y))
	var wp := _woodpile(root, _xf2(WOODPILE[0], WOODPILE[1]))
	# the collapsed shed (back wall to the east, away from the trail)
	var shed_xf := _xf2(SHED[0], SHED[1])
	var shed := ExteriorProps.collapsed_shed(root, _m, shed_xf, 81, cols)
	_wall_cols(shed, cols)
	_spot("shed", shed_xf.origin)
	ExteriorProps.mi(root, _tyre(), shed_xf * Vector3(-1.9, 0.05, 1.6), Vector3(PI * 0.5 - 0.2, 0.4, 0))
	# the uprooted spruce and the hollow log
	var rp_xf := _xf2(ROOTPLATE[0], ROOTPLATE[1], -0.2)
	var rp := ExteriorProps.root_plate(root, _m, rp_xf, 91, cols)
	_wall_cols(rp, cols)
	_spot("root_plate", rp_xf.origin)
	var hl_xf := _xf2(HOLLOW[0], HOLLOW[1], -0.1)
	var hl := ExteriorProps.hollow_log(root, _m, hl_xf, 93, cols)
	_wall_cols(hl, cols)
	# the abandoned car, sunk on its rims, nose to the old track
	var wr_xf := _xf2(WRECK[0], WRECK[1], -0.06)
	var wr := ExteriorProps.car(root, _m, wr_xf, _m.rust, true, 17, cols)
	_wall_cols(wr, cols)
	_spot("wreck", wr_xf.origin)
	# boulders by the stream path
	for bd: Array in BOULDERS:
		var p: Vector2 = bd[0]
		var r: float = bd[1]
		var rk := ExteriorProps.mi(root, ExteriorProps.rock(700 + int(r * 10), _m, 3), Vector3(p.x, height_at(p.x, p.y) - r * 0.25, p.y), Vector3(0, _rng.randf() * TAU, 0))
		rk.scale = Vector3.ONE * r
		_wall(Vector3(r * 1.7, r * 1.3, r * 1.7), Transform3D(Basis(Vector3.UP, rk.rotation.y), rk.position + Vector3(0, r * 0.4, 0)))
	# a hazel thicket to crouch in (hide 1)
	for i in THICKET_1.size():
		var tp: Vector2 = THICKET_1[i]
		var th := ExteriorProps.mi(root, ExteriorProps.thicket(800 + i, _m, 2.2), Vector3(tp.x, height_at(tp.x, tp.y) - 0.05, tp.y), Vector3(0, _rng.randf() * TAU, 0), false)
		th.scale = Vector3.ONE * _rng.randf_range(0.9, 1.15)
	# young spruces packed tight (hide 6), courtyard trees
	for k in 11:
		var a := TAU * k / 11.0 + _rng.randf_range(-0.2, 0.2)
		var rr := 1.0 + _rng.randf_range(0.0, 2.2)
		if k < 3:
			rr = _rng.randf_range(0.0, 0.7)
		_forced_trees.append(["sapling", k % 2, SAPLING_6 + Vector2(cos(a), sin(a)) * rr, _rng.randf() * TAU, _rng.randf_range(0.9, 1.3), false])
	for ct: Array in [["oak", 0, Vector2(-20, -15)], ["oak", 1, Vector2(-14, 19)], ["birch", 0, Vector2(19, -14)], ["oak", 0, Vector2(21, 13)],
			["birch", 1, Vector2(-25, -6)], ["oak", 1, Vector2(4, 19.5)], ["birch", 1, Vector2(-5, -16)], ["birch", 0, Vector2(14, -19)],
			["oak", 0, Vector2(-28, 22)], ["oak", 1, Vector2(26.5, 21)]]:
		_forced_trees.append([ct[0], ct[1], ct[2], _rng.randf() * TAU, _rng.randf_range(0.8, 0.95), true])
	# signs: forest-fire board at the edge of the trees, a danger board by the stream
	_wall_cols(ExteriorProps.fire_sign(root, _m, _xf2(Vector2(51.5, 22.8), -PI * 0.5), cols), cols)
	var dz := ExteriorProps.fire_sign(root, _m, _xf2(Vector2(111.4, -1.0), PI * 0.8), cols)
	_wall_cols(dz, cols)
	for ch: Node in dz.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).material_override == _m.sign:
			ch.queue_free()
	ExteriorProps.sign_quad(dz, _m, "danger", Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0.017)), 1.0)
	# fallen trees closing two dead ends
	for fl: Array in [[Vector2(100.6, 58.2), 0.15, 8.0], [Vector2(176.0, 52.6), 1.2, 9.0], [Vector2(80.6, -16.6), 0.3, 7.5]]:
		var p2: Vector2 = fl[0]
		var lg := ExteriorProps.mi(root, ExteriorProps.log_mesh(900 + int(p2.x), _m, fl[2], 0.34, "bark_spruce"), Vector3(p2.x, height_at(p2.x, p2.y) - 0.12, p2.y), Vector3(0, fl[1], 0))
		_wall(Vector3(float(fl[2]), 0.8, 0.8), Transform3D(Basis(Vector3.UP, float(fl[1])), lg.position + Vector3(0, 0.35, 0)))
	_stream(root)
	# hiding places: where you stand (hide_k), where you step in from
	# (hide_k_front); E works only while set_hides_active(true)
	var hl_in := hl_xf * Vector3(1.6, 0.12, 0.0)
	var hides := [
		[Vector3(63.6, 0, 28.6), Vector3(64.1, 0, 25.5)],
		[shed_xf * Vector3(0.2, 0, -2.0), shed_xf * Vector3(1.9, 0, -2.6)],
		[Vector3(95.2, 0, 49.6), Vector3(96.3, 0, 46.7)],
		[hl_in, hl_xf * Vector3(3.9, 0, 0)],
		[wr_xf * Vector3(0.2, 0, 1.6), wr_xf * Vector3(-1.2, 0, 2.7)],
		[Vector3(SAPLING_6.x, 0, SAPLING_6.y), Vector3(150.7, 0, 91.3)],
		[wp * Vector3(0.0, 0, -1.0), wp * Vector3(2.0, 0, -1.3)],
	]
	for k in hides.size():
		var hin: Vector3 = hides[k][0]
		var hfr: Vector3 = hides[k][1]
		if k != 3:
			hin.y = height_at(hin.x, hin.z)
		hfr.y = height_at(hfr.x, hfr.z)
		var nm := "hide_%d" % (k + 1)
		_spot(nm, hin, _yaw_toward(hin, hfr))
		_spot(nm + "_front", hfr, _yaw_toward(hfr, hin))
		_interact(nm, "ACT_HIDE", Transform3D(Basis.IDENTITY, hin + Vector3(0, 0.9, 0)), Vector3(1.6, 1.8, 1.6), false)
		_hide_list.append(nm)


## Firewood stacked between posts, 2.4 m long, 1.7 high (along x, centred).
func _woodpile(root: Node3D, xf: Transform3D) -> Transform3D:
	var n := Node3D.new()
	n.name = "Woodpile"
	n.transform = xf
	root.add_child(n)
	var b := ExteriorProps.MBuf.new()
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var y := 0.12
	while y < 1.6:
		var x := -1.1
		while x < 1.1:
			var rr := r.randf_range(0.07, 0.11)
			var z0 := -0.26 + r.randf_range(-0.04, 0.04)
			b.tube(PackedVector3Array([Vector3(x + rr, y + rr, z0), Vector3(x + rr + r.randf_range(-0.02, 0.02), y + rr, z0 + 0.52)]), ExteriorProps.taper(2, rr, rr), 7,
					1.0, 0.1, r.randf() * TAU, 0.0, 0.0, 0.0, 0.0, true, true)
			x += rr * 2.0 + 0.005
		y += 0.19
	for sx: float in [-1.25, 1.25]:
		b.tube(PackedVector3Array([Vector3(sx, -0.2, 0), Vector3(sx, 1.85, 0)]), ExteriorProps.taper(2, 0.06, 0.05), 6)
	ExteriorProps.mi(n, b.to_mesh(_m.bark_oak, true))
	ExteriorProps.rbox(n, Vector3(2.8, 0.02, 0.9), Vector3(0, 1.75, 0), _m.corrugated, 0.005, Vector3(0.1, 0, 0))
	_wall(Vector3(2.6, 1.7, 0.6), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)))
	return xf


func _tyre() -> Mesh:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.34
	tm.rings = 24
	tm.ring_segments = 10
	tm.material = _m.rubber
	return tm


## The water of the stream, following its bed.
func _stream(root: Node3D) -> void:
	var b := ExteriorProps.MBuf.new()
	var z := Z0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var first := true
	while z <= Z1:
		var sx := stream_x(z)
		var bed := minf(minf(_hraw(sx, z), _hraw(sx - 0.6, z)), _hraw(sx + 0.6, z))
		var y := bed + 0.24
		var l := Vector3(sx - 1.7, y, z)
		var r := Vector3(sx + 1.7, y, z)
		if not first:
			ExteriorProps.fquad(b, prev_l, prev_r, r, l, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		prev_l = l
		prev_r = r
		first = false
		z += 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Stream"
	mi.mesh = b.to_mesh(_m.water)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ---------------------------------------------------------------------------
# the forest: trees in chunked MultiMeshes (near and far meshes), trunk
# colliders, blocked cells for path()
# ---------------------------------------------------------------------------
const SPECIES := [["spruce", 3, 0.42], ["pine", 2, 0.24], ["oak", 2, 0.14], ["birch", 2, 0.14], ["snag", 1, 0.06], ["sapling", 2, 0.0]]
var _tree := {}
var _inst := {}
var _far_mmis: Array = []
var _far_range := 115.0


func _forest() -> void:
	var seed_k := 0
	for sp: Array in SPECIES:
		for v in int(sp[1]):
			seed_k += 1
			var near := ExteriorProps.tree(sp[0], 3000 + seed_k * 31, 0, _m)
			var far := ExteriorProps.tree(sp[0], 3000 + seed_k * 31, 1, _m)
			_tree["%s_%d" % [sp[0], v]] = {"near": near.mesh, "far": far.mesh, "h": near.h, "r1": near.r1}
	var step := 3.4
	var x := X0 + 2.0
	var count := 0
	while x < X1 - 2.0:
		var z := Z0 + 2.0
		while z < Z1 - 2.0:
			var p := Vector2(x + _rng.randf_range(-1.65, 1.65), z + _rng.randf_range(-1.65, 1.65))
			z += step
			if _noise_b.get_noise_2d(p.x * 0.55 + 300.0, p.y * 0.55) < -0.42:
				continue
			# density: dense stands, thin patches, the odd twin stem
			var dens := _noise_a.get_noise_2d(p.x * 2.2 - 40.0, p.y * 2.2 + 90.0)
			if dens < -0.15 and _rng.randf() < 0.55:
				continue
			var cands: Array[Vector2] = [p]
			if dens > 0.2 and _rng.randf() < 0.75:
				cands.append(p + Vector2(_rng.randf_range(-1.7, 1.7), _rng.randf_range(-1.7, 1.7)))
			for q0: Vector2 in cands:
				if not _tree_ok(q0, 1.8) or _solid_at_r(q0, 0.9):
					continue
				var kind := _pick_species(q0)
				var v := _rng.randi_range(0, _variants(kind) - 1)
				var s := _rng.randf_range(0.78, 1.22) * (1.08 if absf(q0.x) > 60.0 or absf(q0.y) > 60.0 else 0.95)
				_place_tree(kind, v, q0, _rng.randf() * TAU, s, true)
				count += 1
				if kind != "snag" and _rng.randf() < 0.05:
					var tw := q0 + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(0.75, 1.2)
					if _tree_ok(tw, 1.8):
						_place_tree(kind, (v + 1) % _variants(kind), tw, _rng.randf() * TAU, s * _rng.randf_range(0.75, 0.9), true)
						count += 1
			if _rng.randf() < 0.06:
				for k in _rng.randi_range(3, 6):
					var q := p + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
					if _tree_ok(q, 0.4):
						_place_tree("sapling", _rng.randi_range(0, 1), q, _rng.randf() * TAU, _rng.randf_range(0.7, 1.5), false)
		x += step
	for ft: Array in _forced_trees:
		_place_tree(ft[0], ft[1], ft[2], ft[3], ft[4], ft[5])
	_build_tree_mmis()
	if OS.get_cmdline_user_args().has("--trace"):
		print("[ext] trees ", count)


func _variants(kind: String) -> int:
	for sp: Array in SPECIES:
		if sp[0] == kind:
			return int(sp[1])
	return 1


func _pick_species(p: Vector2) -> String:
	var wet := 1.0 - smoothstep(3.0, 26.0, absf(p.x - stream_x(p.y)))
	var nz := _noise_a.get_noise_2d(p.x * 1.7 + 77.0, p.y * 1.7)
	var near_estate := 1.0 - smoothstep(10.0, 45.0, maxf(maxf(ESTATE.position.x - p.x, p.x - ESTATE.end.x), maxf(ESTATE.position.y - p.y, p.y - ESTATE.end.y)))
	var w := {"spruce": 0.42 + wet * 0.35 + nz * 0.25, "pine": 0.24 - nz * 0.2 - wet * 0.1, "oak": 0.14 + near_estate * 0.12,
		"birch": 0.13 + near_estate * 0.1 + maxf(-nz, 0.0) * 0.1, "snag": 0.06}
	var total := 0.0
	for k: String in w:
		w[k] = maxf(float(w[k]), 0.01)
		total += float(w[k])
	var r := _rng.randf() * total
	for k: String in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "spruce"


func _tree_ok(p: Vector2, trail_clear: float) -> bool:
	if p.x < X0 + 1.0 or p.x > X1 - 1.0 or p.y < Z0 + 1.0 or p.y > Z1 - 1.0:
		return false
	if ESTATE.grow(-3.0).has_point(p):
		return false
	if _in_block(p.x, p.y, 4.0):
		return false
	if absf(p.x - ROAD_X) < ROAD_HW + 2.6:
		return false
	if absf(p.x - stream_x(p.y)) < 1.9:
		return false
	if _pdist_at(p.x, p.y) < trail_clear:
		return false
	if _in_rects(p.x, p.y, 2.5):
		return false
	for e: Array in _excl:
		if p.distance_to(e[0]) < float(e[1]):
			return false
	return true


func _place_tree(kind: String, v: int, p: Vector2, yaw: float, s: float, collide: bool) -> void:
	var key := "%s_%d" % [kind, v]
	var info: Dictionary = _tree[key]
	var y := height_at(p.x, p.y) - 0.06
	var tilt := Basis(Vector3(cos(yaw), 0, sin(yaw)), _rng.randf_range(-0.035, 0.035))
	var xf := Transform3D(tilt * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))
	var cx := clampi(int((p.x - X0) / CHUNK), 0, 99)
	var cz := clampi(int((p.y - Z0) / CHUNK), 0, 99)
	var ck := "%s|%d|%d" % [key, cx, cz]
	if not _inst.has(ck):
		_inst[ck] = []
	var dark := _rng.randf_range(0.0, 0.35)
	var yel := _rng.randf_range(0.0, 0.5) if kind == "birch" or kind == "oak" else 0.0
	_inst[ck].append([xf, Color(yel, dark, _rng.randf(), _rng.randf_range(0.0, 0.4))])
	if collide:
		var r := float(info.r1) * s
		_cyl_col(r * 0.92, 3.6, Vector3(p.x, y, p.y))
		_solid_disc(p, r + 0.3)


func _build_tree_mmis() -> void:
	var root := Node3D.new()
	root.name = "Forest"
	add_child(root)
	_far = Node3D.new()
	_far.name = "FarTrees"
	add_child(_far)
	for ck: String in _inst:
		var parts := ck.split("|")
		var info: Dictionary = _tree[parts[0]]
		var cx := int(parts[1])
		var cz := int(parts[2])
		var centre := Vector3(X0 + (cx + 0.5) * CHUNK, 0.0, Z0 + (cz + 0.5) * CHUNK)
		var list: Array = _inst[ck]
		var local: Array = []
		for it: Array in list:
			var xf: Transform3D = it[0]
			local.append([Transform3D(xf.basis, xf.origin - centre), it[1]])
		var small := parts[0].begins_with("sapling") or parts[0].begins_with("snag")
		var near := _mm(root, info.near, local, true, false, not parts[0].begins_with("sapling"))
		near.position = centre
		near.visibility_range_end = 68.0 if small else 52.0
		near.visibility_range_end_margin = 4.0
		near.extra_cull_margin = 3.0
		if small:
			continue
		var far := _mm(_far, info.far, local, true, false, false)
		far.position = centre
		far.visibility_range_begin = 48.0
		far.visibility_range_begin_margin = 4.0
		far.visibility_range_end = _far_range
		far.extra_cull_margin = 3.0
		_far_mmis.append(far)
	_inst.clear()


# ---------------------------------------------------------------------------
# undergrowth, rocks, deadwood (chunked MultiMeshes)
# ---------------------------------------------------------------------------
func _undergrowth() -> void:
	var root := Node3D.new()
	root.name = "Undergrowth"
	add_child(root)
	var kinds := {
		"fern": [ExteriorProps.fern(11, _m), ExteriorProps.fern(12, _m)],
		"bush": [ExteriorProps.bush(21, _m, 0.75), ExteriorProps.bush(23, _m, 1.05)],
		"grass": [ExteriorProps.grass(31, _m, 0.42), ExteriorProps.grass(32, _m, 0.55)],
		"rock": [ExteriorProps.rock(41, _m, 2), ExteriorProps.rock(42, _m, 2), ExteriorProps.rock(43, _m, 2)],
		"stump": [ExteriorProps.stump(51, _m), ExteriorProps.stump(52, _m)],
		"log": [ExteriorProps.log_mesh(61, _m, 5.0, 0.26), ExteriorProps.log_mesh(62, _m, 7.0, 0.32, "bark_oak"), ExteriorProps.log_mesh(63, _m, 4.0, 0.22, "bark_birch")],
		"stick": [ExteriorProps.stick(71, _m), ExteriorProps.stick(72, _m)],
	}
	var vis := {"fern": 44.0, "bush": 52.0, "grass": 34.0, "rock": 80.0, "stump": 70.0, "log": 85.0, "stick": 30.0}
	var buckets := {}
	var area := WALK.grow(14.0)
	# ferns, bushes, grass, sticks, small rocks on a jittered grid
	for spec: Array in [["fern", 2.4], ["bush", 2.8], ["grass", 2.3], ["stick", 3.2], ["rock", 7.5], ["stump", 15.0], ["log", 17.0]]:
		var kind: String = spec[0]
		var step: float = spec[1]
		var x := area.position.x
		while x < area.end.x:
			var z := area.position.y
			while z < area.end.y:
				var p := Vector2(x + _rng.randf_range(-step * 0.45, step * 0.45), z + _rng.randf_range(-step * 0.45, step * 0.45))
				z += step
				_maybe_scatter(kind, p, buckets)
			x += step
	# lawn grass in the courtyard
	var gx := COURT.position.x + 0.5
	while gx < COURT.end.x:
		var gz := COURT.position.y + 0.5
		while gz < COURT.end.y:
			var p2 := Vector2(gx + _rng.randf_range(-0.7, 0.7), gz + _rng.randf_range(-0.7, 0.7))
			gz += 1.7
			if _in_rects(p2.x, p2.y, 0.25) or _in_block(p2.x, p2.y, 0.6) or _entrance_near(p2, 0.5) or _solid_at(p2):
				continue
			if _rng.randf() < 0.55:
				_bucket(buckets, "grass", _rng.randi_range(0, 1), p2, _rng.randf_range(0.7, 1.2), Color(_rng.randf_range(0.0, 0.4), _rng.randf_range(0.0, 0.3), _rng.randf(), 0))
		gx += 1.7
	# stones in the stream bed
	var sz := Z0 + 1.0
	while sz < Z1:
		var sxp := stream_x(sz) + _rng.randf_range(-1.1, 1.1)
		if _rng.randf() < 0.7:
			_bucket(buckets, "rock", _rng.randi_range(0, 2), Vector2(sxp, sz), _rng.randf_range(0.15, 0.4), Color(0, 0, 0, 0), -0.05)
		sz += 1.3
	for bk: String in buckets:
		var parts := bk.split("|")
		var kind2 := parts[0]
		var v := int(parts[1])
		var centre := Vector3(X0 + (int(parts[2]) + 0.5) * CHUNK, 0.0, Z0 + (int(parts[3]) + 0.5) * CHUNK)
		var local: Array = []
		for it: Array in buckets[bk]:
			var xf: Transform3D = it[0]
			local.append([Transform3D(xf.basis, xf.origin - centre), it[1]])
		var custom := kind2 in ["fern", "bush", "grass"]
		var mmi := _mm(root, kinds[kind2][v], local, custom, false, kind2 in ["rock", "stump", "log"])
		mmi.position = centre
		mmi.visibility_range_end = vis[kind2] + CHUNK * 0.7
		mmi.extra_cull_margin = 1.0


func _maybe_scatter(kind: String, p: Vector2, buckets: Dictionary) -> void:
	if p.x < X0 + 1.0 or p.x > X1 - 1.0 or p.y < Z0 + 1.0 or p.y > Z1 - 1.0:
		return
	if ESTATE.grow(-4.0).has_point(p) or _in_block(p.x, p.y, 1.0) or _in_rects(p.x, p.y, 0.4):
		return
	if absf(p.x - ROAD_X) < ROAD_HW + 0.6:
		return
	var pd := _pdist_at(p.x, p.y)
	var ds := absf(p.x - stream_x(p.y))
	var damp := clampf(_noise_b.get_noise_2d(p.x * 0.7 + 50.0, p.y * 0.7) * 1.4 + 0.15, 0.0, 1.0)
	var edge := 1.0 - smoothstep(0.3, 3.0, pd)
	for e: Array in _excl:
		if p.distance_to(e[0]) < float(e[1]) * (0.8 if kind in ["fern", "grass", "stick"] else 1.0):
			return
	var s := 1.0
	var c := Color(_rng.randf_range(0.0, 0.3), _rng.randf_range(0.0, 0.35), _rng.randf(), _rng.randf_range(0.0, 0.3))
	match kind:
		"fern":
			if pd < 0.25 or ds < 1.2:
				return
			if _rng.randf() > 0.12 + damp * 0.55 + edge * 0.3 + (0.35 if ds < 6.0 else 0.0):
				return
			s = _rng.randf_range(0.7, 1.35)
			c.r = _rng.randf_range(0.0, 0.7) * (1.0 - damp)
		"bush":
			if pd < 0.3 or ds < 1.5:
				return
			if _rng.randf() > 0.3 + edge * 0.35:
				return
			s = _rng.randf_range(0.7, 1.3)
		"grass":
			if pd < 0.0 and _rng.randf() < 0.85:
				return
			var open := 0.15 + edge * 0.35 + (0.5 if absf(p.x - ROAD_X) < ROAD_HW + 3.0 else 0.0)
			if _rng.randf() > open:
				return
			s = _rng.randf_range(0.7, 1.3)
		"stick":
			if _rng.randf() > 0.55:
				return
			s = _rng.randf_range(0.8, 1.2)
		"rock":
			if ds < 1.0 or _rng.randf() > 0.5:
				return
			s = _rng.randf_range(0.18, 0.55)
			if pd < 1.6 or ESTATE.grow(2.0).has_point(p):
				s = minf(s, 0.26)
		"stump":
			if pd < 1.5 or ds < 2.5 or _rng.randf() > 0.45 or not _tree_ok(p, 1.5):
				return
			s = _rng.randf_range(0.8, 1.2)
			_cyl_col(0.36 * s, 1.0, Vector3(p.x, height_at(p.x, p.y), p.y))
			_solid_disc(p, 0.36 * s + 0.3)
		"log":
			if pd < 3.0 or ds < 3.0 or _rng.randf() > 0.42 or not _tree_ok(p, 3.0):
				return
			var v := _rng.randi_range(0, 2)
			var yaw := _rng.randf() * TAU
			var length: float = [5.0, 7.0, 4.0][v]
			var rr: float = [0.26, 0.32, 0.22][v]
			var y := height_at(p.x, p.y) - rr * 0.35
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y))
			_wall(Vector3(length, rr * 2.0, rr * 2.0), xf * Transform3D(Basis.IDENTITY, Vector3(0, rr, 0)))
			_bucket_xf(buckets, "log", v, p, xf, Color(0, _rng.randf_range(0.0, 0.3), 0, 0))
			return
	var vv := _rng.randi_range(0, 2 if kind == "rock" else 1)
	_bucket(buckets, kind, vv, p, s, c)
	if kind == "rock" and s > 0.42:
		_wall(Vector3(s * 1.6, s * 1.0, s * 1.6), Transform3D(Basis.IDENTITY, Vector3(p.x, height_at(p.x, p.y) + s * 0.25, p.y)))


func _bucket(buckets: Dictionary, kind: String, v: int, p: Vector2, s: float, c: Color, lift := 0.0) -> void:
	var y := height_at(p.x, p.y) + lift - (0.04 if kind in ["fern", "bush", "grass"] else 0.0)
	if kind == "rock":
		y -= s * 0.22
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))
	_bucket_xf(buckets, kind, v, p, xf, c)


func _bucket_xf(buckets: Dictionary, kind: String, v: int, p: Vector2, xf: Transform3D, c: Color) -> void:
	var key := "%s|%d|%d|%d" % [kind, v, clampi(int((p.x - X0) / CHUNK), 0, 99), clampi(int((p.y - Z0) / CHUNK), 0, 99)]
	if not buckets.has(key):
		buckets[key] = []
	buckets[key].append([xf, c])


## Any blocked cell within r of p (keeps trunks from growing into each other).
func _solid_at_r(p: Vector2, r: float) -> bool:
	for off: Vector2 in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if _solid_at(p + off):
			return true
	return false


func _solid_at(p: Vector2) -> bool:
	var i := int((p.x - X0) / CELL)
	var j := int((p.y - Z0) / CELL)
	if i < 0 or j < 0 or i >= _gw or j >= _gd:
		return true
	return _solid[j * _gw + i] != 0


# ---------------------------------------------------------------------------
# the road out: asphalt over the low hills, verges, markings, barriers, the
# one street light (sodium) where the trail comes out, a bus stop
# ---------------------------------------------------------------------------
func _road() -> void:
	var root := Node3D.new()
	root.name = "Road"
	add_child(root)
	var asp := ExteriorProps.MBuf.new()
	var grav := ExteriorProps.MBuf.new()
	var paint := ExteriorProps.MBuf.new()
	var z := Z0
	while z < Z1 - 0.01:
		var z1 := minf(z + 2.0, Z1)
		_ground_strip(asp, Rect2(ROAD_X - ROAD_HW, z, ROAD_HW * 2.0, z1 - z), 7.0, 0.03)
		_ground_strip(grav, Rect2(ROAD_X - ROAD_HW - 1.3, z, 1.3, z1 - z), 1.3, 0.02)
		_ground_strip(grav, Rect2(ROAD_X + ROAD_HW, z, 1.3, z1 - z), 1.3, 0.02)
		for ex: float in [ROAD_X - ROAD_HW + 0.25, ROAD_X + ROAD_HW - 0.25]:
			_ground_strip(paint, Rect2(ex - 0.06, z, 0.12, z1 - z), 2.0, 0.04)
		if fmod(z - Z0, 6.0) < 0.5:
			_ground_strip(paint, Rect2(ROAD_X - 0.06, z, 0.12, 2.0), 2.0, 0.04)
		z = z1
	var mesh := asp.to_mesh(_m.road, true)
	grav.commit(mesh, _m.gravel, true)
	var pm := _m.paint_line.duplicate() as StandardMaterial3D
	paint.commit(mesh, pm)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var cols: Array = []
	# crash barriers, broken where the trail comes out of the trees
	for seg: Array in [[ROAD_X - ROAD_HW - 1.0, WALK.position.y - 4.0, 94.0], [ROAD_X - ROAD_HW - 1.0, 101.0, WALK.end.y + 4.0], [ROAD_X + ROAD_HW + 1.0, WALK.position.y - 4.0, WALK.end.y + 4.0]]:
		var bz: float = seg[1]
		while bz < float(seg[2]) - 0.5:
			var bl := minf(10.0, float(seg[2]) - bz)
			var bx: float = seg[0]
			var cb := ExteriorProps.crash_barrier(root, _m, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(bx, _hraw(bx, bz + bl * 0.5), bz)), bl, cols)
			_wall_cols(cb, cols)
			bz += bl
	var ly := _hraw(ROAD_X + ROAD_HW + 1.6, 98.0)
	var lamp := ExteriorProps.street_lamp(_lights, _m, Transform3D(Basis(Vector3.UP, PI), Vector3(ROAD_X + ROAD_HW + 1.6, ly, 98.0)), "sodium", 7.2, cols)
	_wall_cols(lamp.node, cols)
	(lamp.light as SpotLight3D).shadow_enabled = true
	(lamp.light as SpotLight3D).light_energy = 8.5
	_add_lamp(lamp.light, [lamp.glass], lamp.halo, "steady", 8.0, lamp.node.get_child(lamp.node.get_child_count() - 1) as Node3D)
	var bs := ExteriorProps.bus_stop(root, _m, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(ROAD_X + ROAD_HW + 1.5, _hraw(ROAD_X + ROAD_HW + 1.5, 104.5), 104.5)), cols)
	_wall_cols(bs, cols)
	var ex := Vector3(ROAD_X - 0.8, 0, 98.0)
	ex.y = height_at(ex.x, ex.z) + 0.03
	_spot("forest_exit", ex, -PI * 0.5)


# ---------------------------------------------------------------------------
# A* over the whole area
# ---------------------------------------------------------------------------
func _nav() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, _gw, _gd)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.offset = Vector2(X0 + CELL * 0.5, Z0 + CELL * 0.5)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.jumping_enabled = false
	_astar.update()
	var wi0 := int((WALK.position.x - X0) / CELL)
	var wi1 := int((WALK.end.x - X0) / CELL)
	var wj0 := int((WALK.position.y - Z0) / CELL)
	var wj1 := int((WALK.end.y - Z0) / CELL)
	for j in _gd:
		for i in _gw:
			if i < wi0 or i >= wi1 or j < wj0 or j >= wj1:
				_solid[j * _gw + i] = 1
	_seal_pockets()
	_astar.fill_solid_region(Rect2i(0, 0, wi0, _gd))
	_astar.fill_solid_region(Rect2i(wi1, 0, _gw - wi1, _gd))
	_astar.fill_solid_region(Rect2i(0, 0, _gw, wj0))
	_astar.fill_solid_region(Rect2i(0, wj1, _gw, _gd - wj1))
	for j in range(wj0, wj1):
		for i in range(wi0, wi1):
			if _solid[j * _gw + i] != 0:
				_astar.set_point_solid(Vector2i(i, j))
	# the cells of the railing gap (closed for searches that stay outside)
	for j in range(int((GAP_C.y - 1.6 - Z0) / CELL), int((GAP_C.y + 1.6 - Z0) / CELL) + 1):
		for i in range(int((GAP_C.x - 0.7 - X0) / CELL), int((GAP_C.x + 0.7 - X0) / CELL) + 1):
			if _solid[j * _gw + i] == 0:
				_gap_cells.append(Vector2i(i, j))
	# invisible walls round where you may go (the forest goes on beyond them)
	var h := 30.0
	for wall: Array in [[Vector3(WALK.size.x, h, 1.0), Vector3(WALK.get_center().x, 0, WALK.position.y)], [Vector3(WALK.size.x, h, 1.0), Vector3(WALK.get_center().x, 0, WALK.end.y)],
			[Vector3(1.0, h, WALK.size.y), Vector3(WALK.position.x, 0, WALK.get_center().y)], [Vector3(1.0, h, WALK.size.y), Vector3(WALK.end.x, 0, WALK.get_center().y)]]:
		_box_col(wall[0], Transform3D(Basis.IDENTITY, wall[1]))


## Free cells that cannot be reached from the courtyard (gaps between close
## trunks and rocks) are sealed, so path() never searches the whole map for a
## goal it cannot reach; such a goal snaps to the nearest reachable cell.
func _seal_pockets() -> void:
	var n := _gw * _gd
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var queue := PackedInt32Array()
	queue.resize(n)
	var start := _cell(Vector3(0.0, 0.0, 0.5))
	var s0 := start.y * _gw + start.x
	if _solid[s0] != 0:
		return
	var head := 0
	var tail := 0
	queue[tail] = s0
	tail += 1
	seen[s0] = 1
	var w := _gw
	while head < tail:
		var c := queue[head]
		head += 1
		var ci := c % w
		if ci > 0 and seen[c - 1] == 0 and _solid[c - 1] == 0:
			seen[c - 1] = 1
			queue[tail] = c - 1
			tail += 1
		if ci < w - 1 and seen[c + 1] == 0 and _solid[c + 1] == 0:
			seen[c + 1] = 1
			queue[tail] = c + 1
			tail += 1
		if c >= w and seen[c - w] == 0 and _solid[c - w] == 0:
			seen[c - w] = 1
			queue[tail] = c - w
			tail += 1
		if c < n - w and seen[c + w] == 0 and _solid[c + w] == 0:
			seen[c + w] = 1
			queue[tail] = c + w
			tail += 1
	var sealed := 0
	for c in n:
		if _solid[c] == 0 and seen[c] == 0:
			_solid[c] = 1
			sealed += 1
	if OS.get_cmdline_user_args().has("--trace"):
		print("[ext] sealed %d unreachable cells, %d reachable" % [sealed, tail])


func _cell(lp: Vector3) -> Vector2i:
	return Vector2i(int(floor((lp.x - X0) / CELL)), int(floor((lp.z - Z0) / CELL)))


func _cell_free(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _gw and c.y < _gd and _solid[c.y * _gw + c.x] == 0


func _free_near(c: Vector2i) -> Vector2i:
	if _cell_free(c):
		return c
	for r in range(1, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if _cell_free(q):
					return q
	return Vector2i(-1, -1)


func _cell_centre(c: Vector2i) -> Vector2:
	return Vector2(X0 + (c.x + 0.5) * CELL, Z0 + (c.y + 0.5) * CELL)


## Straight walk over free cells between two local points.
func _los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(ceil(d.length() / (CELL * 0.5)))
	for k in range(1, n):
		var p := a + d * (float(k) / n)
		var i := int((p.x - X0) / CELL)
		var j := int((p.y - Z0) / CELL)
		if i < 0 or j < 0 or i >= _gw or j >= _gd or _solid[j * _gw + i] != 0:
			return false
	return true


## A walkable route between two global points: A* over 0.5 m cells (trees,
## rocks, logs, buildings, fences blocked), pulled straight where the way is
## clear, a point at least every metre, y on the ground (height_at). Empty if
## no route. Endpoints inside an obstacle are moved to the nearest free cell.
## The courtyard is walled in by blocks and railings with one gap: routes
## between inside and outside go through the gap, and routes that stay outside
## never search the courtyard.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _astar == null:
		return out
	var la := to_local(from)
	var lb := to_local(to)
	var a2 := Vector2(la.x, la.z)
	var b2 := Vector2(lb.x, lb.z)
	# classify by where each end really stands (an end inside a wall or a
	# trunk snaps to the nearest reachable cell first)
	var ca := _free_near(_cell(la))
	var cb := _free_near(_cell(lb))
	if ca.x < 0 or cb.x < 0:
		return out
	if not _cell_free(_cell(la)):
		a2 = _cell_centre(ca)
	if not _cell_free(_cell(lb)):
		b2 = _cell_centre(cb)
	var ina := _inside(a2)
	var inb := _inside(b2)
	var pts: Array[Vector2] = []
	if ina != inb:
		var p1 := _route(a2, GAP_C)
		var p2 := _route(GAP_C, b2)
		if p1.is_empty() or p2.is_empty():
			return out
		pts = p1
		pts.append_array(p2.slice(1))
	elif not ina:
		for c: Vector2i in _gap_cells:
			_astar.set_point_solid(c, true)
		pts = _route(a2, b2)
		for c: Vector2i in _gap_cells:
			_astar.set_point_solid(c, false)
	else:
		pts = _route(a2, b2)
	if pts.is_empty():
		return out
	# string-pull: from each point jump to the farthest one in plain view
	var sm: Array[Vector2] = [pts[0]]
	var i := 0
	var n := pts.size()
	while i < n - 1:
		var step := mini(48, n - 1 - i)
		var j := i + 1
		while step >= 1:
			var cand := i + step
			if cand > j and _los(pts[i], pts[cand]):
				j = cand
				break
			step /= 2
		sm.append(pts[j])
		i = j
	for k in sm.size() - 1:
		var p0 := sm[k]
		var p1 := sm[k + 1]
		var ns := maxi(1, int(ceil(p0.distance_to(p1) / 1.0)))
		for s in ns:
			var p := p0.lerp(p1, float(s) / ns)
			out.append(to_global(Vector3(p.x, height_at(p.x, p.y), p.y)))
	var last := sm[sm.size() - 1]
	out.append(to_global(Vector3(last.x, height_at(last.x, last.y), last.y)))
	return out


## Cell-centre route between two local points (endpoints kept when free).
func _route(a: Vector2, b: Vector2) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var ca := _free_near(_cell(Vector3(a.x, 0, a.y)))
	var cb := _free_near(_cell(Vector3(b.x, 0, b.y)))
	if ca.x < 0 or cb.x < 0:
		return pts
	var ids := _astar.get_id_path(ca, cb, true)
	if ids.is_empty():
		return pts
	for id: Vector2i in ids:
		pts.append(_cell_centre(id))
	if _cell_free(_cell(Vector3(a.x, 0, a.y))):
		pts[0] = a
	if ids[ids.size() - 1] == cb and _cell_free(_cell(Vector3(b.x, 0, b.y))):
		pts[pts.size() - 1] = b
	return pts


## Inside the ring of blocks and railings.
func _inside(p: Vector2) -> bool:
	for r: Rect2 in ENCLOSURE:
		if r.has_point(p):
			return not _in_block(p.x, p.y, 0.0)
	return false


# ---------------------------------------------------------------------------
# environment: night sky, moon, fog and mist, sound
# ---------------------------------------------------------------------------
const MOON_DIR := Vector3(0.6, 0.5, 0.62)


func _environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/night_sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.042, 0.064, 0.078)
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.75
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 0.4)
	env.set_glow_level(2, 0.7)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.05, 0.078, 0.088)
	env.fog_light_energy = 1.0
	env.fog_density = 0.009
	env.fog_sky_affect = 0.3
	env.fog_height = 3.5
	env.fog_height_density = 0.05
	env.fog_sun_scatter = 0.12
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.44, 0.57, 0.6)
	env.volumetric_fog_emission = Color(0.004, 0.0065, 0.0075)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.38
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.14
	env.volumetric_fog_sky_affect = 0.2
	env.volumetric_fog_temporal_reprojection_enabled = not _capture
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	_attr = CameraAttributesPractical.new()
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.66, 0.8, 0.96)
	_moon.light_energy = 0.62
	_moon.light_angular_distance = 0.6
	_moon.shadow_enabled = true
	_moon.shadow_blur = 1.5
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_moon.directional_shadow_max_distance = 60.0
	_moon.directional_shadow_blend_splits = true
	_moon.light_volumetric_fog_energy = 0.6
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_lights.add_child(_moon)
	_moon.basis = Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
	_mist_volumes()
	var court := _loop_stream("amb_courtyard.ogg")
	var forest := _loop_stream("amb_forest.ogg")
	if court:
		_amb_court = AudioStreamPlayer.new()
		_amb_court.stream = court
		_amb_court.bus = "Ambience"
		_amb_court.volume_db = -80.0
		add_child(_amb_court)
	if forest:
		_amb_forest = AudioStreamPlayer.new()
		_amb_forest.stream = forest
		_amb_forest.bus = "Ambience"
		_amb_forest.volume_db = -80.0
		add_child(_amb_forest)
	var rustle := _loop_stream("amb_forest_rustle.ogg")
	if rustle:
		_amb_rustle = AudioStreamPlayer.new()
		_amb_rustle.stream = rustle
		_amb_rustle.bus = "Ambience"
		_amb_rustle.volume_db = -80.0
		add_child(_amb_rustle)
	_gust_noise = FastNoiseLite.new()
	_gust_noise.seed = 5
	_gust_noise.frequency = 0.045
	_gust_noise.fractal_octaves = 2
	if not Settings.changed.is_connected(apply_quality):
		Settings.changed.connect(apply_quality)


func _loop_stream(file: String) -> AudioStream:
	var p := SFX + file
	if not ResourceLoader.exists(p):
		return null
	var st: AudioStream = load(p)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	return st


## Low banks of mist in the hollows, along the stream, creeping in at the gap.
func _mist_volumes() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 32
	tex.depth = 64
	tex.seamless = true
	tex.noise = noise
	var mat := FogMaterial.new()
	mat.density = 0.075
	mat.albedo = Color(0.66, 0.76, 0.86)
	mat.emission = Color(0.004, 0.006, 0.009)
	mat.height_falloff = 0.6
	mat.edge_fade = 0.6
	mat.density_texture = tex
	var spots_m := [Vector3(47, 0, 20), Vector3(60, 0, 22), Vector3(78, 0, 14), Vector3(92, 0, 32), Vector3(stream_x(32.0), 0, 30), Vector3(stream_x(5.0), 0, 5),
		Vector3(stream_x(60.0), 0, 60), Vector3(126, 0, 40), Vector3(146, 0, 64), Vector3(166, 0, 88), Vector3(27, 0, -44), Vector3(-44, 0, -27),
		Vector3(116, 0, 76), Vector3(138, 0, 22), Vector3(182, 0, 98), Vector3(-10, 0, 40), Vector3(60, 0, -20)]
	for p: Vector3 in spots_m:
		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		fv.size = Vector3(26.0, 8.0, 26.0)
		fv.material = mat
		fv.position = Vector3(p.x, height_at(p.x, p.z) + 1.5, p.z)
		_lights.add_child(fv)
		_mist.append([fv, fv.position, _rng.randf() * TAU])


func apply_quality() -> void:
	if env == null:
		return
	var q := Settings.quality
	env.volumetric_fog_enabled = q >= 1
	env.ssao_enabled = q >= 1
	env.glow_enabled = q >= 1
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.ssr_enabled = q >= 3
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_moon.directional_shadow_max_distance = [32.0, 45.0, 60.0, 70.0][clampi(q, 0, 3)]
	if active:
		RenderingServer.environment_set_volumetric_fog_volume_size(64 if q < 2 else 96, 64 if q < 2 else 96)
	var fk: float = [0.7, 0.85, 1.0, 1.15][clampi(q, 0, 3)]
	for m: ShaderMaterial in _fol_mats:
		var ff: float = m.get_meta("fade_far", 0.0)
		if ff > 0.0:
			m.set_shader_parameter("fade_far", ff * fk)


# ---------------------------------------------------------------------------
# spots, the end of the build
# ---------------------------------------------------------------------------
func _finish() -> void:
	_spot("courtyard_mid", Vector3(0, 0, 0.5))
	_spot("forest_gate", Vector3(46.2, height_at(46.2, 20.9), 20.9), -PI * 0.5)
	_lights.visible = false
	for L: Dictionary in lamps:
		_lamp_apply(L, 0.0 if L.mode == "dead" else 1.0)


# ---------------------------------------------------------------------------
# entering and leaving
# ---------------------------------------------------------------------------
## Swap the WorldEnvironment to the outdoor night (and the camera's far plane
## out to 170 m), show the exterior and its lights, start the ambience.
func enter(world_env: WorldEnvironment) -> void:
	if active:
		return
	active = true
	visible = true
	_lights.visible = true
	_world_env = world_env
	if world_env:
		_saved_env = world_env.environment
		_saved_attr = world_env.camera_attributes
		world_env.environment = env
		world_env.camera_attributes = _attr
	apply_quality()
	var cam := get_viewport().get_camera_3d()
	if cam:
		_saved_cam = cam
		_saved_far = cam.far
		cam.far = maxf(cam.far, 170.0)
	_fog_k = in_forest(cam.global_position) if cam else 0.0
	if _amb_court:
		_amb_court.play()
	if _amb_forest:
		_amb_forest.play(randf() * 30.0)
	if _amb_rustle:
		_amb_rustle.play(randf() * 20.0)
	_update_env(0.0, true)


## Back to the interior settings; hide the exterior and its lights.
func exit(world_env: WorldEnvironment = null) -> void:
	if not active:
		return
	active = false
	visible = false
	_lights.visible = false
	var we := world_env if world_env else _world_env
	if we and _saved_env:
		we.environment = _saved_env
		we.camera_attributes = _saved_attr
	if _saved_cam and is_instance_valid(_saved_cam):
		_saved_cam.far = _saved_far
	if _amb_court:
		_amb_court.stop()
	if _amb_forest:
		_amb_forest.stop()
	if _amb_rustle:
		_amb_rustle.stop()


## 0 in the courtyard .. 1 thirty metres and more into the trees.
func in_forest(pos: Vector3) -> float:
	var lp := to_local(pos)
	var dx := maxf(maxf(COURT.position.x - 4.0 - lp.x, lp.x - COURT.end.x - 4.0), 0.0)
	var dz := maxf(maxf(COURT.position.y - 4.0 - lp.z, lp.z - COURT.end.y - 4.0), 0.0)
	return smoothstep(2.0, 30.0, sqrt(dx * dx + dz * dz))


## True on the road (the escape).
func at_road(pos: Vector3) -> bool:
	var lp := to_local(pos)
	return absf(lp.x - ROAD_X) < ROAD_HW + 1.2


## The footstep sound for the ground at `pos` (gravel on paving, asphalt and
## steps; leaves and needles elsewhere).
func step_sound(pos: Vector3) -> String:
	var lp := to_local(pos)
	var hard := _in_rects(lp.x, lp.z) or absf(lp.x - ROAD_X) < ROAD_HW + 1.4 or _entrance_near(Vector2(lp.x, lp.z), 0.0)
	return SFX + ("step_gravel_%d.ogg" if hard else "step_leaf_%d.ogg") % _rng.randi_range(1, 6)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	_update_env(delta, false)
	_update_wind()
	for L: Dictionary in lamps:
		var lv := _lamp_level(L, delta)
		_lamp_apply(L, lv)
	for mv: Array in _mist:
		var fv: FogVolume = mv[0]
		var base: Vector3 = mv[1]
		var ph: float = mv[2]
		fv.position = base + Vector3(sin(_t * 0.03 + ph) * 4.0, 0.0, cos(_t * 0.025 + ph * 1.3) * 4.0)


## One gust envelope for the whole forest: it drives the sway of every
## branch and needle card (so their moon shadows move too) and the swell of
## the leaf rustle.
func _update_wind() -> void:
	if _gust_noise == null:
		return
	var n := _gust_noise.get_noise_1d(_t) * 0.5 + 0.5
	var surge := pow(clampf(_gust_noise.get_noise_1d(_t * 0.37 + 100.0) * 1.6, 0.0, 1.0), 2.0)
	_gust = clampf(0.15 + n * 0.45 + surge * 0.5, 0.1, 1.0)
	var ws := lerpf(0.1, 0.62, _gust)
	for m: ShaderMaterial in _fol_mats:
		m.set_shader_parameter("wind_strength", ws)
	for m: ShaderMaterial in _bark_mats:
		m.set_shader_parameter("wind_strength", ws)
	if _amb_rustle:
		var near_trees := 0.35 + 0.65 * _fog_k
		_amb_rustle.volume_db = linear_to_db(clampf(_gust * _gust * near_trees, 0.0001, 1.0)) - 3.0


func _update_env(delta: float, snap: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var k := in_forest(cam.global_position)
	_fog_k = k if snap else move_toward(_fog_k, k, delta * 0.2)
	var q := Settings.quality
	var vol := q >= 1
	env.volumetric_fog_density = lerpf(0.011, 0.025, _fog_k)
	env.ambient_light_energy = lerpf(0.75, 1.9, _fog_k)
	# eyes adapting to the dark under the trees
	env.tonemap_exposure = 1.75 * lerpf(1.0, 1.22, _fog_k) * exposure_boost
	env.volumetric_fog_ambient_inject = lerpf(0.14, 0.26, _fog_k)
	env.fog_density = lerpf(0.008, 0.02, _fog_k) * (1.0 if vol else 1.7)
	env.fog_height_density = lerpf(0.035, 0.07, _fog_k)
	env.fog_sky_affect = lerpf(0.35, 0.82, _fog_k)
	env.volumetric_fog_sky_affect = lerpf(0.25, 0.8, _fog_k)
	for m: ShaderMaterial in _fol_mats:
		m.set_shader_parameter("cam_pos", cam.global_position)
	if _amb_court:
		_amb_court.volume_db = linear_to_db(clampf(1.0 - _fog_k * 0.85, 0.0001, 1.0)) - 6.0
	if _amb_forest:
		_amb_forest.volume_db = linear_to_db(clampf(0.15 + _fog_k * 0.85, 0.0001, 1.0)) - 5.0
	var want := 62.0 if _fog_k > 0.6 else 115.0
	if want != _far_range:
		_far_range = want
		for f: MultiMeshInstance3D in _far_mmis:
			f.visibility_range_end = want

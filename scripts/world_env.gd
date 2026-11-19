class_name WorldEnv
extends Node3D
## Night environment: sky, moonlight through the pergola, volumetric fog,
## ground mist over the lake, tonemapping and the quality presets.

var env: Environment
var world_env: WorldEnvironment
var cam_attr: CameraAttributesPractical
var moon: DirectionalLight3D
var mist: FogVolume
var lake_mist: FogVolume
var sky_mat: ShaderMaterial
var base_exposure := 1.55
var _t := 0.0


func setup() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var cn := FastNoiseLite.new()
	cn.frequency = 0.004
	cn.fractal_octaves = 5
	var ct := NoiseTexture2D.new()
	ct.width = 1024
	ct.height = 1024
	ct.seamless = true
	ct.noise = cn
	sky_mat.set_shader_parameter("cloud_noise", ct)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = base_exposure
	env.tonemap_white = 6.0

	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.7)
	env.set_glow_level(5, 0.4)

	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15

	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.2

	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.05, 0.055, 0.07)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.25
	env.fog_height = 0.6
	env.fog_height_density = 0.04

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0045
	env.volumetric_fog_albedo = Color(0.82, 0.85, 0.9)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.3
	env.volumetric_fog_ambient_inject = 0.04
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.85

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.82

	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 34.0
	cam_attr.dof_blur_far_transition = 30.0
	cam_attr.dof_blur_amount = 0.05

	world_env = WorldEnvironment.new()
	world_env.environment = env
	world_env.camera_attributes = cam_attr
	add_child(world_env)

	# cold moonlight leaking through the rafters and the dead vines
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.66, 0.9)
	moon.light_energy = 0.085
	moon.light_volumetric_fog_energy = 0.6
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.light_angular_distance = 0.6
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = 55.0
	moon.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(-62.0), 0.0)
	add_child(moon)

	# ground mist over the lake and drifting into the corridor
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 3
	var ft := NoiseTexture3D.new()
	ft.width = 64
	ft.height = 32
	ft.depth = 64
	ft.seamless = true
	ft.noise = fn
	var fm := FogMaterial.new()
	fm.density = 0.03
	fm.albedo = Color(0.75, 0.8, 0.86)
	fm.height_falloff = 1.6
	fm.edge_fade = 0.4
	fm.density_texture = ft
	lake_mist = FogVolume.new()
	lake_mist.size = Vector3(60.0, 2.6, 180.0)
	lake_mist.material = fm
	lake_mist.position = Vector3(-30.0, -0.4, -60.0)
	add_child(lake_mist)

	var fm2 := FogMaterial.new()
	fm2.density = 0.045
	fm2.albedo = Color(0.78, 0.8, 0.84)
	fm2.height_falloff = 2.5
	fm2.edge_fade = 0.3
	mist = FogVolume.new()
	mist.size = Vector3(10.0, 1.4, 160.0)
	mist.material = fm2
	mist.position = Vector3(0.0, 0.0, -60.0)
	add_child(mist)

	Settings.changed.connect(apply_settings)
	apply_settings()


func _process(delta: float) -> void:
	_t += delta


## Mist volumes travel with the walker (the corridor never ends).
func follow(walker_z: float) -> void:
	if lake_mist:
		lake_mist.position = Vector3(-30.0 + sin(_t * 0.01) * 6.0, -0.4, walker_z - 50.0 + sin(_t * 0.013) * 4.0)
	if mist:
		mist.position = Vector3(sin(_t * 0.023) * 0.8, 0.0, walker_z - 50.0)


func apply_settings() -> void:
	var q: int = Settings.quality
	var vp := get_viewport()
	env.tonemap_exposure = base_exposure * pow(Settings.brightness, 1.4)
	env.volumetric_fog_enabled = q >= 1
	env.fog_density = 0.0035 if q >= 1 else 0.012
	env.ssao_enabled = q >= 1
	env.ssil_enabled = q >= 2
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 48 if q == 1 else (96 if q == 2 else 160)
	env.sdfgi_enabled = q >= 3
	if q >= 3:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.15
		env.sdfgi_energy = 0.7
	env.glow_enabled = true
	cam_attr.dof_blur_far_enabled = q >= 2
	if lake_mist:
		lake_mist.visible = q >= 1
		mist.visible = q >= 1
	moon.shadow_enabled = q >= 1
	if vp:
		match q:
			0:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			1:
				vp.msaa_3d = Viewport.MSAA_2X
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			2:
				vp.msaa_3d = Viewport.MSAA_4X
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			_:
				vp.msaa_3d = Viewport.MSAA_8X
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if q <= 1 else (96 if q == 2 else 128), 64 if q <= 1 else (96 if q == 2 else 128))
	RenderingServer.directional_shadow_atlas_set_size(2048 if q <= 1 else 4096, true)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM if q <= 1 else RenderingServer.ENV_SSAO_QUALITY_HIGH, true, 0.5, 2, 50, 300)

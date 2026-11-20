class_name InteriorEnv
extends Node
## Environment for the night interiors: no sky, a faint cold ambient,
## volumetric fog thin enough that only the moonlight and the bulbs draw
## shafts and halos, SSAO / SSIL / SDFGI by quality, AgX, a little glow.

var env: Environment
var world_env: WorldEnvironment
var cam_attr: CameraAttributesPractical
var base_exposure := 1.7


func setup(parent: Node) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.07, 0.09, 0.12)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = base_exposure
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 0.5)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.6)
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 2.0
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.9
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.015
	env.volumetric_fog_albedo = Color(0.7, 0.78, 0.86)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 24.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.08
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	world_env.camera_attributes = cam_attr
	parent.add_child(world_env)
	apply_settings()


func apply_settings() -> void:
	var q := Settings.quality
	env.ssao_enabled = q >= 1
	env.ssil_enabled = q >= 2
	env.sdfgi_enabled = q >= 3
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 2
		env.sdfgi_min_cell_size = 0.1
		env.sdfgi_energy = 0.7
	env.volumetric_fog_enabled = q >= 1
	env.glow_enabled = q >= 1
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if q < 2 else 96, 64 if q < 2 else 96)
	cam_attr.dof_blur_far_enabled = q >= 2
	cam_attr.dof_blur_far_distance = 7.0
	cam_attr.dof_blur_far_transition = 5.0
	cam_attr.dof_blur_amount = 0.04

class_name NightEnvironment extends WorldEnvironment
## Night look: HDRI city sky, AgX tonemap, bloom for lamps/tail-lights, SSR on the damp road,
## SSAO, volumetric fog so sodium lamps throw visible cones, and a cool moon key light.

const HDRI := "res://assets/hdri/shanghai_bund_4k.hdr"


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/night_sky.gdshader")
	mat.set_shader_parameter("panorama", load(HDRI))
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05

	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [2, 3, 4, 5] else 0.0)

	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6

	# Thin, dark, forward-scattering haze: the ambient sky barely lights it (no grey veil),
	# the lamp spots light it strongly, so each head throws a visible warm cone.
	RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)  # finer froxels: crisper cones
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.95, 0.9, 0.85)
	env.volumetric_fog_emission = Color(0.004, 0.004, 0.007)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 200.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.11, 0.16)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.15

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	environment = env

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.12
	moon.rotation_degrees = Vector3(-35, 150, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	add_child(moon)
	add_child(PerfProbe.new())
	add_child(SpeedFx.new())

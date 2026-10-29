# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Mirrors extends CanvasLayer
## Rear-view (top centre) and side mirrors (bottom, either side of the car): each a low-res
## SubViewport sharing the game world, with its own Camera3D at the car's mirror anchor looking
## back (side mirrors on the screen's left/right edges, above the speedo line), shown horizontally flipped like a real mirror (only the 3D picture is flipped; the HUD
## is a separate layer). Small rounded frames, soft vignette, far-distance blur. Police lights
## and headlights behind you show up in them: you see the cops coming.
##
## Mode (Settings "mirrors", the M key cycles OFF -> TOP ONLY -> SIDES ONLY -> ALL) and size ("mirror_size") apply
## live; --mirrors=off|top|sides|all overrides for one run. Rules/anchors: MirrorConfig.

const GROUP := &"mirrors"
const SHADER := """
shader_type canvas_item;
// The SubViewport picture, flipped left-right (a mirror), rounded corners, vignette, glass tint.
uniform vec2 px_size = vec2(500.0, 170.0);
uniform float radius = 14.0;
uniform float vignette = 0.55;
void fragment() {
	vec2 uv = vec2(1.0 - UV.x, UV.y);
	vec3 c = texture(TEXTURE, uv).rgb;
	vec2 d = (UV - 0.5) * 2.0;
	float v = 1.0 - vignette * smoothstep(0.35, 1.45, length(d * vec2(0.85, 1.0)));
	c *= v * vec3(0.94, 0.97, 1.0);
	vec2 p = UV * px_size;
	vec2 q = abs(p - px_size * 0.5) - (px_size * 0.5 - vec2(radius));
	float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	COLOR = vec4(c, clamp(0.5 - sd, 0.0, 1.0));
}
"""
const FRAME_PAD := 5.0
const TOP_Y := 16.0
const HOOD_TOP_Y := 30.0
const BOTTOM_Y := 384.0        # side mirrors' bottom edge above the screen bottom (clears the speedo)
const SIDE_X := 56.0           # side mirrors' outer edge from the screen edge

var player: PlayerCar
var camera: ChaseCamera
var hud: Hud
var police: PoliceManager      # read-only: lit cops behind flash the mirror frames red/blue
var settings: Settings
var mode := MirrorConfig.ALL
var size := 1
var anchors := {}
var _views := {}               # "rear"/"left"/"right" -> {vp, cam, frame, tex, stalk}
var _root: Control
var _toast: Label
var _toast_t := 0.0
var _frame := 0
var _hood := false
var _env: Environment
var _arg_mode := -1
var _t := 0.0


func _ready() -> void:
	layer = 1
	add_to_group(GROUP)
	if settings == null:
		settings = Settings.get_current()
	_arg_mode = MirrorConfig.parse_mode(String(LaunchArgs.get_value("mirrors", "")))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var spec: Dictionary = player.spec if player and not player.spec.is_empty() else CarCatalog.spec(CarCatalog.DEFAULT_ID)
	var model_half := Vector2.ZERO
	if player and player.car and player.car.has_meta("half_extents"):
		model_half = player.car.get_meta("half_extents")
	anchors = MirrorConfig.anchors(spec, model_half)
	_env = _mirror_env()
	for kind in ["rear", "left", "right"]:
		_views[kind] = _build_view(kind)
	_toast = SettingsMenu.make_label(_root, load(SettingsMenu.BODY), 24, Color(1, 1, 1, 0.9))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.modulate.a = 0.0
	apply_settings(settings)
	print("MIRRORS mode=%s size=%s rear=%s left=%s right=%s" % [MirrorConfig.MODE_NAMES[mode], MirrorConfig.SIZE_NAMES[size],
		anchors.rear, anchors.left, anchors.right])


## Settings.apply() calls this (live from the settings menu).
func apply_settings(s: Settings) -> void:
	mode = _arg_mode if _arg_mode >= 0 else s.get_value("mirrors")
	size = s.get_value("mirror_size")
	_env = _mirror_env()
	for kind in _views:
		var v: Dictionary = _views[kind]
		(v.vp as SubViewport).size = MirrorConfig.render_size("rear" if kind == "rear" else "side", size)
		(v.cam as Camera3D).environment = _env
	_layout()


## M: OFF -> TOP ONLY -> SIDES ONLY -> ALL (saved, like the settings menu).
func cycle() -> void:
	_arg_mode = -1
	settings.set_value("mirrors", MirrorConfig.next_mode(mode))
	settings.save()
	apply_settings(settings)
	_toast.text = "MIRRORS  ·  " + MirrorConfig.MODE_NAMES[mode]
	_toast_t = 1.6


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("mirrors") and _in_run():
		get_viewport().set_input_as_handled()
		cycle()


func _in_run() -> bool:
	return hud == null or hud.visible


func is_shown(kind: String) -> bool:
	if not _in_run():
		return false
	return MirrorConfig.shows_rear(mode) if kind == "rear" else MirrorConfig.shows_sides(mode)


func _process(delta: float) -> void:
	_frame += 1
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	var hood := camera != null and camera.hood
	if hood != _hood:
		_hood = hood
		_layout()
	var any := false
	for kind in _views:
		var v: Dictionary = _views[kind]
		var on := is_shown(kind)
		(v.frame as Control).visible = on
		var vp: SubViewport = v.vp
		if not on:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		any = true
		_place_camera(kind, v.cam)
		_cue(kind, v)
		if MirrorConfig.renders_on(kind, mode, _frame):
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if hud:
		hud.set_top_shift(_rear_bottom() if any and is_shown("rear") else 0.0)


## Lit cop behind, in this mirror's sector: the frame strobes red/blue with the light bar timing.
func _cue(kind: String, v: Dictionary) -> void:
	var sb: StyleBoxFlat = (v.frame as Control).get_meta("sb")
	var k := 0.0
	if police and player:
		var inv := player.global_transform.affine_inverse()
		for c in police.cops:
			if is_instance_valid(c) and c.bar and c.bar.on:
				k = maxf(k, MirrorConfig.cop_cue(kind, inv * c.global_position))
	_t += get_process_delta_time() if kind == "rear" else 0.0
	if k <= 0.0:
		sb.border_color = Color(1, 1, 1, 0.16)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 8
		return
	var red := LightBar.strobe(0, _t)
	var blue := LightBar.strobe(1, _t)
	var col := Color(1.0, 0.12, 0.18) if red >= blue else Color(0.2, 0.45, 1.0)
	var lit := maxf(red, blue)
	sb.border_color = Color(col, lerpf(0.3, 1.0, lit * k))
	sb.shadow_color = Color(col, 0.75 * lit * k)
	sb.shadow_size = int(lerpf(8.0, 22.0, lit * k))


func _place_camera(kind: String, cam: Camera3D) -> void:
	if player == null:
		return
	var xf := player.get_global_transform_interpolated()
	# Yaw only: mirrors are bolted to the body, but body roll/pitch is visual-only here.
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var pos: Vector3 = xf.origin + basis * (anchors[kind] as Vector3)
	var look := Vector3(0, -0.05, 1)          # rear-view: straight back, a touch down
	if kind == "left":
		look = Vector3(-0.2, -0.07, 1)        # side mirrors aim a little outward
	elif kind == "right":
		look = Vector3(0.2, -0.07, 1)
	cam.global_position = pos
	cam.look_at(pos + basis * look, Vector3.UP)


func _build_view(kind: String) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = MirrorConfig.render_size("rear" if kind == "rear" else "side", size)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 0      # no headlight shadows in the mirrors
	vp.mesh_lod_threshold = 4.0
	vp.audio_listener_enable_3d = false
	vp.name = "Mirror_" + kind
	vp.add_to_group(PerfProbe.VP_GROUP)
	add_child(vp)
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.15
	cam.far = 400.0
	cam.fov = 19.0 if kind == "rear" else 30.0  # rear-view ~47 deg wide: a cop at 40 m still reads
	# Layer 2 = hero DRL blades (as the hood cam); MAIN_ONLY = the shadow-casting moon.
	cam.cull_mask = 0xFFFFF & ~2 & ~NightEnvironment.MAIN_ONLY_LAYER
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true         # far traffic goes soft, like a small mirror
	attrs.dof_blur_far_distance = 70.0
	attrs.dof_blur_far_transition = 120.0
	attrs.dof_blur_amount = 0.06
	cam.attributes = attrs
	cam.environment = _env
	vp.add_child(cam)
	cam.current = true

	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.07, 0.92)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_meta("sb", sb)
	_root.add_child(frame)
	var tex := TextureRect.new()
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	tex.material = mat
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = FRAME_PAD
	tex.offset_top = FRAME_PAD
	tex.offset_right = -FRAME_PAD
	tex.offset_bottom = -FRAME_PAD
	frame.add_child(tex)
	var stalk: ColorRect = null
	if kind == "rear":  # hood cam: the mount down from the roof lining
		stalk = ColorRect.new()
		stalk.color = Color(0.2, 0.19, 0.25, 0.95)
		stalk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(stalk)
		_root.move_child(stalk, 0)
	return {"vp": vp, "cam": cam, "frame": frame, "tex": tex, "stalk": stalk, "mat": mat}


## Place the frames (1080p HUD units: the CanvasLayer scales with the window's stretch mode).
func _layout() -> void:
	for kind in _views:
		var v: Dictionary = _views[kind]
		var d := MirrorConfig.display_size("rear" if kind == "rear" else "side", size, _hood)
		var f: Panel = v.frame
		match kind:
			"rear":
				var top := HOOD_TOP_Y if _hood else TOP_Y
				_place(f, Control.PRESET_CENTER_TOP, -d.x * 0.5, top, d.x, d.y)
				var st: ColorRect = v.stalk
				_place(st, Control.PRESET_CENTER_TOP, -22, 0, 44, top + 10)
				st.visible = _hood and is_shown("rear")
			"left":
				_place(f, Control.PRESET_BOTTOM_LEFT, SIDE_X, -BOTTOM_Y - d.y, d.x, d.y)
			"right":
				_place(f, Control.PRESET_BOTTOM_RIGHT, -SIDE_X - d.x, -BOTTOM_Y - d.y, d.x, d.y)
		(v.mat as ShaderMaterial).set_shader_parameter("px_size", d - Vector2(FRAME_PAD, FRAME_PAD) * 2.0)
		(v.mat as ShaderMaterial).set_shader_parameter("radius", 13.0)
	if _toast:
		_toast.offset_top = _rear_bottom() + 8.0
		_toast.offset_bottom = _toast.offset_top + 34.0


func _rear_bottom() -> float:
	return (HOOD_TOP_Y if _hood else TOP_Y) + MirrorConfig.display_size("rear", size, _hood).y


static func _place(c: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


## The world's look without the expensive screen-space passes (glow stays: lights must pop).
func _mirror_env() -> Environment:
	var we := get_tree().get_first_node_in_group(NightEnvironment.GROUP) as WorldEnvironment if is_inside_tree() else null
	if we == null or we.environment == null:
		return null
	var e := we.environment.duplicate() as Environment
	e.ssr_enabled = false
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false
	# The HDRI behind the car is the Bund's warm-lit riverside (it reads as daylight in a mirror):
	# the mirrors see the night skyline panorama turned round instead.
	if e.sky and e.sky.sky_material is ShaderMaterial:
		var sky := Sky.new()
		sky.radiance_size = Sky.RADIANCE_SIZE_64
		var m := (e.sky.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
		var rot = m.get_shader_parameter("rotation")
		m.set_shader_parameter("rotation", (float(rot) if rot != null else 0.0) + PI)
		sky.sky_material = m
		e.sky = sky
	return e


## Proof/test helper: the camera transform of a mirror after a placement pass.
func camera_of(kind: String) -> Camera3D:
	return _views[kind].cam if _views.has(kind) else null

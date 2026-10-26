# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name CarStyleFx extends Node3D
## The animated bits of a CarStyle loadout: underglow (a soft additive pool + a low omni light that
## also lights the wet road) and exhaust flames that pop on a throttle lift ("backfire") or on
## demand in the garage. Rainbow items cycle their hue.

var glow_color := Color(0, 0, 0, 0)
var glow_cycle := false
var flame_color := Color(1.0, 0.45, 0.08)
var flame_cycle := false
var _glow_mesh: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _glow_light: OmniLight3D
var _flames: Array[MeshInstance3D] = []
var _flame_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _flame_t := 0.0     # seconds of flame left
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(half: Vector2, rig: Dictionary, glow: Dictionary, flame: Dictionary) -> void:
	_rng.seed = 77
	glow_color = glow.color
	glow_cycle = glow.get("cycle", false)
	flame_color = flame.color
	flame_cycle = flame.get("cycle", false)
	if glow_color.a > 0.0:
		_glow_mesh = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(half.x * 2.0 + 1.4, half.y * 2.0 + 1.2)
		_glow_mesh.mesh = pm
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.albedo_texture = _radial()
		_glow_mat.render_priority = 1
		_glow_mesh.material_override = _glow_mat
		_glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow_mesh.position.y = 0.035
		add_child(_glow_mesh)
		_glow_light = OmniLight3D.new()
		_glow_light.position.y = 0.18
		_glow_light.omni_range = maxf(half.y, half.x) + 1.6
		_glow_light.light_energy = 2.2
		_glow_light.shadow_enabled = false
		add_child(_glow_light)
		_set_glow(glow_color)
	# Flames: a coloured outer cone and a hot white core per exhaust tip, pointing out the back.
	_flame_mat = _additive()
	_core_mat = _additive()
	for x in rig.exhaust_x:
		for core in [false, true]:
			var f := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.05 if core else 0.085
			cm.height = 0.32 if core else 0.55
			cm.radial_segments = 12
			cm.rings = 1
			cm.cap_top = false
			f.mesh = cm
			f.material_override = _core_mat if core else _flame_mat
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.rotation.x = PI * 0.5  # cylinder +Y -> car +Z (out the back)
			f.position = Vector3(x, rig.exhaust_y, half.y + rig.exhaust_z + cm.height * 0.5)
			f.visible = false
			add_child(f)
			_flames.append(f)
	_set_flame(flame_color)


## Pop the exhausts for `seconds` (backfire).
func pop(seconds := 0.22) -> void:
	_flame_t = maxf(_flame_t, seconds)


func _process(delta: float) -> void:
	_t += delta
	if glow_cycle and _glow_mat:
		_set_glow(Color.from_hsv(fmod(_t * 0.18, 1.0), 0.85, 1.0))
	if _glow_light:
		_glow_light.light_energy = 2.2 * (0.92 + 0.08 * sin(_t * 9.0))
	if flame_cycle:
		_set_flame(Color.from_hsv(fmod(_t * 0.5, 1.0), 0.8, 1.0))
	var on := _flame_t > 0.0
	_flame_t = maxf(0.0, _flame_t - delta)
	for i in _flames.size():
		var f := _flames[i]
		f.visible = on
		if on:
			var k := 0.55 + _rng.randf() * 0.65
			f.scale = Vector3(0.8 + _rng.randf() * 0.4, k, 0.8 + _rng.randf() * 0.4)


func _set_glow(c: Color) -> void:
	_glow_mat.albedo_color = Color(c.r, c.g, c.b, 0.85)
	_glow_light.light_color = c


func _set_flame(c: Color) -> void:
	_flame_mat.albedo_color = Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, 0.9)
	_core_mat.albedo_color = Color(1.4, 1.35, 1.25, 0.9).lerp(Color(c.r * 2.0, c.g * 2.0, c.b * 2.0), 0.25)


static func _additive() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


static func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.6, Color(1, 1, 1, 0.35))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

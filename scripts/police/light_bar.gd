class_name LightBar extends Node3D
## Roof light bar: red (left) and blue (right) emissive lenses plus one red and one blue
## OmniLight that wash the car, the road and anything alongside. Strobes in the classic
## double-flash pattern when on; dark lenses when off. Cheap: 3 boxes, 2 unshadowed lights.

const RED := Color(1.0, 0.06, 0.04)
const BLUE := Color(0.08, 0.25, 1.0)
const PERIOD := 0.56          # seconds per red+blue cycle

var on := false
var _t := 0.0
var _lens: Array[MeshInstance3D] = []
var _mat: Array[StandardMaterial3D] = []
var _lights: Array[OmniLight3D] = []


## width: bar length across the roof (m).
func build(width: float) -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.07, 0.26)
	base.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.04, 0.05)
	dark.roughness = 0.4
	base.material_override = dark
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var m := StandardMaterial3D.new()
		var col := RED if i == 0 else BLUE
		m.albedo_color = col * 0.35
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.0
		m.roughness = 0.2
		var lens := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(width * 0.44, 0.1, 0.22)
		lens.mesh = lm
		lens.material_override = m
		lens.position = Vector3(side * width * 0.25, 0.06, 0)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lens)
		_lens.append(lens)
		_mat.append(m)
		var l := OmniLight3D.new()
		l.light_color = col
		l.omni_range = 16.0
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.light_specular = 0.6
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 0.0
		l.position = Vector3(side * width * 0.5, 0.35, 0)
		l.visible = false
		add_child(l)
		_lights.append(l)


func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	_t = randf() * PERIOD  # chasers out of phase, like real units
	for l in _lights:
		l.visible = v
	if not v:
		for m in _mat:
			m.emission_energy_multiplier = 0.0


## Strobe level 0..1 for side (0 red, 1 blue) at time t: each side double-flashes in its half.
static func strobe(side: int, t: float) -> float:
	var ph := fposmod(t / PERIOD, 1.0)
	var local := ph - (0.0 if side == 0 else 0.5)
	if local < 0.0 or local >= 0.5:
		return 0.06  # a dim glow between flashes so the bar never reads as "off"
	var k := local / 0.5
	return 1.0 if (k < 0.32 or (k > 0.48 and k < 0.8)) else 0.06


func _process(delta: float) -> void:
	if not on:
		return
	_t += delta
	for i in 2:
		var s := strobe(i, _t)
		_mat[i].emission_energy_multiplier = 9.0 * s
		_lights[i].light_energy = 7.0 * s

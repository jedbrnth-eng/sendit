class_name SpeedFx extends CanvasLayer
## Screen-space post pass (scripts/post/speed_fx.gdshader). Sits below the HUD layer so UI stays
## crisp. Speed comes from the active camera's own motion, so it needs no link to the car.

const START_KMH := 130.0
const FULL_KMH := 260.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _last_pos := Vector3.INF
var _kmh := 0.0


## Effect intensity 0..1 for a speed; eased so it ramps in gently above cruising speed.
static func amount_for(kmh: float) -> float:
	return smoothstep(START_KMH, FULL_KMH, kmh)


func _ready() -> void:
	layer = -1
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/post/speed_fx.gdshader")
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or delta <= 0.0:
		return
	var p := cam.global_position
	if _last_pos != Vector3.INF:
		var inst := (p - _last_pos).length() / delta * 3.6
		if inst < 600.0:  # larger jumps are camera teleports (restart), not speed
			_kmh = lerpf(_kmh, inst, clampf(delta * 4.0, 0.0, 1.0))  # smooth out shake
	_last_pos = p
	_mat.set_shader_parameter("amount", amount_for(_kmh))

extends Node
## Smoothness probe: runs the real game (autodrive) and, every rendered frame, records how far the
## camera moved along the road per second. With judder that rate jumps frame to frame even at a
## steady speed; with physics interpolation it should be steady.
## Prints SMOOTH: frames=N fps=F jitter_pct=J (std/mean of per-frame camera speed, steady part).

var _main: Node
var _rates: PackedFloat64Array = []
var _last_z := 0.0
var _frames := 0


func _ready() -> void:
	process_priority = 10000  # sample after the camera has updated this frame
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	_frames += 1
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var z := cam.global_position.z
	if OS.get_cmdline_user_args().has("--raw"):
		z = (_main.get("player") as Node3D).global_position.z  # un-interpolated physics position
	if _frames > 240 and delta > 0.0:
		_rates.append(absf(z - _last_z) / delta)
	_last_z = z
	if _frames >= 840:
		# Judder = the per-frame speed jumping between consecutive frames. Real acceleration is
		# smooth, so consecutive differences isolate judder from braking/accelerating.
		var m := 0.0
		for r in _rates:
			m += r
		m /= _rates.size()
		var d: Array[float] = []
		for i in range(1, _rates.size()):
			d.append(absf(_rates[i] - _rates[i - 1]))
		d.sort()
		var med := d[d.size() / 2]
		var p95 := d[int(d.size() * 0.95)]
		print("SMOOTH: frames=%d fps=%.1f mean_mps=%.1f judder_med_pct=%.2f judder_p95_pct=%.2f" % [_rates.size(), Engine.get_frames_per_second(), m, 100.0 * med / maxf(m, 0.001), 100.0 * p95 / maxf(m, 0.001)])
		get_tree().quit()

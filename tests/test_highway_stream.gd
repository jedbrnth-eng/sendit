extends RefCounted

var runner


func _covers(pz: float) -> bool:
	var r := Highway.chunk_range(pz)
	# chunk i spans z in [-(i+1)*L, -i*L]
	var near_z := -r.x * RoadSpec.CHUNK_LEN          # +Z end of first chunk
	var far_z := -(r.y + 1) * RoadSpec.CHUNK_LEN     # -Z end of last chunk
	return near_z >= pz + RoadSpec.VIEW_BEHIND - 0.001 and far_z <= pz - RoadSpec.VIEW_AHEAD + 0.001


func test_stream_window_covers_behind_and_ahead() -> void:
	for pz in [0.0, -80.0, -99.9, -100.0, -12345.6, 250.0]:
		runner.check(_covers(pz), "window covers player at z=%s" % pz)


func test_stream_window_is_bounded() -> void:
	var r := Highway.chunk_range(-5000.0)
	var n := r.y - r.x + 1
	var expected := int(ceil((RoadSpec.VIEW_AHEAD + RoadSpec.VIEW_BEHIND) / RoadSpec.CHUNK_LEN)) + 1
	runner.check(n <= expected, "at most %d chunks, got %d" % [expected, n])

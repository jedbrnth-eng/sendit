extends RefCounted

var runner


func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


func test_footprints_are_convex_and_consistently_wound() -> void:
	var expect := {TowerKit.Shape.BOX: 4, TowerKit.Shape.CHAMFER: 8, TowerKit.Shape.ROUND: 12, TowerKit.Shape.BLADE: 4}
	for shape in expect:
		var p := TowerKit.footprint(shape, 30.0, 20.0)
		runner.check(p.size() == expect[shape], "shape %d has %d corners" % [shape, p.size()])
		runner.check(_area(p) > 0.0, "shape %d has positive signed area" % shape)
		for i in p.size():
			var a := p[i]
			var b := p[(i + 1) % p.size()]
			var c := p[(i + 2) % p.size()]
			runner.check((b - a).cross(c - b) >= -1e-4, "shape %d convex at corner %d" % [shape, i])


func test_plan_is_deterministic() -> void:
	var a := TowerKit.plan(4242, 200.0)
	var b := TowerKit.plan(4242, 200.0)
	runner.check(a.top == b.top and a.style == b.style and a.tiers.size() == b.tiers.size(), "same seed, same tower")


func test_plans_stack_cleanly_within_height_class() -> void:
	for max_h in [26.0, 48.0, 170.0, 240.0]:
		for s in 200:
			var p := TowerKit.plan(s * 31 + 7, max_h)
			var tiers: Array = p.tiers
			runner.check(tiers.size() >= 1, "has tiers")
			runner.check(p.top <= maxf(18.0, max_h) + 0.001, "top %.1f within class %.0f" % [p.top, max_h])
			var y := 0.0
			for i in tiers.size():
				var t: Dictionary = tiers[i]
				runner.check(is_equal_approx(t.y0, y), "tier %d starts where the last ended" % i)
				runner.check(t.y1 > t.y0, "tier %d has height" % i)
				runner.check(i == 0 or t.style != TowerKit.Style.PODIUM, "podium only at the base")
				y = t.y1
			runner.check(is_equal_approx(y, p.top), "last tier reaches the top")


## Every row's widest possible tower must stay clear of the road: the near rows only get small
## footprints (no podiums below 50 m), so a tower can never straddle the guard rail.
func test_skyline_rows_never_reach_the_road() -> void:
	for row: Array in Highway.CITY_ROWS:
		var worst := 0.0
		for s in 300:
			var p := TowerKit.plan(s * 97 + 1, row[2])
			for t: Dictionary in p.tiers:
				for v: Vector2 in t.poly:
					worst = maxf(worst, v.length())
		runner.check(worst + 2.0 < row[0], "row at %.0f m: widest tower radius %.1f m" % [row[0], worst])


func test_mesh_faces_point_outward_and_wind_for_godot() -> void:
	var kit := TowerKit.new()
	var xf := Transform3D(Basis(Vector3.UP, 0.3), Vector3(100, -0.1, -50))
	for s in 20:
		kit.add_tower(TowerKit.plan(s + 1, 200.0), xf)
	var mesh := kit.commit()
	runner.check(mesh != null and mesh.get_surface_count() == 1, "one batched surface")
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	runner.check(c0.size() == v.size() * 4, "CUSTOM0 is RGBA float per vertex")
	var bad_wind := 0
	var bad_out := 0
	for i in range(0, v.size(), 3):
		var face_n := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		if face_n.dot(n[i]) >= 0.0:  # Godot front faces are clockwise: cross opposes the normal
			bad_wind += 1
		var centre := (v[i] + v[i + 1] + v[i + 2]) / 3.0
		var radial := Vector3(centre.x - 100.0, 0, centre.z + 50.0)
		if absf(n[i].y) < 0.5 and radial.dot(n[i]) <= 0.0:
			bad_out += 1
	runner.check(bad_wind == 0, "%d triangles wound back-to-front" % bad_wind)
	runner.check(bad_out == 0, "%d wall normals point inward" % bad_out)


func test_tall_towers_get_aviation_beacons() -> void:
	var kit := TowerKit.new()
	var tall := 0
	for s in 40:
		var p := TowerKit.plan(s + 500, 240.0)
		if p.top > 60.0:
			tall += 1
		kit.add_tower(p, Transform3D.IDENTITY)
	runner.check(kit.beacons.size() == tall, "one beacon per tower over 60 m (%d vs %d)" % [kit.beacons.size(), tall])

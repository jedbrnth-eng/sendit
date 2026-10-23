extends SceneTree
## Prints each car model's raw AABB so orientation/scale assumptions in CarModel can be checked.

func _init() -> void:
	for dir in ["res://assets/traffic", "res://assets/cars/cosmo", "res://assets/cars/quaternius"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb"):
				continue
			var n := (load(dir + "/" + f) as PackedScene).instantiate() as Node3D
			var a := CarModel.aabb_of(n, Transform3D.IDENTITY)
			print("%-40s size=(%.2f, %.2f, %.2f) centre=(%.2f, %.2f, %.2f)" % [f, a.size.x, a.size.y, a.size.z, a.get_center().x, a.get_center().y, a.get_center().z])
			n.free()
	quit()

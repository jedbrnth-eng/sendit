# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name PursuitCam extends Camera3D
## Proof camera (--cam=pursuit): hangs ahead of and beside the player, low, looking back past the
## car at the nearest chaser so the light bars and the player share the frame. Not used in play.

var police: PoliceManager
var player: PlayerCar


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.1
	far = 3000.0
	fov = 55.0
	make_current.call_deferred()


func _process(_delta: float) -> void:
	if player == null:
		return
	var pp := player.get_global_transform_interpolated().origin
	var focus := pp + Vector3(0, 0.8, 18.0)
	var best := INF
	for c in police.chasers():
		var d := c.global_position.distance_to(pp)
		if d < best and d < 120.0:
			best = d
			focus = pp.lerp(c.get_global_transform_interpolated().origin, 0.6) + Vector3(0, 0.8, 0)
	var side := -1.0 if pp.x > RoadSpec.lane_x(2) else 1.0
	global_position = pp + Vector3(side * 2.4, 1.5, -9.5)
	look_at(focus, Vector3.UP)

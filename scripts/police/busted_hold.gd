# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name BustedHold extends Autopilot
## Takes the wheel when you are BUSTED: straight ahead, full brakes, until the results card.


func drive(_p: PlayerCar) -> Vector3:
	return Vector3(0.0, 0.0, 1.0)

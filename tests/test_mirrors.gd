# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Mirrors: modes, sizes, per-car anchors and settings persistence (no rendering).

var runner

const TMP := "user://_test_mirrors_settings.cfg"


func test_mode_cycle_and_clamp() -> void:
	runner.check(MirrorConfig.next_mode(MirrorConfig.OFF) == MirrorConfig.REAR, "OFF -> REAR")
	runner.check(MirrorConfig.next_mode(MirrorConfig.REAR) == MirrorConfig.ALL, "REAR -> ALL")
	runner.check(MirrorConfig.next_mode(MirrorConfig.ALL) == MirrorConfig.OFF, "ALL -> OFF")
	runner.check(MirrorConfig.clamp_mode(9) == MirrorConfig.ALL and MirrorConfig.clamp_mode(-3) == MirrorConfig.OFF, "mode clamps")
	runner.check(MirrorConfig.clamp_size(7) == 2 and MirrorConfig.clamp_size(-1) == 0, "size clamps")
	runner.check(MirrorConfig.parse_mode("rear") == MirrorConfig.REAR and MirrorConfig.parse_mode("off") == MirrorConfig.OFF
		and MirrorConfig.parse_mode("all") == MirrorConfig.ALL and MirrorConfig.parse_mode("junk") == -1, "launch arg parse")
	runner.check(MirrorConfig.shows_rear(MirrorConfig.REAR) and not MirrorConfig.shows_sides(MirrorConfig.REAR), "rear only")
	runner.check(MirrorConfig.shows_rear(MirrorConfig.ALL) and MirrorConfig.shows_sides(MirrorConfig.ALL), "all")
	runner.check(not MirrorConfig.shows_rear(MirrorConfig.OFF) and not MirrorConfig.shows_sides(MirrorConfig.OFF), "off")


func test_render_sizes_stay_low_res() -> void:
	for s in 3:
		var r: Vector2i = MirrorConfig.render_size("rear", s)
		var d: Vector2i = MirrorConfig.render_size("side", s)
		runner.check(r.x <= 640 and r.y <= 240 and r.x >= 256, "rear render stays low-res at size %d: %s" % [s, r])
		runner.check(d.x <= 320 and d.y <= 256 and d.x >= 128, "side render stays low-res at size %d: %s" % [s, d])
	runner.check(MirrorConfig.render_size("rear", 1) == Vector2i(512, 192), "medium rear = 512x192")
	runner.check(MirrorConfig.render_size("rear", 99) == MirrorConfig.render_size("rear", 2), "size index clamps")
	var small: Vector2 = MirrorConfig.display_size("rear", 0, false)
	var big: Vector2 = MirrorConfig.display_size("rear", 2, false)
	runner.check(small.x < big.x and small.y < big.y, "display grows with size option")
	runner.check(MirrorConfig.display_size("rear", 1, true).x > MirrorConfig.display_size("rear", 1, false).x, "hood cam rear-view is larger")


func test_anchor_derivation_for_every_catalog_car() -> void:
	var specs: Array = CarCatalog.VEHICLES.duplicate()
	specs.append(CarCatalog.SHELVED_SOI_ROCKET)
	for s in specs:
		var a: Dictionary = MirrorConfig.anchors(s)
		var half_len: float = s.length * 0.5
		var hb: Vector2 = s.hitbox
		var rear: Vector3 = a.rear
		var left: Vector3 = a.left
		var right: Vector3 = a.right
		runner.check(rear.z > half_len - 0.2 and absf(rear.x) < 0.01, "%s: rear cam at the tail, centred (%s)" % [s.id, rear])
		runner.check(rear.y > 0.5 and rear.y < 2.5, "%s: rear cam height sane (%.2f)" % [s.id, rear.y])
		runner.check(left.x < -hb.x and right.x > hb.x, "%s: side cams outside the body (%s / %s)" % [s.id, left, right])
		runner.check(is_equal_approx(left.x, -right.x) and is_equal_approx(left.y, right.y) and is_equal_approx(left.z, right.z), "%s: sides symmetric" % s.id)
		runner.check(left.z < 0.0 and left.z > -half_len, "%s: side mirrors ahead of centre, on the body (%.2f)" % [s.id, left.z])
		runner.check(left.y > 0.4 and left.y < 2.2, "%s: side mirror height sane (%.2f)" % [s.id, left.y])


func test_anchor_uses_measured_model_extents() -> void:
	var s: Dictionary = CarCatalog.spec("naga")
	var plain := MirrorConfig.anchors(s)
	var wide := MirrorConfig.anchors(s, Vector2(1.3, 2.9))
	runner.check(wide.left.x < -1.3 and wide.right.x > 1.3, "side cams clear the measured mesh width")
	runner.check(wide.rear.z > 2.9, "rear cam clears the measured mesh length")
	runner.check(is_equal_approx(MirrorConfig.anchors(s, Vector2(0.5, 1.0)).left.x, plain.left.x), "a smaller mesh never pulls the cams inside the hitbox")


func test_anchor_overrides_win() -> void:
	var s: Dictionary = CarCatalog.spec("voltage").duplicate()
	s["mirror_rear"] = Vector3(0, 1.7, 3.0)
	s["mirror_side"] = Vector3(-1.4, 1.1, -0.6)
	var a := MirrorConfig.anchors(s)
	runner.check(a.rear == Vector3(0, 1.7, 3.0), "rear override used")
	runner.check(a.left == Vector3(-1.4, 1.1, -0.6) and a.right == Vector3(1.4, 1.1, -0.6), "side override mirrored to the right")
	# A positive-x side override is still treated as the left mirror's distance.
	s["mirror_side"] = Vector3(1.4, 1.1, -0.6)
	runner.check(is_equal_approx(MirrorConfig.anchors(s).left.x, -1.4), "side override sign normalised")


func test_settings_persist_and_presets() -> void:
	var s := Settings.new()
	runner.check(s.get_value("mirrors") == MirrorConfig.ALL and s.get_value("mirror_size") == 1, "defaults: all mirrors, medium")
	s.set_value("mirrors", 7)
	runner.check(s.get_value("mirrors") == MirrorConfig.ALL, "settings clamp mode")
	s.set_value("mirrors", MirrorConfig.REAR)
	s.set_value("mirror_size", 2)
	runner.check(s.save(TMP) == OK, "saves")
	var t := Settings.new()
	t.load_from(TMP)
	runner.check(t.get_value("mirrors") == MirrorConfig.REAR and t.get_value("mirror_size") == 2, "mirror settings persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	t.set_quality(0)
	runner.check(t.get_value("mirrors") == MirrorConfig.REAR, "LOW preset = rear-view only")
	t.set_quality(2)
	runner.check(t.get_value("mirrors") == MirrorConfig.ALL, "HIGH preset = all mirrors")
	runner.check("mirrors" in Settings.REBINDABLE and Settings.default_keys("mirrors") == [KEY_M], "M cycles mirrors (rebindable)")


func test_police_cue_sectors() -> void:
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, 20)) > 0.9, "cop close behind: rear-view flashes hard")
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, 200)) > 0.0 and MirrorConfig.cop_cue("rear", Vector3(0, 0, 200)) < 0.5, "far behind: faint")
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, 400)) == 0.0, "out of range: none")
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, -30)) == 0.0, "cop ahead: no mirror cue")
	runner.check(MirrorConfig.cop_cue("left", Vector3(-3.5, 0, 15)) > 0.5 and MirrorConfig.cop_cue("right", Vector3(-3.5, 0, 15)) == 0.0, "behind-left: left mirror only")
	runner.check(MirrorConfig.cop_cue("right", Vector3(3.5, 0, 15)) > 0.5 and MirrorConfig.cop_cue("left", Vector3(3.5, 0, 15)) == 0.0, "behind-right: right mirror only")
	runner.check(MirrorConfig.cop_cue("left", Vector3(0, 0, 15)) == 0.0, "dead behind: not in the side mirrors' cue")


func test_one_mirror_render_per_frame() -> void:
	var counts := {"rear": 0, "left": 0, "right": 0}
	for f in 400:
		var n := 0
		for k in counts:
			if MirrorConfig.renders_on(k, MirrorConfig.ALL, f):
				counts[k] += 1
				n += 1
		runner.check(n == 1, "ALL: exactly one mirror renders on frame %d (got %d)" % [f, n])
	runner.check(counts.rear == 200 and counts.left == 100 and counts.right == 100, "ALL: rear 1/2 rate, sides 1/4 each: %s" % counts)
	for f in 10:
		runner.check(MirrorConfig.renders_on("rear", MirrorConfig.REAR, f) and not MirrorConfig.renders_on("left", MirrorConfig.REAR, f), "REAR: rear-view every frame")
		runner.check(not MirrorConfig.renders_on("rear", MirrorConfig.OFF, f), "OFF: nothing renders")

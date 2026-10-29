# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Mirrors: modes, sizes, per-car anchors and settings persistence (no rendering).

var runner

const TMP := "user://_test_mirrors_settings.cfg"


func test_mode_cycle_and_clamp() -> void:
	# M cycles OFF -> TOP ONLY -> SIDES ONLY -> ALL -> OFF.
	runner.check(MirrorConfig.next_mode(MirrorConfig.OFF) == MirrorConfig.TOP, "OFF -> TOP")
	runner.check(MirrorConfig.next_mode(MirrorConfig.TOP) == MirrorConfig.SIDES, "TOP -> SIDES")
	runner.check(MirrorConfig.next_mode(MirrorConfig.SIDES) == MirrorConfig.ALL, "SIDES -> ALL")
	runner.check(MirrorConfig.next_mode(MirrorConfig.ALL) == MirrorConfig.OFF, "ALL -> OFF")
	runner.check(MirrorConfig.MODE_NAMES.size() == 4 and MirrorConfig.MODE_NAMES[MirrorConfig.TOP] == "TOP ONLY"
		and MirrorConfig.MODE_NAMES[MirrorConfig.SIDES] == "SIDES ONLY" and MirrorConfig.MODE_NAMES[MirrorConfig.ALL] == "ALL"
		and MirrorConfig.MODE_NAMES[MirrorConfig.OFF] == "OFF", "menu labels in cycle order")
	runner.check(MirrorConfig.clamp_mode(9) == MirrorConfig.ALL and MirrorConfig.clamp_mode(-3) == MirrorConfig.OFF, "mode clamps")
	runner.check(MirrorConfig.clamp_size(7) == 2 and MirrorConfig.clamp_size(-1) == 0, "size clamps")
	runner.check(MirrorConfig.parse_mode("rear") == MirrorConfig.TOP and MirrorConfig.parse_mode("top") == MirrorConfig.TOP
		and MirrorConfig.parse_mode("off") == MirrorConfig.OFF and MirrorConfig.parse_mode("sides") == MirrorConfig.SIDES
		and MirrorConfig.parse_mode("all") == MirrorConfig.ALL and MirrorConfig.parse_mode("junk") == -1, "launch arg parse")
	runner.check(MirrorConfig.shows_rear(MirrorConfig.TOP) and not MirrorConfig.shows_sides(MirrorConfig.TOP), "top only")
	runner.check(not MirrorConfig.shows_rear(MirrorConfig.SIDES) and MirrorConfig.shows_sides(MirrorConfig.SIDES), "sides only")
	runner.check(MirrorConfig.shows_rear(MirrorConfig.ALL) and MirrorConfig.shows_sides(MirrorConfig.ALL), "all")
	runner.check(not MirrorConfig.shows_rear(MirrorConfig.OFF) and not MirrorConfig.shows_sides(MirrorConfig.OFF), "off")


func test_saved_mode_migration() -> void:
	# v1 files stored 0 off, 1 rear-view, 2 rear + sides: they keep meaning the same mirrors.
	runner.check(MirrorConfig.migrate_mode(0, 1) == MirrorConfig.OFF, "v1 0 -> OFF")
	runner.check(MirrorConfig.migrate_mode(1, 1) == MirrorConfig.TOP, "v1 1 -> TOP ONLY")
	runner.check(MirrorConfig.migrate_mode(2, 1) == MirrorConfig.ALL, "v1 2 -> ALL")
	runner.check(MirrorConfig.migrate_mode(7, 1) == MirrorConfig.ALL, "v1 junk clamps")
	for m in 4:
		runner.check(MirrorConfig.migrate_mode(m, 2) == m, "v2 value %d kept" % m)
	# Through a real file: an old (unversioned) settings.cfg with mirrors=2 loads as ALL, a
	# saved new file keeps SIDES ONLY.
	var cf := ConfigFile.new()
	cf.set_value("settings", "mirrors", 2)
	cf.save(TMP)
	var s := Settings.new()
	s.load_from(TMP)
	runner.check(s.get_value("mirrors") == MirrorConfig.ALL, "old file mirrors=2 -> ALL (got %d)" % s.get_value("mirrors"))
	s.set_value("mirrors", MirrorConfig.SIDES)
	s.save(TMP)
	var t := Settings.new()
	t.load_from(TMP)
	runner.check(t.get_value("mirrors") == MirrorConfig.SIDES, "new file keeps SIDES ONLY (got %d)" % t.get_value("mirrors"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


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
	var s: Dictionary = CarCatalog.spec("naga_xr")
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
	runner.check(s.get_value("mirrors") == MirrorConfig.TOP and s.get_value("mirror_size") == 1, "defaults: top only, medium")
	s.set_value("mirrors", 7)
	runner.check(s.get_value("mirrors") == MirrorConfig.ALL, "settings clamp mode")
	s.set_value("mirrors", MirrorConfig.TOP)
	s.set_value("mirror_size", 2)
	runner.check(s.save(TMP) == OK, "saves")
	var t := Settings.new()
	t.load_from(TMP)
	runner.check(t.get_value("mirrors") == MirrorConfig.TOP and t.get_value("mirror_size") == 2, "mirror settings persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	t.set_quality(0)
	runner.check(t.get_value("mirrors") == MirrorConfig.OFF, "LOW preset = mirrors off")
	t.set_quality(1)
	runner.check(t.get_value("mirrors") == MirrorConfig.TOP, "MEDIUM preset = top only")
	t.set_quality(2)
	runner.check(t.get_value("mirrors") == MirrorConfig.TOP, "HIGH preset = top only")
	runner.check("mirrors" in Settings.REBINDABLE and Settings.default_keys("mirrors") == [KEY_M], "M cycles mirrors (rebindable)")


func test_police_cue_sectors() -> void:
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, 20)) > 0.9, "cop close behind: rear-view flashes hard")
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, 200)) > 0.0 and MirrorConfig.cop_cue("rear", Vector3(0, 0, 200)) < 0.5, "far behind: faint")
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, 400)) == 0.0, "out of range: none")
	runner.check(MirrorConfig.cop_cue("rear", Vector3(0, 0, -30)) == 0.0, "cop ahead: no mirror cue")
	runner.check(MirrorConfig.cop_cue("left", Vector3(-3.5, 0, 15)) > 0.5 and MirrorConfig.cop_cue("right", Vector3(-3.5, 0, 15)) == 0.0, "behind-left: left mirror only")
	runner.check(MirrorConfig.cop_cue("right", Vector3(3.5, 0, 15)) > 0.5 and MirrorConfig.cop_cue("left", Vector3(3.5, 0, 15)) == 0.0, "behind-right: right mirror only")
	runner.check(MirrorConfig.cop_cue("left", Vector3(0, 0, 15)) == 0.0, "dead behind: not in the side mirrors' cue")


func test_every_shown_mirror_renders_every_frame() -> void:
	# Smooth mirrors: no round-robin (15-30 Hz looked choppy); cost is cut per pass instead.
	for f in 8:
		for m in 4:
			for k in ["rear", "left", "right"]:
				var shown := MirrorConfig.shows_rear(m) if k == "rear" else MirrorConfig.shows_sides(m)
				runner.check(MirrorConfig.renders_on(k, m, f) == shown, "mode %d frame %d: %s renders iff shown" % [m, f, k])

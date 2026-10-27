# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Writes a max-level test profile (level 50, lots of credits, every item owned) to --out=<path>.
## usage: godot --headless --path . -s tools/make_maxed_profile.gd -- --out=/abs/path/profile_max.cfg
func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var p := Profile.new()
	p.xp = XpCurve.total_for(XpCurve.MAX_LEVEL)
	p.credits = 500000
	for slot in UnlockCatalog.SLOTS:
		for it in UnlockCatalog.items(slot):
			p.owned[it.id] = true
	var err := ProfileStore.save_to(p, out)
	print("MAXED_PROFILE err=%d level=%d items=%d path=%s" % [err, XpCurve.level_for(p.xp), p.owned.size(), out])
	quit()

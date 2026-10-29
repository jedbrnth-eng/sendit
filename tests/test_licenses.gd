# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## CREDITS.md must cover every shipped asset file, and every path pattern in it must still match
## something (a stale row once said *.wav after the OGG conversion, prop atlases were not listed).
## Path column syntax: comma-separated entries; an entry with * or ? is a glob on the full res path,
## otherwise it is a file or a directory (prefix) under the project root.

var runner


static func rows() -> Array:
	var out: Array = []
	var txt := FileAccess.get_file_as_string("res://CREDITS.md")
	for line in txt.split("\n"):
		if not line.begins_with("| ") or line.begins_with("| Asset ") or line.begins_with("|---"):
			continue
		var cols := line.split("|")
		if cols.size() < 4:
			continue
		var pats: Array = []
		for p in String(cols[2]).split(","):
			var s := p.strip_edges()
			if s != "":
				pats.append(s)
		out.append(pats)
	return out


static func matches(pat: String, path: String) -> bool:
	if pat.contains("*") or pat.contains("?"):
		return path.match(pat)
	return path == pat or path.begins_with(pat.trim_suffix("/") + "/")


static func asset_files(dir := "assets") -> Array:
	var out: Array = []
	var d := DirAccess.open("res://" + dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid") or f.begins_with("."):
			continue
		out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(asset_files(dir + "/" + sub))
	return out


func test_matcher() -> void:
	runner.check(matches("assets/props/*.glb", "assets/props/cone_a.glb"), "glob")
	runner.check(not matches("assets/props/*.glb", "assets/props/cone_a_Prop_cone_a.jpg"), "glob ext")
	runner.check(matches("assets/traffic", "assets/traffic/a/b.glb"), "dir prefix")
	runner.check(not matches("assets/traffic", "assets/trafficx/b.glb"), "dir prefix is a whole segment")
	runner.check(matches("assets/props/cone_a.glb", "assets/props/cone_a.glb"), "exact file")


func test_every_asset_file_has_a_licence_row() -> void:
	var rs := rows()
	runner.check(rs.size() > 20, "parsed licence rows (%d)" % rs.size())
	var files := asset_files()
	runner.check(files.size() > 100, "found asset files (%d)" % files.size())
	var missing: Array = []
	for f in files:
		var ok := false
		for pats in rs:
			for p in pats:
				if matches(p, f):
					ok = true
					break
			if ok:
				break
		if not ok:
			missing.append(f)
	runner.check(missing.is_empty(), "asset files without a CREDITS.md row (%d): %s" % [missing.size(), str(missing.slice(0, 12))])


func test_no_stale_licence_patterns() -> void:
	var files := asset_files()
	var stale: Array = []
	for pats in rows():
		for p in pats:
			if not String(p).begins_with("assets"):
				var full := ProjectSettings.globalize_path("res://" + p.get_base_dir() if p.contains("*") else "res://" + p)
				if not (DirAccess.dir_exists_absolute(full) or FileAccess.file_exists("res://" + p)):
					stale.append(p)
				continue
			var hit := false
			for f in files:
				if matches(p, f):
					hit = true
					break
			if not hit:
				stale.append(p)
	runner.check(stale.is_empty(), "CREDITS.md patterns matching no file: %s" % str(stale))

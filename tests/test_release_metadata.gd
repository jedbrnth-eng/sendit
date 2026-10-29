# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## Release hygiene: one version everywhere, and every shipped asset is credited under an allowed licence.

var runner
const ALLOWED := ["CC0", "CC-BY 4.0", "SIL OFL 1.1", "GPL-3.0"]  # GPL-3.0 = original work in this repo


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


## Rows of the CREDITS.md table as {path, licence}.
func _rows() -> Array:
	var rows := []
	for line in _read("res://CREDITS.md").split("\n"):
		if not line.begins_with("| ") or line.begins_with("| Asset") or line.begins_with("|---"):
			continue
		var cols := line.split("|")
		if cols.size() < 5:
			continue
		rows.append({"path": cols[2].strip_edges(), "licence": cols[3].strip_edges()})
	return rows


## A credited path is a file, a folder, or a glob like assets/sfx/loop_*.wav that must match something.
func _exists(rel: String) -> bool:
	if not rel.contains("*"):
		return FileAccess.file_exists("res://" + rel) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + rel))
	var dir := DirAccess.open("res://" + rel.get_base_dir())
	if dir == null:
		return false
	for f in dir.get_files():
		if f.match(rel.get_file()):
			return true
	return false


func _app_info() -> GDScript:
	return load("res://scripts/core/app_info.gd") as GDScript


func test_version_file_is_semver() -> void:
	var v := _read("res://VERSION").strip_edges()
	var re := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	runner.check(re.search(v) != null, "VERSION is MAJOR.MINOR.PATCH, got '%s'" % v)


func test_project_version_matches_version_file() -> void:
	var v := _read("res://VERSION").strip_edges()
	var configured := str(ProjectSettings.get_setting("application/config/version", ""))
	runner.check(configured == v, "project.godot version '%s' equals VERSION '%s'" % [configured, v])


func test_app_info_reports_label() -> void:
	var info := _app_info()
	runner.check(info != null, "scripts/core/app_info.gd exists")
	if info == null:
		return
	runner.check(info.version_label() == "v" + _read("res://VERSION").strip_edges(), "label is v<VERSION>")


func test_cc_by_attribution_shown_in_game() -> void:
	var info := _app_info()
	runner.check(info != null, "scripts/core/app_info.gd exists")
	if info == null:
		return
	var text := "\n".join(info.attribution_lines())
	runner.check(text.contains("CarConcept") and text.contains("CC BY 4.0"), "credits the CC-BY car in game: " + text)


func test_credits_rows_point_at_real_files_with_allowed_licences() -> void:
	var rows := _rows()
	runner.check(rows.size() >= 15, "CREDITS.md table parsed (%d rows)" % rows.size())
	for r in rows:
		runner.check(_exists(r.path), "credited path exists: " + r.path)
		runner.check(r.licence in ALLOWED, "licence allowed for %s: %s" % [r.path, r.licence])


func test_every_asset_folder_is_credited() -> void:
	var rows := _rows()
	var dir := DirAccess.open("res://assets")
	for d in dir.get_directories():
		var covered := false
		for r in rows:
			if r.path.begins_with("assets/" + d):
				covered = true
		runner.check(covered, "assets/%s has a CREDITS.md row" % d)


## Whole-word match, so "audio" does not trip on "audi".
func _has_word(haystack: String, word: String) -> bool:
	return RegEx.create_from_string("(^|[^a-z])" + word + "([^a-z]|$)").search(haystack) != null


func test_brand_matcher_is_word_aware() -> void:
	runner.check(_has_word("ferrari_f40.glb", "ferrari"), "catches a brand in a file name")
	runner.check(_has_word("audi.png", "audi"), "catches a bare brand")
	runner.check(not _has_word("car_audio.gd", "audi"), "'audio' is not 'audi'")
	runner.check(not _has_word("", "audi"), "empty name is fine")


func test_credits_flags_nothing_unallowed_in_asset_names() -> void:
	# Near-miss: no real car marques in shipped file names (fictional brands only).
	var banned := ["ferrari", "lamborghini", "porsche", "bmw", "mercedes", "audi", "toyota", "honda", "nissan", "tesla", "bugatti", "mclaren", "mazda", "isuzu", "subaru", "mitsubishi"]
	var stack := ["res://assets"]
	while not stack.is_empty():
		var p: String = stack.pop_back()
		var d := DirAccess.open(p)
		for sub in d.get_directories():
			stack.append(p + "/" + sub)
		for f in d.get_files():
			for b in banned:
				runner.check(not _has_word(f.to_lower(), b), "no brand '%s' in %s/%s" % [b, p, f])


func test_export_presets_carry_the_version() -> void:
	# The macOS bundle and Windows exe show these numbers; they must follow VERSION on every bump.
	var v := _read("res://VERSION").strip_edges()
	var presets := _read("res://export_presets.cfg")
	runner.check(presets.contains("application/short_version=\"%s\"" % v), "macOS short_version is " + v)
	runner.check(presets.contains("application/version=\"%s\"" % v), "macOS version is " + v)
	runner.check(presets.contains("application/file_version=\"%s.0\"" % v), "Windows file_version is %s.0" % v)
	runner.check(presets.contains("application/product_version=\"%s.0\"" % v), "Windows product_version is %s.0" % v)


func test_changelog_has_a_section_for_the_version() -> void:
	# The Release workflow copies this section into the release notes.
	var v := _read("res://VERSION").strip_edges()
	runner.check(_read("res://CHANGELOG.md").contains("\n## [%s] - " % v), "CHANGELOG.md has a '## [%s] - <date>' section" % v)


func test_meshy_assets_are_credited_as_meshy_not_cc0() -> void:
	# Meshy Pro output is owned by the customer and released here under GPL-3.0, never as CC0.
	var meshy := ["assets/cars/naga_xr", "assets/cars/kaze", "assets/cars/kaiju", "assets/traffic/police_meshy", "assets/props"]
	var lines := _read("res://CREDITS.md").split("\n")
	for path in meshy:
		var row := ""
		for line in lines:
			var cols := line.split("|")
			if cols.size() >= 5 and cols[2].strip_edges() == path:
				row = line
		runner.check(row != "", "CREDITS.md has a row for " + path)
		runner.check(row.contains("Generated with Meshy") and row.contains("Pro plan"), "%s row says it is Meshy Pro output" % path)
		runner.check(not row.split("|")[3].contains("CC0"), "%s is not claimed as CC0" % path)


## The CREDITS.md row whose path column is exactly `path` ("" if none).
func _row_for(path: String) -> String:
	for line in _read("res://CREDITS.md").split("\n"):
		var cols := line.split("|")
		if cols.size() >= 5 and cols[2].strip_edges() == path:
			return line
	return ""


func test_synthesized_audio_is_credited_as_own_cc0() -> void:
	# 0.3.1: these sets are made by tools/audio/synth_*.py with no recorded input.
	for path in ["assets/sfx/engine", "assets/sfx/road", "assets/sfx/crash", "assets/sfx/traffic", "assets/sfx/score", "assets/sfx/ui", "assets/sfx/police"]:
		var row := _row_for(path)
		runner.check(row != "", "CREDITS.md has a row for " + path)
		runner.check(row.split("|")[3].strip_edges() == "CC0" if row != "" else false, "%s is CC0" % path)
		runner.check(row.contains("own synthesis") and row.contains("tools/audio/synth_"), "%s names its generator script" % path)


func test_recorded_audio_names_its_source_page() -> void:
	# Third-party recordings keep a link to the page that states their licence.
	for path in ["assets/sfx/tire-squeal-s0500.ogg", "assets/sfx/cut/passby_*.ogg", "assets/sfx/road_roar_loop.wav", "assets/sfx/wind_loop.wav"]:
		var row := _row_for(path)
		runner.check(row != "" and row.contains("https://"), "CREDITS.md row with a source link for " + path)


func test_retired_naga_x_is_gone() -> void:
	# 0.3.1 retired the Naga X (saves migrate naga -> naga_xr); no model, generator or credit row left.
	runner.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/cars/naga")), "assets/cars/naga is removed")
	runner.check(not FileAccess.file_exists("res://tools/blender/naga_pickup.py"), "the Naga X generator is removed")
	runner.check(_row_for("assets/cars/naga") == "", "no CREDITS.md row for the Naga X")

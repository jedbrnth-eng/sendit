# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends RefCounted
## A save that can't be read is kept (never overwritten) and the player is told once, on the title.

var runner
const DIR := "user://test_profile_recovery"


func _fresh(n: String) -> String:
	var d := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + "/" + f)
	return "%s/%s.cfg" % [DIR, n]


func _garbage(path: String, text := "[profile\nxp = = ]]] \u0001") -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_recovery_is_reported_once() -> void:
	var path := _fresh("bad")
	ProfileStore.take_recovery_note()  # clear anything left by other tests
	_garbage(path)
	ProfileStore.load_from(path)
	var note := ProfileStore.take_recovery_note()
	runner.check(note == path + ".corrupt", "the backup path is reported (%s)" % note)
	runner.check(ProfileStore.take_recovery_note() == "", "and only once")
	ProfileStore.load_from(_fresh("missing"))
	runner.check(ProfileStore.take_recovery_note() == "", "a missing file (first launch) is not a recovery")


func test_second_recovery_keeps_the_first_backup() -> void:
	var path := _fresh("twice")
	_garbage(path, "first")
	ProfileStore.load_from(path)
	_garbage(path, "second")
	ProfileStore.load_from(path)
	var note := ProfileStore.take_recovery_note()
	runner.check(FileAccess.get_file_as_string(path + ".corrupt") == "first", "the first backup is not overwritten")
	runner.check(note != path + ".corrupt" and FileAccess.get_file_as_string(note) == "second", "the second gets its own name (%s)" % note)


func test_title_screen_tells_the_player() -> void:
	var path := _fresh("title")
	var keep_file := ProfileStore.file
	var keep_cur := ProfileStore.current
	ProfileStore.take_recovery_note()
	_garbage(path)
	ProfileStore.file = path
	ProfileStore.current = null
	var t := TitleScreen.new()
	runner.root.add_child(t)
	if not t.is_node_ready():
		t._ready()
	runner.check(t.notice_text().contains("could not be read") and t.notice_text().contains(".corrupt"),
		"the title says the save was unreadable and where the backup is (%s)" % t.notice_text())
	t.free()
	var t2 := TitleScreen.new()
	runner.root.add_child(t2)
	if not t2.is_node_ready():
		t2._ready()
	runner.check(t2.notice_text() == "", "the next title screen does not repeat it")
	t2.free()
	ProfileStore.file = keep_file
	ProfileStore.current = keep_cur

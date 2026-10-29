# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name GarageStore
## Last chosen vehicle, in its own user:// file (separate from settings and best scores).

const PATH := "user://garage.cfg"
## Where it lives (launch arg --garage-file=<path> overrides it, for probes and tests).
static var file := PATH


static func load_last(path := "") -> String:
	var cf := ConfigFile.new()
	if cf.load(path if path != "" else file) != OK:
		return ""
	return CarCatalog.canonical(String(cf.get_value("garage", "car", "")))  # retired ids -> replacement


static func save_last(id: String, path := "") -> Error:
	var p := path if path != "" else file
	var cf := ConfigFile.new()
	cf.load(p)  # keep anything else in the file
	cf.set_value("garage", "car", id)
	return cf.save(p)

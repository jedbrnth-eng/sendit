# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name AppInfo extends RefCounted
## Build identity and the in-game credit line. The version lives in `VERSION` and is mirrored in
## project.godot (tests/test_release_metadata.gd keeps the two equal).

const CC_BY_CREDITS: Array[String] = [
	"Car model \"CarConcept\" by Eric Chadwick, \u00a9 2024 Darmstadt Graphics Group GmbH, CC BY 4.0",
]


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func version_label() -> String:
	return "v" + version()


## Attribution that must be visible to players (CC BY 4.0 assets). The full list is CREDITS.md.
static func attribution_lines() -> Array[String]:
	return CC_BY_CREDITS

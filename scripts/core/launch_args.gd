# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name LaunchArgs
## Launch args after `--` (e.g. `-- --autodrive --seed=7`). Static so any script, including
## ones loaded by the headless test runner (where autoload names do not resolve), can read them.

static var _args: Dictionary = {}
static var _parsed := false


static func all() -> Dictionary:
	if not _parsed:
		_parsed = true
		for a in OS.get_cmdline_user_args():
			var kv := String(a).trim_prefix("--").split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return _args


static func has(name: String) -> bool:
	return all().has(name)


static func get_value(name: String, default = null):
	return all().get(name, default)


## Seed for one round: `--seed=N` pins it; proof runs (--autodrive / --capture) default to 7 so the
## gate smoke and captures stay reproducible. Normal play draws a fresh one on every call, so each
## restart (scene reload) gets new traffic, cops and hazards.
static func round_seed() -> int:
	return seed_from(all())


static func seed_from(args: Dictionary) -> int:
	if args.has("seed"):
		return int(args["seed"])
	if args.has("autodrive") or args.has("capture"):
		return 7
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7FFFFFFF

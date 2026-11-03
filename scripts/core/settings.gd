# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name Settings extends RefCounted
## Player settings: audio levels, graphics quality, display, camera and key bindings.
## Persisted to a ConfigFile (user://settings.cfg), applied at boot (Boot autoload) and live from
## the settings menu. Values and their maths are pure and unit-tested (tests/test_settings.gd);
## `apply()` pushes them into the engine (buses, window, environment, camera, input map).

const PATH := "user://settings.cfg"
const LEVELS := ["LOW", "MEDIUM", "HIGH"]
## Keyboard actions the player may rebind (pads keep their fixed layout).
const REBINDABLE := ["throttle", "brake", "steer_left", "steer_right", "handbrake", "camera", "restart", "mirrors"]
const DEFAULTS := {
	"master": 1.0,
	"music": 0.8,
	"sfx": 1.0,
	"shadows": 2,        # 0 off, 1 sun only (no headlight shadows), 2 everything
	"glow": 2,           # 0 off, 1 soft, 2 full bloom
	"draw": 2,           # draw distance: 0 ~500 m, 1 ~720 m, 2 900 m
	"fullscreen": false,
	"fov": 0.0,          # degrees added to the chase cam's speed-widened FOV
	"hood_cam": false,   # start runs in the hood camera
	"mirrors": 1,        # MirrorConfig: 0 off, 1 top (rear-view) only, 2 sides only, 3 all
	"auto_quality": true, # AUTO: step quality down when frames run slow (QualityGovernor)
	"mirror_size": 1,    # 0 small, 1 medium, 2 large
	"replay": true,      # end-of-round highlight replay (scripts/replay)
}
const DRAW_SCALE := [0.55, 0.8, 1.0]

## Rows a quality preset (and AUTO) touches.
const GFX_KEYS := ["shadows", "glow", "draw", "mirrors"]
## AUTO quality's override for this session only (never saved): the graphics values AUTO dropped
## to, and the player's values they replaced. It lapses as soon as the player changes any of
## those rows or turns AUTO off: the player's choice always wins.
static var auto_override := {}
static var auto_base := {}

## The live, applied settings (Boot loads them; the menu edits and saves them).
static var current: Settings
## Where they live (launch arg --settings-file=<path> overrides it, for probes and tests).
static var file := PATH

var values := DEFAULTS.duplicate()
var keys := {}       # action -> physical keycode override


static func get_current() -> Settings:
	if current == null:
		current = Settings.new()
	return current


func get_value(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v) -> void:
	values[key] = clamp_value(key, v)


static func clamp_value(key: String, v):
	match key:
		"master", "music", "sfx":
			return clampf(float(v), 0.0, 1.0)
		"shadows", "glow", "draw":
			return clampi(int(v), 0, 2)
		"fov":
			return clampf(snappedf(float(v), 1.0), -10.0, 15.0)
		"fullscreen", "hood_cam", "replay", "auto_quality":
			return bool(v)
		"mirrors":
			return MirrorConfig.clamp_mode(v)
		"mirror_size":
			return MirrorConfig.clamp_size(v)
	return v


func reset() -> void:
	values = DEFAULTS.duplicate()
	keys.clear()


## One preset for the three graphics rows plus the mirrors (LOW: off; MEDIUM/HIGH: top only,
## the side mirrors are an opt-in extra pass each). Measured costs: README, Performance.
func set_quality(level: int) -> void:
	for k in ["shadows", "glow", "draw"]:
		set_value(k, level)
	set_value("mirrors", MirrorConfig.OFF if level <= 0 else MirrorConfig.TOP)


## The preset level when shadows/glow/draw agree, else -1 (custom).
func quality() -> int:
	var s: int = get_value("shadows")
	return s if get_value("glow") == s and get_value("draw") == s else -1


func gfx_values() -> Dictionary:
	var out := {}
	for k in GFX_KEYS:
		out[k] = get_value(k)
	return out


func set_auto_override(over: Dictionary) -> void:
	auto_base = gfx_values()
	auto_override = over.duplicate()


static func clear_auto_override() -> void:
	auto_override = {}
	auto_base = {}


func auto_active() -> bool:
	return not auto_override.is_empty() and bool(get_value("auto_quality")) and gfx_values() == auto_base


## What gets applied: these settings, or a copy with AUTO's lower tier when it is active.
func effective() -> Settings:
	if not auto_active():
		if not auto_override.is_empty() and self == current:
			clear_auto_override()
		return self
	var e := Settings.new()
	e.values = values.duplicate()
	e.keys = keys
	for k in auto_override:
		e.values[k] = clamp_value(k, auto_override[k])
	return e


## Slider 0..1 -> bus dB (0 is silent).
static func volume_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func save(path := "") -> int:
	if path == "":
		path = file
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", MirrorConfig.SETTINGS_VERSION)
	for k in values:
		cf.set_value("settings", k, values[k])
	for a in keys:
		cf.set_value("keys", a, keys[a])
	return cf.save(path)


func load_from(path := "") -> void:
	if path == "":
		path = file
	reset()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	var raw_version = cf.get_value("meta", "version", 1)
	var version: int = raw_version if raw_version is int else 1
	if version > MirrorConfig.SETTINGS_VERSION:
		# Written by a newer build: keep that file as it was before this build rewrites it
		# (going back to the newer build can restore it); read what this build understands.
		var bak := "%s.v%d" % [path, version]
		if not FileAccess.file_exists(bak):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bak))
		push_warning("settings: %s is from a newer build (v%d); kept a copy as %s" % [path, version, bak])
	for k in DEFAULTS:
		if cf.has_section_key("settings", k):
			var v = cf.get_value("settings", k)
			# ConfigFile can contain any Variant. Reject invalid values before conversion,
			# so one edited field cannot abort startup or poison a later graphics setting.
			if not (v is bool or v is int or v is float):
				continue
			if v is float and (is_nan(v) or is_inf(v)):
				continue
			if k == "mirrors":
				v = MirrorConfig.migrate_mode(v, version)
			set_value(k, v)
	if cf.has_section("keys"):
		for a in cf.get_section_keys("keys"):
			var code = cf.get_value("keys", a)
			if a in REBINDABLE and code is int and code > 0:
				keys[a] = code


# --- key bindings ------------------------------------------------------------------------------

## Bind `keycode` as the keyboard key for `action`; the key is taken off any other driving action
## so one key never drives two things. The default arrow-key alternates stay. When that leaves the
## other action with no key at all, it gets the key `action` is giving up (a swap). Returns the
## swapped action ("" when none) so the menu can say so.
func rebind(action: String, keycode: int) -> String:
	if not action in REBINDABLE:
		return ""
	var before := {}
	for a in REBINDABLE:
		before[a] = effective_keys(a)
	var leaving: int = before[action][0] if not (before[action] as Array).is_empty() else 0
	for a in keys.keys():
		if a != action and keys[a] == keycode:
			keys.erase(a)
	keys[action] = keycode
	var swapped := ""
	for a in REBINDABLE:
		if a != action and not (before[a] as Array).is_empty() and effective_keys(a).is_empty() \
				and leaving != 0 and leaving != keycode:
			keys[a] = leaving
			swapped = a
	apply_keys()
	return swapped


## The keyboard keys an action ends up with (pure): its defaults with the first replaced by any
## override, minus keys another action's override took.
func effective_keys(action: String) -> Array:
	var codes: Array = default_keys(action).duplicate()
	if keys.has(action):
		if codes.is_empty():
			codes.append(keys[action])
		else:
			codes[0] = keys[action]
	var out := []
	for code in codes:
		var owner := ""
		for a in keys:
			if keys[a] == code:
				owner = a
		if owner != "" and owner != action:
			continue
		out.append(code)
	return out


## The keyboard key shown for an action (override, else the first default key).
static func key_for(action: String) -> int:
	var s := get_current()
	if s.keys.has(action):
		return s.keys[action]
	for ev in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return 0


static func key_name(code: int) -> String:
	return OS.get_keycode_string(code) if code != 0 else "-"


## Rebuild keyboard events: defaults from Boot.ACTIONS, the first key replaced by any override,
## and an overridden key removed from every other action.
func apply_keys() -> void:
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		for code in effective_keys(action):
			var k := InputEventKey.new()
			k.physical_keycode = code
			InputMap.action_add_event(action, k)


static func default_keys(action: String) -> Array:
	var out := []
	var boot := load("res://scripts/core/boot.gd")
	for spec in boot.ACTIONS.get(action, []):
		if spec is int and spec >= KEY_SPACE:
			out.append(spec)
	return out


# --- apply -------------------------------------------------------------------------------------

## Push everything into the engine. `tree` may be null (boot, before the scene exists).
func apply(tree: SceneTree = null) -> void:
	var gfx := effective()  # AUTO's transient tier (if any) for the graphics side only
	AudioMix.ensure_buses()
	_bus(&"Master", get_value("master"))
	_bus(AudioMix.MUSIC, get_value("music"))
	_bus(AudioMix.EFFECTS, get_value("sfx"))
	Highway.draw_scale = DRAW_SCALE[gfx.get_value("draw")]
	ChaseCamera.fov_offset = get_value("fov")
	ChaseCamera.start_hood = get_value("hood_cam")
	apply_keys()
	if DisplayServer.get_name() != "headless" and not LaunchArgs.has("capture") and not LaunchArgs.has("windowed"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayMode.is_fullscreen(DisplayServer.window_get_mode()) != bool(get_value("fullscreen")):
			DisplayServer.window_set_mode(want)
	if tree:
		tree.root.positional_shadow_atlas_size = 4096 if gfx.get_value("shadows") >= 2 else 0
		tree.call_group(NightEnvironment.GROUP, "apply_settings", gfx)
		tree.call_group(Mirrors.GROUP, "apply_settings", gfx)


func _bus(name: StringName, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, volume_db(v))
		AudioServer.set_bus_mute(i, v <= 0.001)

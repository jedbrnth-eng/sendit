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
	var version: int = int(cf.get_value("meta", "version", 1))
	for k in DEFAULTS:
		if cf.has_section_key("settings", k):
			var v = cf.get_value("settings", k)
			if k == "mirrors":
				v = MirrorConfig.migrate_mode(v, version)
			set_value(k, v)
	if cf.has_section("keys"):
		for a in cf.get_section_keys("keys"):
			if a in REBINDABLE:
				keys[a] = int(cf.get_value("keys", a))


# --- key bindings ------------------------------------------------------------------------------

## Bind `keycode` as the keyboard key for `action`; the key is taken off any other driving action
## so one key never drives two things. The default arrow-key alternates stay.
func rebind(action: String, keycode: int) -> void:
	if not action in REBINDABLE:
		return
	for a in keys.keys():
		if a != action and keys[a] == keycode:
			keys.erase(a)
	keys[action] = keycode
	apply_keys()


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
	var taken := {}
	for a in keys:
		taken[keys[a]] = a
	for action in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		var defaults: Array = default_keys(action)
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		var codes: Array = defaults.duplicate()
		if keys.has(action):
			codes[0] = keys[action]
		for code in codes:
			if taken.has(code) and taken[code] != action:
				continue
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
	AudioMix.ensure_buses()
	_bus(&"Master", get_value("master"))
	_bus(AudioMix.MUSIC, get_value("music"))
	_bus(AudioMix.EFFECTS, get_value("sfx"))
	Highway.draw_scale = DRAW_SCALE[get_value("draw")]
	ChaseCamera.fov_offset = get_value("fov")
	ChaseCamera.start_hood = get_value("hood_cam")
	apply_keys()
	if DisplayServer.get_name() != "headless" and not LaunchArgs.has("capture") and not LaunchArgs.has("windowed"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayMode.is_fullscreen(DisplayServer.window_get_mode()) != bool(get_value("fullscreen")):
			DisplayServer.window_set_mode(want)
	if tree:
		tree.root.positional_shadow_atlas_size = 4096 if get_value("shadows") >= 2 else 0
		tree.call_group(NightEnvironment.GROUP, "apply_settings", self)
		tree.call_group(Mirrors.GROUP, "apply_settings", self)


func _bus(name: StringName, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, volume_db(v))
		AudioServer.set_bus_mute(i, v <= 0.001)

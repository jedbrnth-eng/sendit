# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

class_name ReplayDirector extends Node3D
## End-of-round highlight replay. Plays ReplayPicker clips from a ReplayRecorder in the live scene:
## the world is frozen (traffic/police hidden and paused, hazards' contacts off), the real player
## car is posed from the recording, recorded traffic/cops are rebuilt as proxies with CarModel from
## their recorded build args, and the live Highway/ShoulderHazards re-stream at the recorded z (both
## are deterministic per chunk, so the road, lamps and skyline come back exactly). On finish (or a
## skip) everything is put back as it was at the end of the run.
##
## Why the live scene: rebuilding a second world (environment, HDRI, city, road materials) would
## double the load for a 20 s replay; re-streaming chunks at a new z is what the game already does
## every frame, and nothing in the frozen world can score, crash or move while the replay runs.
##
## Shots per clip (ReplayPicker.shot): low side chase -> front 3/4 through the pass with a 0.35x
## slow-mo ramp -> trackside mini zoom. Letterbox bars, caption, one press of Enter/Space/A/Esc
## skips the whole replay.

signal finished

const DISPLAY := "res://assets/fonts/RussoOne-Regular.ttf"
const BODY := "res://assets/fonts/ChakraPetch-Bold.ttf"
const BAR_H := 120.0
const FLASH_S := 0.22

var rec: ReplayRecorder
var clips: Array = []
var skipped := false

var _main: Node
var _player: PlayerCar
var _cam: Camera3D
var _proxies := {}          # entity id -> {node, body, last_z}
var _proxy_root: Node3D
var _clip := -1
var _t := 0.0               # replay time (recording clock)
var _side := 1.0            # which side the near car passes on (+x of the player = 1)
var _shot := ""
var _anchor := Vector3.ZERO # trackside camera spot for the zoom shot
var _ui: CanvasLayer
var _caption: Label
var _flash: ColorRect
var _bars: Array[ColorRect] = []
var _saved := {}
var _done := false
var _wall_t0 := 0


## Whether the replay plays by itself at the end of a run: the setting, and never in proof runs
## (--autodrive / --capture) unless asked with --replay-at-end / --replay-test.
static func auto_play() -> bool:
	if LaunchArgs.has("replay-at-end") or LaunchArgs.has("replay-test"):
		return true
	if LaunchArgs.has("autodrive") or LaunchArgs.has("capture"):
		return false
	return bool(Settings.get_current().get_value("replay"))


## Build a director for main.gd's scene, or null when there is nothing to replay.
static func make(main: Node, recorder: ReplayRecorder, end_reason: String) -> ReplayDirector:
	var c := ReplayPicker.pick(recorder.events, recorder.crashes, recorder.start_time(), recorder.end_time(), end_reason)
	if c.is_empty():
		return null
	var d := ReplayDirector.new()
	d.rec = recorder
	d.clips = c
	d._main = main
	return d


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_wall_t0 = Time.get_ticks_msec()
	UiSfx.play("replay_in")
	_player = _main.player
	_freeze()
	_proxy_root = Node3D.new()
	add_child(_proxy_root)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 4000.0
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_build_ui()
	print("REPLAY clips=%d rec=%.1f..%.1fs frames=%d bytes=%d" % [clips.size(), rec.start_time(), rec.end_time(), rec.frame_count(), rec.byte_size()])
	_next_clip()


func _freeze() -> void:
	var p := _player
	_saved = {
		"pos": p.position, "rot": p.rotation, "yaw": p.yaw, "speed": p.speed, "steer": p.steer_input,
		"brake": p.brake, "throttle": p.throttle, "body": p.body.rotation if p.body else Vector3.ZERO,
		"interp": p.physics_interpolation_mode, "phys": p.is_physics_processing(),
		"traffic_mode": _main.traffic.process_mode, "traffic_vis": _main.traffic.visible,
		"police_mode": _main.police.process_mode, "hazards_phys": _main.hazards.is_physics_processing(),
		"hud": _main.hud.visible, "phud": _main.pursuit_hud.visible,
	}
	p.set_physics_process(false)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_main.traffic.process_mode = Node.PROCESS_MODE_DISABLED
	_main.traffic.visible = false
	_main.police.process_mode = Node.PROCESS_MODE_DISABLED
	_main.hazards.set_physics_process(false)  # no contacts against the posed car
	_main.hud.visible = false
	_main.pursuit_hud.visible = false
	for fx in ["_smoke", "_sparks"]:
		var n = p.get(fx)
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = false


func _restore() -> void:
	var p := _player
	p.position = _saved.pos
	p.rotation = _saved.rot
	p.yaw = _saved.yaw
	p.speed = _saved.speed
	p.steer_input = _saved.steer
	p.brake = _saved.brake
	p.throttle = _saved.throttle
	if p.body:
		p.body.rotation = _saved.body
	p.physics_interpolation_mode = _saved.interp
	p.set_physics_process(_saved.phys)
	p.reset_physics_interpolation()
	_main.traffic.process_mode = _saved.traffic_mode
	_main.traffic.visible = _saved.traffic_vis
	_main.police.process_mode = _saved.police_mode
	_main.hazards.set_physics_process(_saved.hazards_phys)
	_main.hud.visible = _saved.hud
	_main.pursuit_hud.visible = _saved.phud
	_main.highway.update_stream(p.position.z)
	_main.hazards.update_stream(p.position.z)
	(_main.camera as Camera3D).make_current()


# --- clips -------------------------------------------------------------------------------------

func _next_clip() -> void:
	_clip += 1
	if _clip >= clips.size():
		finish()
		return
	var c: Dictionary = clips[_clip]
	_t = float(c.start)
	_side = _near_side(float(c.t))
	_shot = ""
	for k in _proxies:
		(_proxies[k].node as Node3D).queue_free()
	_proxies.clear()
	_caption.text = ReplayPicker.caption(c)
	_flash.color.a = 1.0
	create_tween().tween_property(_flash, "color:a", 0.0, FLASH_S)
	print("REPLAY_CLIP %d/%d kind=%s t=%.2f window=%.2f..%.2f phys_frame=%d caption=\"%s\"" % [
		_clip + 1, clips.size(), c.kind, float(c.t), float(c.start), float(c.end), Engine.get_physics_frames(), _caption.text])
	_pose(0.0)


## Side the closest car passes on at time t (sign of its x relative to the player).
func _near_side(t: float) -> float:
	var s := rec.sample(t)
	var p: PackedFloat32Array = s.player
	if p.is_empty():
		return 1.0
	var best := INF
	var side := 1.0
	for id in s.ents:
		var e: Array = s.ents[id]
		var dz := absf(float(e[4]) - p[1])
		var dx := float(e[3]) - p[0]
		if absf(dx) < 7.0 and dz < best:
			best = dz
			side = signf(dx) if dx != 0.0 else 1.0
	return side


func _process(delta: float) -> void:
	if _done or _clip >= clips.size():
		return
	var c: Dictionary = clips[_clip]
	var rate := 1.0 if c.kind == "last" else ReplayPicker.play_rate(_t - float(c.t))
	var step := delta * rate
	_t += step
	if _t >= float(c.end):
		_next_clip()
		return
	_pose(step)


func _pose(step: float) -> void:
	var c: Dictionary = clips[_clip]
	var s := rec.sample(_t)
	var p: PackedFloat32Array = s.player
	if p.is_empty():
		return
	# Player: the real car, posed.
	_player.position = Vector3(p[0], 0.0, p[1])
	_player.rotation.y = p[2]
	_player.yaw = p[2]
	_player.speed = p[3]
	_player.steer_input = p[4]
	_player.brake = p[5]
	_player.throttle = clampf(1.0 - p[5], 0.0, 1.0)
	if _player.body:
		_player.body.rotation = Vector3(p[6], p[7], p[8])
	if _player.car and step > 0.0:
		_player.car.set_brake(p[5])
		_player.car.roll(p[3], step, -p[4] * lerpf(0.4, 0.06, clampf(p[3] / 50.0, 0.0, 1.0)))
	# The road, lamps, skyline and shoulder at the recorded spot (cheap: chunk dictionary lookups).
	_main.highway.update_stream(p[1])
	_main.hazards.update_stream(p[1])
	# Traffic / cops as proxies.
	var seen := {}
	for id in s.ents:
		var e: Array = s.ents[id]
		var px: Dictionary = _proxies.get(id, {})
		if px.is_empty():
			px = _make_proxy(e)
			_proxies[id] = px
		var n: Node3D = px.node
		n.visible = true
		n.position = Vector3(e[3], 0.0, e[4])
		n.rotation.y = e[5]
		var body: CarBody = px.body
		body.set_brake(e[6])
		if step > 0.0:
			var v := absf(float(e[4]) - float(px.last_z)) / step
			body.roll(minf(v, 90.0), step)
		px.last_z = e[4]
		if px.bar:
			(px.bar as LightBar).set_on((int(e[2]) & ReplayRecorder.FLAG_CHASING) != 0)
		seen[id] = true
	for id in _proxies:
		if not seen.has(id):
			(_proxies[id].node as Node3D).visible = false
	_camera(c, p)


func _make_proxy(e: Array) -> Dictionary:
	var src: Array = rec.specs[int(e[1])]
	var n := Node3D.new()
	var body := CarModel.build(src[0], src[1], src[2], src[3], src[4], src[5])
	n.add_child(body)
	var bar: LightBar = null
	if (int(e[2]) & ReplayRecorder.FLAG_COP) != 0:
		bar = LightBar.new()
		bar.build(float(body.get_meta("body_half_width", 0.95)) * 2.0 * 0.62)
		var he: Vector2 = body.get_meta("half_extents")
		bar.position = Vector3(0, float(body.get_meta("height")) - 0.04, he.y * 0.06)
		n.add_child(bar)
	_proxy_root.add_child(n)
	return {"node": n, "body": body, "last_z": e[4], "bar": bar}


# --- camera ------------------------------------------------------------------------------------

func _camera(c: Dictionary, p: PackedFloat32Array) -> void:
	var dt := _t - float(c.t)
	var sh := ReplayPicker.shot(dt)
	if c.kind == "last":
		sh = "side" if _t < (float(c.start) + float(c.end)) * 0.5 else "front"
	var pos := Vector3(p[0], 0.0, p[1])
	var yaw := p[2]
	var h := Vector3(-sin(yaw), 0, -cos(yaw))
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var up := Vector3.UP
	if sh != _shot:
		_shot = sh
		if sh == "zoom":
			# A raised spot just behind the car, off the far side from the car it passed: the car
			# pulls away from it under a tele zoom (looking back at the nose blew out in headlight
			# glare, and a lane-level spot ahead got filled by the next car, seed 7 clips 1 and 4).
			_anchor = pos - h * 3.0 - r * _side * 2.8 + up * 2.2
		print("REPLAY_SHOT clip=%d shot=%s t=%.2f phys_frame=%d" % [_clip + 1, sh, _t, Engine.get_physics_frames()])
	match sh:
		"side":  # low side chase, a little off the far side of the car
			_cam.fov = 58.0
			_cam.global_position = pos - h * 6.2 - r * _side * 2.4 + up * 0.75
			_cam.look_at(pos + h * 6.0 + up * 0.55, Vector3.UP)
		"front":  # front 3/4: ahead of the car, looking back across it at the car it threads
			_cam.fov = 52.0
			_cam.global_position = pos + h * 7.2 - r * _side * 3.1 + up * 1.0
			_cam.look_at(pos + r * _side * 0.9 - h * 1.5 + up * 0.55, Vector3.UP)
		"zoom":  # fixed camera, tele zoom keeps the car about the same size as it pulls away
			_cam.global_position = _anchor
			var target := pos + up * 0.6
			var d := _anchor.distance_to(target)
			_cam.fov = clampf(rad_to_deg(2.0 * atan(5.5 / maxf(d, 0.1))), 11.0, 60.0)
			if d > 0.5:
				_cam.look_at(target, Vector3.UP)


# --- UI ----------------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 7
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0, 0, 0, 1)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 1)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		b.offset_top = 0.0 if top else -BAR_H
		b.offset_bottom = BAR_H if top else 0.0
		root.add_child(b)
		_bars.append(b)
	var display: Font = load(DISPLAY)
	var body: Font = load(BODY)
	var tag := _label(root, display, 34, Color(1.0, 0.24, 0.32))
	tag.text = "●  REPLAY"
	_place(tag, Control.PRESET_TOP_LEFT, 64, 38, 400, 48)
	var hint := _label(root, body, 22, Color(1, 1, 1, 0.6))
	hint.text = "ENTER / SPACE / A   SKIP"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(hint, Control.PRESET_TOP_RIGHT, -664, 46, 600, 34)
	_caption = _label(root, display, 44, Color.WHITE)
	_place(_caption, Control.PRESET_BOTTOM_LEFT, 64, -BAR_H + 30, 1600, 60)
	var gold := _label(root, body, 22, Color(1.0, 0.82, 0.35))
	gold.text = "BEST GAPS OF THE ROUND"
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(gold, Control.PRESET_BOTTOM_RIGHT, -664, -BAR_H + 44, 600, 34)


func _label(parent: Control, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _place(c: Control, preset: int, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


# --- input / end -------------------------------------------------------------------------------

## Any of these skips the whole replay at once.
static func is_skip(e: InputEvent) -> bool:
	if e is InputEventKey and e.pressed and not e.echo:
		return (e as InputEventKey).physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]
	if e is InputEventJoypadButton and e.pressed:
		return (e as InputEventJoypadButton).button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_BACK]
	return false


func _input(e: InputEvent) -> void:
	if _done:
		return
	if is_skip(e):
		get_viewport().set_input_as_handled()
		skipped = true
		finish()
	elif (e is InputEventKey or e is InputEventJoypadButton) and e.is_pressed():
		get_viewport().set_input_as_handled()  # other presses do nothing while it plays


func finish() -> void:
	if _done:
		return
	_done = true
	print("REPLAY_END clips=%d played=%d skipped=%s wall_ms=%d" % [clips.size(), mini(_clip + 1, clips.size()), skipped, Time.get_ticks_msec() - _wall_t0])
	_restore()
	finished.emit()
	queue_free()
